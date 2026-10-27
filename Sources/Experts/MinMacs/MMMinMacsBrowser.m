// Browser tabs: read, close and reopen, aimed at one process id. Ported from Browser.m on branch legacy.
// ScriptingBridge is loaded when a tab is first read, so build.sh links no extra framework
// and an app that never trims a browser never loads it.
#import <AppKit/AppKit.h>
#import "Experts/MinMacs/MMMinMacs.h"

@implementation MMMinMacsTab
@end

static NSSet *Chromium(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSSet setWithArray:@[@"com.google.Chrome", @"com.google.Chrome.canary", @"org.chromium.Chromium",
        @"com.brave.Browser", @"com.microsoft.edgemac", @"com.vivaldi.Vivaldi", @"com.operasoftware.Opera"]]; });
    return s;
}
// Browsers whose scripting model MinMacs does not speak.
static NSSet *Untrimmable(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSSet setWithArray:@[@"company.thebrowser.Browser", @"org.mozilla.firefox"]]; });
    return s;
}

static NSMutableSet *TestBrowsers(void) {
    static NSMutableSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}
static BOOL IsTestBrowser(NSString *b) { @synchronized (TestBrowsers()) { return b && [TestBrowsers() containsObject:b]; } }
#ifdef MM_TESTS
void MMMinMacsAddTestBrowser(NSString *bundleID) { if (bundleID) @synchronized (TestBrowsers()) { [TestBrowsers() addObject:bundleID]; } }
#endif

static BOOL IsChromium(NSString *b) { return [Chromium() containsObject:b] || IsTestBrowser(b); }
BOOL MMMinMacsCanTrim(NSString *b) { return b.length && (IsChromium(b) || [b isEqualToString:@"com.apple.Safari"]); }
BOOL MMMinMacsIsBrowser(NSString *b) { return MMMinMacsCanTrim(b) || [Untrimmable() containsObject:b]; }

#pragma mark Apple events

// The ScriptingBridge calls this file makes, declared here so nothing links the framework.
@protocol MMMinMacsSBElements <NSObject>
- (NSArray *)arrayByApplyingSelector:(SEL)selector;
- (id)objectWithID:(id)identifier;
- (NSUInteger)count;
- (id)objectAtIndexedSubscript:(NSUInteger)i;
@end
@protocol MMMinMacsSBObject <NSObject>
- (id)get;
- (id)sendEvent:(AEEventClass)eventClass id:(AEEventID)eventID parameters:(DescType)firstParamCode, ...;
@end
@protocol MMMinMacsSBApp <NSObject>
@property long timeout;
@end

static Class SBApplicationClass(void) {
    static Class c; static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/ScriptingBridge.framework"] load];
        c = NSClassFromString(@"SBApplication");
    });
    return c;
}

static id Get(id obj, NSString *key) {
    @try { id v = [obj valueForKey:key]; return [v respondsToSelector:@selector(get)] ? [v get] : v; }
    @catch (NSException *e) { return nil; }
}

static NSString *HostOf(NSString *url) {
    NSString *h = [NSURL URLWithString:url ?: @""].host.lowercaseString ?: @"";
    return [h hasPrefix:@"www."] ? [h substringFromIndex:4] : h;
}

/// Apple events through ScriptingBridge, to one process id. The person's permission is asked by macOS
/// the first time, under Privacy and Security, Automation.
@interface MMMinMacsAppleEvents : NSObject <MMMinMacsTabBridge>
@end

@implementation MMMinMacsAppleEvents

- (id)appFor:(pid_t)pid {
    Class sb = SBApplicationClass();
    // applicationWithProcessIdentifier: takes a pid_t, so it is called through an IMP of the right type.
    SEL sel = NSSelectorFromString(@"applicationWithProcessIdentifier:");
    if (!sb || ![sb respondsToSelector:sel]) return nil;
    id (*make)(id, SEL, pid_t) = (id (*)(id, SEL, pid_t))[sb methodForSelector:sel];
    id<MMMinMacsSBApp> a = make(sb, sel, pid);
    if ([a respondsToSelector:@selector(setTimeout:)]) a.timeout = 5 * 60;   // ticks: five seconds
    return a;
}

