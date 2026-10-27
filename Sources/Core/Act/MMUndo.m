// The one undo engine: records, the Trash, the recovery folder, git bundles, restore and tool commands.
// Ported from WorkForest's WFRemove and WFRestore, LocoHost's restart command and Noo-Noo's Grave.
// Records go to the log of P38 as append-only rows. Nothing here deletes a file, and nothing empties the Trash.
#import <AppKit/AppKit.h>
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Know/MMGit.h"

static const uint64_t kRecoverFileMax = 20ull << 20, kRecoverTotalMax = 100ull << 20;   // as WorkForest's SaveIgnored
static NSString *const kTable = @"undo";

static NSString *StateName(MMUndoState s) {
    switch (s) {
        case MMUndoPending: return @"pending";
        case MMUndoDone: return @"done";
        case MMUndoFailed: return @"failed";
        case MMUndoRestored: return @"restored";
    }
    return @"pending";
}
static MMUndoState StateFrom(NSString *s) {
    if ([s isEqualToString:@"done"]) return MMUndoDone;
    if ([s isEqualToString:@"failed"]) return MMUndoFailed;
    if ([s isEqualToString:@"restored"]) return MMUndoRestored;
    return MMUndoPending;
}

#pragma mark - The log

static void LogAppend(NSDictionary *body) {
    [MMLog.shared append:kTable rid:body[@"rid"] expert:body[@"expert"] subject:body[@"subject"] state:body[@"state"] body:body];
}
/// The newest body of each record, newest first.
static NSArray<NSDictionary *> *LogLatest(NSString *expert) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMLogEntry *e in [MMLog.shared latest:kTable expert:expert subject:nil since:nil limit:100000]) if (e.body) [out addObject:e.body];
    return out;
}
static NSDictionary *LogLatestOf(NSString *rid) {
    return rid ? [MMLog.shared history:rid].lastObject.body : nil;
}

#pragma mark - Records

@interface MMUndoRecord ()
@property (readwrite, copy) NSString *rid, *expert, *kind, *findingID, *subject, *why, *by, *parentRid, *error;
@property (readwrite) MMUndoState state;
@property (readwrite) NSDate *at;
@property (readwrite) NSDictionary *payload;
@property (readwrite) int64_t freedBytes;
@property BOOL hasParts;
@end

@implementation MMUndoRecord
+ (instancetype)fromBody:(NSDictionary *)b {
    if (![b isKindOfClass:NSDictionary.class] || ![b[@"rid"] isKindOfClass:NSString.class]) return nil;
    MMUndoRecord *r = [MMUndoRecord new];
    id (^str)(NSString *) = ^id(NSString *k) { return [b[k] isKindOfClass:NSString.class] ? b[k] : nil; };
    r.rid = b[@"rid"]; r.expert = str(@"expert"); r.kind = str(@"kind"); r.findingID = str(@"findingID");
    r.subject = str(@"subject"); r.why = str(@"why"); r.by = str(@"by"); r.parentRid = str(@"parentRid"); r.error = str(@"error");
    r.state = StateFrom(str(@"state"));
    r.at = [NSDate dateWithTimeIntervalSince1970:[b[@"at"] doubleValue]];
    r.payload = [b[@"payload"] isKindOfClass:NSDictionary.class] ? b[@"payload"] : @{};
    r.freedBytes = [b[@"freedBytes"] longLongValue];
    return r;
}
- (NSDictionary *)body {
    NSMutableDictionary *b = [NSMutableDictionary new];
    b[@"rid"] = self.rid; b[@"state"] = StateName(self.state); b[@"at"] = @(self.at.timeIntervalSince1970);
    b[@"payload"] = self.payload ?: @{}; b[@"freedBytes"] = @(self.freedBytes);
    b[@"expert"] = self.expert; b[@"kind"] = self.kind; b[@"findingID"] = self.findingID; b[@"subject"] = self.subject;
    b[@"why"] = self.why; b[@"by"] = self.by; b[@"parentRid"] = self.parentRid; b[@"error"] = self.error;
    return b;
}
- (BOOL)canRestore {
    if (self.state != MMUndoDone && self.state != MMUndoFailed) return NO;
    if ([self.kind isEqualToString:@"tool"]) return NO;
    NSDictionary *p = self.payload;
    return self.hasParts || [p[@"trashed"] count] || p[@"restart"] || p[@"bundle"] || p[@"worktree"] || p[@"recovery"] || p[@"relaunch"];
}
@end

