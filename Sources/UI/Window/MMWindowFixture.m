// Made-up days for the render tool and the checks, in the spirit of 195-a's Quiet, Busy and Peak.
// Nothing here is measured. Every name is invented, and the numbers only have to look like a working Mac.
#import "UI/Window/MMWindowUI.h"
#import "UI/MMFormat.h"

static const uint64_t MB = 1ull << 20, GB = 1ull << 30;

/// The same made-up noise on every run, from a seed.
static double Noise(uint32_t *seed) { *seed = *seed * 1664525u + 1013904223u; return ((*seed >> 8) & 0xFFFF) / 65535.0 - 0.5; }

static uint32_t Seed(NSString *s) { uint32_t h = 2166136261u; for (NSUInteger i = 0; i < s.length; i++) h = (h ^ [s characterAtIndex:i]) * 16777619u; return h; }

/// An hour that ends at `now`: flat, a step, a climb or a hump, by the seed.
static NSArray *HourTo(double now, NSString *key, NSInteger shape) {
    uint32_t seed = Seed(key);
    NSMutableArray *v = [NSMutableArray new];
    for (NSInteger i = 0; i < 60; i++) {
        double t = i / 59.0, f = 1;
        if (shape == 1) f = i < 22 ? 0.72 : 1;
        else if (shape == 2) f = 0.7 + 0.3 * t;
        else if (shape == 3) f = 0.8 + 0.2 * sin(t * M_PI * 0.8 + 0.5);
        [v addObject:@((uint64_t)MAX(0, now * (f + Noise(&seed) * 0.012)))];
    }
    v[59] = @((uint64_t)now);
    return v;
}

static MMWindowRow *Row(MMWindowKind kind, NSString *key, NSString *name, NSString *hint, NSString *state, uint64_t bytes, double cpu) {
    MMWindowRow *r = [MMWindowRow new];
    r.kind = kind; r.key = key; r.name = name; r.iconHint = hint; r.state = state; r.bytes = bytes; r.cpuPercent = cpu;
    return r;
}

static MMWindowFact *F(NSString *label, NSString *value) { return [MMWindowFact label:label value:value]; }

static NSArray<MMWindowRow *> *Servers(NSInteger count) {
    // port, framework, megabytes, CPU in tenths or -1, state, project
    NSArray *t = @[@[@3001, @"Next.js", @412, @6, @"", @"atlas"], @[@6006, @"Storybook", @520, @3, @"", @"icons"],
                   @[@3000, @"Next.js", @412, @-1, @"", @"studio"], @[@4000, @"Phoenix", @260, @-1, @"", @"lexicon"],
                   @[@8888, @"Jupyter", @290, @-1, @"", @"scoring"], @[@1313, @"Hugo", @60, @-1, @"nobody", @"handbook"],
                   @[@4100, @"Phoenix", @260, @5, @"", @"lexicon"], @[@3334, @"Astro", @240, @-1, @"idle", @"parity"],
                   @[@4321, @"Astro", @240, @4, @"idle", @"parity"], @[@4322, @"Astro", @240, @2, @"idle", @"parity"],
                   @[@9000, @"Django", @210, @-1, @"", @"uploader"], @[@5180, @"Vite", @188, @4, @"", @"speed"],
                   @[@5173, @"Vite", @188, @4, @"", @"media"], @[@5174, @"Vite", @188, @3, @"", @"search"],
                   @[@5175, @"Vite", @188, @-1, @"", @"lane-c"], @[@8000, @"FastAPI", @180, @2, @"", @"scoring"],
                   @[@8080, @"Go", @160, @1, @"", @"gateway"], @[@7007, @"Rails", @140, @-1, @"", @"billing"],
                   @[@4200, @"Angular", @136, @-1, @"", @"console"], @[@5500, @"Flask", @36, @-1, @"nobody", @"notes"],
                   @[@5181, @"Vite", @196, @7, @"", @"glossary"], @[@5182, @"Vite", @192, @5, @"", @"schema"],
                   @[@3002, @"Next.js", @430, @9, @"", @"budget"], @[@4001, @"Phoenix", @270, @3, @"", @"judge"],
                   @[@8001, @"FastAPI", @184, @2, @"", @"ranking"], @[@6007, @"Storybook", @505, @4, @"", @"fieldsets"]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *s = t[i];
        NSInteger port = [s[0] integerValue];
        NSString *name = [NSString stringWithFormat:@":%ld %@", (long)port, s[1]];
        BOOL idle = [s[4] length] > 0;
        MMWindowRow *r = Row(MMWindowServer, [NSString stringWithFormat:@"server:%ld", (long)port], name, [s[1] lowercaseString],
                             [s[4] length] ? s[4] : nil, [s[2] unsignedLongLongValue] * MB, [s[3] integerValue] < 0 ? -1 : [s[3] integerValue] / 10.0);
        r.hour = HourTo(r.bytes, r.key, i % 4);
        r.inFix = idle;
        r.facts = @[F(@"Project", s[5]), F(@"Runs", @"pnpm dev, 2 processes"), F(@"Port", [NSString stringWithFormat:@":%ld on 127.0.0.1", (long)port]),
                    F(@"Connections", idle ? @"none in the last 2 h" : @"2 now"),
                    F(@"Why", idle ? @"Goes. Nobody has asked it for a page in 2 h." : @"Stays. A browser tab and an agent use it.")];
        [rows addObject:r];
    }
    return rows;
}

