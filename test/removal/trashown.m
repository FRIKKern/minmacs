// Included by trashreview.m. Issue #113, third review: what a record names itself, at any Trash name, is its own; what a
// record that still runs has written in its Trash list counts as named; and the guards the second review found with no
// check get one. Every file is a fixture under <dir>, and the Trash is the test home's own, MMTrashFolder().

/// YES when the last HoldInTrash's MinMacs said it holds.
static BOOL gHeld;
/// A second MinMacs, this binary, sends path to the Trash for a part of a new Wrap Up of tree, as StopInTrash does, and
/// holds at point until *release is closed. Returns the task, and in *rids "<wrap up rid> <part rid>".
static NSTask *HoldInTrash(NSString *tree, NSString *path, NSString *point, NSFileHandle **release, NSArray<NSString *> **rids) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:gSelf];
    t.arguments = @[@"--stop-in-trash", tree, path];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"MINMACS_TEST_HOLD_TRASH"] = point;
    t.environment = env;
    NSPipe *out = [NSPipe pipe], *in = [NSPipe pipe];
    t.standardOutput = out; t.standardInput = in;
    *release = in.fileHandleForWriting;
    *rids = @[];
    if (![t launchAndReturnError:nil]) return nil;
    NSMutableString *said = [NSMutableString new];
    while (![said containsString:@"held\n"]) {
        NSData *d = out.fileHandleForReading.availableData;
        if (!d.length) break;
        [said appendString:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @""];
    }
    *rids = [[said componentsSeparatedByString:@"\n"].firstObject componentsSeparatedByString:@" "];
    gHeld = [said containsString:@"held\n"];
    return t;
}
static void Release(NSTask *t, NSFileHandle *release) { [release closeFile]; [t waitUntilExit]; }

