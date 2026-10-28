// The one 5-second pass, the power facts and the pushed signals. Patterns P6 to P14 and P66.
// The pass is one KERN_PROC_ALL sysctl for every pid, then rusage and the socket table for our own uid.
// It starts from -[LHScanner sample] and ScanSockets in LocoHost Ports.m, and the power reads in Insomnia main.m.
// No subprocess runs here. AppKit is used for NSWorkspace and NSRunningApplication only.
#import "Core/Senses/MMSenses.h"
#import "Core/Runtime/MMRuntime.h"
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <os/lock.h>
#import <os/signpost.h>
#include <stdatomic.h>
#include <libproc.h>
#include <dlfcn.h>
#include <notify.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/event.h>
#include <sys/mount.h>
#include <netinet/in.h>
#include <netinet/tcp_fsm.h>
#include <net/route.h>
#include <net/if.h>

static const NSTimeInterval kPassEvery = 5, kPassLeeway = 1;
static const NSTimeInterval kPassBudget = 0.25;   // wall time; an overrun skips the next turn
// Issue #52: the pass backs off on battery and while the person is away from the keyboard and pointer.
static const NSTimeInterval kAwayAfter = 300;
static const double kBatteryFactor = 2, kAwayFactor = 3;
// A process that used no CPU time keeps its sockets this long, plus up to 15 seconds by pid, so carried
// sockets are not all read again in the same pass.
static const uint64_t kSocketCarryNs = 45ull * NSEC_PER_SEC;

/// The tick's signposts: the pass here, and the rebuild and each expert's findings in the graph.
static os_log_t MMTickLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "tick"); });
    return log;
}

#pragma mark - P7 identity

static BOOL KInfo(pid_t pid, struct kinfo_proc *k) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t len = sizeof *k;
    return sysctl(mib, 4, k, &len, NULL, 0) == 0 && len == sizeof *k;
}

/// A zombie counts as gone: it has exited and only waits for its parent to read its status.
BOOL MMProcAlive(MMProcKey key) {
    struct kinfo_proc k;
    if (key.pid <= 0 || !KInfo(key.pid, &k)) return NO;
    return k.kp_proc.p_pid == key.pid && k.kp_proc.p_stat != SZOMB && (uint64_t)k.kp_proc.p_starttime.tv_sec == key.startSec;
}

NSString *MMProcKeyString(MMProcKey key) { return [NSString stringWithFormat:@"%d:%llu", key.pid, key.startSec]; }

#pragma mark - P7 MMProc

@interface MMProc () {
@public
    pid_t _pid, _ppid; uid_t _uid; uint64_t _startSec;
    double _cpuPercent, _energyRank, _energyDelta; uint64_t _footprint;
    NSString *_name;
    BOOL _idle;                           // our own process, same start, and no CPU time used since the last pass
}
@end

@implementation MMProc
- (pid_t)pid { return _pid; }
- (pid_t)ppid { return _ppid; }
- (uid_t)uid { return _uid; }
- (uint64_t)startSec { return _startSec; }
- (MMProcKey)key { return (MMProcKey){_pid, _startSec}; }
- (NSString *)name { return _name; }
- (double)cpuPercent { return _cpuPercent; }
- (double)energyRank { return _energyRank; }
- (uint64_t)footprint { return _footprint; }
- (NSString *)description { return [NSString stringWithFormat:@"<%@ %d %@>", self.class, _pid, _name]; }
@end

#pragma mark - P6 and P8 MMSample

static NSArray<NSString *> *ProcessArgs(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return @[];
    char *buf = malloc(size);
    if (!buf || sysctl(mib, 3, buf, &size, NULL, 0) != 0) { free(buf); return @[]; }
    int argc = 0; memcpy(&argc, buf, sizeof(int));
    char *p = buf + sizeof(int), *end = buf + size;
    while (p < end && *p) p++;            // the exec path
    while (p < end && !*p) p++;           // its padding
    NSMutableArray *args = [NSMutableArray new];
    for (int i = 0; i < argc && p < end; i++) {
        size_t n = strnlen(p, (size_t)(end - p));
        NSString *a = [[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding];
        if (a) [args addObject:a];
        p += n + 1;
    }
    free(buf);
    return args;
}

static NSString *ProcessCwd(pid_t pid) {
    struct proc_vnodepathinfo v;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, sizeof v) != sizeof v) return nil;
    return v.pvi_cdir.vip_path[0] ? @(v.pvi_cdir.vip_path) : nil;
}

