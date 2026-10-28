// The bench: what MinMacs 2.0 costs at rest, how long its menus take to build, and what the old apps cost
// over the same window. Issues #23 and #51. tools/bench/build.sh builds it from every .m under Sources except
// main.m, with the release flags, so it runs the same Core and experts the app runs.
//
//   bench idle --seconds N [--warmup N]   MMCoreStart with every built-in expert, no status items, every mode Idle.
//                                         Senses samples the real process table. Nothing acts.
//   bench menus [--iterations N]          each expert's menu as the app opens it, and each card as a hover builds it,
//                                         from a fixture snapshot that the graph queue's prepare step ran on first
//   bench hangs [--rounds N]              menu opens and card hovers for every expert under the main-thread watchdog,
//                                         with Core running, issue #55. Lists every pass of main over 50 ms
//   bench startup [--wait N]              the app's launch headless: Core, the items without the status bar, and
//                                         each expert's first summary line, timed from where MMMain starts
//   bench apps                            the old apps that run now, read once with proc_pid_rusage
//
// Each prints one JSON object on stdout. It reads itself with getrusage, task_info and proc_pid_rusage,
// and the old apps with proc_pid_rusage and ps. It never signals a process.
// It refuses to run unless MINMACS_HOME, MINMACS_CLAUDE, MINMACS_CODEX, MINMACS_CMUX and MINMACS_TMUX are set,
// so no real model, cmux or tmux is ever asked and nothing lands in the person's support folder.
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <libproc.h>
#import <pthread/qos.h>
#import <sys/resource.h>
#import <sys/sysctl.h>
#import "Core/MMCore.h"
#import "Shell/MMShell.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"
#import "Shell/MMWatchdog.h"
#import "Experts/LocoHost/MMLHHost.h"
#import "Experts/MinMacs/MMMinMacs.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/Insomnia/MMInsomnia.h"

#pragma mark - Clocks and counters

static double gTicksToNs;   // mach time units to nanoseconds, for proc_pid_rusage times

static uint64_t NowNs(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static uint64_t ThreadCPUNs(void) { return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID); }
static uint64_t ProcessCPUNs(void) { return clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID); }
static double MB(uint64_t bytes) { return bytes / 1048576.0; }
/// A number rounded for JSON. A decimal number prints as written, where a double would print its binary tail.
static NSNumber *R2(double x) { return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.2f", x]]; }
static NSNumber *R3(double x) { return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.3f", x]]; }

/// Median, p95 and max of a list of numbers, rounded to 3 places.
static NSDictionary *Stats(NSArray<NSNumber *> *xs) {
    if (!xs.count) return @{@"n": @0};
    NSArray *s = [xs sortedArrayUsingSelector:@selector(compare:)];
    double (^at)(double) = ^double(double q) {
        NSUInteger i = (NSUInteger)ceil(q * s.count) - 1;
        return [s[MIN(i, s.count - 1)] doubleValue];
    };
    double sum = 0; for (NSNumber *x in s) sum += x.doubleValue;
    return @{@"n": @(s.count), @"median": (R3(at(0.5))), @"p95": (R3(at(0.95))), @"max": (R3([s.lastObject doubleValue])),
             @"mean": (R3(sum / s.count))};
}

/// The bench process itself, from getrusage and task_info.
typedef struct {
    uint64_t wallNs, cpuNs, childCPUNs;
    uint64_t footprint, resident, peakFootprint;
    uint64_t interruptWakeups, idleWakeups;
} MMBenchSelf;

static MMBenchSelf ReadSelf(void) {
    MMBenchSelf s = {0};
    s.wallNs = NowNs();
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    s.cpuNs = ((uint64_t)ru.ru_utime.tv_sec + (uint64_t)ru.ru_stime.tv_sec) * 1000000000ull
            + ((uint64_t)ru.ru_utime.tv_usec + (uint64_t)ru.ru_stime.tv_usec) * 1000ull;
    getrusage(RUSAGE_CHILDREN, &ru);
    s.childCPUNs = ((uint64_t)ru.ru_utime.tv_sec + (uint64_t)ru.ru_stime.tv_sec) * 1000000000ull
                 + ((uint64_t)ru.ru_utime.tv_usec + (uint64_t)ru.ru_stime.tv_usec) * 1000ull;
    task_vm_info_data_t vm; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &n) == KERN_SUCCESS) {
        s.footprint = vm.phys_footprint; s.resident = vm.resident_size;
        s.peakFootprint = vm.ledger_phys_footprint_peak;
    }
    task_power_info_data_t pw; n = TASK_POWER_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_POWER_INFO, (task_info_t)&pw, &n) == KERN_SUCCESS) {
        s.interruptWakeups = pw.task_interrupt_wakeups; s.idleWakeups = pw.task_platform_idle_wakeups;
    }
    return s;
}

#pragma mark - The old apps, read only

/// One process read with proc_pid_rusage. Times are in nanoseconds.
typedef struct {
    BOOL ok;
    uint64_t cpuNs, footprint, resident, peakFootprint, interruptWakeups, idleWakeups;
} MMBenchProc;

static MMBenchProc ReadProc(pid_t pid) {
    MMBenchProc p = {0};
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return p;
    p.ok = YES;
    p.cpuNs = (uint64_t)((ri.ri_user_time + ri.ri_system_time) * gTicksToNs);
    p.footprint = ri.ri_phys_footprint; p.resident = ri.ri_resident_size; p.peakFootprint = ri.ri_lifetime_max_phys_footprint;
    p.interruptWakeups = ri.ri_interrupt_wkups; p.idleWakeups = ri.ri_pkg_idle_wkups;
    return p;
}

/// The old apps that run now: LocoHost, WorkForest, Insomnia, and MinMacs only when its bundle says version 1.
/// Found by the path of the executable inside its bundle, never by a process name.
static NSArray<NSDictionary *> *OldApps(void) {
    NSArray *names = @[@"LocoHost", @"WorkForest", @"Insomnia", @"MinMacs"];
    int cap = proc_listallpids(NULL, 0) + 64;
    pid_t *pids = calloc((size_t)cap, sizeof(pid_t));
    int n = proc_listallpids(pids, cap * (int)sizeof(pid_t));
    NSMutableArray *out = [NSMutableArray new];
    for (int i = 0; i < n; i++) {
        if (pids[i] <= 1 || pids[i] == getpid()) continue;
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof path) <= 0) continue;
        NSString *p = @(path);
        for (NSString *name in names) {
            NSString *tail = [NSString stringWithFormat:@"/%@.app/Contents/MacOS/%@", name, name];
            if (![p hasSuffix:tail]) continue;
            NSString *bundle = [p substringToIndex:p.length - tail.length + name.length + 5];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Contents/Info.plist"]];
            NSString *version = info[@"CFBundleShortVersionString"] ?: @"";
            if ([name isEqualToString:@"MinMacs"] && ![version hasPrefix:@"1."]) continue;   // 2.0 builds are not a baseline
            [out addObject:@{@"app": name, @"pid": @(pids[i]), @"version": version}];
        }
    }
    free(pids);
    return [out sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"app" ascending:YES]]];
}

/// ps for these pids: rss in KB, cumulative CPU time and elapsed time, as ps prints them.
static NSDictionary<NSNumber *, NSDictionary *> *PS(NSArray<NSDictionary *> *apps) {
    if (!apps.count) return @{};
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/ps"];
    t.arguments = @[@"-o", @"pid=,rss=,time=,etime=", @"-p", [[apps valueForKey:@"pid"] componentsJoinedByString:@","]];
    NSPipe *pipe = [NSPipe pipe];
    t.standardOutput = pipe; t.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![t launchAndReturnError:nil]) return @{};
    NSData *d = [pipe.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *line in [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"]) {
        NSArray *w = [[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                      componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        w = [w filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (w.count < 4) continue;
        out[@([w[0] intValue])] = @{@"rssKB": @([w[1] longLongValue]), @"cputime": w[2], @"etime": w[3]};
    }
    return out;
}

/// The old apps over one window: what proc_pid_rusage read at its start and end, and ps at both ends.
static NSArray *OldAppsOver(NSArray<NSDictionary *> *apps, NSDictionary<NSNumber *, NSValue *> *start,
                            NSDictionary *psStart, double windowSec) {
    NSDictionary *psEnd = PS(apps);
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *a in apps) {
        MMBenchProc b = ReadProc([a[@"pid"] intValue]), s;
        NSValue *v = start[a[@"pid"]];
        if (!v || !b.ok) { [out addObject:@{@"app": a[@"app"], @"pid": a[@"pid"], @"error": @"it exited in the window"}]; continue; }
        [v getValue:&s size:sizeof s];
        double cpu = (b.cpuNs - s.cpuNs) / 1e9;
        [out addObject:@{@"app": a[@"app"], @"pid": a[@"pid"], @"version": a[@"version"],
                         @"cpuSeconds": (R3(cpu)), @"cpuPercent": (R3(cpu / windowSec * 100)),
                         @"cpuSecondsPerMinute": (R3(cpu / windowSec * 60)),
                         @"footprintMB": (R2(MB(b.footprint))), @"residentMB": (R2(MB(b.resident))),
                         @"peakFootprintMB": (R2(MB(b.peakFootprint))),
                         @"interruptWakeupsPerSecond": (R3((b.interruptWakeups - s.interruptWakeups) / windowSec)),
                         @"idleWakeupsPerSecond": (R3((b.idleWakeups - s.idleWakeups) / windowSec)),
                         @"psStart": psStart[a[@"pid"]] ?: @{}, @"psEnd": psEnd[a[@"pid"]] ?: @{}}];
    }
    return out;
}

#pragma mark - Arguments and the environment

static NSString *Option(NSArray<NSString *> *args, NSString *flag, NSString *dflt) {
    NSUInteger i = [args indexOfObject:flag];
    return i != NSNotFound && i + 1 < args.count ? args[i + 1] : dflt;
}

static void PrintJSON(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    fwrite(d.bytes, 1, d.length, stdout);
    fputc('\n', stdout);
}

/// YES when path is dir itself or inside it, after both are standardized.
static BOOL Inside(NSString *path, NSString *dir) {
    NSString *p = path.stringByStandardizingPath, *d = dir.stringByStandardizingPath;
    return [p isEqualToString:d] || [p hasPrefix:[d stringByAppendingString:@"/"]];
}

/// The bench never reaches a real model, cmux, tmux or support folder. MINMACS_HOME must be set and not the
/// real support folder. Each CLI must be /usr/bin/false or a fake inside MINMACS_HOME. MINMACS_ROOTS, when set,
/// must lie inside MINMACS_HOME, so the repo index never walks the person's folders.
static BOOL SafeEnvironment(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *home = env[@"MINMACS_HOME"];
    if (!home.length) { fprintf(stderr, "bench: MINMACS_HOME must be set; tools/bench/run.sh sets it\n"); return NO; }
    NSString *real = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"];
    if (Inside(home, real) || Inside(real, home)) { fprintf(stderr, "bench: MINMACS_HOME must not hold the real support folder\n"); return NO; }
    for (NSString *k in @[@"MINMACS_CLAUDE", @"MINMACS_CODEX", @"MINMACS_CMUX", @"MINMACS_TMUX"]) {
        NSString *v = env[k];
        if (!v.length) { fprintf(stderr, "bench: %s must be set; tools/bench/run.sh sets it\n", k.UTF8String); return NO; }
        if (![v isEqualToString:@"/usr/bin/false"] && !Inside(v, home)) {
            fprintf(stderr, "bench: %s must be /usr/bin/false or a fake inside MINMACS_HOME\n", k.UTF8String); return NO;
        }
    }
    for (NSString *r in [env[@"MINMACS_ROOTS"] ?: @"" componentsSeparatedByString:@":"])
        if (r.length && !Inside(r, home)) { fprintf(stderr, "bench: MINMACS_ROOTS must lie inside MINMACS_HOME\n"); return NO; }
    return YES;
}

/// Every registered expert in mode Idle, written to the prefs in MINMACS_HOME. Returns the experts that are not.
static NSArray<NSString *> *AllIdle(void) {
    NSMutableArray *notIdle = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        MMSetMode(e.expertID, MMModeIdle);
        if (MMModeFor(e.expertID) != MMModeIdle) [notIdle addObject:e.expertID];
    }
    return notIdle;
}

static void RunMain(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) @autoreleasepool { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:end]; }
}

