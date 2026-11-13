// The rows of the render's made-up days. Nothing here is measured and every name is invented. The shape is the
// feed's, Shell/MMWindowRows.m: the same state words, the same fact labels in the same order, values in the same form.
#import "UI/Window/MMWindowFixtureParts.h"

static const uint64_t MB = MMFixMB, DMB = MMFixDiskMB;

/// The same made-up noise on every run, from a seed.
static double Noise(uint32_t *seed) { *seed = *seed * 1664525u + 1013904223u; return ((*seed >> 8) & 0xFFFF) / 65535.0 - 0.5; }

static uint32_t Seed(NSString *s) { uint32_t h = 2166136261u; for (NSUInteger i = 0; i < s.length; i++) h = (h ^ [s characterAtIndex:i]) * 16777619u; return h; }

NSArray *MMWindowFixtureHour(double now, NSString *key, NSInteger shape) {
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

MMWindowRow *MMWindowFixtureRow(MMWindowKind kind, NSString *key, NSString *name, NSString *hint, NSString *state, uint64_t bytes, double cpu) {
    MMWindowRow *r = [MMWindowRow new];
    r.kind = kind; r.key = key; r.name = name; r.iconHint = hint; r.state = state; r.bytes = bytes; r.cpuPercent = cpu;
    return r;
}

static MMWindowFact *F(NSString *label, NSString *value) { return [MMWindowFact label:label value:value]; }

NSArray<MMWindowRow *> *MMWindowFixtureServers(NSInteger count) {
    // port, framework, megabytes, CPU in tenths or -1, state, project
    NSArray *t = @[@[@3001, @"Next.js", @412, @6, @"", @"atlas"], @[@6006, @"Storybook", @520, @3, @"", @"icons"],
                   @[@3000, @"Next.js", @412, @-1, @"", @"studio"], @[@4000, @"Phoenix", @260, @-1, @"kept", @"lexicon"],
                   @[@8888, @"Jupyter", @290, @-1, @"", @"scoring"], @[@1313, @"Hugo", @60, @-1, @"idle", @"handbook"],
                   @[@4100, @"Phoenix", @260, @5, @"", @"lexicon"], @[@3334, @"Astro", @240, @-1, @"idle", @"parity"],
                   @[@4321, @"Astro", @240, @4, @"idle", @"parity"], @[@4322, @"Astro", @240, @2, @"idle", @"parity"],
                   @[@9000, @"Django", @210, @-1, @"", @"uploader"], @[@5180, @"Vite", @188, @4, @"", @"speed"],
                   @[@5173, @"Vite", @188, @4, @"", @"media"], @[@5174, @"Vite", @188, @3, @"", @"search"],
                   @[@5175, @"Vite", @188, @-1, @"", @"lane-c"], @[@8000, @"FastAPI", @180, @2, @"", @"scoring"],
                   @[@8080, @"Go", @160, @1, @"", @"gateway"], @[@7007, @"Rails", @140, @-1, @"", @"billing"],
                   @[@4200, @"Angular", @136, @-1, @"", @"console"], @[@5500, @"Flask", @36, @-1, @"idle", @"notes"],
                   @[@5181, @"Vite", @196, @7, @"", @"glossary"], @[@5182, @"Vite", @192, @5, @"", @"schema"],
                   @[@3002, @"Next.js", @430, @9, @"", @"budget"], @[@4001, @"Phoenix", @270, @3, @"", @"judge"],
                   @[@8001, @"FastAPI", @184, @2, @"", @"ranking"], @[@6007, @"Storybook", @505, @4, @"", @"fieldsets"]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *s = t[i];
        NSInteger port = [s[0] integerValue];
        BOOL idle = [s[4] isEqualToString:@"idle"], kept = [s[4] isEqualToString:@"kept"];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowServer, [NSString stringWithFormat:@"server:%ld", (long)port], [NSString stringWithFormat:@":%ld %@", (long)port, s[1]],
                                            [s[1] lowercaseString], [s[4] length] ? s[4] : nil, [s[2] unsignedLongLongValue] * MB, [s[3] integerValue] < 0 ? -1 : [s[3] integerValue] / 10.0);
        r.hour = MMWindowFixtureHour(r.bytes, r.key, i % 4);
        r.inFix = idle; r.quiet = idle;
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithArray:@[
            F(@"Port", @(port).stringValue), F(@"Project", i % 5 == 4 ? [NSString stringWithFormat:@"/Users/sam/code/%@-worktrees/review/apps/web", s[5]] : s[5]),
            F(@"Runs in", i % 3 ? @"Ghostty, tab 2" : @"Terminal"), F(@"Started by", i % 2 ? @"Claude Code" : @"launchd"),
            idle ? F(@"Idle", @"2h 10m") : F(@"Last used", @"3m ago"), F(@"Up", i % 2 ? @"1d 6h" : @"2h 36m")]];
        if (kept) { [facts addObject:F(@"Kept", @"for 1h 20m")]; [facts addObject:F(@"Stays", @"you asked to keep it")]; }
        r.facts = facts;
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureAgents(NSInteger count, NSInteger asking) {
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
        BOOL asks = i < asking, idle = !asks && [a[2] integerValue] < 0;
        MMWindowRow *r = MMWindowFixtureRow(MMWindowAgent, [NSString stringWithFormat:@"agent:%ld", (long)i], a[0], i % 3 == 2 ? @"codex" : @"claude-code",
                                            asks ? @"asks" : idle ? @"idle" : @"working", [a[1] unsignedLongLongValue] * MB, [a[2] integerValue] < 0 ? -1 : [a[2] integerValue] / 10.0);
        r.needsYou = asks; r.quiet = idle;
        r.hour = MMWindowFixtureHour(r.bytes, r.key, (i + 1) % 4);
        // The feed's Why is a raw fact of the agent's processes, and an idle agent has none.
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithArray:@[F(@"Agent", i % 3 == 2 ? @"Codex" : @"Claude Code"), F(@"Project", a[3]),
                                                                                 F(@"State", asks ? @"waits on you" : idle ? @"idle" : @"working")]];
        if (asks) [facts addObject:F(@"Why", @"a permission prompt is open")];
        else if (!idle) [facts addObject:F(@"Why", i % 2 ? @"child caffeinate" : @"status file busy")];
        r.facts = facts;
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureApps(NSInteger count) {
    // name, bundle id or "" for a helper, megabytes, CPU in tenths or -1, state, why it stays or ""
    NSArray *t = @[@[@"Safari", @"com.apple.Safari", @4915, @19, @"kept", @"it is on the keep list"],
                   @[@"Terminal", @"com.apple.Terminal", @4300, @21, @"kept", @"in use"],
                   @[@"Xcode", @"com.apple.dt.Xcode", @2765, @9, @"kept", @"it is on the keep list"],
                   @[@"localhost tabs", @"tabs", @1434, @-1, @"will close", @""],
                   @[@"Simulator", @"com.apple.iphonesimulator", @1126, @6, @"", @""],
                   @[@"language-server", @"", @905, @11, @"left behind", @""],
                   @[@"chrome-headless", @"", @640, @4, @"left behind", @""],
                   @[@"Music", @"com.apple.Music", @578, @1, @"will close", @""],
                   @[@"Mail", @"com.apple.mail", @420, @-1, @"kept", @"it is on the keep list"],
                   @[@"esbuild", @"", @380, @4, @"left behind", @""],
                   @[@"Notes", @"com.apple.Notes", @310, @-1, @"", @""],
                   @[@"Preview", @"com.apple.Preview", @280, @-1, @"", @""],
                   @[@"tsserver", @"", @210, @2, @"left behind", @""],
                   @[@"Calendar", @"com.apple.iCal", @190, @-1, @"", @""],
                   @[@"fsevents-watcher", @"", @120, @-1, @"left behind", @""]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *a = t[i];
        BOOL tabs = [a[1] isEqualToString:@"tabs"], helper = [a[1] length] == 0;
        MMWindowRow *r = MMWindowFixtureRow(tabs ? MMWindowTabs : helper ? MMWindowHelper : MMWindowApp, [NSString stringWithFormat:@"app:%ld", (long)i], a[0],
                                            tabs || helper ? nil : a[1], [a[4] length] ? a[4] : nil, [a[2] unsignedLongLongValue] * MB, [a[3] integerValue] < 0 ? -1 : [a[3] integerValue] / 10.0);
        if (tabs) r.tabs = 14;
        r.inFix = [a[4] isEqualToString:@"will close"];
        r.quiet = helper || tabs || (r.cpuPercent >= 0 && r.cpuPercent < 0.5);
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
        if (helper) [facts addObjectsFromArray:@[F(@"Left by", @"fix-auth-redirect"), F(@"Folder", @"~/code/atlas-worktrees/fix-auth-redirect")]];
        else if (tabs) [facts addObjectsFromArray:@[F(@"Open", @"14 tabs"), F(@"On", @":3001, :4321"), F(@"Left by", @"fix-auth-redirect")]];
        else {
            if (i < 2) [facts addObjectsFromArray:@[F(@"Used by", @"Claude Code"), F(@"Serves", @":3000, :3001, :6006")]];
            if ([a[5] length]) [facts addObject:F(@"Stays", a[5])];
        }
        r.facts = facts;
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureWorktrees(NSInteger count) {
    // name, state, megabytes of disk, in Fix Everything
    NSArray *t = @[@[@"dogfood", @"", @3144, @NO], @[@"fix-auth-redirect", @"merged", @1905, @YES], @[@"parity", @"kept", @1884, @NO],
                   @[@"media-scope", @"changed", @1393, @NO], @[@"speed-3-base", @"changed", @1331, @NO], @[@"bundle-split", @"merged", @1126, @YES],
                   @[@"sweep-403", @"", @1085, @NO], @[@"judge-scoring", @"changed", @990, @NO], @[@"fieldsets", @"merged", @900, @YES],
                   @[@"search-index", @"changed", @850, @NO], @[@"perf-budget", @"changed", @710, @NO], @[@"uploader-v2", @"", @690, @NO],
                   @[@"lane-c", @"changed", @650, @NO], @[@"icons-v1", @"merged", @590, @YES], @[@"glossary-import", @"changed", @490, @NO],
                   @[@"schema-diff", @"changed", @410, @NO], @[@"billing-cents", @"changed", @388, @NO], @[@"notes-export", @"", @342, @NO]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *w = t[i];
        NSString *state = w[1];
        BOOL changed = [state isEqualToString:@"changed"], merged = [state isEqualToString:@"merged"];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowWorktree, [@"worktree:" stringByAppendingString:w[0]], w[0], nil, state.length ? state : nil, [w[2] unsignedLongLongValue] * DMB, -1);
        r.inFix = [w[3] boolValue];
        r.quiet = !changed;
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithObject:F(@"Branch", w[0])];
        if (merged) [facts addObject:F(@"Merged", @"yes")];
        if (changed) { [facts addObject:F(@"Files", i % 2 ? @"3 changed, 1 new" : @"2 changed")]; [facts addObject:F(@"Not pushed", @"2 commits")]; }
        [facts addObject:F(@"Quiet", [NSString stringWithFormat:@"%ldd", (long)(1 + i)])];
        [facts addObject:F(@"Folder", [NSString stringWithFormat:@"~/code/%@-worktrees/%@", i % 2 ? @"studio" : @"atlas", w[0]])];
        if ([state isEqualToString:@"kept"]) [facts addObject:F(@"Stays", @"you asked to keep it")];
        r.facts = facts;
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureCaches(NSInteger count) {
    // name, state, megabytes of disk, kind, project, why it stays or ""
    NSArray *t = @[@[@"DerivedData", @"", @14541, @"Xcode build output", @"atlas", @""],
                   @[@"npm cache", @"kept", @6246, @"Package cache", @"", @"its own tool cleans it, on your press"],
                   @[@"Docker build cache", @"in use", @4300, @"Build cache", @"gateway", @"a running process has a file open in it"],
                   @[@"Playwright browsers", @"in use", @3380, @"Test browsers", @"studio", @"the newest set is in use"],
                   @[@"Simulators", @"kept", @800, @"Simulator data", @"", @"root owns it, so MinMacs only reports it"]];
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *c = t[i];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowCache, [NSString stringWithFormat:@"cache:%ld", (long)i], c[0], nil, [c[1] length] ? c[1] : nil, [c[2] unsignedLongLongValue] * DMB, -1);
        r.inFix = i == 0;
        r.quiet = ![c[1] isEqualToString:@"in use"];
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithObject:F(@"Kind", c[3])];
        if ([c[4] length]) [facts addObject:F(@"Project", c[4])];
        [facts addObject:F(@"Last used", [NSString stringWithFormat:@"%ldd ago", (long)(2 + i * 5)])];
        [facts addObject:F(@"Folder", i == 0 ? @"~/Library/Developer/Xcode/DerivedData" : [NSString stringWithFormat:@"~/Library/Caches/%@", [c[0] lowercaseString]])];
        if ([c[5] length]) [facts addObject:F(@"Stays", c[5])];
        r.facts = facts;
        [rows addObject:r];
    }
    return rows;
}

