// The log in the middle of the window, slice 1 of the center. Included by window.m, after welcome.m, and run by
// test/log.sh. It uses window.m's world, controller.m's Spin and SnapshotAt and welcome.m's fake login item. Every
// row goes to the log of this tool's own MINMACS_HOME. Nothing here acts: the undo rows are written as Act writes
// them, and no action runs.

/// A body as -[MMUndo begin:] and -finish: write them, with the payload that says how restore takes it back.
static NSDictionary *UndoBody(NSString *rid, NSString *kind, NSString *subject, NSString *state, NSString *by, NSString *why,
                              NSDictionary *payload, NSString *parent, NSString *error) {
    NSMutableDictionary *b = [@{@"rid": rid, @"kind": kind, @"subject": subject, @"state": state, @"by": by, @"expert": @"locohost",
                                @"at": @(NSDate.date.timeIntervalSince1970), @"payload": payload ?: @{}, @"freedBytes": @0} mutableCopy];
    if (why) b[@"why"] = why;
    if (parent) b[@"parentRid"] = parent;
    if (error) b[@"error"] = error;
    return b;
}

static void Undo(MMLog *log, NSString *rid, NSString *kind, NSString *subject, NSString *state, NSString *by, NSString *why, NSDictionary *payload,
                 NSString *parent, NSString *error) {
    NSDictionary *b = UndoBody(rid, kind, subject, state, by, why, payload, parent, error);
    [log append:@"undo" rid:rid expert:b[@"expert"] subject:subject state:state body:b];
}

static NSDictionary *Review(NSString *expert, NSString *trigger, NSInteger keep, NSInteger go, NSInteger acted, NSInteger tokens) {
    NSMutableDictionary *v = [NSMutableDictionary new];
    for (NSInteger i = 0; i < keep + go; i++) v[[NSString stringWithFormat:@"%@:f%ld", expert, (long)i]] = @{@"kind": i < keep ? @"keep" : @"go", @"confidence": @0.9};
    NSMutableArray *actions = [NSMutableArray new];
    for (NSInteger i = 0; i < acted; i++) [actions addObject:@{@"finding": @"x"}];
    return @{@"expert": expert, @"trigger": trigger, @"verdicts": v, @"actions": actions, @"calls": tokens ? @[@{@"uncached": @(tokens), @"model": @"opus"}] : @[],
             @"at": @(NSDate.date.timeIntervalSince1970), @"mode": @1, @"sent": @(keep + go)};
}

