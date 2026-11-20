// Fix Everything's planned disk with a worktree not measured yet, issue #83. Included by window.m, after unmeasured.m.
// The run filled its disk line to diskPlanned, the sum of the fixes' disk back. A worktree whose first size walk has
// not ended adds 0 to that sum, so the sum is no total, and the line posed as one. Here the two merged worktrees of
// the world are not measured, as in unmeasured.m: the Wrap Up and the removal each have a part with no number.

/// A key the old model does not have reads as nil here, so this file builds against it and the checks fail.
static id Key(id o, NSString *k) { @try { return [o valueForKey:k]; } @catch (NSException *e) { return nil; } }
static NSString *Flag(id v) { return !v ? @"missing" : [v boolValue] ? @"yes" : @"no"; }

/// With chore, the removal has a second worktree, merged and measured, beside the one that is not.
static MMPerformance *PlannedWorld(MMWindowModel **model, BOOL chore) {
    World();
    NSString *w1 = Dir(@"trees/fix-auth-redirect"), *w2 = Dir(@"trees/old-spike"), *w3 = Dir(@"repo");
    NSDictionary *(^tree)(NSString *, id, BOOL) = ^(NSString *path, id merged, BOOL sized) {
        return @{@"path": path, @"branch": path.lastPathComponent, @"merged": merged, @"dirty": @0, @"untracked": @0, @"unpushed": @0,
                 @"sized": @(sized), @"missing": @NO, @"lastWorkAt": @(NSDate.date.timeIntervalSince1970 - 12 * 86400)};
    };
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", w1, @"repo/fix-auth-redirect", w1, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(w1, @"squash", NO)),
        Finding(@"workforest", @"worktree", w2, @"repo/old-spike", w2, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(w2, @"ancestor", NO)),
        Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 456 * 1000 * 1000, nil, tree(w3, NSNull.null, YES))];
    if (chore) {
        NSString *w5 = Dir(@"trees/done-chore");
        Tree(w5, NO, MMMergedAncestor);
        gFindings[@"workforest"] = [gFindings[@"workforest"] arrayByAddingObject:
            Finding(@"workforest", @"worktree", w5, @"repo/done-chore", w5, 0, 0, 120 * 1000 * 1000, P(@"remove", MMReversibleRestart), tree(w5, @"ancestor", YES))];
    }
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    if (model) *model = MMWindowModelFrom(s, p, nil);
    return p;
}

