// Removal, issue #62 and D2: the old pref ignored, the one decision that always keeps a way back, the one place
// that deletes, which only a check's seam reaches now, and what a record says.
// test/removal.sh builds this with all of Sources/Core and runs it twice.
// Usage: removaltest <dir> <registry/clutter>     every check, on fixtures it makes in <dir>
//        removaltest --wall <path>                asks MMRemovalApply to delete <path> and prints why it refused
//        removaltest --leave-waiting <dir>        leaves two items in staging that MinMacs cannot settle, for the CLI
//        removaltest --pipe <case> <dir>          one case of pipes.m, ended by an alarm when it waits on a pipe
//        removaltest --stop-in-trash <tree> <path> sends path to the Trash and stops where MINMACS_TEST_STOP_TRASH says
//        removaltest --stop-second <tree> <a> <b> <point>  sends a, then b, to the Trash for one part, stopping in b's move
//        removaltest --leave-in-trash <dir>       leaves a file MinMacs sent to the Trash that no record names, for the CLI
// <dir> is inside $MINMACS_HOME. The --wall form runs with MINMACS_HOME set to a folder inside the section's own
// folder, so the path it is asked to delete is a fixture too, and would only cost a fixture if the wall failed.
// It prints one line per check, CHECK<tab>name<tab>want<tab>got, and removal.sh hands each to check.
#import <sys/stat.h>
#import "Core/MMCore.h"

static void T(NSString *name, id want, id got) {
    printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, [want description].UTF8String ?: "", [got description].UTF8String ?: "(nil)");
    fflush(stdout);
}
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }
static NSString *Or(NSString *s) { return s ?: @"nil"; }
static NSString *gDir;
static NSString *Path(NSString *name) { return [gDir stringByAppendingPathComponent:name]; }
static BOOL Exists(NSString *p) { struct stat st; return lstat(p.fileSystemRepresentation, &st) == 0; }
static void Write(NSString *path, NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static NSUInteger TrashCount(void) { return [NSFileManager.defaultManager contentsOfDirectoryAtPath:MMTrashFolder() error:nil].count; }

/// "delete" or "keep", then why.
static NSString *Says(MMRemovalDecision *d) { return [NSString stringWithFormat:@"%@: %@", d.deleteNow ? @"delete" : @"keep", d.why]; }
static NSString *Word(MMRemovalDecision *d) { return d.deleteNow ? @"delete" : @"keep"; }

static MMRemovalFacts *Tree(BOOL merged, BOOL gone, NSInteger dirty, NSInteger untracked, NSInteger unpushed, NSInteger stashes) {
    return [MMRemovalFacts worktreeKnown:YES merged:merged upstreamGone:gone dirty:dirty untracked:untracked unpushed:unpushed stashes:stashes];
}
static MMRemovalFacts *Clutter(MMClutterClass klass, BOOL rebuilt, BOOL free, BOOL ownerGone) {
    MMRemovalFacts *f = [MMRemovalFacts new];
    f.klass = klass; f.rebuilt = rebuilt; f.free = free; f.ownerGone = ownerGone;
    return f;
}

#pragma mark - The pref

/// Every thing, on the given facts, asked by each who can ask: the words of each answer, joined.
static NSString *EveryAnswer(MMRemovalFacts *f) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSNumber *t in @[@(MMRemovalWorktree), @(MMRemovalIgnoredFiles), @(MMRemovalConfigFiles), @(MMRemovalClutter), @(MMRemovalToolCopy)])
        for (NSString *by in @[@"manual", @"cli", @"proactive", @"eager", @"guard", @""])
            [out addObject:Word(MMRemovalDecide((MMRemovalThing)t.integerValue, f, by.length ? by : nil))];
    return [[NSSet setWithArray:out].allObjects componentsJoinedByString:@" "];
}

