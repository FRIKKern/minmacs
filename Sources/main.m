// MinMacs — reclaim your Mac for developers and agents.
// Menu bar app + CLI. Shows exactly what is burning CPU and RAM, and quits
// the apps on your close list, gracefully, with one click. Restore brings them back.
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import "Scanner.h"
#import "Rules.h"

static NSString *const kAskKey        = @"minmacs.askBeforeClosing";   // default YES
static NSString *const kInsomniaKey   = @"minmacs.turnOnInsomnia";     // default YES
static NSString *const kClosedKey     = @"minmacs.closedBundleIDs";    // for Restore
static NSString *const kRepo          = @"FRIKKern/minmacs";

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

#pragma mark - Plan

/// What a MinMacs press would do right now.
@interface MMPlan : NSObject
@property (strong) NSArray<MMApp *> *close, *keep, *unsorted;
@property double closeCPU; @property uint64_t closeMemory;
@end
@implementation MMPlan @end

static MMPlan *MakePlan(MMScanner *s) {
    MMPlan *p = [MMPlan new];
    NSMutableArray *c = [NSMutableArray new], *k = [NSMutableArray new], *u = [NSMutableArray new];
    for (MMApp *a in s.apps) {
        switch ([MMRules.shared verdictFor:a.bundleID]) {
            case MMClose: [c addObject:a]; p.closeCPU += a.cpuPercent; p.closeMemory += a.memory; break;
            case MMKeep:  [k addObject:a]; break;
            default:      [u addObject:a]; break;
        }
    }
    p.close = c; p.keep = k; p.unsorted = u;
    return p;
}

static NSString *Pct(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; }

#pragma mark - Closing

/// Graceful quit only. Returns the apps that did not quit within the grace period
/// (usually because they are asking the user to save something).
static NSArray<MMApp *> *QuitApps(NSArray<MMApp *> *apps, NSTimeInterval grace) {
    for (MMApp *a in apps) [a.app terminate];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:grace];
    NSMutableArray *left = [apps mutableCopy];
    while (left.count && [deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        [left filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMApp *a, id _) { return !a.app.terminated; }]];
    }
    return left;
}

static void RememberClosed(NSArray<MMApp *> *apps) {
    NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSetWithArray:PrefGet(kClosedKey) ?: @[]];
    for (MMApp *a in apps) [ids addObject:a.bundleID];
    PrefSet(kClosedKey, ids.array);
}

static NSArray<NSString *> *ClosedIDs(void) { id v = PrefGet(kClosedKey); return [v isKindOfClass:NSArray.class] ? v : @[]; }

