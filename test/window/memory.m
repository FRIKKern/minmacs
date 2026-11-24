// What the closed menu window holds, and that a reopen still draws its first frame before it shows. test/window.sh
// builds this with Sources/UI and runs it. It never starts the app, Core or a scan: it makes an MMWindowHolder as the
// shell does, gives it a fixture model and opens its panel far off every screen, where nobody sees it.
// Each footprint is this process's own, from proc_pid_rusage, as the field sampler reads the app.
// Usage: memory <rest seconds> [more rounds]
// Prints "CHECK\t<name>\t<want>\t<got>" and "info\t<line>" lines, then END.
#import <Cocoa/Cocoa.h>
#import <libproc.h>
#import <sys/resource.h>
#import <malloc/malloc.h>
#import <QuartzCore/QuartzCore.h>
#import "UI/Window/MMWindowParts.h"

static void Check(BOOL ok, NSString *name, NSString *got) {
    printf("CHECK\twindow memory: %s\tyes\t%s\n", name.UTF8String, ok ? "yes" : [NSString stringWithFormat:@"no (%@)", got].UTF8String);
}
static void Info(NSString *line) { printf("info\t%s\n", line.UTF8String); fflush(stdout); }

static double FootprintMB(void) {
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return -1;
    return ri.ri_phys_footprint / 1048576.0;
}

static void Spin(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }

/// The footprint once the frees of the last moment have landed: the lowest of a few reads a little apart. Free malloc
/// pages are given back first, as the system takes them under pressure, so what is counted is what is held.
static double Settled(NSTimeInterval seconds) {
    double low = 1e9;
    for (int i = 0; i < 4; i++) { Spin(seconds / 4); malloc_zone_pressure_relief(NULL, 0); low = MIN(low, FootprintMB()); }
    return low;
}

/// What a process pays once, the first time it draws a window this large, as the app has done for its status item
/// and the first open: the GPU, Core Animation, the fonts. A plain window, not the holder's panel, draws a view with
/// the same model far off every screen and is closed and let go, and the baseline is read after it.
static void WarmUp(MMWindowModel *model) { @autoreleasepool {
    NSRect frame = NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.ignoresMouseEvents = YES;
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:frame];
    glass.wantsLayer = YES;
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:frame];
    v.wantsLayer = YES;
    v.model = model;
    [glass addSubview:v];
    w.contentView = glass;
    [w setFrameOrigin:NSMakePoint(-30000, -30000)];
    [w.contentView displayIfNeeded];
    [CATransaction flush];
    [w orderBack:nil];
    Spin(1);
    [w orderOut:nil];
    w.contentView = nil;
}}

/// YES when every layer under the view holds drawn contents, or draws none of its own, and nothing waits to be drawn.
static BOOL Drawn(NSView *v, NSMutableArray<NSString *> *why) {
    if (v.hidden) return YES;
    if (v.needsDisplay) [why addObject:[NSString stringWithFormat:@"%@ needs display", v.class]];
    BOOL ok = !v.needsDisplay;
    for (NSView *sub in v.subviews) ok = Drawn(sub, why) && ok;
    return ok;
}

/// Opens the holder's panel as the icon does, far off every screen, and says what the first frame was at the moment
/// it came on screen. The panel takes the keyboard as it does for the person, and gives it back at the close.
static double Open(MMWindowHolder *h, BOOL *drawn, NSString *__strong *why) { @autoreleasepool {
    __block BOOL firstDrawn = NO;
    __block NSString *what = @"never shown";
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    MMWindowPanel *p = h.panel;
    __weak MMWindowPanel *wp = p;
    p.onWillShow = ^{
        MMWindowPanel *p = wp;
        NSMutableArray *w = [NSMutableArray new];
        MMWindowView *v = p.view;
        BOOL model = v.model != nil, contents = v.layer.contents != nil || v.layer.sublayers.count;
        if (!model) [w addObject:@"no model"];
        if (!contents) [w addObject:@"the window's layer holds nothing drawn"];
        firstDrawn = Drawn(p.contentView, w) && model && contents;
        what = w.count ? [w componentsJoinedByString:@", "] : @"";
    };
    [p openInFrame:NSMakeRect(-30000, -30000, MMWindowSize.width, MMWindowSize.height) key:YES];
    double ms = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e6;
    p.onWillShow = nil;
    *drawn = firstDrawn; *why = what;
    return ms;
}}

