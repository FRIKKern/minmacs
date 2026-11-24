// When MinMacs cannot write its own list of what it sends to the Trash, issue #74: on the owner's Mac core/ was 0600,
// and one Fix Everything gave 169 entries, one per group, each saying the same. Included by window.m after logundo.m,
// and run by test/window.sh as `trash-list` and test/log.sh as `log-fold`. It uses window.m's world and fake experts,
// and logundo.m's FakeRow, UndoBody, Today and Said. Every row goes to this tool's own MINMACS_HOME, and nothing acts:
// the run tries no move at all.

#include <sys/stat.h>

/// Counts what would have been posted, so a check sees at most one notification.
@interface TLNotifier : NSObject <MMNotifier>
@property NSMutableArray<NSString *> *posted;
@end
@implementation TLNotifier
- (void)post:(NSString *)title body:(NSString *)body undoRid:(NSString *)undoRid passive:(BOOL)passive expert:(NSString *)expert {
    @synchronized (self) { [self.posted addObject:title]; }
}
@end

/// Runs runner off main and waits: dispatch_sync from main would run it on main, where a run does nothing.
static MMWindowRun *RunOff(MMFixRunner *runner) {
    __block MMWindowRun *end = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"windowtest", @"trash", QOS_CLASS_USER_INITIATED), ^{ end = [runner run]; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return end;
}

/// Fix Everything over 50 groups while core/ is 0600, as on the owner's Mac: none is tried, one notice says why, and
/// the log has no entry per group.
static void TrashList(void) {
    Reset();
    gRan = [NSMutableArray new]; gNowKept = [NSMutableSet new]; gRefuses = [NSMutableSet new];
    NSMutableArray<MMFinding *> *fs = [NSMutableArray new];
    for (int i = 0; i < 50; i++) {
        NSString *root = Dir([NSString stringWithFormat:@"tmp/t%02d", i]);
        [fs addObject:Finding(@"noonoo", @"clutter", [NSString stringWithFormat:@"mmworker:%02d", i], @"MMWorker-* folders",
                              [root stringByAppendingPathComponent:@"MMWorker-*"], 0, 0, 10 * MB, P(@"remove", MMReversibleTrash),
                              @{@"kindTitle": @"Worker folders", @"name": @"MMWorker-* folders", @"state": @"free"})];
    }
    for (NSString *e in @[@"locohost", @"minmacs", @"workforest", @"insomnia"]) gFindings[e] = @[];
    gFindings[@"noonoo"] = fs;
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    NSInteger moves = 0;
    for (MMPerformanceFix *f in p.fixes) if ([f.kind isEqualToString:@"trash"]) moves += (NSInteger)f.actions.count;
    T(@"trash list: the fixture plans 50 moves to the Trash", @"50", [NSString stringWithFormat:@"%ld", (long)moves]);

    TLNotifier *n = [TLNotifier new]; n.posted = [NSMutableArray new];
    MMUseNotifier(n);
    MMSetPref(@"act.notifyGap", @0);   // no rate limit, so every notice would post
    NSString *core = MMExpertDir(@"core");
    chmod(core.fileSystemRepresentation, 0600);
    T(@"trash list: with core/ at 0600 the list cannot be written", MMRemovalTrashListUnwritten, MMRemovalTrashListCannot() ?: @"(nil)");
    // The home may hold rows of the modes that ran before in it, so only the rows after this one count.
    MMLog *log = MMLog.shared;
    NSArray<NSString *> *tables = MMWindowLogTables();
    int64_t mark = [log rows:tables before:0 limit:1].firstObject.row;
    NSArray<MMLogEntry *> *(^since)(NSArray<NSString *> *) = ^NSArray<MMLogEntry *> *(NSArray<NSString *> *t) {
        NSMutableArray *out = [NSMutableArray new];
        for (MMLogEntry *e in [log rows:t before:0 limit:5000]) if (e.row > mark) [out addObject:e];
        return out;
    };
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    MMWindowRun *end = RunOff(runner);
    chmod(core.fileSystemRepresentation, 0700);

    NSInteger blocked = 0;
    for (MMFixResult *x in runner.results) if ([x.outcome isEqualToString:@"blocked"] && [x.why isEqualToString:MMRemovalTrashListUnwritten]) blocked++;
    T(@"trash list: no move is tried", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)gRan.count]);
    T(@"trash list: each of the 50 is skipped with why", @"50 50", [NSString stringWithFormat:@"%lu %ld", (unsigned long)runner.results.count, (long)blocked]);
    NSInteger records = (NSInteger)since(@[@"undo"]).count;
    NSArray<MMLogEntry *> *notices = since(@[MMLogNoticeTable]);
    T(@"trash list: no undo record is written for a move never tried", @"0", [NSString stringWithFormat:@"%ld", (long)records]);
    T(@"trash list: one notice, which says why once", @"1 Could Not Move 50 Groups to the Trash", [NSString stringWithFormat:@"%lu %@",
      (unsigned long)notices.count, notices.firstObject.body[@"title"]]);
    T(@"trash list: at most one notification", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)n.posted.count]);
    MMWindowLog *l = MMWindowLogFrom(since(tables), NSDate.date, MMWindowLogMost, MMWindowLogDays, 0);
    NSMutableArray *kinds = [NSMutableArray new];
    for (MMWindowLogEntry *e in l.entries) [kinds addObject:e.kind];
    T(@"trash list: the log holds the run and the one notice, and no entry per group", @"notice run", [[kinds sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    MMWindowLogEntry *notice = nil, *run = nil;
    for (MMWindowLogEntry *e in l.entries) { if ([e.kind isEqualToString:@"notice"]) notice = e; if ([e.kind isEqualToString:@"run"]) run = e; }
    T(@"trash list: the notice in the log", @"Could not move 50 groups to the Trash. MinMacs could not write its own list of what it sends to the Trash, "
      @"so they stay where they are. Fix Everything tried none of them.", notice.sentence);
    T(@"trash list: the run's entry", @"Fix Everything: 0 done, 50 skipped. 50 could not start.", run.sentence);
    T(@"trash list: the run's more says the why once", @"Skipped MMWorker-* folders, MMWorker-* folders and 48 more: MinMacs could not write its own list of what it sends "
      @"to the Trash, so the item stays where it is.", run.more);
    T(@"trash list: the end note counts them", @"yes", YN([end.endNote containsString:@"50"]));

    // Once the list can be written again, the moves are tried as before.
    T(@"trash list: with core/ at 0700 the list can be written", @"(nil)", MMRemovalTrashListCannot() ?: @"(nil)");
    MMFixRunner *again = [[MMFixRunner alloc] initWithPerformance:p];
    (void)RunOff(again);
    T(@"trash list: then each move is tried", @"50", [NSString stringWithFormat:@"%lu", (unsigned long)gRan.count]);
    T(@"trash list: and the notice stays one", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)since(@[MMLogNoticeTable]).count]);
    MMUseNotifier(nil);
    MMSetPref(@"act.notifyGap", nil);
}

