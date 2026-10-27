// The verb registry, the legacy names, the hand-over to the app and the cold snapshot. See MMCLI.h.
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#include <stdio.h>
#include <string.h>
#include <os/lock.h>

NSString *const MMPhase = @"phase 1";

#pragma mark - Legacy names

NSDictionary<NSString *, NSString *> *MMLegacyNames(void) {
    return @{@"locohost": @"locohost", @"workforest": @"workforest", @"noo-noo": @"noonoo", @"noonoo": @"noonoo",
             @"insomnia": @"insomnia"};
}

/// The expert a program name stands for, or nil for minmacs itself.
static NSString *ExpertOfProgram(NSString *program) {
    if (!program.length || [program isEqualToString:@"minmacs"]) return nil;
    for (id<MMExpert> e in MMExperts())
        if ([e respondsToSelector:@selector(legacyName)] && [e.legacyName.lowercaseString isEqualToString:program]) return e.expertID;
    return MMLegacyNames()[program];
}

NSString *MMProgramName(const char *argv0) {
    NSString *base = argv0 ? @(argv0).lastPathComponent.lowercaseString : @"";
    return ExpertOfProgram(base) ? base : @"minmacs";
}

/// One alias: the old command and the words it becomes. $1 is the old command's first argument.
static NSArray<NSString *> *Expand(NSArray<NSString *> *pattern, NSArray<NSString *> *words) {
    NSMutableArray *out = [NSMutableArray new];
    NSArray *rest = words.count > 1 ? [words subarrayWithRange:NSMakeRange(1, words.count - 1)] : @[];
    NSString *first = nil;
    for (NSString *w in rest) if (![w hasPrefix:@"--"]) { first = w; break; }
    BOOL usedFirst = NO;
    for (NSString *p in pattern) {
        if ([p isEqualToString:@"$1"]) { if (first) { [out addObject:first]; usedFirst = YES; } continue; }
        [out addObject:p];
    }
    BOOL skipped = NO;
    for (NSString *w in rest) {
        if (usedFirst && !skipped && [w isEqualToString:first]) { skipped = YES; continue; }
        [out addObject:w];
    }
    return out;
}

NSArray<NSString *> *MMLegacyWords(NSString *program, NSArray<NSString *> *words) {
    // LocoHost 1.x, from locohost/Sources/main.m Usage. Its other commands are LocoHost's own verbs.
    static NSDictionary *locohost, *minmacs, *workforest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        locohost = @{
            @"list":       @[@"hosts"],
            @"explain":    @[@"hosts", @"$1"],
            @"who":        @[@"hosts", @"$1"],
            @"where":      @[@"where", @"--port", @"$1"],
            @"review":     @[@"review", @"locohost", @"--now"],
            @"summary":    @[@"review", @"locohost"],
            @"auto":       @[@"tidy", @"locohost"],
            // 1.x stopped every server the review confirmed idle, whatever the mode. In 2.0 that is what Eager does.
            @"idle":       @[@"tidy", @"locohost", @"--dry-run", @"--mode", @"eager"],
            @"close-idle": @[@"tidy", @"locohost", @"--mode", @"eager"],
            @"stopped":    @[@"restore", @"--list", @"--expert", @"locohost"],
            @"mode":       @[@"mode", @"locohost", @"$1"],
        };
        // WorkForest 0.1, from workforest/Sources/main.m Usage. Each command is a part of WorkForest's trees verb.
        workforest = @{
            @"list":     @[@"trees", @"list"],
            @"explain":  @[@"trees", @"explain", @"$1"],
            @"review":   @[@"trees", @"review"],
            @"summary":  @[@"trees", @"plan"],
            @"auto":     @[@"trees", @"auto"],
            @"clean-up": @[@"trees", @"clean-up"],
            @"remove":   @[@"trees", @"remove", @"$1"],
            @"restore":  @[@"trees", @"restore", @"$1"],
            @"removed":  @[@"trees", @"removed"],
            @"keep":     @[@"trees", @"keep", @"$1"],
            @"prune":    @[@"trees", @"prune", @"$1"],
            @"fetch":    @[@"trees", @"fetch"],
            @"rules":    @[@"trees", @"rules"],
            @"mode":     @[@"mode", @"workforest", @"$1"],
        };
        // MinMacs 1.2, from git show legacy:Sources/main.m Usage. trim, classify and rules are the MinMacs expert's.
        minmacs = @{
            @"plan":   @[@"tidy", @"minmacs", @"--dry-run"],
            @"run":    @[@"tidy", @"minmacs"],
            @"agents": @[@"work"],
        };
    });
    NSDictionary *table = [program isEqualToString:@"locohost"] ? locohost : [program isEqualToString:@"minmacs"] ? minmacs
                        : [program isEqualToString:@"workforest"] ? workforest : nil;
    NSString *cmd = words.firstObject ?: @"";
    NSArray *pattern = table[cmd];
    return pattern ? Expand(pattern, words.count ? words : @[@""]) : nil;
}

#pragma mark - The registry

