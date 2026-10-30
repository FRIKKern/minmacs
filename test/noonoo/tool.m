// Noo-Noo's test tool. test/noonoo.sh builds it with all of Core, the kit, the CLI's MMArgs and the expert, under -DMM_TESTS.
// It runs as the app does for a handed-over verb: MMArgs says inApp, so a verb that changes things runs here.
// Every path it reads or acts on sits under $MINMACS_CLUTTER_ROOT or $MINMACS_HOME, which the test made:
// MMClutterRoot refuses a root outside MINMACS_HOME, and MMClutterToolPath runs only the fakes in $MINMACS_TOOLS.
//   tool verb <clutter|clean> [words...]          one verb, as `minmacs <verb>` runs it
//   tool scan                                     every row now, then the item count
//   tool walls <dir>                              every path under dir that the walls let through, one per line
//   tool record <kind> <days> <from> <to>         a recorded trend: one point a day for days back, today left out
//   tool points <kind>                            how many points the log holds for the row
//   tool modes                                    each actionable finding: row, section, and whether Proactive and Eager take it
//   tool undo                                     Noo-Noo's undo records as JSON
//   tool render <folder>                          the menu and cards to PNG in four appearances, plus checks.txt
//   tool ask <path> <by>                          the row's own command for the item at path, through MMRunAction as by asks;
//                                                 NN_CMD_TIMEOUT sets its time limit. Prints the record as JSON, or the refusal
//   tool freed <text>                             what MMClutterFreedFromOutput reads from text
// NN_RUNNING_APPS names the bundle ids that count as running, comma separated, for the rows' quitFirst.
// NN_PROJECTS names the checkouts, colon separated. NN_MERGED names the worktree whose git facts say squash-merged.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "CLI/MMArgs.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

static NSArray<NSString *> *Projects(void) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in [Env(@"NN_PROJECTS") componentsSeparatedByString:@":"]) if (p.length) [out addObject:p];
    return out;
}

#pragma mark Facts

