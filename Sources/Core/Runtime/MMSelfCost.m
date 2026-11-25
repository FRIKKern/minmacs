// What a MinMacs app costs this Mac, MMSelfCost.h. Energy is left out: the kernel's billed energy did not read as
// joules on Apple silicon, and a wrong number is worse.
#import "Core/Runtime/MMSelfCost.h"
#import <libproc.h>
#import <mach/mach_time.h>
#import <os/lock.h>

#ifndef MM_VERSION
#define MM_VERSION "0.0.0"
#endif

const double MMSelfBudgetCPU = 0.3;
const double MMSelfBudgetWakeups = 1.0;
const uint64_t MMSelfBudgetMemory = 45ull * 1048576;

static double Ticks(uint64_t t) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)t * tb.numer / tb.denom / 1e9;
}

MMSelfRead MMSelfReadPid(pid_t pid) {
    MMSelfRead r = {0};
    struct rusage_info_v4 ri;
    if (pid <= 0 || proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return r;
    r.ok = YES;
    r.cpu = Ticks(ri.ri_user_time + ri.ri_system_time);
    r.childCPU = Ticks(ri.ri_child_user_time + ri.ri_child_system_time);
    r.idleWakeups = (double)ri.ri_pkg_idle_wkups;
    r.interruptWakeups = (double)ri.ri_interrupt_wkups;
    r.footprint = ri.ri_phys_footprint; r.peak = ri.ri_lifetime_max_phys_footprint;
    r.read = ri.ri_diskio_bytesread; r.written = ri.ri_diskio_byteswritten; r.logicalWritten = ri.ri_logical_writes;
    uint64_t now = mach_absolute_time();
    r.running = now > ri.ri_proc_start_abstime ? Ticks(now - ri.ri_proc_start_abstime) : 0;
    return r;
}

static double Rate(double a, double b, double secs) { return secs > 0 ? MAX(b - a, 0) / secs : 0; }

NSArray<NSString *> *MMSelfJudged(void) { return @[@"cpuSinceLaunch", @"idleWakeupsSinceLaunch", @"memoryNow"]; }

NSDictionary *MMSelfReport(pid_t pid, MMSelfRead a, MMSelfRead b, double secs) {
    double up = b.running;
    double cpuAll = up > 0 ? b.cpu / up * 100 : 0, wakeAll = up > 0 ? b.idleWakeups / up : 0;
    NSMutableArray *over = [NSMutableArray new];
    if (cpuAll > MMSelfBudgetCPU) [over addObject:@"cpuSinceLaunch"];
    if (wakeAll > MMSelfBudgetWakeups) [over addObject:@"idleWakeupsSinceLaunch"];
    if (b.footprint > MMSelfBudgetMemory) [over addObject:@"memoryNow"];
    NSMutableDictionary *j = [@{
        @"pid": @(pid), @"runningSeconds": @(round(up)),
        @"sinceLaunch": @{@"cpuSeconds": @(b.cpu), @"cpuPercent": @(cpuAll), @"childCpuSeconds": @(b.childCPU),
                          @"childCpuPercent": @(up > 0 ? b.childCPU / up * 100 : 0),
                          @"idleWakeupsPerSecond": @(wakeAll), @"interruptWakeupsPerSecond": @(up > 0 ? b.interruptWakeups / up : 0)},
        @"memory": @{@"footprintBytes": @(b.footprint), @"peakBytes": @(b.peak)},
        @"disk": @{@"readBytes": @(b.read), @"writtenBytes": @(b.written), @"logicalWrittenBytes": @(b.logicalWritten)},
        @"budgets": @{@"cpuPercent": @(MMSelfBudgetCPU), @"idleWakeupsPerSecond": @(MMSelfBudgetWakeups), @"memoryBytes": @(MMSelfBudgetMemory)},
    } mutableCopy];
    if (secs > 0) {
        double cpuNow = Rate(a.cpu, b.cpu, secs) * 100, wakeNow = Rate(a.idleWakeups, b.idleWakeups, secs);
        if (cpuNow > MMSelfBudgetCPU) [over addObject:@"cpuNow"];
        if (wakeNow > MMSelfBudgetWakeups) [over addObject:@"idleWakeupsNow"];
        j[@"now"] = @{@"seconds": @(secs), @"cpuPercent": @(cpuNow), @"childCpuPercent": @(Rate(a.childCPU, b.childCPU, secs) * 100),
                      @"idleWakeupsPerSecond": @(wakeNow), @"interruptWakeupsPerSecond": @(Rate(a.interruptWakeups, b.interruptWakeups, secs)),
                      @"writtenBytes": @(b.written >= a.written ? b.written - a.written : 0)};
    }
    j[@"over"] = over;
    return j;
}

NSDictionary *MMSelfSinceLaunch(pid_t pid) {
    MMSelfRead r = MMSelfReadPid(pid);
    if (!r.ok) return nil;
    NSDictionary *full = MMSelfReport(pid, r, r, 0);
    NSMutableArray *over = [NSMutableArray new];
    for (NSString *o in full[@"over"]) if ([o hasSuffix:@"SinceLaunch"]) [over addObject:o];
    NSDictionary *all = full[@"sinceLaunch"];
    return @{@"pid": @(pid), @"runningSeconds": full[@"runningSeconds"],
             @"sinceLaunch": @{@"cpuPercent": all[@"cpuPercent"], @"idleWakeupsPerSecond": all[@"idleWakeupsPerSecond"]},
             @"memory": full[@"memory"], @"budgets": full[@"budgets"], @"over": over};
}

NSDictionary *MMSelfReportWith(pid_t pid, MMSelfRead before, MMSelfRead now, double secs, NSString *version, NSString *build) {
    BOOL rate = before.ok && secs > 0;
    NSMutableDictionary *j = [MMSelfReport(pid, rate ? before : now, now, rate ? secs : 0) mutableCopy];
    j[@"version"] = version;
    if (build.length) j[@"build"] = build;
    return j;
}

NSDictionary *MMSelfOnBuild(void) {
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static MMSelfRead base;
    static uint64_t baseAt;
    pid_t me = getpid();
    MMSelfRead cur = MMSelfReadPid(me);
    if (!cur.ok) return nil;
    uint64_t at = mach_absolute_time();
    os_unfair_lock_lock(&lock);
    MMSelfRead from = base;
    double secs = from.ok && at > baseAt ? Ticks(at - baseAt) : 0;
    // The read it measures from moves on once it is 5 seconds old, or when it is too old to say what happens now.
    if (!from.ok || secs >= 5 || secs > 120) { base = cur; baseAt = at; }
    os_unfair_lock_unlock(&lock);
    NSString *build = [NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] description];
    return MMSelfReportWith(me, from, cur, secs >= 1 && secs <= 120 ? secs : 0, @MM_VERSION, build);
}