/// Relaunches everything MinMacs closed, in the background, without stealing focus.
static NSInteger RestoreApps(void) {
    NSInteger n = 0;
    dispatch_group_t g = dispatch_group_create();
    for (NSString *bid in ClosedIDs()) {
        NSURL *u = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
        if (!u) continue;
        NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
        cfg.activates = NO;
        dispatch_group_enter(g);
        [NSWorkspace.sharedWorkspace openApplicationAtURL:u configuration:cfg
            completionHandler:^(NSRunningApplication *a, NSError *e) { dispatch_group_leave(g); }];
        n++;
    }
    // Launch requests are asynchronous; give them time to land (matters for the CLI, which exits right after).
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (dispatch_group_wait(g, DISPATCH_TIME_NOW) != 0 && [deadline timeIntervalSinceNow] > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    PrefSet(kClosedKey, nil);
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

static int RunCLI(int argc, const char **argv) {
    NSMutableArray *args = [NSMutableArray new];
    for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
    NSString *cmd = args.firstObject ?: @"plan";
    BOOL json = [args containsObject:@"--json"], yes = [args containsObject:@"--yes"];
    NSString *only = nil; NSUInteger oi = [args indexOfObject:@"--only"];
    if (oi != NSNotFound && oi + 1 < args.count) only = args[oi + 1];

    if ([cmd isEqualToString:@"restore"]) { printf("restored %ld app(s)\n", (long)RestoreApps()); return 0; }
    if ([cmd isEqualToString:@"rules"]) { printf("%s\n", MMRules.shared.fileURL.path.UTF8String); return 0; }
    if (![cmd isEqualToString:@"plan"] && ![cmd isEqualToString:@"run"]) {
        fprintf(stderr, "usage: minmacs [plan|run|restore|rules] [--json] [--yes] [--only <bundle-id>]\n"
                        "  plan     show what MinMacs would close (default)\n"
                        "  run      close the apps on the close list (asks unless --yes)\n"
                        "  restore  relaunch what the last run closed\n"
                        "  rules    print the rules file path\n");
        return 2;
    }

    MMScanner *s = [MMScanner new];
    [s sample]; [NSThread sleepForTimeInterval:1.0]; [s sample];   // two samples for CPU%
    MMPlan *p = MakePlan(s);
    NSArray<MMApp *> *targets = only ? [p.close filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID == %@", only]] : p.close;

    if (json) {
        NSMutableArray *(^enc)(NSArray *) = ^(NSArray<MMApp *> *arr) {
            NSMutableArray *o = [NSMutableArray new];
            for (MMApp *a in arr) [o addObject:@{@"name": a.name, @"bundleID": a.bundleID, @"cpu": @(round(a.cpuPercent)),
                                                 @"memoryBytes": @(a.memory), @"processes": @(a.processCount)}];
            return o;
        };
        NSDictionary *j = @{@"close": enc(targets), @"keep": enc(p.keep), @"unsorted": enc(p.unsorted),
                            @"reclaimableCPU": @(round(p.closeCPU)), @"reclaimableMemoryBytes": @(p.closeMemory),
                            @"thermal": @(NSProcessInfo.processInfo.thermalState)};
        NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    } else {
        PrintApps(@"Will close", targets);
        PrintApps(@"Kept (developer and agent essentials)", p.keep);
        PrintApps(@"Unsorted (never touched; sort them in the menu or rules file)", p.unsorted);
        printf("Reclaimable: %s CPU, %s memory\n", Pct(p.closeCPU).UTF8String, MMFormatBytes(p.closeMemory).UTF8String);
    }
    if ([cmd isEqualToString:@"plan"]) return 0;

    if (!targets.count) { printf("nothing to close\n"); return 0; }
    if (!yes) {
        printf("Quit these %lu app(s)? [y/N] ", (unsigned long)targets.count); fflush(stdout);
        char buf[8] = {0}; if (!fgets(buf, sizeof buf, stdin) || (buf[0] != 'y' && buf[0] != 'Y')) { printf("aborted\n"); return 1; }
    }
    RememberClosed(targets);
    NSArray *left = QuitApps(targets, 8);
    for (MMApp *a in left) printf("still running (probably asking to save): %s\n", a.name.UTF8String);
    printf("closed %lu of %lu\n", (unsigned long)(targets.count - left.count), (unsigned long)targets.count);
    return left.count ? 3 : 0;
}

#pragma mark - App

@interface MinMacs : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) MMScanner *scanner;
@property (strong) NSTimer *timer;
@property (strong) MMPlan *plan;
@end

@implementation MinMacs

- (BOOL)ask { return PrefBool(kAskKey, YES); }
- (BOOL)insomnia { return PrefBool(kInsomniaKey, YES); }

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.scanner = [MMScanner new];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(handleClick:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self.scanner sample];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:4 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    self.timer.tolerance = 1;
    [self tick];
}

- (void)tick {
    [self.scanner sample];
    self.plan = MakePlan(self.scanner);
    [self refreshIcon];
}

- (void)refreshIcon {
    BOOL restorable = ClosedIDs().count > 0;
    NSImage *img = [NSImage imageWithSystemSymbolName:restorable ? @"gauge.with.dots.needle.0percent" : @"gauge.with.dots.needle.67percent"
                                accessibilityDescription:@"MinMacs"]
                   ?: [NSImage imageWithSystemSymbolName:@"speedometer" accessibilityDescription:@"MinMacs"];
    img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]];
    img.template = YES;
    self.statusItem.button.image = img;
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"MinMacs: %lu app(s) to close, %@ CPU and %@ reclaimable",
                                      (unsigned long)self.plan.close.count, Pct(self.plan.closeCPU), MMFormatBytes(self.plan.closeMemory)];
}

