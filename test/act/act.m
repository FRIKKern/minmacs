// The Act checks, issue #18. test/act.sh builds this with Sources/Core/Act and the doubles, then runs it.
// Usage: acttest <fixture binary> <fixture dir>
// Every process, file and repo it acts on is a fixture it or act.sh made inside $MINMACS_HOME.
// It prints one line per check, CHECK<tab>name<tab>want<tab>got, and act.sh hands each to check.
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import "doubles.h"
#import "Core/Store/MMStore.h"

extern char **environ;
NSString *MMStopWhyNot(MMProcKey key);

static void T(NSString *name, id want, id got) {
    printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, [want description].UTF8String ?: "", [got description].UTF8String ?: "(nil)");
    fflush(stdout);
}
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }
static NSString *Or(NSString *s) { return s ?: @"nil"; }
static NSString *Pre(NSString *s, NSUInteger n) { return s.length > n ? [s substringToIndex:n] : Or(s); }

/// Runs block on a background queue and waits. dispatch_sync from main would run it on main.
static void OffMain(void (^block)(void)) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_queue_create("no.guerrilla.minmacs.acttest.run", DISPATCH_QUEUE_SERIAL), ^{ block(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

static NSString *gFixture, *gDir, *gExpert = @"acttest";
static NSMutableArray<NSValue *> *gStarted;    // keys of the processes this test started; it stops these and nothing else

#pragma mark - Fixture processes

static MMProcKey KeyOf(pid_t pid) {
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    MMProcKey k = { pid, 0 };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len) k.startSec = (uint64_t)kp.kp_proc.p_starttime.tv_sec;
    return k;
}
static NSValue *V(MMProcKey k) { return [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]; }
static MMProcKey Spawn(NSString *mode, int seconds) {
    pid_t pid = 0;
    char secs[16]; snprintf(secs, sizeof secs, "%d", seconds);
    char *argv[] = { (char *)gFixture.fileSystemRepresentation, (char *)mode.UTF8String, secs, NULL };
    if (posix_spawn(&pid, gFixture.fileSystemRepresentation, NULL, NULL, argv, environ) != 0) return (MMProcKey){0, 0};
    usleep(100000);
    MMProcKey k = KeyOf(pid);
    [gStarted addObject:V(k)];
    return k;
}
static void Reap(void) { int st; while (waitpid(-1, &st, WNOHANG) > 0) {} }
static BOOL Running(MMProcKey k) { Reap(); return MMProcAlive(k); }
static void WaitGone(MMProcKey k, double secs) {
    for (int i = 0; i < secs * 20 && Running(k); i++) usleep(50000);
}

#pragma mark - Files and git

static NSString *Path(NSString *name) { return [gDir stringByAppendingPathComponent:name]; }
static void Write(NSString *path, NSString *text) { [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
static BOOL Exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }
static double MTime(NSString *path) {
    return [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate timeIntervalSince1970];
}
static int Git(NSString *dir, NSArray *args, NSString **out) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    t.arguments = [@[@"-C", dir] arrayByAddingObjectsFromArray:args];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p; t.standardError = p;
    if (![t launchAndReturnError:nil]) return -1;
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (out) *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return t.terminationStatus;
}

#pragma mark - Findings, reviews and the test policy

static MMFinding *Finding(NSString *kind, NSString *key) {
    MMFinding *f = [MMFinding new];
    f.expert = gExpert; f.kind = kind; f.stableKey = key;
    f.findingID = [NSString stringWithFormat:@"%@:%@:%@", gExpert, kind, key];
    f.title = key; f.fingerprint = @"fp1"; f.keepReasons = @[]; f.facts = @{};
    f.proposal = [MMProposal verb:@"remove" title:@"Remove" reversibility:MMReversibleTrash];
    return f;
}
static MMFinding *ProcFinding(MMProcKey k) {
    MMFinding *f = Finding(@"proc", [NSString stringWithFormat:@"fixture-%d", k.pid]);
    f.procs = @[V(k)];
    f.proposal = [MMProposal verb:@"stop" title:@"Stop" reversibility:MMReversibleRestart];
    return f;
}
static MMFinding *FileFinding(NSString *path) {
    MMFinding *f = Finding(@"file", path.lastPathComponent);
    f.path = path;
    f.facts = @{@"mtime": @(MTime(path))};
    return f;
}
static MMFinding *TreeFinding(NSString *path) {
    MMFinding *f = Finding(@"worktree", path.lastPathComponent);
    f.path = path;
    f.proposal = [MMProposal verb:@"remove" title:@"Remove" reversibility:MMReversibleBundle];
    return f;
}
static MMVerdict *Verdict(MMFinding *f, MMVerdictKind kind, double confidence) {
    MMVerdict *v = [MMVerdict new];
    v.kind = kind; v.confidence = confidence; v.findingID = f.findingID; v.fingerprint = f.fingerprint; v.reason = @"quiet for days";
    return v;
}
static MMReview *Review(NSArray<MMVerdict *> *verdicts) {
    MMReview *r = [MMReview new];
    r.expert = gExpert; r.at = NSDate.date;
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (MMVerdict *v in verdicts) d[v.findingID] = v;
    r.verdicts = d;
    return r;
}

/// The graph double reads each fixture again, as -[MMGraph freshFactsFor:] does.
static MMFacts *Gather(MMFinding *f) {
    if ([f.facts[@"unverifiable"] boolValue]) return nil;
    NSMutableDictionary *v = [NSMutableDictionary new];
    if ([f.kind isEqualToString:@"proc"]) {
        MMProcKey k; [f.procs.firstObject getValue:&k size:sizeof k];
        v[@"alive"] = @(Running(k));
        v[@"busy"] = @(Exists(Path([NSString stringWithFormat:@"busy-%d", k.pid])));
    } else if ([f.kind isEqualToString:@"file"]) {
        v[@"exists"] = @(Exists(f.path));
        v[@"mtime"] = @(MTime(f.path));
    } else if ([f.kind isEqualToString:@"worktree"]) {
        NSString *out = nil;
        int st = Git(f.path, @[@"status", @"--porcelain"], &out);
        v[@"dirty"] = @(st != 0 ? -1 : (NSInteger)(out.length ? [out componentsSeparatedByString:@"\n"].count : 0));
    }
    MMFacts *facts = [MMFacts new];
    facts.values = v;
    return facts;
}

@interface MMTestPolicy : NSObject <MMExpertPolicy>
@end
@implementation MMTestPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    NSDictionary *v = facts.values;
    if ([f.kind isEqualToString:@"proc"]) {
        if (![v[@"alive"] boolValue]) return @"cannot verify: the process is gone";
        if ([v[@"busy"] boolValue]) return @"an agent works here";
    } else if ([f.kind isEqualToString:@"file"]) {
        if (![v[@"exists"] boolValue]) return @"cannot verify: the file is gone";
        if ([v[@"mtime"] doubleValue] > [f.facts[@"mtime"] doubleValue]) return @"changed since it was found";
    } else if ([f.kind isEqualToString:@"worktree"]) {
        NSInteger d = [v[@"dirty"] integerValue];
        if (d < 0) return @"cannot verify: git status failed";
        if (d > 0) return [NSString stringWithFormat:@"%ld change%@ not committed", (long)d, d == 1 ? @"" : @"s"];
    }
    return nil;
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r {
    NSNumber *work = f.facts[@"lastWork"];
    return work && work.doubleValue > r.at.timeIntervalSince1970 ? @"worked on after the last review" : nil;
}
- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r {
    return m == MMModeProactive && [f.facts[@"young"] boolValue] ? @"Proactive waits 7 quiet days" : nil;
}
@end

#pragma mark - Test actions

@interface MMTestAction : NSObject <MMAction>
@property MMFinding *finding;
@property (copy) NSString *kind;
@property (copy) NSString *(^check)(void);
@property (copy) BOOL (^work)(MMUndoRecord *r, NSString **error);
@end
@implementation MMTestAction
- (NSString *)recheck { return self.check ? self.check() : nil; }
- (NSString *)dryRun { return @"would act on the fixture"; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error { return self.work(record, error); }
@end
static MMTestAction *Action(MMFinding *f, NSString *kind, BOOL (^work)(MMUndoRecord *, NSString **)) {
    MMTestAction *a = [MMTestAction new];
    a.finding = f; a.kind = kind; a.work = work;
    return a;
}

@interface MMFakeNotifier : NSObject <MMNotifier>
@property NSMutableArray<NSDictionary *> *posts;
@end
@implementation MMFakeNotifier
- (void)post:(NSString *)title body:(NSString *)body undoRid:(NSString *)undoRid passive:(BOOL)passive expert:(NSString *)expert {
    [self.posts addObject:@{@"title": title ?: @"", @"body": body ?: @"", @"rid": undoRid ?: @"", @"passive": @(passive), @"expert": expert ?: @""}];
}
@end

static NSUInteger RecordCount(void) { return [MMUndo.shared recent:gExpert limit:0].count; }
static void SetSince(double ago) {
    Write([MMSupportDir() stringByAppendingPathComponent:@"watching-since"], [NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970 - ago]);
}

#pragma mark - Sections

static void Modes(void) {
    for (NSString *e in @[@"minmacs", @"locohost", @"workforest", @"noonoo", @"insomnia"])
        T([NSString stringWithFormat:@"%@ starts in Proactive", e], @"proactive", MMModeName(MMModeFor(e)));
    MMSetMode(gExpert, MMModeEager);
    T(@"a mode set is the mode read", @"eager", MMModeName(MMModeFor(gExpert)));
    MMSetMode(gExpert, MMModeIdle);
    T(@"Idle reads back", @"idle", MMModeName(MMModeFor(gExpert)));
    T(@"mode names parse in any case", @"2", @(MMModeFrom(@"Eager")).stringValue);
    T(@"an unknown mode name is -1", @"-1", @(MMModeFrom(@"lazy")).stringValue);
    MMSetMode(gExpert, MMModeProactive);

    T(@"before the first launch no mode may act", @"no", YN(MMWatchedLongEnough(gExpert)));
    T(@"before the first launch a whole day is left", @"86400", @((NSInteger)MMWatchingLeft(gExpert)).stringValue);
    MMStartWatching();
    T(@"the first launch starts the day of watching", @"yes", YN(Exists([MMSupportDir() stringByAppendingPathComponent:@"watching-since"])));
    T(@"right after it no mode may act", @"no", YN(MMWatchedLongEnough(gExpert)));
    SetSince(25 * 3600);
    MMStartWatching();
    T(@"a later launch does not restart the day", @"yes", YN(MMWatchedLongEnough(gExpert)));
    T(@"after a day nothing is left to wait", @"0", @((NSInteger)MMWatchingLeft(gExpert)).stringValue);
}

static void MustKeep(void) {
    MMTestPolicy *p = [MMTestPolicy new];
    MMProcKey k = Spawn(@"plain", 30);
    MMFinding *pf = ProcFinding(k);
    T(@"MustKeep: no finding cannot be verified", @"cannot verify: there is no finding", Or(MMMustKeep(nil, Gather(pf), nil, p)));
    T(@"MustKeep: no policy cannot be verified", @"cannot verify: the expert has no rules", Or(MMMustKeep(pf, Gather(pf), nil, nil)));
    MMFinding *uf = ProcFinding(k); uf.facts = @{@"unverifiable": @YES};
    T(@"MustKeep: no fresh facts cannot be verified", @"cannot verify: fresh facts could not be gathered", Or(MMMustKeep(uf, Gather(uf), nil, p)));
    T(@"MustKeep: a live fixture process is free", @"nil", Or(MMMustKeep(pf, Gather(pf), nil, p)));
    Write(Path([NSString stringWithFormat:@"busy-%d", k.pid]), @"x");
    T(@"MustKeep: a work keep on fresh facts", @"an agent works here", Or(MMMustKeep(pf, Gather(pf), nil, p)));
    kill(k.pid, SIGTERM); WaitGone(k, 3);
    T(@"MustKeep: a process gone since the snapshot is kept", @"cannot verify: the process is gone", Or(MMMustKeep(pf, Gather(pf), nil, p)));

    NSString *file = Path(@"keep-file.txt");
    Write(file, @"one");
    MMFinding *ff = FileFinding(file);
    T(@"MustKeep: an unchanged fixture file is free", @"nil", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:5]} ofItemAtPath:file error:nil];
    T(@"MustKeep: a file changed after the snapshot is kept", @"changed since it was found", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    ff = FileFinding(file);
    ff.keepReasons = @[@"3 uncommitted files"];
    T(@"MustKeep: a snapshot keep reason holds", @"3 uncommitted files", Or(MMMustKeep(ff, Gather(ff), nil, p)));

    NSString *wt = NSProcessInfo.processInfo.environment[@"ACT_WORKTREE"];
    MMFinding *tf = TreeFinding(wt);
    T(@"MustKeep: a clean fixture worktree is free", @"nil", Or(MMMustKeep(tf, Gather(tf), nil, p)));
    Write([wt stringByAppendingPathComponent:@"new.txt"], @"work");
    T(@"MustKeep: an untracked file in the worktree keeps it", @"1 change not committed", Or(MMMustKeep(tf, Gather(tf), nil, p)));
    [NSFileManager.defaultManager removeItemAtPath:[wt stringByAppendingPathComponent:@"new.txt"] error:nil];
    MMFinding *gone = TreeFinding(Path(@"no-such-worktree"));
    T(@"MustKeep: a worktree git cannot read is kept", @"cannot verify: git status failed", Or(MMMustKeep(gone, Gather(gone), nil, p)));

    ff = FileFinding(file);
    MMReview *r = Review(@[Verdict(ff, MMVerdictGo, 0.9)]);
    T(@"MustKeep: a fresh review that covers it lets it go", @"nil", Or(MMMustKeep(ff, Gather(ff), r, p)));
    r.expert = @"other";
    T(@"MustKeep: a review of another expert keeps", @"the review is for another expert", Or(MMMustKeep(ff, Gather(ff), r, p)));
    r.expert = gExpert; r.error = @"usage limit";
    T(@"MustKeep: a failed review keeps", @"the last review failed", Or(MMMustKeep(ff, Gather(ff), r, p)));
    r.error = nil; r.at = [NSDate dateWithTimeIntervalSinceNow:-7 * 3600];
    T(@"MustKeep: an old review keeps", @"the last review is 7 hours old", Or(MMMustKeep(ff, Gather(ff), r, p)));
    r.at = NSDate.date; r.verdicts = @{};
    T(@"MustKeep: a finding not in the review is kept", @"not in the last review", Or(MMMustKeep(ff, Gather(ff), r, p)));
    r = Review(@[Verdict(ff, MMVerdictGo, 0.9)]);
    ff.fingerprint = @"fp2";
    T(@"MustKeep: a finding that moved since the review is kept", @"changed since the last review", Or(MMMustKeep(ff, Gather(ff), r, p)));
    ff.fingerprint = @"fp1";
    ff.facts = @{@"mtime": ff.facts[@"mtime"], @"lastWork": @(NSDate.date.timeIntervalSince1970 + 60)};
    T(@"MustKeep: the expert's review keep holds", @"worked on after the last review", Or(MMMustKeep(ff, Gather(ff), r, p)));

    ff = FileFinding(file);
    [MMKeep keep:ff.stableKey expert:gExpert until:[NSDate dateWithTimeIntervalSinceNow:7 * 86400 + 60]];
    T(@"MustKeep: a timed keep holds by stable key", @"kept by you for 7 days more", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    MMFinding *again = FileFinding(file); again.instanceKey = @"another-instance";
    T(@"MustKeep: the timed keep survives a new instance", @"yes", YN([Or(MMMustKeep(again, Gather(again), nil, p)) hasPrefix:@"kept by you"]));
    [MMKeep keep:ff.stableKey expert:gExpert until:nil];
    T(@"MustKeep: an ended keep no longer holds", @"nil", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    [MMKeep keep:ff.stableKey expert:gExpert until:[NSDate dateWithTimeIntervalSinceNow:-1]];
    T(@"MustKeep: a passed keep no longer holds", @"nil", Or(MMMustKeep(ff, Gather(ff), nil, p)));

    NSString *rules = [MMExpertDir(gExpert) stringByAppendingPathComponent:@"rules.json"];
    for (NSString *entry in @[ff.stableKey, [gDir stringByAppendingString:@"/*"], @"*keep-fi*"]) {
        Write(rules, [NSString stringWithFormat:@"{\"protect\": [\"%@\"]}", entry]);
        T([NSString stringWithFormat:@"MustKeep: the protect entry %@ holds", [entry hasPrefix:@"/"] ? @"<dir>/*" : entry], @"protected", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    }
    Write(rules, @"{\"protect\": [\"other*\"]}");
    T(@"MustKeep: a protect entry that does not match lets go", @"nil", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    Write([MMExpertDir(@"core") stringByAppendingPathComponent:@"rules.json"], @"{\"protect\": [\"*keep-file*\"]}");
    T(@"MustKeep: the shared protect list holds for every expert", @"protected", Or(MMMustKeep(ff, Gather(ff), nil, p)));
    Write([MMExpertDir(@"core") stringByAppendingPathComponent:@"rules.json"], @"{\"protect\": []}");
}

static void Plans(void) {
    MMTestPolicy *p = [MMTestPolicy new];
    NSString *file = Path(@"plan-file.txt");
    Write(file, @"plan");
    MMFinding *f = FileFinding(file);
    MMFacts *facts = Gather(f);
    MMPlanEntry *(^one)(MMFinding *, MMReview *, MMMode) = ^(MMFinding *x, MMReview *r, MMMode m) {
        return MMPlan(@[x], facts, r, m, p).firstObject;
    };
    MMReview *sure = Review(@[Verdict(f, MMVerdictGo, 0.9)]);
    MMPlanEntry *e = one(f, sure, MMModeIdle);
    T(@"plan: Idle acts on nothing", @"no Idle mode only reports", [NSString stringWithFormat:@"%@ %@", YN(e.act), e.why]);
    T(@"plan: Proactive acts on a sure go", @"yes", YN(one(f, sure, MMModeProactive).act));
    MMReview *maybe = Review(@[Verdict(f, MMVerdictGo, 0.7)]);
    T(@"plan: Proactive keeps a go under 80%", @"no", YN(one(f, maybe, MMModeProactive).act));
    T(@"plan: Eager acts on a go of 70%", @"yes", YN(one(f, maybe, MMModeEager).act));
    MMReview *judged = Review(@[Verdict(f, MMVerdictGo, 0.5)]);
    judged.verdicts[f.findingID].judged = YES;
    T(@"plan: Eager acts on what the judge let go", @"yes", YN(one(f, judged, MMModeEager).act));
    T(@"plan: Eager keeps a go of 50% the judge did not make", @"no", YN(one(f, Review(@[Verdict(f, MMVerdictGo, 0.5)]), MMModeEager).act));
    MMReview *ev = Review(@[Verdict(f, MMVerdictGo, 0.95)]);
    ev.verdicts[f.findingID].keepEvidence = @"a PR is open";
    T(@"plan: keep evidence holds in Eager", @"evidence: a PR is open", one(f, ev, MMModeEager).why);
    T(@"plan: a keep verdict holds in Eager", @"no", YN(one(f, Review(@[Verdict(f, MMVerdictKeep, 0.9)]), MMModeEager).act));
    T(@"plan: no review, no action", @"no review yet", one(f, nil, MMModeEager).why);
    NSString *wt = NSProcessInfo.processInfo.environment[@"ACT_WORKTREE"];
    MMFinding *tf = TreeFinding(wt);
    MMReview *tr = Review(@[Verdict(tf, MMVerdictGo, 0.95)]);
    MMPlanEntry *te = MMPlan(@[tf], Gather(tf), tr, MMModeProactive, p).firstObject;
    T(@"plan: decision 7, Proactive keeps commits on no remote", @"no", YN(te.act));
    T(@"plan: decision 7, Eager may act on them", @"yes", YN(MMPlan(@[tf], Gather(tf), tr, MMModeEager, p).firstObject.act));
    MMFinding *force = FileFinding(file);
    force.proposal = [MMProposal verb:@"stop" title:@"Force Stop" reversibility:MMReversibleRestart];
    force.proposal.needsForce = YES;
    T(@"plan: a mode never makes a second request", @"no", YN(one(force, Review(@[Verdict(force, MMVerdictGo, 1)]), MMModeEager).act));
    MMFinding *young = FileFinding(file); young.facts = @{@"mtime": f.facts[@"mtime"], @"young": @YES};
    T(@"plan: the expert's mode rule holds", @"Proactive waits 7 quiet days", one(young, sure, MMModeProactive).why);
    T(@"plan: the expert's mode rule is only for its mode", @"yes", YN(one(young, sure, MMModeEager).act));
    MMFinding *none = FileFinding(file); none.proposal = nil;
    T(@"plan: a finding with no proposal is left alone", @"nothing to do", one(none, sure, MMModeEager).why);
    MMFinding *kept = FileFinding(file); kept.keepReasons = @[@"an agent works here"];
    T(@"plan: MustKeep comes before the mode", @"an agent works here", one(kept, sure, MMModeEager).why);
    SetSince(3600);
    e = one(f, sure, MMModeEager);
    T(@"plan: nothing acts during the day of watching", @"no", YN(e.act));
    T(@"plan: the day of watching says what it would do", @"would act", Pre(e.why, 9));
    SetSince(25 * 3600);
}

static void Runs(void) {
    MMTestPolicy *p = [MMTestPolicy new];
    MMGraph.shared.gather = ^MMFacts *(MMFinding *f) { return Gather(f); };
    NSString *file = Path(@"run-file.txt");
    Write(file, @"run");
    MMFinding *f = FileFinding(file);
    __block NSString *seen = nil;
    MMTestAction *a = Action(f, @"trash", ^BOOL(MMUndoRecord *r, NSString **error) {
        seen = @([MMUndo.shared record:r.rid].state).stringValue;
        NSError *e = nil;
        if (![MMUndo.shared trash:[NSURL fileURLWithPath:file] record:r error:&e]) { *error = e.localizedDescription; return NO; }
        return YES;
    });

    NSString *mainErr = nil;
    (void)MMRunAction(a, p, nil, @"manual", @"test", &mainErr);
    T(@"run: never on the main thread", @"an action never runs on the main thread", Or(mainErr));
    T(@"run: the file is untouched after a refused run", @"yes", YN(Exists(file)));

    MMUndoRecord *(^run)(id<MMAction>, MMReview *, NSString *, NSString **) = ^(id<MMAction> act, MMReview *r, NSString *by, NSString **err) {
        __block MMUndoRecord *rec = nil; __block NSString *e = nil;
        OffMain(^{ rec = MMRunAction(act, p, r, by, @"test", &e); });
        if (err) *err = e;
        return rec;
    };

    NSString *err = nil;
    a.check = ^NSString *{ return @"the menu row is out of date"; };
    NSUInteger before = RecordCount();
    T(@"run: a failed recheck stops it", @"nil", Or(run(a, nil, @"manual", &err).rid));
    T(@"run: a failed recheck says why", @"cannot run now: the menu row is out of date", Or(err));
    a.check = nil;

    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:5]} ofItemAtPath:file error:nil];
    T(@"run: fresh facts right before acting keep it", @"nil", Or(run(a, nil, @"manual", &err).rid));
    T(@"run: the fresh keep says why", @"kept: changed since it was found", Or(err));
    T(@"run: a kept action writes no undo record", @(before).stringValue, @(RecordCount()).stringValue);
    f = FileFinding(file); a.finding = f;

    MMGraph.shared.gather = nil;
    T(@"run: without fresh facts nothing runs", @"kept: cannot verify: fresh facts could not be gathered",
      (run(a, nil, @"manual", &err), Or(err)));
    MMGraph.shared.gather = ^MMFacts *(MMFinding *x) { return Gather(x); };

    MMSetMode(gExpert, MMModeProactive);
    MMReview *r = Review(@[Verdict(f, MMVerdictGo, 0.9)]);
    run(a, r, @"eager", &err);
    T(@"run: a mode run checks the mode again", @"kept: the mode is now proactive", Or(err));
    run(a, nil, @"proactive", &err);
    T(@"run: a mode run needs a review", @"kept: no review yet", Or(err));
    SetSince(60);
    run(a, r, @"proactive", &err);
    T(@"run: a mode run waits for the day of watching", @"kept: MinMacs watches", Pre(err, 21));
    SetSince(25 * 3600);

    MMUndoRecord *rec = run(a, r, @"proactive", &err);
    T(@"run: the undo record was pending when the action ran", @(MMUndoPending).stringValue, Or(seen));
    T(@"run: the record ends done", @(MMUndoDone).stringValue, @(rec.state).stringValue);
    T(@"run: the record keeps who and why", @"proactive test trash", [NSString stringWithFormat:@"%@ %@ %@", rec.by, rec.why, rec.kind]);
    NSString *inTrash = [rec.payload[@"trashed"] firstObject][@"to"];
    T(@"undo: the file went to the Trash", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(Exists(file)), YN(Exists(inTrash))]);
    T(@"undo: the record can be restored", @"yes", YN(rec.canRestore));
    T(@"undo: restore moves it back from the Trash", @"nil", Or([MMUndo.shared restore:rec.rid]));
    T(@"undo: it is back and the Trash no longer holds it", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(Exists(file)), YN(Exists(inTrash))]);
    T(@"undo: the record is now restored", @(MMUndoRestored).stringValue, @([MMUndo.shared record:rec.rid].state).stringValue);
    T(@"undo: a second restore is refused", @"it was already restored", Or([MMUndo.shared restore:rec.rid]));

    f = FileFinding(file);
    MMTestAction *bad = Action(f, @"trash", ^BOOL(MMUndoRecord *x, NSString **error) { *error = @"the fixture said no"; return NO; });
    rec = run(bad, nil, @"manual", &err);
    T(@"run: a failed action leaves a failed record", @"failed the fixture said no",
      [NSString stringWithFormat:@"%@ %@", rec.state == MMUndoFailed ? @"failed" : @"other", rec.error]);
}

