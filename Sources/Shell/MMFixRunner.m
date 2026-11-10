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
    if ([kind isEqualToString:@"trash"]) return [NSString stringWithFormat:@"Moving %@ to the Trash", name];
    return [@"Fixing " stringByAppendingString:name];
}

@implementation MMFixRunner {
    MMPerformance *_p;
    atomic_bool _stop, _running;
    NSMutableArray<MMFixResult *> *_results;
    NSInteger _done, _total;
    uint64_t _memoryBack, _diskBack, _memoryPlanned, _diskPlanned;
    BOOL _trashed, _recovered;
}

- (instancetype)initWithPerformance:(MMPerformance *)p {
    if ((self = [super init])) { _p = p; _results = [NSMutableArray new]; }
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

/// Where a finished record's deletes went, from its payload: the Trash, a recovery folder, or neither.
- (void)readWhere:(MMUndoRecord *)rec {
    if (!rec) return;
    NSMutableArray<MMUndoRecord *> *all = [NSMutableArray arrayWithObject:rec];
    id parts = rec.payload[@"done"];
    if ([parts isKindOfClass:NSArray.class])
        for (id rid in parts) { MMUndoRecord *part = [rid isKindOfClass:NSString.class] ? [MMUndo.shared record:rid] : nil; if (part) [all addObject:part]; }
    for (MMUndoRecord *r in all) {
        if ([r.payload[@"trashed"] isKindOfClass:NSArray.class] && [r.payload[@"trashed"] count]) _trashed = YES;
        id rec2 = r.payload[@"recovery"];
        if ([rec2 isKindOfClass:NSDictionary.class] && [rec2[@"saved"] isKindOfClass:NSArray.class] && [rec2[@"saved"] count]) _recovered = YES;
    }
}

- (MMWindowRun *)run {
    MMWindowRun *end = [MMWindowRun new];
    if (NSThread.isMainThread || atomic_exchange(&_running, true)) {
        end.endTitle = @"0 fixes done"; end.endNote = @"Nothing ran.";
        return end;
    }
    atomic_store(&_stop, false);
    NSMutableArray<MMPerformanceFix *> *fixes = [NSMutableArray new];
    NSInteger needYou = 0;
    for (MMPerformanceFix *f in _p.fixes) {
        if (f.needsYou) { needYou++; continue; }
        [fixes addObject:f];
        _memoryPlanned += f.memoryBack; _diskPlanned += f.diskBack;
    }
    _total = (NSInteger)fixes.count;
    BOOL treesMoved = NO;
    NSInteger notRun = 0;
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
            if ([x.outcome isEqualToString:@"done"]) { landed = YES; _memoryBack += f.memoryBack; }
        } else {
            for (id<MMAction> a in f.actions) {
                if (atomic_load(&_stop)) break;
                NSString *name = MMWindowNameOf(a.finding);
                [self tell:[self progress:MMFixStepText(f.kind, name)]];
                NSString *err = nil;
                MMUndoRecord *rec = MMRunAction(a, f.policy, nil, @"manual", @"Fix Everything", &err);
                MMFixResult *x = [self note:f name:name record:rec error:err];
                if (rec) { _diskBack += (uint64_t)MAX(rec.freedBytes, 0); [self readWhere:rec]; }
                if (![x.outcome isEqualToString:@"done"]) continue;
                landed = YES;
                if ([f.kind isEqualToString:@"stop"] || [f.kind isEqualToString:@"quit"]) _memoryBack += a.finding.cost.ramBytes;
                if ([f.kind isEqualToString:@"remove"]) treesMoved = YES;
            }
        }
        if (landed) _done++;
    }
    // What the menus do after a removal: the repo index reads the worktrees again, then the graph builds anew.
    if (treesMoved) [MMRepoIndex.shared refresh:nil];
    [MMGraph.shared rebuild:@"fix everything"];

    end = [self progress:nil];
    end.running = NO;
    end.endTitle = _done == _total ? [NSString stringWithFormat:@"%@ done", MMPlural(_done, @"fix")]
                                   : [NSString stringWithFormat:@"%ld of %@ done", (long)_done, MMPlural(_total, @"fix")];
    end.endNote = [self endNote:needYou notRun:notRun];
    atomic_store(&_running, false);
    [self tell:end];
    return end;
}

/// One or two short sentences: what was skipped and why, then where deleted things went. Nothing here says a thing is
/// gone for good, since every step left an undo record.
- (NSString *)endNote:(NSInteger)needYou notRun:(NSInteger)notRun {
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
    if (notRun > 0) [skipped addObject:[NSString stringWithFormat:@"%@ you stopped", MMPlural(notRun, @"fix")]];
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    if (skipped.count) {
        NSString *list = skipped.count == 1 ? skipped[0]
            : [NSString stringWithFormat:@"%@ and %@", [[skipped subarrayWithRange:NSMakeRange(0, skipped.count - 1)] componentsJoinedByString:@", "], skipped.lastObject];
        [out addObject:[NSString stringWithFormat:@"Skipped %@.", list]];
    }
    if (_trashed && _recovered) [out addObject:@"Deletes went to the Trash, and files git ignores were saved in a recovery folder."];
    else if (_trashed) [out addObject:@"Deletes went to the Trash."];
    else if (_recovered) [out addObject:@"Files git ignores were saved in a recovery folder."];
    return out.count ? [out componentsJoinedByString:@" "] : nil;
}

@end
