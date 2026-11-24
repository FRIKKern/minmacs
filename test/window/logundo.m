// The log, slice 2 of the center: Undo from the log, one entry per thing, folds that say one time for one minute,
// and run rows. Included by window.m after log.m, and run by test/log.sh as `log-undo`. It uses window.m's world and
// fake experts, controller.m's Spin and SnapshotAt, welcome.m's fake login item and log.m's UndoBody and Review.
// Every row goes to the log of this tool's own MINMACS_HOME, and every file an action touches lies in the fixture
// folder: a removal goes to the home's own Trash, and an Undo moves it back from there. No process is signaled.

/// A row as -[MMLog rows:before:limit:] gives it, made by hand, so a check can say when it was written.
static MMLogEntry *FakeRow(int64_t row, NSString *table, NSString *rid, NSString *state, NSDate *at, NSDictionary *body) {
    MMLogEntry *e = [MMLogEntry new];
    [e setValue:@(row) forKey:@"row"]; [e setValue:table forKey:@"table"]; [e setValue:at forKey:@"at"]; [e setValue:body forKey:@"body"];
    if (rid) [e setValue:rid forKey:@"rid"];
    if (state) [e setValue:state forKey:@"state"];
    [e setValue:@"locohost" forKey:@"expert"];
    return e;
}

static NSString *UndoStateWord(MMUndoState s) { return @[@"pending", @"done", @"failed", @"restored"][(NSUInteger)s]; }

/// Today at this many minutes after midnight, here.
static NSDate *Today(NSInteger minutes) { return [[NSCalendar.currentCalendar startOfDayForDate:NSDate.date] dateByAddingTimeInterval:minutes * 60]; }

static NSString *Said(NSArray<MMWindowLogEntry *> *es) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowLogEntry *e in es) [out addObject:[NSString stringWithFormat:@"%@ [%@] %@%@", e.sentence, e.time, e.kind, e.canUndo ? @" undo" : @""]];
    return [out componentsJoinedByString:@" | "];
}

