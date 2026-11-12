// How long the menu window takes to its first drawn frame, issue #53. tools/render.m includes this file, so it is
// part of the render tool. It is not built on its own, and it never opens the app.
//
// What it times, on main, with the fixture model made beforehand:
//   cold   a new MMWindowView, the model set, laid out and drawn once. The app does this at the first click.
//   warm   the same view given a new model and drawn again. The app does this at every later click and snapshot.
// It draws into a bitmap at two pixels a point, as the PNGs are. It leaves out what only a screen has: the glass
// blur behind the panel and the window server putting the frame up. So it is the app's own share of an open.
// The numbers go to window/open-ms.txt and are not a gate: this Mac runs many builds at once, and a render that
// failed on a slow minute would stop every section that renders. #53's budget is 30 ms at p95.
#include <time.h>

static NSString *OpenStats(NSMutableArray<NSNumber *> *ms) {
    [ms sortUsingSelector:@selector(compare:)];
    double p50 = ms[ms.count / 2].doubleValue, p95 = ms[MIN(ms.count - 1, (NSUInteger)ceil(ms.count * 0.95) - 1)].doubleValue;
    return [NSString stringWithFormat:@"p50 %.1f ms, p95 %.1f ms, max %.1f ms, n %lu", p50, p95, ms.lastObject.doubleValue, (unsigned long)ms.count];
}

static void WindowOpenTiming(NSString *dir, NSAppearance *ap) {
    if (!ap) return;
    const NSInteger rounds = 30;
    NSRect frame = NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.appearance = ap;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(frame.size.width * 2)
        pixelsHigh:(NSInteger)(frame.size.height * 2) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = frame.size;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *name in @[@"quiet", @"busy", @"peak"]) {
        NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
        for (NSInteger i = 0; i < rounds * 2; i++) [models addObject:MMWindowFixture(name)];
        NSMutableArray<NSNumber *> *cold = [NSMutableArray new], *warm = [NSMutableArray new];
        __block double first = 0;
        for (NSInteger i = 0; i < rounds; i++) {
            __block MMWindowView *v = nil;
            void (^draw)(MMWindowModel *) = ^(MMWindowModel *m) {
                v.model = m;
                [w layoutIfNeeded];
                [v willOpen];
                [ap performAsCurrentDrawingAppearance:^{ [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep]; }];
            };
            uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            v = [[MMWindowView alloc] initWithFrame:frame];
            v.drawsBacking = YES;
            [w.contentView addSubview:v];
            draw(models[i * 2]);
            uint64_t t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            draw(models[i * 2 + 1]);
            uint64_t t2 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            [v removeFromSuperview];
            // The first round of the first fixture also pays for fonts and symbols the process had not loaded yet.
            if (i == 0) first = (t1 - t0) / 1e6;
            else [cold addObject:@((t1 - t0) / 1e6)];
            [warm addObject:@((t2 - t1) / 1e6)];
        }
        NSInteger rows = 0;
        for (NSArray<MMWindowGroup *> *side in @[models[0].memoryGroups, models[0].diskGroups]) for (MMWindowGroup *g in side) rows += g.rows.count;
        [lines addObject:[NSString stringWithFormat:@"%@, %ld rows: cold first %.1f ms, then %@; warm %@", name, (long)rows, first, OpenStats(cold), OpenStats(warm)]];
    }
    NSString *text = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    [text writeToFile:[dir stringByAppendingPathComponent:@"open-ms.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    for (NSString *l in lines) printf("window open, issue #53: %s\n", l.UTF8String);
}
