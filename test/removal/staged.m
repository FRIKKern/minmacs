// Included by wall.m. What a Wrap Up stages, issue #62: a part's delete waits in a folder of MinMacs's own, never in
// the person's Trash. It is deleted after the last part, put back at its exact old path when a part refuses, and put
// back after a crash. Every file here is a fixture under <dir>, inside $MINMACS_HOME.

static MMUndoRecord *Part(NSString *parent, NSString *subject) {
    return [MMUndo.shared begin:@"removaltest" kind:@"trash" finding:[@"removaltest:" stringByAppendingString:subject] subject:subject
                            why:@"test" by:@"manual" parent:parent payload:@{@"part": @0}];
}
static NSString *Read(NSString *path) { return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"(none)"; }
static NSString *StagedRoot(void) { return [MMRemovalRealPath(MMSupportDir()) stringByAppendingPathComponent:@"staged"]; }
static NSUInteger Holds(NSString *folder) { return [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil].count; }

/// A part of parent that stages the file at path under Delete, as a config part does. Returns the finished record.
static MMUndoRecord *StageOne(MMUndoRecord *parent, NSString *subject, NSString *path) {
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *part = Part(parent.rid, subject);
    MMRemovalNote(part, del, nil);
    MMRemovalAsk(part, @[path]);
    MMRemovalApply(path, del, part, nil);
    MMRemovalDone(part, nil);
    return Done(part);
}

