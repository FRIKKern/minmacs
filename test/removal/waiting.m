// Included by damaged.m. Issue #67: what a done Wrap Up left staged is deleted, not put back into a worktree that is
// gone; what still cannot be settled is listed, and the person can delete it or put it back. Every file is a fixture
// under <dir>, inside $MINMACS_HOME.

/// The Wrap Up went through: the record says the deletes began and is done, as MMRunWrapUp leaves it.
static MMUndoRecord *DoneWrapUp(MMUndoRecord *parent) {
    [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
    return [MMUndo.shared record:parent.rid];
}
static MMRemovalWaitingItem *WaitingAt(NSString *stagedAt) {
    for (MMRemovalWaitingItem *i in MMRemovalWaiting()) if ([i.stagedAt isEqualToString:stagedAt]) return i;
    return nil;
}
static NSString *WhyName(MMRemovalWaitingItem *i) {
    return i ? @[@"delete-failed", @"old-path-taken", @"put-back-failed", @"damaged"][i.why] : @"not listed";
}
static NSString *StagedTo(MMUndoRecord *part) { return MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"to"); }

static void Leftovers(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"leftovers/wt"), *mods = [tree stringByAppendingPathComponent:@"node_modules"], *plain = [tree stringByAppendingPathComponent:@".env"];

    // 1. The issue's case: a done Wrap Up whose delete of a staged folder failed partway, since a folder inside it
    // cannot be written to. git took the worktree.
    Write([mods stringByAppendingPathComponent:@"a.js"], @"A=1");
    Write([mods stringByAppendingPathComponent:@"ro/b.js"], @"B=1");
    MMUndoRecord *parent = Unfinished(@"done, delete failed", tree, nil);
    MMUndoRecord *part = StageMany(parent, @"node_modules, delete failed", @[mods], YES);
    NSString *to = StagedTo(part), *ro = [to stringByAppendingPathComponent:@"ro"];
    chmod(ro.fileSystemRepresentation, 0500);
    [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
    (void)MMRemovalFinishStaged(@[part]);
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
    [fm removeItemAtPath:[to stringByAppendingPathComponent:@"a.js"] error:nil];
    [fm removeItemAtPath:tree error:nil];
    part = [MMUndo.shared record:part.rid];
    T(@"finish: a folder whose delete failed partway stays staged, and its entry says why", @"B=1 yes no",
      [NSString stringWithFormat:@"%@ %@ %@", Read([ro stringByAppendingPathComponent:@"b.js"]), YN(MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"why").length > 0), YN(part.deletedNow)]);
    NSInteger n = MMRemovalSweepStaged(NULL);
    part = [MMUndo.shared record:part.rid];
    T(@"sweep: a half-deleted folder of a done Wrap Up is not put back, and its worktree is not made again", @"0 no B=1 yes",
      [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, YN(Exists(tree)), Read([ro stringByAppendingPathComponent:@"b.js"]), YN(MMRecordFlag(part.payload, @"sweepTried"))]);
    MMRemovalWaitingItem *item = WaitingAt(to);
    T(@"sweep: one that still cannot be deleted is listed", [NSString stringWithFormat:@"delete-failed node_modules %@ yes yes yes yes %@:%@", mods, part.rid, to.lastPathComponent],
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@", WhyName(item), item.name, item.oldPath, YN(item.bytes > 0), YN(item.canDelete), YN(item.canPutBack), YN(item.detail.length > 0), item.itemID]);
    T(@"waiting: its words and its JSON", @"could not be deleted delete-failed node_modules", [NSString stringWithFormat:@"%@ %@ %@", item.whyWords, item.json[@"why"], item.json[@"name"]]);
    chmod(ro.fileSystemRepresentation, 0700);
    T(@"sweep: the delete is tried once more, not at every start", @"0 yes", [NSString stringWithFormat:@"%ld %@", (long)MMRemovalSweepStaged(NULL), YN(Exists(to))]);
    int64_t freed = -1;
    NSString *said = MMRemovalDeleteWaiting(item.itemID, &freed);
    T(@"waiting: the person deletes it now, and it is no longer listed, and its worktree is not made again", @"nil no not listed yes no yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", Or(said), YN(Exists(to)), WhyName(WaitingAt(to)), YN([MMUndo.shared record:part.rid].deletedNow), YN(Exists(tree)), YN(freed >= 0)]);

    // 2. The delete after the last part failed once, and can go now: the sweep deletes it.
    Write([mods stringByAppendingPathComponent:@"a.js"], @"A=1");
    parent = Unfinished(@"done, deleted at the sweep", tree, nil);
    part = StageMany(parent, @"node_modules, deleted at the sweep", @[mods], YES);
    to = StagedTo(part);
    parent = DoneWrapUp(parent);
    [fm removeItemAtPath:tree error:nil];
    n = MMRemovalSweepStaged(NULL);
    T(@"sweep: a staged item of a done Wrap Up is deleted, not put back", @"1 no no yes not listed",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)n, YN(Exists(to)), YN(Exists(tree)), YN([MMUndo.shared record:part.rid].deletedNow), WhyName(WaitingAt(to))]);

    // 3. The identity check: another file in the staging folder of a done Wrap Up is never deleted.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"done, swapped", tree, nil);
    part = StageMany(parent, @"config, swapped", @[plain], YES);
    to = StagedTo(part);
    [fm removeItemAtPath:to error:nil];
    Write(to, @"NOT THE ITEM");
    parent = DoneWrapUp(parent);
    n = MMRemovalSweepStaged(NULL);
    T(@"sweep: a swapped item in the staging folder of a done Wrap Up is never deleted, nor put back", @"0 NOT THE ITEM no",
      [NSString stringWithFormat:@"%ld %@ %@", (long)n, Read(to), YN(Exists(plain))]);
    item = WaitingAt(to);
    said = MMRemovalDeleteWaiting(item.itemID, NULL);
    T(@"waiting: it is listed as not deleted, says it is not the file, and the person's delete is refused too", @"delete-failed it is not the file that was staged yes NOT THE ITEM",
      [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(item), item.detail, YN([said containsString:@"it is not the file that was staged"]), Read(to)]);
    [fm removeItemAtPath:to error:nil];

    // 4. C3. The volume's UUID cannot be read at check time: refused, and the words say so, not "another file".
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"uuid unread", tree, nil);
    part = StageMany(parent, @"config, uuid unread", @[plain], YES);
    to = StagedTo(part);
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    NSString *back = MMRemovalPutBack(@[part]);
    [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
    (void)MMRemovalFinishStaged(@[part]);
    NSString *entryWhy = MMRecordString(MMRecordList([MMUndo.shared record:part.rid].payload, @"staged").firstObject, @"why");
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    T(@"identity: a UUID that cannot be read now is refused in words that say so, and the file is neither moved nor deleted", @"yes no yes PLAIN=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", YN([back containsString:@"its volume's UUID cannot be read now"]), YN([back containsString:@"another file"]),
       YN([entryWhy containsString:@"its volume's UUID cannot be read now"]), Read(to), YN(Exists(plain))]);
    [MMUndo.shared note:parent payload:@{@"finishing": @NO}];
    T(@"identity: once it can be read again, the file goes back", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(plain)]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    // A volume with no UUID at move time: the entry has none, and the file is known by its inode alone at that path.
    parent = Unfinished(@"no uuid", tree, nil);
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    part = StageMany(parent, @"config, no uuid", @[plain], YES);
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    NSDictionary *entry = MMRecordList(part.payload, @"staged").firstObject;
    T(@"identity: on a volume with no UUID the entry holds the inode, and the file still goes back", @"no yes nil PLAIN=1",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(entry[@"vol"] != nil), YN(MMRecordNumber(entry, @"ino") != nil), Or(MMRemovalPutBack(@[part])), Read(plain)]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // 5. A failed Wrap Up whose old path is taken: listed, and put back where the person says, never over anything.
    parent = Unfinished(@"failed, old path taken", tree, nil);
    part = StageMany(parent, @"config, old path taken", @[plain], YES);
    to = StagedTo(part);
    NSString *folder = MMRecordString(part.payload, @"stagedIn");
    Write(plain, @"NEWER=1");
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    n = MMRemovalSweepStaged(NULL);
    item = WaitingAt(to);
    T(@"waiting: an item whose old path is taken is listed after the sweep", [NSString stringWithFormat:@"0 old-path-taken .env %@ yes yes its old place is taken", plain],
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@ %@", (long)n, WhyName(item), item.name, item.oldPath, YN(item.canDelete), YN(item.canPutBack), item.whyWords]);
    NSString *aside = Path(@"leftovers/aside.env");
    NSArray *refusals = @[Or(MMRemovalPutBackWaiting(item.itemID, nil)), Or(MMRemovalPutBackWaiting(item.itemID, @"aside.env")),
                          Or(MMRemovalPutBackWaiting(item.itemID, Path(@"leftovers/no/such/folder/.env"))), Or(MMRemovalPutBackWaiting(item.itemID, [Path(@"leftovers") stringByAppendingString:@"/../leftovers/x.env"]))];
    T(@"waiting: put back is refused over something, for a path that is not full or real, and into a folder that does not exist", @"yes yes yes yes PLAIN=1 NEWER=1",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN([refusals[0] containsString:@"something already exists at"]), YN([refusals[1] isEqualToString:@"give a full path"]),
       YN([refusals[2] containsString:@"does not exist"]), YN([refusals[3] isEqualToString:@"its path is not a real path"]), Read(to), Read(plain)]);
    T(@"waiting: the person puts it back to a path of their own, and it is no longer listed, and the staging folder goes", @"nil PLAIN=1 NEWER=1 no not listed no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", Or(MMRemovalPutBackWaiting(item.itemID, aside)), Read(aside), Read(plain), YN(Exists(to)), WhyName(WaitingAt(to)), YN(Exists(folder))]);
    T(@"waiting: an id that names nothing is refused", @"nothing waits under that id|nothing waits under that id",
      [NSString stringWithFormat:@"%@|%@", Or(MMRemovalDeleteWaiting(item.itemID, NULL)), Or(MMRemovalPutBackWaiting(@"nope:0.x", nil))]);
    Write(plain, @"PLAIN=1");

    // 6. A record that cannot be read: its item is listed as damaged, with no old path, and is never deleted.
    NSString *other = [tree stringByAppendingPathComponent:@".env.local"];
    Write(other, @"OTHER=1");
    parent = Unfinished(@"damaged, ended", tree, nil);
    part = StageMany(parent, @"config, staged list damaged", @[other], YES);
    to = StagedTo(part);
    [MMUndo.shared note:part payload:@{@"staged": @"no list"}];
    parent = DoneWrapUp(parent);
    (void)MMRemovalSweepStaged(NULL);
    item = WaitingAt(to);
    said = MMRemovalDeleteWaiting(item.itemID, NULL);
    T(@"waiting: an item of a record whose staged list cannot be read is listed as damaged, with no old path, and the person's delete is refused", @"damaged nil no no yes OTHER=1",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", WhyName(item), Or(item.oldPath), YN(item.canDelete), YN(item.canPutBack), YN([said containsString:@"damaged"] || [said containsString:@"does not say"]), Read(to)]);
    T(@"waiting: a part whose parent is no text is listed as damaged too", @"damaged", WhyName(WaitingAt(StagedTo(OddParent(tree)))));

    // C6. The sweep's check of a damaged Wrap Up: its record says the deletes began, but it cannot be read, so its
    // staged item goes back and is never deleted.
    parent = Unfinished(@"done, but damaged", tree, nil);
    part = StageMany(parent, @"config of a damaged done one", @[plain], YES);
    to = StagedTo(part);
    parent = DoneWrapUp(parent);
    [MMUndo.shared note:parent payload:@{@"bundle": @"no dictionary"}];
    n = MMRemovalSweepStaged(NULL);
    T(@"sweep: a done Wrap Up whose record cannot be read never has its staged item deleted: it goes back", @"1 PLAIN=1 no restored no",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)n, Read(plain), YN(Exists(to)), StateWord(part), YN([MMUndo.shared record:part.rid].deletedNow)]);
    // The same for a damaged part of a Wrap Up that reads: put back, never deleted.
    parent = Unfinished(@"done, part damaged", tree, nil);
    part = StageMany(parent, @"config, recovery damaged", @[plain], YES);
    to = StagedTo(part);
    [MMUndo.shared note:part payload:@{@"recovery": @"no dictionary"}];
    parent = DoneWrapUp(parent);
    n = MMRemovalSweepStaged(NULL);
    T(@"sweep: a damaged part of a done Wrap Up never has its staged item deleted: it goes back", @"1 PLAIN=1 no restored",
      [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, Read(plain), YN(Exists(to)), StateWord(part)]);
}