static NSArray<MMVerbSpec *> *ExpertVerbs(id<MMExpert> e) {
    NSArray *v = [e verbs];
    return [v isKindOfClass:NSArray.class] ? v : @[];
}

NSArray<MMVerbSpec *> *MMAllVerbs(void) {
    NSMutableArray *all = [MMCoreVerbs() mutableCopy];
    for (id<MMExpert> e in MMExperts()) [all addObjectsFromArray:ExpertVerbs(e)];
    return all;
}

MMVerbSpec *MMFindVerb(NSString *program, NSString *verb) {
    if (!verb.length) return nil;
    NSString *own = ExpertOfProgram(program);
    if (own) for (MMVerbSpec *v in ExpertVerbs(MMExpertNamed(own))) if ([v.verb isEqualToString:verb]) return v;
    for (MMVerbSpec *v in MMCoreVerbs()) if ([v.verb isEqualToString:verb]) return v;
    for (id<MMExpert> e in MMExperts()) for (MMVerbSpec *v in ExpertVerbs(e)) if ([v.verb isEqualToString:verb]) return v;
    return nil;
}

/// Verbs that always run in this process: they say who this binary is, or they are the worker of P4.
static BOOL RunsHere(NSString *verb) {
    return [@[@"version", @"help", @"_walk", @"_serve"] containsObject:verb] || [verb hasPrefix:@"_"];
}

BOOL MMWantsCLI(int argc, const char *argv[]) {
    if (argc < 2) return NO;
    if (!strcmp(argv[1], "--version") || !strcmp(argv[1], "--help") || !strcmp(argv[1], "-h")) return YES;
    return argv[1][0] != '-';
}

#pragma mark - The snapshot

static id<MMFactSource> gCLISource;
void MMSetCLIFactSource(id<MMFactSource> source) { gCLISource = source; }

/// One sample of Senses and Know, for a CLI run with no app. Worktrees and clutter come with phases 2 and 3.
@interface MMColdFacts : NSObject <MMFactSource>
@end
@implementation MMColdFacts
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    MMPower *p = [MMSenses.shared power];
    NSArray *agents = s ? [MMRegistry.shared agentsIn:s power:p] : @[];
    [MMSessions.shared refresh];
    return [MMFacts generation:generation sample:s power:p agents:agents ?: @[] sessions:[MMSessions.shared all] ?: @[]
                     worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

/// The source a cold run reads: the one a test set, else the graph's, else one MMColdFacts the graph gets too.
static id<MMFactSource> ColdSource(void) {
    if (gCLISource) return gCLISource;
    @synchronized (MMGraph.shared) {
        if (!MMGraph.shared.source) MMGraph.shared.source = [MMColdFacts new];
        return MMGraph.shared.source;
    }
}

static uint64_t NextGeneration(void) {
    static uint64_t gen; static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    uint64_t g = ++gen;
    os_unfair_lock_unlock(&lock);
    return g;
}

static MMSnapshot *ColdSnapshot(id<MMFactSource> src) {
    MMFacts *facts = [src factsFor:NextGeneration()];
    NSMutableDictionary *reviews = [NSMutableDictionary new];
    for (id<MMExpert> e in MMExperts()) {
        MMReview *r = [MMReview lastFor:e.expertID];
        if (r) reviews[e.expertID] = r;
    }
    return [MMSnapshot snapshotFrom:facts experts:MMExperts() reviews:reviews holds:nil];
}

MMSnapshot *MMCLISnapshot(BOOL inApp) {
    if (inApp) {
        MMSnapshot *s = MMGraph.shared.latest;
        if (s) return s;
    }
    return ColdSnapshot(ColdSource());
}

MMSnapshot *MMCLISettledSnapshot(BOOL inApp) {
    if (inApp) {
        MMSnapshot *s = MMGraph.shared.latest;
        if (s) return s;
    }
    id<MMFactSource> src = ColdSource();
    // Every expert sees the first sample, so it can count what changed by the second, such as LocoHost's connections.
    [MMSnapshot snapshotFrom:[src factsFor:NextGeneration()] experts:MMExperts() reviews:nil holds:nil];
    [NSThread sleepForTimeInterval:1.0];
    return ColdSnapshot(src);
}

void MMOnMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_sync(dispatch_get_main_queue(), block);
}

id MMJSONSafe(id v) {
    if (!v || v == NSNull.null) return NSNull.null;
    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) return v;
    if ([v isKindOfClass:NSDate.class]) return @(round([v timeIntervalSince1970]));
    if ([v isKindOfClass:NSURL.class]) return [v absoluteString];
    if ([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSSet.class]) {
        NSMutableArray *a = [NSMutableArray new];
        for (id x in v) [a addObject:MMJSONSafe(x)];
        return a;
    }
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d = [NSMutableDictionary new];
        [v enumerateKeysAndObjectsUsingBlock:^(id k, id x, BOOL *stop) { d[[k description]] = MMJSONSafe(x); }];
        return d;
    }
    return [v description];
}

#pragma mark - Running a verb

