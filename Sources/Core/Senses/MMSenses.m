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

static const NSTimeInterval kPassEvery = 5, kPassLeeway = 1;
static const NSTimeInterval kPassBudget = 0.25;   // wall time; an overrun skips the next turn

#pragma mark - P7 identity

static BOOL KInfo(pid_t pid, struct kinfo_proc *k) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t len = sizeof *k;
    return sysctl(mib, 4, k, &len, NULL, 0) == 0 && len == sizeof *k;
}

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

@interface MMSample () {
    NSDictionary<NSNumber *, NSArray<NSNumber *> *> *_kids;
    NSData *_sockets;
    os_unfair_lock _lock;
    NSMutableDictionary *_args, *_cwds, *_treeCPU, *_treeFoot, *_socketsByPid;
}
@property (readwrite) NSDate *at;
@property (readwrite) uint64_t generation;
@property (readwrite) NSDictionary<NSNumber *, MMProc *> *procs;
@end

@implementation MMSample

- (instancetype)initWithProcs:(NSDictionary *)procs kids:(NSDictionary *)kids sockets:(NSData *)sockets
                           at:(NSDate *)at generation:(uint64_t)generation {
    if ((self = [super init])) {
        _procs = procs; _kids = kids; _sockets = sockets; _at = at; _generation = generation;
        _lock = OS_UNFAIR_LOCK_INIT;
        _args = [NSMutableDictionary new]; _cwds = [NSMutableDictionary new];
        _treeCPU = [NSMutableDictionary new]; _treeFoot = [NSMutableDictionary new];
    }
    return self;
}

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
    id v = [self memo:_cwds pid:pid make:^id { return ProcessCwd(pid); }];
    return v == NSNull.null ? nil : v;
}

- (NSArray<NSNumber *> *)childrenOf:(pid_t)pid { return _kids[@(pid)] ?: @[]; }

- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max {
    if (!_procs[@(pid)] || max == 0) return @[];
    NSMutableArray *tree = [NSMutableArray arrayWithObject:@(pid)];
    NSMutableSet *seen = [NSMutableSet setWithObject:@(pid)];
    for (NSUInteger i = 0; i < tree.count && tree.count < max; i++)
        for (NSNumber *k in _kids[tree[i]]) {
            if (tree.count >= max) break;
            if (![seen containsObject:k]) { [seen addObject:k]; [tree addObject:k]; }
        }
    return tree;
}

- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *up = [NSMutableArray new];
    MMProc *p = _procs[@(pid)];
    while (p && up.count < hops && p->_ppid > 0 && p->_ppid != p->_pid) {
        [up addObject:@(p->_ppid)];
        if (p->_ppid == 1) break;
        p = _procs[@(p->_ppid)];
    }
    return up;
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

/// From AppOf in LocoHost Where.m:62: the process itself, its parents, then its responsible app.
NSRunningApplication *MMOwningApp(MMSample *s, pid_t pid) {
    NSMutableArray<NSNumber *> *chain = [NSMutableArray arrayWithObject:@(pid)];
    [chain addObjectsFromArray:[s ancestorsOf:pid limit:20]];
    pid_t r = MMResponsiblePid(pid);
    if (r > 1 && r != pid) [chain addObject:@(r)];
    for (NSNumber *p in chain) {
        if (p.intValue <= 1) continue;
        NSRunningApplication *a = [NSRunningApplication runningApplicationWithProcessIdentifier:p.intValue];
        if (a.bundleIdentifier && a.activationPolicy == NSApplicationActivationPolicyRegular) return a;
    }
    // A helper whose path sits inside a running app's bundle belongs to that app.
    for (NSNumber *p in chain) {
        char buf[PROC_PIDPATHINFO_MAXSIZE];
        if (p.intValue <= 1 || proc_pidpath(p.intValue, buf, sizeof buf) <= 0) continue;
        NSString *exec = @(buf);
        NSRange app = [exec rangeOfString:@".app/Contents/"];
        if (app.location == NSNotFound) continue;
        NSString *bundle = [exec substringToIndex:app.location + 4];
        for (NSRunningApplication *ra in NSWorkspace.sharedWorkspace.runningApplications)
            if ([ra.bundleURL.path isEqualToString:bundle] && ra.activationPolicy == NSApplicationActivationPolicyRegular) return ra;
    }
    return nil;
}

#pragma mark - P13 and P14 MMPower

@interface MMPower ()
@property (readwrite) NSDate *at;
@property (readwrite) BOOL onAC, lidClosed, lowPowerMode, lidOverride;
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
    p.at = NSDate.date; p.onAC = YES; p.batteryPercent = -1; p.memoryPressure = 1; p.assertionsByPid = @{};
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

/// From ScanSockets in LocoHost Ports.m:326. One fd buffer is reused for every pid.
static void ScanSockets(const pid_t *pids, size_t n, NSMutableData *out) {
    static struct proc_fdinfo *fds; static int cap;
    for (size_t j = 0; j < n; j++) {
        pid_t pid = pids[j];
        int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (size <= 0) continue;
        size += 32 * (int)sizeof(struct proc_fdinfo);   // room for fds opened since the size query
        if (size > cap) { free(fds); cap = size * 2; fds = malloc((size_t)cap); if (!fds) { cap = 0; return; } }
        size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, cap);
        for (int i = 0; i < size / (int)sizeof(struct proc_fdinfo); i++) {
            if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo si;
            if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &si, sizeof si) != sizeof si) continue;
            if (si.psi.soi_kind != SOCKINFO_TCP) continue;
            struct tcp_sockinfo *t = &si.psi.soi_proto.pri_tcp;
            if (t->tcpsi_state != TCPS_LISTEN && t->tcpsi_state != TCPS_ESTABLISHED) continue;
            struct in_sockinfo *in = &t->tcpsi_ini;
            MMSocket s = {0};
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
}

