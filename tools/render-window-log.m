// The log in the middle of the menu window, slice 1 of the center: an empty log, a new Mac's first hour and a busy
// month of 300 entries, in pictures and in checks. tools/render.m includes this file after render-window-polish.m and
// uses its Check, PolishView, WordViews and the word watch of render-window-words.m. It is not built on its own.

/// fixture, state, the row the pointer rests on. "scrolled" moves the log 120 entries down, "end" to its last.
static NSArray<NSArray *> *WindowLogShots(void) {
    return @[@[@"log-empty", @"main", @""], @[@"log-new", @"main", @""], @[@"log-busy", @"main", @""],
             @[@"log-busy", @"scrolled", @""], @[@"log-busy", @"end", @""], @[@"log-busy", @"server", @"server:6006"]];
}

static MMWindowLogView *LogViewOf(MMWindowView *v) { return WordViews(v, MMWindowLogView.class).firstObject; }

/// Moves the log of a shot where its state says.
static void LogShotState(MMWindowView *v, NSString *state) {
    if ([state isEqualToString:@"scrolled"]) LogViewOf(v).first = 120;
    if ([state isEqualToString:@"end"]) LogViewOf(v).first = 100000;
}

/// Draws a view into a throwaway bitmap, so its drawRect runs.
static void LogDraw(NSView *v) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
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
        for (NSString *name in @[@"log-empty", @"log-new", @"log-busy", @"busy", @"young", @"long"]) {
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
    BOOL twelve = [seen containsObject:@"the last 11 min"];
    [seen removeAllObjects];
    LogDraw(WordViews(PolishView(@"young"), MMWindowMiddleView.class).firstObject);
    BOOL young = [seen containsObject:@"Fills in as the hour passes."] && ![seen containsObject:@"the last hour"];
    Check(hour && twelve && young, @"window log: the strip says the last hour, the last 11 min of a young hour, and that the first minutes fill in",
          [NSString stringWithFormat:@"%@ %@ %@", hour ? @"yes" : @"no", twelve ? @"yes" : @"no", young ? @"yes" : @"no"]);
    MMWindowWatchDraws(nil);
}
