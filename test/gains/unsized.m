// A removal whose size was not measured, in the gains log, issue #83. Included by gains.m, before main.
// A worktree's size comes from a walk in the background, and until the first one ends its finding's cost holds 0,
// which is no reading. A removal of such a worktree wrote that 0 as disk back, so the look-back counted less than
// came back and did not say so. gains.sh runs this mode in a home of its own: fixture folders inside it are "removed"
// by the fake action, which deletes nothing, so only the rows of the log are read here.

/// A worktree finding as WorkForest makes it: the fact sized is NO until the first walk of the folder ended.
static MMFinding *TreeFinding(NSString *name, uint64_t freed, BOOL sized) {
    NSString *path = Path(name);
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSMutableData dataWithLength:40000] writeToFile:[path stringByAppendingPathComponent:@"a.bin"] atomically:YES];
    return [MMFinding expert:gExpert kind:@"worktree" stableKey:path build:^(MMFindingBuilder *b) {
        b.title = name; b.path = path; b.keepReasons = @[]; b.facts = @{@"sized": @(sized), @"missing": @NO};
        MMCost c = {0}; c.diskFreed = freed; c.cpuPercent = -1; b.cost = c;
        b.proposal = [MMProposal verb:@"remove" title:@"Remove Worktree" reversibility:MMReversibleRestart];
    }];
}

/// A policy that walks the folder on fresh facts right before the action, as WorkForest's does.
@interface GNWalks : NSObject <MMExpertPolicy>
@end
@implementation GNWalks
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts { (void)[MMTreeDisk.shared factsFor:f.path read:MMTreeDiskNow]; return nil; }
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

static NSString *JV(id v) { return !v ? @"missing" : v == NSNull.null ? @"null" : [v description]; }
static NSString *JB(id v) { return !v ? @"missing" : v == NSNull.null ? @"null" : [v boolValue] ? @"yes" : @"no"; }
/// One row or one total: its disk back, whether the row was measured, and whether the total is marked as no total.
static NSString *RowDisk(NSString *rid) {
    NSDictionary *j = [[MMGains.shared gain:rid] json];
    return [NSString stringWithFormat:@"%@ %@ %@", JV(j[@"diskBack"]), JB(j[@"measured"]), JV(j[@"diskState"])];
}
static NSString *TotalDisk(NSDictionary *t) { return [NSString stringWithFormat:@"%@ %@", JV(t[@"diskBack"]), JB(t[@"diskBackPartial"])]; }