/// D2: there is no choice. Whatever core.removal holds, an old "smart" or "delete" too, every answer keeps a way back.
static void Pref(void) {
    MMRemovalFacts *best = Tree(YES, NO, 0, 0, 0, 0), *cache = Clutter(MMClutterCache, YES, YES, NO), *tool = Clutter(MMClutterTool, YES, YES, NO);
    NSMutableArray *got = [NSMutableArray new];
    for (id v in @[NSNull.null, @"smart", @"trash", @"delete", @"Delete", @"shred", @2]) {
        MMSetPref(MMRemovalKey, v == NSNull.null ? nil : v);
        [got addObject:[NSString stringWithFormat:@"%@:%@/%@/%@/%@", v == NSNull.null ? @"none" : v, MMRemovalChoiceName(MMRemovalChoiceNow()),
                        EveryAnswer(best), EveryAnswer(cache), EveryAnswer(tool)]];
    }
    T(@"pref: whatever core.removal holds, an old smart or delete too, the choice is trash and every answer keeps a way back",
      @"none:trash/keep/keep/keep smart:trash/keep/keep/keep trash:trash/keep/keep/keep delete:trash/keep/keep/keep Delete:trash/keep/keep/keep shred:trash/keep/keep/keep 2:trash/keep/keep/keep",
      [got componentsJoinedByString:@" "]);
    MMSetPref(MMRemovalKey, @"delete");
    BOOL cleared = MMRemovalForgetOldChoice();
    T(@"pref: Core's start clears an old value, once, and then finds nothing to clear", @"yes nil no",
      [NSString stringWithFormat:@"%@ %@ %@", YN(cleared), Or(MMPref(MMRemovalKey)), YN(MMRemovalForgetOldChoice())]);
    T(@"pref: the one name and the one sentence", @"trash|Everything MinMacs removes keeps a way back: a worktree through git, the rest in the Trash or a recovery folder. MinMacs never deletes anything at once and never empties the Trash.",
      [NSString stringWithFormat:@"%@|%@", MMRemovalChoiceName(MMRemovalTrash), MMRemovalExplain()]);
}

#pragma mark - The decision

static void Worktrees(void) {
    MMRemovalThing w = MMRemovalWorktree;
    // A worktree keeps a way back on any facts. The words say whether git alone could give it back, MMRemovalGitWhyNot.
    T(@"worktree: merged and clean keeps a way back, and git can give it back", @"keep: git can give it back: its branch is merged and every commit is on a remote",
      Says(MMRemovalDecide(w, Tree(YES, NO, 0, 0, 0, 0), @"manual")));
    T(@"worktree: remote branch gone and clean keeps a way back", @"keep: git can give it back: its remote branch is gone and every commit is on a remote",
      Says(MMRemovalDecide(w, Tree(NO, YES, 0, 0, 0, 0), @"manual")));
    T(@"worktree: an uncommitted change says so", @"keep: a way back is kept, since 1 change is not committed", Says(MMRemovalDecide(w, Tree(YES, NO, 1, 0, 0, 0), @"manual")));
    T(@"worktree: an untracked file says so", @"keep: a way back is kept, since 1 untracked file is not in git", Says(MMRemovalDecide(w, Tree(YES, NO, 0, 1, 0, 0), nil)));
    T(@"worktree: an unpushed commit says so", @"keep: a way back is kept, since 2 commits are on no remote", Says(MMRemovalDecide(w, Tree(YES, NO, 0, 0, 2, 0), @"cli")));
    T(@"worktree: a stash says so", @"keep: a way back is kept, since it has 1 stash", Says(MMRemovalDecide(w, Tree(YES, NO, 0, 0, 0, 1), @"proactive")));
    T(@"worktree: not merged with its remote branch says so", @"keep: a way back is kept, since its branch is not merged and its remote branch still exists",
      Says(MMRemovalDecide(w, Tree(NO, NO, 0, 0, 0, 0), @"eager")));
    // Issue #118: an upstream that could not be read is not one git gives back, even beside a gone flag; none says none.
    MMRemovalFacts *unread = Tree(NO, YES, 0, 0, 0, 0), *untracked = Tree(NO, NO, 0, 0, 0, 0);
    unread.upstreamUnknown = YES; untracked.upstreamNone = YES;
    T(@"git words: an upstream not read is not one git gives back, and says so", @"its branch is not merged and its remote branch could not be read", Or(MMRemovalGitWhyNot(unread)));
    T(@"git words: a branch with no upstream says so", @"its branch is not merged and it tracks no remote branch", Or(MMRemovalGitWhyNot(untracked)));
    T(@"git words: a count git could not give is not one git gives back", @"cannot verify what git holds of it|cannot verify what git holds of it|cannot verify what git holds of it|cannot verify what git holds of it",
      [NSString stringWithFormat:@"%@|%@|%@|%@", Or(MMRemovalGitWhyNot(Tree(YES, NO, -1, 0, 0, 0))), Or(MMRemovalGitWhyNot(Tree(YES, NO, 0, -1, 0, 0))),
       Or(MMRemovalGitWhyNot(Tree(YES, NO, 0, 0, -1, 0))), Or(MMRemovalGitWhyNot(Tree(YES, NO, 0, 0, 0, -1)))]);
    MMRemovalFacts *unknown = Tree(YES, NO, 0, 0, 0, 0);
    unknown.gitKnown = NO;
    T(@"git words: unknown git facts, or none set, are never ones git gives back", @"cannot verify its git facts|cannot verify its git facts|cannot verify its git facts",
      [NSString stringWithFormat:@"%@|%@|%@", Or(MMRemovalGitWhyNot(unknown)), Or(MMRemovalGitWhyNot([MMRemovalFacts new])), Or(MMRemovalGitWhyNot(nil))]);
    T(@"git words: merged and clean is one git gives back", @"nil", Or(MMRemovalGitWhyNot(Tree(YES, NO, 0, 0, 0, 0))));
    MMRemovalFacts *best = Tree(YES, NO, 0, 0, 0, 0);
    T(@"ignored files: kept, to the recovery folder", @"keep: git does not hold the files it ignores, so they go to the recovery folder", Says(MMRemovalDecide(MMRemovalIgnoredFiles, best, @"eager")));
    T(@"config files: kept, to the Trash", @"keep: it goes to the Trash, so Restore moves it back", Says(MMRemovalDecide(MMRemovalConfigFiles, best, @"manual")));
}

