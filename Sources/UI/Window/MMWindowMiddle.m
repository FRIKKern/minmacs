// The middle of the window: the two last-hour graphs, or the story of the row the pointer rests on.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

@implementation MMWindowMiddleView

- (void)setMemoryHour:(MMWindowHour *)h { _memoryHour = h; self.needsDisplay = YES; }
- (void)setDiskHour:(MMWindowHour *)h { _diskHour = h; self.needsDisplay = YES; }
- (void)setRow:(MMWindowRow *)row { if (_row == row) return; _row = row; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    if (self.row) { [self drawStory:self.row]; return; }
    CGFloat h = floor((self.bounds.size.height - 34) / 2);
    MMWindowHour *memory = self.memoryHour ?: [self before:MMWindowMemory], *disk = self.diskHour ?: [self before:MMWindowDisk];
    if (memory) [self drawHour:memory in:NSMakeRect(18, 17, self.bounds.size.width - 36, h - 17)];
    if (disk) [self drawHour:disk in:NSMakeRect(18, 17 + h + 17, self.bounds.size.width - 36, h - 17)];
}

/// Before Core has kept a first minute there is no hour. The middle still stands: the same frame with no minute
/// filled, and the number the ring holds now. Nothing in it is a reading of the past.
- (MMWindowHour *)before:(MMWindowSide)side {
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

/// How long ago the minute at this index was, as an end of the graph says it. The newest minute is "now".
static NSString *Ago(NSInteger index, NSInteger count) {
    NSInteger minutes = count - 1 - index;
    return minutes <= 0 ? @"now" : minutes >= 59 ? @"an hour ago" : [NSString stringWithFormat:@"%ld min ago", (long)minutes];
}

static NSAttributedString *End(NSString *when, double bytes, BOOL disk, NSColor *quiet, NSColor *value) {
    return MMWindowJoin(@[MMWindowText([when stringByAppendingString:@", "], 10.5, NSFontWeightRegular, quiet),
                          MMWindowText(MMWindowBytes((uint64_t)bytes, disk), 10.5, NSFontWeightRegular, value)]);
}

/// One graph: its title, "the last hour", how far it moved, what the height means, the filled line and both ends in words.
/// The filled part spans the whole width, and each end says how old it is, so a young hour reads as what it is.
- (void)drawHour:(MMWindowHour *)hour in:(NSRect)r {
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSColor *ink = MMWindowColor(hour.side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(hour.title, 12.5, NSFontWeightMedium, NSColor.whiteColor), MMWindowText(@"  the last hour", 11.5, NSFontWeightSemibold, t2)]),
                 r.origin.x, r.origin.y + 8.5, -1);
    BOOL disk = hour.side == MMWindowDisk;
    MMWindowDrawBlock(hour.explain, 11, 10, NSFontWeightRegular, t2, r.origin.x, r.origin.y + 24, r.size.width, -1, 0, 26);
    NSInteger a, b, filled, count = (NSInteger)hour.values.count;
    NSArray *span = MMWindowHourSpan(hour.values, &a, &b, &filled);
    if (!span) { [self drawYoung:hour newest:b filled:filled in:r ink:ink]; return; }
    double first = [hour.values[a] doubleValue], last = [hour.values[b] doubleValue], moved = last - first;
    // A move too small for the unit to show reads as no move.
    uint64_t by = (uint64_t)fabs(moved);
    NSString *move = by < (1 << 20) || by < MAX(first, last) * 0.002 ? @"about the same"
        : [NSString stringWithFormat:@"%@ %@", moved > 0 ? @"up" : @"down", MMWindowBytes(by, disk)];
    MMWindowDraw(MMWindowText(move, 12, NSFontWeightSemibold, [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]), NSMaxX(r), r.origin.y + 8.5, 1);
    MMWindowDrawHour(hour.values, NSMakeRect(r.origin.x, r.origin.y + 36, r.size.width, r.size.height - 36 - 16), ink, MMWindowHourGraph);
    CGFloat y = NSMaxY(r) - 6.5;
    MMWindowDraw(End(Ago(a, count), first, disk, t3, t2), r.origin.x, y, -1);
    MMWindowDraw(End(Ago(b, count), last, disk, t3, t2), NSMaxX(r), y, 1);
}

