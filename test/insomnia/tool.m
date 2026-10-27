// The Insomnia expert's test tool. test/insomnia.sh builds it with all of Core, the kit, the CLI and the expert,
// under -DMM_TESTS, and runs it inside the section's MINMACS_HOME.
//   tool matrix <script>     runs a guard matrix script and prints one line per check: check<TAB>name<TAB>want<TAB>got
// Power facts come from a fake power source, so nothing here reads or changes the Mac's own power state.
// The lid override goes through the real MMLidOverride, which with MINMACS_HOME set runs only $MINMACS_INSOMNIA_CMD.
// The fake writes its state into $MINMACS_HOME/insomnia-fake, and the fake power source reads lidOverride from there.
// Workers are copies of sleep under a name unique to the run, started and stopped by this tool alone.
// Script lines, one command each:
//   power key=value ...        onAC, battery, lidClosed, online (0 or 1, or a number) and thermal (nominal ... critical)
//   pref <key> <value|delete>  a pref in the test home
//   set <what> <value>         -[MMInsomniaExpert set:value:by:] with by "cli": on, off, a number or never
//   cli <words>                one verb through its MMVerbSpec, as the app runs it
//   clock +<minutes>           moves the expert's clock
//   worker <id> start|working|idle|exit
//   proc <id> start|exit       a plain process that is no agent, for holds a script asks for
//   hold <id> <reason> | unhold <id>
//   mark                       remembers the display and write counts for display-new and writes-new
//   waitgraph                  waits up to 3 seconds for the graph to carry a hold
//   A word $<id> in a cli line becomes that process's pid.
//   fake lid 0|1 | fake rule on|off | fake fail on|off | fake other on|off
//   step                       one pass
//   wait held <n>              waits up to 3 seconds for MMAwake to hold n
//   expect <field> <want> <name...>
#import <Cocoa/Cocoa.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/Insomnia/MMInsomnia.h"
#include <spawn.h>
#include <signal.h>
#include <sys/sysctl.h>
#include <sys/wait.h>

