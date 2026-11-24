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

/// One read once the frees of the last moment have landed: the autoreleased objects of the last turn go, Core
/// Animation commits, and free malloc pages are given back, as the system takes them under pressure, so what is
/// counted is what is held.
static double Read(NSTimeInterval spin) {
    Spin(spin);
    @autoreleasepool { [CATransaction flush]; }
    malloc_zone_pressure_relief(NULL, 0);
    return FootprintMB();
}

/// The lowest of a few reads a little apart.
static double Settled(NSTimeInterval seconds) {
    double low = 1e9;
    for (int i = 0; i < 4; i++) low = MIN(low, Read(seconds / 4));
    return low;
}

/// The lowest read once a second of reads no longer comes down by more than half a MB, or when `timeout` ran out: the
/// baseline, read before anything of the panel was made, so what the warm-up gave back late is not counted as held.
static double Stable(NSTimeInterval timeout) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    double low = Settled(2);
    while ((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e9 < timeout) {
        double next = MIN(low, Settled(1));
        if (low - next < 0.5) return next;
        low = next;
    }
    return low;
}

/// The lowest read once it is under `target`, or when `timeout` ran out. On a loaded Mac the malloc zones and the GPU
/// driver give memory back late, at a moment the load decides, so a single read a fixed time after the rest can land
/// before it. A held panel never comes down, so the wait runs out and the read stays near 60 MB over. `waited` says
/// how long it took.
static double SettledUnder(double target, NSTimeInterval timeout, NSTimeInterval *waited) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    double low = Settled(1);
    NSTimeInterval s = 1;
    while (low >= target && s < timeout) {
        low = MIN(low, Read(0.25));
        s = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e9;
    }
    if (waited) *waited = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e9;
    return low;
}