static NSArray<MMWindowRow *> *Agents(NSInteger count, NSInteger asking) {
    NSArray *t = @[@[@"Import the glossary", @695, @-1, @"glossary"], @[@"Score answers", @306, @-1, @"scoring"], @[@"Match studio views", @431, @-1, @"studio"],
                   @[@"Sort lane C by due", @763, @13, @"lane-c"], @[@"Write lane C fixtures", @760, @16, @"lane-c"], @[@"Tune the ranking", @628, @3, @"ranking"],
                   @[@"Rebuild the search", @625, @22, @"search"], @[@"Check bundle sizes", @622, @-1, @"budget"], @[@"Speed up the base", @622, @10, @"speed"],
                   @[@"Fix the auth redirect", @580, @-1, @"atlas"], @[@"Split the upload form", @540, @8, @"uploader"], @[@"Review the schema diff", @512, @-1, @"schema"],
                   @[@"Trim the icon set", @470, @2, @"icons"], @[@"Port the date helpers", @455, @-1, @"lexicon"], @[@"Draft the release notes", @390, @-1, @"handbook"],
                   @[@"Audit the perf budget", @372, @4, @"budget"], @[@"Name the media scopes", @364, @6, @"media"], @[@"Sweep the 403 pages", @351, @-1, @"gateway"],
                   @[@"Merge the judge rubric", @340, @5, @"judge"], @[@"Move billing to cents", @322, @-1, @"billing"], @[@"Label the console tabs", @301, @3, @"console"],
                   @[@"Sync the notes export", @288, @-1, @"notes"]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *a = t[i];
        MMWindowRow *r = Row(MMWindowAgent, [NSString stringWithFormat:@"agent:%ld", (long)i], a[0], i % 3 == 2 ? @"codex" : @"claude-code", nil,
                             [a[1] unsignedLongLongValue] * MB, [a[2] integerValue] < 0 ? -1 : [a[2] integerValue] / 10.0);
        r.needsYou = i < asking;
        if (r.needsYou) r.state = @"asks you";
        r.hour = HourTo(r.bytes, r.key, (i + 1) % 4);
        r.facts = @[F(@"Agent", i % 3 == 2 ? @"Codex" : @"Claude Code"), F(@"Project", a[3]), F(@"Started", [NSString stringWithFormat:@"%ld min ago", (long)(14 + i * 7)]), F(@"Processes", i % 2 ? @"3, with a test runner" : @"2"),
                    F(@"Why", r.needsYou ? @"Waits on you. It asked a question and has not moved since." : @"Stays. It is working.")];
        [rows addObject:r];
    }
    return rows;
}

