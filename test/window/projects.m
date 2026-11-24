// The worktrees by project. Included by window.m, after unmeasured.m.
// The owner asked for the Worktrees group to come by project, so that with more than one project each one shows its
// most active worktree first. A project is a worktree finding's repo. Here three repos hold seven worktrees, worked on
// at known times, and a world of one repo holds two. The list's sub-headers and its share of the room are drawn by
// the view and checked by tools/render.sh; this checks the model the feed makes: the names, the order and the JSON.

static void Projects(void) {
    World();
    NSTimeInterval now = floor(NSDate.date.timeIntervalSince1970);
    const uint64_t DMB = 1000 * 1000;
    // repo folder, branch, main checkout, minutes since the last work (below 0: not known), megabytes
    NSArray *t = @[@[@"atlas", @"main", @YES, @600, @900], @[@"atlas", @"fix-login", @NO, @5, @300], @[@"atlas", @"old-spike", @NO, @(9 * 1440), @2000],
                   @[@"barkbot", @"main", @YES, @30, @700], @[@"barkbot", @"lane-c", @NO, @30, @800],
                   @[@"minmacs", @"seam-130", @NO, @-1, @100], @[@"minmacs", @"main", @YES, @(2 * 1440), @400]];
    NSMutableArray *found = [NSMutableArray new];
    for (NSArray *w in t) {
        NSString *repo = Dir(w[0]), *branch = w[1];
        BOOL main = [w[2] boolValue];
        NSString *path = main ? repo : Dir([NSString stringWithFormat:@"%@-trees/%@", w[0], branch]);
        NSMutableDictionary *facts = [@{@"path": path, @"repo": repo, @"branch": branch, @"main": @(main), @"merged": NSNull.null, @"dirty": @0,
                                        @"untracked": @0, @"unpushed": @0, @"sized": @YES, @"missing": @NO} mutableCopy];
        if ([w[3] integerValue] >= 0) facts[@"lastWorkAt"] = @(now - [w[3] doubleValue] * 60);
        [found addObject:Finding(@"workforest", @"worktree", path, [NSString stringWithFormat:@"%@/%@", w[0], branch], path, 0, 0,
                                 [w[4] unsignedLongLongValue] * DMB, nil, facts)];
    }
    gFindings[@"workforest"] = found;
    MMSnapshot *s = WorldSnapshot();
    MMWindowModel *m = MMWindowModelFrom(s, Build(s), [MMWindowExtras readWithLogin:YES]);
    MMWindowGroup *trees = m.diskGroups[0];

    // The names: a main checkout by its repo and a linked worktree by repo and branch, as before. Under its project's
    // sub-header a row needs only its branch, or says it is the main checkout.
    NSMutableArray *names = [NSMutableArray new], *inProject = [NSMutableArray new], *projects = [NSMutableArray new];
    for (MMWindowRow *r in trees.rows) { [names addObject:r.name]; [inProject addObject:r.nameInProject ?: @"(nil)"]; [projects addObject:r.project ?: @"(nil)"]; }
    // atlas leads: its fix-login was worked on 5 min ago. barkbot's two were worked on at one time, 30 min ago, so the
    // bigger leads. minmacs comes last: its main checkout 2 days ago, and seam-130, with no time known, after it.
    T(@"projects: the projects by their most active worktree, each project's worktrees by activity, a tie by size, an unknown time last",
      @"atlas · fix-login | atlas | atlas · old-spike | barkbot · lane-c | barkbot | minmacs | minmacs · seam-130", [names componentsJoinedByString:@" | "]);
    T(@"projects: a row's name under its project's sub-header is its branch, or main checkout",
      @"fix-login | main checkout | old-spike | lane-c | main checkout | main checkout | seam-130", [inProject componentsJoinedByString:@" | "]);
    T(@"projects: each worktree's project is its repo's folder", @"atlas atlas atlas barkbot barkbot minmacs minmacs", [projects componentsJoinedByString:@" "]);
    T(@"projects: the group comes by project, shows sub-headers with three projects, and only the worktrees do", @"yes yes no no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(trees.byProject), YN(trees.grouped), YN(m.diskGroups[1].byProject), YN(m.memoryGroups[0].byProject)]);
    T(@"projects: MMWindowProjectsOf names each project once, in the group's order", @"atlas barkbot minmacs",
      [MMWindowProjectsOf(trees.rows) componentsJoinedByString:@" "]);
    MMWindowRow *fix = trees.rows[0], *seam = trees.rows[6];
    T(@"projects: a row's last work is its lastWorkAt, and 0 when not known", @"yes 0",
      [NSString stringWithFormat:@"%@ %.0f", YN(fabs(fix.workedAt - (now - 300)) < 1), seam.workedAt]);
    NSDictionary *j = trees.json, *row = j[@"rows"][0];
    T(@"projects: --json says the group comes by project, and each row its project and last work", @"1 atlas yes null",
      [NSString stringWithFormat:@"%@ %@ %@ %@", j[@"byProject"], row[@"project"], YN([row[@"workedAt"] doubleValue] > 0), j[@"rows"][6][@"workedAt"] == NSNull.null ? @"null" : @"set"]);
    T(@"projects: the more lines say how many wait and where", @"3 more in barkbot | 1 more | 12 more in 4 projects | 1 more in 1 project",
      [@[MMWindowProjectMoreLine(3, @"barkbot"), MMWindowProjectMoreLine(1, nil), MMWindowProjectsMoreLine(12, 4), MMWindowProjectsMoreLine(1, 1)] componentsJoinedByString:@" | "]);

    // The same rows in another order come out the same: the order is the rows' own, not the order they came in.
    NSArray *reversed = MMWindowByProject(trees.rows.reverseObjectEnumerator.allObjects);
    T(@"projects: the order holds whatever order the rows came in", @"yes", YN([[reversed valueForKey:@"key"] isEqualToArray:[trees.rows valueForKey:@"key"]]));

    // One repo: the list is flat, as before, the most active first.
    World();
    NSString *one = Dir(@"solo"), *two = Dir(@"solo-trees/next");
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", one, @"solo", one, 0, 0, 5000 * DMB, nil,
                @{@"path": one, @"repo": one, @"branch": @"main", @"main": @YES, @"merged": NSNull.null, @"dirty": @0, @"untracked": @0, @"unpushed": @0, @"lastWorkAt": @(now - 86400)}),
        Finding(@"workforest", @"worktree", two, @"solo/next", two, 0, 0, 100 * DMB, nil,
                @{@"path": two, @"repo": one, @"branch": @"next", @"main": @NO, @"merged": NSNull.null, @"dirty": @1, @"untracked": @0, @"unpushed": @0, @"lastWorkAt": @(now - 60)})];
    MMSnapshot *s2 = WorldSnapshot();
    MMWindowGroup *solo = MMWindowModelFrom(s2, Build(s2), [MMWindowExtras readWithLogin:YES]).diskGroups[0];
    T(@"projects: with one project the group shows no sub-header, and its rows keep their names, the most active first", @"yes no solo · next | solo",
      [NSString stringWithFormat:@"%@ %@ %@", YN(solo.byProject), YN(solo.grouped), [[solo.rows valueForKey:@"name"] componentsJoinedByString:@" | "]]);
}
