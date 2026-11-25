// What a MinMacs app costs this Mac, from the kernel's own accounting of its process: proc_pid_rusage, read and never
// signalled. `minmacs self` reads the app twice, a window apart, and the menu window reads the app it runs in once a
// build, with the rate since the build before. Both make their report here, so the two say one thing.
// The budgets are PLAN.md section 9's, as tools/bench/budgets.json and docs/2.0/BENCH.md hold them: idle CPU 0.3 % of
// one core, at most 1 idle wakeup a second, and an idle footprint of 45 MB.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const double MMSelfBudgetCPU;         // percent of one core, idle
extern const double MMSelfBudgetWakeups;     // package idle wakeups a second
extern const uint64_t MMSelfBudgetMemory;    // bytes of footprint, 45 MB in 1024s

/// One read of a process's accounting, in plain units.
typedef struct {
    BOOL ok;
    double cpu, childCPU;                   // seconds: the process, and its children that have ended
    double idleWakeups, interruptWakeups;   // counts since launch
    uint64_t footprint, peak, read, written, logicalWritten;  // bytes
    double running;                         // seconds since it started, by mach time, so a sleep does not count
} MMSelfRead;

/// One proc_pid_rusage of pid. ok is NO when pid does not answer.
MMSelfRead MMSelfReadPid(pid_t pid);

/// The report from two reads `secs` apart: {pid, runningSeconds, now, sinceLaunch, memory, disk, budgets, over}.
/// With secs at 0 there is no rate now, and `now` is left out. `over` names each budget that is over:
/// cpuSinceLaunch, idleWakeupsSinceLaunch, memoryNow, cpuNow and idleWakeupsNow. The budgets a row judges by are the
/// first three, MMSelfJudged: a rate now over a few seconds counts the window that is drawing it.
NSDictionary *MMSelfReport(pid_t pid, MMSelfRead a, MMSelfRead b, double secs);

/// The budgets a row of MinMacs itself is judged by, in `over`'s words: cpuSinceLaunch, idleWakeupsSinceLaunch, memoryNow.
NSArray<NSString *> *MMSelfJudged(void);

/// One read of a MinMacs process, for `device`: since launch only, so it costs one proc_pid_rusage and no wait.
/// {pid, runningSeconds, sinceLaunch: {cpuPercent, idleWakeupsPerSecond}, memory: {footprintBytes, peakBytes},
/// budgets, over}, or nil when pid does not answer.
NSDictionary *_Nullable MMSelfSinceLaunch(pid_t pid);

/// This process's own report, for a build of the menu window's model: one proc_pid_rusage, no wait and no timer. The
/// rate now is over the time since an earlier read of this process, when that read is 1 to 120 seconds old; the read
/// it measures from moves on once it is 5 seconds old, as `minmacs self` measures over 5 seconds. Without one, `now`
/// is left out. It adds version and build, as core.sock's ping says them. Any queue; the caller keeps it off main.
NSDictionary *_Nullable MMSelfOnBuild(void);

/// The report of two reads with version and build, as `minmacs self` and MMSelfOnBuild make it. `before` with ok NO
/// or secs at 0 gives no now.
NSDictionary *MMSelfReportWith(pid_t pid, MMSelfRead before, MMSelfRead now, double secs, NSString *version, NSString *_Nullable build);

NS_ASSUME_NONNULL_END