/// Fixture rows of every kind, oldest first, and the sentences they must give, newest first.
static void LogWords(void) {
    MMLog *log = MMLog.shared;
    Undo(log, @"r-stop", @"stop", @":3000 Next.js atlas", @"pending", @"manual", @"Fix Everything", nil, nil, nil);
    Undo(log, @"r-stop", @"stop", @":3000 Next.js atlas", @"done", @"manual", @"Fix Everything", @{@"restart": @{@"command": @"pnpm dev"}}, nil, nil);
    Undo(log, @"r-quit", @"quit", @"Chat", @"done", @"eager", @"memory pressure", @{@"relaunch": @{@"bundleID": @"com.example.chat"}}, nil, nil);
    Undo(log, @"r-back", @"trash", @"leftovers in atlas", @"done", @"manual", nil, @{@"trashed": @[@{@"from": @"/a", @"to": @"/b"}]}, nil, nil);
    Undo(log, @"r-fail", @"quit", @"Preview", @"failed", @"manual", nil, nil, nil, @"it did not quit. It may be asking to save");
    Undo(log, @"r-wrap", @"wrapup", @"Wrap Up fix-auth", @"done", @"manual", nil, @{@"path": @"/w"}, nil, nil);
    Undo(log, @"r-p1", @"stop", @":4000 Phoenix", @"done", @"run", nil, @{@"restart": @{@"command": @"mix phx.server"}}, @"r-wrap", nil);
    Undo(log, @"r-p2", @"remove", @"fix-auth", @"done", @"run", nil, @{@"worktree": @{@"path": @"/w"}}, @"r-wrap", nil);
    Undo(log, @"r-tool", @"tool", @"npm cache", @"done", @"manual", nil, @{@"command": @"npm cache clean"}, nil, nil);
    [log append:@"review" rid:nil expert:@"locohost" subject:nil state:nil body:Review(@"locohost", @"manual", 2, 1, 1, 1200)];
    for (NSInteger i = 0; i < 3; i++) [log append:@"review" rid:nil expert:@"workforest" subject:nil state:nil body:Review(@"workforest", @"schedule", 4, 0, 0, 100)];
    [log append:@"usage" rid:nil expert:@"workforest" subject:nil state:nil body:@{@"usage": @{@"uncached": @300}}];
    [log append:@"investigate" rid:nil expert:@"workforest" subject:@"fix-auth" state:@"done"
           body:@{@"subject": @"fix-auth", @"title": @"fix-auth", @"answer": @"It holds work.", @"model": @"opus", @"usage": @{@"uncached": @34000}}];
    MMLogSetting(@"locohost.mode", @"proactive", @"eager", @"cli");
    MMLogSetting(@"locohost.mode", @"eager", @"eager", @"cli");                 // the same value: no row
    MMLogSetting(MMReviewModelKey, nil, @"opus", @"settings");
    MMLogSetting(MMWindowLoginKey, @NO, @YES, @"welcome");
    MMLogSetting(MMWindowWelcomedKey, @NO, @YES, @"welcome");
    [MMKeep keep:@"atlas#dev" expert:@"locohost" until:[NSDate dateWithTimeIntervalSinceNow:4 * 3600 + 30] by:@"manual" name:@":3000 Next.js atlas"];
    [MMKeep keep:@"atlas#dev" expert:@"locohost" until:nil by:@"cli" name:@":3000 Next.js atlas"];
    Undo(log, @"r-back", @"trash", @"leftovers in atlas", @"restored", @"cli", nil, @{@"trashed": @[@{@"from": @"/a", @"to": @"/b"}]}, nil, nil);
    Undo(log, @"r-hang", @"stop", @":5173 Vite site", @"pending", @"proactive", nil, nil, nil, nil);

    MMWindowLog *l = MMWindowLogRead(log, NSDate.date, MMWindowLogMost, MMWindowLogDays);
    NSMutableArray *got = [NSMutableArray new];
    for (MMWindowLogEntry *e in l.entries) [got addObject:[NSString stringWithFormat:@"%@ [%@]", e.sentence, e.who ?: @"-"]];
    NSArray *want = @[
        @"Began to stop :5173 Vite site. No end is written yet. [on its own, Careful]",
        @"Moved back from the Trash: leftovers in atlas. [from the command line]",
        @":3000 Next.js atlas is no longer kept. The rules decide for it again. [from the command line]",
        @"Kept :3000 Next.js atlas for 4 h. No rule acts on it until then. [by you in a menu]",
        @"Start was pressed in the welcome. The welcome does not come back. [by you in the welcome]",
        @"Open at login turned on. [by you in the welcome]",
        @"The model reviews ask changed from auto to opus. [by you in Settings]",
        @"Stop idle servers changed from Careful to Eager. [from the command line]",
        @"Looked into fix-auth. [with opus]",
        @"3 reviews acted on nothing. [on its hourly round]",
        @"Review of servers: looked at 3, kept 2, 1 can go, acted on 1. [asked by you]",
        @"Ran the cleanup of npm cache. [by you]",
        @"Wrapped up fix-auth in 2 steps. Undo brings it all back. [by you]",
        @"Could not quit Preview. It did not quit. It may be asking to save. [by you]",
        @"Moved leftovers in atlas to the Trash. [by you]",
        @"Quit Chat. Undo opens it again. [on its own, Eager]",
        @"Stopped :3000 Next.js atlas. Undo starts it again. [by you, in Fix Everything]"];
    for (NSUInteger i = 0; i < MAX(want.count, got.count); i++)
        T([NSString stringWithFormat:@"log words: entry %lu", (unsigned long)i + 1], i < want.count ? want[i] : @"none", i < got.count ? got[i] : @"none");
    NSArray<MMWindowLogEntry *> *es = l.entries;
    NSMutableArray *can = [NSMutableArray new];
    for (MMWindowLogEntry *e in es) if (e.canUndo) [can addObject:[e.sentence componentsSeparatedByString:@"."].firstObject];
    T(@"log words: only records that can still be taken back say Undo", [@[@"Wrapped up fix-auth in 2 steps", @"Quit Chat", @"Stopped :3000 Next"] componentsJoinedByString:@" | "],
      [can componentsJoinedByString:@" | "]);
    MMWindowLogEntry *folded = es.count > 9 ? es[9] : nil, *review = es.count > 10 ? es[10] : nil, *look = es.count > 8 ? es[8] : nil;
    T(@"log words: the tokens of a review, of folded reviews and of a look", @"1200 300 34000", [NSString stringWithFormat:@"%ld %ld %ld", (long)review.tokens, (long)folded.tokens, (long)look.tokens]);
    T(@"log words: the quiet line says the time, who and the tokens", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN([review.detail isEqualToString:[review.time stringByAppendingString:@" · asked by you · 1,200 tokens"]]), YN([folded.time containsString:@" to "])]);
    T(@"log words: every entry is today, with the newest row first", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN([[NSSet setWithArray:[es valueForKey:@"day"]] isEqualToSet:[NSSet setWithObject:@"Today"]]), YN(es.firstObject.row > es.lastObject.row)]);
    NSMutableArray *shown = [NSMutableArray new];
    for (MMWindowLogEntry *e in es) { [shown addObject:e.sentence]; [shown addObject:e.detail]; }
    T(@"log words: no sentence names an old app, claims a result or says for good", @"", Bad(shown));
    T(@"log words: a log of 30 days shows nothing from 31 days later, and says it is empty", @"0 yes", [NSString stringWithFormat:@"%lu %@",
      (unsigned long)MMWindowLogFrom([log rows:MMWindowLogTables() before:0 limit:100], [NSDate dateWithTimeIntervalSinceNow:31 * 86400], 300, MMWindowLogDays, 0).entries.count,
      YN([MMWindowLogFrom(@[], NSDate.date, 300, MMWindowLogDays, 0).note hasPrefix:@"Nothing is in the log yet."])]);
    T(@"log words: at most `most` entries", @"4", @(MMWindowLogRead(log, NSDate.date, 4, 0).entries.count));

    // The range read: newest first, only the tables asked for, before a row, at most a limit.
    NSArray<MMLogEntry *> *all = [log rows:MMWindowLogTables() before:0 limit:1000];
    NSArray<MMLogEntry *> *page = [log rows:MMWindowLogTables() before:all[3].row limit:2];
    BOOL newestFirst = YES;
    for (NSUInteger i = 1; i < all.count; i++) if (all[i].row >= all[i - 1].row) newestFirst = NO;
    T(@"log read: newest first, no usage row, before a row and at most the limit", @"yes no 2 yes", [NSString stringWithFormat:@"%@ %@ %lu %@",
      YN(newestFirst), YN([[all valueForKey:@"table"] containsObject:@"usage"]), (unsigned long)page.count, YN(page.firstObject.row == all[4].row && page.lastObject.row == all[5].row)]);
    T(@"log read: a setting of the same value wrote no row", @"1", @([[all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"table == 'setting' AND subject == 'locohost.mode'"]] count]));
    NSDictionary *row = [[all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"table == 'setting' AND subject == 'locohost.mode'"]].firstObject body];
    T(@"log read: a setting row holds the key, from what, to what and who", @"locohost.mode proactive eager cli",
      [NSString stringWithFormat:@"%@ %@ %@ %@", row[@"key"], row[@"old"], row[@"new"], row[@"by"]]);
}

