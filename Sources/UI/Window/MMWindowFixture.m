// Made-up days for the render tool and the checks, in the spirit of 195-a's Quiet, Busy and Peak.
// Nothing here is measured. Every name is invented, and the numbers only have to look like a working Mac.
#import "UI/Window/MMWindowFixtureParts.h"
#import "UI/MMFormat.h"

static const uint64_t MB = MMFixMB, GB = MMFixGB, DMB = MMFixDiskMB, DGB = MMFixDiskGB;

/// A row whose name is longer than its group's column, one per group, for the day named "long".
static MMWindowRow *Long(MMWindowRow *like, NSString *key, NSString *name, uint64_t bytes) {
    MMWindowRow *r = MMWindowFixtureRow(like.kind, key, name, like.iconHint, like.state, bytes, like.cpuPercent);
    r.hour = like.hour; r.facts = like.facts; r.quiet = like.quiet;
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

static MMWindowRule *Card(NSString *rid, NSString *title, NSInteger picked, NSArray<NSArray<NSString *> *> *choices, NSString *note) {
    return MMWindowChoiceCard(rid, title, picked, choices, note);
}

/// Settings as the feed fills it, Shell/MMWindowRules.m: the four rules from the same words the feed uses, the card
/// for the removal choice with Core's own three sentences, then This Mac. The render cannot link Core, so the three
/// removal sentences are written here too, and test/window.sh and test/window/window.m hold them to Core's.
/// `picked` is the choice of each of the four rules and of the removal card.
static MMWindowSettings *SettingsLike(NSArray<NSNumber *> *picked, NSDictionary<NSString *, NSString *> *notes) {
    MMWindowSettings *s = [MMWindowSettings new];
    NSMutableArray<MMWindowRule *> *rules = [NSMutableArray new];
    NSArray<NSString *> *ids = MMWindowRuleIDs();
    for (NSUInteger i = 0; i < ids.count; i++) [rules addObject:MMWindowRuleCard(ids[i], picked[i].integerValue, notes[ids[i]])];
    [rules addObject:
                Card(@"removal", MMWindowRemovalTitle, picked[4].integerValue, @[
                     @[@"Smart", @"Deletes what git or its tool can give back. The rest goes to the Trash."],
                     @[@"Trash", @"Everything goes to the Trash. The disk comes back when you empty it."],
                     @[@"Delete", @"Deletes everything it removes at once. Nothing can be brought back."]], notes[@"removal"])];
    s.rules = rules;
    s.switches = @[MMWindowLidSwitch(YES, NO, @"On now. The Mac keeps running with the lid shut."), MMWindowLoginSwitch(YES, nil)];
    return s;
}

/// A working day: servers and worktrees on Careful, caches on Eager, apps Off with one app ready for a press.
static MMWindowSettings *Settings(void) {
    return SettingsLike(@[@1, @0, @1, @2, @0], @{@"apps": MMWindowReadyNote(1)});
}

/// "removal": the same day. It keeps its name from when only it had the removal card.
static MMWindowSettings *SettingsWithRemoval(void) { return Settings(); }

/// The welcome as the feed makes it for a person new to MinMacs, MMWindowWelcomeNow in Shell/MMWindowRules.m, with
/// the switch on or off and one removal choice picked. test/window.sh checks its facts against the feed's.
static MMWindowWelcome *Welcome(BOOL login, NSInteger picked, BOOL watched) {
    MMWindowWelcome *w = [MMWindowWelcome welcomeWithRemoval:SettingsWithRemoval().rules.lastObject.choices picked:picked facts:@[
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

MMWindowModel *MMWindowFixture(NSString *name) {
    MMWindowModel *other = MMWindowFixtureMore(name);
    if (other) { other.settings = Settings(); return other; }
    BOOL quiet = [name isEqualToString:@"quiet"], peak = [name isEqualToString:@"peak"], empty = [name isEqualToString:@"empty"];
    BOOL running = [name isEqualToString:@"running"], done = [name isEqualToString:@"done"];
    // "memory-only" and "disk-only": the busy day with only the fixes that give that one side back.
    BOOL memoryOnly = [name isEqualToString:@"memory-only"], diskOnly = [name isEqualToString:@"disk-only"];
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
        // the removal choice not made yet, so none is picked, the lid switch not available and the login item left alone.
        NSString *watching = MMWindowWatchingNote(@"23h");
        m.settings = SettingsLike(@[@1, @1, @1, @1, @-1], @{@"servers": watching, @"worktrees": watching, @"caches": watching,
            @"removal": @"Not chosen yet. Until you pick one, what MinMacs removes on its own goes to the Trash."});
        m.settings.switches = @[MMWindowLidSwitch(NO, YES, MMWindowNoLidNote), MMWindowLoginSwitch(NO, nil)];
    }
    if (empty) m.settings = SettingsLike(@[@0, @0, @0, @0, @1], @{});
    if (welcome) m.welcome = Welcome(![name isEqualToString:@"welcome-off"], [name isEqualToString:@"welcome-trash"] ? 1 : [name isEqualToString:@"welcome-delete"] ? 2 : 0,
                                     [name isEqualToString:@"welcome-watched"]);
    NSInteger asking = empty || young || calm ? 0 : quiet ? 1 : peak ? 3 : 2;
    NSArray<MMWindowRow *> *servers = Young(MMWindowFixtureServers(empty ? 0 : quiet || calm ? 7 : peak ? 26 : 20), minutes);
    NSArray<MMWindowRow *> *agents = Young(MMWindowFixtureAgents(empty ? 0 : quiet || calm ? 3 : peak ? 22 : 16, asking), minutes);
    NSArray<MMWindowRow *> *apps = MMWindowFixtureApps(empty ? 0 : quiet || calm ? 12 : 15);
    NSArray<MMWindowRow *> *trees = MMWindowFixtureWorktrees(empty || young ? 0 : quiet || calm ? 4 : peak ? 18 : 16);
    NSArray<MMWindowRow *> *caches = MMWindowFixtureCaches(empty || young ? 0 : quiet || calm ? 2 : 5);
    // Nothing is in Fix Everything on the young and the calm day, and on a one-side day only that side's fixes are.
    // A row no fix touches carries no mark, and an app or tabs row loses the word the mark gave it.
    NSArray *stay = young || calm ? @[servers, apps, trees, caches] : memoryOnly ? @[trees, caches]
                  : diskOnly ? @[servers, apps, [trees subarrayWithRange:NSMakeRange(1, 1)]] : @[];
    for (NSArray<MMWindowRow *> *rows in stay) for (MMWindowRow *r in rows) {
        if (r.inFix && [r.state isEqualToString:@"will close"]) r.state = nil;
        r.inFix = NO;
    }
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
        Fix(@"trash:leftovers", @"Clean up 1 leftover", 0, 14541 * DMB, NO),
        Fix(@"stop:idle", quiet ? @"Stop 3 idle servers" : @"Stop 5 idle servers", (quiet ? 720 : 816) * MB, 0, NO),
        Fix(@"quit:apps", @"Quit 1 app", 578 * MB, 0, NO)]];
    if (!quiet) [fixes addObject:Fix(@"remove:merged", @"Remove 3 merged worktrees", 0, 2616 * DMB, NO)];
    [fixes addObject:Fix(@"clean:npm", @"Clean npm cache", 0, 6246 * DMB, YES)];
    if (memoryOnly || diskOnly) {
        NSMutableArray *kept = [NSMutableArray new];
        for (MMWindowFix *x in fixes) if (!x.needsYou && (memoryOnly ? x.diskBack == 0 : x.memoryBack == 0)) [kept addObject:x];
        fixes = kept;
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
