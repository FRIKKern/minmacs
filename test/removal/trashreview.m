// Included by trashstop.m. Issue #113, second review: the words about an item MinMacs sent to the Trash, or was
// sending there, say only what is known. A list entry with no Trash path only says the move was about to run, a look
// that was refused is no "not there", and what any record names is that record's. Each guard that keeps MinMacs from
// naming a wrong file has a case here that goes red without it. Every file is a fixture under <dir>, and the Trash is
// the test home's own, MMTrashFolder(): never the person's.

/// Writes items as record rid's list of what it sent to the Trash, as a forger with the support folder would.
static void ForgeTrashList(NSString *rid, NSArray<NSDictionary *> *items) {
    [[NSJSONSerialization dataWithJSONObject:@{@"items": items} options:NSJSONWritingWithoutEscapingSlashes error:nil] writeToFile:TrashListOf(rid) atomically:YES];
}
/// The identity of the file at path with from as its old path, as a list entry.
static NSDictionary *EntryFor(NSString *path, NSString *from, BOOL withVolume) {
    NSMutableDictionary *e = [MMFileIdentity(path) mutableCopy] ?: [NSMutableDictionary new];
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) == 0) e[@"ino"] = @(st.st_ino);   // a link's own inode
    if (!withVolume) [e removeObjectForKey:@"vol"];
    e[@"from"] = from;
    return e;
}