/// The first minutes, before there is a line to draw. The block is a graph's whole frame, so nothing looks missing:
/// the title above, the newest value large in the middle, and at the foot, where a graph's floor and its two ends
/// stand, an empty track with the minutes that have passed filled in at its right end, where "now" is, and the words
/// that say what will come. No value is made up.
- (void)drawYoung:(MMWindowHour *)hour newest:(NSInteger)b filled:(NSInteger)filled in:(NSRect)r ink:(NSColor *)ink {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    BOOL disk = hour.side == MMWindowDisk;
    CGFloat floorY = NSMaxY(r) - 20, left = NSMinX(r) + 1, right = NSMaxX(r) - 3, middle = round((r.origin.y + 36 + floorY) / 2);
    NSInteger count = (NSInteger)hour.values.count;
    // With no minute kept yet, the number is the one the ring holds now.
    MMWindowRing *ring = self.model.ring;
    uint64_t newest = b >= 0 ? [hour.values[b] unsignedLongLongValue] : disk ? ring.diskFree : ring.memoryUsed;
    if (b >= 0 || ring) {
        MMWindowDraw(MMWindowNumber(newest, disk, 34, NSFontWeightMedium, text, 14), r.origin.x, middle - 4, -1);
        MMWindowDraw(MMWindowText(@"now", 11.5, NSFontWeightRegular, t2), r.origin.x, middle + 22, -1);
    }
    NSBezierPath *track = [NSBezierPath bezierPath];
    [track moveToPoint:NSMakePoint(left, floorY)]; [track lineToPoint:NSMakePoint(right, floorY)];
    track.lineWidth = 1.5; track.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.24 : 0.09] setStroke];
    [track stroke];
    if (b >= 0 && count > 1) {
        // The newest minute is the right end, as on a full graph. Each minute that has passed is a sixtieth of the track.
        CGFloat end = left + (right - left) * b / (count - 1), start = end - (right - left) * MAX(filled - 1, 0) / (count - 1);
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(start, floorY)]; [line lineToPoint:NSMakePoint(end, floorY)];
        line.lineWidth = 1.5; line.lineCapStyle = NSLineCapStyleRound;
        [ink setStroke]; [line stroke];
        [ink setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(end - 2.4, floorY - 2.4, 4.8, 4.8)] fill];
    }
    MMWindowDraw(MMWindowText(@"The line fills in as the hour passes.", 10.5, NSFontWeightRegular, t3), r.origin.x, NSMaxY(r) - 6.5, -1);
    if (filled > 0) MMWindowDraw(MMWindowText(MMWindowCount(filled, @"minute", @"minutes"), 10.5, NSFontWeightRegular, t3), NSMaxX(r), NSMaxY(r) - 6.5, 1);
}

#pragma mark A row's story

static NSString *GroupKey(MMWindowKind kind) {
    switch (kind) {
        case MMWindowServer: return @"servers";
        case MMWindowAgent: return @"agents";
        case MMWindowApp: case MMWindowHelper: case MMWindowTabs: return @"apps";
        case MMWindowWorktree: return @"worktrees";
        case MMWindowCache: return @"caches";
    }
    return @"";
}

/// "The biggest", "2nd biggest", "11th biggest", and "The smallest" for the last of several.
static NSString *Rank(NSInteger n, NSInteger of) {
    if (n <= 1) return @"The biggest";
    if (n == of) return @"The smallest";
    NSString *end = n % 100 >= 11 && n % 100 <= 13 ? @"th" : n % 10 == 1 ? @"st" : n % 10 == 2 ? @"nd" : n % 10 == 3 ? @"rd" : @"th";
    return [NSString stringWithFormat:@"%ld%@ biggest", (long)n, end];
}

