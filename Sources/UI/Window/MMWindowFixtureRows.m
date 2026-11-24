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

/// The facts that are there, in order: a fact with nothing to say is nil and left out, as in the feed.
static NSArray<MMWindowFact *> *Facts(NSArray *made) {
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    for (id f in made) if (f != NSNull.null) [out addObject:f];
    return out;
}
#define OR_NONE(f) ((f) ?: (id)NSNull.null)

NSArray<MMWindowRow *> *MMWindowFixtureServers(NSInteger count) {
    // port, framework, megabytes, CPU in tenths or -1, state, project
    NSArray *t = @[@[@3001, @"Next.js", @412, @6, @"", @"atlas"], @[@6006, @"Storybook", @520, @3, @"", @"icons"],
                   @[@3000, @"Next.js", @412, @-1, @"", @"studio"], @[@4000, @"Phoenix", @260, @-1, @"kept", @"lexicon"],
                   @[@49210, @"Claude Code", @306, @-1, @"", @"scoring"], @[@1313, @"Hugo", @60, @-1, @"idle", @"handbook"],
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
        // An agent's own port: Claude Code listens on it itself, so the server is named by the agent and says which
        // session it is, as the agent "Score answers" says it serves this port.
        if ([s[1] isEqualToString:@"Claude Code"]) {
            r.facts = Facts(@[MMWindowFactPort(port), MMWindowFactAgent(s[1]), MMWindowFactSession(@"Score answers"), MMWindowFactProject(s[5]),
                              MMWindowFactStartedBy(@"Terminal"), MMWindowFactLastUsed(180), MMWindowFactUp(2640)]);
            [rows addObject:r];
            continue;
        }
        r.facts = Facts(@[MMWindowFactPort(port), MMWindowFactProject(i % 5 == 4 ? [NSString stringWithFormat:@"/Users/sam/code/%@-worktrees/review/apps/web", s[5]] : s[5]),
                          MMWindowFactRunsIn(i % 3 ? @"Ghostty, tab 2" : @"Terminal"), MMWindowFactStartedBy(i % 4 == 3 ? @"cmux · parent exited" : i % 2 ? @"Claude Code" : @"launchd"),
                          idle ? MMWindowFactIdle(7800) : MMWindowFactLastUsed(i % 6 ? 180 : 4), MMWindowFactUp(i % 2 ? 108000 : 9360),
                          OR_NONE(kept ? MMWindowFactKept(4800) : nil), OR_NONE(kept ? MMWindowFactStays(@"you asked to keep it") : nil)]);
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureAgents(NSInteger count, NSInteger asking) {
    NSArray *t = @[@[@"Import the glossary", @695, @-1, @"glossary"], @[@"Score answers", @306, @-1, @"scoring"], @[@"Match studio views", @431, @-1, @"studio"],
                   @[@"Sort lane C by due", @763, @13, @"lane-c"], @[@"Write lane C fixtures now", @760, @140, @"lane-c"], @[@"Tune the ranking", @628, @3, @"ranking"],
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
        r.facts = Facts(@[MMWindowFactAgent(i % 3 == 2 ? @"Codex" : @"Claude Code"), MMWindowFactProject(a[3]), OR_NONE(i == 1 ? MMWindowFactServes(@[@49210]) : nil), MMWindowFactState(asks ? @"waits on you" : idle ? @"idle" : @"working")]);
        [rows addObject:r];
    }
    return rows;
}

void MMWindowFixtureAgentStories(NSArray<MMWindowRow *> *agents) {
    // As MMWindowAgentFacts tells them, Shell/MMWindowAgent.m. "Sort lane C by due" has every fact: its folder and
    // branch, how long it runs, what it did in the last hour, its cmux tab with Go to, its worktree with the pull
    // request, the server it started, its session's scratch and the processes under it. "Match studio views", Codex,
    // has no session facts: only what is known is said.
    if (agents.count > 3) {
        MMWindowRow *r = agents[3];
        r.goTo = @"cmux";
        r.facts = Facts(@[MMWindowFactAgent(@"Claude Code"), MMWindowFactProject(@"~/code/barkbot-worktrees/lane-c"), MMWindowFactBranch(@"lane-c"),
                          MMWindowFactUp(2 * 3600 + 36 * 60), MMWindowFactLastActive(5), MMWindowFactRecently(42, 6, 3600),
                          MMWindowFactRunsIn(@"cmux, barkbot, lane C"), MMWindowFactWorktree(@"barkbot · lane-c", @"worktree:lane-c"),
                          MMWindowFactPullRequest(142, @"open", NO, @"Phase 6"), MMWindowFactServes(@[@49211]),
                          MMWindowFactServer(@":5175 Vite", @"server:5175"), MMWindowFactCache(@"Claude Code scratch", 112 * DMB, YES, @"kin:noonoo:claude-code-scratch"),
                          MMWindowFactProcesses(14, 820 * MB), MMWindowFactState(@"working")]);
    }
    if (agents.count > 2) agents[2].facts = Facts(@[MMWindowFactAgent(@"Codex"), MMWindowFactState(@"idle")]);
}

NSArray<MMWindowRow *> *MMWindowFixtureApps(NSInteger count) {
    // name, bundle id or "" for a helper, megabytes, CPU in tenths or -1, state, why it stays or ""
    NSArray *t = @[@[@"Safari", @"com.apple.Safari", @4915, @19, @"kept", @"it is on the keep list"],
                   @[@"Terminal", @"com.apple.Terminal", @4300, @21, @"kept", @"in use"],
                   @[@"Xcode", @"com.apple.dt.Xcode", @2765, @9, @"kept", @"it is on the keep list"],
                   @[@"Safari", @"tabs", @1434, @-1, @"will close", @""],
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
        if (helper) r.facts = Facts(@[MMWindowFactLeftBy(@"fix-auth-redirect"), MMWindowFactFolder(@"~/code/atlas-worktrees/fix-auth-redirect")]);
        else if (tabs) r.facts = Facts(@[MMWindowFactOpenTabs(14), MMWindowFactOnPorts(@[@3001, @4321]), MMWindowFactLeftBy(@"fix-auth-redirect")]);
        else r.facts = Facts(@[OR_NONE(i < 2 ? MMWindowFactUsedBy(@"Claude Code") : nil), OR_NONE(i < 2 ? MMWindowFactServes(@[@3000, @3001, @6006]) : nil), OR_NONE(MMWindowFactStays(a[5]))]);
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureWorktrees(NSInteger count, NSInteger projects) {
    // branch, state, megabytes of disk, in Fix Everything, project, main checkout, seconds since the last work. Five
    // projects, as on a Mac where agents work in several repos at once: the first four rows are two of them.
    NSArray *t = @[@[@"dogfood", @"changed", @3144, @NO, @"minmacs", @NO, @40], @[@"fix-auth-redirect", @"merged", @1905, @YES, @"atlas", @NO, @(6 * 86400)],
                   @[@"main", @"kept", @1884, @NO, @"atlas", @YES, @(50 * 60)], @[@"media-scope", @"changed", @1393, @NO, @"minmacs", @NO, @(12 * 60)],
                   @[@"speed-3-base", @"changed", @1331, @NO, @"barkbot", @NO, @(2 * 3600)], @[@"bundle-split", @"merged", @1126, @YES, @"studio", @NO, @(11 * 86400)],
                   @[@"sweep-403", @"", @1085, @NO, @"gateway", @NO, @(3 * 86400)], @[@"judge-scoring", @"changed", @990, @NO, @"barkbot", @NO, @(25 * 60)],
                   @[@"fieldsets", @"merged", @900, @YES, @"studio", @NO, @(14 * 86400)], @[@"search-index", @"changed", @850, @NO, @"atlas", @NO, @(3 * 3600)],
                   @[@"perf-budget", @"changed", @710, @NO, @"minmacs", @NO, @(5 * 3600)], @[@"uploader-v2", @"", @690, @NO, @"gateway", @NO, @(4 * 86400)],
                   @[@"lane-c", @"changed", @650, @NO, @"barkbot", @NO, @86400], @[@"icons-v1", @"merged", @590, @YES, @"studio", @NO, @(20 * 86400)],
                   @[@"glossary-import", @"changed", @490, @NO, @"atlas", @NO, @(7 * 3600)], @[@"schema-diff", @"changed", @410, @NO, @"gateway", @NO, @(9 * 3600)],
                   @[@"billing-cents", @"changed", @388, @NO, @"barkbot", @NO, @(2 * 86400)], @[@"notes-export", @"", @342, @NO, @"studio", @NO, @(30 * 86400)]];
    // The made-up now that every last work is counted back from, so a render is the same on every run.
    const NSTimeInterval now = 1800000000;
    NSMutableArray *rows = [NSMutableArray new];
    for (NSInteger i = 0; i < MIN(count, (NSInteger)t.count); i++) {
        NSArray *w = t[i];
        NSString *state = w[1], *branch = w[0], *project = projects == 1 ? @"atlas" : w[4];
        BOOL changed = [state isEqualToString:@"changed"], main = [w[5] boolValue] && projects != 1;
        NSTimeInterval ago = [w[6] doubleValue];
        // As MMWindowNameOf names them: a main checkout by its repo, a linked worktree by its repo and branch.
        NSString *key = main ? [@"worktree:" stringByAppendingString:project] : [@"worktree:" stringByAppendingString:branch];
        NSString *name = main ? project : [NSString stringWithFormat:@"%@ · %@", project, branch];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowWorktree, key, name, nil, state.length ? state : nil, [w[2] unsignedLongLongValue] * DMB, -1);
        r.project = project; r.nameInProject = main ? MMWindowMainCheckout : branch; r.workedAt = now - ago;
        r.inFix = [w[3] boolValue];
        r.quiet = !changed;
        NSString *folder = main ? [@"~/code/" stringByAppendingString:project] : [NSString stringWithFormat:@"~/code/%@-worktrees/%@", project, branch];
        r.facts = Facts(@[MMWindowFactBranch(branch), OR_NONE(changed ? MMWindowFactFiles(i % 2 ? 3 : 2, i % 2 ? 1 : 0) : nil), OR_NONE(changed ? MMWindowFactNotPushed(2) : nil),
                          MMWindowFactUntouched(ago), MMWindowFactFolder(folder),
                          OR_NONE([state isEqualToString:@"kept"] ? MMWindowFactStays(main ? @"it is the repo's main checkout" : @"you asked to keep it") : nil)]);
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
        r.facts = Facts(@[MMWindowFactKind(c[3]), OR_NONE(MMWindowFactOwner(c[4])), MMWindowFactLastUsed(86400.0 * (2 + i * 5)),
                          MMWindowFactFolder(i == 0 ? @"~/Library/Developer/Xcode/DerivedData" : [NSString stringWithFormat:@"~/Library/Caches/%@", [c[0] lowercaseString]]),
                          OR_NONE(MMWindowFactStays(c[5]))]);
        [rows addObject:r];
    }
    return rows;
}

NSArray<MMWindowRow *> *MMWindowFixtureLeftovers(void) {
    // As Noo-Noo and the feed make them, Shell/MMWindowRows.m: one row a temp-folder family, named by its prefix, in one
    // temp folder, each with its split as its why. 169 families of the owner's Mac, three of them in use.
    NSArray<NSString *> *names = @[@"MMArgs", @"MMAct", @"MMRepoIndex", @"MMUndo", @"MMSizer", @"MMGitFacts", @"swift-build", @"clang-module", @"vite-deps",
                                   @"tsc-watch", @"jest-cache", @"esbuild-meta", @"go-link", @"pytest-run", @"cargo-install"];
    NSString *folder = @"/private/var/folders/x4/k7_2l9qn1s5c/T";
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    NSInteger folders = 0;
    for (NSInteger i = 0; i < 169; i++) {
        NSString *prefix = i < (NSInteger)names.count ? names[(NSUInteger)i] : [NSString stringWithFormat:@"build-%03ld", (long)i];
        BOOL live = i == 4 || i == 61 || i == 130;
        NSInteger members = i == 168 ? 45282 - folders : 240 + (i * 37) % 40;
        folders += members;
        MMWindowRow *r = MMWindowFixtureRow(MMWindowCache, [NSString stringWithFormat:@"noonoo:clutter:tmpdir-families:%@-", prefix], [prefix stringByAppendingString:@"-* folders"], nil,
                                            live ? @"in use" : nil, (uint64_t)(2400 - i * 13) * 2000, -1);
        r.inFix = !live; r.quiet = !live;
        NSString *why = live ? @"a running process has a file open in it" : [NSString stringWithFormat:@"%ld old and empty", (long)members];
        r.facts = Facts(@[MMWindowFactKind(@"Temp folder families"), MMWindowFactFolder(folder), MMWindowFactStays(why)]);
        MMWindowKin *k = [MMWindowKin new];
        k.key = @"noonoo:tmpdir-families"; k.title = @"Temp folders left by tools"; k.one = @"group"; k.many = @"groups";
        k.innerOne = @"folder"; k.innerMany = @"folders"; k.inner = members;
        k.path = [NSString stringWithFormat:@"%@/%@-*", folder, prefix]; k.canGo = !live; k.why = live ? why : nil;
        r.kin = k;
        [rows addObject:r];
    }
    // Claude Code's scratch of four sessions, one of them still running.
    NSArray<NSString *> *sessions = @[@"3f9a21c0", @"b71e0d44", @"c02f9e1a", @"e8d4a7b2"];
    for (NSUInteger i = 0; i < sessions.count; i++) {
        BOOL live = i == 2;
        MMWindowRow *r = MMWindowFixtureRow(MMWindowCache, [@"noonoo:clutter:claude-code-scratch:" stringByAppendingString:sessions[i]], @"Claude Code scratch", nil,
                                            live ? @"in use" : nil, (uint64_t)(1200 - 260 * i) * DMB, -1);
        r.inFix = !live; r.quiet = !live;
        NSString *why = live ? @"its session is still running" : @"its session ended 9 d ago";
        r.facts = Facts(@[MMWindowFactKind(@"Claude Code scratch"), MMWindowFactOwner([@"session " stringByAppendingString:sessions[i]]),
                          MMWindowFactFolder([NSString stringWithFormat:@"/private/tmp/claude-501/-Users-sam-code/%@", sessions[i]]), MMWindowFactStays(why)]);
        MMWindowKin *k = [MMWindowKin new];
        k.key = @"noonoo:claude-code-scratch"; k.title = @"Claude Code scratch"; k.one = @"session"; k.many = @"sessions";
        k.path = [@"/private/tmp/claude-501/-Users-sam-code/" stringByAppendingString:sessions[i]]; k.canGo = !live; k.why = live ? why : nil;
        r.kin = k;
        [rows addObject:r];
    }
    return rows;
}

MMWindowGroup *MMWindowFixtureGroup(NSString *key, NSString *title, MMWindowSide side, NSArray<MMWindowRow *> *rows) {
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = key; g.title = title; g.side = side;
    g.emptyNote = MMWindowEmptyNote(key, MMWindowLookedDone);
    // The worktrees as the feed orders them: by project, the most active first.
    if ([key isEqualToString:@"worktrees"]) { g.byProject = YES; g.rows = MMWindowByProject(rows); return g; }
    // As the feed orders them: the measured rows biggest first, then the ones not measured yet.
    g.rows = [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) {
        if (a.unmeasured != b.unmeasured) return a.unmeasured ? NSOrderedDescending : NSOrderedAscending;
        return a.bytes > b.bytes ? NSOrderedAscending : a.bytes < b.bytes ? NSOrderedDescending : NSOrderedSame;
    }];
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
