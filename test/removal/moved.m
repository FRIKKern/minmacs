// Included by stopped.m. Issue #79: a volume may give a file another id where it lies after the rename into the
// staging folder, as msdosfs does for an empty file. The staging folder's list is written before the rename, with the
// id read at the old place, and is what a put-back and a delete believe. So after the rename the list is written
// again, with the id read at the new place, and only for the very file MinMacs held open across the rename.
// MINMACS_TEST_ID_MOVES_ON_RENAME has the first write hold another id, as such a volume would.
// Every file is a fixture under <dir>, inside $MINMACS_HOME.

static unsigned long long InodeAt(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 ? (unsigned long long)st.st_ino : 0;
}
/// The inode the staging folder's own list holds for the item that waits at stagedAt.
static unsigned long long ListedInode(NSString *stagedAt) {
    NSDictionary *e = MMRecordDict(ListOfFolder(stagedAt.stringByDeletingLastPathComponent), stagedAt.lastPathComponent);
    return MMRecordNumber(e, @"ino").unsignedLongLongValue;
}
/// A part of a new Wrap Up of tree stages path on a volume that gives it another id at the new place.
static MMUndoRecord *StageMoved(NSString *subject, NSString *tree, NSString *path, MMUndoRecord **wrapUp) {
    setenv("MINMACS_TEST_ID_MOVES_ON_RENAME", "1", 1);
    *wrapUp = Unfinished(subject, tree, nil);
    MMUndoRecord *part = StageMany(*wrapUp, [subject stringByAppendingString:@", part"], @[path], YES);
    unsetenv("MINMACS_TEST_ID_MOVES_ON_RENAME");
    return part;
}

