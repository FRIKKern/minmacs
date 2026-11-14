// One row of a list: where each of its parts stands, how its name fits, its second line, and its drawing.
// A name is never cut and never ends on an ellipsis. It first takes the room of what matters less, a column with
// nothing to show, the state word, then the row's own hour, then CPU, and a name still too long wraps: the row grows
// by a line for each. The parts are placed once, from the right, and drawn where they were placed.
#import "UI/Window/MMWindowParts.h"

const CGFloat MMWindowNameLine = 16;

/// How wide a word is in the row's type, measured with the real font and kept: a list measures every name at every
/// model, and most names stay. No width is guessed from a count of letters: a name of few wide letters, Japanese ones
/// or capital W, is wider than many narrow ones.
static CGFloat Wide(NSString *text, CGFloat size) {
    static NSMutableDictionary<NSString *, NSNumber *> *kept[2];
    int which = size == 13 ? 0 : 1;
    if (!kept[which]) kept[which] = [NSMutableDictionary new];
    NSNumber *w = kept[which][text];
    if (w) return w.doubleValue;
    if (kept[which].count > 4000) [kept[which] removeAllObjects];
    CGFloat width = MMWindowWidth(MMWindowText(text, size, NSFontWeightRegular, NSColor.whiteColor));
    kept[which][text] = @(width);
    return width;
}

// The columns right of a name, from the right: the row's own hour, CPU and the state word, after the size.
enum { kHour, kCPU, kState, kColumns };

/// Where the name ends with the columns that are held.
static CGFloat NameEdge(CGFloat start, const CGFloat *width, const BOOL *held) {
    for (int i = 0; i < kColumns; i++) if (held[i]) start -= width[i];
    return start;
}

NSArray<NSString *> *MMWindowRowName(MMWindowRow *row, MMWindowSide side, BOOL hasHour, NSRect rect, MMWindowRowColumns *columns) {
    NSString *name = row.shownName;
    BOOL disk = side == MMWindowDisk;
    CGFloat nameLeft = NSMinX(rect) + 31, right = NSMaxX(rect) - 9, sizeWidth = disk ? 58 : 50, start = right - sizeWidth - 6, y = rect.origin.y, h = rect.size.height;
    // A column is there where its group has it: the hour where any row of the group has one, CPU on the memory side.
    // So the hour lines and the CPU numbers of a group stand one under another.
    CGFloat width[kColumns] = {hasHour ? 40 : 0, disk ? 0 : 46, row.state.length ? Wide(row.state, 11.5) + 8 : 0};
    BOOL shows[kColumns] = {MMWindowHourSpan(row.hour, NULL, NULL, NULL) != nil, MMWindowCPU(row.cpuPercent) != nil, row.state.length > 0};
    BOOL held[kColumns];
    for (int i = 0; i < kColumns; i++) held[i] = width[i] > 0;
    CGFloat need = Wide(name, 13);
    // A name too long for what is left first takes a column with nothing to show in this row, then the state word,
    // then the row's own hour, then CPU. Whatever goes, what stands left of it moves right into its place.
    if (NameEdge(start, width, held) - nameLeft < need) for (int i = 0; i < kColumns; i++) if (!shows[i]) held[i] = NO;
    const int order[kColumns] = {kState, kHour, kCPU};
    for (int k = 0; k < kColumns && NameEdge(start, width, held) - nameLeft < need; k++) held[order[k]] = NO;

    MMWindowRowColumns c = {NSMakeRect(right - sizeWidth, y, sizeWidth, h), NSZeroRect, NSZeroRect, NSZeroRect, NSZeroRect, 1};
    CGFloat x = start;
    if (held[kHour]) { c.hour = NSMakeRect(x - 34, y, 34, h); x -= width[kHour]; }
    if (held[kCPU]) { c.cpu = NSMakeRect(x - width[kCPU], y, width[kCPU], h); x -= width[kCPU]; }
    if (held[kState]) { c.state = NSMakeRect(x - width[kState] + 8, y, width[kState] - 8, h); x -= width[kState]; }
    c.name = NSMakeRect(nameLeft, y, x - nameLeft, h);
    NSArray<NSString *> *lines = x - nameLeft >= need ? @[name] : MMWindowLines(name, 13, NSFontWeightRegular, x - nameLeft);
    c.lines = (NSInteger)lines.count;
    if (columns) *columns = c;
    return lines;
}