#pragma mark - Running a command

/// Runs a binary with a timeout and returns its status, or -1 when it would not start or ran too long.
/// Only the process started here is ever signaled.
static int RunTool(NSString *path, NSArray<NSString *> *args, NSString *cwd, NSDictionary *env, NSTimeInterval timeout,
                   NSString **output) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args ?: @[];
    if (cwd) t.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    if (env.count) {
        NSMutableDictionary *e = [NSProcessInfo.processInfo.environment mutableCopy];
        [e addEntriesFromDictionary:env];
        t.environment = e;
    }
    // MMRunTask drains both pipes on one thread, and past the limit sends SIGTERM, then SIGKILL, and stops reading.
    NSData *o = nil, *x = nil;
    MMRunResult r = MMRunTask(t, nil, timeout > 0 ? timeout : 600, &o, &x);
    if (!r.didRun) { if (output) *output = @"the command would not start"; return -1; }
    if (output) {
        NSMutableData *all = [o ?: NSData.data mutableCopy];
        [all appendData:x ?: NSData.data];
        *output = [[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding] ?: @"";
    }
    return r.timedOut ? -1 : r.status;
}

static int Git(NSString *dir, NSArray<NSString *> *args, NSString **output) {
    NSString *out = nil;
    int st = RunTool(@"/usr/bin/git", [@[@"-C", dir] arrayByAddingObjectsFromArray:args], nil, nil, 120, &out);
    if (output) *output = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return st;
}

static NSString *Quoted(NSArray<NSString *> *argv) {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *a in argv) {
        BOOL plain = a.length && [a rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\"'\\$`*?&|;<>()"]].location == NSNotFound;
        [parts addObject:plain ? a : [NSString stringWithFormat:@"'%@'", [a stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *Tail(NSString *s, NSUInteger max) {
    return s.length > max ? [s substringFromIndex:s.length - max] : (s ?: @"");
}

#pragma mark - The engine

@implementation MMUndo

+ (instancetype)shared {
    static MMUndo *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ u = [MMUndo new]; });
    return u;
}

- (void)write:(MMUndoRecord *)r { LogAppend(r.body); }

- (MMUndoRecord *)begin:(NSString *)expert kind:(NSString *)kind finding:(NSString *)findingID subject:(NSString *)subject
                    why:(NSString *)why by:(NSString *)by parent:(NSString *)parent payload:(NSDictionary *)payload {
    MMUndoRecord *r = [MMUndoRecord new];
    r.rid = [[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:12].lowercaseString;
    r.expert = expert; r.kind = kind; r.findingID = findingID; r.subject = subject; r.why = why; r.by = by;
    r.parentRid = parent; r.state = MMUndoPending; r.at = NSDate.date; r.payload = payload ?: @{};
    @synchronized (self) { [self write:r]; }
    return r;
}

- (void)note:(MMUndoRecord *)record payload:(NSDictionary *)more {
    if (!record || !more.count) return;
    @synchronized (self) {
        NSMutableDictionary *p = [record.payload mutableCopy] ?: [NSMutableDictionary new];
        [p addEntriesFromDictionary:more];
        record.payload = p;
        [self write:record];
    }
}

- (void)finish:(MMUndoRecord *)record ok:(BOOL)ok freed:(int64_t)bytes error:(NSString *)error {
    if (!record) return;
    @synchronized (self) {
        record.state = ok ? MMUndoDone : MMUndoFailed;
        record.freedBytes = bytes;
        record.error = error;
        [self write:record];
    }
}

- (NSURL *)trash:(NSURL *)item record:(MMUndoRecord *)record error:(NSError **)error {
    NSURL *to = nil;
    if (![NSFileManager.defaultManager trashItemAtURL:item resultingItemURL:&to error:error] || !to) return nil;
    @synchronized (self) {
        NSMutableArray *t = [record.payload[@"trashed"] mutableCopy] ?: [NSMutableArray new];
        [t addObject:@{@"from": item.path, @"to": to.path}];
        [self note:record payload:@{@"trashed": t}];
    }
    return to;
}

- (NSString *)recover:(NSArray<NSString *> *)files from:(NSString *)root record:(MMUndoRecord *)record error:(NSString **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [[MMExpertDir(record.expert ?: @"core") stringByAppendingPathComponent:@"recovery"] stringByAppendingPathComponent:record.rid];
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (error) *error = @"the recovery folder could not be made";
        return nil;
    }
    NSMutableArray *saved = [NSMutableArray new], *skipped = [NSMutableArray new];
    uint64_t total = 0;
    for (NSString *rel in files) {
        if (!rel.length || [rel hasPrefix:@"/"] || [rel.pathComponents containsObject:@".."]) { [skipped addObject:rel ?: @""]; continue; }
        NSString *src = [root stringByAppendingPathComponent:rel];
        uint64_t size = 0;
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:src isDirectory:&isDir]) { [skipped addObject:rel]; continue; }
        if (isDir) {
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:src];
            while ([e nextObject]) { size += e.fileAttributes.fileSize; if (size > kRecoverTotalMax) break; }
        } else size = [fm attributesOfItemAtPath:src error:nil].fileSize;
        if (size > kRecoverFileMax || total + size > kRecoverTotalMax) { [skipped addObject:rel]; continue; }
        NSString *to = [dir stringByAppendingPathComponent:rel];
        [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if ([fm copyItemAtPath:src toPath:to error:nil]) { [saved addObject:rel]; total += size; }
        else [skipped addObject:rel];
    }
    [self note:record payload:@{@"recovery": @{@"dir": dir, @"root": root ?: @"", @"saved": saved, @"skipped": skipped}}];
    return dir;
}

