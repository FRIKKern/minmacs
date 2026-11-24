// Who holds the menu window's panel. Drawn once, the panel, its views and their layers hold about 100 MB of
// IOSurface and graphics memory, and a panel that is only ordered out keeps all of it. So once the window has stayed
// closed for a while the panel is let go, and the next open makes it again. Its first frame is still drawn before it
// comes on screen, from the last model the window was sent.
#import "UI/Window/MMWindowParts.h"

const NSTimeInterval MMWindowRestSeconds = 45;

@implementation MMWindowHolder {
    __weak id<MMWindowHost> _host;
    MMWindowPanel *_panel;
    MMWindowModel *_last;          // the newest model, for the first frame of a panel made again
    NSUInteger _turn;              // each open and close counts on, so a wait from an earlier close lets nothing go
}

- (instancetype)initWithHost:(id<MMWindowHost>)host {
    if ((self = [super init])) { _host = host; _rest = MMWindowRestSeconds; }
    return self;
}

- (MMWindowPanel *)panel {
    if (_panel) return _panel;
    _panel = [[MMWindowPanel alloc] initWithHost:_host];
    _made++;
    __weak typeof(self) me = self;
    _panel.onOpenChange = ^(BOOL open) { [me openChanged:open]; };
    if (_last) [_panel show:_last];
    return _panel;
}

- (nullable MMWindowPanel *)madePanel { return _panel; }
- (BOOL)isOpen { return _panel.isOpen; }

- (void)show:(MMWindowModel *)model {
    _last = model;
    [_panel show:model];
}

- (void)openChanged:(BOOL)open {
    _turn++;
    if (!open) [self restFor:_rest turn:_turn];
    if (self.onOpenChange) self.onOpenChange(open);
}

/// One wait, never a timer: when it ends and nothing opened the window since, the panel goes.
- (void)restFor:(NSTimeInterval)seconds turn:(NSUInteger)turn {
    if (seconds < 0) return;
    __weak typeof(self) me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MMWindowHolder *h = me;
        if (!h || turn != h->_turn || h->_panel.isOpen) return;
        // A run of Fix Everything that plays keeps the window as it is, and is asked again a while later.
        if (h.busy && h.busy()) { [h restFor:MAX(seconds, 1) turn:turn]; return; }
        [h letGo];
    });
}

- (void)letGo {
    if (!_panel || _panel.isOpen) return;
    // A welcome that is gone from the view, since Start was pressed, does not come back in the next panel.
    // A model made before the first snapshot holds nothing else, so none is kept then.
    if (_last.welcome && !_panel.view.showsWelcome) {
        if (_last.generation) _last.welcome = nil; else _last = nil;
    }
    _lastLetGo = _panel;
    [_panel emptyOut];
    _panel = nil;
}

@end
