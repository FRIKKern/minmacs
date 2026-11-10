// The middle of the window: the two last-hour graphs, or the story of the row the pointer rests on.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

@implementation MMWindowMiddleView

- (void)setMemoryHour:(MMWindowHour *)h { _memoryHour = h; self.needsDisplay = YES; }
- (void)setDiskHour:(MMWindowHour *)h { _diskHour = h; self.needsDisplay = YES; }
- (void)setRow:(MMWindowRow *)row { if (_row == row) return; _row = row; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirty {
    if (self.row) { [self drawStory:self.row]; return; }
    CGFloat h = floor((self.bounds.size.height - 34) / 2);
    if (self.memoryHour) [self drawHour:self.memoryHour in:NSMakeRect(18, 17, self.bounds.size.width - 36, h - 17)];
    if (self.diskHour) [self drawHour:self.diskHour in:NSMakeRect(18, 17 + h + 17, self.bounds.size.width - 36, h - 17)];
}

/// How long ago the minute at this index was, as the graph's left end says it.
static NSString *Ago(NSInteger index, NSInteger count) {
    NSInteger minutes = count - 1 - index;
    return minutes >= 55 ? @"an hour ago" : [NSString stringWithFormat:@"%ld min ago", (long)minutes];
}

/// The first and the last filled minute.
static BOOL Ends(NSArray *values, NSInteger *first, NSInteger *last) {
    *first = -1; *last = -1;
    for (NSInteger i = 0; i < (NSInteger)values.count; i++) {
        if (![values[i] isKindOfClass:NSNumber.class]) continue;
        if (*first < 0) *first = i;
        *last = i;
    }
    return *first >= 0 && *last > *first;
}

/// One graph: its title, "the last hour", how far it moved, what the height means, the filled line and both ends in words.
- (void)drawHour:(MMWindowHour *)hour in:(NSRect)r {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSColor *ink = MMWindowColor(hour.side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(hour.title, 12.5, NSFontWeightSemibold, text), MMWindowText(@"  the last hour", 12, NSFontWeightRegular, t2)]),
                 r.origin.x, r.origin.y + 8.5, -1);
    MMWindowDraw(MMWindowFit(hour.explain, 11, NSFontWeightRegular, t2, r.size.width), r.origin.x, r.origin.y + 25, -1);
    NSInteger a, b;
    if (!Ends(hour.values, &a, &b)) {
        MMWindowDraw(MMWindowText(@"The line shows after two minutes.", 11, NSFontWeightRegular, t3), r.origin.x, r.origin.y + 52, -1);
        return;
    }
    double first = [hour.values[a] doubleValue], last = [hour.values[b] doubleValue], moved = last - first;
    // A move too small for the unit to show reads as no move.
    uint64_t by = (uint64_t)fabs(moved);
    NSString *move = by < (1 << 20) || by < MAX(first, last) * 0.002 ? @"about the same"
        : [NSString stringWithFormat:@"%@ %@", moved > 0 ? @"up" : @"down", MMWindowBytes(by)];
    MMWindowDraw(MMWindowText(move, 12.5, NSFontWeightSemibold, text), NSMaxX(r), r.origin.y + 8.5, 1);
    MMWindowDrawHour(hour.values, NSMakeRect(r.origin.x, r.origin.y + 36, r.size.width, r.size.height - 36 - 16), ink, 1.5, YES);
    CGFloat y = NSMaxY(r) - 6.5;
    MMWindowDraw(MMWindowJoin(@[MMWindowText([Ago(a, (NSInteger)hour.values.count) stringByAppendingString:@", "], 10.5, NSFontWeightRegular, t3),
                                MMWindowText(MMWindowBytes((uint64_t)first), 10.5, NSFontWeightMedium, t2)]), r.origin.x, y, -1);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(@"now, ", 10.5, NSFontWeightRegular, t3), MMWindowText(MMWindowBytes((uint64_t)last), 10.5, NSFontWeightMedium, t2)]), NSMaxX(r), y, 1);
}

