// The test tool of test/device.sh and test/quiet.sh. Built with all of Core, the kit, the CLI and the experts under
// -DMM_TESTS, it stands in for the app: a verb runs as one handed over core.sock, so `quiet hold` runs here, and this
// process keeps the hold's assertions. It reads and acts only on fixtures the test made inside $MINMACS_HOME.
//   tool cli <words...>                  one verb through MMCLIReply, off main, as the app runs it
//   tool hold <pid> <reason> [seconds]   `quiet hold <pid> --reason <reason>`, then waits until this process keeps no
//                                        hold, at most seconds (60), and prints "held <rid>" and then "ended"
//   tool auto <expert> <port|path> [--by <who>] [--dry]
//                                        a mode's run on one fixture finding of locohost or noonoo: an Eager review that
//                                        says go, the mode set to eager, then MMPlan and, unless --dry, MMRunAction as
//                                        <who> (eager by default). Prints {found, act, why, ran, error} as JSON
//   tool _walk                           the size worker's child, which the clutter scan starts
//   tool device <facts.json>             `device --json` with the power facts and displays the file names: its "power"
//                                        holds MMPower keys, its "displays" MMDisplay keys, its "prefs" prefs to set
// The facts a cold snapshot reads come from this tool: a sample taken now, no sessions, no worktrees, and the clutter
// of a scan of $MINMACS_CLUTTER_ROOT. The power facts come from a fake power source when a command names them.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/NooNoo/MMNooNoo.h"

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
}

#pragma mark Fakes

