// Included by waiting.m. Issue #70: a record that was not written by MinMacs never makes it move or delete a file it
// did not stage. Put-back, in the sweep, in recovery and in an Undo, moves only from the staging folder MinMacs made
// for that Wrap Up, and an item whose Wrap Up has no record is listed and never acted on. Every file is a fixture
// under <dir>, inside $MINMACS_HOME: "Documents" here is a folder of the test's own.

/// A list entry that names file truly, by its inode and volume, and says it waits at to and was at from.
static NSDictionary *ForgedEntry(NSString *file, NSString *to, NSString *from) {
    NSMutableDictionary *e = [MMFileIdentity(file) mutableCopy] ?: [NSMutableDictionary new];
    e[@"to"] = to; e[@"from"] = from;
    return e;
}
/// A failed Wrap Up at tree with one part that truly staged plain, so its staging folder and marker are MinMacs's own.
static MMUndoRecord *FailedWithPart(NSString *subject, NSString *tree, NSString *plain, MMUndoRecord **parent) {
    Write(plain, @"PLAIN=1");
    *parent = Unfinished(subject, tree, nil);
    MMUndoRecord *part = StageMany(*parent, [subject stringByAppendingString:@", part"], @[plain], YES);
    [MMUndo.shared finish:*parent ok:NO freed:0 error:@"test"];
    return [MMUndo.shared record:part.rid];
}
/// Takes every entry out of the part's lists, so no later sweep finds the forged one again.
static void Forget(MMUndoRecord *part) { [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[], @"trashed": @[]}]; }

