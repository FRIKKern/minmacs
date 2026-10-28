// The app delegate and the status items. Ported from the main() and -toggleLogin of LocoHost and WorkForest,
// and the URL handlers of LocoHost and MinMacs 1.2, now one router in Sources/CLI/MMRouter.
#import "Shell/MMShell.h"
#import <ServiceManagement/ServiceManagement.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "CLI/MMRouter.h"
#import "UI/MMUI.h"
#import "UI/MMSettings.h"
#import "UI/MMSpecMenu.h"
#import "Shell/MMWatchdog.h"

NSString *const MMLoginNotice = @"MinMacs opens at login. Settings can turn that off.";
static NSString *const kLaunchedKey = @"core.launched";          // set on the first launch
static NSString *const kLoginNoticeKey = @"core.loginNoticeUntil";   // seconds since 1970
static NSString *const kOneIconExpert = @"minmacs";               // One Icon stands in for MinMacs's item in Settings
NSString *const MMOneIconAutosaveName = @"minmacs.oneicon";
static NSString *const kOneIconSymbol = @"gauge.with.dots.needle.33percent";

NSArray<NSString *> *MMBuiltInExpertClasses(void) {
    return @[@"MMMinMacsExpert", @"MMLocoHost", @"MMWorkForestExpert", @"MMNooNooExpert", @"MMInsomniaExpert"];
}

NSUInteger MMRegisterBuiltInExperts(void) {
    NSUInteger n = 0;
    for (NSString *name in MMBuiltInExpertClasses()) {
        Class c = NSClassFromString(name);
        if (![c conformsToProtocol:@protocol(MMExpert)]) continue;
        // An expert with a shared instance registers that one, so its verbs and menus see the same object.
        id<MMExpert> e = [c respondsToSelector:@selector(shared)] ? [c performSelector:@selector(shared)] : [c new];
        MMRegisterExpert(e);
        n++;
    }
    return n;
}

BOOL MMMayRegisterLoginItem(NSDictionary<NSString *, NSString *> *env, NSString *bundlePath) {
#ifdef MM_TESTS
    return NO;
#else
    if (env[@"MINMACS_HOME"].length || env[@"MM_TESTS"].length) return NO;
    return [bundlePath.pathExtension isEqualToString:@"app"];
#endif
}

NSNumber *MMIconVisibleFor(BOOL fieldEmpty, BOOL seen, BOOL firstLaunch) {
    if (seen) return nil;
    if (!fieldEmpty) return @YES;                          // the field appeared: show the icon, once
    return firstLaunch ? @NO : nil;
}

BOOL MMOneIconShows(NSString *expertID, BOOL fieldEmpty, BOOL iconVisible) {
    if (fieldEmpty) return NO;
    // MinMacs's own visible state is the one icon's, so it never hides its own section.
    return iconVisible || [expertID isEqualToString:kOneIconExpert];
}

static NSString *SeenKey(NSString *expert) { return [NSString stringWithFormat:@"core.fieldSeen.%@", expert]; }

#pragma mark - Menus

static MMCardProvider CardsFor(id<MMExpert> e, MMSnapshot *s) {
    return ^MMCardSpec *(NSString *fid) {
        MMFinding *f = [s finding:fid];
        return f ? [e cardFor:f snapshot:s] : nil;
    };
}

/// A row gets a card when its finding is in the snapshot. The card itself waits for the hover.
static MMCardCheck HasCard(MMSnapshot *s) { return ^BOOL(NSString *fid) { return [s finding:fid] != nil; }; }

NSMenu *MMShellMenu(id<MMExpert> e, MMSnapshot *s, NSString *notice, id footerTarget) {
    return MMMenuFromSpecOnHover([e menuFor:s], HasCard(s), CardsFor(e, s), notice, footerTarget);
}

NSMenu *MMShellOneIconMenu(MMSnapshot *s, NSString *notice, id footerTarget) {
    NSMutableArray *parts = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        if (!MMOneIconShows(e.expertID, [e fieldEmptyIn:s], MMIconVisible(e.expertID))) continue;
        MMOneIconPart *p = [MMOneIconPart new];
        p.name = e.name; p.spec = [e menuFor:s]; p.cards = CardsFor(e, s); p.has = HasCard(s);
        [parts addObject:p];
    }
    return MMOneIconMenu(parts, notice, footerTarget);
}