- (NSString *)bundle:(NSString *)worktree record:(MMUndoRecord *)record error:(NSString **)error {
    NSString *common = nil, *head = nil, *branch = nil, *count = nil, *out = nil;
    if (Git(worktree, @[@"rev-parse", @"--path-format=absolute", @"--git-common-dir"], &common) != 0 || !common.length) {
        if (error) *error = @"not a git worktree";
        return nil;
    }
    NSString *repo = [common.lastPathComponent isEqualToString:@".git"] ? common.stringByDeletingLastPathComponent : common;
    if (Git(worktree, @[@"rev-parse", @"HEAD"], &head) != 0 || !head.length) {
        if (error) *error = @"its HEAD could not be read";
        return nil;
    }
    if (Git(worktree, @[@"symbolic-ref", @"--quiet", @"--short", @"HEAD"], &branch) != 0) branch = nil;
    if (Git(worktree, @[@"rev-list", @"--count", @"HEAD", @"--not", @"--remotes"], &count) != 0) {
        if (error) *error = @"its commits could not be counted";
        return nil;
    }
    if (count.integerValue == 0) {
        if (error) *error = @"every commit is on a remote, so no bundle is needed";
        return nil;
    }
    NSString *dir = [MMExpertDir(record.expert ?: @"core") stringByAppendingPathComponent:@"bundles"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:[record.rid stringByAppendingPathExtension:@"bundle"]];
    if (Git(worktree, @[@"bundle", @"create", path, @"HEAD", @"--not", @"--remotes"], &out) != 0) {
        if (error) *error = [@"git bundle create failed: " stringByAppendingString:Tail(out, 300)];
        return nil;
    }
    if (Git(worktree, @[@"bundle", @"verify", path], &out) != 0) {
        if (error) *error = [@"git bundle verify failed: " stringByAppendingString:Tail(out, 300)];
        return nil;
    }
    NSMutableDictionary *b = [@{@"path": path, @"repo": repo, @"worktree": worktree, @"head": head,
                                @"commits": @(count.integerValue)} mutableCopy];
    if (branch.length) b[@"branch"] = branch;
    [self note:record payload:@{@"bundle": b}];
    return path;
}

#pragma mark Restore

