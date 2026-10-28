// Investigate, issue #35. MMInvestigate.h says what it does and why the tools are MinMacs's own.
#import "Core/Review/MMInvestigate.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#include <fcntl.h>
#include <fts.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const MMInvestigateModel = @"haiku";
const NSInteger MMInvestigateMaxTurns = 12;
const NSInteger MMInvestigateDefaultEstimate = 35000;

@interface MMModel (MMInvestigate)
+ (MMAnswer *)investigate:(NSString *)question system:(NSString *)system folders:(NSArray<NSString *> *)folders
                    audit:(NSString *)audit maxTurns:(NSInteger)maxTurns;
@end

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }

static NSString *Tilde(NSString *s) {
    NSString *home = NSHomeDirectory();
    if (home.length <= 1 || !s) return s;
    if ([s isEqualToString:home]) return @"~";
    return [s hasPrefix:[home stringByAppendingString:@"/"]] ? [@"~" stringByAppendingString:[s substringFromIndex:home.length]] : s;
}

static NSString *Real(NSString *path) {
    char buf[PATH_MAX];
    return path.length && realpath(path.fileSystemRepresentation, buf) ? @(buf) : nil;
}

/// YES when path is folder or lies below it. Both are real paths.
static BOOL Inside(NSString *path, NSString *folder) {
    if ([folder isEqualToString:@"/"]) return YES;
    return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

#pragma mark - Scope

NSString *MMInvestigateScoped(NSArray<NSString *> *folders, NSString *path, NSString **reason) {
    if (!folders.count) { if (reason) *reason = @"no folder is in scope"; return nil; }
    NSString *p = path.length ? path : folders.firstObject;
    if ([p isEqualToString:@"~"] || [p hasPrefix:@"~/"]) p = p.stringByExpandingTildeInPath;
    if (!p.isAbsolutePath) p = [folders.firstObject stringByAppendingPathComponent:p];
    // realpath resolves every symlink and every .. before the check, so neither can lead out.
    NSString *real = Real(p);
    if (!real) { if (reason) *reason = [NSString stringWithFormat:@"%@ does not exist", Tilde(p)]; return nil; }
    for (NSString *f in folders) if (Inside(real, f)) return real;
    if (reason) *reason = [NSString stringWithFormat:@"%@ is outside the folders of this investigation", Tilde(p)];
    return nil;
}

NSArray<NSString *> *MMInvestigateFolders(NSArray<NSString *> *candidates) {
    NSString *home = Real(NSHomeDirectory());
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSString *c in candidates) {
        if (![c isKindOfClass:NSString.class] || !c.length) continue;
        NSString *r = Real([c hasPrefix:@"~"] ? c.stringByExpandingTildeInPath : c);
        BOOL dir = NO;
        if (!r || ![NSFileManager.defaultManager fileExistsAtPath:r isDirectory:&dir]) continue;
        if (!dir) r = r.stringByDeletingLastPathComponent;
        if ([r isEqualToString:@"/"] || r.pathComponents.count < 3) continue;   // the root and folders like /Users
        if (home && Inside(home, r)) continue;                                  // the home folder or above it
        BOOL covered = NO;
        for (NSString *o in out) if (Inside(r, o)) covered = YES;
        if (covered) continue;
        [out filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *o, NSDictionary *b) { return !Inside(o, r); }]];
        [out addObject:r];
    }
    return [out copy];
}

#pragma mark - A run

@implementation MMInvestigation

- (NSDictionary *)json {
    NSMutableDictionary *j = [@{@"subject": self.subjectID ?: @"", @"title": self.title ?: @"", @"question": self.question ?: @"",
                                @"model": self.model ?: MMInvestigateModel, @"folders": self.folders ?: @[],
                                @"tool_calls": @(self.toolCalls), @"refused": @(self.refused), @"bytes_read": @(self.bytesRead),
                                @"running": @(self.running)} mutableCopy];
    if (self.answer) j[@"answer"] = self.answer;
    if (self.error) j[@"error"] = self.error;
    if (self.usage) j[@"usage"] = self.usage.json;
    if (self.at) j[@"at"] = @(self.at.timeIntervalSince1970);
    return j;
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (!Dict(j) || !Str(j[@"subject"]).length) return nil;
    MMInvestigation *r = [MMInvestigation new];
    r.subjectID = j[@"subject"]; r.title = Str(j[@"title"]); r.question = Str(j[@"question"]);
    r.answer = Str(j[@"answer"]); r.error = Str(j[@"error"]); r.model = Str(j[@"model"]);
    r.folders = [j[@"folders"] isKindOfClass:NSArray.class] ? j[@"folders"] : @[];
    r.usage = [MMUsage fromJSON:Dict(j[@"usage"])];
    r.toolCalls = [j[@"tool_calls"] integerValue]; r.refused = [j[@"refused"] integerValue]; r.bytesRead = [j[@"bytes_read"] integerValue];
    if ([j[@"at"] isKindOfClass:NSNumber.class]) r.at = [NSDate dateWithTimeIntervalSince1970:[j[@"at"] doubleValue]];
    return r;
}

