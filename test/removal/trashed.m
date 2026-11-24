// Included by pipes.m. Issue #74: a record that names a file of the person's own in the Trash, with that file's true
// inode and volume, never makes MinMacs move it out. Only what MinMacs's own list of what it sent to the Trash names,
// written before the move, goes back: in the start's sweep, in recovery, in the person's put-back and in an Undo.
// Every file is a fixture under <dir>, and the Trash is the test home's own, MMTrashFolder(): never the person's.

/// The list MinMacs keeps of what record rid sent to the Trash, as the file it lives in.
static NSString *TrashListOf(NSString *rid) { return [[MMExpertDir(@"core") stringByAppendingPathComponent:@"trashed"] stringByAppendingPathComponent:[rid stringByAppendingPathExtension:@"json"]]; }

/// A record of its own that sends path to the test home's Trash, as under the Trash choice. Returns it done.
static MMUndoRecord *TrashAlone(NSString *subject, NSString *path) {
    MMRemovalDecision *keep = MMRemovalDecide(MMRemovalClutter, nil, nil);
    MMUndoRecord *r = Begin(@"trash", subject);
    MMRemovalNote(r, keep, nil);
    MMRemovalAsk(r, @[path]);
    MMRemovalApply(path, keep, r, nil);
    MMRemovalDone(r, nil);
    return Done(r);
}
/// The entries that list holds, or none.
static NSArray<NSDictionary *> *TrashListed(NSString *rid) {
    NSData *d = [NSData dataWithContentsOfFile:TrashListOf(rid)];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return MMRecordList(j, @"items") ?: @[];
}
static NSString *TrashedTo(MMUndoRecord *r) { return MMRecordString(MMRecordList([MMUndo.shared record:r.rid].payload, @"trashed").firstObject, @"to"); }

