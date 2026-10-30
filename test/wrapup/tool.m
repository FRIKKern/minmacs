// The Wrap Up test tool, issue #27. test/wrapup.sh builds it with every .m under Sources but main.m and the shell.
// It registers the four experts that own Wrap Up's parts and runs each verb the way the app runs a verb handed over
// core.sock, off main, so a verb that changes things runs too.
//   tool verb <words...>     one verb, as `minmacs <words...>` runs it in the app
//   tool card <path>         the WorkForest card of that worktree, as JSON: its title, status and actions
//   tool plan <path> <n>     the plan built on main n times, a second apart, as a menu builds it: step and title each
//   tool _walk               the worker child of P4, which the repo index starts from this same binary
// Facts are real and fixture-scoped: the Senses sample, Know's sessions under $CLAUDE_CONFIG_DIR, the repo index
// under $MINMACS_ROOTS with git facts read now, and the clutter catalog scanned under $MINMACS_CLUTTER_ROOT.
// It refuses to run unless MINMACS_HOME, MINMACS_ROOTS and MINMACS_CLUTTER_ROOT are set and the last two sit inside
// the first, so it never reads or acts on anything outside the test's own folder.
// MinMacs sees one app only: the fixture browser WU_BROWSER, a bundle id unique to the run, at the pid in
// WU_BROWSER_PID. Its tabs live in the JSON file WU_TABS, read and changed by a fake tab bridge, so no Apple event
// ever reaches a real browser. With no WU_BROWSER_PID, MinMacs sees no app at all.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/MinMacs/MMMinMacs.h"

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

/// The fake tab bridge: {"tabs": [{pid, window, id, url, title, mode}], "closed": [], "opened": [], "denied": false}.
/// A tab with mode incognito is a private window: it is handed over marked, so the check is the expert's own.
/// WU_MOVE_URL makes the tab on that URL navigate away right before it would close, as a person might.
/// "denied" true answers that reading would prompt, so a background read never happens.
@interface WUBridge : NSObject <MMMinMacsTabBridge>
@property (copy) NSString *path, *moveURL;
@end
@implementation WUBridge
- (NSMutableDictionary *)load {
    NSData *d = [NSData dataWithContentsOfFile:self.path];
    NSMutableDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![j isKindOfClass:NSMutableDictionary.class]) j = [NSMutableDictionary new];
    for (NSString *k in @[@"tabs", @"closed", @"opened", @"reads"]) if (![j[k] isKindOfClass:NSMutableArray.class]) j[k] = [NSMutableArray new];
    return j;
}
- (void)save:(NSDictionary *)j {
    [[NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted error:nil] writeToFile:self.path atomically:YES];
}
- (BOOL)mayReadWithoutAsking:(pid_t)pid bundleID:(NSString *)bundleID { return ![[self load][@"denied"] boolValue]; }
- (NSArray<MMMinMacsTab *> *)tabsOf:(pid_t)pid bundleID:(NSString *)bundleID error:(NSString **)error {
    NSMutableDictionary *j = [self load];
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *t in j[@"tabs"]) {
        if ([t[@"pid"] intValue] != pid) continue;
        MMMinMacsTab *x = [MMMinMacsTab new];
        x.url = t[@"url"]; x.title = t[@"title"] ?: t[@"url"]; x.host = [NSURL URLWithString:x.url].host.lowercaseString ?: @"";
        x.windowID = [t[@"window"] integerValue]; x.tabID = [t[@"id"] integerValue];
        x.privateWindow = [t[@"mode"] isEqual:@"incognito"];
        [out addObject:x];
    }
    [j[@"reads"] addObject:@(pid)];
    [self save:j];
    return out;
}
- (NSArray<MMMinMacsTab *> *)close:(NSArray<MMMinMacsTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bundleID {
    NSMutableDictionary *j = [self load];
    NSMutableArray *closed = [NSMutableArray new];
    for (MMMinMacsTab *t in tabs) {
        for (NSMutableDictionary *e in [j[@"tabs"] copy]) {
            if ([e[@"pid"] intValue] != pid || [e[@"window"] integerValue] != t.windowID || [e[@"id"] integerValue] != t.tabID) continue;
            if (self.moveURL && [e[@"url"] isEqualToString:self.moveURL]) e[@"url"] = @"https://moved.example.org/";
            if (![e[@"url"] isEqualToString:t.url]) continue;
            [j[@"tabs"] removeObject:e];
            [j[@"closed"] addObject:t.url];
            [closed addObject:t];
        }
    }
    [self save:j];
    return closed;
}
- (NSString *)open:(NSArray<NSString *> *)urls bundleID:(NSString *)bundleID appPath:(NSString *)appPath {
    NSMutableDictionary *j = [self load];
    for (NSString *u in urls) [j[@"opened"] addObject:@{@"url": u, @"bundleID": bundleID ?: @"", @"at": @(NSDate.date.timeIntervalSince1970)}];
    [self save:j];
    return nil;
}
@end

/// The one app MinMacs sees: the fixture browser, or none.
static MMMinMacsInput *FixtureApps(MMFacts *facts) {
    MMMinMacsInput *in = [MMMinMacsInput new];
    in.memoryPressure = 1; in.thermal = NSProcessInfoThermalStateNominal;
    pid_t pid = (pid_t)Env(@"WU_BROWSER_PID").intValue;
    MMProc *p = pid > 1 ? [facts.sample proc:pid] : nil;
    if (!p || !Env(@"WU_BROWSER").length) { in.apps = @[]; return in; }
    MMMinMacsApp *a = [MMMinMacsApp new];
    a.pid = pid; a.startSec = p.startSec; a.bundleID = Env(@"WU_BROWSER"); a.name = @"Fixture Browser";
    a.bundlePath = [Env(@"MINMACS_HOME") stringByAppendingPathComponent:@"FixtureBrowser.app"];
    a.pids = @[@(pid)]; a.processCount = 1; a.memory = 1 << 20;
    in.apps = @[a];
    return in;
}

@interface WUSource : NSObject <MMFactSource>
@end
@implementation WUSource
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    MMPower *p = MMSenses.shared.power;
    [MMSessions.shared refresh];
    NSArray<MMWorktree *> *trees = MMRepoIndex.shared.worktrees;
    NSMutableDictionary *git = [NSMutableDictionary new];
    for (MMWorktree *w in trees) {
        MMGitFacts *g = w.path ? [MMRepoIndex.shared factsFor:w wait:!NSThread.isMainThread] : nil;
        if (g) git[w.path] = g;
    }
    return [MMFacts generation:generation sample:s power:p agents:[MMRegistry.shared agentsIn:s power:p] ?: @[]
                      sessions:MMSessions.shared.all ?: @[] worktrees:trees clutter:MMClutterCatalog.shared.items ?: @[] git:git];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:MMGraph.shared.latest.generation]; }