#pragma mark - Idle

/// The cost of one tick, measured on one thread after the window, so nothing else runs inside the numbers:
/// a Senses pass, the facts a rebuild gathers, the snapshot the experts build from them, and what each menu reads.
/// A sample reads args and cwd once and keeps them, so each part is also timed alone on a sample of its own:
/// the registry, the session index and each expert's findings. Those runs start with a new pass too.
static NSDictionary *TickCost(int n) {
    NSMutableArray *pass = [NSMutableArray new], *passWall = [NSMutableArray new], *facts = [NSMutableArray new], *snap = [NSMutableArray new];
    NSMutableArray *prep = [NSMutableArray new];
    NSMutableArray *sessions = [NSMutableArray new], *agents = [NSMutableArray new], *agentsWarm = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray *> *experts = [NSMutableDictionary new], *expertsWarm = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) { experts[e.expertID] = [NSMutableArray new]; expertsWarm[e.expertID] = [NSMutableArray new]; }
    dispatch_queue_t graphQ = MMQueue(@"core", @"graph", QOS_CLASS_UTILITY);
    for (int i = 0; i < n; i++) @autoreleasepool {
        uint64_t c = ThreadCPUNs(), w = NowNs();
        [MMSenses.shared sampleNow];   // runs on this thread: dispatch_sync on an idle serial queue
        [pass addObject:@((ThreadCPUNs() - c) / 1e6)];
        [passWall addObject:@((NowNs() - w) / 1e6)];
        dispatch_sync(graphQ, ^{
            uint64_t c0 = ThreadCPUNs();
            MMFacts *f = [MMGraph.shared.source factsFor:1000000 + (uint64_t)i];
            uint64_t c1 = ThreadCPUNs();
            MMSnapshot *built = [MMSnapshot snapshotFrom:f experts:MMExperts() reviews:nil holds:nil];
            uint64_t c2 = ThreadCPUNs();
            [built prepareFor:MMExperts()];   // what each menu reads, made as the graph queue makes it
            [facts addObject:@((c1 - c0) / 1e6)];
            [snap addObject:@((c2 - c1) / 1e6)];
            [prep addObject:@((ThreadCPUNs() - c2) / 1e6)];
        });
        // The parts, each on a new sample, so none reads what another part already read.
        dispatch_sync(graphQ, ^{
            MMSample *s = [MMSenses.shared sampleNow];
            uint64_t c0 = ThreadCPUNs();
            [MMRegistry.shared agentsIn:s power:MMSenses.shared.power];
            [agents addObject:@((ThreadCPUNs() - c0) / 1e6)];
            // Again on the same sample, which now holds the args and cwd the first run read.
            c0 = ThreadCPUNs();
            [MMRegistry.shared agentsIn:s power:MMSenses.shared.power];
            [agentsWarm addObject:@((ThreadCPUNs() - c0) / 1e6)];
            c0 = ThreadCPUNs();
            [MMSessions.shared refresh];
            [sessions addObject:@((ThreadCPUNs() - c0) / 1e6)];
        });
        for (id<MMExpert> e in MMExperts()) dispatch_sync(graphQ, ^{
            [MMSenses.shared sampleNow];
            MMFacts *f = [MMGraph.shared.source factsFor:2000000 + (uint64_t)i];
            uint64_t c0 = ThreadCPUNs();
            [e findingsFrom:f];
            [experts[e.expertID] addObject:@((ThreadCPUNs() - c0) / 1e6)];
            c0 = ThreadCPUNs();
            [e findingsFrom:f];
            [expertsWarm[e.expertID] addObject:@((ThreadCPUNs() - c0) / 1e6)];
        });
    }
    NSMutableDictionary *findings = [NSMutableDictionary new], *findingsWarm = [NSMutableDictionary new];
    for (NSString *k in experts) { findings[k] = Stats(experts[k]); findingsWarm[k] = Stats(expertsWarm[k]); }
    return @{@"passes": @(n), @"passCPUms": Stats(pass), @"passWallms": Stats(passWall),
             @"factsCPUms": Stats(facts), @"snapshotCPUms": Stats(snap), @"prepareCPUms": Stats(prep),
             @"parts": @{@"sessionsRefreshCPUms": Stats(sessions), @"registryAgentsCPUms": Stats(agents), @"findingsCPUms": findings,
                         @"registryAgentsWarmCPUms": Stats(agentsWarm), @"findingsWarmCPUms": findingsWarm}};
}

static int Idle(NSArray<NSString *> *args) {
    double seconds = Option(args, @"--seconds", @"60").doubleValue, warmup = Option(args, @"--warmup", @"10").doubleValue;
    int tickRuns = Option(args, @"--tick-runs", @"20").intValue;
    if (seconds <= 0 || warmup < 0) { fprintf(stderr, "usage: bench idle --seconds N [--warmup N] [--tick-runs N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    // AppKit loaded as in the app, with no status item, window or Dock icon. --no-appkit leaves it out.
    BOOL appkit = ![args containsObject:@"--no-appkit"];
    if (appkit) [NSApplication sharedApplication].activationPolicy = NSApplicationActivationPolicyProhibited;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);   // main runs at the app's QoS
    NSUInteger experts = MMRegisterBuiltInExperts();
    NSArray *notIdle = AllIdle();
    if (notIdle.count) { fprintf(stderr, "bench: these experts are not Idle: %s\n", [notIdle componentsJoinedByString:@" "].UTF8String); return 1; }

    // The tick record. Both observers go in before MMCoreStart, so they run before Core's own on main:
    // the CPU read at a sample signal comes before Core asks for the rebuild.
    __block BOOL inWindow = NO;
    __block uint64_t sampleGen = 0, sampleCPU = 0, sampleAt = 0, lastSnapCPU = 0;
    __block BOOL sampleOpen = NO, haveSnap = NO;
    __block NSUInteger snapshots = 0, samples = 0;
    NSMutableArray *passCPU = [NSMutableArray new], *rebuildCPU = [NSMutableArray new], *rebuildWall = [NSMutableArray new];
    NSMutableArray *tickGaps = [NSMutableArray new], *tickCPU = [NSMutableArray new];
    __block uint64_t prevSampleAt = 0, prevSampleCPU = 0;
    id sensesToken = [MMSenses.shared observe:MMSignalSample block:^(MMSignal changed, id detail) {
        uint64_t cpu = ProcessCPUNs(), now = NowNs();
        if (inWindow) {
            samples++;
            // Everything since the last snapshot reached main: the pass itself, and the quiet time before it.
            if (haveSnap) [passCPU addObject:@((cpu - lastSnapCPU) / 1e6)];
            if (prevSampleAt) [tickGaps addObject:@((now - prevSampleAt) / 1e9)];
            // Issue #52: the whole process's CPU from one sample to the next. A tick whose rebuild found nothing
            // changed has no snapshot, so this is the number that holds every tick.
            if (prevSampleCPU) [tickCPU addObject:@((cpu - prevSampleCPU) / 1e6)];
        }
        prevSampleAt = now; prevSampleCPU = cpu;
        sampleGen = MMSenses.shared.latest.generation; sampleCPU = cpu; sampleAt = now; sampleOpen = YES;
    }];
    // The pushed signals in the window, by kind, so the report can say what woke the graph besides the tick.
    NSCountedSet *signals = [NSCountedSet new];
    id signalToken = [MMSenses.shared observe:MMSignalExit | MMSignalApp | MMSignalPower | MMSignalLid | MMSignalMemory |
                                              MMSignalThermal | MMSignalSleep | MMSignalDisk block:^(MMSignal changed, id detail) {
        if (!inWindow) return;
        NSArray *names = @[@"memory", @"disk", @"thermal", @"power", @"lid", @"exit", @"app", @"sleep"];
        for (NSUInteger i = 0; i < names.count; i++) if (changed & (1u << i)) [signals addObject:names[i]];
        if ((changed & MMSignalExit) && [detail isKindOfClass:NSValue.class]) {
            // Which process ended, by name, from the sample before it ended.
            MMProcKey k; [(NSValue *)detail getValue:&k size:sizeof k];
            NSString *name = [MMSenses.shared.latest proc:k.pid].name ?: @"?";
            [signals addObject:[@"exit:" stringByAppendingString:name]];
        }
    }];
    id graphToken = [MMGraph.shared observe:^(MMSnapshot *s) {
        uint64_t cpu = ProcessCPUNs(), now = NowNs();
        if (inWindow) snapshots++;
        if (inWindow && sampleOpen && s.facts.sample.generation == sampleGen) {
            [rebuildCPU addObject:@((cpu - sampleCPU) / 1e6)];
            [rebuildWall addObject:@((now - sampleAt) / 1e6)];
        }
        if (s.facts.sample.generation == sampleGen) sampleOpen = NO;
        lastSnapCPU = cpu; haveSnap = YES;
    }];

    MMBenchSelf boot = ReadSelf();
    MMCoreStart();
    RunMain(warmup);

    NSArray *apps = OldApps();
    NSMutableDictionary *appStart = [NSMutableDictionary new];
    NSDictionary *psStart = PS(apps);
    for (NSDictionary *a in apps) { MMBenchProc p = ReadProc([a[@"pid"] intValue]); appStart[a[@"pid"]] = [NSValue valueWithBytes:&p objCType:@encode(MMBenchProc)]; }
    MMBenchSelf a = ReadSelf();
    MMBenchProc selfA = ReadProc(getpid());
    NSDictionary *costA = MMGraph.shared.costs;
    MMSensesCounts sensesA = MMSenses.shared.counts;
    NSUInteger readsA = MMSessions.shared.readCount, skipsA = MMSessions.shared.skipCount;
    NSDate *startedAt = NSDate.date;
    inWindow = YES;
    RunMain(seconds);
    inWindow = NO;
    MMBenchSelf b = ReadSelf();
    MMBenchProc selfB = ReadProc(getpid());
    NSDictionary *costB = MMGraph.shared.costs;
    MMSensesCounts sensesB = MMSenses.shared.counts;
    NSUInteger readsB = MMSessions.shared.readCount, skipsB = MMSessions.shared.skipCount;
    NSString *interval = [NSString stringWithFormat:@"%.0f s, %@", MMSenses.shared.interval, MMSenses.shared.intervalReason];
    // Issue #52: what each part of the tick cost in the window, in CPU ms a build, from the graph's own counters,
    // and what the Senses passes read and carried.
    double builds = MAX(1, [costB[@"builds"] doubleValue] - [costA[@"builds"] doubleValue]);
    NSMutableDictionary *perBuild = [NSMutableDictionary new], *reused = [NSMutableDictionary new];
    for (NSString *k in costB) {
        if ([k isEqualToString:@"builds"] || [k isEqualToString:@"skipped"]) continue;
        double d = [costB[k] doubleValue] - [costA[k] doubleValue];
        if ([k hasPrefix:@"reused."]) { reused[[k substringFromIndex:7]] = @((uint64_t)d); continue; }   // a count
        perBuild[k] = R3(d / 1e6 / builds);
    }
    double passes = MAX(1, (double)(sensesB.passes - sensesA.passes));
    NSDictionary *senses = @{@"passes": @(sensesB.passes - sensesA.passes),
                             @"passCPUms": R3((sensesB.cpuNs - sensesA.cpuNs) / 1e6 / passes),
                             @"argsCarriedPerPass": R2((sensesB.argsCarried - sensesA.argsCarried) / passes),
                             @"cwdsCarriedPerPass": R2((sensesB.cwdsCarried - sensesA.cwdsCarried) / passes),
                             @"socketPidsReadPerPass": R2((sensesB.socketPidsScanned - sensesA.socketPidsScanned) / passes),
                             @"socketPidsCarriedPerPass": R2((sensesB.socketPidsCarried - sensesA.socketPidsCarried) / passes),
                             @"interval": interval,
                             @"partsCPUms": @{@"table": R3((sensesB.tableNs - sensesA.tableNs) / 1e6 / passes),
                                              @"procs": R3((sensesB.procsNs - sensesA.procsNs) / 1e6 / passes),
                                              @"sockets": R3((sensesB.socketsNs - sensesA.socketsNs) / 1e6 / passes),
                                              @"carry": R3((sensesB.carryNs - sensesA.carryNs) / 1e6 / passes),
                                              @"power": R3((sensesB.powerNs - sensesA.powerNs) / 1e6 / passes)}};
    NSDictionary *graph = @{@"builds": @((NSUInteger)builds),
                            @"skipped": @([costB[@"skipped"] unsignedLongLongValue] - [costA[@"skipped"] unsignedLongLongValue]),
                            @"perBuildCPUms": perBuild, @"reusedFindings": reused,
                            @"sessionReads": @(readsB - readsA), @"sessionSkips": @(skipsB - skipsA)};
    double window = (b.wallNs - a.wallNs) / 1e9;
    NSArray *old = OldAppsOver(apps, appStart, psStart, window);

    MMSnapshot *snap = MMGraph.shared.current;
    NSMutableDictionary *findings = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) findings[e.expertID] = @([snap findingsFor:e.expertID].count);
    [MMSenses.shared stopObserving:sensesToken];
    [MMSenses.shared stopObserving:signalToken];
    NSMutableDictionary *signalCounts = [NSMutableDictionary new];
    for (NSString *k in signals) signalCounts[k] = @([signals countForObject:k]);
    [MMGraph.shared stopObserving:graphToken];
    MMCoreStop();
    NSUInteger records = [MMUndo.shared recent:nil limit:1000].count;
    NSDictionary *ticks = tickRuns > 0 ? TickCost(tickRuns) : @{};

    double cpu = (b.cpuNs - a.cpuNs) / 1e9;
    PrintJSON(@{
        @"kind": @"idle",
        @"startedAt": @(round(startedAt.timeIntervalSince1970)),
        @"windowSeconds": (R2(window)), @"warmupSeconds": @(warmup),
        @"experts": @(experts), @"expertIDs": [MMExperts() valueForKey:@"expertID"], @"findings": findings,
        @"modes": @"idle", @"undoRecords": @(records), @"appkit": @(appkit),
        @"cpuSeconds": (R3(cpu)), @"cpuPercent": (R3(cpu / window * 100)), @"cpuSecondsPerMinute": (R3(cpu / window * 60)),
        @"cpuPercentFromRusageInfo": (R3((selfB.cpuNs - selfA.cpuNs) / 1e9 / window * 100)),
        @"childCPUSeconds": (R3((b.childCPUNs - a.childCPUNs) / 1e9)),
        @"startupCPUSeconds": (R3((a.cpuNs - boot.cpuNs) / 1e9)),
        @"interruptWakeupsPerSecond": (R3((b.interruptWakeups - a.interruptWakeups) / window)),
        @"idleWakeupsPerSecond": (R3((b.idleWakeups - a.idleWakeups) / window)),
        @"footprintMB": (R2(MB(b.footprint))), @"residentMB": (R2(MB(b.resident))),
        @"peakFootprintMB": (R2(MB(b.peakFootprint))), @"footprintAtWindowStartMB": (R2(MB(a.footprint))),
        @"samples": @(samples), @"snapshots": @(snapshots), @"pids": @(snap.facts.sample.procs.count),
        @"tickSeconds": Stats(tickGaps),
        @"inWindow": @{@"passCPUms": Stats(passCPU), @"rebuildCPUms": Stats(rebuildCPU), @"rebuildWallms": Stats(rebuildWall),
                       @"tickCPUms": Stats(tickCPU)},
        @"tickCost": ticks,
        @"senses": senses, @"graph": graph, @"signals": signalCounts,
        @"backoff": NSProcessInfo.processInfo.environment[@"MINMACS_NO_BACKOFF"].length ? @"off" : @"on",
        @"oldApps": old,
    });
    return 0;
}

