// Fix Everything with an old removal choice in the pref, issue #62 and D2. Included by window.m, after controller.m.
// The same world and the same fixes as RunAll. An old "smart" or "delete" in the pref, as an older MinMacs wrote it,
// changes nothing: everything keeps a way back, and the end note says it truthfully for this run.

static void RunChoice(NSString *old) {
    MMSetPref(MMRemovalKey, old);
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    NSString *derived = Dir(@"library/DerivedData"), *spike = Dir(@"trees/old-spike"), *wrapped = Dir(@"trees/fix-auth-redirect");
    NSString *name = [@"old " stringByAppendingString:old];
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    NSMutableArray<MMWindowRun *> *seen = [NSMutableArray new];
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    __block MMWindowRun *end = nil;
    runner.onProgress = ^(MMWindowRun *r) {
        @synchronized (seen) { [seen addObject:r]; }
        if (!r.running) { end = r; dispatch_semaphore_signal(ended); }
    };
    NSFileManager *fm = NSFileManager.defaultManager;
    // The test home's Trash is shared with the modes that ran before, so the count is of this run only.
    NSUInteger trashBefore = [fm contentsOfDirectoryAtPath:MMTrashFolder() error:nil].count;
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T([name stringByAppendingString:@": the run ends"], @"yes", @"no"); MMSetPref(MMRemovalKey, nil); return; }
    NSUInteger inTrash = [fm contentsOfDirectoryAtPath:MMTrashFolder() error:nil].count - trashBefore;
    MMUndoRecord *tree = nil, *cache = nil;
    for (MMFixResult *x in runner.results) {
        if ([x.name isEqualToString:@"old-spike"]) tree = [MMUndo.shared record:x.rid];
        if ([x.name isEqualToString:@"DerivedData"]) cache = [MMUndo.shared record:x.rid];
    }
    NSString *saved = [tree.payload[@"recovery"] isKindOfClass:NSDictionary.class] ? tree.payload[@"recovery"][@"dir"] : nil;
    BOOL savedEnv = saved.length && [fm fileExistsAtPath:[saved stringByAppendingPathComponent:@".env"]];
    T([name stringByAppendingString:@": everything the run removes left its place"], @"no no no", [NSString stringWithFormat:@"%@ %@ %@", YN([fm fileExistsAtPath:derived]),
      YN([fm fileExistsAtPath:spike]), YN([fm fileExistsAtPath:wrapped])]);
    T([name stringByAppendingString:@": the cache step says where it goes"], @"yes", YN([Steps(seen) containsString:@"Moving DerivedData to the Trash"]));
    // The four removed things: node_modules, DerivedData and the two worktree folders, which this fixture trashes in git's place.
    T([name stringByAppendingString:@": nothing was deleted, and all four are in the test Trash"], @"4", @(inTrash));
    T([name stringByAppendingString:@": the end note says so"], @"Skipped 1 agent that asks you and 1 fix that needs your own press. "
      @"Moved 4 to the Trash. Files git ignores were saved in a recovery folder.", end.endNote);
    T([name stringByAppendingString:@": the records keep a way back"], @"trash 0 yes trash 0 yes yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@", tree.payload[@"removal"][@"choice"],
      tree.payload[@"removal"][@"deleted"], YN(tree.canRestore), cache.payload[@"removal"][@"choice"], cache.payload[@"removal"][@"deleted"], YN(cache.canRestore), YN(savedEnv)]);
    T([name stringByAppendingString:@": every step still left a finished record by manual"], @"yes", ({ BOOL ok = YES;
        for (MMFixResult *x in runner.results) { if (![x.outcome isEqualToString:@"done"]) continue;
            MMUndoRecord *r = x.rid ? [MMUndo.shared record:x.rid] : nil; if (!r || r.state != MMUndoDone || ![r.by isEqualToString:@"manual"]) ok = NO; }
        YN(ok); }));
    T([name stringByAppendingString:@": no shown string names an old app or says for good"], @"", Bad(@[end.endTitle ?: @"", end.endNote ?: @"", Steps(seen)]));
    __block NSString *problem = @"not run";
    dispatch_sync(MMQueue(@"windowtest", @"restore", QOS_CLASS_USER_INITIATED), ^{ problem = cache ? [MMUndo.shared restore:cache.rid] : @"no record"; });
    T([name stringByAppendingString:@": restore of the cache brings it back"], @"(nil) yes", [NSString stringWithFormat:@"%@ %@", problem ?: @"(nil)", YN([fm fileExistsAtPath:derived])]);
    MMSetPref(MMRemovalKey, nil);
}
