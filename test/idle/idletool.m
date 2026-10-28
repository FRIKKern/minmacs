// Checks for the idle cost of the 5-second tick, issue #52. Built by test/idle.sh against Sources/Core with
// -DMM_TESTS. Each command prints one JSON object. It reads only fixtures the shell started inside MINMACS_HOME,
// and the process table, which Senses reads for every pass anyway. It signals only the child it starts itself.
//
//   carry <pid> <port>  a pass, a second pass, then a connection to the fixture's port and a third pass
//   exec <pid> <go>     the fixture's args before and after it execs, once the file go exists
//   without             a child of this tool ends, and the last sample without it, made with no pass
//   pace                the pass interval for each power and away state
//   cadence             the timer's gaps at the base interval, then on battery
//   graph               the facts digest and the findings an expert hands back when its inputs did not change
//   sessions <dir>      the FSEvents watch over Claude Code's folders in dir, set by CLAUDE_CONFIG_DIR
//   apps                the app list and the owning app, kept between calls
//   stamp               the log's stamp before and after a write
#import <Foundation/Foundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import "Core/MMCore.h"

/// Keys that hold counts. Every other 0 or 1 is a yes or no, printed as JSON true or false.
static NSSet *Counts(void) {
    return [NSSet setWithArray:@[@"argsCarried", @"socketsCarried", @"establishedAfter", @"passes", @"unwatchedReads",
                                 @"otherNotes", @"reusedFindings", @"apps"]];
}

static void Print(NSDictionary *in) {
    NSMutableDictionary *d = [in mutableCopy];
    for (NSString *k in in) {
        NSNumber *v = in[k];
        if (![v isKindOfClass:NSNumber.class] || [Counts() containsObject:k] || strcmp(v.objCType, @YES.objCType) == 0) continue;
        if (v.doubleValue == 0 || v.doubleValue == 1) d[k] = v.boolValue ? @YES : @NO;
    }
    NSData *j = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
    fwrite(j.bytes, 1, j.length, stdout);
    fputc('\n', stdout);
}

static NSUInteger EstablishedOn(MMSample *s, pid_t pid, uint16_t port) {
    NSUInteger n = 0;
    for (NSValue *v in [s socketsOf:pid]) {
        MMSocket k; [v getValue:&k size:sizeof k];
        if (k.state == MMSocketEstablished && k.localPort == port) n++;
    }
    return n;
}

static BOOL Listens(MMSample *s, pid_t pid, uint16_t port) {
    for (NSValue *v in [s socketsOf:pid]) {
        MMSocket k; [v getValue:&k size:sizeof k];
        if (k.state == MMSocketListen && k.localPort == port) return YES;
    }
    return NO;
}

#pragma mark - Senses

static int Carry(pid_t pid, uint16_t port) {
    MMSenses *senses = MMSenses.shared;
    MMSample *a = [senses sampleNow];
    NSArray *argsA = [a argsOf:pid];
    NSString *cwdA = [a cwdOf:pid];
    usleep(300000);
    MMSensesCounts c0 = senses.counts;
    MMSample *b = [senses sampleNow];
    MMSensesCounts c1 = senses.counts;
    BOOL idle = [b unchanged:pid];
    BOOL listenB = Listens(b, pid, port);
    NSArray *argsB = [b argsOf:pid];
    // A connection makes the fixture accept, so it runs and its sockets are read again.
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = { .sin_len = sizeof sa, .sin_family = AF_INET, .sin_port = htons(port) };
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    BOOL connected = connect(fd, (struct sockaddr *)&sa, sizeof sa) == 0;
    usleep(400000);
    MMSample *c = [senses sampleNow];
    NSUInteger established = EstablishedOn(c, pid, port);
    close(fd);
    Print(@{@"argsSame": @([argsA isEqual:argsB] && argsA.count > 0), @"cwdSame": @([cwdA isEqual:[b cwdOf:pid]] && cwdA.length > 0),
            @"argsCarried": @(c1.argsCarried - c0.argsCarried), @"socketsCarried": @(c1.socketPidsCarried - c0.socketPidsCarried),
            @"idleSecondPass": @(idle), @"listenA": @(Listens(a, pid, port)), @"listenB": @(listenB),
            @"connected": @(connected), @"establishedAfter": @(established), @"ranAfter": @(![c unchanged:pid]),
            @"passes": @(c1.passes - c0.passes), @"partsSum": @(c1.tableNs + c1.procsNs + c1.socketsNs + c1.carryNs + c1.powerNs <= c1.cpuNs + 1000)});
    return 0;
}

