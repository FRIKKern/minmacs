// The test tool for Core Senses and Runtime, issue #14. test/senses.sh builds it with -DMM_TESTS
// against Sources/Core/Runtime and Sources/Core/Senses, and runs one mode per check.
// It acts only on the fixture pids, ports and folders it is given, and on the worker child it starts.
#import <Cocoa/Cocoa.h>
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#import "Core/Senses/MMSenses.h"
#import "Core/Senses/MMFolders.h"
#import "Core/Know/MMSizer.h"
#include <sys/resource.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <arpa/inet.h>
#include <signal.h>
#include <unistd.h>

#pragma mark - A fake Sizer, so the worker child has something to call

@implementation MMSizer
+ (MMSize)quick:(NSString *)root {
    if ([root.lastPathComponent isEqualToString:@"slow"]) sleep(3);
    return (MMSize){ .allocated = 1000 + root.length, .freedIfDeleted = 7, .files = 3, .errors = 0 };
}
+ (uint64_t)exact:(NSArray<NSString *> *)roots { return 42 * roots.count; }
+ (int64_t)freedOnVolume:(NSString *)path by:(BOOL (^)(void))action { return 0; }
@end

#pragma mark - A fake power source

@interface MMFakePower : NSObject <MMPowerSource>
@property (copy) NSDictionary *facts;
@property (copy) NSString *readLabel;
@property BOOL readOnMain;
@end
@implementation MMFakePower
- (MMPower *)read {
    self.readLabel = @(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL));
    self.readOnMain = NSThread.isMainThread;
    return MMPowerFrom(self.facts);
}
@end

#pragma mark - Helpers

static void Out(NSDictionary *d) {
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding].UTF8String);
}

/// Runs the main run loop until done says YES or secs pass. Returns done's last answer.
static BOOL Spin(double secs, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:secs];
    while (!done() && end.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    return done();
}

static double CPUSeconds(void) {
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    return ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6 + ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6;
}

static NSString *Addr(const MMSocket *s, BOOL local) {
    char buf[64];
    inet_ntop(s->family, local ? s->localAddr : s->remoteAddr, buf, sizeof buf);
    return @(buf);
}

static double Quantile(NSArray<NSNumber *> *xs, double q) {
    NSArray *s = [xs sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger i = (NSUInteger)MIN(s.count - 1, (NSUInteger)ceil(q * s.count) - (q > 0 ? 1 : 0));
    return [s[i] doubleValue];
}

#pragma mark - Modes

static int Labels(void) {
    dispatch_queue_t a = MMQueue(@"core", @"senses", QOS_CLASS_UTILITY), b = MMQueue(@"core", @"senses", QOS_CLASS_UTILITY);
    dispatch_queue_t c = MMQueue(@"locohost", @"where", QOS_CLASS_UTILITY);
    __block NSString *inside = nil;
    dispatch_sync(c, ^{ inside = @(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)); });
    __block BOOL pool = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __weak __block id weakObj = nil;
    // The object's only owner is the autorelease pool, so it dies when the block's pool drains and not before.
    dispatch_async(c, ^{ __autoreleasing id o = [NSObject new]; weakObj = o; });
    dispatch_async(c, ^{ pool = weakObj == nil; dispatch_semaphore_signal(sem); });
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    Out(@{@"senses": @(dispatch_queue_get_label(a)), @"same": @(a == b), @"where": inside, @"poolDrained": @(pool)});
    return 0;
}