/// The fold of identical failures in the log, on rows made by hand, newest first.
static void LogFold(void) {
    NSDate *now = Today(23 * 60);
    NSMutableArray<MMLogEntry *> *rows = [NSMutableArray new];
    __block int64_t row = 2000;
    void (^undo)(NSString *, NSString *, NSString *, NSString *, NSString *, NSString *, NSDate *) =
        ^(NSString *rid, NSString *kind, NSString *subject, NSString *state, NSString *why, NSString *error, NSDate *at) {
            [rows addObject:FakeRow(row--, @"undo", rid, state, at, UndoBody(rid, kind, subject, state, @"manual", why, nil, nil, error))];
        };
    NSDictionary *run = @{@"what": MMLogRunFixEverything, @"by": @"manual", @"planned": @169, @"done": @0, @"skipped": @[], @"gains": @{}};
    [rows addObject:FakeRow(row--, MMLogRunTable, nil, @"ended", Today(12 * 60 + 3), run)];
    // 169 groups whose move failed the same way, each a failed row after its pending row.
    for (int i = 168; i >= 0; i--) {
        NSString *rid = [NSString stringWithFormat:@"r%03d", i];
        NSDate *at = Today(12 * 60 + i / 60);
        undo(rid, @"trash", @"MMWorker-* folders", @"failed", @"Fix Everything", MMRemovalTrashListUnwritten, at);
        undo(rid, @"trash", @"MMWorker-* folders", @"pending", @"Fix Everything", nil, at);
    }
    // Before them, two that failed the same way with an action between them, and one that failed another way.
    undo(@"x1", @"trash", @"DerivedData", @"failed", nil, MMRemovalTrashListUnwritten, Today(11 * 60 + 2));
    undo(@"x2", @"stop", @":3000 Next.js atlas", @"done", nil, nil, Today(11 * 60 + 1));
    undo(@"x3", @"trash", @"node_modules", @"failed", nil, MMRemovalTrashListUnwritten, Today(11 * 60));
    undo(@"x4", @"quit", @"Preview", @"failed", nil, @"it did not quit. It may be asking to save", Today(10 * 60));
    MMWindowLog *l = MMWindowLogFrom(rows, now, 300, MMWindowLogDays, 0);
    T(@"log fold: 169 identical failures are one entry, between the run and what came before", @"Fix Everything: 0 done. [12:03] run | "
      @"Could not move 169 groups to the Trash. MinMacs could not write its own list of what it sends to the Trash, so they stay where they are. [12:00 to 12:02] failed | "
      @"Could not move DerivedData to the Trash. MinMacs could not write its own list of what it sends to the Trash, so the item stays where it is. [11:02] failed | "
      @"Stopped :3000 Next.js atlas. [11:01] action | "
      @"Could not move node_modules to the Trash. MinMacs could not write its own list of what it sends to the Trash, so the item stays where it is. [11:00] failed | "
      @"Could not quit Preview. It did not quit. It may be asking to save. [10:00] failed", Said(l.entries));
    MMWindowLogEntry *fold = l.entries.count > 1 ? l.entries[1] : nil;
    T(@"log fold: the entry names them in its more", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN([fold.more hasPrefix:@"MMWorker-* folders, MMWorker-* folders,"]),
      YN([fold.more hasSuffix:@"and 157 more."])]);
    T(@"log fold: its key is its oldest row's, so it stays while newer failures join", @"failed:", [fold.key substringToIndex:MIN(fold.key.length, (NSUInteger)7)]);
    // The same read before the newest 50 of them came gives the same key: the oldest row did not move.
    NSArray *before = [@[rows[0]] arrayByAddingObjectsFromArray:[rows subarrayWithRange:NSMakeRange(101, rows.count - 101)]];
    MMWindowLog *fewer = MMWindowLogFrom(before, now, 300, MMWindowLogDays, 0);
    T(@"log fold: the key does not change as the fold grows", @"yes", YN(fewer.entries.count > 1 && [fewer.entries[1].key isEqualToString:fold.key]));
    // Two runs, each with its run row, never fold into one another.
    NSArray *two = @[FakeRow(10, MMLogRunTable, nil, @"ended", Today(13 * 60 + 1), run),
                     FakeRow(9, @"undo", @"b", @"failed", Today(13 * 60), UndoBody(@"b", @"trash", @"MMWorker-* folders", @"failed", @"manual", @"Fix Everything", nil, nil, MMRemovalTrashListUnwritten)),
                     FakeRow(8, MMLogRunTable, nil, @"ended", Today(12 * 60 + 1), run),
                     FakeRow(7, @"undo", @"a", @"failed", Today(12 * 60), UndoBody(@"a", @"trash", @"MMWorker-* folders", @"failed", @"manual", @"Fix Everything", nil, nil, MMRemovalTrashListUnwritten))];
    T(@"log fold: two runs stay two", @"4", [NSString stringWithFormat:@"%lu", (unsigned long)MMWindowLogFrom(two, now, 300, MMWindowLogDays, 0).entries.count]);
    // A notice's title keeps the capitals of a name in the log: MinMacs and the Trash.
    NSArray *notice = @[FakeRow(5, MMLogNoticeTable, nil, @"notice", Today(9 * 60), @{@"title": @"MinMacs Could Not Clean 3 Items", @"text": @"a: it is in use"}),
                        FakeRow(4, MMLogNoticeTable, nil, @"notice", Today(9 * 60), @{@"title": @"Lid Mode Needs a One-Time Setup", @"text": @"Run it once."})];
    T(@"log fold: a notice keeps the capitals of a name", @"MinMacs could not clean 3 items. A: it is in use. [09:00] notice | Lid mode needs a one-time setup. Run it once. [09:00] notice",
      Said(MMWindowLogFrom(notice, now, 300, MMWindowLogDays, 0).entries));
    // A notice's text from several failures says each why once.
    T(@"log fold: a notice's text folds identical whys", @"a, b and 2 more: it is in use / c: it is gone",
      [MMNoticeLines(@[@[@"a", @"it is in use"], @[@"b", @"it is in use"], @[@"c", @"it is gone"], @[@"d", @"it is in use"], @[@"e", @"it is in use"]]) stringByReplacingOccurrencesOfString:@"\n" withString:@" / "]);
}