/// A row's story: its icon and name, its number large, CPU, its own hour when it has one, and its facts.
- (void)drawStory:(MMWindowRow *)row {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    CGFloat x = 18, w = self.bounds.size.width - 36;
    BOOL disk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
    MMWindowDrawIcon(row, NSMakeRect(x, 18, 28, 28), [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1]);
    NSString *name = row.kind == MMWindowTabs && row.tabs > 0 && ![row.name hasPrefix:@(row.tabs).stringValue]
        ? [NSString stringWithFormat:@"%ld %@", (long)row.tabs, row.name] : row.name;
    MMWindowDraw(MMWindowFit(name, 15, NSFontWeightSemibold, text, w - 44), x + 44, row.state.length ? 24 : 32, -1);
    if (row.state.length) MMWindowDraw(MMWindowFit(row.state, 12, NSFontWeightRegular, t2, w - 44), x + 44, 42, -1);

    // The numbers: memory or disk, CPU when known, and the row's own hour to the right.
    CGFloat top = 70, at = x;
    MMWindowDraw(MMWindowText(disk ? @"Disk" : @"Memory", 11.5, NSFontWeightRegular, t2), at, top + 7, -1);
    NSAttributedString *big = MMWindowNumber(row.bytes, 25, NSFontWeightMedium, text, 12);
    MMWindowDraw(big, at, top + 32, -1);
    at += MAX(MMWindowWidth(big), 60) + 24;
    if (row.cpuPercent >= 0) {
        MMWindowDraw(MMWindowText(@"CPU", 11.5, NSFontWeightRegular, t2), at, top + 7, -1);
        NSString *cpu = row.cpuPercent >= 99.5 ? [NSString stringWithFormat:@"%.0f", row.cpuPercent] : [NSString stringWithFormat:@"%.1f", row.cpuPercent];
        NSAttributedString *c = MMWindowJoin(@[MMWindowText(cpu, 25, NSFontWeightMedium, text), MMWindowText(@" %", 12, NSFontWeightRegular, t2)]);
        MMWindowDraw(c, at, top + 32, -1);
        at += MAX(MMWindowWidth(c), 50) + 24;
    }
    NSInteger a, b;
    if (row.hour && Ends(row.hour, &a, &b) && x + w - at >= 90) {
        NSColor *ink = MMWindowColor(disk ? MMWindowInkDisk : MMWindowInkMemory);
        MMWindowDraw(MMWindowText(@"Its last hour", 11.5, NSFontWeightRegular, t2), at, top + 7, -1);
        MMWindowDrawHour(row.hour, NSMakeRect(at, top + 18, x + w - at, 26), ink, 1.2, NO);
        MMWindowDraw(MMWindowFit([NSString stringWithFormat:@"%@, %@", Ago(a, (NSInteger)row.hour.count), MMWindowBytes([row.hour[a] unsignedLongLongValue])],
                                 10.5, NSFontWeightRegular, t3, x + w - at), at, top + 54, -1);
    }

    // The facts, labels in one column. A long value wraps and is never cut.
    [MMWindowColor(MMWindowInkLine) setFill];
    NSRectFillUsingOperation(NSMakeRect(x, top + 72, w, 1), NSCompositingOperationSourceOver);
    CGFloat y = top + 86, column = 0;
    for (MMWindowFact *f in row.facts) column = MAX(column, MMWindowWidth(MMWindowText(f.label, 12, NSFontWeightRegular, t2)));
    column = MIN(MAX(column + 18, 96), 150);
    NSMutableParagraphStyle *wrap = [NSMutableParagraphStyle new];
    wrap.lineBreakMode = NSLineBreakByWordWrapping;
    for (MMWindowFact *f in row.facts) {
        NSAttributedString *value = [[NSAttributedString alloc] initWithString:f.value ?: @"" attributes:@{
            NSFontAttributeName: MMWindowFont(12.5, NSFontWeightRegular), NSForegroundColorAttributeName: text, NSParagraphStyleAttributeName: wrap}];
        NSRect need = [value boundingRectWithSize:NSMakeSize(w - column, 400) options:NSStringDrawingUsesLineFragmentOrigin];
        CGFloat h = MAX(ceil(need.size.height), 16);
        if (y + h > self.bounds.size.height - 8) break;
        MMWindowDraw(MMWindowText(f.label, 12, NSFontWeightRegular, t2), x, y + 8, -1);
        [value drawWithRect:NSMakeRect(x + column, y, w - column, h) options:NSStringDrawingUsesLineFragmentOrigin];
        y += h + 9;
    }
}

@end