- (NSArray<MMMinMacsTab *> *)tabsOf:(pid_t)pid bundleID:(NSString *)bid error:(NSString **)error {
    if (!MMMinMacsCanTrim(bid)) { if (error) *error = @"MinMacs cannot read this browser's tabs"; return nil; }
    id app = [self appFor:pid];
    if (!app) { if (error) *error = @"Apple events are not available"; return nil; }
    BOOL chromium = IsChromium(bid);
    NSMutableArray<MMMinMacsTab *> *out = [NSMutableArray new];
    @try {
        id<MMMinMacsSBElements> windows = [app valueForKey:@"windows"];
        NSArray *wids = [windows arrayByApplyingSelector:NSSelectorFromString(@"id")];
        if (!wids) { if (error) *error = @"MinMacs may not read tabs. Allow it in System Settings, Privacy and Security, Automation"; return nil; }
        for (NSUInteger w = 0; w < wids.count; w++) {
            id window = [windows objectWithID:wids[w]];
            // Only Chromium's incognito windows are skipped. Safari's scripting does not say which windows are private.
            if (chromium && [[Get(window, @"mode") description] isEqualToString:@"incognito"]) continue;
            id<MMMinMacsSBElements> tabs = [window valueForKey:@"tabs"];
            NSArray *urls = [tabs arrayByApplyingSelector:NSSelectorFromString(@"URL")];
            NSArray *titles = [tabs arrayByApplyingSelector:NSSelectorFromString(chromium ? @"title" : @"name")];
            NSArray *ids = chromium ? [tabs arrayByApplyingSelector:NSSelectorFromString(@"id")] : nil;
            for (NSUInteger i = 0; i < urls.count; i++) {
                MMMinMacsTab *t = [MMMinMacsTab new];
                t.url = [urls[i] isKindOfClass:NSString.class] ? urls[i] : @"";
                t.title = i < titles.count && [titles[i] isKindOfClass:NSString.class] ? titles[i] : t.url;
                t.windowID = [wids[w] integerValue];
                t.tabID = chromium ? [ids[i] integerValue] : (NSInteger)i + 1;
                t.host = HostOf(t.url);
                [out addObject:t];
            }
        }
    } @catch (NSException *e) {
        if (error) *error = [@"could not read tabs: " stringByAppendingString:e.reason ?: e.name];
        return nil;
    }
    return out;
}

- (NSArray<MMMinMacsTab *> *)close:(NSArray<MMMinMacsTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bid {
    NSMutableArray<MMMinMacsTab *> *closed = [NSMutableArray new];
    if (!tabs.count || !MMMinMacsCanTrim(bid)) return closed;
    id app = [self appFor:pid];
    if (!app) return closed;
    BOOL chromium = IsChromium(bid);
    // Safari names tabs by index, so each window closes from its highest index down.
    NSArray *ordered = [tabs sortedArrayUsingComparator:^NSComparisonResult(MMMinMacsTab *a, MMMinMacsTab *b) {
        if (a.windowID != b.windowID) return a.windowID < b.windowID ? NSOrderedAscending : NSOrderedDescending;
        return a.tabID > b.tabID ? NSOrderedAscending : a.tabID < b.tabID ? NSOrderedDescending : NSOrderedSame;
    }];
    @try {
        id<MMMinMacsSBElements> windows = [app valueForKey:@"windows"];
        for (MMMinMacsTab *t in ordered) {
            id window = [windows objectWithID:@(t.windowID)];
            id<MMMinMacsSBElements> wt = [window valueForKey:@"tabs"];
            id<MMMinMacsSBObject> tab = chromium ? [wt objectWithID:@(t.tabID)] : (t.tabID - 1 < (NSInteger)wt.count ? wt[(NSUInteger)(t.tabID - 1)] : nil);
            if (!tab) continue;
            // A tab that moved on since it was read stays open.
            NSString *now = Get(tab, @"URL");
            if (![now isKindOfClass:NSString.class] || ![now isEqualToString:t.url]) continue;
            [tab sendEvent:'core' id:'clos' parameters:0];
            [closed addObject:t];
        }
    } @catch (NSException *e) {
    }
    return closed;
}

- (NSString *)open:(NSArray<NSString *> *)urls bundleID:(NSString *)bid appPath:(NSString *)path {
    NSMutableArray<NSURL *> *list = [NSMutableArray new];
    for (NSString *u in urls) { NSURL *x = [NSURL URLWithString:u]; if (x) [list addObject:x]; }
    if (!list.count) return nil;
    NSURL *app = path.length ? [NSURL fileURLWithPath:path] : [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
    if (!app) return @"the browser is no longer installed";
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.activates = NO;
    __block NSString *problem = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [NSWorkspace.sharedWorkspace openURLs:list withApplicationAtURL:app configuration:cfg
                        completionHandler:^(NSRunningApplication *a, NSError *e) {
        if (e) problem = [@"the tabs would not open: " stringByAppendingString:e.localizedDescription];
        dispatch_semaphore_signal(done);
    }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0) return @"the browser took too long to open the tabs";
    return problem;
}

@end

static id<MMMinMacsTabBridge> gBridge;
void MMMinMacsUseTabBridge(id<MMMinMacsTabBridge> bridge) { @synchronized (MMMinMacsTab.class) { gBridge = bridge; } }
id<MMMinMacsTabBridge> MMMinMacsTabBridgeNow(void) {
    @synchronized (MMMinMacsTab.class) {
        if (!gBridge) gBridge = [MMMinMacsAppleEvents new];
        return gBridge;
    }
}