- (MMWindowGroup *)groupOf:(MMWindowRow *)row {
    for (NSArray<MMWindowGroup *> *side in @[self.model.memoryGroups ?: @[], self.model.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) if ([g.rows containsObject:row]) return g;
    return nil;
}

/// A row's story, 195-a's: its icon, name and group with the Mac's ring small beside them; its number large, CPU and
/// its own hour; the one line on whether it stays, goes or asks; its facts; and where it stands in its group.
- (void)drawStory:(MMWindowRow *)row {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    CGFloat x = 14, w = self.bounds.size.width - 28, bottom = self.bounds.size.height - 8;
    BOOL disk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
    MMWindowGroup *group = [self groupOf:row];
    NSColor *backing = [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1];

    // The whole name, on as many lines as it needs. Everything under it moves down by those lines.
    NSString *name = row.shownName;
    CGFloat nameLeft = x + 46, nameRoom = w - 46 - 72;
    NSInteger nameLines = (NSInteger)MMWindowLines(name, 15, NSFontWeightSemibold, nameRoom).count;
    // Under the name: the group it is listed in, and its quiet word.
    NSString *sub = group.title ?: @"";
    if (row.state.length) sub = sub.length ? [NSString stringWithFormat:@"%@ · %@", sub, row.state] : row.state;
    CGFloat nameHeight = MMWindowLineHeight(15) * nameLines, subHeight = MMWindowBlockHeight(sub, 11.5, 11.5, NSFontWeightRegular, nameRoom);
    CGFloat more = nameHeight + subHeight - MMWindowLineHeight(15) - MMWindowLineHeight(11.5);
    MMWindowDrawIcon(row, NSMakeRect(x, 21, 28, 28), backing);
    MMWindowDrawBlock(name, 15, 15, NSFontWeightSemibold, text, nameLeft, 17, nameRoom, -1, -1, 0);
    MMWindowDrawBlock(sub, 11.5, 11.5, NSFontWeightRegular, t2, nameLeft, 17 + nameHeight + 0.5, nameRoom, -1, -1, 0);
    // The Mac's ring, small, with this row's arc lit: its share at a glance.
    MMWindowDrawRing(self.model, NSMakePoint(x + w - 31, 37), YES, row, NO);

    // The numbers: memory or disk, CPU when known, and the row's own hour to the right.
    CGFloat top = 72 + more, at = x;
    // Tabs that hold no bytes of their own show their count where the size would stand.
    NSAttributedString *big = row.showsSize ? MMWindowNumber(row.bytes, disk, 24, NSFontWeightMedium, text, 12)
                                            : MMWindowText(@(row.tabs).stringValue, 24, NSFontWeightMedium, text);
    MMWindowDraw(MMWindowText(!row.showsSize ? @"Tabs" : disk ? @"Disk" : @"Memory", 11, NSFontWeightRegular, t2), at, top + 7, -1);
    MMWindowDraw(big, at, top + 28, -1);
    at += MAX(MMWindowWidth(big), 44) + 20;
    if (row.cpuPercent >= 0) {
        MMWindowDraw(MMWindowText(@"CPU", 11, NSFontWeightRegular, t2), at, top + 7, -1);
        NSAttributedString *c = MMWindowJoin(@[MMWindowText(MMWindowCPU(row.cpuPercent) ?: @"0", 24, NSFontWeightMedium, text), MMWindowText([MMWindowThin stringByAppendingString:@"%"], 12, NSFontWeightRegular, t2)]);
        MMWindowDraw(c, at, top + 28, -1);
        at += MAX(MMWindowWidth(c), 44) + 20;
    }
    NSInteger a, b;
    if (MMWindowHourSpan(row.hour, &a, &b, NULL) && x + w - at >= 90) {
        NSColor *ink = MMWindowColor(disk ? MMWindowInkDisk : MMWindowInkMemory);
        MMWindowDraw(MMWindowText(@"Its last hour", 11, NSFontWeightRegular, t2), at, top + 7, -1);
        MMWindowDrawHour(row.hour, NSMakeRect(at, top + 16, x + w - at, 28), ink, MMWindowHourStory);
        // Where the line began, under it, when it fits on its one line at 10 points or more. A detail: left out when it does not.
        NSString *began = [NSString stringWithFormat:@"%@, %@", Ago(a, (NSInteger)row.hour.count), MMWindowBytes([row.hour[a] unsignedLongLongValue], disk)];
        if (MMWindowLines(began, 10, NSFontWeightRegular, x + w - at).count == 1) MMWindowDrawBlock(began, 10.5, 10, NSFontWeightRegular, t3, at, top + 44, x + w - at, -1, -1, 14);
    }
    CGFloat y = top + 66;

    // The one line: a mark, the lead in bold and the sentence after it, in the color of what it says.
    NSMutableParagraphStyle *wrap = [NSMutableParagraphStyle new];
    wrap.lineBreakMode = NSLineBreakByWordWrapping;
    MMWindowFate *fate = row.fate;
    if (fate) {
        NSColor *ink = fate.kind == MMWindowFateAsks ? NSColor.whiteColor : fate.kind == MMWindowFateGoes ? MMWindowColor(MMWindowInkFix) : MMWindowGroupColor(GroupKey(row.kind));
        NSMutableAttributedString *line = [NSMutableAttributedString new];
        if (fate.lead.length) [line appendAttributedString:MMWindowText(fate.note.length ? [fate.lead stringByAppendingString:@" "] : fate.lead, 12, NSFontWeightSemibold, ink)];
        if (fate.note.length) [line appendAttributedString:MMWindowText(fate.note, 12, NSFontWeightRegular, ink)];
        [line addAttribute:NSParagraphStyleAttributeName value:wrap range:NSMakeRange(0, line.length)];
        CGFloat h = MAX(ceil([line boundingRectWithSize:NSMakeSize(w - 19, 200) options:NSStringDrawingUsesLineFragmentOrigin].size.height), 15);
        NSRect mark = NSMakeRect(x, y + 2, 12, 12);
        if (fate.kind == MMWindowFateAsks) MMWindowDrawDiamond(mark, ink);
        else if (fate.kind == MMWindowFateGoes) {
            NSBezierPath *tri = [NSBezierPath bezierPath];
            [tri moveToPoint:NSMakePoint(x + 1.8, y + 5)]; [tri lineToPoint:NSMakePoint(x + 10.2, y + 5)]; [tri lineToPoint:NSMakePoint(x + 6, y + 11.6)]; [tri closePath];
            [ink setFill]; [tri fill];
        } else { [ink setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x + 2.4, y + 4.4, 7.2, 7.2)] fill]; }
        MMWindowDrawIn(line, NSMakeRect(x + 19, y, w - 19, h));
        y += h + 9;
    }

    // The facts, labels in one column. A long value wraps and is never cut.
    CGFloat column = 0;
    NSArray<MMWindowFact *> *facts = row.storyFacts;
    for (MMWindowFact *f in facts) column = MAX(column, MMWindowWidth(MMWindowText(f.label, 12, NSFontWeightRegular, t2)));
    column = MIN(MAX(column + 16, 100), 150);
    for (MMWindowFact *f in facts) {
        NSAttributedString *value = [[NSAttributedString alloc] initWithString:f.value ?: @"" attributes:@{
            NSFontAttributeName: MMWindowFont(12.5, NSFontWeightRegular), NSForegroundColorAttributeName: text, NSParagraphStyleAttributeName: wrap}];
        NSRect need = [value boundingRectWithSize:NSMakeSize(w - column, 400) options:NSStringDrawingUsesLineFragmentOrigin];
        CGFloat h = MAX(ceil(need.size.height), 16);
        if (y + h > bottom) return;
        MMWindowDraw(MMWindowText(f.label, 12, NSFontWeightRegular, t2), x, y + 8, -1);
        MMWindowDrawIn(value, NSMakeRect(x + column, y, w - column, h));
        y += h + 6;
    }

    // Where it stands in its group, with the biggest of the others, under a hairline.
    NSInteger place = group ? (NSInteger)[group.rows indexOfObject:row] : NSNotFound;
    if (place == NSNotFound || group.rows.count < 2 || y + 12 + 26 + 21 > bottom) return;
    y += 6;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.07] setFill];
    NSRectFillUsingOperation(NSMakeRect(x, y, w, 1), NSCompositingOperationSourceOver);
    MMWindowDraw(MMWindowText([NSString stringWithFormat:@"%@ of %lu %@", Rank(place + 1, (NSInteger)group.rows.count), (unsigned long)group.rows.count, group.title.lowercaseString], 11, NSFontWeightRegular, t2), x, y + 17, -1);
    y += 28;
    NSInteger shown = 0;
    for (MMWindowRow *other in group.rows) {
        if (other == row) continue;
        NSAttributedString *size = other.showsSize ? MMWindowText(MMWindowBytes(other.bytes, disk), 11.5, NSFontWeightRegular, t2) : nil;
        CGFloat room = w - (size ? MMWindowWidth(size) + 12 : 0), h = MAX(21, MMWindowBlockHeight(other.shownName, 12.5, 12.5, NSFontWeightRegular, room) + 4);
        if (shown >= 5 || y + h > bottom) break;
        MMWindowDrawBlock(other.shownName, 12.5, 12.5, NSFontWeightRegular, text, x, y + 2, room, -1, -1, 0);
        if (size) MMWindowDraw(size, x + w, y + 10.5, 1);
        y += h; shown++;
    }
}

@end