@interface TSource : NSObject <MMFactSource>
@end
@implementation TSource
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    return [MMFacts generation:generation sample:s power:MMSenses.shared.power agents:@[] sessions:@[] worktrees:@[]
                       clutter:MMClutterCatalog.shared.items ?: @[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

static NSDictionary *gPower;
@interface TPower : NSObject <MMPowerSource>
@end
@implementation TPower
- (MMPower *)read { return MMPowerFrom(gPower ?: @{}); }
@end

#pragma mark Commands

static int Cli(NSArray<NSString *> *words) {
    NSDictionary *r = MMCLIReply(@{@"cli": words, @"program": @"minmacs", @"cwd": NSFileManager.defaultManager.currentDirectoryPath});
    fputs([r[@"out"] UTF8String] ?: "", stdout);
    fputs([r[@"err"] UTF8String] ?: "", stderr);
    fflush(stdout);
    return [r[@"status"] intValue];
}

static int Hold(NSString *pid, NSString *reason, NSTimeInterval most) {
    NSDictionary *r = MMCLIReply(@{@"cli": @[@"quiet", @"hold", pid, @"--reason", reason, @"--json"], @"program": @"minmacs"});
    if ([r[@"status"] intValue] != 0) { fputs([r[@"err"] UTF8String] ?: "", stderr); return [r[@"status"] intValue]; }
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:[r[@"out"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    printf("held %s\n", [j[@"rid"] description].UTF8String);
    fflush(stdout);
    // The hold ends on the pid's exit or on a release from any process. Until then this process keeps the assertions.
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:most];
    while (MMQuietKept().count && end.timeIntervalSinceNow > 0) usleep(100000);
    usleep(300000);
    printf("%s\n", MMQuietKept().count ? "timeout" : "ended");
    fflush(stdout);
    return 0;
}

static MMReview *GoReview(NSString *expert, MMFinding *f) {
    MMVerdict *v = [MMVerdict new];
    v.kind = MMVerdictGo; v.word = @"go"; v.confidence = 1; v.findingID = f.findingID; v.fingerprint = f.fingerprint;
    v.instanceKey = f.instanceKey; v.reason = @"the test's review lets it go"; v.decidedBy = @"model"; v.madeAt = NSDate.date;
    MMReview *r = [MMReview new];
    r.expert = expert; r.trigger = @"manual"; r.at = NSDate.date; r.mode = MMModeEager; r.verdicts = @{f.findingID: v};
    return r;
}

static int Auto(NSString *expert, NSString *what, NSString *by, BOOL dry) {
    id<MMExpert> e = [expert isEqualToString:@"locohost"] ? (id<MMExpert>)MMLocoHost.shared : (id<MMExpert>)MMNooNooExpert.shared;
    if ([expert isEqualToString:@"noonoo"]) {
        if (!MMClutterRoot().length) { fprintf(stderr, "tool: MINMACS_CLUTTER_ROOT must lie in MINMACS_HOME\n"); return 9; }
        [MMClutterCatalog.shared forgetScanTimes];
        NSUInteger scanned = [MMClutterCatalog.shared scan].count;
        if (Env(@"DQ_DEBUG")) fprintf(stderr, "scan: %lu items, home %s\n", (unsigned long)scanned, MMClutterHome().UTF8String);
    }
    // A mode acts only once MinMacs watched for a day, in the mode set, after a review.
    [[NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970 - 2 * 86400]
        writeToFile:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    MMSetPref([expert stringByAppendingString:@".mode"], @"eager");
    MMSnapshot *s = MMCLISettledSnapshot(NO);
    MMFinding *f = nil;
    for (MMFinding *x in [s findingsFor:expert]) {
        if ([expert isEqualToString:@"locohost"] && [x.facts[@"ports"] containsObject:@(what.integerValue)]) f = x;
        if ([expert isEqualToString:@"noonoo"] && [x.facts[@"path"] isEqual:what]) f = x;
    }
    if (!f) {
        NSMutableArray *seen = [NSMutableArray new];
        for (MMFinding *x in [s findingsFor:expert]) [seen addObject:[NSString stringWithFormat:@"%@ %@", x.facts[@"path"] ?: @"", x.facts[@"ports"] ?: @""]];
        PrintJSON(@{@"found": @NO, @"seen": seen, @"clutter": @(s.facts.clutter.count)});
        return 1;
    }
    MMReview *r = GoReview(expert, f);
    MMPlanEntry *p = MMPlan(@[f], s.facts, r, MMModeEager, [e policy]).firstObject;
    NSMutableDictionary *out = [@{@"found": @YES, @"act": @(p.act), @"why": p.why ?: @"", @"ran": @NO} mutableCopy];
    if (!dry) {
        NSString *err = nil;
        MMUndoRecord *rec = MMRunAction([e actionFor:f step:MMStopTerm], [e policy], [by isEqualToString:@"manual"] ? nil : r, by, p.why, &err);
        out[@"ran"] = @((BOOL)(rec.state == MMUndoDone));
        out[@"error"] = err ?: rec.error ?: NSNull.null;
    }
    PrintJSON(out);
    return 0;
}

static int Device(NSString *path) {
    NSDictionary *facts = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: [NSData data] options:0 error:nil];
    if (![facts isKindOfClass:NSDictionary.class]) { fprintf(stderr, "tool: %s holds no JSON object\n", path.UTF8String); return 2; }
    gPower = facts[@"power"];
    if (gPower) MMUsePowerSource([TPower new]);
    if (facts[@"displays"]) MMUseDisplays(facts[@"displays"]);
    NSDictionary *prefs = facts[@"prefs"];
    for (NSString *k in prefs) MMSetPref(k, prefs[k]);
    return Cli(@[@"device", @"--json"]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: tool cli|hold|auto|device ...\n"); return 2; }
        // The clutter scan sizes folders in a child of this same binary, as the app does.
        if (!strcmp(argv[1], "_walk")) return MMWorkerChildMain();
        if (!Env(@"MINMACS_HOME").length) { fprintf(stderr, "tool: MINMACS_HOME must be set\n"); return 9; }
        NSMutableArray<NSString *> *args = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        MMRegisterExpert(MMLocoHost.shared);
        MMRegisterExpert(MMNooNooExpert.shared);
        TSource *src = [TSource new];
        MMSetCLIFactSource(src);
        MMGraph.shared.source = src;
        // Every action refuses on main, as in the app, so the command runs on a queue and main waits.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            int status = 2;
            @autoreleasepool {
                NSString *cmd = args[0];
                if ([cmd isEqualToString:@"cli"] && args.count > 1) status = Cli([args subarrayWithRange:NSMakeRange(1, args.count - 1)]);
                else if ([cmd isEqualToString:@"hold"] && args.count >= 3) status = Hold(args[1], args[2], args.count > 3 ? args[3].doubleValue : 60);
                else if ([cmd isEqualToString:@"auto"] && args.count >= 3) {
                    NSUInteger i = [args indexOfObject:@"--by"];
                    status = Auto(args[1], args[2], i != NSNotFound && i + 1 < args.count ? args[i + 1] : @"eager", [args containsObject:@"--dry"]);
                }
                else if ([cmd isEqualToString:@"device"] && args.count == 2) status = Device(args[1]);
                else fprintf(stderr, "tool: unknown command %s\n", cmd.UTF8String);
            }
            fflush(stdout);
            exit(status);
        });
        dispatch_main();
    }
}