/// The review of #69: guards that must bite, an Undo that could not finish, a folder that is no staging folder, and
/// the two item functions on their own.
static void Guards(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"guards/wt"), *plain = [tree stringByAppendingPathComponent:@".env"], *aside = Path(@"guards/aside.env");
    Write(plain, @"PLAIN=1");

    // G1. A failed Wrap Up is put back, even when its record says the deletes began.
    MMUndoRecord *parent = Unfinished(@"failed, finishing", tree, nil);
    MMUndoRecord *part = StageMany(parent, @"config, failed but finishing", @[plain], YES);
    NSString *to = StagedTo(part);
    [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    NSInteger n = MMRemovalSweepStaged(NULL);
    T(@"sweep: a staged item of a failed Wrap Up is put back, not deleted, though its record says the deletes began", @"1 PLAIN=1 no restored no",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)n, Read(plain), YN(Exists(to)), StateWord(part), YN([MMUndo.shared record:part.rid].deletedNow)]);

    // G11. The person's delete of an item whose record is damaged, though its lists read: refused, and it stays.
    parent = Unfinished(@"failed, part damaged, old path taken", tree, nil);
    part = StageMany(parent, @"config, recovery damaged, old path taken", @[plain], YES);
    to = StagedTo(part);
    [MMUndo.shared note:part payload:@{@"recovery": @"no dictionary"}];
    Write(plain, @"NEWER=1");
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    (void)MMRemovalSweepStaged(NULL);
    MMRemovalWaitingItem *item = WaitingAt(to);
    NSString *said = MMRemovalDeleteWaiting(item.itemID, NULL), *direct = MMRemovalDeleteStagedItem(part, to, NULL);
    T(@"waiting: the person's delete of an item whose record is damaged is refused, and it stays", @"damaged no yes yes yes PLAIN=1",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", WhyName(item), YN(item.canDelete), YN(item.canPutBack), YN([said containsString:@"damaged"]), YN([direct containsString:@"damaged"]), Read(to)]);
    T(@"waiting: it can still be put back to a path of the person's own", @"nil PLAIN=1 no", [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBackWaiting(item.itemID, aside)), Read(aside), YN(Exists(to))]);
    [fm removeItemAtPath:aside error:nil];
    Write(plain, @"PLAIN=1");

    // G12, F6. A Wrap Up that still runs: its item is not listed, and neither item function acts on it.
    parent = Unfinished(@"still running", tree, MMRemovalOwner());
    part = StageMany(parent, @"config of a running one", @[plain], YES);
    to = StagedTo(part);
    NSString *del = MMRemovalDeleteStagedItem(part, to, NULL), *mv = MMRemovalPutBackStagedItem(part, to, aside);
    T(@"waiting: an item of a Wrap Up that still runs is not listed, and delete and put-back are refused", @"not listed yes yes PLAIN=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", WhyName(WaitingAt(to)), YN([del isEqualToString:@"its Wrap Up still runs"]), YN([mv isEqualToString:@"its Wrap Up still runs"]), Read(to), YN(Exists(aside))]);
    // With a damaged part it is listed, so a person sees it, but only to be moved by hand while the Wrap Up runs.
    [MMUndo.shared note:part payload:@{@"recovery": @"no dictionary"}];
    item = WaitingAt(to);
    T(@"waiting: a damaged part of a Wrap Up that still runs is listed, and can be neither deleted nor put back", @"damaged no no its Wrap Up still runs",
      [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(item), YN(item.canDelete), YN(item.canPutBack), Or(MMRemovalPutBackWaiting(item.itemID, aside))]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    (void)MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);

    // G22. A part that never ended is not deleted by the person, even in a Wrap Up that ended.
    parent = Unfinished(@"part never ended", tree, nil);
    part = StageMany(parent, @"config, part pending", @[plain], NO);
    to = StagedTo([MMUndo.shared record:part.rid]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    T(@"waiting: an item of a part that never ended is not deleted", @"its part has not ended PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalDeleteStagedItem(part, to, NULL)), Read(to)]);
    T(@"waiting: an item of a part that never ended is not put back by the person either", @"its part has not ended PLAIN=1 no",
      [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBackStagedItem(part, to, aside)), Read(to), YN(Exists(aside))]);
    [MMUndo.shared finish:part ok:NO freed:0 error:@"test"];
    (void)MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);

    // G13. An entry that does not lie in its Wrap Up's staging folder is never moved, and never listed.
    NSString *doc = Path(@"guards/Documents/thesis.txt");
    Write(doc, @"MY THESIS");
    parent = Unfinished(@"forged entry", tree, nil);
    part = StageMany(parent, @"config, forged", @[plain], YES);
    to = StagedTo(part);
    NSMutableDictionary *forged = [MMFileIdentity(doc) mutableCopy];
    forged[@"from"] = [tree stringByAppendingPathComponent:@"thesis.txt"]; forged[@"to"] = doc;
    [MMUndo.shared note:part payload:@{@"staged": @[forged, MMRecordList(part.payload, @"staged").firstObject]}];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    part = [MMUndo.shared record:part.rid];
    T(@"waiting: put-back refuses an entry that does not lie in this Wrap Up's staging folder, and does not list it", @"yes MY THESIS no not listed",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN([MMRemovalPutBackStagedItem(part, doc, aside) isEqualToString:@"it does not lie directly in the staging folder"]), Read(doc), YN(Exists(aside)), WhyName(WaitingAt(doc))]);
    (void)MMRemovalPutBackStagedItem(part, to, plain);
    // The forged entry is taken out again, so no later sweep finds it.
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[]}];

    // A staging folder whose marker names another Wrap Up is not this one's: nothing of it is moved or listed.
    parent = Unfinished(@"marker of another", tree, nil);
    part = StageMany(parent, @"config, marker changed", @[plain], YES);
    to = StagedTo(part);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    NSString *marker = [to.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".minmacs"];
    Write(marker, @"another Wrap Up");
    T(@"waiting: put-back refuses a staging folder whose marker names another Wrap Up, and does not list it", @"yes PLAIN=1 no not listed",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN([MMRemovalPutBackStagedItem(part, to, aside) isEqualToString:@"its folder was not made by MinMacs for this Wrap Up"]), Read(to), YN(Exists(aside)), WhyName(WaitingAt(to))]);
    Write(marker, parent.rid);
    (void)MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);

    // F4. A damaged record whose stagedIn is no staging folder: nothing of that folder is listed.
    parent = Unfinished(@"stagedIn elsewhere", tree, nil);
    part = StageMany(parent, @"config, stagedIn forged", @[plain], YES);
    to = StagedTo(part);
    [MMUndo.shared note:part payload:@{@"staged": @"no list", @"stagedIn": doc.stringByDeletingLastPathComponent}];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    NSUInteger fromDocs = 0;
    for (MMRemovalWaitingItem *i in MMRemovalWaiting()) if ([i.stagedAt hasPrefix:doc.stringByDeletingLastPathComponent]) fromDocs++;
    T(@"waiting: a damaged record whose stagedIn is no staging folder lists nothing from it", @"0 MY THESIS", [NSString stringWithFormat:@"%lu %@", (unsigned long)fromDocs, Read(doc)]);
    [fm moveItemAtPath:to toPath:plain error:nil];
    // And one whose staged list reads but whose trashed list does not: an entry that names a file outside its staging
    // folder is not listed either.
    parent = Unfinished(@"trashed damaged, forged entry", tree, nil);
    part = StageMany(parent, @"config, trashed damaged, forged", @[plain], YES);
    to = StagedTo(part);
    forged = [MMFileIdentity(doc) mutableCopy];
    forged[@"from"] = [tree stringByAppendingPathComponent:@"thesis.txt"]; forged[@"to"] = doc;
    [MMUndo.shared note:part payload:@{@"staged": @[forged, MMRecordList(part.payload, @"staged").firstObject], @"trashed": @"no list"}];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    T(@"waiting: a damaged record lists what waits in its staging folder, and not a file elsewhere that it names", @"damaged not listed MY THESIS",
      [NSString stringWithFormat:@"%@ %@ %@", WhyName(WaitingAt(to)), WhyName(WaitingAt(doc)), Read(doc)]);
    [fm moveItemAtPath:to toPath:plain error:nil];

    // F3. The person asked for an Undo of a done Wrap Up and it could not finish: from then on its leftover is only
    // put back or listed, never deleted by the sweep.
    NSString *mods = [tree stringByAppendingPathComponent:@"node_modules"];
    Write([mods stringByAppendingPathComponent:@"a.js"], @"A=1");
    parent = Unfinished(@"done, then an Undo", tree, nil);
    part = StageMany(parent, @"node_modules, Undo refused", @[mods], YES);
    to = StagedTo(part);
    parent = DoneWrapUp(parent);
    Write(mods, @"SOMETHING ELSE");
    NSString *undo = [MMUndo.shared restore:parent.rid];
    n = MMRemovalSweepStaged(NULL);
    item = WaitingAt(to);
    T(@"sweep: after an Undo that could not finish, a leftover is not deleted", @"yes 0 A=1 old-path-taken SOMETHING ELSE",
      [NSString stringWithFormat:@"%@ %ld %@ %@ %@", YN(undo != nil), (long)n, Read([to stringByAppendingPathComponent:@"a.js"]), WhyName(item), Read(mods)]);
    [fm removeItemAtPath:mods error:nil];
    T(@"sweep: once its old path is free, the next sweep puts it back", @"1 A=1", [NSString stringWithFormat:@"%ld %@", (long)MMRemovalSweepStaged(NULL), Read([mods stringByAppendingPathComponent:@"a.js"])]);

    // R2. An Undo that stopped at a later part never reached the earlier one: only the Wrap Up's own undoAsked keeps
    // the earlier part's leftover from being deleted.
    NSString *early = Path(@"guards/wt2/early.env"), *late = Path(@"guards/wt2/late.env");
    Write(early, @"EARLY=1"); Write(late, @"LATE=1");
    parent = Unfinished(@"done, Undo stopped at a later part", Path(@"guards/wt2"), nil);
    MMUndoRecord *first = StageMany(parent, @"config, part 0", @[early], YES), *second = StageMany(parent, @"config, part 1", @[late], YES);
    [MMUndo.shared note:[MMUndo.shared record:first.rid] payload:@{@"part": @0}];
    [MMUndo.shared note:[MMUndo.shared record:second.rid] payload:@{@"part": @1}];
    parent = DoneWrapUp(parent);
    Write(late, @"SOMETHING ELSE");
    undo = [MMUndo.shared restore:parent.rid];
    // Read before the sweep: its own put-back is a restore of the part, which notes undoAsked on it too.
    BOOL firstAsked = MMRecordFlag([MMUndo.shared record:first.rid].payload, @"undoAsked");
    (void)MMRemovalSweepStaged(NULL);
    T(@"sweep: after an Undo that stopped at another part, a leftover is not deleted", @"yes no yes EARLY=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", YN(undo != nil), YN(firstAsked),
       YN(MMRecordFlag([MMUndo.shared record:parent.rid].payload, @"undoAsked")), Read(early), YN([MMUndo.shared record:first.rid].deletedNow)]);
    [fm removeItemAtPath:late error:nil];
    (void)MMRemovalSweepStaged(NULL);

    // R2. A damaged Wrap Up whose Trash item could not go back stays pending, and once its old path is free it goes
    // back and the Wrap Up fails, its words saying what went back and that nothing was deleted.
    NSString *kept = Path(@"guards/wt3/.env.local");
    Write(kept, @"KEPT=1");
    parent = Unfinished(@"damaged, Trash item blocked", Path(@"guards/wt3"), GoneOwner());
    part = TrashOne(parent, @"config to the Trash, damaged", kept);
    NSString *inTrash = MMRecordString(MMRecordList(part.payload, @"trashed").firstObject, @"to");
    [MMUndo.shared note:part payload:@{@"recovery": @"no dictionary"}];
    Write(kept, @"NEWER=1");
    (void)MMRemovalRecoverStaged();
    T(@"damaged: a Wrap Up whose Trash item could not go back stays pending", @"pending KEPT=1 NEWER=1",
      [NSString stringWithFormat:@"%@ %@ %@", StateWord(parent), Read(inTrash), Read(kept)]);
    [fm removeItemAtPath:kept error:nil];
    (void)MMRemovalRecoverStaged();
    NSString *words = [MMUndo.shared record:parent.rid].error ?: @"";
    T(@"damaged: once it went back, the Wrap Up fails and its words say what went back", @"failed KEPT=1 yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", StateWord(parent), Read(kept), YN([words containsString:@"1 item it had moved out of the worktree went back"]), YN([words containsString:@"Nothing was deleted"])]);

    // R1. A Wrap Up whose state cannot be read may have ended and had its worktree taken: nothing of it is pulled
    // back from the Trash or the staging folder, nothing is deleted, it stays pending, and what it staged is listed.
    NSString *trashed = Path(@"guards/wt4/.env"), *staged = Path(@"guards/wt4/.env.local");
    Write(trashed, @"TRASHED=1"); Write(staged, @"STAGED=1");
    parent = Unfinished(@"state cannot be read", Path(@"guards/wt4"), GoneOwner());
    MMUndoRecord *toTrash = TrashOne(parent, @"config to the Trash, state unread", trashed);
    part = StageMany(parent, @"config staged, state unread", @[staged], YES);
    to = StagedTo(part); inTrash = MMRecordString(MMRecordList(toTrash.payload, @"trashed").firstObject, @"to");
    parent = DoneWrapUp(parent);
    RewriteBody(parent, @"state", @[@"done"]);
    n = MMRemovalRecoverStaged() + MMRemovalSweepStaged(NULL);
    item = WaitingAt(to);
    T(@"damaged: a Wrap Up whose state cannot be read is not pulled back or failed, and what it staged is listed", @"0 TRASHED=1 no STAGED=1 no pending damaged no no yes",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@ %@ %@ %@ %@", (long)n, Read(inTrash), YN(Exists(trashed)), Read(to), YN(Exists(staged)), StateWord(parent), WhyName(item), YN(item.canDelete), YN(item.canPutBack),
       YN([MMRemovalDamagedRecords() containsObject:parent.rid])]);
}

