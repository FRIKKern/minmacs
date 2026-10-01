// MinMacs — reclaim your Mac for developers and agents.
// Menu bar app + CLI. Shows exactly what is burning CPU and RAM, quits the apps on
// your close list, trims noise tabs out of browsers, spares anything that is serving
// an agent, and brings it all back with Restore.
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <signal.h>
#import "Scanner.h"
#import "Rules.h"
#import "Browser.h"
#import "Agents.h"
#import "Hosts.h"

static NSString *const kAskKey        = @"minmacs.askBeforeClosing";   // default YES
static NSString *const kInsomniaKey   = @"minmacs.turnOnInsomnia";     // default YES
static NSString *const kClosedKey     = @"minmacs.closedBundleIDs";    // for Restore
static NSString *const kClosedTabsKey = @"minmacs.closedTabs";         // [{bundleID, url}] for Restore
static NSString *const kForceKey      = @"minmacs.forceMode";          // 0 leave, 1 ask (default), 2 force
static NSString *const kQuitBrowsers  = @"minmacs.quitBrowsers";       // default NO: browsers are trimmed
static NSString *const kCmuxKey       = @"minmacs.readCmux";           // default NO: read cmux for the waiting state
static NSString *const kCmuxDirKey    = @"minmacs.debug.cmuxDir";      // debug: read the two cmux files from here

typedef NS_ENUM(NSInteger, MMForceMode) { MMForceNever = 0, MMForceAsk = 1, MMForceAlways = 2 };
static const NSTimeInterval kGrace = 8;   // seconds an app gets to quit on its own

#pragma mark - Preferences

// Explicit domain, so the CLI (run through a symlink, where the bundle may not resolve)
// and the menu bar app read and write the same preferences.
static CFStringRef const kDomain = CFSTR("no.guerrilla.minmacs");
static id PrefGet(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDomain));
}
static void PrefSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kDomain);
    CFPreferencesAppSynchronize(kDomain);
}
static BOOL PrefBool(NSString *key, BOOL dflt) { id v = PrefGet(key); return v ? [v boolValue] : dflt; }
static MMForceMode ForceMode(void) { id v = PrefGet(kForceKey); return v ? (MMForceMode)[v integerValue] : MMForceAsk; }

/// Everything outside the process table that knows an agent's state better: sets MMAgents.overrides
/// before detect: runs. Today that is cmux, when the user turned it on (or --cmux for one run).
static void ApplyHostOverrides(MMAgents *detector, MMCmuxReader *cmux, BOOL cmuxOn) {
    NSMutableDictionary<NSNumber *, NSString *> *ov = [NSMutableDictionary new], *why = [NSMutableDictionary new];
    if (cmuxOn) {
        id dir = PrefGet(kCmuxDirKey);
        [cmux addOverridesTo:ov reasons:why directory:[dir isKindOfClass:NSString.class] ? dir : nil];
    }
    detector.overrides = ov; detector.overrideReasons = why;
}

#pragma mark - Plan

/// A browser that will be trimmed rather than quit.
@interface MMTrim : NSObject
@property (strong) MMApp *app;
@property (strong) NSArray<MMTab *> *tabs, *noise;   // nil tabs = could not read
@property (copy) NSString *error;
@end
@implementation MMTrim @end

/// A close-list app that is left alone, and why.
@interface MMSpared : NSObject
@property (strong) MMApp *app;
@property (copy) NSString *reason;
@end
@implementation MMSpared @end

/// What a MinMacs press would do right now.
@interface MMPlan : NSObject
@property (strong) NSArray<MMApp *> *close, *keep, *unsorted;
@property (strong) NSArray<MMTrim *> *trim;
@property (strong) NSArray<MMSpared *> *spared;
@property double closeCPU; @property uint64_t closeMemory;
@property (readonly) NSInteger noiseTabCount;
@end
@implementation MMPlan
- (NSInteger)noiseTabCount { NSInteger n = 0; for (MMTrim *t in self.trim) n += t.noise.count; return n; }
@end

/// Non-nil when an agent or tool is using this app right now.
static NSString *ServingReason(MMApp *a) {
    if ([MMRules.shared ignoresServing:a.bundleID]) return nil;
    for (NSString *arg in MMProcessArgs(a.app.processIdentifier)) {
        if ([arg hasPrefix:@"--remote-debugging-port"]) return [NSString stringWithFormat:@"remote debugging on (%@)", [arg substringFromIndex:2]];
        if ([arg hasPrefix:@"--remote-debugging-pipe"]) return @"driven by an automation tool (remote debugging pipe)";
    }
    NSArray<NSNumber *> *ports = MMLoopbackListeners(a.pids);
    if (ports.count) return [NSString stringWithFormat:@"serving on 127.0.0.1:%@", [[ports valueForKey:@"stringValue"] componentsJoinedByString:@", :"]];
    return nil;
}