/// The finding a link names, as the snapshot holds it. An expert may name a path as the repo index keeps it, such as
/// /var/folders/x, where WorkForest keeps the kernel's /private/var/folders/x, so both spellings are tried.
static NSString *LinkedFinding(MMSnapshot *s, NSString *fid) {
    if (!fid.length || [s finding:fid]) return fid;
    for (NSString *dir in @[@"/var/", @"/tmp/"]) {
        NSString *bare = [@":" stringByAppendingString:dir], *priv = [@":/private" stringByAppendingString:dir];
        NSString *alt = [fid containsString:priv] ? [fid stringByReplacingOccurrencesOfString:priv withString:bare]
                      : [fid containsString:bare] ? [fid stringByReplacingOccurrencesOfString:bare withString:priv] : nil;
        if (alt && [s finding:alt]) return alt;
    }
    return fid;
}

/// One expert's menu, or with expert nil the One Icon menu. focusID names the finding a link opened, in focusExpert.
static NSMenu *BuildMenu(id<MMExpert> expert, MMSnapshot *s, NSString *notice, id footer, NSString *focusExpert, NSString *focusID) {
    if (!focusID.length) return expert ? MMShellMenu(expert, s, notice, footer) : MMShellOneIconMenu(s, notice, footer);
    focusID = LinkedFinding(s, focusID);
    if (expert) {
        NSString *focus = [expert.expertID isEqualToString:focusExpert] ? focusID : nil;
        return MMMenuFromSpecFocused([expert menuFor:s], CardsFor(expert, s), notice, footer, focus);
    }
    NSMutableArray *parts = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        BOOL linked = [e.expertID isEqualToString:focusExpert];
        // A link names a finding, so its expert shows even when the person hid its section.
        if (!linked && !MMOneIconShows(e.expertID, [e fieldEmptyIn:s], MMIconVisible(e.expertID))) continue;
        MMOneIconPart *p = [MMOneIconPart new];
        p.name = e.name; p.spec = [e menuFor:s]; p.cards = CardsFor(e, s); p.has = HasCard(s);
        if (linked) p.focusID = focusID;
        [parts addObject:p];
    }
    return MMOneIconMenu(parts, notice, footer);
}

NSMenu *MMLinkMenu(NSString *expertID, NSString *findingID, MMSnapshot *s, BOOL oneIcon, id footerTarget) {
    id<MMExpert> e = MMExpertNamed(expertID);
    if (!e || !s) return nil;
    return BuildMenu(oneIcon ? nil : e, s, nil, footerTarget, expertID, findingID);
}

#pragma mark - Startup times

static uint64_t gStartNs;
static NSMutableDictionary *gStartup;      // main only
static BOOL gTraceSummaries;                // the bench asks for each expert's first summary line

