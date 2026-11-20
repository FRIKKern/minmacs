#import "Shell/MMWatchdog.h"
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <libproc.h>
#import <os/lock.h>
#import <pthread.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <time.h>
#import "Core/MMCore.h"

const double MMWatchdogDefaultMs = 50;

enum { kMaxFrames = 64 };
static const uint64_t kLookNs = 1000000;   // how often the watchdog thread reads main's run state while a pass runs

// Written by main's observer, read by the watchdog thread.
static _Atomic uint64_t gGen;          // the pass number; a new pass makes a new one
static _Atomic bool gBusy;             // main is inside a pass
static _Atomic uint64_t gBeginNs, gBeginCPU;
static _Atomic int64_t gBeginNoCPU;    // NoCPUTicks at the same mark, kUnknown when the read failed
/// Where a pass over the threshold ended. Main keeps the last few, since many short passes can end before the
/// watchdog thread wakes to read one.
typedef struct { uint64_t gen, ns, cpu; int64_t noCPU; } PassEnd;
enum { kEndsKept = 16 };
static PassEnd gEnds[kEndsKept];       // under gEndsLock
static unsigned gEndsCount;
static os_unfair_lock gEndsLock = OS_UNFAIR_LOCK_INIT;
static _Atomic bool gParked;           // the watchdog thread waits for a pass to start
static _Atomic bool gRunning;
static _Atomic uint64_t gThresholdNs;
static _Atomic NSUInteger gPasses;

static dispatch_semaphore_t gWake;
static CFRunLoopObserverRef gBegin, gEnd;   // first and last in their activities, so other observers' work counts
static mach_port_t gMain;
static NSMutableArray<NSDictionary *> *gStalls;   // under @synchronized (gStalls)

static uint64_t NowNs(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static uint64_t ThreadCPUNs(void) { return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID); }

static const int64_t kUnknown = INT64_MIN;
/// How long this process's threads have been ready to run with no CPU to run on, all of them together, in mach time.
/// The kernel's runnable time counts the time they ran too, so the CPU they used comes off. kUnknown when it cannot
/// be read.
static int64_t NoCPUTicks(void) {
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return kUnknown;
    return (int64_t)ri.ri_runnable_time - (int64_t)(ri.ri_user_time + ri.ri_system_time);
}

BOOL MMWatchdogWanted(NSDictionary<NSString *, NSString *> *env) {
#ifdef MM_DEBUG
    return YES;
#else
    return [env[@"MINMACS_WATCHDOG"] isEqualToString:@"1"];
#endif
}

#pragma mark - Main's side

static void End(void);

static void Begin(void) {
    // A pass that goes on into a new one without a wait, such as when the loop returns to its caller, ends here.
    // Its end is kept as any other, so its stall has the CPU it used.
    if (atomic_load(&gBusy)) End();
    atomic_store(&gBeginNoCPU, NoCPUTicks());
    atomic_store(&gBeginCPU, ThreadCPUNs());
    atomic_store(&gBeginNs, NowNs());
    atomic_fetch_add(&gGen, 1);
    atomic_store(&gBusy, true);
    atomic_fetch_add(&gPasses, 1);
    if (atomic_exchange(&gParked, false)) dispatch_semaphore_signal(gWake);
}

static void End(void) {
    if (!atomic_load(&gBusy)) return;
    uint64_t cpu = ThreadCPUNs(), now = NowNs();
    if (now - atomic_load(&gBeginNs) >= atomic_load(&gThresholdNs)) {
        PassEnd e = { atomic_load(&gGen), now, cpu, NoCPUTicks() };
        os_unfair_lock_lock(&gEndsLock);
        gEnds[gEndsCount++ % kEndsKept] = e;
        os_unfair_lock_unlock(&gEndsLock);
    }
    atomic_store(&gBusy, false);
}

/// The end of pass gen, when main kept one: it ran over the threshold by main's own clock.
static BOOL EndOf(uint64_t gen, PassEnd *end) {
    BOOL found = NO;
    os_unfair_lock_lock(&gEndsLock);
    for (int k = 0; k < kEndsKept; k++) if (gEnds[k].gen == gen) { *end = gEnds[k]; found = YES; }
    os_unfair_lock_unlock(&gEndsLock);
    return found;
}

