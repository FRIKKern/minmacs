// Act's part of the kept log of what came back, MMGains.h: what one finished action gave back, and of which kind.
// MMRunAction reads the memory before the action and writes the row after it. Restore takes the row back.
#import "Core/Store/MMGains.h"
#import "Core/Act/MMAct.h"
#import "Core/Know/MMTreeDisk.h"

static BOOL Stops(NSString *actionKind) { return [actionKind isEqualToString:@"stop"] || [actionKind isEqualToString:@"quit"]; }

/// Every process a gain row counted, as "pid:start", to the rid of that row. A process is ended once, so its memory
/// comes back once: a quit of Terminal counts the dev server that runs in it, and a stop of that server later in the
/// same Fix Everything, or any time after while it still runs, counts it no more. A row taken back by an undo no
/// longer holds its processes. Kept for a day, at most 4096.
static NSMutableDictionary<NSString *, NSArray *> *gCounted;

static BOOL CountedBefore(NSString *key) {
    NSArray *had;
    @synchronized (MMGains.class) { had = gCounted[key]; }
    if (!had) return NO;
    MMGain *g = [MMGains.shared gain:had[0]];
    return g && !g.undone;
}

static void NoteCounted(NSSet<NSString *> *keys, NSString *rid) {
    if (!keys.count || !rid.length) return;
    @synchronized (MMGains.class) {
        if (!gCounted) gCounted = [NSMutableDictionary new];
        NSDate *now = NSDate.date;
        if (gCounted.count + keys.count > 4096) {
            for (NSString *k in gCounted.allKeys) if ([now timeIntervalSinceDate:gCounted[k][1]] > 86400) [gCounted removeObjectForKey:k];
            while (gCounted.count + keys.count > 4096) [gCounted removeObjectForKey:gCounted.allKeys.firstObject];
        }
        for (NSString *k in keys) gCounted[k] = @[rid, now];
    }
}

uint64_t MMGainsMemoryBefore(id<MMAction> action, MMFinding *f, MMFacts *fresh, NSSet<NSString *> **counted) {
    if (counted) *counted = nil;
    if (!f || !Stops(action.kind)) return 0;
    MMSample *s = fresh.sample;
    if (!s || !f.procs.count) return f.cost.ramBytes;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet new];
    NSMutableSet<NSString *> *keys = [NSMutableSet new];
    uint64_t sum = 0;
    for (NSValue *v in f.procs) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        MMProc *p = [s proc:k.pid];
        // A pid whose start time moved is another process now, and it is not the one the action stops.
        if (!p || (k.startSec && p.startSec != k.startSec)) continue;
        // The tree by childrenOf:, at most 500 pids as treeOf:limit: caps it. Fact sources in tests give samples
        // that answer proc: and childrenOf: only.
        NSMutableArray<NSNumber *> *todo = [NSMutableArray arrayWithObject:@(k.pid)];
        while (todo.count && seen.count < 500) {
            NSNumber *pid = todo.lastObject;
            [todo removeLastObject];
            if ([seen containsObject:pid]) continue;
            [seen addObject:pid];
            MMProc *q = [s proc:pid.intValue];
            NSString *key = q ? [NSString stringWithFormat:@"%d:%llu", pid.intValue, (unsigned long long)q.startSec] : nil;
            // Its children still count: a process an earlier action counted can hold one that came after.
            if (key && !CountedBefore(key)) { [keys addObject:key]; sum += q.footprint; }
            [todo addObjectsFromArray:[s childrenOf:pid.intValue]];
        }
    }
    if (counted) *counted = keys;
    return sum;
}

NSNumber *MMGainsDiskBefore(id<MMAction> action, MMFinding *f) {
    if (!f || Stops(action.kind)) return nil;
    if (!f.unmeasured) return @(f.cost.diskFreed);
    // Not measured when it was listed, so its cost holds 0, which is no reading. A walk kept now ended after that:
    // WorkForest's policy takes one on fresh facts right before a removal. With none kept, nobody knows the size.
    MMTreeDiskFacts *d = [MMTreeDisk.shared lastWalkOf:f.path];
    return d ? @(d.freed) : nil;
}

