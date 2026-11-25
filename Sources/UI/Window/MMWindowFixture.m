// Made-up days for the render tool and the checks, in the spirit of 195-a's Quiet, Busy and Peak.
// Nothing here is measured. Every name is invented, and the numbers only have to look like a working Mac.
#import "UI/Window/MMWindowFixtureParts.h"
#import "UI/MMFormat.h"

static const uint64_t MB = MMFixMB, GB = MMFixGB, DMB = MMFixDiskMB, DGB = MMFixDiskGB;

/// A row whose name is longer than its group's column, one per group, for the day named "long".
static MMWindowRow *Long(MMWindowRow *like, NSString *key, NSString *name, uint64_t bytes) {
    MMWindowRow *r = MMWindowFixtureRow(like.kind, key, name, like.iconHint, like.state, bytes, like.cpuPercent);
    r.hour = like.hour; r.facts = like.facts; r.quiet = like.quiet;
    // A worktree keeps its project, and is named in it as the feed names it.
    if (like.project) { r.project = like.project; r.workedAt = like.workedAt; r.nameInProject = name; r.name = [NSString stringWithFormat:@"%@ · %@", like.project, name]; }
    return r;
}

/// The same rows on a Mac where the app has run for only `filled` minutes: each row's hour holds that many.
static NSArray<MMWindowRow *> *Young(NSArray<MMWindowRow *> *rows, NSInteger filled) {
    for (MMWindowRow *r in rows) {
        if (!r.hour) continue;
        NSMutableArray *v = [r.hour mutableCopy];
        for (NSInteger i = 0; i < 60 - filled; i++) v[i] = NSNull.null;
        r.hour = v;
    }
    return rows;
}

static MMWindowFix *Fix(NSString *key, NSString *title, uint64_t memory, uint64_t disk, BOOL needsYou) {
    MMWindowFix *f = [MMWindowFix new];
    f.key = key; f.title = title; f.memoryBack = memory; f.diskBack = disk; f.needsYou = needsYou;
    return f;
}

/// Settings as the feed fills it, Shell/MMWindowRules.m: the four rules from the same words the feed uses, then This
/// Mac. There is no removal card: everything MinMacs removes keeps a way back. `picked` is the choice of each rule.
static MMWindowSettings *SettingsLike(NSArray<NSNumber *> *picked, NSDictionary<NSString *, NSString *> *notes) {
    MMWindowSettings *s = [MMWindowSettings new];
    NSMutableArray<MMWindowRule *> *rules = [NSMutableArray new];
    NSArray<NSString *> *ids = MMWindowRuleIDs();
    for (NSUInteger i = 0; i < ids.count; i++) [rules addObject:MMWindowRuleCard(ids[i], picked[i].integerValue, notes[ids[i]])];
    s.rules = rules;
    s.switches = @[MMWindowAwakeSwitch(NO, nil), MMWindowAgentsSwitch(YES, MMWindowAgentsNote(YES, 2)),
                    MMWindowLidSwitch(YES, NO, @"Working with the lid shut now."), MMWindowLoginSwitch(YES, nil), MMWindowPullsSwitch(YES), MMWindowAskClaudeSwitch(YES)];
    return s;
}

/// A working day: servers and worktrees on Careful, caches on Eager, apps Off with one app ready for a press.
static MMWindowSettings *Settings(void) {
    return SettingsLike(@[@1, @0, @1, @2], @{@"apps": MMWindowReadyNote(1)});
}

