// Included by owner.m. The fourth review of #64: the very file still goes back when its volume came back under
// another device number, a record that cannot be read is never acted on, and a live pid that is not the owner does
// not keep a record for ever. Every file is a fixture under <dir>, inside $MINMACS_HOME.
#import "Core/Store/MMLog.h"

/// Writes the first entry of the part's list key again, changed by the block.
static MMUndoRecord *Rewrite(MMUndoRecord *part, NSString *key, void (^change)(NSMutableDictionary *entry)) {
    NSMutableDictionary *e = [[MMRecordList(part.payload, key) firstObject] mutableCopy];
    change(e);
    [MMUndo.shared note:part payload:@{key: @[e]}];
    return [MMUndo.shared record:part.rid];
}
/// Writes the record's body to the log again with one field of the body changed, as a broken record would be.
static void RewriteBody(MMUndoRecord *r, NSString *key, id value) {
    NSMutableDictionary *b = [[MMLog.shared history:r.rid].lastObject.body mutableCopy];
    b[key] = value;
    // The log's own columns take text, so a damaged kind or state lives in the body alone, as a broken body would.
    id (^text)(NSString *) = ^id(NSString *k) { return [b[k] isKindOfClass:NSString.class] ? b[k] : nil; };
    [MMLog.shared append:@"undo" rid:b[@"rid"] expert:text(@"expert") subject:text(@"subject") state:text(@"state") ?: @"pending" body:b];
}

/// A part whose parentRid is a number, staged on its own: no Wrap Up claims it.
static MMUndoRecord *OddParent(NSString *tree) {
    static MMUndoRecord *odd;
    if (odd) return [MMUndo.shared record:odd.rid];
    NSString *file = [tree stringByAppendingPathComponent:@"orphaned/.env"];
    Write(file, @"ODD=1");
    MMUndoRecord *p = Unfinished(@"parent of a part that loses it", tree, GoneOwner());
    odd = StageMany(p, @"a part whose parent is a number", @[file], YES);
    RewriteBody(odd, @"parentRid", @12);
    [MMUndo.shared finish:p ok:NO freed:0 error:@"test"];
    return [MMUndo.shared record:odd.rid];
}