static uint64_t NowNs(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

void MMStartupBegin(void) {
    gStartNs = NowNs();
    gStartup = [NSMutableDictionary new];
}

static void Mark(NSString *key) {
    if (!gStartNs || !gStartup || gStartup[key]) return;
    gStartup[key] = @(round((NowNs() - gStartNs) / 1e4) / 100);
}

NSDictionary *MMStartupTimes(void) { return [gStartup copy] ?: @{}; }

#pragma mark - One status item

/// One expert's status item and menu. The menu is built when it opens, from the current snapshot.
@interface MMExpertItem : NSObject <NSMenuDelegate>
@property (strong) id<MMExpert> expert;                 // nil for the One Icon item
@property (strong) NSStatusItem *item;                  // nil until made, and always nil headless
@property BOOL made;                                    // the item is made, or counted as made headless
@property BOOL seen;                                    // core.fieldSeen.<expert>, read once
@property BOOL summarized;
@property (strong) NSMenu *menu;
@property (weak) MMShell *shell;
- (void)label:(MMSnapshot *)s;
@property (copy) NSString *focusExpert, *focusID;       // the link that opens the menu next, cleared when it closes
@end

@interface MMShell ()
@property (strong) NSMutableArray<MMExpertItem *> *items;
@property (strong) MMSettings *settings;
@property (strong) id graphToken;
@property BOOL headless;                                // the bench: no NSStatusItem and no NSApp run loop
@property BOOL sawSnapshot;
- (NSString *)notice;
- (void)showSettings:(id)sender;
- (void)rebuildItems;
- (void)launch;
@end

@implementation MMExpertItem

- (NSString *)itemName { return self.expert ? self.expert.name : @"MinMacs"; }
- (NSString *)itemSymbol { return self.expert ? self.expert.symbol : kOneIconSymbol; }
- (NSString *)visibleKey { return self.expert ? MMIconVisibleKey(self.expert.expertID) : MMIconVisibleKey(@"oneicon"); }

/// Makes the status item. Headless, it makes the icon image and label the item would show, and no item.
- (void)make {
    if (self.made) return;
    self.made = YES;
    if (self.shell.headless) { (void)MMStatusImage(self.itemSymbol, MMStatusLabel(self.itemName, nil)); return; }
    // The saved position and the Visible state live under minmacs.<expert id>, which Settings reads too.
    // The one icon has a name of its own, so its Hide Icon never hides MinMacs's own item.
    self.item = MMMakeStatusItemSaved(self.itemName, self.itemSymbol, self.expert ? MMStatusAutosaveName(self.expert.expertID) : MMOneIconAutosaveName);
    self.menu = [NSMenu new];
    self.menu.delegate = self;
    self.menu.autoenablesItems = NO;
    self.item.menu = self.menu;
}

- (BOOL)visible { return self.item ? self.item.visible : MMPrefBool(self.visibleKey, YES); }

/// Shows or hides the icon. An item not made yet is made to be shown. Headless, the pref stands in for the item.
- (void)setVisible:(BOOL)on {
    if (on && !self.made) [self make];
    if (self.item) self.item.visible = on;
    else MMSetPref(self.visibleKey, @(on));
}


@implementation MMExpertItem

- (NSMenu *)build {
    MMSnapshot *s = MMGraph.shared.current;
    NSString *notice = [self.shell notice];
    if (!s) {
        NSMenu *m = [NSMenu new];
        [m addItem:MMTextItem(@"MinMacs is taking its first look. It takes a few seconds.", 2)];
        MMAddFooter(m, self);
        return m;
    }
    return BuildMenu(self.expert, s, notice, self, self.focusExpert, self.focusID);
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSMenu *built = [self build];
    NSArray *items = built.itemArray;
    [built removeAllItems];
    [menu removeAllItems];
    for (NSMenuItem *i in items) [menu addItem:i];
}

- (void)menuDidClose:(NSMenu *)menu { self.focusExpert = nil; self.focusID = nil; }

- (void)hideIcon:(id)sender { [self setVisible:NO]; }
- (void)showSettings:(id)sender { [self.shell showSettings:sender]; }

/// The expert item's label, state and badge from this snapshot. Headless, only the label is made.
- (void)label:(MMSnapshot *)s {
    id<MMExpert> e = self.expert;
    NSString *state = [e accessibilityStateFor:s], *badge = [e badgeFor:s];
    if (self.item) MMUpdateStatusItem(self.item, e.name, e.symbol, state, badge);
    else (void)MMStatusLabel(e.name, state);
}

- (void)update:(MMSnapshot *)s {
    if (!self.expert) {
        NSInteger acts = 0;
        for (id<MMExpert> e in MMExperts()) acts += [MMStatusBadge([e badgeFor:s]) integerValue];
        // The label names the state too, DESIGN.md menu bar rule 5: "MinMacs, 3 to act on".
        NSString *state = acts ? [NSString stringWithFormat:@"%ld to act on", (long)acts] : nil;
        NSString *badge = acts ? [NSString stringWithFormat:@"%ld", (long)acts] : nil;
        if (self.item) MMUpdateStatusItem(self.item, @"MinMacs", kOneIconSymbol, state, badge);
        else (void)MMStatusLabel(@"MinMacs", state);
        return;
    }
    id<MMExpert> e = self.expert;
    if (gTraceSummaries && !self.summarized && [e menuFor:s].summary.length) {
        self.summarized = YES;
        Mark([@"summary." stringByAppendingString:e.expertID]);
    }
    BOOL empty = [e fieldEmptyIn:s];
    // An item not made yet waits for its field. Only the first time the field appears does it show, as DESIGN.md asks.
    if (!self.made) {
        if (empty || self.seen) return;
        [self setVisible:YES];
        self.seen = YES;
        MMSetPref(SeenKey(e.expertID), @YES);
    }
    [self label:s];
    if (self.seen) return;
    NSNumber *v = MMIconVisibleFor(empty, NO, MMPref(self.visibleKey) == nil || !MMPrefBool(kLaunchedKey, NO));
    if (v) {
        [self setVisible:v.boolValue];
        if (v.boolValue) { self.seen = YES; MMSetPref(SeenKey(e.expertID), @YES); }
    }
}

@end

#pragma mark - The app

@implementation MMShell

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // A second copy hands over to the one that runs: it opens Settings there, as opening MinMacs again does.
    if (MMAnotherInstanceRuns()) {
        [MMCoreSocket ask:@{@"verb": @"reopen"} timeout:1];
        [NSApp terminate:nil];
        return;
    }
    if (MMWatchdogWanted(NSProcessInfo.processInfo.environment)) MMWatchdogStart(MMWatchdogDefaultMs);
    [self launch];
}