extern char **environ;

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }
static NSString *FakeDir(void) { return [Env(@"MINMACS_HOME") stringByAppendingPathComponent:@"insomnia-fake"]; }
static NSString *FakeFile(NSString *name) { return [FakeDir() stringByAppendingPathComponent:name]; }
static BOOL Exists(NSString *name) { return [NSFileManager.defaultManager fileExistsAtPath:FakeFile(name)]; }
static NSString *Read(NSString *name) {
    return [[NSString stringWithContentsOfFile:FakeFile(name) encoding:NSUTF8StringEncoding error:nil]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}
static void Write(NSString *name, NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:FakeDir() withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:FakeFile(name) atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void Remove(NSString *name) { [NSFileManager.defaultManager removeItemAtPath:FakeFile(name) error:nil]; }
static NSUInteger LogCount(NSString *needle) {
    NSUInteger n = 0;
    for (NSString *line in [Read(@"log") componentsSeparatedByString:@"\n"]) n += [line hasSuffix:needle];
    return n;
}

/// The lid writes the fake saw, both values.
static NSUInteger Writes(void) {
    return LogCount(@"/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1") + LogCount(@"/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0");
}

#pragma mark Fakes

static NSMutableDictionary *gPower;
static BOOL gOther;
static NSDate *gBase;
static NSTimeInterval gOffset;

@interface TPower : NSObject <MMPowerSource>
@end
@implementation TPower
- (MMPower *)read {
    NSMutableDictionary *d;
    @synchronized (gPower) { d = [gPower mutableCopy]; }
    d[@"lidOverride"] = @([Read(@"lid") isEqualToString:@"1"]);
    return MMPowerFrom(d);
}
@end

@interface TSource : NSObject <MMFactSource>
@end
@implementation TSource
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    return [MMFacts generation:generation sample:s power:MMSenses.shared.power agents:@[] sessions:@[] worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

#pragma mark Workers

@interface TWorker : NSObject
@property MMProcKey key;
@property BOOL working;
@property (copy) NSString *name;
@end
@implementation TWorker
@end

static NSMutableDictionary<NSString *, TWorker *> *gWorkers, *gProcs;
static NSMutableDictionary<NSString *, NSString *> *gHolds;

static uint64_t StartOf(pid_t pid) {
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len != sizeof kp) return 0;
    return (uint64_t)kp.kp_proc.p_starttime.tv_sec;
}

static TWorker *Spawn(NSString *id) {
    NSString *sleeper = Env(@"IN_SLEEPER");
    char *argv[] = { (char *)sleeper.fileSystemRepresentation, "600", NULL };
    pid_t pid = 0;
    // The tool runs on a dispatch thread, which blocks signals. The child starts with none blocked, so SIGTERM ends it.
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    sigset_t none, all;
    sigemptyset(&none); sigfillset(&all);
    posix_spawnattr_setsigmask(&attr, &none);
    posix_spawnattr_setsigdefault(&attr, &all);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    int r = sleeper.length ? posix_spawn(&pid, argv[0], NULL, &attr, argv, environ) : -1;
    posix_spawnattr_destroy(&attr);
    if (r != 0) return nil;
    TWorker *w = [TWorker new];
    MMProcKey k = { pid, StartOf(pid) };
    w.key = k; w.name = [NSString stringWithFormat:@"Agent %@", id];
    return w;
}

static void Stop(TWorker *w) {
    if (!w || w.key.pid <= 1) return;
    kill(w.key.pid, SIGTERM);
    int st;
    for (int i = 0; i < 40 && waitpid(w.key.pid, &st, WNOHANG) == 0; i++) usleep(50000);
    if (waitpid(w.key.pid, &st, WNOHANG) == 0) { kill(w.key.pid, SIGKILL); waitpid(w.key.pid, &st, 0); }
}

/// The types of our own assertions, sorted and without repeats.
static NSString *OurTypes(void) {
    CFDictionaryRef byPid = NULL;
    NSMutableSet *types = [NSMutableSet new];
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        for (NSDictionary *a in ((__bridge NSDictionary *)byPid)[@(getpid())])
            if ([a[@"AssertName"] hasPrefix:@"MinMacs keeps the Mac awake"] && a[@"AssertType"]) [types addObject:a[@"AssertType"]];
        CFRelease(byPid);
    }
    return types.count ? [[types.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","] : @"none";
}

static NSUInteger OurAssertions(void) {
    CFDictionaryRef byPid = NULL;
    NSUInteger n = 0;
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        for (NSDictionary *a in ((__bridge NSDictionary *)byPid)[@(getpid())])
            if ([a[@"AssertName"] hasPrefix:@"MinMacs keeps the Mac awake"]) n++;
        CFRelease(byPid);
    }
    return n;
}

#pragma mark The script

static id Value(NSString *v) {
    if ([v isEqualToString:@"on"] || [v isEqualToString:@"true"]) return @YES;
    if ([v isEqualToString:@"off"] || [v isEqualToString:@"false"]) return @NO;
    if ([v isEqualToString:@"never"]) return @0;
    NSScanner *sc = [NSScanner scannerWithString:v];
    NSInteger n;
    if ([sc scanInteger:&n] && sc.isAtEnd) return @(n);
    return v;
}

static int RunScript(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) { fprintf(stderr, "tool: cannot read %s\n", path.UTF8String); return 2; }
    MMInsomniaExpert *e = MMInsomniaExpert.shared;
    MMRegisterExpert(e);
    gPower = [@{@"onAC": @YES, @"batteryPercent": @100, @"online": @YES, @"lidClosed": @NO, @"thermal": @0} mutableCopy];
    MMUsePowerSource([TPower new]);
    TSource *src = [TSource new];
    MMGraph.shared.source = src;
    gWorkers = [NSMutableDictionary new]; gProcs = [NSMutableDictionary new]; gHolds = [NSMutableDictionary new];
    NSUInteger markDisplay = 0, markWrites = 0;
    gBase = NSDate.date;
    e.clock = ^NSDate *{ return [gBase dateByAddingTimeInterval:gOffset]; };
    e.inputFrom = ^MMINInput *(MMFacts *facts) {
        MMINInput *in = [MMINInput new];
        NSMutableArray *ws = [NSMutableArray new];
        for (NSString *id in [gWorkers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            TWorker *t = gWorkers[id];
            MMINWorker *w = [MMINWorker new];
            w.kind = @"agent"; w.key = t.key; w.name = t.name; w.harness = @"fixture"; w.sessionID = id;
            w.cwd = [Env(@"MINMACS_HOME") stringByAppendingPathComponent:id]; w.working = t.working; w.why = t.working ? @"fixture works" : @"fixture idle";
            w.stableKey = [@"fixture:" stringByAppendingString:id];
            [ws addObject:w];
        }
        in.workers = ws; in.otherApp = gOther;
        return in;
    };
    MMINState *st = nil;
    NSString *lastSet = @"none", *cliOut = @"", *cliStatus = @"none";
    uint64_t gen = 0;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSArray<NSString *> *w = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        w = [w filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        NSString *cmd = w[0];
        NSMutableArray *subst = [NSMutableArray new];
        for (NSString *x in w) {
            TWorker *t = [x hasPrefix:@"$"] ? (gProcs[[x substringFromIndex:1]] ?: gWorkers[[x substringFromIndex:1]]) : nil;
            [subst addObject:t ? @(t.key.pid).stringValue : x];
        }
        w = subst;
        if ([cmd isEqualToString:@"section"]) {
            printf("section\t%s\n", [[w subarrayWithRange:NSMakeRange(1, w.count - 1)] componentsJoinedByString:@" "].UTF8String);
        } else if ([cmd isEqualToString:@"power"]) {
            NSDictionary *thermal = @{@"nominal": @0, @"fair": @1, @"serious": @2, @"critical": @3};
            NSDictionary *names = @{@"onAC": @"onAC", @"battery": @"batteryPercent", @"lidClosed": @"lidClosed", @"online": @"online", @"thermal": @"thermal"};
            @synchronized (gPower) {
                for (NSString *kv in [w subarrayWithRange:NSMakeRange(1, w.count - 1)]) {
                    NSArray *p = [kv componentsSeparatedByString:@"="];
                    if (p.count != 2 || !names[p[0]]) { fprintf(stderr, "tool: bad power %s\n", kv.UTF8String); return 2; }
                    gPower[names[p[0]]] = [p[0] isEqualToString:@"thermal"] ? thermal[p[1]] : @([p[1] integerValue]);
                }
            }
        } else if ([cmd isEqualToString:@"pref"] && w.count == 3) {
            MMSetPref(w[1], [w[2] isEqualToString:@"delete"] ? nil : Value(w[2]));
        } else if ([cmd isEqualToString:@"set"] && w.count == 3) {
            lastSet = [e set:w[1] value:Value(w[2]) by:@"cli"] ?: @"ok";
        } else if ([cmd isEqualToString:@"cli"] && w.count >= 2) {
            MMVerbSpec *spec = nil;
            for (MMVerbSpec *v in MMINVerbs()) if ([v.verb isEqualToString:w[1]]) spec = v;
            MMArgs *a = [MMArgs verb:w[1] words:[w subarrayWithRange:NSMakeRange(2, w.count - 2)] usage:spec.usage];
            a.inApp = YES; a.outBuffer = [NSMutableString new]; a.errBuffer = [NSMutableString new];
            cliStatus = @(spec ? spec.run(a) : 2).stringValue;
            cliOut = [a.outBuffer stringByAppendingString:a.errBuffer];
        } else if ([cmd isEqualToString:@"clock"] && w.count == 2) {
            gOffset += [[w[1] stringByReplacingOccurrencesOfString:@"+" withString:@""] doubleValue] * 60;
        } else if ([cmd isEqualToString:@"worker"] && w.count == 3) {
            if ([w[2] isEqualToString:@"start"]) {
                TWorker *t = Spawn(w[1]);
                if (!t) { fprintf(stderr, "tool: could not start a worker\n"); return 2; }
                t.working = YES; gWorkers[w[1]] = t;
                printf("pid\t%d\n", t.key.pid);
            } else if ([w[2] isEqualToString:@"exit"]) {
                Stop(gWorkers[w[1]]); [gWorkers removeObjectForKey:w[1]];
            } else gWorkers[w[1]].working = [w[2] isEqualToString:@"working"];
        } else if ([cmd isEqualToString:@"proc"] && w.count == 3) {
            if ([w[2] isEqualToString:@"start"]) {
                TWorker *t = Spawn(w[1]);
                if (!t) { fprintf(stderr, "tool: could not start a process\n"); return 2; }
                gProcs[w[1]] = t;
                printf("pid\t%d\n", t.key.pid);
            } else { Stop(gProcs[w[1]]); [gProcs removeObjectForKey:w[1]]; }
        } else if ([cmd isEqualToString:@"mark"]) {
            markDisplay = LogCount(@"/usr/bin/pmset displaysleepnow");
            markWrites = Writes();
        } else if ([cmd isEqualToString:@"waitgraph"]) {
            for (int i = 0; i < 60 && !MMGraph.shared.latest.awakeHolds.count; i++) usleep(50000);
        } else if ([cmd isEqualToString:@"hold"] && w.count >= 3) {
            gHolds[MMProcKeyString((gProcs[w[1]] ?: gWorkers[w[1]]).key)] = [[w subarrayWithRange:NSMakeRange(2, w.count - 2)] componentsJoinedByString:@" "];
        } else if ([cmd isEqualToString:@"unhold"] && w.count == 2) {
            [gHolds removeObjectForKey:MMProcKeyString((gProcs[w[1]] ?: gWorkers[w[1]]).key)];
        } else if ([cmd isEqualToString:@"fake"] && w.count == 3) {
            BOOL on = [w[2] isEqualToString:@"on"] || [w[2] isEqualToString:@"1"];
            if ([w[1] isEqualToString:@"lid"]) Write(@"lid", on ? @"1" : @"0");
            else if ([w[1] isEqualToString:@"other"]) gOther = on;
            else if (on) Write(w[1], @"");
            else Remove(w[1]);
        } else if ([cmd isEqualToString:@"step"]) {
            MMFacts *facts = [src factsFor:++gen];
            NSMutableDictionary *holds = [gHolds mutableCopy];
            [holds addEntriesFromDictionary:MMGraph.shared.latest.awakeHolds ?: @{}];
            MMSnapshot *snap = [MMSnapshot snapshotFrom:facts experts:@[e] reviews:nil holds:holds];
            st = [e reconcile:snap];
        } else if ([cmd isEqualToString:@"wait"] && w.count == 3) {
            for (int i = 0; i < 60 && MMAwake.held.count != (NSUInteger)w[2].integerValue; i++) usleep(50000);
        } else if ([cmd isEqualToString:@"expect"] && w.count >= 4) {
            NSString *field = w[1], *want = w[2], *got = @"?";
            NSString *name = [[w subarrayWithRange:NSMakeRange(3, w.count - 3)] componentsJoinedByString:@" "];
            st = e.state ?: st;   // a change of setting passes once too, so the newest state is the expert's
            if ([field isEqualToString:@"asserts"]) got = @(OurAssertions()).stringValue;
            else if ([field isEqualToString:@"types"]) got = OurTypes();
            else if ([field isEqualToString:@"held"]) got = @(MMAwake.held.count).stringValue;
            else if ([field isEqualToString:@"lid"]) got = [Read(@"lid") isEqualToString:@"1"] ? @"live" : @"paused";
            else if ([field isEqualToString:@"holding"]) got = st.holding ? @"yes" : @"no";
            else if ([field isEqualToString:@"holders"]) got = @(st.holders.count).stringValue;
            else if ([field isEqualToString:@"reason"]) got = st.pauseReason ? [st.pauseReason componentsSeparatedByString:@" "].firstObject : @"none";
            else if ([field isEqualToString:@"problem"]) got = st.lidProblem ? @"yes" : @"none";
            else if ([field isEqualToString:@"display"]) got = @(LogCount(@"/usr/bin/pmset displaysleepnow")).stringValue;
            else if ([field isEqualToString:@"display-new"]) got = @(LogCount(@"/usr/bin/pmset displaysleepnow") - markDisplay).stringValue;
            else if ([field isEqualToString:@"writes-new"]) got = @(Writes() - markWrites).stringValue;
            else if ([field isEqualToString:@"unplugged"]) got = st.clocks.unpluggedAt ? @"set" : @"none";
            else if ([field isEqualToString:@"offline"]) got = st.clocks.offlineAt ? @"set" : @"none";
            else if ([field isEqualToString:@"state"]) got = [MMINAccessibilityState(st) stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            else if ([field isEqualToString:@"rule"]) got = Exists(@"rule") ? @"yes" : @"no";
            else if ([field isEqualToString:@"set"]) got = [lastSet isEqualToString:@"ok"] ? @"ok" : @"refused";
            else if ([field isEqualToString:@"cli-status"]) got = cliStatus;
            else if ([field isEqualToString:@"cli-says"]) got = [cliOut containsString:[want stringByReplacingOccurrencesOfString:@"_" withString:@" "]] ? want : cliOut;
            else if ([field isEqualToString:@"lowbattery"]) got = st.lowBattery ? @"yes" : @"no";
            else if ([field isEqualToString:@"undo"] || [field isEqualToString:@"undo-matches"]) {
                NSUInteger n = 0;
                for (MMUndoRecord *r in [MMUndo.shared recent:@"insomnia" limit:500]) n += [r.kind isEqualToString:@"lid"] && r.state == MMUndoDone;
                NSUInteger done = 0;
                for (NSString *l in [Read(@"done") componentsSeparatedByString:@"\n"]) done += l.length > 0;
                got = [field isEqualToString:@"undo"] ? @(n).stringValue : n == done && n > 0 ? @"yes" : [NSString stringWithFormat:@"%lu records, %lu writes", (unsigned long)n, (unsigned long)done];
            } else if ([field hasPrefix:@"holdfor:"]) {
                NSString *id = [field substringFromIndex:8];
                TWorker *t = gWorkers[id] ?: gProcs[id];
                got = t && MMAwake.held[MMProcKeyString(t.key)] ? @"yes" : @"no";
            } else if ([field hasPrefix:@"pref:"]) {
                id v = MMPref([field substringFromIndex:5]);
                got = v ? [v description] : @"none";
            }
            printf("check\t%s\t%s\t%s\n", name.UTF8String, want.UTF8String, got.UTF8String);
        } else {
            fprintf(stderr, "tool: unknown line: %s\n", line.UTF8String);
            return 2;
        }
        fflush(stdout);
    }
    for (TWorker *t in gWorkers.allValues) Stop(t);
    for (TWorker *t in gProcs.allValues) Stop(t);
    [MMAwake releaseAll];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // The real routing table, for the check of MMPower.online against route(8). No fake power source here.
        if (argc == 2 && !strcmp(argv[1], "online")) { (void)[MMSenses.shared sampleNow]; printf("%d\n", MMSenses.shared.power.online); return 0; }
        // In a test home with no fake, every lid command refuses, on main and off it.
        if (argc == 2 && !strcmp(argv[1], "nofake")) {
            NSString *main = nil, *off = nil;
            BOOL a = [MMLidOverride set:YES error:&main];
            __block BOOL b = YES;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *e = nil; b = [MMLidOverride set:YES error:&e] || [MMLidOverride sleepDisplay] || [MMLidOverride ruleInstalled];
                printf("off main: %s\n", e.UTF8String ?: "");
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
            (void)off;
            printf("on main: %s\nran: %s\n", main.UTF8String ?: "", a || b ? "yes" : "no");
            return 0;
        }
        if (argc < 3 || strcmp(argv[1], "matrix") != 0) { fprintf(stderr, "usage: tool matrix <script> | online | nofake\n"); return 2; }
        if (!Env(@"MINMACS_HOME").length || !Env(@"MINMACS_INSOMNIA_CMD").length) { fprintf(stderr, "tool: needs MINMACS_HOME and the fake command\n"); return 2; }
        // Every pass runs off main, as in the app. MMRunAction refuses on main.
        __block int r = 0;
        NSString *path = @(argv[2]);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ r = RunScript(path); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        return r;
    }
}
