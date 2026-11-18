// Included by unasked.m. Issue #75: MinMacs stops between the rename into the staging folder and the write of the
// part's record. The staging folder's own list, .minmacs-items, already names the item then, so recovery, the sweep
// and the waiting list find it from the folder alone, and the Wrap Up's words never say it went back when it did not.
// Every file is a fixture under <dir>, inside $MINMACS_HOME.

static NSString *gSelf;

/// A second MinMacs, this binary, stages path for a new Wrap Up of tree and stops right after the rename, as a crash
/// would. Returns its lines: "<wrap up rid> <part rid>", and "went on" when it did not stop.
static NSArray<NSString *> *StopAfterRename(NSString *tree, NSString *path) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:gSelf];
    t.arguments = @[@"--stop-after-rename", tree, path];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"MINMACS_TEST_STOP_AFTER_RENAME"] = @"1";
    t.environment = env;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    if (![t launchAndReturnError:nil]) return @[];
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [s componentsSeparatedByString:@"\n"];
}
/// The other side: run as `removaltest --stop-after-rename <tree> <path>`.
static int StopAfterRenameChild(NSString *tree, NSString *path) {
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *parent = Unfinished(@"stopped after the rename", tree, MMRemovalOwner());
    MMUndoRecord *part = Part(parent.rid, @"config, stopped after the rename");
    MMRemovalNote(part, del, nil); MMRemovalAsk(part, @[path]);
    printf("%s %s\n", parent.rid.UTF8String, part.rid.UTF8String);
    fflush(stdout);
    MMRemovalApply(path, del, part, nil);
    printf("went on\n");
    return 0;
}
static NSString *StagedFolderOf(NSString *rid) { return [StagedRoot() stringByAppendingPathComponent:rid]; }
static NSDictionary *ListOfFolder(NSString *folder) {
    NSData *d = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@".minmacs-items"]];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : @{};
}
/// The one name the folder's list holds, or "(none)".
static NSString *ListedName(NSString *folder) { return [ListOfFolder(folder).allKeys firstObject] ?: @"(none)"; }
static MMRemovalWaitingItem *WaitingOfPart(NSString *partRid) {
    for (MMRemovalWaitingItem *i in MMRemovalWaiting()) if ([i.partRid isEqualToString:partRid]) return i;
    return nil;
}
/// The part's record as it would be had MinMacs stopped before it wrote what it staged: no "staged", no "stagedIn".
static void ForgetStaged(MMUndoRecord *part) {
    NSMutableDictionary *p = [[MMUndo.shared record:part.rid].payload mutableCopy];
    [p removeObjectsForKeys:@[@"staged", @"stagedIn"]];
    RewriteBody([MMUndo.shared record:part.rid], @"payload", p);
}

