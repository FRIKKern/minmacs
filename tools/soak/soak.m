// The soak subject, issue #56. MMCoreStart with every built-in expert in one process, headless as tools/bench runs
// it, every mode Idle, the main-thread watchdog on, and each expert's menu opened from Core's live snapshot with
// every card hovered once a minute. tools/soak/run.sh starts it, makes fixture churn beside it and samples it.
//
//   soak run --seconds N [--menus-every S] [--status PATH]
//   soak _walk    the repo walker child that Core's worker starts from this binary, as from the app
//
// It writes one JSON line to --status every minute and one JSON object to stdout when it stops: at the end of
// --seconds or on SIGTERM. It never signals, quits or stops a process, and every mode is Idle, so nothing acts.
// It refuses to run unless MINMACS_HOME, MINMACS_ROOTS, MINMACS_CLAUDE, MINMACS_CODEX, MINMACS_CMUX and MINMACS_TMUX
// are set, each fake or inside MINMACS_HOME, so no real model, cmux, tmux, repo or support folder is ever reached.
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <pthread/qos.h>
#import <signal.h>
#import <unistd.h>
#import "Core/MMCore.h"
#import "Shell/MMShell.h"
#import "Shell/MMWatchdog.h"
#import "UI/MMSpecMenu.h"

static BOOL Inside(NSString *path, NSString *dir) {
    NSString *p = path.stringByStandardizingPath, *d = dir.stringByStandardizingPath;
    return [p isEqualToString:d] || [p hasPrefix:[d stringByAppendingString:@"/"]];
}

/// The bench's rules, plus MINMACS_ROOTS: it must be set and lie inside MINMACS_HOME, so the repo index walks
/// the fixture repos only.
static BOOL SafeEnvironment(void) {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    NSString *home = env[@"MINMACS_HOME"];
    if (!home.length) { fprintf(stderr, "soak: MINMACS_HOME must be set; tools/soak/run.sh sets it\n"); return NO; }
    NSString *real = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"];
    if (Inside(home, real) || Inside(real, home)) { fprintf(stderr, "soak: MINMACS_HOME must not hold the real support folder\n"); return NO; }
    for (NSString *k in @[@"MINMACS_CLAUDE", @"MINMACS_CODEX", @"MINMACS_CMUX", @"MINMACS_TMUX"]) {
        NSString *v = env[k];
        if (!v.length) { fprintf(stderr, "soak: %s must be set; tools/soak/run.sh sets it\n", k.UTF8String); return NO; }
        if (![v isEqualToString:@"/usr/bin/false"] && !Inside(v, home)) {
            fprintf(stderr, "soak: %s must be /usr/bin/false or a fake inside MINMACS_HOME\n", k.UTF8String); return NO;
        }
    }
    NSString *roots = env[@"MINMACS_ROOTS"] ?: @"";
    if (!roots.length) { fprintf(stderr, "soak: MINMACS_ROOTS must be set to fixture repos inside MINMACS_HOME\n"); return NO; }
    for (NSString *r in [roots componentsSeparatedByString:@":"])
        if (r.length && !Inside(r, home)) { fprintf(stderr, "soak: MINMACS_ROOTS must lie inside MINMACS_HOME\n"); return NO; }
    for (NSString *k in @[@"CLAUDE_CONFIG_DIR", @"CODEX_HOME"])
        if (!env[k].length || !Inside(env[k], home)) { fprintf(stderr, "soak: %s must lie inside MINMACS_HOME\n", k.UTF8String); return NO; }
    return YES;
}

@interface MMSoakFooter : NSObject
- (void)hideIcon:(id)sender;
- (void)showSettings:(id)sender;
@end
@implementation MMSoakFooter
- (void)hideIcon:(id)sender {}
- (void)showSettings:(id)sender {}
@end

/// Each card that waits for a hover, More submenus included.
static NSArray<NSMenu *> *WaitingCards(NSMenu *m) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSMenuItem *i in m.itemArray) {
        if (!i.submenu) continue;
        if (MMCardWaits(i.submenu)) [out addObject:i.submenu];
        else [out addObjectsFromArray:WaitingCards(i.submenu)];
    }
    return out;
}