@end

@implementation MMInvestigateEstimate

- (NSString *)sentence {
    NSString *model = self.model.length ? [[self.model substringToIndex:1].uppercaseString stringByAppendingString:[self.model substringFromIndex:1]] : @"Haiku";
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    NSString *n = [f stringFromNumber:@(self.tokens)];
    NSString *basis = self.basedOn == 0 ? @"an estimate before the first run" :
        self.basedOn == 1 ? @"the cost of the last run" : [NSString stringWithFormat:@"the median of the last %ld runs", (long)self.basedOn];
    return [NSString stringWithFormat:@"About %@ tokens on %@, %@.", n, model, basis];
}

- (NSDictionary *)json { return @{@"model": self.model ?: MMInvestigateModel, @"tokens": @(self.tokens), @"based_on": @(self.basedOn)}; }

@end

#pragma mark - Subjects

@implementation MMInvestigateSubject

static NSString *const kFindingQuestion = @"What is this, what is it for, and does anything still need it?";
static NSString *const kWorkstreamQuestion = @"What is this piece of work, how far along is it, and what is left to do?";

+ (instancetype)finding:(MMFinding *)f snapshot:(MMSnapshot *)s {
    if (!f) return nil;
    NSMutableArray *c = [NSMutableArray new];
    for (NSString *p in @[f.path ?: @"", f.ownerPath ?: @"", f.owner.path ?: @""]) if (p.length) [c addObject:p];
    MMWorkstream *w = [s workstreamAt:f.path ?: f.ownerPath];
    if (w.worktree.path) [c addObject:w.worktree.path];
    NSArray *folders = MMInvestigateFolders(c);
    if (!folders.count) return nil;
    MMInvestigateSubject *x = [MMInvestigateSubject new];
    x.subjectID = f.findingID; x.title = f.title; x.expert = f.expert; x.folders = folders; x.question = kFindingQuestion;
    return x;
}

+ (instancetype)workstream:(MMWorkstream *)w {
    if (!w) return nil;
    NSArray *folders = MMInvestigateFolders(@[w.worktree.path ?: @"", w.owner.path ?: @""]);
    if (!folders.count) return nil;
    MMInvestigateSubject *x = [MMInvestigateSubject new];
    x.subjectID = w.owner.ownerID; x.title = w.owner.name ?: w.worktree.path.lastPathComponent; x.expert = @"workstream";
    x.folders = folders; x.question = kWorkstreamQuestion;
    return x;
}

+ (instancetype)folder:(NSString *)path {
    NSArray *folders = MMInvestigateFolders(path.length ? @[path] : @[]);
    if (!folders.count) return nil;
    MMInvestigateSubject *x = [MMInvestigateSubject new];
    x.subjectID = [@"folder:" stringByAppendingString:Tilde(folders[0])]; x.title = [folders[0] lastPathComponent];
    x.expert = @"folder"; x.folders = folders; x.question = kWorkstreamQuestion;
    return x;
}

+ (instancetype)named:(NSString *)name snapshot:(MMSnapshot *)s cwd:(NSString *)cwd {
    if (!name.length) return nil;
    MMFinding *f = [s finding:name];
    if (f) return [self finding:f snapshot:s];
    for (MMWorkstream *w in s.workstreams) if ([w.owner.ownerID isEqualToString:name]) return [self workstream:w];
    NSString *p = [name hasPrefix:@"~"] ? name.stringByExpandingTildeInPath : name;
    if (!p.isAbsolutePath) p = [(cwd ?: NSFileManager.defaultManager.currentDirectoryPath) stringByAppendingPathComponent:p];
    NSString *real = Real(p);
    if (!real) return nil;
    MMFinding *at = nil;
    for (MMFinding *x in s.findings) {
        NSString *xp = Real(x.path);
        if (xp && [xp isEqualToString:real] && (!at || [x.kind isEqualToString:@"worktree"])) at = x;
    }
    // Each step that finds no folder it may read falls through to the next, down to the folder itself.
    MMInvestigateSubject *x = at ? [self finding:at snapshot:s] : nil;
    if (!x) x = [self workstream:[s workstreamAt:real]];
    return x ?: [self folder:real];
}

@end

#pragma mark - The store and the run

