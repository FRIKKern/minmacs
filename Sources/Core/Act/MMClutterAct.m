// Clutter actions: the Trash for cache, build and leak rows, the tool's own command for tool rows.
// Ported from NN's Apply and FreedByDelete, internal/leaks/module.go and internal/sizer, with the permanent delete
// replaced by the Trash, and the tool command preceded by an APFS clone that undo copies back from.
#import "Core/Act/MMClutterAct.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#import "Core/Know/MMGit.h"
#include <fts.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <unistd.h>

NSArray<NSDictionary *> *MMClutterAudit(NSArray<NSString *> *paths) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in paths) {
        struct stat st;
        BOOL exists = lstat(p.fileSystemRepresentation, &st) == 0;
        NSMutableDictionary *a = [@{@"path": p, @"exists": @(exists)} mutableCopy];
        if (exists) {
            MMSize s = [MMSizer quick:p];
            a[@"allocated"] = @(s.allocated); a[@"files"] = @(s.files); a[@"mtime"] = @(st.st_mtimespec.tv_sec);
        }
        [out addObject:a];
    }
    return out;
}

@interface MMClutterAction ()
@property (readwrite) MMClutterItem *item;
@property (strong) MMFinding *finding;
@property (strong) MMClutterCatalog *catalog;
@property (strong) MMClutterItem *fresh;
@end

@implementation MMClutterAction

+ (instancetype)actionFor:(MMFinding *)finding item:(MMClutterItem *)item catalog:(MMClutterCatalog *)catalog {
    if (!finding || !item) return nil;
    MMClutterAction *a = [MMClutterAction new];
    a.finding = finding; a.item = item; a.catalog = catalog ?: MMClutterCatalog.shared;
    return a;
}

- (BOOL)isTool { return self.item.kind.klass == MMClutterTool; }
- (NSString *)kind { return self.isTool ? @"clean" : @"trash"; }

- (NSString *)toolPath { return MMClutterToolPath(self.item.kind.cleanupArgs.firstObject); }

- (NSString *)recheck {
    MMClutterKind *k = self.item.kind;
    if (!k) return @"cannot verify which row it belongs to";
    if (k.reportOnly) return k.ownerSetting ?: @"its row only reports it";
    if (self.isTool && !self.toolPath) return [NSString stringWithFormat:@"%@ is not installed", k.cleanupArgs.firstObject ?: @"the tool"];
    MMClutterItem *now = [self.catalog inspect:self.item];
    if (!now) return @"it is gone";
    if (now.state != MMClutterFree) return now.why ?: @"it is in use";
    for (NSString *m in now.members) {
        NSString *w = [self.catalog whyNot:m kind:k];
        if (w) return w;
    }
    self.fresh = now;
    return nil;
}

- (NSString *)dryRun {
    MMClutterItem *i = self.fresh ?: self.item;
    NSString *what = i.members.count == 1 ? i.members.firstObject.stringByAbbreviatingWithTildeInPath
                                          : [NSString stringWithFormat:@"%lu folders of %@", (unsigned long)i.members.count, i.path.stringByAbbreviatingWithTildeInPath];
    if (self.isTool)
        return [NSString stringWithFormat:@"would copy %@ to the recovery folder, then run %@. Undo copies back what it removed.", what, i.kind.cleanup];
    return [NSString stringWithFormat:@"would move %@ to the Trash. Undo moves it back.", what];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMClutterItem *i = self.fresh ?: [self.catalog inspect:self.item];
    if (!i) { if (error) *error = @"it is gone"; return NO; }
    NSArray *paths = i.members;
    [MMUndo.shared note:record payload:@{@"kindID": i.kind.kindID, @"paths": paths, @"audit": @{@"before": MMClutterAudit(paths)}}];
    BOOL ok = self.isTool ? [self clean:i record:record error:error] : [self trash:i record:record error:error];
    MMUndoRecord *now = [MMUndo.shared record:record.rid];
    NSMutableDictionary *audit = [now.payload[@"audit"] mutableCopy] ?: [NSMutableDictionary new];
    audit[@"after"] = MMClutterAudit(paths);
    [MMUndo.shared note:record payload:@{@"audit": audit}];
    return ok;
}