static void TrashedByMinMacs(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"trashed"), *tree = [base stringByAppendingPathComponent:@"wt"], *plain = [tree stringByAppendingPathComponent:@".env"];
    // A file the person put in the Trash themselves, and a free path a forged record would have it moved to.
    NSString *mine = [MMTrashFolder() stringByAppendingPathComponent:@"person-thesis.txt"], *free = [base stringByAppendingPathComponent:@"elsewhere/thesis.txt"];
    void (^fresh)(void) = ^{ Write(mine, @"PERSON TRASHED THIS"); [fm removeItemAtPath:free.stringByDeletingLastPathComponent error:nil]; };
    NSString *(^still)(void) = ^NSString *{ return [NSString stringWithFormat:@"%@ %@", Read(mine), YN(Exists(free))]; };
    NSString *why = @"stays where it is: MinMacs's own list of what it sent to the Trash does not name it, so MinMacs does not move it";
    MMUndoRecord *parent = nil, *part = nil;
    fresh();

    // 1. The start's sweep: a failed Wrap Up whose part truly staged an item, and whose record also names the person's
    // Trash file with its true inode and volume. The staged item goes back, and the Trash file stays.
    part = FailedWithPart(@"trash forged, the sweep", tree, plain, &parent);
    [MMUndo.shared note:part payload:@{@"trashed": @[ForgedEntry(mine, mine, free)], @"removal": @{@"choice": @"trash"}}];
    (void)MMRemovalRecoverStaged(); (void)MMRemovalSweepStaged(NULL);
    T(@"trash forged: the start's sweep never moves a Trash file MinMacs did not send there, and the staged item still goes back", @"PERSON TRASHED THIS no PLAIN=1",
      [NSString stringWithFormat:@"%@ %@", still(), Read(plain)]);
    Forget(part);
    fresh();

    // 2. Recovery after a crash: a Wrap Up whose process is gone, with a part that names the Trash file.
    parent = Unfinished(@"trash forged, recovery", tree, GoneOwner());
    part = Done(Part(parent.rid, @"trash forged, recovery, part"));
    [MMUndo.shared note:part payload:@{@"trashed": @[ForgedEntry(mine, mine, free)], @"removal": @{@"choice": @"trash"}}];
    (void)MMRemovalRecoverStaged();
    NSString *error = [MMUndo.shared record:parent.rid].error ?: @"";
    T(@"trash forged: nor does recovery, and its words name the Trash path and say why", @"PERSON TRASHED THIS no failed yes",
      [NSString stringWithFormat:@"%@ %@ %@", still(), StateWord(parent), YN([error containsString:[NSString stringWithFormat:@"%@ %@", mine, why]])]);
    Forget(part);
    fresh();

    // 3. The person's put-back of a waiting item: a Trash file is never one, by any id.
    parent = Unfinished(@"trash forged, put-back", tree, GoneOwner());
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    part = Done(Part(parent.rid, @"trash forged, put-back, part"));
    [MMUndo.shared note:part payload:@{@"trashed": @[ForgedEntry(mine, mine, free)], @"removal": @{@"choice": @"trash"}}];
    NSString *byId = MMRemovalPutBackWaiting([NSString stringWithFormat:@"%@:%@", part.rid, mine], free);
    NSString *byItem = MMRemovalPutBackStagedItem(part, mine, free);
    T(@"trash forged: --waiting --put-back neither lists it nor moves it", @"not listed yes yes PERSON TRASHED THIS no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(WaitingAt(mine)), YN(byId != nil), YN(byItem != nil), still()]);
    Forget(part);
    fresh();

    // 4. The person's Undo of a record that names it, on its own and as a part of a Wrap Up.
    MMUndoRecord *alone = Done(Begin(@"trash", @"trash forged, an Undo"));
    [MMUndo.shared note:alone payload:@{@"trashed": @[ForgedEntry(mine, mine, free)]}];
    NSString *said = [MMUndo.shared restore:alone.rid];
    T(@"trash forged: an Undo does not move it, says why with its Trash path, and the record is not called restored", @"PERSON TRASHED THIS no yes done",
      [NSString stringWithFormat:@"%@ %@ %@", still(), YN([said containsString:[NSString stringWithFormat:@"%@ %@", mine, why]]), StateWord(alone)]);
    Forget(alone);
    fresh();
    parent = Unfinished(@"trash forged, an Undo of the Wrap Up", tree, nil);
    part = Done(Part(parent.rid, @"trash forged, an Undo of the Wrap Up, part"));
    [MMUndo.shared note:part payload:@{@"trashed": @[ForgedEntry(mine, mine, free)], @"removal": @{@"choice": @"trash"}}];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    said = [MMUndo.shared restore:parent.rid];
    T(@"trash forged: nor an Undo of its Wrap Up", @"PERSON TRASHED THIS no yes", [NSString stringWithFormat:@"%@ %@", still(), YN(said != nil)]);
    Forget(part);
    fresh();

    // 5. A forged entry in a record MinMacs truly wrote, beside its true one, with another old path: the list names
    // what this record sent there and from where, so the Undo refuses, and nothing moves.
    NSString *cache = [base stringByAppendingPathComponent:@"cache/a.bin"];
    Write(cache, @"CACHE");
    MMUndoRecord *honest = TrashAlone(@"trash honest, with a forged entry beside", cache.stringByDeletingLastPathComponent);
    NSString *at = TrashedTo(honest);
    NSDictionary *trueEntry = MMRecordList(honest.payload, @"trashed").firstObject;
    [MMUndo.shared note:honest payload:@{@"trashed": @[trueEntry, ForgedEntry(mine, mine, free), ForgedEntry(at, at, free)]}];
    said = [MMUndo.shared restore:honest.rid];
    T(@"trash forged: beside a true entry, nor one that names the true item with another old path", @"PERSON TRASHED THIS no yes yes no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", still(), YN([said containsString:[NSString stringWithFormat:@"%@ %@", mine, why]]), YN(Exists(at)), YN(Exists(cache))]);
    [MMUndo.shared note:[MMUndo.shared record:honest.rid] payload:@{@"trashed": @[trueEntry]}];

    // 6. The honest case: what MinMacs sent to the Trash itself, its list written before the move, comes back.
    NSDictionary *listed = TrashListed(honest.rid).firstObject;
    T(@"trash honest: MinMacs's own list names what it sent to the Trash, with its old path, its Trash path and its id there", @"1 yes yes yes",
      [NSString stringWithFormat:@"%lu %@ %@ %@", (unsigned long)TrashListed(honest.rid).count, YN([MMRecordString(listed, @"from") isEqualToString:cache.stringByDeletingLastPathComponent]),
       YN([MMRecordString(listed, @"to") isEqualToString:at]), YN([MMRecordNumber(listed, @"ino") isEqual:MMRecordNumber(trueEntry, @"ino")])]);
    T(@"trash honest: an Undo brings it back", @"nil CACHE no restored", [NSString stringWithFormat:@"%@ %@ %@ %@", Or([MMUndo.shared restore:honest.rid]), Read(cache), YN(Exists(at)), StateWord(honest)]);
    // The person trashes it again themselves, the same file at the same Trash path, and the record is written as done
    // again. MinMacs took it back once, so its list names it no more, and it stays.
    [fm moveItemAtPath:cache.stringByDeletingLastPathComponent toPath:at error:nil];
    RewriteBody(honest, @"state", @"done");
    said = [MMUndo.shared restore:honest.rid];
    T(@"trash honest: once it went back, a record written again never takes the same file out of the Trash a second time", @"yes yes no",
      [NSString stringWithFormat:@"%@ %@ %@", YN(Exists(at)), YN([said containsString:why]), YN(Exists(cache))]);
    [fm moveItemAtPath:at toPath:cache.stringByDeletingLastPathComponent error:nil];

    // The same as a Wrap Up's part: its process is gone, and recovery moves it back.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"trash honest, recovery", tree, GoneOwner());
    part = TrashOne(parent, @"trash honest, recovery, part", plain);
    (void)MMRemovalRecoverStaged();
    T(@"trash honest: recovery moves back what a Wrap Up's part sent to the Trash", @"PLAIN=1 restored failed no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Read(plain), StateWord(part), StateWord(parent), YN([[MMUndo.shared record:parent.rid].error containsString:@", except: "])]);

    // 7. A record from before this list: MinMacs truly sent the file there, but nothing of its own says so now. It stays
    // in the Trash, and the Undo says where it is and why, so the person can put it back from the Trash themselves.
    Write(cache, @"CACHE");
    MMUndoRecord *older = TrashAlone(@"trash, a record from before the list", cache.stringByDeletingLastPathComponent);
    at = TrashedTo(older);
    [fm removeItemAtPath:TrashListOf(older.rid) error:nil];
    said = [MMUndo.shared restore:older.rid];
    T(@"trash, before the list: the item stays in the Trash and the Undo names its Trash path and why", @"yes no yes done",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(Exists(at)), YN(Exists(cache)), YN([said isEqualToString:[NSString stringWithFormat:@"%@ %@", at, why]]), StateWord(older)]);
    // A list that is a link to a file elsewhere is not MinMacs's own, whatever that file says.
    NSString *elsewhere = [base stringByAppendingPathComponent:@"list-elsewhere.json"];
    Write(elsewhere, [NSString stringWithFormat:@"{\"items\":[{\"from\":\"%@\",\"to\":\"%@\",\"ino\":%@,\"dev\":%@%@}]}", cache.stringByDeletingLastPathComponent, at,
                      MMFileIdentity(at)[@"ino"], MMFileIdentity(at)[@"dev"], MMFileIdentity(at)[@"vol"] ? [NSString stringWithFormat:@",\"vol\":\"%@\"", MMFileIdentity(at)[@"vol"]] : @""]);
    symlink(elsewhere.fileSystemRepresentation, TrashListOf(older.rid).fileSystemRepresentation);
    said = [MMUndo.shared restore:older.rid];
    T(@"trash, a linked list: a list that is a link is not MinMacs's own, and the item stays", @"yes no yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN(Exists(at)), YN(Exists(cache)), YN([said containsString:why])]);
    [fm removeItemAtPath:TrashListOf(older.rid) error:nil];
    [fm removeItemAtPath:at error:nil];

    // 8. When the list cannot be written, as when a folder holds its name, nothing goes to the Trash: the item stays.
    Write(cache, @"CACHE");
    MMUndoRecord *blocked = Begin(@"trash", @"trash, the list cannot be written");
    [fm createDirectoryAtPath:TrashListOf(blocked.rid) withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger inTrash = [fm contentsOfDirectoryAtPath:MMTrashFolder() error:nil].count;
    NSError *e = nil;
    BOOL went = MMRemovalApply(cache.stringByDeletingLastPathComponent, MMRemovalDecide(MMRemovalClutter, nil, nil), blocked, &e);
    T(@"trash, no list: when MinMacs cannot write its own list the item stays where it is, and the words say why", @"no CACHE 0 0 MinMacs could not write its own list of what it sends to the Trash, so the item stays where it is",
      [NSString stringWithFormat:@"%@ %@ %lu %lu %@", YN(went), Read(cache), (unsigned long)MMRecordList([MMUndo.shared record:blocked.rid].payload, @"trashed").count,
       (unsigned long)([fm contentsOfDirectoryAtPath:MMTrashFolder() error:nil].count - inTrash), e.localizedDescription]);
    [fm removeItemAtPath:TrashListOf(blocked.rid) error:nil];
    [MMUndo.shared finish:blocked ok:NO freed:0 error:@"test"];
    [fm removeItemAtPath:mine error:nil];
}

// Issue #113: a stop between the move to the Trash and the record.
#import "trashstop.m"