static NSArray<MMWindowRow *> *Apps(NSInteger count) {
    // name, bundle id or "" for a helper, megabytes, CPU in tenths or -1, state, why
    NSArray *t = @[@[@"Safari", @"com.apple.Safari", @4915, @19, @"kept", @"Kept. You use it every day."],
                   @[@"Terminal", @"com.apple.Terminal", @4300, @21, @"kept", @"Kept. 9 agents run in it."],
                   @[@"Xcode", @"com.apple.dt.Xcode", @2765, @9, @"kept", @"Kept. A build ran 6 min ago."],
                   @[@"localhost tabs", @"tabs", @1434, @-1, @"will close", @"Goes. 14 tabs point at servers that stopped."],
                   @[@"Simulator", @"com.apple.iphonesimulator", @1126, @6, @"", @"Stays. Xcode holds it open."],
                   @[@"Language server", @"", @905, @11, @"", @"Stays. An editor asks it for answers."],
                   @[@"Browser helper", @"", @640, @4, @"", @"Stays. It draws the pages Safari shows."],
                   @[@"Music", @"com.apple.Music", @578, @1, @"will close", @"Goes. On your close list, and nothing has played for 3 h."],
                   @[@"Mail", @"com.apple.mail", @420, @-1, @"kept", @"Kept. You use it every day."],
                   @[@"Search indexing", @"", @380, @4, @"", @"Stays. macOS runs it and stops it on its own."],
                   @[@"Notes", @"com.apple.Notes", @310, @-1, @"", @"Stays. A note has changes not yet saved."],
                   @[@"Preview", @"com.apple.Preview", @280, @-1, @"unsorted", @"Stays. Nothing says it may close."],
                   @[@"Photo analysis", @"", @210, @2, @"", @"Stays. macOS runs it and stops it on its own."],
                   @[@"Calendar", @"com.apple.iCal", @190, @-1, @"", @"Stays. A reminder is due at 15:00."],
                   @[@"Font helper", @"", @120, @-1, @"", @"Stays. Three apps share it."]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *a = t[i];
        BOOL tabs = [a[1] isEqualToString:@"tabs"], helper = [a[1] length] == 0;
        MMWindowRow *r = Row(tabs ? MMWindowTabs : helper ? MMWindowHelper : MMWindowApp, [NSString stringWithFormat:@"app:%ld", (long)i], a[0],
                             tabs || helper ? nil : a[1], [a[4] length] ? a[4] : nil, [a[2] unsignedLongLongValue] * MB, [a[3] integerValue] < 0 ? -1 : [a[3] integerValue] / 10.0);
        if (tabs) r.tabs = 14;
        r.inFix = [a[4] isEqualToString:@"will close"];
        r.facts = @[F(helper ? @"Part of" : @"Open", helper ? @"macOS and the apps that use it" : tabs ? @"in Safari, 2 windows" : @"since this morning"), F(@"Why", a[5])];
        [rows addObject:r];
    }
    return rows;
}

static NSArray<MMWindowRow *> *Worktrees(NSInteger count) {
    // name, state, megabytes, in Fix Everything
    NSArray *t = @[@[@"dogfood", @"nobody", @3144, @NO], @[@"fix-auth-redirect", @"merged", @1905, @YES], @[@"parity", @"in use", @1884, @NO],
                   @[@"media-scope", @"changed", @1393, @NO], @[@"speed-3-base", @"changed", @1331, @NO], @[@"bundle-split", @"merged", @1126, @YES],
                   @[@"sweep-403", @"nobody", @1085, @NO], @[@"judge-scoring", @"changed", @990, @NO], @[@"fieldsets", @"merged", @900, @YES],
                   @[@"search-index", @"changed", @850, @NO], @[@"perf-budget", @"changed", @710, @NO], @[@"uploader-v2", @"nobody", @690, @NO],
                   @[@"lane-c", @"changed", @650, @NO], @[@"icons-v1", @"merged", @590, @YES], @[@"glossary-import", @"changed", @490, @NO],
                   @[@"schema-diff", @"changed", @410, @NO], @[@"billing-cents", @"changed", @388, @NO], @[@"notes-export", @"nobody", @342, @NO]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *w = t[i];
        NSString *state = w[1];
        MMWindowRow *r = Row(MMWindowWorktree, [@"worktree:" stringByAppendingString:w[0]], w[0], nil, state, [w[2] unsignedLongLongValue] * MB, -1);
        r.inFix = [w[3] boolValue];
        NSString *why = [state isEqualToString:@"merged"] ? @"Goes. Its branch is merged and nothing in it is uncommitted."
            : [state isEqualToString:@"in use"] ? @"Stays. An agent works in it now."
            : [state isEqualToString:@"changed"] ? @"Stays. 3 files are not committed." : @"Stays. Not merged, and no session has touched it for 9 days.";
        r.facts = @[F(@"Branch", w[0]), F(@"Repo", i % 2 ? @"studio" : @"atlas"), F(@"Frees", MMBytes(r.bytes)), F(@"Last touched", [NSString stringWithFormat:@"%ld d ago", (long)(1 + i)]), F(@"Why", why)];
        [rows addObject:r];
    }
    return rows;
}