/// Asks the graph to rebuild, so a card shows the new state. Only once the graph has built, so a cold CLI never
/// starts a build of its own for this.
static void Rebuild(NSString *why) {
    if (MMGraph.shared.latest) [MMGraph.shared rebuild:why];
}

static NSString *const kSystem =
    @"You look into one finding or one piece of work on a developer's Mac for MinMacs, a menu bar app. "
    @"Your only tools are Read, Grep and Glob, and they open only the folders the message names. A path outside them is refused. "
    @"Never print secrets, keys, tokens or the contents of .env files. Use few tool calls: read what answers the question, then stop. "
    @"Answer in at most five plain sentences, and name the files and facts you used.";

@implementation MMInvestigations {
    NSMutableDictionary<NSString *, MMInvestigation *> *_latest;
    NSMutableArray<NSNumber *> *_costs;                 // uncached tokens of finished runs, newest first
    BOOL _loaded, _loading;
    dispatch_queue_t _queue;                            // runs, one at a time
    dispatch_queue_t _prepare;                          // loads and estimates, so an alert never waits on a run
}

+ (instancetype)shared {
    static MMInvestigations *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMInvestigations new]; });
    return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _latest = [NSMutableDictionary new]; _costs = [NSMutableArray new];
    _queue = MMQueue(@"core", @"investigate", QOS_CLASS_UTILITY);
    _prepare = MMQueue(@"core", @"investigate-prepare", QOS_CLASS_USER_INITIATED);
    return self;
}

/// On main a read never touches the log. The first read there loads it on the investigate queue, and the graph
/// rebuilds when it is done, so an open card shows what was saved.
- (void)loadSoon {
    @synchronized (self) { if (_loaded || _loading) return; _loading = YES; }
    dispatch_async(_prepare, ^{
        [self load];
        BOOL any;
        @synchronized (self) { any = self->_latest.count > 0; }
        if (any) Rebuild(@"investigations loaded");   // only when a card has something new to show
    });
}

- (MMInvestigation *)latestFor:(NSString *)subjectID {
    if (!subjectID) return nil;
    BOOL loaded;
    @synchronized (self) { loaded = _loaded; }
    if (!loaded) { if (NSThread.isMainThread) [self loadSoon]; else [self load]; }
    @synchronized (self) { return _latest[subjectID]; }
}

- (MMInvestigateEstimate *)estimate {
    if (NSThread.isMainThread) [self loadSoon]; else [self load];
    MMInvestigateEstimate *e = [MMInvestigateEstimate new];
    e.model = MMInvestigateModel;
    NSArray *last;
    @synchronized (self) { last = [_costs subarrayWithRange:NSMakeRange(0, MIN(_costs.count, (NSUInteger)5))]; }
    if (!last.count) { e.tokens = MMInvestigateDefaultEstimate; return e; }
    NSArray *sorted = [last sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger n = sorted.count;
    e.tokens = n % 2 ? [sorted[n / 2] integerValue] : ([sorted[n / 2 - 1] integerValue] + [sorted[n / 2] integerValue]) / 2;
    e.basedOn = (NSInteger)n;
    return e;
}

- (void)load {
    @synchronized (self) { if (_loaded) return; }
    NSArray<MMLogEntry *> *rows = [MMLog.shared latest:@"investigate" expert:nil subject:nil since:nil limit:500];
    @synchronized (self) {
        if (_loaded) return;
        for (MMLogEntry *e in rows) {   // newest first
            MMInvestigation *r = [MMInvestigation fromJSON:e.body];
            if (!r) continue;
            if (!_latest[r.subjectID]) _latest[r.subjectID] = r;
            if (r.answer && r.usage.uncached > 0) [_costs addObject:@(r.usage.uncached)];
        }
        _loaded = YES; _loading = NO;
    }
}

- (void)remember:(MMInvestigation *)run {
    if (!run.subjectID) return;
    @synchronized (self) {
        _loaded = YES;
        _latest[run.subjectID] = run;
        if (run.answer && run.usage.uncached > 0) [_costs insertObject:@(run.usage.uncached) atIndex:0];
    }
}

/// The audit lines the tool server wrote: how many calls, how many refused, and the bytes handed over.
static void ReadAudit(NSString *path, MMInvestigation *r) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSDictionary *j = line.length ? Dict([NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]) : nil;
        if (!j) continue;
        r.toolCalls++;
        if (Str(j[@"refused"])) r.refused++;
        r.bytesRead += [j[@"bytes"] integerValue];
    }
}