/// Starts a stopped process again with its recorded command. With PATH in the recorded env it runs through /bin/sh,
/// else through a login zsh, so PATH matches the person's terminal, as LocoHost's Restart does.
- (NSString *)restart:(NSDictionary *)r pid:(pid_t *)pid {
    NSString *cmd = r[@"command"];
    if (![cmd isKindOfClass:NSString.class] || !cmd.length) return @"the record has no restart command";
    NSDictionary *env = [r[@"env"] isKindOfClass:NSDictionary.class] ? r[@"env"] : nil;
    NSString *dir = MMExpertDir(@"core");
    NSString *log = [dir stringByAppendingPathComponent:@"restart.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:log]) [NSData.data writeToFile:log atomically:YES];
    NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:log];
    [out seekToEndOfFile];
    [out writeData:[[NSString stringWithFormat:@"\n%@ $ %@\n", NSDate.date, cmd] dataUsingEncoding:NSUTF8StringEncoding]];
    NSTask *t = [NSTask new];
    BOOL login = !env[@"PATH"];
    t.executableURL = [NSURL fileURLWithPath:login ? @"/bin/zsh" : @"/bin/sh"];
    t.arguments = login ? @[@"-lc", cmd] : @[@"-c", cmd];
    NSString *cwd = r[@"cwd"];
    if ([cwd isKindOfClass:NSString.class] && cwd.length) t.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    if (env) {
        NSMutableDictionary *e = [NSProcessInfo.processInfo.environment mutableCopy];
        [e addEntriesFromDictionary:env];
        t.environment = e;
    }
    t.standardInput = NSFileHandle.fileHandleWithNullDevice; t.standardOutput = out; t.standardError = out;
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) return [@"the restart command would not start: " stringByAppendingString:err.localizedDescription];
    if (pid) *pid = t.processIdentifier;
    return nil;
}

- (NSString *)untrash:(NSArray *)items {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSDictionary *i in items) {
        NSString *from = i[@"from"], *to = i[@"to"];
        if ([fm fileExistsAtPath:from]) return [NSString stringWithFormat:@"something already exists at %@", from];
        if (![fm fileExistsAtPath:to]) return [NSString stringWithFormat:@"the Trash no longer holds %@", from.lastPathComponent];
    }
    for (NSDictionary *i in items.reverseObjectEnumerator) {
        NSString *from = i[@"from"], *to = i[@"to"];
        [fm createDirectoryAtPath:from.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *e = nil;
        if (![fm moveItemAtPath:to toPath:from error:&e]) return [NSString stringWithFormat:@"%@ could not leave the Trash: %@", from.lastPathComponent, e.localizedDescription];
    }
    return nil;
}

/// Recreates a worktree at its commit, as WFRestore does. The commit comes from the bundle when the repo lost it.
- (NSString *)unbundle:(NSDictionary *)b {
    NSString *repo = b[@"repo"], *path = b[@"worktree"], *head = b[@"head"], *branch = b[@"branch"], *bundle = b[@"path"];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) return @"something already exists at that path";
    NSString *out = nil;
    // The bundle is needed only when the repo lost the commit. A worktree whose commits are all on a remote has none.
    if (Git(repo, @[@"cat-file", @"-e", [head stringByAppendingString:@"^{commit}"]], nil) != 0) {
        if (!bundle.length || ![NSFileManager.defaultManager fileExistsAtPath:bundle])
            return bundle.length ? @"the bundle is missing" : @"the commit is gone from the repo, and no bundle was taken";
        if (Git(repo, @[@"fetch", @"--no-tags", bundle, @"HEAD"], &out) != 0)
            return [@"the commits could not be read back from the bundle: " stringByAppendingString:Tail(out, 300)];
    }
    NSArray *args;
    if (branch.length) {
        BOOL exists = Git(repo, @[@"rev-parse", @"--verify", @"--quiet", [@"refs/heads/" stringByAppendingString:branch]], nil) == 0;
        args = exists ? @[@"worktree", @"add", path, branch] : @[@"worktree", @"add", @"-b", branch, path, head];
    } else args = @[@"worktree", @"add", @"--detach", path, head];
    if (Git(repo, args, &out) != 0) return [@"git worktree add failed: " stringByAppendingString:Tail(out, 300)];
    return nil;
}