static NSArray<MMWindowRow *> *Caches(NSInteger count) {
    NSArray *t = @[@[@"DerivedData", @"may go", @14541, @"Xcode", @"Goes. 4 of its 7 projects are gone from this Mac."],
                   @[@"npm cache", @"own clean", @6246, @"npm", @"Stays until you press. npm cleans it with its own command."],
                   @[@"Container build cache", @"", @4300, @"the container tool", @"Stays. A build used it 2 h ago."],
                   @[@"Test browsers", @"", @3380, @"the test runner", @"Stays. The newest set is in use."],
                   @[@"Simulators", @"report only", @800, @"Xcode", @"Stays. Xcode keeps its own simulators, so this is only reported."]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *c = t[i];
        MMWindowRow *r = Row(MMWindowCache, [NSString stringWithFormat:@"cache:%ld", (long)i], c[0], nil, [c[1] length] ? c[1] : nil, [c[2] unsignedLongLongValue] * MB, -1);
        r.inFix = i == 0;
        r.facts = @[F(@"Owner", c[3]), F(@"Frees", MMBytes(r.bytes)), F(@"Last used", [NSString stringWithFormat:@"%ld d ago", (long)(2 + i * 5)]), F(@"Why", c[4])];
        [rows addObject:r];
    }
    return rows;
}

/// A row whose name is longer than its group's column, one per group, for the day named "long".
static MMWindowRow *Long(MMWindowRow *like, NSString *key, NSString *name, uint64_t bytes) {
    MMWindowRow *r = Row(like.kind, key, name, like.iconHint, like.state, bytes, like.cpuPercent);
    r.hour = like.hour; r.facts = like.facts;
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

static MMWindowGroup *Group(NSString *key, NSString *title, MMWindowSide side, NSArray<MMWindowRow *> *rows) {
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = key; g.title = title; g.side = side;
    g.emptyNote = @{@"servers": @"No servers found", @"agents": @"No agents found", @"apps": @"No apps found",
                    @"worktrees": @"No worktrees found", @"caches": @"No caches or leftovers found"}[key];
    g.rows = [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return a.bytes > b.bytes ? NSOrderedAscending : a.bytes < b.bytes ? NSOrderedDescending : NSOrderedSame; }];
    return g;
}

static MMWindowFix *Fix(NSString *key, NSString *title, uint64_t memory, uint64_t disk, BOOL needsYou) {
    MMWindowFix *f = [MMWindowFix new];
    f.key = key; f.title = title; f.memoryBack = memory; f.diskBack = disk; f.needsYou = needsYou;
    return f;
}

static MMWindowRule *Rule(NSString *rid, NSString *title, NSInteger picked, NSString *ask, NSString *automatic, NSString *note) {
    MMWindowRule *r = [MMWindowRule new];
    r.ruleID = rid; r.title = title; r.picked = picked; r.note = note;
    NSMutableArray *choices = [NSMutableArray new];
    for (NSArray *c in @[@[@"Off", @"Not watching. Nothing is shown, nothing happens."], @[@"Ask", ask], @[@"Auto", automatic]]) {
        MMWindowChoice *x = [MMWindowChoice new]; x.title = c[0]; x.explain = c[1];
        [choices addObject:x];
    }
    r.choices = choices;
    return r;
}

static MMWindowSettings *Settings(void) {
    MMWindowSettings *s = [MMWindowSettings new];
    NSString *ask = @"Shows a button. Nothing happens until you press it.";
    s.rules = @[Rule(@"wrapup", @"Wrap Up workstreams", 1, ask, @"Runs the plan 1 h after the merge, once its sessions end. What it removes goes to the Trash.", @"1 ready, 1.9 GB disk. Wrap Up waits for your press."),
                Rule(@"apps", @"Close apps", 1, ask, @"Closes the apps on your close list when memory pressure warns, then sends a notice with Restore.", @"Memory pressure is normal. A button shows for Music once it warns."),
                Rule(@"leftovers", @"Clean up leftovers", 1, ask, @"Moves what may go to the Trash every Sunday.", @"8 leftovers may go. Nothing happens until you press."),
                Rule(@"servers", @"Stop idle servers", 2, ask, @"Stops a server after 2 h idle, then sends a notice with Undo.", @"Auto stops :1313 next."),
                Rule(@"worktrees", @"Remove merged worktrees", 1, ask, @"Removes a worktree no workstream owns 1 day after its merge, once nothing in it is uncommitted.", @"3 merged 1 day ago or more. Each waits for your press.")];
    MMWindowSwitch *lid = [MMWindowSwitch new];
    lid.switchID = @"lid"; lid.title = @"Keep working with the lid closed"; lid.on = YES;
    lid.note = @"MinMacs keeps the Mac awake while 11 agents work. On battery it stops at 20 %, off Wi-Fi or when the Mac runs hot.";
    MMWindowSwitch *login = [MMWindowSwitch new];
    login.switchID = @"login"; login.title = @"Open at login"; login.on = YES; login.note = @"MinMacs starts when you sign in.";
    s.switches = @[lid, login];
    return s;
}

