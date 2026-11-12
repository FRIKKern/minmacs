// The checks that came from the owner's first look at the real menu window, issue #62. tools/render.m includes this
// file, so it is part of the render tool and uses its Check. It is not built on its own.

static NSArray<MMWindowListView *> *WindowLists(NSView *v) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *sub in v.subviews) {
        if ([sub isKindOfClass:MMWindowListView.class]) [out addObject:sub];
        [out addObjectsFromArray:WindowLists(sub)];
    }
    return out;
}

/// What the first look at the real window found, each as a check: no row's name is cut, a young hour draws no line,
/// an empty group says so, the top band folds away when nobody asks, and a group rests on a whole row.
static void WindowLookChecks(void) {
    for (NSString *name in @[@"busy", @"peak", @"young", @"calm", @"long"]) {
        MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        MMWindowModel *m = MMWindowFixture(name);
        v.model = m;
        NSMutableArray<NSString *> *drawn = [NSMutableArray new], *whole = [NSMutableArray new], *bad = [NSMutableArray new];
        for (MMWindowListView *l in WindowLists(v)) [drawn addObjectsFromArray:l.drawnNames];
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) [whole addObjectsFromArray:[g.rows valueForKey:@"shownName"]];
        NSInteger shortened = 0;
        for (NSUInteger i = 0; i < drawn.count && i < whole.count; i++) {
            NSString *d = drawn[i], *w = whole[i];
            if ([d isEqualToString:w]) continue;
            shortened++;
            // A shortened name is whole words from the start of the real one, with no ellipsis.
            BOOL words = d.length >= 8 && [w hasPrefix:d] && [@" -/._" containsString:[w substringWithRange:NSMakeRange(d.length, 1)]];
            if (!words || [d containsString:@"…"] || [d containsString:@"..."]) [bad addObject:[NSString stringWithFormat:@"%@ -> %@", w, d]];
        }
        for (NSString *d in drawn) if ([d containsString:@"…"]) [bad addObject:d];
        BOOL isLong = [name isEqualToString:@"long"];
        Check(drawn.count == whole.count && drawn.count > 0 && bad.count == 0 && (isLong ? shortened >= 1 && shortened <= 4 : shortened == 0),
              [NSString stringWithFormat:@"window %@: no row's name is cut with an ellipsis%@", name, isLong ? @", and a name longer than the row loses whole words only" : @", and every name is whole"],
              [NSString stringWithFormat:@"%ld shortened of %lu. %@", (long)shortened, (unsigned long)drawn.count, [bad componentsJoinedByString:@" | "]]);
    }

    // The hour: one minute draws no line and twelve draw the filled part, with honest ends.
    NSInteger a, b, n;
    MMWindowModel *young = MMWindowFixture(@"young"), *calm = MMWindowFixture(@"calm"), *busy = MMWindowFixture(@"busy");
    NSArray *span = MMWindowHourSpan(young.memoryHour.values, &a, &b, &n);
    Check(span == nil && n == 1 && b == 59, @"window young: one filled minute is no line, and the newest value is still there", [NSString stringWithFormat:@"%ld filled", (long)n]);
    span = MMWindowHourSpan(calm.memoryHour.values, &a, &b, &n);
    Check(span.count == 12 && a == 48 && b == 59, @"window calm: twelve filled minutes draw as twelve, from 11 min ago to now", [NSString stringWithFormat:@"%lu values from %ld to %ld", (unsigned long)span.count, (long)a, (long)b]);
    span = MMWindowHourSpan(busy.memoryHour.values, &a, &b, &n);
    Check(span.count == 60 && a == 0, @"window busy: a full hour draws all sixty minutes", @"");
    BOOL rowLine = NO;
    for (MMWindowGroup *g in young.memoryGroups) for (MMWindowRow *r in g.rows) if (MMWindowHourSpan(r.hour, NULL, NULL, NULL)) rowLine = YES;
    Check(!rowLine && MMWindowHourLeast == 5, @"window young: no row shows an hour line before five filled minutes", @"");

    // Nobody asks, nothing on disk, nothing to fix.
    Check(young.asks == nil && young.fixCount == 0 && young.diskGroups.count == 2 && young.diskGroups[0].rows.count == 0 && young.diskGroups[1].rows.count == 0 &&
          [young.diskGroups[0].emptyNote isEqualToString:@"No worktrees found"] && [young.diskGroups[1].emptyNote isEqualToString:@"No caches or leftovers found"],
          @"window young: nobody asks, nothing to fix, and each empty disk group says so in words", @"");
    Check(calm.fixCount == 0 && calm.memoryBackToday > 0 && calm.diskBackToday > 0 && young.memoryBackToday == 0 && young.diskBackToday == 0,
          @"window calm: nothing to fix, with memory and disk back today as two numbers", @"");
    for (NSArray<MMWindowGroup *> *side in @[busy.memoryGroups, busy.diskGroups]) for (MMWindowGroup *g in side)
        Check(g.emptyNote.length > 0, [NSString stringWithFormat:@"window: the %@ group has words for when it is empty", g.key], @"");

    // The gains: a side that is zero is not shown as a gain, before a press, while a run plays and once it ended.
    NSString *(^gains)(MMWindowModel *, MMWindowDockPhase) = ^NSString *(MMWindowModel *model, MMWindowDockPhase phase) {
        MMWindowDockView *d = [[MMWindowDockView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, 132)];
        d.model = model; d.phase = phase;
        d.memoryShown = model.run.memoryBack; d.diskShown = model.run.diskBack;
        return [d.gainLines componentsJoinedByString:@" | "];
    };
    MMWindowModel *memoryOnly = MMWindowFixture(@"memory-only"), *diskOnly = MMWindowFixture(@"disk-only"), *none = MMWindowFixture(@"young");
    NSString *both = gains(busy, MMWindowDockCalm), *mem = gains(memoryOnly, MMWindowDockCalm), *dsk = gains(diskOnly, MMWindowDockCalm);
    Check([both isEqualToString:@"3.1 GB memory back | 18.6 GB disk back"] && [mem isEqualToString:@"2.7 GB memory back"] && [dsk isEqualToString:@"16.8 GB disk back"],
          @"window gains: both sides when both are above zero, and one side alone when the other is zero", [NSString stringWithFormat:@"%@ / %@ / %@", both, mem, dsk]);
    Check(memoryOnly.fixCount > 0 && memoryOnly.diskBack == 0 && diskOnly.fixCount > 0 && diskOnly.memoryBack == 0 && gains(none, MMWindowDockCalm).length == 0,
          @"window gains: with nothing to fix and nothing back today no gain is shown", gains(none, MMWindowDockCalm));
    Check([gains(calm, MMWindowDockCalm) isEqualToString:@"250 MB memory back today | 3.1 GB disk back today"], @"window gains: nothing to fix shows what came back today", gains(calm, MMWindowDockCalm));
    // A run that set out to give back memory only, and one that ended with nothing on one side.
    MMWindowRun *run = [MMWindowRun new];
    run.running = YES; run.total = memoryOnly.fixCount; run.memoryPlanned = memoryOnly.memoryBack;
    memoryOnly.run = run;
    NSString *atStart = gains(memoryOnly, MMWindowDockRunning);
    run.running = NO; run.memoryBack = 0; run.diskBack = 0;
    NSString *nothing = gains(memoryOnly, MMWindowDockEnded);
    run.memoryBack = run.memoryPlanned;
    NSString *ended = gains(memoryOnly, MMWindowDockEnded);
    Check([atStart isEqualToString:@"0 KB memory back so far"] && nothing.length == 0 && [ended isEqualToString:@"2.7 GB memory back"],
          @"window gains: a run counts up only the side it set out to give back, and its end shows only what came back", [NSString stringWithFormat:@"%@ / %@ / %@", atStart, nothing, ended]);
    NSMutableArray<NSString *> *zeros = [NSMutableArray new];
    for (NSString *name in @[@"busy", @"quiet", @"peak", @"done", @"empty", @"young", @"calm", @"long", @"memory-only", @"disk-only"]) {
        MMWindowModel *x = MMWindowFixture(name);
        for (NSString *line in [gains(x, x.run ? MMWindowDockEnded : MMWindowDockCalm) componentsSeparatedByString:@" | "]) if ([line hasPrefix:@"0 "]) [zeros addObject:[NSString stringWithFormat:@"%@: %@", name, line]];
    }
    Check(zeros.count == 0, @"window gains: no resting fixture shows a zero as a gain", [zeros componentsJoinedByString:@" | "]);

    // The top band folds away when nobody asks, and the window keeps its size.
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.model = busy;
    CGFloat with = WindowLists(v).firstObject.frame.size.height, top = WindowLists(v).firstObject.superview.frame.origin.y;
    v.model = young;
    MMWindowListView *left = WindowLists(v).firstObject;
    Check(with == 538 && top == 40 && left.frame.size.height == 566 && left.superview.frame.origin.y == 12 && NSEqualSizes(v.frame.size, MMWindowSize),
          @"window: with nobody asking the top band folds away and the lists get its height", [NSString stringWithFormat:@"%g then %g", with, left.frame.size.height]);
    v.model = busy;
    Check(WindowLists(v).firstObject.frame.size.height == 538, @"window: the band comes back when an agent asks", @"");

    // A group rests on a whole row: after the pointer goes to its last row, and at its top once the window closed.
    left = WindowLists(v).firstObject;
    BOOL atTop = YES, wholeRow = YES;
    for (NSNumber *o in left.offsets.allValues) if (o.doubleValue != 0) atTop = NO;
    for (MMWindowGroup *g in busy.memoryGroups) [left reveal:g.rows.lastObject.key];
    for (NSNumber *o in left.offsets.allValues) if (o.doubleValue <= 0 || fmod(o.doubleValue, 24) != 0) wholeRow = NO;
    Check(atTop && wholeRow && left.offsets.count == 3, @"window: every group opens at its first row, and scrolled to its end it still rests on a whole row",
          [left.offsets.allValues componentsJoinedByString:@" "]);
    [left rest];
    Check(left.offsets.count == 0, @"window: a closed window forgets its scrolling, so it opens at the top again", @"");
}

