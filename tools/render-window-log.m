// The log in the middle of the menu window, slice 1 of the center: an empty log, a new Mac's first hour and a busy
// month of 300 entries, in pictures and in checks. tools/render.m includes this file after render-window-polish.m and
// uses its Check, PolishView, WordViews and the word watch of render-window-words.m. It is not built on its own.

/// fixture, state, the row the pointer rests on. "scrolled" moves the log 120 entries down, "end" to its last.
static NSArray<NSArray *> *WindowLogShots(void) {
    return @[@[@"log-empty", @"main", @""], @[@"log-new", @"main", @""], @[@"log-busy", @"main", @""],
             @[@"log-busy", @"scrolled", @""], @[@"log-busy", @"end", @""], @[@"log-busy", @"server", @"server:6006"],
             // The Undo presses and the runs, and Undo under the pointer.
             @[@"log-undo", @"main", @""], @[@"log-undo", @"undo-hover", @""]];
}

static MMWindowLogView *LogViewOf(MMWindowView *v) { return WordViews(v, MMWindowLogView.class).firstObject; }

/// Moves the log of a shot where its state says.
static void LogShotState(MMWindowView *v, NSString *state) {
    if ([state isEqualToString:@"undo-hover"]) [LogViewOf(v).undoButtons.firstObject setHover:YES];
    if ([state isEqualToString:@"scrolled"]) LogViewOf(v).first = 120;
    if ([state isEqualToString:@"end"]) LogViewOf(v).first = 100000;
}

/// Draws a view into a throwaway bitmap, so its drawRect runs.
static void LogDraw(NSView *v) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
}

/// The Undo presses: one for each shown entry that can still be taken back and none for any other, each inside the
/// log and clear of the words beside it, a press hands its record to the host, and Tab and VoiceOver reach them.
static void WindowLogUndoChecks(void) {
    PolishHost *host = [PolishHost new];
    MMWindowView *v = PolishView(@"log-undo");
    v.host = host;
    MMWindowLogView *log = LogViewOf(v);
    LogDraw(v);
    NSArray<MMWindowButton *> *presses = log.undoButtons;
    NSMutableArray<NSString *> *want = [NSMutableArray new], *got = [NSMutableArray new];
    for (MMWindowLogEntry *e in log.log.entries) if (e.canUndo && [log.drawnSentences containsObject:e.sentence]) [want addObject:e.undoRid];
    for (MMWindowButton *b in presses) [got addObject:b.identifier ?: @"-"];
    Check(want.count == 2 && [want isEqualToArray:got], @"window log: an Undo press stands at each shown entry that can still be taken back, and at no other: not the one taken back, the one being taken back or the deleted one",
          [NSString stringWithFormat:@"want %@, got %@", [want componentsJoinedByString:@" "], [got componentsJoinedByString:@" "]]);
    // Each press inside the log, at its right edge, and clear of every word drawn in the log.
    __block NSMutableArray<NSValue *> *words = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) { if (NSEqualRects(bounds, log.bounds)) [words addObject:[NSValue valueWithRect:used]]; });
    LogDraw(log);
    MMWindowWatchDraws(nil);
    NSInteger clear = 0;
    for (MMWindowButton *b in presses) {
        BOOL inside = NSContainsRect(log.bounds, b.frame), apart = YES;
        for (NSValue *w in words) if (NSIntersectsRect(NSInsetRect(b.frame, 1, 1), w.rectValue)) apart = NO;
        if (inside && apart && b.toolTip.length && [b.accessibilityLabel hasPrefix:@"Undo: "]) clear++;
    }
    Check(presses.count && clear == (NSInteger)presses.count && words.count > 10, @"window log: each Undo press is inside the log, over no drawn word, with a tooltip and a VoiceOver label that names its entry",
          [NSString stringWithFormat:@"%ld of %lu, %lu words, %@", (long)clear, (unsigned long)presses.count, (unsigned long)words.count, presses.firstObject.accessibilityLabel]);
    [presses.firstObject performClick:nil];
    Check(host.undos == 1 && [host.lastUndo isEqualToString:want.firstObject ?: @"?"], @"window log: a press on Undo hands the entry's record to the host, once",
          [NSString stringWithFormat:@"%ld %@", (long)host.undos, host.lastUndo]);
    // VoiceOver reads each entry and its press after it, and a run's skips after its quiet line.
    NSArray *kids = log.accessibilityChildren;
    NSUInteger at = [kids indexOfObject:presses.firstObject];
    id before = at != NSNotFound && at > 0 ? kids[at - 1] : nil;
    BOOL runSaid = NO;
    for (id k in kids) if ([[k accessibilityLabel] containsString:@"Fix Everything: 5 done, 2 skipped."] && [[k accessibilityLabel] containsString:@"Skipped Claude Code in atlas: it asks you."]) runSaid = YES;
    Check(at != NSNotFound && [[before accessibilityLabel] containsString:@"Stopped :3000 Next.js atlas."] && runSaid, @"window log: VoiceOver reads each entry with its Undo press right after it, and a run with each thing it skipped",
          [NSString stringWithFormat:@"%lu children", (unsigned long)kids.count]);
    // Tab reaches every press, in the window as it is shown.
    NSWindow *win = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    win.releasedWhenClosed = NO;
    win.contentView = v;
    [win recalculateKeyViewLoop];
    NSInteger reached = 0;
    for (MMWindowButton *b in presses) if (b.canBecomeKeyView) reached++;
    NSView *next = presses.firstObject.nextValidKeyView;
    Check(reached == (NSInteger)presses.count && next != nil, @"window log: Tab reaches every Undo press", [NSString stringWithFormat:@"%ld of %lu", (long)reached, (unsigned long)presses.count]);
    // A run is one entry with its skips as its more, and the restored action says both its times in one entry.
    MMWindowLog *l = log.log;
    NSInteger runs = 0, backs = 0;
    for (MMWindowLogEntry *e in l.entries) {
        if ([e.kind isEqualToString:@"run"] && e.more.length) runs++;
        if ([e.kind isEqualToString:@"restored"] && [e.time containsString:@", started again "]) backs++;
    }
    Check(runs == 2 && backs == 1, @"window log: a run is one entry with what it skipped as its more, and an action taken back is one entry with its two times", @"");
    [win close];
}

