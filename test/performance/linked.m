// The busy world under a root that is a link, issue #101. Included by performance.m, before main.
// The index keeps each checkout by the root's path, with realPath resolved, and its git facts by that path, and each
// linked worktree a second time by its resolved path. WorkForest
// names its findings by the resolved path, and a cache is named here by the root's path, as a scan of that root does.
// Before, the remove fix matched the checkout by the kept path as text: the merged worktree outside the Wrap Up was
// no fix, the caches inside a removed worktree counted twice, and a folder held twice could plan two Wrap Ups. Every
// fix and part must read as under a plain root.

static void PerformanceLinked(void) {
    Busy();
    NSString *real = Dir(@""), *link = [real stringByAppendingString:@"-link"];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:real error:nil];
    NSString *(^kept)(NSString *) = ^NSString *(NSString *p) {
        return [p hasPrefix:[real stringByAppendingString:@"/"]] ? [link stringByAppendingString:[p substringFromIndex:real.length]] : p;
    };
    // Each linked worktree is held twice, as the index holds it: by the root's path from the walk, and by the resolved
    // path .git/worktrees names. The main checkout is walked only.
    NSMutableDictionary *git = [NSMutableDictionary new];
    NSMutableArray *twice = [NSMutableArray new];
    for (TWorktree *w in gTrees) {
        git[kept(w.path)] = gGit[w.path];
        if (!w.isMain) {
            TWorktree *r = [TWorktree new]; r.path = r.realPath = w.path; r.repo = kept(w.repo); r.branch = w.branch;
            [twice addObject:r]; git[w.path] = gGit[w.path];
        }
        w.realPath = w.path; w.path = kept(w.path); w.repo = kept(w.repo);
    }
    [gTrees addObjectsFromArray:twice];
    [gGit setDictionary:git];
    NSMutableArray *caches = [NSMutableArray new];
    for (MMFinding *f in gFindings[@"noonoo"]) {
        NSString *path = kept(f.path);
        [caches addObject:[MMFinding expert:f.expert kind:f.kind stableKey:f.stableKey build:^(MMFindingBuilder *b) {
            b.title = f.title; b.path = path; b.instanceKey = f.stableKey; b.cost = f.cost; b.proposal = f.proposal; b.facts = f.facts;
        }]];
    }
    gFindings[@"noonoo"] = caches;
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ p = [MMPerformance from:s history:Hour(8 * GB) lookBack:nil]; });

    MMPerformanceFix *wrap = nil, *rem = nil, *trash = nil;
    for (MMPerformanceFix *f in p.fixes) {
        if ([f.kind isEqualToString:@"wrapup"]) wrap = f; else if ([f.kind isEqualToString:@"remove"]) rem = f;
        else if ([f.kind isEqualToString:@"trash"]) trash = f;
    }
    T(@"linked: one fix per Wrap Up and per kind of action, as under a plain root", @"clean,quit,remove,stop,trash,wrapup",
      [[[[p.fixes valueForKey:@"kind"] sortedArrayUsingSelector:@selector(compare:)] valueForKey:@"description"] componentsJoinedByString:@","]);
    T(@"linked: remove holds the merged worktree outside the Wrap Up, by its finding's id", [@"1 5 workforest:worktree:" stringByAppendingString:Dir(@"trees/w2")],
      [NSString stringWithFormat:@"%lu %llu %@", (unsigned long)rem.rows.count, rem.diskBack / GB, rem.rows.firstObject]);
    T(@"linked: the Wrap Up gives back what it does under a plain root", @"364 2048",
      [NSString stringWithFormat:@"%llu %llu", wrap.memoryBack / MB, wrap.diskBack / MB]);
    NSUInteger wraps = 0;
    for (MMPerformanceFix *f in p.fixes) if ([f.kind isEqualToString:@"wrapup"]) wraps++;
    T(@"linked: the worktree held twice has one Wrap Up", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)wraps]);
    T(@"linked: trash leaves out the caches inside the Wrap Up and the removed worktree", @"noonoo:clutter:derived-data 14",
      [NSString stringWithFormat:@"%@ %llu", [trash.rows componentsJoinedByString:@","], trash.diskBack / GB]);
    T(@"linked: a cache inside a worktree counts in clutter, not twice", @"16 24",
      [NSString stringWithFormat:@"%llu %llu", [p.disk.parts[MMPerformanceWorktrees] unsignedLongLongValue] / GB,
       [p.disk.parts[MMPerformanceClutter] unsignedLongLongValue] / GB]);
}
