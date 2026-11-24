// The strip at the top of the middle, DESIGN rule 2: memory in use and disk free, side by side, over the last hour or
// the last 7 days, with the two words "hour · 7 days" under them that choose which. Every line is a reading Core kept:
// a minute or an hour with none is a gap, and nothing is drawn across it. The pointer over a line shows the reading
// under it, from the values the strip already holds, so a move of the pointer only redraws.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

static const CGFloat kSideTop = 6, kSideHeight = 68, kWordsMid = 83, kWordsHeight = 16;

@interface MMWindowStripState : NSObject
@property (strong) MMWindowHour *memoryWeek, *diskWeek;
@property BOOL week;
@property (strong) NSNumber *asked;                    // the press's choice, until a model says the same
@property (strong) MMWindowButton *hourPress, *weekPress;
@property (copy) void (^onWeek)(BOOL week);
@property NSInteger side;                              // the side under the pointer: 0 none, 1 memory, 2 disk
@property NSInteger index;                             // the value under the pointer, an index of the side's values
@property (copy) NSString *reading;
@end
@implementation MMWindowStripState
@end

/// One side's reading under the pointer, as the strip draws it.
typedef struct { NSInteger first, count; BOOL drawn; } MMStripSpan;

@implementation MMWindowMiddleView (MMWindowStrip)

#pragma mark The state

- (MMWindowStripState *)stripState {
    if (!self.strip) self.strip = [MMWindowStripState new];
    return self.strip;
}
- (MMWindowHour *)memoryWeek { return self.stripState.memoryWeek; }
- (MMWindowHour *)diskWeek { return self.stripState.diskWeek; }
- (void)setMemoryWeek:(MMWindowHour *)h { self.stripState.memoryWeek = h; self.needsDisplay = YES; }
- (void)setDiskWeek:(MMWindowHour *)h { self.stripState.diskWeek = h; self.needsDisplay = YES; }
- (BOOL)stripWeek { return self.stripState.week; }
- (void)setStripWeek:(BOOL)week {
    MMWindowStripState *st = self.stripState;
    if (st.week != week) { st.side = 0; st.reading = nil; }
    st.week = week;
    st.hourPress.lit = !week; st.weekPress.lit = week;
    st.hourPress.accessibilitySelected = !week; st.weekPress.accessibilitySelected = week;
    self.needsDisplay = YES;
}
- (MMWindowButton *)hourPress { return self.stripState.hourPress; }
- (MMWindowButton *)weekPress { return self.stripState.weekPress; }
- (void (^)(BOOL))onWeek { return self.stripState.onWeek; }
- (void)setOnWeek:(void (^)(BOOL))onWeek { self.stripState.onWeek = onWeek; }
- (NSString *)stripReading { return self.stripState.reading; }

- (void)takeStripWeek:(BOOL)week {
    MMWindowStripState *st = self.stripState;
    if (st.asked && st.asked.boolValue != week) return;
    st.asked = nil;
    self.stripWeek = week;
}

#pragma mark The two words

- (void)makeStripPresses {
    MMWindowStripState *st = self.stripState;
    st.hourPress = [MMWindowButton kind:MMWindowButtonSegment title:@"hour" target:self action:@selector(pressStripWord:)];
    st.weekPress = [MMWindowButton kind:MMWindowButtonSegment title:@"7 days" target:self action:@selector(pressStripWord:)];
    st.hourPress.toolTip = @"Show the last hour, one value a minute";
    st.weekPress.toolTip = @"Show the last 7 days, one value an hour";
    for (MMWindowButton *b in @[st.hourPress, st.weekPress]) [self addSubview:b];
    self.stripWeek = NO;
    [self placeStripPresses];
}