/// Each path is checked against the walls once more, right before it moves.
- (BOOL)trash:(MMClutterItem *)i record:(MMUndoRecord *)record error:(NSString **)error {
    NSMutableArray *refused = [NSMutableArray new];
    NSInteger moved = 0;
    for (NSString *m in i.members) {
        NSString *w = [self.catalog whyNot:m kind:i.kind];
        if (w) { [refused addObject:[NSString stringWithFormat:@"%@: %@", m.lastPathComponent, w]]; continue; }
        NSError *e = nil;
        if ([MMUndo.shared trash:[NSURL fileURLWithPath:m] record:record error:&e]) moved++;
        else [refused addObject:[NSString stringWithFormat:@"%@: %@", m.lastPathComponent, e.localizedDescription ?: @"it could not go to the Trash"]];
    }
    if (refused.count) [MMUndo.shared note:record payload:@{@"refused": refused}];
    if (moved == 0) { if (error) *error = refused.firstObject ?: @"nothing went to the Trash"; return NO; }
    return YES;
}

/// The paths under copy whose twin is gone now: what the tool removed, relative to /, as the recovery copy holds them
/// under dir. A gone folder is named once.
static NSArray<NSString *> *Vanished(NSString *dir, NSString *copy) {
    NSMutableArray *out = [NSMutableArray new];
    char *argv[] = { (char *)copy.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_NOSTAT, NULL);
    if (!fts) return out;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info == FTS_DP || e->fts_level == 0) continue;
        NSString *p = @(e->fts_path);
        if (![p hasPrefix:[dir stringByAppendingString:@"/"]]) continue;
        NSString *rel = [p substringFromIndex:dir.length + 1];
        struct stat st;
        if (lstat([@"/" stringByAppendingString:rel].fileSystemRepresentation, &st) != 0) {
            [out addObject:rel];
            fts_set(fts, e, FTS_SKIP);
        }
    }
    fts_close(fts);
    return out;
}

- (BOOL)clean:(MMClutterItem *)i record:(MMUndoRecord *)record error:(NSString **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [[MMExpertDir(@"noonoo") stringByAppendingPathComponent:@"recovery"] stringByAppendingPathComponent:record.rid];
    for (NSString *m in i.members) {
        NSString *to = [dir stringByAppendingString:m];
        [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        // An APFS clone shares every block, so the copy costs almost nothing until the tool removes the original.
        if (clonefile(m.fileSystemRepresentation, to.fileSystemRepresentation, CLONE_NOFOLLOW) != 0) {
            if (error) *error = [NSString stringWithFormat:@"no recovery copy of %@ could be made: %s. MinMacs leaves it.", m.lastPathComponent, strerror(errno)];
            return NO;
        }
    }
    NSArray *argv = i.kind.cleanupArgs, *dry = i.kind.dryRunArgs;
    NSArray *dryArgs = dry.count && [dry.firstObject isEqualToString:argv.firstObject] ? [dry subarrayWithRange:NSMakeRange(1, dry.count - 1)] : nil;
    MMToolCommand *cmd = [MMToolCommand tool:i.kind.kindID path:self.toolPath args:[argv subarrayWithRange:NSMakeRange(1, argv.count - 1)]
                                  dryRunArgs:dryArgs env:nil];
    NSString *out = nil, *err = nil;
    BOOL ok = [cmd runWithRecord:record output:&out error:&err];
    // Whatever the exit status, what is gone now can be copied back.
    NSMutableArray *saved = [NSMutableArray new];
    for (NSString *m in i.members) {
        NSString *copy = [dir stringByAppendingString:m];
        struct stat st;
        if (lstat(m.fileSystemRepresentation, &st) != 0) [saved addObject:[m substringFromIndex:1]];
        else [saved addObjectsFromArray:Vanished(dir, copy)];
    }
    // A copy of a path the tool left in place shares its blocks with the original until one of them changes.
    // Restore copies only the saved paths, from dir to root, and never over a file that exists.
    [MMUndo.shared note:record payload:@{@"recovery": @{@"dir": dir, @"root": @"/", @"saved": saved, @"skipped": @[]}}];
    if (!ok && error) *error = err ?: @"the tool failed";
    return ok;
}

@end

#pragma mark - A row's own cleanup command, for good

int64_t MMClutterFreedFromOutput(NSString *output) {
    if (!output.length) return -1;
    static NSRegularExpression *size, *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+(?:\\.[0-9]+)?)\\s?([kKMGT]i?B|B|bytes)(?![A-Za-z])" options:0 error:nil];
        words = [NSRegularExpression regularExpressionWithPattern:@"free|reclaim|remov|delet|total|would" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    int64_t found = -1;
    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange all = NSMakeRange(0, line.length);
        if (![words firstMatchInString:line options:0 range:all]) continue;
        NSTextCheckingResult *m = [size matchesInString:line options:0 range:all].lastObject;
        if (!m) continue;
        double n = [line substringWithRange:[m rangeAtIndex:1]].doubleValue;
        NSString *u = [line substringWithRange:[m rangeAtIndex:2]];
        double scale = 1;
        if (u.length >= 2 && ![u isEqualToString:@"bytes"]) {
            NSUInteger power = [@"KMGT" rangeOfString:[u substringToIndex:1].uppercaseString].location + 1;
            scale = pow([u characterAtIndex:1] == 'i' ? 1024.0 : 1000.0, (double)power);
        }
        found = (int64_t)llround(n * scale);
    }
    return found;
}

