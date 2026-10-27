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

NSString *const MMLoginNotice = @"MinMacs opens at login. Settings can turn that off.";
static NSString *const kLaunchedKey = @"core.launched";          // set on the first launch
static NSString *const kLoginNoticeKey = @"core.loginNoticeUntil";   // seconds since 1970
static NSString *const kOneIconExpert = @"minmacs";               // One Icon uses MinMacs's item and position
static NSString *const kOneIconSymbol = @"gauge.with.dots.needle.33percent";

NSArray<NSString *> *MMBuiltInExpertClasses(void) {
    return @[@"MMMinMacsExpert", @"MMLocoHostExpert", @"MMWorkForestExpert", @"MMNooNooExpert", @"MMInsomniaExpert"];
}

NSUInteger MMRegisterBuiltInExperts(void) {
    NSUInteger n = 0;
    for (NSString *name in MMBuiltInExpertClasses()) {
        Class c = NSClassFromString(name);
        if (![c conformsToProtocol:@protocol(MMExpert)]) continue;
        MMRegisterExpert([c new]);
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

#pragma mark - One status item

/// One expert's status item and menu. The menu is built when it opens, from the current snapshot.
@interface MMExpertItem : NSObject <NSMenuDelegate>
@property (strong) id<MMExpert> expert;                 // nil for the One Icon item
@property (strong) NSStatusItem *item;
@property (strong) NSMenu *menu;
@property (weak) MMShell *shell;
@end

@interface MMShell ()
@property (strong) NSMutableArray<MMExpertItem *> *items;
@property (strong) MMSettings *settings;
@property (strong) id graphToken;
- (NSString *)notice;
- (void)showSettings:(id)sender;
- (void)rebuildItems;
@end

@implementation MMExpertItem

- (MMCardProvider)cardsFor:(id<MMExpert>)e snapshot:(MMSnapshot *)s {
    return ^MMCardSpec *(NSString *fid) {
        MMFinding *f = [s finding:fid];
        return f ? [e cardFor:f snapshot:s] : nil;
    };
}

- (NSMenu *)build {
    MMSnapshot *s = MMGraph.shared.current;
    NSString *notice = [self.shell notice];
    if (!s) {
        NSMenu *m = [NSMenu new];
        [m addItem:MMTextItem(@"MinMacs is taking its first look. It takes a few seconds.", 2)];
        MMAddFooter(m, self);
        return m;
    }
    if (self.expert) return MMMenuFromSpec([self.expert menuFor:s], [self cardsFor:self.expert snapshot:s], notice, self);
    NSMutableArray *parts = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        if (!MMOneIconShows(e.expertID, [e fieldEmptyIn:s], MMIconVisible(e.expertID))) continue;
        MMOneIconPart *p = [MMOneIconPart new];
        p.name = e.name; p.spec = [e menuFor:s]; p.cards = [self cardsFor:e snapshot:s];
        [parts addObject:p];
    }
    return MMOneIconMenu(parts, notice, self);
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSMenu *built = [self build];
    NSArray *items = built.itemArray;
    [built removeAllItems];
    [menu removeAllItems];
    for (NSMenuItem *i in items) [menu addItem:i];
}

- (void)hideIcon:(id)sender { self.item.visible = NO; }
- (void)showSettings:(id)sender { [self.shell showSettings:sender]; }

- (void)update:(MMSnapshot *)s {
    if (!self.expert) {
        NSInteger acts = 0;
        for (id<MMExpert> e in MMExperts()) acts += [MMStatusBadge([e badgeFor:s]) integerValue];
        // The label names the state too, DESIGN.md menu bar rule 5: "MinMacs, 3 to act on".
        NSString *state = acts ? [NSString stringWithFormat:@"%ld to act on", (long)acts] : nil;
        MMUpdateStatusItem(self.item, @"MinMacs", kOneIconSymbol, state, acts ? [NSString stringWithFormat:@"%ld", (long)acts] : nil);
        return;
    }
    id<MMExpert> e = self.expert;
    MMUpdateStatusItem(self.item, e.name, e.symbol, [e accessibilityStateFor:s], [e badgeFor:s]);
    BOOL seen = MMPrefBool(SeenKey(e.expertID), NO);
    NSNumber *v = MMIconVisibleFor([e fieldEmptyIn:s], seen, MMPref(MMIconVisibleKey(e.expertID)) == nil || !MMPrefBool(kLaunchedKey, NO));
    if (v) {
        self.item.visible = v.boolValue;
        if (v.boolValue) MMSetPref(SeenKey(e.expertID), @YES);
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
    // The verbs the app adds to core.sock. Core answers ping and status itself.
    MMCoreServe(@"reopen", ^NSDictionary *(NSDictionary *req) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showSettings:nil]; });
        return @{@"ok": @YES};
    });
    MMCoreServe(@"cli", ^NSDictionary *(NSDictionary *req) { return MMCLIReply(req); });
    MMCoreStart();

    BOOL first = !MMPrefBool(kLaunchedKey, NO);
    if (first) {
        MMStartWatching();
        if (MMMayRegisterLoginItem(NSProcessInfo.processInfo.environment, NSBundle.mainBundle.bundlePath)) {
            NSError *e = nil;
            if ([SMAppService.mainAppService registerAndReturnError:&e])
                MMSetPref(kLoginNoticeKey, @(NSDate.date.timeIntervalSince1970 + 86400));
            else NSLog(@"MinMacs: the login item did not register: %@", e.localizedDescription);
        }
    }
    [self rebuildItems];
    MMSetPref(kLaunchedKey, @YES);
    __weak MMShell *weak = self;
    self.graphToken = [MMGraph.shared observe:^(MMSnapshot *s) { for (MMExpertItem *i in weak.items) [i update:s]; }];
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
- (void)rebuildItems {
    for (MMExpertItem *i in self.items) [NSStatusBar.systemStatusBar removeStatusItem:i.item];
    self.items = [NSMutableArray new];
    NSMutableArray *wanted = [NSMutableArray new];
    if (MMPrefBool(MMOneIconKey, NO)) [wanted addObject:NSNull.null];
    else [wanted addObjectsFromArray:MMExperts()];
    for (id e in wanted) {
        MMExpertItem *x = [MMExpertItem new];
        x.shell = self;
        x.expert = e == NSNull.null ? nil : e;
        NSString *eid = x.expert ? x.expert.expertID : kOneIconExpert;
        x.item = MMMakeStatusItem(x.expert ? x.expert.name : @"MinMacs", x.expert ? x.expert.symbol : kOneIconSymbol);
        // The saved position and the Visible state live under minmacs.<expert id>, which Settings reads too.
        x.item.autosaveName = MMStatusAutosaveName(eid);
        x.menu = [NSMenu new];
        x.menu.delegate = x;
        x.menu.autoenablesItems = NO;
        x.item.menu = x.menu;
        [self.items addObject:x];
        MMSnapshot *s = MMGraph.shared.current;
        if (s) [x update:s];
    }
}