static void Stops(void) {
    MMProcKey one = { 1, KeyOf(1).startSec };
    T(@"stop: pid 1 is never signaled", @"pid 1 is never signaled", Or(MMStopWhyNot(one)));
    T(@"stop: MinMacs never signals itself", @"MinMacs never signals itself", Or(MMStopWhyNot(KeyOf(getpid()))));
    // A root process, found by a read-only sysctl. MMStopWhyNot only reads; nothing is signaled.
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t len = 0; sysctl(mib, 3, NULL, &len, NULL, 0);
    struct kinfo_proc *all = malloc(len); MMProcKey rootKey = { 0, 0 };
    if (sysctl(mib, 3, all, &len, NULL, 0) == 0)
        for (size_t i = 0; i < len / sizeof *all; i++)
            if (all[i].kp_eproc.e_ucred.cr_uid == 0 && all[i].kp_proc.p_pid > 1 && all[i].kp_proc.p_stat != SZOMB) {
                rootKey.pid = all[i].kp_proc.p_pid; rootKey.startSec = (uint64_t)all[i].kp_proc.p_starttime.tv_sec; break;
            }
    free(all);
    T(@"stop: another user's process is never signaled", @"it belongs to another user", Or(MMStopWhyNot(rootKey)));

    MMProcKey k = Spawn(@"plain", 30);
    MMProcKey reused = { k.pid, k.startSec + 1 };
    T(@"stop: a reused pid is refused", @"its pid now belongs to another process", Or(MMStopWhyNot(reused)));
    MMStop(@[V(reused)], MMStopTerm, 0.5);
    T(@"stop: the process behind a reused pid keeps running", @"yes", YN(Running(k)));
    NSArray *left = MMStop(@[V(k)], MMStopKill, 0.5);
    T(@"stop: SIGKILL is never the first request", @"yes 1", [NSString stringWithFormat:@"%@ %lu", YN(Running(k)), (unsigned long)left.count]);
    left = MMStop(@[V(k)], MMStopTerm, 3);
    Reap();
    T(@"stop: SIGTERM stops a fixture", @"no 0", [NSString stringWithFormat:@"%@ %lu", YN(Running(k)), (unsigned long)left.count]);
    T(@"stop: a gone process is not signaled again", @"it has already exited", Or(MMStopWhyNot(k)));

    MMProcKey stubborn = Spawn(@"ignore-term", 30);
    left = MMStop(@[V(stubborn)], MMStopTerm, 1);
    T(@"stop: a fixture that ignores SIGTERM is still running", @"yes 1", [NSString stringWithFormat:@"%@ %lu", YN(Running(stubborn)), (unsigned long)left.count]);
    left = MMStop(@[V(stubborn)], MMStopKill, 3);
    Reap();
    T(@"stop: SIGKILL on the second request stops it", @"no 0", [NSString stringWithFormat:@"%@ %lu", YN(Running(stubborn)), (unsigned long)left.count]);

    MMProcKey plain = Spawn(@"plain", 30);
    left = MMQuitApps(@[V(plain)], MMStopTerm, 0.3);
    T(@"quit: a process that is not an app is not quit", @"yes 1", [NSString stringWithFormat:@"%@ %lu", YN(Running(plain)), (unsigned long)left.count]);
    left = MMQuitApps(@[V(KeyOf(getpid()))], MMStopKill, 0.1);
    T(@"quit: MinMacs never quits itself", @"1", @(left.count).stringValue);

    // A stop action with its restart command, then Undo starts it again.
    MMTestPolicy *p = [MMTestPolicy new];
    MMGraph.shared.gather = ^MMFacts *(MMFinding *x) { return Gather(x); };
    MMFinding *f = ProcFinding(plain);
    MMTestAction *a = Action(f, @"stop", ^BOOL(MMUndoRecord *r, NSString **error) {
        [MMUndo.shared note:r payload:@{@"restart": @{@"command": [NSString stringWithFormat:@"exec '%@' plain 20", gFixture],
                                                       @"cwd": gDir, @"env": @{@"PATH": @"/usr/bin:/bin"}}}];
        if (MMStop(f.procs, MMStopTerm, 3).count) { *error = @"still running"; return NO; }
        return YES;
    });
    a.check = ^NSString *{ return Running(plain) ? nil : @"it has already exited"; };
    __block MMUndoRecord *rec = nil; __block NSString *err = nil;
    OffMain(^{
        rec = MMRunAction(a, p, nil, @"manual", @"test", &err);
    });
    Reap();
    T(@"stop action: the fixture is stopped and the record done", @"no done", [NSString stringWithFormat:@"%@ %@", YN(Running(plain)), rec.state == MMUndoDone ? @"done" : Or(err)]);
    T(@"stop action: undo runs the restart command", @"nil", Or([MMUndo.shared restore:rec.rid]));
    pid_t again = [[MMUndo.shared record:rec.rid].payload[@"restored"][@"restartedPid"] intValue];
    if (again > 0) [gStarted addObject:V(KeyOf(again))];
    usleep(300000);
    T(@"stop action: the restarted fixture runs", @"yes", YN(again > 0 && Running(KeyOf(again))));
    if (again > 0 && Running(KeyOf(again))) { MMStop(@[V(KeyOf(again))], MMStopTerm, 3); Reap(); }
}