/// Bumped on every app launch or quit that NSWorkspace reports, so app lookups kept across samples are read again.
static _Atomic uint64_t gAppGeneration;
static uint64_t NowNs(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static const uint64_t kCwdCarryNs = 30ull * NSEC_PER_SEC;

@interface MMSample () {
@public                                   // MMSenses reads these two to make a sample without exited processes
    NSDictionary<NSNumber *, NSArray<NSNumber *> *> *_kids;
    NSData *_sockets;
@private
    os_unfair_lock _lock;
    NSMutableDictionary *_args, *_cwds, *_treeCPU, *_treeFoot, *_socketsByPid;
    // Kept across samples for the same process, issue #52. _cwdAt holds when each cwd was read, in NowNs.
    NSMutableDictionary *_cwdAt, *_resp, *_owner, *_appOf;
    uint64_t _appGen;
}
@property (readwrite) NSDate *at;
@property (readwrite) uint64_t generation;
@property (readwrite) NSDictionary<NSNumber *, MMProc *> *procs;
- (pid_t)responsibleOf:(pid_t)pid;
- (NSRunningApplication *)appOf:(pid_t)pid;
- (NSRunningApplication *)ownerOf:(pid_t)pid compute:(NSRunningApplication *(^)(void))compute;
@end

@implementation MMSample

- (instancetype)initWithProcs:(NSDictionary *)procs kids:(NSDictionary *)kids sockets:(NSData *)sockets
                           at:(NSDate *)at generation:(uint64_t)generation {
    if ((self = [super init])) {
        _procs = procs; _kids = kids; _sockets = sockets; _at = at; _generation = generation;
        _lock = OS_UNFAIR_LOCK_INIT;
        _args = [NSMutableDictionary new]; _cwds = [NSMutableDictionary new];
        _treeCPU = [NSMutableDictionary new]; _treeFoot = [NSMutableDictionary new];
        _cwdAt = [NSMutableDictionary new]; _resp = [NSMutableDictionary new];
        _owner = [NSMutableDictionary new]; _appOf = [NSMutableDictionary new];
        _appGen = atomic_load(&gAppGeneration);
    }
    return self;
}

static BOOL SameProc(MMProc *a, MMProc *b) {
    if (a && a == b) return YES;   // a process object the pass kept
    return a && b && a->_startSec == b->_startSec && a->_ppid == b->_ppid && [a->_name isEqualToString:b->_name];
}

/// Issue #52. Takes what old read for every process that is still the same one: same pid, start time, parent
/// and name. An exec changes the name, so its args are read again. Runs in the pass, before the sample is published.
- (void)carryFrom:(MMSample *)old now:(uint64_t)nowNs args:(uint64_t *)argsCarried cwds:(uint64_t *)cwdsCarried {
    if (!old) return;
    os_unfair_lock_lock(&old->_lock);
    NSDictionary *args = [old->_args copy], *cwds = [old->_cwds copy], *cwdAt = [old->_cwdAt copy], *resp = [old->_resp copy];
    BOOL sameApps = old->_appGen == _appGen;
    NSDictionary *owner = sameApps ? [old->_owner copy] : nil, *appOf = sameApps ? [old->_appOf copy] : nil;
    os_unfair_lock_unlock(&old->_lock);
    NSDictionary<NSNumber *, MMProc *> *mine = _procs, *theirs = old->_procs;
    __block uint64_t na = 0, nc = 0;
    [args enumerateKeysAndObjectsUsingBlock:^(NSNumber *pid, id v, BOOL *stop) {
        if (SameProc(mine[pid], theirs[pid])) { self->_args[pid] = v; na++; }
    }];
    [cwds enumerateKeysAndObjectsUsingBlock:^(NSNumber *pid, id v, BOOL *stop) {
        MMProc *p = mine[pid];
        uint64_t at = [cwdAt[pid] unsignedLongLongValue];
        // A process that did not run cannot have changed folder. One that ran is read again after 30 seconds.
        if (!SameProc(p, theirs[pid]) || !(p->_idle || nowNs - at < kCwdCarryNs)) return;
        self->_cwds[pid] = v; self->_cwdAt[pid] = cwdAt[pid] ?: @(nowNs); nc++;
    }];
    [resp enumerateKeysAndObjectsUsingBlock:^(NSNumber *pid, id v, BOOL *stop) {
        if (SameProc(mine[pid], theirs[pid])) self->_resp[pid] = v;
    }];
    [owner enumerateKeysAndObjectsUsingBlock:^(NSNumber *pid, id v, BOOL *stop) {
        if (SameProc(mine[pid], theirs[pid])) self->_owner[pid] = v;
    }];
    [appOf enumerateKeysAndObjectsUsingBlock:^(NSNumber *pid, id v, BOOL *stop) {
        if (SameProc(mine[pid], theirs[pid])) self->_appOf[pid] = v;
    }];
    if (argsCarried) *argsCarried = na;
    if (cwdsCarried) *cwdsCarried = nc;
}

- (BOOL)unchanged:(pid_t)pid { MMProc *p = _procs[@(pid)]; return p && p->_idle; }

- (MMProc *)proc:(pid_t)pid { return _procs[@(pid)]; }

/// One memo per sample. The value is read outside the lock, so a slow read never holds it.
- (id)memo:(NSMutableDictionary *)memo pid:(pid_t)pid make:(id (^)(void))make {
    os_unfair_lock_lock(&_lock);
    id hit = memo[@(pid)];
    os_unfair_lock_unlock(&_lock);
    if (hit) return hit;
    id v = make() ?: NSNull.null;
    os_unfair_lock_lock(&_lock);
    memo[@(pid)] = v;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (NSArray<NSString *> *)argsOf:(pid_t)pid {
    if (!_procs[@(pid)]) return @[];
    return [self memo:_args pid:pid make:^id { return ProcessArgs(pid); }];
}

- (NSString *)cwdOf:(pid_t)pid {
    if (!_procs[@(pid)]) return nil;
    __block BOOL read = NO;
    id v = [self memo:_cwds pid:pid make:^id { read = YES; return ProcessCwd(pid); }];
    if (read) { os_unfair_lock_lock(&_lock); _cwdAt[@(pid)] = @(NowNs()); os_unfair_lock_unlock(&_lock); }
    return v == NSNull.null ? nil : v;
}

- (pid_t)responsibleOf:(pid_t)pid {
    if (!_procs[@(pid)]) return MMResponsiblePid(pid);
    return [[self memo:_resp pid:pid make:^id { return @(MMResponsiblePid(pid)); }] intValue];
}

- (NSRunningApplication *)appOf:(pid_t)pid {
    if (!_procs[@(pid)]) return [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    id v = [self memo:_appOf pid:pid make:^id { return [NSRunningApplication runningApplicationWithProcessIdentifier:pid]; }];
    return v == NSNull.null ? nil : v;
}

- (NSRunningApplication *)ownerOf:(pid_t)pid compute:(NSRunningApplication *(^)(void))compute {
    if (!_procs[@(pid)]) return compute();
    id v = [self memo:_owner pid:pid make:^id { return compute(); }];
    return v == NSNull.null ? nil : v;
}

- (NSArray<NSNumber *> *)childrenOf:(pid_t)pid { return _kids[@(pid)] ?: @[]; }   // frozen in the pass

- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max {
    if (!_procs[@(pid)] || max == 0) return @[];
    NSMutableArray *tree = [NSMutableArray arrayWithObject:@(pid)];
    NSMutableSet *seen = [NSMutableSet setWithObject:@(pid)];
    for (NSUInteger i = 0; i < tree.count && tree.count < max; i++)
        for (NSNumber *k in _kids[tree[i]]) {
            if (tree.count >= max) break;
            if (![seen containsObject:k]) { [seen addObject:k]; [tree addObject:k]; }
        }
    return [tree copy];
}

- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *up = [NSMutableArray new];
    MMProc *p = _procs[@(pid)];
    while (p && up.count < hops && p->_ppid > 0 && p->_ppid != p->_pid) {
        [up addObject:@(p->_ppid)];
        if (p->_ppid == 1) break;
        p = _procs[@(p->_ppid)];
    }
    return [up copy];
}

- (double)treeCPU:(pid_t)pid {
    return [[self memo:_treeCPU pid:pid make:^id {
        double sum = 0;
        for (NSNumber *t in [self treeOf:pid limit:500]) { double c = self->_procs[t]->_cpuPercent; if (c > 0) sum += c; }
        return @(sum);
    }] doubleValue];
}

- (uint64_t)treeFootprint:(pid_t)pid {
    return [[self memo:_treeFoot pid:pid make:^id {
        uint64_t sum = 0;
        for (NSNumber *t in [self treeOf:pid limit:500]) sum += self->_procs[t]->_footprint;
        return @(sum);
    }] unsignedLongLongValue];
}

- (const MMSocket *)sockets:(NSUInteger *)count {
    if (count) *count = _sockets.length / sizeof(MMSocket);
    return _sockets.bytes;
}

- (NSArray<NSValue *> *)socketsOf:(pid_t)pid {
    os_unfair_lock_lock(&_lock);
    if (!_socketsByPid) {
        NSMutableDictionary *m = [NSMutableDictionary new];
        const MMSocket *s = _sockets.bytes;
        for (NSUInteger i = 0; i < _sockets.length / sizeof(MMSocket); i++) {
            NSMutableArray *a = m[@(s[i].pid)] ?: (m[@(s[i].pid)] = [NSMutableArray new]);
            [a addObject:[NSValue valueWithBytes:&s[i] objCType:@encode(MMSocket)]];
        }
        for (NSNumber *k in m.allKeys) m[k] = [m[k] copy];   // callers get immutable arrays
        _socketsByPid = m;
    }
    NSArray *a = _socketsByPid[@(pid)] ?: @[];
    os_unfair_lock_unlock(&_lock);
    return a;
}

@end

#pragma mark - P9 owners

pid_t MMResponsiblePid(pid_t pid) {
    static pid_t (*fn)(pid_t);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid"); });
    pid_t r = fn ? fn(pid) : pid;
    return r > 0 ? r : pid;
}

@interface MMApp ()
@property (readwrite) pid_t pid;
@property (readwrite, copy) NSString *bundleID, *name, *bundlePath;
@property (readwrite) NSInteger policy;
@property (readwrite) NSRunningApplication *app;
@end
@implementation MMApp
@end

static const uint64_t kAppsMaxAgeNs = 300ull * NSEC_PER_SEC;
static os_unfair_lock gAppsLock = OS_UNFAIR_LOCK_INIT;
static NSArray<MMApp *> *gApps;
static uint64_t gAppsGen, gAppsAt;

/// Each app's identity, read from LaunchServices once per app. The list is walked again when an app launches or
/// quits, and an app already in it keeps what was read, so a launch costs one app's reads. Every 5 minutes each
/// app is read again, which catches one that changed its activation policy.
NSArray<MMApp *> *MMRunningApps(void) {
    uint64_t gen = atomic_load(&gAppGeneration), now = NowNs();
    os_unfair_lock_lock(&gAppsLock);
    NSArray<MMApp *> *have = gApps;
    BOOL stale = !have || now - gAppsAt >= kAppsMaxAgeNs;
    BOOL fresh = have && !stale && gAppsGen == gen;
    os_unfair_lock_unlock(&gAppsLock);
    if (fresh) return have;
    NSMutableDictionary<NSNumber *, MMApp *> *old = [NSMutableDictionary new];
    if (!stale) for (MMApp *a in have) old[@(a.pid)] = a;
    NSMutableArray<MMApp *> *out = [NSMutableArray new];
    for (NSRunningApplication *ra in NSWorkspace.sharedWorkspace.runningApplications) {
        pid_t pid = ra.processIdentifier;
        if (pid <= 0) continue;
        MMApp *was = old[@(pid)];
        if (was && was.app == ra) { [out addObject:was]; continue; }
        if (ra.terminated) continue;
        MMApp *a = [MMApp new];
        a.pid = pid; a.bundleID = ra.bundleIdentifier; a.name = ra.localizedName;
        a.bundlePath = ra.bundleURL.path; a.policy = ra.activationPolicy; a.app = ra;
        [out addObject:a];
    }
    NSArray *list = [out copy];
    os_unfair_lock_lock(&gAppsLock);
    gApps = list; gAppsGen = gen;
    if (stale) gAppsAt = now;
    os_unfair_lock_unlock(&gAppsLock);
    return list;
}

static BOOL IsSample(MMSample *s) { return [(NSObject *)s isKindOfClass:MMSample.class]; }

pid_t MMResponsiblePidIn(MMSample *s, pid_t pid) {
    return IsSample(s) ? [s responsibleOf:pid] : MMResponsiblePid(pid);
}

NSRunningApplication *MMAppWithPid(MMSample *s, pid_t pid) {
    if (pid <= 0) return nil;
    return IsSample(s) ? [s appOf:pid] : [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
}

/// From AppOf in LocoHost Where.m:62: the process itself, its parents, then its responsible app.
static NSRunningApplication *OwningApp(MMSample *s, pid_t pid) {
    NSMutableArray<NSNumber *> *chain = [NSMutableArray arrayWithObject:@(pid)];
    [chain addObjectsFromArray:[s ancestorsOf:pid limit:20]];
    pid_t r = MMResponsiblePidIn(s, pid);
    if (r > 1 && r != pid) [chain addObject:@(r)];
    NSArray<MMApp *> *apps = MMRunningApps();
    NSMutableDictionary<NSNumber *, MMApp *> *byPid = [NSMutableDictionary dictionaryWithCapacity:apps.count];
    for (MMApp *a in apps) byPid[@(a.pid)] = a;
    for (NSNumber *p in chain) {
        if (p.intValue <= 1) continue;
        MMApp *a = byPid[p];
        if (a.bundleID && a.policy == NSApplicationActivationPolicyRegular) return a.app;
    }
    // A helper whose path sits inside a running app's bundle belongs to that app.
    for (NSNumber *p in chain) {
        char buf[PROC_PIDPATHINFO_MAXSIZE];
        if (p.intValue <= 1 || proc_pidpath(p.intValue, buf, sizeof buf) <= 0) continue;
        NSString *exec = @(buf);
        NSRange app = [exec rangeOfString:@".app/Contents/"];
        if (app.location == NSNotFound) continue;
        NSString *bundle = [exec substringToIndex:app.location + 4];
        for (MMApp *a in apps)
            if ([a.bundlePath isEqualToString:bundle] && a.policy == NSApplicationActivationPolicyRegular) return a.app;
    }
    return nil;
}

NSRunningApplication *MMOwningApp(MMSample *s, pid_t pid) {
    if (!IsSample(s)) return OwningApp(s, pid);
    return [s ownerOf:pid compute:^NSRunningApplication *{ return OwningApp(s, pid); }];
}

#pragma mark - P13 and P14 MMPower

@interface MMPower ()
@property (readwrite) NSDate *at;
@property (readwrite) BOOL onAC, lidClosed, lowPowerMode, lidOverride, online;
@property (readwrite) int batteryPercent;
@property (readwrite) NSProcessInfoThermalState thermal;
@property (readwrite) NSInteger memoryPressure;
@property (readwrite) uint64_t diskFree;
@property (readwrite) NSDictionary<NSNumber *, NSArray<NSDictionary *> *> *assertionsByPid;
@end

@implementation MMPower
@end

static BOOL RootDomainBool(io_service_t rd, CFStringRef key) {
    if (!rd) return NO;
    CFTypeRef v = IORegistryEntryCreateCFProperty(rd, key, kCFAllocatorDefault, 0);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}

static io_service_t RootDomain(void) {
    static io_service_t rd; static dispatch_once_t once;
    dispatch_once(&once, ^{ rd = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")); });
    return rd;
}

/// YES when the routing table holds an up default route, IPv4 or IPv6. One NET_RT_FLAGS sysctl per family.
static BOOL HasDefaultRoute(void) {
    int families[2] = { AF_INET, AF_INET6 };
    for (int f = 0; f < 2; f++) {
        int mib[6] = { CTL_NET, PF_ROUTE, 0, families[f], NET_RT_FLAGS, RTF_GATEWAY };
        size_t len = 0;
        if (sysctl(mib, 6, NULL, &len, NULL, 0) != 0 || len == 0) continue;
        char *buf = malloc(len);
        if (!buf) continue;
        BOOL found = NO;
        if (sysctl(mib, 6, buf, &len, NULL, 0) == 0) {
            for (char *p = buf; p + sizeof(struct rt_msghdr) <= buf + len && !found; ) {
                struct rt_msghdr *rtm = (struct rt_msghdr *)p;
                if (rtm->rtm_msglen == 0) break;
                struct sockaddr *dst = (struct sockaddr *)(rtm + 1);
                if ((rtm->rtm_flags & RTF_UP) && (rtm->rtm_addrs & RTA_DST) && !(rtm->rtm_flags & RTF_IFSCOPE)) {
                    if (dst->sa_family == AF_INET) found = ((struct sockaddr_in *)dst)->sin_addr.s_addr == 0;
                    else if (dst->sa_family == AF_INET6) found = IN6_IS_ADDR_UNSPECIFIED(&((struct sockaddr_in6 *)dst)->sin6_addr);
                }
                p += rtm->rtm_msglen;
            }
        }
        free(buf);
        if (found) return YES;
    }
    return NO;
}

/// Every fact from IOKit, sysctl, statfs or NSProcessInfo. Never pmset.
static MMPower *ReadPowerFromSystem(void) {
    MMPower *p = [MMPower new];
    p.at = NSDate.date;
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    CFStringRef type = info ? IOPSGetProvidingPowerSourceType(info) : NULL;
    p.onAC = !type || CFStringCompare(type, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
    p.batteryPercent = -1;
    CFArrayRef list = info ? IOPSCopyPowerSourcesList(info) : NULL;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
        if (![d[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
        double cur = [d[@kIOPSCurrentCapacityKey] doubleValue], max = [d[@kIOPSMaxCapacityKey] doubleValue];
        if (max > 0) p.batteryPercent = (int)(100.0 * cur / max + 0.5);
    }
    if (list) CFRelease(list);
    if (info) CFRelease(info);

    io_service_t rd = RootDomain();
    p.lidClosed = RootDomainBool(rd, CFSTR("AppleClamshellState"));
    p.lidOverride = RootDomainBool(rd, CFSTR("SleepDisabled"));
    p.online = HasDefaultRoute();
    NSProcessInfo *pi = NSProcessInfo.processInfo;
    p.lowPowerMode = pi.isLowPowerModeEnabled;
    p.thermal = pi.thermalState;
    int level = 1; size_t len = sizeof level;
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, NULL, 0) != 0) level = 1;
    p.memoryPressure = level;
    struct statfs fs;
    if (statfs(NSHomeDirectory().fileSystemRepresentation, &fs) == 0) p.diskFree = (uint64_t)fs.f_bavail * fs.f_bsize;
    CFDictionaryRef byPid = NULL;
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        NSDictionary *d = CFBridgingRelease(byPid);
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:d.count];
        for (id k in d) if ([k isKindOfClass:NSNumber.class] && [d[k] isKindOfClass:NSArray.class]) out[k] = d[k];
        p.assertionsByPid = out;
    } else {
        p.assertionsByPid = @{};
    }
    return p;
}

#ifdef MM_TESTS
static id<MMPowerSource> gPowerSource;
static os_unfair_lock gPowerSourceLock = OS_UNFAIR_LOCK_INIT;

void MMUsePowerSource(id<MMPowerSource> source) {
    os_unfair_lock_lock(&gPowerSourceLock);
    gPowerSource = source;
    os_unfair_lock_unlock(&gPowerSourceLock);
}

MMPower *MMPowerFrom(NSDictionary *facts) {
    MMPower *p = [MMPower new];
    p.at = NSDate.date; p.onAC = YES; p.online = YES; p.batteryPercent = -1; p.memoryPressure = 1; p.assertionsByPid = @{};
    for (NSString *k in facts) [p setValue:facts[k] forKey:k];
    return p;
}
#endif

static MMPower *ReadPower(void) {
#ifdef MM_TESTS
    os_unfair_lock_lock(&gPowerSourceLock);
    id<MMPowerSource> src = gPowerSource;
    os_unfair_lock_unlock(&gPowerSourceLock);
    if (src) return [src read];
#endif
    return ReadPowerFromSystem();
}

#pragma mark - P10 sockets

/// The socket fds of one pid, listed into a buffer reused for every pid. One call while the buffer is big enough.
/// Returns the count, and in *hash a digest of the socket fd numbers. Senses queue only.
static int ListSocketFds(pid_t pid, int32_t **out, uint64_t *hash) {
    static struct proc_fdinfo *fds; static int cap;
    static int32_t *socks; static int socksCap;
    *hash = 0;
    if (!fds) { cap = 512 * (int)sizeof(struct proc_fdinfo); fds = malloc((size_t)cap); if (!fds) { cap = 0; return 0; } }
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, cap);
    while (size >= cap - (int)sizeof(struct proc_fdinfo)) {   // it may not have fit: grow and ask again
        int need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (need <= 0) return 0;
        free(fds); cap = (need + 32 * (int)sizeof(struct proc_fdinfo)) * 2; fds = malloc((size_t)cap);
        if (!fds) { cap = 0; return 0; }
        size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, cap);
    }
    if (size <= 0) return 0;
    int n = size / (int)sizeof(struct proc_fdinfo), count = 0;
    if (n > socksCap) { free(socks); socksCap = n * 2; socks = malloc(sizeof(int32_t) * (size_t)socksCap); if (!socks) { socksCap = 0; return 0; } }
    uint64_t h = 0x9e3779b97f4a7c15ull;
    for (int i = 0; i < n; i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
        socks[count++] = fds[i].proc_fd;
        uint64_t x = (uint64_t)fds[i].proc_fd * 0xff51afd7ed558ccdull;
        h += x ^ (x >> 29);
    }
    *hash = h + (uint64_t)count;
    *out = socks;
    return count;
}

/// The TCP sockets, LISTEN and ESTABLISHED, of one pid's socket fds. From ScanSockets in LocoHost Ports.m:326.
/// tcp gets the fd numbers that held a TCP socket in any state, so the next pass can read those alone.
static void ScanSocketFds(pid_t pid, const int32_t *fds, int n, NSMutableData *out, NSMutableData *tcp) {
    for (int i = 0; i < n; i++) {
            struct socket_fdinfo si;
            if (proc_pidfdinfo(pid, fds[i], PROC_PIDFDSOCKETINFO, &si, sizeof si) != sizeof si) continue;
            if (si.psi.soi_kind != SOCKINFO_TCP) continue;
            [tcp appendBytes:&fds[i] length:sizeof fds[i]];
            struct tcp_sockinfo *t = &si.psi.soi_proto.pri_tcp;
            if (t->tcpsi_state != TCPS_LISTEN && t->tcpsi_state != TCPS_ESTABLISHED) continue;
            struct in_sockinfo *in = &t->tcpsi_ini;
            MMSocket s; memset(&s, 0, sizeof s);   // padding too, since the graph digests the bytes
            s.pid = pid;
            s.state = t->tcpsi_state == TCPS_LISTEN ? MMSocketListen : MMSocketEstablished;
            s.localPort = ntohs((uint16_t)in->insi_lport);
            s.remotePort = ntohs((uint16_t)in->insi_fport);
            if (in->insi_vflag & INI_IPV6) {
                struct in6_addr *l = &in->insi_laddr.ina_6, *f = &in->insi_faddr.ina_6;
                if (IN6_IS_ADDR_V4MAPPED(l) || (IN6_IS_ADDR_UNSPECIFIED(l) && IN6_IS_ADDR_V4MAPPED(f))) {
                    s.family = AF_INET;
                    memcpy(s.localAddr, &l->s6_addr[12], 4);
                    memcpy(s.remoteAddr, &f->s6_addr[12], 4);
                } else {
                    s.family = AF_INET6;
                    memcpy(s.localAddr, l, 16);
                    memcpy(s.remoteAddr, f, 16);
                }
            } else {
                s.family = AF_INET;
                memcpy(s.localAddr, &in->insi_laddr.ina_46.i46a_addr4, 4);
                memcpy(s.remoteAddr, &in->insi_faddr.ina_46.i46a_addr4, 4);
            }
            [out appendBytes:&s length:sizeof s];
    }
}

#pragma mark - P6 and P11 to P13 MMSenses

@interface MMSenseObserver : NSObject
@property MMSignal mask;
@property (copy) void (^block)(MMSignal changed, id detail);
@end
@implementation MMSenseObserver @end

typedef struct { uint64_t start; double cpuNs; double energyNj; } MMPrevUse;
/// Where one pid's sockets sit in the last pass's table, and when they were last read from the kernel.
/// fdHash digests the pid's socket fd numbers. A pid with no TCP socket whose socket fds are the same ones keeps
/// its empty list without a read of each socket.
typedef struct { uint64_t start, readNs, fdHash; NSUInteger loc, len; } MMSocketSeen;

static const uint64_t kDiskMarks[] = { 50ull << 30, 20ull << 30, 10ull << 30, 5ull << 30, 2ull << 30, 1ull << 30 };

static NSInteger DiskBand(uint64_t freeBytes) {
    NSInteger band = 0;
    for (size_t i = 0; i < sizeof kDiskMarks / sizeof kDiskMarks[0]; i++) if (freeBytes < kDiskMarks[i]) band++;
    return band;
}

static void RootDomainMessage(void *ctx, io_service_t service, natural_t type, void *arg);

@implementation MMSenses {
    dispatch_queue_t _q;
    os_unfair_lock _lock;                 // guards _latest, _power and _observers
    MMSample *_latest;
    MMPower *_power;
    NSMutableArray<MMSenseObserver *> *_observers;
    // Pass state, touched only on _q.
    NSMutableDictionary<NSNumber *, NSValue *> *_prevUse;
    uint64_t _prevWallNs, _generation;
    double _tbScale;
    BOOL _started;                        // on _q
    BOOL _observing;                      // under _lock
    NSArray<NSDictionary *> *_noteTokens;  // under _lock: the notification observers start added
    dispatch_source_t _timer, _kqSource, _memSource;
    int _kq, _notifyToken;
    NSMutableDictionary<NSNumber *, NSNumber *> *_watched;   // pid -> start time
    IONotificationPortRef _ioPort;
    io_object_t _ioNotifier;
    // Issue #52, on _q: the last pass's socket table and where each pid's part of it sits.
    NSData *_prevSocks;
    NSDictionary<NSNumber *, NSValue *> *_sockSeen;
    NSDictionary<NSNumber *, NSData *> *_tcpFds;     // pid to the fds that held a TCP socket when last read
    NSTimeInterval _base, _interval;       // _interval and _reason under _lock
    NSString *_reason;
    BOOL _noBackoff;
    io_registry_entry_t _hid;
    MMSensesCounts _counts;                // under _lock
    uint64_t _timedPassAt;                 // under _lock: when the timer last started a pass, in NowNs
}

static void *kSensesQueueKey = &kSensesQueueKey;

+ (instancetype)shared {
    static MMSenses *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMSenses new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = MMQueue(@"core", @"senses", QOS_CLASS_UTILITY);
        dispatch_queue_set_specific(_q, kSensesQueueKey, kSensesQueueKey, NULL);
        _lock = OS_UNFAIR_LOCK_INIT;
        _observers = [NSMutableArray new];
        _prevUse = [NSMutableDictionary new];
        _watched = [NSMutableDictionary new];
        _kq = -1;
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        _tbScale = (double)tb.numer / tb.denom;
        NSDictionary *env = NSProcessInfo.processInfo.environment;
        double tick = [env[@"MINMACS_TICK"] doubleValue];
        _base = tick >= 0.2 ? tick : kPassEvery;
        _noBackoff = [env[@"MINMACS_NO_BACKOFF"] isEqualToString:@"1"];
        _interval = _base; _reason = @"base";
    }
    return self;
}

- (NSTimeInterval)interval { os_unfair_lock_lock(&_lock); NSTimeInterval i = _interval; os_unfair_lock_unlock(&_lock); return i; }
- (NSString *)intervalReason { os_unfair_lock_lock(&_lock); NSString *r = _reason; os_unfair_lock_unlock(&_lock); return r; }
- (MMSensesCounts)counts { os_unfair_lock_lock(&_lock); MMSensesCounts c = _counts; os_unfair_lock_unlock(&_lock); return c; }

- (NSTimeInterval)untilNextPass {
    os_unfair_lock_lock(&_lock);
    uint64_t at = _timedPassAt; NSTimeInterval every = _interval; BOOL on = _observing;
    os_unfair_lock_unlock(&_lock);
    if (!on || !at) return 0;
    double since = (double)(NowNs() - at) / NSEC_PER_SEC;
    return MAX(0, every - since);
}

/// Seconds since the last key press or pointer move, from IOHIDSystem's HIDIdleTime. 0 when it cannot be read.
- (double)awaySeconds {
#ifdef MM_TESTS
    const char *fake = getenv("MINMACS_AWAY_SECONDS");   // tests set how long the person has been away
    if (fake && *fake) return atof(fake);
#endif
    if (!_hid) _hid = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"));
    if (!_hid) return 0;
    CFTypeRef v = IORegistryEntryCreateCFProperty(_hid, CFSTR("HIDIdleTime"), kCFAllocatorDefault, 0);
    uint64_t ns = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberSInt64Type, &ns);
    if (v) CFRelease(v);
    return ns / 1e9;
}