static void TrashReviewed(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashreview"), *tree = [base stringByAppendingPathComponent:@"wt"], *env = [tree stringByAppendingPathComponent:@".env.rev"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();
    __block NSString *wrap = @"", *partRid = @"";
    void (^stop)(NSString *, NSString *) = ^(NSString *path, NSString *point) {
        NSArray<NSString *> *rids = [StopInTrash(tree, path, point).firstObject componentsSeparatedByString:@" "];
        wrap = rids.firstObject ?: @""; partRid = rids.count > 1 ? rids[1] : @"";
    };
    NSString *(^recover)(void) = ^NSString *{ (void)MMRemovalRecoverStaged(); return [MMUndo.shared record:wrap].error ?: @""; };
    NSString *(^plain)(NSString *) = ^NSString *(NSString *words) {
        return YN(![words containsString:@"…"] && ![words containsString:@"..."] && ![words containsString:@"for good"] && ![words containsString:@"for ever"]);
    };

    // B1a. A stop before the move, then an editor saves the file anew: another inode at the old path. MinMacs never
    // sent anything to the Trash, so the words say it was sending it, and that it is at neither place.
    Write(env, @"REV=1");
    stop(env, @"before-move");
    Write(env, @"EDITED=1");
    NSString *words = recover();
    T(@"trash review, a stop before the move and a new file at the old path: the words say MinMacs was sending it, never that it had sent it, and that it is at neither place",
      @"EDITED=1 no yes yes no yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", Read(env), Has(words, @"had sent"), Has(words, @"was sending"),
                                      Has(words, @"neither at its old path nor in the Trash"), Has(words, @"put back"), plain(words)]);

    // B1a. A stop after the list's second write: MinMacs had sent it. The person moved it out of the Trash elsewhere.
    NSNumber *ino = MMFileIdentity(env)[@"ino"];
    stop(env, @"after-list");
    NSString *at = TrashedByIno(ino), *aside = [base stringByAppendingPathComponent:@"aside/.env.rev"];
    [fm createDirectoryAtPath:aside.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm moveItemAtPath:at toPath:aside error:nil];
    words = recover();
    T(@"trash review, sent to the Trash and moved elsewhere by the person: the words say MinMacs had sent it and finds it neither at its old path nor in the Trash",
      @"yes no yes no", [NSString stringWithFormat:@"%@ %@ %@ %@", Has(words, @"had sent"), Has(words, @"was sending"), Has(words, @"neither at its old path nor in the Trash"), Has(words, aside)]);
    [fm moveItemAtPath:aside toPath:env error:nil];

    // B1b. A Trash that refuses a look, as it may without Full Disk Access: the item is there, and nothing is said gone.
    // Mode 0 refuses the folder's list too; 0444 lists the names and refuses a look at each. Each with and without a
    // Trash path in the list.
    struct stat tst;
    lstat(MMTrashFolder().fileSystemRepresentation, &tst);
    NSMutableArray<NSString *> *refusedWant = [NSMutableArray new], *refusedGot = [NSMutableArray new];
    for (NSNumber *mode in @[@0, @0444]) for (NSString *point in @[@"after-list", @"after-move"]) {
        ino = MMFileIdentity(env)[@"ino"];
        stop(env, point);
        at = TrashedByIno(ino);
        chmod(MMTrashFolder().fileSystemRepresentation, mode.unsignedShortValue);
        words = recover();
        NSString *listed = WhyName(WaitingOfPart(partRid));
        chmod(MMTrashFolder().fileSystemRepresentation, tst.st_mode & 07777);
        [refusedWant addObject:[NSString stringWithFormat:@"%o %@: no no yes EDITED=1 not listed", mode.intValue, point]];
        [refusedGot addObject:[NSString stringWithFormat:@"%o %@: %@ %@ %@ %@ %@", mode.intValue, point, Has(words, @"is not where MinMacs left it"), Has(words, @"neither at its old path"),
                               Has(words, @"the Trash could not be read"), Read(at), listed]];
        [fm moveItemAtPath:at toPath:env error:nil];
    }
    T(@"trash review, a Trash that cannot be read: the words never say the item is gone from where MinMacs left it, say the Trash could not be read, and it stays",
      [refusedWant componentsJoinedByString:@" | "], [refusedGot componentsJoinedByString:@" | "]);

    // B1b. An old path whose folder refuses a look: a stop before the move left the file there, unseen. The words never
    // say it is at neither place.
    struct stat wst;
    lstat(tree.fileSystemRepresentation, &wst);
    stop(env, @"before-move");
    chmod(tree.fileSystemRepresentation, 0);
    words = recover();
    chmod(tree.fileSystemRepresentation, wst.st_mode & 07777);
    T(@"trash review, an old path that cannot be read: the words never say MinMacs finds it at neither place, and say its old path could not be read", @"no yes EDITED=1",
      [NSString stringWithFormat:@"%@ %@ %@", Has(words, @"neither at its old path"), Has(words, @"its old path could not be read"), Read(env)]);

    // B2. The person put it back by hand, as the words say, and a later record sent the same file to the Trash and
    // names it. It is that record's: the first neither lists it nor speaks of it, and the later Undo still brings it.
    ino = MMFileIdentity(env)[@"ino"];
    stop(env, @"after-move");
    NSString *first = partRid;
    at = TrashedByIno(ino);
    (void)recover();
    [fm moveItemAtPath:at toPath:env error:nil];
    MMUndoRecord *again = TrashAlone(@"trash review, sent again", env);
    NSString *againAt = TrashedTo(again);
    T(@"trash review, put back by hand and sent again under a record that names it: --waiting lists it for neither, and the first record's words name nothing",
      @"not listed not listed nil yes", [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(WaitingOfPart(first)), WhyName(WaitingAt(againAt)),
                                         Or(MMRemovalTrashStrandedWords(@[[MMUndo.shared record:first]])), YN(Exists(againAt))]);
    (void)[MMUndo.shared restore:again.rid];
    T(@"trash review, and the later record's Undo brings it back", @"EDITED=1 no", [NSString stringWithFormat:@"%@ %@", Read(env), YN(Exists(againAt))]);

    // S1. A Wrap Up whose record cannot be read in full: its words never say nothing needed to go back beside an item
    // still in the Trash, and name where it lies.
    ino = MMFileIdentity(env)[@"ino"];
    stop(env, @"after-move");
    at = TrashedByIno(ino);
    RewriteBody([MMUndo.shared record:wrap], @"freedBytes", @"much");
    words = recover();
    T(@"trash review, a damaged Wrap Up: its words name the item's Trash path, never say nothing needed to go back, and never say put back",
      @"yes yes no no", [NSString stringWithFormat:@"%@ %@ %@ %@", Has(words, @"could not be read in full"), Has(words, at), Has(words, @"Nothing it had moved needed to go back"), Has(words, @"put back")]);
    [fm moveItemAtPath:at toPath:env error:nil];

    // S2. A Wrap Up that still runs may yet name what it sent: --waiting leaves it, until its process is gone.
    ino = MMFileIdentity(env)[@"ino"];
    stop(env, @"after-move");
    at = TrashedByIno(ino);
    [MMUndo.shared note:[MMUndo.shared record:wrap] payload:@{@"owner": MMRemovalOwner()}];
    NSString *running = WhyName(WaitingOfPart(partRid));
    [MMUndo.shared note:[MMUndo.shared record:wrap] payload:@{@"owner": GoneOwner()}];
    T(@"trash review, a Wrap Up that still runs: --waiting does not list what it sent, and lists it once its process is gone", @"not listed in-trash",
      [NSString stringWithFormat:@"%@ %@", running, WhyName(WaitingOfPart(partRid))]);
    // A Wrap Up whose state cannot be read: what lies in the Trash keeps nothing from closing it, which moves nothing.
    RewriteBody([MMUndo.shared record:wrap], @"state", @[@"done"]);
    NSString *closeNo = MMRemovalCloseUnreadWhyNot(wrap), *closed = MMRemovalCloseUnread(wrap);
    T(@"trash review, a Wrap Up whose state cannot be read: an item in the Trash keeps nothing from closing it, and it stays in the Trash", @"nil nil EDITED=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Or(closeNo), Or(closed), Read(at), YN(Exists(env))]);
    [fm moveItemAtPath:at toPath:env error:nil];

    // S2. Forged lists for the record's very old path. A file outside the Trash, with its own id as the Trash path:
    // never named. An entry with no volume UUID: an inode alone matches any file of the Trash, so nothing is named.
    NSString *outside = [base stringByAppendingPathComponent:@"Documents/thesis.txt"], *mine = [MMTrashFolder() stringByAppendingPathComponent:@"review-person.txt"];
    Write(outside, @"THESIS"); Write(mine, @"PERSON TRASHED THIS");
    NSMutableDictionary *outsideTo = [EntryFor(outside, env, YES) mutableCopy];
    outsideTo[@"to"] = outside;
    NSArray *forgeries = @[@[@"a Trash path outside the Trash", outsideTo, outside], @[@"an entry with no volume UUID", EntryFor(mine, env, NO), mine]];
    for (NSArray *f in forgeries) {
        ino = MMFileIdentity(env)[@"ino"];
        stop(env, @"after-move");
        at = TrashedByIno(ino);
        ForgeTrashList(partRid, @[f[1]]);
        NSString *waiting = [NSString stringWithFormat:@"%@ %@", WhyName(WaitingOfPart(partRid)), WhyName(WaitingAt(f[2]))];
        words = recover();
        T([NSString stringWithFormat:@"trash review, a forged list with %@: neither --waiting nor the words name that file, and nothing moves", f[0]],
          @"not listed not listed no THESIS PERSON TRASHED THIS", [NSString stringWithFormat:@"%@ %@ %@ %@", waiting, Has(words, f[2]), Read(outside), Read(mine)]);
        [fm moveItemAtPath:at toPath:env error:nil];
    }
    [fm removeItemAtPath:mine error:nil];

    // S2. A Trash folder that is a link to a folder elsewhere is no Trash, by its real path: what lies there is not
    // named as in the Trash.
    ino = MMFileIdentity(env)[@"ino"];
    stop(env, @"after-move");
    at = TrashedByIno(ino);
    NSString *trash = MMTrashFolder(), *elsewhere = [base stringByAppendingPathComponent:@"not-a-trash"];
    [fm moveItemAtPath:trash toPath:elsewhere error:nil];
    symlink(elsewhere.fileSystemRepresentation, trash.fileSystemRepresentation);
    NSString *waiting = WhyName(WaitingOfPart(partRid));
    words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:partRid]]) ?: @"";
    [fm removeItemAtPath:trash error:nil];
    [fm moveItemAtPath:elsewhere toPath:trash error:nil];
    T(@"trash review, a Trash folder that is a link to elsewhere: --waiting and the words do not name what lies there as in the Trash", @"not listed no yes",
      [NSString stringWithFormat:@"%@ %@ %@", waiting, Has(words, @"it is in the Trash"), YN(Exists(at))]);
    (void)recover();
    [fm moveItemAtPath:at toPath:env error:nil];

    // B2's bounds. A record names the item only at that Trash path with that id. One that names only its Trash path
    // with another id, or only its id at another path, or whose Undo ran, does not: the item is listed and named.
    NSArray<NSString *> *bys = @[@"its Trash path with another id", @"its id at another path", @"both, though its Undo ran"];
    for (NSUInteger k = 0; k < bys.count; k++) {
        NSString *named = [tree stringByAppendingPathComponent:[NSString stringWithFormat:@".env.named-%lu", (unsigned long)k]];
        Write(named, @"NAMED=1");
        ino = MMFileIdentity(named)[@"ino"];
        stop(named, @"after-move");
        at = TrashedByIno(ino);
        NSMutableDictionary *x = [EntryFor(at, named, YES) mutableCopy];
        x[@"to"] = at;
        if (k == 0) x[@"ino"] = @(ino.unsignedLongLongValue + 1000003);
        if (k == 1) x[@"to"] = [base stringByAppendingPathComponent:@"named-elsewhere"];
        MMUndoRecord *namer = Begin(@"trash", [@"trash review, a record that names " stringByAppendingString:bys[k]]);
        [MMUndo.shared note:namer payload:@{@"trashed": @[x]}];
        [MMUndo.shared finish:namer ok:NO freed:0 error:@"test"];
        if (k == 2) RewriteBody(namer, @"state", @"restored");
        T([NSString stringWithFormat:@"trash review, another record names %@: the item is still listed and named", bys[k]], [NSString stringWithFormat:@"in-trash yes%@", k == 2 ? @" restored" : @""],
          [NSString stringWithFormat:@"%@ %@%@", WhyName(WaitingOfPart(partRid)), Has(MMRemovalTrashStrandedWords(@[[MMUndo.shared record:partRid]]), at), k == 2 ? [@" " stringByAppendingString:StateWord(namer)] : @""]);
        (void)recover();
        [fm moveItemAtPath:at toPath:named error:nil];
    }

    // The move itself refuses an old path with a "." or ".." name, since MinMacs would not bring it back there.
    NSString *dotted = [base stringByAppendingPathComponent:@"dotted.bin"], *dot = [tree stringByAppendingPathComponent:@".env.dot"];
    Write([base stringByAppendingPathComponent:@"up/x"], @"UP"); Write(dotted, @"DOTTED"); Write(dot, @"DOT");
    MMUndoRecord *up = TrashAlone(@"trash review, a path with ..", [base stringByAppendingString:@"/up/../dotted.bin"]);
    MMUndoRecord *here = TrashAlone(@"trash review, a path with .", [tree stringByAppendingString:@"/./.env.dot"]);
    T(@"trash review, an old path with a . or .. name: MinMacs does not send it to the Trash, and lists nothing", @"DOTTED DOT no no 0 0",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %lu %lu", Read(dotted), Read(dot), YN(TrashedTo(up) != nil), YN(TrashedTo(here) != nil), (unsigned long)TrashListed(up.rid).count, (unsigned long)TrashListed(here.rid).count]);

    // S2. The staging folder's own files are read only as plain files of the person's own: a link in their place,
    // even to a true copy, reads as nothing, so no item is believed from it.
    NSString *staged = [tree stringByAppendingPathComponent:@".env.staged"];
    Write(staged, @"STAGED=1");
    MMUndoRecord *parent = Begin(@"wrapup", @"trash review, staging files");
    [MMUndo.shared note:parent payload:@{@"path": tree}];
    NSString *folder = StagedTo(StageOne(parent, @"trash review, staged config", staged)).stringByDeletingLastPathComponent;
    NSString *items = [folder stringByAppendingPathComponent:@".minmacs-items"], *marker = [folder stringByAppendingPathComponent:@".minmacs"];
    NSString *before = [NSString stringWithFormat:@"%@ %@", YN(MMRemovalStagingItems(folder) != nil), YN(MMRemovalStagingMarkerSays(folder, parent.rid))];
    for (NSString *own in @[items, marker]) {
        NSString *copy = [base stringByAppendingPathComponent:[own.lastPathComponent stringByAppendingString:@".copy"]];
        [fm moveItemAtPath:own toPath:copy error:nil];
        symlink(copy.fileSystemRepresentation, own.fileSystemRepresentation);
    }
    NSString *linked = [NSString stringWithFormat:@"%@ %@ %@", YN(MMRemovalStagingItems(folder) != nil), YN(MMRemovalStagingMarkerSays(folder, parent.rid)), YN(MMRemovalStagingOwnFilesAreOurs(folder))];
    for (NSString *own in @[items, marker]) {
        [fm removeItemAtPath:own error:nil];
        [fm moveItemAtPath:[base stringByAppendingPathComponent:[own.lastPathComponent stringByAppendingString:@".copy"]] toPath:own error:nil];
    }
    T(@"trash review, a staging folder whose list and marker are links to true copies: neither is believed, and both are again once they are plain files",
      @"yes yes|no no no|yes yes", [NSString stringWithFormat:@"%@|%@|%@ %@", before, linked, YN(MMRemovalStagingItems(folder) != nil), YN(MMRemovalStagingMarkerSays(folder, parent.rid))]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    (void)MMRemovalRecoverStaged();
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}

/// For the CLI checks of removal.sh: MinMacs stops after sending a file whose name holds a newline to the Trash, so
/// --waiting lists it. Prints the part's rid.
static int LeaveInTrash(NSString *dir) {
    gDir = dir;
    NSString *tree = Path(@"clitrash/wt"), *odd = [tree stringByAppendingPathComponent:@"nl\nname.env"];
    Write(odd, @"ODD=1");
    NSArray<NSString *> *rids = [StopInTrash(tree, odd, @"after-list").firstObject componentsSeparatedByString:@" "];
    printf("%s\n", rids.count > 1 ? rids[1].UTF8String : "");
    return 0;
}