/// `deep` also reads browser tabs, which costs Apple events; ticks stay shallow.
static MMPlan *MakePlan(MMScanner *s, BOOL deep, BOOL quitBrowsers, MMAgents *detector, NSArray<MMAgent *> *agents) {
    MMPlan *p = [MMPlan new];
    NSMutableArray *c = [NSMutableArray new], *k = [NSMutableArray new], *u = [NSMutableArray new],
                   *t = [NSMutableArray new], *sp = [NSMutableArray new];
    for (MMApp *a in s.apps) {
        MMVerdict v = [MMRules.shared verdictFor:a.bundleID];
        if (v == MMKeep) { [k addObject:a]; continue; }
        if (v == MMUnsorted) { [u addObject:a]; continue; }
        NSString *why = ServingReason(a);
        MMAgent *owner = why ? nil : [detector workingAgentOwning:a.app.processIdentifier in:agents];
        if (owner) why = [NSString stringWithFormat:@"started by a working agent (%@, pid %d)", owner.harness, owner.pid];
        if (why) { MMSpared *x = [MMSpared new]; x.app = a; x.reason = why; [sp addObject:x]; continue; }
        if (!quitBrowsers && [MMBrowser isBrowser:a.bundleID]) {
            MMTrim *x = [MMTrim new]; x.app = a;
            if (![MMBrowser canTrim:a.bundleID]) x.error = @"tabs of this browser cannot be read; left running";
            else if (deep) {
                NSString *err = nil;
                x.tabs = [MMBrowser tabsOfPid:a.app.processIdentifier bundleID:a.bundleID error:&err];
                x.error = err;
                x.noise = [x.tabs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"verdict == 'noise'"]];
            }
            [t addObject:x];
            continue;
        }
        [c addObject:a]; p.closeCPU += a.cpuPercent; p.closeMemory += a.memory;
    }
    p.close = c; p.keep = k; p.unsorted = u; p.trim = t; p.spared = sp;
    return p;
}

static NSString *Pct(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; }
static NSString *Plural(NSInteger n, NSString *word) { return [NSString stringWithFormat:@"%ld %@%@", (long)n, word, n == 1 ? @"" : @"s"]; }

#pragma mark - Closing

static NSArray<MMApp *> *StillRunning(NSArray<MMApp *> *apps, NSTimeInterval wait) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:wait];
    NSMutableArray *left = [apps mutableCopy];
    do {
        [left filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMApp *a, id _) { return !a.app.terminated; }]];
        if (!left.count) break;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    } while ([deadline timeIntervalSinceNow] > 0);
    return left;
}

/// Step one: a normal Quit. Returns the apps that ignored it (usually: asking to save).
static NSArray<MMApp *> *QuitApps(NSArray<MMApp *> *apps, NSTimeInterval grace) {
    for (MMApp *a in apps) [a.app terminate];
    return StillRunning(apps, grace);
}

/// Step two: force quit. Unsaved changes in these apps are lost. Helpers that outlive
/// their parent get SIGKILL. Returns whatever is somehow still running.
static NSArray<MMApp *> *ForceQuitApps(NSArray<MMApp *> *apps) {
    for (MMApp *a in apps) [a.app forceTerminate];
    NSArray *left = StillRunning(apps, 3);
    for (MMApp *a in apps) for (NSNumber *pid in a.pids) if (kill(pid.intValue, 0) == 0) kill(pid.intValue, SIGKILL);
    return left.count ? StillRunning(left, 2) : left;
}

static void RememberClosed(NSArray<MMApp *> *apps) {
    NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSetWithArray:PrefGet(kClosedKey) ?: @[]];
    for (MMApp *a in apps) [ids addObject:a.bundleID];
    PrefSet(kClosedKey, ids.array);
}
static void RememberTabs(MMTrim *t, NSArray<MMTab *> *closed) {
    NSMutableArray *all = [(PrefGet(kClosedTabsKey) ?: @[]) mutableCopy];
    for (MMTab *tab in closed) [all addObject:@{@"bundleID": t.app.bundleID, @"url": tab.url}];
    PrefSet(kClosedTabsKey, all);
}
static NSArray<NSString *> *ClosedIDs(void) { id v = PrefGet(kClosedKey); return [v isKindOfClass:NSArray.class] ? v : @[]; }
static NSArray<NSDictionary *> *ClosedTabs(void) { id v = PrefGet(kClosedTabsKey); return [v isKindOfClass:NSArray.class] ? v : @[]; }
static NSInteger RestorableCount(void) { return ClosedIDs().count + ClosedTabs().count; }

/// Closes noise tabs in every trimmable browser of the plan. Returns tabs closed.
static NSInteger TrimBrowsers(NSArray<MMTrim *> *trims, NSString *onlyHost) {
    NSInteger n = 0;
    for (MMTrim *t in trims) {
        NSArray<MMTab *> *targets = t.noise;
        if (onlyHost) targets = [targets filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMTab *tab, id _) {
            return [tab.host isEqualToString:onlyHost] || [tab.host hasSuffix:[@"." stringByAppendingString:onlyHost]]; }]];
        if (!targets.count) continue;
        RememberTabs(t, targets);
        n += [MMBrowser closeTabs:targets pid:t.app.app.processIdentifier bundleID:t.app.bundleID];
    }
    return n;
}