/// The words of rows made by hand: a restore told in its action's entry, the folds, and the run rows.
static void LogUndoWords(void) {
    NSDate *now = Today(23 * 60);
    NSDictionary *restart = @{@"restart": @{@"command": @"pnpm dev"}};
    // An action and its restore, five minutes on: one entry, at the action's place, with both times and no Undo.
    NSArray *rows = @[FakeRow(22, @"undo", @"r-a", @"restored", Today(12 * 60 + 5), UndoBody(@"r-a", @"stop", @":3000 Next.js atlas", @"restored", @"manual", nil, restart, nil, nil)),
                      FakeRow(21, @"undo", @"r-a", @"done", Today(12 * 60), UndoBody(@"r-a", @"stop", @":3000 Next.js atlas", @"done", @"manual", nil, restart, nil, nil)),
                      FakeRow(20, @"undo", @"r-a", @"pending", Today(12 * 60), UndoBody(@"r-a", @"stop", @":3000 Next.js atlas", @"pending", @"manual", nil, nil, nil, nil))];
    T(@"log undo: an action taken back is one entry, with its two times, and offers no Undo", @"Stopped :3000 Next.js atlas. [12:00, started again 12:05] restored",
      Said(MMWindowLogFrom(rows, now, 300, MMWindowLogDays, 0).entries));
    // A restore whose action is out of reach stands alone, as it did.
    T(@"log undo: a restore whose action is out of reach is told on its own", @"Started again: :3000 Next.js atlas. [12:05] restored",
      Said(MMWindowLogFrom(@[rows[0]], now, 300, MMWindowLogDays, 0).entries));
    // An action of last night taken back this morning says the day of the restore.
    NSArray *night = @[FakeRow(32, @"undo", @"r-n", @"restored", Today(10), UndoBody(@"r-n", @"trash", @"leftovers in atlas", @"restored", @"cli", nil, @{@"trashed": @[@{@"from": @"/a", @"to": @"/b"}]}, nil, nil)),
                       FakeRow(31, @"undo", @"r-n", @"done", Today(-10), UndoBody(@"r-n", @"trash", @"leftovers in atlas", @"done", @"cli", nil, @{@"trashed": @[@{@"from": @"/a", @"to": @"/b"}]}, nil, nil))];
    T(@"log undo: a restore on the next day says which day", @"Moved leftovers in atlas to the Trash. [23:50, moved back today at 00:10] restored",
      Said(MMWindowLogFrom(night, now, 300, MMWindowLogDays, 0).entries));

    // Three quiet reviews in one minute say one time. Two an hour apart say from and to.
    NSDictionary *q = Review(@"workforest", @"schedule", 4, 0, 0, 100);
    NSArray *minute = @[FakeRow(43, @"review", nil, nil, [Today(2 * 60 + 58) dateByAddingTimeInterval:50], q),
                        FakeRow(42, @"review", nil, nil, [Today(2 * 60 + 58) dateByAddingTimeInterval:20], q),
                        FakeRow(41, @"review", nil, nil, [Today(2 * 60 + 58) dateByAddingTimeInterval:1], q)];
    T(@"log fold: reviews folded within one minute show one time, never 02:58 to 02:58", @"3 reviews acted on nothing. [02:58] reviews",
      Said(MMWindowLogFrom(minute, now, 300, MMWindowLogDays, 0).entries));
    // Quiet reviews fold across what came between them on one day, and the line stands where the newest is. A
    // review that acted, and a day that turned, end nothing and join nothing.
    NSDictionary *setting = @{@"key": @"locohost.mode", @"old": @"proactive", @"new": @"eager", @"by": @"cli"};
    NSArray *between = @[FakeRow(56, @"review", nil, nil, Today(9 * 60), q),
                         FakeRow(55, @"setting", nil, @"set", Today(8 * 60 + 30), setting),
                         FakeRow(54, @"review", nil, nil, Today(8 * 60 + 15), Review(@"locohost", @"schedule", 2, 1, 1, 300)),
                         FakeRow(53, @"review", nil, nil, Today(8 * 60), q),
                         FakeRow(52, @"review", nil, nil, Today(-120), q)];
    T(@"log fold: quiet reviews of one day fold across the entries between them, not across a day",
      @"2 reviews acted on nothing. [08:00 to 09:00] reviews | Stop idle servers changed from Careful to Eager. [08:30] setting | "
      @"Review of servers: looked at 3, kept 2, 1 can go, acted on 1. [08:15] review | Review of worktrees: looked at 4, kept 4. [22:00] review",
      Said(MMWindowLogFrom(between, now, 300, MMWindowLogDays, 0).entries));
    T(@"log fold: the fold counts as one entry toward the most", @"2", @(MMWindowLogFrom(between, now, 2, MMWindowLogDays, 0).entries.count));

    // The run rows: one entry each, the skips in their more and in --json.
    NSDictionary *fix = @{@"what": MMLogRunFixEverything, @"by": @"manual", @"planned": @7, @"done": @5,
                          @"skipped": @[MMLogRunSkip(@"Claude Code in atlas", @"it asks you", @"asks"), MMLogRunSkip(@"Codex in notes", @"it asks you", @"asks")],
                          @"gains": @{@"memory": @(2516582400ull), @"disk": @(1860000000ull)}};
    NSDictionary *pass = @{@"what": @"locohost", @"by": @"proactive", @"planned": @3, @"done": @2,
                           @"skipped": @[MMLogRunSkip(@":4321 Astro docs", @"it ignored SIGTERM and still runs", @"failed")], @"gains": @{@"memory": @(671088640ull), @"disk": @0}};
    NSArray<MMWindowLogEntry *> *runs = MMWindowLogFrom(@[FakeRow(62, MMLogRunTable, nil, @"ended", Today(14 * 60), fix), FakeRow(61, MMLogRunTable, nil, @"ended", Today(13 * 60), pass)],
                                                        now, 300, MMWindowLogDays, 0).entries;
    T(@"log run: Fix Everything and a mode pass are one entry each, with who", @"Fix Everything: 5 done, 2 skipped. 2 agents ask you. [14:00] run by you | "
      @"Stop idle servers: 2 done, 1 skipped. 1 failed. [13:00] run on its own, Careful",
      [NSString stringWithFormat:@"%@ %@ | %@ %@", Said(@[runs.firstObject]), runs.firstObject.who, Said(@[runs.lastObject]), runs.lastObject.who]);
    T(@"log run: its more says each skip and why, and what came back", @"Skipped Claude Code in atlas: it asks you. Skipped Codex in notes: it asks you. It gave back 2.34 GB memory and 1.86 GB disk.",
      runs.firstObject.more);
    NSDictionary *j = MMWindowLogEntryJSON(runs.lastObject);
    T(@"log run: --json gives the skips as the row holds them", @":4321 Astro docs|it ignored SIGTERM and still runs|failed",
      [NSString stringWithFormat:@"%@|%@|%@", [j[@"skipped"] firstObject][@"subject"], [j[@"skipped"] firstObject][@"why"], [j[@"skipped"] firstObject][@"as"]]);
    NSMutableArray *shown = [NSMutableArray new];
    for (MMWindowLogEntry *e in runs) { [shown addObject:e.sentence]; [shown addObject:e.more ?: @""]; }
    T(@"log run: no aside in parentheses, no old app's name, no claimed result", @"", [Bad(shown) stringByAppendingString:[[shown componentsJoinedByString:@" "] containsString:@"("] ? @"(" : @""]);

    // What the window's own presses change: undoing hides the press and says so, a refusal says why and keeps it.
    MMWindowLog *one = [MMWindowLog new];
    one.entries = MMWindowLogFrom(@[rows[1], rows[2]], now, 300, MMWindowLogDays, 0).entries;
    MMWindowLogEntry *e0 = one.entries.firstObject;
    MMWindowLog *undoing = MMWindowLogWithUndo(one, [NSSet setWithObject:@"r-a"], @{});
    MMWindowLog *refused = MMWindowLogWithUndo(one, [NSSet set], @{@"r-a": @"a restore of it is already running"});
    T(@"log undo: an entry that can be taken back carries its rid and how Undo works", @"yes r-a Undo starts it again.", [NSString stringWithFormat:@"%@ %@ %@", YN(e0.canUndo), e0.undoRid, e0.undoHelp]);
    T(@"log undo: while it is taken back the press is away and the quiet line says so, and the read log is untouched", @"no yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(undoing.entries.firstObject.canUndo), YN([undoing.entries.firstObject.detail hasSuffix:@" · taking it back"]),
       YN(e0.canUndo), YN(MMWindowLogWithUndo(one, [NSSet set], @{}) == one)]);
    T(@"log undo: an Undo that did not go through says why and keeps the press", @"yes Stopped :3000 Next.js atlas. Undo starts it again. Undo did not go through: a restore of it is already running.",
      [NSString stringWithFormat:@"%@ %@", YN(refused.entries.firstObject.canUndo), refused.entries.firstObject.sentence]);
}

