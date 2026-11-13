// Checks of the menu window that need real fades, issue #62. tools/render.m includes this file after
// render-window-look.m and uses its WelcomeHost, WelcomeWindow, WelcomeHit and WindowLists. It is not built on its own.

#pragma mark In a window that is really ordered in

/// The view in a window that is ordered in far off every screen, so fades run as they do in the panel and nobody
/// sees it. It takes no mouse and never becomes key.
static NSWindow *ShownWindow(MMWindowView *v) {
    NSWindow *win = WelcomeWindow(v);
    v.wantsLayer = YES;
    win.ignoresMouseEvents = YES;
    [win setFrameOrigin:NSMakePoint(-30000, -30000)];
    [win orderBack:nil];
    return win;
}

static void Spin(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }

static NSArray<NSButton *> *Options(NSView *v) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *sub in v.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"MMWindowOption"]) [out addObject:sub];
        [out addObjectsFromArray:Options(sub)];
    }
    return out;
}

/// What only shows with real fades: the turn to Settings, a close inside Start's guard, and a welcome that comes
/// after Settings was asked for. And the panel's hold for a window opened by a way to Settings.
static void WindowShownChecks(void) {
    NSRect frame = NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height);
    BOOL motion = !MMWindowReduceMotion();

    // The turn to Settings: while the two sides fade, neither takes a press. Right after, both do.
    WelcomeHost *host = [WelcomeHost new];
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:frame];
    v.host = host;
    NSWindow *win = ShownWindow(v);
    v.model = MMWindowFixture(@"removal");
    MMWindowDockView *dock = nil;
    for (NSView *sub in WindowLists(v).firstObject.superview.subviews) if ([sub isKindOfClass:MMWindowDockView.class]) dock = (MMWindowDockView *)sub;
    v.showsSettings = YES;
    NSButton *option = nil;
    for (NSButton *o in Options(v)) if (![[o valueForKey:@"picked"] boolValue] && ![[o valueForKey:@"isSwitch"] boolValue]) { option = o; break; }
    BOOL heldOption = !MMWindowTakesPresses(option), heldFix = !MMWindowTakesPresses(dock.fix);
    [option performClick:nil]; [dock.fix performClick:nil];
    NSInteger during = host.rules + host.fixes;
    Spin(0.4);
    BOOL freeOption = MMWindowTakesPresses(option);
    [option performClick:nil];
    Check(win.isVisible && option && dock && (!motion || (heldOption && heldFix)) && during == (motion ? 0 : 1) && freeOption && host.rules == (motion ? 1 : 2) && host.fixes == 0,
          @"window shown: while the window turns to Settings no choice and no Fix Everything takes a press, and right after a choice does",
          [NSString stringWithFormat:@"visible %d, held %d %d, %ld during, %ld rules, %ld fixes", win.isVisible, heldOption, heldFix, (long)during, (long)host.rules, (long)host.fixes]);
    // Back to the menu: the same hold, then Fix Everything takes its press.
    v.showsSettings = NO;
    [dock.fix performClick:nil];
    NSInteger duringBack = host.fixes;
    Spin(0.4);
    [dock.fix performClick:nil];
    Check(duringBack == (motion ? 0 : 1) && host.fixes == (motion ? 1 : 2), @"window shown: turning back holds Fix Everything the same way, then lets it go",
          [NSString stringWithFormat:@"%ld during, %ld after", (long)duringBack, (long)host.fixes]);
    [win close];

    // Start, the window closed inside the guard, opened again: the guard starts over, so no press runs a fix at once.
    host = [WelcomeHost new];
    v = [[MMWindowView alloc] initWithFrame:frame];
    v.host = host;
    win = ShownWindow(v);
    MMWindowModel *m = MMWindowFixture(@"busy");
    m.welcome = MMWindowFixture(@"welcome").welcome;
    v.model = m;
    v.welcomeView.arrival = 1;
    NSButton *start = v.welcomeView.controls.lastObject;
    NSRect at = start.frame;
    MMWindowWelcomeView *w = v.welcomeView;
    WelcomePress(WelcomeHit(v, at, w));
    Spin(0.2);
    [win orderOut:nil]; [v rest];                       // as the panel closes
    [v willOpen]; [win orderBack:nil]; [v opened];      // as it opens
    dock = nil;
    for (NSView *sub in WindowLists(v).firstObject.superview.subviews) if ([sub isKindOfClass:MMWindowDockView.class]) dock = (MMWindowDockView *)sub;
    NSView *hit = WelcomeHit(v, at, w);
    WelcomePress(hit); [dock.fix performClick:nil];
    NSInteger early = host.fixes;
    BOOL there = !dock.superview.hidden && dock.superview.alphaValue == 1 && !v.showsWelcome;
    Spin(MMWindowStartGuard + 0.2);
    WelcomePress(WelcomeHit(v, at, w));
    Check(host.starts == 1 && there && early == 0 && host.fixes == 1,
          @"window shown: closed inside the guard after Start and opened again, the menu is there and takes no press until the guard has run from the opening",
          [NSString stringWithFormat:@"%ld starts, there %d, %ld at once, %ld after", (long)host.starts, there, (long)early, (long)host.fixes]);
    [win close];

    // Settings asked for, then a welcome model: Settings is hidden at once, with nothing fading under the welcome.
    v = [[MMWindowView alloc] initWithFrame:frame];
    win = ShownWindow(v);
    v.showsSettings = YES;
    NSView *settings = nil;
    for (NSView *sub in v.subviews) if ([sub isKindOfClass:MMWindowSettingsView.class]) settings = sub;
    BOOL was = settings && !settings.hidden && v.showsSettings;
    MMWindowModel *bare = [MMWindowModel new];
    bare.welcome = MMWindowFixture(@"welcome").welcome;
    v.model = bare;
    BOOL atOnce = settings.hidden && !v.showsSettings && v.showsWelcome;
    Spin(0.4);
    Check(was && atOnce && settings.hidden && settings.alphaValue == 1 && v.showsWelcome, @"window shown: a welcome that comes while Settings shows hides Settings at once, and it stays hidden",
          [NSString stringWithFormat:@"was %d, at once %d, hidden %d", was, atOnce, settings.hidden]);
    [win close];

    // A window opened by a way to Settings is held open for a moment, and a close ends the hold.
    MMWindowPanel *panel = [[MMWindowPanel alloc] initWithHost:nil];
    BOOL before = panel.held;
    [panel holdOpen:0.2];
    BOOL during2 = panel.held;
    Spin(0.3);
    BOOL after = panel.held;
    [panel holdOpen:5]; [panel close];
    Check(!before && during2 && !after && !panel.held && !panel.isOpen, @"window shown: the panel's hold lasts as long as asked and no longer", [NSString stringWithFormat:@"%d %d %d", before, during2, after]);
}