// Each ask of the holder in a pool of its own, so this tool's own autoreleased returns never keep a panel alive.
static BOOL Held(MMWindowHolder *h) { @autoreleasepool { return h.madePanel != nil; } }
static void Close(MMWindowHolder *h) { @autoreleasepool { [h.madePanel close]; } }
static BOOL Is(MMWindowHolder *h, MMWindowPanel *p) { @autoreleasepool { return h.madePanel == p; } }
static BOOL Shows(MMWindowHolder *h, MMWindowModel *m) { @autoreleasepool { return h.madePanel.view.model == m; } }

int main(int argc, char **argv) { @autoreleasepool {
    NSTimeInterval rest = argc > 1 ? atof(argv[1]) : 3;
    NSApplication *app = NSApplication.sharedApplication;
    app.activationPolicy = NSApplicationActivationPolicyAccessory;
    [app finishLaunching];
    MMWindowModel *model = MMWindowFixture(@"busy");
    MMWindowHolder *h = [[MMWindowHolder alloc] initWithHost:nil];
    h.rest = rest;
    __block BOOL busy = NO;
    h.busy = ^BOOL { return busy; };
    [h show:model];
    WarmUp(model);
    double base = Settled(3);

    BOOL drawn; NSString *why;
    double cold = Open(h, &drawn, &why);
    Check(h.isOpen && drawn, @"the first open draws the first frame from the model before the panel comes on screen", why);
    double open = Settled(2);
    __weak MMWindowPanel *first = nil;
    @autoreleasepool { first = h.madePanel; }
    Close(h);
    double closed = Settled(1);
    Check(Held(h), @"a second after the close the panel is still held, so a quick reopen is the same panel", @"let go at once");

    // A quick reopen inside the rest takes the same panel, and its close starts the rest over.
    double warm = Open(h, &drawn, &why);
    Check(Is(h, first) && h.made == 1 && drawn, @"a reopen inside the rest takes the same panel, drawn before it shows", why);
    Close(h);

    // A run that plays keeps the panel past its rest.
    busy = YES;
    Spin(rest + 1.5);
    Check(Held(h), @"while a run plays the panel is kept past its rest", @"let go");
    busy = NO;
    Spin(MAX(rest, 1) + 1.5);
    Check(!Held(h), @"once the run ended the panel goes at the next ask", @"still held");
    double after = Settled(3);
    BOOL gone = NO;
    @autoreleasepool { gone = first == nil; }
    Check(gone, @"nothing holds on to the views of the panel that was let go", @"the panel is still alive");

    double again = Open(h, &drawn, &why);
    Check(h.isOpen && h.made == 2 && drawn && Shows(h, model),
          @"a reopen after the panel was let go makes it again and draws the last model before it shows", why);
    double reopened = Settled(2);
    Close(h);
    Spin(rest + 1.5);
    double second = Settled(3);
    Check(!Held(h), @"the second panel goes after its rest too", @"still held");

    // More rounds when asked, for the numbers: each after its rest.
    NSMutableArray *rounds = [NSMutableArray new];
    for (int i = 0, n = argc > 2 ? atoi(argv[2]) : 0; i < n; i++) {
        Open(h, &drawn, &why); Spin(1); Close(h); Spin(rest + 1.5);
        [rounds addObject:[NSString stringWithFormat:@"%.1f", Settled(2)]];
    }
    if (rounds.count) Info([@"footprint MB after each later round: " stringByAppendingString:[rounds componentsJoinedByString:@", "]]);
    Info([NSString stringWithFormat:@"footprint MB: launch %.1f, open %.1f, 1 s after close %.1f, after the rest %.1f, reopened %.1f, after the second rest %.1f",
          base, open, closed, after, reopened, second]);
    Info([NSString stringWithFormat:@"open ms: first %.1f, reopen inside the rest %.1f, reopen after the rest %.1f", cold, warm, again]);
    // Drawn once, the window holds about 40 MB here, and a kept panel reads near 60 MB over the baseline after its
    // rest. Let go, it reads 15 to 21 MB over: what the first draw of a window this large costs a process once, the GPU
    // and Core Animation, which later rounds do not add to. So 35 MB allows for noise and still sees a panel kept.
    double slack = 35;
    Check(after - base < slack && second - base < slack, @"after the rest the footprint is back within 35 MB of the baseline",
          [NSString stringWithFormat:@"%.1f and %.1f MB over the baseline of %.1f", after - base, second - base, base]);
    Check(reopened - second > 20, @"the rest gives back at least 20 MB of what the reopened window held",
          [NSString stringWithFormat:@"%.1f MB open, %.1f MB after the rest", reopened, second]);
    Check(second - after < 8, @"a second open and rest adds less than 8 MB to the first",
          [NSString stringWithFormat:@"%.1f then %.1f MB", after, second]);
    printf("END\n");
    return 0;
}}