@end

/// One walk of the roots, waited for, so the verb sees the worktrees on disk now.
static void WalkRoots(void) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    id token = [NSNotificationCenter.defaultCenter addObserverForName:MMRepoIndexDidChangeNotification object:nil queue:nil
                                                           usingBlock:^(NSNotification *n) { dispatch_semaphore_signal(done); }];
    [MMRepoIndex.shared refresh:nil];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
    [NSNotificationCenter.defaultCenter removeObserver:token];
}

/// Runs block off main and turns the main run loop until it ends, as the app's socket queue does.
static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ block(); dispatch_semaphore_signal(done); });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW))
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static BOOL Inside(NSString *path, NSString *home) {
    return path.length && home.length && [path.stringByStandardizingPath hasPrefix:[home.stringByStandardizingPath stringByAppendingString:@"/"]];
}

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:MMJSONSafe(j) options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();
        NSString *home = Env(@"MINMACS_HOME");
        for (NSString *k in @[@"MINMACS_ROOTS", @"MINMACS_CLUTTER_ROOT"])
            if (!Inside(Env(k), home)) { fprintf(stderr, "tool: %s must sit inside MINMACS_HOME\n", k.UTF8String); return 9; }
        if (argc < 3) { fprintf(stderr, "usage: tool verb <words...> | tool card <path>\n"); return 2; }
        MMRegisterExpert(MMLocoHost.shared);
        MMRegisterExpert(MMMinMacsExpert.shared);
        MMRegisterExpert(MMNooNooExpert.shared);
        MMRegisterExpert(MMWorkForestExpert.shared);
        MMMinMacsExpert.shared.inputFrom = ^MMMinMacsInput *(MMFacts *f) { return FixtureApps(f); };
        if (Env(@"WU_TABS").length) {
            WUBridge *bridge = [WUBridge new];
            bridge.path = Env(@"WU_TABS"); bridge.moveURL = Env(@"WU_MOVE_URL");
            MMMinMacsUseTabBridge(bridge);
        }
        if (Env(@"WU_BROWSER").length) MMMinMacsAddTestBrowser(Env(@"WU_BROWSER"));
        WUSource *src = [WUSource new];
        MMSetCLIFactSource(src);
        MMGraph.shared.source = src;
        WalkRoots();
        MMClutterCatalog *c = MMClutterCatalog.shared;
        NSMutableArray *projects = [NSMutableArray new];
        for (MMWorktree *w in MMRepoIndex.shared.worktrees) if (w.path) [projects addObject:w.path];
        c.projects = projects;
        OffMain(^{ (void)[c scan]; });

        if (!strcmp(argv[1], "card")) {
            NSString *path = @(argv[2]).stringByStandardizingPath;
            __block MMSnapshot *s = nil;
            // As the graph queue does in the app: the snapshot, then what each menu reads from it, off main.
            OffMain(^{ s = MMCLISnapshot(NO); });
            MMFinding *f = nil;
            for (MMFinding *x in [s findingsFor:@"workforest"]) {
                char buf[PATH_MAX];
                NSString *real = realpath(path.fileSystemRepresentation, buf) ? @(buf) : path;
                if ([x.path isEqualToString:path] || [x.path isEqualToString:real]) f = x;
            }
            if (!f) { fprintf(stderr, "tool: no worktree finding at %s\n", argv[2]); return 1; }
            // In the app the menu queues this check and shows the card again after it. Here it runs first.
            MMWFTree *t = MMWFTreeOf(f);
            OffMain(^{ (void)MMWrapUpConfigOnly(t.path, t.head, t.untracked, YES); [s prepareFor:MMExperts()]; });
            MMCardSpec *card = [MMWorkForestExpert.shared cardFor:f snapshot:s];
            NSMutableArray *actions = [NSMutableArray new];
            for (MMActionSpec *a in card.actions) [actions addObject:@{@"title": a.title ?: @"", @"tail": a.tail ?: @"", @"disabled": a.disabledReason ?: @""}];
            PrintJSON(@{@"title": card.title ?: @"", @"status": [NSString stringWithFormat:@"%@ %@", card.statusWord, card.statusText], @"actions": actions});
            return 0;
        }
        if (!strcmp(argv[1], "plan") && argc > 3) {
            // On main, where the tabs part never waits: it uses the last read, or queues one in the background.
            NSString *path = @(argv[2]).stringByStandardizingPath;
            int n = atoi(argv[3]);
            NSMutableArray *rounds = [NSMutableArray new];
            for (int i = 0; i < n; i++) {
                __block MMSnapshot *s = nil;
                OffMain(^{ s = MMCLISnapshot(NO); });
                MMWrapUpPlan *plan = MMWrapUpPlanFor(path, s);
                NSMutableArray *parts = [NSMutableArray new];
                for (MMWrapUpPart *p in plan.parts) [parts addObject:[NSString stringWithFormat:@"%@ %@", MMWrapUpStepName(p.step), p.title]];
                [rounds addObject:parts];
                if (i + 1 < n) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            }
            PrintJSON(rounds);
            return 0;
        }
        if (strcmp(argv[1], "verb")) { fprintf(stderr, "tool: unknown command %s\n", argv[1]); return 2; }
        NSMutableArray *words = [NSMutableArray new];
        for (int i = 2; i < argc; i++) [words addObject:@(argv[i])];
        NSDictionary *req = @{@"cli": words, @"program": @"minmacs", @"cwd": NSFileManager.defaultManager.currentDirectoryPath};
        __block NSDictionary *reply;
        OffMain(^{ reply = MMCLIReply(req); });
        fputs([reply[@"out"] description].UTF8String ?: "", stdout);
        fputs([reply[@"err"] description].UTF8String ?: "", stderr);
        fflush(stdout);
        return [reply[@"status"] intValue];
    }
}