NSString *MMWindowRowSecondLine(MMWindowRow *row, CGFloat width) {
    NSDictionary *at = @{NSFontAttributeName: MMWindowFont(11, NSFontWeightRegular)};
    BOOL byWhy = row.kind == MMWindowCache || row.kind == MMWindowApp || row.kind == MMWindowHelper || row.kind == MMWindowTabs;
    NSString *note = row.fate.note;
    if (byWhy && note.length) {
        NSString *plain = [note hasSuffix:@"."] ? [note substringToIndex:note.length - 1] : note;
        if (ceil([plain sizeWithAttributes:at].width) <= width) return plain;
    }
    // Each fact as the phrase a person would say, whole: one that does not fit is left out, never cut.
    NSString *line = nil;
    NSInteger held = 0;
    for (MMWindowFact *f in row.storyFacts) {
        if (!f.phrase.length || [row.name rangeOfString:f.value options:NSCaseInsensitiveSearch].location != NSNotFound) continue;
        NSString *more = line ? [NSString stringWithFormat:@"%@ · %@", line, f.phrase] : f.phrase;
        if (ceil([more sizeWithAttributes:at].width) > width) continue;
        line = more;
        if (++held == 2) break;
    }
    // A line starts with a capital, as a sentence would.
    return line.length ? [[line substringToIndex:1].localizedUppercaseString stringByAppendingString:[line substringFromIndex:1]] : nil;
}

void MMWindowDrawRow(MMWindowRow *row, NSRect r, MMWindowSide side, BOOL hasHour, BOOL hot, BOOL tall) {
    // Nothing going on in it, no fix touches it and it asks nothing: its name steps back, so the busy rows lead.
    BOOL calm = row.quiet && !row.inFix && !row.needsYou && !hot, disk = side == MMWindowDisk;
    MMWindowRowColumns col;
    NSArray<NSString *> *name = MMWindowRowName(row, side, hasHour, r, &col);
    CGFloat nameLeft = NSMinX(col.name);
    NSString *second = tall ? MMWindowRowSecondLine(row, NSMaxX(col.size) - nameLeft) : nil;
    // The name's first line stands where a one-line row has it. More lines and the second line follow under it.
    CGFloat block = MMWindowNameLine * col.lines + (second ? 15 : 0), mid = NSMidY(r) - block / 2 + MMWindowNameLine / 2 + (second ? 1.5 : 0);
    NSColor *text = hot ? NSColor.whiteColor : MMWindowColor(MMWindowInkText);
    NSColor *quiet = hot ? [NSColor colorWithWhite:1 alpha:0.84] : MMWindowColor(MMWindowInkText2);
    NSColor *nameInk = calm ? [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.62] : text;
    if (hot) {
        [MMWindowColor(MMWindowInkHot) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
    }
    MMWindowDrawIcon(row, NSMakeRect(r.origin.x + 9, (col.lines > 1 ? mid : NSMidY(r)) - 8, 16, 16), hot ? MMWindowColor(MMWindowInkHot) : [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1]);

    // Each part in its own column, as MMWindowRowName placed them: the number with its gray unit, the row's own hour,
    // CPU, the quiet state word, and the name in the rest. A tabs row with no bytes has its count in its name, and no size.
    if (row.showsSize) {
        NSArray<NSString *> *size = MMWindowSize2(row.bytes, disk);
        MMWindowDraw(MMWindowJoin(@[MMWindowText(size[0], 13, NSFontWeightRegular, text),
                                    MMWindowText([MMWindowThin stringByAppendingString:size[1]], 11, NSFontWeightRegular, quiet)]), NSMaxX(col.size), mid, 1);
    }
    if (!NSIsEmptyRect(col.hour)) {
        NSColor *ink = hot ? NSColor.whiteColor : MMWindowColor(disk ? MMWindowInkDisk : MMWindowInkMemory);
        MMWindowDrawHour(row.hour, NSMakeRect(NSMinX(col.hour), mid - 7, NSWidth(col.hour), 14), calm ? [ink colorWithAlphaComponent:0.62] : ink, MMWindowHourRow);
    }
    NSString *cpu = NSIsEmptyRect(col.cpu) ? nil : MMWindowCPU(row.cpuPercent);
    if (cpu) {
        // From 3 % of a core on, the number is as bright as the name.
        NSColor *ink = row.cpuPercent >= 3 ? text : quiet;
        MMWindowDraw(MMWindowJoin(@[MMWindowText(cpu, 12, NSFontWeightRegular, ink), MMWindowText([MMWindowThin stringByAppendingString:@"%"], 11, NSFontWeightRegular, quiet)]), NSMaxX(col.cpu), mid, 1);
    }
    if (!NSIsEmptyRect(col.state)) MMWindowDraw(MMWindowText(row.state, 11.5, NSFontWeightRegular, quiet), NSMaxX(col.state), mid, 1);
    for (NSInteger i = 0; i < col.lines; i++) MMWindowDraw(MMWindowText(name[(NSUInteger)i], 13, NSFontWeightRegular, nameInk), nameLeft, mid + MMWindowNameLine * i, -1);
    if (second) MMWindowDraw(MMWindowText(second, 11, NSFontWeightRegular, hot ? [NSColor colorWithWhite:1 alpha:0.78] : MMWindowColor(MMWindowInkText3)),
                             nameLeft, mid + MMWindowNameLine * (col.lines - 1) + 15.5, -1);
}