/// Relaunches every app and reopens every tab MinMacs closed, in the background.
static NSInteger RestoreAll(void) {
    NSInteger n = 0;
    dispatch_group_t g = dispatch_group_create();
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.activates = NO;
    for (NSString *bid in ClosedIDs()) {
        NSURL *u = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
        if (!u) continue;
        dispatch_group_enter(g);
        [NSWorkspace.sharedWorkspace openApplicationAtURL:u configuration:cfg
            completionHandler:^(NSRunningApplication *a, NSError *e) { dispatch_group_leave(g); }];
        n++;
    }
    NSMutableDictionary<NSString *, NSMutableArray<NSURL *> *> *byApp = [NSMutableDictionary new];
    for (NSDictionary *t in ClosedTabs()) {
        NSURL *u = [NSURL URLWithString:t[@"url"] ?: @""];
        if (!u || !t[@"bundleID"]) continue;
        if (!byApp[t[@"bundleID"]]) byApp[t[@"bundleID"]] = [NSMutableArray new];
        [byApp[t[@"bundleID"]] addObject:u];
    }
    for (NSString *bid in byApp) {
        NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
        if (!app) continue;
        dispatch_group_enter(g);
        [NSWorkspace.sharedWorkspace openURLs:byApp[bid] withApplicationAtURL:app configuration:cfg
            completionHandler:^(NSRunningApplication *a, NSError *e) { dispatch_group_leave(g); }];
        n += byApp[bid].count;
    }
    // Launch requests are asynchronous; give them time to land (matters for the CLI, which exits right after).
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (dispatch_group_wait(g, DISPATCH_TIME_NOW) != 0 && [deadline timeIntervalSinceNow] > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    PrefSet(kClosedKey, nil); PrefSet(kClosedTabsKey, nil);
    return n;
}

static BOOL InsomniaInstalled(void) {
    return [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"no.guerrilla.insomnia"] != nil;
}

#pragma mark - CLI

static void PrintApps(NSString *title, NSArray<MMApp *> *apps) {
    if (!apps.count) return;
    printf("%s (%lu)\n", title.UTF8String, (unsigned long)apps.count);
    for (MMApp *a in apps)
        printf("  %5s  %8s  %-28s %s\n", Pct(a.cpuPercent).UTF8String, MMFormatBytes(a.memory).UTF8String,
               [a.name substringToIndex:MIN(28, a.name.length)].UTF8String, a.bundleID.UTF8String);
}

static NSDictionary *AppJSON(MMApp *a) {
    return @{@"name": a.name, @"bundleID": a.bundleID, @"pid": @(a.app.processIdentifier), @"cpu": @(round(a.cpuPercent)),
             @"memoryBytes": @(a.memory), @"processes": @(a.processCount)};
}

static int Usage(void) {
    fprintf(stderr,
        "usage: minmacs <command> [options]\n"
        "  plan                  what MinMacs would do right now (default)\n"
        "  run                   quit the close list and trim browsers; asks unless --yes\n"
        "  trim                  only trim browser tabs; asks unless --yes\n"
        "  agents                which agent sessions are running, and which are working or blocked\n"
        "  restore               relaunch apps and reopen tabs the last run closed\n"
        "  classify <url|host>   say whether a tab is noise, work or other\n"
        "  rules                 print the rules file path\n"
        "options:\n"
        "  --json                machine-readable plan\n"
        "  --yes                 do not ask\n"
        "  --force               force quit apps that ignore a normal Quit (unsaved changes are lost)\n"
        "  --only <bundle-id>    act on this one app\n"
        "  --only-host <host>    trim only tabs on this host\n"
        "  --quit-browsers       quit browsers instead of trimming them\n"
        "  --rows <dir>          agents: read harness rows from this directory instead\n"
        "  --cmux                agents: read cmux for the waiting state this run (setting: Read cmux for Waiting State)\n");
    return 2;
}

static int RunCLI(int argc, const char **argv) {
    NSMutableArray<NSString *> *args = [NSMutableArray new];
    for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
    NSString *cmd = args.firstObject ?: @"plan";
    BOOL json = [args containsObject:@"--json"], yes = [args containsObject:@"--yes"], force = [args containsObject:@"--force"];
    BOOL quitBrowsers = [args containsObject:@"--quit-browsers"] || PrefBool(kQuitBrowsers, NO);
    NSString *(^opt)(NSString *) = ^NSString *(NSString *name) {
        NSUInteger i = [args indexOfObject:name];
        return (i != NSNotFound && i + 1 < args.count) ? args[i + 1] : nil;
    };
    NSString *only = opt(@"--only"), *onlyHost = opt(@"--only-host").lowercaseString;

    if ([cmd isEqualToString:@"restore"]) { printf("restored %ld item(s)\n", (long)RestoreAll()); return 0; }
    if ([cmd isEqualToString:@"rules"]) { printf("%s\n", MMRules.shared.fileURL.path.UTF8String); return 0; }
    if ([cmd isEqualToString:@"classify"]) {
        if (args.count < 2) return Usage();
        NSString *h = [NSURL URLWithString:args[1]].host ?: args[1];
        h = h.lowercaseString; if ([h hasPrefix:@"www."]) h = [h substringFromIndex:4];
        printf("%s\n", [MMRules.shared tabVerdictForHost:h].UTF8String);
        return 0;
    }
    if (![@[@"plan", @"run", @"trim", @"agents"] containsObject:cmd]) return Usage();

    MMScanner *s = [MMScanner new];
    [s sample]; [NSThread sleepForTimeInterval:1.0]; [s sample];   // two samples for CPU%
    MMAgents *detector = [[MMAgents alloc] initWithRowDirectories:opt(@"--rows") ? @[opt(@"--rows")] : MMAgents.defaultRowDirectories];
    detector.holdSeconds = 0;   // one shot: report what is true now
    ApplyHostOverrides(detector, [MMCmuxReader new], [args containsObject:@"--cmux"] || PrefBool(kCmuxKey, NO));
    NSArray<MMAgent *> *agents = [detector detect:s];

    if ([cmd isEqualToString:@"agents"]) {
        // working includes blocked (a live turn); unknown is its own count and is neither working nor idle.
        NSInteger working = [agents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"working == YES"]].count;
        NSInteger unknown = [agents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"state == 'unknown'"]].count;
        NSInteger blocked = [agents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"state == 'blocked'"]].count;
        NSInteger idle = agents.count - working - unknown;
        if (json) {
            NSMutableArray *o = [NSMutableArray new];
            for (MMAgent *a in agents) [o addObject:a.json];
            NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"agents": o, @"working": @(working), @"blocked": @(blocked), @"idle": @(idle), @"unknown": @(unknown), @"rows": @(detector.rowCount)}
                                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
            printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        }
        if (!detector.rowCount) { printf("no harness rows found\n"); return 0; }
        printf("%-16s%-8s%-7s%-10s%5s  %-9s%-5s%-30s%s\n", "harness", "surface", "pid", "state", "cpu", "memory", "kids", "why", "project");
        for (MMAgent *a in agents) {
            BOOL hollow = [a.state isEqualToString:@"unknown"];   // a hollow marker: nothing outside the process says either way
            printf("%-16s%-8s%-7d%s%-*s%5.1f  %-9s%-5ld%-30s%s\n", [a.harness substringToIndex:MIN(15, a.harness.length)].UTF8String, a.surface.UTF8String,
                   a.pid, hollow ? "\xe2\x97\x8c " : "", hollow ? 8 : 10, a.state.UTF8String, a.cpu, MMFormatBytes(a.memory).UTF8String, (long)a.children,
                   [a.why substringToIndex:MIN(29, a.why.length)].UTF8String, a.project.UTF8String);
        }
        printf("\n%lu agent sessions: %ld working%s, %ld idle, %ld unknown (%ld harness rows loaded)\n", (unsigned long)agents.count, (long)working,
               blocked ? [NSString stringWithFormat:@" (%ld blocked on you)", (long)blocked].UTF8String : "",
               (long)idle, (long)unknown, (long)detector.rowCount);
        return 0;
    }
    MMPlan *p = MakePlan(s, YES, quitBrowsers, detector, agents);
    NSPredicate *onlyApp = only ? [NSPredicate predicateWithFormat:@"bundleID == %@", only] : [NSPredicate predicateWithValue:YES];
    NSPredicate *onlyTrim = only ? [NSPredicate predicateWithFormat:@"app.bundleID == %@", only] : [NSPredicate predicateWithValue:YES];
    NSArray<MMApp *> *targets = [cmd isEqualToString:@"trim"] ? @[] : [p.close filteredArrayUsingPredicate:onlyApp];
    NSArray<MMTrim *> *trims = [p.trim filteredArrayUsingPredicate:onlyTrim];

    if (json) {
        NSMutableArray *tj = [NSMutableArray new], *sj = [NSMutableArray new];
        for (MMTrim *t in trims) {
            NSMutableArray *tabs = [NSMutableArray new];
            for (MMTab *tab in t.noise) [tabs addObject:@{@"title": tab.title ?: @"", @"url": tab.url, @"host": tab.host}];
            [tj addObject:@{@"app": AppJSON(t.app), @"tabs": @(t.tabs.count), @"noiseTabs": tabs, @"error": t.error ?: NSNull.null}];
        }
        for (MMSpared *x in p.spared) [sj addObject:@{@"app": AppJSON(x.app), @"reason": x.reason}];
        NSArray *(^enc)(NSArray<MMApp *> *) = ^NSArray *(NSArray<MMApp *> *apps) {
            NSMutableArray *o = [NSMutableArray new];
            for (MMApp *a in apps) [o addObject:AppJSON(a)];
            return o;
        };
        NSDictionary *j = @{@"close": enc(targets), @"trim": tj, @"spared": sj,
                            @"keep": enc(p.keep), @"unsorted": enc(p.unsorted),
                            @"reclaimableCPU": @(round(p.closeCPU)), @"reclaimableMemoryBytes": @(p.closeMemory),
                            @"thermal": @(NSProcessInfo.processInfo.thermalState)};
        NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    } else {
        PrintApps(@"Will quit", targets);
        for (MMTrim *t in trims) {
            if (t.error) { printf("Will leave %s running: %s\n", t.app.name.UTF8String, t.error.UTF8String); continue; }
            printf("Will trim %s: %lu of %lu tabs\n", t.app.name.UTF8String, (unsigned long)t.noise.count, (unsigned long)t.tabs.count);
            for (MMTab *tab in t.noise)
                printf("    %-22s %s\n", [tab.host substringToIndex:MIN(22, tab.host.length)].UTF8String,
                       [tab.title substringToIndex:MIN(70, tab.title.length)].UTF8String);
        }
        for (MMSpared *x in p.spared) printf("Spared %s: %s\n", x.app.name.UTF8String, x.reason.UTF8String);
        PrintApps(@"Kept (developer and agent essentials)", p.keep);
        PrintApps(@"Unsorted (never touched; sort them in the menu or rules file)", p.unsorted);
        printf("Reclaimable by quitting: %s CPU, %s memory\n", Pct(p.closeCPU).UTF8String, MMFormatBytes(p.closeMemory).UTF8String);
    }
    if ([cmd isEqualToString:@"plan"]) return 0;

    NSInteger noise = 0;
    for (MMTrim *t in trims) for (MMTab *tab in t.noise)
        if (!onlyHost || [tab.host isEqualToString:onlyHost] || [tab.host hasSuffix:[@"." stringByAppendingString:onlyHost]]) noise++;
    if (!targets.count && !noise) { printf("nothing to close\n"); return 0; }
    if (!yes) {
        printf("Quit %s and close %s?%s [y/N] ", Plural(targets.count, @"app").UTF8String, Plural(noise, @"tab").UTF8String,
               force ? " Apps that refuse will be FORCE QUIT." : "");
        fflush(stdout);
        char buf[8] = {0}; if (!fgets(buf, sizeof buf, stdin) || (buf[0] != 'y' && buf[0] != 'Y')) { printf("aborted\n"); return 1; }
    }
    NSInteger closedTabs = TrimBrowsers(trims, onlyHost);
    if (noise) printf("closed %ld of %ld tab(s)\n", (long)closedTabs, (long)noise);
    if (!targets.count) return 0;

    RememberClosed(targets);
    NSArray<MMApp *> *left = QuitApps(targets, kGrace);
    NSInteger forced = 0;
    if (left.count && force) {
        for (MMApp *a in left) printf("force quitting: %s\n", a.name.UTF8String);
        forced = left.count;
        left = ForceQuitApps(left);
        forced -= left.count;
    }
    for (MMApp *a in left) printf("still running%s: %s\n", force ? "" : " (ignored Quit; use --force)", a.name.UTF8String);
    printf("closed %lu of %lu app(s)%s\n", (unsigned long)(targets.count - left.count), (unsigned long)targets.count,
           forced ? [NSString stringWithFormat:@", %ld by force", (long)forced].UTF8String : "");
    return left.count ? 3 : 0;
}