NSString *MMClutterCommandTitle(MMClutterKind *k) {
    return k.cleanup.length ? [NSString stringWithFormat:@"Run %@, Cannot Be Undone", k.cleanup] : nil;
}

static MMClutterAppsProvider gRunningApps;
void MMClutterUseRunningApps(MMClutterAppsProvider provider) { gRunningApps = [provider copy]; }

NSArray<NSString *> *MMClutterRunningQuitFirst(MMClutterKind *k) {
    if (!k.quitFirst.count) return @[];
    NSMutableSet *running = [NSMutableSet new];
    MMClutterAppsProvider p = gRunningApps;
    if (p) [running addObjectsFromArray:p() ?: @[]];
    else for (MMApp *a in MMRunningApps()) if (a.bundleID) [running addObject:a.bundleID];
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *b in k.quitFirst) if ([running containsObject:b]) [out addObject:b];
    return out;
}

/// The last dry run of each row, in <noonoo>/commands.json, kept in memory and read again when the file changed,
/// so a dry run the CLI ran reaches the app.
static NSMutableDictionary *gDryRuns;
static struct timespec gDryRunsMtime;
static NSObject *DryRunLock(void) { static NSObject *o; static dispatch_once_t once; dispatch_once(&once, ^{ o = [NSObject new]; }); return o; }
static NSString *DryRunPath(void) { return [MMExpertDir(@"noonoo") stringByAppendingPathComponent:@"commands.json"]; }
static NSMutableDictionary *DryRuns(void) {
    struct stat st;
    struct timespec m = stat(DryRunPath().fileSystemRepresentation, &st) == 0 ? st.st_mtimespec : (struct timespec){0, 0};
    if (m.tv_sec != gDryRunsMtime.tv_sec || m.tv_nsec != gDryRunsMtime.tv_nsec) { gDryRuns = nil; gDryRunsMtime = m; }
    if (!gDryRuns) {
        NSData *d = [NSData dataWithContentsOfFile:DryRunPath()];
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
        gDryRuns = [j isKindOfClass:NSMutableDictionary.class] ? j : [NSMutableDictionary new];
    }
    return gDryRuns;
}
NSDictionary *MMClutterLastDryRun(NSString *kindID) {
    if (!kindID) return nil;
    @synchronized (DryRunLock()) { return [DryRuns()[kindID] copy]; }
}
static void KeepDryRun(NSDictionary *run) {
    @synchronized (DryRunLock()) {
        DryRuns()[run[@"kindID"]] = run;
        [[NSJSONSerialization dataWithJSONObject:gDryRuns options:NSJSONWritingSortedKeys error:nil] writeToFile:DryRunPath() atomically:YES];
        struct stat st;
        if (stat(DryRunPath().fileSystemRepresentation, &st) == 0) gDryRunsMtime = st.st_mtimespec;
    }
}

static NSString *TailOf(NSString *s, NSUInteger n) { return s.length > n ? [s substringFromIndex:s.length - n] : (s ?: @""); }

/// One run of the tool through MMRunTask: {exit, timedOut, didRun, output}. Only the child started here is signaled.
static NSDictionary *RunCommand(NSString *path, NSArray<NSString *> *args, NSTimeInterval timeout) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    NSData *o = nil, *x = nil;
    MMRunResult r = MMRunTask(t, nil, timeout, &o, &x);
    NSMutableData *all = [o ?: NSData.data mutableCopy];
    [all appendData:x ?: NSData.data];
    NSString *out = [[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding] ?: @"";
    return @{@"exit": @(r.didRun && !r.timedOut ? r.status : -1), @"timedOut": @(r.timedOut), @"didRun": @(r.didRun),
             @"output": TailOf(out, 64 << 10)};
}

