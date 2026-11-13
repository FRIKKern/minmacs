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
    if (self.memoryHour) [self drawHour:self.memoryHour in:NSMakeRect(18, 17, self.bounds.size.width - 36, h - 17)];
    if (self.diskHour) [self drawHour:self.diskHour in:NSMakeRect(18, 17 + h + 17, self.bounds.size.width - 36, h - 17)];
}

/// How long ago the minute at this index was, as an end of the graph says it. The newest minute is "now".
static NSString *Ago(NSInteger index, NSInteger count) {
    NSInteger minutes = count - 1 - index;
    return minutes <= 0 ? @"now" : minutes >= 59 ? @"an hour ago" : [NSString stringWithFormat:@"%ld min ago", (long)minutes];
}

static NSAttributedString *End(NSString *when, double bytes, NSColor *quiet, NSColor *value) {
    return MMWindowJoin(@[MMWindowText([when stringByAppendingString:@", "], 10.5, NSFontWeightRegular, quiet),
                          MMWindowText(MMWindowBytes((uint64_t)bytes), 10.5, NSFontWeightRegular, value)]);
}

/// One graph: its title, "the last hour", how far it moved, what the height means, the filled line and both ends in words.
/// The filled part spans the whole width, and each end says how old it is, so a young hour reads as what it is.
- (void)drawHour:(MMWindowHour *)hour in:(NSRect)r {
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSColor *ink = MMWindowColor(hour.side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(hour.title, 12.5, NSFontWeightMedium, NSColor.whiteColor), MMWindowText(@"  the last hour", 11.5, NSFontWeightSemibold, t2)]),
                 r.origin.x, r.origin.y + 8.5, -1);
    MMWindowDraw(MMWindowFit(hour.explain, 11, NSFontWeightRegular, t2, r.size.width), r.origin.x, r.origin.y + 24, -1);
    NSInteger a, b, filled, count = (NSInteger)hour.values.count;
    NSArray *span = MMWindowHourSpan(hour.values, &a, &b, &filled);
    if (!span) { [self drawYoung:hour newest:b filled:filled in:r ink:ink]; return; }
    double first = [hour.values[a] doubleValue], last = [hour.values[b] doubleValue], moved = last - first;
    // A move too small for the unit to show reads as no move.
    uint64_t by = (uint64_t)fabs(moved);
    NSString *move = by < (1 << 20) || by < MAX(first, last) * 0.002 ? @"about the same"
        : [NSString stringWithFormat:@"%@ %@", moved > 0 ? @"up" : @"down", MMWindowBytes(by)];
    MMWindowDraw(MMWindowText(move, 12, NSFontWeightSemibold, [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]), NSMaxX(r), r.origin.y + 8.5, 1);
    MMWindowDrawHour(hour.values, NSMakeRect(r.origin.x, r.origin.y + 36, r.size.width, r.size.height - 36 - 16), ink, MMWindowHourGraph);
    CGFloat y = NSMaxY(r) - 6.5;
    MMWindowDraw(End(Ago(a, count), first, t3, t2), r.origin.x, y, -1);
    MMWindowDraw(End(Ago(b, count), last, t3, t2), NSMaxX(r), y, 1);
}

/// The first minutes, before there is a line to draw: the newest value large, and under it the hour as an empty track
/// with the minutes that have passed filled in at its right end, where "now" is. No value is made up, and the
/// block sits in the middle of the graph's place, so nothing looks missing.
- (void)drawYoung:(MMWindowHour *)hour newest:(NSInteger)b filled:(NSInteger)filled in:(NSRect)r ink:(NSColor *)ink {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSRect plot = NSMakeRect(r.origin.x, r.origin.y + 36, r.size.width, r.size.height - 36);
    CGFloat mid = round(NSMidY(plot)) + 6, left = NSMinX(plot) + 1, right = NSMaxX(plot) - 3;
    NSInteger count = (NSInteger)hour.values.count;
    if (b >= 0) {
        MMWindowDraw(MMWindowNumber([hour.values[b] unsignedLongLongValue], 30, NSFontWeightMedium, text, 13), r.origin.x, mid - 30, -1);
        MMWindowDraw(MMWindowText(Ago(b, count), 11.5, NSFontWeightRegular, t2), NSMaxX(r), mid - 22, 1);
    }
    NSBezierPath *track = [NSBezierPath bezierPath];
    [track moveToPoint:NSMakePoint(left, mid)]; [track lineToPoint:NSMakePoint(right, mid)];
    track.lineWidth = 1.5; track.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.24 : 0.09] setStroke];
    [track stroke];
    if (b >= 0 && count > 1) {
        // The newest minute is the right end, as on a full graph. Each minute that has passed is a sixtieth of the track.
        CGFloat end = left + (right - left) * b / (count - 1), start = end - (right - left) * MAX(filled - 1, 0) / (count - 1);
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(start, mid)]; [line lineToPoint:NSMakePoint(end, mid)];
        line.lineWidth = 1.5; line.lineCapStyle = NSLineCapStyleRound;
        [ink setStroke]; [line stroke];
        [ink setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(end - 2.4, mid - 2.4, 4.8, 4.8)] fill];
    }
    MMWindowDraw(MMWindowText(@"The line fills in as the hour passes.", 11, NSFontWeightRegular, t3), r.origin.x, mid + 18, -1);
    if (filled > 0) MMWindowDraw(MMWindowText(MMPlural(filled, @"minute"), 10.5, NSFontWeightRegular, t3), NSMaxX(r), mid + 18, 1);
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