static int Sample(pid_t pid, int port, pid_t kid) {
    MMSenses *s = MMSenses.shared;
    [s sampleNow];
    MMSample *x = [s sampleNow];
    MMProc *p = [x proc:pid];
    NSMutableArray *listen = [NSMutableArray new]; NSInteger est = 0, estOnPort = 0;
    for (NSValue *v in [x socketsOf:pid]) {
        MMSocket k; [v getValue:&k size:sizeof k];
        if (k.state == MMSocketListen) [listen addObject:[NSString stringWithFormat:@"%@:%u", Addr(&k, YES), k.localPort]];
        else { est++; if (k.localPort == port || k.remotePort == port) estOnPort++; }
    }
    NSUInteger total = 0; [x sockets:&total];
    NSArray *tree = [x treeOf:p.ppid limit:500];
    NSArray *up = [x ancestorsOf:pid limit:20];
    MMProc *launchd = [x proc:1];
    NSValue *keyv = nil;
    MMProcKey key = p.key;
    keyv = [NSValue valueWithBytes:&key objCType:@encode(MMProcKey)];
    MMProcKey stale = { pid, p.startSec + 1 };
    Out(@{@"found": @(p != nil), @"name": p.name ?: @"", @"ppid": @(p.ppid), @"uidIsMine": @(p.uid == getuid()),
          @"alive": @(MMProcAlive(key)), @"staleAlive": @(MMProcAlive(stale)), @"keyString": MMProcKeyString(key),
          @"startSec": @(p.startSec), @"args": [x argsOf:pid], @"cwd": [x cwdOf:pid] ?: @"",
          @"listen": listen, @"established": @(est), @"establishedOnPort": @(estOnPort), @"sockets": @(total),
          @"inParentTree": @([tree containsObject:@(pid)]), @"childrenOfParent": @([x childrenOf:p.ppid].count),
          @"lastAncestor": up.lastObject ?: @0, @"launchdCPU": @(launchd.cpuPercent), @"launchdFootprint": @(launchd.footprint),
          @"procs": @(x.procs.count), @"generation": @(x.generation), @"treeFootprint": @([x treeFootprint:p.ppid] >= p.footprint),
          @"cpuSane": @(p.cpuPercent >= 0 && p.cpuPercent < 2000), @"rankSane": @(p.energyRank >= 0 && p.energyRank <= 1),
          @"responsible": @(MMResponsiblePid(pid) > 0), @"key": keyv ? @"ok" : @"none",
          @"latestIsSample": @(s.latest == x), @"kidInTree": @([[x treeOf:pid limit:500] containsObject:@(kid)]),
          @"kidIsChild": @([[x childrenOf:pid] containsObject:@(kid)]), @"kidParent": @([[x ancestorsOf:kid limit:20].firstObject intValue] == pid)});
    return 0;
}

static uint64_t Footprint(void) {
    struct rusage_info_v6 ru;
    return proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *)&ru) == 0 ? ru.ri_phys_footprint : 0;
}

static int Bench(int n) {
    MMSenses *s = MMSenses.shared;
    [s sampleNow];   // the first pass warms caches and has no CPU deltas
    NSMutableArray *cpu = [NSMutableArray new], *wall = [NSMutableArray new];
    NSUInteger pids = 0, socks = 0, children = 0;
    uint64_t footAfterWarm = 0;
    for (int i = 0; i < n; i++) {
        if (i == 10) footAfterWarm = Footprint();
        double c0 = CPUSeconds(); NSDate *t0 = NSDate.date;
        MMSample *x = [s sampleNow];
        [wall addObject:@(-t0.timeIntervalSinceNow * 1000)];
        [cpu addObject:@((CPUSeconds() - c0) * 1000)];
        pids = x.procs.count; [x sockets:&socks];
        children = [x childrenOf:getpid()].count;
        usleep(20000);
    }
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    Out(@{@"passes": @(n), @"pids": @(pids), @"sockets": @(socks), @"children": @(children),
          @"cpuMedianMs": @(Quantile(cpu, 0.5)), @"cpuP95Ms": @(Quantile(cpu, 0.95)),
          @"wallMedianMs": @(Quantile(wall, 0.5)), @"wallP95Ms": @(Quantile(wall, 0.95)),
          @"maxResidentMB": @(ru.ru_maxrss / 1048576.0),
          @"footprintGrowthKB": @(((double)Footprint() - (double)footAfterWarm) / 1024.0)});
    return 0;
}

static int Exits(pid_t pid) {
    MMSenses *s = MMSenses.shared;
    MMProc *p = [[s sampleNow] proc:pid];
    if (!p) { Out(@{@"error": @"no such pid"}); return 1; }
    __block NSMutableArray *got = [NSMutableArray new];
    __block BOOL onMain = YES;
    [s observe:MMSignalExit block:^(MMSignal changed, id detail) {
        MMProcKey k; [(NSValue *)detail getValue:&k size:sizeof k];
        onMain = onMain && NSThread.isMainThread;
        [got addObject:MMProcKeyString(k)];
    }];
    MMProcKey live = p.key, gone = { pid, p.startSec - 1 };   // a key for an earlier process with this pid
    NSDate *t0 = NSDate.date;
    [s watchExits:@[[NSValue valueWithBytes:&gone objCType:@encode(MMProcKey)]]];
    BOOL goneAtOnce = Spin(1, ^BOOL { return got.count >= 1; });
    double goneMs = -t0.timeIntervalSinceNow * 1000;
    [s watchExits:@[[NSValue valueWithBytes:&live objCType:@encode(MMProcKey)]]];
    BOOL liveFired = Spin(10, ^BOOL { return got.count >= 2; });
    BOOL deadNow = !MMProcAlive(live);
    Out(@{@"goneAtOnce": @(goneAtOnce), @"goneMs": @((int)goneMs), @"liveFired": @(liveFired), @"deadWhenFired": @(deadNow),
          @"keys": got, @"want": @[MMProcKeyString(gone), MMProcKeyString(live)], @"onMain": @(onMain)});
    return 0;
}