/// The welcome as the feed makes it for a person new to MinMacs, MMWindowWelcomeNow in Shell/MMWindowRules.m, with
/// the switch on or off. test/window.sh checks its facts against the feed's.
static MMWindowWelcome *Welcome(BOOL login, BOOL watched) {
    MMWindowWelcome *w = [MMWindowWelcome welcomeWithFacts:@[
        // "welcome-watched": a person who used MinMacs for more than a day before the welcome, with every rule on Careful.
        watched ? [MMWindowFact label:@"It has watched a day" value:@"MinMacs may now stop servers, remove worktrees and clean up leftovers on its own."]
                : [MMWindowFact label:@"It waits a day" value:@"For its first day MinMacs stops, quits and removes nothing on its own."],
        [MMWindowFact label:@"You set every rule" value:@"Each rule can be Off, Careful or Eager. Each starts on Careful."],
        [MMWindowFact label:@"It starts quietly" value:@"No permission is asked at launch. The Mac stays awake while agents work."]]];
    w.loginOn = login;
    return w;
}

static MMWindowHour *Hour(NSString *title, NSString *explain, MMWindowSide side, double from, double to, NSInteger filled) {
    MMWindowHour *h = [MMWindowHour new];
    h.title = title; h.explain = explain; h.side = side;
    uint32_t seed = (uint32_t)title.hash;
    NSMutableArray *v = [NSMutableArray new];
    for (NSInteger i = 0; i < 60; i++) {
        if (i < 60 - filled) { [v addObject:NSNull.null]; continue; }
        // Memory climbs fast and then slowly. Disk free falls fast and then levels.
        double t = filled > 1 ? (i - (60 - filled)) / (double)(filled - 1) : 1, eased = side == MMWindowMemory ? pow(t, 0.55) : 1 - pow(1 - t, 2.4);
        seed = seed * 1664525u + 1013904223u;
        [v addObject:@((uint64_t)(from + (to - from) * eased + (((seed >> 8) & 0xFFFF) / 65535.0 - 0.5) * fabs(to - from) * 0.07))];
    }
    if (filled > 0) v[59] = @((uint64_t)to);
    if (filled > 1) v[60 - filled] = @((uint64_t)from);
    h.values = v;
    return h;
}

static MMWindowModel *Day(NSString *name);
static void MMWindowFixtureStripHour(MMWindowModel *m, NSString *name);

/// What the families and the scratch that may go give back, in disk megabytes.
static uint64_t LeftoversBack(NSArray<MMWindowRow *> *caches) {
    uint64_t n = 0;
    for (MMWindowRow *r in caches) for (MMWindowRow *m in r.members) if (m.kin.canGo) n += m.bytes;
    return n / DMB;
}

/// Each day with its log. "log-empty", "log-new", "log-busy" and "log-undo" are the young, the young, the busy and the
/// young day with an empty log, a new Mac's first hour, 300 entries over a month and the Undo presses with two runs. The days of a new Mac show the first hour too.
MMWindowModel *MMWindowFixture(NSString *name) {
    // Ask MinMacs on the busy day: the field alone, or an answer in the log's place, MMWindowFixtureAsk.m.
    if ([name hasPrefix:@"ask-"]) {
        MMWindowModel *m = Day(@"busy");
        m.log = MMWindowFixtureLog(@"day");
        if (![name isEqualToString:@"ask-empty"] && ![name isEqualToString:@"ask-typing"]) m.answer = MMWindowFixtureAnswer(name);
        return m;
    }
    // "week", "week-young" and "week-gap": the calm day with its strip on the 7 days.
    BOOL week = [name hasPrefix:@"week"];
    NSString *day = week || [name hasPrefix:@"strip-"] ? @"calm" : [name hasPrefix:@"log-"] ? ([name isEqualToString:@"log-busy"] ? @"busy" : @"young") : name;
    MMWindowModel *m = Day(day);
    if (week) MMWindowFixtureWeek(m, name);
    NSString *log = [name isEqualToString:@"log-empty"] || [name isEqualToString:@"empty"] ? @"empty"
                  : [name isEqualToString:@"log-busy"] ? @"busy" : [name isEqualToString:@"log-undo"] ? @"undo"
                  : [name isEqualToString:@"log-new"] || [name isEqualToString:@"young"] || [name isEqualToString:@"calm"] || week || [name hasPrefix:@"strip-"] || [name hasPrefix:@"welcome"] ? @"new" : @"day";
    m.log = MMWindowFixtureLog(log);
    if ([name hasPrefix:@"strip-"]) MMWindowFixtureStripHour(m, name);
    return m;
}

