// The fixture day of 54-a.html, in MMSheet objects. Minutes are relative to now, as the prototype counts from 16:42.
#import "UI/Sheet/MMSheetFixture.h"

static const uint64_t MB = 1000 * 1000, GB = 1000 * MB;

static NSDate *At(NSDate *now, double minutes) { return [now dateByAddingTimeInterval:minutes * 60]; }

static NSArray<MMLaneSpan *> *Spans(NSDate *now, NSArray<NSArray *> *list) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSArray *s in list) {
        NSDate *end = s[1] == NSNull.null ? nil : At(now, [s[1] doubleValue]);
        [out addObject:[MMLaneSpan kind:(MMLaneKind)[s[2] integerValue] start:At(now, [s[0] doubleValue]) end:end]];
    }
    return out;
}

static MMHold *Hold(MMHoldKind kind, NSString *label, NSString *detail, MMRowMark mark) {
    MMHold *h = [MMHold new];
    h.kind = kind; h.label = label; h.detail = detail; h.mark = mark;
    return h;
}

static MMLaneNext *Next(MMNextStyle style, NSString *line, NSString *sub, NSDate *at) {
    MMLaneNext *n = [MMLaneNext new];
    n.style = style; n.line = line; n.sub = sub; n.at = at;
    return n;
}

static MMActionSpec *Act(NSString *title, NSString *tail) {
    return [MMActionSpec title:title tail:tail run:^(BOOL option) {}];
}

static MMCardSpec *Card(NSString *title, NSString *word, NSString *text, MMRowMark mark, NSArray<NSArray *> *facts) {
    MMCardSpec *c = [MMCardSpec new];
    c.title = title; c.statusWord = word; c.statusText = text; c.mark = mark;
    NSMutableArray *fs = [NSMutableArray new];
    for (NSArray *f in facts) [fs addObject:[MMCardFact label:f[0] value:f[1]]];
    c.facts = fs;
    c.actions = @[Act(@"Go to Tab", nil), Act(@"Open in Editor", nil)];
    return c;
}

static MMServerSpan *Server(NSDate *now, double from, double to, BOOL busy) {
    MMServerSpan *s = [MMServerSpan new];
    s.busy = busy; s.start = At(now, from); s.end = to == 0 ? nil : At(now, to);
    return s;
}

static MMLaneMark *Mark(NSDate *now, MMLaneMarkKind kind, double at, NSString *label) {
    MMLaneMark *m = [MMLaneMark new];
    m.kind = kind; m.at = At(now, at); m.label = label;
    return m;
}

static MMLane *Lane(NSString *lid, NSString *name, NSString *where, NSString *tool, MMLaneState state) {
    MMLane *l = [MMLane new];
    l.laneID = lid; l.name = name; l.where = where; l.tool = tool; l.state = state;
    l.spans = @[]; l.servers = @[]; l.marks = @[]; l.holds = @[];
    l.actions = @[Act(@"Go to Tab", nil), Act(@"Open in Editor", nil)];
    return l;
}

static MMSheetRule *Rule(NSString *rid, NSString *title, MMSheetMode mode, NSString *explain, NSString *preview,
                         NSArray<NSString *> *values, NSInteger value, NSString *expert) {
    MMSheetRule *r = [MMSheetRule new];
    r.ruleID = rid; r.title = title; r.mode = mode; r.explain = explain; r.preview = preview;
    r.valueTitles = values; r.value = value; r.expert = expert;
    return r;
}

static MMSheetRow *Row(NSString *name, NSString *detail, NSString *value, NSString *value2, MMRowMark mark) {
    MMSheetRow *r = [MMSheetRow new];
    r.name = name; r.detail = detail; r.value = value; r.value2 = value2; r.mark = mark; r.actions = @[];
    return r;
}

static MMSheetGroup *Group(NSString *title, NSArray<MMSheetRow *> *rows) {
    MMSheetGroup *g = [MMSheetGroup new]; g.title = title; g.rows = rows; return g;
}

static MMPerfRow *App(NSString *name, NSString *bundle, double cpu, double gb, NSString *reason) {
    MMPerfRow *r = [MMPerfRow new];
    r.name = name; r.bundleID = bundle; r.cpu = cpu; r.memory = (uint64_t)(gb * GB); r.reason = reason;
    r.agents = @[]; r.actions = @[Act(@"Quit", nil), Act(@"Always Keep", nil)];
    return r;
}

