// Two more made-up days for the render's checks.
// "real" has the shape of what the feed made on a working Mac, from a recorded `minmacs window --json`, with every
// name changed: a 16 GB Mac, a 245 GB disk, servers whose Project is a long path, agents with long titles, apps
// whose rows hold more together than the Mac has in use, since an app holds its servers, and no hour yet.
// "extreme", "extreme-running" and "extreme-done" hold what must never break the window: 120 servers, names of sixty
// characters with spaces and without, sizes at the edges of their units, the longest step and the longest end note
// the runner can make.
#import "UI/Window/MMWindowFixtureParts.h"

static const uint64_t MB = MMFixMB, GB = MMFixGB, DMB = MMFixDiskMB, DGB = MMFixDiskGB;

static NSArray<MMWindowFact *> *Facts(NSArray *made) {
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    for (id f in made) if (f != NSNull.null) [out addObject:f];
    return out;
}
#define OR_NONE(f) ((f) ?: (id)NSNull.null)

static MMWindowFix *Fix(NSString *key, NSString *title, uint64_t memory, uint64_t disk, BOOL needsYou) {
    MMWindowFix *f = [MMWindowFix new];
    f.key = key; f.title = title; f.memoryBack = memory; f.diskBack = disk; f.needsYou = needsYou;
    return f;
}