static void Bundles(void) {
    NSString *wt = NSProcessInfo.processInfo.environment[@"ACT_WORKTREE"], *repo = NSProcessInfo.processInfo.environment[@"ACT_REPO"];
    NSString *err = nil;
    MMUndoRecord *main = [MMUndo.shared begin:gExpert kind:@"remove" finding:@"x" subject:@"main" why:@"test" by:@"manual" parent:nil payload:nil];
    T(@"bundle: a checkout with every commit on a remote needs none", @"every commit is on a remote, so no bundle is needed",
      ([MMUndo.shared bundle:repo record:main error:&err], Or(err)));
    [MMUndo.shared finish:main ok:NO freed:0 error:@"test"];

    NSString *head = nil; Git(wt, @[@"rev-parse", @"HEAD"], &head);
    MMTestPolicy *p = [MMTestPolicy new];
    MMGraph.shared.gather = ^MMFacts *(MMFinding *x) { return Gather(x); };
    MMFinding *f = TreeFinding(wt);
    MMTestAction *a = Action(f, @"remove", ^BOOL(MMUndoRecord *r, NSString **error) {
        NSString *e = nil;
        if (![MMUndo.shared bundle:wt record:r error:&e]) { *error = e; return NO; }   // no bundle, no removal
        if (![MMUndo.shared recover:@[@".env.local"] from:wt record:r error:&e]) { *error = e; return NO; }
        if (Git(repo, @[@"worktree", @"remove", wt], nil) != 0) { *error = @"git worktree remove refused"; return NO; }
        return YES;
    });
    __block MMUndoRecord *rec = nil; __block NSString *e2 = nil;
    OffMain(^{
        rec = MMRunAction(a, p, nil, @"manual", @"merged and quiet", &e2);
    });
    NSDictionary *b = rec.payload[@"bundle"];
    T(@"bundle: the worktree was removed after its bundle", @"done no", [NSString stringWithFormat:@"%@ %@", rec.state == MMUndoDone ? @"done" : Or(e2), YN(Exists(wt))]);
    T(@"bundle: it holds the one commit on no remote", @"1", [b[@"commits"] description]);
    NSString *heads = nil;
    Git(repo, @[@"bundle", @"list-heads", Or(b[@"path"])], &heads);
    T(@"bundle: git can read it, at the worktree's HEAD", @"yes", YN(head.length && [heads hasPrefix:head]));
    T(@"recovery: the ignored .env.local was saved", @"yes", YN(Exists([rec.payload[@"recovery"][@"dir"] stringByAppendingPathComponent:@".env.local"])));
    // Make the repo forget the commit, so restore must read it back from the bundle. The repo is a fixture.
    Git(repo, @[@"branch", @"-D", Or(b[@"branch"])], nil);
    Git(repo, @[@"reflog", @"expire", @"--expire=now", @"--all"], nil);
    Git(repo, @[@"gc", @"--prune=now", @"--quiet"], nil);
    T(@"bundle: the fixture repo lost the commit", @"no", YN(Git(repo, @[@"cat-file", @"-e", [Or(head) stringByAppendingString:@"^{commit}"]], nil) == 0));
    T(@"bundle: restore recreates the worktree", @"nil", Or([MMUndo.shared restore:rec.rid]));
    NSString *now = nil; Git(wt, @[@"rev-parse", @"HEAD"], &now);
    NSString *branch = nil; Git(wt, @[@"symbolic-ref", @"--short", @"HEAD"], &branch);
    T(@"bundle: it is back at its commit and branch", [NSString stringWithFormat:@"%@ %@", head, b[@"branch"]], [NSString stringWithFormat:@"%@ %@", now, branch]);
    T(@"recovery: .env.local is back", @"secret=1",
      [[NSString stringWithContentsOfFile:[wt stringByAppendingPathComponent:@".env.local"] encoding:NSUTF8StringEncoding error:nil]
          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);

    MMUndoRecord *x = [MMUndo.shared begin:gExpert kind:@"remove" finding:@"x" subject:@"escape" why:@"test" by:@"manual" parent:nil payload:nil];
    [MMUndo.shared recover:@[@"../outside", @"/etc/hosts"] from:wt record:x error:&err];
    T(@"recovery: paths that leave the root are skipped", @"0 2",
      [NSString stringWithFormat:@"%lu %lu", (unsigned long)[[MMUndo.shared record:x.rid].payload[@"recovery"][@"saved"] count],
                                 (unsigned long)[[MMUndo.shared record:x.rid].payload[@"recovery"][@"skipped"] count]]);
    [MMUndo.shared finish:x ok:NO freed:0 error:@"test"];
}

static void Tools(void) {
    NSString *tool = Path(@"tool.sh"), *junk = Path(@"tool-junk");
    Write(tool, [NSString stringWithFormat:@"#!/bin/sh\nif [ \"$1\" = --dry-run ]; then echo \"would remove tool-junk\"; exit 0; fi\n"
                                            "if [ \"$1\" = --fail-dry ]; then echo broken; exit 3; fi\nrm -f '%@'\necho removed\n", junk]);
    chmod(tool.fileSystemRepresentation, 0755);
    Write(junk, @"cache");
    MMToolCommand *c = [MMToolCommand tool:@"fixture-tool" path:tool args:@[@"prune"] dryRunArgs:@[@"--dry-run"] env:@{@"FIXTURE": @"1"}];
    NSString *err = nil;
    T(@"tool: the dry run reports and changes nothing", @"would remove tool-junk yes",
      [NSString stringWithFormat:@"%@ %@", [[c dryRun:&err] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet], YN(Exists(junk))]);
    MMUndoRecord *r = [MMUndo.shared begin:gExpert kind:@"tool" finding:@"t" subject:@"fixture-tool" why:@"test" by:@"manual" parent:nil payload:nil];
    NSString *out = nil;
    BOOL ok = [c runWithRecord:r output:&out error:&err];
    [MMUndo.shared finish:r ok:ok freed:0 error:err];
    MMUndoRecord *done = [MMUndo.shared record:r.rid];
    T(@"tool: the command ran after its dry run", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(ok), YN(Exists(junk))]);
    T(@"tool: the record keeps the dry-run output", @"would remove tool-junk", [done.payload[@"dryRun"] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]);
    T(@"tool: the record keeps the command", [tool stringByAppendingString:@" prune"], Or(done.payload[@"command"]));
    T(@"tool: a tool's cleanup cannot be restored", @"no", YN(done.canRestore));
    T(@"tool: restore says why", @"a tool's own cleanup cannot be undone; its dry-run output is in the record", Or([MMUndo.shared restore:r.rid]));

    Write(junk, @"cache");
    MMToolCommand *failing = [MMToolCommand tool:@"fixture-tool" path:tool args:@[@"prune"] dryRunArgs:@[@"--fail-dry"] env:nil];
    MMUndoRecord *r2 = [MMUndo.shared begin:gExpert kind:@"tool" finding:@"t" subject:@"fixture-tool" why:@"test" by:@"manual" parent:nil payload:nil];
    ok = [failing runWithRecord:r2 output:&out error:&err];
    [MMUndo.shared finish:r2 ok:ok freed:0 error:err];
    T(@"tool: a failed dry run stops the command", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(ok), YN(Exists(junk))]);

    MMToolCommand *bare = [MMToolCommand tool:@"fixture-tool" path:tool args:@[@"prune"] dryRunArgs:nil env:nil];
    err = @"unset";
    T(@"tool: no dry-run form gives nil and no error", @"nil nil", [NSString stringWithFormat:@"%@ %@", Or([bare dryRun:&err]), Or(err)]);
    MMUndoRecord *r3 = [MMUndo.shared begin:gExpert kind:@"tool" finding:@"t" subject:@"fixture-tool" why:@"test" by:@"manual" parent:nil payload:nil];
    ok = [bare runWithRecord:r3 output:&out error:&err];
    [MMUndo.shared finish:r3 ok:ok freed:0 error:err];
    T(@"tool: with no dry-run form the record keeps the command line", [tool stringByAppendingString:@" prune"], Or([MMUndo.shared record:r3.rid].payload[@"dryRun"]));
}