/// A pass starts when the loop starts an iteration or wakes, and ends when it goes to sleep. A nested loop, such as a
/// menu's tracking loop, makes passes of its own. When it exits, the outer pass goes on as a new one.
static void Observe(CFRunLoopObserverRef o, CFRunLoopActivity a, void *info) {
    switch (a) {
        case kCFRunLoopEntry: case kCFRunLoopBeforeTimers: case kCFRunLoopAfterWaiting: case kCFRunLoopExit: Begin(); break;
        case kCFRunLoopBeforeWaiting: End(); break;
        default: break;
    }
}

#pragma mark - The watchdog's side

/// Main's frames, innermost first. Main is suspended between the two calls, so nothing here allocates or locks.
static int Frames(uintptr_t *pcs, int max) {
    int n = 0;
    uintptr_t pc = 0, fp = 0, lr = 0;
#if defined(__arm64__)
    arm_thread_state64_t st; mach_msg_type_number_t c = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(gMain, ARM_THREAD_STATE64, (thread_state_t)&st, &c) != KERN_SUCCESS) return 0;
    pc = (uintptr_t)arm_thread_state64_get_pc(st); fp = (uintptr_t)arm_thread_state64_get_fp(st); lr = (uintptr_t)arm_thread_state64_get_lr(st);
#elif defined(__x86_64__)
    x86_thread_state64_t st; mach_msg_type_number_t c = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(gMain, x86_THREAD_STATE64, (thread_state_t)&st, &c) != KERN_SUCCESS) return 0;
    pc = (uintptr_t)st.__rip; fp = (uintptr_t)st.__rbp;
#endif
    // System code signs its return addresses. The pointer's own bits are the low 47.
    const uintptr_t mask = 0x00007FFFFFFFFFFFULL;
    if (pc && n < max) pcs[n++] = pc & mask;
    if (lr && n < max) pcs[n++] = lr & mask;   // a leaf function may not have pushed a frame yet
    for (int k = 0; fp && n < max && k < 512; k++) {
        uintptr_t frame[2] = {0, 0};
        vm_size_t got = 0;
        if (fp & 7) break;
        if (vm_read_overwrite(mach_task_self(), (vm_address_t)fp, sizeof frame, (vm_address_t)frame, &got) != KERN_SUCCESS || got != sizeof frame) break;
        uintptr_t ret = frame[1] & mask;
        if (!ret) break;
        if (!(n == 2 && ret == pcs[1])) pcs[n++] = ret;
        if ((frame[0] & mask) <= fp) break;     // the stack grows down, so each caller's frame sits higher
        fp = frame[0] & mask;
    }
    return n;
}

static NSArray<NSString *> *Symbols(const uintptr_t *pcs, int n, NSString **what) {
    NSMutableArray *out = [NSMutableArray new];
    NSString *mine = nil, *first = nil;
    const char *exe = NULL;
    Dl_info self;
    if (dladdr((const void *)&Frames, &self)) exe = self.dli_fname;
    for (int k = 0; k < n; k++) {
        Dl_info d;
        NSString *line;
        if (dladdr((const void *)pcs[k], &d) && d.dli_fname) {
            NSString *image = @(d.dli_fname).lastPathComponent;
            if (d.dli_sname) line = [NSString stringWithFormat:@"%@ %s + %lu", image, d.dli_sname, (unsigned long)(pcs[k] - (uintptr_t)d.dli_saddr)];
            else line = [NSString stringWithFormat:@"%@ 0x%lx", image, (unsigned long)(pcs[k] - (uintptr_t)d.dli_fbase)];
            if (!mine && exe && d.dli_sname && strcmp(d.dli_fname, exe) == 0) mine = line;
        } else line = [NSString stringWithFormat:@"0x%lx", (unsigned long)pcs[k]];
        if (!first) first = line;
        [out addObject:line];
    }
    if (what) *what = mine ?: first ?: @"no frames";
    return out;
}

static NSString *StallsPath(void) {
    NSString *dir = MMSupportDir();
    return dir.length ? [dir stringByAppendingPathComponent:@"stalls.log"] : nil;
}