static int Exec(pid_t pid, NSString *go) {
    MMSenses *senses = MMSenses.shared;
    MMSample *a = [senses sampleNow];
    NSArray *before = [a argsOf:pid];
    NSString *nameBefore = [a proc:pid].name ?: @"";
    [@"go" writeToFile:go atomically:YES encoding:NSUTF8StringEncoding error:nil];
    MMSample *b = nil;
    for (int i = 0; i < 50; i++) {
        usleep(100000);
        b = [senses sampleNow];
        if (![[b proc:pid].name isEqualToString:nameBefore]) break;
    }
    Print(@{@"before": before, @"after": [b argsOf:pid], @"nameBefore": nameBefore, @"nameAfter": [b proc:pid].name ?: @""});
    return 0;
}

static int Without(void) {
    MMSenses *senses = MMSenses.shared;
    pid_t kid = 0;
    char *argv[] = { "/bin/sleep", "30", NULL };
    if (posix_spawn(&kid, "/bin/sleep", NULL, NULL, argv, NULL) != 0) { Print(@{@"error": @"spawn"}); return 1; }
    usleep(200000);
    MMSample *a = [senses sampleNow];
    MMProc *p = [a proc:kid];
    MMProcKey k = p.key;
    BOOL wasChild = [[a childrenOf:getpid()] containsObject:@(kid)];
    kill(kid, SIGTERM);
    waitpid(kid, NULL, 0);
    MMSensesCounts c0 = senses.counts;
    NSValue *v = [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)];
    MMSample *b = [senses sampleWithout:@[v]];
    MMSensesCounts c1 = senses.counts;
    Print(@{@"seen": @(p != nil), @"wasChild": @(wasChild), @"gone": @([b proc:kid] == nil),
            @"childGone": @(![[b childrenOf:getpid()] containsObject:@(kid)]), @"selfKept": @([b proc:getpid()] != nil),
            @"newGeneration": @(b.generation > a.generation), @"sameTime": @([b.at isEqualToDate:a.at]),
            @"latest": @(senses.latest == b), @"noPass": @(c1.passes == c0.passes),
            @"argsKept": @([[b argsOf:getpid()] isEqual:[a argsOf:getpid()]])});
    return 0;
}

#pragma mark - Pace

@interface MMIdlePower : NSObject <MMPowerSource>
@property BOOL ac;
@end
@implementation MMIdlePower
- (MMPower *)read { return MMPowerFrom(@{@"onAC": @(self.ac)}); }
@end

static int Pace(void) {
    MMSenses *senses = MMSenses.shared;
    MMIdlePower *src = [MMIdlePower new];
    MMUsePowerSource(src);
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSArray *c in @[@[@YES, @"0"], @[@NO, @"0"], @[@YES, @"400"], @[@NO, @"400"], @[@YES, @"0"]]) {
        src.ac = [c[0] boolValue];
        setenv("MINMACS_AWAY_SECONDS", [c[1] UTF8String], 1);
        [senses sampleNow];
        NSString *k = [NSString stringWithFormat:@"%@ %@", [c[0] boolValue] ? @"ac" : @"battery", c[1]];
        out[k] = [NSString stringWithFormat:@"%g %@", senses.interval, senses.intervalReason];
    }
    MMUsePowerSource(nil);
    Print(out);
    return 0;
}