static void WrapUp(void) {
    NSString *a = Path(@"wrap-a.txt"), *b = Path(@"wrap-b.txt");
    Write(a, @"a"); Write(b, @"b");
    MMUndoRecord *parent = [MMUndo.shared begin:gExpert kind:@"wrapup" finding:@"w" subject:@"a workstream" why:@"test" by:@"manual" parent:nil payload:nil];
    for (NSString *path in @[a, b]) {
        MMUndoRecord *part = [MMUndo.shared begin:gExpert kind:@"trash" finding:path subject:path.lastPathComponent why:@"test" by:@"manual" parent:parent.rid payload:nil];
        [MMUndo.shared trash:[NSURL fileURLWithPath:path] record:part error:nil];
        [MMUndo.shared finish:part ok:YES freed:0 error:nil];
    }
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
    T(@"wrap up: both parts went to the Trash", @"no no", [NSString stringWithFormat:@"%@ %@", YN(Exists(a)), YN(Exists(b))]);
    T(@"wrap up: the parent record can be restored", @"yes", YN([MMUndo.shared record:parent.rid].canRestore));
    T(@"wrap up: restoring it restores every part", @"nil", Or([MMUndo.shared restore:parent.rid]));
    T(@"wrap up: both parts are back", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(Exists(a)), YN(Exists(b))]);
    NSUInteger restored = 0;
    for (MMUndoRecord *r in [MMUndo.shared recent:gExpert limit:0]) if ([r.parentRid isEqual:parent.rid] && r.state == MMUndoRestored) restored++;
    T(@"wrap up: each part's record says restored", @"2", @(restored).stringValue);
}