static void Damaged(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"damaged/wt"), *plain = [tree stringByAppendingPathComponent:@".env"];
    Write(plain, @"PLAIN=1");

    // The one checked reader: a value of the wrong type reads as absent.
    NSDictionary *odd = @{@"s": @7, @"n": @"7", @"b": @YES, @"t": @1, @"d": @[], @"l": @{}, @"mixed": @[@{@"a": @1}, @"x", @2, NSNull.null], @"null": NSNull.null};
    T(@"reader: a wrong type reads as absent, a boolean is no number and a number is no boolean", @"nil nil nil no nil nil nil nil 1 1 no",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@ %lu %lu %@", Or(MMRecordString(odd, @"s")), Or(MMRecordNumber(odd, @"n").stringValue), Or(MMRecordNumber(odd, @"b").stringValue),
       YN(MMRecordFlag(odd, @"t")), Or(MMRecordDict(odd, @"d").description), Or(MMRecordList(odd, @"l").description), Or(MMRecordString(odd, @"null")), Or(MMRecordString(@"not a dictionary", @"s")),
       (unsigned long)MMRecordList(odd, @"mixed").count, (unsigned long)MMRecordStrings(odd, @"mixed").count, YN(MMRecordFlag(odd, @"null") || MMRecordFlag(nil, @"b"))]);
    T(@"reader: the right types read", @"x 7 yes 1 1", [NSString stringWithFormat:@"%@ %@ %@ %lu %lu", MMRecordString(@{@"s": @"x"}, @"s"), MMRecordNumber(@{@"n": @7}, @"n"), YN(MMRecordFlag(odd, @"b")),
      (unsigned long)MMRecordDict(@{@"d": @{@"a": @1}}, @"d").count, (unsigned long)MMRecordList(@{@"l": @[@{}]}, @"l").count]);

    // B1. Which file it is: its inode and its volume's UUID. The device number changes when a volume comes back.
    NSDictionary *me = MMFileIdentity(plain);
    T(@"identity: a file is named by its inode and its volume's UUID", @"yes yes 1", [NSString stringWithFormat:@"%@ %@ %d", YN([me[@"ino"] unsignedLongLongValue] > 0), YN([me[@"vol"] length] > 0), MMFileIsEntry(plain, me)]);
    NSMutableDictionary *moved = [me mutableCopy]; moved[@"dev"] = @([me[@"dev"] longLongValue] + 1);
    NSMutableDictionary *other = [me mutableCopy]; other[@"vol"] = @"00000000-0000-0000-0000-000000000000";
    NSMutableDictionary *older = [moved mutableCopy]; [older removeObjectForKey:@"vol"];
    NSMutableDictionary *wrong = [me mutableCopy]; wrong[@"ino"] = @([me[@"ino"] unsignedLongLongValue] + 1);
    T(@"identity: another device number is the same file, another volume or inode is not, and an entry with neither does not say", @"1 0 1 0 -1 -1 -1 0",
      [NSString stringWithFormat:@"%d %d %d %d %d %d %d %d", MMFileIsEntry(plain, moved), MMFileIsEntry(plain, other), MMFileIsEntry(plain, older), MMFileIsEntry(plain, wrong),
       MMFileIsEntry(plain, @{@"from": @"a", @"to": @"b"}), MMFileIsEntry(plain, @{@"ino": [me[@"ino"] stringValue], @"dev": [me[@"dev"] stringValue]}), MMFileIsEntry(plain, @{@"ino": me[@"ino"]}),
       MMFileIsEntry(Path(@"damaged/none"), me)]);
    MMUndoRecord *parent = Unfinished(@"volume came back", tree, nil);
    MMUndoRecord *part = StageMany(parent, @"config, device changed", @[plain], YES);
    T(@"staged: the entry holds the inode and the volume's UUID", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(MMRecordNumber(MMRecordList(part.payload, @"staged").firstObject, @"ino") != nil),
      YN(MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"vol").length > 0)]);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { e[@"dev"] = @([e[@"dev"] longLongValue] + 1); });
    T(@"put back: the very file still goes back when its volume has another device number", @"nil PLAIN=1 restored", [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[part])), Read(plain), StateWord(part)]);
    // An entry as one build wrote it: a device number and no UUID. Matched by its inode alone at that path.
    part = StageMany(parent, @"config, old entry", @[plain], YES);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { e[@"dev"] = @([e[@"dev"] longLongValue] + 1); [e removeObjectForKey:@"vol"]; });
    T(@"put back: an entry with a device number and no UUID goes back by its inode", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBack(@[part])), Read(plain)]);
    // The delete after the last part holds to the same rule.
    part = StageMany(parent, @"config, device changed, finished", @[plain], YES);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { e[@"dev"] = @([e[@"dev"] longLongValue] + 1); });
    (void)MMRemovalFinishStaged(@[part]);
    T(@"finish: the very file is still deleted when its volume has another device number", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(Exists(plain) || Exists(MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"to"))),
      YN([MMUndo.shared record:part.rid].deletedNow)]);
    // A hand-pressed Undo of a Trash removal, which is no part of a Wrap Up.
    Write(plain, @"PLAIN=1");
    MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalClutter, nil);
    MMUndoRecord *single = Begin(@"trash", @"a cache to the Trash");
    MMRemovalNote(single, keep, nil); MMRemovalAsk(single, @[plain]);
    MMRemovalApply(plain, keep, single, nil);
    MMRemovalDone(single, nil);
    single = Rewrite(Done(single), @"trashed", ^(NSMutableDictionary *e) { e[@"dev"] = @([e[@"dev"] longLongValue] + 1); });
    T(@"undo: a Trash removal still comes back when its volume has another device number", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or([MMUndo.shared restore:single.rid]), Read(plain)]);
    // Never weaker for the wrong file: another volume's UUID, or with the old entry another inode, is not taken.
    part = StageMany(parent, @"config, another volume", @[plain], YES);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { e[@"vol"] = @"00000000-0000-0000-0000-000000000000"; });
    NSString *to = MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"to");
    (void)MMRemovalFinishStaged(@[part]);
    T(@"put back: a file on a volume with another UUID is not taken for the item, and is not deleted either", @"yes no PLAIN=1", [NSString stringWithFormat:@"%@ %@ %@",
      YN([MMRemovalPutBack(@[part]) containsString:@"holds another file at"]), YN(Exists(plain)), Read(to)]);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { [e removeObjectForKey:@"vol"]; });
    [fm removeItemAtPath:to error:nil];
    Write(to, @"NOT THE ITEM");
    T(@"put back: with an entry that has no UUID, another file there is still not taken", @"yes no NOT THE ITEM", [NSString stringWithFormat:@"%@ %@ %@",
      YN([MMRemovalPutBack(@[part]) containsString:@"holds another file at"]), YN(Exists(plain)), Read(to)]);
    [fm removeItemAtPath:to error:nil];
    // An entry that does not say which file: never deleted, and never taken to be back.
    Write(plain, @"PLAIN=1");
    part = StageMany(parent, @"config, no identity", @[plain], YES);
    part = Rewrite(part, @"staged", ^(NSMutableDictionary *e) { [e removeObjectsForKeys:@[@"dev", @"ino", @"vol"]]; });
    to = MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"to");
    (void)MMRemovalFinishStaged(@[part]);
    T(@"finish: an entry that does not say which file was staged is not deleted", @"PLAIN=1 no", [NSString stringWithFormat:@"%@ %@", Read(to), YN([MMUndo.shared record:part.rid].deletedNow)]);
    [fm moveItemAtPath:to toPath:plain error:nil];
    T(@"put back: an entry that does not say which file is never taken to be back", @"yes done", [NSString stringWithFormat:@"%@ %@", YN([MMRemovalPutBack(@[part]) containsString:@"something else sits at"]), StateWord(part)]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // B3 and C2. With no start time in the record, a live pid whose process began after the record may have taken the
    // pid since, or the clock moved back while the owner ran. It is never read as gone at once: the age decides.
    parent = Unfinished(@"pid taken since", tree, nil);
    part = StageMany(parent, @"config, pid taken since", @[plain], YES);
    usleep(50000);
    pid_t child = fork();
    if (child == 0) { pause(); _exit(0); }
    usleep(50000);
    [MMUndo.shared note:parent payload:@{@"owner": @{@"pid": @(child), @"start": @0}}];
    parent = [MMUndo.shared record:parent.rid];
    int verdict = MMRemovalOwnerAlive(parent);
    NSInteger n = MMRemovalRecoverStaged();
    T(@"crash: with no start time, a live pid is kept when the record is only a little older than the process", @"-1 0 no pending",
      [NSString stringWithFormat:@"%d %ld %@ %@", verdict, (long)n, YN(Exists(plain)), StateWord(parent)]);
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    n = MMRemovalRecoverStaged();
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
    T(@"crash: and once the record is old its age settles it, so a pid taken since keeps nothing for ever", @"1 PLAIN=1 failed", [NSString stringWithFormat:@"%ld %@ %@", (long)n, Read(plain), StateWord(parent)]);
    kill(child, SIGKILL);
    int st; waitpid(child, &st, 0);
    // A process of another user, which answers EPERM, is no MinMacs of this person: the record's age decides.
    parent = Unfinished(@"pid of another user", tree, @{@"pid": @1, @"start": @0});
    part = StageMany(parent, @"config, pid 1", @[plain], YES);
    verdict = MMRemovalOwnerAlive(parent);
    NSInteger young = MMRemovalRecoverStaged();
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    NSInteger old = MMRemovalRecoverStaged();
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
    T(@"crash: a pid of another user does not keep the record for ever: its age decides", @"-1 0 1 PLAIN=1 failed", [NSString stringWithFormat:@"%d %ld %ld %@ %@", verdict, (long)young, (long)old, Read(plain), StateWord(parent)]);
    // C6. Read as a number, true would be pid 1, and with this start time the answer would be 0, gone.
    T(@"owner: a pid that is a boolean names no owner", @"-1 -1", [NSString stringWithFormat:@"%d %d", MMRemovalOwnerAlive(Unfinished(@"pid true", tree, @{@"pid": @YES, @"start": @1})),
      MMRemovalOwnerAlive(Unfinished(@"pid true, no start", tree, @{@"pid": @YES, @"start": @0}))]);
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    (void)MMRemovalRecoverStaged();
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");

    // B2, B5 and C1. A record that cannot be read: one Wrap Up per shape, its owner gone, one file staged. Nothing of
    // it is ever finished or deleted, nothing raises, its own record stays pending, and each is named once. A part
    // whose body and staged and trashed lists read still has its file put back. One whose do not is left as it is.
    // who is damaged, the field, what it holds, whether the deletes are said to have begun, and whether it is left
    NSArray<NSArray *> *shapes = @[
        @[@"part", @"staged", @"a string", @NO, @YES], @[@"part", @"staged", @7, @NO, @YES], @[@"part", @"staged", NSNull.null, @NO, @YES], @[@"part", @"staged", @{@"from": @"x"}, @NO, @YES],
        @[@"part", @"trashed", @"a string", @NO, @YES], @[@"part", @"trashed", @7, @NO, @YES], @[@"part", @"trashed", NSNull.null, @NO, @YES], @[@"part", @"trashed", @{@"from": @"x"}, @NO, @YES],
        @[@"part", @"bundle", @"a string", @NO, @NO], @[@"part", @"recovery", @"a string", @NO, @NO],
        @[@"part", @"deleted", @"a string", @YES, @NO], @[@"part", @"deleted", @{@"path": @"x"}, @YES, @NO], @[@"part", @"from", @7, @YES, @YES], @[@"part", @"ino", @"12", @YES, @YES],
        @[@"parent", @"finishing", @[@1], @NO, @NO], @[@"parent", @"finishing", @{@"a": @1}, @NO, @NO], @[@"parent", @"finishing", @"yes", @NO, @NO], @[@"parent", @"finishing", @1, @NO, @NO],
        @[@"part body", @"at", @[@1], @NO, @YES], @[@"part body", @"freedBytes", @[@1], @YES, @YES], @[@"parent body", @"at", @[@1], @NO, @NO], @[@"parent body", @"freedBytes", @"much", @NO, @NO],
        // C4: a kind, a state or a parent that is no text.
        @[@"parent body", @"kind", @7, @NO, @NO], @[@"parent body", @"state", @[@"pending"], @YES, @NO], @[@"part body", @"kind", @YES, @NO, @YES], @[@"part body", @"state", @2, @NO, @YES]];
    NSUInteger namedBefore = MMRemovalDamagedRecords().count;
    NSMutableArray<NSArray *> *made = [NSMutableArray new];
    for (NSUInteger i = 0; i < shapes.count; i++) {
        NSArray *shape = shapes[i];
        NSString *file = [tree stringByAppendingPathComponent:[NSString stringWithFormat:@"shape-%lu/.env", (unsigned long)i]];
        Write(file, @"KEEP=1");
        MMUndoRecord *p = Unfinished([NSString stringWithFormat:@"damaged %@ %@", shape[0], shape[1]], tree, GoneOwner());
        MMUndoRecord *x = StageMany(p, [NSString stringWithFormat:@"part of damaged %lu", (unsigned long)i], @[file], YES);
        NSString *waits = MMRecordString(MMRecordList(x.payload, @"staged").firstObject, @"to");
        if ([shape[3] boolValue]) [MMUndo.shared note:p payload:@{@"finishing": @YES}];
        NSString *who = shape[0], *key = shape[1];
        if ([key isEqualToString:@"from"] || [key isEqualToString:@"ino"]) x = Rewrite(x, @"staged", ^(NSMutableDictionary *e) { e[key] = shape[2]; });
        else if ([who isEqualToString:@"part"]) [MMUndo.shared note:x payload:@{key: shape[2]}];
        else if ([who isEqualToString:@"parent"]) [MMUndo.shared note:p payload:@{key: shape[2]}];
        else RewriteBody([who hasPrefix:@"part"] ? x : p, key, shape[2]);
        [made addObject:@[p, x, file, waits, [who hasPrefix:@"part"] ? x : p]];
    }
    NSInteger settled = MMRemovalRecoverStaged() + MMRemovalRecoverStaged();
    NSInteger swept = MMRemovalSweepStaged(NULL) + MMRemovalSweepStaged(NULL);
    NSMutableArray<NSString *> *bad = [NSMutableArray new];
    NSUInteger left = 0, back = 0;
    for (NSUInteger i = 0; i < made.count; i++) {
        MMUndoRecord *p = made[i][0], *x = made[i][1], *hurt = [MMUndo.shared record:[made[i][4] rid]];
        NSString *file = made[i][2], *waits = made[i][3];
        BOOL frozen = [shapes[i][4] boolValue];
        // Each act that could move or delete it, asked directly.
        (void)MMRemovalFinishStaged(@[x]);
        (void)hurt.canRestore;
        NSString *undo = [MMUndo.shared restore:hurt.rid];
        BOOL refused = [undo hasPrefix:@"its record is damaged, so MinMacs does not act on it: "] || [undo isEqualToString:@"the action has not finished"] ||
                       (!frozen && [undo isEqualToString:@"it was already restored"]);
        // Left: it still waits in the staging folder. Put back: it is at its old path, and nothing waits.
        BOOL where = frozen ? [Read(waits) isEqualToString:@"KEEP=1"] && !Exists(file) : [Read(file) isEqualToString:@"KEEP=1"] && !Exists(waits);
        BOOL safe = where && [StateWord(p) isEqualToString:@"pending"] && hurt.damage.length && refused &&
                    ![MMUndo.shared record:x.rid].deletedNow && !MMRecordList([MMUndo.shared record:x.rid].payload, @"deleted").count && [MMRemovalDamagedRecords() containsObject:hurt.rid];
        if (safe) { if (frozen) left++; else back++; }
        else [bad addObject:[NSString stringWithFormat:@"%@ %@ as %@: waits %@, old path %@, parent %@, damage %@, undo %@", shapes[i][0], shapes[i][1], [shapes[i][2] class], Read(waits), Read(file),
                             StateWord(p), hurt.damage, undo]];
    }
    T(@"damaged: no shape of a record that cannot be read stops recovery or the sweep, nothing of it is deleted, and its Wrap Up stays pending", @"0 0 ",
      [NSString stringWithFormat:@"%ld %ld %@", (long)settled, (long)swept, [bad componentsJoinedByString:@" | "]]);
    T(@"damaged: a part whose body and lists cannot be read is left where it waits, and one whose lists read is put back", @"14 12",
      [NSString stringWithFormat:@"%lu %lu", (unsigned long)left, (unsigned long)back]);
    T(@"damaged: each is named once", @(shapes.count).stringValue, @(MMRemovalDamagedRecords().count - namedBefore).stringValue);
    T(@"damaged: a kind, a state or a parent that is no text is damage, and says which", @"its kind is no text|its state is no text|its parent is no text", [@[
      Or([MMUndo.shared record:[made[22][0] rid]].damage), Or([MMUndo.shared record:[made[23][0] rid]].damage), Or(OddParent(tree).damage)] componentsJoinedByString:@"|"]);

    // C1. Only its deleted list is damaged, and the deletes had begun: put back all the same, and never deleted.
    for (NSNumber *finishing in @[@NO, @YES]) {
        Write(plain, @"PLAIN=1");
        parent = Unfinished(@"part with a damaged deleted list", tree, GoneOwner());
        part = StageMany(parent, @"config, deleted list damaged", @[plain], YES);
        if (finishing.boolValue) [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
        [MMUndo.shared note:part payload:@{@"deleted": @"not a list"}];
        to = MMRecordString(MMRecordList(part.payload, @"staged").firstObject, @"to");
        n = MMRemovalRecoverStaged();
        T([NSString stringWithFormat:@"damaged: a part whose staged list reads fine is still put back when only its deleted list is damaged%@", finishing.boolValue ? @", also once the deletes had begun" : @""],
          @"0 PLAIN=1 no restored pending yes", [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@", (long)n, Read(plain), YN(Exists(to)), StateWord(part), StateWord(parent),
          YN([MMRemovalDamagedRecords() containsObject:part.rid])]);
    }
    // A record that can be read, beside all of these, is still settled.
    parent = Unfinished(@"fine, beside the damaged ones", tree, GoneOwner());
    part = StageMany(parent, @"config of a fine one", @[plain], YES);
    T(@"damaged: a Wrap Up that can be read is still settled beside them", @"1 PLAIN=1 failed", [NSString stringWithFormat:@"%ld %@ %@", (long)MMRemovalRecoverStaged(), Read(plain), StateWord(parent)]);
    // B5. Only a true yes counts as "the deletes had begun": the number 1 and the word yes were in the table above.
    parent = Unfinished(@"finishing, truly", tree, GoneOwner());
    part = StageMany(parent, @"config, finishing", @[plain], YES);
    [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
    T(@"crash while finishing: a true yes, as MinMacs writes it, still finishes the delete", @"1 no done", [NSString stringWithFormat:@"%ld %@ %@", (long)MMRemovalRecoverStaged(), YN(Exists(plain)), StateWord(parent)]);
}

// Issue #67: what a done Wrap Up left staged, and what still waits.
#import "waiting.m"