/// The kind of thing an action gave back, or nil when it gives nothing back, such as the lid override,
/// a keep-awake hold or a setting.
static NSString *KindOf(NSString *actionKind, MMFinding *f) {
    if ([actionKind isEqualToString:@"stop"]) return [f.kind isEqualToString:@"server"] ? MMGainServer : MMGainHelper;
    if ([actionKind isEqualToString:@"quit"]) return MMGainApp;
    if ([actionKind isEqualToString:@"trim"]) return MMGainTab;
    if ([actionKind isEqualToString:@"remove"]) return MMGainWorktree;
    if ([actionKind isEqualToString:@"trash"] || [actionKind isEqualToString:@"clean"] || [actionKind isEqualToString:@"tool"])
        return [f.kind isEqualToString:@"worktree"] ? MMGainWorktree : MMGainCache;
    return nil;
}

static NSString *WhoOf(MMUndoRecord *r) {
    if (r.parentRid.length) return MMGainByRun;
    if ([r.by isEqualToString:@"proactive"] || [r.by isEqualToString:@"eager"] || [r.by isEqualToString:@"guard"]) return MMGainByAuto;
    return MMGainByYou;
}

/// The owner id of the workstream the finding belonged to, or of its worktree when no session held it.
static NSString *WorkstreamOf(MMFinding *f, MMUndoRecord *r) {
    NSString *tree = nil;
    for (MMOwner *o = f.owner; o; o = o.parent) {
        if (o.kind == MMOwnerWorkstream) return o.ownerID;
        if (o.kind == MMOwnerWorktree && !tree) tree = o.ownerID;
    }
    if (tree) return tree;
    if (r.parentRid.length) {
        NSString *path = [MMUndo.shared record:r.parentRid].payload[@"path"];
        if ([path isKindOfClass:NSString.class] && path.length) return [@"worktree:" stringByAppendingString:path];
    }
    return nil;
}

MMGain *MMGainsRecordAction(id<MMAction> action, MMUndoRecord *record, MMFinding *f, uint64_t memoryBefore, NSSet<NSString *> *counted,
                            NSNumber *diskBefore) {
    if (!record || record.state != MMUndoDone || !f) return nil;
    // The migration's own moves, the old apps and Noo-Noo's agent, are not gains. Their findings are Core's.
    if ([f.expert isEqualToString:@"core"]) return nil;
    NSString *kind = KindOf(action.kind, f);
    if (!kind) return nil;
    NSDictionary *p = record.payload;
    NSArray *trashed = MMRecordTrashed(p);
    NSString *state = MMGainDiskNone;
    uint64_t disk = 0;
    NSInteger items = 1;
    if ([kind isEqualToString:MMGainTab]) items = [p[@"tabs"] isKindOfClass:NSArray.class] ? (NSInteger)[p[@"tabs"] count] : 1;
    else if (!Stops(action.kind)) {
        // The reading taken before the action ran. With none, the row says not measured, and never 0.
        disk = diskBefore ? diskBefore.unsignedLongLongValue : MMGainDiskNotMeasured;
        // A tool's own cleanup has no Sizer size of its own at times, so its statfs delta stands in.
        if ((!disk || disk == MMGainDiskNotMeasured) && ([action.kind isEqualToString:@"clean"] || [action.kind isEqualToString:@"tool"])) disk = (uint64_t)MAX(record.freedBytes, 0);
        state = trashed.count ? MMGainDiskTrash : MMGainDiskFreed;
    }
    NSString *run = record.parentRid.length ? record.parentRid : nil;
    NSString *who = WhoOf(record);
    NSString *gainKind = run ? MMGainWorkstream : kind, *part = run ? kind : nil;
    BOOL ok = [MMGains.shared add:record.rid run:run kind:gainKind part:part who:who by:record.by ?: @"manual"
                           expert:f.expert ?: @"" subject:record.subject ?: f.title ?: @"" workstream:WorkstreamOf(f, record)
                               at:NSDate.date memory:memoryBefore disk:disk diskState:state trashed:trashed items:items];
    if (ok) NoteCounted(counted, record.rid);
    return ok ? [MMGains.shared gain:record.rid] : nil;
}
