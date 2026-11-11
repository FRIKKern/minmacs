// Fix Everything's runner, MMFixRunner.h.
#import <stdatomic.h>
#import "Shell/MMFixRunner.h"
#import "Shell/MMWindowFeed.h"
#import "UI/MMFormat.h"

@implementation MMFixResult
@end

NSString *MMFixStepText(NSString *kind, NSString *name) {
    if ([kind isEqualToString:@"wrapup"]) return [@"Wrapping up " stringByAppendingString:name];
    if ([kind isEqualToString:@"stop"]) return [@"Stopping " stringByAppendingString:name];
    if ([kind isEqualToString:@"quit"]) return [@"Quitting " stringByAppendingString:name];
    if ([kind isEqualToString:@"remove"]) return [@"Removing " stringByAppendingString:name];
    if ([kind isEqualToString:@"trash"]) {
        // Under Smart the step's own fresh check decides, so the step says neither before it ran.
        MMRemovalChoice c = MMRemovalChoiceNow();
        return c == MMRemovalTrash ? [NSString stringWithFormat:@"Moving %@ to the Trash", name]
             : [(c == MMRemovalDelete ? @"Deleting " : @"Cleaning up ") stringByAppendingString:name];
    }
    return [@"Fixing " stringByAppendingString:name];
}

@implementation MMFixRunner {
    MMPerformance *_p;
    atomic_bool _stop, _running;
    NSMutableArray<MMFixResult *> *_results;
    NSInteger _done, _total;
    uint64_t _memoryBack, _diskBack, _memoryPlanned, _diskPlanned;
    BOOL _recovered;
    NSMutableArray<MMUndoRecord *> *_removed;   // each finished record of the run, a Wrap Up as its parts
}

- (instancetype)initWithPerformance:(MMPerformance *)p {
    if ((self = [super init])) { _p = p; _results = [NSMutableArray new]; _removed = [NSMutableArray new]; }
    return self;
}

- (BOOL)running { return atomic_load(&_running); }
- (void)stop { atomic_store(&_stop, true); }
- (NSArray<MMFixResult *> *)results { @synchronized (self) { return [_results copy]; } }

- (void)start {
    if (self.running) return;
    dispatch_async(MMQueue(@"core", @"fix-everything", QOS_CLASS_USER_INITIATED), ^{ (void)[self run]; });
}

- (MMWindowRun *)progress:(NSString *)step {
    MMWindowRun *r = [MMWindowRun new];
    r.running = YES; r.step = step; r.done = _done; r.total = _total;
    r.memoryBack = _memoryBack; r.diskBack = _diskBack; r.memoryPlanned = _memoryPlanned; r.diskPlanned = _diskPlanned;
    return r;
}

- (void)tell:(MMWindowRun *)r { void (^b)(MMWindowRun *) = self.onProgress; if (b) b(r); }

- (MMFixResult *)note:(MMPerformanceFix *)fix name:(NSString *)name record:(MMUndoRecord *)rec error:(NSString *)err {
    MMFixResult *x = [MMFixResult new];
    x.fix = fix.key; x.kind = fix.kind; x.name = name; x.rid = rec.rid;
    if (rec && rec.state == MMUndoDone) x.outcome = @"done";
    else if (rec) { x.outcome = @"failed"; x.why = err ?: rec.error; }
    // MMRunAction says "kept: ..." when MustKeep holds it on fresh facts, and anything else when it could not start.
    else { x.outcome = [err hasPrefix:@"kept: "] ? @"kept" : @"blocked"; x.why = err; }
    @synchronized (self) { [_results addObject:x]; }
    return x;
}

/// Where a finished record's removed things went, from its payload: deleted, the Trash, a recovery folder, or none.
/// The records are kept for the end note, which MMRemovalWhereWords counts from them.
- (void)readWhere:(MMUndoRecord *)rec {
    if (!rec) return;
    NSMutableArray<MMUndoRecord *> *all = [NSMutableArray arrayWithObject:rec];
    id parts = rec.payload[@"done"];
    if ([parts isKindOfClass:NSArray.class])
        for (id rid in parts) { MMUndoRecord *part = [rid isKindOfClass:NSString.class] ? [MMUndo.shared record:rid] : nil; if (part) [all addObject:part]; }
    for (MMUndoRecord *r in all) {
        [_removed addObject:r];
        id rec2 = r.payload[@"recovery"];
        if ([rec2 isKindOfClass:NSDictionary.class] && [rec2[@"saved"] isKindOfClass:NSArray.class] && [rec2[@"saved"] count]) _recovered = YES;
    }
}

/// The memory one finished record gave back: the footprint Act read on fresh facts right before the action ran, as
/// the gains log holds it. A record that failed, was kept or never started has no row there, and gives 0.
- (uint64_t)memoryOf:(MMUndoRecord *)rec {
    if (!rec || rec.state != MMUndoDone || !rec.rid.length) return 0;
    return [MMGains.shared gain:rec.rid].memoryBytes;
}

