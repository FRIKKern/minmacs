// Included by trashed.m. Issue #113: MinMacs stops inside -[MMUndo trash:record:error:], after the move to the Trash
// and before the record names the item. MinMacs's own list of what it sent to the Trash, written before the move,
// still names it, so removal --waiting and recovery name it, with where it is in the Trash when it is found there by
// inode and volume UUID, and never say it went back. Nothing here is moved out of the Trash by MinMacs. Every file is
// a fixture under <dir>, and the Trash is the test home's own, MMTrashFolder(): never the person's.

/// A second MinMacs, this binary, sends path to the Trash for a part of a new Wrap Up of tree and stops at point, as
/// a crash would. Returns its lines: "<wrap up rid> <part rid>", and "went on" when it did not stop.
static NSArray<NSString *> *StopInTrash(NSString *tree, NSString *path, NSString *point) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:gSelf];
    t.arguments = @[@"--stop-in-trash", tree, path];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"MINMACS_TEST_STOP_TRASH"] = point;
    t.environment = env;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    if (![t launchAndReturnError:nil]) return @[];
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [s componentsSeparatedByString:@"\n"];
}
/// The other side: run as `removaltest --stop-in-trash <tree> <path>`.
static int StopInTrashChild(NSString *tree, NSString *path) {
    MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalConfigFiles, nil);
    MMUndoRecord *parent = Unfinished(@"stopped in the move to the Trash", tree, MMRemovalOwner());
    MMUndoRecord *part = Part(parent.rid, @"config, stopped in the move to the Trash");
    MMRemovalNote(part, keep, nil); MMRemovalAsk(part, @[path]);
    printf("%s %s\n", parent.rid.UTF8String, part.rid.UTF8String);
    fflush(stdout);
    MMRemovalApply(path, keep, part, nil);
    printf("went on\n");
    return 0;
}
/// What lies directly in the test home's Trash with that inode, or nil.
static NSString *TrashedByIno(NSNumber *ino) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:MMTrashFolder() error:nil]) {
        NSString *p = [MMTrashFolder() stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) == 0 && (unsigned long long)st.st_ino == ino.unsignedLongLongValue) return p;
    }
    return nil;
}
static NSString *Has(NSString *words, NSString *part) { return YN(part.length && [words containsString:part]); }