/// The launch after the instance check, shared with the bench's headless start.
- (void)launch {
    // The verbs the app adds to core.sock. Core answers ping and status itself.
    MMCoreServe(@"reopen", ^NSDictionary *(NSDictionary *req) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showSettings:nil]; });
        return @{@"ok": @YES};
    });
    MMCoreServe(@"cli", ^NSDictionary *(NSDictionary *req) { return MMCLIReply(req); });
    MMCoreStart();
    Mark(@"core");

    BOOL first = !MMPrefBool(kLaunchedKey, NO);
    if (first) {
        MMStartWatching();
        if (!self.headless && MMMayRegisterLoginItem(NSProcessInfo.processInfo.environment, NSBundle.mainBundle.bundlePath)) {
            NSError *e = nil;
            if ([SMAppService.mainAppService registerAndReturnError:&e])
                MMSetPref(kLoginNoticeKey, @(NSDate.date.timeIntervalSince1970 + 86400));
            else NSLog(@"MinMacs: the login item did not register: %@", e.localizedDescription);
        }
    }
    [self rebuildItems];
    MMSetPref(kLaunchedKey, @YES);
    __weak MMShell *weak = self;
    // Every card's link rows open through here, whichever expert drew the card.
    MMSetLinkOpener(^(NSString *expert, NSString *key) { [weak openLink:expert finding:key]; });
    self.graphToken = [MMGraph.shared observe:^(MMSnapshot *s) {
        MMShell *me = weak;
        if (!me) return;
        if (!me.sawSnapshot) { me.sawSnapshot = YES; Mark(@"snapshot"); }
        BOOL all = YES;
        for (MMExpertItem *i in me.items) { [i update:s]; if (i.expert && !i.summarized) all = NO; }
        if (gTraceSummaries && all) Mark(@"summaries");
    }];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [MMGraph.shared stopObserving:self.graphToken];
    MMCoreStop();
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag {
    [self showSettings:nil];
    return NO;
}

- (NSString *)notice {
    double until = MMPrefDouble(kLoginNoticeKey, 0);
    return until > NSDate.date.timeIntervalSince1970 ? MMLoginNotice : nil;
}