/// The running record for subject, put in memory, or nil when one already runs for it.
- (MMInvestigation *)reserve:(MMInvestigateSubject *)subject question:(NSString *)question {
    MMInvestigation *r = [MMInvestigation new];
    r.subjectID = subject.subjectID; r.title = subject.title; r.folders = subject.folders; r.model = MMInvestigateModel;
    r.question = question.length ? question : subject.question; r.at = NSDate.date; r.running = YES;
    @synchronized (self) {
        if (_latest[r.subjectID].running) return nil;
        _latest[r.subjectID] = r;
    }
    return r;
}

- (MMInvestigation *)run:(MMInvestigateSubject *)subject question:(NSString *)question error:(NSString **)error {
    if (!subject.folders.count) { if (error) *error = @"there is no folder to look in"; return nil; }
    [self load];
    MMInvestigation *r = [self reserve:subject question:question];
    if (!r) { if (error) *error = @"an investigation of this already runs"; return nil; }
    return [self runReserved:r subject:subject error:error];
}

- (MMInvestigation *)runReserved:(MMInvestigation *)r subject:(MMInvestigateSubject *)subject error:(NSString **)error {
    [self load];
    Rebuild(@"investigate started");
    NSString *dir = [MMExpertDir(@"review") stringByAppendingPathComponent:@"investigate"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *audit = [dir stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".jsonl"]];
    NSMutableArray *shown = [NSMutableArray new];
    for (NSString *f in subject.folders) [shown addObject:Tilde(f)];
    NSString *prompt = [NSString stringWithFormat:@"Subject: %@\nFolders: %@\nQuestion: %@\n", MMClip(subject.title, 200) ?: @"a folder",
                        [shown componentsJoinedByString:@", "], MMClip(r.question, 1000) ?: @""];
    MMAnswer *a = [MMModel investigate:prompt system:kSystem folders:subject.folders audit:audit maxTurns:MMInvestigateMaxTurns];
    [MMBudget.shared record:a.usage expert:@"investigate"];
    ReadAudit(audit, r);
    [NSFileManager.defaultManager removeItemAtPath:audit error:nil];
    MMInvestigation *done = [MMInvestigation fromJSON:r.json];
    done.usage = a.usage;
    done.model = a.model ?: MMInvestigateModel;
    NSString *text = Str(a.json[@"text"]);
    // The answer is redacted with the home folder as ~, as everything the review sends or saves.
    if (text.length) done.answer = MMRedact(Tilde([text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]));
    else done.error = a.error ?: @"the model did not answer";
    [MMLog.shared append:@"investigate" rid:nil expert:subject.expert ?: @"investigate" subject:done.subjectID
                   state:done.answer ? @"done" : @"failed" body:done.json];
    @synchronized (self) {
        _latest[done.subjectID] = done;
        if (done.answer && done.usage.uncached > 0) [_costs insertObject:@(done.usage.uncached) atIndex:0];
    }
    if (!done.answer && error) *error = done.error;
    return done;
}

- (void)prepare:(NSString *)subjectID snapshot:(MMSnapshot *)s
           done:(void (^)(MMInvestigateSubject *, MMInvestigateEstimate *))done {
    dispatch_async(_prepare, ^{
        MMInvestigateSubject *x = [MMInvestigateSubject named:subjectID snapshot:s cwd:nil];
        MMInvestigateEstimate *e = [self estimate];
        dispatch_async(dispatch_get_main_queue(), ^{ done(x, e); });
    });
}

- (NSString *)costText:(MMInvestigateSubject *)x estimate:(MMInvestigateEstimate *)e {
    NSMutableArray *shown = [NSMutableArray new];
    for (NSString *f in x.folders) [shown addObject:Tilde(f)];
    return [NSString stringWithFormat:@"%@ It reads only %@, with Read, Grep and Glob.", e.sentence ?: @"", [shown componentsJoinedByString:@" and "]];
}

- (void)ask:(NSString *)subjectID snapshot:(MMSnapshot *)s
    confirm:(NSString *(^)(NSString *, NSString *, NSString *))confirm failed:(void (^)(NSString *))failed {
    [self prepare:subjectID snapshot:s done:^(MMInvestigateSubject *x, MMInvestigateEstimate *e) {
        if (!x) { if (failed) failed(@"it has no folder to look in"); return; }
        NSMutableString *text = [[self costText:x estimate:e] mutableCopy];
        MMInvestigation *last = [self latestFor:x.subjectID];
        if (last.answer) {
            NSString *a = last.answer.length > 600 ? [[last.answer substringToIndex:599] stringByAppendingString:@"…"] : last.answer;
            [text appendFormat:@"\n\nThe last answer: %@", a];
        }
        NSString *title = x.title.length > 60 ? [[x.title substringToIndex:59] stringByAppendingString:@"…"] : x.title;
        NSString *q = confirm ? confirm([NSString stringWithFormat:@"Investigate %@?", title ?: @"this"], text, x.question) : nil;
        if (!q) return;
        [self start:x question:q.length ? q : nil done:^(MMInvestigation *run, NSString *error) {
            if (!run.answer && failed) failed(error ?: run.error);
        }];
    }];
}

