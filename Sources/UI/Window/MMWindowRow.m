// One row of a list: what stands beside its name, how its name fits, its second line, and its drawing.
// A name is never cut and never ends on an ellipsis. It first takes the room of what matters less, the state word,
// then the row's own hour, then CPU, and a name still too long wraps: the row grows by a line for each.
#import "UI/Window/MMWindowParts.h"

const CGFloat MMWindowNameLine = 16;

NSArray<NSString *> *MMWindowRowName(MMWindowRow *row, MMWindowSide side, BOOL hasHour, CGFloat nameLeft, CGFloat right, MMWindowRowFit *fit) {
    NSString *name = row.shownName;
    BOOL hour = hasHour && MMWindowHourSpan(row.hour, NULL, NULL, NULL) != nil, cpu = side == MMWindowMemory && MMWindowCPU(row.cpuPercent) != nil;
    CGFloat afterSize = right - (side == MMWindowDisk ? 58 : 50) - 6;
    CGFloat hourWidth = hasHour ? 40 : 0, cpuWidth = side == MMWindowMemory ? 46 : 0;
    MMWindowRowFit f = {NO, cpu, hour, afterSize - hourWidth - cpuWidth, 1};
    // A short name fits beside everything. Only a long one is measured.
    if (name.length >= 12) {
        CGFloat need = MMWindowWidth(MMWindowText(name, 13, NSFontWeightRegular, NSColor.whiteColor));
        CGFloat stateWidth = row.state.length ? MMWindowWidth(MMWindowText(row.state, 11.5, NSFontWeightRegular, NSColor.whiteColor)) + 8 : 0;
        if (stateWidth > 0 && f.edge - stateWidth - nameLeft >= need) { f.state = YES; f.edge -= stateWidth; }
        else if (f.edge - nameLeft >= need) {}
        else if (afterSize - cpuWidth - nameLeft >= need) { f.hour = NO; f.edge = afterSize - cpuWidth; }
        else { f.hour = NO; f.cpu = NO; f.edge = afterSize; }
    } else if (row.state.length) {
        CGFloat stateWidth = MMWindowWidth(MMWindowText(row.state, 11.5, NSFontWeightRegular, NSColor.whiteColor)) + 8;
        if (f.edge - stateWidth - nameLeft >= name.length * 11.0 || f.edge - stateWidth - nameLeft >= MMWindowWidth(MMWindowText(name, 13, NSFontWeightRegular, NSColor.whiteColor))) {
            f.state = YES; f.edge -= stateWidth;
        }
    }
    NSArray<NSString *> *lines = f.edge - nameLeft >= name.length * 11.0 ? @[name] : MMWindowLines(name, 13, NSFontWeightRegular, f.edge - nameLeft);
    f.lines = (NSInteger)lines.count;
    if (fit) *fit = f;
    return lines;
}

/// A path as its last folders, as many whole ones as fit, or nil when not even the last one does.
static NSString *Tail(NSString *path, NSString *label, NSDictionary *at, CGFloat width) {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    NSString *best = nil;
    for (NSInteger from = (NSInteger)parts.count - 1; from >= 0; from--) {
        NSString *tail = [[parts subarrayWithRange:NSMakeRange((NSUInteger)from, parts.count - (NSUInteger)from)] componentsJoinedByString:@"/"];
        if (!tail.length) continue;
        if (ceil([[NSString stringWithFormat:@"%@ %@", label, tail] sizeWithAttributes:at].width) > width) break;
        best = tail;
    }
    return best;
}

NSString *MMWindowRowSecondLine(MMWindowRow *row, CGFloat width) {
    NSDictionary *at = @{NSFontAttributeName: MMWindowFont(11, NSFontWeightRegular)};
    BOOL byWhy = row.kind == MMWindowCache || row.kind == MMWindowApp || row.kind == MMWindowHelper || row.kind == MMWindowTabs;
    NSString *note = row.fate.note;
    if (byWhy && note.length) {
        NSString *plain = [note hasSuffix:@"."] ? [note substringToIndex:note.length - 1] : note;
        if (ceil([plain sizeWithAttributes:at].width) <= width) return plain;
    }
    // Whole facts only: a fact that does not fit is left out, and a path shows its last folders.
    NSString *line = nil;
    NSInteger held = 0;
    for (MMWindowFact *f in row.storyFacts) {
        if (!f.value.length || [row.name rangeOfString:f.value options:NSCaseInsensitiveSearch].location != NSNotFound) continue;
        NSString *lead = line ? [line stringByAppendingString:@" · "] : @"";
        CGFloat room = width - ceil([lead sizeWithAttributes:at].width);
        NSString *whole = [NSString stringWithFormat:@"%@ %@", f.label, f.value], *part = nil;
        if (ceil([whole sizeWithAttributes:at].width) <= room) part = whole;
        else if ([f.value containsString:@"/"]) { NSString *tail = Tail(f.value, f.label, at, room); if (tail) part = [NSString stringWithFormat:@"%@ %@", f.label, tail]; }
        if (!part) continue;
        line = [lead stringByAppendingString:part];
        if (++held == 2) break;
    }
    return line;
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