static void Staged(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"staged/wt"), *env = [tree stringByAppendingPathComponent:@".env.local"];
    MMUndoRecord *parent = Begin(@"wrapup", @"staged parent");
    [MMUndo.shared note:parent payload:@{@"path": tree}];
    NSUInteger trash0 = TrashCount();

    // The staging folder as a rule on strings.
    NSString *sup = @"/Users/me/Library/Application Support/MinMacs", *own = [sup stringByAppendingString:@"/staged/abc123"];
    T(@"staging rule: MinMacs's own folder for the rid, and the hidden one beside a worktree, hold what may go", @"may go|may go", [@[
      MMRemovalStagingWhyNot([own stringByAppendingString:@"/0.env"], own, @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot(@"/Volumes/D/code/.minmacs-staged-abc123/0.env", @"/Volumes/D/code/.minmacs-staged-abc123", @"abc123", sup) ?: @"may go"] componentsJoinedByString:@"|"]);
    T(@"staging rule: a folder for another Wrap Up, one that only looks alike, and one outside are refused",
      @"its folder is not the staging folder of this Wrap Up|its folder is not the staging folder of this Wrap Up|its folder is not the staging folder of this Wrap Up|its folder is not the staging folder of this Wrap Up", [@[
      MMRemovalStagingWhyNot([sup stringByAppendingString:@"/staged/zzz999/0.env"], [sup stringByAppendingString:@"/staged/zzz999"], @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot(@"/Volumes/D/code/.minmacs-staged-abc1234/0.env", @"/Volumes/D/code/.minmacs-staged-abc1234", @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot(@"/Users/me/staged/abc123/0.env", @"/Users/me/staged/abc123", @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot(@"/Users/me/Documents/0.env", @"/Users/me/Documents", @"abc123", sup) ?: @"may go"] componentsJoinedByString:@"|"]);
    T(@"staging rule: only what lies directly in the folder, and only with a rid", @"it does not lie directly in the staging folder|it does not lie directly in the staging folder|cannot verify whose staging folder it is", [@[
      MMRemovalStagingWhyNot([own stringByAppendingString:@"/deep/0.env"], own, @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot(own, own, @"abc123", sup) ?: @"may go",
      MMRemovalStagingWhyNot([own stringByAppendingString:@"/0.env"], own, @"", sup) ?: @"may go"] componentsJoinedByString:@"|"]);

    // A part of a Wrap Up under Delete: its file leaves by one rename and waits in MinMacs's own folder.
    Write(env, @"API=1");
    MMUndoRecord *part = StageOne(parent, @"config", env);
    NSString *to = [part.payload[@"staged"] firstObject][@"to"], *folder = part.payload[@"stagedIn"];
    T(@"staged: the file left its place and waits in <support>/staged/<wrap up rid>", [NSString stringWithFormat:@"no yes %@", [StagedRoot() stringByAppendingPathComponent:parent.rid]],
      [NSString stringWithFormat:@"%@ %@ %@", YN(Exists(env)), YN(to.length && Exists(to) && [to.stringByDeletingLastPathComponent isEqualToString:folder]), folder]);
    T(@"staged: nothing went to the Trash, and the record lists no Trash entry", @"0 0", [NSString stringWithFormat:@"%ld %lu", (long)(TrashCount() - trash0), (unsigned long)[part.payload[@"trashed"] count]]);
    T(@"staged: the folder holds the marker with the Wrap Up's rid", parent.rid, Read([folder stringByAppendingPathComponent:@".minmacs"]));
    T(@"staged: its record says staged, not deleted, and can still restore", @"delete 1 1 0 no yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", part.payload[@"removal"][@"choice"],
      part.payload[@"removal"][@"wants"], part.payload[@"removal"][@"staged"], part.payload[@"removal"][@"deleted"], YN(part.deletedNow), YN(part.canRestore)]);
    // A later part refused: the item goes back to its exact old path, and the empty folder goes.
    T(@"put back: the file is at its exact old path again, as it was, and the staging folder is gone", @"nil API=1 no no", [NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalPutBack(@[part])),
      Read(env), YN(Exists(to)), YN(Exists(folder))]);
    part = [MMUndo.shared record:part.rid];
    T(@"put back: the part says restored, and never deleted", @"restored no", [NSString stringWithFormat:@"%@ %@", part.state == MMUndoRestored ? @"restored" : @"other", YN(part.deletedNow)]);

    // Something sits at the old path by the time it should go back: nothing is written over, and it says so.
    part = StageOne(parent, @"config blocked", env);
    to = [part.payload[@"staged"] firstObject][@"to"]; folder = part.payload[@"stagedIn"];
    Write(env, @"NEWER=1");
    NSString *problem = MMRemovalPutBack(@[part]);
    T(@"put back: with something at the old path it refuses, writes over nothing, and keeps the staged file", @"yes NEWER=1 API=1 yes", [NSString stringWithFormat:@"%@ %@ %@ %@",
      YN([problem containsString:@"something already exists at"]), Read(env), Read(to), YN(Exists(folder))]);
    [fm removeItemAtPath:env error:nil];
    T(@"put back: once the old path is free it goes back", @"nil API=1 no", [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(env), YN(Exists(folder))]);

    // Every part went through: the staged file is deleted from MinMacs's folder, and only then does the record say so.
    MMUndoRecord *two = StageOne(parent, @"config again", env);
    to = [two.payload[@"staged"] firstObject][@"to"]; folder = two.payload[@"stagedIn"];
    (void)MMRemovalFinishStaged(@[two]);
    two = [MMUndo.shared record:two.rid];
    T(@"finish: the file is gone, the staging folder is gone, and the Trash is as it was", @"no no no 0", [NSString stringWithFormat:@"%@ %@ %@ %ld", YN(Exists(env)), YN(Exists(to)), YN(Exists(folder)),
      (long)(TrashCount() - trash0)]);
    T(@"finish: the record now says deleted, lists the path it came from, and cannot restore", [NSString stringWithFormat:@"1 yes no 0 %@", env],
      [NSString stringWithFormat:@"%@ %@ %@ %lu %@", two.payload[@"removal"][@"deleted"], YN(two.deletedNow), YN(two.canRestore), (unsigned long)[two.payload[@"staged"] count],
       [two.payload[@"deleted"] firstObject][@"path"]]);
    T(@"finish: its restore says it was deleted", @"it was deleted and cannot be brought back", Or([MMUndo.shared restore:two.rid]));

    // Finish deletes only the very file it staged, in the folder MinMacs made for this Wrap Up. Each of these only
    // looks like it, and each stays.
    Write(env, @"API=2");
    MMUndoRecord *three = StageOne(parent, @"config swapped", env);
    to = [three.payload[@"staged"] firstObject][@"to"]; folder = three.payload[@"stagedIn"];
    [fm removeItemAtPath:to error:nil];
    Write(to, @"another file");
    (void)MMRemovalFinishStaged(@[three]);
    T(@"lookalike: another file at the staged place stays, and the record does not say deleted", @"another file no 1", [NSString stringWithFormat:@"%@ %@ %lu", Read(to),
      YN([MMUndo.shared record:three.rid].deletedNow), (unsigned long)[[MMUndo.shared record:three.rid].payload[@"staged"] count]]);
    NSMutableArray *kept = [NSMutableArray new];
    // name of the folder, what its marker says. The record is told its file was staged there, with the file's true inode.
    for (NSArray<NSString *> *fake in @[@[[@"staged/.minmacs-staged-" stringByAppendingString:parent.rid], @""],            // right name, no marker
                                        @[[@"staged/.minmacs-staged-" stringByAppendingString:parent.rid], @"zzz999"],      // right name, another rid's marker
                                        @[@"staged/.minmacs-staged-zzz999", parent.rid],                                    // another rid's name, this rid's marker
                                        @[@"staged/looks-staged", parent.rid]]) {                                            // any folder with the marker
        NSString *dir = Path(fake[0]), *file = [dir stringByAppendingPathComponent:@"0.notes.txt"];
        [fm removeItemAtPath:dir error:nil];
        Write(file, @"mine");
        if (fake[1].length) Write([dir stringByAppendingPathComponent:@".minmacs"], fake[1]);
        struct stat st; lstat(file.fileSystemRepresentation, &st);
        MMUndoRecord *liar = Part(parent.rid, @"lookalike");
        MMRemovalNote(liar, MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil), nil);
        [MMUndo.shared note:liar payload:@{@"stagedIn": dir, @"staged": @[@{@"from": env, @"to": file, @"dev": @(st.st_dev), @"ino": @(st.st_ino)}]}];
        liar = Done(liar);
        (void)MMRemovalFinishStaged(@[liar]);
        [kept addObject:[NSString stringWithFormat:@"%@ %@", Read(file), YN([MMUndo.shared record:liar.rid].deletedNow)]];
    }
    T(@"lookalike: a folder with no marker, another rid's marker, another rid's name, or just a marker: nothing in it is deleted", @"mine no|mine no|mine no|mine no", [kept componentsJoinedByString:@"|"]);
    // One level too deep inside the true staging folder is not staged either.
    NSString *deep = [folder stringByAppendingPathComponent:@"deep/0.notes.txt"];
    Write(deep, @"mine");
    struct stat ds; lstat(deep.fileSystemRepresentation, &ds);
    MMUndoRecord *liar = Part(parent.rid, @"too deep");
    [MMUndo.shared note:liar payload:@{@"stagedIn": folder, @"staged": @[@{@"from": env, @"to": deep, @"dev": @(ds.st_dev), @"ino": @(ds.st_ino)}]}];
    liar = Done(liar);
    (void)MMRemovalFinishStaged(@[liar]);
    T(@"lookalike: a file one level deeper in the true staging folder stays, and the folder is not removed while it holds things", @"mine yes", [NSString stringWithFormat:@"%@ %@", Read(deep), YN(Exists(folder))]);
    [fm removeItemAtPath:[folder stringByAppendingPathComponent:@"deep"] error:nil];
    [fm removeItemAtPath:to error:nil];
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];

    // An item on another volume than the support folder waits in a hidden folder beside the worktree.
    setenv("MINMACS_STAGE_BESIDE", "1", 1);
    MMUndoRecord *far = Begin(@"wrapup", @"far parent");
    [MMUndo.shared note:far payload:@{@"path": tree}];
    Write(env, @"API=3");
    MMUndoRecord *fpart = StageOne(far, @"config far", env);
    NSString *beside = [tree.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:far.rid]];
    T(@"beside: it waits in .minmacs-staged-<rid> beside the worktree, never inside it", [NSString stringWithFormat:@"%@ no 0", beside],
      [NSString stringWithFormat:@"%@ %@ %lu", fpart.payload[@"stagedIn"], YN(Exists(env)), (unsigned long)Holds(tree)]);
    T(@"beside: put back returns it and removes the hidden folder", @"nil API=3 no", [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[fpart])), Read(env), YN(Exists(beside))]);
    fpart = StageOne(far, @"config far again", env);
    (void)MMRemovalFinishStaged(@[fpart]);
    T(@"beside: finish deletes it and removes the hidden folder", @"no no yes", [NSString stringWithFormat:@"%@ %@ %@", YN(Exists(env)), YN(Exists(beside)), YN([MMUndo.shared record:fpart.rid].deletedNow)]);
    // No folder of MinMacs's own on the item's volume: it is never copied. It stays where it is, and the part says so.
    MMUndoRecord *lost = Begin(@"wrapup", @"no path parent");
    Write(env, @"API=4");
    MMUndoRecord *lpart = StageOne(lost, @"config unstaged", env);
    T(@"unstaged: with nowhere to rename to, the file stays where it is and nothing says deleted", @"API=4 0 1 0 no", [NSString stringWithFormat:@"%@ %lu %lu %@ %@", Read(env),
      (unsigned long)[lpart.payload[@"staged"] count], (unsigned long)[lpart.payload[@"unstaged"] count], lpart.payload[@"removal"][@"deleted"], YN(lpart.deletedNow)]);
    T(@"unstaged: the record says why", @"no folder of MinMacs's own is on its volume", [lpart.payload[@"unstaged"] firstObject][@"why"]);
    unsetenv("MINMACS_STAGE_BESIDE");
    [MMUndo.shared finish:far ok:YES freed:0 error:nil];
    [MMUndo.shared finish:lost ok:NO freed:0 error:@"test"];

    // A single action, with no Wrap Up around it, has no later part: it deletes at once, and stages nothing.
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *single = Begin(@"trash", @"single");
    MMRemovalNote(single, del, nil);
    MMRemovalAsk(single, @[env]);
    MMRemovalApply(env, del, single, nil);
    T(@"single: an action that is no part of a Wrap Up deletes at once", @"no 0 1", [NSString stringWithFormat:@"%@ %lu %lu", YN(Exists(env)),
      (unsigned long)[[MMUndo.shared record:single.rid].payload[@"staged"] count], (unsigned long)[[MMUndo.shared record:single.rid].payload[@"deleted"] count]]);
}