static NSString *RunProblem(NSString *what, NSDictionary *run, NSTimeInterval limit) {
    if (![run[@"didRun"] boolValue]) return [what stringByAppendingString:@" would not start"];
    if ([run[@"timedOut"] boolValue]) return [NSString stringWithFormat:@"%@ ran past its limit of %.0f seconds and was stopped", what, limit];
    int st = [run[@"exit"] intValue];
    return st == 0 ? nil : [NSString stringWithFormat:@"%@ exited %d: %@", what, st, TailOf([run[@"output"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], 300)];
}

static uint64_t Allocated(NSArray<NSDictionary *> *audit) {
    uint64_t n = 0;
    for (NSDictionary *a in audit) n += [a[@"allocated"] unsignedLongLongValue];
    return n;
}

@interface MMClutterCommandAction ()
@property (readwrite) MMClutterItem *item;
@property (readwrite, copy) NSString *by, *toolPath;
@property (readwrite) NSDictionary *lastDryRun;
@property (strong) MMFinding *finding;
@property (strong) MMClutterCatalog *catalog;
@property (strong) MMClutterItem *fresh;
@end

@implementation MMClutterCommandAction

+ (instancetype)actionFor:(MMFinding *)finding item:(MMClutterItem *)item catalog:(MMClutterCatalog *)catalog by:(NSString *)by {
    if (!finding || !item.kind.cleanupArgs.count) return nil;
    MMClutterCommandAction *a = [MMClutterCommandAction new];
    a.finding = finding; a.item = item; a.catalog = catalog ?: MMClutterCatalog.shared; a.by = by;
    a.toolPath = MMClutterToolPath(item.kind.cleanupArgs.firstObject);
    a.timeout = 300; a.dryRunTimeout = 120;
    return a;
}

- (NSString *)kind { return @"tool"; }
- (NSString *)title { return MMClutterCommandTitle(self.item.kind); }

/// The command's arguments after the binary, and the dry run's when it names the same binary.
- (NSArray<NSString *> *)args { NSArray *a = self.item.kind.cleanupArgs; return [a subarrayWithRange:NSMakeRange(1, a.count - 1)]; }
- (NSArray<NSString *> *)dryArgs {
    NSArray *d = self.item.kind.dryRunArgs;
    return d.count && [d.firstObject isEqualToString:self.item.kind.cleanupArgs.firstObject] ? [d subarrayWithRange:NSMakeRange(1, d.count - 1)] : nil;
}

- (NSString *)recheck {
    MMClutterKind *k = self.item.kind;
    if (![self.by isEqualToString:@"manual"] && ![self.by isEqualToString:@"cli"])
        return @"a tool's own cleanup runs only when you press it";
    if (!k.cleanupArgs.count) return @"its row names no command";
    if (k.reportOnly) return k.ownerSetting ?: @"its row only reports it";
    NSString *name = k.cleanupArgs.firstObject;
    NSString *now = MMClutterToolPath(name);
    if (!self.toolPath || !now) return [NSString stringWithFormat:@"%@ is not installed", name];
    if (![now isEqualToString:self.toolPath]) return [NSString stringWithFormat:@"%@ moved since this was asked, to %@", name, now.stringByAbbreviatingWithTildeInPath];
    struct stat st;
    if (stat(now.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode) || access(now.fileSystemRepresentation, X_OK) != 0)
        return [NSString stringWithFormat:@"%@ at %@ is not a program MinMacs can run", name, now.stringByAbbreviatingWithTildeInPath];
    NSArray *running = MMClutterRunningQuitFirst(k);
    if (running.count) return [NSString stringWithFormat:@"quit %@ first", [running componentsJoinedByString:@" and "]];
    MMClutterItem *i = [self.catalog inspect:self.item];
    if (!i) return @"it is gone";
    if (i.state != MMClutterFree) return i.why ?: @"it is in use";
    for (NSString *m in i.members) {
        NSString *w = [self.catalog whyNot:m kind:k];
        if (w) return w;
    }
    self.fresh = i;
    return nil;
}

- (NSString *)dryRun {
    MMClutterItem *i = self.fresh ?: self.item;
    MMClutterKind *k = i.kind;
    NSString *never = [NSString stringWithFormat:@"It cannot be undone. %@", k.rebuild.length ? [k.rebuild stringByAppendingString:@"."] : @"The tool fetches what it needs again."];
    NSArray *dry = self.dryArgs;
    if (!dry || !self.toolPath) {
        return [NSString stringWithFormat:@"would run %@ on %@, about %@ by the last scan. %@", k.cleanup,
                i.path.stringByAbbreviatingWithTildeInPath, [NSByteCountFormatter stringFromByteCount:(long long)i.size.freedIfDeleted countStyle:NSByteCountFormatterCountStyleFile], never];
    }
    NSDictionary *run = RunCommand(self.toolPath, dry, self.dryRunTimeout);
    int64_t would = MMClutterFreedFromOutput(run[@"output"]);
    NSMutableDictionary *kept = [run mutableCopy];
    [kept removeObjectForKey:@"didRun"];
    kept[@"kindID"] = k.kindID; kept[@"command"] = k.dryRun; kept[@"at"] = @(NSDate.date.timeIntervalSince1970);
    kept[@"wouldFree"] = @(would);
    kept[@"output"] = TailOf(run[@"output"], 4096);
    self.lastDryRun = kept;
    KeepDryRun(kept);
    NSString *problem = RunProblem([@"the dry run " stringByAppendingString:k.dryRun], run, self.dryRunTimeout);
    if (problem) return [NSString stringWithFormat:@"would not run %@: %@", k.cleanup, problem];
    NSString *size = would >= 0 ? [NSString stringWithFormat:@"%@, by its dry run", [NSByteCountFormatter stringFromByteCount:would countStyle:NSByteCountFormatterCountStyleFile]]
                                : @"a size its dry run does not name";
    return [NSString stringWithFormat:@"would run %@ to free %@. %@", k.cleanup, size, never];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMClutterItem *i = self.fresh ?: [self.catalog inspect:self.item];
    if (!i) { if (error) *error = @"it is gone"; return NO; }
    MMClutterKind *k = i.kind;
    NSArray *paths = i.members;
    NSArray *before = MMClutterAudit(paths);
    NSString *undo = [NSString stringWithFormat:@"%@ removes it for good, so this cannot be undone.%@", k.cleanup,
                      k.rebuild.length ? [NSString stringWithFormat:@" %@.", k.rebuild] : @""];
    [MMUndo.shared note:record payload:@{@"kindID": k.kindID, @"paths": paths, @"tool": k.kindID, @"toolPath": self.toolPath ?: @"",
                                         @"command": k.cleanup, @"undo": undo, @"audit": @{@"before": before},
                                         @"sizeBefore": @(Allocated(before))}];
    NSArray *dry = self.dryArgs;
    if (dry) {
        NSDictionary *run = RunCommand(self.toolPath, dry, self.dryRunTimeout);
        int64_t would = MMClutterFreedFromOutput(run[@"output"]);
        [MMUndo.shared note:record payload:@{@"dryRun": run[@"output"], @"dryRunExit": run[@"exit"], @"dryRunTimedOut": run[@"timedOut"],
                                             @"wouldFree": @(would)}];
        NSString *problem = RunProblem([@"the dry run " stringByAppendingString:k.dryRun], run, self.dryRunTimeout);
        if (problem) { if (error) *error = [problem stringByAppendingString:@". MinMacs did not run the command."]; return NO; }
    } else {
        [MMUndo.shared note:record payload:@{@"dryRun": [@"no dry-run form; ran " stringByAppendingString:k.cleanup]}];
    }
    NSDictionary *run = RunCommand(self.toolPath, self.args, self.timeout);
    NSArray *after = MMClutterAudit(paths);
    uint64_t was = Allocated(before), now = Allocated(after);
    [MMUndo.shared note:record payload:@{@"output": run[@"output"], @"exit": run[@"exit"], @"timedOut": run[@"timedOut"],
                                         @"audit": @{@"before": before, @"after": after}, @"sizeAfter": @(now),
                                         @"sizeFreed": @(was > now ? was - now : 0)}];
    NSString *problem = RunProblem(k.cleanup, run, self.timeout);
    if (problem && error) *error = problem;
    return problem == nil;
}

@end