/// Worktrees and git facts as WorkForest will hand them over, made here, since git facts come in phase 2.
@interface TSource : NSObject <MMFactSource>
@end
@implementation TSource
- (MMFacts *)factsFor:(uint64_t)generation {
    NSMutableArray *trees = [NSMutableArray new];
    NSMutableDictionary *git = [NSMutableDictionary new];
    NSString *main = Projects().firstObject;
    for (NSString *p in Projects()) {
        MMWorktree *w = [MMWorktree new];
        [w setValue:p forKey:@"path"]; [w setValue:main forKey:@"repo"];
        [w setValue:@([p isEqualToString:main]) forKey:@"isMain"];
        [w setValue:p.lastPathComponent forKey:@"branch"];
        [trees addObject:w];
        MMGitFacts *g = [MMGitFacts new];
        [g setValue:@"0123456789abcdef" forKey:@"head"];
        [g setValue:@([p isEqualToString:Env(@"NN_MERGED")] ? MMMergedSquash : MMMergedNone) forKey:@"merged"];
        git[p] = g;
    }
    [MMSessions.shared refresh];
    return [MMFacts generation:generation sample:nil power:nil agents:@[] sessions:MMSessions.shared.all ?: @[]
                     worktrees:trees clutter:MMClutterCatalog.shared.items git:git];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

#pragma mark Render

static int Render(NSString *out) {
    [NSApplication sharedApplication];
    [NSFileManager.defaultManager createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
    MMNooNooExpert *e = MMNooNooExpert.shared;
    MMSnapshot *s = [e snapshotNow];
    (void)[e findingsFrom:s.facts];   // the growth threshold pref and the undo list, as a rebuild reads them
    MMMenuSpec *spec = [e menuFor:s];
    NSMutableDictionary<NSString *, MMCardSpec *> *cards = [NSMutableDictionary new];
    for (MMFinding *f in [s findingsFor:@"noonoo"]) cards[f.findingID] = [e cardFor:f snapshot:s];
    NSMenu *menu = MMMenuFromSpec(spec, ^MMCardSpec *(NSString *fid) { return cards[fid]; }, nil, nil);
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *p in MMMenuProblems(menu)) [lines addObject:[@"FAIL menu: " stringByAppendingString:p]];
    // One card per section, named by the row it hangs under.
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary new];
    for (MMSectionSpec *sec in spec.sections) {
        MMRowSpec *r = sec.rows.firstObject;
        if (r.findingID) names[r.findingID] = [[sec.title componentsSeparatedByString:@" "].firstObject lowercaseString];
    }
    for (NSString *fid in names) for (NSString *p in [MMCardFromSpec(cards[fid]) layoutProblems]) [lines addObject:[NSString stringWithFormat:@"FAIL card %@: %@", names[fid], p]];
    NSDictionary<NSString *, NSAppearance *> *aps = MMRenderAppearances();
    BOOL first = YES;
    for (NSString *mode in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        NSAppearance *ap = aps[mode];
        if (!ap) { [lines addObject:[@"FAIL appearance missing: " stringByAppendingString:mode]]; continue; }
        NSArray *cut = MMRenderMenu(menu, [out stringByAppendingFormat:@"/noonoo-menu-%@.png", mode], ap);
        if (!cut) [lines addObject:@"FAIL menu PNG not written"];
        if (first && cut.count) [lines addObject:[@"FAIL menu cut off: " stringByAppendingString:[cut componentsJoinedByString:@", "]]];
        for (NSString *fid in names) {
            NSMenu *cm = [MMCardFromSpec(cards[fid]) menu];
            cut = MMRenderMenu(cm, [out stringByAppendingFormat:@"/noonoo-card-%@-%@.png", names[fid], mode], ap);
            if (!cut) [lines addObject:[@"FAIL card PNG not written: " stringByAppendingString:names[fid]]];
            if (first && cut.count) [lines addObject:[NSString stringWithFormat:@"FAIL card %@ cut off: %@", names[fid], [cut componentsJoinedByString:@", "]]];
        }
        first = NO;
    }
    [lines addObject:[NSString stringWithFormat:@"TEXT header %@ %@ | %@", spec.headerBig, spec.headerUnit, spec.headerLine]];
    [lines addObject:[@"TEXT summary " stringByAppendingString:spec.summary ?: @""]];
    for (MMActionSpec *a in spec.actions) [lines addObject:[NSString stringWithFormat:@"TEXT action %@ | %@", a.title, a.tail ?: @""]];
    for (MMSectionSpec *sec in spec.sections) {
        [lines addObject:[@"TEXT section " stringByAppendingString:sec.title]];
        for (MMRowSpec *row in sec.rows) [lines addObject:[NSString stringWithFormat:@"TEXT row %@ | %@ | %ld", row.name, [row.facts componentsJoinedByString:@" · "], (long)row.mark]];
    }
    for (MMActionSpec *a in spec.more) [lines addObject:[NSString stringWithFormat:@"TEXT more %@ | %@", a.title, a.tail ?: @""]];
    for (NSString *fid in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        MMCardSpec *c = cards[fid];
        [lines addObject:[NSString stringWithFormat:@"TEXT card %@ | %@ | %@ %@", names[fid], c.title, c.statusWord, c.statusText]];
        for (MMCardFact *f in c.facts) [lines addObject:[NSString stringWithFormat:@"TEXT fact %@ | %@ | %@", names[fid], f.label, f.value]];
        for (MMActionSpec *a in c.actions) [lines addObject:[NSString stringWithFormat:@"TEXT cardaction %@ | %@ | %@", names[fid], a.title, a.disabledReason ?: @""]];
    }
    [lines addObject:[@"TEXT a11y " stringByAppendingString:[e accessibilityStateFor:s]]];
    [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:[out stringByAppendingPathComponent:@"checks.txt"]
                                                                                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: tool <command> ...\n"); return 2; }
        NSMutableArray<NSString *> *args = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        NSString *cmd = args[0];
        if (!Env(@"MINMACS_HOME").length || !MMClutterRoot().length) { fprintf(stderr, "tool: MINMACS_HOME and MINMACS_CLUTTER_ROOT inside it must be set\n"); return 9; }
        MMClutterCatalog *c = MMClutterCatalog.shared;
        c.projects = Projects();
        MMNooNooExpert *e = MMNooNooExpert.shared;
        MMGraph.shared.source = [TSource new];
        MMStartWatching();
        if (Env(@"NN_RUNNING_APPS")) {
            NSArray *apps = [Env(@"NN_RUNNING_APPS") componentsSeparatedByString:@","];
            MMClutterUseRunningApps(^NSArray<NSString *> *{ return apps; });
        }

        if ([cmd isEqualToString:@"render"]) return args.count > 1 ? Render(args[1]) : 2;
        if ([cmd isEqualToString:@"verb"] && args.count > 1) {
            for (MMVerbSpec *v in e.verbs) if ([v.verb isEqualToString:args[1]]) {
                MMArgs *a = [MMArgs verb:v.verb words:[args subarrayWithRange:NSMakeRange(2, args.count - 2)] usage:v.usage];
                a.inApp = YES; a.program = @"minmacs"; a.cwd = NSFileManager.defaultManager.currentDirectoryPath;
                return v.run(a);
            }
            fprintf(stderr, "tool: no verb %s\n", args[1].UTF8String);
            return 2;
        }
        if ([cmd isEqualToString:@"scan"]) {
            [c forgetScanTimes];
            printf("%lu\n", (unsigned long)[c scan].count);
            return 0;
        }
        if ([cmd isEqualToString:@"walls"] && args.count > 1) {
            NSDirectoryEnumerator *en = [NSFileManager.defaultManager enumeratorAtPath:args[1]];
            NSString *rel;
            while ((rel = [en nextObject])) {
                NSString *p = [args[1] stringByAppendingPathComponent:rel];
                if (![c whyNot:p kind:nil]) printf("%s\n", p.UTF8String);
            }
            return 0;
        }
        if ([cmd isEqualToString:@"record"] && args.count > 4) {
            NSInteger days = args[2].integerValue;
            double from = args[3].doubleValue, to = args[4].doubleValue;
            NSDate *now = NSDate.date;
            for (NSInteger d = days; d >= 1; d--) {
                double v = from + (to - from) * (double)(days - d) / (double)MAX(1, days - 1);
                [MMLog.shared addPoint:MMClutterSeries(args[1]) value:v at:[now dateByAddingTimeInterval:-86400.0 * d] bucket:86400];
            }
            return 0;
        }
        if ([cmd isEqualToString:@"points"] && args.count > 1) {
            printf("%lu\n", (unsigned long)([MMLog.shared points:MMClutterSeries(args[1]) since:nil].length / sizeof(MMTrendPoint)));
            return 0;
        }
        if ([cmd isEqualToString:@"modes"]) {
            // For each finding with an action: its row, its section, and whether Proactive and Eager may take it.
            id<MMExpertPolicy> pol = MMNNPolicy();
            for (MMFinding *f in [[e snapshotNow] findingsFor:@"noonoo"]) {
                if (!f.proposal) continue;
                printf("%s %s %s %s\n", [f.facts[@"kindID"] UTF8String], [f.facts[@"section"] UTF8String],
                       [pol modeKeeps:f mode:MMModeProactive review:nil] ? "keep" : "go", [pol modeKeeps:f mode:MMModeEager review:nil] ? "keep" : "go");
            }
            return 0;
        }
        if ([cmd isEqualToString:@"freed"] && args.count > 1) {
            printf("%lld\n", (long long)MMClutterFreedFromOutput([[args subarrayWithRange:NSMakeRange(1, args.count - 1)] componentsJoinedByString:@" "]));
            return 0;
        }
        if ([cmd isEqualToString:@"ask"] && args.count > 2) {
            MMFinding *f = nil;
            for (MMFinding *x in [[e snapshotNow] findingsFor:@"noonoo"]) if ([x.facts[@"path"] isEqual:args[1]]) f = x;
            MMClutterCommandAction *act = f ? [e commandFor:f by:args[2]] : nil;
            if (!act) { fprintf(stderr, "tool: no command for %s\n", args[1].UTF8String); return 1; }
            if (Env(@"NN_CMD_TIMEOUT")) act.timeout = Env(@"NN_CMD_TIMEOUT").doubleValue;
            __block MMUndoRecord *r = nil;
            __block NSString *err = nil;
            dispatch_group_t g = dispatch_group_create();
            dispatch_group_async(g, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                r = MMRunAction(act, MMNNPolicy(), nil, args[2], @"asked by the test", &err);
            });
            dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
            if (!r) { printf("refused: %s\n", err.UTF8String); return 1; }
            PrintJSON(@{@"rid": r.rid, @"kind": r.kind ?: @"", @"state": @[@"pending", @"done", @"failed", @"restored"][r.state],
                        @"error": r.error ?: @"", @"canRestore": @(r.canRestore), @"payload": r.payload ?: @{}});
            return r.state == MMUndoDone ? 0 : 1;
        }
        if ([cmd isEqualToString:@"undo"]) {
            NSMutableArray *out = [NSMutableArray new];
            for (MMUndoRecord *r in [MMUndo.shared recent:@"noonoo" limit:100])
                [out addObject:@{@"rid": r.rid, @"kind": r.kind ?: @"", @"state": @[@"pending", @"done", @"failed", @"restored"][r.state],
                                 @"findingID": r.findingID ?: @"", @"by": r.by ?: @"", @"payload": r.payload ?: @{}, @"error": r.error ?: @"",
                                 @"canRestore": @(r.canRestore), @"freedBytes": @(r.freedBytes)}];
            PrintJSON(out);
            return 0;
        }
        fprintf(stderr, "tool: unknown command %s\n", cmd.UTF8String);
        return 2;
    }
}