/// The interval for the power facts p, and the timer moved to it when it changed. Runs on _q.
- (void)pace:(MMPower *)p {
    NSTimeInterval want = _base;
    NSString *why = @"base";
    if (!_noBackoff && p) {
        BOOL battery = !p.onAC, away = [self awaySeconds] >= kAwayAfter;
        if (battery) want *= kBatteryFactor;
        if (away) want *= kAwayFactor;
        why = battery && away ? @"battery, away" : battery ? @"battery" : away ? @"away" : @"base";
    }
    os_unfair_lock_lock(&_lock);
    BOOL moved = want != _interval;
    _interval = want; _reason = why;
    os_unfair_lock_unlock(&_lock);
    if (moved && _timer)
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(want * NSEC_PER_SEC)),
                                  (uint64_t)(want * NSEC_PER_SEC), (uint64_t)(MAX(kPassLeeway, want / 5) * NSEC_PER_SEC));
}

- (MMSample *)latest { os_unfair_lock_lock(&_lock); MMSample *s = _latest; os_unfair_lock_unlock(&_lock); return s; }
- (MMPower *)power { os_unfair_lock_lock(&_lock); MMPower *p = _power; os_unfair_lock_unlock(&_lock); return p; }

#pragma mark Start

- (void)start {
    os_unfair_lock_lock(&_lock);
    BOOL first = !_observing;
    _observing = YES;
    os_unfair_lock_unlock(&_lock);
    if (!first) return;
    dispatch_async(_q, ^{
        if (self->_started) return;
        self->_started = YES;
        [self startPushedSources];
        __weak MMSenses *weak = self;
        self->_timer = MMTimer(self->_q, self->_base, MAX(kPassLeeway, self->_base / 5), ^{ [weak scheduledPass]; });
        [self scheduledPass];
    });
    // App, sleep and power state notifications. They arrive on the posting thread, main for NSWorkspace,
    // and only hand over to the Senses queue or to the observers.
    __weak MMSenses *weak = self;
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    NSMutableArray *tokens = [NSMutableArray new];
    void (^add)(NSNotificationCenter *, NSNotificationName, void (^)(NSNotification *)) =
        ^(NSNotificationCenter *c, NSNotificationName n, void (^block)(NSNotification *)) {
            [tokens addObject:@{@"center": c, @"token": [c addObserverForName:n object:nil queue:nil usingBlock:block]}];
        };
    for (NSNotificationName n in @[NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification])
        add(ws, n, ^(NSNotification *note) {
            atomic_fetch_add(&gAppGeneration, 1);   // app lookups kept across samples are read again
            [weak emit:MMSignalApp detail:note.userInfo[NSWorkspaceApplicationKey]];
        });
    for (NSNotificationName n in @[NSWorkspaceWillSleepNotification, NSWorkspaceDidWakeNotification])
        add(ws, n, ^(NSNotification *note) { [weak emit:MMSignalSleep detail:nil]; });
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSNotificationName n in @[NSProcessInfoThermalStateDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification])
        add(nc, n, ^(NSNotification *note) { [weak refreshPowerAsync]; });
    os_unfair_lock_lock(&_lock);
    _noteTokens = tokens;
    os_unfair_lock_unlock(&_lock);
}