/// The timer itself: gaps between passes at the base interval, then after the power source changes to battery.
static int Cadence(void) {
    MMSenses *senses = MMSenses.shared;
    MMIdlePower *src = [MMIdlePower new];
    src.ac = YES;
    MMUsePowerSource(src);
    setenv("MINMACS_AWAY_SECONDS", "0", 1);
    NSMutableArray *gaps = [NSMutableArray new];
    __block NSDate *last = nil;
    __block NSMutableArray *into = gaps;
    id token = [senses observe:MMSignalSample block:^(MMSignal changed, id detail) {
        NSDate *now = NSDate.date;
        if (last) [into addObject:@(round([now timeIntervalSinceDate:last] * 100) / 100)];
        last = now;
    }];
    [senses start];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.6]];
    NSMutableArray *slow = [NSMutableArray new];
    src.ac = NO;
    [senses sampleNow];   // the pass that reads battery power moves the timer
    into = slow; last = nil;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3.6]];
    [senses stopObserving:token];
    [senses stop];
    MMUsePowerSource(nil);
    Print(@{@"base": gaps, @"battery": slow, @"reason": senses.intervalReason ?: @""});
    return 0;
}

#pragma mark - Graph

@interface TIProc : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property uint64_t startSec;
@property (copy) NSString *name; @property double cpuPercent, energyRank; @property uint64_t footprint;
@end
@implementation TIProc
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface TISample : NSObject
@property NSDate *at; @property uint64_t generation;
@property NSDictionary<NSNumber *, TIProc *> *procs;
@end
@implementation TISample
- (TIProc *)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return nil; }
- (NSArray *)childrenOf:(pid_t)pid { return @[]; }
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops { return @[]; }
- (const MMSocket *)sockets:(NSUInteger *)count { if (count) *count = 0; return NULL; }
@end

/// An expert that counts its findingsFrom: calls. With digest set, it says its inputs are always the same.
@interface TIExpert : NSObject <MMExpert>
@property (copy) NSString *expertID;
@property BOOL digest;
@property (atomic) NSUInteger calls;
@end
@implementation TIExpert
- (NSString *)name { return self.expertID; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    self.calls++;
    return @[[MMFinding expert:self.expertID kind:@"thing" stableKey:@"one" build:^(MMFindingBuilder *b) { b.title = @"one"; }]];
}
- (BOOL)respondsToSelector:(SEL)sel {
    if (sel == @selector(inputDigestFrom:)) return self.digest;
    return [super respondsToSelector:sel];
}
- (uint64_t)inputDigestFrom:(MMFacts *)facts { return 42; }
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return nil; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return nil; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return NO; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
@end