/// MinMacs stopped between staging and the end of the Wrap Up: the parent record never finished.
static void Crash(void) {
    NSString *tree = Path(@"crash/wt"), *env = [tree stringByAppendingPathComponent:@".env.local"], *mods = [tree stringByAppendingPathComponent:@"node_modules"];
    // 1. Stopped while parts still ran. Nothing is deleted, and both staged items go back.
    MMUndoRecord *parent = Begin(@"wrapup", @"crashed parent");
    [MMUndo.shared note:parent payload:@{@"path": tree}];
    Write(env, @"KEEP=1"); Write([mods stringByAppendingPathComponent:@"pkg/index.js"], @"x");
    MMUndoRecord *a = StageOne(parent, @"caches", mods), *b = StageOne(parent, @"config", env);
    NSString *folder = b.payload[@"stagedIn"];
    T(@"crash: both are staged and the Wrap Up never finished", @"no no pending", [NSString stringWithFormat:@"%@ %@ %@", YN(Exists(env)), YN(Exists(mods)),
      [MMUndo.shared record:parent.rid].state == MMUndoPending ? @"pending" : @"other"]);
    // These records name no owner, as one written by an older build: only for those does the age decide.
    T(@"crash: a record with no owner that is too young to be a crash is left alone", @"0 no", [NSString stringWithFormat:@"%ld %@", (long)MMRemovalRecoverStaged(), YN(Exists(env))]);
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    NSInteger n = MMRemovalRecoverStaged();
    T(@"crash: recovery puts every staged item back at its old path and deletes nothing", @"1 KEEP=1 x no", [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, Read(env),
      Read([mods stringByAppendingPathComponent:@"pkg/index.js"]), YN(Exists(folder))]);
    parent = [MMUndo.shared record:parent.rid];
    T(@"crash: the Wrap Up's record says what happened, and no part says deleted", @"failed MinMacs stopped before this Wrap Up ended. What it had moved out of the worktree was put back no no restored restored",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", parent.state == MMUndoFailed ? @"failed" : @"other", parent.error, YN([MMUndo.shared record:a.rid].deletedNow), YN([MMUndo.shared record:b.rid].deletedNow),
       [MMUndo.shared record:a.rid].state == MMUndoRestored ? @"restored" : @"other", [MMUndo.shared record:b.rid].state == MMUndoRestored ? @"restored" : @"other"]);
    T(@"crash: a second recovery finds nothing left", @"0", @(MMRemovalRecoverStaged()).stringValue);

    // 2. Stopped inside a part, right after its rename: that part's record is still pending.
    MMUndoRecord *mid = Begin(@"wrapup", @"crashed mid-part");
    [MMUndo.shared note:mid payload:@{@"path": tree}];
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *part = Part(mid.rid, @"config mid");
    MMRemovalNote(part, del, nil); MMRemovalAsk(part, @[env]);
    MMRemovalApply(env, del, part, nil);
    T(@"crash mid-part: recovery puts the file back though the part never finished", @"1 KEEP=1 no", [NSString stringWithFormat:@"%ld %@ %@", (long)MMRemovalRecoverStaged(), Read(env),
      YN([MMUndo.shared record:part.rid].deletedNow)]);

    // 3. Stopped after every part went through, while the deletes ran: the worktree is gone, so they are finished.
    MMUndoRecord *late = Begin(@"wrapup", @"crashed while finishing");
    [MMUndo.shared note:late payload:@{@"path": tree}];
    MMUndoRecord *c = StageOne(late, @"config late", env);
    [MMUndo.shared note:late payload:@{@"finishing": @YES}];
    n = MMRemovalRecoverStaged();
    late = [MMUndo.shared record:late.rid];
    T(@"crash while finishing: the delete is finished, not undone into a worktree that is gone", @"1 no done yes no", [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)n, YN(Exists(env)),
      late.state == MMUndoDone ? @"done" : @"other", YN([MMUndo.shared record:c.rid].deletedNow), YN(Exists(c.payload[@"stagedIn"]))]);
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}

// Links, a put-back that stopped halfway, whose Wrap Up it is, the Trash after a crash, and what was left staged.
#import "stranded.m"
