// Ask MinMacs, tier 1: what the rules cannot answer goes to Claude. Included by window.m after ask.m, and run by
// test/ask.sh as `ask-claude` and `ask-claude-controller`, with MINMACS_CLAUDE naming test/ask/fakeclaude.py, so the
// real claude never runs. ASK_FAKE_MODE picks the fake's answer, ASK_FAKE_SENT gets what it was sent. Every row goes
// to this tool's own MINMACS_HOME. Nothing here acts.
#import "Core/Review/MMReview.h"

static NSString *FakeSent(void) {
    NSString *p = NSProcessInfo.processInfo.environment[@"ASK_FAKE_SENT"];
    return p ? ([NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil] ?: @"") : @"";
}
static NSInteger FakeCalls(void) {
    NSString *p = [NSProcessInfo.processInfo.environment[@"ASK_FAKE_SENT"] stringByAppendingString:@".calls"];
    NSString *s = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil] ?: @"";
    return (NSInteger)[[s componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]].count;
}
static NSDictionary *FakeLastCall(void) {
    NSString *p = [NSProcessInfo.processInfo.environment[@"ASK_FAKE_SENT"] stringByAppendingString:@".calls"];
    NSArray *lines = [[[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil] ?: @"" componentsSeparatedByString:@"\n"]
                      filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return lines.count ? [NSJSONSerialization JSONObjectWithData:[lines.lastObject dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
}
static void FakeMode(NSString *mode) { setenv("ASK_FAKE_MODE", mode.UTF8String, 1); }

/// A world for the context alone: many long rows, a story fact that holds transcript words and a path, and a log
/// entry whose subject is a path.
static MMAskWorld *BigWorld(void) {
    MMWindowModel *m = [MMWindowModel new];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < 400; i++) {
        MMWindowRow *r = [MMWindowRow new];
        r.key = [NSString stringWithFormat:@"worktree:%ld", (long)i]; r.kind = MMWindowWorktree;
        r.name = [NSString stringWithFormat:@"feature-branch-with-a-long-name-%ld", (long)i]; r.bytes = 1000000; r.state = @"merged";
        r.facts = @[[MMWindowFact label:@"Did" value:@"TRANSCRIPT-WORDS-77 read /Users/sam/secret/notes.txt"]];
        [rows addObject:r];
    }
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = @"worktrees"; g.title = @"Worktrees"; g.side = MMWindowDisk; g.rows = rows;
    m.memoryGroups = @[]; m.diskGroups = @[g]; m.fixes = @[];
    MMWindowRing *ring = [MMWindowRing new];
    ring.memoryUsed = 20ull << 30; ring.memoryTotal = 32ull << 30; ring.diskFree = 100ull << 30; ring.diskTotal = 1000ull << 30;
    m.ring = ring;
    MMAskWorld *w = [MMAskWorld new];
    w.model = m; w.targets = @{}; w.now = NSDate.date;
    w.rows = [MMAskWorld rowsOf:MMLog.shared];
    return w;
}

static void AskClaude(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    AskRows();
    AskUndo(@"r-p", @"noonoo", @"trash", nil, @"/Users/sam/code/atlas/.next", @"done", @"proactive", @"its project is finished", nil, nil);
    MMAskWorld *w = [MMAskWorld new];
    w.model = m; w.rows = [MMAskWorld rowsOf:MMLog.shared]; w.targets = [MMAskWorld targetsOf:m snapshot:s]; w.now = NSDate.date;
    T(@"ask claude: the pref ask.claude is on by default", @"yes", YN(MMAskUsesClaude()));

    // unknown -> Claude, with its tokens, through the reviews' claude -p with every tool off.
    FakeMode(@"answer");
    MMWindowAnswer *rules = MMAskTier0(@"Hey!", w);
    NSInteger calls = FakeCalls();
    MMWindowAnswer *a = MMAskTier1(rules, w, nil, nil);
    NSDictionary *call = FakeLastCall();
    T(@"ask claude: a question the rules cannot answer goes to Claude once, and its words are the answer, answered by Claude with its tokens",
      @"unknown claude claude 1 Hello. I can say what MinMacs did, would clean or keeps. I saw 0 earlier questions. | Answered by Claude · 300 tokens | 300 no",
      [NSString stringWithFormat:@"%@ %@ %@ %ld %@ | %@ | %ld %@", rules.kind, a.kind, a.answeredBy, (long)(FakeCalls() - calls), a.answer, a.byline, (long)a.tokens, YN(a.suggest != nil)]);
    T(@"ask claude: the call is the reviews' claude -p with every tool off, at low effort, on the reviews' model, in a fresh folder of its own",
      @"tools: effort:low model:opus folder:yes", [NSString stringWithFormat:@"tools:%@ effort:%@ model:%@ folder:%@", call[@"tools"], call[@"effort"], call[@"model"],
                                                  YN([call[@"cwd"] containsString:@"/review/calls/call."])]);

    // What is sent.
    NSString *ctx = MMAskContext(@"Hey!", w, rules, nil);
    NSString *sentNow = FakeSent();
    NSString *spikePath = [w.targets[gAskSpike].command substringFromIndex:@"minmacs keep ".length];
    T(@"ask claude: what is sent holds the question, the Mac's memory and disk, the rows by group with their stays or goes line, the log's sentences and the near matches",
      @"yes yes yes yes yes yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN([ctx hasPrefix:@"The question: Hey!\n"]), YN([ctx containsString:@"This Mac now: memory "] && [ctx containsString:@" disk "]),
                                   YN([ctx containsString:@"Servers:\n- :3001 Next.js · server"]), YN([ctx containsString:@"Goes with Fix Everything"]),
                                   YN([ctx containsString:@"Quit Chat"]), YN([ctx containsString:@"The rules answer questions such as: "])]);
    T(@"ask claude: the fake got exactly that context", @"yes", YN([sentNow containsString:ctx]));
    T(@"ask claude: no path is sent: not the home folder, not a worktree's path, not a path a log entry names",
      @"no no no yes", [NSString stringWithFormat:@"%@ %@ %@ %@", YN([sentNow containsString:NSHomeDirectory()]), YN(spikePath.length && [sentNow containsString:spikePath]),
                        YN([ctx containsString:@"/Users/sam"]), YN([ctx containsString:@"a path"])]);
    MMAskWorld *big = BigWorld();
    NSArray *turns = @[[MMAskTurn question:[@"" stringByPaddingToLength:900 withString:@"q " startingAtIndex:0] answer:[@"" stringByPaddingToLength:900 withString:@"a " startingAtIndex:0]],
                       [MMAskTurn question:@"one" answer:@"two"], [MMAskTurn question:@"three" answer:@"four"], [MMAskTurn question:@"five" answer:@"six"]];
    NSString *bc = MMAskContext([@"" stringByPaddingToLength:1500 withString:@"long question " startingAtIndex:0], big, nil, turns);
    T(@"ask claude: with 400 rows, a long question and four turns, what is sent stays under 8 KB, says what was left out, and keeps the last 3 turns",
      @"yes yes 3", [NSString stringWithFormat:@"%@ %@ %lu", YN([bc lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= MMAskContextMost),
                     YN([bc containsString:@"more lines not sent"]), (unsigned long)([bc componentsSeparatedByString:@"\nQ: "].count - 1)]);
    T(@"ask claude: no story fact is sent, so no transcript words and no path from one", @"no no",
      [NSString stringWithFormat:@"%@ %@", YN([bc containsString:@"TRANSCRIPT-WORDS-77"]), YN([bc containsString:@"secret/notes"])]);

    // ACTION lines: one the rules know becomes their button; any other is dropped, and never shown.
    FakeMode(@"action");
    a = MMAskTier1(rules, w, nil, nil);
    T(@"ask claude: a last line ACTION: keep 3001 becomes the rules' own Keep for 4 hours button and verb, and is not shown",
      @"keep Keep for 4 hours locohost:server:app#dev minmacs keep 3001 no", [NSString stringWithFormat:@"%@ %@ %@ %@ %@", a.suggest.action, a.suggest.title, a.suggest.target,
                                                                          a.suggest.command, YN([a.answer containsString:@"ACTION"])]);
    NSString *before = Counts();
    FakeMode(@"badaction");
    a = MMAskTier1(rules, w, nil, nil);
    T(@"ask claude: an action no rule knows is dropped: no button, and the line is not shown", @"no I would wipe the disk.", [NSString stringWithFormat:@"%@ %@", YN(a.suggest != nil), a.answer]);
    T(@"ask claude: no answer acted", before, Counts());
    T(@"ask claude: a suggestion is parsed only from the last line, in its fixed form", @"no no",
      [NSString stringWithFormat:@"%@ %@", YN(MMAskFromClaude(rules, w, @"ACTION: keep 3001\nThat is all.", nil, 1, @"opus").suggest != nil),
       YN(MMAskFromClaude(rules, w, @"Fine.\nACTION keep 3001", nil, 1, @"opus").suggest != nil)]);

    // Claude out of reach: said honestly, with the rules' examples.
    FakeMode(@"fail");
    a = MMAskTier1(rules, w, nil, nil);
    T(@"ask claude: a signed-out claude gives the honest answer and why, with the rules' three examples",
      @"unknown rules 3 Claude isn't reachable: Not logged in · Please run /login. The rules answer the questions below.",
      [NSString stringWithFormat:@"%@ %@ %lu %@", a.kind, a.answeredBy, (unsigned long)a.examples.count, a.answer]);
    NSString *real = NSProcessInfo.processInfo.environment[@"MINMACS_CLAUDE"];
    setenv("MINMACS_CLAUDE", [NSHomeDirectory() stringByAppendingPathComponent:@"no-such-claude"].UTF8String, 1);
    a = MMAskTier1(rules, w, nil, nil);
    T(@"ask claude: a claude that cannot start says so", @"yes", YN([a.answer hasPrefix:@"Claude isn't reachable: could not start"]));
    setenv("MINMACS_CLAUDE", real.UTF8String, 1);

    // The timeout gives an honest message, in time.
    FakeMode(@"sleep");
    setenv("MINMACS_ASK_TIMEOUT", "1", 1);
    NSDate *t0 = NSDate.date;
    a = MMAskTier1(rules, w, nil, nil);
    double took = -t0.timeIntervalSinceNow;
    T(@"ask claude: a Claude too slow gives the honest message within the time limit, with the examples", @"yes yes 3 rules",
      [NSString stringWithFormat:@"%@ %@ %lu %@", YN([a.answer hasPrefix:@"Claude didn't answer within 1 seconds"]), YN(took < 4), (unsigned long)a.examples.count, a.answeredBy]);
    MMModelStop *stop = [MMModelStop new];
    setenv("MINMACS_ASK_TIMEOUT", "15", 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [stop stop]; });
    t0 = NSDate.date;
    a = MMAskTier1(rules, w, nil, stop);
    took = -t0.timeIntervalSinceNow;
    T(@"ask claude: Stop ends the call at once, and nothing comes of it", @"yes Stopped before Claude answered. Nothing was done.",
      [NSString stringWithFormat:@"%@ %@", YN(took < 4), a.answer]);
    unsetenv("MINMACS_ASK_TIMEOUT");

    // The row in the log, with the tokens.
    FakeMode(@"answer");
    MMAskLog(MMAskTier1(rules, w, nil, nil), @"cli");
    __block NSArray<MMLogEntry *> *asks = nil;
    Spin(5, ^BOOL { asks = [MMLog.shared rows:@[MMLogAskTable] before:0 limit:10]; return asks.count > 0; });
    NSDictionary *b = asks.firstObject.body;
    T(@"ask claude: the ask's row says answeredBy claude, with its tokens and model", @"claude 300 opus",
      [NSString stringWithFormat:@"%@ %@ %@", b[@"answeredBy"], b[@"tokens"], b[@"model"]]);
    MMWindowLog *log = MMWindowLogRead(MMLog.shared, NSDate.date, 10, 0);
    T(@"ask claude: the log tells it as answered by Claude, with the tokens on its quiet line", @"Asked “Hey!”. Answered by Claude. 300",
      [NSString stringWithFormat:@"%@ %ld", log.entries[0].sentence, (long)log.entries[0].tokens]);

    // The rules answer: no model call.
    calls = FakeCalls();
    MMWindowAnswer *plan = MMAskTier0(@"what would you clean now", w);
    T(@"ask claude: a question the rules answer never reaches the model", @"plan 0", [NSString stringWithFormat:@"%@ %ld", plan.kind, (long)(FakeCalls() - calls)]);
}

/// The window's controller: "Asking Claude" with Stop at once, Claude's answer in a later model, a memory of the last
/// 3 turns that a closed window lets go, Stop, the pref off, and main runs no query.
static void AskClaudeController(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    NSUInteger queries = MMLogMainThreadQueries(), writes = MMLogMainThreadWrites();
    MMWindowController *c = [MMWindowController new];
    WLogin *login = [WLogin new];
    c.shell = login;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    [c setOpen:YES];
    [c take:SnapshotAt(1)];
    Spin(20, ^BOOL { return models.count >= 1; });
    FakeMode(@"answer");

    [c windowAsk:@"Hey!" row:nil];
    BOOL asking = Spin(10, ^BOOL { return models.lastObject.answer.asking; });
    MMWindowAnswer *first = models.lastObject.answer;
    BOOL got = Spin(20, ^BOOL { return [models.lastObject.answer.answeredBy isEqualToString:@"claude"]; });
    MMWindowAnswer *a = models.lastObject.answer;
    T(@"ask claude controller: the answer says Asking Claude with Stop at once, then Claude's words come in a later model, the same ask",
      @"yes Asking Claude Stop yes 1 Answered by Claude · 300 tokens", [NSString stringWithFormat:@"%@ %@ %@ %@ %ld %@", YN(asking), first.answer, first.suggest.title, YN(got), (long)a.serial, a.byline]);
    for (NSString *q in @[@"one more", @"and again", @"once more"]) {
        NSInteger serial = models.lastObject.answer.serial;
        [c windowAsk:q row:nil];
        Spin(20, ^BOOL { return models.lastObject.answer.serial > serial && [models.lastObject.answer.answeredBy isEqualToString:@"claude"]; });
    }
    T(@"ask claude controller: each ask sends the turns before it, the last 3 at most", @"yes",
      YN([models.lastObject.answer.answer containsString:@"I saw 3 earlier questions."]));
    [c setOpen:NO];
    [c setOpen:YES];
    [c take:SnapshotAt(2)];
    Spin(20, ^BOOL { return models.lastObject.generation == 2; });
    [c windowAsk:@"after closing" row:nil];
    Spin(20, ^BOOL { return [models.lastObject.answer.question isEqualToString:@"after closing"] && [models.lastObject.answer.answeredBy isEqualToString:@"claude"]; });
    T(@"ask claude controller: a closed window lets its conversation go", @"yes", YN([models.lastObject.answer.answer containsString:@"I saw 0 earlier questions."]));

    // Stop: the call ends, the answer says so, and the ask is a row of the log.
    FakeMode(@"sleep");
    [c windowAsk:@"take your time" row:nil];
    Spin(10, ^BOOL { return models.lastObject.answer.asking && [models.lastObject.answer.question isEqualToString:@"take your time"]; });
    NSDate *t0 = NSDate.date;
    [c windowAskStop];
    got = Spin(5, ^BOOL { return [models.lastObject.answer.answer hasPrefix:@"Stopped before Claude answered"]; });
    T(@"ask claude controller: Stop stops it at once, and the answer says nothing came back", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(got), YN(-t0.timeIntervalSinceNow < 3)]);

    // The pref off: the rules' own fallback, and no call.
    FakeMode(@"answer");
    MMSetPref(MMAskClaudeKey, @NO);
    NSInteger calls = FakeCalls();
    [c windowAsk:@"Hey again" row:nil];
    Spin(20, ^BOOL { return [models.lastObject.answer.question isEqualToString:@"Hey again"]; });
    T(@"ask claude controller: with Ask uses Claude off, the rules' fallback stands and Claude is not asked", @"I can't answer that without the model yet. 0",
      [NSString stringWithFormat:@"%@ %ld", models.lastObject.answer.answer, (long)(FakeCalls() - calls)]);
    MMSetPref(MMAskClaudeKey, @YES);
    BOOL shown = NO;
    for (MMWindowSwitch *sw in models.lastObject.settings.switches) if ([sw.switchID isEqualToString:@"askclaude"] && [sw.title isEqualToString:@"Ask uses Claude"]) shown = YES;
    T(@"ask claude controller: Settings has Ask uses Claude", @"yes", YN(shown));
    T(@"ask claude controller: main ran no query and wrote no row", @"0 0", [NSString stringWithFormat:@"%lu %lu",
      (unsigned long)(MMLogMainThreadQueries() - queries), (unsigned long)(MMLogMainThreadWrites() - writes)]);
    [c setOpen:NO];
}
