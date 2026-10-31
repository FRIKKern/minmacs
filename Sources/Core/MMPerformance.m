// The Performance tab as a model, MMPerformance.h. It reads one snapshot and builds no view.
#import "Core/MMPerformance.h"
#import "Core/MMExpert.h"
#import "Core/Graph/MMHistory.h"
#import "Core/Store/MMGains.h"

NSString *const MMPerformanceServers = @"servers", *const MMPerformanceAgents = @"agents", *const MMPerformanceApps = @"apps",
    *const MMPerformanceTabsGroup = @"tabs", *const MMPerformanceHelpers = @"helpers", *const MMPerformanceWorktrees = @"worktrees",
    *const MMPerformanceClutter = @"clutter", *const MMPerformanceOther = @"other";

NSInteger MMPerformanceFold(NSString *group) {
    static NSDictionary *folds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        folds = @{MMPerformanceServers: @6, MMPerformanceAgents: @1, MMPerformanceApps: @2, MMPerformanceTabsGroup: @0,
                  MMPerformanceHelpers: @0, MMPerformanceWorktrees: @12, MMPerformanceClutter: @10};
    });
    return [folds[group ?: @""] integerValue];
}

static NSArray<NSString *> *MemoryOrder(void) {
    return @[MMPerformanceServers, MMPerformanceAgents, MMPerformanceApps, MMPerformanceTabsGroup, MMPerformanceHelpers];
}
static NSArray<NSString *> *DiskOrder(void) { return @[MMPerformanceWorktrees, MMPerformanceClutter]; }

static BOOL PathIn(NSString *path, NSString *folder) {
    if (!path.length || !folder.length || ![path hasPrefix:folder]) return NO;
    return path.length == folder.length || [path characterAtIndex:folder.length] == '/';
}

static MMProcKey KeyOf(NSValue *v) { MMProcKey k = {0, 0}; [v getValue:&k size:sizeof k]; return k; }

#pragma mark - Rows and groups

@interface MMPerformanceRow ()
@property (readwrite, copy) NSString *key, *findingID, *expert, *group, *name;
@property (readwrite) MMPerformanceSide side;
@property (readwrite) uint64_t number;
@property (readwrite) MMPerformanceUnit unit;
@property (readwrite) BOOL needsYou;
@property MMFinding *finding;
@end

@implementation MMPerformanceRow
- (NSDictionary *)json {
    return @{@"key": self.key ?: @"", @"findingID": self.findingID ?: @"", @"expert": self.expert ?: @"", @"group": self.group ?: @"",
             @"name": self.name ?: @"", @"number": @(self.number), @"unit": self.unit == MMPerformanceTabs ? @"tabs" : @"bytes",
             @"needsYou": @(self.needsYou)};
}
@end

@interface MMPerformanceGroup ()
@property (readwrite, copy) NSString *key;
@property (readwrite) MMPerformanceSide side;
@property (readwrite) NSInteger fold;
@property (readwrite) NSArray<MMPerformanceRow *> *rows;
@end

@implementation MMPerformanceGroup
- (NSDictionary *)json {
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:self.rows.count];
    for (MMPerformanceRow *r in self.rows) [rows addObject:r.json];
    return @{@"group": self.key ?: @"", @"fold": @(self.fold), @"rows": rows};
}
@end

#pragma mark - The ring

@interface MMPerformanceSideRing ()
@property (readwrite) MMPerformanceSide side;
@property (readwrite) uint64_t total, used, cut;
@property (readwrite) NSDictionary<NSString *, NSNumber *> *parts;
@property (readwrite) NSArray<NSString *> *order;
@end

