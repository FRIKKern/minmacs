// Near-identical rows as one, DESIGN rule 16. Included by window.m, after overlap.m.
// The owner's Caches held 169 rows of one registry row, tmpdir-families, each "657 old and empty": one row in the window
// now, with the totals, a merged quiet word and its biggest members in its story. The CLI keeps each one apart.
// The family findings have the shape Noo-Noo writes, Sources/Experts/NooNoo/MMNooNooExpert.m, with each one's path a
// folder of this tool's fixtures, so a run's removals move only what this tool made, into the test home's Trash.

static NSDictionary *FamilyWords(void) {
    return @{@"title": @"Temp folders left by tools", @"one": @"group", @"many": @"groups", @"innerOne": @"folder", @"innerMany": @"folders"};
}

/// One temp-folder family as Noo-Noo's finding of it: its path a fixture folder holding a file, its members and
/// leftovers counted, free or live. A live one has no proposal: Fix Everything leaves it.
static MMFinding *Family(NSInteger i, BOOL live, NSInteger members) {
    NSString *name = [NSString stringWithFormat:@"MMFam%03ld-", (long)i];
    NSString *dir = Dir([@"T/" stringByAppendingString:name]);
    [@"fixture\n" writeToFile:[dir stringByAppendingPathComponent:@"left"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *fx = [@{@"kindID": @"tmpdir-families", @"kindTitle": @"Temp folder families", @"class": @"leak", @"name": [name stringByAppendingString:@"* folders"],
                                 @"path": [[dir stringByDeletingLastPathComponent] stringByAppendingPathComponent:[name stringByAppendingString:@"*"]],
                                 @"members": @(members), @"leftovers": @(live ? 0 : members), @"state": live ? @"live" : @"free", @"section": live ? @"kept" : @"leftovers",
                                 @"collapse": FamilyWords(), @"why": live ? @"a running process has a file open in it" : [NSString stringWithFormat:@"%ld old and empty", (long)members]} mutableCopy];
    if (live) fx[@"keep"] = @"a running process has a file open in it";
    // Sizes differ, so the biggest are known: family i holds (i + 1) MB that may go.
    return Finding(@"noonoo", @"clutter", [@"tmpdir-families:" stringByAppendingString:name], fx[@"name"], dir, 0, 0, (uint64_t)(i + 1) * 1000 * 1000,
                   live ? nil : P(@"remove", MMReversibleTrash), fx);
}

static MMFinding *Scratch(NSString *session, uint64_t bytes) {
    NSString *dir = Dir([@"scratch/" stringByAppendingString:session]);
    return Finding(@"noonoo", @"clutter", [@"claude-code-scratch:" stringByAppendingString:session], @"Claude Code scratch", dir, 0, 0, bytes, P(@"remove", MMReversibleTrash),
                   @{@"kindID": @"claude-code-scratch", @"kindTitle": @"Claude Code scratch", @"name": @"Claude Code scratch", @"state": @"free", @"path": dir,
                     @"owner": [@"session " stringByAppendingString:session], @"collapse": @{@"title": @"Claude Code scratch", @"one": @"session", @"many": @"sessions"}});
}

static MMFinding *Modules(NSString *project, NSString *state, NSString *keep, NSString *inside) {
    NSString *dir = Dir([NSString stringWithFormat:@"code/%@/%@node_modules", project, inside ?: @""]);
    NSMutableDictionary *fx = [@{@"kindID": @"node-modules", @"kindTitle": @"node_modules", @"name": @"node_modules", @"state": state, @"path": dir, @"owner": project,
                                 @"collapse": @{@"title": @"node_modules", @"one": @"project", @"many": @"projects"}} mutableCopy];
    if (keep) fx[@"keep"] = keep;
    return Finding(@"noonoo", @"clutter", [@"node-modules:" stringByAppendingString:dir], [@"node_modules in " stringByAppendingString:project], dir, 0, 0,
                   500ull * 1000 * 1000, keep ? nil : P(@"remove", MMReversibleTrash), fx);
}

static MMWindowGroup *Caches(MMWindowModel *m) { return m.diskGroups[1]; }
static MMWindowFact *FactOf(MMWindowRow *r, NSString *label) { for (MMWindowFact *f in r.facts) if ([f.label isEqualToString:label]) return f; return nil; }

static void Collapse(void) {
    World();
    NSMutableArray *clutter = [NSMutableArray new];
    NSInteger folders = 0;
    uint64_t familyBytes = 0, goBytes = 0;
    // 169 families, three of them in use, holding 45,282 folders together.
    for (NSInteger i = 0; i < 169; i++) {
        BOOL live = i % 60 == 7;
        NSInteger members = i == 168 ? 45282 - folders : 250 + i % 20;
        folders += members;
        familyBytes += (uint64_t)(i + 1) * 1000 * 1000;
        if (!live) goBytes += (uint64_t)(i + 1) * 1000 * 1000;
        [clutter addObject:Family(i, live, members)];
    }
    // Two sessions' scratch: below three, each its own row.
    [clutter addObject:Scratch(@"a1b2c3d4", 300ull * 1000 * 1000)];
    [clutter addObject:Scratch(@"e5f6a7b8", 200ull * 1000 * 1000)];
    // node_modules in three projects, one of them kept: one row, its states merged.
    [clutter addObject:Modules(@"atlas", @"free", nil, nil)];
    [clutter addObject:Modules(@"barkbot", @"free", nil, nil)];
    [clutter addObject:Modules(@"helperbot", @"kept", @"an agent works in the project", nil)];
    // Three of a kin where one lies inside another: one row still, whose size counts the outer two only.
    [clutter addObject:Finding(@"noonoo", @"clutter", @"dist:a", @"dist", Dir(@"web/dist"), 0, 0, 100ull * 1000 * 1000, nil,
                               @{@"kindID": @"dist-build", @"kindTitle": @"dist", @"name": @"dist", @"state": @"free", @"path": Dir(@"web/dist")})];
    [clutter addObject:Finding(@"noonoo", @"clutter", @"dist:b", @"dist", Dir(@"web/dist/inner/dist"), 0, 0, 40ull * 1000 * 1000, nil,
                               @{@"kindID": @"dist-build", @"kindTitle": @"dist", @"name": @"dist", @"state": @"free", @"path": Dir(@"web/dist/inner/dist")})];
    [clutter addObject:Finding(@"noonoo", @"clutter", @"dist:c", @"dist", Dir(@"api/dist"), 0, 0, 30ull * 1000 * 1000, nil,
                               @{@"kindID": @"dist-build", @"kindTitle": @"dist", @"name": @"dist", @"state": @"free", @"path": Dir(@"api/dist")})];
    gFindings[@"noonoo"] = clutter;
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    MMWindowGroup *caches = Caches(m);

    MMWindowRow *fam = [m row:@"kin:noonoo:tmpdir-families"], *mods = [m row:@"kin:noonoo:node-modules"];
    NSInteger scratch = 0, dist = 0, apart = 0;
    for (MMWindowRow *r in caches.rows) {
        if ([r.name isEqualToString:@"Claude Code scratch"]) scratch++;
        if ([r.name isEqualToString:@"dist"]) dist++;
        if ([r.key hasPrefix:@"noonoo:clutter:tmpdir-families:"]) apart++;
    }
    T(@"collapse: Performance keeps all 169 families apart, and the window shows them as one row", @"177 1 0",
      [NSString stringWithFormat:@"%lu %@ %ld", (unsigned long)p.diskGroups[1].rows.count, fam ? @"1" : @"0", (long)apart]);
    T(@"collapse: Caches holds the family row, two scratch rows, the node_modules row and one dist row", @"5 2 1 yes",
      [NSString stringWithFormat:@"%lu %ld %ld %@", (unsigned long)caches.rows.count, (long)scratch, (long)dist, YN(mods != nil)]);
    MMWindowRow *dists = [m row:@"kin:noonoo:dist-build"];
    T(@"collapse: a kin with one member inside another is one row that counts what lies inside once: size, count and --json", @"130 2 folders 3 1",
      [NSString stringWithFormat:@"%llu %@ %@ %@", dists.bytes / (1000 * 1000), FactOf(dists, @"Holds").value, dists.json[@"collapsed"][@"count"], dists.json[@"collapsed"][@"inside"]]);
    T(@"collapse: the row is named in plain words from its registry row, and holds every member, biggest first", @"Temp folders left by tools 169 MMFam168-* folders",
      [NSString stringWithFormat:@"%@ %lu %@", fam.name, (unsigned long)fam.members.count, fam.members.firstObject.name]);
    T(@"collapse: its size is the members' sum, true since none holds another", @(familyBytes), @(fam.bytes));
    T(@"collapse: its totals, as its second line says them", @"45,282 folders in 169 groups", FactOf(fam, @"Holds").value);
    T(@"collapse: some are in use, so its word is in use, and the story says how many can go", @"in use | 166 groups can go, 3 in use | a running process has a file open in it",
      [NSString stringWithFormat:@"%@ | %@ | %@", fam.state, FactOf(fam, @"Now").value, FactOf(fam, @"Why some stay").value]);
    T(@"collapse: it goes with Fix Everything, says the split after the lead, and is not quiet while a fix touches it", @"yes Goes with Fix Everything. 166 groups can go, 3 in use.",
      [NSString stringWithFormat:@"%@ %@ %@", YN(fam.inFix), fam.fate.lead, fam.fate.note]);
    T(@"collapse: the story's facts are the totals, the kind and why some stay; the split is the first line", @"Holds Kind Why some stay",
      [[fam.storyFacts valueForKey:@"label"] componentsJoinedByString:@" "]);
    NSInteger famPlace = (NSInteger)[caches.rows indexOfObject:fam], modsPlace = (NSInteger)[caches.rows indexOfObject:mods];
    T(@"collapse: the one row sorts by its size among the others", @"yes", YN(famPlace >= 0 && modsPlace >= 0 && famPlace < modsPlace && fam.bytes > mods.bytes));

    // Mixed states below: two projects free, one kept.
    T(@"collapse: node_modules in three projects is one row, kept by one of them", @"kept | 3 projects | 2 projects can go, 1 kept | an agent works in the project",
      [NSString stringWithFormat:@"%@ | %@ | %@ | %@", mods.state, FactOf(mods, @"Holds").value, FactOf(mods, @"Now").value, FactOf(mods, @"Why some stay").value]);

    // Fix Everything: one trash fix still acts on each member, and counts the family row once in its title.
    MMPerformanceFix *trash = nil;
    for (MMPerformanceFix *f in p.fixes) if ([f.kind isEqualToString:@"trash"]) trash = f;
    MMWindowFix *wtrash = nil;
    for (MMWindowFix *f in m.fixes) if ([f.key isEqualToString:@"trash"]) wtrash = f;
    uint64_t trashWant = goBytes + 2 * 500ull * 1000 * 1000 + 500ull * 1000 * 1000;   // the families that go, node_modules in two projects, the scratch
    T(@"collapse: the trash fix acts on each family that goes, and gives back what they hold", @"170 yes",
      [NSString stringWithFormat:@"%lu %@", (unsigned long)trash.actions.count, YN(trash.diskBack == trashWant)]);
    T(@"collapse: its title counts what the window shows: the family row once, the node_modules row once and two scratch rows",
      @"Move 4 leftovers to the Trash", wtrash.title);
    T(@"collapse: the button's count and the gains are Performance's own", @"yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN(m.fixCount == (NSInteger)[[p.fixes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"needsYou == NO"]] count]),
       YN(m.memoryBack == p.memoryBackOnce), YN(m.diskBack == ({ uint64_t n = 0; for (MMPerformanceFix *f in p.fixes) if (!f.needsYou) n += f.diskBack; n; }))]);

    // --json says the row stands for several, with each member whole.
    NSDictionary *j = fam.json;
    T(@"collapse: --json says collapsed, with the count and every member", @"169 169 noonoo:tmpdir-families yes",
      [NSString stringWithFormat:@"%@ %lu %@ %@", j[@"collapsed"][@"count"], (unsigned long)[j[@"collapsed"][@"members"] count], j[@"collapsed"][@"kin"],
       YN([j[@"collapsed"][@"members"][0][@"key"] hasPrefix:@"noonoo:clutter:tmpdir-families:"])]);
    T(@"collapse: a row that stands alone has no collapsed key", @"no", YN([[caches.rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"members == nil"]].lastObject json][@"collapsed"] != nil));

    // Every family's own facts are still there for `clutter list`, which reads the findings: none was merged in Core.
    NSInteger findings = 0;
    for (MMFinding *f in s.findings) if ([f.facts[@"kindID"] isEqual:@"tmpdir-families"]) findings++;
    T(@"collapse: the snapshot still holds 169 family findings", @(169), @(findings));

    // Below the threshold no row merges; at it they do.
    MMWindowRow *(^cache)(NSString *, NSString *) = ^MMWindowRow *(NSString *key, NSString *kin) {
        MMWindowRow *r = [MMWindowRow new]; r.key = key; r.kind = MMWindowCache; r.name = @"x"; r.bytes = 10;
        r.kin = [MMWindowKin new]; r.kin.key = kin; r.kin.path = [@"/fixture/" stringByAppendingString:key]; r.kin.canGo = YES;
        return r;
    };
    NSArray *two = @[cache(@"a", @"k"), cache(@"b", @"k")], *three = @[cache(@"a", @"k"), cache(@"b", @"k"), cache(@"c", @"k")];
    T(@"collapse: two of a kin stand apart, three are one row", @"2 1 30 3 groups can go",
      [NSString stringWithFormat:@"%lu %lu %llu %@", (unsigned long)MMWindowCollapsed(two).count, (unsigned long)MMWindowCollapsed(three).count,
       MMWindowCollapsed(three).firstObject.bytes, MMWindowCollapsedSplit(3, 0, 0, 0, @"group", @"groups")]);
    T(@"collapse: the split's words", @"1 group can go | 2 sessions in use, 1 stays | 1 project kept | 3 groups can go, 1 in use, 2 kept, 1 stays",
      [@[MMWindowCollapsedSplit(1, 0, 0, 0, @"group", @"groups"), MMWindowCollapsedSplit(0, 2, 0, 1, @"session", @"sessions"),
         MMWindowCollapsedSplit(0, 0, 1, 0, @"project", @"projects"), MMWindowCollapsedSplit(3, 1, 2, 1, @"group", @"groups")] componentsJoinedByString:@" | "]);
    T(@"collapse: the members line", @"Its 4 projects | The 5 biggest of its 169 groups",
      [NSString stringWithFormat:@"%@ | %@", MMWindowMembersLine(4, 4, @"project", @"projects"), MMWindowMembersLine(5, 169, @"group", @"groups")]);
}