/// Real records in the fixture home: one that can come back, one an older MinMacs deleted at once, a tool's own
/// cleanup and a failed quit. Only the first is offered Undo. A press goes through the controller to -[MMUndo
/// restore:], the file is back, and the entry says it was taken back.
static void LogUndoPress(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    NSUInteger writes = MMLogMainThreadWrites(), queries = MMLogMainThreadQueries();
    dispatch_queue_t off = dispatch_queue_create("no.guerrilla.minmacs.test.logundo", DISPATCH_QUEUE_SERIAL);
    void (^offMain)(dispatch_block_t) = ^(dispatch_block_t work) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(off, ^{ work(); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    };
    NSString *kept = [Dir(@"undo/kept") stringByAppendingPathComponent:@"cache"], *gone = [Dir(@"undo/gone") stringByAppendingPathComponent:@"cache"];
    for (NSString *p in @[kept, gone]) {
        [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
        [@"fixture\n" writeToFile:[p stringByAppendingPathComponent:@"a.bin"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    __block MMUndoRecord *back = nil, *deleted = nil, *tool = nil, *failed = nil;
    offMain(^{
        MMUndo *u = MMUndo.shared;
        // The way every removal goes: to the Trash, here the home's own.
        back = [u begin:@"noonoo" kind:@"trash" finding:@"noonoo:clutter:kept" subject:@"kept cache" why:@"test" by:@"manual" parent:nil payload:nil];
        MMRemovalNote(back, MMRemovalDecide(MMRemovalClutter, nil, nil), nil);
        MMRemovalAsk(back, @[kept]);
        NSError *e = nil;
        BOOL ok = MMRemovalApply(kept, MMRemovalDecide(MMRemovalClutter, nil, nil), back, &e);
        MMRemovalDone(back, nil);
        [u finish:back ok:ok freed:0 error:nil];
        back = [u record:back.rid];
        // What an older MinMacs did under Delete: gone at once, with no way back. Only the checks' seam makes it now.
        deleted = [u begin:@"noonoo" kind:@"trash" finding:@"noonoo:clutter:gone" subject:@"gone cache" why:@"test" by:@"manual" parent:nil payload:nil];
        MMRemovalDecision *del = MMRemovalTestDeleteDecision(MMRemovalClutter);
        MMRemovalNote(deleted, del, nil);
        MMRemovalAsk(deleted, @[gone]);
        ok = MMRemovalApply(gone, del, deleted, &e);
        MMRemovalDone(deleted, nil);
        [u finish:deleted ok:ok freed:0 error:nil];
        deleted = [u record:deleted.rid];
        tool = [u begin:@"noonoo" kind:@"tool" finding:@"noonoo:tool:npm" subject:@"npm cache" why:@"test" by:@"manual" parent:nil payload:@{@"command": @"npm cache clean"}];
        [u finish:tool ok:YES freed:0 error:nil];
        failed = [u begin:@"minmacs" kind:@"quit" finding:@"minmacs:app:preview" subject:@"Preview" why:@"test" by:@"manual" parent:nil payload:@{@"relaunch": @{@"bundleID": @"com.example.preview"}}];
        [u finish:failed ok:NO freed:0 error:@"it did not quit"];
    });
    T(@"log undo: the fixtures: one in the home's Trash that can come back, one deleted at once that cannot", @"yes yes no no yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", YN(back.canRestore), YN([[back.payload[@"trashed"] firstObject][@"to"] hasPrefix:MMTrashFolder()]),
       YN([NSFileManager.defaultManager fileExistsAtPath:kept]), YN(deleted.canRestore), YN(deleted.deletedNow)]);

    MMWindowController *c = [MMWindowController new];
    WLogin *login = [WLogin new];
    c.shell = login;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    [c setOpen:YES];
    [c take:SnapshotAt(1)];
    Spin(20, ^BOOL { return models.lastObject.log.entries.count >= 4; });
    MMWindowLogEntry *(^entryOf)(NSString *) = ^MMWindowLogEntry *(NSString *subject) {
        for (MMWindowLogEntry *e in models.lastObject.log.entries) if ([e.sentence containsString:subject]) return e;
        return nil;
    };
    MMWindowLogEntry *b = entryOf(@"kept cache"), *d = entryOf(@"gone cache"), *t = entryOf(@"npm cache"), *f = entryOf(@"Preview");
    T(@"log undo: Undo is offered for the record that can come back, with its rid, and never for the deleted one, the tool's cleanup or the failed quit",
      [NSString stringWithFormat:@"yes %@ no no no", back.rid],
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", YN(b.canUndo), b.undoRid, YN(d.canUndo || d.undoRid), YN(t.canUndo || t.undoRid), YN(f.canUndo || f.undoRid)]);
    T(@"log undo: the deleted one says so, and promises no Undo", @"Deleted gone cache. It cannot be brought back.", d.sentence);

    // The press: the same restore the notification's Undo runs, off main. The file is back, and the entry says so.
    NSString *key = b.key;
    [c windowUndo:back.rid];
    BOOL restored = Spin(30, ^BOOL {
        MMWindowLogEntry *e = entryOf(@"kept cache");
        return [e.kind isEqualToString:@"restored"] && [e.time containsString:@", moved back "];
    });
    MMWindowLogEntry *after = entryOf(@"kept cache");
    // The checks' own reads run off main, so main's counts are the window's alone.
    NSString *(^stateNow)(void) = ^NSString * { __block NSString *w = nil; offMain(^{ w = UndoStateWord([MMUndo.shared record:back.rid].state); }); return w; };
    NSInteger mentions = 0;
    for (MMWindowLogEntry *e in models.lastObject.log.entries) if ([e.sentence containsString:@"kept cache"]) mentions++;
    T(@"log undo: a press on Undo restores the record, and the entry shows it was taken back", @"yes yes restored 1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %ld %@", YN(restored), YN([NSFileManager.defaultManager fileExistsAtPath:[kept stringByAppendingPathComponent:@"a.bin"]]),
       stateNow(), (long)mentions, YN(after.canUndo)]);
    T(@"log undo: the restore is told in the action's own entry, at its place", @"yes Moved kept cache to the Trash.", [NSString stringWithFormat:@"%@ %@", YN([after.key isEqualToString:key]), after.sentence]);
    // A second press on a record taken back does nothing, and says why.
    [c windowUndo:back.rid];
    Spin(1, ^BOOL { return NO; });
    T(@"log undo: a second press on it restores nothing again", @"restored", stateNow());
    T(@"log undo: main wrote no row and ran no query for the press", @"0 0", [NSString stringWithFormat:@"%lu %lu",
      (unsigned long)(MMLogMainThreadWrites() - writes), (unsigned long)(MMLogMainThreadQueries() - queries)]);
    [c setOpen:NO];
}

/// A run of Fix Everything on the fixture world writes one run row: what it planned, did and skipped, with why.
static void LogUndoRun(void) {
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    [gNowKept addObject:@"minmacs:app:com.example.chat"];
    NSInteger before = (NSInteger)[MMLog.shared rows:@[MMLogRunTable] before:0 limit:100].count;
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    runner.onProgress = ^(MMWindowRun *r) { if (!r.running) dispatch_semaphore_signal(ended); };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"log run: the run ends", @"yes", @"no"); return; }
    NSArray<MMLogEntry *> *rows = [MMLog.shared rows:@[MMLogRunTable] before:0 limit:100];
    MMLogEntry *row = rows.firstObject;
    NSDictionary *b = row.body;
    NSMutableArray *skips = [NSMutableArray new];
    for (NSDictionary *x in b[@"skipped"]) [skips addObject:[NSString stringWithFormat:@"%@=%@", x[@"as"], x[@"subject"]]];
    NSInteger planned = 0;
    for (MMPerformanceFix *f in p.fixes) planned += f.wrapUp ? 1 : (NSInteger)f.actions.count;
    T(@"log run: one run row, by the person, with what it planned and did", [NSString stringWithFormat:@"1 fix-everything manual %ld 4", (long)planned],
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)rows.count - before, b[@"what"], b[@"by"], b[@"planned"], b[@"done"]]);
    T(@"log run: each thing it skipped, with why", @"asks=Claude Code | press=pnpm store | kept=Chat", [skips componentsJoinedByString:@" | "]);
    T(@"log run: what came back, as two numbers", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN([b[@"gains"][@"memory"] unsignedLongLongValue] > 0), YN([b[@"gains"][@"disk"] isKindOfClass:NSNumber.class])]);
    MMWindowLogEntry *e = MMWindowLogFrom(rows, NSDate.date, 300, MMWindowLogDays, 0).entries.firstObject;
    T(@"log run: the log says it in one entry", @"Fix Everything: 4 done, 3 skipped. 1 agent asks you, 1 waits for your own press and 1 was kept, since it is in use or changed.", e.sentence);
    T(@"log run: its more names the kept one and why", @"yes", YN([e.more containsString:@"Skipped Chat: it is in use now."]));
}

static void LogUndo(void) {
    LogUndoWords();
    LogUndoPress();
    LogUndoRun();
}