static NSUInteger OurAssertions(void) {
    CFDictionaryRef byPid = NULL;
    NSUInteger n = 0;
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        NSArray *ours = ((__bridge NSDictionary *)byPid)[@(getpid())];
        for (NSDictionary *a in ours) if ([a[@"AssertName"] hasPrefix:@"MinMacs keeps the Mac awake"]) n++;
        CFRelease(byPid);
    }
    return n;
}

static void Awake(void) {
    MMProcKey k = Spawn(@"plain", 30);
    [MMAwake holdFor:k reason:@"an agent works"];
    T(@"awake: a hold is tied to the agent's pid", @"an agent works", Or(MMAwake.held[MMProcKeyString(k)]));
    T(@"awake: it holds the pair caffeinate takes", @"2", @(OurAssertions()).stringValue);
    kill(k.pid, SIGTERM);
    for (int i = 0; i < 60 && MMAwake.held.count; i++) usleep(50000);
    Reap();
    T(@"awake: the hold ends when the agent exits", @"0 0", [NSString stringWithFormat:@"%lu %lu", (unsigned long)MMAwake.held.count, (unsigned long)OurAssertions()]);
    [MMAwake holdFor:k reason:@"gone"];
    T(@"awake: a process that has exited is never held", @"0", @(MMAwake.held.count).stringValue);
    MMProcKey a = Spawn(@"plain", 30), b = Spawn(@"plain", 30);
    [MMAwake holdFor:a reason:@"one"]; [MMAwake holdFor:b reason:@"two"];
    [MMAwake release:a];
    T(@"awake: release ends one hold", @"1", @(MMAwake.held.count).stringValue);
    [MMAwake releaseAll];
    T(@"awake: releaseAll ends every hold", @"0 0", [NSString stringWithFormat:@"%lu %lu", (unsigned long)MMAwake.held.count, (unsigned long)OurAssertions()]);
    MMStop(@[V(a), V(b)], MMStopTerm, 3); Reap();
}