static MMWindowModel *Real(void) {
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    // port, name, megabytes, state, project, started by, up
    NSArray *st = @[@[@5432, @"Postgres", @1803, @"kept", @"/opt/homebrew/var/postgresql@17", @"launchd", @108000],
                    @[@58968, @"Agent", @688, @"", @"Agent", @"launchd", @108000],
                    @[@9367, @"Google Chrome", @541, @"", @"/Volumes/Work/github/page-editor-wt/marks-ci", @"cmux · parent exited", @9360],
                    @[@18789, @"node", @456, @"", @"node", @"launchd", @108000],
                    @[@56784, @"BEAM", @197, @"", @"/Volumes/Work/dev-caches/tmp/agent-code/agent-501/-Volumes-Work-github-parkbench/d2e0bec6-c416-4758-a794-96bebe269ac4/scratchpad/orchestrate/wt/desk-a-hint/api", @"Claude Code", @120],
                    @[@58491, @"Google Chrome", @143, @"idle", @"/Volumes/Work/github/helperbot-wt/resume-1", @"cmux · parent exited", @8400],
                    @[@5217, @"Vite", @121, @"", @"/Volumes/Work/github/page-editor-wt/marks-ci", @"Claude Code", @2460],
                    @[@57150, @"node", @96, @"idle", @"/Volumes/Work/github/parkbench-studio", @"cmux · parent exited", @10920],
                    @[@22885, @"ControlCenter", @44, @"", @"ControlCenter", @"launchd", @108000]];
    NSMutableArray<MMWindowRow *> *servers = [NSMutableArray new];
    for (NSArray *s in st) {
        BOOL idle = [s[3] isEqualToString:@"idle"];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowServer, [NSString stringWithFormat:@"server:%@", s[0]], [NSString stringWithFormat:@":%@ %@", s[0], s[1]], [s[1] lowercaseString],
                                            [s[3] length] ? s[3] : nil, [s[2] unsignedLongLongValue] * MB, 0);
        r.quiet = idle;
        r.facts = Facts(@[MMWindowFactPort([s[0] integerValue]), MMWindowFactProject(s[4]), MMWindowFactStartedBy(s[5]), OR_NONE(idle ? MMWindowFactIdle(7800) : nil),
                          MMWindowFactUp([s[6] doubleValue])]);
        [servers addObject:r];
    }
    // title, megabytes, state, project, harness
    NSArray *at = @[@[@"Phoenix Parkbench Studio parity with the desk", @1326, @"working", @"parkbench", @"Claude Code"], @[@"Menu window look", @911, @"working", @"github", @"Claude Code"],
                    @[@"Review the polish pass of today", @767, @"working", @"github", @"Claude Code"], @[@"Docs sweep, the third wave", @641, @"idle", @"github", @"Claude Code"],
                    @[@"Barkdown round-trip fixtures", @610, @"working", @"parkbench", @"Claude Code"], @[@"Grok Bot", @412, @"idle", @"/", @"Grok Bot"],
                    @[@"github", @388, @"working", @"github", @"Claude Code"], @[@"Lane C, the sorting", @301, @"idle", @"parkbench-studio", @"Claude Code"],
                    @[@"Home folder", @260, @"idle", @"sam", @"Codex"], @[@"page-editor", @244, @"working", @"page-editor", @"Claude Code"],
                    @[@"helperbot", @190, @"idle", @"helperbot", @"Codex"], @[@"Oracle reads, round nine", @171, @"working", @"page-editor", @"Claude Code"]];
    NSMutableArray<MMWindowRow *> *agents = [NSMutableArray new];
    for (NSUInteger i = 0; i < at.count; i++) {
        NSArray *a = at[i];
        BOOL idle = [a[2] isEqualToString:@"idle"];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowAgent, [NSString stringWithFormat:@"agent:%lu", (unsigned long)i], a[0], [a[4] isEqualToString:@"Codex"] ? @"codex" : @"claude-code", a[2],
                                            [a[1] unsignedLongLongValue] * MB, 0);
        r.quiet = idle;
        r.facts = Facts(@[MMWindowFactAgent(a[4]), OR_NONE(MMWindowFactProject(a[3])), MMWindowFactState(a[2])]);
        (void)idle;
        [agents addObject:r];
    }
    // name, megabytes, state, serves, stays
    NSArray *pt = @[@[@"cmux", @7344, @"kept", @[@9367, @5217, @58491, @57150, @56784], @"it is on the keep list"], @[@"Google Chrome", @4109, @"", @"", @""],
                    @[@"ControlCenter", @2360, @"", @[@22885], @""], @[@"Finder", @1184, @"kept", @"", @"it is on the keep list"], @[@"Messages", @448, @"", @"", @""],
                    @[@"Notes", @307, @"kept", @"", @"it is on the keep list"], @[@"Preview", @260, @"", @"", @""], @[@"Activity Monitor", @214, @"", @"", @""],
                    @[@"System Settings", @188, @"", @"", @""], @[@"Calendar", @150, @"", @"", @""], @[@"Reminders", @122, @"", @"", @""], @[@"Keychain Access", @96, @"", @"", @""],
                    @[@"TextEdit", @71, @"", @"", @""]];
    NSMutableArray<MMWindowRow *> *apps = [NSMutableArray new];
    for (NSUInteger i = 0; i < pt.count; i++) {
        NSArray *a = pt[i];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowApp, [NSString stringWithFormat:@"app:%lu", (unsigned long)i], a[0], nil, [a[2] length] ? a[2] : nil, [a[1] unsignedLongLongValue] * MB, 0);
        r.quiet = YES;
        r.facts = Facts(@[OR_NONE([a[3] isKindOfClass:NSArray.class] ? MMWindowFactServes(a[3]) : nil), OR_NONE(MMWindowFactStays(a[4]))]);
        [apps addObject:r];
    }
    MMWindowRow *polish = MMWindowFixtureRow(MMWindowWorktree, @"worktree:window-polish", @"window-polish", nil, @"changed", 1860 * DMB, -1);
    polish.facts = Facts(@[MMWindowFactBranch(@"window-polish"), MMWindowFactFiles(3, 1), MMWindowFactNotPushed(2), MMWindowFactUntouched(0), MMWindowFactFolder(@"/Volumes/Work/github/menus-worktrees/window-polish")]);
    MMWindowRow *choice = MMWindowFixtureRow(MMWindowWorktree, @"worktree:removal-choice", @"removal-choice", nil, @"merged", 800 * DMB, -1);
    choice.inFix = YES; choice.quiet = YES;
    choice.facts = Facts(@[MMWindowFactBranch(@"removal-choice"), MMWindowFactUntouched(12 * 86400.0), MMWindowFactFolder(@"/Volumes/Work/github/menus-worktrees/removal-choice")]);
    MMWindowRow *derived = MMWindowFixtureRow(MMWindowCache, @"cache:0", @"DerivedData", nil, nil, 14000 * DMB, -1);
    derived.facts = Facts(@[MMWindowFactKind(@"Xcode build output"), MMWindowFactOwner(@"menus"), MMWindowFactLastUsed(9 * 86400.0), MMWindowFactFolder(@"~/Library/Developer/Xcode/DerivedData")]);
    m.memoryGroups = @[MMWindowFixtureGroup(@"servers", @"Servers", MMWindowMemory, servers), MMWindowFixtureGroup(@"agents", @"Agents", MMWindowMemory, agents),
                       MMWindowFixtureGroup(@"apps", @"Apps and helpers", MMWindowMemory, apps)];
    m.diskGroups = @[MMWindowFixtureGroup(@"worktrees", @"Worktrees", MMWindowDisk, @[polish, choice]), MMWindowFixtureGroup(@"caches", @"Caches", MMWindowDisk, @[derived])];
    MMWindowFixtureRing(m, 13996654592ull, 17179869184ull, 38651658240ull, 245107195904ull);
    m.fixes = @[Fix(@"remove:merged", @"Remove 1 merged worktree", 0, 800 * DMB, NO)];
    return m;
}

