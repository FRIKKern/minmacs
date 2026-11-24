// Ask MinMacs, tier 0, slice 4 of the center. Included by window.m after pulls.m, and run by test/ask.sh as
// `ask-engine`, `ask-controller` and `ask-rows`. It uses window.m's world and fake experts, controller.m's Spin and
// SnapshotAt and welcome.m's fake login item. Every row goes to the log of this tool's own MINMACS_HOME. Nothing here
// acts but the one press on Keep the controller check makes, which writes a keep into this home's own files.
#import "Shell/MMAsk.h"

/// An undo row as -[MMUndo begin:] and -finish: write it, for a finding of the world.
static void AskUndo(NSString *rid, NSString *expert, NSString *kind, NSString *finding, NSString *subject, NSString *state, NSString *by, NSString *why,
                    NSDictionary *payload, NSString *parent) {
    NSMutableDictionary *b = [@{@"rid": rid, @"kind": kind, @"subject": subject, @"state": state, @"by": by, @"expert": expert, @"findingID": finding ?: @"",
                                @"at": @(NSDate.date.timeIntervalSince1970), @"payload": payload ?: @{}, @"freedBytes": @0} mutableCopy];
    if (why) b[@"why"] = why;
    if (parent) b[@"parentRid"] = parent;
    [MMLog.shared append:@"undo" rid:rid expert:expert subject:subject state:state body:b];
}

static NSString *gAskServer, *gAskApp, *gAskSpike;

/// The rows of a day: a review that said why, two stops of one server, one of them taken back, a Wrap Up with a part
/// that removed a worktree, and a quit. Oldest first.
static void AskRows(void) {
    gAskServer = @"locohost:server:w1#dev"; gAskApp = @"minmacs:app:com.example.chat";
    NSDictionary *restart = @{@"restart": @{@"command": @"pnpm dev"}};
    [MMLog.shared append:@"review" rid:nil expert:@"locohost" subject:nil state:nil
                    body:@{@"expert": @"locohost", @"trigger": @"schedule", @"actions": @[@{@"finding": gAskServer}], @"calls": @[],
                           @"verdicts": @{gAskServer: @{@"kind": @"go", @"confidence": @0.9, @"reason": @"No requests in an hour and nothing changed in its project"}}}];
    AskUndo(@"r-a2", @"locohost", @"stop", gAskServer, @":3000 Vite fix-auth-redirect", @"pending", @"manual", @"Fix Everything", nil, nil);
    AskUndo(@"r-a2", @"locohost", @"stop", gAskServer, @":3000 Vite fix-auth-redirect", @"done", @"manual", @"Fix Everything", restart, nil);
    AskUndo(@"r-a2", @"locohost", @"stop", gAskServer, @":3000 Vite fix-auth-redirect", @"restored", @"cli", @"Fix Everything", restart, nil);
    AskUndo(@"r-w", @"core", @"wrapup", nil, @"Wrap Up old-spike", @"done", @"manual", @"its work is merged", @{@"path": @"/w"}, nil);
    AskUndo(@"r-w1", @"workforest", @"remove", @"workforest:worktree:old", @"old-spike", @"done", @"run", nil, @{@"worktree": @{@"path": @"/w"}}, @"r-w");
    AskUndo(@"r-q", @"minmacs", @"quit", gAskApp, @"Chat", @"done", @"eager", @"memory pressure", @{@"relaunch": @{@"bundleID": @"com.example.chat"}}, nil);
    AskUndo(@"r-a1", @"locohost", @"stop", gAskServer, @":3000 Vite fix-auth-redirect", @"pending", @"proactive", @"idle for 1 h, no agent above it", nil, nil);
    AskUndo(@"r-a1", @"locohost", @"stop", gAskServer, @":3000 Vite fix-auth-redirect", @"done", @"proactive", @"idle for 1 h, no agent above it", restart, nil);
}

static NSString *Counts(void) {
    NSArray<MMLogEntry *> *rows = [MMLog.shared rows:@[@"undo", MMLogKeepTable] before:0 limit:1000];
    NSInteger restored = 0, keeps = 0;
    for (MMLogEntry *e in rows) { if ([e.table isEqualToString:@"undo"] && [e.state isEqualToString:@"restored"]) restored++; if ([e.table isEqualToString:MMLogKeepTable]) keeps++; }
    return [NSString stringWithFormat:@"%ld restored, %ld keeps", (long)restored, (long)keeps];
}