static void Unsized(void) {
    MMUndoRecord *sized = Run(Act(@"remove", TreeFinding(@"tree-sized", 3000000, YES)), @"manual", NULL);
    MMUndoRecord *empty = Run(Act(@"remove", TreeFinding(@"tree-empty", 0, YES)), @"manual", NULL);
    T(@"unsized: a measured worktree keeps its number, and a measured 0 stays a reading", @"3000000 yes freed | 0 yes freed",
      [NSString stringWithFormat:@"%@ | %@", RowDisk(sized.rid), RowDisk(empty.rid)]);

    // Not measured when it was listed, and walked on fresh facts right before the removal: that walk is its size.
    MMFinding *wf = TreeFinding(@"tree-walked", 0, NO);
    __block MMUndoRecord *walked = nil;
    __block uint64_t real = 0;
    OffMain(^{
        NSString *e = nil;
        walked = MMRunAction(Act(@"remove", wf), [GNWalks new], nil, @"manual", @"gains test", &e);
        real = [MMTreeDisk.shared factsFor:wf.path read:MMTreeDiskNow].freed;
    });
    T(@"unsized: the fixture folder has a size to read", @"yes", YN(real > 0));
    T(@"unsized: a worktree measured right before its removal is logged with that size, never 0",
      [NSString stringWithFormat:@"%llu yes freed", real], RowDisk(walked.rid));

    // Never measured at all: nobody knows what came back, and the row says so.
    MMUndoRecord *unknown = Run(Act(@"remove", TreeFinding(@"tree-unknown", 0, NO)), @"manual", NULL);
    T(@"unsized: a worktree nobody measured is logged as not measured, with null and never 0", @"null no freed", RowDisk(unknown.rid));
    T(@"unsized: all four removals finished", @"1 1 1 1", [NSString stringWithFormat:@"%ld %ld %ld %ld", (long)sized.state, (long)empty.state, (long)walked.state, (long)unknown.state]);

    // The sums hold the measured rows alone and are marked as no total, so the look-back can say "or more".
    NSDictionary *s = [MMGains.shared summary:7 now:NSDate.date];
    NSString *sum = [NSString stringWithFormat:@"%llu yes", 3000000 + real];
    T(@"unsized: today's disk back is of the measured rows and is marked as no total", sum, TotalDisk(s[@"today"]));
    T(@"unsized: so are the week, the day and the kind", [NSString stringWithFormat:@"%@ | %@ | %@", sum, sum, sum],
      [NSString stringWithFormat:@"%@ | %@ | %@", TotalDisk(s[@"total"]), TotalDisk([s[@"byDay"] lastObject]), TotalDisk(s[@"byKind"][MMGainWorktree])]);
    T(@"unsized: a kind with every row measured is a total", @"0 no", TotalDisk(s[@"byKind"][MMGainServer]));
    T(@"unsized: memory back is untouched", @"0", JV(s[@"today"][@"memoryBack"]));
    NSDictionary *back = [MMPerformanceLookBack read:MMGains.shared now:NSDate.date].json;
    T(@"unsized: the look-back carries the mark, today and this week", [NSString stringWithFormat:@"%@ | %@", sum, sum],
      [NSString stringWithFormat:@"%@ | %@", TotalDisk(back[@"today"]), TotalDisk(back[@"week"])]);

    // In the Trash it is the same: bytes nobody measured do not wait there as 0.
    NSString *file = MakeFile(@"unsized-item.bin");
    MMFinding *tf = [MMFinding expert:gExpert kind:@"clutter" stableKey:@"unsized-item" build:^(MMFindingBuilder *b) {
        b.title = @"unsized-item"; b.path = file; b.keepReasons = @[]; b.facts = @{@"sized": @NO};
        MMCost c = {0}; c.cpuPercent = -1; b.cost = c;
        b.proposal = [MMProposal verb:@"clean" title:@"Move to Trash" reversibility:MMReversibleTrash];
    }];
    MMUndoRecord *trashed = Run(Act(@"trash", tf), @"manual", NULL);
    NSDictionary *tj = [[MMGains.shared gain:trashed.rid] json];
    s = [MMGains.shared summary:7 now:NSDate.date];
    T(@"unsized: a thing not measured that went to the Trash waits there with null, marked, and adds no disk back", [NSString stringWithFormat:@"null no trash | 0 yes | %@", sum],
      [NSString stringWithFormat:@"%@ %@ %@ | %@ %@ | %@", JV(tj[@"diskInTrash"]), JB(tj[@"measured"]), JV(tj[@"diskState"]),
       JV(s[@"today"][@"diskInTrash"]), JB(s[@"today"][@"diskInTrashPartial"]), TotalDisk(s[@"today"])]);

    // A row taken back counts nothing, so it no longer makes the sum a part.
    [MMGains.shared takeBack:unknown.rid];
    [MMGains.shared takeBack:trashed.rid];
    s = [MMGains.shared summary:7 now:NSDate.date];
    T(@"unsized: with the rows not measured taken back the sums are totals again", [NSString stringWithFormat:@"%llu no no", 3000000 + real],
      [NSString stringWithFormat:@"%@ %@", TotalDisk(s[@"today"]), JB(s[@"today"][@"diskInTrashPartial"])]);
    // One more stays in the log for `minmacs gains`, which gains.sh reads next.
    (void)Run(Act(@"remove", TreeFinding(@"tree-left", 0, NO)), @"manual", NULL);
}