/// Memory pressure, power source and lid. Each source runs on the Senses queue and re-reads the power facts.
- (void)stop {
    os_unfair_lock_lock(&_lock);
    BOOL was = _observing;
    _observing = NO;
    NSArray *tokens = _noteTokens;
    _noteTokens = nil;
    os_unfair_lock_unlock(&_lock);
    if (!was) return;
    for (NSDictionary *t in tokens) [t[@"center"] removeObserver:t[@"token"]];
    dispatch_sync(_q, ^{
        if (!self->_started) return;
        self->_started = NO;
        if (self->_timer) { dispatch_source_cancel(self->_timer); self->_timer = nil; }
        if (self->_memSource) { dispatch_source_cancel(self->_memSource); self->_memSource = nil; }
        if (self->_notifyToken) { notify_cancel(self->_notifyToken); self->_notifyToken = 0; }
        if (self->_ioNotifier) { IOObjectRelease(self->_ioNotifier); self->_ioNotifier = 0; }
        if (self->_ioPort) { IONotificationPortDestroy(self->_ioPort); self->_ioPort = NULL; }
    });
}

- (void)startPushedSources {
    __weak MMSenses *weak = self;
    _memSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
        DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, _q);
    dispatch_source_set_event_handler(_memSource, ^{ [weak refreshPower]; });
    dispatch_resume(_memSource);
    notify_register_dispatch(kIOPSNotifyAnyPowerSource, &_notifyToken, _q, ^(int token) { [weak refreshPower]; });
    _ioPort = IONotificationPortCreate(kIOMainPortDefault);
    io_service_t rd = RootDomain();
    if (_ioPort && rd) {
        IONotificationPortSetDispatchQueue(_ioPort, _q);
        IOServiceAddInterestNotification(_ioPort, rd, kIOGeneralInterest, RootDomainMessage,
                                         (__bridge void *)self, &_ioNotifier);
    }
    [self ensureKqueue];
}