/// "The biggest", "2nd biggest", "11th biggest".
static NSString *Rank(NSInteger n) {
    if (n <= 1) return @"The biggest";
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

    // The whole name, on two lines when one is too short for it. Everything under it moves down by that line.
    NSString *name = row.shownName;
    CGFloat nameLeft = x + 46, nameRoom = w - 46 - 72;
    NSMutableParagraphStyle *words = [NSMutableParagraphStyle new];
    words.lineBreakMode = NSLineBreakByWordWrapping;
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:name attributes:@{
        NSFontAttributeName: MMWindowFont(15, NSFontWeightSemibold), NSForegroundColorAttributeName: text, NSParagraphStyleAttributeName: words}];
    BOOL two = MMWindowWidth(MMWindowText(name, 15, NSFontWeightSemibold, text)) > nameRoom;
    CGFloat more = two ? 18 : 0;
    MMWindowDrawIcon(row, NSMakeRect(x, 21 + more / 2, 28, 28), backing);
    if (two) [title drawWithRect:NSMakeRect(nameLeft, 17, nameRoom, 40) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine];
    else MMWindowDraw(title, nameLeft, 27, -1);
    // Under the name: the group it is listed in, and its quiet word.
    NSString *sub = group.title ?: @"";
    if (row.state.length) sub = sub.length ? [NSString stringWithFormat:@"%@ · %@", sub, row.state] : row.state;
    MMWindowDraw(MMWindowFit(sub, 11.5, NSFontWeightRegular, t2, nameRoom), nameLeft, 44.5 + more, -1);
    // The Mac's ring, small, with this row's arc lit: its share at a glance.
    MMWindowDrawRing(self.model, NSMakePoint(x + w - 31, 37), YES, row);

    // The numbers: memory or disk, CPU when known, and the row's own hour to the right.
    CGFloat top = 72 + more, at = x;
    // Tabs that hold no bytes of their own show their count where the size would stand.
    NSAttributedString *big = row.showsSize ? MMWindowNumber(row.bytes, 24, NSFontWeightMedium, text, 12)
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
        MMWindowDraw(MMWindowFit([NSString stringWithFormat:@"%@, %@", Ago(a, (NSInteger)row.hour.count), MMWindowBytes([row.hour[a] unsignedLongLongValue])],
                                 10.5, NSFontWeightRegular, t3, x + w - at), at, top + 50.5, -1);
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
        [line drawWithRect:NSMakeRect(x + 19, y, w - 19, h) options:NSStringDrawingUsesLineFragmentOrigin];
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
        [value drawWithRect:NSMakeRect(x + column, y, w - column, h) options:NSStringDrawingUsesLineFragmentOrigin];
        y += h + 6;
    }

    // Where it stands in its group, with the biggest of the others, under a hairline.
    NSInteger place = group ? (NSInteger)[group.rows indexOfObject:row] : NSNotFound;
    if (place == NSNotFound || group.rows.count < 2 || y + 12 + 26 + 21 > bottom) return;
    y += 6;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.07] setFill];
    NSRectFillUsingOperation(NSMakeRect(x, y, w, 1), NSCompositingOperationSourceOver);
    MMWindowDraw(MMWindowText([NSString stringWithFormat:@"%@ of %lu %@", Rank(place + 1), (unsigned long)group.rows.count, group.title.lowercaseString], 11, NSFontWeightRegular, t2), x, y + 17, -1);
    y += 28;
    NSInteger shown = 0;
    for (MMWindowRow *other in group.rows) {
        if (other == row) continue;
        if (shown >= 5 || y + 21 > bottom) break;
        NSAttributedString *size = other.showsSize ? MMWindowText(MMWindowBytes(other.bytes), 11.5, NSFontWeightRegular, t2) : nil;
        CGFloat room = w - (size ? MMWindowWidth(size) + 12 : 0);
        MMWindowDraw(MMWindowText(MMWindowShorten(other.shownName, 12.5, NSFontWeightRegular, room), 12.5, NSFontWeightRegular, text), x, y + 10.5, -1);
        if (size) MMWindowDraw(size, x + w, y + 10.5, 1);
        y += 21; shown++;
    }
}

@end