/// "strip-3", "strip-46" and "strip-60": the calm day with that many minutes kept, the newest now. Both 46 minutes:
/// "strip-gap", a Mac on battery and away whose backed-off pass left every other minute without a build until the
/// last three, and "strip-sleep", a Mac that slept from its first minute until the last three.
static void MMWindowFixtureStripHour(MMWindowModel *m, NSString *name) {
    BOOL gap = [name isEqualToString:@"strip-gap"], sleep = [name isEqualToString:@"strip-sleep"];
    NSInteger minutes = gap || sleep ? 46 : MAX([name substringFromIndex:6].integerValue, 1);
    MMWindowHour *memory = Hour(m.memoryHour.title, m.memoryHour.explain, MMWindowMemory, 20.0 * GB, 23.2 * GB, minutes);
    MMWindowHour *disk = Hour(m.diskHour.title, m.diskHour.explain, MMWindowDisk, 188.0 * DGB, 182.0 * DGB, minutes);
    if (gap || sleep) for (MMWindowHour *h in @[memory, disk]) {
        NSMutableArray *v = [h.values mutableCopy];
        for (NSInteger i = 60 - minutes + 1; i < 57; i++) if (sleep || (i - (60 - minutes)) % 2) v[i] = NSNull.null;
        h.values = v;
    }
    m.memoryHour = memory; m.diskHour = disk;
}