#pragma mark The welcome

/// A host that only writes down what Start handed it.
@interface WelcomeHost : NSObject <MMWindowHost>
@property NSInteger starts, removal, fixes, rules;
@property BOOL login;
@end
@implementation WelcomeHost
- (void)windowRunFixEverything { self.fixes++; }
- (void)windowStopRun {}
- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice { self.rules++; }
- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on { self.rules++; }
- (void)windowQuit {}
- (void)windowWelcomeStart:(BOOL)openAtLogin removal:(NSInteger)removal { self.starts++; self.login = openAtLogin; self.removal = removal; }
@end

static NSArray<MMWindowButton *> *WindowButtons(NSView *v) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *sub in v.subviews) if ([sub isKindOfClass:MMWindowButton.class]) [out addObject:sub];
    return out;
}

/// The view in a window that is never shown, so a point can be hit-tested as a press would be.
static NSWindow *WelcomeWindow(MMWindowView *v) {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    win.releasedWhenClosed = NO;
    [win.contentView addSubview:v];
    return win;
}

/// What a press at the middle of `at` would land on.
static NSView *WelcomeHit(MMWindowView *v, NSRect at, NSView *in) {
    NSPoint p = [v.superview convertPoint:NSMakePoint(NSMidX(at), NSMidY(at)) fromView:in];
    return [v hitTest:p];
}