/// A hover as the card submenu's delegate runs it, then the layout and drawing the menu does.
static void Hover(NSMenu *card) {
    [card.delegate menuNeedsUpdate:card];
    NSView *v = [card itemAtIndex:0].view;
    if (!v) return;
    [v layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    if (rep) [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
}

static NSString *Stamp(void) {
    static NSISO8601DateFormatter *f;
    if (!f) f = [NSISO8601DateFormatter new];
    return [f stringFromDate:NSDate.date];
}

static NSData *JSONLine(id obj) {
    NSMutableData *d = [[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys error:nil] mutableCopy];
    [d appendBytes:"\n" length:1];
    return d;
}

static volatile sig_atomic_t gStop = 0;

/// The menu round's steps, main thread only. Each runs in a pass of main of its own, 3 ms after the one before.
static NSMutableArray<dispatch_block_t> *gSteps;

static void NextStep(void) {
    if (!gSteps.count || gStop) { [gSteps removeAllObjects]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!gSteps.count) return;
        dispatch_block_t step = gSteps.firstObject;
        [gSteps removeObjectAtIndex:0];
        @autoreleasepool { step(); }
        NextStep();
    });
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Core's worker runs this binary again as `_walk`, as it runs the app. That child is the walker and nothing else.
        if (argc == 2 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();
        if (argc < 2 || strcmp(argv[1], "run") != 0) {
            fprintf(stderr, "usage: soak run --seconds N [--menus-every S] [--status PATH]\n"); return 2;
        }
        NSMutableArray<NSString *> *args = [NSMutableArray new];
        for (int i = 2; i < argc; i++) [args addObject:@(argv[i])];
        NSString *(^opt)(NSString *, NSString *) = ^NSString *(NSString *flag, NSString *dflt) {
            NSUInteger i = [args indexOfObject:flag];
            return i != NSNotFound && i + 1 < args.count ? args[i + 1] : dflt;
        };
        double seconds = opt(@"--seconds", @"3600").doubleValue, menusEvery = opt(@"--menus-every", @"60").doubleValue;
        NSString *statusPath = opt(@"--status", @"");
        if (seconds <= 0 || menusEvery <= 0) { fprintf(stderr, "usage: soak run --seconds N [--menus-every S] [--status PATH]\n"); return 2; }
        if (!SafeEnvironment()) return 2;
        // A session of its own, as test rule 5 asks of a detached fixture: nothing aimed at the run's group reaches it.
        setsid();

        [NSApplication sharedApplication].activationPolicy = NSApplicationActivationPolicyProhibited;
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
        NSUInteger experts = MMRegisterBuiltInExperts();
        NSMutableArray *notIdle = [NSMutableArray new];
        for (id<MMExpert> e in MMExperts()) {
            MMSetMode(e.expertID, MMModeIdle);
            if (MMModeFor(e.expertID) != MMModeIdle) [notIdle addObject:e.expertID];
        }
        if (notIdle.count) { fprintf(stderr, "soak: not Idle: %s\n", [notIdle componentsJoinedByString:@" "].UTF8String); return 1; }

        // SIGTERM ends the run on main, so the summary is still written.
        signal(SIGTERM, SIG_IGN);
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(term, ^{ gStop = 1; CFRunLoopStop(CFRunLoopGetMain()); });
        dispatch_resume(term);

        NSFileHandle *status = nil;
        if (statusPath.length) {
            [NSFileManager.defaultManager createFileAtPath:statusPath contents:nil attributes:nil];
            status = [NSFileHandle fileHandleForWritingAtPath:statusPath];
        }

        __block NSUInteger snapshots = 0;
        id graphToken = [MMGraph.shared observe:^(MMSnapshot *s) { snapshots++; }];
        MMWatchdogStart(MMWatchdogDefaultMs);
        MMCoreStart();

        gSteps = [NSMutableArray new];
        __block NSUInteger menuRounds = 0, menusOpened = 0, cardsHovered = 0;
        NSMutableDictionary<NSString *, NSNumber *> *peak = [NSMutableDictionary new], *peakFixture = [NSMutableDictionary new];
        // A finding about a folder inside MINMACS_HOME is the churn's. LocoHost also lists this Mac's own servers, read
        // only, so its count alone does not show that the fixture servers were seen.
        NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
        __block NSUInteger peakAgents = 0, peakSessions = 0, peakHolds = 0;
        MMSoakFooter *footer = [MMSoakFooter new];
        NSDate *started = NSDate.date;

        // Each expert's menu on the live snapshot, then the One Icon menu, every card hovered. Each open and each hover
        // is a pass of main of its own, 3 ms after the one before, as when the person moves along the menu.
        void (^menus)(void) = ^{
            MMSnapshot *live = MMGraph.shared.current;
            if (!live || gSteps.count) return;   // a round still running is not doubled
            menuRounds++;
            NSMutableArray<NSMenu *(^)(void)> *opens = [NSMutableArray new];
            for (id<MMExpert> e in MMExperts()) [opens addObject:^NSMenu *{ return MMShellMenu(e, live, nil, footer); }];
            [opens addObject:^NSMenu *{ return MMShellOneIconMenu(live, nil, footer); }];
            for (NSMenu *(^open)(void) in opens) {
                [gSteps addObject:^{
                    NSMenu *m = open();
                    if (!m) return;
                    menusOpened++;
                    // The hovers go right after this open, before the next menu's.
                    NSArray *cards = WaitingCards(m);
                    NSMutableArray *hovers = [NSMutableArray new];
                    for (NSMenu *c in cards) [hovers addObject:^{ Hover(c); cardsHovered++; }];
                    [gSteps insertObjects:hovers atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, hovers.count)]];
                }];
            }
            NextStep();
        };
        // What the live snapshot holds, once a minute, and the most each count reached.
        void (^line)(void) = ^{
            MMSnapshot *live = MMGraph.shared.current;
            NSMutableDictionary *findings = [NSMutableDictionary new];
            for (id<MMExpert> e in MMExperts()) {
                NSUInteger n = [live findingsFor:e.expertID].count;
                findings[e.expertID] = @(n);
                if (n > peak[e.expertID].unsignedIntegerValue) peak[e.expertID] = @(n);
                NSUInteger fx = 0;
                for (MMFinding *f in [live findingsFor:e.expertID])
                    if ((f.path && Inside(f.path, home)) || (f.ownerPath && Inside(f.ownerPath, home))) fx++;
                if (fx > peakFixture[e.expertID].unsignedIntegerValue) peakFixture[e.expertID] = @(fx);
            }
            NSUInteger holds = MMAwake.held.count;
            peakAgents = MAX(peakAgents, live.facts.agents.count);
            peakSessions = MAX(peakSessions, live.facts.sessions.count);
            peakHolds = MAX(peakHolds, holds);
            if (!status) return;
            [status writeData:JSONLine(@{@"at": Stamp(), @"uptime": @(round(-started.timeIntervalSinceNow)),
                                         @"generation": @(live.generation), @"snapshots": @(snapshots),
                                         @"findings": findings, @"agents": @(live.facts.agents.count),
                                         @"sessions": @(live.facts.sessions.count), @"awakeHolds": @(holds),
                                         @"menuRounds": @(menuRounds), @"cardsHovered": @(cardsHovered),
                                         @"stalls": @(MMWatchdogStalls().count)})];
        };
        NSTimer *menuTimer = [NSTimer scheduledTimerWithTimeInterval:menusEvery repeats:YES block:^(NSTimer *t) { menus(); }];
        NSTimer *lineTimer = [NSTimer scheduledTimerWithTimeInterval:MIN(60, menusEvery) repeats:YES block:^(NSTimer *t) { line(); }];
        menuTimer.tolerance = 1; lineTimer.tolerance = 1;

        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
        while (!gStop && end.timeIntervalSinceNow > 0) @autoreleasepool {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
        }
        line();
        [menuTimer invalidate]; [lineTimer invalidate];
        MMWatchdogStop();
        NSArray *stalls = MMWatchdogStalls();
        [MMGraph.shared stopObserving:graphToken];
        MMCoreStop();
        NSUInteger records = [MMUndo.shared recent:nil limit:1000].count;
        NSMutableArray *modes = [NSMutableArray new];
        for (id<MMExpert> e in MMExperts()) if (MMModeFor(e.expertID) != MMModeIdle) [modes addObject:e.expertID];

        NSData *d = [NSJSONSerialization dataWithJSONObject:@{
            @"kind": @"soak", @"seconds": @(round(-started.timeIntervalSinceNow)), @"stoppedBy": gStop ? @"SIGTERM" : @"time",
            @"experts": @(experts), @"expertIDs": [MMExperts() valueForKey:@"expertID"],
            @"notIdle": modes, @"undoRecords": @(records), @"snapshots": @(snapshots),
            @"menuRounds": @(menuRounds), @"menusOpened": @(menusOpened), @"cardsHovered": @(cardsHovered),
            @"peakFindings": peak, @"peakFixtureFindings": peakFixture, @"peakAgents": @(peakAgents), @"peakSessions": @(peakSessions), @"peakAwakeHolds": @(peakHolds),
            @"watchdogPasses": @(MMWatchdogPasses()), @"stalls": stalls,
            @"logQueriesOnMain": @(MMLogMainThreadQueries()), @"keepReadsOnMain": @(MMKeepMainThreadReads()),
        } options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        fwrite(d.bytes, 1, d.length, stdout);
        fputc('\n', stdout);
        [status closeFile];
        return 0;
    }
}