/// What the window server still has of a window: nil when it has none, else its size. A window AppKit keeps ordered
/// out keeps its backing at that size, so a panel let go must be gone or one point square.
static NSString *ServerWindow(CGWindowID number) {
    if (!number) return @"no number";
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSString *what = nil;
    for (NSDictionary *w in (__bridge NSArray *)list) {
        if ([w[(id)kCGWindowNumber] unsignedIntValue] != number) continue;
        CGRect r;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &r)) r = CGRectNull;
        what = [NSString stringWithFormat:@"%.0f x %.0f", r.size.width, r.size.height];
    }
    if (list) CFRelease(list);
    return what;
}
static BOOL ServerLetGo(CGWindowID number) {
    NSString *w = ServerWindow(number);
    return !w || [w isEqualToString:@"1 x 1"] || [w isEqualToString:@"0 x 0"];
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

/// The panel the holder has now, its views and its window number, held weakly, so the checks can see them go.
@interface Watch : NSObject
@property (weak) MMWindowPanel *panel;
@property (weak) NSView *view, *content;
@property CGWindowID number;
@end
@implementation Watch
@end
static Watch *WatchPanel(MMWindowHolder *h) { @autoreleasepool {
    Watch *w = [Watch new];
    MMWindowPanel *p = h.madePanel;
    w.panel = p; w.view = p.view; w.content = p.contentView; w.number = (CGWindowID)p.windowNumber;
    return w;
}}
/// What still holds on to a panel that was let go, or @"" when nothing does.
static NSString *Alive(Watch *w) { @autoreleasepool {
    NSMutableArray *why = [NSMutableArray new];
    if (w.panel) [why addObject:@"the panel is alive"];
    if (w.view) [why addObject:@"its view is alive"];
    if (w.content) [why addObject:@"its content view is alive"];
    NSString *server = ServerWindow(w.number);
    if (!ServerLetGo(w.number)) [why addObject:[NSString stringWithFormat:@"the window server holds its window at %@", server]];
    return [why componentsJoinedByString:@", "];
}}

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
    double base = Stable(10);

    BOOL drawn; NSString *why;
    double cold = Open(h, &drawn, &why);
    Check(h.isOpen && drawn, @"the first open draws the first frame from the model before the panel comes on screen", why);
    double open = Settled(2);
    Watch *first = WatchPanel(h);
    Close(h);
    double closed = Settled(1);
    Check(Held(h), @"a second after the close the panel is still held, so a quick reopen is the same panel", @"let go at once");
    NSString *heldServer = ServerWindow(first.number);

    // A quick reopen inside the rest takes the same panel, and its close starts the rest over.
    double warm = Open(h, &drawn, &why);
    Check(Is(h, first.panel) && h.made == 1 && drawn, @"a reopen inside the rest takes the same panel, drawn before it shows", why);
    Close(h);

    // A run that plays keeps the panel past its rest.
    busy = YES;
    Spin(rest + 1.5);
    Check(Held(h), @"while a run plays the panel is kept past its rest", @"let go");
    busy = NO;
    Spin(MAX(rest, 1) + 1.5);
    Check(!Held(h), @"once the run ended the panel goes at the next ask", @"still held");
    Spin(0.5);
    // What the checks guard is the panel being held, about 60 MB in this process. The objects say it first and
    // exactly: the panel, its views, and the window server's window behind it.
    NSString *alive = Alive(first);
    Check(!alive.length, @"nothing holds on to the panel that was let go, its views or its window server backing", alive);

    // The footprint says it too, with room for noise. Drawn once, the window holds about 40 MB here, and a kept panel
    // reads 58 to 60 MB over the baseline after its rest. Let go, it reads 15 to 21 MB over: what the first draw of a
    // window this large costs a process once, the GPU and Core Animation, which later rounds do not add to. So 35 MB
    // allows for noise and still sees a panel kept. On a loaded Mac what is given back lands late, so each read after
    // a rest waits up to 20 s for it.
    double slack = 35, timeout = 20, waitAfter = 0, waitSecond = 0, waitThird = 0;
    double after = SettledUnder(base + slack, timeout, &waitAfter);

    double again = Open(h, &drawn, &why);
    Check(h.isOpen && h.made == 2 && drawn && Shows(h, model),
          @"a reopen after the panel was let go makes it again and draws the last model before it shows", why);
    double reopened = Settled(2);
    Watch *second = WatchPanel(h);
    Close(h);
    Spin(rest + 1.5);
    Check(!Held(h), @"the second panel goes after its rest too", @"still held");
    Spin(0.5);
    alive = Alive(second);
    Check(!alive.length, @"nothing holds on to the second panel either", alive);
    double secondRest = SettledUnder(MIN(base + slack, reopened - 20), timeout, &waitSecond);

    // A third round, to see nothing pile up. The second rest is the one to compare with, not the first: the first
    // draw's cost to the process lands over the first two rounds, about 5 MB more by the second, and under memory
    // pressure the first rest can read 10 MB low while the GPU's purgeable memory is out. From the second round on
    // each rest reads the same, within a MB.
    Open(h, &drawn, &why);
    Settled(1);
    Close(h);
    Spin(rest + 1.5);
    double third = SettledUnder(MIN(base + slack, secondRest + 8), timeout, &waitThird);

    // More rounds when asked, for the numbers: each after its rest.
    NSMutableArray *rounds = [NSMutableArray new];
    for (int i = 0, n = argc > 2 ? atoi(argv[2]) : 0; i < n; i++) {
        Open(h, &drawn, &why); Spin(1); Close(h); Spin(rest + 1.5);
        [rounds addObject:[NSString stringWithFormat:@"%.1f", Settled(2)]];
    }
    if (rounds.count) Info([@"footprint MB after each later round: " stringByAppendingString:[rounds componentsJoinedByString:@", "]]);
    Info([NSString stringWithFormat:@"footprint MB: launch %.1f, open %.1f, 1 s after close %.1f, after the rest %.1f, reopened %.1f, after the second rest %.1f, after the third %.1f",
          base, open, closed, after, reopened, secondRest, third]);
    Info([NSString stringWithFormat:@"waited for the footprint after each rest %.1f, %.1f and %.1f s; the closed panel's window server window before the let-go: %@",
          waitAfter, waitSecond, waitThird, heldServer ?: @"none"]);
    Info([NSString stringWithFormat:@"open ms: first %.1f, reopen inside the rest %.1f, reopen after the rest %.1f", cold, warm, again]);
    Check(after - base < slack && secondRest - base < slack && third - base < slack, @"after the rest the footprint is back within 35 MB of the baseline",
          [NSString stringWithFormat:@"%.1f, %.1f and %.1f MB over the baseline of %.1f", after - base, secondRest - base, third - base, base]);
    // What the reopened window held over the baseline. On a Mac with a GPU that is 60 MB or more, and the rest gives at
    // least 20 MB of it back. A runner that draws in software, such as CI's, holds far less, so the bound is half of
    // what was held, at most 20 MB; the panel's own objects, checked above, are what catch a held panel anywhere.
    double held = reopened - base, giveBack = MIN(20.0, held / 2);
    Check(reopened - secondRest > giveBack, @"the rest gives back at least half of what the reopened window held, at most 20 MB",
          [NSString stringWithFormat:@"%.1f MB open, %.1f MB after the rest, %.1f MB held over the baseline", reopened, secondRest, held]);
    Check(third - secondRest < 8, @"a third open and rest adds less than 8 MB to the second",
          [NSString stringWithFormat:@"%.1f then %.1f MB", secondRest, third]);
    printf("END\n");
    return 0;
}}