- (MMExpertItem *)itemFor:(NSString *)expert {
    for (MMExpertItem *i in self.items) if ([i.expert.expertID isEqualToString:expert]) return i;
    // In One Icon mode MinMacs's own item is the one icon, under the same autosave name.
    if ([expert isEqualToString:kOneIconExpert]) for (MMExpertItem *i in self.items) if (!i.expert) return i;
    return nil;
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
        x.iconVisible = i ? i.item.visible : MMIconVisible(e.expertID);
        x.mode = MMModeName(MMModeFor(e.expertID));
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
            if (i) i.item.visible = visible; else MMSetPref(MMIconVisibleKey(expert), @(visible));
        };
        st.onMode = ^(NSString *expert, NSString *mode) { NSInteger m = MMModeFrom(mode); if (m >= 0) MMSetMode(expert, (MMMode)m); };
        st.onModel = ^(NSString *model) { MMSetPref(MMReviewModelKey, model); };
        st.onOneIcon = ^(BOOL on) { MMSetPref(MMOneIconKey, @(on)); [weak rebuildItems]; };
        st.onOpenAtLogin = ^(BOOL on) { [weak setLogin:on]; };
        st.onOpenMenu = ^(NSString *expert, NSView *from) {
            MMExpertItem *i = [weak itemFor:expert] ?: weak.items.firstObject;
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

int MMMain(int argc, const char *argv[]) {
    if (MMWantsCLI(argc, argv)) return MMRunCLI(argc, argv);
    NSApplication *app = NSApplication.sharedApplication;
    MMShell *delegate = [MMShell new];
    app.delegate = delegate;
    app.activationPolicy = NSApplicationActivationPolicyAccessory;
    [app run];
    return 0;
}