static void Moved(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"moved/wt"), *env = [tree stringByAppendingPathComponent:@".env.local"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    MMUndoRecord *wrapUp = nil;

    // 1. The list holds the id read at the new place, and the Wrap Up's own put-back brings the item back.
    Write(env, @"KEEP=1");
    MMUndoRecord *part = StageMoved(@"moved, put back", tree, env, &wrapUp);
    NSString *stagedAt = StagedTo(part), *folder = part.payload[@"stagedIn"];
    T(@"moved: after the rename the staging folder's list holds the id the file has at its new place", @"no yes",
      [NSString stringWithFormat:@"%@ %@", YN(Exists(env)), YN(InodeAt(stagedAt) != 0 && ListedInode(stagedAt) == InodeAt(stagedAt))]);
    T(@"moved: a put-back brings it back to its old path, and its folder goes", @"nil KEEP=1 no",
      [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[part])), Read(env), YN(Exists(folder))]);
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];

    // 2. It waits with its old path taken: --waiting offers both ways out, and the person's put-back works.
    part = StageMoved(@"moved, the person puts it back", tree, env, &wrapUp);
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
    Write(env, @"NEWER=1");
    MMRemovalWaitingItem *item = WaitingOfPart(part.rid);
    T(@"moved: removal --waiting lists it with its old path, and offers both ways out",
      [NSString stringWithFormat:@"old-path-taken %@ yes yes was at %@.", env, env],
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", WhyName(item), item.oldPath, YN(item.canPutBack), YN(item.canDelete), item.wasWords]);
    [fm removeItemAtPath:env error:nil];
    T(@"moved: the person's put-back brings it back", @"nil KEEP=1 no",
      [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBackWaiting(item.itemID, nil)), Read(env), YN(Exists(folder))]);

    // 3. The person's delete takes it, and only it.
    part = StageMoved(@"moved, the person deletes it", tree, env, &wrapUp);
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
    Write(env, @"NEWER=1");
    item = WaitingOfPart(part.rid);
    T(@"moved: the person's delete takes it, and the file at its old path stays", @"nil no NEWER=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalDeleteWaiting(item.itemID, NULL)), YN(Exists(stagedAt)), Read(env), YN(Exists(folder))]);
    [fm removeItemAtPath:env error:nil];

    // 4. MinMacs stops between the rename and the second write. The list still holds the id from the old place, so
    // MinMacs cannot tell that the file is the one it staged: it is kept and listed, and never moved or deleted.
    Write(env, @"KEEP=1");
    setenv("MINMACS_TEST_ID_MOVES_ON_RENAME", "1", 1);
    NSArray<NSString *> *said = StopAfterRename(tree, env);
    unsetenv("MINMACS_TEST_ID_MOVES_ON_RENAME");
    NSArray<NSString *> *rids = [said.firstObject componentsSeparatedByString:@" "];
    NSString *wrap = rids.firstObject, *partRid = rids.count > 1 ? rids[1] : @"";
    folder = StagedFolderOf(wrap);
    stagedAt = [folder stringByAppendingPathComponent:ListedName(folder)];
    T(@"moved, stopped before the second write: the item is in the folder, and its list holds the id from the old place", @"1 no KEEP=1 no",
      [NSString stringWithFormat:@"%lu %@ %@ %@", (unsigned long)said.count, YN(Exists(env)), Read(stagedAt), YN(ListedInode(stagedAt) == InodeAt(stagedAt))]);
    (void)MMRemovalRecoverStaged();
    (void)MMRemovalSweepStaged(NULL);
    item = WaitingOfPart(partRid);
    T(@"moved, stopped before the second write: recovery and the sweep move nothing, and it is listed with no way out", @"KEEP=1 no no no it is not the file that was staged",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Read(stagedAt), YN(Exists(env)), YN(item.canPutBack), YN(item.canDelete), Or(item.detail)]);
    T(@"moved, stopped before the second write: a delete and a put-back of it are refused, and it stays", @"yes yes KEEP=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(MMRemovalDeleteWaiting(item.itemID, NULL) != nil), YN(MMRemovalPutBackWaiting(item.itemID, env) != nil), Read(stagedAt), YN(Exists(env))]);
    // The list's old path is of the file the list names, and MinMacs cannot tell that this is that file.
    T(@"moved, stopped before the second write: the listing does not give the list's old path as this file's own", @"nil|.env.local|yes",
      [NSString stringWithFormat:@"%@|%@|%@", Or(item.oldPath), item.name, YN([item.listedOldPath isEqualToString:env] && [item.json[@"listedOldPath"] isEqual:env] && item.json[@"oldPath"] == NSNull.null)]);
    T(@"moved, stopped before the second write: its line says so in plain words",
      [NSString stringWithFormat:@"The list of its staging folder holds this name for another file, which was at %@. Where this one was, MinMacs cannot say.", env], item.wasWords);
    [fm removeItemAtPath:stagedAt error:nil];
    MMRemovalDropEmptyStagingFolder(folder, wrap);

    // 5. Another file takes the item's place right after the rename. The second write is only for the very file
    // MinMacs held open across the rename, so the list never comes to name the other file: it is never moved or deleted.
    NSString *other = Path(@"moved/other.txt");
    Write(env, @"KEEP=1"); Write(other, @"OTHER=1");
    setenv("MINMACS_TEST_SWAP_AFTER_RENAME", other.fileSystemRepresentation, 1);
    wrapUp = Unfinished(@"moved, swapped", tree, nil);
    part = StageMany(wrapUp, @"moved, swapped, part", @[env], YES);
    unsetenv("MINMACS_TEST_SWAP_AFTER_RENAME");
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    T(@"moved, swapped after the rename: the list does not take the other file's id", @"OTHER=1 no",
      [NSString stringWithFormat:@"%@ %@", Read(stagedAt), YN(ListedInode(stagedAt) == InodeAt(stagedAt))]);
    T(@"moved, swapped after the rename: a put-back moves nothing", @"yes OTHER=1 no",
      [NSString stringWithFormat:@"%@ %@ %@", YN([MMRemovalPutBack(@[part]) containsString:@"it is not the file that was staged"]), Read(stagedAt), YN(Exists(env))]);
    [MMUndo.shared finish:wrapUp ok:YES freed:0 error:nil];
    (void)MMRemovalFinishStaged(@[[MMUndo.shared record:part.rid]]);
    item = WaitingOfPart(part.rid);
    T(@"moved, swapped after the rename: the delete at the end of the Wrap Up and the person's delete both leave it", @"OTHER=1 no no yes OTHER=1",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Read(stagedAt), YN(item.canDelete), YN(item.canPutBack), YN(MMRemovalDeleteWaiting(item.itemID, NULL) != nil), Read(stagedAt)]);
    T(@"moved, swapped after the rename: the listing does not give the list's old path as the other file's own", @"nil yes",
      [NSString stringWithFormat:@"%@ %@", Or(item.oldPath), YN([item.listedOldPath isEqualToString:env])]);
    [fm removeItemAtPath:stagedAt error:nil];
    MMRemovalDropEmptyStagingFolder(folder, wrapUp.rid);
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}