static void WelcomePress(NSView *hit) { if ([hit isKindOfClass:NSButton.class]) [(NSButton *)hit performClick:nil]; }

/// A second press where Start was must never reach the menu that arrives under it: with fixes ready, Fix Everything
/// sits at that very point. Nothing of the menu takes a press or a key until it has arrived and a moment more.
static void WindowWelcomeGuardChecks(void) {
    WelcomeHost *host = [WelcomeHost new];
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.host = host;
    NSWindow *win = WelcomeWindow(v);
    MMWindowModel *m = MMWindowFixture(@"busy");
    m.welcome = MMWindowFixture(@"welcome").welcome;
    v.model = m;
    MMWindowWelcomeView *w = v.welcomeView;
    NSButton *start = w.controls.lastObject;
    NSRect at = start.frame;
    NSView *first = WelcomeHit(v, at, w);
    Check(first == start && m.fixCount == 7, @"welcome guard: with seven fixes ready, a press at Start lands on Start", NSStringFromClass(first.class));
    WelcomePress(first);
    NSView *second = WelcomeHit(v, at, w);
    WelcomePress(second);
    WelcomePress(WelcomeHit(v, at, w));
    Check(host.starts == 1 && host.fixes == 0, @"welcome guard: a second and a third press at the same point right after Start run no fix",
          [NSString stringWithFormat:@"%ld starts, %ld runs of Fix Everything, the press landed on %@", (long)host.starts, (long)host.fixes, NSStringFromClass(second.class)]);
    MMWindowDockView *dock = nil;
    for (NSView *sub in WindowLists(v).firstObject.superview.subviews) if ([sub isKindOfClass:MMWindowDockView.class]) dock = (MMWindowDockView *)sub;
    MMWindowButton *gear = nil, *power = nil;
    for (MMWindowButton *b in WindowButtons(v)) { if (b.kind == MMWindowButtonGear) gear = b; if (b.kind == MMWindowButtonPower) power = b; }
    [dock.fix performClick:nil];
    [gear performClick:nil];
    NSEvent *enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    NSEvent *space = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
    [v keyDown:enter]; [v keyDown:space];
    Check(dock && host.fixes == 0 && !v.showsSettings && !dock.fix.canBecomeKeyView && !gear.canBecomeKeyView && WelcomeHit(v, gear.frame, v) != gear,
          @"welcome guard: until the menu has arrived, no press, key or VoiceOver press reaches Fix Everything or the gear, and Tab reaches neither", @"");
    Check(WelcomeHit(v, power.frame, v) == power && power.canBecomeKeyView, @"welcome guard: Quit stays pressable all the way", @"");
    // The guard is the time the menu takes to arrive and a moment more. Then the menu is the menu.
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MMWindowStartGuard + 0.2]];
    NSView *later = WelcomeHit(v, at, w);
    Check(later == dock.fix && dock.fix.canBecomeKeyView && gear.canBecomeKeyView && WelcomeHit(v, gear.frame, v) == gear, @"welcome guard: after the guard time Fix Everything and the gear take a press again", NSStringFromClass(later.class));
    WelcomePress(later);
    Check(host.fixes == 1, @"welcome guard: and a press on Fix Everything then runs it once", [NSString stringWithFormat:@"%ld", (long)host.fixes]);
    [win close];

    // A view on its way in or out takes no press: the welcome's own buttons while they rise in.
    MMWindowView *r = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    WelcomeHost *rh = [WelcomeHost new];
    r.host = rh;
    NSWindow *rwin = WelcomeWindow(r);
    r.model = MMWindowFixture(@"welcome");
    MMWindowWelcomeView *rw = r.welcomeView;
    NSButton *rs = rw.controls.lastObject, *rl = rw.controls.firstObject;
    NSRect home = rs.frame;
    rw.arrival = 0.5;
    WelcomePress(WelcomeHit(r, home, rw));
    [rs performClick:nil]; [rl performClick:nil];
    [r keyDown:enter];
    Check(rs.alphaValue < 1 && rh.starts == 0 && rw.loginOn && !rs.canBecomeKeyView, @"welcome guard: while the welcome's parts rise in, no press or Return reaches a button that is not there yet",
          [NSString stringWithFormat:@"alpha %g, %ld starts", rs.alphaValue, (long)rh.starts]);
    rw.arrival = 1;
    // The rise is short: Start is in its place, and takes a press, within 0.9 s of the window's opening. Right before
    // the end it still takes none, and under Reduce Motion nothing rises at all.
    rw.arrival = 0.98;
    BOOL lateStill = rs.alphaValue < 1 && !MMWindowTakesPresses(rs);
    rw.arrival = 1;
    Check(MMWindowWelcomeRise > 0.6 && MMWindowWelcomeRise <= 0.9001 && lateStill && rs.alphaValue == 1 && MMWindowTakesPresses(rs),
          @"welcome: every part has risen in within 0.9 s of the opening, and Start takes a press from then and not before",
          [NSString stringWithFormat:@"%.2f s, alpha %g", MMWindowWelcomeRise, rs.alphaValue]);
    // The one-side days: only the rows of the fixes that are left carry the mark, and no other row's story says it goes.
    for (NSString *name in @[@"memory-only", @"disk-only"]) {
        MMWindowModel *m = MMWindowFixture(name);
        NSMutableArray<NSString *> *off = [NSMutableArray new];
        BOOL memory = [name isEqualToString:@"memory-only"];
        NSInteger marked = 0;
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) {
            BOOL goes = [r.facts.lastObject.value hasPrefix:@"Goes."];
            if (r.inFix) marked++;
            if (r.inFix != goes || (r.inFix && (side == m.diskGroups) == memory)) [off addObject:r.key];
            if (!r.inFix && [@[@"will close", @"may go", @"merged"] containsObject:r.state ?: @""]) [off addObject:r.key];
        }
        Check(off.count == 0 && marked > 0, [NSString stringWithFormat:@"window %@: only rows of the fixes that are left say they go", name], [off componentsJoinedByString:@" "]);
    }
    // Tab goes through the five controls and Quit, and back to the first.
    [rwin recalculateKeyViewLoop];
    NSMutableArray<NSString *> *loop = [NSMutableArray new];
    NSView *key = rl;
    for (NSInteger i = 0; i < 12 && key; i++) {
        [loop addObject:key.accessibilityLabel ?: NSStringFromClass(key.class)];
        key = key.nextValidKeyView;
        if (key == rl) break;
    }
    Check(key == rl && loop.count == 6 && [loop containsObject:@"Quit MinMacs, Command Q"] && [loop.firstObject hasPrefix:@"Open at login"] && [loop containsObject:@"Start"],
          @"welcome: Tab goes through the switch, the three choices, Start and Quit, and around", [loop componentsJoinedByString:@" > "]);
    WelcomePress(WelcomeHit(r, home, rw));
    Check(rh.starts == 1, @"welcome guard: once they have landed, Start starts", @"");
    [rwin close];
}