#pragma mark - Menu fixtures

/// An expert that hands over findings made in advance, so a snapshot can hold fixture findings of a real expert.
@interface MMBenchReplay : NSObject <MMExpert>
@property (copy) NSString *expertID;
@property (copy) NSArray<MMFinding *> *findings;
@end
@implementation MMBenchReplay
- (NSString *)name { return self.expertID; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts { return self.findings; }
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return nil; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return nil; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return self.findings.count == 0; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
@end

/// A fixture process and sample, with every message MMSample answers, for experts with no fixture of their own.
@interface MMBenchProcFix : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property uint64_t startSec;
@property (copy) NSString *name, *cwd;
@property double cpuPercent, energyRank; @property uint64_t footprint;
@end
@implementation MMBenchProcFix
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface MMBenchSample : NSObject
@property NSDate *at; @property uint64_t generation;
@property NSDictionary<NSNumber *, MMBenchProcFix *> *procs;
@end
@implementation MMBenchSample
- (MMBenchProcFix *)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return self.procs[@(pid)].cwd; }
- (NSArray *)childrenOf:(pid_t)pid {
    NSMutableArray *k = [NSMutableArray new];
    for (MMBenchProcFix *p in self.procs.allValues) if (p.ppid == pid) [k addObject:@(p.pid)];
    return k;
}
- (NSArray *)treeOf:(pid_t)pid limit:(NSUInteger)max {
    NSMutableArray *t = [NSMutableArray arrayWithObject:@(pid)];
    for (NSUInteger i = 0; i < t.count && t.count < max; i++) [t addObjectsFromArray:[self childrenOf:[t[i] intValue]]];
    return t;
}
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *a = [NSMutableArray new];
    for (MMBenchProcFix *p = self.procs[@(self.procs[@(pid)].ppid)]; p && a.count < hops; p = p.pid == 1 ? nil : self.procs[@(p.ppid)]) [a addObject:@(p.pid)];
    return a;
}
- (double)treeCPU:(pid_t)pid { double c = 0; for (NSNumber *x in [self treeOf:pid limit:500]) c += self.procs[x].cpuPercent; return c; }
- (uint64_t)treeFootprint:(pid_t)pid { uint64_t f = 0; for (NSNumber *x in [self treeOf:pid limit:500]) f += self.procs[x].footprint; return f; }
- (const MMSocket *)sockets:(NSUInteger *)count { if (count) *count = 0; return NULL; }
- (NSArray *)socketsOf:(pid_t)pid { return @[]; }
@end

/// The fixture facts every expert reads: a launchd, a terminal with a shell, two node servers and an app.
/// Fixture pids sit above any real pid macOS hands out, so no lookup by pid can reach a real process.
static MMFacts *FixtureFacts(uint64_t generation) {
    NSString *home = [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"bench-fixture"];
    NSArray *rows = @[@[@1, @0, @"launchd", @"/"], @[@100050, @1, @"Terminal", @"/"], @[@100060, @100050, @"zsh", home],
                      @[@100110, @100060, @"node", [home stringByAppendingPathComponent:@"web"]],
                      @[@100130, @100060, @"node", [home stringByAppendingPathComponent:@"docs"]], @[@100500, @1, @"Notes", @"/"],
                      @[@100700, @100060, @"claude", [home stringByAppendingPathComponent:@"web"]],
                      @[@100701, @100060, @"codex", [home stringByAppendingPathComponent:@"docs"]]];
    NSMutableDictionary *procs = [NSMutableDictionary new];
    for (NSArray *r in rows) {
        MMBenchProcFix *p = [MMBenchProcFix new];
        p.pid = [r[0] intValue]; p.ppid = [r[1] intValue]; p.uid = getuid(); p.startSec = 1761000000 + (uint64_t)p.pid;
        p.name = r[2]; p.cwd = r[3]; p.cpuPercent = 0.5; p.footprint = 64ull << 20;
        if (p.pid >= 100700) p.startSec = 1761000100 + (uint64_t)(p.pid - 100700) * 100;   // the agents' keys in InsomniaFixture
        procs[@(p.pid)] = p;
    }
    MMBenchSample *s = [MMBenchSample new];
    s.at = NSDate.date; s.generation = generation; s.procs = procs;
    return [MMFacts generation:generation sample:(MMSample *)s power:nil agents:@[] sessions:@[] worktrees:@[] clutter:@[] git:@{}];
}

/// Twelve servers, more than a section shows, so the menu has a More item and every state appears.
static NSArray<MMFinding *> *LocoHostFixture(void) {
    NSArray *rows = @[
        @[@"acme-web.worktrees/checkout-flow", @3000, @"Vite", @905, @(MMLHActive), @"feat/checkout-flow"],
        @[@"orbit-api", @4000, @"Next.js", @640, @(MMLHRecent), @"main"],
        @[@"acme-web", @6006, @"Storybook", @310, @(MMLHActive), @"main"],
        @[@"acme-web.worktrees/search", @5173, @"Vite", @410, @(MMLHActive), @"feat/search"],
        @[@"acme-web/docs", @3001, @"Vite", @512, @(MMLHIdle), @"main"],
        @[@"acme-admin", @3002, @"Vite", @700, @(MMLHIdle), @"main"],
        @[@"billing", @3003, @"Remix", @450, @(MMLHIdle), @"fix/invoices"],
        @[@"marketing-site", @4321, @"Astro", @280, @(MMLHRecent), @"main"],
        @[@"mobile-api", @8080, @"Express", @190, @(MMLHIdle), @"main"],
        @[@"design-tokens", @6007, @"Storybook", @350, @(MMLHIdle), @"main"],
        @[@"orbit-api.worktrees/webhooks", @4001, @"Next.js", @600, @(MMLHActive), @"feat/webhooks"],
        @[@"analytics", @5000, @"Flask", @120, @(MMLHRecent), @"main"]];
    NSMutableArray *out = [NSMutableArray new];
    NSInteger i = 0;
    for (NSArray *r in rows) {
        MMLHHost *h = [MMLHHost new];
        NSInteger port = [r[1] integerValue];
        NSString *key = [NSString stringWithFormat:@"~/code/%@#dev", r[0]];
        h.findingID = [@"locohost:server:" stringByAppendingString:key]; h.stableKey = key;
        h.pid = (pid_t)(100200 + i); h.startSec = 1761000000 + (uint64_t)i; h.key = [NSString stringWithFormat:@"%d:%llu", h.pid, h.startSec];
        h.name = @"node"; h.kind = @"dev"; h.framework = r[2]; h.cwd = [@"/Users/dev/code" stringByAppendingPathComponent:r[0]];
        h.ports = @[@(port)]; h.bind = @"127.0.0.1"; h.memory = [r[3] unsignedLongLongValue] << 20; h.state = (MMLHState)[r[4] integerValue];
        h.started = [NSDate dateWithTimeIntervalSinceNow:-(3600.0 * (i + 1))]; h.firstSeen = h.started;
        h.lastActive = [NSDate dateWithTimeIntervalSinceNow:-(h.state == MMLHIdle ? 3 * 3600.0 : 120.0)];
        h.args = @[@"node", @"dev"]; h.launcher = @"pnpm dev · cmux"; h.branch = r[5];
        h.repo = [[r[0] componentsSeparatedByString:@"/"].firstObject stringByReplacingOccurrencesOfString:@".worktrees" withString:@""];
        h.placeLabel = @"cmux, fixture"; h.placeApp = @"cmux"; h.cpuPercent = h.state == MMLHActive ? 3 : 0;
        h.clients = h.state == MMLHActive ? @[@"Safari"] : @[]; h.connections = h.state == MMLHActive ? 2 : 0;
        [out addObject:[MMFinding expert:@"locohost" kind:@"server" stableKey:key build:^(MMFindingBuilder *b) {
            b.instanceKey = h.key;
            b.title = [NSString stringWithFormat:@":%ld %@ %@", (long)h.port, h.framework, h.project];
            b.path = h.cwd;
            b.cost = (MMCost){ .ramBytes = h.memory, .cpuPercent = h.cpuPercent };
            b.proposal = [MMProposal verb:@"stop" title:@"Stop Server" reversibility:MMReversibleRestart];
            b.facts = h.json;
            b.fingerprint = h.findingID;
        }]];
        i++;
    }
    return out;
}