MMWindowGroup *MMWindowFixtureGroup(NSString *key, NSString *title, MMWindowSide side, NSArray<MMWindowRow *> *rows) {
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = key; g.title = title; g.side = side;
    g.emptyNote = @{@"servers": @"No servers found", @"agents": @"No agents found", @"apps": @"No apps found",
                    @"worktrees": @"No worktrees found", @"caches": @"No caches or leftovers found"}[key];
    g.rows = [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return a.bytes > b.bytes ? NSOrderedAscending : a.bytes < b.bytes ? NSOrderedDescending : NSOrderedSame; }];
    return g;
}

void MMWindowFixtureRing(MMWindowModel *m, uint64_t memoryUsed, uint64_t memoryTotal, uint64_t diskFree, uint64_t diskTotal) {
    MMWindowRing *ring = m.ring;
    ring.memoryUsed = memoryUsed; ring.memoryTotal = memoryTotal; ring.diskFree = diskFree; ring.diskTotal = diskTotal;
    // As Core cuts them: each group's slice is what its rows hold, cut to what is still left of the whole, then the rest.
    NSArray *(^slices)(NSArray<MMWindowGroup *> *, uint64_t) = ^NSArray *(NSArray<MMWindowGroup *> *groups, uint64_t used) {
        NSMutableArray *out = [NSMutableArray new];
        uint64_t left = used;
        for (MMWindowGroup *g in groups) {
            uint64_t sum = 0;
            for (MMWindowRow *r in g.rows) sum += r.bytes;
            MMWindowSlice *s = [MMWindowSlice new];
            s.group = g.key; s.bytes = MIN(sum, left); left -= s.bytes;
            [out addObject:s];
        }
        MMWindowSlice *rest = [MMWindowSlice new];
        rest.group = @"other"; rest.bytes = left;
        [out addObject:rest];
        return out;
    };
    ring.memory = slices(m.memoryGroups, memoryUsed);
    ring.disk = slices(m.diskGroups, diskTotal > diskFree ? diskTotal - diskFree : 0);
}