static void RootDomainMessage(void *ctx, io_service_t service, natural_t type, void *arg) {
    if (type == kIOPMMessageClamshellStateChange) [(__bridge MMSenses *)ctx refreshPower];
}

#pragma mark The pass

- (void)scheduledPass {
    os_unfair_lock_lock(&_lock);
    _timedPassAt = NowNs();
    os_unfair_lock_unlock(&_lock);
    [MMJob run:@"senses" expert:@"core" on:_q budget:kPassBudget work:^(MMJob *job) { [self pass]; }];
}

- (MMSample *)sampleNow {
    if (dispatch_get_specific(kSensesQueueKey)) { [self pass]; return self.latest; }
    dispatch_sync(_q, ^{
        MMBreadcrumbEnter(@"core", @"senses");
        [self pass];
        MMBreadcrumbLeave(@"core", @"senses");
    });
    return self.latest;
}

- (MMSample *)sampleWithout:(NSArray<NSValue *> *)keys {
    __block MMSample *out = nil;
    void (^work)(void) = ^{
        MMSample *old = self.latest;
        if (!old) { [self pass]; out = self.latest; return; }
        NSMutableSet<NSNumber *> *gone = [NSMutableSet new];
        for (NSValue *v in keys) {
            MMProcKey k; [v getValue:&k size:sizeof k];
            MMProc *p = old.procs[@(k.pid)];
            if (p && (k.startSec == 0 || p->_startSec == k.startSec)) [gone addObject:@(k.pid)];
        }
        if (!gone.count) { out = old; return; }
        NSMutableDictionary *procs = [old.procs mutableCopy];
        [procs removeObjectsForKeys:gone.allObjects];
        NSMutableDictionary<NSNumber *, NSArray *> *kids = [NSMutableDictionary dictionaryWithCapacity:old->_kids.count];
        [old->_kids enumerateKeysAndObjectsUsingBlock:^(NSNumber *ppid, NSArray *list, BOOL *stop) {
            if ([gone containsObject:ppid]) return;
            BOOL touched = NO;
            for (NSNumber *k in list) if ([gone containsObject:k]) { touched = YES; break; }
            if (!touched) { kids[ppid] = list; return; }
            NSMutableArray *left = [list mutableCopy];
            [left removeObjectsInArray:gone.allObjects];
            kids[ppid] = [left copy];
        }];
        NSMutableData *socks = [NSMutableData dataWithCapacity:old->_sockets.length];
        const MMSocket *sv = old->_sockets.bytes;
        for (NSUInteger i = 0; i < old->_sockets.length / sizeof(MMSocket); i++)
            if (![gone containsObject:@(sv[i].pid)]) [socks appendBytes:&sv[i] length:sizeof(MMSocket)];
        MMSample *s = [[MMSample alloc] initWithProcs:[procs copy] kids:kids sockets:[socks copy] at:old.at generation:++self->_generation];
        [s carryFrom:old now:NowNs() args:NULL cwds:NULL];
        os_unfair_lock_lock(&self->_lock);
        self->_latest = s;
        os_unfair_lock_unlock(&self->_lock);
        out = s;
    };
    if (dispatch_get_specific(kSensesQueueKey)) work(); else dispatch_sync(_q, work);
    return out;
}