static void Clutters(NSString *rows) {
    MMRemovalThing c = MMRemovalClutter;
    // What Smart once deleted at once now goes to the Trash: a rebuilt cache, build output, a leftover, on any facts.
    T(@"clutter: a rebuilt, free cache goes to the Trash", @"keep: it goes to the Trash, so Restore moves it back", Says(MMRemovalDecide(c, Clutter(MMClutterCache, YES, YES, NO), @"manual")));
    T(@"clutter: build output, a leftover, a tool, data and report row, and facts nobody set all keep a way back", @"keep keep keep keep keep keep keep",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@", Word(MMRemovalDecide(c, Clutter(MMClutterBuild, YES, YES, NO), @"manual")), Word(MMRemovalDecide(c, Clutter(MMClutterLeak, NO, YES, NO), @"eager")),
       Word(MMRemovalDecide(c, Clutter(MMClutterTool, YES, YES, NO), nil)), Word(MMRemovalDecide(c, Clutter(MMClutterData, YES, YES, NO), @"cli")),
       Word(MMRemovalDecide(c, Clutter(MMClutterReport, YES, YES, NO), @"guard")), Word(MMRemovalDecide(c, [MMRemovalFacts new], nil)), Word(MMRemovalDecide(c, nil, nil))]);
    T(@"tool copy: a recovery copy is always kept, a rebuilt tool row too", @"keep: a recovery copy is kept, so Restore copies back what the tool removed|keep",
      [NSString stringWithFormat:@"%@|%@", Says(MMRemovalDecide(MMRemovalToolCopy, Clutter(MMClutterTool, YES, YES, NO), @"manual")),
       Word(MMRemovalDecide(MMRemovalToolCopy, Clutter(MMClutterTool, NO, YES, NO), @"proactive"))]);
    T(@"the answer as json wants no delete, and says nothing is deleted", @"trash 0 0 it goes to the Trash, so Restore moves it back", ({ NSDictionary *j = MMRemovalDecide(c, Clutter(MMClutterCache, YES, YES, NO), nil).json;
      [NSString stringWithFormat:@"%@ %@ %@ %@", j[@"choice"], j[@"wants"], j[@"deleted"], j[@"why"]]; }));

    // The rows: only a cache, build or tool row with "rebuilt": true says so. A leftover that claims it does not.
    NSString *mine = Path(@"rows");
    Write([mine stringByAppendingPathComponent:@"rm-leak.json"], @"{\"id\": \"rm-leak\", \"title\": \"Leak\", \"group\": \"x\", \"class\": \"leak\", \"signature\": \"aged\", \"paths\": [\"~/.rm/leak\"], \"rebuilt\": true, \"every\": 600}");
    Write([mine stringByAppendingPathComponent:@"rm-word.json"], @"{\"id\": \"rm-word\", \"title\": \"Word\", \"group\": \"x\", \"class\": \"cache\", \"paths\": [\"~/.rm/word\"], \"rebuilt\": \"yes\", \"every\": 600}");
    Write([mine stringByAppendingPathComponent:@"rm-one.json"], @"{\"id\": \"rm-one\", \"title\": \"One\", \"group\": \"x\", \"class\": \"cache\", \"paths\": [\"~/.rm/one\"], \"rebuilt\": 1, \"every\": 600}");
    Write([mine stringByAppendingPathComponent:@"rm-yes.json"], @"{\"id\": \"rm-yes\", \"title\": \"Yes\", \"group\": \"x\", \"class\": \"cache\", \"paths\": [\"~/.rm/yes\"], \"rebuilt\": true, \"every\": 600}");
    MMClutterCatalog *cat = [[MMClutterCatalog alloc] initWithRowDirectories:@[rows, mine]];
    NSMutableArray *got = [NSMutableArray new];
    for (NSString *k in @[@"node-modules", @"pip-cache", @"xcode-derived-data", @"pnpm-store", @"gradle-project", @"python-pycache", @"npm-cache", @"cursor", @"dist-build", @"python-venv", @"maven",
                          @"tmpdir-families", @"claude-code-scratch", @"simulator-devices", @"rm-leak", @"rm-word", @"rm-one", @"rm-yes"])
        [got addObject:[NSString stringWithFormat:@"%@=%d", k, [cat kind:k].rebuilt]];
    T(@"rows: which say a tool rebuilds them",
      @"node-modules=1 pip-cache=1 xcode-derived-data=1 pnpm-store=1 gradle-project=0 python-pycache=0 npm-cache=0 cursor=0 dist-build=0 python-venv=0 maven=0 tmpdir-families=0 claude-code-scratch=0 simulator-devices=0 rm-leak=0 rm-word=0 rm-one=0 rm-yes=1",
      [got componentsJoinedByString:@" "]);
    NSInteger leaks = 0, said = 0;
    for (MMClutterKind *k in cat.kinds) { if (k.rebuilt) said++; if (k.rebuilt && k.klass != MMClutterCache && k.klass != MMClutterBuild && k.klass != MMClutterTool) leaks++; }
    T(@"rows: no leftover, data or report row says rebuilt", @"0 yes", [NSString stringWithFormat:@"%ld %@", (long)leaks, YN(said >= 20)]);
    T(@"rows: what proves a rebuild: a lockfile for node_modules, the row's beside file where it names no other", @"package-lock.json,npm-shrinkwrap.json,pnpm-lock.yaml,yarn.lock,bun.lock,bun.lockb|Cargo.toml|0 0",
      [NSString stringWithFormat:@"%@|%@|%d %d", [[cat kind:@"node-modules"].rebuiltFrom componentsJoinedByString:@","], [[cat kind:@"cargo-target"].rebuiltFrom componentsJoinedByString:@","],
       [cat kind:@"gradle-project"].rebuilt, [cat kind:@"python-pycache"].rebuilt]);
}