static void WindowLogChecks(void) {
    // Every string the log and its strip draw, at every place the fingers can move the busy log to, in both looks:
    // no ellipsis, none past its box, none past its view.
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    __block NSMutableArray<NSString *> *seen = [NSMutableArray new];
    __block NSInteger strings = 0;
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        strings++;
        [seen addObject:text];
        NSString *fault = nil;
        if ([text containsString:@"…"] || [text containsString:@"..."]) fault = @"ellipsis";
        else if (!NSIsEmptyRect(allowed) && (NSWidth(used) > NSWidth(allowed) + 1 || NSMaxY(used) > NSMaxY(allowed) + 1)) fault = @"past its box";
        else if (!NSIsEmptyRect(bounds) && (NSMinX(used) < NSMinX(bounds) - 1 || NSMaxX(used) > NSMaxX(bounds) + 1 || NSMinY(used) < NSMinY(bounds) - 1 || NSMaxY(used) > NSMaxY(bounds) + 1)) fault = @"past its view";
        if (fault && faults.count < 10) [faults addObject:[NSString stringWithFormat:@"%@: %@", fault, text]];
    });
    NSInteger places = 0;
    for (NSNumber *contrast in @[@NO, @YES]) {
        MMWindowForceContrast(contrast.boolValue);
        for (NSString *name in @[@"log-empty", @"log-new", @"log-busy", @"log-undo", @"busy", @"young", @"long"]) {
            MMWindowView *v = PolishView(name);
            MMWindowLogView *log = LogViewOf(v);
            NSInteger n = (NSInteger)log.log.entries.count;
            for (NSInteger at = 0; at <= n; at += n > 40 ? 7 : 1) {
                log.first = at;
                LogDraw(v); places++;
            }
        }
    }
    MMWindowForceContrast(NO);
    Check(faults.count == 0 && places > 100, @"window log: at every place in every log, in both looks, no drawn string holds an ellipsis, none is past its box and none leaves its view",
          [NSString stringWithFormat:@"%ld strings at %ld places. %@", (long)strings, (long)places, [faults componentsJoinedByString:@" | "]]);

    // The busy log: whole entries from the newest, the foot says what waits, and the fingers reach the oldest.
    MMWindowView *busy = PolishView(@"log-busy");
    MMWindowLogView *log = LogViewOf(busy);
    LogDraw(busy);
    NSArray<NSString *> *top = log.drawnSentences;
    NSString *foot = log.footLine;
    Check(log.log.entries.count == 300 && top.count >= 5 && [top.firstObject isEqualToString:log.log.entries.firstObject.sentence] && [foot hasSuffix:@"more below"],
          @"window log: the busy log of 300 shows whole entries from the newest, and says how many wait below",
          [NSString stringWithFormat:@"%lu shown, foot %@", (unsigned long)top.count, foot]);
    log.first = 100000;
    LogDraw(busy);
    Check([log.drawnSentences.lastObject isEqualToString:log.log.entries.lastObject.sentence] && [log.footLine hasSuffix:@"more above"] && log.first < 300,
          @"window log: moved to its end, the oldest entry is the last one drawn, whole, and the foot says how many wait above",
          [NSString stringWithFormat:@"first %ld, foot %@", (long)log.first, log.footLine]);
    // A new log that still holds the entry at the top keeps it there.
    log.first = 40;
    NSString *kept = log.log.entries[40].key;
    MMWindowModel *again = MMWindowFixture(@"log-busy");
    busy.model = again;
    Check(log.log == again.log && [log.log.entries[(NSUInteger)log.first].key isEqualToString:kept], @"window log: a new log keeps the entry at the top where it was", @(log.first).stringValue);
    // Under a pointed row the story stands over the whole middle, and the log is away.
    busy.pointedRow = @"server:6006";
    Check(log.hidden, @"window log: a pointed row's story replaces the middle, the log too", @"");
    busy.pointedRow = nil;
    Check(!log.hidden, @"window log: the log is back when the pointer leaves the row", @"");

    // A new or empty Mac says what MinMacs watches and that it acts on nothing in its first day, and claims no result.
    for (NSString *name in @[@"log-empty", @"log-new"]) {
        MMWindowView *v = PolishView(name);
        [seen removeAllObjects];
        LogDraw(v);
        NSString *note = LogViewOf(v).log.note;
        BOOL says = [[seen componentsJoinedByString:@" "] containsString:note ?: @"-"] && [note containsString:@"MinMacs watches your servers, agents, apps, worktrees and caches."]
                 && [note containsString:@"For its first day it stops, quits and removes nothing on its own."];
        Check(says, [NSString stringWithFormat:@"window log %@: the note says what MinMacs watches and that it acts on nothing in its first day", name], note ?: @"no note");
    }
    MMWindowView *empty = PolishView(@"log-empty");
    LogDraw(empty);
    Check(LogViewOf(empty).drawnSentences.count == 0 && LogViewOf(empty).footLine == nil && [LogViewOf(empty).log.note hasPrefix:@"Nothing is in the log yet."],
          @"window log: an empty log draws its note alone", @"");
    Check(MMWindowLogNote(NO, nil) == nil, @"window log: after the first day a log with entries has no note", @"");

    // The strip keeps the hour's honesty: a full hour says the last hour, a young one says it fills in.
    [seen removeAllObjects];
    LogDraw(WordViews(PolishView(@"busy"), MMWindowMiddleView.class).firstObject);
    BOOL hour = [seen containsObject:@"the last hour"];
    [seen removeAllObjects];
    LogDraw(WordViews(PolishView(@"calm"), MMWindowMiddleView.class).firstObject);
    // The young hour's words are dev's own, MMWindowHourSpanWords over the minutes the line holds: "the last 12 min".
    NSInteger ca = -1, cb = -1;
    MMWindowHourSpanAtLeast(MMWindowFixture(@"calm").memoryHour.values, MMWindowHourGraphLeast, &ca, &cb, NULL);
    NSString *calmWords = MMWindowHourSpanWords(cb - ca + 1);
    BOOL twelve = cb - ca + 1 < 60 && [seen containsObject:calmWords];
    [seen removeAllObjects];
    LogDraw(WordViews(PolishView(@"young"), MMWindowMiddleView.class).firstObject);
    BOOL young = [seen containsObject:@"Fills in as the hour passes."] && ![seen containsObject:@"the last hour"];
    Check(hour && twelve && young, @"window log: the strip says the last hour, how many minutes a young hour holds, and that the first minutes fill in",
          [NSString stringWithFormat:@"%@ %@ (%@) %@", hour ? @"yes" : @"no", twelve ? @"yes" : @"no", calmWords, young ? @"yes" : @"no"]);
    MMWindowWatchDraws(nil);
    // Its own word watch, so after the one above.
    WindowLogUndoChecks();
}