#pragma mark - P6 and P11 to P13 MMSenses

@interface MMSenseObserver : NSObject
@property MMSignal mask;
@property (copy) void (^block)(MMSignal changed, id detail);
@end
@implementation MMSenseObserver @end

typedef struct { uint64_t start; double cpuNs; double energyNj; } MMPrevUse;

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
    dispatch_source_t _timer, _kqSource, _memSource;
    int _kq, _notifyToken;
    NSMutableDictionary<NSNumber *, NSNumber *> *_watched;   // pid -> start time
    IONotificationPortRef _ioPort;
    io_object_t _ioNotifier;
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
    }
    return self;
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
        self->_timer = MMTimer(self->_q, kPassEvery, kPassLeeway, ^{ [weak scheduledPass]; });
        [self scheduledPass];
    });
    // App, sleep and power state notifications. They arrive on the posting thread, main for NSWorkspace,
    // and only hand over to the Senses queue or to the observers.
    __weak MMSenses *weak = self;
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSNotificationName n in @[NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification])
        [ws addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
            [weak emit:MMSignalApp detail:note.userInfo[NSWorkspaceApplicationKey]];
        }];
    for (NSNotificationName n in @[NSWorkspaceWillSleepNotification, NSWorkspaceDidWakeNotification])
        [ws addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
            [weak emit:MMSignalSleep detail:nil];
        }];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    for (NSNotificationName n in @[NSProcessInfoThermalStateDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification])
        [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) { [weak refreshPowerAsync]; }];
}

/// Memory pressure, power source and lid. Each source runs on the Senses queue and re-reads the power facts.
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

/// The one pass. Runs on _q only.
- (void)pass {
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

    NSMutableDictionary<NSNumber *, MMProc *> *procs = [NSMutableDictionary dictionaryWithCapacity:n];
    NSMutableDictionary<NSNumber *, NSMutableArray *> *kids = [NSMutableDictionary dictionaryWithCapacity:n / 2];
    NSMutableDictionary<NSNumber *, NSValue *> *use = [NSMutableDictionary dictionaryWithCapacity:n];
    pid_t *mine = malloc(sizeof(pid_t) * (n + 1)); size_t mineCount = 0;
    double maxEnergy = 0;
    for (size_t i = 0; i < n; i++) {
        struct kinfo_proc *k = &kp[i];
        pid_t pid = k->kp_proc.p_pid;
        if (pid < 0) continue;
        MMProc *p = [MMProc new];
        p->_pid = pid; p->_ppid = k->kp_eproc.e_ppid; p->_uid = k->kp_eproc.e_ucred.cr_uid;
        p->_startSec = (uint64_t)k->kp_proc.p_starttime.tv_sec;
        p->_name = [[NSString alloc] initWithBytes:k->kp_proc.p_comm length:strnlen(k->kp_proc.p_comm, MAXCOMLEN)
                                          encoding:NSUTF8StringEncoding] ?: @"?";
        p->_cpuPercent = -1;
        if (p->_uid == me && pid > 0 && k->kp_proc.p_stat != SZOMB) {
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
                if (p->_energyDelta > maxEnergy) maxEnergy = p->_energyDelta;
                use[@(pid)] = [NSValue valueWithBytes:&now objCType:@encode(MMPrevUse)];
            }
            mine[mineCount++] = pid;
        }
        procs[@(pid)] = p;
        NSMutableArray *siblings = kids[@(p->_ppid)] ?: (kids[@(p->_ppid)] = [NSMutableArray new]);
        if (pid != p->_ppid) [siblings addObject:@(pid)];
    }
    if (maxEnergy > 0)
        for (MMProc *p in procs.objectEnumerator) p->_energyRank = p->_energyDelta / maxEnergy;
    free(kp);
    _prevUse = use; _prevWallNs = nowNs;

    NSMutableData *socks = [NSMutableData dataWithCapacity:512 * sizeof(MMSocket)];
    ScanSockets(mine, mineCount, socks);
    free(mine);

    MMSample *s = [[MMSample alloc] initWithProcs:procs kids:kids sockets:socks at:NSDate.date generation:++_generation];
    MMPower *p = ReadPower();
    MMPower *old = self.power;
    os_unfair_lock_lock(&_lock);
    _latest = s; _power = p;
    os_unfair_lock_unlock(&_lock);
    [self emit:MMSignalSample | [self changesFrom:old to:p] detail:nil];
}

- (MMSignal)changesFrom:(MMPower *)a to:(MMPower *)b {
    if (!a || !b) return 0;
    MMSignal c = 0;
    if (a.memoryPressure != b.memoryPressure) c |= MMSignalMemory;
    if (DiskBand(a.diskFree) != DiskBand(b.diskFree)) c |= MMSignalDisk;
    if (a.thermal != b.thermal) c |= MMSignalThermal;
    if (a.onAC != b.onAC || a.batteryPercent != b.batteryPercent || a.lowPowerMode != b.lowPowerMode) c |= MMSignalPower;
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
