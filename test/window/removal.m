// Fix Everything under the Trash choice and under Delete, issue #62. Included by window.m, after controller.m.
// The same world and the same fixes as RunAll, which runs under Smart. Only where removed things go differs, and the
// end note must say it truthfully for this run.

static void RunChoice(MMRemovalChoice choice) {
    MMSetRemovalChoice(choice);
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    NSString *derived = Dir(@"library/DerivedData"), *spike = Dir(@"trees/old-spike"), *wrapped = Dir(@"trees/fix-auth-redirect");
    NSString *name = MMRemovalChoiceName(choice);
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
    if (choice == MMRemovalTrash) {
        T(@"trash: the cache step says where it goes", @"yes", YN([Steps(seen) containsString:@"Moving DerivedData to the Trash"]));
        // The four removed things: node_modules, DerivedData and the two worktree folders, which this fixture trashes in git's place.
        T(@"trash: nothing was deleted, and all four are in the test Trash", @"4", @(inTrash));
        T(@"trash: the end note says so", @"Skipped 1 agent that asks you and 1 fix that needs your own press. "
          @"Moved 4 to the Trash. Files git ignores were saved in a recovery folder.", end.endNote);
        T(@"trash: the records keep a way back", @"0 yes 0 yes yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@", tree.payload[@"removal"][@"deleted"], YN(tree.canRestore),
          cache.payload[@"removal"][@"deleted"], YN(cache.canRestore), YN(savedEnv)]);
    } else {
        T(@"delete: the cache step says it is deleted", @"yes", YN([Steps(seen) containsString:@"Deleting DerivedData"]));
        T(@"delete: nothing went to the Trash", @"0", @(inTrash));
        T(@"delete: the end note says so, and names no recovery folder", @"Skipped 1 agent that asks you and 1 fix that needs your own press. "
          @"Deleted 4.", end.endNote);
        T(@"delete: no record can restore, and the ignored file was not saved", @"1 no 1 no no", [NSString stringWithFormat:@"%@ %@ %@ %@ %@", tree.payload[@"removal"][@"deleted"],
          YN(tree.canRestore), cache.payload[@"removal"][@"deleted"], YN(cache.canRestore), YN(savedEnv)]);
        __block NSString *problem = nil;
        dispatch_sync(MMQueue(@"windowtest", @"restore", QOS_CLASS_USER_INITIATED), ^{ problem = cache ? [MMUndo.shared restore:cache.rid] : @"no record"; });
        T(@"delete: restore of the cache says it was deleted", @"it was deleted and cannot be brought back", problem ?: @"(nil)");
    }
    T([name stringByAppendingString:@": every step still left a finished record by manual"], @"yes", ({ BOOL ok = YES;
        for (MMFixResult *x in runner.results) { if (![x.outcome isEqualToString:@"done"]) continue;
            MMUndoRecord *r = x.rid ? [MMUndo.shared record:x.rid] : nil; if (!r || r.state != MMUndoDone || ![r.by isEqualToString:@"manual"]) ok = NO; }
        YN(ok); }));
    T([name stringByAppendingString:@": no shown string names an old app or says for good"], @"", Bad(@[end.endTitle ?: @"", end.endNote ?: @"", Steps(seen)]));
    MMSetPref(MMRemovalKey, nil);
}
