// `minmacs self`: what the running MinMacs app costs this Mac, from the kernel's own accounting of its process.
// Energy is left out: the kernel's billed energy did not read as joules on Apple silicon, and a wrong number is worse.
// It runs in the CLI process, finds the app's pid through core.sock's ping, and reads proc_pid_rusage of that pid
// twice, a window apart: the rate now, and the totals since launch. It reads only; it never signals or asks the app
// for anything but its pid, version and build. The report is Core's, MMSelfCost.h, which the menu window's row of
// MinMacs itself reads too, so the two say one thing.
#import <Foundation/Foundation.h>
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#import "UI/MMFormat.h"

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
    NSDictionary *ping = [MMCoreSocket ask:@{@"verb": @"ping"} timeout:0.5];
    pid_t pid = (pid_t)[ping[@"pid"] intValue];
    MMSelfRead first = MMSelfReadPid(pid);
    if (!first.ok) { [a error:@"No MinMacs app is running, so there is nothing of its own to measure."]; return MMExitFailed; }
    [NSThread sleepForTimeInterval:window];
    MMSelfRead second = MMSelfReadPid(pid);
    if (!second.ok) { [a error:@"MinMacs quit while it was measured."]; return MMExitFailed; }
    NSString *version = [ping[@"version"] isKindOfClass:NSString.class] ? ping[@"version"] : @MM_VERSION;
    NSString *build = [ping[@"build"] isKindOfClass:NSString.class] ? ping[@"build"] : nil;
    NSDictionary *j = MMSelfReportWith(pid, first, second, window, version, build);
    if (a.json) { [a printJSON:j]; return 0; }
    NSDictionary *now = j[@"now"], *all = j[@"sinceLaunch"];
    double cpuNow = [now[@"cpuPercent"] doubleValue], cpuAll = [all[@"cpuPercent"] doubleValue];
    double wakeNow = [now[@"idleWakeupsPerSecond"] doubleValue], wakeAll = [all[@"idleWakeupsPerSecond"] doubleValue];
    [a print:@"MinMacs %@%@, pid %d, running for %@", version, build.length ? [@", build " stringByAppendingString:build] : @"", pid, MMDuration(second.running) ?: @"a few seconds"];
    [a print:@"Now, over %g s:  CPU %@, %.2f idle wakeups a second", window, Pct(cpuNow), wakeNow];
    [a print:@"Since launch:   CPU %@ (%@ of %g %%), %.2f idle wakeups a second (%@ of %g)", Pct(cpuAll), Mark(cpuAll, MMSelfBudgetCPU), MMSelfBudgetCPU,
             wakeAll, Mark(wakeAll, MMSelfBudgetWakeups), MMSelfBudgetWakeups];
    [a print:@"Tools it ran:   %@ CPU, %.1f s in all, counted once each has ended", Pct([all[@"childCpuPercent"] doubleValue]), second.childCPU];
    [a print:@"Memory:         %.1f MB now (%@ of %llu MB), %.1f MB at most", second.footprint / 1048576.0,
             second.footprint > MMSelfBudgetMemory ? @"over the budget" : @"within the budget", MMSelfBudgetMemory / 1048576, second.peak / 1048576.0];
    [a print:@"Disk:           %.1f MB written, %.1f MB read since launch", second.written / 1e6, second.read / 1e6];
    return 0;
}