/// Right under the two sides, at the strip's right end: "hour · 7 days". Away while a story stands over the middle.
- (void)placeStripPresses {
    MMWindowStripState *st = self.stripState;
    if (!st.hourPress) return;
    CGFloat right = self.bounds.size.width - 14, dot = 12;
    CGFloat weekWidth = ceil(MMWindowText(@"7 days", 10.5, NSFontWeightSemibold, NSColor.whiteColor).size.width) + 14;
    CGFloat hourWidth = ceil(MMWindowText(@"hour", 10.5, NSFontWeightSemibold, NSColor.whiteColor).size.width) + 14;
    st.weekPress.frame = NSMakeRect(right - weekWidth, kWordsMid - kWordsHeight / 2, weekWidth, kWordsHeight);
    st.hourPress.frame = NSMakeRect(right - weekWidth - dot - hourWidth, kWordsMid - kWordsHeight / 2, hourWidth, kWordsHeight);
    st.hourPress.hidden = st.weekPress.hidden = self.row != nil;
}

- (void)pressStripWord:(MMWindowButton *)sender {
    BOOL week = sender == self.stripState.weekPress;
    self.stripState.asked = @(week);
    self.stripWeek = week;
    if (self.stripState.onWeek) self.stripState.onWeek(week);
}

#pragma mark The two sides

/// What each side draws now: the 7 days once the shell has read them while the strip shows them, else the hour.
- (BOOL)showsWeek { return self.stripWeek && (self.memoryWeek || self.diskWeek); }

- (NSRect)sideRect:(NSInteger)side {
    CGFloat gap = 16, w = floor((self.bounds.size.width - 28 - gap) / 2);
    return NSMakeRect(side == 2 ? 14 + w + gap : 14, kSideTop, w, kSideHeight);
}

- (MMWindowHour *)sideHour:(NSInteger)side {
    BOOL disk = side == 2;
    if (self.showsWeek) return disk ? self.diskWeek : self.memoryWeek;
    return (disk ? self.diskHour : self.memoryHour) ?: [self stripBefore:disk ? MMWindowDisk : MMWindowMemory];
}

/// Before Core has kept a first minute there is no hour. The strip still stands: the same frame with no minute
/// filled, and the number the ring holds now. Nothing in it is a reading of the past.
- (MMWindowHour *)stripBefore:(MMWindowSide)side {
    MMWindowRing *ring = self.model.ring;
    if (!ring || !(side == MMWindowDisk ? ring.diskTotal : ring.memoryTotal)) return nil;
    MMWindowHour *h = [MMWindowHour new];
    h.side = side;
    BOOL disk = side == MMWindowDisk;
    h.title = MMWindowHourTitle(disk);
    h.explain = MMWindowHourExplain(disk, disk ? ring.diskTotal : ring.memoryTotal);
    NSMutableArray *none = [NSMutableArray new];
    for (NSInteger i = 0; i < 60; i++) [none addObject:NSNull.null];
    h.values = none;
    return h;
}

/// The part of a side's values its line spreads across its width: from the first filled to the last for the hour,
/// from the first filled to the newest hour for the 7 days.
static MMStripSpan SpanOf(MMWindowHour *h, BOOL week) {
    NSInteger a = -1, b = -1;
    NSArray *span = week ? MMWindowWeekSpan(h.values, &a, NULL) : MMWindowHourSpanAtLeast(h.values, MMWindowHourGraphLeast, &a, &b, NULL);
    return (MMStripSpan){ a, (NSInteger)span.count, span != nil };
}

/// The graph's rect inside a side, and where in it the value at index i of the span stands, as MMWindowDrawHour puts it.
static NSRect GraphRect(NSRect r) { return NSMakeRect(r.origin.x, r.origin.y + 38, r.size.width, NSMaxY(r) - r.origin.y - 38); }
static CGFloat XOf(NSRect g, NSInteger i, NSInteger count) { return NSMinX(g) + 1 + (g.size.width - 2.6) * i / MAX(count - 1, 1); }