/// Five icons by default, decision 3. One Icon gives MinMacs's item a flat menu with a section per expert.
/// An expert whose icon was hidden at the last run waits: no status item, menu or update until its field appears or
/// Settings shows it. On this Mac that is an expert with an empty field, or one the person hid.
- (void)rebuildItems {
    for (MMExpertItem *i in self.items) if (i.item) [NSStatusBar.systemStatusBar removeStatusItem:i.item];
    self.items = [NSMutableArray new];
    NSMutableArray *wanted = [NSMutableArray new];
    if (MMPrefBool(MMOneIconKey, NO)) [wanted addObject:NSNull.null];
    else [wanted addObjectsFromArray:MMExperts()];
    NSMutableArray *made = [NSMutableArray new], *deferred = [NSMutableArray new];
    MMSnapshot *s = MMGraph.shared.current;
    for (id e in wanted) {
        MMExpertItem *x = [MMExpertItem new];
        x.shell = self;
        x.expert = e == NSNull.null ? nil : e;
        NSString *eid = x.expert ? x.expert.expertID : @"oneicon";
        x.seen = x.expert && MMPrefBool(SeenKey(eid), NO);
        BOOL wait = x.expert && MMPref(x.visibleKey) != nil && !MMPrefBool(x.visibleKey, YES);
        if (!wait) [x make];
        [(wait ? deferred : made) addObject:eid];
        [self.items addObject:x];
        if (s) [x update:s];
    }
    if (gStartup && !gStartup[@"made"]) { gStartup[@"made"] = made; gStartup[@"deferred"] = deferred; }
    Mark(@"items");
}

- (MMExpertItem *)itemFor:(NSString *)expert {
    for (MMExpertItem *i in self.items) if ([i.expert.expertID isEqualToString:expert]) return i;
    // In One Icon mode the one icon stands in for MinMacs's own item, under its own autosave name.
    if ([expert isEqualToString:kOneIconExpert]) for (MMExpertItem *i in self.items) if (!i.expert) return i;
    return nil;
}

/// A link row was picked. Its menu is closing, so the linked expert's menu opens on the next turn of the run loop,
/// with the linked card as its first row. In One Icon mode the one icon opens. An item the system hides, or one the
/// person hid, cannot open, so the same menu pops up at the pointer instead.
- (void)openLink:(NSString *)expert finding:(NSString *)findingID {
    MMExpertItem *i = MMPrefBool(MMOneIconKey, NO) ? nil : [self itemFor:expert];
    if (!i) for (MMExpertItem *x in self.items) if (!x.expert) i = x;
    if (!i) return;
    i.focusExpert = expert; i.focusID = findingID;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSStatusBarButton *b = i.item.button;
        if (i.item.visible && (b.window.occlusionState & NSWindowOcclusionStateVisible)) {
            [b performClick:nil];
            return;
        }
        NSMenu *m = [i build];
        i.focusExpert = nil; i.focusID = nil;
        [m popUpMenuPositioningItem:nil atLocation:NSEvent.mouseLocation inView:nil];
    });
}

- (BOOL)loginEnabled { return SMAppService.mainAppService.status == SMAppServiceStatusEnabled; }

- (void)setLogin:(BOOL)on {
    if (!MMMayRegisterLoginItem(NSProcessInfo.processInfo.environment, NSBundle.mainBundle.bundlePath)) return;
    if (self.loginEnabled == on) return;
    NSError *e = nil;
    BOOL ok = on ? [SMAppService.mainAppService registerAndReturnError:&e] : [SMAppService.mainAppService unregisterAndReturnError:&e];
    if (!ok) NSBeep();
    if (!on) MMSetPref(kLoginNoticeKey, nil);
}

- (void)fillSettings {
    MMSnapshot *s = MMGraph.shared.current;
    NSMutableArray *rows = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        MMSettingsExpert *x = [MMSettingsExpert expert:e.expertID name:e.name symbol:e.symbol];
        if (s) {
            MMMenuSpec *m = [e menuFor:s];
            x.headline = MMHeaderLine(m);
            NSString *first = [m.summary componentsSeparatedByString:@". "].firstObject;
            x.summary = first.length ? MMSentence(first) : nil;
        }
        MMExpertItem *i = [self itemFor:e.expertID];
        x.iconVisible = i ? i.visible : MMIconVisible(e.expertID);
        x.mode = MMModeName(MMModeFor(e.expertID));
        // An expert's own prefs get a pane of their own. The expert reads what it holds, never disk.
        if ([e respondsToSelector:@selector(prefSpecs)]) x.prefs = [e prefSpecs];
        [rows addObject:x];
    }
    self.settings.experts = rows;
    self.settings.model = MMPrefString(MMReviewModelKey, @"auto");
    self.settings.oneIcon = MMPrefBool(MMOneIconKey, NO);
    self.settings.openAtLogin = self.loginEnabled;
}

