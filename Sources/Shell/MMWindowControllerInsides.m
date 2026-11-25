// The window controller's part of an app row's insides, MMWindowControllerInsides.h: it asks the app only while the
// window is open and the row's insides show, D11.
#import "Shell/MMWindowControllerInsides.h"

#pragma mark The controller's part

@interface MMWindowController (InsidesPrivate)
- (void)send;
@end

static dispatch_queue_t WindowQueue(void) { return MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED); }
static NSMutableSet<NSString *> *gOpenRows;             // window queue: the app rows whose insides show in the list
static BOOL gLooping;                                   // window queue: a re-ask waits
static id gObserver;                                    // under @synchronized (MMWindowController.class)

@implementation MMWindowController (Insides)

- (void)insidesOpen:(BOOL)open {
    @synchronized (MMWindowController.class) { if (gObserver) [NSNotificationCenter.defaultCenter removeObserver:gObserver]; gObserver = nil; }
    if (open) { [self insidesListen]; return; }
    // Closed: nothing is asked, and the answer is let go, D11.
    dispatch_async(WindowQueue(), ^{ [gOpenRows removeAllObjects]; [MMAppInsides.shared forget]; });
}

/// Hears what cmux told, or a look that ended, from the first ask on while the window is open. Any queue.
- (void)insidesListen {
    @synchronized (MMWindowController.class) {
        if (gObserver) return;
        __weak MMWindowController *weak = self;
        gObserver = [NSNotificationCenter.defaultCenter addObserverForName:MMAppInsidesDidChangeNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *n) { dispatch_async(WindowQueue(), ^{ [weak send]; }); }];
    }
}

/// Window queue. Asks cmux when the window is open, at most once in `every`, and shows the look at once.
- (void)askInsides {
    if (!self.open) return;
    [self insidesListen];
    if ([MMAppInsides.shared want:MMAppInsidesCmux]) [self send];
}

- (BOOL)insidesStory:(NSString *)key {
    if (!self.open || !key.length) return NO;
    dispatch_async(WindowQueue(), ^{
        BOOL ours = [key hasPrefix:@"insides:cmux:"] || [key hasSuffix:MMAppInsidesCmux];
        if (ours) [self askInsides];
    });
    return [key hasPrefix:@"insides:"];
}

- (void)windowInsides:(NSString *)rowKey open:(BOOL)open {
    if (!rowKey.length || !self.open) return;
    dispatch_async(WindowQueue(), ^{
        if (!gOpenRows) gOpenRows = [NSMutableSet new];
        // The view tells every open row at each model: a repeat changes nothing.
        if (open && [gOpenRows containsObject:rowKey]) return;
        if (open) [gOpenRows addObject:rowKey]; else [gOpenRows removeObject:rowKey];
        if (!open || !self.open) return;
        [self askInsides];
        [self loopInsides];
    });
}

/// While insides show in the list and the window is open, cmux is asked again each `every` seconds. Nothing else.
- (void)loopInsides {
    if (gLooping) return;
    gLooping = YES;
    __weak MMWindowController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MMAppInsides.shared.every * NSEC_PER_SEC)), WindowQueue(), ^{
        gLooping = NO;
        MMWindowController *me = weak;
        if (!me.open || !gOpenRows.count) return;
        [me askInsides];
        [me loopInsides];
    });
}

- (BOOL)insidesGoTo:(NSString *)key {
    BOOL isTab = [key hasPrefix:@"insides:cmux:tab:"], isSpace = [key hasPrefix:@"insides:cmux:ws:"] && ![key hasSuffix:@":idle"];
    if (!isTab && !isSpace) return NO;
    dispatch_async(WindowQueue(), ^{
        MMInsidesAnswer *a = [MMAppInsides.shared knownFor:MMAppInsidesCmux];
        NSString *ref = [key substringFromIndex:(isTab ? @"insides:cmux:tab:" : @"insides:cmux:ws:").length];
        for (MMInsidesNode *win in a.root.children) for (MMInsidesNode *space in win.children) {
            BOOL mine = !isTab && ([space.uid isEqualToString:ref] || [space.ref isEqualToString:ref]);
            MMInsidesNode *go = nil, *first = nil;
            for (MMInsidesNode *pane in space.children) for (MMInsidesNode *tab in pane.children) {
                if (isTab && [tab.ref isEqualToString:ref]) go = tab;
                // A workspace goes to its focused pane's selected tab, else to its first.
                if (mine && !go && pane.selected && tab.selected) go = tab;
                if (mine && !first) first = tab;
            }
            go = go ?: first;
            if (!go) continue;
            MMPlace *place = MMPlaceInCmux(win.ref, space.ref, go.ref, go.title);
            dispatch_async(MMQueue(@"core", @"go", QOS_CLASS_USER_INITIATED), ^{
                NSString *err = nil;
                if (!MMGoTo(place, &err) && err) MMNotice(@"minmacs", @"Could Not Go to cmux", err);
            });
            return;
        }
    });
    return YES;
}

@end
