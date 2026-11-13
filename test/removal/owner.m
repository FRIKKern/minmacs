// Included by stranded.m. The third review of #64: an owner that cannot be read, a damaged record, and a file that
// only sits where the item waited. Every file is a fixture under <dir>, inside $MINMACS_HOME.

/// A part of parent that sends the file at path to the test home's Trash, as under the Trash choice.
static MMUndoRecord *TrashOne(MMUndoRecord *parent, NSString *subject, NSString *path) {
    MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalConfigFiles, nil);
    MMUndoRecord *part = Part(parent.rid, subject);
    MMRemovalNote(part, keep, nil);
    MMRemovalAsk(part, @[path]);
    MMRemovalApply(path, keep, part, nil);
    MMRemovalDone(part, nil);
    return Done(part);
}

static void Owners(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = Path(@"owners/wt"), *plain = [tree stringByAppendingPathComponent:@".env"];
    Write(plain, @"PLAIN=1");
    NSNumber *me = MMRemovalOwner()[@"pid"];

    // S1. A start time that could not be read says nothing about the owner. While its pid lives, the record is left.
    NSMutableArray *got = [NSMutableArray new];
    for (NSDictionary *owner in @[@{@"pid": me, @"start": @0}, @{@"pid": me}]) {
        MMUndoRecord *parent = Unfinished(@"start unread", tree, owner);
        MMUndoRecord *part = StageMany(parent, @"config, start unread", @[plain], YES);
        NSInteger n = MMRemovalRecoverStaged();
        [got addObject:[NSString stringWithFormat:@"%ld %@ %@", (long)n, YN(Exists(plain)), StateWord(parent)]];
        // Not even when the deletes had begun: the owner still runs them.
        [MMUndo.shared note:parent payload:@{@"finishing": @YES}];
        n = MMRemovalRecoverStaged();
        [got addObject:[NSString stringWithFormat:@"%ld %@ %@", (long)n, YN(Exists([part.payload[@"staged"] firstObject][@"to"])), StateWord(parent)]];
        [MMUndo.shared note:parent payload:@{@"finishing": @NO}];
        (void)MMRemovalPutBack(@[part]);
        [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    }
    T(@"crash: an owner whose start time could not be read is left alone while its pid lives", @"0 no pending|0 yes pending|0 no pending|0 yes pending", [got componentsJoinedByString:@"|"]);
    NSMutableDictionary *gone = [GoneOwner() mutableCopy];
    gone[@"start"] = @0;
    MMUndoRecord *parent = Unfinished(@"start unread, pid gone", tree, gone);
    MMUndoRecord *part = StageMany(parent, @"config, pid gone", @[plain], YES);
    T(@"crash: with no start time and a pid that is gone, it is settled at once", @"1 PLAIN=1 failed", [NSString stringWithFormat:@"%ld %@ %@", (long)MMRemovalRecoverStaged(), Read(plain), StateWord(parent)]);

    // L1. A damaged owner counts as no owner, so the age decides, and recovery goes on.
    NSArray *damaged = @[@{@"owner": NSNull.null}, @{@"owner": @"me"}, @{@"owner": @[@1]}, @{@"owner": @{@"pid": NSNull.null}}, @{@"owner": @{@"pid": @"12"}},
                         @{@"owner": @{@"pid": me, @"start": NSNull.null}}, @{@"owner": @{@"pid": me, @"start": @"soon"}}, @{@"owner": @{@"pid": me, @"start": @[@1]}}];
    NSMutableArray<MMUndoRecord *> *parents = [NSMutableArray new];
    for (NSDictionary *d in damaged) {
        MMUndoRecord *p = Begin(@"wrapup", @"damaged owner");
        NSMutableDictionary *payload = [d mutableCopy];
        payload[@"path"] = tree;
        [MMUndo.shared note:p payload:payload];
        [parents addObject:p];
    }
    // And a part whose staged entry is damaged too, in a Wrap Up of its own that ended.
    MMUndoRecord *oddParent = Unfinished(@"ended, with a damaged part", tree, nil);
    [MMUndo.shared finish:oddParent ok:NO freed:0 error:@"test"];
    MMUndoRecord *odd = Part(oddParent.rid, @"damaged entry");
    MMRemovalNote(odd, MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil), nil);
    [MMUndo.shared note:odd payload:@{@"stagedIn": @7, @"staged": @[@{@"from": plain, @"to": @[], @"dev": @"x", @"ino": NSNull.null}, @"not an entry", @{@"from": @3}]}];
    odd = Done(odd);
    NSInteger young = MMRemovalRecoverStaged();
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    NSInteger old = MMRemovalRecoverStaged();
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
    NSMutableSet *states = [NSMutableSet new];
    for (MMUndoRecord *p in parents) [states addObject:StateWord(p)];
    T(@"crash: a damaged owner field does not stop recovery", [NSString stringWithFormat:@"0 %lu failed PLAIN=1", (unsigned long)damaged.count],
      [NSString stringWithFormat:@"%ld %ld %@ %@", (long)young, (long)old, [states.allObjects componentsJoinedByString:@","], Read(plain)]);
    (void)MMRemovalFinishStaged(@[odd]);
    T(@"crash: a damaged staged entry stops neither the finish nor the sweep", @"yes PLAIN=1", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalSweepStaged(NULL) >= 0), Read(plain)]);

    // S2. The Trash was emptied and another file of the same name was trashed since. That one is the person's.
    parent = Unfinished(@"trash swapped", tree, GoneOwner());
    part = TrashOne(parent, @"config to the Trash", plain);
    NSString *inTrash = [part.payload[@"trashed"] firstObject][@"to"];
    T(@"trash: the record knows the very file it put in the Trash", @"yes", YN([[part.payload[@"trashed"] firstObject][@"ino"] unsignedLongLongValue] > 0));
    [fm removeItemAtPath:inTrash error:nil];
    Write(inTrash, @"ANOTHER PROJECT");
    NSInteger n = MMRemovalRecoverStaged();
    T(@"crash: another file at the Trash path is not taken for the trashed one", @"1 no ANOTHER PROJECT failed done yes", [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@", (long)n, YN(Exists(plain)), Read(inTrash),
      StateWord(parent), StateWord(part), YN([[MMUndo.shared record:parent.rid].error containsString:@"the Trash holds another file at"])]);
    [fm removeItemAtPath:inTrash error:nil];

    // L3. The Trash item is gone and something else sits at the old path: nothing was put back, and it says so.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"trash emptied", tree, GoneOwner());
    part = TrashOne(parent, @"config to the Trash, emptied", plain);
    [fm removeItemAtPath:[part.payload[@"trashed"] firstObject][@"to"] error:nil];
    Write(plain, @"SOMETHING ELSE");
    n = MMRemovalRecoverStaged();
    NSString *words = [MMUndo.shared record:parent.rid].error;
    T(@"crash: a Trash item that is gone is reported, not called put back", @"1 SOMETHING ELSE failed done yes yes", [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@", (long)n, Read(plain), StateWord(parent), StateWord(part),
      YN([words containsString:@", except: "]), YN([words containsString:@"the Trash no longer holds .env"])]);
    // The same file back at its old path, as after a put-back that stopped: that is back.
    Write(plain, @"PLAIN=1");
    parent = Unfinished(@"trash, moved back by hand", tree, GoneOwner());
    part = TrashOne(parent, @"config to the Trash, back by hand", plain);
    [fm moveItemAtPath:[part.payload[@"trashed"] firstObject][@"to"] toPath:plain error:nil];
    n = MMRemovalRecoverStaged();
    T(@"crash: the very file back at its old path counts as back", @"1 PLAIN=1 restored no", [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, Read(plain), StateWord(part),
      YN([[MMUndo.shared record:parent.rid].error containsString:@", except: "])]);

    // L4. The same for the staging folder: only the very file that was staged goes back.
    parent = Unfinished(@"staging swapped", tree, nil);
    part = StageMany(parent, @"config, swapped in staging", @[plain], YES);
    NSString *to = [part.payload[@"staged"] firstObject][@"to"];
    [fm removeItemAtPath:to error:nil];
    Write(to, @"NOT THE ITEM");
    NSString *problem = MMRemovalPutBack(@[part]);
    T(@"put back: another file in the staging folder is not taken for the staged one", @"yes no NOT THE ITEM done", [NSString stringWithFormat:@"%@ %@ %@ %@",
      YN([problem containsString:@"MinMacs's staging folder holds another file at"]), YN(Exists(plain)), Read(to), StateWord(part)]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    Write(plain, @"PLAIN=1");

    // L2. An empty staging folder is removed only when what it holds is what MinMacs wrote: two plain files.
    NSString *root = [MMRemovalRealPath(MMSupportDir()) stringByAppendingPathComponent:@"staged"];
    NSString *oddone = [root stringByAppendingPathComponent:@"oddone"], *other = [root stringByAppendingPathComponent:@"otherone"], *ours = [root stringByAppendingPathComponent:@"oursone"];
    Write([oddone stringByAppendingPathComponent:@".minmacs"], @"oddone");
    Write([oddone stringByAppendingPathComponent:@".gitignore/person.txt"], @"a person's file");
    Write([other stringByAppendingPathComponent:@".minmacs"], @"otherone");
    Write([other stringByAppendingPathComponent:@".gitignore"], @"*.log\nnotes\n");
    Write([ours stringByAppendingPathComponent:@".minmacs"], @"oursone");
    Write([ours stringByAppendingPathComponent:@".gitignore"], @"*\n");
    NSArray<NSString *> *orphans = nil;
    (void)MMRemovalSweepStaged(&orphans);
    T(@"sweep: a staging folder whose .gitignore is a folder is left as it is", @"a person's file yes", [NSString stringWithFormat:@"%@ %@", Read([oddone stringByAppendingPathComponent:@".gitignore/person.txt"]),
      YN([orphans containsObject:oddone])]);
    T(@"sweep: one whose .gitignore says something else is left too, and one with just MinMacs's two files goes", @"yes no", [NSString stringWithFormat:@"%@ %@",
      YN([Read([other stringByAppendingPathComponent:@".gitignore"]) isEqualToString:@"*.log\nnotes\n"]), YN(Exists(ours))]);
}

// The fourth review: a volume that came back, records that cannot be read, and a pid that is not the owner.
#import "damaged.m"