/// The one pass. Runs on _q only.
- (void)pass {
    os_signpost_id_t sp = os_signpost_id_generate(MMTickLog());
    os_signpost_interval_begin(MMTickLog(), sp, "pass");
    uint64_t cpu0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    uint64_t nowNs = (uint64_t)(mach_absolute_time() * _tbScale);
    double wallDelta = _prevWallNs ? (double)(nowNs - _prevWallNs) : 0;
    uid_t me = getuid();

    // One sysctl for every process, root's included.
    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    size_t len = 0;
    struct kinfo_proc *kp = NULL;
    for (int tries = 0; tries < 4; tries++) {
        if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0) break;
        len += 64 * sizeof(struct kinfo_proc);
        free(kp); kp = malloc(len);
        if (!kp) break;
        if (sysctl(mib, 3, kp, &len, NULL, 0) == 0) break;
        if (errno != ENOMEM) { len = 0; break; }
        len = 0;
    }
    size_t n = kp ? len / sizeof(struct kinfo_proc) : 0;
    uint64_t cpuTable = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);

    NSMutableDictionary<NSNumber *, MMProc *> *procs = [NSMutableDictionary dictionaryWithCapacity:n];
    NSMutableDictionary<NSNumber *, NSMutableArray *> *kids = [NSMutableDictionary dictionaryWithCapacity:n / 2];
    NSMutableDictionary<NSNumber *, NSValue *> *use = [NSMutableDictionary dictionaryWithCapacity:n];
    MMProc *__unsafe_unretained *mine = (MMProc *__unsafe_unretained *)calloc(n + 1, sizeof(MMProc *));
    size_t mineCount = 0;
    double maxEnergy = 0;
    NSDictionary<NSNumber *, MMProc *> *before = self.latest.procs;
    for (size_t i = 0; i < n; i++) {
        struct kinfo_proc *k = &kp[i];
        pid_t pid = k->kp_proc.p_pid;
        // A zombie has exited and only waits for its parent to reap it, so it is left out, as MMProcAlive says.
        if (pid < 0 || k->kp_proc.p_stat == SZOMB) continue;
        uid_t uid = k->kp_eproc.e_ucred.cr_uid;
        uint64_t start = (uint64_t)k->kp_proc.p_starttime.tv_sec;
        // The same process as in the last pass keeps its name. Another user's process has nothing more to read,
        // so it keeps its whole object, which no pass changes once made.
        MMProc *was = before[@(pid)];
        size_t commLen = strnlen(k->kp_proc.p_comm, MAXCOMLEN);
        BOOL same = was && was->_startSec == start && was->_ppid == k->kp_eproc.e_ppid && was->_uid == uid &&
                    strlen(was->_name.UTF8String ?: "") == commLen && !strncmp(was->_name.UTF8String ?: "", k->kp_proc.p_comm, commLen);
        if (same && uid != me) {
            procs[@(pid)] = was;
            NSMutableArray *siblings = kids[@(was->_ppid)] ?: (kids[@(was->_ppid)] = [NSMutableArray new]);
            if (pid != was->_ppid) [siblings addObject:@(pid)];
            continue;
        }
        MMProc *p = [MMProc new];
        p->_pid = pid; p->_ppid = k->kp_eproc.e_ppid; p->_uid = uid;
        p->_startSec = start;
        p->_name = same ? was->_name : [[NSString alloc] initWithBytes:k->kp_proc.p_comm length:commLen encoding:NSUTF8StringEncoding] ?: @"?";
        p->_cpuPercent = -1;
        if (p->_uid == me && pid > 0) {
            struct rusage_info_v6 ru;
            if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&ru) == 0) {
                double cpuNs = (double)(ru.ri_user_time + ru.ri_system_time) * _tbScale;
                p->_footprint = ru.ri_phys_footprint;
                MMPrevUse now = { p->_startSec, cpuNs, (double)ru.ri_energy_nj }, prev;
                NSValue *pv = _prevUse[@(pid)];
                BOOL had = NO;
                if (pv) { [pv getValue:&prev size:sizeof prev]; had = prev.start == p->_startSec; }
                p->_cpuPercent = had && wallDelta > 0 ? MAX(0, (cpuNs - prev.cpuNs) / wallDelta * 100.0) : 0;
                p->_energyDelta = had ? MAX(0, now.energyNj - prev.energyNj) : 0;
                p->_idle = had && cpuNs == prev.cpuNs;
                // Idle in this pass and the one before, with the same footprint: the last object says it all.
                if (same && p->_idle && was->_idle && was->_cpuPercent == 0 && was->_footprint == p->_footprint &&
                    was->_energyDelta == 0 && was->_energyRank == 0)
                    p = was;
                if (p->_energyDelta > maxEnergy) maxEnergy = p->_energyDelta;
                use[@(pid)] = [NSValue valueWithBytes:&now objCType:@encode(MMPrevUse)];
            }
            mine[mineCount++] = p;
        }
        procs[@(pid)] = p;
        NSMutableArray *siblings = kids[@(p->_ppid)] ?: (kids[@(p->_ppid)] = [NSMutableArray new]);
        if (pid != p->_ppid) [siblings addObject:@(pid)];
    }
    if (maxEnergy > 0)
        for (MMProc *p in procs.objectEnumerator) if (p->_energyDelta > 0) p->_energyRank = p->_energyDelta / maxEnergy;
    free(kp);
    _prevUse = use; _prevWallNs = nowNs;

    uint64_t cpuProcs = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    // Sockets. A process that used no CPU time since it was last read keeps what it had, for a while.
    NSMutableData *socks = [NSMutableData dataWithCapacity:512 * sizeof(MMSocket)];
    NSMutableDictionary<NSNumber *, NSValue *> *seen = [NSMutableDictionary dictionaryWithCapacity:mineCount];
    NSMutableDictionary<NSNumber *, NSData *> *tcpFds = [NSMutableDictionary new];
    uint64_t scanned = 0, carried = 0;
    const uint8_t *prevBytes = _prevSocks.bytes;
    NSUInteger prevLen = _prevSocks.length;
    for (size_t j = 0; j < mineCount; j++) {
        MMProc *p = mine[j];
        MMSocketSeen was = {0}, now = { p->_startSec, nowNs, 0, socks.length, 0 };
        NSValue *v = _sockSeen[@(p->_pid)];
        BOOL had = NO, keep = NO;
        if (v) {
            [v getValue:&was size:sizeof was];
            uint64_t maxAge = kSocketCarryNs + (uint64_t)(p->_pid % 16) * NSEC_PER_SEC;
            had = was.start == p->_startSec && nowNs - was.readNs < maxAge && was.loc + was.len <= prevLen;
        }
        keep = had && p->_idle;
        now.fdHash = was.fdHash;
        NSData *tcpWas = had ? _tcpFds[@(p->_pid)] : nil;
        if (!keep) {
            int32_t *fds = NULL; uint64_t hash = 0;
            int nfds = ListSocketFds(p->_pid, &fds, &hash);
            now.fdHash = hash;
            if (had && hash == was.fdHash) {
                // It ran, but holds the same socket fds. Those that were not TCP are still not, so only the TCP ones
                // are read again, for their state. With none, it keeps its empty list.
                if (tcpWas.length) {
                    NSMutableData *tcp = [NSMutableData new];
                    ScanSocketFds(p->_pid, tcpWas.bytes, (int)(tcpWas.length / sizeof(int32_t)), socks, tcp);
                    tcpWas = tcp;
                    scanned++;
                    now.readNs = was.readNs;   // every socket fd is read again once the full read is a minute old
                    now.len = socks.length - now.loc;
                    seen[@(p->_pid)] = [NSValue valueWithBytes:&now objCType:@encode(MMSocketSeen)];
                    if (tcp.length) tcpFds[@(p->_pid)] = tcp;
                    continue;
                }
                keep = YES;
            } else {
                NSMutableData *tcp = [NSMutableData new];
                ScanSocketFds(p->_pid, fds, nfds, socks, tcp);
                tcpWas = tcp;
                scanned++;
            }
        }
        if (keep) {
            if (was.len) [socks appendBytes:prevBytes + was.loc length:was.len];
            now.readNs = was.readNs;
            carried++;
        }
        if (tcpWas.length) tcpFds[@(p->_pid)] = tcpWas;
        now.len = socks.length - now.loc;
        seen[@(p->_pid)] = [NSValue valueWithBytes:&now objCType:@encode(MMSocketSeen)];
    }
    free(mine);
    _prevSocks = socks; _sockSeen = seen; _tcpFds = tcpFds;

    uint64_t cpuSockets = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    NSMutableDictionary<NSNumber *, NSArray *> *frozen = [NSMutableDictionary dictionaryWithCapacity:kids.count];
    [kids enumerateKeysAndObjectsUsingBlock:^(NSNumber *k, NSMutableArray *v, BOOL *stop) { frozen[k] = [v copy]; }];
    MMSample *s = [[MMSample alloc] initWithProcs:[procs copy] kids:frozen sockets:[socks copy] at:NSDate.date generation:++_generation];
    uint64_t argsCarried = 0, cwdsCarried = 0;
    [s carryFrom:self.latest now:NowNs() args:&argsCarried cwds:&cwdsCarried];
    uint64_t cpuCarry = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    MMPower *p = ReadPower();
    MMPower *old = self.power;
    uint64_t cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu0;
    os_unfair_lock_lock(&_lock);
    _latest = s; _power = p;
    _counts.passes++; _counts.pids += s.procs.count; _counts.argsCarried += argsCarried; _counts.cwdsCarried += cwdsCarried;
    _counts.socketPidsScanned += scanned; _counts.socketPidsCarried += carried; _counts.cpuNs += cpu;
    _counts.tableNs += cpuTable - cpu0; _counts.procsNs += cpuProcs - cpuTable; _counts.socketsNs += cpuSockets - cpuProcs;
    _counts.carryNs += cpuCarry - cpuSockets; _counts.powerNs += cpu0 + cpu - cpuCarry;
    os_unfair_lock_unlock(&_lock);
    os_signpost_interval_end(MMTickLog(), sp, "pass", "%zu pids, %llu socket reads, %llu carried", s.procs.count, scanned, carried);
    [self pace:p];
    [self emit:MMSignalSample | [self changesFrom:old to:p] detail:nil];
}