static MMMinMacsApp *FixtureApp(NSInteger i, NSString *name, NSString *bid, uint64_t mb, double cpu, NSInteger procs) {
    MMMinMacsApp *a = [MMMinMacsApp new];
    a.name = name; a.bundleID = bid; a.memory = mb << 20; a.cpuPercent = cpu; a.energyRank = cpu / 20; a.processCount = procs;
    a.pid = (pid_t)(100600 + i); a.startSec = 1761000000; a.pids = @[@(a.pid)];
    return a;
}

/// Twenty apps and two agents, the size of a busy working day.
static MMMinMacsInput *MinMacsFixture(MMFacts *facts) {
    NSArray *rows = @[@[@"Spotify", @"com.spotify.client", @1310, @6], @[@"Slack", @"com.tinyspeck.slackmacgap", @820, @2],
                      @[@"Photos", @"com.apple.Photos", @410, @0], @[@"Google Chrome", @"com.google.Chrome", @2450, @18],
                      @[@"Figma", @"com.figma.Desktop", @1130, @9], @[@"Notion", @"notion.id", @640, @1],
                      @[@"Terminal", @"com.apple.Terminal", @210, @1], @[@"Xcode", @"com.apple.dt.Xcode", @1900, @3],
                      @[@"Linear", @"com.linear", @300, @0], @[@"Safari", @"com.apple.Safari", @900, @2],
                      @[@"Mail", @"com.apple.mail", @350, @0], @[@"Calendar", @"com.apple.iCal", @120, @0],
                      @[@"Music", @"com.apple.Music", @260, @1], @[@"Preview", @"com.apple.Preview", @180, @0],
                      @[@"Zoom", @"us.zoom.xos", @520, @4], @[@"Discord", @"com.hnc.Discord", @610, @1],
                      @[@"Docker Desktop", @"com.docker.docker", @1500, @5], @[@"Cursor", @"com.todesktop.230313mzl4w4u92", @1700, @7],
                      @[@"Finder", @"com.apple.finder", @150, @0], @[@"Notes", @"com.apple.Notes", @140, @0]];
    NSMutableArray *apps = [NSMutableArray new];
    NSInteger i = 0;
    for (NSArray *r in rows) { [apps addObject:FixtureApp(i, r[0], r[1], [r[2] unsignedLongLongValue], [r[3] doubleValue], 1 + i % 7)]; i++; }
    ((MMMinMacsApp *)apps[4]).agentName = @"Claude Code";
    ((MMMinMacsApp *)apps[5]).loopbackPorts = @[@51789];
    MMMinMacsInput *in = [MMMinMacsInput new];
    in.apps = apps;
    MMMinMacsAgent *claude = [MMMinMacsAgent new];
    claude.name = @"Claude Code"; claude.harnessID = @"claude-code"; claude.sessionID = @"bench-1"; claude.project = @"/Users/dev/code/acme-web";
    claude.why = @"status file busy"; claude.state = MMAgentWorking; claude.key = (MMProcKey){ 100700, 1761000100 }; claude.memory = 720ull << 20; claude.cpuPercent = 14;
    MMMinMacsAgent *codex = [MMMinMacsAgent new];
    codex.name = @"Codex"; codex.harnessID = @"codex"; codex.sessionID = @"bench-2"; codex.project = @"/Users/dev/code/orbit-api";
    codex.why = @"newest turn completed"; codex.state = MMAgentIdle; codex.key = (MMProcKey){ 100701, 1761000200 }; codex.memory = 180ull << 20;
    in.agents = @[claude, codex];
    in.memoryPressure = 1; in.thermal = NSProcessInfoThermalStateNominal;
    return in;
}

/// One worktree, as WorkForest's own finding would hold it.
static MMWFTree *FixtureTree(NSString *repo, NSString *folder, NSString *branch, uint64_t mb, NSTimeInterval quiet) {
    MMWFTree *t = [MMWFTree new];
    t.repo = [@"/Users/dev/code" stringByAppendingPathComponent:repo];
    t.path = [[t.repo stringByAppendingString:@".worktrees"] stringByAppendingPathComponent:folder];
    t.findingID = [@"workforest:worktree:" stringByAppendingString:t.path];
    t.branch = branch; t.maker = @"person"; t.gitKnown = YES; t.head = @"4f1c2d9e8a7b";
    t.defaultBranch = @"origin/main"; t.upstream = [@"origin/" stringByAppendingString:branch ?: @""]; t.onRemote = YES;
    t.sized = YES; t.diskBytes = mb << 20; t.freedBytes = mb << 20; t.cacheBytes = (mb / 2) << 20; t.files = 1200;
    t.lastCommit = [NSDate dateWithTimeIntervalSinceNow:-quiet]; t.touched = t.lastCommit; t.created = [NSDate dateWithTimeIntervalSinceNow:-quiet - 86400];
    return t;
}

/// Sixteen worktrees in two repos, the size of the render tool's WorkForest subject: merged, squash-merged, busy,
/// dirty and quiet ones, and both main checkouts. Built as WorkForest's FindingFor builds them, from each tree's JSON.
static NSArray<MMFinding *> *WorkForestFixture(void) {
    NSMutableArray<MMWFTree *> *trees = [NSMutableArray new];
    MMWFTree *promo = FixtureTree(@"acme-web", @"acme-web-promo-banner", @"feat/promo-banner", 4900, 6 * 86400);
    promo.merged = @"squash"; promo.upstream = @"gone"; promo.notInDefault = 2; [trees addObject:promo];
    MMWFTree *docs = FixtureTree(@"acme-web", @"acme-web-docs-refresh", @"docs/refresh", 540, 13 * 86400);
    docs.merged = @"ancestor"; [trees addObject:docs];
    MMWFTree *checkout = FixtureTree(@"acme-web", @"acme-web-checkout-flow", @"feat/checkout-flow", 905, 3 * 3600);
    checkout.processes = @[@"node", @"zsh"]; checkout.notInDefault = 4;
    checkout.session = @{@"agent": @"Claude Code", @"title": @"Checkout flow", @"lastActiveAt": @(NSDate.date.timeIntervalSince1970 - 1200), @"live": @YES};
    [trees addObject:checkout];
    MMWFTree *search = FixtureTree(@"acme-web", @"acme-web-search-facets", @"feat/search-facets", 820, 2 * 3600);
    search.dirty = 3; search.notInDefault = 2; [trees addObject:search];
    MMWFTree *hooks = FixtureTree(@"orbit-api", @"billing-webhooks", @"fix/billing-webhooks", 1300, 36 * 3600);
    hooks.processes = @[@"node"]; hooks.notInDefault = 1; [trees addObject:hooks];
    MMWFTree *limits = FixtureTree(@"orbit-api", @"rate-limits", @"wip/rate-limits", 310, 9 * 86400);
    limits.notInDefault = 5; [trees addObject:limits];
    NSArray *names = @[@"onboarding-copy", @"pricing-table", @"sso-okta", @"dark-mode", @"image-cdn", @"cart-refactor", @"i18n-nb", @"search-v2"];
    for (NSUInteger k = 0; k < names.count; k++) {
        MMWFTree *q = FixtureTree(k % 2 ? @"orbit-api" : @"acme-web", names[k], [@"feat/" stringByAppendingString:names[k]], 120 + 40 * k, (4 + 3 * k) * 86400);
        q.notInDefault = 1 + k % 3;
        [trees addObject:q];
    }
    for (NSString *repo in @[@"acme-web", @"orbit-api"]) {
        MMWFTree *m = FixtureTree(repo, repo, @"main", 2400, 3600);
        m.path = m.repo; m.isMain = YES; m.isProtected = YES; m.findingID = [@"workforest:worktree:" stringByAppendingString:m.path];
        [trees addObject:m];
    }
    NSMutableArray *out = [NSMutableArray new];
    for (MMWFTree *t in trees) {
        [out addObject:[MMFinding expert:@"workforest" kind:@"worktree" stableKey:t.path build:^(MMFindingBuilder *b) {
            b.instanceKey = t.head; b.path = t.path;
            b.title = t.isMain ? t.repoName : [NSString stringWithFormat:@"%@/%@", t.repoName, t.name];
            b.cost = (MMCost){ .cpuPercent = -1, .diskFreed = t.freedBytes, .diskAllocated = t.diskBytes };
            if (!t.isMain) b.proposal = [MMProposal verb:@"remove" title:@"Remove Worktree" reversibility:MMReversibleRestart];
            NSString *keep = t.isMain ? nil : MMWFWorkKeeps(t);
            if (keep) b.keepReasons = @[keep];
            b.facts = t.json;
            b.fingerprint = t.path;
        }]];
    }
    return out;
}

