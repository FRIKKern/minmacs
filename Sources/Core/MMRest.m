// The rest of the memory by kind, MMRest.h. The table is MMRestTable.m; here the processes no row claims are put in
// their categories, with the kept lookups that make a second pass cost a dictionary read a process.
#import "Core/MMRest.h"
#import "Core/MMPerformance.h"
#import <libproc.h>
#import <os/lock.h>

@interface MMRestProc ()
@property (readwrite) pid_t pid, ppid;
@property (readwrite) uint64_t startSec;
@property (readwrite) uid_t uid;
@property (readwrite, copy) NSString *name;
@property (readwrite, copy) NSString *human;
@property (readwrite) uint64_t bytes;
@property (readwrite) BOOL measured;
@property (readwrite) double cpuPercent;
@end
@implementation MMRestProc
- (NSString *)shownName { return self.human.length ? self.human : self.name ?: @""; }
@end

@interface MMRestCategory ()
@property (readwrite) MMRestKind *kind;
@property (readwrite) uint64_t bytes, unheld;
@property (readwrite) double cpuPercent;
@property (readwrite) NSArray<MMRestProc *> *procs;
@property (readwrite) NSInteger unmeasured;
@end
@implementation MMRestCategory
@end

#pragma mark - What the rows claim

static MMProcKey KeyOf(NSValue *v) { MMProcKey k = {0, 0}; [v getValue:&k size:sizeof k]; return k; }

NSSet<NSNumber *> *MMRestClaimed(MMPerformance *p, MMSample *sample) {
    NSMutableSet<NSNumber *> *claimed = [NSMutableSet new];
    if (!sample) return claimed;
    NSMutableSet<NSNumber *> *apps = [NSMutableSet new];
    for (MMPerformanceGroup *g in p.memoryGroups) {
        BOOL app = [g.key isEqualToString:MMPerformanceApps];
        for (MMPerformanceRow *r in g.rows) {
            for (NSValue *v in r.finding.procs) {
                MMProcKey k = KeyOf(v);
                MMProc *proc = [sample proc:k.pid];
                if (!proc || proc.startSec != k.startSec) continue;
                if (app) { [apps addObject:@(k.pid)]; continue; }
                [claimed addObjectsFromArray:[sample treeOf:k.pid limit:500]];
            }
        }
    }
    if (!apps.count) return claimed;
    // An app holds every process that rolls up into it, as MMPerformance rolls it: its responsible app, else the
    // first app among itself and its parents, 12 hops at most.
    for (NSNumber *n in sample.procs) {
        if ([claimed containsObject:n]) continue;
        pid_t pid = n.intValue;
        if ([apps containsObject:@(MMResponsiblePidIn(sample, pid))]) { [claimed addObject:n]; continue; }
        pid_t cur = pid;
        for (int hops = 0; hops < 12 && cur > 1; hops++) {
            if ([apps containsObject:@(cur)]) { [claimed addObject:n]; break; }
            MMProc *x = [sample proc:cur];
            if (!x) break;
            cur = x.ppid;
        }
    }
    return claimed;
}

#pragma mark - The kept lookups

/// What one process was found to be, kept for its life: by pid and start time, so a pid used again is looked up again.
@interface MMRestKnown : NSObject
@property uint64_t startSec;
@property (copy) NSString *key, *human, *fullName, *path;
@property uint64_t seenGeneration;
@end
@implementation MMRestKnown
@end

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, MMRestKnown *> *gKnown;
static NSUInteger gClassified, gPathsRead;

#ifdef MM_TESTS
static MMRestPathReader gTestReader;
void MMRestUsePathReader(MMRestPathReader reader) { gTestReader = [reader copy]; }
#endif

static NSString *ReadPath(pid_t pid, MMRestPathReader reader) {
#ifdef MM_TESTS
    if (!reader) reader = gTestReader;
#endif
    if (reader) return reader(pid);
    char buf[PROC_PIDPATHINFO_MAXSIZE];
    int n = proc_pidpath(pid, buf, sizeof buf);
    return n > 0 ? [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] : nil;
}

/// The kernel cuts a name at 15 or 16 characters. Such a name, and one the table does not know by name, is read by
/// its path once, and the path's last part gives the whole name.
static MMRestKnown *Lookup(MMSample *sample, MMProc *p, uid_t me, MMRestPathReader reader) {
    NSNumber *pid = @(p.pid);
    os_unfair_lock_lock(&gLock);
    MMRestKnown *k = gKnown[pid];
    if (k && k.startSec != p.startSec) k = nil;
    os_unfair_lock_unlock(&gLock);
    if (k) return k;
    NSString *name = p.name ?: @"";
    MMRestAnswer byName = MMRestByName(name);
    NSString *path = nil, *full = name;
    if (byName.needsPath || name.length >= 15) {
        path = ReadPath(p.pid, reader);
        os_unfair_lock_lock(&gLock); gPathsRead++; os_unfair_lock_unlock(&gLock);
        NSString *last = path.lastPathComponent;
        if (name.length >= 15 && [last hasPrefix:name]) full = last;
    }
    MMProc *parent = p.ppid > 1 ? [sample proc:p.ppid] : nil;
    MMRestAnswer a = MMRestClassify(full, path, parent.name, p.uid == me);
    k = [MMRestKnown new];
    k.startSec = p.startSec; k.key = a.key; k.human = a.human; k.fullName = full; k.path = path;
    os_unfair_lock_lock(&gLock);
    if (!gKnown) gKnown = [NSMutableDictionary new];
    gKnown[pid] = k; gClassified++;
    os_unfair_lock_unlock(&gLock);
    return k;
}