#pragma mark Menu

static NSMenuItem *Item(NSMenu *m, NSString *t, SEL a, id target, BOOL on) {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:@""];
    i.target = target; i.state = on ? NSControlStateValueOn : NSControlStateValueOff; [m addItem:i]; return i;
}

- (NSMenuItem *)appItem:(MMApp *)a verdict:(MMVerdict)v {
    NSString *title = [NSString stringWithFormat:@"%@   %@ · %@", a.name, Pct(a.cpuPercent), MMFormatBytes(a.memory)];
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    i.image = a.app.icon; i.image.size = NSMakeSize(16, 16);
    NSMenu *sub = [NSMenu new];
    Item(sub, a.bundleID, NULL, nil, NO).enabled = NO;
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"Close on MinMacs", @selector(markClose:), self, v == MMClose).representedObject = a.bundleID;
    Item(sub, @"Keep (never close)", @selector(markKeep:), self, v == MMKeep).representedObject = a.bundleID;
    Item(sub, @"Unsorted (list only)", @selector(markUnsorted:), self, v == MMUnsorted).representedObject = a.bundleID;
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"Quit Now", @selector(quitOne:), self, NO).representedObject = a;
    i.submenu = sub;
    return i;
}

- (void)handleClick:(id)sender {
    [self tick];
    MMPlan *p = self.plan;
    NSMenu *menu = [NSMenu new];
    static NSString *const th[] = { @"nominal", @"fair", @"serious", @"critical" };
    Item(menu, [NSString stringWithFormat:@"%lu apps · system load %@ · thermal %@",
                (unsigned long)self.scanner.apps.count, Pct(self.scanner.totalCPU), th[NSProcessInfo.processInfo.thermalState]], NULL, nil, NO).enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];

    NSString *go = p.close.count ? [NSString stringWithFormat:@"MinMacs Now: close %lu app%@ (%@ CPU · %@)", (unsigned long)p.close.count,
                                     p.close.count == 1 ? @"" : @"s", Pct(p.closeCPU), MMFormatBytes(p.closeMemory)]
                                 : @"MinMacs Now: nothing on the close list is running";
    NSMenuItem *goItem = Item(menu, go, @selector(minmacsNow), self, NO);
    goItem.enabled = p.close.count > 0;
    goItem.image = [NSImage imageWithSystemSymbolName:@"bolt.fill" accessibilityDescription:nil];
    if (ClosedIDs().count)
        Item(menu, [NSString stringWithFormat:@"Restore %lu closed app%@", (unsigned long)ClosedIDs().count, ClosedIDs().count == 1 ? @"" : @"s"],
             @selector(restore), self, NO);
    [menu addItem:NSMenuItem.separatorItem];

    Item(menu, [NSString stringWithFormat:@"Will close (%lu)", (unsigned long)p.close.count], NULL, nil, NO).enabled = NO;
    for (MMApp *a in p.close) [menu addItem:[self appItem:a verdict:MMClose]];
    if (p.unsorted.count) {
        Item(menu, [NSString stringWithFormat:@"Unsorted, not touched (%lu)", (unsigned long)p.unsorted.count], NULL, nil, NO).enabled = NO;
        for (MMApp *a in p.unsorted) [menu addItem:[self appItem:a verdict:MMUnsorted]];
    }
    NSMenuItem *keptItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Kept, essentials (%lu)", (unsigned long)p.keep.count] action:nil keyEquivalent:@""];
    NSMenu *kept = [NSMenu new];
    for (MMApp *a in p.keep) [kept addItem:[self appItem:a verdict:MMKeep]];
    keptItem.submenu = kept;
    [menu addItem:keptItem];

    NSMenuItem *sysItem = [[NSMenuItem alloc] initWithTitle:@"Background load (system, informational)" action:nil keyEquivalent:@""];
    NSMenu *sys = [NSMenu new];
    NSInteger shown = 0;
    for (MMProc *pr in self.scanner.unattributed) {
        if (shown++ >= 8) break;
        Item(sys, [NSString stringWithFormat:@"%@   %@ · %@   (pid %d)", pr.name, Pct(pr.cpuPercent), MMFormatBytes(pr.footprint), pr.pid], NULL, nil, NO).enabled = NO;
    }
    sysItem.submenu = sys;
    [menu addItem:sysItem];
    [menu addItem:NSMenuItem.separatorItem];

    Item(menu, @"Ask Before Closing", @selector(toggleAsk), self, self.ask);
    Item(menu, @"Also Turn On Insomnia", @selector(toggleInsomnia), self, self.insomnia).enabled = InsomniaInstalled();
    Item(menu, @"Edit Rules…", @selector(editRules), self, NO);
    Item(menu, @"Launch at Login", @selector(toggleLogin), self, SMAppService.mainAppService.status == SMAppServiceStatusEnabled);
    [menu addItem:NSMenuItem.separatorItem];
    Item(menu, @"Quit MinMacs", @selector(quit), self, NO).keyEquivalent = @"q";

    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;
}

