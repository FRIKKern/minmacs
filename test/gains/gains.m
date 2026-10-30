// The checks of the kept log of what came back, MMGains.h. test/gains.sh builds this with all of Sources/Core.
// Usage: gainstest <fixture binary> <fixture dir>
// Every process and file it acts on is a fixture it made inside $MINMACS_HOME. With MINMACS_HOME set, MMUndo moves
// files into $MINMACS_HOME/Trash, and "emptying the Trash" here removes only the fixture's own item from that folder.
// It prints one line per check, CHECK<tab>name<tab>want<tab>got, and gains.sh hands each to check.
#import <spawn.h>
#import <sqlite3.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import "Core/MMCore.h"

extern char **environ;

static void T(NSString *name, id want, id got) {
    printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, [want description].UTF8String ?: "", [got description].UTF8String ?: "(nil)");
    fflush(stdout);
}
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }
static NSString *Or(NSString *s) { return s ?: @"nil"; }

static void OffMain(void (^block)(void)) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"gainstest", @"run", QOS_CLASS_USER_INITIATED), ^{ block(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

static NSString *gFixture, *gDir, *gExpert = @"gainstest";
static NSMutableArray<NSValue *> *gStarted;

#pragma mark - Fixtures

static MMProcKey KeyOf(pid_t pid) {
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    MMProcKey k = { pid, 0 };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len) k.startSec = (uint64_t)kp.kp_proc.p_starttime.tv_sec;
    return k;
}
static NSValue *V(MMProcKey k) { return [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]; }
static void Reap(void) { int st; while (waitpid(-1, &st, WNOHANG) > 0) {} }
/// Starts the fixture with mb megabytes touched, and waits until its footprint shows them.
static MMProcKey Spawn(int mb) {
    pid_t pid = 0;
    char m[16]; snprintf(m, sizeof m, "%d", mb);
    char *argv[] = { (char *)gFixture.fileSystemRepresentation, m, "60", NULL };
    if (posix_spawn(&pid, gFixture.fileSystemRepresentation, NULL, NULL, argv, environ) != 0) return (MMProcKey){0, 0};
    MMProcKey k = { pid, 0 };
    for (int i = 0; i < 50; i++) {
        usleep(100000);
        k = KeyOf(pid);
        MMProc *p = [MMSenses.shared.sampleNow proc:pid];
        if (p && p.footprint >= ((uint64_t)mb << 20)) break;
    }
    [gStarted addObject:V(k)];
    return k;
}
static NSString *Path(NSString *name) { return [gDir stringByAppendingPathComponent:name]; }
static NSString *MakeFile(NSString *name) {
    NSString *p = Path(name);
    [@"fixture cache\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return p;
}
static BOOL Exists(NSString *p) { return [NSFileManager.defaultManager fileExistsAtPath:p]; }

#pragma mark - Findings, actions and the policy

static MMFinding *ServerFinding(MMProcKey k, MMOwner *owner) {
    return [MMFinding expert:gExpert kind:@"server" stableKey:[NSString stringWithFormat:@"fixture-%d", k.pid] build:^(MMFindingBuilder *b) {
        b.title = [NSString stringWithFormat:@"fixture server %d", k.pid];
        b.instanceKey = MMProcKeyString(k); b.procs = @[V(k)]; b.owner = owner; b.keepReasons = @[]; b.facts = @{};
        MMCost c = {0}; c.ramBytes = 1; c.cpuPercent = -1; b.cost = c;
        b.proposal = [MMProposal verb:@"stop" title:@"Stop" reversibility:MMReversibleRestart];
    }];
}
static MMFinding *CacheFinding(NSString *path, uint64_t freed, NSDictionary *facts) {
    return [MMFinding expert:gExpert kind:@"clutter" stableKey:path.lastPathComponent build:^(MMFindingBuilder *b) {
        b.title = path.lastPathComponent; b.path = path; b.keepReasons = @[]; b.facts = facts ?: @{};
        MMCost c = {0}; c.diskFreed = freed; c.cpuPercent = -1; b.cost = c;
        b.proposal = [MMProposal verb:@"clean" title:@"Move to Trash" reversibility:MMReversibleTrash];
    }];
}

@interface GNAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property (copy) NSString *kind;
@property BOOL fails;
@end
@implementation GNAction
- (NSString *)recheck { return nil; }
- (NSString *)dryRun { return @"would act on a fixture"; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    if (self.fails) { if (error) *error = @"the fixture action fails on purpose"; return NO; }
    if ([self.kind isEqualToString:@"stop"]) return MMStop(self.finding.procs, MMStopTerm, 5).count == 0;
    if ([self.kind isEqualToString:@"trash"]) {
        NSError *e = nil;
        NSURL *to = [MMUndo.shared trash:[NSURL fileURLWithPath:self.finding.path] record:record error:&e];
        if (!to && error) *error = e.localizedDescription ?: @"the trash failed";
        return to != nil;
    }
    return YES;
}
@end
static GNAction *Act(NSString *kind, MMFinding *f) { GNAction *a = [GNAction new]; a.kind = kind; a.finding = f; return a; }

@interface GNPolicy : NSObject <MMExpertPolicy>
@end
@implementation GNPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts { return [f.facts[@"keep"] boolValue] ? @"the fixture says keep" : nil; }
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

/// Fresh facts: a new sample of every process, as the app's source takes for a stop.
@interface GNSource : NSObject <MMFactSource>
@end
@implementation GNSource
- (MMFacts *)factsFor:(uint64_t)generation { return nil; }
- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    MMSample *s = finding.procs.count ? MMSenses.shared.sampleNow : nil;
    return [MMFacts generation:0 sample:s power:nil agents:nil sessions:nil worktrees:nil clutter:nil git:nil];
}
@end

static MMUndoRecord *Run(GNAction *a, NSString *by, NSString **err) {
    __block MMUndoRecord *r = nil;
    __block NSString *e = nil;
    OffMain(^{ r = MMRunAction(a, [GNPolicy new], nil, by, @"gains test", &e); });
    if (err) *err = e;
    return r;
}
static MMUndoRecord *RunPart(GNAction *a, NSString *parent, NSInteger i) {
    __block MMUndoRecord *r = nil;
    OffMain(^{ NSString *e = nil; r = MMRunActionPart(a, [GNPolicy new], @"manual", @"part of the gains test Wrap Up", parent, i, &e); });
    return r;
}
static NSString *Restore(NSString *rid) {
    __block NSString *p = nil;
    OffMain(^{ p = [MMUndo.shared restore:rid]; });
    return p;
}
static NSString *TrashedTo(MMUndoRecord *r) { return [r.payload[@"trashed"] firstObject][@"to"]; }

#pragma mark - The checks

static void Actions(void) {
    MMGains *g = MMGains.shared;
    T(@"gains: the table opens at schema 1", @"1", @([g schemaVersion]));
    MMOwner *ws = [MMOwner kind:MMOwnerWorkstream key:Path(@"ws") name:@"ws" path:Path(@"ws") parent:nil];

    // A stop: memory back is the tree footprint read right before it ran, never the finding's cost.
    MMProcKey k = Spawn(48);
    T(@"gains: the 48 MB fixture runs", @"yes", YN(MMProcAlive(k)));
    NSString *err = nil;
    MMUndoRecord *stop = Run(Act(@"stop", ServerFinding(k, ws)), @"manual", &err);
    MMGain *a = [g gain:stop.rid];
    T(@"gains: a stop that finished writes a row", @"yes", YN(a != nil));
    T(@"gains: a stopped server is kind server", @"server", Or(a.kind));
    T(@"gains: a stop from the menu was done by you", @"you", Or(a.who));
    T(@"gains: memory back is the footprint read before, 48 MB or more", @"yes", YN(a.memoryBytes >= (48ull << 20)));
    T(@"gains: memory back is not the finding's cost", @"yes", YN(a.memoryBytes != 1));
    T(@"gains: a stop gives no disk back", @"0 none", [NSString stringWithFormat:@"%llu %@", a.diskBytes, a.diskState]);
    T(@"gains: the row keeps its workstream", [@"workstream:" stringByAppendingString:Path(@"ws")], Or(a.workstream));

    // A move to the Trash by an expert's own rule: its bytes wait in the Trash until the item is gone.
    NSString *fb = MakeFile(@"cache-b");
    MMUndoRecord *rb = Run(Act(@"trash", CacheFinding(fb, 5000000, nil)), @"guard", &err);
    MMGain *b = [g gain:rb.rid];
    T(@"gains: a moved cache is kind cache, by Auto", @"cache auto", [NSString stringWithFormat:@"%@ %@", b.kind, b.who]);
    T(@"gains: it waits in the Trash", @"trash", Or(b.diskState));
    NSDictionary *s = [g summary:1 now:NSDate.date];
    T(@"gains: today has no disk back while it is in the Trash", @"0", [s[@"today"][@"diskBack"] description]);
    T(@"gains: today shows it in the Trash", @"5000000", [s[@"today"][@"diskInTrash"] description]);
    NSString *tb = TrashedTo(rb);
    T(@"gains: the fixture item is in the test's Trash", @"yes", YN(tb && [tb hasPrefix:MMTrashFolder()] && Exists(tb)));
    if (tb && [tb hasPrefix:MMTrashFolder()]) [NSFileManager.defaultManager removeItemAtPath:tb error:nil];
    s = [g summary:1 now:NSDate.date];
    T(@"gains: once the Trash is emptied its bytes are back", @"5000000", [s[@"today"][@"diskBack"] description]);
    T(@"gains: the row is settled as freed", @"freed", Or([g gain:rb.rid].diskState));

    // An undo takes the gain back.
    NSString *fc = MakeFile(@"cache-c");
    MMUndoRecord *rc = Run(Act(@"trash", CacheFinding(fc, 7000000, nil)), @"manual", &err);
    T(@"gains: a second move writes a row", @"yes", YN([g gain:rc.rid] != nil));
    T(@"gains: restore of it works", @"nil", Or(Restore(rc.rid)));
    T(@"gains: the file is back", @"yes", YN(Exists(fc)));
    T(@"gains: the undone row is marked undone", @"yes", YN([g gain:rc.rid].undone));
    s = [g summary:1 now:NSDate.date];
    T(@"gains: an undone row counts nothing in the Trash", @"0", [s[@"today"][@"diskInTrash"] description]);
    BOOL listed = NO;
    for (NSDictionary *x in s[@"gains"]) if ([x[@"rid"] isEqual:rc.rid]) listed = YES;
    T(@"gains: an undone row is not listed", @"no", YN(listed));

    // An item put back by hand never counts; a new item an app made at the old path does not stop the count.
    NSString *fi = MakeFile(@"cache-i");
    MMUndoRecord *ri = Run(Act(@"trash", CacheFinding(fi, 1000000, nil)), @"manual", &err);
    NSString *ti = TrashedTo(ri);
    if (ti) [NSFileManager.defaultManager moveItemAtPath:ti toPath:fi error:nil];
    [g summary:1 now:NSDate.date];
    T(@"gains: an item put back by hand is marked put-back", @"put-back", Or([g gain:ri.rid].diskState));
    NSString *fj = MakeFile(@"cache-j");
    MMUndoRecord *rj = Run(Act(@"trash", CacheFinding(fj, 2000000, nil)), @"manual", &err);
    NSString *tj = TrashedTo(rj);
    if (tj && [tj hasPrefix:MMTrashFolder()]) [NSFileManager.defaultManager removeItemAtPath:tj error:nil];
    MakeFile(@"cache-j");
    [g summary:1 now:NSDate.date];
    T(@"gains: a new item at the old path still counts as freed", @"freed", Or([g gain:rj.rid].diskState));

    // A failed action, a kept one and one that gives nothing back record nothing.
    GNAction *fail = Act(@"trash", CacheFinding(MakeFile(@"cache-d"), 9000000, nil));
    fail.fails = YES;
    MMUndoRecord *rd = Run(fail, @"manual", &err);
    T(@"gains: the failed action has a failed undo record", @"yes", YN(rd && rd.state == MMUndoFailed));
    T(@"gains: a failed action records nothing", @"no", YN([g gain:rd.rid] != nil));
    MMUndoRecord *rk = Run(Act(@"trash", CacheFinding(MakeFile(@"cache-k"), 9000000, @{@"keep": @YES})), @"manual", &err);
    T(@"gains: a kept action does not start", @"yes", YN(rk == nil && [err hasPrefix:@"kept:"]));
    MMUndoRecord *rl = Run(Act(@"lid", CacheFinding(Path(@"lid"), 0, nil)), @"guard", &err);
    T(@"gains: the lid override finished", @"yes", YN(rl && rl.state == MMUndoDone));
    T(@"gains: the lid override is not a gain", @"no", YN(!rl || [g gain:rl.rid] != nil));

    // A Wrap Up: each part is a row of kind workstream by a run, counted as one action.
    NSString *wt = Path(@"wt");
    MMUndoRecord *parent = [MMUndo.shared begin:@"core" kind:@"wrapup" finding:[@"core:workstream:" stringByAppendingString:wt]
                                        subject:@"Wrap Up wt" why:@"gains test" by:@"manual" parent:nil payload:@{@"path": wt}];
    MMProcKey k2 = Spawn(16);
    MMUndoRecord *p0 = RunPart(Act(@"stop", ServerFinding(k2, nil)), parent.rid, 0);
    MMUndoRecord *p1 = RunPart(Act(@"trash", CacheFinding(MakeFile(@"cache-h"), 3000000, nil)), parent.rid, 1);
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
    MMGain *g0 = [g gain:p0.rid], *g1 = [g gain:p1.rid];
    T(@"gains: a Wrap Up part is kind workstream", @"workstream workstream", [NSString stringWithFormat:@"%@ %@", g0.kind, g1.kind]);
    T(@"gains: each part keeps what it was", @"server cache", [NSString stringWithFormat:@"%@ %@", g0.part, g1.part]);
    T(@"gains: a part was done by a run", @"run", Or(g0.who));
    T(@"gains: a part names its run", parent.rid, Or(g0.run));
    T(@"gains: a part's workstream is the Wrap Up's worktree", [@"worktree:" stringByAppendingString:wt], Or(g0.workstream));
    T(@"gains: the stopped part gives 16 MB or more back", @"yes", YN(g0.memoryBytes >= (16ull << 20)));
    s = [g summary:1 now:NSDate.date];
    T(@"gains: a run of two parts is one workstream action", @"1 2",
      [NSString stringWithFormat:@"%@ %@", s[@"byKind"][@"workstream"][@"actions"], s[@"byKind"][@"workstream"][@"items"]]);
    T(@"gains: restore of the Wrap Up works", @"nil", Or(Restore(parent.rid)));
    T(@"gains: the restored cache part is undone", @"yes", YN([g gain:p1.rid].undone));
    T(@"gains: the stop part had nothing to restore and still counts", @"no", YN([g gain:p0.rid].undone));

    s = [g summary:1 now:NSDate.date];
    // Left today: the stop, the freed cache, the put-back cache, the cache with a new item, and the run's stop.
    T(@"gains: today counts five actions", @"5", [s[@"today"][@"actions"] description]);
    T(@"gains: today's disk back is the two freed caches", @"7000000", [s[@"today"][@"diskBack"] description]);
    T(@"gains: by who", @"1 3 1", [NSString stringWithFormat:@"%@ %@ %@", s[@"byWho"][@"auto"][@"actions"], s[@"byWho"][@"you"][@"actions"], s[@"byWho"][@"run"][@"actions"]]);
    T(@"gains: memory and disk are never summed", @"yes",
      YN([s[@"today"][@"memoryBack"] unsignedLongLongValue] == a.memoryBytes + g0.memoryBytes));
}

/// Runs sql on a file with SQLite directly, as an older build or the clock would have left it.
static void Exec(NSString *path, NSString *sql) {
    sqlite3 *db = NULL;
    if (sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK) {
        char *e = NULL;
        if (sqlite3_exec(db, sql.UTF8String, NULL, NULL, &e) != SQLITE_OK) fprintf(stderr, "sql: %s\n", e ?: "?");
        sqlite3_free(e);
    }
    sqlite3_close(db);
}
static NSInteger Count(NSString *path, NSString *sql) {
    sqlite3 *db = NULL; sqlite3_stmt *st = NULL;
    NSInteger n = -1;
    if (sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK && sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK
        && sqlite3_step(st) == SQLITE_ROW) n = (NSInteger)sqlite3_column_int64(st, 0);
    sqlite3_finalize(st); sqlite3_close(db);
    return n;
}
static NSString *Row(NSString *rid, double at) {
    return [NSString stringWithFormat:@"INSERT INTO gains (rid, kind, who, by, expert, subject, at, memory, disk, disk_state, items)"
            " VALUES ('%@', 'server', 'you', 'manual', 'gainstest', '%@', %.3f, 1000, 0, 'none', 1);", rid, rid, at];
}

static void Seeded(void) {
    // The migration: a log an older build made, with rows and no gains table, gets the table and keeps its rows.
    NSString *old = Path(@"old.sqlite");
    MMLog *log = [[MMLog alloc] initWithPath:old];
    MMLogEntry *e = [log append:@"undo" rid:nil expert:gExpert subject:@"old" state:@"done" body:@{@"rid": @"old"}];
    log = nil;
    T(@"migrate: the old file has no gains table", @"0", @(Count(old, @"SELECT COUNT(*) FROM sqlite_master WHERE name = 'gains'")));
    MMGains *m = [[MMGains alloc] initWithPath:old];
    T(@"migrate: it gets the gains table at schema 1", @"1 1",
      [NSString stringWithFormat:@"%ld %ld", (long)Count(old, @"SELECT COUNT(*) FROM sqlite_master WHERE name = 'gains'"), (long)[m schemaVersion]]);
    T(@"migrate: the log's rows stay", @"1", @([[MMLog alloc] initWithPath:old] ? Count(old, [NSString stringWithFormat:@"SELECT COUNT(*) FROM rows WHERE rid = '%@'", e.rid]) : -1));
    MMGains *again = [[MMGains alloc] initWithPath:old];
    T(@"migrate: a second open keeps one schema row", @"1 1", [NSString stringWithFormat:@"%ld %ld", (long)[again schemaVersion], (long)Count(old, @"SELECT COUNT(*) FROM gains_schema")]);

    // The day boundary and the 30 days, on rows the clock left.
    NSString *path = Path(@"seed.sqlite");
    MMGains *g = [[MMGains alloc] initWithPath:path];
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *today = [cal startOfDayForDate:NSDate.date];
    double now = NSDate.date.timeIntervalSince1970;
    Exec(path, [@[Row(@"before-midnight", today.timeIntervalSince1970 - 30), Row(@"after-midnight", today.timeIntervalSince1970 + 30),
                  Row(@"days-29", now - 29 * 86400.0), Row(@"days-31", now - 31 * 86400.0)] componentsJoinedByString:@""]);
    T(@"keep: four rows are seeded", @"4", @(Count(path, @"SELECT COUNT(*) FROM gains")));
    NSDictionary *s = [g summary:2 now:[today dateByAddingTimeInterval:60]];
    NSArray *days = s[@"byDay"];
    T(@"day: two days, oldest first", @"2", @(days.count));
    T(@"day: a row 30 seconds before midnight is yesterday's", @"1", [days.firstObject[@"actions"] description]);
    T(@"day: a row 30 seconds after midnight is today's", @"1", [days.lastObject[@"actions"] description]);
    T(@"day: today holds only the row after midnight", @"1 1000", [NSString stringWithFormat:@"%@ %@", s[@"today"][@"actions"], s[@"today"][@"memoryBack"]]);
    T(@"day: the first day starts at yesterday's midnight", @"yes",
      YN([days.firstObject[@"start"] doubleValue] == [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0].timeIntervalSince1970));
    T(@"keep: a row 31 days old is dropped", @"nil", [g gain:@"days-31"] ? @"kept" : @"nil");
    T(@"keep: a row 29 days old stays", @"kept", [g gain:@"days-29"] ? @"kept" : @"nil");
    T(@"keep: the table holds three rows", @"3", @(Count(path, @"SELECT COUNT(*) FROM gains")));
    s = [g summary:30 now:NSDate.date];
    T(@"keep: 30 days hold the three rows", @"3", [s[@"total"][@"actions"] description]);
    s = [g summary:99 now:NSDate.date];
    T(@"keep: days are cut to 30", @"30", [s[@"days"] description]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: gainstest <fixture> <dir>\n"); return 2; }
        gFixture = @(argv[1]); gDir = @(argv[2]);
        gStarted = [NSMutableArray new];
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "MINMACS_HOME is not set\n"); return 2; }
        MMGraph.shared.source = [GNSource new];
        Actions();
        Seeded();
        // Stop only what this test started, and only while its start time still matches.
        for (NSValue *v in gStarted) { MMProcKey k; [v getValue:&k size:sizeof k]; if (MMProcAlive(k)) kill(k.pid, SIGKILL); }
        Reap();
        printf("END\n");
    }
    return 0;
}
