// Act's part of the kept log of what came back, MMGains.h: what one finished action gave back, and of which kind.
// MMRunAction reads the memory before the action and writes the row after it. Restore takes the row back.
#import "Core/Store/MMGains.h"
#import "Core/Act/MMAct.h"

static BOOL Stops(NSString *actionKind) { return [actionKind isEqualToString:@"stop"] || [actionKind isEqualToString:@"quit"]; }

uint64_t MMGainsMemoryBefore(id<MMAction> action, MMFinding *f, MMFacts *fresh) {
    if (!f || !Stops(action.kind)) return 0;
    MMSample *s = fresh.sample;
    if (!s || !f.procs.count) return f.cost.ramBytes;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet new];
    uint64_t sum = 0;
    for (NSValue *v in f.procs) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        MMProc *p = [s proc:k.pid];
        // A pid whose start time moved is another process now, and it is not the one the action stops.
        if (!p || (k.startSec && p.startSec != k.startSec)) continue;
        for (NSNumber *pid in [s treeOf:k.pid limit:500]) {
            if ([seen containsObject:pid]) continue;
            [seen addObject:pid];
            sum += [s proc:pid.intValue].footprint;
        }
    }
    return sum;
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

MMGain *MMGainsRecordAction(id<MMAction> action, MMUndoRecord *record, MMFinding *f, uint64_t memoryBefore) {
    if (!record || record.state != MMUndoDone || !f) return nil;
    // The migration's own moves, the old apps and Noo-Noo's agent, are not gains. Their findings are Core's.
    if ([f.expert isEqualToString:@"core"]) return nil;
    NSString *kind = KindOf(action.kind, f);
    if (!kind) return nil;
    NSDictionary *p = record.payload;
    NSArray *trashed = [p[@"trashed"] isKindOfClass:NSArray.class] ? p[@"trashed"] : @[];
    NSString *state = MMGainDiskNone;
    uint64_t disk = 0;
    NSInteger items = 1;
    if ([kind isEqualToString:MMGainTab]) items = [p[@"tabs"] isKindOfClass:NSArray.class] ? (NSInteger)[p[@"tabs"] count] : 1;
    else if (!Stops(action.kind)) {
        disk = f.cost.diskFreed;
        // A tool's own cleanup has no Sizer size of its own at times, so its statfs delta stands in.
        if (!disk && ([action.kind isEqualToString:@"clean"] || [action.kind isEqualToString:@"tool"])) disk = (uint64_t)MAX(record.freedBytes, 0);
        state = trashed.count ? MMGainDiskTrash : MMGainDiskFreed;
    }
    NSString *run = record.parentRid.length ? record.parentRid : nil;
    NSString *who = WhoOf(record);
    NSString *gainKind = run ? MMGainWorkstream : kind, *part = run ? kind : nil;
    BOOL ok = [MMGains.shared add:record.rid run:run kind:gainKind part:part who:who by:record.by ?: @"manual"
                           expert:f.expert ?: @"" subject:record.subject ?: f.title ?: @"" workstream:WorkstreamOf(f, record)
                               at:NSDate.date memory:memoryBefore disk:disk diskState:state trashed:trashed items:items];
    return ok ? [MMGains.shared gain:record.rid] : nil;
}
