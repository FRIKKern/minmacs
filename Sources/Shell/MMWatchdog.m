#import "Shell/MMWatchdog.h"
#import <mach/mach.h>
#import <pthread.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <time.h>
#import "Core/MMCore.h"

const double MMWatchdogDefaultMs = 50;

enum { kMaxFrames = 64 };

// Written by main's observer, read by the watchdog thread.
static _Atomic uint64_t gGen;          // the pass number; a new pass makes a new one
static _Atomic bool gBusy;             // main is inside a pass
static _Atomic uint64_t gBeginNs, gBeginCPU, gEndNs, gEndCPU, gEndGen;
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

BOOL MMWatchdogWanted(NSDictionary<NSString *, NSString *> *env) {
#ifdef MM_DEBUG
    return YES;
#else
    return [env[@"MINMACS_WATCHDOG"] isEqualToString:@"1"];
#endif
}

#pragma mark - Main's side

static void Begin(void) {
    atomic_store(&gBeginCPU, ThreadCPUNs());
    atomic_store(&gBeginNs, NowNs());
    atomic_fetch_add(&gGen, 1);
    atomic_store(&gBusy, true);
    atomic_fetch_add(&gPasses, 1);
    if (atomic_exchange(&gParked, false)) dispatch_semaphore_signal(gWake);
}

static void End(void) {
    atomic_store(&gEndCPU, ThreadCPUNs());
    atomic_store(&gEndNs, NowNs());
    atomic_store(&gEndGen, atomic_load(&gGen));
    atomic_store(&gBusy, false);
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

static void Record(double ms, double cpuMs, NSString *state, NSArray *stack, NSString *what) {
    NSDictionary *s = @{@"ms": @(round(ms * 10) / 10), @"cpuMs": @(round(cpuMs * 10) / 10), @"state": state,
                        @"at": @(round(NSDate.date.timeIntervalSince1970)), @"stack": stack, @"what": what ?: @""};
    @synchronized (gStalls) { [gStalls addObject:s]; }
    NSLog(@"MinMacs: main stalled %.0f ms, %.0f ms CPU, %@, in %@\n  %@", ms, cpuMs, state, what, [stack componentsJoinedByString:@"\n  "]);
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
        uint64_t due = begin + atomic_load(&gThresholdNs), now = NowNs();
        if (now < due) SleepNs(due - now);
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
        while (atomic_load(&gRunning) && atomic_load(&gGen) == gen && atomic_load(&gBusy)) SleepNs(2000000);
        uint64_t end = atomic_load(&gEndGen) == gen ? atomic_load(&gEndNs) : NowNs();
        uint64_t endCPU = atomic_load(&gEndGen) == gen ? atomic_load(&gEndCPU) : beginCPU;
        NSString *what = nil;
        NSArray *stack = Symbols(pcs, n, &what);
        Record((end - begin) / 1e6, endCPU > beginCPU ? (endCPU - beginCPU) / 1e6 : 0, waits ? @"waits" : @"runs", stack, what);
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
