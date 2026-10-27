// The WorkForest CLI for test/workforest.sh. It links every .m under Sources except main.m, registers WorkForest,
// and runs each verb the way the app runs a verb handed over core.sock, so a verb that changes things runs too.
// Worktrees come from Core's repo index, which walks $MINMACS_ROOTS in the worker. Processes come from Senses and
// sessions from Know. Git facts come from the fixture file $WF_GIT_FACTS, keyed by worktree path, until Know
// computes them itself. Nothing here runs git: the test writes that file.
// The name it runs under picks the program, so a symlink named workforest gets WorkForest 0.1's syntax.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/WorkForest/MMWorkForest.h"

static NSString *Real(NSString *path) {
    char buf[PATH_MAX];
    return path.length && realpath(path.fileSystemRepresentation, buf) ? @(buf) : path;
}

static NSDictionary *GitFile(void) {
    NSString *p = NSProcessInfo.processInfo.environment[@"WF_GIT_FACTS"];
    NSData *d = p.length ? [NSData dataWithContentsOfFile:p] : nil;
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : @{};
}

/// Fixture git facts, set on Core's own class, the way Know will hand them over.
static MMGitFacts *Facts(NSDictionary *j) {
    MMGitFacts *g = [MMGitFacts new];
    NSDictionary *kinds = @{@"ancestor": @(MMMergedAncestor), @"tree": @(MMMergedTree), @"patch": @(MMMergedPatch), @"squash": @(MMMergedSquash),
                            @"pr": @(MMMergedPR), @"merge-tree": @(MMMergedMergeTree)};
    for (NSString *k in @[@"head", @"defaultBranch", @"upstream"]) if ([j[k] isKindOfClass:NSString.class]) [g setValue:j[k] forKey:k];
    for (NSString *k in @[@"dirty", @"untracked", @"stashes", @"unpushed", @"notInDefault", @"onRemote", @"upstreamGone"])
        if ([j[k] isKindOfClass:NSNumber.class]) [g setValue:j[k] forKey:k];
    [g setValue:kinds[j[@"merged"] ?: @""] ?: @(MMMergedNone) forKey:@"merged"];
    if ([j[@"lastCommit"] isKindOfClass:NSNumber.class]) [g setValue:[NSDate dateWithTimeIntervalSince1970:[j[@"lastCommit"] doubleValue]] forKey:@"lastCommit"];
    return g;
}

@interface WFSource : NSObject <MMFactSource>
@end
@implementation WFSource
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    MMPower *p = MMSenses.shared.power;
    [MMSessions.shared refresh];
    NSDictionary *file = GitFile();
    NSMutableDictionary *git = [NSMutableDictionary new];
    NSArray<MMWorktree *> *trees = MMRepoIndex.shared.worktrees;
    for (MMWorktree *w in trees) {
        NSDictionary *j = file[Real(w.path)] ?: file[w.path];
        if ([j isKindOfClass:NSDictionary.class]) git[w.path] = Facts(j);
    }
    return [MMFacts generation:generation sample:s power:p agents:[MMRegistry.shared agentsIn:s power:p] ?: @[]
                      sessions:MMSessions.shared.all ?: @[] worktrees:trees clutter:@[] git:git];
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

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child is this same binary
        MMRegisterExpert(MMWorkForestExpert.shared);
        if (argc > 1 && !strcmp(argv[1], "_verbs")) {
            for (MMVerbSpec *v in MMWorkForestExpert.shared.verbs) printf("%s\t%d\n", v.verb.UTF8String, v.mutates);
            printf("legacyName\t%s\n", MMWorkForestExpert.shared.legacyName.UTF8String);
            printf("registered\t%s\n", MMExpertNamed(@"workforest") == MMWorkForestExpert.shared ? "yes" : "no");
            NSArray *w = MMLegacyWords(@"workforest", @[@"remove", @"/x", @"--yes"]);
            printf("shim\t%s\n", [w componentsJoinedByString:@" "].UTF8String);
            return 0;
        }
        WFSource *src = [WFSource new];
        MMSetCLIFactSource(src);
        MMGraph.shared.source = src;
        WalkRoots();
        NSMutableArray *words = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [words addObject:@(argv[i])];
        if (!words.count) [words addObject:@"list"];
        NSDictionary *req = @{@"cli": words, @"program": MMProgramName(argv[0]), @"cwd": NSFileManager.defaultManager.currentDirectoryPath};
        __block NSDictionary *reply;
        // As in the app: the verb runs off main, where MMRunAction may gather fresh facts.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ reply = MMCLIReply(req); dispatch_semaphore_signal(done); });
        while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW)) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        fputs([reply[@"out"] description].UTF8String ?: "", stdout);
        fputs([reply[@"err"] description].UTF8String ?: "", stderr);
        fflush(stdout);
        return [reply[@"status"] intValue];
    }
}