static void Planned(void) {
    MMWindowModel *m = nil;
    MMPerformance *p = PlannedWorld(&m, NO);
    T(@"planned: before the press the window's disk back is marked as no total", @"yes", YN(m.diskBackPartial && m.diskBack > 0));

    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    NSMutableArray<MMWindowRun *> *seen = [NSMutableArray new];
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    __block MMWindowRun *end = nil;
    runner.onProgress = ^(MMWindowRun *r) {
        @synchronized (seen) { [seen addObject:r]; }
        if (!r.running) { end = r; dispatch_semaphore_signal(ended); }
    };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"planned: the run ends", @"yes", @"no"); return; }
    MMWindowRun *first = seen.firstObject;
    for (MMFixResult *x in runner.results) if (![x.outcome isEqualToString:@"done"]) Info([NSString stringWithFormat:@"%@ %@: %@", x.outcome, x.name, x.why]);

    // While a fix with a part not measured has not landed, the planned disk is no total, and the run says so.
    T(@"planned: the run starts with its planned disk marked as no total, in the model and in --json", @"yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@", Flag(Key(first, @"diskPlannedPartial")), Flag(first.json[@"diskPlannedPartial"]), YN(first.diskPlanned == m.diskBack)]);
    T(@"planned: the memory side is a total all along", @"yes", YN(first.memoryPlanned == m.memoryBack && end.memoryPlanned == m.memoryBack));
    // The disk line fills toward a total only. With the plan no total it does not fill at all, however much came back.
    MMWindowRun *half = [MMWindowRun new];
    half.running = YES; half.diskBack = 6; half.diskPlanned = 8; half.memoryBack = 1; half.memoryPlanned = 4;
    NSString *whole = [NSString stringWithFormat:@"%@ %@", Key(half, @"diskShare") ?: @"missing", Key(half, @"memoryShare") ?: @"missing"];
    @try { [half setValue:@YES forKey:@"diskPlannedPartial"]; } @catch (NSException *e) {}
    T(@"planned: the disk line fills to its share of a total, and not at all toward a sum that is no total", @"0.75 0.25 | 0 0.25",
      [NSString stringWithFormat:@"%@ | %@ %@", whole, Key(half, @"diskShare") ?: @"missing", Key(half, @"memoryShare") ?: @"missing"]);
    half.diskBack = 20;
    T(@"planned: more back than was planned is still no full line while the plan is no total", @"0", Key(half, @"diskShare") ?: @"missing");

    // Once every such fix landed, what each gave back is known, so the plan is a total again and holds it.
    BOOL landed = YES;
    for (MMFixResult *x in runner.results) if (([x.kind isEqualToString:@"wrapup"] || [x.kind isEqualToString:@"remove"]) && ![x.outcome isEqualToString:@"done"]) landed = NO;
    T(@"planned: the Wrap Up and the removal both landed", @"yes", YN(landed));
    T(@"planned: with every such fix landed the planned disk is a total again, and never less than what came back", @"no no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Flag(Key(end, @"diskPlannedPartial")), Flag(end.json[@"diskPlannedPartial"]), YN(end.diskPlanned >= m.diskBack)]);
    T(@"planned: the run's JSON keys", @"diskBack diskPlanned diskPlannedPartial done endNote endTitle memoryBack memoryPlanned running step total",
      [[end.json.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    T(@"planned: no shown string names an old app or says for good", @"", Bad(@[end.endTitle ?: @"", end.endNote ?: @"", Steps(seen)]));

    // A run stopped before the fixes with a part not measured landed never learned their size.
    MMPerformance *p2 = PlannedWorld(NULL, NO);
    MMFixRunner *stopped = [[MMFixRunner alloc] initWithPerformance:p2];
    dispatch_semaphore_t ended2 = dispatch_semaphore_create(0);
    __block MMWindowRun *end2 = nil;
    stopped.onProgress = ^(MMWindowRun *r) { if (!r.running) { end2 = r; dispatch_semaphore_signal(ended2); } };
    [stopped stop];
    [stopped start];
    if (dispatch_semaphore_wait(ended2, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"planned: the stopped run ends", @"yes", @"no"); return; }
    T(@"planned: a run stopped before them ends with its planned disk still no total", @"0 yes yes",
      [NSString stringWithFormat:@"%ld %@ %@", (long)end2.done, Flag(Key(end2, @"diskPlannedPartial")), Flag(end2.json[@"diskPlannedPartial"])]);

    // One removal of two worktrees: the fresh check keeps the one not measured, and the measured one goes. The fix
    // did something, yet nobody learned the kept one's size, so the plan stays no total.
    MMPerformance *p3 = PlannedWorld(NULL, YES);
    [gNowKept addObject:[@"workforest:worktree:" stringByAppendingString:Dir(@"trees/old-spike")]];
    MMFixRunner *mixed = [[MMFixRunner alloc] initWithPerformance:p3];
    dispatch_semaphore_t ended3 = dispatch_semaphore_create(0);
    __block MMWindowRun *end3 = nil;
    mixed.onProgress = ^(MMWindowRun *r) { if (!r.running) { end3 = r; dispatch_semaphore_signal(ended3); } };
    [mixed start];
    if (dispatch_semaphore_wait(ended3, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"planned: the mixed run ends", @"yes", @"no"); return; }
    NSMutableDictionary<NSString *, NSString *> *by = [NSMutableDictionary new];
    for (MMFixResult *x in mixed.results) by[x.name] = x.outcome;
    T(@"planned: a removal that kept its worktree not measured and removed a measured one leaves the planned disk no total",
      @"kept done done yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", by[@"old-spike"], by[@"done-chore"], by[@"fix-auth-redirect"],
          Flag(Key(end3, @"diskPlannedPartial")), Flag(end3.json[@"diskPlannedPartial"])]);
}