- (void)start:(MMInvestigateSubject *)subject question:(NSString *)question done:(void (^)(MMInvestigation *, NSString *))done {
    // The run is marked as running before it queues, so a second ask for the same subject while one waits or runs
    // is refused at once and the card dims its action, and no subject is paid for twice.
    MMInvestigation *reserved = subject.folders.count ? [self reserve:subject question:question] : nil;
    if (!reserved) {
        NSString *e = subject.folders.count ? @"an investigation of this already runs" : @"there is no folder to look in";
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(nil, e); });
        return;
    }
    Rebuild(@"investigate queued");
    dispatch_async(_queue, ^{
        NSString *e = nil;
        MMInvestigation *r = [self runReserved:reserved subject:subject error:&e];
        Rebuild(@"investigate done");
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(r, e); });
    });
}

@end

#pragma mark - The tool server

static const NSUInteger kMaxReadBytes = 512 * 1024;       // a file past this is read only to here
static const NSUInteger kMaxOutput = 100 * 1024;          // what one call hands the model
static const NSUInteger kMaxWalk = 50000;                 // entries one Grep or Glob walks
static const NSUInteger kMaxFileForGrep = 1024 * 1024;

/// Files that hold secrets by their name. Read refuses them and Grep skips them.
static BOOL SecretName(NSString *name) {
    NSString *n = name.lowercaseString;
    if ([n hasPrefix:@".env"]) return !([n hasSuffix:@".example"] || [n hasSuffix:@".sample"] || [n hasSuffix:@".template"]);
    for (NSString *x in @[@".pem", @".key", @".p12", @".pfx", @".keychain"]) if ([n hasSuffix:x]) return YES;
    for (NSString *x in @[@"id_rsa", @"id_dsa", @"id_ecdsa", @"id_ed25519"]) if ([n hasPrefix:x]) return YES;
    return [@[@".netrc", @".npmrc", @".pypirc", @"credentials", @"credentials.json", @".git-credentials"] containsObject:n];
}

static BOOL Binary(NSData *d) {
    return memchr(d.bytes, 0, MIN(d.length, (NSUInteger)8192)) != NULL;
}

