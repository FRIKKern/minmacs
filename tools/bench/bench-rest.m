// bench rest: what the rest of the memory by category costs, Core/MMRest.h, on this Mac's real process table.
// tools/bench/bench.m includes this file. It is not built on its own.
//
// The window's feed classifies what no row holds while the window is open, and only then. Here the real sample is
// read twice by Senses, as the app reads it, and the categories are built with no row claiming anything, so every
// process of the Mac is classified: more than the window ever does. Cold is the first build, with every process looked
// up and every path its name does not place read once; warm is each build after it, from the kept lookups, as the
// window builds one per snapshot. The story's details are read for the 60 biggest processes of the biggest category.
// It reads processes and never signals one.
#import "Core/MMRest.h"

static int Rest(NSArray<NSString *> *args) {
    int n = Option(args, @"--iterations", @"100").intValue;
    if (n <= 0) { fprintf(stderr, "usage: bench rest [--iterations N]\n"); return 2; }
    if (!SafeEnvironment()) return 2;
    MMSenses *senses = MMSenses.shared;
    [senses sampleNow];
    MMSample *s = [senses sampleNow];
    uint64_t rest = 6ull << 30;
    MMRestForget();
    uint64_t t0 = ThreadCPUNs();
    NSArray<MMRestCategory *> *cats = MMRestBuild(s, [NSSet set], rest, nil);
    double cold = (ThreadCPUNs() - t0) / 1e6;
    MMRestCounts afterCold = MMRestCountsNow();
    NSMutableArray *warm = [NSMutableArray new];
    for (int i = 0; i < n; i++) {
        uint64_t a = ThreadCPUNs();
        cats = MMRestBuild(s, [NSSet set], rest, nil);
        [warm addObject:@((ThreadCPUNs() - a) / 1e6)];
    }
    MMRestCounts afterWarm = MMRestCountsNow();
    MMRestCategory *biggest = nil;
    for (MMRestCategory *c in cats) if (!biggest || c.procs.count > biggest.procs.count) biggest = c;
    uint64_t d0 = ThreadCPUNs();
    NSUInteger details = 0;
    for (MMRestProc *p in biggest.procs) { if (details++ >= 60) break; (void)MMRestDetails(s, p.pid, nil); }
    double story = (ThreadCPUNs() - d0) / 1e6;
    NSMutableDictionary *by = [NSMutableDictionary new];
    for (MMRestCategory *c in cats) by[c.kind.key] = @{@"processes": @(c.procs.count), @"measuredMB": R2((c.bytes - c.unheld) / 1048576.0), @"unmeasured": @(c.unmeasured)};
    PrintJSON(@{@"kind": @"rest", @"processes": @(s.procs.count), @"iterations": @(n),
                @"coldMs": R3(cold), @"warmMs": Stats(warm), @"storyDetailsMs": R3(story), @"storyProcesses": @(MIN(details, (NSUInteger)60)),
                @"classified": @(afterCold.classified), @"pathsRead": @(afterCold.pathsRead),
                @"classifiedAgain": @(afterWarm.classified - afterCold.classified), @"categories": by});
    return 0;
}
