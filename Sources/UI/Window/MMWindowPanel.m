// The panel that holds the window's view: borderless dark glass that hangs under the status item's button.
// It takes the keyboard without making MinMacs the active app. As a menu does, it closes on Escape, on a click
// outside, when it stops being the key window, when another app comes to the front and when the space changes.
#import "UI/Window/MMWindowParts.h"
#import <QuartzCore/CATransaction.h>

@implementation MMWindowPanel {
    id _outside, _inside;               // event monitors, held only while the panel shows
    NSArray *_others, *_own;            // observers on the workspace's center and on the default one, the same
    BOOL _closing;                      // -orderOut: gives up the keyboard, which must not close a second time
    NSDate *_heldUntil;                 // -holdOpen: until then another app coming to the front does not close it
    __weak NSWindow *_anchor;           // the status item's own window: its clicks toggle, they do not count as outside
}

- (instancetype)initWithHost:(id<MMWindowHost>)host {
    NSRect frame = NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height);
    // Not deferred: a window the window server has not made yet draws nothing, so its first frame would wait for the
    // screen. MMWindowHolder makes a panel only when the window is about to open.
    if ((self = [super initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                   backing:NSBackingStoreBuffered defer:NO])) {
        self.opaque = NO; self.backgroundColor = NSColor.clearColor; self.hasShadow = YES;
        self.level = NSStatusWindowLevel;
        self.floatingPanel = YES; self.hidesOnDeactivate = NO; self.becomesKeyOnlyIfNeeded = NO;
        self.releasedWhenClosed = NO;
        self.animationBehavior = NSWindowAnimationBehaviorNone;   // it opens at once, as a menu does
        self.collectionBehavior = NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

        NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:frame];
        glass.material = NSVisualEffectMaterialHUDWindow;
        glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        glass.state = NSVisualEffectStateActive;
        NSImage *mask = [NSImage imageWithSize:NSMakeSize(25, 25) flipped:NO drawingHandler:^BOOL(NSRect r) {
            [NSColor.blackColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:12 yRadius:12] fill];
            return YES;
        }];
        mask.capInsets = NSEdgeInsetsMake(12, 12, 12, 12);
        mask.resizingMode = NSImageResizingModeStretch;
        glass.maskImage = mask;
        glass.wantsLayer = YES;
        glass.layer.cornerRadius = 12; glass.layer.masksToBounds = YES;
        self.contentView = glass;

        _view = [[MMWindowView alloc] initWithFrame:frame];
        _view.host = host;
        _view.wantsLayer = YES;
        [glass addSubview:_view];
        self.initialFirstResponder = _view;
    }
    return self;
}

- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (BOOL)isOpen { return self.isVisible; }

- (void)show:(MMWindowModel *)model { self.view.model = model; }

- (void)toggleUnder:(NSStatusBarButton *)button {
    if (self.isOpen) { [self close]; return; }
    _anchor = button.window;
    NSRect anchor = button.window ? [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]] : NSZeroRect;
    NSScreen *screen = button.window.screen ?: NSScreen.mainScreen;
    NSRect room = screen.visibleFrame;
    NSSize size = MMWindowSize;
    if (!button.window) anchor = NSMakeRect(NSMaxX(room) - 40, NSMaxY(room), 24, 22);
    // Centered under the button, then moved as far as it takes to stay on the screen.
    CGFloat x = MIN(MAX(NSMidX(anchor) - size.width / 2, NSMinX(room) + 8), NSMaxX(room) - size.width - 8);
    CGFloat y = MAX(MIN(NSMinY(anchor), NSMaxY(room)) - 6 - size.height, NSMinY(room) + 8);
    [self openInFrame:NSMakeRect(round(MAX(x, NSMinX(room))), round(y), size.width, size.height) key:YES];
}

- (void)openInFrame:(NSRect)frame key:(BOOL)key {
    [self setFrame:frame display:NO];
    BOOL contrast = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;
    self.appearance = [NSAppearance appearanceNamed:contrast ? NSAppearanceNameAccessibilityHighContrastDarkAqua : NSAppearanceNameDarkAqua];
    // The first frame is drawn before the panel comes on screen.
    [self.view willOpen];
    [self.contentView displayIfNeeded];
    // Layer-backed views draw when Core Animation commits, so the commit comes now, before the panel is ordered in.
    // CATransaction is asked for by name, as CAMediaTimingFunction is, so the render tool links no QuartzCore.
    [(Class)NSClassFromString(@"CATransaction") flush];
    if (self.onWillShow) self.onWillShow();
    if (key) [self makeKeyAndOrderFront:nil]; else [self orderFront:nil];
    [self makeFirstResponder:self.view];
    [self.view opened];
    [self watch];
    if (self.onOpenChange) self.onOpenChange(YES);
}