/// Hard links. A file with more than one link is one file under several names, and a name inside the folders may be
/// the same file as a name outside them, such as a key linked in with ln. F_GETPATH names only one of the names, and
/// macOS keeps no list of the others, so the only way to know that every name lies inside is to find them all there.
/// One walk per tool call counts the names inside the folders of each file with more than one link. A file whose
/// link count is higher than the names found inside has a name outside, and is refused. The walk does not skip .git
/// or node_modules. When it stops at its limit it cannot count, and every file with more than one link is refused.
@interface MMInvestigateLinks : NSObject
- (instancetype)initWithFolders:(NSArray<NSString *> *)folders;
/// YES when every one of the st_nlink names of this file lies inside the folders.
- (BOOL)allInside:(const struct stat *)st;
@end
@implementation MMInvestigateLinks {
    NSArray<NSString *> *_folders;
    NSMutableDictionary<NSString *, NSNumber *> *_names;   // "dev:ino" of each file with more than one link
    BOOL _complete;
}
- (instancetype)initWithFolders:(NSArray<NSString *> *)folders { if ((self = [super init])) _folders = [folders copy]; return self; }
- (void)count {
    _names = [NSMutableDictionary new];
    _complete = YES;
    NSUInteger seen = 0;
    for (NSString *f in _folders) {
        char *roots[] = {(char *)f.fileSystemRepresentation, NULL};
        FTS *fts = fts_open(roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
        if (!fts) { _complete = NO; continue; }
        FTSENT *e;
        while ((e = fts_read(fts))) {
            if (++seen > kMaxWalk * 4) { _complete = NO; break; }
            if (e->fts_info != FTS_F || e->fts_statp->st_nlink < 2) continue;
            NSString *k = [NSString stringWithFormat:@"%d:%llu", e->fts_statp->st_dev, (unsigned long long)e->fts_statp->st_ino];
            _names[k] = @(_names[k].integerValue + 1);
        }
        fts_close(fts);
    }
}
- (BOOL)allInside:(const struct stat *)st {
    if (st->st_nlink < 2) return YES;
    if (!_names) [self count];
    if (!_complete) return NO;
    NSString *k = [NSString stringWithFormat:@"%d:%llu", st->st_dev, (unsigned long long)st->st_ino];
    return _names[k].integerValue >= (NSInteger)st->st_nlink;
}
@end

/// Opens a real path for reading and checks the file it got, so a swap after the check cannot lead out.
/// A file with more than one hard link is read only when links finds every one of its names inside the folders.
static NSData *ReadScoped(NSArray *folders, MMInvestigateLinks *links, NSString *real, NSUInteger max, NSString **reason) {
    // O_NONBLOCK, so a named pipe or a device in the folder never holds the tool server. A regular file reads as before.
    int fd = open(real.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) { *reason = [NSString stringWithFormat:@"%@ could not be opened", Tilde(real)]; return nil; }
    struct stat st;
    char got[PATH_MAX];
    BOOL ok = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && fcntl(fd, F_GETPATH, got) == 0;
    if (ok) { ok = NO; for (NSString *f in folders) if (Inside(@(got), f)) ok = YES; }
    if (!ok) { close(fd); *reason = [NSString stringWithFormat:@"%@ is not a file inside the folders", Tilde(real)]; return nil; }
    if (![links allInside:&st]) {
        close(fd);
        *reason = [NSString stringWithFormat:@"%@ has a hard link outside the folders, so it is not read", Tilde(real)];
        return nil;
    }
    NSMutableData *d = [NSMutableData dataWithLength:MIN((NSUInteger)st.st_size, max)];
    ssize_t n = d.length ? read(fd, d.mutableBytes, d.length) : 0;
    close(fd);
    if (n < 0) { *reason = @"the file could not be read"; return nil; }
    d.length = (NSUInteger)n;
    return d;
}

/// A glob as a regular expression on a path relative to the walk's base. ** crosses folders and * does not.
static NSRegularExpression *GlobRegex(NSString *glob) {
    NSMutableString *r = [NSMutableString stringWithString:@"^"];
    NSUInteger i = 0, n = glob.length;
    BOOL brace = NO;
    while (i < n) {
        unichar c = [glob characterAtIndex:i];
        if (c == '*' && i + 1 < n && [glob characterAtIndex:i + 1] == '*') {
            BOOL slash = i + 2 < n && [glob characterAtIndex:i + 2] == '/';
            [r appendString:slash ? @"(?:.*/)?" : @".*"]; i += slash ? 3 : 2; continue;
        }
        if (c == '*') [r appendString:@"[^/]*"];
        else if (c == '?') [r appendString:@"[^/]"];
        else if (c == '{') { [r appendString:@"(?:"]; brace = YES; }
        else if (c == '}' && brace) { [r appendString:@")"]; brace = NO; }
        else if (c == ',' && brace) [r appendString:@"|"];
        else [r appendString:[NSRegularExpression escapedPatternForString:[NSString stringWithCharacters:&c length:1]]];
        i++;
    }
    [r appendString:@"$"];
    return [NSRegularExpression regularExpressionWithPattern:r options:0 error:nil];
}

static BOOL Matches(NSRegularExpression *re, NSString *s) {
    return re && [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)] != nil;
}

/// Walks base without following any symlink, and calls visit with each regular file's real path and its path
/// relative to base. Skips .git and node_modules. Returns NO when it stopped at kMaxWalk.
static BOOL Walk(NSString *base, BOOL (^visit)(NSString *path, NSString *rel, off_t size)) {
    char *roots[] = {(char *)base.fileSystemRepresentation, NULL};
    FTS *fts = fts_open(roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return YES;
    NSUInteger seen = 0;
    BOOL whole = YES;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (++seen > kMaxWalk) { whole = NO; break; }
        if (e->fts_info == FTS_D && e->fts_level > 0 && (!strcmp(e->fts_name, ".git") || !strcmp(e->fts_name, "node_modules"))) {
            fts_set(fts, e, FTS_SKIP); continue;
        }
        if (e->fts_info != FTS_F) continue;   // a symlink is FTS_SL under FTS_PHYSICAL, and is never read
        NSString *p = @(e->fts_path);
        NSString *rel = p.length > base.length ? [p substringFromIndex:base.length + 1] : p.lastPathComponent;
        if (!visit(p, rel, e->fts_statp->st_size)) break;
    }
    fts_close(fts);
    return whole;
}

static NSDictionary *Schema(NSDictionary *props, NSArray *required) {
    return @{@"type": @"object", @"properties": props, @"required": required ?: @[], @"additionalProperties": @NO};
}

