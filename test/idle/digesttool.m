// The experts' input digests and the graph's skip, issue #52. test/idle.sh builds this with every .m under Sources
// except main.m, under -DMM_TESTS, and runs it in its own folder inside $MINMACS_HOME:
//   digesttool <dir> <sleeper> <server.py>    each input the digests read, changed one at a time, as JSON
// The facts are built by hand from objects made here. The processes it starts are sleepers of its own, under a name
// unique to the run, with their cwd in the fixture's folders, and test/idle/server.py, a listener in a session of its
// own; it stops those pids and no other.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "Core/Know/MMTreeDisk.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/MinMacs/MMMinMacs.h"
#import "Experts/Insomnia/MMInsomnia.h"
#import "Experts/LocoHost/MMLocoHost.h"
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <libproc.h>

extern char **environ;

static MMWorktree *Tree(NSString *path, NSString *branch) {
    MMWorktree *w = [MMWorktree new];
    char real[PATH_MAX];
    [w setValue:path forKey:@"path"]; [w setValue:path forKey:@"repo"];
    [w setValue:(realpath(path.fileSystemRepresentation, real) ? @(real) : path) forKey:@"realPath"];
    [w setValue:@YES forKey:@"isMain"]; [w setValue:branch forKey:@"branch"];
    return w;
}
static MMGitFacts *Git(NSString *head) { MMGitFacts *g = [MMGitFacts new]; [g setValue:head forKey:@"head"]; return g; }
static MMSession *Session(NSString *cwd, pid_t pid) {
    MMSession *x = [MMSession new];
    [x setValue:@"claude-code" forKey:@"agent"]; [x setValue:@"dg-session" forKey:@"sessionID"];
    [x setValue:cwd forKey:@"cwd"]; [x setValue:@"busy" forKey:@"liveStatus"];
    if (pid > 0) [x setValue:@(pid) forKey:@"pid"];
    return x;
}
static MMClutterItem *Item(MMClutterKind *k, NSString *path) {
    MMClutterItem *i = [MMClutterItem new];
    [i setValue:k forKey:@"kind"]; [i setValue:path forKey:@"path"]; [i setValue:@[path] forKey:@"members"];
    return i;
}

/// The facts a build would hand both experts. Arrays are copied each time, as Know's may be.
@interface DGFacts : NSObject
@property MMSample *sample;
@property NSArray *trees, *sessions, *clutter;
@property NSDictionary *git;
@property uint64_t generation;
@end
@implementation DGFacts
- (MMFacts *)facts {
    return [MMFacts generation:++self.generation sample:self.sample power:nil agents:@[] sessions:[self.sessions copy]
                     worktrees:[self.trees copy] clutter:[self.clutter copy] git:[self.git copy]];
}
@end

/// A fact source for the graph check: the same facts each build, until next is set.
@interface DGSource : NSObject <MMFactSource>
@property DGFacts *f;
@end
@implementation DGSource
- (MMFacts *)factsFor:(uint64_t)generation { return [self.f facts]; }
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self.f facts]; }
@end