static int Apps(void) {
    MMSenses *s = MMSenses.shared;
    __block id detail = nil; __block MMSignal bits = 0; __block BOOL onMain = NO;
    __block NSInteger sleeps = 0;
    [s observe:MMSignalApp block:^(MMSignal changed, id d) { bits |= changed; detail = d; onMain = NSThread.isMainThread; }];
    [s observe:MMSignalSleep block:^(MMSignal changed, id d) { sleeps++; }];
    [s start];
    // Posting on the workspace centre itself checks the observer without launching or quitting any app.
    NSRunningApplication *me = NSRunningApplication.currentApplication;
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter;
    [ws postNotificationName:NSWorkspaceDidLaunchApplicationNotification object:NSWorkspace.sharedWorkspace
                    userInfo:@{NSWorkspaceApplicationKey: me}];
    BOOL fired = Spin(2, ^BOOL { return detail != nil; });
    [ws postNotificationName:NSWorkspaceDidWakeNotification object:NSWorkspace.sharedWorkspace userInfo:nil];
    Spin(2, ^BOOL { return sleeps > 0; });
    Out(@{@"fired": @(fired), @"bits": @(bits), @"detailIsApp": @(detail == me),
          @"onMain": @(onMain), @"sleepFired": @(sleeps)});
    return 0;
}

static int Power(void) {
    MMSenses *s = MMSenses.shared;
    [s sampleNow];
    MMPower *p = s.power;
    Out(@{@"battery": @(p.batteryPercent), @"pressure": @(p.memoryPressure), @"thermal": @(p.thermal),
          @"diskFreeGB": @(p.diskFree >> 30), @"assertionPids": @(p.assertionsByPid.count),
          @"onAC": @(p.onAC), @"lidClosed": @(p.lidClosed), @"lidOverride": @(p.lidOverride), @"lowPower": @(p.lowPowerMode),
          @"fresh": @(-p.at.timeIntervalSinceNow < 5)});
    return 0;
}

static int FakePower(void) {
    MMFakePower *fake = [MMFakePower new];
    fake.facts = @{@"onAC": @YES, @"batteryPercent": @80, @"thermal": @0, @"memoryPressure": @1, @"diskFree": @(100ull << 30)};
    MMUsePowerSource(fake);
    MMSenses *s = MMSenses.shared;
    __block MMSignal bits = 0; __block NSInteger samples = 0;
    [s observe:MMSignalMemory | MMSignalDisk | MMSignalThermal | MMSignalPower | MMSignalLid block:^(MMSignal c, id d) { bits |= c; }];
    [s observe:MMSignalSample block:^(MMSignal c, id d) { samples++; }];
    [s start];
    Spin(3, ^BOOL { return samples >= 1; });
    NSString *label = fake.readLabel; BOOL onMain = fake.readOnMain;
    MMSignal before = bits;
    fake.facts = @{@"onAC": @NO, @"batteryPercent": @15, @"thermal": @2, @"memoryPressure": @4,
                   @"lidClosed": @YES, @"diskFree": @(3ull << 30)};
    [s sampleNow];
    Spin(2, ^BOOL { return bits != 0; });
    MMPower *p = s.power;
    MMUsePowerSource(nil);
    [s sampleNow];
    Out(@{@"bitsBeforeChange": @(before), @"bits": @(bits), @"battery": @(p.batteryPercent), @"onAC": @(p.onAC),
          @"lidClosed": @(p.lidClosed), @"readLabel": label ?: @"", @"readOnMain": @(onMain), @"samples": @(samples),
          @"realAgain": @(s.power.diskFree != (3ull << 30))});
    return 0;
}