/// "Tue 14:00" for an hour of the 7 days, "12 min ago" for a minute of the hour.
- (NSString *)whenOf:(MMWindowHour *)h index:(NSInteger)i week:(BOOL)week {
    if (!week) return MMWindowAgo(i, (NSInteger)h.values.count);
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; [f setLocalizedDateFormatFromTemplate:@"EEEHHmm"]; });
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:h.firstAt + i * 3600.0]];
}

- (void)pointStripAt:(NSPoint)p {
    MMWindowStripState *st = self.stripState;
    NSInteger side = 0, index = -1;
    NSString *reading = nil;
    BOOL week = self.showsWeek;
    for (NSInteger s = 1; s <= 2 && !self.row; s++) {
        NSRect r = [self sideRect:s], g = GraphRect(r);
        if (p.x < NSMinX(g) || p.x > NSMaxX(g) || p.y < r.origin.y + 20 || p.y > NSMaxY(r)) continue;
        MMWindowHour *h = [self sideHour:s];
        MMStripSpan span = SpanOf(h, week);
        if (!span.drawn) break;
        NSInteger i = (NSInteger)lround((p.x - NSMinX(g) - 1) / (g.size.width - 2.6) * (span.count - 1));
        index = span.first + MAX(0, MIN(i, span.count - 1));
        side = s;
        id v = h.values[(NSUInteger)index];
        BOOL disk = h.side == MMWindowDisk;
        reading = [NSString stringWithFormat:@"%@ · %@", [self whenOf:h index:index week:week],
                   [v isKindOfClass:NSNumber.class] ? MMWindowBytes([v unsignedLongLongValue], disk) : @"nothing kept"];
    }
    if (st.side == side && st.index == index) return;
    st.side = side; st.index = index; st.reading = reading;
    [self setNeedsDisplayInRect:NSMakeRect(0, 0, self.bounds.size.width, MMWindowStripHeight)];
}

- (void)drawStrips {
    BOOL week = self.showsWeek;
    for (NSInteger s = 1; s <= 2; s++) {
        MMWindowHour *h = [self sideHour:s];
        if (h) [self drawSide:h in:[self sideRect:s] week:week pointed:self.stripState.side == s ? self.stripState.index : -1];
    }
    // The dot between the two words.
    MMWindowButton *hour = self.stripState.hourPress, *days = self.stripState.weekPress;
    if (hour && !hour.hidden)
        MMWindowDraw(MMWindowText(@"·", 10.5, NSFontWeightRegular, MMWindowColor(MMWindowInkText3)), (NSMaxX(hour.frame) + NSMinX(days.frame)) / 2, kWordsMid, 0);
}