#pragma mark - App

@interface MinMacs : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) MMScanner *scanner;
@property (strong) NSTimer *timer;
@property (strong) MMPlan *plan;
@property (strong) MMAgents *detector;
@property (strong) NSArray<MMAgent *> *agents;
@property (strong) MMCmuxReader *cmux;
@end

@implementation MinMacs

- (BOOL)ask { return PrefBool(kAskKey, YES); }
- (BOOL)insomnia { return PrefBool(kInsomniaKey, YES); }
- (BOOL)quitBrowsers { return PrefBool(kQuitBrowsers, NO); }
- (BOOL)readCmux { return PrefBool(kCmuxKey, NO); }

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.scanner = [MMScanner new];
    self.detector = [[MMAgents alloc] initWithRowDirectories:MMAgents.defaultRowDirectories];
    self.cmux = [MMCmuxReader new];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(handleClick:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self.scanner sample];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    self.timer.tolerance = 1;
    [self tick];
}

- (void)tick { [self refresh:NO]; }

- (void)refresh:(BOOL)deep {
    [self.scanner sample];
    ApplyHostOverrides(self.detector, self.cmux, self.readCmux);
    self.agents = [self.detector detect:self.scanner];
    self.plan = MakePlan(self.scanner, deep, self.quitBrowsers, self.detector, self.agents);
    BOOL restorable = RestorableCount() > 0;
    NSImage *img = [NSImage imageWithSystemSymbolName:restorable ? @"gauge.with.dots.needle.0percent" : @"gauge.with.dots.needle.67percent"
                                accessibilityDescription:@"MinMacs"]
                   ?: [NSImage imageWithSystemSymbolName:@"speedometer" accessibilityDescription:@"MinMacs"];
    img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]];
    img.template = YES;
    self.statusItem.button.image = img;
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"MinMacs: %@ to quit, %@ CPU and %@ reclaimable",
                                      Plural(self.plan.close.count, @"app"), Pct(self.plan.closeCPU), MMFormatBytes(self.plan.closeMemory)];
}