/// Twelve clutter items in Noo-Noo's four sections, with the facts its findings carry.
static NSArray<MMFinding *> *NooNooFixture(void) {
    NSArray *rows = @[
        @[@"next-build", @".next", @"Next.js build output", @"finished", @3170, @"search", @"squash-merged", @YES],
        @[@"node-modules", @"node_modules", @"node_modules", @"finished", @1536, @"search", @"squash-merged", @YES],
        @[@"node-modules", @"node_modules", @"node_modules", @"finished", @900, @"old-onboarding", @"remote branch deleted", @YES],
        @[@"claude-scratch", @"Claude Code scratch", @"Claude Code scratch", @"leftovers", @3410, @"", @"", @NO],
        @[@"tmp-family", @"server-budget-* folders", @"temp folders", @"leftovers", @12, @"", @"", @NO],
        @[@"go-build", @"Go build cache", @"Go build cache", @"caches", @2980, @"", @"", @NO],
        @[@"pnpm-store", @"pnpm store", @"pnpm store", @"caches", @5610, @"", @"", @NO],
        @[@"playwright", @"Playwright browsers", @"Playwright browsers", @"caches", @2540, @"chromium-1187", @"", @NO],
        @[@"xcode-derived", @"DerivedData", @"Xcode DerivedData", @"caches", @7400, @"", @"", @NO],
        @[@"node-modules", @"node_modules", @"node_modules", @"kept", @1610, @"checkout-flow", @"", @YES],
        @[@"claude-transcripts", @"Claude Code transcripts", @"Claude Code transcripts", @"kept", @2040, @"acme-web", @"", @NO],
        @[@"trash", @"Trash", @"Trash", @"caches", @2150, @"", @"", @NO]];
    NSMutableArray *out = [NSMutableArray new];
    NSInteger i = 0;
    for (NSArray *r in rows) {
        NSString *path = [NSString stringWithFormat:@"/Users/dev/code/fixture-%ld/%@", (long)i, r[1]];
        uint64_t bytes = [r[4] unsignedLongLongValue] << 20;
        NSMutableDictionary *fx = [@{@"kindID": r[0], @"kindTitle": r[2], @"class": @"build", @"path": path, @"members": @1,
                                     @"state": [r[3] isEqual:@"kept"] ? @"live" : @"free", @"section": r[3], @"allocated": @(bytes), @"freed": @(bytes),
                                     @"name": r[1], @"goes": @([r[3] isEqual:@"finished"]), @"reportOnly": @NO, @"folder": r[7],
                                     @"lastUsed": @(NSDate.date.timeIntervalSince1970 - 86400.0 * (i + 1)),
                                     @"trend": @{@"ok": @YES, @"bytesPerDay": @(bytes / 14.0), @"windowDays": @14, @"firstBytes": @(bytes / 3.0),
                                                 @"lastBytes": @(bytes), @"weekRatio": @1.4}} mutableCopy];
        if ([r[5] length]) fx[@"owner"] = r[5];
        if ([r[6] length]) { fx[@"ownerState"] = r[6]; fx[@"worktree"] = [@"/Users/dev/code/acme-web.worktrees" stringByAppendingPathComponent:r[5]]; }
        if ([r[3] isEqual:@"kept"]) fx[@"why"] = @"an agent works in checkout-flow";
        BOOL kept = [r[3] isEqual:@"kept"];
        NSString *key = [NSString stringWithFormat:@"%@:%@", r[0], path];
        [out addObject:[MMFinding expert:@"noonoo" kind:@"clutter" stableKey:key build:^(MMFindingBuilder *b) {
            b.instanceKey = key; b.title = r[1]; b.path = path;
            b.cost = (MMCost){ .cpuPercent = -1, .diskFreed = bytes, .diskAllocated = bytes };
            b.proposal = [MMProposal verb:@"remove" title:@"Move to Trash" reversibility:MMReversibleTrash];
            if (kept) b.keepReasons = @[@"an agent works in checkout-flow"];
            b.facts = fx;
            b.fingerprint = key;
        }]];
        i++;
    }
    return out;
}

/// Two agents, one working and one quiet, in the fixture facts' folders. Insomnia makes its own findings from them.
static MMINInput *InsomniaFixture(MMFacts *facts) {
    NSString *home = [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"bench-fixture"];
    MMINWorker *claude = [MMINWorker new];
    claude.kind = @"agent"; claude.key = (MMProcKey){ 100700, 1761000100 }; claude.name = @"Claude Code"; claude.harness = @"claude-code";
    claude.sessionID = @"bench-1"; claude.cwd = [home stringByAppendingPathComponent:@"web"]; claude.why = @"status file busy"; claude.working = YES;
    claude.stableKey = @"claude-code:bench-1";
    MMINWorker *codex = [MMINWorker new];
    codex.kind = @"agent"; codex.key = (MMProcKey){ 100701, 1761000200 }; codex.name = @"Codex"; codex.harness = @"codex";
    codex.sessionID = @"bench-2"; codex.cwd = [home stringByAppendingPathComponent:@"docs"]; codex.why = @"newest turn completed"; codex.working = NO;
    codex.stableKey = @"codex:bench-2";
    MMINInput *in = [MMINInput new];
    in.workers = @[claude, codex];
    return in;
}

static MMBenchReplay *Replay(NSString *expertID, NSArray<MMFinding *> *findings) {
    MMBenchReplay *r = [MMBenchReplay new];
    r.expertID = expertID; r.findings = findings;
    return r;
}

/// The expert that makes each registered expert's findings for the fixture snapshot, and what it is called.
static id<MMExpert> FixtureSource(id<MMExpert> e, NSString **kind) {
    if ([e.expertID isEqualToString:@"locohost"]) { *kind = @"12 fixture servers"; return Replay(e.expertID, LocoHostFixture()); }
    if ([e.expertID isEqualToString:@"workforest"]) { *kind = @"16 fixture worktrees in 2 repos"; return Replay(e.expertID, WorkForestFixture()); }
    if ([e.expertID isEqualToString:@"noonoo"]) { *kind = @"12 fixture clutter items"; return Replay(e.expertID, NooNooFixture()); }
    if ([(NSObject *)e isKindOfClass:MMInsomniaExpert.class]) {
        ((MMInsomniaExpert *)e).inputFrom = ^MMINInput *(MMFacts *f) { return InsomniaFixture(f); };
        *kind = @"2 fixture agents";
        return e;
    }
    if ([(NSObject *)e isKindOfClass:MMMinMacsExpert.class]) {
        ((MMMinMacsExpert *)e).inputFrom = ^MMMinMacsInput *(MMFacts *f) { return MinMacsFixture(f); };
        *kind = @"20 fixture apps and 2 agents";
        return e;
    }
    *kind = @"the shared fixture facts";
    return e;
}

#pragma mark - Menus

@interface MMBenchFooter : NSObject
- (void)hideIcon:(id)sender;
- (void)showSettings:(id)sender;
@end
@implementation MMBenchFooter
- (void)hideIcon:(id)sender {}
- (void)showSettings:(id)sender {}
@end

/// Lays out and draws a view into a bitmap, as the menu does when it shows it.
static void Draw(NSView *v) {
    if (!v) return;
    [v layoutSubtreeIfNeeded];
    NSRect r = v.bounds;
    if (NSIsEmptyRect(r)) r = NSMakeRect(0, 0, v.fittingSize.width ?: MMMenuWidth, v.fittingSize.height ?: 20);
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:r];
    if (rep) [v cacheDisplayInRect:r toBitmapImageRep:rep];
}

/// The fixture experts and their snapshots: each registered expert, the source of its fixture findings, and a block
/// that makes a new snapshot of a new generation, so no expert answers from a cache it keeps per snapshot.
@interface MMBenchFixture : NSObject
@property (copy) NSArray<id<MMExpert>> *experts, *sources;
@property (copy) NSDictionary<NSString *, NSString *> *kinds;
@property uint64_t gen;
@end
@implementation MMBenchFixture
/// A snapshot from the fixture facts, with what the graph queue prepares for each menu. Any queue.
- (MMSnapshot *)fresh {
    uint64_t g;
    @synchronized (self) { g = ++_gen; }
    MMSnapshot *s = [MMSnapshot snapshotFrom:FixtureFacts(g) experts:self.sources reviews:nil holds:nil];
    [s prepareFor:self.experts];
    return s;
}
@end

static MMBenchFixture *Fixture(void) {
    MMRegisterBuiltInExperts();
    AllIdle();
    MMBenchFixture *fx = [MMBenchFixture new];
    fx.experts = MMExperts();
    NSMutableArray *sources = [NSMutableArray new];
    NSMutableDictionary *kinds = [NSMutableDictionary new];
    for (id<MMExpert> e in fx.experts) { NSString *k = nil; [sources addObject:FixtureSource(e, &k)]; kinds[e.expertID] = k; }
    fx.sources = sources; fx.kinds = kinds;
    return fx;
}

/// Runs block on q and waits. dispatch_sync from main would run it on main, so it goes through dispatch_async.
static void OffMain(dispatch_queue_t q, dispatch_block_t block) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(q, ^{ block(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

/// Each row's card that waits for a hover, in menu order, with the More items' rows too.
static NSArray<NSMenu *> *WaitingCards(NSMenu *m) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSMenuItem *i in m.itemArray) {
        if (!i.submenu) continue;
        if (MMCardWaits(i.submenu)) [out addObject:i.submenu];
        else [out addObjectsFromArray:WaitingCards(i.submenu)];
    }
    return out;
}

/// A hover: the card's spec, its kit card and its items, as the submenu's delegate builds them, then the layout and
/// drawing as the submenu shows. Returns the time of the build alone in *build.
static double Hover(NSMenu *card, double *build) {
    uint64_t c0 = NowNs();
    [card.delegate menuNeedsUpdate:card];
    uint64_t c1 = NowNs();
    Draw([card itemAtIndex:0].view);
    uint64_t c2 = NowNs();
    if (build) *build = (c1 - c0) / 1e6;
    return (c2 - c0) / 1e6;
}

/// A menu's items as text, submenus included: each title, a view's size, and the alternates, for comparing two menus.
static NSString *Shape(NSMenu *m) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSMenuItem *i in m.itemArray) {
        NSString *t = i.isSeparatorItem ? @"-" : i.view ? [NSString stringWithFormat:@"view %.0fx%.0f", i.view.frame.size.width, i.view.frame.size.height]
                                        : [NSString stringWithFormat:@"%@%@%@", i.attributedTitle.string ?: i.title, i.isAlternate ? @" alt" : @"", i.enabled ? @"" : @" off"];
        if (i.submenu) t = [NSString stringWithFormat:@"%@ [%@]", t, Shape(i.submenu)];
        [out addObject:t];
    }
    return [out componentsJoinedByString:@"; "];
}

