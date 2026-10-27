// Labeled queues, dispatch timers, jobs with budgets and crash breadcrumbs. Patterns P1, P2, P3 and P5.
#import "Core/Runtime/MMRuntime.h"
#import "Core/Senses/MMSenses.h"
#import <os/lock.h>
#import <os/log.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/sysctl.h>

/// The support folder: $MINMACS_HOME when set, otherwise ~/Library/Application Support/MinMacs.
/// Store's MMSupportDir says the same. This copy keeps Runtime and Senses free of a link to Store,
/// and can call MMSupportDir once both are merged.
NSString *MMRuntimeSupportDir(void) {
    NSString *env = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    NSString *dir = env.length ? env
        : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

os_log_t MMRuntimeLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "runtime"); });
    return log;
}

#pragma mark - P1 queues

dispatch_queue_t MMQueue(NSString *expert, NSString *job, dispatch_qos_class_t qos) {
    static NSMutableDictionary<NSString *, dispatch_queue_t> *queues;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    NSString *label = [NSString stringWithFormat:@"no.guerrilla.minmacs.%@.%@", expert, job];
    os_unfair_lock_lock(&lock);
    if (!queues) queues = [NSMutableDictionary new];
    dispatch_queue_t q = queues[label];
    if (!q) {
        dispatch_queue_attr_t a = dispatch_queue_attr_make_with_autorelease_frequency(
            DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
        a = dispatch_queue_attr_make_with_qos_class(a, qos, 0);
        q = dispatch_queue_create(label.UTF8String, a);
        queues[label] = q;
    }
    os_unfair_lock_unlock(&lock);
    return q;
}

#pragma mark - P2 timers

dispatch_source_t MMTimer(dispatch_queue_t q, NSTimeInterval every, NSTimeInterval leeway, dispatch_block_t tick) {
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(every * NSEC_PER_SEC)),
                              (uint64_t)(every * NSEC_PER_SEC), (uint64_t)(leeway * NSEC_PER_SEC));
    dispatch_source_set_event_handler(t, tick);
    dispatch_resume(t);
    return t;
}

#pragma mark - P3 jobs

@interface MMJob ()
@property (readwrite, copy) NSString *name, *expert;
@property (readwrite) NSDate *started;
@property (readwrite) NSTimeInterval budget;
@end

@implementation MMJob

/// The jobs whose last turn overran, by "expert.name". Their next turn is skipped once.
static NSMutableSet<NSString *> *gOverran;
static os_unfair_lock gJobLock = OS_UNFAIR_LOCK_INIT;

+ (void)run:(NSString *)name expert:(NSString *)expert on:(dispatch_queue_t)q
     budget:(NSTimeInterval)budget work:(void (^)(MMJob *job))work {
    NSString *key = [NSString stringWithFormat:@"%@.%@", expert, name];
    dispatch_async(q, ^{
        os_unfair_lock_lock(&gJobLock);
        if (!gOverran) gOverran = [NSMutableSet new];
        BOOL skip = [gOverran containsObject:key];
        if (skip) [gOverran removeObject:key];
        os_unfair_lock_unlock(&gJobLock);
        if (skip) {
            os_log(MMRuntimeLog(), "%{public}@ skipped one turn after an overrun", key);
            return;
        }
        MMJob *job = [MMJob new];
        job.name = name; job.expert = expert; job.budget = budget; job.started = NSDate.date;
        MMBreadcrumbEnter(expert, name);
        work(job);
        MMBreadcrumbLeave(expert, name);
        NSTimeInterval took = -job.started.timeIntervalSinceNow;
        if (took > budget) {
            os_log(MMRuntimeLog(), "%{public}@ overran its budget: %.3f s of %.3f s", key, took, budget);
            os_unfair_lock_lock(&gJobLock);
            [gOverran addObject:key];
            os_unfair_lock_unlock(&gJobLock);
        }
    });
}

- (BOOL)pastDeadline { return -self.started.timeIntervalSinceNow > self.budget; }

