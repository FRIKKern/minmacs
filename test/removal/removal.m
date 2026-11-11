// The removal choice, issue #62: the pref, the one decision, the one place that deletes, and what a record says.
// test/removal.sh builds this with all of Sources/Core and runs it twice.
// Usage: removaltest <dir> <registry/clutter>     every check, on fixtures it makes in <dir>
//        removaltest --wall <path>                asks MMRemovalApply to delete <path> and prints why it refused
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

static void Pref(void) {
    MMSetPref(MMRemovalKey, nil);
    T(@"pref: with no value the choice is smart", @"smart", MMRemovalChoiceName(MMRemovalChoiceNow()));
    MMSetRemovalChoice(MMRemovalTrash);
    T(@"pref: trash is kept as the word trash under core.removal", @"trash trash", [NSString stringWithFormat:@"%@ %@", MMPref(@"core.removal"), MMRemovalChoiceName(MMRemovalChoiceNow())]);
    MMSetRemovalChoice(MMRemovalDelete);
    T(@"pref: it is read again at each ask", @"delete", MMRemovalChoiceName(MMRemovalChoiceNow()));
    // A value nobody can read must never delete: it counts as the Trash, not as the default.
    MMSetPref(MMRemovalKey, @"shred");
    T(@"pref: a word that is no choice counts as trash", @"trash", MMRemovalChoiceName(MMRemovalChoiceNow()));
    MMSetPref(MMRemovalKey, @2);
    T(@"pref: a number counts as trash", @"trash", MMRemovalChoiceName(MMRemovalChoiceNow()));
    MMSetPref(MMRemovalKey, @"Delete");
    T(@"pref: case does not matter", @"delete", MMRemovalChoiceName(MMRemovalChoiceNow()));
    MMSetPref(MMRemovalKey, nil);
    T(@"pref: the three names", @"smart trash delete -1", [NSString stringWithFormat:@"%@ %@ %@ %ld", MMRemovalChoiceName(MMRemovalSmart),
      MMRemovalChoiceName(MMRemovalTrash), MMRemovalChoiceName(MMRemovalDelete), (long)MMRemovalChoiceFrom(@"for good")]);
    T(@"pref: Smart's sentence", @"Deletes what git or its tool can give back. The rest goes to the Trash.", MMRemovalChoiceExplain(MMRemovalSmart));
    T(@"pref: Trash's sentence", @"Everything goes to the Trash. The disk comes back when you empty it.", MMRemovalChoiceExplain(MMRemovalTrash));
    T(@"pref: Delete's sentence", @"Deletes everything it removes at once. Nothing can be brought back.", MMRemovalChoiceExplain(MMRemovalDelete));
}

#pragma mark - The decision

static void Worktrees(void) {
    MMRemovalThing w = MMRemovalWorktree;
    T(@"smart worktree: merged and clean is deleted", @"delete: its branch is merged and every commit is on a remote, so git can give it back",
      Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 0, 0, 0))));
    T(@"smart worktree: remote branch gone and clean is deleted", @"delete: its remote branch is gone and every commit is on a remote, so git can give it back",
      Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(NO, YES, 0, 0, 0, 0))));
    // The strict cases: each one alone keeps a way back, even on a merged branch.
    T(@"smart worktree: an uncommitted change keeps it", @"keep: 1 change is not committed", Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 1, 0, 0, 0))));
    T(@"smart worktree: an untracked file keeps it", @"keep: 1 untracked file is not in git", Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 1, 0, 0))));
    T(@"smart worktree: an unpushed commit keeps it", @"keep: 2 commits are on no remote", Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 0, 2, 0))));
    T(@"smart worktree: a stash keeps it", @"keep: it has 1 stash", Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 0, 0, 1))));
    T(@"smart worktree: not merged with its remote branch keeps it", @"keep: its branch is not merged and its remote branch still exists",
      Says(MMRemovalDecideWith(MMRemovalSmart, w, Tree(NO, NO, 0, 0, 0, 0))));
    T(@"smart worktree: a count git could not give keeps it", @"keep keep keep keep", [NSString stringWithFormat:@"%@ %@ %@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, -1, 0, 0, 0))), Word(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, -1, 0, 0))),
      Word(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 0, -1, 0))), Word(MMRemovalDecideWith(MMRemovalSmart, w, Tree(YES, NO, 0, 0, 0, -1)))]);
    MMRemovalFacts *unknown = Tree(YES, NO, 0, 0, 0, 0);
    unknown.gitKnown = NO;
    T(@"smart worktree: unknown git facts keep it", @"keep: cannot verify its git facts", Says(MMRemovalDecideWith(MMRemovalSmart, w, unknown)));
    T(@"smart worktree: facts nobody set keep it", @"keep keep", [NSString stringWithFormat:@"%@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, w, [MMRemovalFacts new])), Word(MMRemovalDecideWith(MMRemovalSmart, w, nil))]);
    T(@"trash worktree: merged and clean keeps a way back", @"keep: you chose the Trash, so a way back is kept", Says(MMRemovalDecideWith(MMRemovalTrash, w, Tree(YES, NO, 0, 0, 0, 0))));
    T(@"delete worktree: deleted whatever its facts", @"delete: you chose Delete, so it is deleted at once", Says(MMRemovalDecideWith(MMRemovalDelete, w, Tree(NO, NO, 0, 0, 3, 1))));
    // Files git does not hold are never Smart's to delete, on the best facts there are.
    MMRemovalFacts *best = Tree(YES, NO, 0, 0, 0, 0);
    T(@"ignored files: smart and trash keep them, delete does not", @"keep keep delete", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, MMRemovalIgnoredFiles, best)), Word(MMRemovalDecideWith(MMRemovalTrash, MMRemovalIgnoredFiles, best)),
      Word(MMRemovalDecideWith(MMRemovalDelete, MMRemovalIgnoredFiles, best))]);
    T(@"ignored files: smart says why", @"git does not hold the files it ignores", MMRemovalDecideWith(MMRemovalSmart, MMRemovalIgnoredFiles, best).why);
    T(@"config files: smart and trash keep them, delete does not", @"keep keep delete", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, MMRemovalConfigFiles, best)), Word(MMRemovalDecideWith(MMRemovalTrash, MMRemovalConfigFiles, best)),
      Word(MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, best))]);
}