static NSString *Entries(MMWindowAnswer *a) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowAnswerEntry *e in a.entries) [out addObject:e.sentence];
    return [out componentsJoinedByString:@" | "];
}

static void AskEngine(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    AskRows();
    gAskSpike = nil;
    for (MMWindowRow *r in Rows(m)) if ([r.name hasSuffix:@"old-spike"]) gAskSpike = r.key;
    MMAskWorld *w = [MMAskWorld new];
    w.model = m; w.rows = [MMAskWorld rowsOf:MMLog.shared]; w.targets = [MMAskWorld targetsOf:m snapshot:s]; w.now = NSDate.date;
    NSString *before = Counts();
    T(@"ask world: the fixture holds the server, the app and the worktree it asks about", @"yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN([m row:gAskServer] != nil), YN([m row:gAskApp] != nil), YN(gAskSpike != nil)]);

    // why: the log's entries of the records that acted on it, each with its own why, who acted and the review's reason.
    MMWindowAnswer *a = MMAskTier0(@"Why did you stop :3000?", w);
    MMWindowAnswerEntry *e0 = a.entries.firstObject, *e1 = a.entries.count > 1 ? a.entries[1] : nil;
    T(@"ask why: why did you stop :3000 gives its two stops, newest first, from the log's own sentences", @"why 2 | Stopped :3000 Vite fix-auth-redirect. Undo starts it again. | Stopped :3000 Vite fix-auth-redirect.",
      [NSString stringWithFormat:@"%@ %lu | %@", a.kind, (unsigned long)a.entries.count, Entries(a)]);
    T(@"ask why: each says its own reason and the review's, and who acted", @"Its reason: Idle for 1 h, no agent above it. The review said: No requests in an hour and nothing changed in its project. | yes",
      [NSString stringWithFormat:@"%@ | %@", e0.why, YN([e0.detail hasSuffix:@" · on its own, Careful"])]);
    T(@"ask why: Fix Everything is no reason of its own; the one taken back says both times and who", @"The review said: No requests in an hour and nothing changed in its project. | yes yes",
      [NSString stringWithFormat:@"%@ | %@ %@", e1.why, YN([e1.detail containsString:@", started again "]), YN([e1.detail containsString:@"by you, in Fix Everything"])]);
    T(@"ask why: an entry links to its row while the row is in the window", @"locohost:server:w1#dev (null)", [NSString stringWithFormat:@"%@ %@", e0.row, e0.logKey]);
    T(@"ask why: the lead counts what it found and claims nothing", @"The log holds 2 actions on “:3000”, newest first, each with its own reason.", a.answer);
    a = MMAskTier0(@"why did you quit chat", w);
    T(@"ask why: why did you quit chat gives the quit, with its reason and who", @"Quit Chat. Undo opens it again. | Its reason: Memory pressure. | yes",
      [NSString stringWithFormat:@"%@ | %@ | %@", Entries(a), a.entries.firstObject.why, YN([a.entries.firstObject.detail hasSuffix:@"on its own, Eager"])]);
    a = MMAskTier0(@"why did you remove old-spike", w);
    T(@"ask why: a part of a Wrap Up says so, with the Wrap Up's reason, and the Wrap Up stands after it", @"2 Removed the worktree old-spike, in a Wrap Up. | Its reason: Its work is merged. | no | yes",
      [NSString stringWithFormat:@"%lu %@ | %@ | %@ | %@", (unsigned long)a.entries.count, a.entries.firstObject.sentence, a.entries.firstObject.why, YN(a.entries.firstObject.row != nil),
       YN([a.entries.lastObject.sentence hasPrefix:@"Wrapped up old-spike"] && a.entries.lastObject.logKey.length)]);
    a = MMAskTier0(@"why did you quit :3000", w);
    T(@"ask why: the verb counts: a server that was stopped was never quit", @"0 The log holds nothing MinMacs did to “:3000”.", [NSString stringWithFormat:@"%lu %@", (unsigned long)a.entries.count, a.answer]);

    // plan: Fix Everything's plan, what each gives back, and what it skips and why.
    a = MMAskTier0(@"What would you clean now?", w);
    NSInteger runs = 0, press = 0, asking = 0;
    for (MMWindowFix *f in m.fixes) if (!f.needsYou) runs++;
    for (MMWindowAnswerEntry *e in a.entries) { if ([e.why isEqualToString:@"Skipped, since it waits for your own press."]) press++; if ([e.why isEqualToString:@"Skipped, since it asks you."]) asking++; }
    NSString *lead = [NSString stringWithFormat:@"Fix Everything would run %@ and give back ", MMWindowFixes(runs)];
    T(@"ask plan: what would you clean now gives every fix with what it gives back, then what it skips and why", @"plan yes yes 1 1 yes",
      [NSString stringWithFormat:@"%@ %@ %@ %ld %ld %@", a.kind, YN([a.answer hasPrefix:lead]), YN([a.answer hasSuffix:@"Nothing runs until you press it."]), (long)press, (long)asking,
       YN((NSInteger)a.entries.count == runs + press + asking && [a.entries.firstObject.detail hasPrefix:@"+"])]);
    MMAskWorld *empty = [MMAskWorld new];
    empty.model = MMWindowFixture(@"empty"); empty.rows = @[]; empty.now = NSDate.date;
    T(@"ask plan: with nothing to fix it says so and claims no result", @"Fix Everything has no fixes to run now.", MMAskTier0(@"what would you fix", empty).answer);

    // about: the row is made the active one, and the answer has its story's words.
    a = MMAskTier0(@"what is :3001", w);
    T(@"ask about: what is :3001 names the server's row, its group and its story", @"about locohost:server:app#dev | :3001 Next.js, in servers. Goes with Fix Everything | yes",
      [NSString stringWithFormat:@"%@ %@ | %@ | %@", a.kind, a.row, [a.answer substringToIndex:MIN(a.answer.length, (NSUInteger)51)], YN([Entries(a) containsString:@"Port: "])]);
    a = MMAskTier0(@"tell me about old-spike", w);
    T(@"ask about: tell me about a worktree by its branch", gAskSpike ?: @"-", a.row ?: @"none");
    a = MMAskTier0(@"what is zzqx", w);
    T(@"ask about: a name nothing has is said so, and no row is picked", @"none Nothing in the window is named “zzqx” now.", [NSString stringWithFormat:@"%@ %@", a.row ?: @"none", a.answer]);

    // keep and undo: the button that exists already, and its verb. Nothing acts.
    a = MMAskTier0(@"keep old-spike", w);
    NSString *path = [w.targets[gAskSpike].command substringFromIndex:@"minmacs keep ".length];
    T(@"ask keep: keep a worktree offers Keep for 7 days and minmacs keep with its path", @"keep Keep for 7 days yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", a.suggest.action, a.suggest.title, YN([a.suggest.target isEqualToString:gAskSpike]), YN([a.suggest.command isEqualToString:[@"minmacs keep " stringByAppendingString:path]] && [path hasSuffix:@"/trees/old-spike"])]);
    a = MMAskTier0(@"keep :3001", w);
    T(@"ask keep: keep a server offers Keep for 4 hours and minmacs keep with its port", @"Keep for 4 hours minmacs keep 3001", [NSString stringWithFormat:@"%@ %@", a.suggest.title, a.suggest.command]);
    a = MMAskTier0(@"keep DerivedData", w);
    T(@"ask keep: keep a cache offers Keep for 7 days and minmacs keep with its path", @"Keep for 7 days yes", [NSString stringWithFormat:@"%@ %@", a.suggest.title, YN([a.suggest.command hasPrefix:@"minmacs keep /"] && [a.suggest.command hasSuffix:@"/library/DerivedData"])]);
    // minmacs keep finds what each suggestion names, and nothing else.
    MMFinding *byPort = MMKeepFind(s, @"3001"), *byColon = MMKeepFind(s, @":3001"), *byPath = MMKeepFind(s, path), *byName = MMKeepFind(s, @"derivedData");
    T(@"ask keep: minmacs keep finds a server by its port, a worktree by its path and a cache by its name, and nothing for what is none of them", @"locohost:server:app#dev locohost:server:app#dev yes noonoo:clutter:derived-data none none",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", byPort.findingID, byColon.findingID, YN([byPath.findingID isEqualToString:gAskSpike]), byName.findingID,
       MMKeepFind(s, @"Chat").findingID ?: @"none", MMKeepFind(s, @"9999").findingID ?: @"none"]);
    a = MMAskTier0(@"keep chat", w);
    T(@"ask keep: an app is not kept here, and the answer says why", @"no MinMacs keeps servers, worktrees and caches. Chat is none of them.", [NSString stringWithFormat:@"%@ %@", YN(a.suggest != nil), a.answer]);
    w.row = @"locohost:server:app#dev";
    a = MMAskTier0(@"keep this", w);
    T(@"ask keep: keep this means the row whose story shows", @"locohost:server:app#dev", a.suggest.target ?: @"none");
    w.row = nil;
    a = MMAskTier0(@"undo the last one", w);
    T(@"ask undo: undo the last one offers Undo for the newest thing that can be taken back, and its verb", @"undo Undo r-a1 minmacs restore r-a1 Stopped :3000 Vite fix-auth-redirect. Undo starts it again.",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", a.kind, a.suggest.title, a.suggest.target, a.suggest.command, Entries(a)]);
    a = MMAskTier0(@"undo chat", w);
    T(@"ask undo: undo chat finds the quit", @"r-q minmacs restore r-q", [NSString stringWithFormat:@"%@ %@", a.suggest.target, a.suggest.command]);
    a = MMAskTier0(@"undo zzqx", w);
    T(@"ask undo: nothing that matches is said so, with no button", @"no", YN(a.suggest != nil));
    T(@"ask: no answer acted: no record was taken back and nothing was kept", before, Counts());

    // Anything else: the honest fallback, with three questions it can answer. Never a made-up answer.
    a = MMAskTier0(@"is it going to rain tomorrow", w);
    T(@"ask unknown: a question no rule knows gets the fallback, three examples, no entry and no button", @"unknown I can't answer that without the model yet. 3 0 no",
      [NSString stringWithFormat:@"%@ %@ %lu %lu %@", a.kind, a.answer, (unsigned long)a.examples.count, (unsigned long)a.entries.count, YN(a.suggest != nil)]);
    T(@"ask unknown: its first example names something MinMacs did here", @"Why did you stop :3000 Vite fix-auth-redirect?", a.examples.firstObject);
    for (NSString *q in a.examples) {
        MMWindowAnswer *x = MMAskTier0(q, w);
        if ([x.kind isEqualToString:@"unknown"]) T(@"ask unknown: every example is a question a rule answers", @"answered", q);
    }
    T(@"ask: the same question and world give the same answer", @"yes", YN([MMAskJSON(MMAskTier0(@"why did you stop :3000", w)) isEqual:MMAskJSON(MMAskTier0(@"why did you stop :3000", w))]));
    T(@"ask: an empty question is none, and a long one is cut at 1000 characters", @"yes 1000",
      [NSString stringWithFormat:@"%@ %lu", YN(MMAskQuestion(@"  \n ") == nil), (unsigned long)MMAskQuestion([@"" stringByPaddingToLength:1500 withString:@"ab " startingAtIndex:0]).length]);

    // The ask's row, and its entry in the log.
    MMAskLog(MMAskTier0(@"why did you stop :3000", w), @"cli");
    MMAskLog(MMAskTier0(@"is it going to rain", w), @"window");
    NSArray<MMLogEntry *> *asks = [MMLog.shared rows:@[MMLogAskTable] before:0 limit:10];
    NSDictionary *b = asks.lastObject.body;
    T(@"ask row: each ask is a row of the ask table with the question, the kind, the answer, who answered and who asked", @"2 | answer answeredBy by kind question | why rules cli",
      [NSString stringWithFormat:@"%lu | %@ | %@ %@ %@", (unsigned long)asks.count, [[b.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "], b[@"kind"], b[@"answeredBy"], b[@"by"]]);
    MMWindowLog *log = MMWindowLogRead(MMLog.shared, NSDate.date, 10, 0);
    T(@"ask row: the log tells each ask, with who asked and that no model answered", @"ask Asked “is it going to rain”. It had no answer without the model. by you in the window | ask Asked “why did you stop :3000”. Answered from what MinMacs knows, with no model. from the command line",
      [NSString stringWithFormat:@"%@ %@ %@ | %@ %@ %@", log.entries[0].kind, log.entries[0].sentence, log.entries[0].who, log.entries[1].kind, log.entries[1].sentence, log.entries[1].who]);
}

/// The window's controller: an ask answers in a later model and writes its row, nothing acts before a press, Keep
/// keeps through MMKeep with its row by the window, Back to the log lets the answer go, and main runs no query.
static void AskController(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    dispatch_queue_t q = dispatch_queue_create("no.guerrilla.minmacs.test.ask", DISPATCH_QUEUE_SERIAL);
    // dispatch_sync runs its block on the calling thread, main here, so the checks' own reads go to another thread.
    void (^off)(dispatch_block_t) = ^(dispatch_block_t work) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(q, ^{ work(); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    };
    off(^{ AskRows(); });
    NSUInteger queries = MMLogMainThreadQueries(), writes = MMLogMainThreadWrites();
    MMWindowController *c = [MMWindowController new];
    WLogin *login = [WLogin new];
    c.shell = login;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    [c setOpen:YES];
    MMSnapshot *s = SnapshotAt(1);
    [c take:s];
    Spin(20, ^BOOL { return models.count >= 1; });
    NSString *spike = nil;
    for (MMWindowRow *r in Rows(models.lastObject)) if ([r.name hasSuffix:@"old-spike"]) spike = r.key;
    __block NSString *before = nil;
    off(^{ before = Counts(); });

    [c windowAsk:@"keep old-spike" row:nil];
    BOOL got = Spin(20, ^BOOL { return [models.lastObject.answer.kind isEqualToString:@"keep"]; });
    MMWindowAnswer *a = models.lastObject.answer;
    __block NSString *after = nil;
    __block NSArray<MMLogEntry *> *asks = nil;
    Spin(1, ^BOOL { off(^{ asks = [MMLog.shared rows:@[MMLogAskTable] before:0 limit:10]; }); return asks.count > 0; });
    off(^{ after = Counts(); });
    T(@"ask controller: an ask answers in a later model with the button, and writes its row by the window", @"yes keep Keep for 7 days 1 1 window",
      [NSString stringWithFormat:@"%@ %@ %@ %ld %lu %@", YN(got), a.kind, a.suggest.title, (long)a.serial, (unsigned long)asks.count, asks.firstObject.body[@"by"]]);
    T(@"ask controller: nothing acts before the press", before, after);

    // The press: MMKeep by the expert's stable key, for 7 days, with its row by the window, and the button gives way.
    [c windowKeep:a.suggest.target];
    got = Spin(20, ^BOOL { return models.lastObject.answer.suggest.note.length > 0; });
    MMFinding *f = [s finding:spike];
    NSDate *until = [MMKeep keptUntil:f.stableKey expert:@"workforest"];
    __block MMLogEntry *keep = nil;
    off(^{ keep = [MMLog.shared rows:@[MMLogKeepTable] before:0 limit:10].firstObject; });
    T(@"ask controller: Keep keeps it for 7 days through MMKeep, with its row by the window, and says so in the button's place", @"yes yes window Kept for 7 days. No rule acts on it until then.",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(got), YN(until && fabs(until.timeIntervalSinceNow - 7 * 86400) < 120), keep.body[@"by"], models.lastObject.answer.suggest.note]);

    // what is: the answer names the row, which the window makes active.
    [c windowAsk:@"what is :3001" row:nil];
    got = Spin(20, ^BOOL { return [models.lastObject.answer.kind isEqualToString:@"about"]; });
    T(@"ask controller: what is :3001 names its row, and the serial moves on", @"yes locohost:server:app#dev 2", [NSString stringWithFormat:@"%@ %@ %ld", YN(got), models.lastObject.answer.row, (long)models.lastObject.answer.serial]);
    [c windowAsk:@"keep this" row:@"locohost:server:app#dev"];
    got = Spin(20, ^BOOL { return models.lastObject.answer.serial == 3; });
    T(@"ask controller: keep this keeps the row whose story shows", @"yes Keep for 4 hours", [NSString stringWithFormat:@"%@ %@", YN(got), models.lastObject.answer.suggest.title]);
    [c windowAskBack];
    got = Spin(20, ^BOOL { return models.lastObject.answer == nil; });
    T(@"ask controller: Back to the log lets the answer go", @"yes", YN(got));
    [c windowAsk:@"   " row:nil];
    Spin(0.3, ^BOOL { return NO; });
    T(@"ask controller: an empty question asks nothing", @"nil", models.lastObject.answer ? @"answer" : @"nil");
    T(@"ask controller: main ran no query and wrote no row", @"0 0", [NSString stringWithFormat:@"%lu %lu",
      (unsigned long)(MMLogMainThreadQueries() - queries), (unsigned long)(MMLogMainThreadWrites() - writes)]);
    [c windowAsk:@"what would you clean now" row:nil];
    Spin(20, ^BOOL { return [models.lastObject.answer.kind isEqualToString:@"plan"]; });
    [c setOpen:NO];
    [c setOpen:YES];
    [c take:SnapshotAt(2)];
    Spin(20, ^BOOL { return models.lastObject.generation == 2; });
    T(@"ask controller: a closed window lets its answer go", @"nil", models.lastObject.answer ? @"answer" : @"nil");
    [c setOpen:NO];
}