static int Job(void) {
    dispatch_queue_t q = MMQueue(@"test", @"job", QOS_CLASS_UTILITY);
    __block int ran = 0;
    NSMutableArray *turns = [NSMutableArray new];   // "budget:past at start:past at end" for each turn that ran
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    void (^slow)(MMJob *) = ^(MMJob *j) {
        ran++;
        BOOL atStart = j.pastDeadline;
        usleep(150000);
        [turns addObject:[NSString stringWithFormat:@"%g:%d:%d", j.budget, atStart, j.pastDeadline]];
    };
    [MMJob run:@"slow" expert:@"test" on:q budget:0.05 work:slow];   // runs and overruns
    [MMJob run:@"slow" expert:@"test" on:q budget:0.05 work:slow];   // skipped
    [MMJob run:@"slow" expert:@"test" on:q budget:1 work:slow];      // runs again
    dispatch_async(q, ^{ dispatch_semaphore_signal(sem); });
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    int ranSlow = ran;

    // A subprocess past its deadline gets -terminate.
    __block NSTask *t = nil; __block NSDate *t0 = nil;
    [MMJob run:@"child" expert:@"test" on:q budget:0.3 work:^(MMJob *j) {
        t = [NSTask new];
        t.executableURL = [NSURL fileURLWithPath:@"/bin/sleep"]; t.arguments = @[@"30"];
        [t launchAndReturnError:nil];
        t0 = NSDate.date;
        [j watchTask:t];
    }];
    dispatch_sync(q, ^{});
    pid_t child = t.processIdentifier;
    [t waitUntilExit];
    double took = -t0.timeIntervalSinceNow;

    // A job that launches a task and keeps no reference to it. The deadline must still end it.
    __block MMProcKey dropped = {0, 0};
    [MMJob run:@"dropped" expert:@"test" on:q budget:0.3 work:^(MMJob *j) {
        NSTask *d = [NSTask new];
        d.executableURL = [NSURL fileURLWithPath:@"/bin/sleep"]; d.arguments = @[@"30"];
        if (![d launchAndReturnError:nil]) return;
        MMProc *p = [[MMSenses.shared sampleNow] proc:d.processIdentifier];
        dropped = p ? p.key : (MMProcKey){ d.processIdentifier, 0 };
        [j watchTask:d];
    }];
    dispatch_sync(q, ^{});
    BOOL droppedAlive = dropped.startSec && MMProcAlive(dropped);
    usleep(1000000);
    BOOL droppedEnded = dropped.startSec && !MMProcAlive(dropped);
    if (dropped.startSec && MMProcAlive(dropped)) kill(dropped.pid, SIGTERM);   // the sleep this probe started
    Out(@{@"ranSlow": @(ranSlow), @"turns": turns,
          @"childReason": @(t.terminationReason), @"childStatus": @(t.terminationStatus), @"childPid": @(child),
          @"childEndedSoon": @(took > 0.2 && took < 3),
          @"droppedRanFirst": @(droppedAlive), @"droppedEnded": @(droppedEnded)});
    return 0;
}

static int Crumbs(NSString *what) {
    if ([what isEqualToString:@"crash"]) {
        MMBreadcrumbEnter(@"test", @"outer");
        MMBreadcrumbEnter(@"test", @"crashy");
        _exit(3);   // dies inside the job without Leave or atexit, as a crash would
    }
    if ([what isEqualToString:@"clean"]) {
        MMBreadcrumbEnter(@"test", @"tidy");
        MMBreadcrumbLeave(@"test", @"tidy");
        return 0;
    }
    NSString *left = MMBreadcrumbLeftOver();
    NSUInteger files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:
        [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"running"] error:nil].count;
    Out(@{@"leftOver": left ?: @"nil", @"filesNow": @(files), @"again": MMBreadcrumbLeftOver() ?: @"nil"});
    return 0;
}