@implementation MMPerformanceSideRing
/// Parts in order, each cut to what used leaves, then other as the rest.
+ (instancetype)side:(MMPerformanceSide)side total:(uint64_t)total used:(uint64_t)used
               order:(NSArray<NSString *> *)order bytes:(NSDictionary<NSString *, NSNumber *> *)bytes {
    MMPerformanceSideRing *r = [MMPerformanceSideRing new];
    r.side = side; r.total = total; r.used = used;
    NSMutableDictionary *parts = [NSMutableDictionary new];
    uint64_t left = used, cut = 0;
    for (NSString *k in order) {
        uint64_t b = [bytes[k] unsignedLongLongValue], take = MIN(b, left);
        parts[k] = @(take); left -= take; cut += b - take;
    }
    parts[MMPerformanceOther] = @(left);
    r.parts = parts; r.cut = cut;
    r.order = [order arrayByAddingObject:MMPerformanceOther];
    return r;
}
- (NSDictionary *)json {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *k in self.order) [parts addObject:@{@"group": k, @"bytes": self.parts[k] ?: @0}];
    return @{@"total": @(self.total), @"used": @(self.used), @"parts": parts, @"cut": @(self.cut)};
}
@end

#pragma mark - Fixes and the look-back

@interface MMPerformanceFix ()
@property (readwrite, copy) NSString *key, *kind, *expert;
@property (readwrite) uint64_t memoryBack, diskBack;
@property (readwrite) NSArray<NSString *> *rows;
@property (readwrite) BOOL needsYou;
@property (readwrite) double share;
@property (readwrite) MMWrapUpPlan *wrapUp;
@property (readwrite) NSArray<id<MMAction>> *actions;
@property (readwrite) id<MMExpertPolicy> policy;
@end

@implementation MMPerformanceFix
- (NSDictionary *)json {
    NSMutableArray *ids = [NSMutableArray new];
    for (id<MMAction> a in self.actions) [ids addObject:a.finding.findingID ?: @""];
    return @{@"key": self.key ?: @"", @"kind": self.kind ?: @"", @"expert": self.expert ?: @"", @"memoryBack": @(self.memoryBack),
             @"diskBack": @(self.diskBack), @"rows": self.rows ?: @[], @"needsYou": @(self.needsYou), @"share": @(self.share),
             @"wrapUp": self.wrapUp ? self.wrapUp.subject.path ?: @"" : NSNull.null, @"actions": ids};
}
@end

@interface MMPerformanceLookBack ()
@property (readwrite) uint64_t weekMemory, weekDisk, todayMemory, todayDisk;
@end

@implementation MMPerformanceLookBack
+ (instancetype)fromSummary:(NSDictionary *)summary {
    MMPerformanceLookBack *b = [MMPerformanceLookBack new];
    NSDictionary *w = [summary[@"total"] isKindOfClass:NSDictionary.class] ? summary[@"total"] : nil;
    NSDictionary *t = [summary[@"today"] isKindOfClass:NSDictionary.class] ? summary[@"today"] : nil;
    b.weekMemory = [w[@"memoryBack"] unsignedLongLongValue]; b.weekDisk = [w[@"diskBack"] unsignedLongLongValue];
    b.todayMemory = [t[@"memoryBack"] unsignedLongLongValue]; b.todayDisk = [t[@"diskBack"] unsignedLongLongValue];
    return b;
}
+ (instancetype)read:(MMGains *)gains now:(NSDate *)now { return [self fromSummary:[gains summary:7 now:now ?: NSDate.date]]; }
- (NSDictionary *)json {
    return @{@"week": @{@"memoryBack": @(self.weekMemory), @"diskBack": @(self.weekDisk)},
             @"today": @{@"memoryBack": @(self.todayMemory), @"diskBack": @(self.todayDisk)}};
}
@end

#pragma mark - The model

@interface MMPerformance ()
@property (readwrite) uint64_t generation;
@property (readwrite) MMPerformanceSideRing *memory, *disk;
@property (readwrite) NSArray<MMPerformanceGroup *> *memoryGroups, *diskGroups;
@property (readwrite) NSArray<MMPerformanceFix *> *fixes;
@property (readwrite) MMPerformanceLookBack *lookBack;
@property (readwrite) NSInteger needsYou;
@property NSDictionary<NSString *, MMPerformanceRow *> *byKey;
@end

/// Memory used from the hour's Mac ring: its newest filled minute, a mean of that minute's passes.
static uint64_t MemoryUsed(MMHistoryView *h) {
    for (NSInteger i = MMHistoryMinutes - 1; h.mac && i >= 0; i--) {
        MMHistoryMinute m = [h.mac minuteAt:(NSUInteger)i];
        if (m.passes && m.megabytes >= 0) return (uint64_t)((double)m.megabytes * 1048576.0);
    }
    return MMReadHostLoad().memoryUsed;
}