#pragma mark - Acting on it

static MMUndoRecord *Begin(NSString *kind, NSString *subject) {
    return [MMUndo.shared begin:@"removaltest" kind:kind finding:[@"removaltest:" stringByAppendingString:subject] subject:subject
                            why:@"test" by:@"manual" parent:nil payload:nil];
}
static MMUndoRecord *Done(MMUndoRecord *r) { [MMUndo.shared finish:r ok:YES freed:0 error:nil]; return [MMUndo.shared record:r.rid]; }

static void Apply(void) {
    MMRemovalDecision *keep = MMRemovalDecide(MMRemovalClutter, nil, nil);
    MMRemovalDecision *del = MMRemovalTestDeleteDecision(MMRemovalClutter);
    NSError *e = nil;

    NSString *kept = Path(@"apply/kept/cache");
    Write([kept stringByAppendingPathComponent:@"a.bin"], @"a");
    MMUndoRecord *r = Begin(@"trash", @"kept");
    MMRemovalNote(r, keep, nil);
    BOOL ok = MMRemovalApply(kept, keep, r, &e);
    MMRemovalDone(r, nil);
    r = Done(r);
    NSString *to = [r.payload[@"trashed"] firstObject][@"to"];
    T(@"apply keep: it left and sits in the test home's Trash", @"yes no yes yes", [NSString stringWithFormat:@"%@ %@ %@ %@", YN(ok), YN(Exists(kept)), YN(Exists(to)),
      YN([to hasPrefix:[MMTrashFolder() stringByAppendingString:@"/"]])]);
    T(@"apply keep: the record says trash, not deleted, and can restore", @"trash 0 no yes 0", [NSString stringWithFormat:@"%@ %@ %@ %@ %lu", r.payload[@"removal"][@"choice"],
      r.payload[@"removal"][@"deleted"], YN(r.deletedNow), YN(r.canRestore), (unsigned long)[r.payload[@"deleted"] count]]);
    T(@"apply keep: restore brings it back", @"nil yes", [NSString stringWithFormat:@"%@ %@", Or([MMUndo.shared restore:r.rid]), YN(Exists([kept stringByAppendingPathComponent:@"a.bin"]))]);

    NSString *gone = Path(@"apply/gone/cache");
    Write([gone stringByAppendingPathComponent:@"deep/b.bin"], @"b");
    Write([gone stringByAppendingPathComponent:@"c.bin"], @"c");
    NSUInteger before = TrashCount();
    r = Begin(@"trash", @"gone");
    MMRemovalNote(r, del, nil);
    e = nil;
    BOOL unasked = MMRemovalApply(gone, del, r, &e);
    T(@"apply delete: a path no fresh finding named is refused and stays", @"no yes MinMacs never deletes it: no fresh finding names it",
      [NSString stringWithFormat:@"%@ %@ %@", YN(unasked), YN(Exists(gone)), e.localizedDescription]);
    T(@"apply delete: before the act the record wants the delete and says nothing is deleted", @"1 0 no", [NSString stringWithFormat:@"%@ %@ %@",
      r.payload[@"removal"][@"wants"], r.payload[@"removal"][@"deleted"], YN(r.deletedNow)]);
    MMRemovalAsk(r, @[gone]);
    e = nil;
    ok = MMRemovalApply(gone, del, r, &e);
    MMRemovalDone(r, nil);
    r = Done(r);
    T(@"apply delete: the folder is unlinked and nothing new is in the Trash", @"yes no 0", [NSString stringWithFormat:@"%@ %@ %ld", YN(ok), YN(Exists(gone)), (long)(TrashCount() - before)]);
    T(@"apply delete: the record lists the path and holds no trashed entry", [NSString stringWithFormat:@"%@ 0", gone],
      [NSString stringWithFormat:@"%@ %lu", [r.payload[@"deleted"] firstObject][@"path"], (unsigned long)[r.payload[@"trashed"] count]]);
    T(@"apply delete: the record says deleted and cannot restore", @"delete 1 yes no", [NSString stringWithFormat:@"%@ %@ %@ %@", r.payload[@"removal"][@"choice"],
      r.payload[@"removal"][@"deleted"], YN(r.deletedNow), YN(r.canRestore)]);
    T(@"apply delete: restore says it was deleted", @"it was deleted and cannot be brought back", Or([MMUndo.shared restore:r.rid]));
    T(@"apply delete: the refused restore changes nothing", @"done no", [NSString stringWithFormat:@"%@ %@", [MMUndo.shared record:r.rid].state == MMUndoDone ? @"done" : @"other", YN(Exists(gone))]);

    // A symlink is removed as a link. What it points at stays.
    NSString *target = Path(@"apply/target"), *link = Path(@"apply/link");
    Write([target stringByAppendingPathComponent:@"keep.txt"], @"keep");
    [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:target error:nil];
    NSString *holder = Path(@"apply/holder");
    Write([holder stringByAppendingPathComponent:@"x"], @"x");
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[holder stringByAppendingPathComponent:@"inner-link"] withDestinationPath:target error:nil];
    r = Begin(@"trash", @"links");
    MMRemovalAsk(r, @[link, holder]);
    BOOL l1 = MMRemovalApply(link, del, r, nil), l2 = MMRemovalApply(holder, del, r, nil);
    r = Done(r);
    T(@"apply delete: a symlink goes and what it points at stays", @"yes yes no no yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@", YN(l1), YN(l2), YN(Exists(link)), YN(Exists(holder)),
      YN(Exists([target stringByAppendingPathComponent:@"keep.txt"]))]);

    // A delete that stops partway says so in the record and in its answer.
    NSString *stuck = Path(@"apply/stuck");
    Write([stuck stringByAppendingPathComponent:@"locked/d.bin"], @"d");
    chmod([stuck stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, 0500);
    r = Begin(@"trash", @"stuck");
    MMRemovalNote(r, del, nil);
    MMRemovalAsk(r, @[stuck]);
    e = nil;
    ok = MMRemovalApply(stuck, del, r, &e);
    [MMUndo.shared finish:r ok:NO freed:0 error:@"it could not be deleted"];
    r = [MMUndo.shared record:r.rid];
    // The words of a record that failed: it never says deleted, and restore does not say nothing changed.
    T(@"apply delete: the failed record does not say deleted", @"1 0 no no", [NSString stringWithFormat:@"%@ %@ %@ %@", r.payload[@"removal"][@"wants"],
      r.payload[@"removal"][@"deleted"], YN(r.deletedNow), YN(r.canRestore)]);
    T(@"apply delete: restore of it says it failed partway and what went", [@"the action failed partway. What it had deleted by then cannot be brought back: " stringByAppendingString:stuck],
      Or([MMUndo.shared restore:r.rid]));
    T(@"apply delete: a folder it cannot empty fails and the record says partial", @"no yes 1 yes", [NSString stringWithFormat:@"%@ %@ %@ %@", YN(ok), YN(e != nil),
      [r.payload[@"deleted"] firstObject][@"partial"], YN(Exists([stuck stringByAppendingPathComponent:@"locked/d.bin"]))]);
    chmod([stuck stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, 0700);

    // The walls that hold inside MINMACS_HOME: MinMacs's own folder, and what is not there.
    r = Begin(@"trash", @"walls");
    MMRemovalAsk(r, @[MMSupportDir(), Path(@"apply/no-such"), kept]);
    e = nil;
    ok = MMRemovalApply(MMSupportDir(), del, r, &e);
    T(@"apply delete: MinMacs's own folder is refused", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(ok), YN(Exists(MMSupportDir()))]);
    e = nil;
    ok = MMRemovalApply(Path(@"apply/no-such"), del, r, &e);
    T(@"apply delete: a path that is gone is refused", @"no it is gone", [NSString stringWithFormat:@"%@ %@", YN(ok), e.localizedDescription]);
    T(@"apply: nothing to act on is refused", @"no no", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalApply(nil, del, r, nil)), YN(MMRemovalApply(kept, nil, r, nil))]);
    T(@"apply: a path that is not a full path is refused, for the Trash and for a delete", @"no no", [NSString stringWithFormat:@"%@ %@",
      YN(MMRemovalApply(@"apply/kept/cache", keep, r, nil)), YN(MMRemovalApply(@"apply/kept/cache", del, r, nil))]);
    T(@"apply: the refusals left no deleted entry", @"0", @([[MMUndo.shared record:r.rid].payload[@"deleted"] count]).stringValue);
}

