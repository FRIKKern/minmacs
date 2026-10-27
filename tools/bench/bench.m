// The bench: what MinMacs 2.0 costs at rest, how long its menus take to build, and what the old apps cost
// over the same window. Issues #23 and #51. tools/bench/build.sh builds it from every .m under Sources except
// main.m, with the release flags, so it runs the same Core and experts the app runs.
//
//   bench idle --seconds N [--warmup N]   MMCoreStart with every built-in expert, no status items, every mode Idle.
//                                         Senses samples the real process table. Nothing acts.
//   bench menus [--iterations N]          each expert's menu spec, cards and NSMenu from a fixture snapshot
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
#import "Core/MMCore.h"
#import "Shell/MMShell.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"
#import "Experts/LocoHost/MMLHHost.h"
#import "Experts/MinMacs/MMMinMacs.h"

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
/// a Senses pass, the facts a rebuild gathers, and the snapshot the experts build from them.
/// A sample reads args and cwd once and keeps them, so each part is also timed alone on a sample of its own:
/// the registry, the session index and each expert's findings. Those runs start with a new pass too.
static NSDictionary *TickCost(int n) {
    NSMutableArray *pass = [NSMutableArray new], *passWall = [NSMutableArray new], *facts = [NSMutableArray new], *snap = [NSMutableArray new];
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
            [MMSnapshot snapshotFrom:f experts:MMExperts() reviews:nil holds:nil];
            [facts addObject:@((c1 - c0) / 1e6)];
            [snap addObject:@((ThreadCPUNs() - c1) / 1e6)];
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
             @"factsCPUms": Stats(facts), @"snapshotCPUms": Stats(snap),
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
    NSMutableArray *tickGaps = [NSMutableArray new];
    __block uint64_t prevSampleAt = 0;
    id sensesToken = [MMSenses.shared observe:MMSignalSample block:^(MMSignal changed, id detail) {
        uint64_t cpu = ProcessCPUNs(), now = NowNs();
        if (inWindow) {
            samples++;
            // Everything since the last snapshot reached main: the pass itself, and the quiet time before it.
            if (haveSnap) [passCPU addObject:@((cpu - lastSnapCPU) / 1e6)];
            if (prevSampleAt) [tickGaps addObject:@((now - prevSampleAt) / 1e9)];
        }
        prevSampleAt = now;
        sampleGen = MMSenses.shared.latest.generation; sampleCPU = cpu; sampleAt = now; sampleOpen = YES;
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
    NSDate *startedAt = NSDate.date;
    inWindow = YES;
    RunMain(seconds);
    inWindow = NO;
    MMBenchSelf b = ReadSelf();
    MMBenchProc selfB = ReadProc(getpid());
    double window = (b.wallNs - a.wallNs) / 1e9;
    NSArray *old = OldAppsOver(apps, appStart, psStart, window);

    MMSnapshot *snap = MMGraph.shared.current;
    NSMutableDictionary *findings = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) findings[e.expertID] = @([snap findingsFor:e.expertID].count);
    [MMSenses.shared stopObserving:sensesToken];
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
        @"inWindow": @{@"passCPUms": Stats(passCPU), @"rebuildCPUms": Stats(rebuildCPU), @"rebuildWallms": Stats(rebuildWall)},
        @"tickCost": ticks,
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
                      @[@100130, @100060, @"node", [home stringByAppendingPathComponent:@"docs"]], @[@100500, @1, @"Notes", @"/"]];
    NSMutableDictionary *procs = [NSMutableDictionary new];
    for (NSArray *r in rows) {
        MMBenchProcFix *p = [MMBenchProcFix new];
        p.pid = [r[0] intValue]; p.ppid = [r[1] intValue]; p.uid = getuid(); p.startSec = 1761000000 + (uint64_t)p.pid;
        p.name = r[2]; p.cwd = r[3]; p.cpuPercent = 0.5; p.footprint = 64ull << 20;
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

/// The expert that makes each registered expert's findings for the fixture snapshot, and what it is called.
static id<MMExpert> FixtureSource(id<MMExpert> e, NSString **kind) {
    if ([e.expertID isEqualToString:@"locohost"]) {
        MMBenchReplay *r = [MMBenchReplay new];
        r.expertID = e.expertID; r.findings = LocoHostFixture();
        *kind = @"12 fixture servers";
        return r;
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

static int Menus(NSArray<NSString *> *args) {
    int n = Option(args, @"--iterations", @"200").intValue;
    if (n <= 0) { fprintf(stderr, "usage: bench menus [--iterations N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    [NSApplication sharedApplication];
    // The menu builds where the app builds it: on main at user-interactive QoS.
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    MMRegisterBuiltInExperts();
    AllIdle();
    NSArray<id<MMExpert>> *experts = MMExperts();
    NSMutableArray<id<MMExpert>> *sources = [NSMutableArray new];
    NSMutableDictionary *fixtureKinds = [NSMutableDictionary new];
    for (id<MMExpert> e in experts) { NSString *k = nil; [sources addObject:FixtureSource(e, &k)]; fixtureKinds[e.expertID] = k; }
    MMBenchFooter *footer = [MMBenchFooter new];
    __block uint64_t gen = 1;
    MMSnapshot *(^fresh)(void) = ^MMSnapshot *{ return [MMSnapshot snapshotFrom:FixtureFacts(gen++) experts:sources reviews:nil holds:nil]; };

    NSMutableDictionary *out = [NSMutableDictionary new];
    for (id<MMExpert> e in experts) {
        NSMutableArray *spec = [NSMutableArray new], *open = [NSMutableArray new], *cardBuild = [NSMutableArray new], *hover = [NSMutableArray new];
        __block NSUInteger rows = 0, cards = 0, items = 0;
        for (int i = -3; i < n; i++) @autoreleasepool {   // three turns of warm-up
            // A new generation every turn, so no expert answers from a cache it keeps per snapshot.
            MMSnapshot *s = fresh();
            uint64_t t0 = NowNs();
            MMMenuSpec *m = [e menuFor:s];
            uint64_t t1 = NowNs();
            // What MMExpertItem's menuNeedsUpdate: does on main: the spec, every row's card and the NSMenu.
            NSMenu *menu = MMMenuFromSpec(m, ^MMCardSpec *(NSString *fid) {
                MMFinding *f = [s finding:fid];
                return f ? [e cardFor:f snapshot:s] : nil;
            }, nil, footer);
            uint64_t t2 = NowNs();
            if (i < 0) continue;
            [spec addObject:@((t1 - t0) / 1e6)];
            [open addObject:@((t2 - t0) / 1e6)];
            items = menu.numberOfItems;
            rows = 0; for (MMSectionSpec *sec in m.sections) rows += sec.rows.count;
            // A hover: the card's spec and view, then its layout and drawing as the submenu opens.
            cards = 0;
            for (MMSectionSpec *sec in m.sections) for (MMRowSpec *r in sec.rows) {
                MMFinding *f = r.findingID ? [s finding:r.findingID] : nil;
                if (!f) continue;
                uint64_t c0 = NowNs();
                MMCardSpec *cs = [e cardFor:f snapshot:s];
                if (!cs) continue;
                MMCard *card = MMCardFromSpec(cs);
                NSMenu *cm = [card menu];
                uint64_t c1 = NowNs();
                Draw([cm itemAtIndex:0].view);
                uint64_t c2 = NowNs();
                [cardBuild addObject:@((c1 - c0) / 1e6)];
                [hover addObject:@((c2 - c0) / 1e6)];
                cards++;
            }
        }
        out[e.expertID] = @{@"fixture": fixtureKinds[e.expertID], @"rows": @(rows), @"cards": @(cards), @"items": @(items),
                            @"specMs": Stats(spec), @"menuOpenMs": Stats(open), @"cardBuildMs": Stats(cardBuild), @"cardHoverMs": Stats(hover)};
    }
    // One Icon: one menu with a section per expert, built the way the shell builds it.
    NSMutableArray *one = [NSMutableArray new];
    for (int i = -3; i < n; i++) @autoreleasepool {
        MMSnapshot *s = fresh();
        uint64_t t0 = NowNs();
        NSMutableArray *parts = [NSMutableArray new];
        for (id<MMExpert> e in experts) {
            if ([e fieldEmptyIn:s]) continue;
            MMOneIconPart *p = [MMOneIconPart new];
            p.name = e.name; p.spec = [e menuFor:s];
            p.cards = ^MMCardSpec *(NSString *fid) { MMFinding *f = [s finding:fid]; return f ? [e cardFor:f snapshot:s] : nil; };
            [parts addObject:p];
        }
        MMOneIconMenu(parts, nil, footer);
        if (i >= 0) [one addObject:@((NowNs() - t0) / 1e6)];
    }
    PrintJSON(@{@"kind": @"menus", @"iterations": @(n), @"experts": out, @"oneIconMs": Stats(one)});
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
        if ([mode isEqualToString:@"idle"]) return Idle(args);
        if ([mode isEqualToString:@"menus"]) return Menus(args);
        if ([mode isEqualToString:@"apps"]) return Apps();
        fprintf(stderr, "usage: bench idle --seconds N [--warmup N] | menus [--iterations N] | apps\n");
        return 2;
    }
}