static void Clutters(NSString *rows) {
    MMRemovalThing c = MMRemovalClutter;
    T(@"smart clutter: a rebuilt cache is deleted", @"delete: its tool rebuilds it", Says(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterCache, YES, YES, NO))));
    T(@"smart clutter: rebuilt build output is deleted", @"delete", Word(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterBuild, YES, YES, NO))));
    T(@"smart clutter: a cache whose row does not say rebuilt is kept", @"keep: its row does not say that a tool rebuilds it",
      Says(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterCache, NO, YES, NO))));
    T(@"smart clutter: a leftover is kept, whatever else is set", @"keep: it is a leftover, and nothing rebuilds a leftover",
      Says(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterLeak, YES, YES, NO))));
    T(@"smart clutter: an item in use is kept", @"keep: cannot verify that nothing uses it", Says(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterBuild, YES, NO, NO))));
    T(@"smart clutter: build output whose project is gone is kept", @"keep: its project is gone, so nothing can rebuild it",
      Says(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterBuild, YES, YES, YES))));
    T(@"smart clutter: tool, data and report rows are never deleted as clutter", @"keep keep keep", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterTool, YES, YES, NO))), Word(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterData, YES, YES, NO))),
      Word(MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterReport, YES, YES, NO)))]);
    T(@"smart clutter: facts nobody set keep it", @"keep keep", [NSString stringWithFormat:@"%@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, c, [MMRemovalFacts new])), Word(MMRemovalDecideWith(MMRemovalSmart, c, nil))]);
    T(@"trash clutter: a rebuilt cache keeps a way back", @"keep", Word(MMRemovalDecideWith(MMRemovalTrash, c, Clutter(MMClutterCache, YES, YES, NO))));
    T(@"delete clutter: a leftover is deleted", @"delete", Word(MMRemovalDecideWith(MMRemovalDelete, c, Clutter(MMClutterLeak, NO, YES, NO))));
    T(@"tool copy: smart keeps no copy only for a rebuilt tool row", @"delete keep keep", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecideWith(MMRemovalSmart, MMRemovalToolCopy, Clutter(MMClutterTool, YES, YES, NO))),
      Word(MMRemovalDecideWith(MMRemovalSmart, MMRemovalToolCopy, Clutter(MMClutterTool, NO, YES, NO))),
      Word(MMRemovalDecideWith(MMRemovalSmart, MMRemovalToolCopy, Clutter(MMClutterCache, YES, YES, NO)))]);
    T(@"tool copy: trash keeps the copy and delete does not", @"keep delete", [NSString stringWithFormat:@"%@ %@",
      Word(MMRemovalDecideWith(MMRemovalTrash, MMRemovalToolCopy, Clutter(MMClutterTool, YES, YES, NO))),
      Word(MMRemovalDecideWith(MMRemovalDelete, MMRemovalToolCopy, Clutter(MMClutterTool, NO, YES, NO)))]);
    T(@"the answer as json wants the delete, and says nothing is deleted yet", @"smart 1 0 its tool rebuilds it", ({ NSDictionary *j = MMRemovalDecideWith(MMRemovalSmart, c, Clutter(MMClutterCache, YES, YES, NO)).json;
      [NSString stringWithFormat:@"%@ %@ %@ %@", j[@"choice"], j[@"wants"], j[@"deleted"], j[@"why"]]; }));
    // The row says rebuilt, and the fresh check could not prove it for this folder: a way back is kept, with that reason.
    MMRemovalFacts *unproven = Clutter(MMClutterBuild, YES, YES, NO);
    unproven.unproven = @"no package-lock.json sits beside it";
    T(@"smart clutter: a rebuilt row whose rebuild is not proven now is kept", @"keep: no package-lock.json sits beside it", Says(MMRemovalDecideWith(MMRemovalSmart, c, unproven)));
    T(@"delete clutter: an unproven one is deleted, since the person chose so", @"delete", Word(MMRemovalDecideWith(MMRemovalDelete, c, unproven)));

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
    MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalClutter, nil);
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil);
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
    MMRemovalDecision *smartTree = MMRemovalDecideWith(MMRemovalSmart, MMRemovalWorktree, Tree(YES, NO, 0, 0, 0, 0));
    NSDictionary *where = @{@"repo": Path(@"repo"), @"worktree": Path(@"wt"), @"head": @"0123456789abcdef", @"branch": @"feat"};
    // A merged worktree under Smart: the record says deleted, and restore still works, since git holds it.
    MMUndoRecord *a = Begin(@"remove", @"smart tree");
    MMRemovalNote(a, smartTree, nil);
    MMRemovalNote(a, MMRemovalDecideWith(MMRemovalSmart, MMRemovalIgnoredFiles, nil), @"ignored");
    [MMUndo.shared note:a payload:@{@"worktree": where}];
    MMRemovalDone(a, nil); MMRemovalDone(a, @"ignored");
    a = Done(a);
    T(@"record: a smart worktree says deleted and can still restore from git", @"yes yes 0", [NSString stringWithFormat:@"%@ %@ %@", YN(a.deletedNow), YN(a.canRestore),
      a.payload[@"removal"][@"ignored"][@"deleted"]]);
    // Under Delete nothing restores, and the refusal names the bundle that was still taken.
    MMUndoRecord *b = Begin(@"remove", @"delete tree");
    MMRemovalNote(b, MMRemovalDecideWith(MMRemovalDelete, MMRemovalWorktree, nil), nil);
    MMRemovalDone(b, nil);
    [MMUndo.shared note:b payload:@{@"bundle": @{@"path": Path(@"b.bundle"), @"repo": where[@"repo"], @"worktree": where[@"worktree"], @"head": where[@"head"]}}];
    b = Done(b);
    T(@"record: a worktree under Delete cannot restore, bundle or not", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(b.deletedNow), YN(b.canRestore)]);
    T(@"record: its refusal names the bundle", [@"it was deleted and cannot be brought back. Its commits on no remote are in the git bundle " stringByAppendingString:Path(@"b.bundle")],
      Or([MMUndo.shared restore:b.rid]));
    // A worktree under the Trash choice keeps its way back.
    MMUndoRecord *c = Begin(@"remove", @"trash tree");
    MMRemovalNote(c, MMRemovalDecideWith(MMRemovalTrash, MMRemovalWorktree, nil), nil);
    MMRemovalDone(c, nil);
    [MMUndo.shared note:c payload:@{@"worktree": where}];
    c = Done(c);
    T(@"record: a worktree under Trash is not deleted and can restore", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(c.deletedNow), YN(c.canRestore)]);
    // A record written before the choice existed reads as before.
    MMUndoRecord *old = Begin(@"trash", @"old");
    [MMUndo.shared note:old payload:@{@"trashed": @[@{@"from": Path(@"old/from"), @"to": Path(@"old/to")}]}];
    old = Done(old);
    T(@"record: one with no removal entry is not deleted and can restore", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(old.deletedNow), YN(old.canRestore)]);

    MMUndoRecord *gone = Begin(@"trash", @"gone cache");
    MMRemovalNote(gone, MMRemovalDecideWith(MMRemovalSmart, MMRemovalClutter, Clutter(MMClutterCache, YES, YES, NO)), nil);
    MMRemovalDone(gone, nil);
    gone = Done(gone);
    // A removal under Delete that failed before the thing went: it wanted the delete, and nothing says deleted.
    MMUndoRecord *never = Begin(@"remove", @"refused tree");
    MMRemovalNote(never, MMRemovalDecideWith(MMRemovalDelete, MMRemovalWorktree, nil), nil);
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

// Who is asked, the wall as a rule on strings, and what a Wrap Up stages.
#import "wall.m"

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "MINMACS_HOME is not set\n"); return 2; }
        if (argc == 3 && !strcmp(argv[1], "--wall")) {
            MMUndoRecord *r = Begin(@"trash", @"wall");
            // The path is named, as a fresh finding would name it, so the answer is the wall's and not "nobody asked".
            MMRemovalAsk(r, @[@(argv[2])]);
            NSError *e = nil;
            BOOL ok = MMRemovalApply(@(argv[2]), MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil), r, &e);
            printf("%s: %s\n", ok ? "deleted" : "refused", e.localizedDescription.UTF8String ?: "");
            return ok ? 0 : 1;
        }
        if (argc < 3) { fprintf(stderr, "usage: removaltest <dir> <registry/clutter>\n"); return 2; }
        gDir = @(argv[1]);
        Pref();
        Worktrees();
        Clutters(@(argv[2]));
        Apply();
        Records();
        Chosen();
        Wall();
        Staged();
        Crash();
        printf("END\n");
    }
    return 0;
}