MMRestCounts MMRestCountsNow(void) {
    os_unfair_lock_lock(&gLock);
    MMRestCounts c = {gKnown.count, gClassified, gPathsRead};
    os_unfair_lock_unlock(&gLock);
    return c;
}

void MMRestForget(void) {
    os_unfair_lock_lock(&gLock);
    gKnown = nil; gClassified = 0; gPathsRead = 0;
    os_unfair_lock_unlock(&gLock);
}

#pragma mark - The categories

NSArray<MMRestCategory *> *MMRestBuild(MMSample *sample, NSSet<NSNumber *> *claimed, uint64_t rest, MMRestPathReader reader) {
    if (!sample) return @[];
    uid_t me = getuid();
    NSMutableDictionary<NSString *, NSMutableArray<MMRestProc *> *> *by = [NSMutableDictionary new];
    NSMutableSet<NSNumber *> *alive = [NSMutableSet setWithCapacity:sample.procs.count];
    for (NSNumber *n in sample.procs) {
        [alive addObject:n];
        MMProc *p = sample.procs[n];
        // pid 0 is the kernel, which the macOS category holds as what no process holds.
        if (p.pid <= 0 || [claimed containsObject:n]) continue;
        MMRestKnown *k = Lookup(sample, p, me, reader);
        MMRestProc *x = [MMRestProc new];
        x.pid = p.pid; x.ppid = p.ppid; x.startSec = p.startSec; x.uid = p.uid;
        x.name = k.fullName ?: p.name ?: @""; x.human = k.human;
        x.measured = p.uid == me;
        x.bytes = x.measured ? p.footprint : 0;
        x.cpuPercent = x.measured ? p.cpuPercent : -1;
        if (!by[k.key]) by[k.key] = [NSMutableArray new];
        [by[k.key] addObject:x];
    }
    // The kept lookups of processes that are gone go with them.
    os_unfair_lock_lock(&gLock);
    for (NSNumber *n in gKnown.allKeys) if (![alive containsObject:n]) [gKnown removeObjectForKey:n];
    os_unfair_lock_unlock(&gLock);

    NSMutableArray<MMRestCategory *> *out = [NSMutableArray new];
    uint64_t measured = 0;
    for (MMRestKind *kind in MMRestKinds()) {
        NSArray<MMRestProc *> *procs = by[kind.key];
        if (!procs.count && ![kind.key isEqualToString:MMRestMacOS]) continue;
        MMRestCategory *c = [MMRestCategory new];
        c.kind = kind;
        // Biggest first, the ones not measured after them by name, so the order holds between passes.
        c.procs = [procs ?: @[] sortedArrayUsingComparator:^NSComparisonResult(MMRestProc *a, MMRestProc *b) {
            if (a.measured != b.measured) return a.measured ? NSOrderedAscending : NSOrderedDescending;
            if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
            NSComparisonResult r = [a.shownName compare:b.shownName];
            return r != NSOrderedSame ? r : a.pid < b.pid ? NSOrderedAscending : NSOrderedDescending;
        }];
        double cpu = 0; BOOL anyCPU = NO;
        for (MMRestProc *p in c.procs) {
            if (!p.measured) { c.unmeasured++; continue; }
            c.bytes += p.bytes;
            if (p.cpuPercent >= 0) { cpu += p.cpuPercent; anyCPU = YES; }
        }
        c.cpuPercent = anyCPU ? cpu : -1;
        measured += c.bytes;
        [out addObject:c];
    }
    // macOS holds what the rest leaves once each process took its own: the kernel, wired and compressed memory and the
    // processes of other users. A footprint holds compressed pages too, so the measured ones can pass the rest; then
    // macOS holds only what it measured.
    for (MMRestCategory *c in out) if ([c.kind.key isEqualToString:MMRestMacOS]) { c.unheld = rest > measured ? rest - measured : 0; c.bytes += c.unheld; }
    [out filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMRestCategory *c, id _) { return c.bytes > 0 || c.procs.count > 0; }]];
    [out sortUsingComparator:^NSComparisonResult(MMRestCategory *a, MMRestCategory *b) {
        BOOL ae = [a.kind.key isEqualToString:MMRestElse], be = [b.kind.key isEqualToString:MMRestElse];
        if (ae != be) return ae ? NSOrderedDescending : NSOrderedAscending;
        if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
        return [a.kind.key compare:b.kind.key];
    }];
    return out;
}

#pragma mark - One process's details

NSDictionary *MMRestDetails(MMSample *sample, pid_t pid, MMRestPathReader reader) {
    NSMutableDictionary *d = [NSMutableDictionary new];
    MMProc *p = [sample proc:pid];
    if (!p) return d;
    os_unfair_lock_lock(&gLock);
    MMRestKnown *k = gKnown[@(pid)];
    NSString *kept = k && k.startSec == p.startSec ? k.path : nil;
    os_unfair_lock_unlock(&gLock);
    NSString *path = kept ?: ReadPath(pid, reader);
    if (path.length) d[@"path"] = path;
    MMProc *parent = p.ppid > 0 ? [sample proc:p.ppid] : nil;
    if (parent) { d[@"parent"] = parent.name ?: @""; d[@"parentPid"] = @(parent.pid); }
    pid_t resp = MMResponsiblePidIn(sample, pid);
    MMProc *by = resp != pid && resp > 0 ? [sample proc:resp] : nil;
    if (by.name.length) d[@"launchedBy"] = by.name;
    if (p.startSec > 0) d[@"startSec"] = @(p.startSec);
    return d;
}