/// The bytes the processes of procs hold that no earlier group claimed: each process tree in the sample, each pid once.
/// Without a sample, or when no process of the finding is in it, the finding's own cost.
static uint64_t Claim(MMSample *sample, MMFinding *f, NSMutableSet<NSNumber *> *claimed) {
    if (!sample || !f.procs.count) return f.cost.ramBytes;
    uint64_t n = 0; BOOL seen = NO;
    for (NSValue *v in f.procs) {
        MMProcKey k = KeyOf(v);
        MMProc *p = [sample proc:k.pid];
        if (!p || p.startSec != k.startSec) continue;
        seen = YES;
        for (NSNumber *t in [sample treeOf:k.pid limit:500]) {
            if ([claimed containsObject:t]) continue;
            [claimed addObject:t];
            n += [sample proc:t.intValue].footprint;
        }
    }
    return seen ? n : f.cost.ramBytes;
}

/// An app's memory holds every process it is responsible for. Those an earlier group claimed come off: held maps a
/// responsible pid to the footprint of the claimed processes it is responsible for.
static uint64_t AppClaim(MMSample *sample, MMFinding *f, NSDictionary<NSNumber *, NSNumber *> *held) {
    if (!sample || !f.procs.count) return f.cost.ramBytes;
    MMProcKey k = KeyOf(f.procs.firstObject);
    MMProc *app = [sample proc:k.pid];
    if (!app || app.startSec != k.startSec) return f.cost.ramBytes;
    uint64_t taken = [held[@(k.pid)] unsignedLongLongValue];
    return f.cost.ramBytes > taken ? f.cost.ramBytes - taken : 0;
}

static NSString *RowKey(MMFinding *f) {
    if ([f.kind isEqualToString:@"helper"] || [f.kind isEqualToString:@"tabs"])
        return [NSString stringWithFormat:@"%@|%@", f.findingID, f.instanceKey ?: @""];
    return f.findingID;
}

static MMPerformanceRow *RowFor(MMFinding *f, NSString *group, MMPerformanceSide side) {
    MMPerformanceRow *r = [MMPerformanceRow new];
    r.key = RowKey(f); r.findingID = f.findingID; r.expert = f.expert; r.group = group; r.side = side;
    r.name = f.title ?: f.stableKey; r.finding = f;
    if ([group isEqualToString:MMPerformanceTabsGroup]) {
        id urls = f.facts[@"urls"];
        r.number = [urls isKindOfClass:NSArray.class] ? [urls count] : 0; r.unit = MMPerformanceTabs;
    } else r.number = side == MMPerformanceMemory ? f.cost.ramBytes : f.cost.diskFreed;
    return r;
}

/// Biggest number first, then by key, so the order holds between builds.
static NSArray<MMPerformanceRow *> *Sorted(NSArray<MMPerformanceRow *> *rows) {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(MMPerformanceRow *a, MMPerformanceRow *b) {
        if (a.number != b.number) return a.number > b.number ? NSOrderedAscending : NSOrderedDescending;
        return [a.key compare:b.key];
    }];
}

/// The agents waiting on the person, as "pid:start".
static NSSet<NSString *> *Waiting(MMFacts *facts) {
    NSMutableSet *w = [NSMutableSet new];
    for (MMAgent *a in facts.agents) {
        if (a.state == MMAgentWaiting) [w addObject:MMProcKeyString(a.key)];
        for (MMAgent *h in a.hosted) if (h.state == MMAgentWaiting) [w addObject:MMProcKeyString(h.key)];
    }
    return w;
}

/// The fix kind of a finding's proposal, for the actions the experts already offer. nil for any other.
static NSString *FixKind(MMFinding *f) {
    NSString *verb = f.proposal.verb, *k = [NSString stringWithFormat:@"%@/%@/%@", f.expert, f.kind, verb ?: @""];
    static NSDictionary *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kinds = @{@"locohost/server/stop": @"stop", @"minmacs/app/quit": @"quit", @"workforest/worktree/remove": @"remove",
                  @"noonoo/clutter/remove": @"trash", @"noonoo/clutter/clean": @"clean"};
    });
    return kinds[k];
}