/// One side: its title and how much it holds, MMWindowHourSpanWords or MMWindowWeekSpanWords, the newest value and how
/// far it moved, and the filled line small under them. With the pointer on the line, the value there and when. Before
/// two values are kept, the newest number over an empty track, with words for what will come. No value is made up.
- (void)drawSide:(MMWindowHour *)hour in:(NSRect)r week:(BOOL)week pointed:(NSInteger)pointed {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSColor *ink = MMWindowColor(hour.side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory);
    BOOL disk = hour.side == MMWindowDisk;
    NSInteger a, b = -1, filled, count = (NSInteger)hour.values.count;
    NSArray *span;
    if (week) {
        span = MMWindowWeekSpan(hour.values, &a, &filled);
        for (NSInteger i = count - 1; i >= 0 && b < 0; i--) if ([hour.values[i] isKindOfClass:NSNumber.class]) b = i;
    } else span = MMWindowHourSpanAtLeast(hour.values, MMWindowHourGraphLeast, &a, &b, &filled);
    MMWindowDraw(MMWindowText(hour.title, 11.5, NSFontWeightMedium, NSColor.whiteColor), r.origin.x, r.origin.y + 8, -1);
    NSString *words = !span ? @"now" : week ? MMWindowWeekSpanWords(count - a) : MMWindowHourSpanWords(b - a + 1);
    MMWindowDraw(MMWindowText(words, 10.5, NSFontWeightRegular, t3), NSMaxX(r), r.origin.y + 8, 1);
    MMWindowRing *ring = self.model.ring;
    BOOL known = b >= 0 || ring;
    NSRect g = GraphRect(r);
    if (span && pointed >= 0 && pointed < count) {
        // The reading under the pointer, where the newest value and its move stand, and a hairline at its place.
        id v = hour.values[(NSUInteger)pointed];
        if ([v isKindOfClass:NSNumber.class]) MMWindowDraw(MMWindowNumber([v unsignedLongLongValue], disk, 15, NSFontWeightMedium, text, 10.5), r.origin.x, r.origin.y + 27, -1);
        else MMWindowDraw(MMWindowText(@"nothing kept", 11.5, NSFontWeightRegular, t3), r.origin.x, r.origin.y + 27, -1);
        MMWindowDraw(MMWindowText([self whenOf:hour index:pointed week:week], 10.5, NSFontWeightRegular, t2), NSMaxX(r), r.origin.y + 27, 1);
        CGFloat x = round(XOf(g, pointed - a, (NSInteger)span.count)) + 0.5;
        [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.55 : 0.28] setFill];
        NSRectFillUsingOperation(NSMakeRect(x - 0.5, NSMinY(g), 1, g.size.height), NSCompositingOperationSourceOver);
        MMWindowDrawHour(hour.values, g, ink, week ? MMWindowHourWeek : MMWindowHourStrip);
        return;
    }
    uint64_t newest = b >= 0 ? [hour.values[b] unsignedLongLongValue] : disk ? ring.diskFree : ring.memoryUsed;
    if (known) MMWindowDraw(MMWindowNumber(newest, disk, 15, NSFontWeightMedium, text, 10.5), r.origin.x, r.origin.y + 27, -1);
    if (span) {
        double first = [hour.values[a] doubleValue], last = [hour.values[b] doubleValue], moved = last - first;
        // A move too small for the unit to show reads as no move.
        uint64_t by = (uint64_t)fabs(moved);
        NSString *move = by < (1 << 20) || by < MAX(first, last) * 0.002 ? @"about the same"
            : [NSString stringWithFormat:@"%@ %@", moved > 0 ? @"up" : @"down", MMWindowBytes(by, disk)];
        MMWindowDraw(MMWindowText(move, 10.5, NSFontWeightRegular, t2), NSMaxX(r), r.origin.y + 27, 1);
        MMWindowDrawHour(hour.values, g, ink, week ? MMWindowHourWeek : MMWindowHourStrip);
        return;
    }
    // The first minutes or hours: an empty track, with the minutes that passed filled in at its right end, where now is.
    CGFloat floorY = NSMaxY(r) - 3, left = NSMinX(r) + 1, right = NSMaxX(r) - 3;
    NSBezierPath *track = [NSBezierPath bezierPath];
    [track moveToPoint:NSMakePoint(left, floorY)]; [track lineToPoint:NSMakePoint(right, floorY)];
    track.lineWidth = 1.5; track.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.24 : 0.09] setStroke];
    [track stroke];
    if (!week && b >= 0 && count > 1) {
        CGFloat end = left + (right - left) * b / (count - 1), start = end - (right - left) * MAX(filled - 1, 0) / (count - 1);
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(start, floorY)]; [line lineToPoint:NSMakePoint(end, floorY)];
        line.lineWidth = 1.5; line.lineCapStyle = NSLineCapStyleRound;
        [ink setStroke]; [line stroke];
        [ink setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(end - 2.4, floorY - 2.4, 4.8, 4.8)] fill];
    }
    MMWindowDraw(MMWindowText(week ? @"Fills in as the days pass." : @"Fills in as the hour passes.", 10.5, NSFontWeightRegular, t3), r.origin.x, floorY - 11, -1);
}

@end