static void Record(double ms, double cpuMs, double readyMs, NSString *state, NSArray *stack, NSString *what) {
    NSDictionary *s = @{@"ms": @(round(ms * 10) / 10), @"cpuMs": @(round(cpuMs * 10) / 10), @"readyMs": @(round(readyMs * 10) / 10),
                        @"state": state, @"at": @(round(NSDate.date.timeIntervalSince1970)), @"stack": stack, @"what": what ?: @""};
    @synchronized (gStalls) { [gStalls addObject:s]; }
    NSLog(@"MinMacs: main stalled %.0f ms, %.0f ms CPU, %.0f ms ready with no CPU, %@, in %@\n  %@", ms, cpuMs, readyMs, state, what,
          [stack componentsJoinedByString:@"\n  "]);
    NSString *path = StallsPath();
    NSData *line = [NSJSONSerialization dataWithJSONObject:s options:0 error:nil];
    if (!path || !line) return;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:NO];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    [h seekToEndOfFile];
    [h writeData:line];
    [h writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static void SleepNs(uint64_t ns) {
    struct timespec t = { (time_t)(ns / 1000000000ull), (long)(ns % 1000000000ull) };
    nanosleep(&t, NULL);
}

/// One look at main while pass gen runs. When main runs or is ready to, the time since the last look counts as seen
/// ready. A read that fails counts as blocked, and so does a wait that cannot be interrupted, such as a page read
/// from disk. A look after the pass ended counts nothing: the end settles the time since the last look.
static void Look(uint64_t gen, uint64_t *seenReady, uint64_t *last) {
    thread_basic_info_data_t info; mach_msg_type_number_t c = THREAD_BASIC_INFO_COUNT;
    BOOL ready = thread_info(gMain, THREAD_BASIC_INFO, (thread_info_t)&info, &c) == KERN_SUCCESS && info.run_state == TH_STATE_RUNNING;
    uint64_t now = NowNs();
    if (atomic_load(&gGen) != gen || !atomic_load(&gBusy)) return;
    if (ready && now > *last) *seenReady += now - *last;
    *last = now;
}

/// How much of a pass main was ready to run and had no CPU, in ms. No call gives that for one thread, so it is the
/// smaller of two numbers that are each too large at times: what the kernel counts for the whole process, which
/// holds the waiting of every other thread too, and what the looks saw, less the CPU main used. The time between
/// the last look and the end counts as seen ready, since the watchdog thread may have had no CPU itself. So main
/// busy never counts as ready, and main blocked does not either as long as the watchdog thread gets to look.
static double ReadyMs(double ms, double cpuMs, uint64_t seenReady, int64_t noCPUBegin, int64_t noCPUEnd) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    double process = noCPUBegin != kUnknown && noCPUEnd != kUnknown && noCPUEnd > noCPUBegin
        ? (double)(noCPUEnd - noCPUBegin) * tb.numer / tb.denom / 1e6 : 0;
    return MAX(0, MIN(MIN(process, seenReady / 1e6 - cpuMs), ms - cpuMs));
}