#pragma mark - Records

static void Records(void) {
    NSDictionary *where = @{@"repo": Path(@"repo"), @"worktree": Path(@"wt"), @"head": @"0123456789abcdef", @"branch": @"feat"};
    // A merged worktree an older MinMacs removed under Smart: the record says deleted, and restore still works, since
    // git holds it. MinMacs makes no such record now, so its "removal" is written as that MinMacs wrote it.
    MMUndoRecord *a = Begin(@"remove", @"smart tree");
    [MMUndo.shared note:a payload:@{@"removal": @{@"choice": @"smart", @"wants": @YES, @"deleted": @NO, @"why": @"git can give it back",
                                                  @"ignored": @{@"choice": @"smart", @"wants": @NO, @"deleted": @NO, @"why": @"git does not hold the files it ignores"}}}];
    [MMUndo.shared note:a payload:@{@"worktree": where}];
    MMRemovalDone(a, nil); MMRemovalDone(a, @"ignored");
    a = Done(a);
    T(@"record: an old smart worktree says deleted and can still restore from git", @"yes yes 0", [NSString stringWithFormat:@"%@ %@ %@", YN(a.deletedNow), YN(a.canRestore),
      a.payload[@"removal"][@"ignored"][@"deleted"]]);
    // An old record under Delete restores nothing, and the refusal names the bundle that was still taken.
    MMUndoRecord *b = Begin(@"remove", @"delete tree");
    MMRemovalNote(b, MMRemovalTestDeleteDecision(MMRemovalWorktree), nil);
    MMRemovalDone(b, nil);
    [MMUndo.shared note:b payload:@{@"bundle": @{@"path": Path(@"b.bundle"), @"repo": where[@"repo"], @"worktree": where[@"worktree"], @"head": where[@"head"]}}];
    b = Done(b);
    T(@"record: a worktree under Delete cannot restore, bundle or not", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(b.deletedNow), YN(b.canRestore)]);
    T(@"record: its refusal names the bundle", [@"it was deleted and cannot be brought back. Its commits on no remote are in the git bundle " stringByAppendingString:Path(@"b.bundle")],
      Or([MMUndo.shared restore:b.rid]));
    // A worktree removed now keeps its way back.
    MMUndoRecord *c = Begin(@"remove", @"trash tree");
    MMRemovalNote(c, MMRemovalDecide(MMRemovalWorktree, nil, nil), nil);
    MMRemovalDone(c, nil);
    [MMUndo.shared note:c payload:@{@"worktree": where}];
    c = Done(c);
    T(@"record: a worktree removed now is not deleted and can restore", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(c.deletedNow), YN(c.canRestore)]);
    // A record written before the choice existed reads as before.
    MMUndoRecord *old = Begin(@"trash", @"old");
    [MMUndo.shared note:old payload:@{@"trashed": @[@{@"from": Path(@"old/from"), @"to": Path(@"old/to")}]}];
    old = Done(old);
    T(@"record: one with no removal entry is not deleted and can restore", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(old.deletedNow), YN(old.canRestore)]);

    MMUndoRecord *gone = Begin(@"trash", @"gone cache");
    // An old record of a cache Smart deleted at once.
    [MMUndo.shared note:gone payload:@{@"removal": @{@"choice": @"smart", @"wants": @YES, @"deleted": @NO, @"why": @"its tool rebuilds it"}}];
    MMRemovalDone(gone, nil);
    gone = Done(gone);
    // A removal under Delete that failed before the thing went: it wanted the delete, and nothing says deleted.
    MMUndoRecord *never = Begin(@"remove", @"refused tree");
    MMRemovalNote(never, MMRemovalTestDeleteDecision(MMRemovalWorktree), nil);
    [MMUndo.shared finish:never ok:NO freed:0 error:@"git worktree remove refused"];
    never = [MMUndo.shared record:never.rid];
    T(@"record: a failed removal under Delete does not say deleted", @"delete 1 0 no", [NSString stringWithFormat:@"%@ %@ %@ %@", never.payload[@"removal"][@"choice"],
      never.payload[@"removal"][@"wants"], never.payload[@"removal"][@"deleted"], YN(never.deletedNow)]);
    T(@"record: its restore says nothing changed", @"the action failed and changed nothing, so there is nothing to restore", Or([MMUndo.shared restore:never.rid]));
    MMUndoRecord *stop = Begin(@"stop", @"a server");
    [MMUndo.shared note:stop payload:@{@"restart": @{@"command": @"true"}}];
    stop = Done(stop);
    T(@"where: deleted, the Trash and what Restore brings back, each counted once", @"Deleted 2, moved 1 to the Trash and removed 1 that Restore brings back.",
      Or(MMRemovalWhereWords(@[a, gone, old, c, stop])));
    T(@"where: two kinds", @"Deleted 1, moved 1 to the Trash.", Or(MMRemovalWhereWords(@[gone, old])));
    T(@"where: one kind", @"Moved 1 to the Trash.", Or(MMRemovalWhereWords(@[old])));
    T(@"where: a stop is not a removal", @"nil", Or(MMRemovalWhereWords(@[stop])));
    MMUndoRecord *failed = Begin(@"trash", @"failed");
    [MMUndo.shared finish:failed ok:NO freed:0 error:@"no"];
    T(@"where: a failed record counts nowhere", @"nil", Or(MMRemovalWhereWords(@[[MMUndo.shared record:failed.rid]])));
}