#pragma mark Menu

static NSMenuItem *Item(NSMenu *m, NSString *t, SEL a, id target, BOOL on) {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:@""];
    i.target = target; i.state = on ? NSControlStateValueOn : NSControlStateValueOff; [m addItem:i]; return i;
}
static NSMenuItem *Header(NSMenu *m, NSString *t) { NSMenuItem *i = Item(m, t, NULL, nil, NO); i.enabled = NO; return i; }

- (NSMenu *)appSubmenu:(MMApp *)a verdict:(MMVerdict)v serving:(BOOL)serving {
    NSMenu *sub = [NSMenu new];
    Header(sub, a.bundleID);
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"Close on MinMacs", @selector(markClose:), self, v == MMClose).representedObject = a.bundleID;
    Item(sub, @"Keep (never close)", @selector(markKeep:), self, v == MMKeep).representedObject = a.bundleID;
    Item(sub, @"Unsorted (list only)", @selector(markUnsorted:), self, v == MMUnsorted).representedObject = a.bundleID;
    if (serving || [MMRules.shared ignoresServing:a.bundleID]) {
        [sub addItem:NSMenuItem.separatorItem];
        Item(sub, @"Close Even When Serving", @selector(toggleIgnoreServing:), self, [MMRules.shared ignoresServing:a.bundleID]).representedObject = a.bundleID;
    }
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"Quit Now", @selector(quitOne:), self, NO).representedObject = a;
    Item(sub, @"Force Quit Now", @selector(forceOne:), self, NO).representedObject = a;
    return sub;
}

- (NSMenuItem *)appItem:(MMApp *)a title:(NSString *)extra verdict:(MMVerdict)v serving:(BOOL)serving {
    NSString *title = [NSString stringWithFormat:@"%@   %@ · %@%@", a.name, Pct(a.cpuPercent), MMFormatBytes(a.memory), extra ?: @""];
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    i.image = [a.app.icon copy]; i.image.size = NSMakeSize(16, 16);
    i.submenu = [self appSubmenu:a verdict:v serving:serving];
    return i;
}

- (NSMenuItem *)trimItem:(MMTrim *)t {
    NSString *extra = t.error ? @"   · left running"
                              : [NSString stringWithFormat:@"   · trim %lu of %lu tabs", (unsigned long)t.noise.count, (unsigned long)t.tabs.count];
    NSMenuItem *i = [self appItem:t.app title:extra verdict:MMClose serving:NO];
    NSMenu *sub = i.submenu;
    [sub insertItem:NSMenuItem.separatorItem atIndex:0];
    if (t.error) {
        NSMenuItem *e = [[NSMenuItem alloc] initWithTitle:t.error action:nil keyEquivalent:@""]; e.enabled = NO;
        [sub insertItem:e atIndex:0];
        return i;
    }
    NSInteger at = 0;
    NSMenuItem *h = [[NSMenuItem alloc] initWithTitle:t.noise.count ? @"Tabs that will be closed (pick one to keep its site)" : @"No noise tabs open"
                                               action:nil keyEquivalent:@""];
    h.enabled = NO; [sub insertItem:h atIndex:at++];
    for (MMTab *tab in t.noise) {
        if (at > 25) { NSMenuItem *more = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"…and %lu more", (unsigned long)(t.noise.count - 25)] action:nil keyEquivalent:@""]; more.enabled = NO; [sub insertItem:more atIndex:at++]; break; }
        NSString *title = tab.title.length > 60 ? [[tab.title substringToIndex:60] stringByAppendingString:@"…"] : tab.title;
        NSMenuItem *ti = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@  —  %@", tab.host, title] action:@selector(keepHost:) keyEquivalent:@""];
        ti.target = self; ti.representedObject = tab.host; ti.toolTip = @"Keep this site: adds it to the work list";
        [sub insertItem:ti atIndex:at++];
    }
    return i;
}