static void Stopped(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"stopped/wt"), *env = [tree stringByAppendingPathComponent:@".env.local"];
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();

    // 1. A real stop: a second MinMacs stops right after the rename. The folder's list names the item already, and
    // the part's record does not.
    Write(env, @"KEEP=1");
    NSArray<NSString *> *said = StopAfterRename(tree, env);
    NSArray<NSString *> *rids = [said.firstObject componentsSeparatedByString:@" "];
    NSString *wrap = rids.firstObject, *partRid = rids.count > 1 ? rids[1] : @"";
    NSString *folder = StagedFolderOf(wrap);
    T(@"stopped: at the stop the item is in the staging folder, its folder's list names it with its old path, and its record does not",
      [NSString stringWithFormat:@"1 no %@ 0", env],
      [NSString stringWithFormat:@"%lu %@ %@ %lu", (unsigned long)said.count, YN(Exists(env)), MMRecordString(MMRecordDict(ListOfFolder(folder), ListedName(folder)), @"from") ?: @"(none)",
       (unsigned long)MMRecordList([MMUndo.shared record:partRid].payload, @"staged").count]);
    (void)MMRemovalRecoverStaged();
    MMUndoRecord *parent = [MMUndo.shared record:wrap];
    T(@"stopped: at the next start it goes back to its old path, its folder goes, and the Wrap Up's words say so",
      @"KEEP=1 no failed MinMacs stopped before this Wrap Up ended. What it had moved out of the worktree was put back restored",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Read(env), YN(Exists(folder)), StateWord(parent), parent.error, StateWord([MMUndo.shared record:partRid])]);

    // 2. The same stop with its old path taken by then: it waits, the words say it did not go back, and --waiting
    // lists it with its old path. The person puts it back.
    said = StopAfterRename(tree, env);
    rids = [said.firstObject componentsSeparatedByString:@" "];
    wrap = rids.firstObject; partRid = rids.count > 1 ? rids[1] : @"";
    folder = StagedFolderOf(wrap);
    NSString *stagedAt = [folder stringByAppendingPathComponent:ListedName(folder)];
    Write(env, @"NEWER=1");
    (void)MMRemovalRecoverStaged();
    parent = [MMUndo.shared record:wrap];
    T(@"stopped, old path taken: nothing is written over, and the Wrap Up's words do not say it went back",
      @"NEWER=1 KEEP=1 failed yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Read(env), Read(stagedAt), StateWord(parent), YN([parent.error containsString:@", except: "]),
       YN([parent.error containsString:@"something already exists at"])]);
    MMRemovalWaitingItem *item = WaitingOfPart(partRid);
    T(@"stopped, old path taken: removal --waiting lists it with its old path, and offers both ways out",
      [NSString stringWithFormat:@"old-path-taken .env.local %@ %@ yes yes", env, stagedAt],
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", WhyName(item), item.name, item.oldPath, item.stagedAt, YN(item.canPutBack), YN(item.canDelete)]);
    [fm removeItemAtPath:env error:nil];
    T(@"stopped, old path taken: once the old path is free, the person's put-back brings it back, and nothing waits",
      @"nil KEEP=1 no not listed",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalPutBackWaiting(item.itemID, nil)), Read(env), YN(Exists(folder)), WhyName(WaitingOfPart(partRid))]);

    // 3. The record never named it and its Wrap Up ended: nobody ran recovery for it. --waiting finds it from the
    // folder alone, read only, and the sweep puts it back.
    MMUndoRecord *wrapUp = Unfinished(@"ended, record never named it", tree, nil);
    MMUndoRecord *part = StageMany(wrapUp, @"config the record forgot", @[env], YES);
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    ForgetStaged(part);
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
    Write(env, @"NEWER=1");
    item = WaitingOfPart(part.rid);
    T(@"forgotten: --waiting lists it from its staging folder's own list, with its old path, and writes nothing",
      [NSString stringWithFormat:@"old-path-taken %@ %@ 0", env, stagedAt],
      [NSString stringWithFormat:@"%@ %@ %@ %lu", WhyName(item), item.oldPath, item.stagedAt, (unsigned long)MMRecordList([MMUndo.shared record:part.rid].payload, @"staged").count]);
    (void)MMRemovalSweepStaged(NULL);
    T(@"forgotten: the sweep leaves it while its old path is taken, and names it in the record", @"NEWER=1 KEEP=1 1",
      [NSString stringWithFormat:@"%@ %@ %lu", Read(env), Read(stagedAt), (unsigned long)MMRecordList([MMUndo.shared record:part.rid].payload, @"staged").count]);
    [fm removeItemAtPath:env error:nil];
    (void)MMRemovalSweepStaged(NULL);
    T(@"forgotten: once its old path is free, the sweep puts it back and its folder goes", @"KEEP=1 no restored",
      [NSString stringWithFormat:@"%@ %@ %@", Read(env), YN(Exists(folder)), StateWord(part)]);

    // 4. The person deletes one the record never named, through the same check, and only that file.
    wrapUp = Unfinished(@"ended, delete one the record never named", tree, nil);
    part = StageMany(wrapUp, @"config to delete", @[env], YES);
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    ForgetStaged(part);
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
    Write(env, @"NEWER=1");
    item = WaitingOfPart(part.rid);
    T(@"forgotten: the person deletes it, and the file at its old path stays", @"nil no NEWER=1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalDeleteWaiting(item.itemID, NULL)), YN(Exists(stagedAt)), Read(env), YN(Exists(folder))]);

    // 5. Another file under the listed name is not the one MinMacs staged: it is never moved or deleted.
    [fm removeItemAtPath:env error:nil];
    Write(env, @"KEEP=1");
    wrapUp = Unfinished(@"ended, swapped in the folder", tree, nil);
    part = StageMany(wrapUp, @"config swapped", @[env], YES);
    stagedAt = StagedTo(part); folder = part.payload[@"stagedIn"];
    ForgetStaged(part);
    [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
    [fm removeItemAtPath:stagedAt error:nil];
    Write(stagedAt, @"OTHER=1");
    (void)MMRemovalSweepStaged(NULL);
    item = WaitingOfPart(part.rid);
    T(@"forgotten, swapped: the sweep moves nothing, and --waiting offers no way out", @"OTHER=1 no no no it is not the file that was staged",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Read(stagedAt), YN(Exists(env)), YN(item.canPutBack), YN(item.canDelete), Or(item.detail)]);
    T(@"forgotten, swapped: a delete of it is refused", @"yes OTHER=1",
      [NSString stringWithFormat:@"%@ %@", YN(MMRemovalDeleteWaiting(item.itemID, NULL) != nil), Read(stagedAt)]);
    [fm removeItemAtPath:stagedAt error:nil];
    MMRemovalDropEmptyStagingFolder(folder, wrapUp.rid);

    // 6. A file in the staging folder that no list and no record names, as a build before #75 could leave: recovery
    // never says everything went back.
    Write(env, @"KEEP=1");
    said = StopAfterRename(tree, env);
    rids = [said.firstObject componentsSeparatedByString:@" "];
    wrap = rids.firstObject;
    folder = StagedFolderOf(wrap);
    NSString *unnamed = [folder stringByAppendingPathComponent:@"7.notes.txt"];
    Write(unnamed, @"WHOSE?");
    (void)MMRemovalRecoverStaged();
    parent = [MMUndo.shared record:wrap];
    T(@"stopped, an unnamed file waits: the named item goes back, the unnamed one stays, and the words name it",
      [NSString stringWithFormat:@"KEEP=1 WHOSE? yes yes"],
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(env), Read(unnamed), YN([parent.error containsString:@", except: "]), YN([parent.error containsString:unnamed])]);
    [fm removeItemAtPath:unnamed error:nil];
    MMRemovalDropEmptyStagingFolder(folder, wrap);
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
}
