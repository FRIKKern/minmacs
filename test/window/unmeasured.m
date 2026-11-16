// A worktree whose size is not measured yet, issue #62. Included by window.m, after welcome.m.
// A worktree's size comes from a walk in the background, and until the first one ends its finding's cost holds 0.
// The window showed that 0 as "0 MB", a reading nobody took. Here two worktrees are not measured, one is measured at
// 456 MB, one is measured and holds nothing, and one folder is gone. Only the first two may lack a number.

static void Unmeasured(void) {
    World();
    NSString *w1 = Dir(@"trees/fix-auth-redirect"), *w2 = Dir(@"trees/old-spike"), *w3 = Dir(@"repo"), *w4 = Dir(@"trees/wip"), *w5 = Dir(@"trees/gone");
    Tree(w5, NO, MMMergedNone);
    // As MMWFTree's json writes them: sized is NO until the first walk ends, and a folder that is gone is never walked.
    NSDictionary *(^tree)(NSString *, id, BOOL, BOOL) = ^(NSString *path, id merged, BOOL sized, BOOL missing) {
        return @{@"path": path, @"branch": path.lastPathComponent, @"merged": merged, @"dirty": @0, @"untracked": @0, @"unpushed": @0,
                 @"sized": @(sized), @"missing": @(missing), @"lastWorkAt": @(NSDate.date.timeIntervalSince1970 - 12 * 86400)};
    };
    const uint64_t DMB = 1000 * 1000;
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", w1, @"repo/fix-auth-redirect", w1, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(w1, @"squash", NO, NO)),
        Finding(@"workforest", @"worktree", w2, @"repo/old-spike", w2, 0, 0, 0, P(@"remove", MMReversibleRestart), tree(w2, @"ancestor", NO, NO)),
        Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 456 * DMB, nil, tree(w3, NSNull.null, YES, NO)),
        Finding(@"workforest", @"worktree", w4, @"repo/wip", w4, 0, 0, 0, nil, tree(w4, NSNull.null, YES, NO)),
        Finding(@"workforest", @"worktree", w5, @"repo/gone", w5, 0, 0, 0, nil, tree(w5, NSNull.null, NO, YES))];
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    MMWindowGroup *trees = m.diskGroups[0];

    // The rows: what was not measured holds no number, in the model, in the row's slot and in --json.
    NSMutableArray *slots = [NSMutableArray new], *json = [NSMutableArray new];
    for (MMWindowRow *r in trees.rows) {
        [slots addObject:[NSString stringWithFormat:@"%@=%@", r.name, r.sizeWord ?: (r.showsSize ? MMWindowSizeText(r.bytes, YES) : @"none")]];
        NSDictionary *j = r.json;
        [json addObject:[NSString stringWithFormat:@"%@:%@", j[@"bytes"] == NSNull.null ? @"null" : j[@"bytes"], [j[@"measured"] boolValue] ? @"yes" : @"no"]];
    }
    T(@"unmeasured: a size not measured is the word measuring and never 0 MB, a measured 0 and a folder that is gone stay readings, and the measured rows come first",
      @"repo=456 MB gone=0 MB wip=0 MB fix-auth-redirect=measuring old-spike=measuring", [slots componentsJoinedByString:@" "]);
    T(@"unmeasured: --json holds null and measured false for it, never 0", @"456000000:yes 0:yes 0:yes null:no null:no", [json componentsJoinedByString:@" "]);
    T(@"unmeasured: the group counts its rows that are not measured", @"2 of 5", [NSString stringWithFormat:@"%ld of %lu", (long)trees.unmeasured, (unsigned long)trees.rows.count]);
    NSInteger other = 0;
    for (MMWindowGroup *g in [m.memoryGroups arrayByAddingObject:m.diskGroups[1]]) other += g.unmeasured;
    T(@"unmeasured: no server, agent, app or cache is called not measured", @"0", [NSString stringWithFormat:@"%ld", (long)other]);

    // The sums: a sum over rows not all measured says so, and a fix that removes one gives back that much or more.
    uint64_t sum = 0;
    for (MMWindowRow *r in trees.rows) sum += r.bytes;
    T(@"unmeasured: the group's sum is of the measured rows and says so far", @"456 MB so far", MMWindowSumText(MMWindowSizeText(sum, YES), (NSInteger)trees.rows.count, trees.unmeasured));
    T(@"unmeasured: with every row measured the sum stands alone, and with none it is the word",
      @"456 MB | measuring", [NSString stringWithFormat:@"%@ | %@", MMWindowSumText(@"456 MB", 5, 0), MMWindowSumText(@"0 MB", 3, 3)]);
    MMWindowFix *wrap = nil, *remove = nil, *trash = nil;
    for (MMWindowFix *f in m.fixes) {
        if ([f.key hasPrefix:@"wrapup:"]) wrap = f;
        if ([f.key isEqualToString:@"remove"]) remove = f;
        if ([f.key isEqualToString:@"trash"]) trash = f;
    }
    // The Wrap Up's number is its worktree's, which counts the cache inside it, and the merged worktree is all its fix
    // removes: neither has a number. The leftovers are measured. Fix Everything's sum holds them alone, so it is "or more".
    T(@"unmeasured: a fix that removes a thing not measured says not measured yet and never 0 MB, a fix of measured things stands as it is, and their sum is that much or more",
      @"not measured yet | not measured yet | 15.0 GB | 15.0 GB or more",
      [NSString stringWithFormat:@"%@ | %@ | %@ | %@", MMWindowBackText(MMWindowSizeText(wrap.diskBack, YES), wrap.diskBack == 0, wrap.diskPartial),
       MMWindowBackText(MMWindowSizeText(remove.diskBack, YES), remove.diskBack == 0, remove.diskPartial),
       MMWindowBackText(MMWindowSizeText(trash.diskBack, YES), trash.diskBack == 0, trash.diskPartial),
       MMWindowBackText(MMWindowSizeText(m.diskBack, YES), m.diskBack == 0, m.diskBackPartial)]);
    NSDictionary *all = m.json[@"fixEverything"];
    T(@"unmeasured: Fix Everything's disk back is marked as no total, in the model and in --json", @"yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN(m.diskBackPartial), YN([all[@"diskBackPartial"] boolValue]), YN([wrap.json[@"diskBackPartial"] boolValue])]);

    // Where a row stands in its group counts the measured rows only.
    T(@"unmeasured: a row's place counts the measured rows, and a row not measured has none",
      @"The biggest of 3 worktrees measured so far | The smallest of 3 worktrees measured so far | 5 worktrees | 2nd biggest of 5 worktrees | The only one measured so far of 1493 worktrees",
      [@[MMWindowPlaceLine(1, 5, 2, YES, @"worktrees"), MMWindowPlaceLine(3, 5, 2, YES, @"worktrees"), MMWindowPlaceLine(4, 5, 2, NO, @"worktrees"),
         MMWindowPlaceLine(2, 5, 0, YES, @"worktrees"), MMWindowPlaceLine(1, 1493, 1492, YES, @"worktrees")] componentsJoinedByString:@" | "]);

    // The world of every other mode writes no sized fact, as a finding of before would: its rows are all readings.
    World();
    MMSnapshot *s2 = WorldSnapshot();
    MMWindowModel *m2 = MMWindowModelFrom(s2, Build(s2), [MMWindowExtras readWithLogin:YES]);
    T(@"unmeasured: a worktree with no sized fact keeps its number", @"0 no", [NSString stringWithFormat:@"%ld %@", (long)m2.diskGroups[0].unmeasured, YN(m2.diskBackPartial)]);
}
