// The MinMacs expert's test tool. test/minmacs.sh builds it with all of Core, the kit and the expert, under -DMM_TESTS.
// It runs Core cold, as the CLI does: a fact source reads Senses, the registry with the fixture rows only,
// and the sessions under the test's agent homes. The expert's verbs run through their MMVerbSpec blocks.
//   tool verb <apps|status|restore> [words...]   one verb, as `minmacs <verb>` runs it
//   tool stale <bundle-id> <seconds>              snapshot, wait, then quit with the old snapshot's finding
//   tool plan <mode>                              MMPlan over the fixture apps, with a review the list rule made
//   tool list <list> | verdict <id> | serving <id> | undo | render <folder>
//   tool localtab <url>                           yes or no for a localhost host, then the URL's port
// Safety: a verb that quits or trims runs only on a bundle id that starts with $MMM_ONLY, and never with --all.
// MMM_ROWS names the registry rows. MMM_TABS names the fake tab bridge's file, and MMM_BROWSER the fixture browser.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "Experts/MinMacs/MMMinMacs.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

#pragma mark Facts

@interface TSource : NSObject <MMFactSource>
@property (strong) MMRegistry *registry;
@end
@implementation TSource
- (MMFacts *)factsFor:(uint64_t)generation {
    MMSample *s = [MMSenses.shared sampleNow];
    MMPower *p = Env(@"MMM_PRESSURE") ? MMPowerFrom(@{@"memoryPressure": @(Env(@"MMM_PRESSURE").integerValue)}) : MMSenses.shared.power;
    NSArray *agents = self.registry ? [self.registry agentsIn:s power:p] : @[];
    [MMSessions.shared refresh];
    return [MMFacts generation:generation sample:s power:p agents:agents ?: @[] sessions:MMSessions.shared.all ?: @[]
                     worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

#pragma mark The fake tab bridge

/// Tabs live in a JSON file the test writes: {"tabs": [{pid, window, id, url, title, mode}], "closed": [], "opened": []}.
/// moveHost makes the tab on that host navigate away right before it would close, as a person might.
@interface TBridge : NSObject <MMMinMacsTabBridge>
@property (copy) NSString *path, *moveHost;
@end
@implementation TBridge
- (NSMutableDictionary *)load {
    NSData *d = [NSData dataWithContentsOfFile:self.path];
    NSMutableDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![j isKindOfClass:NSMutableDictionary.class]) j = [NSMutableDictionary new];
    for (NSString *k in @[@"tabs", @"closed", @"opened"]) if (![j[k] isKindOfClass:NSMutableArray.class]) j[k] = [NSMutableArray new];
    return j;
}
- (void)save:(NSDictionary *)j {
    [[NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted error:nil] writeToFile:self.path atomically:YES];
}
static NSString *Host(NSString *url) {
    NSString *h = [NSURL URLWithString:url].host.lowercaseString ?: @"";
    return [h hasPrefix:@"www."] ? [h substringFromIndex:4] : h;
}
- (NSArray<MMMinMacsTab *> *)tabsOf:(pid_t)pid bundleID:(NSString *)bundleID error:(NSString **)error {
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *t in [self load][@"tabs"]) {
        if ([t[@"pid"] intValue] != pid || [t[@"mode"] isEqual:@"incognito"]) continue;
        MMMinMacsTab *x = [MMMinMacsTab new];
        x.url = t[@"url"]; x.title = t[@"title"] ?: t[@"url"]; x.host = Host(x.url);
        x.windowID = [t[@"window"] integerValue]; x.tabID = [t[@"id"] integerValue];
        [out addObject:x];
    }
    return out;
}
- (NSArray<MMMinMacsTab *> *)close:(NSArray<MMMinMacsTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bundleID {
    NSMutableDictionary *j = [self load];
    NSMutableArray *closed = [NSMutableArray new];
    for (MMMinMacsTab *t in tabs) {
        for (NSMutableDictionary *e in [j[@"tabs"] copy]) {
            if ([e[@"pid"] intValue] != pid || [e[@"window"] integerValue] != t.windowID || [e[@"id"] integerValue] != t.tabID) continue;
            if (self.moveHost && [Host(e[@"url"]) isEqualToString:self.moveHost]) e[@"url"] = @"https://moved.example.org/";
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
    [j[@"opened"] addObjectsFromArray:urls];
    [self save:j];
    return nil;
}
@end

#pragma mark Drawing specs with the kit

/// The menu as the app draws it, through Sources/UI/MMSpecMenu, and each row's card, for the layout checks and the PNGs.
static NSMenu *MenuFrom(MMMenuSpec *m, MMSnapshot *s, id<MMExpert> e, NSMutableDictionary<NSString *, MMCard *> *cards,
                        NSMutableDictionary<NSString *, NSMenu *> *cardMenus) {
    MMCardProvider provider = ^MMCardSpec *(NSString *fid) { MMFinding *f = [s finding:fid]; return f ? [e cardFor:f snapshot:s] : nil; };
    for (MMSectionSpec *sec in m.sections) for (MMRowSpec *r in sec.rows) {
        MMCardSpec *c = r.findingID ? provider(r.findingID) : nil;
        if (!c) continue;
        cards[r.findingID] = MMCardFromSpec(c);
        cardMenus[r.findingID] = [cards[r.findingID] menu];
    }
    return MMMenuFromSpec(m, provider, nil, nil);
}

#pragma mark The render fixture

static MMMinMacsApp *App(pid_t pid, NSString *name, NSString *bid, uint64_t mb, double cpu, double energy, NSInteger procs) {
    MMMinMacsApp *a = [MMMinMacsApp new];
    a.name = name; a.bundleID = bid; a.memory = mb << 20; a.cpuPercent = cpu; a.energyRank = energy; a.processCount = procs;
    a.pid = pid; a.startSec = 1761000000; a.pids = @[@(a.pid)];
    return a;
}

static MMMinMacsInput *FixtureInput(MMFacts *facts) {
    MMMinMacsInput *in = [MMMinMacsInput new];
    MMMinMacsApp *figma = App(4204, @"Figma", @"com.figma.Desktop", 1130, 9, 0.4, 6);
    figma.agentName = @"Claude Code";
    MMMinMacsApp *notion = App(4205, @"Notion", @"notion.id", 640, 1, 0.1, 5);
    notion.loopbackPorts = @[@51789];
    in.apps = @[App(4200, @"Spotify", @"com.spotify.client", 1310, 6, 0.6, 9), App(4201, @"Slack", @"com.tinyspeck.slackmacgap", 820, 2, 0.2, 7),
                App(4202, @"Photos", @"com.apple.Photos", 410, 0, 0, 3), App(4203, @"Google Chrome", @"com.google.Chrome", 2450, 18, 1.0, 31),
                figma, notion, App(4206, @"Terminal", @"com.apple.Terminal", 210, 1, 0.05, 2), App(4207, @"Xcode", @"com.apple.dt.Xcode", 1900, 3, 0.3, 4),
                App(4208, @"Linear", @"com.linear", 300, 0, 0.02, 4)];
    MMMinMacsAgent *claude = [MMMinMacsAgent new];
    claude.name = @"Claude Code"; claude.harnessID = @"claude-code"; claude.sessionID = @"fixture-1";
    claude.project = [NSHomeDirectory() stringByAppendingPathComponent:@"code/acme-web"]; claude.why = @"status file busy";
    claude.state = MMAgentWorking; claude.key = (MMProcKey){ 5100, 1761000100 }; claude.memory = 720ull << 20; claude.cpuPercent = 14;
    MMMinMacsAgent *codex = [MMMinMacsAgent new];
    codex.name = @"Codex"; codex.harnessID = @"codex"; codex.sessionID = @"fixture-2";
    codex.project = [NSHomeDirectory() stringByAppendingPathComponent:@"code/orbit-api"]; codex.why = @"newest turn completed";
    codex.state = MMAgentIdle; codex.key = (MMProcKey){ 5200, 1761000200 }; codex.memory = 180ull << 20;
    in.agents = @[claude, codex];
    in.memoryPressure = facts.power.memoryPressure ?: 1;
    in.thermal = NSProcessInfoThermalStateNominal;
    return in;
}

static int Render(NSString *out) {
    [NSApplication sharedApplication];
    [NSFileManager.defaultManager createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
    MMMinMacsExpert *e = MMMinMacsExpert.shared;
    e.inputFrom = ^MMMinMacsInput *(MMFacts *f) { return FixtureInput(f); };
    // Slack was asked to quit and did not, and Music was quit an hour ago, so Force Quit and Restore show.
    MMUndoRecord *r = [MMUndo.shared begin:@"minmacs" kind:@"quit" finding:@"minmacs:app:com.tinyspeck.slackmacgap" subject:@"Slack"
                                       why:@"fixture" by:@"manual" parent:nil payload:@{@"relaunch": @{@"bundleID": @"com.tinyspeck.slackmacgap", @"pid": @"4201:1761000000"}}];
    [MMUndo.shared finish:r ok:NO freed:0 error:@"it did not quit"];
    r = [MMUndo.shared begin:@"minmacs" kind:@"quit" finding:@"minmacs:app:com.apple.Music" subject:@"Music"
                         why:@"fixture" by:@"manual" parent:nil payload:@{@"relaunch": @{@"bundleID": @"com.apple.Music", @"pid": @"4100:1761000000"}}];
    [MMUndo.shared finish:r ok:YES freed:0 error:nil];
    MMFacts *facts = [MMFacts generation:1 sample:nil power:MMPowerFrom(@{@"memoryPressure": @2}) agents:@[] sessions:@[] worktrees:@[] clutter:@[] git:@{}];
    MMSnapshot *s = [MMSnapshot snapshotFrom:facts experts:@[e] reviews:nil holds:nil];
    NSMutableDictionary *cards = [NSMutableDictionary new], *cardMenus = [NSMutableDictionary new];
    // The snapshot was built above, on this thread, as the graph queue builds it. The menu and the cards then read
    // only what it holds: no query of the undo log runs on main while they are drawn.
    NSUInteger queries = MMLogMainThreadQueries();
    MMMenuSpec *spec = [e menuFor:s];
    NSMenu *menu = MenuFrom(spec, s, e, cards, cardMenus);
    (void)[e badgeFor:s]; (void)[e accessibilityStateFor:s];
    queries = MMLogMainThreadQueries() - queries;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *p in MMMenuProblems(menu)) [lines addObject:[@"FAIL menu: " stringByAppendingString:p]];
    for (NSString *k in cards) for (NSString *p in [cards[k] layoutProblems]) [lines addObject:[NSString stringWithFormat:@"FAIL card %@: %@", k, p]];
    NSDictionary *names = @{@"minmacs:app:com.spotify.client": @"spotify", @"minmacs:app:com.tinyspeck.slackmacgap": @"slack",
                            @"minmacs:app:com.google.Chrome": @"chrome", @"minmacs:app:com.figma.Desktop": @"figma",
                            @"minmacs:app:notion.id": @"notion", @"minmacs:agent:claude-code:fixture-1": @"agent"};
    NSDictionary<NSString *, NSAppearance *> *aps = MMRenderAppearances();
    BOOL first = YES;
    for (NSString *mode in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        NSAppearance *ap = aps[mode];
        if (!ap) { [lines addObject:[@"FAIL appearance missing: " stringByAppendingString:mode]]; continue; }
        NSArray *cut = MMRenderMenu(menu, [out stringByAppendingFormat:@"/minmacs-menu-%@.png", mode], ap);
        if (!cut) [lines addObject:@"FAIL menu PNG not written"];
        if (first && cut.count) [lines addObject:[@"FAIL menu cut off: " stringByAppendingString:[cut componentsJoinedByString:@", "]]];
        for (NSString *k in names) {
            if (!cardMenus[k]) { if (first) [lines addObject:[@"FAIL no card for " stringByAppendingString:k]]; continue; }
            cut = MMRenderMenu(cardMenus[k], [out stringByAppendingFormat:@"/minmacs-card-%@-%@.png", names[k], mode], ap);
            if (!cut) [lines addObject:[@"FAIL card PNG not written: " stringByAppendingString:names[k]]];
            if (first && cut.count) [lines addObject:[NSString stringWithFormat:@"FAIL card %@ cut off: %@", names[k], [cut componentsJoinedByString:@", "]]];
        }
        first = NO;
    }
    // The visible text, so the test can check words and the render check can be read without the PNGs.
    [lines addObject:[NSString stringWithFormat:@"TEXT header %@ %@ | %@", spec.headerBig, spec.headerUnit, spec.headerLine]];
    [lines addObject:[@"TEXT summary " stringByAppendingString:spec.summary]];
    for (MMActionSpec *a in spec.actions) [lines addObject:[NSString stringWithFormat:@"TEXT action %@ | %@", a.title, a.tail ?: @""]];
    for (MMSectionSpec *sec in spec.sections) {
        [lines addObject:[@"TEXT section " stringByAppendingString:sec.title]];
        for (MMRowSpec *row in sec.rows) [lines addObject:[NSString stringWithFormat:@"TEXT row %@ | %@ | %ld", row.name, [row.facts componentsJoinedByString:@" · "], (long)row.mark]];
    }
    for (MMActionSpec *a in spec.more) [lines addObject:[NSString stringWithFormat:@"TEXT more %@ | %@", a.title, a.tail ?: @""]];
    for (NSString *k in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        MMCardSpec *c = [e cardFor:[s finding:k] snapshot:s];
        [lines addObject:[NSString stringWithFormat:@"TEXT card %@ | %@ | %@ %@", names[k], c.title, c.statusWord, c.statusText]];
        for (MMCardFact *f in c.facts) [lines addObject:[NSString stringWithFormat:@"TEXT fact %@ | %@ | %@", names[k], f.label, f.value]];
        for (MMActionSpec *a in c.actions) [lines addObject:[NSString stringWithFormat:@"TEXT cardaction %@ | %@ | %@", names[k], a.title, a.disabledReason ?: @""]];
    }
    [lines addObject:[@"TEXT a11y " stringByAppendingString:[e accessibilityStateFor:s]]];
    [lines addObject:[NSString stringWithFormat:@"TEXT mainqueries %lu", (unsigned long)queries]];
    [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:[out stringByAppendingPathComponent:@"checks.txt"]
                                                                                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return 0;
}

#pragma mark Commands

static MMFinding *AppFinding(MMSnapshot *s, NSString *bid) {
    for (MMFinding *f in [s findingsFor:@"minmacs"]) if ([f.facts[@"bundleID"] isEqual:bid]) return f;
    return nil;
}

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: tool <command> ...\n"); return 2; }
        NSMutableArray<NSString *> *args = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        NSString *cmd = args[0];
        MMMinMacsExpert *e = MMMinMacsExpert.shared;
        if ([cmd isEqualToString:@"render"]) return args.count > 1 ? Render(args[1]) : 2;
        if ([cmd isEqualToString:@"localtab"] && args.count > 1) {
            printf("%s %ld\n", MMMinMacsIsLocalHost([NSURL URLWithString:args[1]].host) ? "yes" : "no", (long)MMMinMacsPortOf(args[1]));
            return 0;
        }

        TSource *src = [TSource new];
        if (Env(@"MMM_ROWS").length) src.registry = [[MMRegistry alloc] initWithRowDirectories:@[Env(@"MMM_ROWS")]];
        src.registry.holdSeconds = 0;
        MMGraph.shared.source = src;
        TBridge *bridge = nil;
        if (Env(@"MMM_TABS").length) { bridge = [TBridge new]; bridge.path = Env(@"MMM_TABS"); bridge.moveHost = Env(@"MMM_MOVE_HOST"); MMMinMacsUseTabBridge(bridge); }
        if (Env(@"MMM_BROWSER").length) MMMinMacsAddTestBrowser(Env(@"MMM_BROWSER"));
        NSString *only = Env(@"MMM_ONLY");

        if ([cmd isEqualToString:@"verb"] && args.count > 1) {
            NSArray *words = [args subarrayWithRange:NSMakeRange(2, args.count - 2)];
            NSMutableArray *plain = [NSMutableArray new];
            for (NSString *w in words) if (![w hasPrefix:@"--"]) [plain addObject:w];
            BOOL acts = [args[1] isEqualToString:@"apps"] && plain.count && [@[@"quit", @"trim"] containsObject:plain[0]];
            if (acts && (!only.length || [words containsObject:@"--all"] || plain.count < 2 || ![plain[1] hasPrefix:only])) {
                fprintf(stderr, "tool: quit and trim run only on a fixture bundle id that starts with $MMM_ONLY\n");
                return 9;
            }
            for (MMVerbSpec *v in e.verbs) if ([v.verb isEqualToString:args[1]]) return v.run(nil);
            fprintf(stderr, "tool: no verb %s\n", args[1].UTF8String);
            return 2;
        }
        if ([cmd isEqualToString:@"stale"] && args.count > 2) {
            if (!only.length || ![args[1] hasPrefix:only]) return 9;
            MMFinding *f = AppFinding([e snapshotNow], args[1]);
            if (!f) { printf("no finding\n"); return 1; }
            printf("old %s\n", f.instanceKey.UTF8String);
            fflush(stdout);
            [NSThread sleepForTimeInterval:args[2].doubleValue];
            __block MMUndoRecord *r = nil; __block NSString *err = nil;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                r = MMRunAction([e actionFor:f step:MMStopTerm], e.policy, nil, @"cli", @"stale test", &err);
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
            printf("%s\n", r ? "ran" : [@"refused: " stringByAppendingString:err ?: @""].UTF8String);
            return r ? 0 : 1;
        }
        if ([cmd isEqualToString:@"plan"] && args.count > 1) {
            MMSnapshot *s = [e snapshotNow];
            NSMutableArray *mine = [NSMutableArray new];
            for (MMFinding *f in [s findingsFor:@"minmacs"]) if (only.length && [f.facts[@"bundleID"] hasPrefix:only]) [mine addObject:f];
            MMReview *review = [MMReview new];
            review.expert = @"minmacs"; review.at = NSDate.date;
            NSMutableDictionary *verdicts = [NSMutableDictionary new];
            id<MMRule> rule = e.rules.firstObject;
            for (MMFinding *f in mine) { MMVerdict *v = [rule decide:f facts:s.facts]; if (v) verdicts[f.findingID] = v; }
            review.verdicts = verdicts;
            NSInteger mode = MMModeFrom(args[1]);
            for (MMPlanEntry *p in MMPlan(mine, s.facts, review, (MMMode)MAX(0, mode), e.policy))
                printf("%s\t%s\t%s\n", [p.finding.facts[@"bundleID"] UTF8String], p.act ? "act" : "keep", p.why.UTF8String);
            return 0;
        }
        MMMinMacsRules *rules = MMMinMacsRules.shared;
        if ([cmd isEqualToString:@"list"] && args.count > 1) {
            NSDictionary *lists = @{@"keep": rules.keep, @"close": rules.close, @"unsorted": rules.unsorted, @"noise": rules.noiseHosts,
                                    @"work": rules.workHosts, @"ignoreServing": rules.ignoreServing};
            for (NSString *x in lists[args[1]]) printf("%s\n", x.UTF8String);
            return 0;
        }
        if ([cmd isEqualToString:@"verdict"] && args.count > 1) { printf("%s\n", MMMinMacsVerdictName([rules verdictFor:args[1]]).UTF8String); return 0; }
        if ([cmd isEqualToString:@"serving"] && args.count > 1) { printf("%s\n", [rules ignoresServing:args[1]] ? "yes" : "no"); return 0; }
        if ([cmd isEqualToString:@"undo"]) {
            NSMutableArray *out = [NSMutableArray new];
            for (MMUndoRecord *r in [MMUndo.shared recent:@"minmacs" limit:100])
                [out addObject:@{@"rid": r.rid, @"kind": r.kind ?: @"", @"state": @[@"pending", @"done", @"failed", @"restored"][r.state],
                                 @"findingID": r.findingID ?: @"", @"by": r.by ?: @"", @"payload": r.payload ?: @{}, @"error": r.error ?: @""}];
            PrintJSON(out);
            return 0;
        }
        fprintf(stderr, "tool: unknown command %s\n", cmd.UTF8String);
        return 2;
    }
}
