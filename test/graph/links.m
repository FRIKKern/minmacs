// Checks for a checkout whose path holds a link. Included by graph.m, which has the fakes and the helpers.
// The repo index keeps a checkout's path as its root gave it, and the path with every link resolved beside it. The
// kernel names a process's folder by the resolved path, and WorkForest names its finding by it. The graph compared
// the two as text, so under a linked root, or under /tmp which leads to /private/tmp, a worktree finding had no
// workstream and `work --json` listed none.
// Every path here is text. No file is read.

static TTree *WL(NSString *path, NSString *real, BOOL isMain) {
    TTree *t = [TTree new]; t.path = path; t.realPath = real; t.repo = path; t.isMain = isMain; return t;
}

/// One repo with a live session in its main checkout, and a worktree beside it with none. kept is the folder as the
/// index keeps it, real is where it leads. Every process, session and clutter item names the real one.
static TWorld *LinkedWorld(NSString *kept, NSString *real) {
    NSString *shop = [real stringByAppendingString:@"/shop"], *feat = [real stringByAppendingString:@"/shop.worktrees/feat"];
    TWorld *w = [TWorld new];
    w.procs = [NSMutableDictionary new];
    for (TProc *p in @[P(1, 0, 1, @"launchd", @"/"), P(50, 1, 10, @"Terminal", @"/"), P(100, 50, 100, @"claude", shop),
                       P(110, 100, 110, @"node", [shop stringByAppendingString:@"/web"]),
                       P(130, 50, 130, @"node", feat)]) w.procs[@(p.pid)] = p;
    w.agents = [@[A(@"claude-code", @"s1", shop, 100, 100, MMAgentWorking)] mutableCopy];
    w.sessions = [@[S(@"claude-code", @"s1", shop, 100, 3600)] mutableCopy];
    w.trees = [@[WL([kept stringByAppendingString:@"/shop"], shop, YES),
                 WL([kept stringByAppendingString:@"/shop.worktrees/feat"], feat, NO)] mutableCopy];
    w.clutter = [@[C([shop stringByAppendingString:@"/.next"], nil, 64 << 20), C(@"/h/Library/DerivedData/Shop-abc", shop, 5 << 20)] mutableCopy];
    w.git = [NSMutableDictionary new];
    return w;
}

static void LinkChecksFor(NSString *what, NSString *kept, NSString *real, NSArray *experts) {
    NSString *keptShop = [kept stringByAppendingString:@"/shop"], *shop = [real stringByAppendingString:@"/shop"];
    NSString *keptFeat = [kept stringByAppendingString:@"/shop.worktrees/feat"], *feat = [real stringByAppendingString:@"/shop.worktrees/feat"];
    NSString *stream = [@"workstream:" stringByAppendingString:keptShop];
    MMSnapshot *s = [MMSnapshot snapshotFrom:[LinkedWorld(kept, real) facts:1] experts:experts reviews:nil holds:nil];
    Check([what stringByAppendingString:@": a session in the resolved folder makes the workstream of that checkout"], stream,
          [[s.workstreams valueForKeyPath:@"owner.ownerID"] componentsJoinedByString:@" "]);
    Check([what stringByAppendingString:@": a worktree finding named by the resolved path belongs to that workstream"], stream,
          OwnerOf(s, [@"workforest:worktree:" stringByAppendingString:shop]));
    Check([what stringByAppendingString:@": a worktree beside it with no session owns its finding, by the path as kept"],
          [@"worktree:" stringByAppendingString:keptFeat], OwnerOf(s, [@"workforest:worktree:" stringByAppendingString:feat]));
    Check([what stringByAppendingString:@": a server in the resolved folder belongs to the workstream"], stream,
          OwnerOf(s, [NSString stringWithFormat:@"locohost:server:%@/web#dev", shop]));
    Check([what stringByAppendingString:@": a server in the worktree beside it belongs to that worktree"],
          [@"worktree:" stringByAppendingString:keptFeat], OwnerOf(s, [NSString stringWithFormat:@"locohost:server:%@#dev", feat]));
    MMWorkstream *w = s.workstreams.firstObject;
    NSInteger trees = 0;
    for (MMFinding *f in w.findings) if ([f.kind isEqualToString:@"worktree"]) trees++;
    Check([what stringByAppendingString:@": the workstream lists its worktree finding, its server and its clutter"], @"1 4 2",
          [NSString stringWithFormat:@"%ld %lu %lu", (long)trees, (unsigned long)w.findings.count, (unsigned long)w.clutter.count]);
    Check([what stringByAppendingString:@": workstreamAt finds it by the path as kept and by the resolved path"],
          [NSString stringWithFormat:@"%@ %@ nil", stream, stream],
          [NSString stringWithFormat:@"%@ %@ %@", [s workstreamAt:[keptShop stringByAppendingString:@"/src"]].owner.ownerID ?: @"nil",
              [s workstreamAt:[shop stringByAppendingString:@"/src"]].owner.ownerID ?: @"nil", [s workstreamAt:feat].owner.ownerID ?: @"nil"]);
}

static void LinkChecks(NSArray *experts) {
    LinkChecksFor(@"a linked root", @"/h/GitHub", @"/Volumes/disk/github", experts);
    LinkChecksFor(@"/tmp", @"/tmp/w/code", @"/private/tmp/w/code", experts);

    // The deepest checkout still wins when the path is the resolved one, and a checkout that is gone, whose finding
    // keeps the path as the index holds it, is found as before.
    TWorld *w = LinkedWorld(@"/h/GitHub", @"/Volumes/disk/github");
    [w.trees addObject:WL(@"/h/GitHub/shop/.claude/worktrees/deep", @"/Volumes/disk/github/shop/.claude/worktrees/deep", NO)];
    [w.trees addObject:WL(@"/h/GitHub/gone", @"/h/GitHub/gone", NO)];
    w.procs[@140] = P(140, 50, 140, @"node", @"/Volumes/disk/github/shop/.claude/worktrees/deep/web");
    MMSnapshot *s = [MMSnapshot snapshotFrom:[w facts:1] experts:experts reviews:nil holds:nil];
    Check(@"a linked root: the deepest checkout wins by the resolved path", @"worktree:/h/GitHub/shop/.claude/worktrees/deep",
          OwnerOf(s, @"locohost:server:/Volumes/disk/github/shop/.claude/worktrees/deep/web#dev"));
    Check(@"a linked root: a checkout with no other form is found by the path as kept", @"worktree:/h/GitHub/gone",
          OwnerOf(s, @"workforest:worktree:/h/GitHub/gone"));
    Check(@"a linked root: a folder that only starts with a checkout's name is outside it", @"nil",
          [s workstreamAt:@"/Volumes/disk/github/shopping"].owner.ownerID ?: @"nil");
}