#pragma mark Actions

- (void)minmacsNow { [self runWithConfirm:self.ask]; }

- (void)runWithConfirm:(BOOL)confirm {
    [self tick];
    NSArray<MMApp *> *targets = self.plan.close;
    if (!targets.count) return;
    if (confirm) {
        NSAlert *a = [NSAlert new];
        a.messageText = [NSString stringWithFormat:@"Quit %lu app%@ and reclaim %@ CPU, %@?", (unsigned long)targets.count,
                         targets.count == 1 ? @"" : @"s", Pct(self.plan.closeCPU), MMFormatBytes(self.plan.closeMemory)];
        NSMutableString *list = [NSMutableString new];
        for (MMApp *t in targets) [list appendFormat:@"•  %@   (%@ · %@)\n", t.name, Pct(t.cpuPercent), MMFormatBytes(t.memory)];
        [list appendString:@"\nApps get a normal Quit, never a force kill, so unsaved work will ask first. Restore brings them all back."];
        a.informativeText = list;
        [a addButtonWithTitle:@"Quit Them"]; [a addButtonWithTitle:@"Cancel"];
        a.suppressionButton.title = @"Don't ask again"; a.showsSuppressionButton = YES;
        [NSApp activateIgnoringOtherApps:YES];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (a.suppressionButton.state == NSControlStateValueOn) PrefSet(kAskKey, @NO);
    }
    RememberClosed(targets);
    if (self.insomnia && InsomniaInstalled()) [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"insomnia://on"]];
    NSArray *left = QuitApps(targets, 8);
    [self tick];
    if (left.count) {
        NSAlert *a = [NSAlert new];
        a.messageText = [NSString stringWithFormat:@"%lu app%@ did not quit", (unsigned long)left.count, left.count == 1 ? @"" : @"s"];
        a.informativeText = [[left valueForKeyPath:@"name"] componentsJoinedByString:@", "];
        a.informativeText = [a.informativeText stringByAppendingString:@"\n\nUsually they are asking you to save something. MinMacs never force-quits."];
        [NSApp activateIgnoringOtherApps:YES]; [a runModal];
    }
}

- (void)restore { RestoreApps(); [self performSelector:@selector(tick) withObject:nil afterDelay:2]; }
- (void)quitOne:(NSMenuItem *)i { MMApp *a = i.representedObject; RememberClosed(@[a]); QuitApps(@[a], 8); [self tick]; }
- (void)markClose:(NSMenuItem *)i    { [MMRules.shared setVerdict:MMClose forBundleID:i.representedObject]; [self tick]; }
- (void)markKeep:(NSMenuItem *)i     { [MMRules.shared setVerdict:MMKeep forBundleID:i.representedObject]; [self tick]; }
- (void)markUnsorted:(NSMenuItem *)i { [MMRules.shared setVerdict:MMUnsorted forBundleID:i.representedObject]; [self tick]; }
- (void)toggleAsk { PrefSet(kAskKey, @(!self.ask)); }
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
        if (argc > 1 && argv[1][0] != '-') return RunCLI(argc, argv);    // CLI mode: minmacs plan|run|restore|rules
        NSApplication *app = NSApplication.sharedApplication;
        MinMacs *delegate = [MinMacs new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
