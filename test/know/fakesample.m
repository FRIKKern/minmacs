// A small stand-in for Senses, for the Know checks only. It is compiled into test/know's tool and never into the app.
// It reads the live process table read-only: one KERN_PROC_ALL sysctl, KERN_PROCARGS2 for args, and
// proc_pid_rusage twice, half a second apart, for CPU. Power assertions come from IOPMCopyAssertionsByProcess.
#import "Core/Senses/MMSenses.h"
#import <libproc.h>
#import <mach/mach_time.h>
#import <sys/sysctl.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

@interface MMProc ()
@property (readwrite) pid_t pid, ppid;
@property (readwrite) uid_t uid;
@property (readwrite) uint64_t startSec;
@property (readwrite, copy) NSString *name;
@property (readwrite) double cpuPercent, energyRank;
@property (readwrite) uint64_t footprint;
@end
@implementation MMProc
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface MMPower ()
@property (readwrite) NSDictionary<NSNumber *, NSArray<NSDictionary *> *> *assertionsByPid;
@end
@implementation MMPower
@end

@interface MMSample ()
@property (readwrite) NSDate *at;
@property (readwrite) NSDictionary<NSNumber *, MMProc *> *procs;
@end

static NSArray<NSString *> *ArgsOf(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return @[];
    NSMutableData *buf = [NSMutableData dataWithLength:size];
    if (sysctl(mib, 3, buf.mutableBytes, &size, NULL, 0) != 0) return @[];
    const char *b = buf.bytes, *end = b + size;
    int argc; memcpy(&argc, b, sizeof argc);
    const char *p = b + sizeof argc;
    while (p < end && *p) p++;          // the executable path
    while (p < end && !*p) p++;         // its padding
    NSMutableArray *out = [NSMutableArray new];
    for (int i = 0; i < argc && p < end; i++) {
        NSString *a = [[NSString alloc] initWithBytes:p length:strnlen(p, (size_t)(end - p)) encoding:NSUTF8StringEncoding];
        [out addObject:a ?: @""];
        p += strnlen(p, (size_t)(end - p)) + 1;
    }
    return out;
}

static uint64_t CPUTime(pid_t pid, uint64_t *footprint) {
    struct rusage_info_v2 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&ri) != 0) return 0;
    if (footprint) *footprint = ri.ri_phys_footprint;
    return ri.ri_user_time + ri.ri_system_time;
}

@implementation MMSample {
    NSDictionary<NSNumber *, NSArray<NSNumber *> *> *_kids;
    NSMutableDictionary *_args;
}

+ (instancetype)live {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    sysctl(mib, 4, NULL, &len, NULL, 0);
    len += 64 * sizeof(struct kinfo_proc);
    struct kinfo_proc *kp = malloc(len);
    if (sysctl(mib, 4, kp, &len, NULL, 0) != 0) { free(kp); return nil; }
    size_t n = len / sizeof(struct kinfo_proc);
    uid_t me = getuid();
    NSMutableDictionary<NSNumber *, NSNumber *> *before = [NSMutableDictionary new];
    for (size_t i = 0; i < n; i++) if (kp[i].kp_eproc.e_ucred.cr_uid == me) before[@(kp[i].kp_proc.p_pid)] = @(CPUTime(kp[i].kp_proc.p_pid, NULL));
    uint64_t t0 = mach_absolute_time();
    usleep(500000);
    uint64_t dt = mach_absolute_time() - t0;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double wallNs = (double)dt * tb.numer / tb.denom;
    NSMutableDictionary *procs = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSMutableArray *> *kids = [NSMutableDictionary new];
    for (size_t i = 0; i < n; i++) {
        if (kp[i].kp_proc.p_stat == SZOMB) continue;   // an exited child its parent never reaped, as fakeagent's caffeinate
        MMProc *p = [MMProc new];
        p.pid = kp[i].kp_proc.p_pid; p.ppid = kp[i].kp_eproc.e_ppid;
        p.uid = kp[i].kp_eproc.e_ucred.cr_uid;
        p.startSec = (uint64_t)kp[i].kp_proc.p_starttime.tv_sec;
        p.name = @(kp[i].kp_proc.p_comm);
        p.cpuPercent = -1;
        if (p.uid == me) {
            uint64_t fp = 0, now = CPUTime(p.pid, &fp);
            // proc_pid_rusage times are in mach units on Apple silicon and in ns on Intel; scale both by the timebase.
            double used = (double)(now - MIN(now, [before[@(p.pid)] unsignedLongLongValue])) * tb.numer / tb.denom;
            p.cpuPercent = wallNs > 0 ? 100.0 * used / wallNs : 0;
            p.footprint = fp;
        }
        procs[@(p.pid)] = p;
        if (!kids[@(p.ppid)]) kids[@(p.ppid)] = [NSMutableArray new];
        if (p.pid != p.ppid) [kids[@(p.ppid)] addObject:@(p.pid)];
    }
    free(kp);
    MMSample *s = [MMSample new];
    s.at = NSDate.date; s.procs = procs;
    s->_kids = kids; s->_args = [NSMutableDictionary new];
    return s;
}

- (uint64_t)generation { return 1; }
- (MMProc *)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray<NSString *> *)argsOf:(pid_t)pid {
    @synchronized (_args) {
        if (!_args[@(pid)]) _args[@(pid)] = ArgsOf(pid);
        return _args[@(pid)];
    }
}
- (NSString *)cwdOf:(pid_t)pid {
    struct proc_vnodepathinfo v;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, sizeof v) <= 0) return nil;
    return v.pvi_cdir.vip_path[0] ? @(v.pvi_cdir.vip_path) : nil;
}
- (NSArray<NSNumber *> *)childrenOf:(pid_t)pid { return _kids[@(pid)] ?: @[]; }
- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max {
    NSMutableArray *t = [NSMutableArray arrayWithObject:@(pid)];
    for (NSUInteger i = 0; i < t.count && t.count < max; i++) [t addObjectsFromArray:_kids[t[i]] ?: @[]];
    return t;
}
- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *a = [NSMutableArray new];
    for (pid_t p = [self proc:pid].ppid; p > 0 && a.count < hops; p = [self proc:p].ppid) { [a addObject:@(p)]; if (p == 1) break; }
    return a;
}
- (double)treeCPU:(pid_t)pid {
    double c = 0;
    for (NSNumber *p in [self treeOf:pid limit:500]) c += MAX(0, [self proc:p.intValue].cpuPercent);
    return c;
}
- (uint64_t)treeFootprint:(pid_t)pid {
    uint64_t f = 0;
    for (NSNumber *p in [self treeOf:pid limit:500]) f += [self proc:p.intValue].footprint;
    return f;
}
- (const MMSocket *)sockets:(NSUInteger *)count { if (count) *count = 0; return NULL; }
- (NSArray<NSValue *> *)socketsOf:(pid_t)pid { return @[]; }
@end

MMPower *MMFakeLivePower(void) {
    MMPower *p = [MMPower new];
    CFDictionaryRef byPid = NULL;
    NSMutableDictionary *out = [NSMutableDictionary new];
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        NSDictionary *d = (__bridge NSDictionary *)byPid;
        for (NSNumber *pid in d) out[pid] = d[pid];
        CFRelease(byPid);
    }
    p.assertionsByPid = out;
    return p;
}