- (void)handleClick:(id)sender {
    [self refresh:YES];
    MMPlan *p = self.plan;
    NSMenu *menu = [NSMenu new];
    static NSString *const th[] = { @"nominal", @"fair", @"serious", @"critical" };
    Header(menu, [NSString stringWithFormat:@"%lu apps · system load %@ · thermal %@",
                  (unsigned long)self.scanner.apps.count, Pct(self.scanner.totalCPU), th[NSProcessInfo.processInfo.thermalState]]);
    BOOL cmuxUp = MMCmuxReader.cmuxRunning;
    if (self.agents.count || cmuxUp || self.readCmux) {
        NSInteger working = 0, blocked = 0, unknown = 0; uint64_t mem = 0;
        for (MMAgent *a in self.agents) {
            if ([a.state isEqualToString:@"blocked"]) blocked++; else working += a.working;
            unknown += [a.state isEqualToString:@"unknown"]; mem += a.memory;
        }
        NSInteger idle = self.agents.count - working - blocked - unknown;
        NSString *title = !self.agents.count ? @"Agents: none running"
            : [NSString stringWithFormat:@"Agents: %ld working, %@%ld idle%@ · %@", (long)working,
               blocked ? [NSString stringWithFormat:@"%ld blocked on you, ", (long)blocked] : @"", (long)idle,
               unknown ? [NSString stringWithFormat:@", %ld unknown", (long)unknown] : @"", MMFormatBytes(mem)];
        NSMenuItem *ai = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        ai.image = [NSImage imageWithSystemSymbolName:blocked ? @"exclamationmark.circle.fill" : working ? @"circle.fill" : @"circle" accessibilityDescription:nil];
        NSMenu *am = [NSMenu new];
        for (MMAgent *a in self.agents) {
            NSString *where = a.project.lastPathComponent.length ? a.project.lastPathComponent : a.project;
            BOOL isBlocked = [a.state isEqualToString:@"blocked"];
            NSString *t = [NSString stringWithFormat:@"%@  %@  ·  %@%@   %@ · %@", isBlocked ? @"\u25c6" : a.working ? @"\u25cf" : [a.state isEqualToString:@"unknown"] ? @"\u25cc" : @"\u25cb", a.harness, where,
                           a.working ? [NSString stringWithFormat:@"  ·  %@", a.why] : @"", Pct(a.cpu), MMFormatBytes(a.memory)];
            Header(am, t).toolTip = [NSString stringWithFormat:@"pid %d · %@ · %@", a.pid, a.surface, a.project];
        }
        if (self.agents.count) {
            [am addItem:NSMenuItem.separatorItem];
            Header(am, @"MinMacs never touches anything a working or blocked agent started.");
        }
        [am addItem:NSMenuItem.separatorItem];
        NSMenuItem *ci = Item(am, @"Read cmux for Waiting State", @selector(toggleCmux), self, self.readCmux);
        ci.toolTip = @"When cmux is running, MinMacs reads two files in ~/.cmuxterm:\n"
                     @"claude-hook-sessions.json: the keys pid, sessionId, surfaceId, workspaceId, updatedAt.\n"
                     @"workstream.jsonl: the last 2 MB only, the keys kind, createdAt, workstreamId.\n"
                     @"Prompts, tool inputs and payloads are never read. It marks an agent blocked when it waits on you.";
        ai.submenu = am;
        [menu addItem:ai];
    }
    [menu addItem:NSMenuItem.separatorItem];

    NSInteger noise = p.noiseTabCount;
    NSMutableArray *parts = [NSMutableArray new];
    if (p.close.count) [parts addObject:[NSString stringWithFormat:@"quit %@", Plural(p.close.count, @"app")]];
    if (noise) [parts addObject:[NSString stringWithFormat:@"close %@", Plural(noise, @"tab")]];
    NSString *go = parts.count ? [NSString stringWithFormat:@"MinMacs Now: %@%@", [parts componentsJoinedByString:@", "],
                                  p.close.count ? [NSString stringWithFormat:@" (%@ CPU · %@)", Pct(p.closeCPU), MMFormatBytes(p.closeMemory)] : @""]
                               : @"MinMacs Now: nothing to close";
    NSMenuItem *goItem = Item(menu, go, @selector(minmacsNow), self, NO);
    goItem.enabled = parts.count > 0;
    goItem.image = [NSImage imageWithSystemSymbolName:@"bolt.fill" accessibilityDescription:nil];
    if (RestorableCount())
        Item(menu, [NSString stringWithFormat:@"Restore %@", Plural(RestorableCount(), @"closed item")], @selector(restore), self, NO);
    [menu addItem:NSMenuItem.separatorItem];

    Header(menu, [NSString stringWithFormat:@"Will quit (%lu)", (unsigned long)p.close.count]);
    for (MMApp *a in p.close) [menu addItem:[self appItem:a title:nil verdict:MMClose serving:NO]];
    if (p.trim.count) {
        Header(menu, [NSString stringWithFormat:@"Browsers, trimmed not quit (%lu)", (unsigned long)p.trim.count]);
        for (MMTrim *t in p.trim) [menu addItem:[self trimItem:t]];
    }
    if (p.spared.count) {
        Header(menu, [NSString stringWithFormat:@"Spared, in use by an agent or tool (%lu)", (unsigned long)p.spared.count]);
        for (MMSpared *x in p.spared)
            [menu addItem:[self appItem:x.app title:[NSString stringWithFormat:@"   · %@", x.reason] verdict:MMClose serving:YES]];
    }
    if (p.unsorted.count) {
        Header(menu, [NSString stringWithFormat:@"Unsorted, not touched (%lu)", (unsigned long)p.unsorted.count]);
        for (MMApp *a in p.unsorted) [menu addItem:[self appItem:a title:nil verdict:MMUnsorted serving:NO]];
    }
    NSMenuItem *keptItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Kept, essentials (%lu)", (unsigned long)p.keep.count] action:nil keyEquivalent:@""];
    NSMenu *kept = [NSMenu new];
    for (MMApp *a in p.keep) [kept addItem:[self appItem:a title:nil verdict:MMKeep serving:NO]];
    keptItem.submenu = kept;
    [menu addItem:keptItem];

    NSMenuItem *sysItem = [[NSMenuItem alloc] initWithTitle:@"Background load (system, informational)" action:nil keyEquivalent:@""];
    NSMenu *sys = [NSMenu new];
    NSInteger shown = 0;
    for (MMProc *pr in self.scanner.unattributed) {
        if (shown++ >= 8) break;
        Header(sys, [NSString stringWithFormat:@"%@   %@ · %@   (pid %d)", pr.name, Pct(pr.cpuPercent), MMFormatBytes(pr.footprint), pr.pid]);
    }
    sysItem.submenu = sys;
    [menu addItem:sysItem];
    [menu addItem:NSMenuItem.separatorItem];

    Item(menu, @"Ask Before Closing", @selector(toggleAsk), self, self.ask);
    NSMenuItem *fItem = [[NSMenuItem alloc] initWithTitle:@"When an App Won't Quit" action:nil keyEquivalent:@""];
    NSMenu *f = [NSMenu new];
    Item(f, @"Ask Me", @selector(setForce:), self, ForceMode() == MMForceAsk).tag = MMForceAsk;
    Item(f, @"Force Quit It", @selector(setForce:), self, ForceMode() == MMForceAlways).tag = MMForceAlways;
    Item(f, @"Leave It Running", @selector(setForce:), self, ForceMode() == MMForceNever).tag = MMForceNever;
    [f addItem:NSMenuItem.separatorItem];
    Header(f, [NSString stringWithFormat:@"Apps get %.0f seconds to quit on their own first.", kGrace]);
    Header(f, @"Force quitting discards unsaved changes.");
    fItem.submenu = f; [menu addItem:fItem];
    NSMenuItem *bItem = [[NSMenuItem alloc] initWithTitle:@"Browsers" action:nil keyEquivalent:@""];
    NSMenu *b = [NSMenu new];
    Item(b, @"Trim Noise Tabs, Keep the Browser", @selector(setBrowserMode:), self, !self.quitBrowsers).tag = 0;
    Item(b, @"Quit Browsers", @selector(setBrowserMode:), self, self.quitBrowsers).tag = 1;
    bItem.submenu = b; [menu addItem:bItem];
    Item(menu, @"Also Turn On Insomnia", @selector(toggleInsomnia), self, self.insomnia).enabled = InsomniaInstalled();
    Item(menu, @"Edit Rules…", @selector(editRules), self, NO);
    Item(menu, @"Launch at Login", @selector(toggleLogin), self, SMAppService.mainAppService.status == SMAppServiceStatusEnabled);
    [menu addItem:NSMenuItem.separatorItem];
    Header(menu, [NSString stringWithFormat:@"MinMacs %@", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @""]);
    Item(menu, @"Quit MinMacs", @selector(quit), self, NO).keyEquivalent = @"q";

    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;
}