static uint64_t Sum(MMWindowGroup *g) { uint64_t n = 0; for (MMWindowRow *r in g.rows) n += r.bytes; return n; }

static MMWindowSlice *Slice(NSString *group, uint64_t bytes) { MMWindowSlice *s = [MMWindowSlice new]; s.group = group; s.bytes = bytes; return s; }

static MMWindowHour *Hour(NSString *title, NSString *explain, MMWindowSide side, double from, double to, NSInteger filled) {
    MMWindowHour *h = [MMWindowHour new];
    h.title = title; h.explain = explain; h.side = side;
    uint32_t seed = Seed(title);
    NSMutableArray *v = [NSMutableArray new];
    for (NSInteger i = 0; i < 60; i++) {
        if (i < 60 - filled) { [v addObject:NSNull.null]; continue; }
        // Memory climbs fast and then slowly. Disk free falls fast and then levels.
        double t = filled > 1 ? (i - (60 - filled)) / (double)(filled - 1) : 1, eased = side == MMWindowMemory ? pow(t, 0.55) : 1 - pow(1 - t, 2.4);
        [v addObject:@((uint64_t)(from + (to - from) * eased + Noise(&seed) * fabs(to - from) * 0.07))];
    }
    if (filled > 0) v[59] = @((uint64_t)to);
    if (filled > 1) v[60 - filled] = @((uint64_t)from);
    h.values = v;
    return h;
}