static void TrashOwnNames(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashown"), *tree = [base stringByAppendingPathComponent:@"wt"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();

    // B3. A record that went through, whose item the person renamed in the Trash: it is that record's, wherever it lies.
    NSString *f = [tree stringByAppendingPathComponent:@".env.own"];
    Write(f, @"OWN=1");
    MMUndoRecord *r = TrashAlone(@"trash own, renamed in the Trash", f);
    NSString *at = TrashedTo(r), *renamed = [MMTrashFolder() stringByAppendingPathComponent:@"renamed by the person"];
    [fm moveItemAtPath:at toPath:renamed error:nil];
    T(@"trash own, a clean record whose item the person renamed in the Trash: --waiting does not list it", @"not listed not listed",
      [NSString stringWithFormat:@"%@ %@", WhyName(WaitingOfPart(r.rid)), WhyName(WaitingAt(renamed))]);
    [fm moveItemAtPath:renamed toPath:at error:nil];
    (void)[MMUndo.shared restore:r.rid];

    // B3. Put back by hand, another file takes the old Trash name, and the person trashes it again, as Finder names it
    // when the name is taken.
    NSString *g = [tree stringByAppendingPathComponent:@".env.again"];
    Write(g, @"AGAIN=1");
    MMUndoRecord *r2 = TrashAlone(@"trash own, trashed again by hand", g);
    NSString *at2 = TrashedTo(r2), *finder = [MMTrashFolder() stringByAppendingPathComponent:@".env.again 12.34.56"];
    [fm moveItemAtPath:at2 toPath:g error:nil];
    Write(at2, @"ANOTHER FILE");
    [fm moveItemAtPath:g toPath:finder error:nil];
    T(@"trash own, a clean record whose item was put back and trashed again under another name: --waiting does not list it", @"not listed not listed",
      [NSString stringWithFormat:@"%@ %@", WhyName(WaitingOfPart(r2.rid)), WhyName(WaitingAt(finder))]);
    [fm removeItemAtPath:at2 error:nil];
    [fm moveItemAtPath:finder toPath:g error:nil];

    // S3. A stopped Wrap Up A's list names the file. The person put it back. A running Wrap Up B sends it to the Trash
    // under the same name and has written its list, not yet its record. It is B's: not listed under A, nor under B.
    NSString *e = [tree stringByAppendingPathComponent:@".env.held"];
    Write(e, @"HELD=1");
    NSNumber *ino = MMFileIdentity(e)[@"ino"];
    NSArray<NSString *> *rids = [StopInTrash(tree, e, @"after-move").firstObject componentsSeparatedByString:@" "];
    NSString *aWrap = rids.firstObject ?: @"", *aPart = rids.count > 1 ? rids[1] : @"";
    at = TrashedByIno(ino);
    (void)MMRemovalRecoverStaged();
    [fm moveItemAtPath:at toPath:e error:nil];
    NSFileHandle *release = nil;
    NSTask *held = HoldInTrash(tree, e, @"after-list", &release, &rids);
    NSString *bWrap = rids.firstObject ?: @"", *bPart = rids.count > 1 ? rids[1] : @"";
    NSString *heldAt = TrashedByIno(ino);
    T(@"trash own, a Wrap Up still runs and has listed the file under the name a stopped one's list holds: --waiting lists it under neither, and the stopped one's words name nothing",
      [NSString stringWithFormat:@"yes 0 %@ not listed not listed nil", at], [NSString stringWithFormat:@"%@ %lu %@ %@ %@ %@", YN(gHeld),
       (unsigned long)MMRecordList([MMUndo.shared record:bPart].payload, @"trashed").count, Or(heldAt), WhyName(WaitingOfPart(aPart)), WhyName(WaitingOfPart(bPart)),
                                                                        Or(MMRemovalTrashStrandedWords(@[[MMUndo.shared record:aPart]]))]);
    Release(held, release);
    (void)MMRemovalRecoverStaged();
    T(@"trash own, once it ends its record names the file, and recovery of it brings the file back", @"1 HELD=1",
      [NSString stringWithFormat:@"%lu %@", (unsigned long)MMRecordList([MMUndo.shared record:bPart].payload, @"trashed").count, Read(e)]);
    (void)aWrap; (void)bWrap;

    // S4. Another record names its id at a Trash name it no longer has: that record cannot undo it, and the words say
    // only that no record MinMacs can undo names it there.
    ino = MMFileIdentity(e)[@"ino"];
    rids = [StopInTrash(tree, e, @"after-move").firstObject componentsSeparatedByString:@" "];
    NSString *sWrap = rids.firstObject ?: @"", *sPart = rids.count > 1 ? rids[1] : @"";
    at = TrashedByIno(ino);
    NSMutableDictionary *x = [MMFileIdentity(at) mutableCopy];
    x[@"from"] = e; x[@"to"] = [MMTrashFolder() stringByAppendingPathComponent:@".env.held renamed away"];
    MMUndoRecord *namer = Begin(@"trash", @"trash own, names its id at another Trash name");
    [MMUndo.shared note:namer payload:@{@"trashed": @[x]}];
    [MMUndo.shared finish:namer ok:NO freed:0 error:@"test"];
    MMRemovalWaitingItem *item = WaitingOfPart(sPart);
    (void)MMRemovalRecoverStaged();
    NSString *words = [MMUndo.shared record:sWrap].error ?: @"";
    T(@"trash own, another record names its id at another Trash name: it is listed, and --waiting and the words say no record MinMacs can undo names it there",
      @"in-trash is in the Trash where no record MinMacs can undo names it yes no", [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(item), item.whyWords,
                                                                                    Has(words, [at stringByAppendingString:@", where no record MinMacs can undo names it"]), Has(words, @"and no record names it")]);
    T(@"trash own, and a put-back of it through MinMacs says the same and moves nothing", @"yes yes",
      [NSString stringWithFormat:@"%@ %@", YN([MMRemovalPutBackWaitingWhyNot(item, nil) hasPrefix:@"no record MinMacs can undo names it where it lies"]), YN(Exists(at))]);
    [fm moveItemAtPath:at toPath:e error:nil];

    // S5, N2. A volume whose id cannot be read at the look: nothing is said gone, and the words say why.
    ino = MMFileIdentity(e)[@"ino"];
    rids = [StopInTrash(tree, e, @"after-list").firstObject componentsSeparatedByString:@" "];
    NSString *nPart = rids.count > 1 ? rids[1] : @"";
    at = TrashedByIno(ino);
    setenv("MINMACS_TEST_NO_VOLUME_UUID", "1", 1);
    words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:nPart]]) ?: @"";
    NSString *listed = WhyName(WaitingOfPart(nPart));
    unsetenv("MINMACS_TEST_NO_VOLUME_UUID");
    T(@"trash own, a volume id that cannot be read at the look: the words never say MinMacs finds it at neither place, nor that the Trash could not be read, and say the id cannot be read",
      @"no no yes not listed", [NSString stringWithFormat:@"%@ %@ %@ %@", Has(words, @"neither at its old path"), Has(words, @"the Trash could not be read"), Has(words, @"volume's id cannot be read"), listed]);
    (void)MMRemovalRecoverStaged();
    [fm moveItemAtPath:at toPath:e error:nil];

    // S5, N7. The list's Trash path lies in a folder in the Trash that refuses a look: the item is there, unseen.
    ino = MMFileIdentity(e)[@"ino"];
    rids = [StopInTrash(tree, e, @"after-list").firstObject componentsSeparatedByString:@" "];
    NSString *lPart = rids.count > 1 ? rids[1] : @"";
    at = TrashedByIno(ino);
    NSString *locked = [MMTrashFolder() stringByAppendingPathComponent:@"locked folder"], *inside = [locked stringByAppendingPathComponent:at.lastPathComponent];
    [fm createDirectoryAtPath:locked withIntermediateDirectories:YES attributes:nil error:nil];
    [fm moveItemAtPath:at toPath:inside error:nil];
    NSMutableDictionary *moved = [TrashListed(lPart).firstObject mutableCopy];
    moved[@"to"] = inside;
    [[NSJSONSerialization dataWithJSONObject:@{@"items": @[moved]} options:NSJSONWritingWithoutEscapingSlashes error:nil] writeToFile:TrashListOf(lPart) atomically:YES];
    chmod(locked.fileSystemRepresentation, 0);
    words = MMRemovalTrashStrandedWords(@[[MMUndo.shared record:lPart]]) ?: @"";
    chmod(locked.fileSystemRepresentation, 0700);
    T(@"trash own, the list's Trash path lies in a folder that refuses a look: the words never say MinMacs finds it at neither place, and say the Trash could not be read",
      @"no yes HELD=1", [NSString stringWithFormat:@"%@ %@ %@", Has(words, @"neither at its old path"), Has(words, @"the Trash could not be read"), Read(inside)]);
    (void)MMRemovalRecoverStaged();
    [fm moveItemAtPath:inside toPath:e error:nil];
    [fm removeItemAtPath:locked error:nil];

    // S5, M19. The lists' folder becomes a link between the list's read and its write, as a swap in a race would: no
    // list is written through it, and the item stays where it is.
    NSString *w = [tree stringByAppendingPathComponent:@".env.swap"];
    Write(w, @"SWAP=1");
    NSString *dir = TrashListOf(@"x").stringByDeletingLastPathComponent, *real = [base stringByAppendingPathComponent:@"lists-moved"];
    held = HoldInTrash(tree, w, @"list-write", &release, &rids);
    NSString *wPart = rids.count > 1 ? rids[1] : @"";
    [fm moveItemAtPath:dir toPath:real error:nil];
    symlink(real.fileSystemRepresentation, dir.fileSystemRepresentation);
    Release(held, release);
    BOOL through = Exists([real stringByAppendingPathComponent:[wPart stringByAppendingPathExtension:@"json"]]);
    [fm removeItemAtPath:dir error:nil];
    [fm moveItemAtPath:real toPath:dir error:nil];
    BOOL wasHeld = gHeld;
    T(@"trash own, the lists' folder turns into a link between the list's read and its write: nothing is written through it, and the item stays", @"yes no SWAP=1 0",
      [NSString stringWithFormat:@"%@ %@ %@ %lu", YN(wasHeld), YN(through), Read(w), (unsigned long)MMRecordList([MMUndo.shared record:wPart].payload, @"trashed").count]);
    (void)MMRemovalRecoverStaged();

    // S5, M6b. One read that never follows a link: a link to a pipe and a link to nothing are refused as links, so a
    // dangling link at a list's name never reads as "no list yet", which the next write would replace.
    NSString *fifo = [base stringByAppendingPathComponent:@"own.fifo"], *toFifo = [base stringByAppendingPathComponent:@"to-fifo"], *dangling = [base stringByAppendingPathComponent:@"dangling"];
    mkfifo(fifo.fileSystemRepresentation, 0600);
    symlink(fifo.fileSystemRepresentation, toFifo.fileSystemRepresentation);
    symlink([base stringByAppendingPathComponent:@"nothing here"].fileSystemRepresentation, dangling.fileSystemRepresentation);
    int w1 = 0, w2 = 0;
    NSData *d1 = MMReadOwnPlain(toFifo, 64, &w1), *d2 = MMReadOwnPlain(dangling, 64, &w2);
    T(@"own read: a link to a pipe and a link to nothing read as nothing, each as a link", @"nil yes nil yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@", d1 ? @"data" : @"nil", YN(w1 == ELOOP), d2 ? @"data" : @"nil", YN(w2 == ELOOP)]);
    [fm removeItemAtPath:toFifo error:nil]; [fm removeItemAtPath:dangling error:nil]; [fm removeItemAtPath:fifo error:nil];
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}

// Issue #113, fourth review.
#import "trashlinks.m"
