// Issue #125: the keep check right before a removal, on the fresh read, under a root that is a link. Linked into
// wfcli, which links every .m under Sources but main.m. Every path it gets lies in $MINMACS_HOME, and the index walks
// $MINMACS_ROOTS alone. Nothing here removes anything or asks git to.
// Usage: wfcli _freshkeep <app|cli> <worktree> <finding path> <command>
//   The source's facts as a plan reads them, and WorkForest's finding of worktree, given by its resolved path, made
//   from them and named by finding path, the resolved one or the one through the link. Then /bin/sh -c command, the
//   change after the plan. Then the source's freshFactsFor: on that finding, as MMRunAction asks it, and MMMustKeep
//   with the manual policy on those facts, before git is asked to remove. app is the app's source in MMCore.m, cli
//   is MMColdFacts, a cold CLI's. The index is walked and read once first, as a cold run reads it.
//   Prints JSON: plan and fresh, each the keep's words or "go", and entries, the git facts the fresh read handed
//   over for each name of the folder: name dirty untracked head.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Experts/WorkForest/MMWorkForest.h"

static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ block(); dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
}

static NSString *Entries(MMFacts *facts, NSString *real) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWorktree *w in facts.worktrees) {
        if (![w.realPath isEqualToString:real] && ![w.path isEqualToString:real]) continue;
        MMGitFacts *g = [facts gitFor:w];
        [out addObject:g ? [NSString stringWithFormat:@"%@ %ld %ld %@", w.path, (long)g.dirty, (long)g.untracked,
                                                        g.head.length >= 8 ? [g.head substringToIndex:8] : @"-"]
                         : [w.path stringByAppendingString:@" none"]];
    }
    return [out componentsJoinedByString:@" | "];
}

int WFFreshKeep(int argc, const char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: wfcli _freshkeep app|cli <worktree> <finding path> <command>\n"); return 2; }
    NSString *kind = @(argv[0]), *tree = @(argv[1]), *named = @(argv[2]), *command = @(argv[3]);
    id<MMFactSource> cold = [NSClassFromString(@"MMColdFacts") new];
    id<MMFactSource> source = [kind isEqualToString:@"app"] ? [NSClassFromString(@"MMCoreFactSource") new]
                            : [kind isEqualToString:@"cli"] ? cold : nil;
    if (!cold || !source) { fprintf(stderr, "no such source: %s\n", argv[0]); return 2; }
    __block MMFacts *plan = nil, *fresh = nil;
    __block MMFinding *f = nil;
    __block NSString *planKeep = nil, *freshKeep = nil;
    OffMain(^{
        [cold factsFor:0];   // the walk and one git read of every checkout, as a cold run makes them
        plan = [source factsFor:1];
        MMWFReadNow = YES;   // the disk facts read now, as a verb with its own snapshot reads them
        for (MMFinding *x in [MMWorkForestExpert.shared findingsFrom:plan])
            if ([x.kind isEqualToString:@"worktree"] && [x.path isEqualToString:tree]) f = x;
        if (f && ![named isEqualToString:tree]) {
            MMFinding *was = f;
            f = [MMFinding expert:was.expert kind:was.kind stableKey:named build:^(MMFindingBuilder *b) {
                b.path = named; b.title = was.title; b.instanceKey = was.instanceKey; b.facts = was.facts;
                b.keepReasons = was.keepReasons; b.proposal = was.proposal;
            }];
        }
        if (f) planKeep = MMMustKeep(f, plan, nil, MMWFManualPolicy());
    });
    if (!f) { fprintf(stderr, "no worktree finding at %s\n", argv[1]); return 2; }
    NSTask *t = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"] arguments:@[@"-c", command] error:nil
                                   terminationHandler:nil];
    [t waitUntilExit];
    if (t.terminationStatus != 0) { fprintf(stderr, "the change failed\n"); return 2; }
    OffMain(^{
        fresh = [source freshFactsFor:f];
        freshKeep = MMMustKeep(f, fresh, nil, MMWFManualPolicy());
    });
    NSDictionary *j = @{@"plan": planKeep ?: @"go", @"fresh": freshKeep ?: @"go", @"entries": Entries(fresh, tree)};
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    return 0;
}