static void TrashStopped(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashstop"), *tree = [base stringByAppendingPathComponent:@"wt"], *env = [tree stringByAppendingPathComponent:@".env.stop"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();
    __block NSString *wrap = @"", *partRid = @"";
    NSArray<NSString *> *(^stop)(NSString *) = ^NSArray<NSString *> *(NSString *point) {
        NSArray<NSString *> *said = StopInTrash(tree, env, point);
        NSArray<NSString *> *rids = [said.firstObject componentsSeparatedByString:@" "];
        wrap = rids.firstObject ?: @""; partRid = rids.count > 1 ? rids[1] : @"";
        return said;
    };
    NSString *(^recover)(void) = ^NSString *{ (void)MMRemovalRecoverStaged(); return [MMUndo.shared record:wrap].error ?: @""; };
    NSUInteger (^named)(void) = ^NSUInteger { return MMRecordList([MMUndo.shared record:partRid].payload, @"trashed").count; };

    // 1. The issue's case: a stop right after the move. The list names the item with its old path and the identity it
    // had there, and no Trash path yet. The record names nothing.
    Write(env, @"KEEP=1");
    NSNumber *ino = MMFileIdentity(env)[@"ino"];
    NSArray<NSString *> *said = stop(@"after-move");
    NSString *at = TrashedByIno(ino);
    NSDictionary *listed = TrashListed(partRid).firstObject;
    T(@"trash stop, after the move: MinMacs stopped with the item in the Trash, its own list names it with its old path and no Trash path, and its record names nothing",
      [NSString stringWithFormat:@"1 no yes %@ no 0", env],
      [NSString stringWithFormat:@"%lu %@ %@ %@ %@ %lu", (unsigned long)said.count, YN(Exists(env)), YN(at != nil), MMRecordString(listed, @"from") ?: @"(none)",
       YN(MMRecordHas(listed, @"to")), (unsigned long)named()]);
    MMRemovalWaitingItem *item = WaitingOfPart(partRid);
    T(@"trash stop, after the move: removal --waiting lists it with its Trash path and its old path, and offers no way out",
      [NSString stringWithFormat:@"in-trash .env.stop %@ %@ no no", at, env],
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", WhyName(item), item.name, item.stagedAt, item.oldPath, YN(item.canPutBack), YN(item.canDelete)]);
    NSString *words = recover();
    T(@"trash stop, after the move: recovery leaves it in the Trash, and its words name its Trash path and its old path and never say put back",
      @"KEEP=1 no failed yes yes no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", Read(at), YN(Exists(env)), StateWord([MMUndo.shared record:wrap]), Has(words, at), Has(words, env), Has(words, @"put back")]);
    item = WaitingOfPart(partRid);
    NSString *noBack = MMRemovalPutBackWaiting(item.itemID, nil), *noDelete = MMRemovalDeleteWaiting(item.itemID, NULL);
    T(@"trash stop, after the move: once recovery ran --waiting still lists it, and a put-back or a delete of it through MinMacs is refused and moves nothing",
      @"in-trash yes yes KEEP=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", WhyName(item), YN(noBack != nil), YN(noDelete != nil), Read(at), YN(Exists(env))]);
    // The person puts it back from the Trash: it is at its old path, the very file, and nothing is listed any more.
    [fm moveItemAtPath:at toPath:env error:nil];
    T(@"trash stop, after the move: once the person put it back by hand, nothing is listed", @"KEEP=1 not listed", [NSString stringWithFormat:@"%@ %@", Read(env), WhyName(WaitingOfPart(partRid))]);

    // 2. A stop after the list's second write, which names the Trash path, and before the record's note.
    said = stop(@"after-list");
    at = TrashedByIno(ino);
    listed = TrashListed(partRid).firstObject;
    T(@"trash stop, after the list's second write: the list names its Trash path too, and its record names nothing",
      [NSString stringWithFormat:@"1 %@ 0", at], [NSString stringWithFormat:@"%lu %@ %lu", (unsigned long)said.count, MMRecordString(listed, @"to") ?: @"(none)", (unsigned long)named()]);
    item = WaitingOfPart(partRid);
    T(@"trash stop, after the list's second write: --waiting lists it with its Trash path", [NSString stringWithFormat:@"in-trash %@ %@", at, env],
      [NSString stringWithFormat:@"%@ %@ %@", WhyName(item), item.stagedAt, item.oldPath]);
    words = recover();
    T(@"trash stop, after the list's second write: recovery leaves it in the Trash, names its Trash path and never says put back", @"KEEP=1 no yes no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(at), YN(Exists(env)), Has(words, at), Has(words, @"put back")]);
    [fm moveItemAtPath:at toPath:env error:nil];

    // 3. A stop after the list's first write and before the move: the item never left. Nothing is stranded.
    said = stop(@"before-move");
    T(@"trash stop, before the move: the list names it, it is still at its old path, and --waiting lists nothing", @"1 KEEP=1 1 not listed",
      [NSString stringWithFormat:@"%lu %@ %lu %@", (unsigned long)said.count, Read(env), (unsigned long)TrashListed(partRid).count, WhyName(WaitingOfPart(partRid))]);
    words = recover();
    T(@"trash stop, before the move: recovery's words name nothing in the Trash, and it stays where it is", @"KEEP=1 no", [NSString stringWithFormat:@"%@ %@", Read(env), Has(words, @"Trash")]);

    // 4. Another file under its name in the Trash: the person moved the item out and something else took its name.
    // That file is not the item by its inode, so it is never named as the item.
    said = stop(@"after-move");
    at = TrashedByIno(ino);
    NSString *aside = [base stringByAppendingPathComponent:@"aside/.env.stop"];
    [fm createDirectoryAtPath:aside.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [fm moveItemAtPath:at toPath:aside error:nil];
    Write(at, @"OTHER=1");
    T(@"trash stop, another file under its Trash name: --waiting does not take it for the item", @"not listed", WhyName(WaitingOfPart(partRid)));
    words = recover();
    T(@"trash stop, another file under its Trash name: recovery's words do not name that file, never say put back, and say it is not known where the item is",
      @"OTHER=1 no no yes", [NSString stringWithFormat:@"%@ %@ %@ %@", Read(at), Has(words, at), Has(words, @"put back"), Has(words, @"it is not known where")]);
    [fm removeItemAtPath:at error:nil];
    [fm moveItemAtPath:aside toPath:env error:nil];

    // 5. A damaged list: nothing in it is believed, so nothing is named from it, and the words say it cannot be read.
    said = stop(@"after-move");
    at = TrashedByIno(ino);
    [@"{\"items\": [" writeToFile:TrashListOf(partRid) atomically:YES encoding:NSUTF8StringEncoding error:nil];
    T(@"trash stop, a damaged list: --waiting names nothing from it", @"not listed", WhyName(WaitingOfPart(partRid)));
    words = recover();
    T(@"trash stop, a damaged list: recovery names nothing from it, never says put back, and says the list cannot be read", @"KEEP=1 no no yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(at), Has(words, at), Has(words, @"put back"), Has(words, @"cannot be read")]);
    [fm moveItemAtPath:at toPath:env error:nil];

    // 6. A forged list: it names a file the person trashed themselves, by its true inode and volume, from an old path
    // the record never asked for. It is never named as what MinMacs sent there.
    NSString *mine = [MMTrashFolder() stringByAppendingPathComponent:@"person-stop-notes.txt"];
    Write(mine, @"PERSON TRASHED THIS");
    said = stop(@"after-move");
    at = TrashedByIno(ino);
    NSMutableDictionary *forged = [MMFileIdentity(mine) mutableCopy];
    forged[@"from"] = [base stringByAppendingPathComponent:@"elsewhere/notes.txt"]; forged[@"to"] = mine;
    NSMutableDictionary *noTo = [MMFileIdentity(mine) mutableCopy];
    noTo[@"from"] = [base stringByAppendingPathComponent:@"elsewhere/other.txt"];
    [[NSJSONSerialization dataWithJSONObject:@{@"items": @[forged, noTo]} options:0 error:nil] writeToFile:TrashListOf(partRid) atomically:YES];
    T(@"trash stop, a forged list: --waiting never names the person's Trash file", @"not listed not listed",
      [NSString stringWithFormat:@"%@ %@", WhyName(WaitingOfPart(partRid)), WhyName(WaitingAt(mine))]);
    words = recover();
    T(@"trash stop, a forged list: nor do recovery's words, which never say put back, and the file stays", @"no no PERSON TRASHED THIS",
      [NSString stringWithFormat:@"%@ %@ %@", Has(words, mine), Has(words, @"put back"), Read(mine)]);
    [fm removeItemAtPath:mine error:nil];
    [fm moveItemAtPath:at toPath:env error:nil];

    // 7. A hard link: the item has a second name beside it, outside the Trash. Only its name in the Trash is named.
    NSString *second = [tree stringByAppendingPathComponent:@".env.stop.second"];
    link(env.fileSystemRepresentation, second.fileSystemRepresentation);
    said = stop(@"after-move");
    at = TrashedByIno(ino);
    item = WaitingOfPart(partRid);
    T(@"trash stop, a hard link: --waiting names it at its Trash path, and never its second name outside the Trash", [NSString stringWithFormat:@"in-trash %@ yes not listed", at],
      [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(item), item.stagedAt, YN(Exists(second)), WhyName(WaitingAt(second))]);
    // The person sends the second name to the Trash too: two names there for one file. MinMacs cannot tell which one
    // it moved, so it names neither.
    NSString *secondInTrash = [MMTrashFolder() stringByAppendingPathComponent:@"second-name-of-env"];
    [fm moveItemAtPath:second toPath:secondInTrash error:nil];
    T(@"trash stop, a hard link with its second name in the Trash too: --waiting names neither", @"not listed not listed",
      [NSString stringWithFormat:@"%@ %@", WhyName(WaitingOfPart(partRid)), WhyName(WaitingAt(secondInTrash))]);
    words = recover();
    T(@"trash stop, a hard link with its second name in the Trash too: recovery's words name neither, never say put back, and say why", @"no no no yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Has(words, at), Has(words, secondInTrash), Has(words, @"put back"), Has(words, @"more than one name")]);
    [fm removeItemAtPath:secondInTrash error:nil];
    [fm moveItemAtPath:at toPath:env error:nil];
    [fm removeItemAtPath:env error:nil];
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}

/// The lows of issue #113: a list folder that is a link, and an old path with "..".
static void TrashListLows(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashlows"), *cache = [base stringByAppendingPathComponent:@"cache/b.bin"];

    // core/trashed is a link: the lists would go wherever it points. MinMacs takes no list there, so the item stays.
    NSString *dir = TrashListOf(@"x").stringByDeletingLastPathComponent, *real = [base stringByAppendingPathComponent:@"lists-elsewhere"];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    [fm moveItemAtPath:dir toPath:real error:nil];
    symlink(real.fileSystemRepresentation, dir.fileSystemRepresentation);
    Write(cache, @"CACHE");
    MMUndoRecord *r = Begin(@"trash", @"trash, the list folder is a link");
    MMRemovalAsk(r, @[cache.stringByDeletingLastPathComponent]);
    NSError *e = nil;
    BOOL went = MMRemovalApply(cache.stringByDeletingLastPathComponent, MMRemovalDecideWith(MMRemovalTrash, MMRemovalClutter, nil), r, &e);
    T(@"trash list, a linked folder: MinMacs writes no list through it, and the item stays where it is", @"no CACHE no",
      [NSString stringWithFormat:@"%@ %@ %@", YN(went), Read(cache), YN(Exists([real stringByAppendingPathComponent:[r.rid stringByAppendingPathExtension:@"json"]]))]);
    [MMUndo.shared finish:r ok:NO freed:0 error:@"test"];
    [fm removeItemAtPath:dir error:nil];
    [fm moveItemAtPath:real toPath:dir error:nil];
    // A link is gone the same way, if the move sent the folder there anyway.
    NSString *at = TrashedTo(r);
    if (at) [fm moveItemAtPath:at toPath:cache.stringByDeletingLastPathComponent error:nil];

    // A trashed entry whose old path holds "..", in its record and in its list alike: MinMacs does not move it there.
    MMUndoRecord *honest = TrashAlone(@"trash, an old path with ..", cache.stringByDeletingLastPathComponent);
    at = TrashedTo(honest);
    NSString *dotted = [base stringByAppendingPathComponent:@"cache/../moved-up"], *landing = [base stringByAppendingPathComponent:@"moved-up"];
    NSMutableDictionary *entry = [MMRecordList(honest.payload, @"trashed").firstObject mutableCopy];
    entry[@"from"] = dotted;
    [MMUndo.shared note:honest payload:@{@"trashed": @[entry]}];
    NSMutableDictionary *listed = [TrashListed(honest.rid).firstObject mutableCopy];
    listed[@"from"] = dotted;
    [[NSJSONSerialization dataWithJSONObject:@{@"items": @[listed]} options:NSJSONWritingWithoutEscapingSlashes error:nil] writeToFile:TrashListOf(honest.rid) atomically:YES];
    NSString *said = [MMUndo.shared restore:honest.rid];
    T(@"trash list, an old path with ..: an Undo refuses it, it stays in the Trash, and nothing comes to the path it names", @"yes yes no",
      [NSString stringWithFormat:@"%@ %@ %@", YN([said containsString:@"its old path is not a real path"]), YN(Exists(at)), YN(Exists(landing))]);
    if (Exists(at)) [fm removeItemAtPath:at error:nil];
    if (Exists(landing)) [fm removeItemAtPath:landing error:nil];
}
