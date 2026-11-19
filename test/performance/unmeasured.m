// A worktree whose size is not measured yet, issue #76. Included by performance.m, before main.
// A worktree's size comes from a walk in the background, and until the first one ends its finding's cost holds 0.
// The model held that 0 as the row's number, and `minmacs performance` printed it as a reading nobody took. Here two
// worktrees are not measured, one is measured at 10 GB, one is measured and holds nothing, and one folder is gone.
// Only the first two may lack a number.

static void Unmeasured(void) {
    Busy();
    NSString *w1 = Dir(@"trees/w1"), *w2 = Dir(@"trees/w2"), *w3 = Dir(@"repo"), *w4 = Dir(@"trees/w4"), *w5 = Dir(@"trees/gone");
    Tree(w5, NO, MMMergedNone);
    // As MMWFTree's json writes them: sized is NO until the first walk ends, and a folder that is gone is never walked.
    NSDictionary *(^tree)(BOOL, BOOL) = ^(BOOL sized, BOOL missing) { return @{@"sized": @(sized), @"missing": @(missing)}; };
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", w1, @"repo/w1", w1, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(NO, NO)),
        Finding(@"workforest", @"worktree", w2, @"repo/w2", w2, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(NO, NO)),
        Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 10 * GB, nil, tree(YES, NO)),
        Finding(@"workforest", @"worktree", w4, @"repo/w4", w4, 0, 0, 0, nil, tree(YES, NO)),
        Finding(@"workforest", @"worktree", w5, @"repo/gone", w5, 0, 0, 0, nil, tree(NO, YES))];
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ p = [MMPerformance from:s history:Hour(8 * GB) lookBack:nil]; });
    MMPerformanceGroup *trees = p.diskGroups[0];

    // The rows: what was not measured holds no number, in the model and in --json, and comes after the rest.
    NSMutableArray *rows = [NSMutableArray new], *json = [NSMutableArray new];
    for (MMPerformanceRow *r in trees.rows) {
        [rows addObject:[NSString stringWithFormat:@"%@=%@", r.name, r.unmeasured ? @"none" : [NSString stringWithFormat:@"%llu", r.number / GB]]];
        NSDictionary *j = r.json;
        [json addObject:[NSString stringWithFormat:@"%@:%@", j[@"number"] == NSNull.null ? @"null" : j[@"number"], YN([j[@"measured"] boolValue])]];
    }
    T(@"unmeasured: a worktree not measured holds no number, a measured 0 and a folder that is gone stay readings, and the measured rows come first",
      @"repo=10 repo/gone=0 repo/w4=0 repo/w1=none repo/w2=none", [rows componentsJoinedByString:@" "]);
    T(@"unmeasured: --json holds null and measured false for it, never 0", @"10737418240:yes 0:yes 0:yes null:no null:no", [json componentsJoinedByString:@" "]);
    T(@"unmeasured: the group counts its rows that are not measured", @"2 of 5",
      [NSString stringWithFormat:@"%ld of %lu", (long)trees.unmeasured, (unsigned long)trees.rows.count]);
    NSInteger other = 0;
    for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObject:p.diskGroups[1]]) other += g.unmeasured;
    T(@"unmeasured: no server, agent, app, helper or cache is called not measured", @"0", [NSString stringWithFormat:@"%ld", (long)other]);

    // The ring: the worktrees part counts the measured ones only, says so, and the parts still add up to used.
    NSMutableArray *parts = [NSMutableArray new];
    for (NSDictionary *x in p.disk.json[@"parts"]) [parts addObject:[NSString stringWithFormat:@"%@:%@", x[@"group"], YN([x[@"partial"] boolValue])]];
    T(@"unmeasured: the ring's worktrees part is of the measured ones and is marked as no total, in the model and in --json",
      @"10 worktrees | worktrees:yes clutter:no other:no",
      [NSString stringWithFormat:@"%llu %@ | %@", [p.disk.parts[MMPerformanceWorktrees] unsignedLongLongValue] / GB,
       [p.disk.partial.allObjects componentsJoinedByString:@","], [parts componentsJoinedByString:@" "]]);
    T(@"unmeasured: disk parts and other still add up to disk used", @(p.disk.used), @(Sum(p.disk.parts)));
    NSMutableArray *mem = [NSMutableArray new];
    for (NSDictionary *x in p.memory.json[@"parts"]) if ([x[@"partial"] boolValue]) [mem addObject:x[@"group"]];
    T(@"unmeasured: no memory part is marked", @"", [mem componentsJoinedByString:@","]);

    // The fixes: one that removes a thing not measured gives back more than its number holds, and says so.
    MMPerformanceFix *wrap = nil, *rem = nil, *trash = nil;
    for (MMPerformanceFix *f in p.fixes) {
        if ([f.kind isEqualToString:@"wrapup"]) wrap = f;
        else if ([f.kind isEqualToString:@"remove"]) rem = f;
        else if ([f.kind isEqualToString:@"trash"]) trash = f;
    }
    T(@"unmeasured: a fix that removes a thing not measured is marked as no total, and a fix of measured things is not",
      @"wrapup 0 yes yes | remove 0 yes yes | trash 14 no no",
      [NSString stringWithFormat:@"wrapup %llu %@ %@ | remove %llu %@ %@ | trash %llu %@ %@",
       wrap.diskBack / GB, YN(wrap.diskPartial), YN([wrap.json[@"diskBackPartial"] boolValue]),
       rem.diskBack / GB, YN(rem.diskPartial), YN([rem.json[@"diskBackPartial"] boolValue]),
       trash.diskBack / GB, YN(trash.diskPartial), YN([trash.json[@"diskBackPartial"] boolValue])]);

    // The world of every other mode writes no sized fact, as a finding of before would: its rows are all readings.
    Busy();
    MMSnapshot *s2 = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *q;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ q = [MMPerformance from:s2 history:Hour(8 * GB) lookBack:nil]; });
    NSInteger none = 0, marked = 0;
    for (MMPerformanceRow *r in AllRows(q)) if (r.unmeasured || r.json[@"number"] == NSNull.null || ![r.json[@"measured"] boolValue]) none++;
    for (MMPerformanceFix *f in q.fixes) if (f.diskPartial) marked++;
    T(@"unmeasured: a worktree with no sized fact keeps its number, and no part or fix is marked", @"0 0 0",
      [NSString stringWithFormat:@"%ld %ld %lu", (long)none, (long)marked, (unsigned long)q.disk.partial.count]);
}