/// Helpers of one name left by one worktree: one row when their trees are apart, and apart when one holds another.
static void CollapseHelpers(void) {
    World();
    NSString *w1 = Dir(@"trees/fix-auth-redirect");
    NSMutableArray *parts = [gParts[w1] mutableCopy];
    for (pid_t pid = 71040; pid < 71043; pid++) {
        Proc(pid, 50 * MB);
        [parts addObject:Finding(@"minmacs", @"helper", [NSString stringWithFormat:@"%@#node-%d", w1, pid], @"node", w1, pid, 50 * MB, 0,
                                 P(@"stop", MMReversibleRestart), @{@"name": @"node", @"cwd": w1, @"worktree": w1})];
    }
    gParts[w1] = parts;
    MMSnapshot *s = WorldSnapshot();
    MMWindowModel *m = MMWindowModelFrom(s, Build(s), [MMWindowExtras readWithLogin:YES]);
    MMWindowRow *node = nil;
    for (MMWindowRow *r in m.memoryGroups[2].rows) if (r.members && [r.name isEqualToString:@"node"]) node = r;
    T(@"collapse: three node helpers left by one worktree are one row of three processes, their memory summed", @"3 processes 150 left behind yes",
      [NSString stringWithFormat:@"%@ %llu %@ %@", FactOf(node, @"Holds").value, node.bytes / MB, node.state, YN(node.inFix)]);
    // One helper is the child of another: their trees overlap, so the sum would count it twice.
    gChildren[@71040] = @[@71041];
    MMSnapshot *s2 = WorldSnapshot();
    MMWindowModel *m2 = MMWindowModelFrom(s2, Build(s2), [MMWindowExtras readWithLogin:YES]);
    NSInteger nodes = 0, one = 0;
    for (MMWindowRow *r in m2.memoryGroups[2].rows) { if ([r.name isEqualToString:@"node"]) nodes++; if (r.members) one++; }
    T(@"collapse: helpers whose trees hold one another stay apart", @"3 0", [NSString stringWithFormat:@"%ld %ld", (long)nodes, (long)one]);
}

