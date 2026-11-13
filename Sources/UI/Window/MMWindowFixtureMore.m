// Two more made-up days for the render's checks.
// "real" has the shape of what the feed made on a working Mac, from a recorded `minmacs window --json`, with every
// name changed: a 16 GB Mac, a 245 GB disk, servers whose Project is a long path, agents with long titles, apps
// whose rows hold more together than the Mac has in use, since an app holds its servers, and no hour yet.
// "extreme", "extreme-running" and "extreme-done" hold what must never break the window: 120 servers, names of sixty
// characters with spaces and without, sizes at the edges of their units, the longest step and the longest end note
// the runner can make.
#import "UI/Window/MMWindowFixtureParts.h"

static const uint64_t MB = MMFixMB, GB = MMFixGB, DMB = MMFixDiskMB, DGB = MMFixDiskGB;

static MMWindowFact *F(NSString *label, NSString *value) { return [MMWindowFact label:label value:value]; }

static MMWindowFix *Fix(NSString *key, NSString *title, uint64_t memory, uint64_t disk, BOOL needsYou) {
    MMWindowFix *f = [MMWindowFix new];
    f.key = key; f.title = title; f.memoryBack = memory; f.diskBack = disk; f.needsYou = needsYou;
    return f;
}

static MMWindowModel *Real(void) {
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    // port, name, megabytes, state, project, started by, up
    NSArray *st = @[@[@5432, @"Postgres", @1803, @"kept", @"/opt/homebrew/var/postgresql@17", @"launchd", @"1d 6h"],
                    @[@58968, @"Agent", @688, @"", @"Agent", @"launchd", @"1d 6h"],
                    @[@9367, @"Google Chrome", @541, @"", @"/Volumes/Work/github/page-editor-wt/marks-ci", @"cmux · parent exited", @"2h 36m"],
                    @[@18789, @"node", @456, @"", @"node", @"launchd", @"1d 6h"],
                    @[@56784, @"BEAM", @197, @"", @"/Volumes/Work/dev-caches/tmp/agent-code/agent-501/-Volumes-Work-github-parkbench/d2e0bec6-c416-4758-a794-96bebe269ac4/scratchpad/orchestrate/wt/desk-a-hint/api", @"Claude Code", @"2m"],
                    @[@58491, @"Google Chrome", @143, @"idle", @"/Volumes/Work/github/helperbot-wt/resume-1", @"cmux · parent exited", @"2h 20m"],
                    @[@5217, @"Vite", @121, @"", @"/Volumes/Work/github/page-editor-wt/marks-ci", @"Claude Code", @"41m"],
                    @[@57150, @"node", @96, @"idle", @"/Volumes/Work/github/parkbench-studio", @"cmux · parent exited", @"3h 2m"],
                    @[@22885, @"ControlCenter", @44, @"", @"ControlCenter", @"launchd", @"1d 6h"]];
    NSMutableArray<MMWindowRow *> *servers = [NSMutableArray new];
    for (NSArray *s in st) {
        BOOL idle = [s[3] isEqualToString:@"idle"];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowServer, [NSString stringWithFormat:@"server:%@", s[0]], [NSString stringWithFormat:@":%@ %@", s[0], s[1]], [s[1] lowercaseString],
                                            [s[3] length] ? s[3] : nil, [s[2] unsignedLongLongValue] * MB, 0);
        r.quiet = idle;
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithArray:@[F(@"Port", [s[0] stringValue]), F(@"Project", s[4]), F(@"Started by", s[5])]];
        if (idle) [facts addObject:F(@"Idle", @"2h 10m")];
        [facts addObject:F(@"Up", s[6])];
        r.facts = facts;
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
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray arrayWithArray:@[F(@"Agent", a[4]), F(@"Project", a[3]), F(@"State", a[2])]];
        if (!idle) [facts addObject:F(@"Why", @"child caffeinate")];
        r.facts = facts;
        [agents addObject:r];
    }
    // name, megabytes, state, serves, stays
    NSArray *pt = @[@[@"cmux", @7344, @"kept", @":9367, :5217, :58491, :57150, :56784", @"it is on the keep list"], @[@"Google Chrome", @4109, @"", @"", @""],
                    @[@"ControlCenter", @2360, @"", @":22885", @""], @[@"Finder", @1184, @"kept", @"", @"it is on the keep list"], @[@"Messages", @448, @"", @"", @""],
                    @[@"Notes", @307, @"kept", @"", @"it is on the keep list"], @[@"Preview", @260, @"", @"", @""], @[@"Activity Monitor", @214, @"", @"", @""],
                    @[@"System Settings", @188, @"", @"", @""], @[@"Calendar", @150, @"", @"", @""], @[@"Reminders", @122, @"", @"", @""], @[@"Keychain Access", @96, @"", @"", @""],
                    @[@"TextEdit", @71, @"", @"", @""]];
    NSMutableArray<MMWindowRow *> *apps = [NSMutableArray new];
    for (NSUInteger i = 0; i < pt.count; i++) {
        NSArray *a = pt[i];
        MMWindowRow *r = MMWindowFixtureRow(MMWindowApp, [NSString stringWithFormat:@"app:%lu", (unsigned long)i], a[0], nil, [a[2] length] ? a[2] : nil, [a[1] unsignedLongLongValue] * MB, 0);
        r.quiet = YES;
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
        if ([a[3] length]) [facts addObject:F(@"Serves", a[3])];
        if ([a[4] length]) [facts addObject:F(@"Stays", a[4])];
        r.facts = facts;
        [apps addObject:r];
    }
    MMWindowRow *polish = MMWindowFixtureRow(MMWindowWorktree, @"worktree:window-polish", @"window-polish", nil, @"changed", 1860 * DMB, -1);
    polish.facts = @[F(@"Branch", @"window-polish"), F(@"Files", @"3 changed, 1 new"), F(@"Not pushed", @"2 commits"), F(@"Quiet", @"0s"), F(@"Folder", @"/Volumes/Work/github/menus-worktrees/window-polish")];
    MMWindowRow *choice = MMWindowFixtureRow(MMWindowWorktree, @"worktree:removal-choice", @"removal-choice", nil, @"merged", 800 * DMB, -1);
    choice.inFix = YES; choice.quiet = YES;
    choice.facts = @[F(@"Branch", @"removal-choice"), F(@"Merged", @"yes"), F(@"Quiet", @"12d"), F(@"Folder", @"/Volumes/Work/github/menus-worktrees/removal-choice")];
    MMWindowRow *derived = MMWindowFixtureRow(MMWindowCache, @"cache:0", @"DerivedData", nil, nil, 14000 * DMB, -1);
    derived.facts = @[F(@"Kind", @"Xcode build output"), F(@"Project", @"menus"), F(@"Last used", @"9d ago"), F(@"Folder", @"~/Library/Developer/Xcode/DerivedData")];
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
        r.facts = @[F(@"Port", @(3000 + i).stringValue), F(@"Project", [NSString stringWithFormat:@"/Users/sam/code/%@/apps/site-%ld", solid, (long)i]), F(@"Started by", @"cmux · parent exited"), F(@"Up", @"2h 36m")];
        [servers addObject:r];
    }
    MMWindowRow *asks = MMWindowFixtureRow(MMWindowAgent, @"agent:0", spaced, @"claude-code", @"asks", 1023 * MB, 3.2);
    asks.needsYou = YES;
    asks.facts = @[F(@"Agent", @"Claude Code"), F(@"Project", solid), F(@"State", @"waits on you"), F(@"Why", @"a permission prompt is open")];
    MMWindowRow *works = MMWindowFixtureRow(MMWindowAgent, @"agent:1", solid, @"codex", @"working", GB, 99.6);
    works.facts = @[F(@"Agent", @"Codex"), F(@"Project", @"/"), F(@"State", @"working"), F(@"Why", @"child caffeinate")];
    MMWindowRow *app = MMWindowFixtureRow(MMWindowApp, @"app:0", [spaced stringByAppendingString:@" Helper (Renderer)"], nil, @"kept", (uint64_t)(9.96 * GB), -1);
    app.facts = @[F(@"Serves", @":3000, :3001, :3002, :3003, :3004, :3005, :3006, :3007, :3008, :3009, :3010, :3011"), F(@"Stays", @"it is on the keep list")];
    MMWindowRow *tabs = MMWindowFixtureRow(MMWindowTabs, @"app:1", @"localhost tabs", nil, @"will close", 0, -1);
    tabs.tabs = 1; tabs.inFix = YES; tabs.quiet = YES;
    tabs.facts = @[F(@"Open", @"1 tab"), F(@"On", @":3003"), F(@"Left by", solid)];
    MMWindowRow *tree = MMWindowFixtureRow(MMWindowWorktree, @"worktree:0", solid, nil, @"merged", (uint64_t)(1023.6 * DGB), -1);
    tree.inFix = YES; tree.quiet = YES;
    tree.facts = @[F(@"Branch", solid), F(@"Merged", @"yes"), F(@"Quiet", @"112d"), F(@"Folder", [@"~/code/atlas-worktrees/" stringByAppendingString:solid])];
    MMWindowRow *tree2 = MMWindowFixtureRow(MMWindowWorktree, @"worktree:1", [spaced stringByReplacingOccurrencesOfString:@" " withString:@"-"], nil, @"changed", (uint64_t)(99.96 * DGB), -1);
    tree2.facts = @[F(@"Branch", tree2.name), F(@"Files", @"1204 changed, 88 new"), F(@"Not pushed", @"312 commits"), F(@"Quiet", @"0s"), F(@"Folder", [@"~/code/atlas-worktrees/" stringByAppendingString:tree2.name])];
    MMWindowRow *cache = MMWindowFixtureRow(MMWindowCache, @"cache:0", [spaced stringByAppendingString:@" cache"], nil, @"in use", 999 * DMB, -1);
    cache.facts = @[F(@"Kind", @"Build cache of a tool with a very long name indeed"), F(@"Last used", @"now"), F(@"Folder", [@"~/Library/Caches/" stringByAppendingString:solid]),
                    F(@"Stays", @"a running process has a file open in it")];
    m.memoryGroups = @[MMWindowFixtureGroup(@"servers", @"Servers", MMWindowMemory, servers), MMWindowFixtureGroup(@"agents", @"Agents", MMWindowMemory, @[asks, works]),
                       MMWindowFixtureGroup(@"apps", @"Apps and helpers", MMWindowMemory, @[app, tabs])];
    m.diskGroups = @[MMWindowFixtureGroup(@"worktrees", @"Worktrees", MMWindowDisk, @[tree, tree2]), MMWindowFixtureGroup(@"caches", @"Caches", MMWindowDisk, @[cache])];
    m.asks = @"1 agent asks you";
    MMWindowFixtureRing(m, 127 * GB, 128 * GB, (uint64_t)(0.4 * DGB), 4000 * DGB);
    m.fixes = @[Fix(@"wrapup:0", [@"Wrap Up " stringByAppendingString:solid], 2 * GB, (uint64_t)(1023.6 * DGB), NO), Fix(@"stop:idle", @"Stop 17 idle servers", 14 * GB, 0, NO),
                Fix(@"clean:0", [@"Clean " stringByAppendingString:cache.name], 0, 14 * DGB, YES)];
    if ([name isEqualToString:@"extreme"]) return m;
    MMWindowRun *run = [MMWindowRun new];
    run.total = m.fixCount; run.memoryPlanned = m.memoryBack; run.diskPlanned = m.diskBack;
    if ([name isEqualToString:@"extreme-running"]) {
        run.running = YES; run.done = 0; run.step = [@"Wrapping up " stringByAppendingString:solid];
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
