// A row under the pointer and a row a press picked, DESIGN rule 2 and the row states: the pointer gives a quiet white
// wash and previews its row's story in the middle, a press makes the row active, blue, and its story comes back once
// the pointer leaves the rows. tools/render.m includes this file after render-window-caches.m and uses its Check, WindowLists, PolishView,
// PolishHost, PolishDock, WordViews and LogDraw. It is not built on its own.

/// fixture, state, the row the pointer rests on. "active" makes server:6006 the active row as well, while the middle
/// previews the row under the pointer.
static NSArray<NSArray *> *WindowPressShots(void) {
    return @[@[@"busy", @"hover", @"server:6006"], @[@"busy", @"active", @"agent:4"]];
}

static void PressShotState(MMWindowView *v, NSString *state) {
    if ([state isEqualToString:@"active"]) v.activeRow = @"server:6006";
}

static MMWindowMiddleView *PressMiddle(MMWindowView *v) { return WordViews(v, MMWindowMiddleView.class).firstObject; }

/// Longer than the beat the window waits after the pointer leaves the rows. Only for a check that the beat changes
/// nothing: one that waits for the beat to change something uses PressUntil.
static void PressBeat(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]]; }

/// Turns the run loop until done holds, for at most 3 seconds, and says whether it holds. The beat is 0.26 s, but on
/// a slow CI runner that draws in software a fixed wait can end before its timer fired: render 45512807813.
static BOOL PressUntil(BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && end.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

/// The list that holds a row, and the middle of that row where it is drawn, in the list's coordinates.
static MMWindowListView *PressList(MMWindowView *v, NSString *key, NSPoint *at) {
    for (MMWindowListView *l in WindowLists(v)) {
        NSRect f = [l frameOfRow:key];
        if (NSIsEmptyRect(f)) continue;
        if (at) *at = NSMakePoint(NSMidX(f), NSMidY(f));
        return l;
    }
    return nil;
}

/// The color drawn at a point of a list, 3 points into the row from its left edge, where neither icon nor text is.
static NSColor *PressPixel(MMWindowListView *l, NSString *key) {
    NSRect f = [l frameOfRow:key];
    NSBitmapImageRep *rep = [l bitmapImageRepForCachingDisplayInRect:l.bounds];
    [l cacheDisplayInRect:l.bounds toBitmapImageRep:rep];
    CGFloat scale = rep.pixelsWide / l.bounds.size.width;
    NSColor *c = [rep colorAtX:(NSInteger)((NSMinX(f) + 3) * scale) y:(NSInteger)(NSMidY(f) * scale)];
    return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: NSColor.clearColor;
}

static NSString *PressSay(NSColor *c) {
    return [NSString stringWithFormat:@"%.2f %.2f %.2f a%.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent];
}

static NSEvent *PressKey(unsigned short code) {
    unichar ch = code == 125 ? NSDownArrowFunctionKey : code == 126 ? NSUpArrowFunctionKey : code == 123 ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey;
    NSString *s = [NSString stringWithCharacters:&ch length:1];
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagFunction timestamp:0 windowNumber:0
                             context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:code];
}

static void WindowPressChecks(void) {
    // The two looks differ, in plain and in Increase Contrast: the wash is neutral and thin, the active row solid blue.
    for (NSNumber *hc in @[@NO, @YES]) {
        MMWindowForceContrast(hc.boolValue);
        MMWindowView *v = PolishView(@"busy");
        v.activeRow = @"server:6006";
        v.pointedRow = @"server:3000";
        MMWindowListView *l = PressList(v, @"server:6006", NULL);
        NSColor *active = PressPixel(l, @"server:6006"), *hover = PressPixel(l, @"server:3000"), *rest = PressPixel(l, @"agent:4");
        BOOL blue = active.alphaComponent > 0.95 && active.blueComponent - active.redComponent > 0.4;
        BOOL neutral = fabs(hover.redComponent - hover.blueComponent) < 0.05 && fabs(hover.redComponent - hover.greenComponent) < 0.05;
        CGFloat want = hc.boolValue ? 0.15 : 0.07;
        BOOL thin = fabs(hover.alphaComponent - want) < 0.03 && rest.alphaComponent < 0.01;
        Check(blue && neutral && thin && ![MMWindowColor(MMWindowInkHover) isEqual:MMWindowColor(MMWindowInkHot)],
              [NSString stringWithFormat:@"window rows%@: the row under the pointer has a thin white wash, never the active row's blue, and a row at rest neither",
               hc.boolValue ? @", Increase Contrast" : @""],
              [NSString stringWithFormat:@"active %@, hover %@, rest %@", PressSay(active), PressSay(hover), PressSay(rest)]);
        MMWindowForceContrast(NO);
    }

    // A press picks a row: blue, its story in the middle and its numbers in the dock. The pointer on another row then
    // gives that row the wash and previews its story, and the dock tells its share, while the active row stays blue.
    // Once the pointer leaves the rows, a beat later, the middle and the dock go back to the active row. Nothing
    // reaches the host.
    MMWindowView *v = PolishView(@"busy");
    PolishHost *host = [PolishHost new];
    v.host = host;
    MMWindowMiddleView *middle = PressMiddle(v);
    MMWindowDockView *dock = PolishDock(v);
    NSPoint a, b, c;
    NSString *disk = [WindowLists(v).lastObject shownKeys:0].firstObject;
    MMWindowListView *la = PressList(v, @"server:6006", &a), *lb = PressList(v, @"agent:4", &b), *lc = PressList(v, disk, &c);
    [la pointAt:a];
    BOOL preview = [middle.row.key isEqualToString:@"server:6006"] && [la.hoverKey isEqualToString:@"server:6006"] && !la.hotKey && [dock.pointed.key isEqualToString:@"server:6006"];
    [la pressAt:a];
    BOOL picked = [v.activeRow isEqualToString:@"server:6006"] && [la.hotKey isEqualToString:@"server:6006"] && !la.hoverKey;
    [lb pointAt:b];
    BOOL other = [middle.row.key isEqualToString:@"agent:4"] && [dock.pointed.key isEqualToString:@"agent:4"] &&
                 [la.hotKey isEqualToString:@"server:6006"] && [lb.hoverKey isEqualToString:@"agent:4"] && [v.activeRow isEqualToString:@"server:6006"];
    [lc pointAt:c];
    BOOL across = [middle.row.key isEqualToString:disk] && [dock.pointed.key isEqualToString:disk] && lc == WindowLists(v).lastObject &&
                  [lc.hoverKey isEqualToString:disk] && [lc.hotKey isEqualToString:@"server:6006"];
    [lc pointAt:NSMakePoint(-10, -10)];
    BOOL beat = [middle.row.key isEqualToString:disk];
    BOOL back = PressUntil(^{ return (BOOL)([middle.row.key isEqualToString:@"server:6006"] && [dock.pointed.key isEqualToString:@"server:6006"] &&
                                            !lc.hoverKey && [lc.hotKey isEqualToString:@"server:6006"]); });
    Check(preview && picked && other && across && beat && back,
          @"window rows: the pointer previews a row's story, active row or not, on either side, with the dock's numbers; a press makes it blue, and a beat after the pointer leaves the rows the middle and the dock show the active row again",
          [NSString stringWithFormat:@"preview %d, picked %d, other %d, across %d, beat %d, back %d, middle %@", preview, picked, other, across, beat, back, middle.row.key]);

    // A press on another row moves the active state there; a second press on it, a press on empty space and Escape each let it go.
    [lb pointAt:b];
    [lb pressAt:b];
    BOOL moved = [v.activeRow isEqualToString:@"agent:4"] && [middle.row.key isEqualToString:@"agent:4"] && [la.hotKey isEqualToString:@"agent:4"];
    [lb pressAt:b];
    BOOL again = v.activeRow == nil && [middle.row.key isEqualToString:@"agent:4"] && [lb.hoverKey isEqualToString:@"agent:4"];
    [lb pressAt:b];
    [la pressAt:NSMakePoint(NSMidX(la.bounds), 4)];
    BOOL empty = v.activeRow == nil;
    [lb pressAt:b];
    [v escape];
    BOOL escaped = v.activeRow == nil && !v.showsSettings;
    Check(moved && again && empty && escaped, @"window rows: a press on another row moves the active row, and a second press, a press on a header or Escape lets it go",
          [NSString stringWithFormat:@"moved %d, again %d, empty %d, escape %d", moved, again, empty, escaped]);

    // No row is active and the pointer leaves the rows: a beat later the middle shows the log, and the dock the Mac.
    [lb pointAt:b];
    BOOL shown = [middle.row.key isEqualToString:@"agent:4"] && v.activeRow == nil;
    [lb pointAt:NSMakePoint(-10, -10)];
    BOOL log = PressUntil(^{ return (BOOL)(middle.row == nil && !middle.logView.hidden && dock.pointed == nil); });
    Check(shown && log,
          @"window rows: with no active row, a beat after the pointer leaves the rows the middle shows the log", middle.row.key ?: @"log");

    // Escape leaves Settings before it lets go of a row, and the press only selects: no fix, stop, rule, switch or Undo.
    [la pressAt:a];
    v.showsSettings = YES;
    BOOL settingsLets = v.activeRow == nil;
    v.showsSettings = NO;
    Check(settingsLets && host.fixes == 0 && host.stops == 0 && host.rules == 0 && host.switches == 0 && host.undos == 0,
          @"window rows: a press on a row reaches no host call, and Settings lets the active row go", [NSString stringWithFormat:@"%ld %ld %ld %ld %ld", (long)host.fixes, (long)host.stops, (long)host.rules, (long)host.switches, (long)host.undos]);

    // With no active row, the pointer from a previewed row onto the middle keeps that story past the beat, and its
    // presses can be pressed; leaving the middle brings back the log, and a press on a link makes its row active.
    MMWindowView *m = PolishView(@"agents");
    MMWindowMiddleView *mm = PressMiddle(m);
    NSPoint p3, p2 = NSZeroPoint;
    MMWindowListView *l3 = PressList(m, @"agent:3", &p3);
    [l3 pointAt:p3];
    [l3 pointAt:NSMakePoint(-10, -10)];
    mm.onPointer(YES);
    PressBeat();
    BOOL reach = mm.storyPresses.count == 4;
    for (MMWindowButton *press in mm.storyPresses) if (press.hidden || !MMWindowTakesPresses(press)) reach = NO;
    BOOL held = [mm.row.key isEqualToString:@"agent:3"] && [PolishDock(m).pointed.key isEqualToString:@"agent:3"] && reach && m.activeRow == nil;
    mm.onPointer(NO);
    BOOL away = PressUntil(^{ return (BOOL)(mm.row == nil && !mm.logView.hidden); });
    [l3 pointAt:p3];
    [l3 pointAt:NSMakePoint(-10, -10)];
    mm.onPointer(YES);
    PressBeat();
    MMWindowButton *tree = nil;
    for (MMWindowButton *press in mm.storyPresses) if ([press.identifier isEqualToString:@"worktree:lane-c"]) tree = press;
    [tree performClick:nil];
    BOOL linked = [m.activeRow isEqualToString:@"worktree:lane-c"] && [mm.row.key isEqualToString:@"worktree:lane-c"];
    Check(l3 && held && away && linked,
          @"window rows: with no active row, the pointer from a previewed row onto the middle keeps that story and its presses, leaving it brings back the log, and a link makes its row active",
          [NSString stringWithFormat:@"held %d, log %d, linked %d, middle %@", held, away, linked, mm.row.key]);

    // With an active row, hover only peeks: the pointer from another row onto the middle brings back the active row's
    // story and its numbers after the beat, and a row the pointer goes to from the middle shows its own.
    mm.onPointer(NO);
    m.activeRow = @"agent:3";
    NSString *drawn = nil;
    for (MMWindowListView *l in WindowLists(m)) for (NSString *k in l.rowKeys) if (!drawn && ![k isEqualToString:@"agent:3"] && !NSIsEmptyRect([l frameOfRow:k])) drawn = k;
    MMWindowListView *ld = drawn ? PressList(m, drawn, &p2) : nil;
    [ld pointAt:p2];
    BOOL peek = drawn && [mm.row.key isEqualToString:drawn];
    [ld pointAt:NSMakePoint(-10, -10)];
    mm.onPointer(YES);
    BOOL waits = [mm.row.key isEqualToString:drawn];
    BOOL active = PressUntil(^{ return (BOOL)([mm.row.key isEqualToString:@"agent:3"] && [PolishDock(m).pointed.key isEqualToString:@"agent:3"] && !ld.hoverKey); });
    [ld pointAt:p2];
    mm.onPointer(NO);
    PressBeat();
    BOOL onRow = [mm.row.key isEqualToString:drawn] && [ld.hoverKey isEqualToString:drawn];
    Check(peek && waits && active && onRow,
          @"window rows: with an active row the pointer only peeks: onto the middle, the active row's story and numbers come back after the beat",
          [NSString stringWithFormat:@"peek %d, waits %d, active %d, on a row %d, middle %@, row %@", peek, waits, active, onRow, mm.row.key, drawn]);

    // The pointer leaves the window from a previewed row: the active row's story comes back at once, with no beat.
    [ld pointAt:NSMakePoint(-10, -10)];
    [m pointLeft];
    BOOL atOnce = [mm.row.key isEqualToString:@"agent:3"] && [PolishDock(m).pointed.key isEqualToString:@"agent:3"] && !ld.hoverKey;
    Check(atOnce, @"window rows: with an active row, the pointer leaving the window brings back its story at once", mm.row.key ?: @"log");

    // The active row leaves the model, as when its process ended: the pin goes, and the middle shows the log again.
    MMWindowView *gone = PolishView(@"busy");
    MMWindowMiddleView *goneMiddle = PressMiddle(gone);
    gone.activeRow = @"server:6006";
    MMWindowModel *after = MMWindowFixture(@"busy");
    after.generation = 2;
    for (MMWindowGroup *g in after.memoryGroups) {
        NSMutableArray *rows = [g.rows mutableCopy];
        [rows filterUsingPredicate:[NSPredicate predicateWithFormat:@"key != %@", @"server:6006"]];
        g.rows = rows;
    }
    BOOL before = [goneMiddle.row.key isEqualToString:@"server:6006"];
    gone.model = after;
    Check(before && gone.activeRow == nil && goneMiddle.row == nil && PolishDock(gone).pointed == nil && !goneMiddle.logView.hidden,
          @"window rows: when the active row leaves the model the pin goes quietly, and the middle shows its log", goneMiddle.row.key ?: @"none");

    // The arrow keys move the active row down its side, across to the other side, and from none to the first.
    MMWindowView *k = PolishView(@"busy");
    MMWindowListView *left = WindowLists(k).firstObject, *right = WindowLists(k).lastObject;
    [k keyDown:PressKey(125)];
    BOOL first = [k.activeRow isEqualToString:left.rowKeys.firstObject];
    [k keyDown:PressKey(125)];
    BOOL down = [k.activeRow isEqualToString:left.rowKeys[1]];
    [k keyDown:PressKey(126)]; [k keyDown:PressKey(126)];
    BOOL top = [k.activeRow isEqualToString:left.rowKeys.firstObject];
    [k keyDown:PressKey(124)];
    BOOL toRight = [right.rowKeys containsObject:k.activeRow];
    NSString *last = right.rowKeys.lastObject;
    for (NSUInteger i = 0; i < right.rowKeys.count + 2; i++) [k keyDown:PressKey(125)];
    BOOL end = [k.activeRow isEqualToString:last] && !NSIsEmptyRect([right frameOfRow:last]) && [PressMiddle(k).row.key isEqualToString:last];
    Check(first && down && top && toRight && end, @"window rows: the arrow keys pick the first row, move the active row up and down its side and across, stop at the ends, and scroll it into view",
          [NSString stringWithFormat:@"first %d, down %d, top %d, right %d, end %d (%@)", first, down, top, toRight, end, k.activeRow]);

    // VoiceOver reads the active row as selected, and only it; its press picks the row as a click does.
    NSArray *kids = right.accessibilityChildren;
    NSMutableArray *selected = [NSMutableArray new];
    for (NSAccessibilityElement *el in kids) if (el.isAccessibilitySelected) [selected addObject:el.accessibilityLabel ?: @""];
    NSAccessibilityElement *firstEl = left.accessibilityChildren.firstObject;
    BOOL pressed = [firstEl accessibilityPerformPress] && [k.activeRow isEqualToString:left.rowKeys.firstObject] && [left.accessibilitySelectedChildren.firstObject isAccessibilitySelected];
    Check(selected.count == 1 && [selected.firstObject containsString:[[MMWindowFixture(@"busy") row:last] shownName] ?: @"-"] && pressed,
          @"window rows: VoiceOver reads the active row as selected, no other, and a VoiceOver press picks a row", [selected componentsJoinedByString:@" | "]);
}