static void Forged(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"forged"), *tree = [base stringByAppendingPathComponent:@"wt"], *plain = [tree stringByAppendingPathComponent:@".env"];
    NSString *docs = [base stringByAppendingPathComponent:@"Documents"], *doc = [docs stringByAppendingPathComponent:@"thesis.txt"];
    NSString *free = [base stringByAppendingPathComponent:@"elsewhere/thesis.txt"];
    MMUndoRecord *parent = nil, *part = nil;
    // Each case starts with the person's file in its place and the forged old path free, so one failure is one failure.
    void (^fresh)(void) = ^{ Write(doc, @"MY THESIS"); [fm removeItemAtPath:free.stringByDeletingLastPathComponent error:nil]; };
    fresh();

    // 1. The issue's first case. The record names a file of the person's own with its true inode, and a free path to
    // move it to. The sweep puts back what a failed Wrap Up left staged: the true item goes, and the file stays.
    part = FailedWithPart(@"forged, the sweep", tree, plain, &parent);
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, doc, free), MMRecordList(part.payload, @"staged").firstObject]}];
    (void)MMRemovalSweepStaged(NULL);
    T(@"put back: a staged entry that does not lie in the Wrap Up's staging folder is not moved", @"MY THESIS no PLAIN=1",
      [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), Read(plain)]);
    Forget(part);
    fresh();

    // The same asked by the person, as an Undo of the part, and the words say why.
    part = FailedWithPart(@"forged, an Undo", tree, plain, &parent);
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, doc, free), MMRecordList(part.payload, @"staged").firstObject]}];
    NSString *said = [MMUndo.shared restore:part.rid];
    T(@"put back: an Undo does not move it either, says why, and the record is not called restored", @"MY THESIS no yes done",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(doc), YN(Exists(free)), YN([said containsString:@"stays where it is: it does not lie directly in the staging folder"]), StateWord(part)]);
    Forget(part);
    fresh();

    // A record with a damaged field has only its lists moved back, -[MMUndo moveBackOnly:]. The same check holds.
    part = FailedWithPart(@"forged, a damaged part", tree, plain, &parent);
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, doc, free), MMRecordList(part.payload, @"staged").firstObject], @"recovery": @"no dictionary"}];
    said = MMRemovalPutBack(@[part]);
    T(@"put back: nor does the put-back of a part with a damaged field", @"MY THESIS no yes", [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), YN(said != nil)]);
    Forget(part);
    fresh();

    // After a crash: recovery puts back what a Wrap Up that never ended had staged.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"forged, recovery", tree, GoneOwner());
    part = StageMany(parent, @"forged, recovery, part", @[plain], YES);
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, doc, free), MMRecordList(part.payload, @"staged").firstObject]}];
    (void)MMRemovalRecoverStaged();
    T(@"put back: nor does recovery after a crash, and the Wrap Up is still settled", @"MY THESIS no PLAIN=1 failed",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(doc), YN(Exists(free)), Read(plain), StateWord(parent)]);
    Forget(part);
    fresh();

    // 2. A path with ".." in it is no real path, wherever it leads.
    part = FailedWithPart(@"forged, dot dot", tree, plain, &parent);
    NSString *dotted = [NSString stringWithFormat:@"%@/../Documents/thesis.txt", docs];
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, dotted, free)]}];
    said = [MMUndo.shared restore:part.rid];
    T(@"put back: a staged entry whose path holds .. is not moved", @"MY THESIS no yes", [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), YN([said containsString:@"its path is not a real path"])]);
    fresh();
    // Nor to an old path spelled that way, though the item truly waits in the staging folder.
    NSString *to = [MMRecordString(part.payload, @"stagedIn") stringByAppendingPathComponent:@"0..env"];
    NSString *up = [NSString stringWithFormat:@"%@/../elsewhere/up.env", docs];
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(to, to, up)]}];
    said = [MMUndo.shared restore:part.rid];
    T(@"put back: nor to an old path that holds ..", @"PLAIN=1 no yes", [NSString stringWithFormat:@"%@ %@ %@", Read(to), YN(Exists([base stringByAppendingPathComponent:@"elsewhere/up.env"])), YN([said containsString:@"its old path is not a real path"])]);
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[ForgedEntry(to, to, plain)]}];
    T(@"put back: with its true old path it goes back", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or([MMUndo.shared restore:part.rid]), Read(plain)]);

    // 3. The staging path is a link. The record's folder has the right name beside the worktree, but it is a link to
    // the person's folder, where a marker with the rid was put too.
    NSString *linked = [base stringByAppendingPathComponent:@"linked"], *ltree = [linked stringByAppendingPathComponent:@"wt"];
    Write([ltree stringByAppendingPathComponent:@".env"], @"L=1");
    parent = Unfinished(@"forged, a link for a staging folder", ltree, nil);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    NSString *link = [linked stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:parent.rid]];
    Write([docs stringByAppendingPathComponent:@".minmacs"], parent.rid);
    symlink(docs.fileSystemRepresentation, link.fileSystemRepresentation);
    NSString *through = [link stringByAppendingPathComponent:@"thesis.txt"];
    part = Done(Part(parent.rid, @"forged, a link for a staging folder, part"));
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, through, free)], @"stagedIn": link}];
    said = [MMUndo.shared restore:part.rid];
    T(@"put back: a staging folder that is a link to another folder is not one, and nothing in it is moved", @"MY THESIS no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), YN([said containsString:@"it does not lie directly in the staging folder"])]);
    T(@"waiting: nor is it listed, deleted or put back by the person", @"not listed yes yes MY THESIS no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", WhyName(WaitingAt(through)), YN(MMRemovalDeleteStagedItem(part, through, NULL) != nil), YN(MMRemovalPutBackStagedItem(part, through, free) != nil), Read(doc), YN(Exists(free))]);
    Forget(part);
    fresh();
    [fm removeItemAtPath:link error:nil];
    [fm removeItemAtPath:[docs stringByAppendingPathComponent:@".minmacs"] error:nil];

    // 4. A folder with a staging folder's name and a true marker, but not where MinMacs would have made it: not in
    // MinMacs's own folder, and not beside the worktree of this Wrap Up.
    part = FailedWithPart(@"forged, a folder of that name elsewhere", tree, plain, &parent);
    NSString *fake = [docs stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:parent.rid]], *inside = [fake stringByAppendingPathComponent:@"0.notes.txt"];
    Write(inside, @"MY NOTES");
    Write([fake stringByAppendingPathComponent:@".minmacs"], parent.rid);
    NSString *real = MMRecordString(part.payload, @"stagedIn");
    MMUndoRecord *other = Done(Part(parent.rid, @"forged, a folder of that name elsewhere, second part"));
    [MMUndo.shared note:other payload:@{@"staged": @[ForgedEntry(inside, inside, free)], @"stagedIn": fake, @"removal": @{@"choice": @"delete", @"wants": @YES, @"staged": @YES, @"deleted": @NO}}];
    said = [MMUndo.shared restore:other.rid];
    T(@"put back: a folder named like a staging folder that is not beside the Wrap Up's worktree is not one", @"MY NOTES no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Read(inside), YN(Exists(free)), YN([said containsString:@"its folder is not beside the worktree of this Wrap Up"])]);
    NSString *del = MMRemovalDeleteStagedItem(other, inside, NULL), *mv = MMRemovalPutBackStagedItem(other, inside, free);
    T(@"waiting: the person's delete and put-back refuse it too, and it stays", @"yes yes MY NOTES no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(del != nil), YN(mv != nil), Read(inside), YN(Exists(free))]);
    Forget(other);
    fresh();
    (void)MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);
    T(@"put back: the true part of that Wrap Up still goes back, and its own folder goes", @"PLAIN=1 no", [NSString stringWithFormat:@"%@ %@", Read(plain), YN(Exists(real))]);

    // 5. A record that lists staged items but is no part of a Wrap Up: only a part stages.
    MMUndoRecord *alone = Done(Begin(@"trash", @"forged, staged with no Wrap Up"));
    [MMUndo.shared note:alone payload:@{@"staged": @[ForgedEntry(doc, doc, free)]}];
    said = [MMUndo.shared restore:alone.rid];
    T(@"put back: a record that names no Wrap Up has nothing moved from its staged list", @"MY THESIS no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), YN([said containsString:@"its record names no Wrap Up"])]);
    Forget(alone);
    fresh();

    // 6. The Trash list the same way: only what lies in the Trash goes back from it.
    alone = Done(Begin(@"trash", @"forged, trashed"));
    [MMUndo.shared note:alone payload:@{@"trashed": @[ForgedEntry(doc, doc, free)]}];
    said = [MMUndo.shared restore:alone.rid];
    T(@"put back: a Trash entry that does not lie in the Trash is not moved", @"MY THESIS no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Read(doc), YN(Exists(free)), YN([said containsString:@"it does not lie in the Trash"])]);
    Forget(alone);
    fresh();

    // 7. The issue's second case. A readable part whose Wrap Up has no record, with a folder of the right name and
    // a marker: it is listed, so the person sees it, and MinMacs takes no act on it.
    NSString *orphan = [base stringByAppendingPathComponent:@"orphan/.minmacs-staged-zzz70"], *kept = [orphan stringByAppendingPathComponent:@"0.keep.txt"];
    NSString *was = [base stringByAppendingPathComponent:@"orphan/wt/keep.txt"];
    Write(kept, @"KEEP=1");
    Write([orphan stringByAppendingPathComponent:@".minmacs"], @"zzz70");
    part = Done(Part(@"zzz70", @"forged, no Wrap Up record"));
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(kept, kept, was)], @"stagedIn": orphan, @"asked": @[was],
                                       @"removal": @{@"choice": @"delete", @"wants": @YES, @"staged": @YES, @"deleted": @NO}}];
    MMRemovalWaitingItem *item = WaitingAt(kept);
    T(@"waiting: an item whose Wrap Up has no record is listed", @"yes keep.txt", [NSString stringWithFormat:@"%@ %@", YN(item != nil), item.name]);
    said = MMRemovalDeleteWaiting(item.itemID, NULL);
    T(@"waiting: an item whose Wrap Up has no record cannot be deleted", @"no yes KEEP=1", [NSString stringWithFormat:@"%@ %@ %@", YN(item.canDelete), YN(said != nil), Read(kept)]);
    T(@"waiting: nor by the item function on its own", @"yes KEEP=1", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalDeleteStagedItem(part, kept, NULL) != nil), Read(kept)]);
    said = MMRemovalPutBackWaiting(item.itemID, nil);
    T(@"waiting: nor put back, by the person or by the sweep", @"no yes 0 KEEP=1 no",
      [NSString stringWithFormat:@"%@ %@ %ld %@ %@", YN(item.canPutBack), YN(said != nil), (long)MMRemovalSweepStaged(NULL), Read(kept), YN(Exists(was))]);
}