- (NSString *)unrecover:(NSDictionary *)r {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = r[@"dir"], *root = r[@"root"];
    NSMutableArray *missed = [NSMutableArray new];
    for (NSString *rel in r[@"saved"]) {
        NSString *to = [root stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:to]) continue;   // never write over what is there now
        [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if (![fm copyItemAtPath:[dir stringByAppendingPathComponent:rel] toPath:to error:nil]) [missed addObject:rel];
    }
    return missed.count ? [@"these files could not be put back: " stringByAppendingString:[missed componentsJoinedByString:@", "]] : nil;
}

/// Opens the app again from its path in "url", or from its "bundleID" when the record has no path,
/// as the rows imported from MinMacs 1.2 do.
- (NSString *)relaunch:(NSDictionary *)r {
    NSString *path = [r[@"url"] isKindOfClass:NSString.class] ? r[@"url"] : nil;
    if (!path && [r[@"bundleID"] isKindOfClass:NSString.class])
        path = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:r[@"bundleID"]].path;
    if (!path.length) return @"the record does not say where the app lives";
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.activates = NO;
    __block NSString *problem = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:path] configuration:cfg
                                    completionHandler:^(NSRunningApplication *app, NSError *e) {
        if (e) problem = [@"the app would not open: " stringByAppendingString:e.localizedDescription];
        dispatch_semaphore_signal(done);
    }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0) return @"the app took too long to open";
    return problem;
}

- (NSArray<MMUndoRecord *> *)partsOf:(NSString *)rid {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSDictionary *b in LogLatest(nil)) if ([b[@"parentRid"] isEqual:rid]) [parts addObject:[MMUndoRecord fromBody:b]];
    return parts;   // newest first, as LogLatest returns them
}

/// The rids a restore runs on now. The notification's Undo and the menu's Undo can ask at once,
/// and a second restore of the same record would run its restart command twice.
static NSMutableSet<NSString *> *Restoring(void) {
    static NSMutableSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}

- (NSString *)restore:(NSString *)rid {
    if (!rid.length) return @"no undo record with that id";
    @synchronized (Restoring()) {
        if ([Restoring() containsObject:rid]) return @"a restore of it is already running";
        [Restoring() addObject:rid];
    }
    NSString *problem = [self restoreOnce:rid];
    @synchronized (Restoring()) { [Restoring() removeObject:rid]; }
    return problem;
}

- (NSString *)restoreOnce:(NSString *)rid {
    MMUndoRecord *r = [self record:rid];
    if (!r) return @"no undo record with that id";
    if (r.state == MMUndoRestored) return @"it was already restored";
    if (r.state == MMUndoPending) return @"the action has not finished";
    if ([r.kind isEqualToString:@"tool"]) return @"a tool's own cleanup cannot be undone; its dry-run output is in the record";
    if (!r.canRestore) return @"the record holds nothing to restore";
    NSMutableArray *problems = [NSMutableArray new];
    for (MMUndoRecord *part in [self partsOf:rid]) {
        if (part.state == MMUndoRestored || !part.canRestore) continue;
        NSString *p = [self restore:part.rid];
        if (p) [problems addObject:[NSString stringWithFormat:@"%@: %@", part.subject ?: part.rid, p]];
    }
    NSDictionary *p = r.payload;
    NSMutableDictionary *done = [NSMutableDictionary new];
    NSString *problem = nil;
    if (!problem && p[@"restart"]) {
        pid_t pid = 0;
        problem = [self restart:p[@"restart"] pid:&pid];
        if (pid) done[@"restartedPid"] = @(pid);
    }
    if (!problem && [p[@"trashed"] count]) problem = [self untrash:p[@"trashed"]];
    if (!problem && p[@"bundle"]) problem = [self unbundle:p[@"bundle"]];
    // A removed worktree with no bundle: its commit is still in the repo, so it is recreated from there.
    else if (!problem && [p[@"worktree"] isKindOfClass:NSDictionary.class]) problem = [self unbundle:p[@"worktree"]];
    if (!problem && p[@"recovery"]) problem = [self unrecover:p[@"recovery"]];
    if (!problem && p[@"relaunch"]) problem = [self relaunch:p[@"relaunch"]];
    if (problem) [problems addObject:problem];
    if (problems.count) return [problems componentsJoinedByString:@"; "];
    done[@"restoredAt"] = @(NSDate.date.timeIntervalSince1970);
    @synchronized (self) {
        NSMutableDictionary *np = [r.payload mutableCopy];
        np[@"restored"] = done;
        r.payload = np;
        r.state = MMUndoRestored;
        [self write:r];
    }
    return nil;
}

