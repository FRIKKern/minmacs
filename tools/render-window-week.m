// The strip's 7 days, slice 3 of the center: full, two days young and with a gap, in pictures and in checks.
// tools/render.m includes this file after render-window-pulls.m and uses its Check, PolishView, WordViews and the
// word watch of render-window-words.m. It is not built on its own.

/// fixture, state, the row the pointer rests on. "hover" puts the pointer on the memory line, "hover-gap" in its gap.
static NSArray<NSArray *> *WindowWeekShots(void) {
    return @[@[@"week", @"main", @""], @[@"week-young", @"main", @""], @[@"week-gap", @"main", @""],
             @[@"week-gap", @"hover", @""], @[@"week-gap", @"hover-gap", @""]];
}

static MMWindowMiddleView *WeekMiddle(MMWindowView *v) { return WordViews(v, MMWindowMiddleView.class).firstObject; }

/// Where the hour at index i of a full week stands on the memory side, as the strip draws it.
static CGFloat WeekX(MMWindowMiddleView *m, NSInteger i) {
    CGFloat w = floor((m.bounds.size.width - 28 - 16) / 2);
    return 14 + 1 + (w - 2.6) * i / (MMWindowWeekHours - 1);
}

static void WeekShotState(MMWindowView *v, NSString *state) {
    MMWindowMiddleView *m = WeekMiddle(v);
    if ([state isEqualToString:@"hover"]) [m pointStripAt:NSMakePoint(WeekX(m, 130), 60)];
    if ([state isEqualToString:@"hover-gap"]) [m pointStripAt:NSMakePoint(WeekX(m, 78), 60)];
}

@interface WeekHost : PolishHost
@property NSInteger weeks;
@property BOOL lastWeek;
@end
@implementation WeekHost
- (void)windowStripWeek:(BOOL)week { self.weeks++; self.lastWeek = week; }
@end

/// The most ink in a column of the memory side's line, between the top and the foot of its graph: 0 is none.
static CGFloat WeekInk(NSBitmapImageRep *rep, MMWindowMiddleView *m, CGFloat x) {
    CGFloat scale = rep.pixelsWide / m.bounds.size.width, most = 0;
    for (CGFloat y = 44; y < 74; y += 0.5) most = MAX(most, [rep colorAtX:(NSInteger)(x * scale) y:(NSInteger)(y * scale)].alphaComponent);
    return most;
}

