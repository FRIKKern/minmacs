// One row of a list: what stands beside its name, how its name fits, its second line, and its drawing.
// A name is never cut and never ends on an ellipsis. It first takes the room of what matters less, the state word,
// then the row's own hour, then CPU, and a name still too long wraps: the row grows by a line for each.
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

NSArray<NSString *> *MMWindowRowName(MMWindowRow *row, MMWindowSide side, BOOL hasHour, CGFloat nameLeft, CGFloat right, MMWindowRowFit *fit) {
    NSString *name = row.shownName;
    BOOL hour = hasHour && MMWindowHourSpan(row.hour, NULL, NULL, NULL) != nil, cpu = side == MMWindowMemory && MMWindowCPU(row.cpuPercent) != nil;
    CGFloat afterSize = right - (side == MMWindowDisk ? 58 : 50) - 6;
    CGFloat hourWidth = hasHour ? 40 : 0, cpuWidth = side == MMWindowMemory ? 46 : 0;
    MMWindowRowFit f = {NO, cpu, hour, afterSize - hourWidth - cpuWidth, 1};
    CGFloat need = Wide(name, 13), stateWidth = row.state.length ? Wide(row.state, 11.5) + 8 : 0;
    if (stateWidth > 0 && f.edge - stateWidth - nameLeft >= need) { f.state = YES; f.edge -= stateWidth; }
    else if (f.edge - nameLeft >= need) {}
    else if (afterSize - cpuWidth - nameLeft >= need) { f.hour = NO; f.edge = afterSize - cpuWidth; }
    else { f.hour = NO; f.cpu = NO; f.edge = afterSize; }
    NSArray<NSString *> *lines = f.edge - nameLeft >= need ? @[name] : MMWindowLines(name, 13, NSFontWeightRegular, f.edge - nameLeft);
    f.lines = (NSInteger)lines.count;
    if (fit) *fit = f;
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
    CGFloat right = NSMaxX(r) - 9, nameLeft = r.origin.x + 31;
    MMWindowRowFit fit;
    NSArray<NSString *> *name = MMWindowRowName(row, side, hasHour, nameLeft, right, &fit);
    NSString *second = tall ? MMWindowRowSecondLine(row, right - nameLeft) : nil;
    // The name's first line stands where a one-line row has it. More lines and the second line follow under it.
    CGFloat block = MMWindowNameLine * fit.lines + (second ? 15 : 0), mid = NSMidY(r) - block / 2 + MMWindowNameLine / 2 + (second ? 1.5 : 0);
    NSColor *text = hot ? NSColor.whiteColor : MMWindowColor(MMWindowInkText);
    NSColor *quiet = hot ? [NSColor colorWithWhite:1 alpha:0.84] : MMWindowColor(MMWindowInkText2);
    NSColor *nameInk = calm ? [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.62] : text;
    if (hot) {
        [MMWindowColor(MMWindowInkHot) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
    }
    MMWindowDrawIcon(row, NSMakeRect(r.origin.x + 9, (fit.lines > 1 ? mid : NSMidY(r)) - 8, 16, 16), hot ? MMWindowColor(MMWindowInkHot) : [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1]);

    // From the right: the number with its gray unit, the row's own hour, CPU, the quiet state word. The name gets the rest.
    // A tabs row with no bytes has its count in its name, and no size.
    if (row.showsSize) {
        NSArray<NSString *> *size = MMWindowSize2(row.bytes, disk);
        MMWindowDraw(MMWindowJoin(@[MMWindowText(size[0], 13, NSFontWeightRegular, text),
                                    MMWindowText([MMWindowThin stringByAppendingString:size[1]], 11, NSFontWeightRegular, quiet)]), right, mid, 1);
    }
    CGFloat edge = right - (disk ? 58 : 50) - 6;
    if (hasHour) {
        NSColor *ink = hot ? NSColor.whiteColor : MMWindowColor(disk ? MMWindowInkDisk : MMWindowInkMemory);
        if (fit.hour) MMWindowDrawHour(row.hour, NSMakeRect(edge - 34, mid - 7, 34, 14), calm ? [ink colorWithAlphaComponent:0.62] : ink, MMWindowHourRow);
        edge -= 40;
    }
    NSString *cpu = fit.cpu ? MMWindowCPU(row.cpuPercent) : nil;
    if (cpu) {
        // From 3 % of a core on, the number is as bright as the name.
        NSColor *ink = row.cpuPercent >= 3 ? text : quiet;
        MMWindowDraw(MMWindowJoin(@[MMWindowText(cpu, 12, NSFontWeightRegular, ink), MMWindowText([MMWindowThin stringByAppendingString:@"%"], 11, NSFontWeightRegular, quiet)]), edge, mid, 1);
    }
    if (fit.state) MMWindowDraw(MMWindowText(row.state, 11.5, NSFontWeightRegular, quiet), edge - (side == MMWindowMemory ? 46 : 0), mid, 1);
    for (NSInteger i = 0; i < fit.lines; i++) MMWindowDraw(MMWindowText(name[(NSUInteger)i], 13, NSFontWeightRegular, nameInk), nameLeft, mid + MMWindowNameLine * i, -1);
    if (second) MMWindowDraw(MMWindowText(second, 11, NSFontWeightRegular, hot ? [NSColor colorWithWhite:1 alpha:0.78] : MMWindowColor(MMWindowInkText3)),
                             nameLeft, mid + MMWindowNameLine * (fit.lines - 1) + 15.5, -1);
}
