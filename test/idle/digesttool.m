// Noo-Noo's and WorkForest's input digests, issue #52. test/idle.sh builds this with every .m under Sources except
// main.m, under -DMM_TESTS, and runs it in its own folder inside $MINMACS_HOME:
//   digesttool <dir>    each input the digests read, changed one at a time, as JSON: same, then one key per input
// The facts are built by hand from objects made here. The one process it starts is a sleeper of its own, under a
// name unique to the run, with its cwd in the fixture checkout; it stops that pid and no other.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "Core/Know/MMTreeDisk.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/WorkForest/MMWorkForest.h"
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
        if (argc < 3 || !NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) {
            fprintf(stderr, "usage: digesttool <dir> <sleeper>, with MINMACS_HOME set\n"); return 2;
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

        // Through the graph: a new sample in which only a process outside the checkout moved builds, and both experts
        // hand back their findings.
        DGSource *src = [DGSource new]; src.f = f;
        MMGraph *g = MMGraph.shared;
        g.source = src;
        [g addExpert:nn]; [g addExpert:wf];
        NSInteger (^cost)(NSString *) = ^NSInteger(NSString *k) { return [g.costs[k] integerValue]; };
        BOOL (^waitBuilds)(NSInteger) = ^BOOL(NSInteger n) {
            for (int i = 0; i < 100 && cost(@"builds") < n; i++) usleep(50000);
            return cost(@"builds") >= n;
        };
        [g start];
        BOOL first = waitBuilds(1);
        NSInteger b0 = cost(@"builds"), rn = cost(@"reused.noonoo"), rw = cost(@"reused.workforest");
        pid_t outside = SpawnDetached(sleeper, other);
        usleep(200000);
        f.sample = MMSenses.shared.sampleNow;
        [g rebuild:@"sample"];
        BOOL built = waitBuilds(b0 + 1);
        out[@"graphBuilt"] = @((BOOL)(first && built));
        out[@"graphReusedNN"] = @(cost(@"reused.noonoo") - rn);
        out[@"graphReusedWF"] = @(cost(@"reused.workforest") - rw);
        // Any reason but a new sample asks every expert again.
        NSInteger b1 = cost(@"builds");
        [g rebuild:@"digest check action"];
        BOOL forced = waitBuilds(b1 + 1);
        out[@"graphForcedAsks"] = @((BOOL)(forced && cost(@"reused.noonoo") - rn == 1 && cost(@"reused.workforest") - rw == 1));
        [g stop];
        StopDetached(outside, sleeper);
        NSData *d = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