/// The words with the legacy alias applied when the verb is not a registered one.
/// A legacy program asks its own expert first, then its 1.x aliases, so `locohost where 3000` keeps its old
/// meaning although 2.0 has a where verb too. minmacs tries its 2.0 verbs before the 1.x aliases.
static NSArray<NSString *> *Resolve(NSString *program, NSArray<NSString *> *words, MMVerbSpec **spec) {
    NSString *own = ExpertOfProgram(program);
    MMVerbSpec *v = nil;
    if (own) for (MMVerbSpec *x in ExpertVerbs(MMExpertNamed(own))) if ([x.verb isEqualToString:words.firstObject]) v = x;
    NSArray *alias = v ? nil : MMLegacyWords(program, words);
    if (alias && (own || !MMFindVerb(program, words.firstObject))) words = alias;
    *spec = v ?: MMFindVerb(program, words.firstObject);
    return words;
}

static int Run(MMVerbSpec *spec, NSArray<NSString *> *words, NSString *program, NSString *cwd, BOOL inApp,
               NSMutableString *out, NSMutableString *err) {
    MMArgs *args = [MMArgs verb:spec.verb words:[words subarrayWithRange:NSMakeRange(1, words.count - 1)] usage:spec.usage];
    args.program = program; args.inApp = inApp; args.outBuffer = out; args.errBuffer = err;
    if (cwd.length) args.cwd = cwd;
    // A verb that changes things runs in the app. With --dry-run it only reads, so it runs anywhere.
    if (spec.mutates && !args.dryRun && !inApp) return [args needsApp];
    if (!spec.run) return MMExitFailed;
    @autoreleasepool { return spec.run(args); }
}

NSDictionary *MMCLIReply(NSDictionary *request) {
    NSArray *words = request[@"cli"];
    if (![words isKindOfClass:NSArray.class] || !words.count) return nil;
    for (id w in words) if (![w isKindOfClass:NSString.class]) return @{@"status": @(MMExitUsage), @"out": @"", @"err": @"bad request\n"};
    NSString *program = [request[@"program"] isKindOfClass:NSString.class] ? request[@"program"] : @"minmacs";
    NSString *cwd = [request[@"cwd"] isKindOfClass:NSString.class] ? request[@"cwd"] : nil;
    MMVerbSpec *spec = nil;
    words = Resolve(program, words, &spec);
    NSMutableString *out = [NSMutableString new], *err = [NSMutableString new];
    int status;
    // A hidden verb, such as the worker of P4, runs only in the process that was started for it, never in the app.
    if (spec && [spec.verb hasPrefix:@"_"]) spec = nil;
    if (!spec) { [err appendFormat:@"%@: unknown verb '%@'. Try '%@ help'.\n", program, words.firstObject, program]; status = MMExitUsage; }
    else status = Run(spec, words, program, cwd, YES, out, err);
    return @{@"status": @(status), @"out": out, @"err": err, @"inApp": @YES};
}

int MMRunCLI(int argc, const char *argv[]) {
    NSString *program = MMProgramName(argv[0]);
    NSMutableArray<NSString *> *words = [NSMutableArray new];
    for (int i = 1; i < argc; i++) [words addObject:@(argv[i])];
    if (!words.count) [words addObject:@""];
    if ([words[0] isEqualToString:@"--version"]) words[0] = @"version";
    if ([words[0] isEqualToString:@"--help"] || [words[0] isEqualToString:@"-h"]) words[0] = @"help";

    MMVerbSpec *spec = nil;
    NSArray *resolved = Resolve(program, words, &spec);
    if (!spec) {
        fprintf(stderr, "%s: unknown verb '%s'. Try '%s help'.\n", program.UTF8String, [words[0] UTF8String], program.UTF8String);
        return MMExitUsage;
    }
    NSString *cwd = NSFileManager.defaultManager.currentDirectoryPath;
    // Ask the running app first. MINMACS_COLD=1 skips it, for scripts that want Core cold.
    BOOL cold = [NSProcessInfo.processInfo.environment[@"MINMACS_COLD"] isEqualToString:@"1"];
    if (!RunsHere(spec.verb) && !cold && [[MMCoreSocket ask:@{@"verb": @"ping"} timeout:0.2][@"ok"] boolValue]) {
        NSDictionary *r = [MMCoreSocket ask:@{@"verb": @"cli", @"cli": words, @"program": program, @"cwd": cwd ?: @""} timeout:600];
        if ([r[@"status"] isKindOfClass:NSNumber.class]) {
            NSString *o = r[@"out"], *e = r[@"err"];
            if ([o isKindOfClass:NSString.class]) fputs(o.UTF8String, stdout);
            if ([e isKindOfClass:NSString.class]) fputs(e.UTF8String, stderr);
            return [r[@"status"] intValue];
        }
        // The app answered the ping and then not the verb. Running cold could repeat a change, so stop here.
        fprintf(stderr, "%s: MinMacs did not answer. Try again, or set MINMACS_COLD=1 to run without it.\n", program.UTF8String);
        return MMExitFailed;
    }
    return Run(spec, resolved, program, cwd, NO, nil, nil);
}