#pragma mark Actions

- (void)minmacsNow { [self runWithConfirm:self.ask]; }

- (void)runWithConfirm:(BOOL)confirm {
    [self refresh:YES];
    MMPlan *p = self.plan;
    NSArray<MMApp *> *targets = p.close;
    NSInteger noise = p.noiseTabCount;
    if (!targets.count && !noise) return;
    if (confirm) {
        NSAlert *a = [NSAlert new];
        NSMutableArray *what = [NSMutableArray new];
        if (targets.count) [what addObject:[NSString stringWithFormat:@"quit %@", Plural(targets.count, @"app")]];
        if (noise) [what addObject:[NSString stringWithFormat:@"close %@", Plural(noise, @"tab")]];
        a.messageText = [NSString stringWithFormat:@"MinMacs will %@", [what componentsJoinedByString:@" and "]];
        NSMutableString *list = [NSMutableString new];
        for (MMApp *t in targets) [list appendFormat:@"•  Quit %@   (%@ · %@)\n", t.name, Pct(t.cpuPercent), MMFormatBytes(t.memory)];
        for (MMTrim *t in p.trim) {
            if (!t.noise.count) continue;
            [list appendFormat:@"•  %@: close %@, keep %lu\n", t.app.name, Plural(t.noise.count, @"tab"), (unsigned long)(t.tabs.count - t.noise.count)];
            NSInteger shown = 0;
            for (MMTab *tab in t.noise) { if (shown++ >= 6) { [list appendFormat:@"       …and %lu more\n", (unsigned long)(t.noise.count - 6)]; break; }
                [list appendFormat:@"       %@\n", tab.host]; }
        }
        for (MMSpared *x in p.spared) [list appendFormat:@"•  Leave %@: %@\n", x.app.name, x.reason];
        NSString *policy = ForceMode() == MMForceAlways ? [NSString stringWithFormat:@"Apps get %.0f seconds to quit on their own, then they are force quit and unsaved changes are lost.", kGrace]
                         : ForceMode() == MMForceAsk    ? [NSString stringWithFormat:@"Apps get %.0f seconds to quit on their own. If one refuses, you will be asked before it is force quit.", kGrace]
                                                        : @"Apps get a normal Quit. One that refuses is left running.";
        [list appendFormat:@"\n%@ Restore brings the apps and tabs back.", policy];
        a.informativeText = list;
        [a addButtonWithTitle:@"MinMacs Now"]; [a addButtonWithTitle:@"Cancel"];
        a.showsSuppressionButton = YES; a.suppressionButton.title = @"Don't ask again";
        [NSApp activateIgnoringOtherApps:YES];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (a.suppressionButton.state == NSControlStateValueOn) PrefSet(kAskKey, @NO);
    }
    if (self.insomnia && InsomniaInstalled()) [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"insomnia://on"]];
    TrimBrowsers(p.trim, nil);
    if (targets.count) {
        RememberClosed(targets);
        [self escalate:QuitApps(targets, kGrace)];
    }
    [self tick];
}