static MMPerfRow *AgentLoad(NSString *lane, NSString *name, double cpu, NSString *state) {
    MMPerfRow *r = [MMPerfRow new];
    r.name = name; r.laneID = lane; r.cpu = cpu; r.reason = state; r.agents = @[]; r.actions = @[];
    return r;
}

MMSheet *MMSheetFixture(NSDate *now) {
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *nine = [cal dateBySettingHour:9 minute:0 second:0 ofDate:now options:0] ?: At(now, -462);
    NSNull *open = NSNull.null;
    NSMutableArray<MMLane *> *lanes = [NSMutableArray new];

    MMLane *lj = Lane(@"ws:lexicon-judge", @"lexicon-judge", @"tmux pane lexicon:1", @"claude-code", MMLaneStateWaiting);
    lj.spans = Spans(now, @[@[@-150, @-3, @(MMLaneWorking)], @[@-3, open, @(MMLaneWaiting)]]);
    lj.next = Next(MMNextAsks, @"Asks you", @"Allow npm run build?", nil);
    lj.holds = @[Hold(MMHoldAgent, @"Claude Code", @"waits for you", MMRowMarkBlocked), Hold(MMHoldWorktree, @"lexicon-judge", @"1 GB", MMRowMarkQuiet)];
    lj.actions = @[Act(@"Go to Tab", @"tmux"), Act(@"Open in Editor", nil)];
    lj.card = Card(@"lexicon-judge", @"Asks you.", @"Claude Code waits for an answer: Allow npm run build?", MMRowMarkBlocked,
                   @[@[@"Agent", @"Claude Code, tmux pane lexicon:1"], @[@"Worktree", @"lexicon-judge, 1 GB"], @[@"Git", @"2 commits not in main"]]);
    [lanes addObject:lj];

    MMLane *s3 = Lane(@"ws:speed-3", @"speed-3", @"cmux tab speed-3", @"claude-code", MMLaneStateWorking);
    s3.spans = Spans(now, @[@[@-300, @-190, @(MMLaneWorking)], @[@-190, @-150, @(MMLaneIdle)], @[@-150, @-30, @(MMLaneWorking)],
                            @[@-30, @-2, @(MMLaneIdle)], @[@-2, open, @(MMLaneWorking)]]);
    s3.servers = @[Server(now, -290, 0, YES)];
    s3.marks = @[Mark(now, MMLaneMarkPROpen, -60, @"PR #214 opened as a draft")];
    s3.next = Next(MMNextPlain, @"Working 2 m", @"2 subagents", nil);
    MMHold *sub1 = Hold(MMHoldAgent, @"subagent", @"working", MMRowMarkWorking); sub1.subagent = YES;
    MMHold *sub2 = Hold(MMHoldAgent, @"subagent", @"working", MMRowMarkWorking); sub2.subagent = YES;
    s3.holds = @[Hold(MMHoldAgent, @"Claude Code", @"working", MMRowMarkWorking), sub1, sub2,
                 Hold(MMHoldServer, @":3000", @"next dev, in use", MMRowMarkWorking), Hold(MMHoldServer, @":5173", @"vite, in use", MMRowMarkWorking),
                 Hold(MMHoldServer, @":5174", @"vite preview, in use", MMRowMarkWorking), Hold(MMHoldPR, @"#214", @"draft", MMRowMarkQuiet),
                 Hold(MMHoldCache, @"1.3 GB", @"node_modules", MMRowMarkQuiet), Hold(MMHoldBrowser, @"Chrome for Testing", @"spared", MMRowMarkQuiet)];
    s3.actions = @[Act(@"Go to Tab", @"cmux"), Act(@"Stop Servers", @"3"), Act(@"Open PR", @"#214"), Act(@"Open in Editor", nil)];
    s3.card = Card(@"speed-3", @"Working.", @"Claude Code works here with 2 subagents. Its 3 servers are in use.", MMRowMarkWorking,
                   @[@[@"Agent", @"Claude Code, cmux tab speed-3"], @[@"Worktree", @"speed-3-base, 2.6 GB"], @[@"Git", @"3 commits not in main"],
                     @[@"PR", @"#214, draft"], @[@"Servers", @":3000 next dev, :5173 vite, :5174 vite preview"]]);
    [lanes addObject:s3];

    MMLane *lc = Lane(@"ws:bp-lane-c", @"bp-lane-c", @"cmux tab bp-lane-c", @"claude-code", MMLaneStateWorking);
    lc.spans = Spans(now, @[@[@-200, @-60, @(MMLaneWorking)], @[@-60, @-14, @(MMLaneIdle)], @[@-14, open, @(MMLaneWorking)]]);
    lc.servers = @[Server(now, -190, 0, YES)];
    lc.next = Next(MMNextPlain, @"Working 14 m", @"no PR yet", nil);
    lc.holds = @[Hold(MMHoldAgent, @"Claude Code", @"working", MMRowMarkWorking), Hold(MMHoldServer, @":4100", @"phoenix, in use", MMRowMarkWorking),
                 Hold(MMHoldCache, @"640 MB", @".next", MMRowMarkQuiet)];
    [lanes addObject:lc];

    MMLane *md = Lane(@"ws:media-scope", @"media-scope", @"Codex app", @"codex", MMLaneStateWorking);
    md.spans = Spans(now, @[@[@-95, @-50, @(MMLaneWorking)], @[@-50, @-6, @(MMLaneIdle)], @[@-6, open, @(MMLaneWorking)]]);
    md.next = Next(MMNextPlain, @"Tests running", @"working 6 m", nil);
    md.holds = @[Hold(MMHoldAgent, @"Codex", @"working", MMRowMarkWorking), Hold(MMHoldWorktree, @"media-scope", @"1.4 GB", MMRowMarkQuiet)];
    [lanes addObject:md];

    MMLane *ic = Lane(@"ws:studio-icons", @"studio-icons", @"Cursor, studio window", @"cursor", MMLaneStateWorking);
    ic.spans = Spans(now, @[@[@-240, @-200, @(MMLaneWorking)], @[@-200, @-1, @(MMLaneIdle)], @[@-1, open, @(MMLaneWorking)]]);
    ic.next = Next(MMNextPlain, @"Working 1 m", @"main checkout", nil);
    ic.holds = @[Hold(MMHoldAgent, @"Cursor", @"working", MMRowMarkWorking)];
    [lanes addObject:ic];

    MMLane *pa = Lane(@"ws:studio-parity", @"studio-parity", @"cmux tab studio-parity", @"claude-code", MMLaneStateIdle);
    pa.spans = Spans(now, @[@[@-400, @-40, @(MMLaneWorking)], @[@-40, open, @(MMLaneIdle)]]);
    pa.servers = @[Server(now, -380, -40, YES), Server(now, -40, 0, NO)];
    pa.marks = @[Mark(now, MMLaneMarkPROpen, -120, @"PR #209 opened")];
    pa.next = Next(MMNextQuiet, @"Idle 40 m", @"#209 checks pass", nil);
    pa.holds = @[Hold(MMHoldAgent, @"Claude Code", @"idle", MMRowMarkQuiet), Hold(MMHoldServer, @":3334", @"sanity, unused 40 m", MMRowMarkQuiet),
                 Hold(MMHoldPR, @"#209", @"open", MMRowMarkQuiet)];
    [lanes addObject:pa];

    MMLane *au = Lane(@"ws:fix-auth-redirect", @"fix auth redirect", @"Codex app", @"codex", MMLaneStateReady);
    au.spans = Spans(now, @[@[@-330, @-120, @(MMLaneWorking)], @[@-60, open, @(MMLaneReady)]]);
    au.servers = @[Server(now, -320, -118, YES), Server(now, -118, 0, NO)];
    au.marks = @[Mark(now, MMLaneMarkFinished, -120, @"Codex finished at 14:42"), Mark(now, MMLaneMarkPRMerged, -120, @"PR #207 merged")];
    au.readySince = At(now, -60);
    au.next = Next(MMNextReady, @"Ready 1 h", @"waits for your press", nil);
    au.holds = @[Hold(MMHoldAgent, @"Codex", @"finished", MMRowMarkGoes), Hold(MMHoldServer, @":4000", @"phoenix, unused 2 h", MMRowMarkQuiet),
                 Hold(MMHoldPR, @"#207", @"merged", MMRowMarkGoes), Hold(MMHoldCache, @"1.8 GB", @"node_modules", MMRowMarkQuiet)];
    au.freeBytes = 2100 * MB;
    au.actions = @[Act(@"Wrap Up", @"2.1 GB"), Act(@"Keep", nil), Act(@"Open in Editor", nil)];
    au.card = Card(@"fix auth redirect", @"Ready.", @"Codex finished at 14:42 and PR #207 merged. Wrap Up stops :4000, removes the worktree after saving .env, and frees 2.1 GB.", MMRowMarkGoes,
                   @[@[@"Agent", @"Codex, finished"], @[@"Worktree", @"auth-redirect, squash-merged"], @[@"PR", @"#207, merged"], @[@"Servers", @":4000 phoenix, unused 2 h"]]);
    [lanes addObject:au];

    MMLane *le = Lane(@"ws:lane-e-sort", @"lane-e-sort", @"no agent", @"", MMLaneStateReady);
    le.marks = @[Mark(now, MMLaneMarkPRMerged, -1800, @"PR #201 merged yesterday")];
    le.readySince = At(now, -1740);
    le.next = Next(MMNextReady, @"Ready 1 d", @"waits for your press", nil);
    le.holds = @[Hold(MMHoldWorktree, @"lane-e-sort", @"merged", MMRowMarkGoes), Hold(MMHoldCache, @"2.3 GB", @"node_modules", MMRowMarkQuiet)];
    le.freeBytes = 2300 * MB;
    le.actions = @[Act(@"Wrap Up", @"2.3 GB"), Act(@"Keep", nil)];
    [lanes addObject:le];

    NSMutableArray<MMLeftover *> *left = [NSMutableArray new];
    NSArray *lo = @[@[@":6006 storybook", @"idle 3 d", @(520 * MB)], @[@"bp8-sweep-studio403", @"stale 34 d", @(1100 * MB)],
                    @[@"sb-fieldsets", @"merged, no owner", @(940 * MB)], @[@"w19-fire", @"merged, no owner", @(610 * MB)],
                    @[@"DerivedData", @"4 gone projects", @(14200 * MB)], @[@"npm cache", @"npm cleans it", @(6100 * MB)],
                    @[@"Docker build cache", @"Docker prunes it", @(4200 * MB)], @[@"Playwright browsers", @"old versions", @(3300 * MB)]];
    for (NSArray *x in lo) {
        MMLeftover *l = [MMLeftover new];
        l.leftoverID = [@"left:" stringByAppendingString:x[0]]; l.name = x[0]; l.detail = x[1]; l.bytes = [x[2] unsignedLongLongValue];
        [left addObject:l];
    }

    MMSheet *s = [MMSheet new];
    s.builtAt = now; s.dayStart = nine;
    s.headLine = @"5 agents working · lid can close";
    s.lanes = lanes; s.leftovers = left;
    s.wrapUpAll = Act(@"Wrap Up 2 Workstreams", @"4.4 GB");
    s.cleanUpLeftovers = Act(@"Clean Up Leftovers", @"31 GB");
    s.wrapUpRule = Rule(@"wrapup", @"Wrap Up", MMSheetModeAsk,
                        @"Ask shows a workstream as ready once its PR merges and its agents finish. Nothing happens until you press Wrap Up.",
                        @"2 workstreams are ready and wait for your press.", @[@"1 h", @"1 day", @"1 week"], 0, @"workforest");
    s.waitingCount = 1;
    s.accessibilityLabel = @"MinMacs, 1 agent waits for you, 2 workstreams ready";

    MMSheetPerformance *p = [MMSheetPerformance new];
    p.cpuPercent = 62; p.cpuFreed = 22; p.memoryUsed = 29 * GB; p.memoryTotal = 32 * GB; p.memoryFreed = (uint64_t)(9.3 * GB); p.pressure = @"warn";
    MMPerfRow *cmux = App(@"cmux", @"com.cmuxterm.app", 44, 6.8, @"agents work in it");
    cmux.agents = @[AgentLoad(@"ws:speed-3", @"speed-3", 18, @"working"), AgentLoad(@"ws:bp-lane-c", @"bp-lane-c", 11, @"working"),
                    AgentLoad(@"ws:studio-parity", @"studio-parity", 1, @"idle")];
    MMPerfRow *cursor = App(@"Cursor", @"com.todesktop.230313mzl4w4u92", 12, 3.1, @"an agent works in it");
    cursor.agents = @[AgentLoad(@"ws:studio-icons", @"studio-icons", 6, @"working")];
    MMPerfRow *codex = App(@"Codex", @"com.openai.codex", 7, 1.4, @"agents work in it");
    codex.agents = @[AgentLoad(@"ws:media-scope", @"media-scope", 7, @"working"), AgentLoad(@"ws:fix-auth-redirect", @"fix auth redirect", 0, @"finished")];
    MMPerfGroup *close = [MMPerfGroup new]; close.title = @"Will close";
    close.rows = @[App(@"Google Chrome", @"com.google.Chrome", 21, 8.7, @"14 noise tabs"), App(@"Spotify", @"com.spotify.client", 1, 0.578, nil)];
    MMPerfGroup *unsorted = [MMPerfGroup new]; unsorted.title = @"Unsorted";
    unsorted.rows = @[App(@"Raycast", @"com.raycast.macos", 0.4, 0.21, nil), App(@"FigmaAgent", @"com.figma.agent", 0, 0.013, nil)];
    MMPerfGroup *kept = [MMPerfGroup new]; kept.title = @"Kept";
    kept.rows = @[cmux, cursor, codex, App(@"Docker", @"com.docker.docker", 6, 2.4, @"you keep it"), App(@"Finder", @"com.apple.finder", 0.3, 0.18, nil)];
    MMPerfGroup *spared = [MMPerfGroup new]; spared.title = @"Spared";
    spared.rows = @[App(@"Chrome for Testing", @"com.google.chrome.for.testing", 9, 1.2, @"speed-3 tests in it")];
    p.groups = @[close, unsorted, kept, spared];
    p.now = Act(@"MinMacs Now", @"2 apps, 9.3 GB");
    p.restore = Act(@"Restore", @"3 apps");
    s.performance = p;

    MMSheetSettings *st = [MMSheetSettings new];
    st.rules = @[s.wrapUpRule,
                 Rule(@"apps", @"Close apps", MMSheetModeAuto, @"Auto closes the apps on Will close when the Mac's load stays above the line you pick.",
                      @"Next: Auto closes Google Chrome's noise tabs and Spotify if load stays above 70 %.", @[@"60 %", @"70 %", @"80 %", @"90 %"], 1, @"minmacs"),
                 Rule(@"leftovers", @"Leftovers", MMSheetModeAuto, @"Auto moves what nobody owns to the Trash or runs its tool's own clean, and Undo brings it back.",
                      @"Next: Auto cleans up 8 leftovers on Sunday.", @[@"every night", @"every Sunday", @"monthly"], 1, @"noonoo")];
    st.lidOn = YES; st.lidNote = @"It stops at 20 % battery, off Wi-Fi or when the Mac runs hot.";
    st.oneIcon = YES; st.openAtLogin = YES; st.advanced = NO;
    s.settings = st;

    MMSheetList *ag = [MMSheetList new]; ag.tab = MMSheetTabAgents; ag.headline = @"8 agents · 5 working · 1 waits for you";
    ag.rule = Rule(@"agents", @"Agents that wait", MMSheetModeAsk, @"Ask tells you when an agent has waited for an answer.", nil, @[@"1 min", @"3 min", @"10 min"], 1, @"core");
    ag.groups = @[Group(@"Waits for you", @[Row(@"lexicon-judge", @"Claude Code · Allow npm run build?", @"3 m", nil, MMRowMarkBlocked)]),
                  Group(@"Working", @[Row(@"speed-3", @"Claude Code · 2 subagents", @"18 %", nil, MMRowMarkWorking), Row(@"bp-lane-c", @"Claude Code", @"11 %", nil, MMRowMarkWorking),
                                      Row(@"media-scope", @"Codex · tests running", @"7 %", nil, MMRowMarkWorking), Row(@"studio-icons", @"Cursor", @"6 %", nil, MMRowMarkWorking)]),
                  Group(@"Idle and finished", @[Row(@"studio-parity", @"Claude Code · idle 40 m", @"1 %", nil, MMRowMarkQuiet), Row(@"fix auth redirect", @"Codex · finished 14:42", @"0 %", nil, MMRowMarkGoes)])];
    MMSheetList *sv = [MMSheetList new]; sv.tab = MMSheetTabServers; sv.headline = @"8 servers · 4 in use · 2.6 GB";
    sv.rule = Rule(@"servers", @"Unused servers", MMSheetModeAuto, @"Auto stops a dev server that nobody has used for the time you pick.", @"Next: Auto stops :4000 in 22 m.", @[@"30 min", @"1 h", @"2 h", @"4 h"], 2, @"locohost");
    NSMutableArray *beat = [NSMutableArray new]; for (int i = 0; i < 60; i++) [beat addObject:@((i * 37 % 11) / 10.0)];
    MMSheetRow *r3000 = Row(@":3000", @"next dev · speed-3", @"412 MB", @"busy", MMRowMarkWorking); r3000.heartbeat = beat;
    sv.groups = @[Group(@"In use", @[r3000, Row(@":5173", @"vite · speed-3", @"188 MB", @"busy", MMRowMarkWorking), Row(@":4100", @"phoenix · bp-lane-c", @"260 MB", @"busy", MMRowMarkWorking)]),
                  Group(@"Unused", @[Row(@":4000", @"phoenix · fix auth redirect", @"290 MB", @"2 h", MMRowMarkQuiet), Row(@":3334", @"sanity · studio-parity", @"640 MB", @"40 m", MMRowMarkQuiet),
                                     Row(@":6006", @"storybook · no workstream", @"520 MB", @"3 d", MMRowMarkQuiet)]),
                  Group(@"Services", @[Row(@":5432", @"postgres · Docker", @"140 MB", @"kept", MMRowMarkQuiet)])];
    MMSheetList *wt = [MMSheetList new]; wt.tab = MMSheetTabWorktrees; wt.headline = @"14 worktrees · 6.2 GB merged";
    wt.rule = Rule(@"worktrees", @"Merged worktrees", MMSheetModeAsk, @"Ask shows a merged worktree as ready to remove. Its .env files are saved first.", nil, @[@"1 h", @"1 day", @"1 week"], 1, @"workforest");
    wt.groups = @[Group(@"Merged", @[Row(@"auth-redirect", @"squash-merged · fix auth redirect", @"1.8 GB", nil, MMRowMarkGoes), Row(@"lane-e-sort", @"merged · 1 d ago", @"2.3 GB", nil, MMRowMarkGoes),
                                     Row(@"sb-fieldsets", @"merged · no owner", @"940 MB", nil, MMRowMarkGoes)]),
                  Group(@"In use", @[Row(@"speed-3-base", @"speed-3", @"2.6 GB", nil, MMRowMarkWorking), Row(@"studio-parity", @"studio-parity", @"1.9 GB", nil, MMRowMarkQuiet)]),
                  Group(@"Stale", @[Row(@"bp7-studio-dogfood", @"1 commit not in main", @"3.2 GB", nil, MMRowMarkQuiet)])];
    MMSheetList *dk = [MMSheetList new]; dk.tab = MMSheetTabDisk; dk.headline = @"38 GB of caches · 28 GB safe to clean";
    dk.rule = Rule(@"disk", @"Safe caches", MMSheetModeAsk, @"Ask shows the caches that are safe to clean. Each goes to the Trash or through its tool's own command.", nil, @[@"every night", @"every Sunday", @"monthly"], 1, @"noonoo");
    dk.groups = @[Group(@"Safe to clean", @[Row(@"Xcode DerivedData", @"7 projects, 4 gone", @"14.2 GB", nil, MMRowMarkQuiet), Row(@"node_modules", @"in merged worktrees", @"9.8 GB", nil, MMRowMarkQuiet),
                                            Row(@"npm cache", @"npm cleans it", @"6.1 GB", nil, MMRowMarkQuiet)]),
                  Group(@"Ask first", @[Row(@"Docker build cache", @"Docker prunes it", @"4.2 GB", nil, MMRowMarkQuiet), Row(@"Playwright browsers", @"old versions", @"3.3 GB", nil, MMRowMarkQuiet)]),
                  Group(@"Report only", @[Row(@"Simulator runtimes", @"report only", @"800 MB", nil, MMRowMarkQuiet)])];
    s.advanced = @{@(MMSheetTabAgents): ag, @(MMSheetTabServers): sv, @(MMSheetTabWorktrees): wt, @(MMSheetTabDisk): dk};
    return s;
}

MMSheet *MMSheetFixtureEmpty(NSDate *now) {
    MMSheet *s = MMSheetFixture(now);
    s.lanes = @[]; s.leftovers = @[]; s.wrapUpAll = nil; s.cleanUpLeftovers = nil; s.waitingCount = 0;
    s.headLine = @"No agents working";
    s.accessibilityLabel = @"MinMacs, nothing waits for you";
    return s;
}