/// The window's controller: the rule switch, the login switch and Start write setting rows with who did it, the log
/// is read only while the window is open and only when it moved, and main never runs a query or writes a row.
static void LogController(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMSetPref(@"locohost.mode", nil);
    // As the app runs it: the log opens on its own queue, and main never opens, reads or writes it.
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    NSUInteger queries = MMLogMainThreadQueries(), writes = MMLogMainThreadWrites(), opens = MMLogMainThreadOpens();
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    dispatch_queue_t off = dispatch_queue_create("no.guerrilla.minmacs.test.log", DISPATCH_QUEUE_SERIAL);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); };
    // dispatch_sync runs its block on the calling thread, which here is main. The checks' own reads and writes run on
    // another thread, so the counts of main's queries and writes are the app's alone.
    void (^offMain)(dispatch_block_t) = ^(dispatch_block_t work) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(off, ^{ work(); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    };
    NSArray<MMLogEntry *> *(^settings)(void) = ^NSArray<MMLogEntry *> * {
        __block NSArray *rows = nil;
        offMain(^{ rows = [MMLog.shared rows:@[MMLogSettingTable] before:0 limit:100]; });
        return rows;
    };
    MMWindowController *c = [MMWindowController new];
    WLogin *login = [WLogin new];
    c.shell = login;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };

    // Closed: a snapshot and a new row read nothing.
    NSUInteger reads = MMWindowLogReads();
    [c take:SnapshotAt(1)];
    offMain(^{ [MMLog.shared append:@"review" rid:nil expert:@"locohost" subject:nil state:nil body:Review(@"locohost", @"manual", 1, 0, 0, 10)]; });
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"log controller: closed, nothing reads the log", @"0 0", [NSString stringWithFormat:@"%lu %lu", (unsigned long)(MMWindowLogReads() - reads), (unsigned long)models.count]);

    // Open: one read, and the model holds the log.
    [c setOpen:YES];
    [c take:SnapshotAt(2)];
    Spin(20, ^BOOL { return models.count >= 1; });
    T(@"log controller: open, the first model reads the log once and holds it", @"1 yes", [NSString stringWithFormat:@"%lu %@",
      (unsigned long)(MMWindowLogReads() - reads), YN([models.lastObject.log.entries.firstObject.sentence hasPrefix:@"Review of servers"])]);
    // A new snapshot with no new row reads nothing again.
    [c take:SnapshotAt(3)];
    Spin(20, ^BOOL { return models.lastObject.generation == 3; });
    T(@"log controller: a new snapshot with the log unchanged reads it no more", @"1 yes", [NSString stringWithFormat:@"%lu %@",
      (unsigned long)(MMWindowLogReads() - reads), YN(models.lastObject.log == models.firstObject.log)]);

    // The rule switch: a setting row by the window, and the log read again because it moved.
    [c windowSetRule:@"servers" picked:MMModeEager];
    BOOL got = Spin(20, ^BOOL { return [models.lastObject.log.entries.firstObject.sentence isEqualToString:@"Stop idle servers changed from Careful to Eager."]; });
    T(@"log controller: the rule switch writes a row by the window, and the open window shows it", @"yes by you in the window 2",
      [NSString stringWithFormat:@"%@ %@ %lu", YN(got), models.lastObject.log.entries.firstObject.who, (unsigned long)(MMWindowLogReads() - reads)]);
    // The login switch, pressed on main: its row is written off main.
    [c windowSetSwitch:@"login" on:YES];
    got = Spin(20, ^BOOL { return [models.lastObject.log.entries.firstObject.sentence isEqualToString:@"Open at login turned on."]; });
    T(@"log controller: the login switch writes a row by the window", @"yes by you in the window", [NSString stringWithFormat:@"%@ %@", YN(got), models.lastObject.log.entries.firstObject.who]);
    // Start in the welcome: the welcome's end and the login item it changed, both by the welcome.
    MMSetPref(MMWindowWelcomedKey, nil);
    [c windowWelcomeStart:NO];
    got = Spin(20, ^BOOL { return settings().count >= 4; });
    settle();
    NSMutableArray *rows = [NSMutableArray new];
    for (MMLogEntry *e in settings().reverseObjectEnumerator) [rows addObject:[NSString stringWithFormat:@"%@ %@>%@ %@", e.subject, e.body[@"old"], e.body[@"new"], e.body[@"by"]]];
    T(@"log controller: the setting rows, oldest first, with who made each", @"locohost.mode proactive>eager window | core.login 0>1 window | core.welcomed 0>1 welcome | core.login 1>0 welcome",
      [rows componentsJoinedByString:@" | "]);
    // A press on a rule that is already there writes nothing.
    [c windowSetRule:@"servers" picked:MMModeEager];
    settle();
    T(@"log controller: a press on the rule as it stands writes no row", @"4", @(settings().count));
    Spin(0.3, ^BOOL { return NO; });
    T(@"log controller: main ran no query, wrote no row and opened no log", @"0 0 0", [NSString stringWithFormat:@"%lu %lu %lu",
      (unsigned long)(MMLogMainThreadQueries() - queries), (unsigned long)(MMLogMainThreadWrites() - writes), (unsigned long)(MMLogMainThreadOpens() - opens)]);

    // Closed again: rows come and snapshots come, and nothing reads the log.
    [c setOpen:NO];
    settle();
    NSUInteger closed = MMWindowLogReads();
    offMain(^{ MMLogSetting(@"noonoo.mode", @"proactive", @"idle", @"cli"); });
    [c take:SnapshotAt(4)];
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"log controller: closed again, a new row and a snapshot read nothing", @"0", @(MMWindowLogReads() - closed));
}
