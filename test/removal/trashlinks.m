// Included by trashown.m. Issue #113, fourth review: a record's own names are its own by old path and id together, so
// a hard link's second name, one file under two old paths, is never hidden by the first; and each answer for a volume
// id that cannot be read has a check. Every file is a fixture under <dir>, and the Trash is the test home's own.

/// The other side of StopSecond: run as `removaltest --stop-second <tree> <first> <second> <point>`. One part asks both
/// paths, sends the first to the Trash with no stop, then the second, stopping at point. Prints the rids first.
static int StopSecondChild(NSString *tree, NSString *first, NSString *second, NSString *point) {
    MMRemovalDecision *keep = MMRemovalDecide(MMRemovalConfigFiles, nil, nil);
    MMUndoRecord *parent = Unfinished(@"two names of one file", tree, MMRemovalOwner());
    MMUndoRecord *part = Part(parent.rid, @"config, two names of one file");
    MMRemovalNote(part, keep, nil); MMRemovalAsk(part, @[first, second]);
    printf("%s %s\n", parent.rid.UTF8String, part.rid.UTF8String);
    fflush(stdout);
    MMRemovalApply(first, keep, part, nil);
    setenv("MINMACS_TEST_STOP_TRASH", point.UTF8String, 1);
    MMRemovalApply(second, keep, part, nil);
    printf("went on\n");
    return 0;
}
static NSArray<NSString *> *StopSecond(NSString *tree, NSString *first, NSString *second, NSString *point) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:gSelf];
    t.arguments = @[@"--stop-second", tree, first, second, point];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    if (![t launchAndReturnError:nil]) return @[];
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    return [[s componentsSeparatedByString:@"\n"].firstObject componentsSeparatedByString:@" "];
}
/// What lies directly in the test home's Trash with that inode, every name of it.
static NSArray<NSString *> *TrashedNamesByIno(NSNumber *ino) {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:MMTrashFolder() error:nil]) {
        NSString *p = [MMTrashFolder() stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) == 0 && (unsigned long long)st.st_ino == ino.unsignedLongLongValue) [out addObject:p];
    }
    return out;
}

static void TrashLinkedNames(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashlinks"), *tree = [base stringByAppendingPathComponent:@"wt"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();

    // S6. A volume id that cannot be read at the look, each place it is asked. The old path: a stop before the move
    // left the file there, and its id cannot be told.
    NSString *e = [tree stringByAppendingPathComponent:@".env.uuid"];
    Write(e, @"UUID=1");
    NSNumber *ino = MMFileIdentity(e)[@"ino"];
    NSArray<NSString *> *rids = [StopInTrash(tree, e, @"before-move").firstObject componentsSeparatedByString:@" "];
    NSString *part = rids.count > 1 ? rids[1] : @"";
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    NSString *words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:part]]) ?: @"";
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    T(@"trash links, a volume id that cannot be read at the old path: the words never say MinMacs finds it at neither place, and say its id cannot be read",
      @"no yes UUID=1", [NSString stringWithFormat:@"%@ %@ %@", Has(words, @"neither at its old path"), Has(words, @"volume's id cannot be read now, so MinMacs cannot say where it is"), Read(e)]);
    (void)MMRemovalRecoverStaged();

    // The scan: a stop right after the move, so the list has no Trash path, and only the look through the Trash meets it.
    rids = [StopInTrash(tree, e, @"after-move").firstObject componentsSeparatedByString:@" "];
    part = rids.count > 1 ? rids[1] : @"";
    NSString *at = TrashedByIno(ino);
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:part]]) ?: @"";
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    T(@"trash links, a volume id that cannot be read in the look through the Trash: the words never say MinMacs finds it at neither place, and say its id cannot be read",
      @"no yes", [NSString stringWithFormat:@"%@ %@", Has(words, @"neither at its old path"), Has(words, @"volume's id cannot be read now, so MinMacs cannot say whether it is there")]);
    (void)MMRemovalRecoverStaged();
    [fm moveItemAtPath:at toPath:e error:nil];

    // The list's Trash path: it lies in a folder in the Trash, which the look through the Trash does not enter.
    rids = [StopInTrash(tree, e, @"after-list").firstObject componentsSeparatedByString:@" "];
    part = rids.count > 1 ? rids[1] : @"";
    at = TrashedByIno(ino);
    NSString *folder = [MMTrashFolder() stringByAppendingPathComponent:@"a folder"], *inside = [folder stringByAppendingPathComponent:at.lastPathComponent];
    [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [fm moveItemAtPath:at toPath:inside error:nil];
    NSMutableDictionary *entry = [TrashListed(part).firstObject mutableCopy];
    entry[@"to"] = inside;
    [[NSJSONSerialization dataWithJSONObject:@{@"items": @[entry]} options:NSJSONWritingWithoutEscapingSlashes error:nil] writeToFile:TrashListOf(part) atomically:YES];
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:part]]) ?: @"";
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    T(@"trash links, a volume id that cannot be read at the list's Trash path: the words never say MinMacs finds it at neither place, and say its id cannot be read",
      @"no yes", [NSString stringWithFormat:@"%@ %@", Has(words, @"neither at its old path"), Has(words, @"volume's id cannot be read now, so MinMacs cannot say whether it is there")]);
    (void)MMRemovalRecoverStaged();
    [fm moveItemAtPath:inside toPath:e error:nil];
    [fm removeItemAtPath:folder error:nil];

    // B4. One part asks two names of one file, hard links. The first goes to the Trash and is named. MinMacs stops after
    // the second's list write. The second is not the first's, though its id is the same: it is listed, before and after
    // recovery, and the words name it in the Trash.
    NSString *a = [tree stringByAppendingPathComponent:@".env.a"], *b = [tree stringByAppendingPathComponent:@".env.b"];
    Write(a, @"LINKED=1");
    link(a.fileSystemRepresentation, b.fileSystemRepresentation);
    ino = MMFileIdentity(a)[@"ino"];
    rids = StopSecond(tree, a, b, @"after-list");
    NSString *wrap = rids.firstObject ?: @"";
    part = rids.count > 1 ? rids[1] : @"";
    NSString *aTo = MMRecordString(MMRecordList([MMUndo.shared record:part].payload, @"trashed").firstObject, @"to"), *bTo = nil;
    for (NSString *p in TrashedNamesByIno(ino)) if (![p isEqualToString:aTo]) bTo = p;
    MMRemovalWaitingItem *item = WaitingAt(bTo);
    T(@"trash links, two names of one file in one part, the second stopped after its list: --waiting lists the second at its Trash path, with its old path",
      [NSString stringWithFormat:@"1 in-trash %@ %@", bTo, b], [NSString stringWithFormat:@"%lu %@ %@ %@", (unsigned long)MMRecordList([MMUndo.shared record:part].payload, @"trashed").count,
                                                               WhyName(item), Or(item.stagedAt), Or(item.oldPath)]);
    Write(a, @"EDITOR SAVED");
    (void)MMRemovalRecoverStaged();
    words = [MMUndo.shared record:wrap].error ?: @"";
    T(@"trash links, and after a recovery that cannot put the first back: the words name the second in the Trash, and --waiting still lists it",
      @"yes in-trash yes", [NSString stringWithFormat:@"%@ %@ %@", Has(words, [NSString stringWithFormat:@"it is in the Trash at %@, where no record MinMacs can undo names it", bTo]),
                            WhyName(WaitingAt(bTo)), YN(Exists(bTo))]);
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}
