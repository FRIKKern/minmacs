// Included by forged.m. The careful review of #73: what a record alone may still make MinMacs do. With nobody asking,
// the sweep and recovery only move files back: they never run a record's command, relaunch, restorer, bundle or
// recovery copy. An Undo checks every entry before it does anything. The staging folder's own files are no items. A
// Trash entry must say which file it is. An item goes back only to the old path the staging folder itself holds for
// it. An entry with an empty path stops nothing. Every file is a fixture under <dir>, inside $MINMACS_HOME.

/// An entry with no identity: it says only where its item waits and where it was.
static NSDictionary *Bare(NSString *to, NSString *from) { return @{@"to": to, @"from": from}; }
static BOOL gRestorerRan;

static void Unasked(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"unasked"), *tree = [base stringByAppendingPathComponent:@"wt"], *plain = [tree stringByAppendingPathComponent:@".env"];
    NSString *docs = [base stringByAppendingPathComponent:@"Documents"], *doc = [docs stringByAppendingPathComponent:@"thesis.txt"];
    NSString *free = [base stringByAppendingPathComponent:@"elsewhere/thesis.txt"], *flag = [base stringByAppendingPathComponent:@"RAN"];
    void (^fresh)(void) = ^{
        Write(doc, @"MY THESIS");
        [fm removeItemAtPath:free.stringByDeletingLastPathComponent error:nil];
        [fm removeItemAtPath:flag error:nil];
        gRestorerRan = NO;
    };
    // A command that leaves a mark and deletes the person's file. It is started detached, so each check waits for it.
    NSDictionary *restart = @{@"command": [NSString stringWithFormat:@"/usr/bin/touch '%@'; /bin/rm -f '%@'", flag, doc], @"env": @{@"PATH": @"/bin:/usr/bin"}};
    MMUndoRestoreKey(@"unaskedtest", ^NSString *(id value) { gRestorerRan = YES; return nil; });
    MMUndoRecord *parent = nil, *part = nil;
    fresh();

    // B1. A part that truly staged, with a restart command, a restorer key and a recovery copy written into its record.
    NSString *copied = [base stringByAppendingPathComponent:@"copied-out"];
    NSDictionary *extras = @{@"restart": restart, @"unaskedtest": @YES, @"recovery": @{@"dir": docs, @"root": copied, @"saved": @[@"thesis.txt"]}};
    part = FailedWithPart(@"unasked, the sweep", tree, plain, &parent);
    [MMUndo.shared finish:[MMUndo.shared record:part.rid] ok:YES freed:0 error:nil];
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:extras];
    NSInteger n = MMRemovalSweepStaged(NULL);
    usleep(1200000);
    T(@"put back: the sweep never runs a record's restart command", @"no MY THESIS", [NSString stringWithFormat:@"%@ %@", YN(Exists(flag)), Read(doc)]);
    T(@"put back: nor a restorer, nor a copy out of a recovery folder, and the staged item still goes back", @"no no 1 PLAIN=1 restored",
      [NSString stringWithFormat:@"%@ %@ %ld %@ %@", YN(gRestorerRan), YN(Exists(copied)), (long)n, Read(plain), StateWord(part)]);
    [fm removeItemAtPath:copied error:nil];
    fresh();

    // The same after a crash: recovery.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"unasked, recovery", tree, GoneOwner());
    part = StageMany(parent, @"unasked, recovery, part", @[plain], YES);
    [MMUndo.shared note:part payload:extras];
    (void)MMRemovalRecoverStaged();
    usleep(1200000);
    T(@"put back: recovery never runs a record's restart command, restorer or recovery copy", @"no MY THESIS no no PLAIN=1 failed",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN(Exists(flag)), Read(doc), YN(gRestorerRan), YN(Exists(copied)), Read(plain), StateWord(parent)]);
    [fm removeItemAtPath:copied error:nil];
    fresh();

    // B1. The person's own Undo: an entry it refuses stops it before anything runs.
    part = FailedWithPart(@"unasked, an Undo that is refused", tree, plain, &parent);
    [MMUndo.shared finish:[MMUndo.shared record:part.rid] ok:YES freed:0 error:nil];
    part = [MMUndo.shared record:part.rid];
    NSString *to = StagedTo(part);
    // The true entry is kept here: note: changes part's payload, so its first entry is the forged one after this.
    NSDictionary *trueEntry = MMRecordList(part.payload, @"staged").firstObject;
    [MMUndo.shared note:part payload:@{@"staged": @[ForgedEntry(doc, doc, free), trueEntry], @"restart": restart, @"unaskedtest": @YES}];
    NSString *said = [MMUndo.shared restore:part.rid];
    usleep(1200000);
    T(@"restore: an Undo with an entry it refuses runs nothing and moves nothing", @"yes no no MY THESIS PLAIN=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN(said != nil), YN(Exists(flag)), YN(gRestorerRan), Read(doc), Read(to), YN(Exists(plain))]);
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[trueEntry], @"restart": @{}, @"unaskedtest": @NO}];
    T(@"restore: with its true entry again, the item goes back", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(plain)]);
    fresh();

    // B2. The staging folder's own marker and .gitignore are no items, whoever names them.
    part = FailedWithPart(@"unasked, the marker", tree, plain, &parent);
    to = StagedTo(part);
    NSString *folder = MMRecordString(part.payload, @"stagedIn"), *marker = [folder stringByAppendingPathComponent:@".minmacs"], *ignore = [folder stringByAppendingPathComponent:@".gitignore"];
    NSString *out = [base stringByAppendingPathComponent:@"marker-out"], *out2 = [base stringByAppendingPathComponent:@"ignore-out"];
    MMUndoRecord *thief = Done(Part(parent.rid, @"unasked, the marker, forged part"));
    [MMUndo.shared note:thief payload:@{@"staged": @[ForgedEntry(marker, marker, out), ForgedEntry(ignore, ignore, out2)], @"stagedIn": folder, @"asked": @[out, out2],
                                        @"removal": @{@"choice": @"delete", @"wants": @YES, @"staged": @YES, @"deleted": @NO}}];
    said = [MMUndo.shared restore:thief.rid];
    NSString *del = MMRemovalDeleteStagedItem(thief, marker, NULL), *mv = MMRemovalPutBackStagedItem(thief, marker, out);
    T(@"put back: the staging folder's own marker is never moved or deleted", @"yes yes yes no no yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@", YN(said != nil), YN(del != nil), YN(mv != nil), YN(Exists(out)), YN(Exists(out2)), YN(Exists(marker)), YN(Exists(ignore))]);
    T(@"put back: so the true item is still listed, and still goes back", @"old-path-taken|put-back-failed nil PLAIN=1",
      [NSString stringWithFormat:@"%@ %@ %@", [@[@"old-path-taken", @"put-back-failed"] containsObject:WhyName(WaitingAt(to))] ? @"old-path-taken|put-back-failed" : WhyName(WaitingAt(to)),
       Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(plain)]);
    Forget(thief);
    fresh();

    // S1. A file the person put in the Trash themselves. An entry that names it, with no identity, moves nothing:
    // not in an Undo, and not in recovery with nobody asking.
    NSString *mine = [MMTrashFolder() stringByAppendingPathComponent:@"person-trashed.txt"], *pulled = [base stringByAppendingPathComponent:@"pulled/person-trashed.txt"];
    Write(mine, @"PERSON TRASHED THIS");
    MMUndoRecord *alone = Done(Begin(@"trash", @"unasked, a Trash entry with no identity"));
    [MMUndo.shared note:alone payload:@{@"trashed": @[Bare(mine, pulled)]}];
    said = [MMUndo.shared restore:alone.rid];
    T(@"put back: a Trash entry that does not say which file it is moves nothing", @"PERSON TRASHED THIS no yes",
      [NSString stringWithFormat:@"%@ %@ %@", Read(mine), YN(Exists(pulled)), YN([said containsString:@"the record does not say which file it is"])]);
    Forget(alone);
    parent = Unfinished(@"unasked, a Trash entry with no identity, recovery", tree, GoneOwner());
    part = Done(Part(parent.rid, @"unasked, a Trash entry with no identity, recovery, part"));
    [MMUndo.shared note:part payload:@{@"trashed": @[Bare(mine, pulled)], @"removal": @{@"choice": @"trash"}}];
    (void)MMRemovalRecoverStaged();
    T(@"put back: nor in recovery, with nobody asking", @"PERSON TRASHED THIS no", [NSString stringWithFormat:@"%@ %@", Read(mine), YN(Exists(pulled))]);
    Forget(part);
    [MMUndo.shared finish:[MMUndo.shared record:parent.rid] ok:NO freed:0 error:@"test"];
    [fm removeItemAtPath:mine error:nil];

    // S2. A second, forged part of a true Wrap Up names its truly staged item, with the item's true identity, and
    // another old path. The item goes back only to the old path the staging folder holds for it, by the part that staged it.
    part = FailedWithPart(@"unasked, another old path", tree, plain, &parent);
    to = StagedTo(part);
    folder = MMRecordString(part.payload, @"stagedIn");
    NSString *wrong = [base stringByAppendingPathComponent:@"wrong/place.env"];
    thief = Done(Part(parent.rid, @"unasked, another old path, forged part"));
    [MMUndo.shared note:thief payload:@{@"staged": @[ForgedEntry(to, to, wrong)], @"stagedIn": folder}];
    said = [MMUndo.shared restore:thief.rid];
    T(@"put back: a forged part never moves another part's staged item to an old path of its own", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(said != nil), YN(Exists(wrong))]);
    Forget(thief);
    // The true part's own record written again with another old path: the staging folder still says where it was.
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[ForgedEntry(to, to, wrong)]}];
    said = MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);
    T(@"put back: nor does the part that staged it, once its record names another old path", @"yes no PLAIN=1", [NSString stringWithFormat:@"%@ %@ %@", YN(said != nil), YN(Exists(wrong)), Read(to)]);
    // It is listed with neither act offered, since its record's old path is not the one the staging folder holds.
    MMRemovalWaitingItem *odd = WaitingAt(to);
    T(@"waiting: an item whose record names another old path is listed, and a put-back there is not offered", @"yes no no yes PLAIN=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN(odd != nil), YN(odd.canDelete), YN(odd.canPutBack),
       YN([MMRemovalPutBackWaiting(odd.itemID, nil) containsString:@"the record names another old path than the one it was staged from"]), Read(to), YN(Exists(wrong))]);
    // The person can still say where it goes, by its id.
    NSString *aside = [base stringByAppendingPathComponent:@"aside.env"];
    T(@"waiting: the person can still put it where they say", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBackStagedItem([MMUndo.shared record:part.rid], to, aside)), Read(aside)]);

    // S3. An entry with an empty path raised in lstat, and MinMacs stopped at every start.
    part = FailedWithPart(@"unasked, an empty path", tree, plain, &parent);
    to = StagedTo(part);
    [MMUndo.shared note:part payload:@{@"staged": @[@{@"to": @"", @"from": free}], @"trashed": @[@{@"to": mine, @"from": @""}]}];
    NSString *damage = [MMUndo.shared record:part.rid].damage;
    BOOL raised = NO;
    @try { (void)MMRemovalSweepStaged(NULL); (void)MMRemovalWaiting(); (void)[MMUndo.shared restore:part.rid]; (void)[MMUndo.shared moveBackOnly:part.rid]; }
    @catch (NSException *e) { raised = YES; }
    T(@"damaged: an entry with an empty path is damage, and the sweep, the list and an Undo go on", @"yes no PLAIN=1",
      [NSString stringWithFormat:@"%@ %@ %@", YN(damage != nil), YN(raised), Read(to)]);
    [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[ForgedEntry(to, to, plain)], @"trashed": @[]}];
    T(@"damaged: with its true entry again, the item goes back", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(plain)]);

    // L2. What the act would refuse is not offered. A folder with the right name and marker that is not beside the
    // Wrap Up's worktree is listed, since it may hold a file of the person's, and neither act is offered for it.
    part = FailedWithPart(@"unasked, listed but refused", tree, plain, &parent);
    NSString *fake = [docs stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:parent.rid]], *inside = [fake stringByAppendingPathComponent:@"0.notes.txt"];
    Write(inside, @"MY NOTES");
    Write([fake stringByAppendingPathComponent:@".minmacs"], parent.rid);
    thief = Done(Part(parent.rid, @"unasked, listed but refused, forged part"));
    [MMUndo.shared note:thief payload:@{@"staged": @[ForgedEntry(inside, inside, free)], @"stagedIn": fake}];
    MMRemovalWaitingItem *item = WaitingAt(inside);
    T(@"waiting: an item the act would refuse is listed with neither act offered, and its words say why", @"yes no no yes yes MY NOTES",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", YN(item != nil), YN(item.canDelete), YN(item.canPutBack),
       YN([MMRemovalDeleteWaitingWhyNot(item) containsString:@"its folder is not beside the worktree of this Wrap Up"]),
       YN([MMRemovalPutBackWaitingWhyNot(item, nil) containsString:@"Move it by hand from"]), Read(inside)]);
    Forget(thief);
    (void)MMRemovalPutBack(@[[MMUndo.shared record:part.rid]]);

    // L3. Close names the very path of what still waits, also a file no record names, which --waiting does not list.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"unasked, close with a stray file", tree, GoneOwner());
    part = StageMany(parent, @"unasked, close with a stray file, part", @[plain], YES);
    to = StagedTo(part);
    NSString *stray = [to.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"stray.txt"];
    RewriteBody(parent, @"state", @"finished");
    [fm moveItemAtPath:to toPath:plain error:nil];
    Write(stray, @"STRAY");
    said = MMRemovalCloseUnread(parent.rid);
    T(@"close: what still waits is named by its path, and --waiting is not said to list a file no record names", @"yes no pending STRAY",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN([said containsString:stray]), YN([said containsString:@"--waiting"]), StateWord(parent), Read(stray)]);
    [fm removeItemAtPath:stray error:nil];
    T(@"close: once it is gone, the close goes through", @"nil failed", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalCloseUnread(parent.rid)), StateWord(parent)]);
}