- (MMSignal)changesFrom:(MMPower *)a to:(MMPower *)b {
    if (!a || !b) return 0;
    MMSignal c = 0;
    if (a.memoryPressure != b.memoryPressure) c |= MMSignalMemory;
    if (DiskBand(a.diskFree) != DiskBand(b.diskFree)) c |= MMSignalDisk;
    if (a.thermal != b.thermal) c |= MMSignalThermal;
    if (a.onAC != b.onAC || a.batteryPercent != b.batteryPercent || a.lowPowerMode != b.lowPowerMode || a.online != b.online) c |= MMSignalPower;
    if (a.lidClosed != b.lidClosed || a.lidOverride != b.lidOverride) c |= MMSignalLid;
    return c;
}

- (void)refreshPowerAsync { dispatch_async(_q, ^{ [self refreshPower]; }); }

/// The power facts alone, for a pushed signal. Runs on _q.
- (void)refreshPower {
    MMPower *p = ReadPower();
    os_unfair_lock_lock(&_lock);
    MMPower *old = _power; _power = p;
    os_unfair_lock_unlock(&_lock);
    MMSignal c = [self changesFrom:old to:p];
    if (c & MMSignalPower) [self pace:p];   // plugging in returns to the base interval at once
    if (c) [self emit:c detail:nil];
}