/// A press anywhere else closes the panel: in another app, or in another window of MinMacs.
- (void)watch {
    __weak typeof(self) me = self;
    NSEventMask downs = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    // A press in an input method's own window, while it composes in Ask MinMacs, is not a press outside.
    if (!_outside) _outside = [NSEvent addGlobalMonitorForEventsMatchingMask:downs handler:^(NSEvent *e) { if (!me.composing) [me close]; }];
    if (!_inside) _inside = [NSEvent addLocalMonitorForEventsMatchingMask:downs handler:^NSEvent *(NSEvent *e) {
        MMWindowPanel *panel = me;
        if (panel && e.window != panel && e.window != panel->_anchor) [panel close];
        return e;
    }];
    if (_others) return;
    void (^shut)(NSNotification *) = ^(NSNotification *n) {
        // MinMacs itself coming to the front is not another app: Settings or an alert took over, and -resignKeyWindow sees that.
        NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
        if (app && app.processIdentifier == getpid()) return;
        if (me.held) return;
        [me close];
    };
    NSNotificationCenter *ws = NSWorkspace.sharedWorkspace.notificationCenter, *own = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    _others = @[[ws addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:main usingBlock:shut],
                [ws addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:main usingBlock:shut]];
    _own = @[[own addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:main usingBlock:shut]];
}

- (void)unwatch {
    if (_outside) { [NSEvent removeMonitor:_outside]; _outside = nil; }
    if (_inside) { [NSEvent removeMonitor:_inside]; _inside = nil; }
    for (id o in _others) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:o];
    for (id o in _own) [NSNotificationCenter.defaultCenter removeObserver:o];
    _others = nil; _own = nil;
}

- (BOOL)composing { NSTextView *t = (NSTextView *)self.firstResponder; return [t isKindOfClass:NSTextView.class] && t.hasMarkedText; }

- (BOOL)watching { return _outside || _inside || _others.count || _own.count; }

/// A press on the status item's own button toggles the panel, so losing the keyboard to that press must not close
/// it first: the toggle would then open it again.
- (BOOL)pressOnAnchor {
    NSWindow *anchor = _anchor;
    return anchor && NSEvent.pressedMouseButtons != 0 && NSPointInRect(NSEvent.mouseLocation, anchor.frame);
}

- (void)resignKeyWindow {
    [super resignKeyWindow];
    // Whatever took the keyboard, an alert of MinMacs or a window of another app, the panel steps aside as a menu does.
    if (self.isVisible && !self.held && ![self pressOnAnchor]) [self close];
}

- (void)holdOpen:(NSTimeInterval)seconds { _heldUntil = seconds > 0 ? [NSDate dateWithTimeIntervalSinceNow:seconds] : nil; }
- (BOOL)held { return _heldUntil && _heldUntil.timeIntervalSinceNow > 0; }

- (void)cancelOperation:(id)sender { [self.view cancelOperation:sender]; }

- (void)close {
    [self unwatch];
    _heldUntil = nil;
    if (!self.isVisible || _closing) return;
    _closing = YES;
    [self orderOut:nil];
    _closing = NO;
    [self.view rest];
    self.view.showsSettings = NO;
    if (self.onOpenChange) self.onOpenChange(NO);
}

- (void)emptyOut {
    [self close];
    self.onOpenChange = nil; self.onWillShow = nil;
    [self.view rest];
    self.initialFirstResponder = nil;
    [self makeFirstResponder:nil];
    self.contentView = nil;
    _view = nil;
    // AppKit can keep an ordered-out window, as the last key window, and with it the window server's backing of its
    // size. One point square, that backing is next to nothing.
    [self setFrame:NSMakeRect(NSMinX(self.frame), NSMinY(self.frame), 1, 1) display:NO];
    [(Class)NSClassFromString(@"CATransaction") flush];
    [super close];
}

- (void)dealloc { [self unwatch]; }

@end