/// Hands out facts built from the current fixture sample, with the same immutable arrays each time.
@interface TISource : NSObject <MMFactSource>
@property (strong) TISample *sample;
@end
@implementation TISource
- (MMFacts *)factsFor:(uint64_t)generation {
    return [MMFacts generation:generation sample:(MMSample *)self.sample power:nil agents:@[] sessions:@[]
                     worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

static TISample *Fixture(NSUInteger count, double cpu) {
    NSMutableDictionary *procs = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < count; i++) {
        TIProc *p = [TIProc new];
        p.pid = (pid_t)(200000 + i); p.ppid = 1; p.uid = getuid(); p.startSec = 1761000000 + i; p.name = @"fixture";
        p.cpuPercent = cpu; p.footprint = 32ull << 20;
        procs[@(p.pid)] = p;
    }
    TISample *s = [TISample new];
    s.at = NSDate.date; s.procs = procs;
    return s;
}

/// Waits on the graph queue, so every rebuild asked before it has run.
static void Settle(void) {
    for (int i = 0; i < 3; i++) dispatch_sync(MMQueue(@"core", @"graph", QOS_CLASS_UTILITY), ^{});
}

static uint64_t Cost(NSString *k) { return [MMGraph.shared.costs[k] unsignedLongLongValue]; }

static int Graph(void) {
    MMGraph *g = MMGraph.shared;
    TISource *src = [TISource new];
    TIExpert *same = [TIExpert new], *plain = [TIExpert new];
    same.expertID = @"idlesame"; same.digest = YES;
    plain.expertID = @"idleplain";
    [g addExpert:same]; [g addExpert:plain];
    src.sample = Fixture(5, 0.2);
    g.source = src;
    [g start];
    Settle();
    uint64_t gen0 = g.latest.generation, skipped0 = Cost(@"skipped");
    NSUInteger s0 = same.calls, p0 = plain.calls;
    // The same facts again: the whole build is skipped.
    [g rebuild:@"sample"]; Settle();
    uint64_t gen1 = g.latest.generation, skipped1 = Cost(@"skipped");
    NSUInteger s1 = same.calls, p1 = plain.calls;
    // CPU inside a band moves nothing either.
    src.sample = Fixture(5, 0.6);
    [g rebuild:@"sample"]; Settle();
    uint64_t gen2 = g.latest.generation;
    // One more process: a build, where the expert with the same inputs hands back its last findings.
    src.sample = Fixture(6, 0.2);
    [g rebuild:@"sample"]; Settle();
    uint64_t gen3 = g.latest.generation;
    NSUInteger s3 = same.calls, p3 = plain.calls;
    NSUInteger found = [g.latest findingsFor:@"idlesame"].count;
    // Any other reason builds, and every expert is asked.
    [g rebuild:@"idle check action"]; Settle();
    uint64_t gen4 = g.latest.generation;
    NSUInteger s4 = same.calls, p4 = plain.calls;
    // A CPU band moves: a build.
    src.sample = Fixture(6, 30);
    [g rebuild:@"sample"]; Settle();
    uint64_t gen5 = g.latest.generation;
    Print(@{@"firstBuilt": @(gen0 > 0 && s0 == 1 && p0 == 1), @"sameSkipped": @(gen1 == gen0 && skipped1 == skipped0 + 1 && s1 == s0 && p1 == p0),
            @"bandSkipped": @(gen2 == gen0), @"changeBuilt": @(gen3 == gen0 + 1), @"reused": @(s3 == s0 && p3 == p0 + 1),
            @"reusedFindings": @(found), @"forcedBuilt": @(gen4 == gen3 + 1 && s4 == s3 + 1 && p4 == p3 + 1),
            @"bandBuilt": @(gen5 == gen4 + 1), @"reusedCounted": @(Cost(@"reused.idlesame") >= 1),
            @"costsByExpert": @(MMGraph.shared.costs[@"findings.idleplain"] != nil && MMGraph.shared.costs[@"facts"] != nil)});
    return 0;
}

#pragma mark - Sessions

static BOOL WaitFor(BOOL (^done)(void), NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    return done();
}

static void Line(NSString *path, NSString *sid, NSString *cwd) {
    NSString *l = [NSString stringWithFormat:@"{\"sessionId\":\"%@\",\"cwd\":\"%@\",\"timestamp\":\"2026-10-28T00:00:00.000Z\"}\n", sid, cwd];
    NSFileHandle *f = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!f) { [l writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    [f seekToEndOfFile]; [f writeData:[l dataUsingEncoding:NSUTF8StringEncoding]]; [f closeFile];
}

static int Sessions(NSString *dir) {
    MMSessions *x = MMSessions.shared;
    NSString *p1 = [dir stringByAppendingPathComponent:@"projects/-w4idle-one"];
    [NSFileManager.defaultManager createDirectoryAtPath:p1 withIntermediateDirectories:YES attributes:nil error:nil];
    Line([p1 stringByAppendingPathComponent:@"w4idle-s1.jsonl"], @"w4idle-s1", @"/w4idle/one");
    // Without the watch every call reads.
    [x refresh]; [x refresh];
    NSUInteger unwatchedReads = x.readCount;
    __block NSUInteger notes = 0;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:MMSessionsDidChangeNotification object:x queue:nil
                                                           usingBlock:^(NSNotification *n) { notes++; }];
    [x startWatching];
    [x refresh];
    NSUInteger r0 = x.readCount, k0 = x.skipCount;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];   // let FSEvents settle
    notes = 0;
    [x refresh]; [x refresh];
    NSUInteger r1 = x.readCount, k1 = x.skipCount;
    // A new transcript in a new folder: FSEvents names it, and the next refresh reads.
    NSString *p2 = [dir stringByAppendingPathComponent:@"projects/-w4idle-two"];
    [NSFileManager.defaultManager createDirectoryAtPath:p2 withIntermediateDirectories:YES attributes:nil error:nil];
    Line([p2 stringByAppendingPathComponent:@"w4idle-s2.jsonl"], @"w4idle-s2", @"/w4idle/two");
    BOOL noted = WaitFor(^BOOL { return notes > 0; }, 8);
    [x refresh];
    BOOL found = [x withID:@"w4idle-s2"] != nil;
    NSUInteger r2 = x.readCount;
    // A line added to the first transcript moves its last activity.
    NSDate *before = [x withID:@"w4idle-s1"].lastActive;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.2]];
    notes = 0;
    Line([p1 stringByAppendingPathComponent:@"w4idle-s1.jsonl"], @"w4idle-s1", @"/w4idle/one");
    BOOL noted2 = WaitFor(^BOOL { return notes > 0; }, 8);
    [x refresh];
    NSDate *after = [x withID:@"w4idle-s1"].lastActive;
    // A change outside the session folders asks for nothing.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.2]];
    notes = 0;
    [@"x" writeToFile:[dir stringByAppendingPathComponent:@"w4idle-other.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.5]];
    NSUInteger otherNotes = notes;
    NSUInteger r3 = x.readCount;
    [x refreshAll];
    NSUInteger r4 = x.readCount;
    [x stopWatching];
    [NSNotificationCenter.defaultCenter removeObserver:token];
    Print(@{@"unwatchedReads": @(unwatchedReads), @"firstRead": @(r0 == unwatchedReads + 1),
            @"quietSkips": @(r1 == r0 && k1 == k0 + 2), @"noted": @(noted), @"newFound": @(found), @"readAfterChange": @(r2 == r1 + 1),
            @"noted2": @(noted2), @"lastActiveMoved": @(after && before && [after compare:before] == NSOrderedDescending),
            @"otherNotes": @(otherNotes), @"noReadWithoutChange": @(r3 == r2 + 1), @"refreshAllReads": @(r4 == r3 + 1)});
    return 0;
}

#pragma mark - Apps and the log

static int Apps(void) {
    NSArray *a = MMRunningApps(), *b = MMRunningApps();
    MMSample *s = [MMSenses.shared sampleNow];
    pid_t me = getpid();
    NSRunningApplication *o1 = MMOwningApp(s, me), *o2 = MMOwningApp(s, me);
    pid_t r1 = MMResponsiblePidIn(s, me), r2 = MMResponsiblePidIn(s, me);
    MMSample *t = [MMSenses.shared sampleNow];
    Print(@{@"sameList": @(a == b), @"apps": @(a.count), @"sameOwner": @(o1 == o2), @"sameResponsible": @(r1 == r2 && r1 > 0),
            @"responsibleCarried": @(MMResponsiblePidIn(t, me) == r1), @"ownerCarried": @(MMOwningApp(t, me) == o1)});
    return 0;
}

static int Stamp(void) {
    NSString *a = MMLogStamp();
    [MMLog.shared append:@"usage" rid:nil expert:@"idle" subject:@"stamp" state:@"done" body:@{}];
    NSString *b = MMLogStamp(), *c = MMLogStamp();
    Print(@{@"moved": @(![a isEqualToString:b]), @"steady": @([b isEqualToString:c])});
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? @(argv[1]) : @"";
        if ([cmd isEqualToString:@"carry"] && argc > 3) return Carry(atoi(argv[2]), (uint16_t)atoi(argv[3]));
        if ([cmd isEqualToString:@"exec"] && argc > 3) return Exec(atoi(argv[2]), @(argv[3]));
        if ([cmd isEqualToString:@"without"]) return Without();
        if ([cmd isEqualToString:@"pace"]) return Pace();
        if ([cmd isEqualToString:@"cadence"]) return Cadence();
        if ([cmd isEqualToString:@"graph"]) return Graph();
        if ([cmd isEqualToString:@"sessions"] && argc > 2) return Sessions(@(argv[2]));
        if ([cmd isEqualToString:@"apps"]) return Apps();
        if ([cmd isEqualToString:@"stamp"]) return Stamp();
        fprintf(stderr, "usage: idletool carry|exec|without|pace|cadence|graph|sessions|apps|stamp\n");
        return 2;
    }
}