static void WindowWeekChecks(void) {
    // Honest words: a full week says 7 days, two days young say 2 days, and none of them says the hour.
    NSMutableArray<NSString *> *seen = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) { [seen addObject:text]; });
    NSMutableArray<NSString *> *said = [NSMutableArray new];
    for (NSString *name in @[@"week", @"week-young", @"week-gap"]) {
        [seen removeAllObjects];
        LogDraw(WeekMiddle(PolishView(name)));
        NSInteger days = [seen filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'the last 7 days'"]].count;
        NSInteger two = [seen filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'the last 2 days'"]].count;
        // Each side draws its words once; a drawing may pass over a string twice, so a side is a pass's pair.
        [said addObject:[NSString stringWithFormat:@"%@ %@ %@ %@", name, days >= 2 ? @"7" : @"-", two >= 2 ? @"2" : @"-",
                         [seen containsObject:@"the last hour"] || [seen containsObject:@"the last 12 min"] ? @"hour" : @"-"]];
    }
    Check([[said componentsJoinedByString:@", "] isEqualToString:@"week 7 - -, week-young - 2 -, week-gap 7 - -"],
          @"window week: each side says how long it holds, the last 7 days or the last 2 days while it is young, and never the hour", [said componentsJoinedByString:@", "]);

    // No line across a gap: the memory side's column inside the gap holds no ink, in dark and in Increase Contrast,
    // while the hours either side of it do. The hour alone between two gaps is a dot.
    NSMutableArray<NSString *> *ink = [NSMutableArray new];
    BOOL clean = YES;
    for (NSNumber *contrast in @[@NO, @YES]) {
        MMWindowForceContrast(contrast.boolValue);
        MMWindowMiddleView *m = WeekMiddle(PolishView(@"week-gap"));
        NSBitmapImageRep *rep = [m bitmapImageRepForCachingDisplayInRect:m.bounds];
        [m cacheDisplayInRect:m.bounds toBitmapImageRep:rep];
        CGFloat inGap = 0;
        for (NSInteger i = 72; i <= 85; i++) inGap = MAX(inGap, WeekInk(rep, m, WeekX(m, i)));
        CGFloat shortGap = WeekInk(rep, m, WeekX(m, 111));
        CGFloat before = WeekInk(rep, m, WeekX(m, 60)), after = WeekInk(rep, m, WeekX(m, 100)), alone = WeekInk(rep, m, WeekX(m, 113));
        clean = clean && inGap < 0.02 && shortGap < 0.02 && before > 0.3 && after > 0.3 && alone > 0.3;
        [ink addObject:[NSString stringWithFormat:@"%@ gap %.2f, short gap %.2f, before %.2f, after %.2f, alone %.2f", contrast.boolValue ? @"contrast" : @"dark",
                        inGap, shortGap, before, after, alone]];
    }
    MMWindowForceContrast(NO);
    Check(clean, @"window week: no line is drawn across the hours the Mac was off or asleep, and an hour alone shows as a dot", [ink componentsJoinedByString:@" | "]);

    // The pointer on a line shows the reading there; in a gap it says nothing was kept, and off the lines it shows none.
    MMWindowMiddleView *m = WeekMiddle(PolishView(@"week-gap"));
    [m pointStripAt:NSMakePoint(WeekX(m, 130), 60)];
    NSString *onLine = m.stripReading ?: @"";
    [m pointStripAt:NSMakePoint(WeekX(m, 78), 60)];
    NSString *inGap = m.stripReading ?: @"";
    [m pointStripAt:NSMakePoint(WeekX(m, 78), 200)];
    Check([onLine containsString:@" · "] && [onLine hasSuffix:@" GB"] && [inGap hasSuffix:@" · nothing kept"] && m.stripReading == nil,
          @"window week: the pointer on a line reads its hour and value, in a gap says nothing was kept, and off the strip reads nothing",
          [NSString stringWithFormat:@"%@ | %@ | %@", onLine, inGap, m.stripReading ?: @"none"]);

    // The two words: real buttons under the sides and above the log, the chosen one bright, and a press tells the host
    // and shows the other at once, before a model says so.
    WeekHost *host = [WeekHost new];
    MMWindowView *v = PolishView(@"week");
    v.host = host;
    m = WeekMiddle(v);
    BOOL lit = m.weekPress.lit && !m.hourPress.lit && m.weekPress.accessibilitySelected;
    BOOL placed = NSMaxY(m.hourPress.frame) <= m.stripHeight && NSMaxY(m.weekPress.frame) <= m.stripHeight && NSMinY(m.hourPress.frame) >= 74
               && NSMinX(m.weekPress.frame) > NSMaxX(m.hourPress.frame) && NSMinY(m.logView.frame) > m.stripHeight;
    [m.hourPress performClick:nil];
    [seen removeAllObjects];
    LogDraw(m);
    BOOL pressed = host.weeks == 1 && !host.lastWeek && !m.stripWeek && m.hourPress.lit && [seen containsObject:@"the last 12 min"];
    // A model built before the press still says the 7 days: the press's choice stands until a model says the hour.
    v.model = MMWindowFixture(@"week");
    BOOL kept = !m.stripWeek;
    MMWindowModel *hourModel = MMWindowFixture(@"week");
    hourModel.stripWeek = NO; hourModel.generation = 2;
    v.model = hourModel;
    MMWindowModel *weekModel = MMWindowFixture(@"week");
    weekModel.generation = 3;
    v.model = weekModel;
    BOOL follows = m.stripWeek;
    v.pointedRow = @"server:6006";
    BOOL hidden = m.hourPress.hidden && m.weekPress.hidden;
    v.pointedRow = nil;
    Check(lit && placed && pressed && kept && follows && hidden && !m.hourPress.hidden,
          @"window week: hour and 7 days are two buttons under the sides, the chosen one lit; a press tells the host and shows the other at once, and a story hides them",
          [NSString stringWithFormat:@"lit %d placed %d pressed %d kept %d follows %d hidden %d", lit, placed, pressed, kept, follows, hidden]);
    MMWindowWatchDraws(nil);

    // The words the 7 days and their readings draw, in dark and Increase Contrast: none holds an ellipsis, and none
    // is wider than its box, leaves its view or stands on another, as rule 8 holds for every string.
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    NSMutableArray<NSArray *> *lines = [NSMutableArray new];
    __block NSInteger strings = 0;
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        strings++;
        if ([text containsString:@"…"] || [text containsString:@"..."]) [faults addObject:[@"ellipsis: " stringByAppendingString:text]];
        else if (!NSIsEmptyRect(allowed) && NSWidth(used) > NSWidth(allowed) + 1) [faults addObject:[@"past its box: " stringByAppendingString:text]];
        else if (!NSIsEmptyRect(bounds) && (NSMinX(used) < NSMinX(bounds) - 1 || NSMaxX(used) > NSMaxX(bounds) + 1)) [faults addObject:[@"past its view: " stringByAppendingString:text]];
        if (text.length && used.size.width > 0) [lines addObject:@[text, [NSValue valueWithRect:used], [NSValue valueWithNonretainedObject:NSView.focusView]]];
    });
    for (NSNumber *contrast in @[@NO, @YES]) {
        MMWindowForceContrast(contrast.boolValue);
        for (NSArray *shot in WindowWeekShots()) {
            MMWindowView *w = PolishView(shot[0]);
            WeekShotState(w, shot[1]);
            [lines removeAllObjects];
            LogDraw(w);
            for (MMWindowButton *b in @[WeekMiddle(w).hourPress, WeekMiddle(w).weekPress]) LogDraw(b);
            for (NSUInteger i = 0; i < lines.count; i++) for (NSUInteger j = i + 1; j < lines.count; j++) {
                if (![lines[i][2] isEqual:lines[j][2]]) continue;
                NSRect a = [lines[i][1] rectValue], b = [lines[j][1] rectValue], both = NSIntersectionRect(a, b);
                if (NSEqualRects(a, b) && [lines[i][0] isEqual:lines[j][0]]) continue;       // one string, drawn in two passes
                if (both.size.width > 1.5 && both.size.height > MIN(a.size.height, b.size.height) * 0.5)
                    [faults addObject:[NSString stringWithFormat:@"%@ %@: %@ over %@", shot[0], shot[1], lines[i][0], lines[j][0]]];
            }
        }
    }
    MMWindowForceContrast(NO);
    MMWindowWatchDraws(nil);
    Check(faults.count == 0 && strings > 100, @"window week: in dark and Increase Contrast, no word of the 7 days or a reading holds an ellipsis, leaves its box or stands on another",
          [NSString stringWithFormat:@"%ld strings. %@", (long)strings, [faults componentsJoinedByString:@" | "]]);
}