#pragma mark P11 exits

- (void)ensureKqueue {
    if (_kq >= 0) return;
    _kq = kqueue();
    if (_kq < 0) return;
    _kqSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_kq, 0, _q);
    __weak MMSenses *weak = self;
    dispatch_source_set_event_handler(_kqSource, ^{ [weak drainKqueue]; });
    dispatch_resume(_kqSource);
}

- (void)drainKqueue {
    struct kevent ev[64]; struct timespec zero = {0, 0};
    int got;
    while ((got = kevent(_kq, NULL, 0, ev, 64, &zero)) > 0) {
        for (int i = 0; i < got; i++) {
            if (ev[i].filter != EVFILT_PROC || !(ev[i].fflags & NOTE_EXIT)) continue;
            pid_t pid = (pid_t)ev[i].ident;
            NSNumber *start = _watched[@(pid)];
            if (!start) continue;
            [_watched removeObjectForKey:@(pid)];
            [self emitExit:(MMProcKey){pid, start.unsignedLongLongValue}];
        }
        if (got < 64) break;
    }
}

- (void)emitExit:(MMProcKey)key {
    [self emit:MMSignalExit detail:[NSValue valueWithBytes:&key objCType:@encode(MMProcKey)]];
}

- (void)watchExits:(NSArray<NSValue *> *)keys {
    dispatch_async(_q, ^{
        [self ensureKqueue];
        for (NSValue *v in keys) {
            MMProcKey k; [v getValue:&k size:sizeof k];
            if (!MMProcAlive(k)) { [self emitExit:k]; continue; }
            struct kevent add;
            EV_SET(&add, k.pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
            if (self->_kq < 0 || kevent(self->_kq, &add, 1, NULL, 0, NULL) != 0) { [self emitExit:k]; continue; }
            // The pid may have ended and been reused between the check and the registration.
            if (!MMProcAlive(k)) {
                EV_SET(&add, k.pid, EVFILT_PROC, EV_DELETE, 0, 0, NULL);
                kevent(self->_kq, &add, 1, NULL, 0, NULL);
                [self emitExit:k];
                continue;
            }
            self->_watched[@(k.pid)] = @(k.startSec);
        }
    });
}

#pragma mark Observers

- (id)observe:(MMSignal)mask block:(void (^)(MMSignal changed, id detail))block {
    MMSenseObserver *o = [MMSenseObserver new];
    o.mask = mask; o.block = block;
    os_unfair_lock_lock(&_lock);
    [_observers addObject:o];
    os_unfair_lock_unlock(&_lock);
    return o;
}

- (void)stopObserving:(id)token {
    if (!token) return;
    os_unfair_lock_lock(&_lock);
    [_observers removeObjectIdenticalTo:token];
    os_unfair_lock_unlock(&_lock);
}

/// The only work Senses puts on main: calling each observer whose mask matches.
- (void)emit:(MMSignal)changed detail:(id)detail {
    if (!changed) return;
    os_unfair_lock_lock(&_lock);
    NSArray *obs = [_observers copy];
    os_unfair_lock_unlock(&_lock);
    if (!obs.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (MMSenseObserver *o in obs) {
            MMSignal mine = o.mask & changed;
            if (!mine) continue;
            os_unfair_lock_lock(&self->_lock);
            BOOL still = [self->_observers indexOfObjectIdenticalTo:o] != NSNotFound;
            os_unfair_lock_unlock(&self->_lock);
            if (still) o.block(mine, detail);
        }
    });
}

@end