static pid_t Spawn(NSString *bin, NSString *cwd) {
    NSString *old = NSFileManager.defaultManager.currentDirectoryPath;
    chdir(cwd.fileSystemRepresentation);
    pid_t pid = 0;
    char *argv[] = { (char *)bin.fileSystemRepresentation, "30", NULL };
    int r = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    chdir(old.fileSystemRepresentation);
    return r == 0 ? pid : 0;
}
static void Stop(pid_t pid) { if (pid > 1) { kill(pid, SIGTERM); waitpid(pid, NULL, 0); } }
/// The sleeper as a child of a shell that exits at once, so it is no child of this tool: WorkForest leaves out
/// MinMacs's own children, such as its git commands. Returns the sleeper's pid, read from the shell.
static pid_t SpawnDetached(NSString *bin, NSString *cwd) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    t.arguments = @[@"-c", @"cd \"$1\" || exit 1; \"$2\" 30 >/dev/null 2>&1 </dev/null & echo $!", @"sh", cwd, bin];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    if (![t launchAndReturnError:nil]) return 0;
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].intValue;
}
/// Stops a detached sleeper this tool started, after checking it is still that sleeper.
static void StopDetached(pid_t pid, NSString *bin) {
    if (pid <= 1) return;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof path) > 0 && [@(path).lastPathComponent isEqualToString:bin.lastPathComponent]) kill(pid, SIGTERM);
    for (int i = 0; i < 40 && kill(pid, 0) == 0; i++) usleep(50000);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 4 || !NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) {
            fprintf(stderr, "usage: digesttool <dir> <sleeper> <server.py>, with MINMACS_HOME set\n"); return 2;
        }
        NSString *sleeper = @(argv[2]);
        NSFileManager *fm = NSFileManager.defaultManager;
        // The folder as the kernel names it, /private/var and not /var, as a process's cwd and the disk walks name it.
        [fm createDirectoryAtPath:@(argv[1]) withIntermediateDirectories:YES attributes:nil error:nil];
        char real[PATH_MAX];
        NSString *dir = realpath(argv[1], real) ? @(real) : @(argv[1]);
        NSString *repo = [dir stringByAppendingPathComponent:@"repo"], *other = [dir stringByAppendingPathComponent:@"other"];
        [fm createDirectoryAtPath:[repo stringByAppendingPathComponent:@"src"] withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:other withIntermediateDirectories:YES attributes:nil error:nil];
        [@"x" writeToFile:[repo stringByAppendingPathComponent:@"src/a.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        // The support folder is $MINMACS_HOME, which every section of one test.sh run shares, and test/act leaves its
        // watching-since a day old. The day of watching starts here, so the watched step below moves the digest.
        [fm removeItemAtPath:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"] error:nil];
        MMStartWatching();

        MMNooNooExpert *nn = MMNooNooExpert.shared;
        MMWorkForestExpert *wf = MMWorkForestExpert.shared;
        MMClutterKind *cache = nil, *tool = nil;
        for (MMClutterKind *k in MMClutterCatalog.shared.kinds) {
            if (!tool && k.cleanupArgs.count && !k.reportOnly) tool = k;
            if (!cache && k.klass == MMClutterCache && !k.cleanupArgs.count) cache = k;
        }
        DGFacts *f = [DGFacts new];
        MMWorktree *w = Tree(repo, @"feat");
        f.trees = @[w]; f.git = @{repo: Git(@"aaaa")};
        f.sessions = @[Session(other, 0)];
        f.clutter = @[Item(cache, [repo stringByAppendingPathComponent:@"node_modules"]), Item(tool, [dir stringByAppendingPathComponent:@"toolcache"])];
        f.sample = MMSenses.shared.sampleNow;

        NSMutableDictionary *out = [NSMutableDictionary new];
        out[@"kinds"] = @((BOOL)(cache && tool));
        __block uint64_t n0 = [nn inputDigestFrom:[f facts]], w0 = [wf inputDigestFrom:[f facts]];
        out[@"nnSame"] = @((BOOL)([nn inputDigestFrom:[f facts]] == n0));
        out[@"wfSame"] = @((BOOL)([wf inputDigestFrom:[f facts]] == w0));
        // Each change is checked against the digest just before it, then becomes the new base.
        void (^nnStep)(NSString *, dispatch_block_t) = ^(NSString *key, dispatch_block_t change) {
            change();
            uint64_t d = [nn inputDigestFrom:[f facts]];
            out[[@"nn." stringByAppendingString:key]] = @((BOOL)(d != n0));
            n0 = d;
        };
        void (^wfStep)(NSString *, dispatch_block_t) = ^(NSString *key, dispatch_block_t change) {
            change();
            uint64_t d = [wf inputDigestFrom:[f facts]];
            out[[@"wf." stringByAppendingString:key]] = @((BOOL)(d != w0));
            w0 = d;
        };

        // Noo-Noo.
        nnStep(@"scan", ^{ f.clutter = @[Item(cache, [repo stringByAppendingPathComponent:@"node_modules"]), f.clutter[1]]; });
        nnStep(@"index", ^{ f.trees = @[Tree(repo, @"feat")]; });
        nnStep(@"git", ^{ f.git = @{repo: Git(@"bbbb")}; });
        nnStep(@"sessionWrote", ^{ MMSession *x = Session(other, 0); [x setValue:NSDate.date forKey:@"lastActive"]; f.sessions = @[x]; });
        nnStep(@"sessions", ^{ MMSession *x = Session(other, 0); [x setValue:@"idle" forKey:@"liveStatus"]; f.sessions = @[x]; });
        nnStep(@"sessionBack", ^{ f.sessions = @[Session(other, 0)]; });
        nnStep(@"keep", ^{ [MMKeep keep:((MMClutterItem *)f.clutter[0]).key expert:@"noonoo" until:[NSDate dateWithTimeIntervalSinceNow:3600] by:@"manual" name:@"dg"]; });
        nnStep(@"keepAgain", ^{ [MMKeep keep:((MMClutterItem *)f.clutter[0]).key expert:@"noonoo" until:[NSDate dateWithTimeIntervalSinceNow:7200] by:@"manual" name:@"dg"]; });
        nnStep(@"mode", ^{ MMSetMode(@"noonoo", MMModeEager, @"manual"); });
        nnStep(@"watched", ^{
            [[NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970 - 2 * 86400]
                writeToFile:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
        nnStep(@"growth", ^{ MMSetPref(@"noonoo.growthMinBytes", @(2.0 * 1024 * 1024 * 1024)); });
        nnStep(@"dryRun", ^{
            NSDictionary *runs = @{tool.kindID: @{@"kindID": tool.kindID, @"at": @(NSDate.date.timeIntervalSince1970), @"exit": @0, @"wouldFree": @12345}};
            [[NSJSONSerialization dataWithJSONObject:runs options:0 error:nil]
                writeToFile:[MMExpertDir(@"noonoo") stringByAppendingPathComponent:@"commands.json"] atomically:YES];
        });
        // A working session started above the checkout runs a process in it: this tool, then its sleeper.
        nnStep(@"agentAbove", ^{ f.sessions = @[Session(dir, getpid())]; });
        __block pid_t kid = 0;
        nnStep(@"agentRuns", ^{ kid = Spawn(sleeper, repo); usleep(200000); f.sample = MMSenses.shared.sampleNow; });
        out[@"nnQuiet"] = @((BOOL)([nn inputDigestFrom:[f facts]] == n0));

        // WorkForest. The sleeper above already runs in the checkout.
        w0 = [wf inputDigestFrom:[f facts]];
        wfStep(@"index", ^{ f.trees = @[Tree(repo, @"feat")]; });
        wfStep(@"git", ^{ f.git = @{repo: Git(@"cccc")}; });
        // A session elsewhere changes nothing; one in the checkout does, and so does its next write.
        wfStep(@"sessionAway", ^{ f.sessions = @[Session(other, 0)]; });
        wfStep(@"sessions", ^{ f.sessions = @[Session(repo, 0)]; });
        wfStep(@"sessionWrote", ^{ MMSession *x = Session(repo, 0); [x setValue:NSDate.date forKey:@"lastActive"]; f.sessions = @[x]; });
        wfStep(@"disk", ^{ (void)[MMTreeDisk.shared factsFor:repo read:MMTreeDiskNow]; });
        wfStep(@"folder", ^{ [@"y" writeToFile:[repo stringByAppendingPathComponent:@"b.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil]; });
        wfStep(@"protect", ^{ [MMWFRules() set:YES value:@"feat" inList:@"protect.branches" key:nil]; });
        Stop(kid); kid = 0;
        f.sample = MMSenses.shared.sampleNow;
        w0 = [wf inputDigestFrom:[f facts]];
        __block pid_t inside = 0, twin = 0, away = 0;
        wfStep(@"procIn", ^{ inside = SpawnDetached(sleeper, repo); usleep(200000); f.sample = MMSenses.shared.sampleNow; });
        // A second process of the same name in the same folder changes nothing, and one in another folder neither.
        wfStep(@"twin", ^{ twin = SpawnDetached(sleeper, repo); usleep(200000); f.sample = MMSenses.shared.sampleNow; });
        wfStep(@"away", ^{ away = SpawnDetached(sleeper, other); usleep(200000); f.sample = MMSenses.shared.sampleNow; });
        wfStep(@"procGone", ^{ StopDetached(inside, sleeper); StopDetached(twin, sleeper); f.sample = MMSenses.shared.sampleNow; });
        wfStep(@"missing", ^{ [fm moveItemAtPath:repo toPath:[repo stringByAppendingString:@"-moved"] error:nil]; });
        [fm moveItemAtPath:[repo stringByAppendingString:@"-moved"] toPath:repo error:nil];
        StopDetached(away, sleeper);
        (void)[MMTreeDisk.shared factsFor:repo read:MMTreeDiskNow];   // a fresh walk, so the graph's first build queues none
        out[@"wfQuiet"] = @((BOOL)([wf inputDigestFrom:[f facts]] == [wf inputDigestFrom:[f facts]]));

        // MinMacs's and Insomnia's input digests, on input made here: what a row's group, reason or proposal reads
        // moves them, and an app's live numbers do not.
        MMMinMacsExpert *mm = MMMinMacsExpert.shared;
        MMMinMacsApp *app = [MMMinMacsApp new];
        app.pid = 4242; app.startSec = 1761000000; app.bundleID = @"com.example.dg"; app.name = @"DG"; app.memory = 300ull << 20; app.cpuPercent = 2;
        MMMinMacsAgent *ag = [MMMinMacsAgent new];
        ag.name = @"Claude Code"; ag.harnessID = @"claude-code"; ag.sessionID = @"dg-s"; ag.project = repo; ag.state = MMAgentWorking;
        MMProcKey ak = { 4343, 1761000001 }; ag.key = ak;
        __block NSArray *apps = @[app], *agents = @[ag];
        mm.inputFrom = ^MMMinMacsInput *(MMFacts *x) {
            MMMinMacsInput *in = [MMMinMacsInput new];
            in.apps = apps; in.agents = agents; in.memoryPressure = 1;
            return in;
        };
        uint64_t m0 = [mm inputDigestFrom:[f facts]];
        out[@"mmSame"] = @((BOOL)([mm inputDigestFrom:[f facts]] == m0));
        void (^mmStep)(NSString *, dispatch_block_t) = ^(NSString *key, dispatch_block_t change) {
            uint64_t before = [mm inputDigestFrom:[f facts]];
            change();
            out[[@"mm." stringByAppendingString:key]] = @((BOOL)([mm inputDigestFrom:[f facts]] != before));
        };
        mmStep(@"numbers", ^{ app.memory = 2ull << 30; app.cpuPercent = 85; app.processCount = 40; ag.cpuPercent = 120; ag.memory = 1ull << 30; });
        mmStep(@"ports", ^{ app.loopbackPorts = @[@5173]; });
        mmStep(@"spared", ^{ app.agentName = @"Claude Code"; app.agentPath = repo; });
        mmStep(@"agentState", ^{ ag.state = MMAgentIdle; });
        mmStep(@"newApp", ^{ MMMinMacsApp *b = [MMMinMacsApp new]; b.pid = 4444; b.startSec = 1761000002; b.bundleID = @"com.example.dg2"; apps = @[app, b]; });
        mmStep(@"rules", ^{ [MMMinMacsRules.shared setVerdict:MMMinMacsKeep forBundleID:@"com.example.dg"]; });
        // D11: while someone looks, the numbers a row shows move the digest, and stop moving it once nobody does.
        MMSetSomeoneLooks(YES);
        mmStep(@"numbersLooking", ^{ app.memory = 3ull << 30; app.cpuPercent = 20; app.processCount = 41; });
        mmStep(@"agentLooking", ^{ ag.cpuPercent = 3; ag.memory = 2ull << 30; });
        MMSetSomeoneLooks(NO);
        mmStep(@"numbersClosed", ^{ app.memory = 4ull << 30; app.cpuPercent = 60; });
        // The session index parses a grown transcript every minute, and every 15 seconds while someone looks.
        double parseClosed = MMSessionsGrownParseEvery();
        MMSetSomeoneLooks(YES);
        double parseLooking = MMSessionsGrownParseEvery();
        MMSetSomeoneLooks(NO);
        out[@"parseEvery"] = [NSString stringWithFormat:@"%.0f %.0f", parseClosed, parseLooking];
        MMInsomniaExpert *in = MMInsomniaExpert.shared;
        MMINWorker *wk = [MMINWorker new];
        wk.kind = @"agent"; wk.key = ak; wk.name = @"Claude Code"; wk.cwd = repo; wk.working = YES; wk.stableKey = @"claude-code:dg-s";
        in.inputFrom = ^MMINInput *(MMFacts *x) { MMINInput *i = [MMINInput new]; i.workers = @[wk]; return i; };
        uint64_t i0 = [in inputDigestFrom:[f facts]];
        out[@"inSame"] = @((BOOL)([in inputDigestFrom:[f facts]] == i0));
        wk.working = NO;
        out[@"in.working"] = @((BOOL)([in inputDigestFrom:[f facts]] != i0));
        in.inputFrom = nil;

        // Through the graph: a new sample in which only a process outside the checkout came builds nothing, and the
        // last snapshot stands, issue #52.
        DGSource *src = [DGSource new]; src.f = f;
        MMGraph *g = MMGraph.shared;
        g.source = src;
        [g addExpert:nn]; [g addExpert:wf]; [g addExpert:mm];
        NSInteger (^cost)(NSString *) = ^NSInteger(NSString *k) { return [g.costs[k] integerValue]; };
        BOOL (^waitCost)(NSString *, NSInteger) = ^BOOL(NSString *k, NSInteger n) {
            for (int i = 0; i < 100 && cost(k) < n; i++) usleep(50000);
            return cost(k) >= n;
        };
        BOOL (^waitBuilds)(NSInteger) = ^BOOL(NSInteger n) { return waitCost(@"builds", n); };
        [g start];
        BOOL first = waitBuilds(1);
        NSInteger b0 = cost(@"builds"), rn = cost(@"reused.noonoo"), rw = cost(@"reused.workforest"), k0 = cost(@"skipped.inputs");
        MMSnapshot *snap0 = g.latest;
        pid_t outside = SpawnDetached(sleeper, other);
        usleep(200000);
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL kept = waitCost(@"skipped.inputs", k0 + 1);
        usleep(100000);
        out[@"graphFirst"] = @(first);
        out[@"graphUnrelated"] = @((BOOL)(kept && cost(@"builds") == b0 && g.latest == snap0));
        // D11: with the window closed, an app's numbers alone build nothing; while it is open they build, and the
        // snapshot's MinMacs row holds the new memory.
        NSInteger k1 = cost(@"skipped.inputs"), bm = cost(@"builds");
        app.memory = 5ull << 30;
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL closedKept = waitCost(@"skipped.inputs", k1 + 1) && cost(@"builds") == bm;
        MMSetSomeoneLooks(YES);
        app.memory = 6ull << 30;
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL openBuilt = waitBuilds(bm + 1);
        uint64_t shown = 0;
        for (MMFinding *x in [g.latest findingsFor:@"minmacs"]) if ([x.stableKey isEqualToString:@"com.example.dg"]) shown = x.cost.ramBytes;
        MMSetSomeoneLooks(NO);
        out[@"graphNumbers"] = [NSString stringWithFormat:@"%d %d %d", closedKept, openBuilt, shown == (6ull << 30)];
        b0 = cost(@"builds");
        // A process that came in the checkout builds, and WorkForest's finding names it.
        StopDetached(outside, sleeper);
        pid_t inCheckout = SpawnDetached(sleeper, repo);
        usleep(200000);
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL builtIn = waitBuilds(b0 + 1);
        NSString *sleeperName = [sleeper.lastPathComponent substringToIndex:MIN((NSUInteger)16, sleeper.lastPathComponent.length)];
        BOOL named = NO;
        for (MMFinding *x in [g.latest findingsFor:@"workforest"]) if ([x.facts[@"processes"] containsObject:sleeperName]) named = YES;
        out[@"graphProcIn"] = @((BOOL)(builtIn && named));
        StopDetached(inCheckout, sleeper);
        // Any reason but a new sample asks every expert again.
        NSInteger b1 = cost(@"builds");
        rn = cost(@"reused.noonoo"); rw = cost(@"reused.workforest");
        [g rebuild:@"digest check action"];
        BOOL forced = waitBuilds(b1 + 1);
        out[@"graphForcedAsks"] = @((BOOL)(forced && cost(@"reused.noonoo") == rn && cost(@"reused.workforest") == rw));
        // A server that starts to listen builds within one pass, with LocoHost there, and its socket is in the snapshot.
        // NSTask starts it in a process group of its own, where setsid may refuse; it is stopped by its pid below.
        [g addExpert:MMLocoHost.shared];
        NSInteger b2 = cost(@"builds");
        [g rebuild:@"digest check action"];
        waitBuilds(b2 + 1);
        NSString *portFile = [dir stringByAppendingPathComponent:@"port"];
        NSTask *srv = [NSTask new];
        srv.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
        srv.arguments = @[@"-I", @"-c", @"import os, runpy, sys\ntry: os.setsid()\nexcept OSError: pass\nsys.argv = sys.argv[1:]\nrunpy.run_path(sys.argv[0], run_name='__main__')",
                          @(argv[3]), portFile];
        srv.currentDirectoryURL = [NSURL fileURLWithPath:other];
        BOOL launched = [srv launchAndReturnError:nil];
        for (int i = 0; i < 100 && ![fm fileExistsAtPath:portFile]; i++) usleep(50000);
        usleep(200000);
        NSInteger b3 = cost(@"builds");
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL builtServer = waitBuilds(b3 + 1);
        BOOL listens = NO;
        NSUInteger n = 0;
        const MMSocket *sv = [g.latest.facts.sample sockets:&n];
        for (NSUInteger i = 0; sv && i < n; i++) if (sv[i].pid == srv.processIdentifier && sv[i].state == MMSocketListen) listens = YES;
        out[@"graphServer"] = [NSString stringWithFormat:@"%d %d %d", launched, builtServer, listens];
        if (launched && srv.running) { [srv terminate]; [srv waitUntilExit]; }
        [g stop];
        mm.inputFrom = nil;
        NSData *d = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