static MMWindowModel *Day(NSString *name) {
    MMWindowModel *other = MMWindowFixtureMore(name);
    if (other) { other.settings = Settings(); return other; }
    BOOL quiet = [name isEqualToString:@"quiet"], peak = [name isEqualToString:@"peak"], empty = [name isEqualToString:@"empty"];
    BOOL running = [name isEqualToString:@"running"], done = [name isEqualToString:@"done"];
    // "memory-only" and "disk-only": the busy day with only the fixes that give that one side back.
    BOOL memoryOnly = [name isEqualToString:@"memory-only"], diskOnly = [name isEqualToString:@"disk-only"];
    // "measuring": the busy day soon after launch, with one worktree's size measured and the others not yet.
    BOOL measuring = [name isEqualToString:@"measuring"];
    // "young": one minute in, on a Mac full of servers, agents and apps, with nothing on disk found yet, nobody asking
    // and nothing to fix. "calm": twelve minutes in, nobody asks, nothing to fix, and something came back today.
    // "long": the busy day with one name in each group that is longer than its column.
    // "welcome": the young day, with the welcome on it.
    BOOL welcome = [name hasPrefix:@"welcome"];
    BOOL young = welcome || [name isEqualToString:@"young"], calm = [name isEqualToString:@"calm"], longNames = [name isEqualToString:@"long"];
    NSInteger minutes = empty || young ? 1 : calm ? 12 : 60;
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    m.settings = Settings();
    if ([name isEqualToString:@"calm"]) {
        // The calm day is a new person's first hour on a Mac with no lid: every rule on Careful and still only watching,
        // so the cleanup card's badge says when they start, the lid switch not available and the login item left alone.
        m.settings = SettingsLike(@[@1, @1, @1, @1], @{});
        m.settings.startsIn = MMWindowStartsNote(23 * 3600 + 7 * 60);
        m.settings.switches = @[MMWindowAwakeSwitch(YES, nil), MMWindowAgentsSwitch(YES, nil), MMWindowLidSwitch(NO, YES, MMWindowNoLidNote), MMWindowLoginSwitch(NO, nil), MMWindowPullsSwitch(YES), MMWindowAskClaudeSwitch(YES)];
    }
    if (empty) m.settings = SettingsLike(@[@0, @0, @0, @0], @{});
    if (welcome) m.welcome = Welcome(![name isEqualToString:@"welcome-off"], [name isEqualToString:@"welcome-watched"]);
    NSInteger asking = empty || young || calm ? 0 : quiet ? 1 : peak ? 3 : 2;
    NSArray<MMWindowRow *> *servers = Young(MMWindowFixtureServers(empty ? 0 : quiet || calm ? 7 : peak ? 26 : 20), minutes);
    NSArray<MMWindowRow *> *agents = Young(MMWindowFixtureAgents(empty ? 0 : quiet || calm ? 3 : peak ? 22 : 16, asking), minutes);
    NSArray<MMWindowRow *> *apps = MMWindowFixtureApps(empty ? 0 : quiet || calm ? 12 : 15);
    // The calm day has two projects, the quiet day one, so its list is flat. The busy days have five.
    NSArray<MMWindowRow *> *trees = MMWindowFixtureWorktrees(empty || young ? 0 : quiet || calm ? 4 : peak ? 18 : 16, quiet ? 1 : 5);
    NSArray<MMWindowRow *> *caches = MMWindowFixtureCaches(empty || young ? 0 : quiet || calm ? 2 : 5);
    // Nothing is in Fix Everything on the young and the calm day, and on a one-side day only that side's fixes are.
    // A row no fix touches carries no mark, and an app or tabs row loses the word the mark gave it.
    NSArray *stay = young || calm ? @[servers, apps, trees, caches] : memoryOnly ? @[trees, caches]
                  : diskOnly ? @[servers, apps, [trees subarrayWithRange:NSMakeRange(1, 1)]] : @[];
    for (NSArray<MMWindowRow *> *rows in stay) for (MMWindowRow *r in rows) {
        if (r.inFix && [r.state isEqualToString:@"will close"]) r.state = nil;
        r.inFix = NO;
    }
    // "caches": the busy day whose Caches also holds 169 temp-folder families and four sessions' scratch, as the owner's
    // Mac had them, each kin one row as the feed shows it, DESIGN rule 16.
    // "agents": the same, with an agent whose story holds every fact and one whose holds almost none.
    BOOL stories = [name isEqualToString:@"agents"];
    if (stories) MMWindowFixtureAgentStories(agents);
    BOOL leftovers = [name isEqualToString:@"caches"] || stories;
    if (leftovers) caches = MMWindowCollapsed([caches arrayByAddingObjectsFromArray:MMWindowFixtureLeftovers()]);
    if (measuring) for (NSUInteger i = 1; i < trees.count; i++) { trees[i].unmeasured = YES; trees[i].bytes = 0; }
    if (longNames) {
        servers = [servers arrayByAddingObject:Long(servers[1], @"server:9366", @":9366 Google Chrome for Testing", 565 * MB)];
        agents = [agents arrayByAddingObject:Long(agents[4], @"agent:long", @"Review the button pages design before the release goes out to everyone", 700 * MB)];
        apps = [apps arrayByAddingObject:Long(apps[0], @"app:long", @"Chrome for Testing Helper Renderer", 2000 * MB)];
        trees = [trees arrayByAddingObject:Long(trees[3], @"worktree:long", @"menu-window-polish-after-the-first-look", 1500 * DMB)];
        caches = [caches arrayByAddingObject:Long(caches[2], @"cache:long", @"Test browsers and their driver downloads", 5000 * DMB)];
    }
    m.memoryGroups = @[MMWindowFixtureGroup(@"servers", @"Servers", MMWindowMemory, servers), MMWindowFixtureGroup(@"agents", @"Agents", MMWindowMemory, agents),
                       MMWindowFixtureGroup(@"apps", @"Apps and helpers", MMWindowMemory, apps)];
    m.diskGroups = @[MMWindowFixtureGroup(@"worktrees", @"Worktrees", MMWindowDisk, trees), MMWindowFixtureGroup(@"caches", @"Caches", MMWindowDisk, caches)];
    // The feed's own line: one agent, or how many.
    m.asks = MMWindowAsksLine(asking);
    if (calm) { m.memoryBackToday = 250 * MB; m.diskBackToday = 3174 * DMB; }

    double used = (empty ? 9.6 : quiet || calm ? 23.2 : peak ? 58.7 : 42.4) * GB, hourAgo = (empty ? 9.5 : quiet || calm ? 20.0 : peak ? 41.3 : 34.8) * GB;
    double freeNow = (empty || young ? 612 : peak ? 96 : 182) * (double)DGB, freeThen = (empty || young ? 612 : peak ? 121 : 188) * (double)DGB;
    MMWindowFixtureRing(m, (uint64_t)used, 64 * GB, (uint64_t)freeNow, 994 * DGB);
    // The empty and the young day have run for one minute, so no line can be drawn yet. The calm day has twelve.
    m.memoryHour = Hour(MMWindowHourTitle(NO), MMWindowHourExplain(NO, 64 * GB), MMWindowMemory, hourAgo, used, minutes);
    m.diskHour = Hour(MMWindowHourTitle(YES), MMWindowHourExplain(YES, 994 * DGB), MMWindowDisk, freeThen, freeNow, minutes);
    if (empty || young || calm) return m;

    // The fixes, titled as the feed titles them, MMWindowFixTitle. The last one waits for its own press.
    NSMutableArray *fixes = [NSMutableArray arrayWithArray:@[
        Fix(@"wrapup:fix-auth-redirect", @"Wrap Up fix-auth-redirect", (412 + 1434) * MB, 1905 * DMB, NO),
        // On the caches day the families and the scratch go too: one row each, as the feed counts them.
        Fix(@"trash:leftovers", leftovers ? @"Move 3 leftovers to the Trash" : @"Move 1 leftover to the Trash", 0, (14541 + (leftovers ? LeftoversBack(caches) : 0)) * DMB, NO),
        Fix(@"stop:idle", quiet ? @"Stop 3 idle servers" : @"Stop 5 idle servers", (quiet ? 720 : 816) * MB, 0, NO),
        Fix(@"quit:apps", @"Quit 1 app", 578 * MB, 0, NO)]];
    if (!quiet) [fixes addObject:Fix(@"remove:merged", @"Remove 3 merged worktrees", 0, 2616 * DMB, NO)];
    [fixes addObject:Fix(@"clean:npm", @"Clean npm cache", 0, 6246 * DMB, YES)];
    if (memoryOnly || diskOnly) {
        NSMutableArray *kept = [NSMutableArray new];
        for (MMWindowFix *x in fixes) if (!x.needsYou && (memoryOnly ? x.diskBack == 0 : x.memoryBack == 0)) [kept addObject:x];
        fixes = kept;
    }
    if (measuring) for (MMWindowFix *x in fixes) {
        // As the feed makes them: a Wrap Up's disk is its worktree's number, which counts the cache inside it, so with
        // the worktree not measured it holds none. Neither do the merged worktrees. Both read "not measured yet".
        if ([x.key hasPrefix:@"wrapup:"] || [x.key isEqualToString:@"remove:merged"]) { x.diskBack = 0; x.diskPartial = YES; }
    }
    m.fixes = fixes;

    if (running || done) {
        MMWindowRun *run = [MMWindowRun new];
        run.total = m.fixCount; run.memoryPlanned = m.memoryBack; run.diskPlanned = m.diskBack;
        if (running) {
            // The runner's own words, MMFixStepText.
            run.running = YES; run.step = @"Stopping :4321 Astro"; run.stepAction = @"Stopping"; run.done = 2;
            run.memoryBack = 2086 * MB; run.diskBack = 16446 * DMB;
        } else {
            run.done = run.total; run.memoryBack = run.memoryPlanned - 96 * MB; run.diskBack = run.diskPlanned;
            run.endTitle = [NSString stringWithFormat:@"%ld fixes done", (long)run.total];
            run.endNote = @"Skipped 2 agents that ask you and 1 fix that needs your own press. Deleted 3, moved 2 to the Trash.";
        }
        m.run = run;
    }
    return m;
}