static NSArray *ToolList(void) {
    return @[
        @{@"name": @"Read", @"description": @"Reads one text file inside the folders of this investigation, with line numbers. "
                                            @"offset is the first line, from 1, and limit the number of lines, 2000 at most.",
          @"inputSchema": Schema(@{@"file_path": @{@"type": @"string"}, @"offset": @{@"type": @"integer"}, @"limit": @{@"type": @"integer"}}, @[@"file_path"])},
        @{@"name": @"Grep", @"description": @"Searches the files inside the folders for a regular expression. path narrows it to one "
                                            @"folder or file, and glob to file names such as *.ts. Prints path:line: text.",
          @"inputSchema": Schema(@{@"pattern": @{@"type": @"string"}, @"path": @{@"type": @"string"}, @"glob": @{@"type": @"string"},
                                   @"case_insensitive": @{@"type": @"boolean"}}, @[@"pattern"])},
        @{@"name": @"Glob", @"description": @"Lists the files inside the folders whose path matches a glob such as **/*.json. "
                                            @"path is the folder to start from.",
          @"inputSchema": Schema(@{@"pattern": @{@"type": @"string"}, @"path": @{@"type": @"string"}}, @[@"pattern"])},
    ];
}

/// One tool call. Returns the text for the model, or nil with *refused.
static NSString *CallTool(NSArray *folders, NSString *name, NSDictionary *args, NSString **subject, NSString **refused) {
    NSString *reason = nil;
    MMInvestigateLinks *links = [[MMInvestigateLinks alloc] initWithFolders:folders];   // walks only when a file has two links
    if ([name isEqualToString:@"Read"]) {
        NSString *path = Str(args[@"file_path"]);
        *subject = path;
        if (!path.length) { *refused = @"file_path is missing"; return nil; }
        NSString *real = MMInvestigateScoped(folders, path, &reason);
        if (!real) { *refused = reason; return nil; }
        if (SecretName(real.lastPathComponent)) { *refused = [NSString stringWithFormat:@"%@ may hold secrets and is not read", Tilde(real)]; return nil; }
        NSData *d = ReadScoped(folders, links, real, kMaxReadBytes, &reason);
        if (!d) { *refused = reason; return nil; }
        if (Binary(d)) { *refused = [NSString stringWithFormat:@"%@ is not a text file", Tilde(real)]; return nil; }
        NSString *text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        NSInteger offset = MAX(1, [args[@"offset"] integerValue]), limit = [args[@"limit"] integerValue];
        if (limit <= 0 || limit > 2000) limit = 2000;
        NSMutableString *out = [NSMutableString new];
        for (NSInteger i = offset - 1; i < (NSInteger)lines.count && i < offset - 1 + limit; i++) {
            NSString *l = lines[i];
            if (l.length > 2000) l = [l substringToIndex:2000];
            [out appendFormat:@"%6ld\t%@\n", (long)i + 1, MMRedact(l)];
            if (out.length > kMaxOutput) { [out appendString:@"[cut here: the output limit]\n"]; break; }
        }
        if (!out.length) [out appendString:@"[no lines in this range]\n"];
        return out;
    }
    if ([name isEqualToString:@"Grep"] || [name isEqualToString:@"Glob"]) {
        BOOL grep = [name isEqualToString:@"Grep"];
        NSString *pattern = Str(args[@"pattern"]), *path = Str(args[@"path"]), *glob = grep ? Str(args[@"glob"]) : pattern;
        *subject = path ?: pattern;
        if (!pattern.length) { *refused = @"pattern is missing"; return nil; }
        if ([glob hasPrefix:@"/"] || [glob hasPrefix:@"~"] || [glob.pathComponents containsObject:@".."]) {
            *refused = @"a glob must be relative and stay inside the folder"; return nil;
        }
        NSArray *bases = folders;
        if (path.length) {
            NSString *real = MMInvestigateScoped(folders, path, &reason);
            if (!real) { *refused = reason; return nil; }
            bases = @[real];
        }
        NSRegularExpression *re = nil, *whole = nil;
        if (grep) {
            NSRegularExpressionOptions o = [args[@"case_insensitive"] boolValue] ? NSRegularExpressionCaseInsensitive : 0;
            re = [NSRegularExpression regularExpressionWithPattern:pattern options:o error:nil];
            // One pass over the whole file first, with ^ and $ at each line, so a file with no match is never split.
            whole = [NSRegularExpression regularExpressionWithPattern:pattern options:o | NSRegularExpressionAnchorsMatchLines error:nil];
            if (!re || !whole) { *refused = @"the pattern is not a valid regular expression"; return nil; }
        }
        NSRegularExpression *g = glob.length ? GlobRegex(glob) : nil;
        BOOL nameOnly = glob.length && ![glob containsString:@"/"];
        NSMutableString *out = [NSMutableString new];
        __block NSUInteger hits = 0, more = 0;
        NSUInteger cap = grep ? 100 : 300;
        BOOL complete = YES;
        for (NSString *base in bases) {
            BOOL dir = NO;
            [NSFileManager.defaultManager fileExistsAtPath:base isDirectory:&dir];
            NSString *walkBase = dir ? base : base.stringByDeletingLastPathComponent;
            complete &= Walk(walkBase, ^BOOL(NSString *p, NSString *rel, off_t size) {
                if (!dir && ![p isEqualToString:base]) return YES;
                if (g && !Matches(g, nameOnly ? rel.lastPathComponent : rel)) return YES;
                if (!grep) {
                    if (hits < cap) [out appendFormat:@"%@\n", Tilde(p)]; else more++;
                    hits++;
                    return YES;
                }
                if (SecretName(p.lastPathComponent) || size > (off_t)kMaxFileForGrep) return YES;
                NSString *why = nil;
                NSData *d = ReadScoped(folders, links, p, kMaxFileForGrep, &why);
                if (!d || Binary(d)) return YES;
                NSString *text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
                if (!text || !Matches(whole, text)) return YES;
                __block NSInteger lineNo = 0;
                [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
                    lineNo++;
                    if (!Matches(re, line)) return;
                    if (hits < cap) {
                        NSString *l = line.length > 300 ? [line substringToIndex:300] : line;
                        [out appendFormat:@"%@:%ld: %@\n", Tilde(p), (long)lineNo, MMRedact(l)];
                    } else more++;
                    hits++;
                }];
                return out.length < kMaxOutput;
            });
        }
        if (!hits) [out appendString:grep ? @"No matches.\n" : @"No files match.\n"];
        if (more) [out appendFormat:@"%lu more not shown.\n", (unsigned long)more];
        if (!complete) [out appendString:@"The walk stopped at its limit, so the list may be short.\n"];
        return out;
    }
    *refused = [NSString stringWithFormat:@"there is no tool named %@", name ?: @"(none)"];
    return nil;
}