- (void)showSettings:(id)sender {
    if (!self.settings) {
        MMSettings *st = [MMSettings new];
        __weak MMShell *weak = self;
        // In One Icon mode an expert has no item of its own, so its visible state goes to the pref its item reads.
        st.onIcon = ^(NSString *expert, BOOL visible) {
            MMExpertItem *i = [weak itemFor:expert];
            if (i) [i setVisible:visible]; else MMSetPref(MMIconVisibleKey(expert), @(visible));
            // An item made just now shows its state and badge from the current snapshot, not only at the next one.
            if (visible && i.item && i.expert && MMGraph.shared.current) [i label:MMGraph.shared.current];
        };
        st.onMode = ^(NSString *expert, NSString *mode) { NSInteger m = MMModeFrom(mode); if (m >= 0) MMSetMode(expert, (MMMode)m); };
        st.onModel = ^(NSString *model) { MMSetPref(MMReviewModelKey, model); };
        st.onOneIcon = ^(BOOL on) { MMSetPref(MMOneIconKey, @(on)); [weak rebuildItems]; };
        st.onOpenAtLogin = ^(BOOL on) { [weak setLogin:on]; };
        st.onPref = ^(NSString *expert, NSString *key, NSNumber *value) {
            id<MMExpert> e = MMExpertNamed(expert);
            if ([e respondsToSelector:@selector(setPref:value:)]) [e setPref:key value:value];
        };
        st.onOpenMenu = ^(NSString *expert, NSView *from) {
            MMExpertItem *i = [weak itemFor:expert];
            // In One Icon mode the expert has no item, so the one icon's menu opens. An item left for later stays shut.
            if (!i) for (MMExpertItem *x in weak.items) if (x.item.visible) { i = x; break; }
            [i.item.button performClick:nil];
        };
        self.settings = st;
    }
    [self fillSettings];
    [self.settings reload];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settings show:MMSettingsOverview];
}

- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        MMRoute *r = MMRouteURL(u, nil);
        switch (r.kind) {
            case MMRouteQuit: [NSApp terminate:nil]; break;
            case MMRouteLoginOn: [self setLogin:YES]; break;
            case MMRouteLoginOff: [self setLogin:NO]; break;
            case MMRouteSettings: [self showSettings:nil]; break;
            case MMRouteExpert: {
                id<MMExpert> e = MMExpertNamed(r.expert);
                BOOL handled = [e respondsToSelector:@selector(openURL:)] && [e openURL:r.url];
                if (!handled && r.words) {
                    // A verb that blocks, such as a review, runs off main, as it does for the CLI.
                    NSArray *words = r.words;
                    dispatch_async(MMQueue(@"core", @"url", QOS_CLASS_USER_INITIATED), ^{ MMCLIReply(@{@"cli": words}); });
                }
                break;
            }
            case MMRouteNone: break;
        }
    }
}

@end

id MMShellStartHeadless(void) {
    MMShell *shell = [MMShell new];
    shell.headless = YES;
    gTraceSummaries = YES;
    [shell launch];
    return shell;
}

void MMShellStopHeadless(id shell) {
    MMShell *sh = shell;
    [MMGraph.shared stopObserving:sh.graphToken];
    MMCoreStop();
}

int MMMain(int argc, const char *argv[]) {
    MMStartupBegin();
    if (MMWantsCLI(argc, argv)) return MMRunCLI(argc, argv);
    NSApplication *app = NSApplication.sharedApplication;
    MMShell *delegate = [MMShell new];
    app.delegate = delegate;
    app.activationPolicy = NSApplicationActivationPolicyAccessory;
    [app run];
    return 0;
}
