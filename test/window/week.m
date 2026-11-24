// The strip's 7 days, for test/window/window.m, which includes this file after controller.m: the words of a young or
// full week, the feed, and the controller, which reads the points only while open and only on the 7 days, keeps them
// until the hour turns or an hour is written, and remembers the choice. The points are fixtures in the test home's log.
#import "Shell/MMWindowController.h"

static NSString *Held(NSArray *v) {
    NSMutableString *s = [NSMutableString new];
    for (id x in v) [s appendString:x == NSNull.null ? @"-" : @"x"];
    return s;
}

static void WeekWords(void) {
    NSString *words = [@[MMWindowWeekSpanWords(168), MMWindowWeekSpanWords(160), MMWindowWeekSpanWords(72), MMWindowWeekSpanWords(48),
                         MMWindowWeekSpanWords(40), MMWindowWeekSpanWords(30), MMWindowWeekSpanWords(5), MMWindowWeekSpanWords(1)] componentsJoinedByString:@" | "];
    T(@"week: the strip says how long its line is, and never more than it holds",
      @"the last 7 days | the last 7 days | the last 3 days | the last 2 days | the last 2 days | the last day | the last 5 h | the last hour", words);
    // Two days young: the first 120 hours hold nothing, so the line spans the last 48 and says so.
    NSMutableArray *young = [NSMutableArray new];
    for (NSInteger i = 0; i < MMWindowWeekHours; i++) [young addObject:i < 120 ? NSNull.null : @(i * 1000000)];
    NSInteger first = -1, filled = 0;
    NSArray *span = MMWindowWeekSpan(young, &first, &filled);
    T(@"week: two days young, the line starts at its first kept hour and says the last 2 days", @"120 48 48 the last 2 days",
      [NSString stringWithFormat:@"%ld %ld %lu %@", (long)first, (long)filled, (unsigned long)span.count, MMWindowWeekSpanWords((NSInteger)young.count - first)]);
    // A gap in the middle and at the end stays where it is: the span runs to the newest hour, gaps and all.
    NSMutableArray *gap = [young mutableCopy];
    for (NSInteger i = 140; i < 150; i++) gap[i] = NSNull.null;
    gap[167] = NSNull.null;
    span = MMWindowWeekSpan(gap, &first, &filled);
    T(@"week: a gap stays a gap in the span, where it was, and an empty last hour stays at the end", @"48 37 yes yes",
      [NSString stringWithFormat:@"%lu %ld %@ %@", (unsigned long)span.count, (long)filled, YN(span[25] == NSNull.null && span[29] == NSNull.null), YN(span.lastObject == NSNull.null)]);
    NSMutableArray *one = [NSMutableArray new];
    for (NSInteger i = 0; i < MMWindowWeekHours; i++) [one addObject:i == 100 ? @1 : NSNull.null];
    T(@"week: one kept hour draws no line", @"yes", YN(MMWindowWeekSpan(one, NULL, NULL) == nil));

    // The feed: the extras' hours become the model's two weeks, with the first hour and the whole of each side.
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowExtras *x = [MMWindowExtras readWithLogin:NO];
    MMWindowModel *m = MMWindowModelFrom(s, p, x);
    T(@"week: with the strip on the hour the model holds no week", @"no no no", [NSString stringWithFormat:@"%@ %@ %@", YN(m.stripWeek), YN(m.memoryWeek != nil), YN(m.diskWeek != nil)]);
    x.stripWeek = YES; x.memoryWeek = young; x.diskWeek = gap; x.weekFirstAt = 1795305600;
    m = MMWindowModelFrom(s, p, x);
    T(@"week: on the 7 days the model holds both, as read, from their first hour", @"yes 168 168 1795305600 Memory in use Disk free",
      [NSString stringWithFormat:@"%@ %lu %lu %.0f %@ %@", YN(m.stripWeek), (unsigned long)m.memoryWeek.values.count, (unsigned long)m.diskWeek.values.count,
       m.diskWeek.firstAt, m.memoryWeek.title, m.diskWeek.title]);
}