/// Fix Everything over a collapsed row: each family is its own action and record, and Undo takes one back alone.
static void CollapseRun(void) {
    World();
    // Clutter alone: no worktree, so no Wrap Up, and no other fix.
    gFindings[@"locohost"] = @[]; gFindings[@"minmacs"] = @[]; gFindings[@"workforest"] = @[]; gParts = [NSMutableDictionary new];
    [gTrees removeAllObjects]; [gGit removeAllObjects]; [gSessions removeAllObjects]; [gAgents removeAllObjects];
    NSMutableArray *clutter = [NSMutableArray new];
    for (NSInteger i = 0; i < 12; i++) [clutter addObject:Family(200 + i, i == 5, 300)];
    gFindings[@"noonoo"] = clutter;
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    MMWindowRow *fam = [m row:@"kin:noonoo:tmpdir-families"];
    T(@"collapse run: twelve families are one row, and Fix Everything is one fix of eleven", @"1 1 11 Move 1 leftover to the Trash",
      [NSString stringWithFormat:@"%lu %ld %lu %@", (unsigned long)Caches(m).rows.count, (long)m.fixCount, (unsigned long)p.fixes.firstObject.actions.count, m.fixes.firstObject.title]);
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    __block MMWindowRun *end = nil;
    runner.onProgress = ^(MMWindowRun *r) { if (!r.running) { end = r; dispatch_semaphore_signal(ended); } };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) { T(@"collapse run: the run ends", @"yes", @"no"); return; }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *rids = [NSMutableArray new];
    for (MMFixResult *x in runner.results) if ([x.outcome isEqualToString:@"done"] && x.rid) [rids addObject:x.rid];
    uint64_t want = 0;
    for (id<MMAction> a in p.fixes.firstObject.actions) want += a.finding.cost.diskFreed;
    T(@"collapse run: one fix done, one record a family, and the disk back is what the fix planned", @"1 fix done 11 yes yes",
      [NSString stringWithFormat:@"%@ %lu %@ %@", end.endTitle, (unsigned long)[NSSet setWithArray:rids].count, YN(end.diskPlanned == want), YN(end.diskPlanned == m.diskBack)]);
    NSInteger inTrash = 0, kept = 0;
    for (id<MMAction> a in p.fixes.firstObject.actions) if (![fm fileExistsAtPath:a.finding.path]) inTrash++;
    for (MMFinding *f in clutter) if (!f.proposal && [fm fileExistsAtPath:f.path]) kept++;
    T(@"collapse run: every family that could go left its place, and the one in use stayed", @"11 1", [NSString stringWithFormat:@"%ld %ld", (long)inTrash, (long)kept]);
    // Undo of one family brings that family alone back.
    MMUndoRecord *first = [MMUndo.shared record:rids.firstObject];
    NSString *back = first.findingID;
    __block NSString *problem = @"not run";
    dispatch_sync(MMQueue(@"windowtest", @"restore", QOS_CLASS_USER_INITIATED), ^{ problem = [MMUndo.shared restore:rids.firstObject]; });
    NSInteger here = 0;
    NSString *backPath = nil;
    for (id<MMAction> a in p.fixes.firstObject.actions) {
        if ([a.finding.findingID isEqualToString:back]) backPath = a.finding.path;
        if ([fm fileExistsAtPath:a.finding.path]) here++;
    }
    T(@"collapse run: Undo of one record brings its family back, and only it", @"(nil) yes 1",
      [NSString stringWithFormat:@"%@ %@ %ld", problem ?: @"(nil)", YN(backPath && [fm fileExistsAtPath:[backPath stringByAppendingPathComponent:@"left"]]), (long)here]);
    T(@"collapse run: the family row stood for all twelve", @(12), @(fam.members.count));
}