/// What to do with apps that ignored a normal Quit, per the user's setting.
- (void)escalate:(NSArray<MMApp *> *)left {
    if (!left.count) return;
    NSString *names = [[left valueForKeyPath:@"name"] componentsJoinedByString:@", "];
    MMForceMode mode = ForceMode();
    if (mode == MMForceAsk) {
        NSAlert *a = [NSAlert new];
        a.alertStyle = NSAlertStyleWarning;
        a.messageText = [NSString stringWithFormat:@"%@ did not quit", left.count == 1 ? names : Plural(left.count, @"app")];
        a.informativeText = [NSString stringWithFormat:@"%@\n\nUsually an app is asking you to save something. Force quitting closes it immediately and discards unsaved changes.", names];
        [a addButtonWithTitle:@"Force Quit"]; [a addButtonWithTitle:@"Leave Running"];
        a.buttons.firstObject.hasDestructiveAction = YES;
        [NSApp activateIgnoringOtherApps:YES];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        mode = MMForceAlways;
    }
    if (mode != MMForceAlways) return;
    NSArray<MMApp *> *stuck = ForceQuitApps(left);
    if (stuck.count) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Could not force quit";
        a.informativeText = [[stuck valueForKeyPath:@"name"] componentsJoinedByString:@", "];
        [NSApp activateIgnoringOtherApps:YES]; [a runModal];
    }
}

- (void)restore { RestoreAll(); [self performSelector:@selector(tick) withObject:nil afterDelay:2]; }
- (void)quitOne:(NSMenuItem *)i { MMApp *a = i.representedObject; RememberClosed(@[a]); [self escalate:QuitApps(@[a], kGrace)]; [self tick]; }
- (void)forceOne:(NSMenuItem *)i {
    MMApp *a = i.representedObject;
    NSAlert *al = [NSAlert new];
    al.alertStyle = NSAlertStyleWarning;
    al.messageText = [NSString stringWithFormat:@"Force quit %@?", a.name];
    al.informativeText = @"It closes immediately. Unsaved changes are lost.";
    [al addButtonWithTitle:@"Force Quit"]; [al addButtonWithTitle:@"Cancel"];
    al.buttons.firstObject.hasDestructiveAction = YES;
    [NSApp activateIgnoringOtherApps:YES];
    if ([al runModal] != NSAlertFirstButtonReturn) return;
    RememberClosed(@[a]); ForceQuitApps(@[a]); [self tick];
}
- (void)markClose:(NSMenuItem *)i    { [MMRules.shared setVerdict:MMClose forBundleID:i.representedObject]; [self tick]; }
- (void)markKeep:(NSMenuItem *)i     { [MMRules.shared setVerdict:MMKeep forBundleID:i.representedObject]; [self tick]; }
- (void)markUnsorted:(NSMenuItem *)i { [MMRules.shared setVerdict:MMUnsorted forBundleID:i.representedObject]; [self tick]; }
- (void)keepHost:(NSMenuItem *)i     { [MMRules.shared addWorkHost:i.representedObject]; }
- (void)toggleIgnoreServing:(NSMenuItem *)i {
    [MMRules.shared setIgnoresServing:![MMRules.shared ignoresServing:i.representedObject] forBundleID:i.representedObject]; [self tick];
}
- (void)setForce:(NSMenuItem *)i { PrefSet(kForceKey, @(i.tag)); }
- (void)setBrowserMode:(NSMenuItem *)i { PrefSet(kQuitBrowsers, @(i.tag == 1)); [self tick]; }
- (void)toggleAsk { PrefSet(kAskKey, @(!self.ask)); }
- (void)toggleCmux { PrefSet(kCmuxKey, @(!self.readCmux)); [self tick]; }
- (void)toggleInsomnia { PrefSet(kInsomniaKey, @(!self.insomnia)); }
- (void)editRules { [MMRules.shared reload]; [NSWorkspace.sharedWorkspace openURL:MMRules.shared.fileURL]; }
- (void)toggleLogin {
    SMAppService *s = SMAppService.mainAppService; NSError *e = nil;
    if (s.status == SMAppServiceStatusEnabled) [s unregisterAndReturnError:&e]; else [s registerAndReturnError:&e];
    if (e) NSBeep();
}
- (void)quit { [NSApp terminate:nil]; }

/// minmacs://run | run-now (no confirm) | restore | login-on | login-off | quit
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        NSString *c = u.host.lowercaseString ?: @"";
        if      ([c isEqualToString:@"run"])       [self runWithConfirm:YES];
        else if ([c isEqualToString:@"run-now"])   [self runWithConfirm:NO];
        else if ([c isEqualToString:@"restore"])   [self restore];
        else if ([c isEqualToString:@"login-on"] || [c isEqualToString:@"login-off"]) {
            BOOL want = [c isEqualToString:@"login-on"];
            if ((SMAppService.mainAppService.status == SMAppServiceStatusEnabled) != want) [self toggleLogin];
        }
        else if ([c isEqualToString:@"quit"])      [NSApp terminate:nil];
    }
}

@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc > 1 && argv[1][0] != '-') return RunCLI(argc, argv);    // CLI mode
        if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) return Usage();
        NSApplication *app = NSApplication.sharedApplication;
        MinMacs *delegate = [MinMacs new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