static void WeekController(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMSetPref(MMWindowWeekKey, nil);
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    dispatch_queue_t off = dispatch_queue_create("no.guerrilla.minmacs.test.week", DISPATCH_QUEUE_SERIAL);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); };
    void (^offMain)(dispatch_block_t) = ^(dispatch_block_t work) { dispatch_sync(off, work); };
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    long long H = (long long)floor(now / 3600);
    // Three hours ago and the last hour that ended, with the hour between them asleep.
    offMain(^{
        MMHistoryWeekWrite(MMLog.shared, (H - 3) * 3600.0, 20.0 * GB, 180.0 * 1e9, now);
        MMHistoryWeekWrite(MMLog.shared, (H - 1) * 3600.0, 24.0 * GB, 179.0 * 1e9, now);
    });
    NSUInteger reads = MMHistoryWeekReads();
    MMWindowController *c = [MMWindowController new];
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };

    // Closed, with the choice on the 7 days: nothing reads the points.
    MMSetPref(MMWindowWeekKey, @YES);
    [c take:SnapshotAt(1)];
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"week controller: closed, nothing reads the points", @"0 0", [NSString stringWithFormat:@"%lu %lu", (unsigned long)(MMHistoryWeekReads() - reads), (unsigned long)models.count]);

    // Open on the hour: no read either.
    MMSetPref(MMWindowWeekKey, @NO);
    [c setOpen:YES];
    [c take:SnapshotAt(2)];
    Spin(20, ^BOOL { return models.count > 0; });
    T(@"week controller: open on the hour, the points are not read and the model holds no week", @"0 no no",
      [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)(MMHistoryWeekReads() - reads), YN(models.lastObject.stripWeek), YN(models.lastObject.memoryWeek != nil)]);

    // The press on "7 days": the pref is kept, off main, and the next model holds both weeks with the gap where it was.
    __block NSUInteger settingRows = 0;
    offMain(^{ settingRows = [MMLog.shared rows:@[MMLogSettingTable] before:0 limit:1000].count; });
    [c windowStripWeek:YES];
    Spin(20, ^BOOL { return models.lastObject.memoryWeek != nil; });
    MMWindowModel *m = models.lastObject;
    NSString *tail = [Held(m.memoryWeek.values) substringFromIndex:164];
    T(@"week controller: on 7 days the model holds the hours read, one read a side, with the hour asleep a gap", @"yes yes 2 -x-x",
      [NSString stringWithFormat:@"%@ %@ %lu %@", YN(m.stripWeek), YN(MMPrefBool(MMWindowWeekKey, NO)), (unsigned long)(MMHistoryWeekReads() - reads), tail]);
    T(@"week controller: the newest kept hour is the last one that ended", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN([m.memoryWeek.values[167] isEqual:@(24 * GB)]), YN(m.memoryWeek.firstAt == (H - 168) * 3600.0)]);

    // A newer snapshot in the same hour reads nothing: the hours are kept until the hour turns or one is written.
    [c take:SnapshotAt(3)];
    Spin(20, ^BOOL { return models.lastObject.generation == 3; });
    T(@"week controller: a new snapshot in the same hour keeps what was read", @"2 yes",
      [NSString stringWithFormat:@"%lu %@", (unsigned long)(MMHistoryWeekReads() - reads), YN(models.lastObject.memoryWeek.values.count == 168)]);
    offMain(^{ MMHistoryWeekWrite(MMLog.shared, (H - 2) * 3600.0, 22.0 * GB, 179.5 * 1e9, now); });
    [c take:SnapshotAt(4)];
    Spin(20, ^BOOL { return models.lastObject.generation == 4; });
    T(@"week controller: an hour this process wrote is read at the next model", @"4 -xxx",
      [NSString stringWithFormat:@"%lu %@", (unsigned long)(MMHistoryWeekReads() - reads), [Held(models.lastObject.memoryWeek.values) substringFromIndex:164]]);

    // Closed again: a snapshot reads nothing.
    [c setOpen:NO];
    NSUInteger had = MMHistoryWeekReads();
    [c take:SnapshotAt(5)];
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"week controller: closed again, nothing reads the points", @"0", @(MMHistoryWeekReads() - had));

    // The choice is remembered: a new controller, as after a restart, opens on the 7 days. Back to the hour, no read.
    MMWindowController *again = [MMWindowController new];
    NSMutableArray<MMWindowModel *> *later = [NSMutableArray new];
    again.onModel = ^(MMWindowModel *x) { [later addObject:x]; };
    [again setOpen:YES];
    [again take:SnapshotAt(6)];
    Spin(20, ^BOOL { return later.count > 0; });
    T(@"week controller: the choice is remembered, and a window opened later shows the 7 days", @"yes yes",
      [NSString stringWithFormat:@"%@ %@", YN(later.lastObject.stripWeek), YN(later.lastObject.memoryWeek != nil)]);
    [again windowStripWeek:NO];
    Spin(20, ^BOOL { return !later.lastObject.stripWeek; });
    had = MMHistoryWeekReads();
    [again take:SnapshotAt(7)];
    Spin(20, ^BOOL { return later.lastObject.generation == 7; });
    T(@"week controller: back on the hour, the pref says so and nothing is read", @"no no 0",
      [NSString stringWithFormat:@"%@ %@ %lu", YN(MMPrefBool(MMWindowWeekKey, NO)), YN(later.lastObject.memoryWeek != nil), (unsigned long)(MMHistoryWeekReads() - had)]);
    __block NSUInteger rowsNow = 0;
    offMain(^{ rowsNow = [MMLog.shared rows:@[MMLogSettingTable] before:0 limit:1000].count; });
    T(@"week controller: the choice writes no setting row, since it is a look", @"0", @(rowsNow - settingRows));
    [again setOpen:NO];
}
