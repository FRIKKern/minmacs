// The Wrap Up test tool, issue #27. test/wrapup.sh builds it with every .m under Sources but main.m and the shell.
// It registers the four experts that own Wrap Up's parts and runs each verb the way the app runs a verb handed over
// core.sock, off main, so a verb that changes things runs too.
//   tool verb <words...>     one verb, as `minmacs <words...>` runs it in the app
//   tool card <path>         the WorkForest card of that worktree, as JSON: its title, status and actions
//   tool _walk               the worker child of P4, which the repo index starts from this same binary
// Facts are real and fixture-scoped: the Senses sample, Know's sessions under $CLAUDE_CONFIG_DIR, the repo index
// under $MINMACS_ROOTS with git facts read now, and the clutter catalog scanned under $MINMACS_CLUTTER_ROOT.
// It refuses to run unless MINMACS_HOME, MINMACS_ROOTS and MINMACS_CLUTTER_ROOT are set and the last two sit inside
// the first, so it never reads or acts on anything outside the test's own folder.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/MinMacs/MMMinMacs.h"

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

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