/// The welcome of the first launch, as checks: it stands alone, nothing is cut or outside the window, the switch and
/// the three choices are real buttons that say what they are, the answers stay the person's, Start hands them over
/// once, and the welcome does not come back.
static void WindowWelcomeChecks(void) {
    WelcomeHost *host = [WelcomeHost new];
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.host = host;
    v.model = MMWindowFixture(@"welcome");
    MMWindowWelcomeView *w = v.welcomeView;
    NSView *menu = WindowLists(v).firstObject.superview;
    MMWindowButton *gear = nil, *power = nil;
    for (MMWindowButton *b in WindowButtons(v)) { if (b.kind == MMWindowButtonGear) gear = b; if (b.kind == MMWindowButtonPower) power = b; }
    Check(v.showsWelcome && w && menu.hidden && gear.hidden && power && !power.hidden && NSEqualSizes(w.frame.size, MMWindowSize) && NSEqualSizes(v.frame.size, MMWindowSize),
          @"welcome: it stands alone at the window's size: no lists, no dock, no gear, and Quit stays", @"");
    v.showsSettings = YES;
    Check(!v.showsSettings && v.showsWelcome, @"welcome: Settings does not open over it", @"");

    // One centered column, top to bottom, inside the window with room at both ends.
    NSArray<NSValue *> *parts = w.partFrames;
    BOOL ordered = parts.count == 8, centered = YES, inside = YES;
    CGFloat last = 0;
    for (NSValue *p in parts) {
        NSRect r = p.rectValue;
        if (r.origin.y < last) ordered = NO;
        last = NSMaxY(r);
        if (fabs(NSMidX(r) - MMWindowSize.width / 2) > 0.5) centered = NO;
        if (r.origin.x < 40 || NSMaxX(r) > MMWindowSize.width - 40 || r.size.height <= 0) inside = NO;
    }
    CGFloat top = parts.firstObject.rectValue.origin.y, bottom = MMWindowSize.height - NSMaxY(parts.lastObject.rectValue);
    Check(ordered && centered && inside && top >= 40 && bottom >= 40 && fabs(top - bottom) <= 1, @"welcome: one centered column, no part over another, with the same room above the mark as below Start",
          [NSString stringWithFormat:@"%g above, %g below", top, bottom]);

    // The switch, the three choices and Start are buttons, in that order, each inside its card and saying what it is.
    NSArray<NSButton *> *c = w.controls;
    BOOL five = c.count == 5, labelled = YES, within = YES, oneLine = YES;
    for (NSButton *b in c) {
        if (!b.accessibilityLabel.length || ![b isDescendantOf:w] || b.hidden) labelled = NO;
        if (!NSContainsRect(w.bounds, [w convertRect:b.bounds fromView:b])) within = NO;
    }
    for (NSUInteger i = 1; i + 1 < c.count; i++) {
        if (!NSContainsRect(parts[4].rectValue, [w convertRect:c[i].bounds fromView:c[i]])) within = NO;
        if (c[i].frame.size.height != 30) oneLine = NO;
    }
    Check(five && labelled && within && oneLine && NSEqualRects(c.firstObject.frame, parts[3].rectValue) && NSEqualRects(c.lastObject.frame, parts[7].rectValue),
          @"welcome: the switch, three choices and Start are real buttons inside the column, and each choice's sentence fits on one line", @"");
    if (!five) return;
    MMWindowWelcome *words = v.model.welcome;
    Check([c[0].accessibilityRole isEqualToString:NSAccessibilityCheckBoxRole] && [c[0].accessibilityValue isEqual:@1] &&
          [c[0].accessibilityLabel isEqualToString:@"Open at login. MinMacs starts when you sign in."],
          @"welcome: VoiceOver reads the switch with its state and what the state means", c[0].accessibilityLabel);
    Check([c[1].accessibilityRole isEqualToString:NSAccessibilityRadioButtonRole] && [c[1].accessibilityValue isEqual:@1] && [c[2].accessibilityValue isEqual:@0] && [c[3].accessibilityValue isEqual:@0] &&
          [c[3].accessibilityLabel isEqualToString:[NSString stringWithFormat:@"%@, %@. %@", words.removalTitle, words.removal[2].title, words.removal[2].explain]],
          @"welcome: VoiceOver reads each removal choice with its sentence, and Smart is the one picked", c[3].accessibilityLabel);
    Check([w.accessibilityLabel containsString:words.title] && [w.accessibilityLabel containsString:words.say] && [w.accessibilityLabel containsString:words.facts.lastObject.value] &&
          [w.accessibilityLabel containsString:@"Both can be changed later in Settings."],
          @"welcome: VoiceOver reads the title, the two sentences, that both can be changed later, and the facts", w.accessibilityLabel);
    NSView *group = c[1].superview;
    Check(group != w && group == c[2].superview && group == c[3].superview && group.isAccessibilityElement && [group.accessibilityRole isEqualToString:NSAccessibilityRadioGroupRole] &&
          [group.accessibilityLabel isEqualToString:words.removalTitle] && NSEqualRects(group.frame, parts[4].rectValue),
          @"welcome: the three choices are one radio group, named by the card's title", @"");
    BOOL keys = YES;
    for (NSButton *b in c) if (!b.canBecomeKeyView) keys = NO;
    Check(keys && c.lastObject.keyEquivalent.length == 0, @"welcome: Tab reaches every control, and no hidden button holds a key of its own", @"");

    // An answer the person has not touched follows the model: a choice made elsewhere while the welcome was closed,
    // as with `minmacs removal trash`, or a login item that changed.
    MMWindowModel *outside = MMWindowFixture(@"welcome-trash");
    outside.welcome.loginOn = NO;
    v.model = outside;
    Check(w.picked == 1 && !w.loginOn && [c[2].accessibilityValue isEqual:@1] && [c[0].accessibilityLabel isEqualToString:@"Open at login. MinMacs starts only when you open it."],
          @"welcome: an answer not touched yet follows a choice made outside meanwhile", [NSString stringWithFormat:@"picked %ld", (long)w.picked]);
    v.model = MMWindowFixture(@"welcome");
    Check(w.picked == 0 && w.loginOn, @"welcome: and follows it back", @"");
    // The arrow keys move the pick through the group and around its ends.
    NSEvent *(^arrow)(unsigned short) = ^NSEvent *(unsigned short code) {
        return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                              characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
    };
    [c[1] keyDown:arrow(125)];
    NSInteger down = w.picked;
    [c[2] keyDown:arrow(125)]; [c[3] keyDown:arrow(125)];
    NSInteger around = w.picked;
    [c[1] keyDown:arrow(126)];
    Check(down == 1 && around == 0 && w.picked == 2 && host.starts == 0, @"welcome: Down moves the pick to the next choice and around the end, and Up back around",
          [NSString stringWithFormat:@"%ld %ld %ld", (long)down, (long)around, (long)w.picked]);
    [c[1] performClick:nil];

    // The answers are the person's: a press changes them, nothing reaches the host, and a newer model takes none back.
    [c[0] performClick:nil];
    [c[3] performClick:nil];
    Check(!w.loginOn && w.picked == 2 && [c[0].accessibilityValue isEqual:@0] && [c[0].accessibilityLabel isEqualToString:@"Open at login. MinMacs starts only when you open it."] &&
          [c[3].accessibilityValue isEqual:@1] && [c[1].accessibilityValue isEqual:@0] && host.starts == 0,
          @"welcome: a press turns the switch off and picks Delete, the switch says what off means, and nothing is applied yet", c[0].accessibilityLabel);
    MMWindowModel *newer = MMWindowFixture(@"welcome");
    newer.generation = 2;
    v.model = newer;
    Check(v.showsWelcome && !w.loginOn && w.picked == 2 && v.welcomeView == w, @"welcome: a newer model keeps what the person picked", @"");
    // The words change under the person's picks: the day of watching ended, so the first fact is another one and
    // the cards are built again. The model still says on and Smart. The picks stay.
    MMWindowModel *changed = MMWindowFixture(@"welcome-watched");
    changed.generation = 2;
    v.model = changed;
    c = w.controls;
    Check(c.count == 5 && !w.loginOn && w.picked == 2 && [c[3].accessibilityValue isEqual:@1] && [c[0].accessibilityValue isEqual:@0] && changed.welcome.loginOn && changed.welcome.removalPicked == 0 &&
          [w.accessibilityLabel containsString:@"It has watched a day"],
          @"welcome: when a fact changes and the cards are built again, the switch and the choice the person picked stay", [NSString stringWithFormat:@"login %d, picked %ld", w.loginOn, (long)w.picked]);
    if (c.count != 5) return;

    // Start, by Return: the two answers go to the host once, the menu takes the welcome's place, and it stays away.
    NSEvent *enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    [v keyDown:enter];
    Check(host.starts == 1 && !host.login && host.removal == 2, @"welcome: Return presses Start, which hands over the switch and the choice", [NSString stringWithFormat:@"%ld starts", (long)host.starts]);
    [v keyDown:enter];
    [w pressStart];
    Check(host.starts == 1, @"welcome: a second Return or press starts nothing again", [NSString stringWithFormat:@"%ld starts", (long)host.starts]);
    Check(!v.showsWelcome && !menu.hidden && !gear.hidden && v.model.welcome == nil, @"welcome: after Start the menu and the gear are back in the same window", @"");
    MMWindowModel *late = MMWindowFixture(@"welcome");
    late.generation = 3;
    v.model = late;
    Check(!v.showsWelcome && !menu.hidden && v.model.generation == 3, @"welcome: a model built before Start does not bring it back", @"");
    v.showsSettings = YES;
    Check(v.showsSettings, @"welcome: after Start, Settings opens as before", @"");

    // Opened before the first snapshot: a model of generation 0 holds the welcome alone.
    MMWindowView *cold = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    WelcomeHost *coldHost = [WelcomeHost new];
    cold.host = coldHost;
    MMWindowModel *bare = [MMWindowModel new];
    bare.welcome = MMWindowFixture(@"welcome").welcome;
    cold.model = bare;
    Check(cold.showsWelcome && cold.model == nil, @"welcome: before the first snapshot it shows with no numbers behind it", @"");
    [cold.welcomeView pressStart];
    cold.model = bare;
    Check(!cold.showsWelcome && cold.model == nil && coldHost.starts == 1 && coldHost.login && coldHost.removal == 0,
          @"welcome: Start before the first snapshot hands over the switch on and Smart, and leaves the window waiting for its first numbers", @"");
    cold.model = MMWindowFixture(@"young");
    Check(!cold.showsWelcome && cold.model.generation == 1 && WindowLists(cold).firstObject.drawnNames.count > 0, @"welcome: then the first numbers fill the lists", @"");

    // A person who pressed Start long ago never sees it.
    MMWindowView *old = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    old.model = MMWindowFixture(@"young");
    Check(!old.showsWelcome && old.welcomeView == nil && MMWindowFixture(@"young").welcome == nil && MMWindowFixture(@"busy").welcome == nil,
          @"welcome: a model with no welcome shows none, and makes no welcome view", @"");

    // The three other pictures differ only in the answers.
    NSArray<MMWindowFact *> *watched = MMWindowFixture(@"welcome-watched").welcome.facts;
    Check(watched.count == 3 && [watched[0].label isEqualToString:@"It has watched a day"] && [watched[1].value isEqualToString:words.facts[1].value],
          @"welcome: the watched fixture differs in its first fact only", @"");
    Check(!MMWindowFixture(@"welcome-off").welcome.loginOn && MMWindowFixture(@"welcome-trash").welcome.removalPicked == 1 && MMWindowFixture(@"welcome-delete").welcome.removalPicked == 2 &&
          MMWindowFixture(@"welcome").welcome.loginOn && MMWindowFixture(@"welcome").welcome.removalPicked == 0,
          @"welcome: the fixtures cover the switch on and off and each removal choice", @"");
    // Welcome and Settings show the same words for both choices.
    MMWindowSettings *st = MMWindowFixture(@"welcome").settings;
    MMWindowRule *card = st.rules.lastObject;
    BOOL same = [card.title isEqualToString:words.removalTitle] && card.choices.count == words.removal.count;
    for (NSUInteger i = 0; same && i < card.choices.count; i++)
        same = [card.choices[i].title isEqualToString:words.removal[i].title] && [card.choices[i].explain isEqualToString:words.removal[i].explain];
    Check(same && [st.switches.lastObject.title isEqualToString:words.loginTitle] && [st.switches.lastObject.note isEqualToString:words.loginOnNote] &&
          [MMWindowLoginNote(NO) isEqualToString:words.loginOffNote],
          @"welcome: the removal choice and Open at login say the same words as their Settings card and switch", @"");
    NSMutableArray<NSString *> *bad = [NSMutableArray new];
    for (NSString *s in [MMWindowView shownStrings:MMWindowFixture(@"welcome")])
        for (NSString *no in @[@"!", @"…", @"...", @"hide icon", @"nothing needs you", @"everything is fine"])
            if ([s rangeOfString:no options:NSCaseInsensitiveSearch].location != NSNotFound) [bad addObject:s];
    Check(bad.count == 0, @"welcome: no shown string holds an exclamation mark, an ellipsis, Hide Icon or a claimed result", [bad componentsJoinedByString:@" | "]);
}