- (NSArray<MMUndoRecord *> *)recent:(NSString *)expert limit:(NSUInteger)limit {
    NSArray *all = LogLatest(nil);
    NSMutableSet *parents = [NSMutableSet new];
    for (NSDictionary *b in all) if ([b[@"parentRid"] isKindOfClass:NSString.class]) [parents addObject:b[@"parentRid"]];
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *b in all) {
        if (expert && ![b[@"expert"] isEqual:expert]) continue;
        MMUndoRecord *r = [MMUndoRecord fromBody:b];
        if (!r) continue;
        r.hasParts = [parents containsObject:r.rid];
        [out addObject:r];
        if (limit && out.count >= limit) break;
    }
    return out;
}

- (MMUndoRecord *)record:(NSString *)rid {
    MMUndoRecord *r = [MMUndoRecord fromBody:LogLatestOf(rid)];
    if (r) r.hasParts = [self partsOf:rid].count > 0;
    return r;
}
@end

#pragma mark - Tool commands

@interface MMToolCommand ()
@property (readwrite, copy) NSString *tool, *path;
@property (readwrite) NSArray<NSString *> *args, *dryRunArgs;
@property (readwrite) NSDictionary<NSString *, NSString *> *env;
@property (readwrite) NSTimeInterval timeout;
@end

@implementation MMToolCommand
+ (instancetype)tool:(NSString *)tool path:(NSString *)path args:(NSArray<NSString *> *)args
          dryRunArgs:(NSArray<NSString *> *)dryRunArgs env:(NSDictionary<NSString *, NSString *> *)env {
    MMToolCommand *c = [MMToolCommand new];
    c.tool = tool; c.path = path; c.args = args ?: @[]; c.dryRunArgs = dryRunArgs; c.env = env; c.timeout = 600;
    return c;
}

- (NSString *)commandLine:(NSArray<NSString *> *)args { return Quoted([@[self.path ?: @""] arrayByAddingObjectsFromArray:args]); }

- (NSString *)dryRun:(NSString **)error {
    if (error) *error = nil;
    if (!self.dryRunArgs) return nil;
    NSString *out = nil;
    int st = RunTool(self.path, self.dryRunArgs, nil, self.env, self.timeout, &out);
    if (st != 0) {
        if (error) *error = [NSString stringWithFormat:@"the dry run %@: %@", st < 0 ? @"did not finish" : [NSString stringWithFormat:@"exited %d", st], Tail(out, 500)];
        return nil;
    }
    return out;
}

- (BOOL)runWithRecord:(MMUndoRecord *)record output:(NSString **)output error:(NSString **)error {
    NSString *e = nil;
    NSString *dry = [self dryRun:&e];
    NSString *line = [self commandLine:self.args];
    if (e) {
        [MMUndo.shared note:record payload:@{@"tool": self.tool ?: @"", @"command": line, @"dryRunError": e}];
        if (error) *error = e;
        return NO;
    }
    [MMUndo.shared note:record payload:@{@"tool": self.tool ?: @"", @"command": line,
                                         @"dryRun": self.dryRunArgs ? Tail(dry, 64 << 10) : line}];
    NSString *out = nil;
    int st = RunTool(self.path, self.args, nil, self.env, self.timeout, &out);
    [MMUndo.shared note:record payload:@{@"output": Tail(out, 64 << 10), @"exit": @(st)}];
    if (output) *output = out;
    if (st != 0) {
        if (error) *error = [NSString stringWithFormat:@"%@ %@", self.tool ?: @"the tool", st < 0 ? @"did not finish" : [NSString stringWithFormat:@"exited %d", st]];
        return NO;
    }
    return YES;
}
@end
