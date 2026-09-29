#import "Scanner.h"
#import <libproc.h>
#import <mach/mach_time.h>
#import <dlfcn.h>

/// The pid macOS holds responsible for another (what Activity Monitor groups by).
/// Handles XPC services and helpers whose parent is launchd. Falls back to the pid itself.
static pid_t Responsible(pid_t pid) {
    static pid_t (*fn)(pid_t);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid"); });
    pid_t r = fn ? fn(pid) : pid;
    return r > 0 ? r : pid;
}

/// A GUI app that deserves its own bucket: regular apps, plus third-party menu bar apps.
/// Apple's own agents (Dock, Spotlight, WebKit helpers) and helper bundles roll up or go to background.
static BOOL IsBucket(NSRunningApplication *ra) {
    NSString *bid = ra.bundleIdentifier;
    if (!bid) return NO;
    if ([bid containsString:@".helper"] || [bid containsString:@".Helper"] || [bid hasPrefix:@"com.apple.WebKit"]) return NO;
    if (ra.activationPolicy == NSApplicationActivationPolicyRegular) return ![bid isEqualToString:@"com.apple.loginwindow"];
    if (ra.activationPolicy == NSApplicationActivationPolicyAccessory) return ![bid hasPrefix:@"com.apple."];
    return NO;
}

@implementation MMProc @end
@implementation MMApp @end

NSString *MMFormatBytes(uint64_t b) {
    if (b >= 1ull << 30) return [NSString stringWithFormat:@"%.1f GB", b / (double)(1ull << 30)];
    if (b >= 1ull << 20) return [NSString stringWithFormat:@"%.0f MB", b / (double)(1ull << 20)];
    return [NSString stringWithFormat:@"%.0f KB", b / 1024.0];
}

@implementation MMScanner {
    NSMutableDictionary<NSNumber *, NSNumber *> *_prevCpu;   // pid -> cpuNs
    uint64_t _prevWallNs;
    double _tbScale;                                          // mach units -> ns
}

- (instancetype)init {
    if ((self = [super init])) {
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        _tbScale = (double)tb.numer / tb.denom;
        _prevCpu = [NSMutableDictionary new];
    }
    return self;
}

- (void)sample {
    uint64_t now = mach_absolute_time() * _tbScale;
    double wallDelta = _prevWallNs ? (double)(now - _prevWallNs) : 0;

    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0) / sizeof(pid_t) + 64;
    pid_t *pids = calloc(n, sizeof(pid_t));
    n = proc_listpids(PROC_ALL_PIDS, 0, pids, n * sizeof(pid_t)) / sizeof(pid_t);

    NSMutableDictionary<NSNumber *, MMProc *> *procs = [NSMutableDictionary dictionaryWithCapacity:n];
    NSMutableDictionary<NSNumber *, NSNumber *> *cpuNow = [NSMutableDictionary dictionaryWithCapacity:n];
    double total = 0;
    for (int i = 0; i < n; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;
        struct proc_bsdinfo bi;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, sizeof(bi)) != sizeof(bi)) continue;
        struct rusage_info_v4 ru;
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ru) != 0) continue;
        MMProc *p = [MMProc new];
        p.pid = pid; p.ppid = bi.pbi_ppid;
        p.name = [NSString stringWithUTF8String:bi.pbi_name[0] ? bi.pbi_name : bi.pbi_comm];
        p.cpuNs = (ru.ri_user_time + ru.ri_system_time) * _tbScale;
        p.footprint = ru.ri_phys_footprint;
        NSNumber *prev = _prevCpu[@(pid)];
        p.cpuPercent = (prev && wallDelta > 0) ? MAX(0, (p.cpuNs - prev.doubleValue) / wallDelta * 100.0) : 0;
        total += p.cpuPercent;
        procs[@(pid)] = p;
        cpuNow[@(pid)] = @(p.cpuNs);
    }
    free(pids);
    _prevCpu = cpuNow; _prevWallNs = now;

    // GUI apps become buckets; everything else rolls up to the nearest app ancestor.
    NSMutableDictionary<NSNumber *, MMApp *> *appsByPid = [NSMutableDictionary new];
    pid_t me = getpid();
    for (NSRunningApplication *ra in NSWorkspace.sharedWorkspace.runningApplications) {
        if (ra.processIdentifier == me || !IsBucket(ra)) continue;
        MMApp *a = [MMApp new];
        a.app = ra; a.bundleID = ra.bundleIdentifier; a.name = ra.localizedName ?: ra.bundleIdentifier;
        appsByPid[@(ra.processIdentifier)] = a;
    }
    NSMutableArray<MMProc *> *loose = [NSMutableArray new];
    for (MMProc *p in procs.allValues) {
        MMApp *owner = appsByPid[@(Responsible(p.pid))];
        pid_t cur = p.pid;
        for (int hops = 0; !owner && hops < 12 && cur > 1; hops++) {
            if ((owner = appsByPid[@(cur)])) break;
            MMProc *parent = procs[@(cur)];
            if (!parent) break;
            cur = parent.ppid;
        }
        if (owner) { owner.cpuPercent += p.cpuPercent; owner.memory += p.footprint; owner.processCount++; }
        else if (p.pid != me) [loose addObject:p];
    }
    _apps = [appsByPid.allValues sortedArrayUsingComparator:^NSComparisonResult(MMApp *a, MMApp *b) {
        if (a.cpuPercent != b.cpuPercent) return a.cpuPercent < b.cpuPercent ? NSOrderedDescending : NSOrderedAscending;
        return a.memory < b.memory ? NSOrderedDescending : NSOrderedAscending;
    }];
    _unattributed = [loose sortedArrayUsingComparator:^NSComparisonResult(MMProc *a, MMProc *b) {
        return a.cpuPercent < b.cpuPercent ? NSOrderedDescending : a.cpuPercent > b.cpuPercent ? NSOrderedAscending : NSOrderedSame;
    }];
    _totalCPU = total;
}

@end