static int Folders(NSString *dir) {
    char real[PATH_MAX];
    if (realpath(dir.fileSystemRepresentation, real)) dir = @(real);   // FSEvents reports real paths, /private included
    NSMutableArray *batches = [NSMutableArray new];
    __block NSString *label = nil;
    void (^changed)(NSSet *, BOOL) = ^(NSSet *dirs, BOOL rescan) {
        label = @(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL));
        @synchronized (batches) { [batches addObject:dirs.allObjects]; }
    };
    NSArray *skip = @[@"node_modules", @".git/objects"];
    MMFolderWatch *w = [MMFolderWatch watch:@[dir] name:@"fixture" skip:skip changed:changed];
    NSString *idFile = [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"fixture.eventid"];
    BOOL savedAtStart = [NSFileManager.defaultManager fileExistsAtPath:idFile];
    usleep(300000);
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"node_modules/pkg"] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:[dir stringByAppendingPathComponent:@"node_modules/pkg/index.js"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"src"] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:[dir stringByAppendingPathComponent:@"src/a.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    NSString *src = [dir stringByAppendingPathComponent:@"src"];
    BOOL live = Spin(5, ^BOOL { @synchronized (batches) { for (NSArray *b in batches) if ([b containsObject:src]) return YES; } return NO; });
    Spin(1, ^BOOL { return NO; });   // let any node_modules event arrive, so the check below means something
    BOOL sawSkipped = NO;
    @synchronized (batches) { for (NSArray *b in batches) for (NSString *p in b) if ([p containsString:@"node_modules"]) sawSkipped = YES; }
    [w stop];
    uint64_t saved = strtoull([NSString stringWithContentsOfFile:idFile encoding:NSUTF8StringEncoding error:nil].UTF8String ?: "0", NULL, 10);

    // While no watch runs, a change lands. The next watch replays it from the saved id.
    NSString *later = [dir stringByAppendingPathComponent:@"later"];
    [fm createDirectoryAtPath:later withIntermediateDirectories:YES attributes:nil error:nil];
    [@"y" writeToFile:[later stringByAppendingPathComponent:@"b.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    usleep(500000);
    @synchronized (batches) { [batches removeAllObjects]; }
    MMFolderWatch *w2 = [MMFolderWatch watch:@[dir] name:@"fixture" skip:skip changed:changed];
    BOOL replayed = Spin(10, ^BOOL { @synchronized (batches) { for (NSArray *b in batches) if ([b containsObject:later]) return YES; } return NO; });
    BOOL replayedOld = NO;
    @synchronized (batches) { for (NSArray *b in batches) if ([b containsObject:src]) replayedOld = YES; }
    [w2 stop];
    Out(@{@"savedAtStart": @(savedAtStart), @"live": @(live), @"sawSkipped": @(sawSkipped), @"savedId": @(saved > 0),
          @"replayed": @(replayed), @"replayedBeforeSavedId": @(replayedOld), @"label": label ?: @""});
    return 0;
}

static int Worker(NSString *root) {
    id<MMWorker> w = MMSharedWorker();
    __block NSArray *trees = nil; __block NSError *err1 = nil; __block BOOL replyOnMain = YES;
    [w findWorktrees:@[root] skip:@[@"node_modules"] reply:^(NSArray *t, NSError *e) {
        trees = t ?: @[]; err1 = e; replyOnMain = NSThread.isMainThread;
    }];
    Spin(10, ^BOOL { return trees != nil; });
    NSMutableArray *rows = [NSMutableArray new];
    for (NSDictionary *t in trees)
        [rows addObject:[NSString stringWithFormat:@"%@|%@|%@|%@", [t[@"path"] lastPathComponent],
                         [t[@"repo"] lastPathComponent], t[@"branch"] ?: @"-", [t[@"locked"] boolValue] ? @"locked" : @"open"]];
    [rows sortUsingSelector:@selector(compare:)];

    __block NSDictionary *sizes = nil; __block uint64_t freed = 0; __block BOOL exactDone = NO;
    [w sizeTrees:@[@"/a", @"/bb"] reply:^(NSDictionary *s, NSError *e) { sizes = s ?: @{}; }];
    [w exactSize:@[@"/a", @"/bb"] reply:^(uint64_t f, NSError *e) { freed = f; exactDone = YES; }];
    Spin(10, ^BOOL { return sizes != nil && exactDone; });

    // The child is ours: find it in a sample and end it while a slow request is in flight.
    MMSample *x = [MMSenses.shared sampleNow];
    pid_t kid = 0;
    for (NSNumber *c in [x childrenOf:getpid()]) if ([[x argsOf:c.intValue] containsObject:@"_walk"]) kid = c.intValue;
    __block NSError *inflight = nil; __block BOOL inflightDone = NO;
    [w sizeTrees:@[@"/x/slow"] reply:^(NSDictionary *s, NSError *e) { inflight = e; inflightDone = YES; }];
    usleep(300000);
    if (kid > 0) kill(kid, SIGTERM);
    Spin(5, ^BOOL { return inflightDone; });
    __block NSArray *again = nil;
    [w findWorktrees:@[root] skip:@[@"node_modules"] reply:^(NSArray *t, NSError *e) { again = t ?: @[]; }];
    Spin(10, ^BOOL { return again != nil; });
    pid_t kid2 = 0;
    x = [MMSenses.shared sampleNow];
    for (NSNumber *c in [x childrenOf:getpid()]) if ([[x argsOf:c.intValue] containsObject:@"_walk"]) kid2 = c.intValue;
    Out(@{@"rows": rows, @"error": err1.localizedDescription ?: @"", @"replyOnMain": @(replyOnMain),
          @"sizeA": sizes[@"/a"][@"allocated"] ?: @0, @"freedA": sizes[@"/a"][@"freedIfDeleted"] ?: @0, @"exact": @(freed),
          @"childFound": @(kid > 0), @"inflightFailed": @(inflight != nil), @"restarted": @(again.count == trees.count && kid2 > 0 && kid2 != kid)});
    return 0;
}

/// The pid of our own worker child in a fresh sample, or 0.
static pid_t WorkerKid(void) {
    MMSample *x = [MMSenses.shared sampleNow];
    for (NSNumber *c in [x childrenOf:getpid()]) if ([[x argsOf:c.intValue] containsObject:@"_walk"]) return c.intValue;
    return 0;
}

/// Sends each request just as the idle close ends the child, run with MM_WORKER_IDLE set low.
/// The stdin of the old child is closed, but its exit has not reached the worker's queue yet.
/// Every request must get a reply or an error, and the worker must keep answering after it.
static int WorkerRace(int rounds) {
    id<MMWorker> w = MMSharedWorker();
    double idle = [NSProcessInfo.processInfo.environment[@"MM_WORKER_IDLE"] doubleValue];
    __block NSInteger answered = 0, errors = 0;
    NSInteger sent = 0;
    NSMutableSet *kids = [NSMutableSet new];
    for (int i = 0; i < rounds; i++) {
        __block BOOL done = NO;
        __block NSDate *repliedAt = nil;
        sent++;
        [w exactSize:@[@"/a"] reply:^(uint64_t f, NSError *e) {
            NSDate *at = NSDate.date;   // the idle timer starts right after this reply, on the worker queue
            dispatch_async(dispatch_get_main_queue(), ^{ answered++; if (e) errors++; repliedAt = at; done = YES; });
        }];
        if (!Spin(5, ^BOOL { return done; })) break;   // a request that never answers ends the run
        pid_t kid = WorkerKid();
        if (kid > 0) [kids addObject:@(kid)];
        // Aim at the moment the idle close lands. dispatch_after may fire up to 10 percent late, so spread the aim.
        double wait = idle * (0.98 + arc4random_uniform(150) / 1000.0) + repliedAt.timeIntervalSinceNow;
        if (wait > 0) usleep((useconds_t)(wait * 1e6));
    }
    Out(@{@"rounds": @(rounds), @"sent": @(sent), @"answered": @(answered), @"errors": @(errors),
          @"children": @(kids.count)});
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: probe <mode> [args]\n"); return 2; }
        NSString *mode = @(argv[1]);
        if ([mode isEqualToString:@"_walk"]) return MMWorkerChildMain();
        if ([mode isEqualToString:@"labels"]) return Labels();
        if ([mode isEqualToString:@"sample"] && argc > 4) return Sample(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
        if ([mode isEqualToString:@"bench"]) return Bench(argc > 2 ? atoi(argv[2]) : 60);
        if ([mode isEqualToString:@"exits"] && argc > 2) return Exits(atoi(argv[2]));
        if ([mode isEqualToString:@"apps"]) return Apps();
        if ([mode isEqualToString:@"power"]) return Power();
        if ([mode isEqualToString:@"fakepower"]) return FakePower();
        if ([mode isEqualToString:@"job"]) return Job();
        if ([mode isEqualToString:@"crumbs"] && argc > 2) return Crumbs(@(argv[2]));
        if ([mode isEqualToString:@"folders"] && argc > 2) return Folders(@(argv[2]));
        if ([mode isEqualToString:@"worker"] && argc > 2) return Worker(@(argv[2]));
        if ([mode isEqualToString:@"workerrace"]) return WorkerRace(argc > 2 ? atoi(argv[2]) : 20);
        fprintf(stderr, "probe: unknown mode %s\n", argv[1]);
        return 2;
    }
}