MMWindowModel *MMWindowFixture(NSString *name) {
    BOOL quiet = [name isEqualToString:@"quiet"], peak = [name isEqualToString:@"peak"], empty = [name isEqualToString:@"empty"];
    BOOL running = [name isEqualToString:@"running"], done = [name isEqualToString:@"done"];
    // "young": one minute in, on a Mac full of servers, agents and apps, with nothing on disk found yet, nobody asking
    // and nothing to fix. "calm": twelve minutes in, nobody asks, nothing to fix, and something came back today.
    // "long": the busy day with one name in each group that is longer than its column.
    BOOL young = [name isEqualToString:@"young"], calm = [name isEqualToString:@"calm"], longNames = [name isEqualToString:@"long"];
    NSInteger minutes = empty || young ? 1 : calm ? 12 : 60;
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    m.settings = Settings();
    NSInteger asking = empty || young || calm ? 0 : quiet ? 1 : peak ? 3 : 2;
    NSArray<MMWindowRow *> *servers = Young(Servers(empty ? 0 : quiet || calm ? 7 : peak ? 26 : 20), minutes);
    NSArray<MMWindowRow *> *agents = Young(Agents(empty ? 0 : quiet || calm ? 3 : peak ? 22 : 16, asking), minutes);
    NSArray<MMWindowRow *> *apps = Apps(empty ? 0 : quiet || calm ? 12 : 15);
    NSArray<MMWindowRow *> *trees = Worktrees(empty || young ? 0 : quiet || calm ? 4 : peak ? 18 : 16);
    NSArray<MMWindowRow *> *caches = Caches(empty || young ? 0 : quiet || calm ? 2 : 5);
    if (young || calm) for (NSArray<MMWindowRow *> *rows in @[servers, apps, trees, caches]) for (MMWindowRow *r in rows) {
        // Nothing is in Fix Everything on these days, so no row says it will go.
        r.inFix = NO;
        if ([@[@"idle", @"nobody", @"will close", @"merged", @"may go"] containsObject:r.state ?: @""]) r.state = nil;
    }
    if (longNames) {
        servers = [servers arrayByAddingObject:Long(servers[1], @"server:9366", @":9366 Google Chrome for Testing", 565 * MB)];
        agents = [agents arrayByAddingObject:Long(agents[4], @"agent:long", @"Review the button pages design before the release goes out to everyone", 700 * MB)];
        apps = [apps arrayByAddingObject:Long(apps[0], @"app:long", @"Chrome for Testing Helper Renderer", 2000 * MB)];
        trees = [trees arrayByAddingObject:Long(trees[3], @"worktree:long", @"menu-window-polish-after-the-first-look", 1500 * MB)];
        caches = [caches arrayByAddingObject:Long(caches[2], @"cache:long", @"Test browsers and their driver downloads", 5000 * MB)];
    }
    m.memoryGroups = @[Group(@"servers", @"Servers", MMWindowMemory, servers), Group(@"agents", @"Agents", MMWindowMemory, agents),
                       Group(@"apps", @"Apps and helpers", MMWindowMemory, apps)];
    m.diskGroups = @[Group(@"worktrees", @"Worktrees", MMWindowDisk, trees), Group(@"caches", @"Caches", MMWindowDisk, caches)];
    if (asking) m.asks = asking == 1 ? @"Import the glossary asks you" : [NSString stringWithFormat:@"%ld agents ask you", (long)asking];
    if (calm) { m.memoryBackToday = 250 * MB; m.diskBackToday = 3174 * MB; }

    double used = (empty ? 9.6 : quiet || calm ? 23.2 : peak ? 58.7 : 42.4) * GB, hourAgo = (empty ? 9.5 : quiet || calm ? 20.0 : peak ? 41.3 : 34.8) * GB;
    double freeNow = (empty || young ? 612 : peak ? 96 : 182) * GB, freeThen = (empty || young ? 612 : peak ? 121 : 188) * GB;
    MMWindowRing *ring = m.ring;
    ring.memoryUsed = (uint64_t)used; ring.memoryTotal = 64 * GB;
    ring.diskFree = (uint64_t)freeNow; ring.diskTotal = 994 * GB;
    NSMutableArray *slices = [NSMutableArray new];
    uint64_t held = 0;
    for (MMWindowGroup *g in m.memoryGroups) { uint64_t s = Sum(g); held += s; if (s) [slices addObject:Slice(g.key, s)]; }
    if (ring.memoryUsed > held) [slices addObject:Slice(@"other", ring.memoryUsed - held)];
    ring.memory = slices;
    slices = [NSMutableArray new]; held = 0;
    for (MMWindowGroup *g in m.diskGroups) { uint64_t s = Sum(g); held += s; if (s) [slices addObject:Slice(g.key, s)]; }
    [slices addObject:Slice(@"other", ring.diskTotal - ring.diskFree - held)];
    ring.disk = slices;
    // The empty and the young day have run for one minute, so no line can be drawn yet. The calm day has twelve.
    m.memoryHour = Hour(@"Memory in use", @"Higher means more of the 64 GB is in use", MMWindowMemory, hourAgo, used, minutes);
    m.diskHour = Hour(@"Disk free", @"Lower means less room left on the 994 GB disk", MMWindowDisk, freeThen, freeNow, minutes);
    if (empty || young || calm) return m;

    NSMutableArray *fixes = [NSMutableArray arrayWithArray:@[
        Fix(@"wrapup:fix-auth-redirect", @"Wrap Up fix-auth-redirect", 412 * MB, 1905 * MB, NO),
        Fix(@"trash:deriveddata", @"Trash DerivedData", 0, 14541 * MB, NO),
        Fix(@"tabs:localhost", @"Close 14 localhost tabs", 1434 * MB, 0, NO),
        Fix(@"stop:astro", @"Stop 3 idle Astro servers", 720 * MB, 0, NO),
        Fix(@"quit:music", @"Quit Music", 578 * MB, 0, NO)]];
    if (!quiet) [fixes addObjectsFromArray:@[Fix(@"remove:merged", @"Remove 3 merged worktrees", 0, 2616 * MB, NO), Fix(@"stop:1313", @"Stop :1313 Hugo", 60 * MB, 0, NO)]];
    [fixes addObject:Fix(@"clean:npm", @"Clean the npm cache", 0, 6246 * MB, YES)];
    m.fixes = fixes;

    if (running || done) {
        MMWindowRun *run = [MMWindowRun new];
        run.total = m.fixCount; run.memoryPlanned = m.memoryBack; run.diskPlanned = m.diskBack;
        if (running) {
            run.running = YES; run.step = @"Closing tab 5 of 14"; run.done = 2;
            run.memoryBack = 780 * MB; run.diskBack = 16446 * MB;
        } else {
            run.done = run.total; run.memoryBack = run.memoryPlanned - 96 * MB; run.diskBack = run.diskPlanned;
            run.endTitle = @"7 fixes done";
            run.endNote = @"Skipped 2 agents that ask you and 1 cache that npm cleans itself. Deletes went to the Trash.";
        }
        m.run = run;
    }
    return m;
}