static int Menus(NSArray<NSString *> *args) {
    int n = Option(args, @"--iterations", @"200").intValue;
    if (n <= 0) { fprintf(stderr, "usage: bench menus [--iterations N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    [NSApplication sharedApplication];
    // The menu builds where the app builds it: on main at user-interactive QoS.
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    MMBenchFixture *fx = Fixture();
    MMBenchFooter *footer = [MMBenchFooter new];
    // The graph queue's prepare step runs where the graph runs it, on a queue of its own, outside the menu's time.
    dispatch_queue_t graphQ = dispatch_queue_create("no.guerrilla.minmacs.bench.graph", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));

    NSMutableDictionary *out = [NSMutableDictionary new];
    NSUInteger before = MMCardsBuiltOnHover();
    BOOL noneAtOpen = YES;
    for (id<MMExpert> e in fx.experts) {
        NSMutableArray *spec = [NSMutableArray new], *open = [NSMutableArray new], *cardBuild = [NSMutableArray new], *hover = [NSMutableArray new];
        NSMutableArray *prepare = [NSMutableArray new];
        __block NSUInteger rows = 0, cards = 0, items = 0;
        uint64_t began = NowNs();
        for (int i = -3; i < n; i++) @autoreleasepool {   // three turns of warm-up
            __block MMSnapshot *s = nil;
            __block double prep = 0;
            OffMain(graphQ, ^{
                s = [MMSnapshot snapshotFrom:FixtureFacts(++fx.gen) experts:fx.sources reviews:nil holds:nil];
                // This expert's part of the graph queue's prepare step, timed. Its menu reads only its own.
                uint64_t p0 = NowNs();
                [s prepareFor:@[e]];
                prep = (NowNs() - p0) / 1e6;
            });
            uint64_t t0 = NowNs();
            MMMenuSpec *m = [e menuFor:s];
            uint64_t t1 = NowNs();
            // What MMExpertItem's menuNeedsUpdate: does on main: MMShellMenu, the spec and the NSMenu, no card.
            NSUInteger built = MMCardsBuiltOnHover();
            uint64_t t2 = NowNs();
            NSMenu *menu = MMShellMenu(e, s, nil, footer);
            uint64_t t3 = NowNs();
            if (MMCardsBuiltOnHover() != built) noneAtOpen = NO;
            if (i < 0) continue;
            [prepare addObject:@(prep)];
            [spec addObject:@((t1 - t0) / 1e6)];
            [open addObject:@((t3 - t2) / 1e6)];
            items = menu.numberOfItems;
            rows = 0; for (MMSectionSpec *sec in m.sections) rows += sec.rows.count;
            cards = 0;
            for (NSMenu *card in WaitingCards(menu)) {
                double b = 0, h = Hover(card, &b);
                [cardBuild addObject:@(b)];
                [hover addObject:@(h)];
                cards++;
            }
        }
        out[e.expertID] = @{@"fixture": fx.kinds[e.expertID], @"rows": @(rows), @"cards": @(cards), @"items": @(items),
                            @"prepareMs": Stats(prepare), @"runSeconds": R2((NowNs() - began) / 1e9), @"specMs": Stats(spec), @"menuOpenMs": Stats(open),
                            @"cardBuildMs": Stats(cardBuild), @"cardHoverMs": Stats(hover)};
    }
    // The menu the app opens, with each card built on hover, holds what the menu with every card built up front holds.
    NSMutableArray *same = [NSMutableArray new], *differ = [NSMutableArray new];
    {
        __block MMSnapshot *s = nil;
        OffMain(graphQ, ^{ s = [fx fresh]; });
        for (id<MMExpert> e in fx.experts) {
            NSMenu *eager = MMMenuFromSpec([e menuFor:s], ^MMCardSpec *(NSString *fid) {
                MMFinding *f = [s finding:fid];
                return f ? [e cardFor:f snapshot:s] : nil;
            }, nil, footer);
            NSMenu *lazy = MMShellMenu(e, s, nil, footer);
            MMLoadCards(lazy);
            [([Shape(eager) isEqualToString:Shape(lazy)] ? same : differ) addObject:e.expertID];
        }
    }
    // One Icon: one menu with a section per expert, built the way the shell builds it.
    NSMutableArray *one = [NSMutableArray new];
    for (int i = -3; i < n; i++) @autoreleasepool {
        __block MMSnapshot *s = nil;
        OffMain(graphQ, ^{ s = [fx fresh]; });
        uint64_t t0 = NowNs();
        MMShellOneIconMenu(s, nil, footer);
        if (i >= 0) [one addObject:@((NowNs() - t0) / 1e6)];
    }
    PrintJSON(@{@"kind": @"menus", @"iterations": @(n), @"experts": out, @"oneIconMs": Stats(one),
                @"cardsBuiltAtOpen": @(noneAtOpen ? 0 : 1), @"cardsBuiltOnHover": @(MMCardsBuiltOnHover() - before),
                @"sameAsCardsUpFront": same, @"differFromCardsUpFront": differ,
                @"logQueriesOnMain": @(MMLogMainThreadQueries()), @"keepReadsOnMain": @(MMKeepMainThreadReads())});
    return 0;
}

#pragma mark - Hangs

/// A stall made on purpose, so the run shows the watchdog catches one and names this function in its stack.
/// Not static, so its name is in the symbol table dladdr reads.
/// It keeps its own frame: no inlining and no tail call, so the stack shows it above usleep.
void MMBenchStallOnPurpose(double ms) __attribute__((noinline, disable_tail_calls));
void MMBenchStallOnPurpose(double ms) { usleep((useconds_t)(ms * 1000)); }

static void RunUntil(BOOL (^done)(void), double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && end.timeIntervalSinceNow > 0) @autoreleasepool {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

/// Hovers card k, then card k + 1 in a pass of its own 3 ms later, and so on to the last. Then done.
static void HoverChain(NSArray<NSMenu *> *cards, NSUInteger k, void (^each)(void), dispatch_block_t done) {
    if (k >= cards.count) { done(); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        Hover(cards[k], NULL);
        each();
        HoverChain(cards, k + 1, each, done);
    });
}

typedef void (^MMBenchStep)(dispatch_semaphore_t done);

/// Every menu open and card hover runs as its own pass of main's run loop, 3 ms after the one before, with Core
/// running beside it. The watchdog logs any pass over 50 ms with main's stack.
static int Hangs(NSArray<NSString *> *args) {
    int rounds = Option(args, @"--rounds", @"5").intValue;
    double limit = Option(args, @"--ms", @"50").doubleValue;
    if (rounds <= 0 || limit <= 0) { fprintf(stderr, "usage: bench hangs [--rounds N] [--ms N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    [NSApplication sharedApplication].activationPolicy = NSApplicationActivationPolicyProhibited;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    MMBenchFixture *fx = Fixture();
    MMBenchFooter *footer = [MMBenchFooter new];
    MMWatchdogStart(limit);

    // The watchdog itself: a pass that sleeps 120 ms on purpose is caught, with this function in its stack.
    dispatch_async(dispatch_get_main_queue(), ^{ MMBenchStallOnPurpose(120); fflush(stderr); });
    RunUntil(^BOOL { return MMWatchdogStalls().count > 0; }, 5);
    NSDictionary *caught = MMWatchdogStalls().firstObject ?: @{};
    MMWatchdogReset();

    MMCoreStart();
    RunUntil(^BOOL { return MMGraph.shared.current != nil; }, 15);
    // The stalls of MMCoreStart and the first snapshot are reported apart, since the gate counts menu opens and card
    // hovers. On a busy Mac they held main in the socket's bind and the breadcrumb read, issue #54's review.
    NSArray *startStalls = MMWatchdogStalls();
    MMWatchdogReset();
    NSUInteger passesBefore = MMWatchdogPasses();

    // Each step makes its snapshot on a queue of its own, prepared off main as the graph queue does, then opens the
    // menu on main and hovers each card in a pass of its own.
    dispatch_queue_t prepQ = dispatch_queue_create("no.guerrilla.minmacs.bench.prep", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger opens = 0, hovers = 0, liveOpens = 0;
    NSMutableDictionary<NSString *, NSNumber *> *hoversBy = [NSMutableDictionary new], *opensBy = [NSMutableDictionary new];
    __block BOOL finished = NO;
    NSMutableArray<MMBenchStep> *steps = [NSMutableArray new];
    for (int r = 0; r < rounds; r++) {
        for (id<MMExpert> e in fx.experts) {
            NSString *eid = e.expertID;
            void (^counted)(void) = ^{ hovers++; hoversBy[eid] = @(hoversBy[eid].integerValue + 1); };
            [steps addObject:^(dispatch_semaphore_t done) {
                __block MMSnapshot *s = nil;
                dispatch_sync(prepQ, ^{ s = [fx fresh]; });
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSMenu *m = MMShellMenu(e, s, nil, footer);
                    opens++; opensBy[eid] = @(opensBy[eid].integerValue + 1);
                    HoverChain(WaitingCards(m), 0, counted, ^{ dispatch_semaphore_signal(done); });
                });
            }];
            // The same menu on the live snapshot Core published last, which the graph queue prepared.
            [steps addObject:^(dispatch_semaphore_t done) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    MMSnapshot *live = MMGraph.shared.current;
                    NSMenu *m = live ? MMShellMenu(e, live, nil, footer) : nil;
                    if (m) liveOpens++;
                    HoverChain(m ? WaitingCards(m) : @[], 0, counted, ^{ dispatch_semaphore_signal(done); });
                });
            }];
        }
        [steps addObject:^(dispatch_semaphore_t done) {
            __block MMSnapshot *s = nil;
            dispatch_sync(prepQ, ^{ s = [fx fresh]; });
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMenu *m = MMShellOneIconMenu(s, nil, footer);
                opens++;
                HoverChain(WaitingCards(m), 0, ^{ hovers++; }, ^{ dispatch_semaphore_signal(done); });
            });
        }];
    }
    dispatch_async(dispatch_queue_create("no.guerrilla.minmacs.bench.steps", DISPATCH_QUEUE_SERIAL), ^{
        for (MMBenchStep step in steps) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            step(done);
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
            usleep(3000);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    });
    RunUntil(^BOOL { return finished; }, 600);
    RunMain(0.3);
    MMWatchdogStop();
    NSArray *stalls = MMWatchdogStalls();
    MMCoreStop();
    PrintJSON(@{@"kind": @"hangs", @"rounds": @(rounds), @"limitMs": @(limit), @"finished": @(finished),
                @"opens": @(opens), @"liveOpens": @(liveOpens), @"hovers": @(hovers), @"opensBy": opensBy, @"hoversBy": hoversBy,
                @"passes": @(MMWatchdogPasses() - passesBefore), @"stalls": stalls, @"startStalls": startStalls,
                @"selfCheck": @{@"ms": caught[@"ms"] ?: @0, @"state": caught[@"state"] ?: @"", @"what": caught[@"what"] ?: @"",
                                @"named": @([[caught[@"stack"] componentsJoinedByString:@"\n"] containsString:@"MMBenchStallOnPurpose"])},
                @"logQueriesOnMain": @(MMLogMainThreadQueries()), @"keepReadsOnMain": @(MMKeepMainThreadReads())});
    return 0;
}

#pragma mark - Startup