static void *Watch(void *arg) {
    pthread_setname_np("no.guerrilla.minmacs.shell.watchdog");
    while (atomic_load(&gRunning)) @autoreleasepool {
        if (!atomic_load(&gBusy)) {
            atomic_store(&gParked, true);
            if (!atomic_load(&gBusy)) dispatch_semaphore_wait(gWake, DISPATCH_TIME_FOREVER);
            atomic_store(&gParked, false);
            continue;
        }
        uint64_t gen = atomic_load(&gGen), begin = atomic_load(&gBeginNs), beginCPU = atomic_load(&gBeginCPU);
        int64_t beginNoCPU = atomic_load(&gBeginNoCPU);
        uint64_t due = begin + atomic_load(&gThresholdNs), now;
        // Until the threshold it looks at main every millisecond, and stops when the pass ends.
        uint64_t seenReady = 0, last = begin;
        while ((now = NowNs()) < due && atomic_load(&gRunning) && atomic_load(&gBusy) && atomic_load(&gGen) == gen) {
            SleepNs(MIN(due - now, kLookNs));
            Look(gen, &seenReady, &last);
        }
        if (!atomic_load(&gRunning)) break;
        if (!atomic_load(&gBusy) || atomic_load(&gGen) != gen) continue;
        // The same pass still runs past the threshold: read main's state and stack now.
        thread_basic_info_data_t info; mach_msg_type_number_t c = THREAD_BASIC_INFO_COUNT;
        BOOL waits = thread_info(gMain, THREAD_BASIC_INFO, (thread_info_t)&info, &c) == KERN_SUCCESS && info.run_state == TH_STATE_WAITING;
        uintptr_t pcs[kMaxFrames];
        int n = 0;
        if (thread_suspend(gMain) == KERN_SUCCESS) {
            n = Frames(pcs, kMaxFrames);
            thread_resume(gMain);
        }
        if (atomic_load(&gGen) != gen) n = 0;   // the pass ended while main stopped; these frames belong to the next one
        while (atomic_load(&gRunning) && atomic_load(&gGen) == gen && atomic_load(&gBusy)) { SleepNs(kLookNs); Look(gen, &seenReady, &last); }
        // Main keeps the end of a pass that ran over the threshold. With none kept, the pass ended in time by main's
        // clock and is no stall, unless the watchdog stopped inside it: then it ends now, and nothing counts as ready.
        // A stall is lost only when kEndsKept later passes ran over the threshold before this thread read its end.
        PassEnd e = {0};
        BOOL ended = EndOf(gen, &e);
        if (!ended && atomic_load(&gRunning)) continue;
        uint64_t end = ended ? e.ns : NowNs();
        double ms = (end - begin) / 1e6, cpuMs = ended && e.cpu > beginCPU ? (e.cpu - beginCPU) / 1e6 : 0;
        if (end > last) seenReady += end - last;
        double readyMs = ended ? ReadyMs(ms, cpuMs, seenReady, beginNoCPU, e.noCPU) : 0;
        NSString *what = nil;
        NSArray *stack = Symbols(pcs, n, &what);
        Record(ms, cpuMs, readyMs, waits ? @"waits" : @"runs", stack, what);
    }
    return NULL;
}

#pragma mark - Start and stop

void MMWatchdogStart(double thresholdMs) {
    atomic_store(&gThresholdNs, (uint64_t)((thresholdMs > 0 ? thresholdMs : MMWatchdogDefaultMs) * 1e6));
    if (atomic_load(&gRunning) || !NSThread.isMainThread) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gWake = dispatch_semaphore_create(0);
        gStalls = [NSMutableArray new];
        gMain = pthread_mach_thread_np(pthread_self());
    });
    atomic_store(&gRunning, true);
    gBegin = CFRunLoopObserverCreate(NULL, kCFRunLoopEntry | kCFRunLoopBeforeTimers | kCFRunLoopAfterWaiting | kCFRunLoopExit, true, INT_MIN, Observe, NULL);
    gEnd = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, true, INT_MAX, Observe, NULL);
    CFRunLoopAddObserver(CFRunLoopGetMain(), gBegin, kCFRunLoopCommonModes);
    CFRunLoopAddObserver(CFRunLoopGetMain(), gEnd, kCFRunLoopCommonModes);
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t t;
    pthread_create(&t, &attr, Watch, NULL);
    pthread_attr_destroy(&attr);
}

void MMWatchdogStop(void) {
    if (!atomic_exchange(&gRunning, false)) return;
    CFRunLoopObserverRef *both[] = { &gBegin, &gEnd };
    for (int k = 0; k < 2; k++) {
        if (!*both[k]) continue;
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), *both[k], kCFRunLoopCommonModes);
        CFRelease(*both[k]); *both[k] = NULL;
    }
    atomic_store(&gBusy, false);
    dispatch_semaphore_signal(gWake);
}

BOOL MMWatchdogRunning(void) { return atomic_load(&gRunning); }

NSArray<NSDictionary *> *MMWatchdogStalls(void) {
    if (!gStalls) return @[];
    @synchronized (gStalls) { return [gStalls copy]; }
}

void MMWatchdogReset(void) {
    if (!gStalls) return;
    @synchronized (gStalls) { [gStalls removeAllObjects]; }
}

NSUInteger MMWatchdogPasses(void) { return atomic_load(&gPasses); }