// The wall as a rule on strings, and what a Wrap Up stages.
#import "wall.m"

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "MINMACS_HOME is not set\n"); return 2; }
        if (argc == 3 && !strcmp(argv[1], "--wall")) {
            MMUndoRecord *r = Begin(@"trash", @"wall");
            // The path is named, as a fresh finding would name it, so the answer is the wall's and not "nobody asked".
            MMRemovalAsk(r, @[@(argv[2])]);
            NSError *e = nil;
            BOOL ok = MMRemovalApply(@(argv[2]), MMRemovalTestDeleteDecision(MMRemovalClutter), r, &e);
            printf("%s: %s\n", ok ? "deleted" : "refused", e.localizedDescription.UTF8String ?: "");
            return ok ? 0 : 1;
        }
        if (argc == 3 && !strcmp(argv[1], "--leave-waiting")) return LeaveWaiting(@(argv[2]));
        if (argc == 4 && !strcmp(argv[1], "--stop-after-rename")) return StopAfterRenameChild(@(argv[2]), @(argv[3]));
        if (argc == 4 && !strcmp(argv[1], "--pipe")) return PipeChild(@(argv[2]), @(argv[3]));
        if (argc == 4 && !strcmp(argv[1], "--stop-in-trash")) return StopInTrashChild(@(argv[2]), @(argv[3]));
        if (argc == 6 && !strcmp(argv[1], "--stop-second")) return StopSecondChild(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        char me[PATH_MAX];
        gSelf = realpath(argv[0], me) ? @(me) : @(argv[0]);
        if (argc == 3 && !strcmp(argv[1], "--leave-in-trash")) return LeaveInTrash(@(argv[2]));
        if (argc < 3) { fprintf(stderr, "usage: removaltest <dir> <registry/clutter>\n"); return 2; }
        gDir = @(argv[1]);
        Pref();
        Worktrees();
        Clutters(@(argv[2]));
        Apply();
        Records();
        Wall();
        Staged();
        Crash();
        Stranded();
        Owners();
        Damaged();
        Leftovers();
        Guards();
        Forged();
        DamagedWordsSay();
        Closing();
        Unasked();
        TrashRule();
        Stopped();
        Moved();
        Pipes();
        TrashedByMinMacs();
        TrashStopped();
        TrashListLows();
        TrashReviewed();
        TrashOwnNames();
        TrashLinkedNames();
        printf("END\n");
    }
    return 0;
}