/// For the CLI checks of removal.sh: leaves one item a done Wrap Up could not delete, one whose old path is taken and
/// one whose record is damaged, in MINMACS_HOME, and prints the first two ids, the second one's old path, then the third id.
static int LeaveWaiting(NSString *dir) {
    gDir = dir;
    NSString *tree = Path(@"cli/wt"), *mods = [tree stringByAppendingPathComponent:@"node_modules"], *plain = [tree stringByAppendingPathComponent:@".env"];
    Write([mods stringByAppendingPathComponent:@"a.js"], @"A=1");
    Write(plain, @"PLAIN=1");
    MMUndoRecord *parent = Unfinished(@"cli, done", tree, nil);
    MMUndoRecord *part = StageMany(parent, @"cli node_modules", @[mods], YES);
    DoneWrapUp(parent);
    MMUndoRecord *other = Unfinished(@"cli, failed", tree, nil);
    MMUndoRecord *part2 = StageMany(other, @"cli config", @[plain], YES);
    Write(plain, @"NEWER=1");
    [MMUndo.shared finish:other ok:NO freed:0 error:@"test"];
    // A third: its part's record is damaged, though its lists read, and its old path is taken.
    NSString *local = [tree stringByAppendingPathComponent:@".env.local"];
    Write(local, @"LOCAL=1");
    MMUndoRecord *third = Unfinished(@"cli, damaged", tree, nil);
    MMUndoRecord *part3 = StageMany(third, @"cli damaged config", @[local], YES);
    [MMUndo.shared note:part3 payload:@{@"recovery": @"no dictionary"}];
    Write(local, @"NEWER=1");
    [MMUndo.shared finish:third ok:NO freed:0 error:@"test"];
    printf("%s:%s\n%s:%s\n%s\n%s:%s\n", part.rid.UTF8String, StagedTo(part).lastPathComponent.UTF8String, part2.rid.UTF8String, StagedTo(part2).lastPathComponent.UTF8String, plain.UTF8String,
           part3.rid.UTF8String, StagedTo(part3).lastPathComponent.UTF8String);
    return 0;
}