/// The app's launch from where MMMain starts, headless: Core, the status items as the shell makes them but without the
/// status bar, and each expert's first summary line. Run it twice in one MINMACS_HOME: the second run is a later
/// launch, where an expert whose field was empty starts with its item left for later.
static int Startup(NSArray<NSString *> *args) {
    double wait = Option(args, @"--wait", @"10").doubleValue;
    if (wait <= 0) { fprintf(stderr, "usage: bench startup [--wait N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    [NSApplication sharedApplication].activationPolicy = NSApplicationActivationPolicyProhibited;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    // main.m registers the experts, then calls MMMain. The modes are set before, so nothing acts.
    MMRegisterBuiltInExperts();
    AllIdle();
    BOOL first = !MMPrefBool(@"core.launched", NO);
    MMStartupBegin();
    id shell = MMShellStartHeadless();
    NSDictionary *atStart = MMStartupTimes();
    RunUntil(^BOOL { return MMStartupTimes()[@"summaries"] != nil; }, wait);
    NSDictionary *t = MMStartupTimes();
    MMSnapshot *s = MMGraph.shared.current;
    NSMutableDictionary *empty = [NSMutableDictionary new], *summaries = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) {
        empty[e.expertID] = @(s ? [e fieldEmptyIn:s] : YES);
        summaries[e.expertID] = s ? [e menuFor:s].summary ?: @"" : @"";
    }
    MMShellStopHeadless(shell);
    PrintJSON(@{@"kind": @"startup", @"firstLaunch": @(first), @"times": t, @"itemsAtStart": atStart[@"items"] ?: NSNull.null,
                @"fieldEmpty": empty, @"summaries": summaries, @"experts": [MMExperts() valueForKey:@"expertID"]});
    return 0;
}

#pragma mark - Scale

// Issue #54: scans and review at scale. MMCoreStart with every built-in expert over MINMACS_ROOTS, a fixture of
// test/git/benchfix.py, and MINMACS_CLUTTER_ROOT, a fixture of tools/bench/clutterfix.py, both inside MINMACS_HOME.
// A thread of its own reads the memory of this process and of the worker child every 20 ms.

/// argv[1] of pid, from KERN_PROCARGS2, or nil.
static NSString *FirstArg(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return nil;
    char *buf = malloc(size);
    NSString *out = nil;
    if (buf && sysctl(mib, 3, buf, &size, NULL, 0) == 0) {
        int argc; memcpy(&argc, buf, sizeof argc);
        char *p = buf + sizeof argc, *end = buf + size;
        while (p < end && *p) p++;          // the exec path
        while (p < end && !*p) p++;         // its padding
        if (argc >= 2 && p < end) {
            while (p < end && *p) p++;      // argv[0]
            p++;
            if (p < end) out = [[NSString alloc] initWithBytes:p length:strnlen(p, (size_t)(end - p)) encoding:NSUTF8StringEncoding];
        }
    }
    free(buf);
    return out;
}

/// The worker children: children of this process that run this binary as `bench _walk`. git's children run git.
static NSArray<NSNumber *> *WorkerPids(void) {
    static char me[PROC_PIDPATHINFO_MAXSIZE]; static dispatch_once_t once;
    dispatch_once(&once, ^{ if (proc_pidpath(getpid(), me, sizeof me) <= 0) me[0] = 0; });
    pid_t pids[256];
    int n = proc_listchildpids(getpid(), pids, (int)sizeof pids);
    NSMutableArray *out = [NSMutableArray new];
    for (int i = 0; i < n && i < 256; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (pids[i] > 1 && proc_pidpath(pids[i], path, sizeof path) > 0 && me[0] && !strcmp(path, me) &&
            [FirstArg(pids[i]) isEqualToString:@"_walk"]) [out addObject:@(pids[i])];
    }
    return out;
}

/// Peak memory by phase: this process's footprint, and the worker child's footprint and lifetime peak.
@interface MMBenchMemory : NSObject
- (void)phase:(NSString *)name;
- (NSDictionary *)report;
@end

@implementation MMBenchMemory {
    dispatch_source_t _timer;
    NSString *_phase;
    NSMutableArray<NSString *> *_order;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_byPhase;
    NSMutableSet<NSNumber *> *_workers;
}

- (instancetype)init {
    if ((self = [super init])) {
        _order = [NSMutableArray new]; _byPhase = [NSMutableDictionary new]; _workers = [NSMutableSet new];
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_queue_create("no.guerrilla.minmacs.bench.memory", DISPATCH_QUEUE_SERIAL));
        dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
        __weak MMBenchMemory *weak = self;
        dispatch_source_set_event_handler(_timer, ^{ [weak sample]; });
        dispatch_resume(_timer);
    }
    return self;
}

- (void)sample {
    MMBenchSelf me = ReadSelf();
    uint64_t now = 0, life = 0;
    NSArray *pids = WorkerPids();
    for (NSNumber *pid in pids) {
        MMBenchProc p = ReadProc(pid.intValue);
        if (!p.ok) continue;
        now += p.footprint; life = MAX(life, p.peakFootprint);
    }
    @synchronized (self) {
        [_workers addObjectsFromArray:pids];
        NSMutableDictionary *d = _phase ? _byPhase[_phase] : nil;
        if (!d) return;
        d[@"samples"] = @([d[@"samples"] integerValue] + 1);
        if (me.footprint > [d[@"core"] unsignedLongLongValue]) d[@"core"] = @(me.footprint);
        if (now > [d[@"worker"] unsignedLongLongValue]) d[@"worker"] = @(now);
        if (life > [d[@"workerLife"] unsignedLongLongValue]) d[@"workerLife"] = @(life);
        if (pids.count) [d[@"pids"] addObjectsFromArray:pids];
    }
}

- (void)phase:(NSString *)name {
    [self sample];
    @synchronized (self) {
        _phase = name;
        if (name && !_byPhase[name]) {
            _byPhase[name] = [@{@"samples": @0, @"pids": [NSMutableSet new]} mutableCopy];
            [_order addObject:name];
        }
    }
    [self sample];
}

- (NSDictionary *)report {
    [self sample];
    NSMutableDictionary *out = [NSMutableDictionary new];
    @synchronized (self) {
        for (NSString *k in _order) {
            NSDictionary *d = _byPhase[k];
            out[k] = @{@"samples": d[@"samples"], @"corePeakMB": R2(MB([d[@"core"] unsignedLongLongValue])),
                       @"workerPeakMB": R2(MB(MAX([d[@"worker"] unsignedLongLongValue], [d[@"workerLife"] unsignedLongLongValue]))),
                       @"workerPids": @([d[@"pids"] count])};
        }
        out[@"workerPidsSeen"] = @(_workers.count);
    }
    return out;
}

- (void)stop { dispatch_source_cancel(_timer); }
@end

/// Every checkout's git facts are in memory: the number with facts, of all the index lists.
static NSUInteger KnownFacts(void) {
    NSUInteger n = 0;
    for (MMWorktree *w in MMRepoIndex.shared.worktrees) if ([MMRepoIndex.shared factsFor:w wait:NO]) n++;
    return n;
}

/// Runs block on a queue off main while main keeps its run loop, and returns the seconds it took.
static double TimedOffMain(dispatch_queue_t q, dispatch_block_t block, double limit) {
    __block BOOL done = NO;
    __block uint64_t took = 0;
    dispatch_async(q, ^{ uint64_t t0 = NowNs(); block(); took = NowNs() - t0; done = YES; });
    RunUntil(^BOOL { return done; }, limit);
    return done ? took / 1e9 : -1;
}

/// A full walk and the update pass after it, as the 10-minute timer runs it. Off main. Returns NO on a timeout.
/// *walk is the seconds until the worker's walk was in.
static BOOL WalkAndSettle(double limit, double *walk) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    NSInteger done = ix.stats[@"walksDone"].integerValue;
    uint64_t t0 = NowNs(), end = t0 + (uint64_t)(limit * 1e9);
    [ix refresh:nil];
    while (ix.stats[@"walksDone"].integerValue <= done) { if (NowNs() > end) return NO; usleep(1000); }
    if (walk) *walk = (NowNs() - t0) / 1e9;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    [ix updateFacts:^(NSUInteger ran) { dispatch_semaphore_signal(s); }];
    return dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC))) == 0;
}

static NSInteger Counter(NSDictionary *a, NSDictionary *b, NSString *k) { return [b[k] integerValue] - [a[k] integerValue]; }

/// What the graph's builds cost between two reads of -[MMGraph costs]: builds, skips, and CPU ms a build by part.
static NSDictionary *GraphCosts(NSDictionary *a, NSDictionary *b) {
    double builds = MAX(1, [b[@"builds"] doubleValue] - [a[@"builds"] doubleValue]);
    NSMutableDictionary *per = [NSMutableDictionary new];
    for (NSString *k in b) {
        if ([k isEqualToString:@"builds"] || [k isEqualToString:@"skipped"] || [k hasPrefix:@"reused."]) continue;
        per[k] = R3(([b[k] doubleValue] - [a[k] doubleValue]) / 1e6 / builds);
    }
    return @{@"builds": @(Counter(a, b, @"builds")), @"skipped": @(Counter(a, b, @"skipped")), @"perBuildCPUms": per};
}

static NSDictionary *UsageOf(MMReview *r, double seconds) {
    NSInteger uncached = 0, cacheRead = 0, output = 0, input = 0, writes = 0;
    double cost = 0;
    NSMutableArray *callSeconds = [NSMutableArray new];
    for (MMUsage *u in r.calls) {
        uncached += u.uncached; cacheRead += u.cacheRead; output += u.output; input += u.input;
        writes += u.cacheWrite5m + u.cacheWrite1h; cost += u.listCostUSD;
        [callSeconds addObject:@(u.seconds)];
    }
    return @{@"seconds": R3(seconds), @"sent": @(r.sent), @"verdicts": @(r.verdicts.count), @"calls": @(r.calls.count),
             @"decided": r.decided ?: @{}, @"error": r.error ?: NSNull.null, @"uncachedTokens": @(uncached),
             @"cacheReadTokens": @(cacheRead), @"cacheWriteTokens": @(writes), @"outputTokens": @(output), @"inputTokens": @(input),
             @"listCostUSD": R3(cost * 1000), @"listCostUnit": @"thousandths of a dollar",
             @"callSeconds": Stats(callSeconds), @"uncachedPerFinding": R2(r.sent ? (double)uncached / r.sent : 0)};
}

