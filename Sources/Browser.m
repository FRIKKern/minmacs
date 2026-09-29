#import "Browser.h"
#import "Rules.h"
#import <ScriptingBridge/ScriptingBridge.h>

@implementation MMTab @end

static NSSet *Chromium(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [NSSet setWithArray:@[@"com.google.Chrome", @"com.google.Chrome.canary", @"org.chromium.Chromium",
        @"com.brave.Browser", @"com.microsoft.edgemac", @"com.vivaldi.Vivaldi", @"com.operasoftware.Opera"]]; });
    return s;
}
static NSSet *Untrimmable(void) {   // browsers whose scripting model MinMacs does not speak
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [NSSet setWithArray:@[@"company.thebrowser.Browser", @"org.mozilla.firefox"]]; });
    return s;
}

@implementation MMBrowser

+ (BOOL)canTrim:(NSString *)b { return [Chromium() containsObject:b] || [b isEqualToString:@"com.apple.Safari"]; }
+ (BOOL)isBrowser:(NSString *)b { return [self canTrim:b] || [Untrimmable() containsObject:b]; }

static id Get(id obj, NSString *key) {
    @try { id v = [obj valueForKey:key]; return [v respondsToSelector:@selector(get)] ? [v get] : v; }
    @catch (NSException *e) { return nil; }
}

+ (NSArray<MMTab *> *)tabsOfPid:(pid_t)pid bundleID:(NSString *)bid error:(NSString **)error {
    if (![self canTrim:bid]) { if (error) *error = @"tabs of this browser cannot be read"; return nil; }
    SBApplication *app = [SBApplication applicationWithProcessIdentifier:pid];
    app.timeout = 5 * 60;   // ticks: five seconds
    BOOL chromium = [Chromium() containsObject:bid];
    NSMutableArray<MMTab *> *out = [NSMutableArray new];
    @try {
        SBElementArray *windows = [app valueForKey:@"windows"];
        NSArray *wids = [windows arrayByApplyingSelector:NSSelectorFromString(@"id")];
        if (!wids) { if (error) *error = @"not allowed to read tabs. Allow MinMacs under System Settings, Privacy and Security, Automation"; return nil; }
        for (NSUInteger w = 0; w < wids.count; w++) {
            id window = [windows objectWithID:wids[w]];
            if (chromium && [[Get(window, @"mode") description] isEqualToString:@"incognito"]) continue;
            SBElementArray *tabs = [window valueForKey:@"tabs"];
            NSArray *urls = [tabs arrayByApplyingSelector:NSSelectorFromString(@"URL")];
            NSArray *titles = [tabs arrayByApplyingSelector:NSSelectorFromString(chromium ? @"title" : @"name")];
            NSArray *ids = chromium ? [tabs arrayByApplyingSelector:NSSelectorFromString(@"id")] : nil;
            for (NSUInteger i = 0; i < urls.count; i++) {
                MMTab *t = [MMTab new];
                t.url = [urls[i] isKindOfClass:NSString.class] ? urls[i] : @"";
                t.title = (i < titles.count && [titles[i] isKindOfClass:NSString.class]) ? titles[i] : t.url;
                t.windowID = [wids[w] integerValue];
                t.tabID = chromium ? [ids[i] integerValue] : (NSInteger)i + 1;
                t.host = [NSURL URLWithString:t.url].host.lowercaseString ?: @"";
                if ([t.host hasPrefix:@"www."]) t.host = [t.host substringFromIndex:4];
                t.verdict = [MMRules.shared tabVerdictForHost:t.host];
                [out addObject:t];
            }
        }
    } @catch (NSException *e) {
        if (error) *error = [NSString stringWithFormat:@"could not read tabs: %@", e.reason ?: e.name];
        return nil;
    }
    return out;
}

+ (NSInteger)closeTabs:(NSArray<MMTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bid {
    if (!tabs.count || ![self canTrim:bid]) return 0;
    SBApplication *app = [SBApplication applicationWithProcessIdentifier:pid];
    app.timeout = 5 * 60;
    BOOL chromium = [Chromium() containsObject:bid];
    NSInteger closed = 0;
    // Safari addresses tabs by index, so close from the highest index down within each window.
    NSArray *ordered = [tabs sortedArrayUsingComparator:^NSComparisonResult(MMTab *a, MMTab *b) {
        if (a.windowID != b.windowID) return a.windowID < b.windowID ? NSOrderedAscending : NSOrderedDescending;
        return a.tabID > b.tabID ? NSOrderedAscending : a.tabID < b.tabID ? NSOrderedDescending : NSOrderedSame;
    }];
    @try {
        SBElementArray *windows = [app valueForKey:@"windows"];
        for (MMTab *t in ordered) {
            id window = [windows objectWithID:@(t.windowID)];
            SBElementArray *wt = [window valueForKey:@"tabs"];
            SBObject *tab = chromium ? [wt objectWithID:@(t.tabID)] : (t.tabID - 1 < (NSInteger)wt.count ? wt[t.tabID - 1] : nil);
            if (!tab) continue;
            // Never close a tab that navigated somewhere else since the plan was shown.
            NSString *now = Get(tab, @"URL");
            if (![now isKindOfClass:NSString.class] || ![now isEqualToString:t.url]) continue;
            [tab sendEvent:'core' id:'clos' parameters:0];
            closed++;
        }
    } @catch (NSException *e) { }
    return closed;
}

@end