- (void)watchTask:(NSTask *)task {
    NSTimeInterval left = MAX(0, self.budget + self.started.timeIntervalSinceNow);
    NSString *key = [NSString stringWithFormat:@"%@.%@", self.expert, self.name];
    __weak NSTask *weak = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(left * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *t = weak;
        if (!t.isRunning) return;   // it exited, or was never launched: nothing to watch
        os_log(MMRuntimeLog(), "%{public}@ ended pid %d at its deadline", key, t.processIdentifier);
        [t terminate];
    });
}

@end

#pragma mark - P5 breadcrumbs

// Each process writes <support>/running/<pid>-<start>. Its lines name the jobs inside their work block,
// newest last. A clean exit removes the file. A file whose process no longer runs is a crash left over.
static os_unfair_lock gCrumbLock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray<NSString *> *gCrumbs;
static int gCrumbFd = -1;
static char gCrumbPath[1024];
static NSString *gLeftOver;

static void CrumbRemove(void) { if (gCrumbPath[0]) unlink(gCrumbPath); }

static NSString *CrumbDir(void) {
    NSString *d = [MMRuntimeSupportDir() stringByAppendingPathComponent:@"running"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static uint64_t StartOfSelf(void) {
    struct kinfo_proc k; size_t len = sizeof k;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    return sysctl(mib, 4, &k, &len, NULL, 0) == 0 && len == sizeof k ? (uint64_t)k.kp_proc.p_starttime.tv_sec : 0;
}

/// Reads what earlier processes left behind, once, before this process writes its own file.
static void CrumbSetUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = CrumbDir();
        NSDate *newest = nil;
        for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]) {
            NSArray *parts = [n componentsSeparatedByString:@"-"];
            if (parts.count != 2) continue;
            MMProcKey k = { [parts[0] intValue], (uint64_t)[parts[1] longLongValue] };
            if (MMProcAlive(k)) continue;   // another MinMacs or CLI that still runs
            NSString *p = [dir stringByAppendingPathComponent:n];
            NSString *body = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
            NSString *last = [[body stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]
                              componentsSeparatedByString:@"\n"].lastObject;
            NSDate *at = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil].fileModificationDate;
            if (last.length && (!newest || [at compare:newest] == NSOrderedDescending)) { newest = at; gLeftOver = last; }
            [NSFileManager.defaultManager removeItemAtPath:p error:nil];
        }
        NSString *mine = [dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%d-%llu", getpid(), StartOfSelf()]];
        strlcpy(gCrumbPath, mine.fileSystemRepresentation, sizeof gCrumbPath);
        gCrumbFd = open(gCrumbPath, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
        gCrumbs = [NSMutableArray new];
        atexit(CrumbRemove);
    });
}

/// Rewrites this process's file in place: one pwrite and one ftruncate, no rename.
static void CrumbWrite(void) {
    if (gCrumbFd < 0) return;
    NSString *body = gCrumbs.count ? [[gCrumbs componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] : @"";
    NSData *d = [body dataUsingEncoding:NSUTF8StringEncoding];
    if (pwrite(gCrumbFd, d.bytes, d.length, 0) < 0) return;
    ftruncate(gCrumbFd, (off_t)d.length);
}

void MMBreadcrumbEnter(NSString *expert, NSString *job) {
    CrumbSetUp();
    os_unfair_lock_lock(&gCrumbLock);
    [gCrumbs addObject:[NSString stringWithFormat:@"%@.%@", expert, job]];
    CrumbWrite();
    os_unfair_lock_unlock(&gCrumbLock);
}

void MMBreadcrumbLeave(NSString *expert, NSString *job) {
    CrumbSetUp();
    NSString *line = [NSString stringWithFormat:@"%@.%@", expert, job];
    os_unfair_lock_lock(&gCrumbLock);
    for (NSInteger i = (NSInteger)gCrumbs.count - 1; i >= 0; i--) {
        if (![gCrumbs[i] isEqualToString:line]) continue;
        [gCrumbs removeObjectAtIndex:i];
        CrumbWrite();
        break;
    }
    os_unfair_lock_unlock(&gCrumbLock);
}

NSString *MMBreadcrumbLeftOver(void) {
    CrumbSetUp();
    return gLeftOver;
}