static NSString *Line(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingWithoutEscapingSlashes error:nil];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

int MMInvestigateServeTools(NSArray<NSString *> *folders, NSString *audit, MMInvestigateReadLine readLine, MMInvestigateWriteLine write) {
    NSFileHandle *log = nil;
    if (audit.length) {
        [NSFileManager.defaultManager createFileAtPath:audit contents:nil attributes:@{NSFilePosixPermissions: @0600}];
        log = [NSFileHandle fileHandleForWritingAtPath:audit];
        [log seekToEndOfFile];
    }
    NSString *line;
    while ((line = readLine())) {
        @autoreleasepool {
            NSDictionary *m = Dict([NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data options:0 error:nil]);
            if (!m) continue;
            id rid = m[@"id"];
            NSString *method = Str(m[@"method"]);
            if (!rid || rid == NSNull.null) continue;   // a notification, such as notifications/initialized
            NSDictionary *params = Dict(m[@"params"]) ?: @{};
            id result = nil;
            if ([method isEqualToString:@"initialize"]) {
                result = @{@"protocolVersion": Str(params[@"protocolVersion"]) ?: @"2025-06-18", @"capabilities": @{@"tools": @{}},
                           @"serverInfo": @{@"name": @"minmacs", @"version": @"2.0"}};
            } else if ([method isEqualToString:@"ping"]) {
                result = @{};
            } else if ([method isEqualToString:@"tools/list"]) {
                result = @{@"tools": ToolList()};
            } else if ([method isEqualToString:@"tools/call"]) {
                NSString *subject = nil, *refused = nil;
                NSString *text = CallTool(folders, Str(params[@"name"]), Dict(params[@"arguments"]) ?: @{}, &subject, &refused);
                NSString *body = text ?: [NSString stringWithFormat:@"Refused: %@.", refused];
                result = @{@"content": @[@{@"type": @"text", @"text": body}], @"isError": text ? @NO : @YES};
                NSMutableDictionary *a = [@{@"tool": Str(params[@"name"]) ?: @"", @"bytes": @(text ? [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] : 0)} mutableCopy];
                if (subject) a[@"path"] = Tilde(subject);
                if (refused) a[@"refused"] = MMRedact(Tilde(refused)) ?: @"";
                [log writeData:[[Line(a) stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            }
            if (result) write(Line(@{@"jsonrpc": @"2.0", @"id": rid, @"result": result}));
            else write(Line(@{@"jsonrpc": @"2.0", @"id": rid, @"error": @{@"code": @(-32601), @"message": @"method not found"}}));
        }
    }
    [log closeFile];
    return 0;
}