static void Notify(void) {
    MMFakeNotifier *fake = [MMFakeNotifier new];
    fake.posts = [NSMutableArray new];
    MMUseNotifier(fake);
    setenv("MINMACS_TEST_DISK_FREE", "900000000000", 1);
    MMUndoRecord *asked = [MMUndo.shared begin:gExpert kind:@"stop" finding:@"n" subject:@"x" why:@"test" by:@"manual" parent:nil payload:nil];
    MMNotify(gExpert, @"Stopped 1 Server", @"It used 200 MB.", asked.rid);
    T(@"notify: nothing after an action the person asked for", @"0", @(fake.posts.count).stringValue);
    MMUndoRecord *mode = [MMUndo.shared begin:gExpert kind:@"stop" finding:@"n" subject:@"x" why:@"test" by:@"proactive" parent:nil payload:nil];
    MMNotify(gExpert, @"Stopped 1 Server.", @"It used 200 MB.", mode.rid);
    NSDictionary *n = fake.posts.lastObject;
    T(@"notify: one after an action nobody asked for", @"1", @(fake.posts.count).stringValue);
    T(@"notify: the title has no final period", @"Stopped 1 Server", Or(n[@"title"]));
    T(@"notify: it carries Undo for its record", mode.rid, Or(n[@"rid"]));
    T(@"notify: it is passive when the disk has room", @"1", [n[@"passive"] description]);
    MMNotify(@"locohost", @"Stopped 2 Servers", @"Again.", mode.rid);
    T(@"notify: one per review across every expert", @"1", @(fake.posts.count).stringValue);
    MMSetPref(@"act.notifyGap", @0);
    setenv("MINMACS_TEST_DISK_FREE", "1000000", 1);
    MMNotify(gExpert, @"Cleaned 3 Caches", @"The disk is nearly full.", nil);
    T(@"notify: it is not passive when the disk is nearly full", @"0", [fake.posts.lastObject[@"passive"] description]);
    unsetenv("MINMACS_TEST_DISK_FREE");
    MMUseNotifier(nil);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: acttest <fixture> <dir>\n"); return 2; }
        gFixture = @(argv[1]); gDir = @(argv[2]);
        gStarted = [NSMutableArray new];
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "MINMACS_HOME is not set\n"); return 2; }
        Modes();
        MustKeep();
        Plans();
        Runs();
        Stops();
        Bundles();
        Tools();
        WrapUp();
        Awake();
        Notify();
        // Stop only what this test started, and only while its start time still matches.
        for (NSValue *v in gStarted) { MMProcKey k; [v getValue:&k size:sizeof k]; if (MMProcAlive(k)) kill(k.pid, SIGKILL); }
        Reap();
        printf("END\n");
    }
    return 0;
}