static double PressureWeight(MMPower *p) { return p.memoryPressure >= 4 ? 2.5 : p.memoryPressure >= 2 ? 1.5 : 1; }

@implementation MMPerformance

- (MMPerformanceRow *)row:(NSString *)key { return key ? self.byKey[key] : nil; }

+ (instancetype)from:(MMSnapshot *)s {
    return [self from:s history:nil lookBack:[MMPerformanceLookBack read:MMGains.shared now:NSDate.date]];
}

+ (instancetype)from:(MMSnapshot *)s history:(MMHistoryView *)history lookBack:(MMPerformanceLookBack *)lookBack {
    MMPerformance *m = [MMPerformance new];
    MMFacts *facts = s.facts;
    MMSample *sample = facts.sample;
    m.generation = s.generation;
    m.lookBack = lookBack ?: [MMPerformanceLookBack fromSummary:@{}];
    NSMutableDictionary<NSString *, NSMutableArray<MMPerformanceRow *> *> *groups = [NSMutableDictionary new];
    for (NSString *g in [MemoryOrder() arrayByAddingObjectsFromArray:DiskOrder()]) groups[g] = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMPerformanceRow *> *byKey = [NSMutableDictionary new];
    void (^add)(MMPerformanceRow *) = ^(MMPerformanceRow *r) {
        if (!r.key.length || byKey[r.key]) return;
        byKey[r.key] = r; [groups[r.group] addObject:r];
    };

    // The rows from the snapshot's findings.
    NSSet *waiting = Waiting(facts);
    for (MMFinding *f in s.findings) {
        NSString *ek = [NSString stringWithFormat:@"%@/%@", f.expert, f.kind];
        MMPerformanceRow *r = nil;
        if ([ek isEqualToString:@"locohost/server"]) r = RowFor(f, MMPerformanceServers, MMPerformanceMemory);
        else if ([ek isEqualToString:@"minmacs/agent"]) {
            r = RowFor(f, MMPerformanceAgents, MMPerformanceMemory);
            for (NSValue *v in f.procs) if ([waiting containsObject:MMProcKeyString(KeyOf(v))]) r.needsYou = YES;
        }
        else if ([ek isEqualToString:@"minmacs/app"]) r = RowFor(f, MMPerformanceApps, MMPerformanceMemory);
        else if ([ek isEqualToString:@"workforest/worktree"]) r = RowFor(f, MMPerformanceWorktrees, MMPerformanceDisk);
        else if ([ek isEqualToString:@"noonoo/clutter"]) r = RowFor(f, MMPerformanceClutter, MMPerformanceDisk);
        if (r) add(r);
    }

    // Wrap Up plans of the merged linked worktrees. A finished workstream's helpers and localhost tabs are rows, and a
    // plan that passes MustKeep is a fix.
    NSMutableArray<MMPerformanceFix *> *fixes = [NSMutableArray new];
    NSMutableSet<NSString *> *inFix = [NSMutableSet new];
    NSMutableArray<NSString *> *removedTrees = [NSMutableArray new];
    for (MMWorktree *w in facts.worktrees) {
        if (w.isMain || w.missing || !w.path.length || [facts gitFor:w].merged == MMMergedNone) continue;
        MMWrapUpPlan *plan = MMWrapUpPlanFor(w.path, s);
        if (plan.subject.whyNot) continue;
        for (MMWrapUpPart *p in plan.parts) {
            MMFinding *f = p.action.finding;
            if (p.step == MMWrapUpHelpers && [f.kind isEqualToString:@"helper"]) add(RowFor(f, MMPerformanceHelpers, MMPerformanceMemory));
            else if (p.step == MMWrapUpTabs && [f.kind isEqualToString:@"tabs"]) add(RowFor(f, MMPerformanceTabsGroup, MMPerformanceMemory));
        }
        if (plan.whyNot) continue;
        MMPerformanceFix *x = [MMPerformanceFix new];
        x.key = [@"wrapup:" stringByAppendingString:plan.subject.path ?: w.path]; x.kind = @"wrapup"; x.expert = @"core";
        x.wrapUp = plan; x.actions = @[]; x.diskBack = plan.freedBytes;
        NSMutableOrderedSet *rows = [NSMutableOrderedSet new];
        NSMutableSet *counted = [NSMutableSet new];
        for (MMWrapUpPart *p in plan.parts) {
            MMFinding *f = p.action.finding;
            if ((p.step == MMWrapUpServers || p.step == MMWrapUpHelpers) && f.findingID && ![counted containsObject:RowKey(f)]) {
                [counted addObject:RowKey(f)]; x.memoryBack += f.cost.ramBytes;
            }
            if (byKey[RowKey(f)]) [rows addObject:RowKey(f)];
            if (f.findingID) [inFix addObject:f.findingID];
        }
        x.rows = rows.array;
        [removedTrees addObject:plan.subject.path ?: w.path];
        [fixes addObject:x];
    }

    // One fix per kind of action the experts offer, of every finding outside the Wrap Ups that MustKeep lets go.
    NSMutableDictionary<NSString *, NSMutableArray<MMFinding *> *> *byKind = [NSMutableDictionary new];
    for (MMFinding *f in s.findings) {
        NSString *kind = FixKind(f);
        if (!kind || f.kept || [inFix containsObject:f.findingID] || !byKey[RowKey(f)]) continue;
        if ([kind isEqualToString:@"remove"]) {
            MMWorktree *tree = nil;
            for (MMWorktree *w in facts.worktrees) if ([w.path isEqualToString:f.path]) tree = w;
            if (!tree || tree.isMain || [facts gitFor:tree].merged == MMMergedNone) continue;
        }
        id<MMExpert> e = MMExpertNamed(f.expert);
        id<MMExpertPolicy> policy = [e policy];
        if (!e || MMMustKeep(f, facts, nil, policy) || ![e actionFor:f step:MMStopTerm]) continue;
        if (!byKind[kind]) byKind[kind] = [NSMutableArray new];
        [byKind[kind] addObject:f];
    }
    for (MMFinding *f in byKind[@"remove"]) if (f.path) [removedTrees addObject:f.path];
    for (NSString *kind in @[@"stop", @"quit", @"remove", @"trash", @"clean"]) {
        NSMutableArray<id<MMAction>> *actions = [NSMutableArray new];
        NSMutableArray<NSString *> *rows = [NSMutableArray new];
        MMPerformanceFix *x = [MMPerformanceFix new];
        x.key = kind; x.kind = kind; x.needsYou = [kind isEqualToString:@"clean"];
        for (MMFinding *f in byKind[kind]) {
            // What a removed worktree holds goes with it, so a cache inside one is not a fix of its own.
            BOOL inside = NO;
            if ([kind isEqualToString:@"trash"] || [kind isEqualToString:@"clean"])
                for (NSString *t in removedTrees) if (PathIn(f.path, t)) inside = YES;
            if (inside) continue;
            id<MMExpert> e = MMExpertNamed(f.expert);
            [actions addObject:[e actionFor:f step:MMStopTerm]];
            [rows addObject:RowKey(f)];
            x.expert = f.expert; x.policy = [e policy];
            if ([kind isEqualToString:@"stop"] || [kind isEqualToString:@"quit"]) x.memoryBack += f.cost.ramBytes;
            else x.diskBack += f.cost.diskFreed;
        }
        if (!actions.count) continue;
        x.actions = actions; x.rows = rows;
        [fixes addObject:x];
    }

    // The groups, biggest first.
    NSMutableArray *mg = [NSMutableArray new], *dg = [NSMutableArray new];
    for (NSString *g in [MemoryOrder() arrayByAddingObjectsFromArray:DiskOrder()]) {
        MMPerformanceGroup *x = [MMPerformanceGroup new];
        x.key = g; x.fold = MMPerformanceFold(g);
        x.side = [DiskOrder() containsObject:g] ? MMPerformanceDisk : MMPerformanceMemory;
        x.rows = Sorted(groups[g]);
        [x.side == MMPerformanceDisk ? dg : mg addObject:x];
        for (MMPerformanceRow *r in x.rows) if (r.needsYou) m.needsYou++;
    }
    m.memoryGroups = mg; m.diskGroups = dg; m.byKey = byKey;

    // The memory ring: each process once, servers first, then agents, helpers and apps.
    NSMutableSet<NSNumber *> *claimed = [NSMutableSet new];
    NSMutableDictionary<NSString *, NSNumber *> *mem = [NSMutableDictionary new];
    for (NSString *g in @[MMPerformanceServers, MMPerformanceAgents, MMPerformanceHelpers]) {
        uint64_t n = 0;
        for (MMPerformanceRow *r in groups[g]) n += Claim(sample, r.finding, claimed);
        mem[g] = @(n);
    }
    NSMutableDictionary<NSNumber *, NSNumber *> *held = [NSMutableDictionary new];
    if (sample && groups[MMPerformanceApps].count)
        for (NSNumber *t in claimed) {
            NSNumber *rp = @(MMResponsiblePidIn(sample, t.intValue));
            held[rp] = @([held[rp] unsignedLongLongValue] + [sample proc:t.intValue].footprint);
        }
    uint64_t an = 0;
    for (MMPerformanceRow *r in groups[MMPerformanceApps]) an += AppClaim(sample, r.finding, held);
    mem[MMPerformanceApps] = @(an);
    m.memory = [MMPerformanceSideRing side:MMPerformanceMemory total:NSProcessInfo.processInfo.physicalMemory
                                      used:MemoryUsed(history ?: s.history)
                                     order:@[MMPerformanceServers, MMPerformanceAgents, MMPerformanceApps, MMPerformanceHelpers] bytes:mem];

    // The disk ring: a cache inside a worktree row counts in caches and clutter, so it comes off that worktree.
    uint64_t clutter = 0, trees = 0;
    for (MMPerformanceRow *r in groups[MMPerformanceClutter]) clutter += r.number;
    for (MMPerformanceRow *t in groups[MMPerformanceWorktrees]) {
        uint64_t inside = 0;
        for (MMPerformanceRow *c in groups[MMPerformanceClutter]) if (PathIn(c.finding.path, t.finding.path)) inside += c.number;
        trees += t.number > inside ? t.number - inside : 0;
    }
    MMPower *power = facts.power;
    uint64_t dt = power.diskTotal, df = MIN(power.diskFree, dt);
    m.disk = [MMPerformanceSideRing side:MMPerformanceDisk total:dt used:dt - df order:DiskOrder()
                                   bytes:@{MMPerformanceWorktrees: @(trees), MMPerformanceClutter: @(clutter)}];

    // The order: the larger share of what comes back, memory and disk apart.
    double mw = PressureWeight(power), dw = df < 100ull * 1000 * 1000 * 1000 ? 3 : 1;
    uint64_t mt = m.memory.total, dtt = m.disk.total;
    for (MMPerformanceFix *x in fixes) {
        double a = mt ? (double)x.memoryBack / (double)mt * mw : 0, b = dtt ? (double)x.diskBack / (double)dtt * dw : 0;
        x.share = MAX(a, b);
    }
    [fixes sortUsingComparator:^NSComparisonResult(MMPerformanceFix *a, MMPerformanceFix *b) {
        if (a.share != b.share) return a.share > b.share ? NSOrderedAscending : NSOrderedDescending;
        if (a.memoryBack != b.memoryBack) return a.memoryBack > b.memoryBack ? NSOrderedAscending : NSOrderedDescending;
        if (a.diskBack != b.diskBack) return a.diskBack > b.diskBack ? NSOrderedAscending : NSOrderedDescending;
        return [a.key compare:b.key];
    }];
    m.fixes = fixes;
    return m;
}

- (NSDictionary *)json {
    NSMutableArray *mg = [NSMutableArray new], *dg = [NSMutableArray new], *fx = [NSMutableArray new];
    for (MMPerformanceGroup *g in self.memoryGroups) [mg addObject:g.json];
    for (MMPerformanceGroup *g in self.diskGroups) [dg addObject:g.json];
    for (MMPerformanceFix *f in self.fixes) [fx addObject:f.json];
    return @{@"generation": @(self.generation), @"ring": @{@"memory": self.memory.json ?: @{}, @"disk": self.disk.json ?: @{}},
             @"memory": mg, @"disk": dg, @"fixes": fx, @"lookBack": self.lookBack.json ?: @{}, @"needsYou": @(self.needsYou)};
}
@end