static MMWindowModel *Extreme(NSString *name) {
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    NSString *spaced = @"Review every button page of the release before it goes out", *solid = @"averyveryverylongsinglewordbranchnamewithnobreakanywhereinit0";
    NSMutableArray<MMWindowRow *> *servers = [NSMutableArray new];
    for (NSInteger i = 0; i < 120; i++) {
        MMWindowRow *r = MMWindowFixtureRow(MMWindowServer, [NSString stringWithFormat:@"server:%ld", (long)(3000 + i)],
                                            i == 0 ? [NSString stringWithFormat:@":3000 %@", solid] : i == 1 ? [NSString stringWithFormat:@":3001 %@", spaced] : [NSString stringWithFormat:@":%ld Vite", (long)(3000 + i)],
                                            @"vite", i % 7 == 3 ? @"idle" : nil, (uint64_t)(999 - i * 7) * MB, i % 3 ? 0.4 * (i % 9) : 104.0);
        r.hour = MMWindowFixtureHour(r.bytes, r.key, i % 4);
        r.quiet = i % 7 == 3; r.inFix = i % 7 == 3;
        r.facts = Facts(@[MMWindowFactPort(3000 + i), MMWindowFactProject([NSString stringWithFormat:@"/Users/sam/code/%@/apps/site-%ld", solid, (long)i]), MMWindowFactStartedBy(@"cmux · parent exited"), MMWindowFactUp(9360)]);
        [servers addObject:r];
    }
    MMWindowRow *asks = MMWindowFixtureRow(MMWindowAgent, @"agent:0", spaced, @"claude-code", @"asks", 1023 * MB, 3.2);
    asks.needsYou = YES;
    asks.facts = Facts(@[MMWindowFactAgent(@"Claude Code"), MMWindowFactProject(solid), MMWindowFactState(@"waits on you")]);
    MMWindowRow *works = MMWindowFixtureRow(MMWindowAgent, @"agent:1", solid, @"codex", @"working", GB, 99.6);
    works.facts = Facts(@[MMWindowFactAgent(@"Codex"), OR_NONE(MMWindowFactProject(@"/")), MMWindowFactState(@"working")]);
    MMWindowRow *app = MMWindowFixtureRow(MMWindowApp, @"app:0", [spaced stringByAppendingString:@" Helper (Renderer)"], nil, @"kept", (uint64_t)(9.96 * GB), -1);
    app.facts = Facts(@[MMWindowFactServes(@[@3000, @3001, @3002, @3003, @3004, @3005, @3006, @3007, @3008, @3009, @3010, @3011]), MMWindowFactStays(@"it is on the keep list")]);
    MMWindowRow *tabs = MMWindowFixtureRow(MMWindowTabs, @"app:1", @"Safari", nil, @"will close", 0, -1);
    tabs.tabs = 1; tabs.inFix = YES; tabs.quiet = YES;
    tabs.facts = Facts(@[MMWindowFactOpenTabs(1), MMWindowFactOnPorts(@[@3003]), MMWindowFactLeftBy(solid)]);
    MMWindowRow *tree = MMWindowFixtureRow(MMWindowWorktree, @"worktree:0", solid, nil, @"merged", (uint64_t)(1023.6 * DGB), -1);
    tree.inFix = YES; tree.quiet = YES;
    tree.facts = Facts(@[MMWindowFactBranch(solid), MMWindowFactUntouched(112 * 86400.0), MMWindowFactFolder([@"~/code/atlas-worktrees/" stringByAppendingString:solid])]);
    MMWindowRow *tree2 = MMWindowFixtureRow(MMWindowWorktree, @"worktree:1", [spaced stringByReplacingOccurrencesOfString:@" " withString:@"-"], nil, @"changed", (uint64_t)(99.96 * DGB), -1);
    tree2.facts = Facts(@[MMWindowFactBranch(tree2.name), MMWindowFactFiles(1204, 88), MMWindowFactNotPushed(312), MMWindowFactUntouched(0), MMWindowFactFolder([@"~/code/atlas-worktrees/" stringByAppendingString:tree2.name])]);
    MMWindowRow *cache = MMWindowFixtureRow(MMWindowCache, @"cache:0", [spaced stringByAppendingString:@" cache"], nil, @"in use", 999 * DMB, -1);
    cache.facts = Facts(@[MMWindowFactKind(@"Build cache of a tool with a very long name indeed"), MMWindowFactLastUsed(0), MMWindowFactFolder([@"~/Library/Caches/" stringByAppendingString:solid]),
                          MMWindowFactStays(@"a running process has a file open in it")]);
    // Wide letters: a name of few characters that is wider than many of Latin ones, with its hour and CPU beside it.
    NSArray<NSString *> *wide = @[@"日本語のとても長いブランチ名です。", @"WWWWWWWWWWWWWWWWWW", @"🚀🚀🚀🚀🚀 ship it 🚀🚀🚀🚀🚀", @"مراجعة كل صفحات الأزرار قبل الإصدار"];
    NSMutableArray<MMWindowRow *> *agents = [NSMutableArray arrayWithObjects:asks, works, nil];
    for (NSUInteger i = 0; i < wide.count; i++) {
        MMWindowRow *r = MMWindowFixtureRow(MMWindowAgent, [NSString stringWithFormat:@"agent:wide%lu", (unsigned long)i], wide[i], @"claude-code", @"working", (600 - 50 * i) * MB, 12.5);
        r.hour = MMWindowFixtureHour(r.bytes, r.key, (NSInteger)i);
        r.facts = Facts(@[MMWindowFactAgent(@"Claude Code"), MMWindowFactProject(wide[i]), MMWindowFactState(@"working")]);
        [agents addObject:r];
    }
    m.memoryGroups = @[MMWindowFixtureGroup(@"servers", @"Servers", MMWindowMemory, servers), MMWindowFixtureGroup(@"agents", @"Agents", MMWindowMemory, agents),
                       MMWindowFixtureGroup(@"apps", @"Apps and helpers", MMWindowMemory, @[app, tabs])];
    m.diskGroups = @[MMWindowFixtureGroup(@"worktrees", @"Worktrees", MMWindowDisk, @[tree, tree2]), MMWindowFixtureGroup(@"caches", @"Caches", MMWindowDisk, @[cache])];
    m.asks = MMWindowAsksLine(1);
    MMWindowFixtureRing(m, 127 * GB, 128 * GB, (uint64_t)(0.4 * DGB), 4000 * DGB);
    m.fixes = @[Fix(@"wrapup:0", [@"Wrap Up " stringByAppendingString:solid], 2 * GB, (uint64_t)(1023.6 * DGB), NO), Fix(@"stop:idle", @"Stop 17 idle servers", 14 * GB, 0, NO),
                Fix(@"clean:0", [@"Clean " stringByAppendingString:cache.name], 0, 14 * DGB, YES)];
    if ([name isEqualToString:@"extreme"]) return m;
    MMWindowRun *run = [MMWindowRun new];
    run.total = m.fixCount; run.memoryPlanned = m.memoryBack; run.diskPlanned = m.diskBack;
    if ([name isEqualToString:@"extreme-running"]) {
        // A name far too long for the button: four names' worth.
        run.running = YES; run.done = 0; run.stepAction = @"Wrapping up";
        run.step = [NSString stringWithFormat:@"Wrapping up %@ %@ %@ %@", solid, spaced, solid, spaced];
    } else {
        // Every skip the runner can name, then its two tail sentences, Shell/MMFixRunner.m.
        run.done = 1; run.memoryBack = 2 * GB; run.diskBack = 3 * DGB;
        run.endTitle = @"1 of 2 fixes done";
        run.endNote = @"Skipped 12 agents that ask you, 3 fixes that need your own press, 14 kept since they changed or are in use, 6 blocked, 5 things in the fix you stopped partway and 2 fixes you stopped. "
                      @"Deleted 3, moved 2 to the Trash and kept 1 in a recovery folder. Files git ignores were saved in a recovery folder.";
    }
    m.run = run;
    return m;
}

MMWindowModel *MMWindowFixtureMore(NSString *name) {
    if ([name isEqualToString:@"real"]) return Real();
    if ([name hasPrefix:@"extreme"]) return Extreme(name);
    return nil;
}
