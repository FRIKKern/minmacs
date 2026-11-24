// `minmacs self`: what the running MinMacs app costs this Mac, from the kernel's own accounting of its process.
// Energy is left out: the kernel's billed energy did not read as joules on Apple silicon, and a wrong number is worse.
// It runs in the CLI process, finds the app's pid through core.sock's ping, and reads proc_pid_rusage of that pid
// twice, a window apart: the rate now, and the totals since launch. It reads only; it never signals or asks the app
// for anything but its pid. The budgets are PLAN.md section 9's, as tools/bench/budgets.json holds them.
#import <Foundation/Foundation.h>
#import <libproc.h>
#import <mach/mach_time.h>
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#import "UI/MMFormat.h"

static const double kBudgetCPU = 0.3;      // percent of one core, idle
static const double kBudgetWakeups = 1.0;  // package idle wakeups a second

/// One read of a process's accounting, in plain units.
typedef struct {
    BOOL ok;
    double cpu, childCPU;                   // seconds: the process, and its children that have ended
    double idleWakeups, interruptWakeups;   // counts since launch
    uint64_t footprint, peak, read, written, logicalWritten;  // bytes
    double running;                         // seconds since it started, by mach time, so a sleep does not count
} MMSelfRead;

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

/// The report from two reads `secs` apart: rates now, rates since launch, totals, and which budgets are over.
NSDictionary *MMSelfReport(pid_t pid, MMSelfRead a, MMSelfRead b, double secs) {
    double up = b.running;
    double cpuNow = Rate(a.cpu, b.cpu, secs) * 100, cpuAll = up > 0 ? b.cpu / up * 100 : 0;
    double wakeNow = Rate(a.idleWakeups, b.idleWakeups, secs), wakeAll = up > 0 ? b.idleWakeups / up : 0;
    NSMutableArray *over = [NSMutableArray new];
    if (cpuAll > kBudgetCPU) [over addObject:@"cpuSinceLaunch"];
    if (wakeAll > kBudgetWakeups) [over addObject:@"idleWakeupsSinceLaunch"];
    if (cpuNow > kBudgetCPU) [over addObject:@"cpuNow"];
    if (wakeNow > kBudgetWakeups) [over addObject:@"idleWakeupsNow"];
    return @{
        @"pid": @(pid), @"runningSeconds": @(round(up)),
        @"now": @{@"seconds": @(secs), @"cpuPercent": @(cpuNow), @"childCpuPercent": @(Rate(a.childCPU, b.childCPU, secs) * 100),
                  @"idleWakeupsPerSecond": @(wakeNow), @"interruptWakeupsPerSecond": @(Rate(a.interruptWakeups, b.interruptWakeups, secs)),
                  @"writtenBytes": @(b.written >= a.written ? b.written - a.written : 0)},
        @"sinceLaunch": @{@"cpuSeconds": @(b.cpu), @"cpuPercent": @(cpuAll), @"childCpuSeconds": @(b.childCPU),
                          @"childCpuPercent": @(up > 0 ? b.childCPU / up * 100 : 0),
                          @"idleWakeupsPerSecond": @(wakeAll), @"interruptWakeupsPerSecond": @(up > 0 ? b.interruptWakeups / up : 0)},
        @"memory": @{@"footprintBytes": @(b.footprint), @"peakBytes": @(b.peak)},
        @"disk": @{@"readBytes": @(b.read), @"writtenBytes": @(b.written), @"logicalWrittenBytes": @(b.logicalWritten)},
        @"budgets": @{@"cpuPercent": @(kBudgetCPU), @"idleWakeupsPerSecond": @(kBudgetWakeups)},
        @"over": over,
    };
}

static NSString *Pct(double v) { return [NSString stringWithFormat:v < 10 ? @"%.2f %%" : @"%.1f %%", v]; }
static NSString *Mark(double v, double budget) { return v > budget ? @"over the budget" : @"within the budget"; }

int MMSelfVerb(MMArgs *a) {
    double window = 5;
    NSString *w = [a option:@"--window"];
    if (w) {
        NSScanner *sc = [NSScanner scannerWithString:w];
        double n = 0;
        if (![sc scanDouble:&n] || !sc.isAtEnd || n < 0.5 || n > 60) { [a error:@"--window takes seconds from 0.5 to 60"]; return [a usageError]; }
        window = n;
    }
    if (a.words.count) return [a usageError];
    // The app's pid, from its own answer on core.sock. With no answer there is no app to read.
    pid_t pid = (pid_t)[[MMCoreSocket ask:@{@"verb": @"ping"} timeout:0.5][@"pid"] intValue];
    MMSelfRead first = MMSelfReadPid(pid);
    if (!first.ok) { [a error:@"No MinMacs app is running, so there is nothing of its own to measure."]; return MMExitFailed; }
    [NSThread sleepForTimeInterval:window];
    MMSelfRead second = MMSelfReadPid(pid);
    if (!second.ok) { [a error:@"MinMacs quit while it was measured."]; return MMExitFailed; }
    NSDictionary *j = MMSelfReport(pid, first, second, window);
    if (a.json) { [a printJSON:j]; return 0; }
    NSDictionary *now = j[@"now"], *all = j[@"sinceLaunch"];
    double cpuNow = [now[@"cpuPercent"] doubleValue], cpuAll = [all[@"cpuPercent"] doubleValue];
    double wakeNow = [now[@"idleWakeupsPerSecond"] doubleValue], wakeAll = [all[@"idleWakeupsPerSecond"] doubleValue];
    [a print:@"MinMacs %s, pid %d, running for %@", MM_VERSION, pid, MMDuration(second.running) ?: @"a few seconds"];
    [a print:@"Now, over %g s:  CPU %@, %.2f idle wakeups a second", window, Pct(cpuNow), wakeNow];
    [a print:@"Since launch:   CPU %@ (%@ of %g %%), %.2f idle wakeups a second (%@ of %g)", Pct(cpuAll), Mark(cpuAll, kBudgetCPU), kBudgetCPU,
             wakeAll, Mark(wakeAll, kBudgetWakeups), kBudgetWakeups];
    [a print:@"Tools it ran:   %@ CPU, %.1f s in all, counted once each has ended", Pct([all[@"childCpuPercent"] doubleValue]), second.childCPU];
    [a print:@"Memory:         %.1f MB now, %.1f MB at most", second.footprint / 1048576.0, second.peak / 1048576.0];
    [a print:@"Disk:           %.1f MB written, %.1f MB read since launch", second.written / 1e6, second.read / 1e6];
    return 0;
}