/// The Trash as a rule on strings, so the person's real Trash is never touched by a check.
static void TrashRule(void) {
    NSString *home = @"/Users/me";
    NSArray<NSString *> *paths = @[@"/Users/me/.Trash/notes.txt", @"/Volumes/Disk/.Trashes/501/notes.txt", @"/Users/me/Documents/.Trash/notes.txt", @"/Users/me/.Trash/deep/notes.txt",
                                   @"/Volumes/Disk/.Trashes/502/notes.txt", @"/Volumes/Disk/code/.Trashes/501/notes.txt", @"/Users/other/.Trash/notes.txt", @"/Users/me/.Trash", @"/tmp/.Trashes/501/notes.txt"];
    NSMutableArray<NSString *> *says = [NSMutableArray new];
    for (NSString *p in paths) [says addObject:YN(MMPathLiesInTrash(p, home, 501, nil))];
    T(@"trash rule: only directly in the home Trash or in this user's Trash on another volume, never a folder merely named so", @"yes yes no no no no no no no", [says componentsJoinedByString:@" "]);
    T(@"trash rule: a check has one Trash, its own, and with no home nothing is a Trash", @"yes no no no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(MMPathLiesInTrash(@"/t/home/Trash/a", home, 501, @"/t/home/Trash")), YN(MMPathLiesInTrash(@"/Users/me/.Trash/a", home, 501, @"/t/home/Trash")),
       YN(MMPathLiesInTrash(@"/t/home/Trash/a", home, 501, @"")), YN(MMPathLiesInTrash(@"/.Trash/a", @"", 501, nil))]);
}

// Issue #75: a stop between the rename into the staging folder and the record.
#import "stopped.m"