- (MMWindowRun *)run {
    MMWindowRun *end = [MMWindowRun new];
    if (NSThread.isMainThread || atomic_exchange(&_running, true)) {
        end.endTitle = @"0 fixes done"; end.endNote = @"Nothing ran.";
        return end;
    }
    NSMutableArray<MMPerformanceFix *> *fixes = [NSMutableArray new];
    NSInteger needYou = 0;
    for (MMPerformanceFix *f in _p.fixes) {
        if (f.needsYou) { needYou++; continue; }
        [fixes addObject:f];
        _memoryPlanned += f.memoryBack; _diskPlanned += f.diskBack;
    }
    _total = (NSInteger)fixes.count;
    BOOL treesMoved = NO;
    NSInteger notRun = 0, notReached = 0;
    for (MMPerformanceFix *f in fixes) {
        if (atomic_load(&_stop)) { notRun++; continue; }
        BOOL landed = NO;
        if (f.wrapUp) {
            NSString *name = f.wrapUp.subject.worktree.branch.length ? f.wrapUp.subject.worktree.branch : f.wrapUp.subject.path.lastPathComponent;
            [self tell:[self progress:MMFixStepText(f.kind, name ?: @"")]];
            NSString *err = nil;
            MMUndoRecord *rec = MMRunWrapUp(f.wrapUp, @"manual", &err);
            MMFixResult *x = [self note:f name:name ?: @"" record:rec error:err];
            if (rec) { _diskBack += (uint64_t)MAX(rec.freedBytes, 0); treesMoved = YES; [self readWhere:rec]; }
            // A Wrap Up that ended at a failed part still stopped the parts before it, and those count.
            id parts = rec.payload[@"done"];
            if ([parts isKindOfClass:NSArray.class]) for (id rid in parts) if ([rid isKindOfClass:NSString.class]) _memoryBack += [self memoryOf:[MMUndo.shared record:rid]];
            if ([x.outcome isEqualToString:@"done"]) landed = YES;
        } else {
            NSInteger reached = 0;
            for (id<MMAction> a in f.actions) {
                if (atomic_load(&_stop)) break;
                reached++;
                NSString *name = MMWindowNameOf(a.finding);
                [self tell:[self progress:MMFixStepText(f.kind, name)]];
                NSString *err = nil;
                MMUndoRecord *rec = MMRunAction(a, f.policy, nil, @"manual", @"Fix Everything", &err);
                MMFixResult *x = [self note:f name:name record:rec error:err];
                if (rec) { _diskBack += (uint64_t)MAX(rec.freedBytes, 0); [self readWhere:rec]; }
                if (![x.outcome isEqualToString:@"done"]) continue;
                landed = YES;
                _memoryBack += [self memoryOf:rec];
                if ([f.kind isEqualToString:@"remove"]) treesMoved = YES;
            }
            // Stopped inside the fix: it is not done. What it did stays in the results, and the rest is counted as not reached.
            NSInteger left = (NSInteger)f.actions.count - reached;
            if (left > 0) {
                landed = NO;
                if (reached) notReached += left; else notRun++;
            }
        }
        if (landed) _done++;
    }
    self.endedAt = NSDate.date;
    // What the menus do after a removal: the repo index reads the worktrees again, then the graph builds anew.
    if (treesMoved) [MMRepoIndex.shared refresh:nil];
    [MMGraph.shared rebuild:@"fix everything"];

    end = [self progress:nil];
    end.running = NO;
    end.endTitle = _done == _total ? [NSString stringWithFormat:@"%@ done", MMPlural(_done, @"fix")]
                                   : [NSString stringWithFormat:@"%ld of %@ done", (long)_done, MMPlural(_total, @"fix")];
    end.endNote = [self endNote:needYou notRun:notRun notReached:notReached];
    // A stop asked for before the run began is kept, so it ends the run at once. It is spent here, at the end.
    atomic_store(&_stop, false);
    atomic_store(&_running, false);
    [self tell:end];
    return end;
}

/// One or two short sentences: what was skipped and why, then where removed things went in this run, counted from the
/// records: "Deleted 3, moved 2 to the Trash." Every step left a record, and a deleted thing's record says so.
- (NSString *)endNote:(NSInteger)needYou notRun:(NSInteger)notRun notReached:(NSInteger)notReached {
    NSInteger kept = 0, stuck = 0;
    for (MMFixResult *x in self.results) {
        if ([x.outcome isEqualToString:@"kept"]) kept++;
        else if (![x.outcome isEqualToString:@"done"]) stuck++;
    }
    NSMutableArray<NSString *> *skipped = [NSMutableArray new];
    if (_p.needsYou > 0) [skipped addObject:_p.needsYou == 1 ? @"1 agent that asks you" : [NSString stringWithFormat:@"%ld agents that ask you", (long)_p.needsYou]];
    if (needYou > 0) [skipped addObject:needYou == 1 ? @"1 fix that needs your own press" : [NSString stringWithFormat:@"%ld fixes that need your own press", (long)needYou]];
    if (kept > 0) [skipped addObject:[NSString stringWithFormat:@"%ld kept since %@ changed or %@ in use", (long)kept, kept == 1 ? @"it" : @"they", kept == 1 ? @"is" : @"are"]];
    if (stuck > 0) [skipped addObject:[NSString stringWithFormat:@"%ld blocked", (long)stuck]];
    if (notReached > 0) [skipped addObject:[NSString stringWithFormat:@"%@ in the fix you stopped partway", MMPlural(notReached, @"thing")]];
    if (notRun > 0) [skipped addObject:[NSString stringWithFormat:@"%@ you stopped", MMPlural(notRun, @"fix")]];
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    if (skipped.count) {
        NSString *list = skipped.count == 1 ? skipped[0]
            : [NSString stringWithFormat:@"%@ and %@", [[skipped subarrayWithRange:NSMakeRange(0, skipped.count - 1)] componentsJoinedByString:@", "], skipped.lastObject];
        [out addObject:[NSString stringWithFormat:@"Skipped %@.", list]];
    }
    NSString *where = MMRemovalWhereWords(_removed);
    if (where) [out addObject:where];
    if (_recovered) [out addObject:@"Files git ignores were saved in a recovery folder."];
    return out.count ? [out componentsJoinedByString:@" "] : nil;
}

@end