/// bench scale: a launch over the fixture roots, warm walks, the clutter scans and a review of N worktrees.
static int Scale(NSArray<NSString *> *args) {
    NSUInteger expect = (NSUInteger)Option(args, @"--expect", @"300").integerValue;
    int warmRuns = Option(args, @"--warm", @"5").intValue;
    NSUInteger reviewN = (NSUInteger)Option(args, @"--review", @"0").integerValue;
    BOOL clutter = [args containsObject:@"--clutter"];
    double idleWait = Option(args, @"--idle", @"10").doubleValue;
    if (!SafeEnvironment()) return 2;
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (!env[@"MINMACS_ROOTS"].length) { fprintf(stderr, "bench: scale needs MINMACS_ROOTS inside MINMACS_HOME\n"); return 2; }
    if (clutter && (!env[@"MINMACS_CLUTTER_ROOT"].length || !Inside(env[@"MINMACS_CLUTTER_ROOT"], env[@"MINMACS_HOME"]))) {
        fprintf(stderr, "bench: --clutter needs MINMACS_CLUTTER_ROOT inside MINMACS_HOME\n"); return 2;
    }
    if (reviewN && [env[@"MINMACS_CLAUDE"] isEqualToString:@"/usr/bin/false"]) {
        fprintf(stderr, "bench: --review needs MINMACS_CLAUDE to name a fake inside MINMACS_HOME\n"); return 2;
    }
    [NSApplication sharedApplication].activationPolicy = NSApplicationActivationPolicyProhibited;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    MMRegisterBuiltInExperts();
    NSArray *notIdle = AllIdle();
    if (notIdle.count) { fprintf(stderr, "bench: these experts are not Idle: %s\n", [notIdle componentsJoinedByString:@" "].UTF8String); return 1; }
    BOOL cached = [NSFileManager.defaultManager fileExistsAtPath:[MMSupportDir() stringByAppendingPathComponent:@"git.json"]];
    // The scheduled reviews would send LocoHost's and MinMacs's findings from the real process table to the fake CLI
    // a minute after launch. A day over budget makes them wait. The review below is manual, and a manual review runs.
    MMBudget.shared.dailyUncached = 1;
    [MMBudget.shared record:[MMUsage fromJSON:@{@"input": @2, @"model": @"bench"}] expert:@"bench"];
    MMBenchMemory *mem = [MMBenchMemory new];
    MMRepoIndex *ix = MMRepoIndex.shared;
    NSMutableDictionary *out = [@{@"kind": @"scale", @"expect": @(expect), @"cachesAtLaunch": @(cached)} mutableCopy];
    dispatch_queue_t off = dispatch_queue_create("no.guerrilla.minmacs.bench.scale", DISPATCH_QUEUE_SERIAL);

    // The launch: from MMCoreStart until every checkout has git facts in memory, then until a snapshot holds them.
    MMBenchSelf boot = ReadSelf();
    NSDictionary *gl0 = MMGraph.shared.costs;
    [mem phase:@"launch"];
    uint64_t t0 = NowNs();
    MMCoreStart();
    __block double factsAt = -1;
    RunUntil(^BOOL {
        if (factsAt < 0 && ix.worktrees.count >= expect && KnownFacts() >= ix.worktrees.count) factsAt = (NowNs() - t0) / 1e9;
        return factsAt >= 0;
    }, 600);
    __block double graphAt = -1;
    RunUntil(^BOOL {
        MMFacts *f = MMGraph.shared.current.facts;
        NSUInteger withGit = 0;
        for (MMWorktree *w in f.worktrees) if ([f gitFor:w]) withGit++;
        if (factsAt >= 0 && f.worktrees.count >= expect && withGit >= f.worktrees.count) graphAt = (NowNs() - t0) / 1e9;
        return graphAt >= 0;
    }, 120);
    MMBenchSelf launched = ReadSelf();
    NSDictionary *st = ix.stats;
    out[@"launch"] = @{@"factsSeconds": R3(factsAt), @"snapshotSeconds": R3(graphAt), @"worktrees": @(ix.worktrees.count),
                       @"withFacts": @(KnownFacts()), @"cpuSeconds": R3((launched.cpuNs - boot.cpuNs) / 1e9),
                       @"childCPUSeconds": R3((launched.childCPUNs - boot.childCPUNs) / 1e9),
                       @"gitRuns": st[@"gitRuns"] ?: @0, @"statusRuns": st[@"statusRuns"] ?: @0, @"historyRuns": st[@"historyRuns"] ?: @0,
                       @"patchIdsComputed": st[@"patchIdsComputed"] ?: @0, @"squashChecks": st[@"squashChecks"] ?: @0,
                       @"walks": st[@"walksDone"] ?: @0, @"lastUpdateMs": st[@"lastUpdateMs"] ?: @0,
                       @"graph": GraphCosts(gl0, MMGraph.shared.costs)};
    NSMutableDictionary *kinds = [NSMutableDictionary new];
    for (MMWorktree *w in ix.worktrees) {
        NSString *k = [ix factsFor:w wait:NO].json[@"merged"] ?: @"unknown";
        kinds[k] = @([kinds[k] integerValue] + 1);
    }
    out[@"merged"] = kinds;

    // Warm: the full walk the 10-minute timer runs, with every fingerprint read again. git runs for none.
    [mem phase:@"warm"];
    NSMutableArray *warm = [NSMutableArray new], *warmCPU = [NSMutableArray new], *rebuild = [NSMutableArray new];
    NSMutableArray *walks = [NSMutableArray new], *passes = [NSMutableArray new];
    NSDictionary *w0 = ix.stats, *g0 = MMGraph.shared.costs;
    for (int i = 0; i < warmRuns; i++) {
        uint64_t c0 = ProcessCPUNs();
        __block double walk = -1;
        double secs = TimedOffMain(off, ^{ WalkAndSettle(60, &walk); }, 90);
        [warm addObject:@(secs)];
        [walks addObject:@(walk)];
        [passes addObject:ix.stats[@"lastUpdateMs"] ?: @(-1)];
        [warmCPU addObject:@((ProcessCPUNs() - c0) / 1e9)];
        // A rebuild over the 300 checkouts, from the request to the snapshot on main.
        uint64_t g = MMGraph.shared.current.generation, r0 = NowNs();
        [MMGraph.shared rebuild:@"bench"];
        RunUntil(^BOOL { return MMGraph.shared.current.generation > g; }, 30);
        [rebuild addObject:@((NowNs() - r0) / 1e6)];
    }
    NSDictionary *w1 = ix.stats;
    out[@"warm"] = @{@"seconds": Stats(warm), @"cpuSeconds": Stats(warmCPU), @"gitRuns": @(Counter(w0, w1, @"gitRuns")),
                     @"statusRuns": @(Counter(w0, w1, @"statusRuns")), @"historyRuns": @(Counter(w0, w1, @"historyRuns")),
                     @"fingerprintReads": @(Counter(w0, w1, @"fingerprintReads")), @"walks": @(Counter(w0, w1, @"walksDone")),
                     @"walkSeconds": Stats(walks), @"lastPassMs": Stats(passes), @"rebuildMs": Stats(rebuild), @"graph": GraphCosts(g0, MMGraph.shared.costs)};
    MMSnapshot *snap = MMGraph.shared.current;
    NSMutableDictionary *findings = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) findings[e.expertID] = @([snap findingsFor:e.expertID].count);
    out[@"findings"] = findings;
    out[@"workstreams"] = @(snap.workstreams.count);

    // The clutter tree: every row scanned through the worker, then again.
    if (clutter) {
        [mem phase:@"clutter"];
        MMClutterCatalog *c = MMClutterCatalog.shared;
        __block NSArray<MMClutterItem *> *items = nil;
        dispatch_queue_t cq = MMQueue(@"core", @"clutter", QOS_CLASS_UTILITY);
        uint64_t c0 = ProcessCPUNs(); MMBenchSelf cs = ReadSelf();
        double first = TimedOffMain(cq, ^{ items = [c scan]; }, 600);
        double firstCPU = (ProcessCPUNs() - c0) / 1e9; MMBenchSelf ce = ReadSelf();
        double again = TimedOffMain(cq, ^{ items = [c scan]; }, 600);
        uint64_t alloc = 0, freed = 0; NSInteger files = 0;
        NSMutableDictionary *rows = [NSMutableDictionary new];
        for (MMClutterItem *it in items) {
            alloc += it.size.allocated; freed += it.size.freedIfDeleted; files += it.size.files;
            rows[it.kind.kindID] = @([rows[it.kind.kindID] integerValue] + 1);
        }
        out[@"clutter"] = @{@"firstSeconds": R3(first), @"againSeconds": R3(again), @"cpuSeconds": R3(firstCPU),
                            @"childCPUSeconds": R3((ce.childCPUNs - cs.childCPUNs) / 1e9), @"items": @(items.count), @"rows": rows,
                            @"allocatedGB": R2(alloc / 1e9), @"freedIfDeletedGB": R2(freed / 1e9), @"files": @(files)};
    }

    // A review of N worktrees through the fake CLI: once past the fingerprint cache, then again with it.
    if (reviewN) {
        [mem phase:@"review"];
        MMSnapshot *s = MMGraph.shared.current;
        NSMutableArray *pick = [NSMutableArray new];
        NSArray *all = [MMWFReviewable([s findingsFor:@"workforest"]) sortedArrayUsingComparator:^NSComparisonResult(MMFinding *a, MMFinding *b) {
            return [a.path compare:b.path];
        }];
        // The first N linked worktrees by path, copied without their work keeps. The fixture's worktrees were made a
        // minute ago, so WorkForest's rules keep every one, and a review would send none. The request is WorkForest's
        // own: its prompt, words, facts per finding and shared keys, under an expert id with no rules of its own.
        for (MMFinding *f in all) {
            if (pick.count >= reviewN) break;
            [pick addObject:[MMFinding expert:f.expert kind:f.kind stableKey:f.stableKey build:^(MMFindingBuilder *b) {
                b.instanceKey = f.instanceKey; b.title = f.title; b.path = f.path; b.fingerprint = f.fingerprint;
                b.ownerPath = f.ownerPath; b.owner = f.owner; b.cost = f.cost; b.evidence = f.evidence;
                b.proposal = f.proposal; b.procs = f.procs; b.facts = f.facts;
            }]];
        }
        __block MMReview *first = nil, *again = nil;
        MMReviewRequest *(^request)(void) = ^MMReviewRequest *{
            MMReviewRequest *q = MMWFReviewRequest(pick, s, @"manual", MMModeIdle, @"auto");
            q.expert = @"benchscale";
            return q;
        };
        MMReviewRequest *q = request();
        q.ignoreCache = YES;
        double t1 = TimedOffMain(off, ^{ first = [MMReviewBroker.shared run:q]; }, 600);
        MMReviewRequest *q2 = request();
        double t2 = TimedOffMain(off, ^{ again = [MMReviewBroker.shared run:q2]; }, 600);
        out[@"review"] = @{@"asked": @(pick.count), @"reviewable": @(all.count), @"first": first ? UsageOf(first, t1) : NSNull.null,
                           @"cached": again ? UsageOf(again, t2) : NSNull.null, @"batchSize": @(q.batchSize), @"parallel": @(q.parallel)};
    }

    // Back to idle: the worker child closes 30 seconds after its last request. Then a quiet window. --idle 0 skips it.
    if (idleWait > 0) {
        [mem phase:@"after"];
        uint64_t a0 = NowNs();
        RunUntil(^BOOL { return WorkerPids().count == 0; }, 60);
        double workerGone = WorkerPids().count ? -1 : (NowNs() - a0) / 1e9;
        MMBenchSelf ia = ReadSelf();
        NSDictionary *ga = MMGraph.shared.costs, *ra = ix.stats;
        RunMain(idleWait);
        MMBenchSelf ib = ReadSelf();
        NSDictionary *gb = MMGraph.shared.costs, *rb = ix.stats;
        double window = (ib.wallNs - ia.wallNs) / 1e9;
        out[@"idleAfter"] = @{@"workerGoneSeconds": R3(workerGone), @"windowSeconds": R3(window),
                              @"cpuPercent": R3((ib.cpuNs - ia.cpuNs) / 1e9 / window * 100), @"footprintMB": R2(MB(ib.footprint)),
                              @"footprintAtLaunchMB": R2(MB(launched.footprint)), @"footprintBootMB": R2(MB(boot.footprint)),
                              @"lifetimePeakFootprintMB": R2(MB(ib.peakFootprint)), @"workerChildren": @(WorkerPids().count),
                              @"graph": GraphCosts(ga, gb), @"gitRuns": @(Counter(ra, rb, @"gitRuns")),
                              @"fingerprintReads": @(Counter(ra, rb, @"fingerprintReads")), @"sizeWalks": @(Counter(ra, rb, @"sizeWalks"))};
    }
    out[@"memory"] = [mem report];
    [mem stop];
    MMCoreStop();
    out[@"undoRecords"] = @([MMUndo.shared recent:nil limit:1000].count);
    PrintJSON(out);
    return 0;
}

#pragma mark - Apps

static int Apps(void) {
    NSArray *apps = OldApps();
    NSDictionary *ps = PS(apps);
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *a in apps) {
        MMBenchProc p = ReadProc([a[@"pid"] intValue]);
        if (!p.ok) continue;
        [out addObject:@{@"app": a[@"app"], @"pid": a[@"pid"], @"version": a[@"version"], @"cpuSecondsTotal": (R2(p.cpuNs / 1e9)),
                         @"footprintMB": (R2(MB(p.footprint))), @"residentMB": (R2(MB(p.resident))),
                         @"peakFootprintMB": (R2(MB(p.peakFootprint))), @"ps": ps[a[@"pid"]] ?: @{}}];
    }
    PrintJSON(@{@"kind": @"apps", @"apps": out});
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        gTicksToNs = (double)tb.numer / tb.denom;
        NSMutableArray *args = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        NSString *mode = args.firstObject ?: @"";
        if ([mode isEqualToString:@"_walk"]) return MMWorkerChildMain();   // the worker child, as `minmacs _walk`
        if ([mode isEqualToString:@"idle"]) return Idle(args);
        if ([mode isEqualToString:@"menus"]) return Menus(args);
        if ([mode isEqualToString:@"hangs"]) return Hangs(args);
        if ([mode isEqualToString:@"startup"]) return Startup(args);
        if ([mode isEqualToString:@"apps"]) return Apps();
        if ([mode isEqualToString:@"scale"]) return Scale(args);
        fprintf(stderr, "usage: bench idle --seconds N [--warmup N] | menus [--iterations N] | hangs [--rounds N] | startup [--wait N] | apps\n"
                        "       bench scale [--expect N] [--warm N] [--clutter] [--review N] [--idle S]\n");
        return 2;
    }
}
