// The window's colors, fonts and text drawing, from 195-a's computed styles. MMWindowParts.h says what each is for.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"
#import "UI/MMMenuKit.h"

const NSSize MMWindowSize = {1020, 728};

@implementation MMWindowFlipped
- (BOOL)isFlipped { return YES; }
@end

static BOOL gForceContrast;

void MMWindowForceContrast(BOOL on) { gForceContrast = on; }
BOOL MMWindowContrast(void) { return gForceContrast || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast; }
BOOL MMWindowReduceMotion(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

static NSColor *RGBA(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a];
}

NSColor *MMWindowColor(MMWindowInk ink) {
    BOOL hc = MMWindowContrast();
    switch (ink) {
        case MMWindowInkBase:   return hc ? RGBA(10, 10, 14, 1) : RGBA(31, 27, 46, 1);
        case MMWindowInkGlass:  return RGBA(36, 35, 46, hc ? 0.96 : 0.78);
        case MMWindowInkLine:   return RGBA(255, 255, 255, hc ? 0.34 : 0.10);
        case MMWindowInkText:   return RGBA(255, 255, 255, hc ? 1.0 : 0.92);
        case MMWindowInkText2:  return RGBA(235, 235, 245, hc ? 0.86 : 0.56);
        case MMWindowInkText3:  return RGBA(235, 235, 245, hc ? 0.72 : 0.44);
        case MMWindowInkHot:    return RGBA(11, 99, 216, 1);
        case MMWindowInkMemory: return RGBA(158, 194, 255, 1);
        case MMWindowInkDisk:   return RGBA(242, 196, 107, 1);
        case MMWindowInkFix:    return RGBA(255, 159, 69, 1);
        case MMWindowInkCard:   return RGBA(255, 255, 255, hc ? 0.07 : 0.035);
    }
    return NSColor.whiteColor;
}

NSColor *MMWindowGroupColor(NSString *key) {
    NSString *k = key.lowercaseString ?: @"";
    if ([k containsString:@"server"]) return RGBA(63, 208, 184, 1);
    if ([k containsString:@"agent"]) return RGBA(238, 133, 181, 1);
    if ([k containsString:@"app"] || [k containsString:@"helper"] || [k containsString:@"tab"]) return RGBA(91, 155, 255, 1);
    if ([k containsString:@"worktree"] || [k containsString:@"tree"]) return RGBA(76, 201, 107, 1);
    if ([k containsString:@"cache"] || [k containsString:@"leftover"]) return RGBA(242, 181, 68, 1);
    if ([k containsString:@"wrap"] || [k containsString:@"workstream"]) return RGBA(255, 138, 102, 1);
    return RGBA(170, 172, 190, 1);
}

NSFont *MMWindowFont(CGFloat size, NSFontWeight weight) {
    static NSMutableDictionary<NSNumber *, NSFont *> *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSNumber *key = @((NSInteger)(size * 10) * 1000 + (NSInteger)((weight + 1) * 100));
    NSFont *f = cache[key];
    if (f) return f;
    f = [NSFont systemFontOfSize:size weight:weight];
    // Tabular digits, so a number that ticks does not shift the text beside it.
    NSFontDescriptor *d = [f.fontDescriptor fontDescriptorByAddingAttributes:@{
        NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
                                            NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
    f = [NSFont fontWithDescriptor:d size:size] ?: f;
    cache[key] = f;
    return f;
}

NSAttributedString *MMWindowText(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{NSFontAttributeName: MMWindowFont(size, weight), NSForegroundColorAttributeName: color}];
}

NSAttributedString *MMWindowJoin(NSArray<NSAttributedString *> *runs) {
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    for (NSAttributedString *r in runs) [s appendAttributedString:r];
    return s;
}

CGFloat MMWindowWidth(NSAttributedString *line) { return ceil(line.size.width); }

// A thin space: 195-a sets a unit two or three points after its number, closer than a word.
NSString *const MMWindowThin = @"\u2009";

void MMWindowCrisp(void) { CGContextSetShouldSmoothFonts(NSGraphicsContext.currentContext.CGContext, false); }

static void (^gSeen)(NSString *, NSRect, NSRect, NSRect);

void MMWindowWatchDraws(void (^seen)(NSString *text, NSRect used, NSRect allowed, NSRect bounds)) { gSeen = [seen copy]; }

void MMWindowDraw(NSAttributedString *line, CGFloat x, CGFloat midY, NSInteger align) {
    MMWindowCrisp();
    NSSize s = line.size;
    CGFloat left = align < 0 ? x : align == 0 ? x - s.width / 2 : x - s.width;
    NSPoint at = NSMakePoint(round(left * 2) / 2, round((midY - s.height / 2) * 2) / 2);
    [line drawAtPoint:at];
    if (gSeen) gSeen(line.string, NSMakeRect(at.x, at.y, s.width, s.height), NSZeroRect, NSView.focusView.bounds);
}

CGFloat MMWindowDrawIn(NSAttributedString *text, NSRect rect) {
    MMWindowCrisp();
    CGFloat need = ceil([text boundingRectWithSize:NSMakeSize(rect.size.width, 100000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
    // Drawn at its full height: a rect too low would drop its last lines without a word.
    [text drawWithRect:NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, MAX(need, rect.size.height)) options:NSStringDrawingUsesLineFragmentOrigin];
    if (gSeen) gSeen(text.string, NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, need), rect, NSView.focusView.bounds);
    return need;
}

static CGFloat Wide(NSString *t, NSDictionary *at) { return ceil([t sizeWithAttributes:at].width); }

NSArray<NSString *> *MMWindowLines(NSString *text, CGFloat size, NSFontWeight weight, CGFloat width) {
    NSString *t = text ?: @"";
    NSDictionary *at = @{NSFontAttributeName: MMWindowFont(size, weight)};
    width = MAX(width, 12);
    if (Wide(t, at) <= width) return @[t];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    NSString *line = @"";
    for (NSString *word in [t componentsSeparatedByString:@" "]) {
        NSString *more = line.length ? [NSString stringWithFormat:@"%@ %@", line, word] : word;
        if (Wide(more, at) <= width) { line = more; continue; }
        if (line.length) { [lines addObject:line]; line = @""; }
        // A word wider than the line breaks between two characters, as many times as it must.
        NSString *rest = word;
        while (Wide(rest, at) > width) {
            __block NSUInteger cut = 0;
            [rest enumerateSubstringsInRange:NSMakeRange(0, rest.length) options:NSStringEnumerationByComposedCharacterSequences
                                  usingBlock:^(NSString *sub, NSRange r, NSRange enclosing, BOOL *stop) {
                if (Wide([rest substringToIndex:NSMaxRange(r)], at) > width) { *stop = YES; return; }
                cut = NSMaxRange(r);
            }];
            if (cut == 0) cut = [rest rangeOfComposedCharacterSequenceAtIndex:0].length;
            [lines addObject:[rest substringToIndex:cut]];
            rest = [rest substringFromIndex:cut];
        }
        line = rest;
    }
    if (line.length) [lines addObject:line];
    return lines;
}

CGFloat MMWindowLineHeight(CGFloat size) { return ceil(size * 1.3); }

CGFloat MMWindowFitSize(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, CGFloat width) {
    for (CGFloat s = size; s > floor; s -= 0.5) if (Wide(text ?: @"", @{NSFontAttributeName: MMWindowFont(s, weight)}) <= width) return s;
    return floor;
}

CGFloat MMWindowDrawBlock(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, NSColor *color, CGFloat x, CGFloat y, CGFloat width, NSInteger align, NSInteger anchor, CGFloat room) {
    MMWindowCrisp();
    CGFloat fit = MMWindowFitSize(text, size, floor, weight, width), line = MMWindowLineHeight(fit);
    NSArray<NSString *> *lines = MMWindowLines(text, fit, weight, width);
    CGFloat height = line * lines.count, top = anchor < 0 ? y : anchor == 0 ? y - height / 2 : y - height;
    // What the place allows: its room around the same anchor, or the block's own height when it may grow.
    CGFloat allowedHeight = room > 0 ? room : height, allowedTop = anchor < 0 ? y : anchor == 0 ? y - allowedHeight / 2 : y - allowedHeight;
    CGFloat left = align < 0 ? x : align == 0 ? x - width / 2 : x - width;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSAttributedString *a = MMWindowText(lines[i], fit, weight, color);
        NSSize s = a.size;
        CGFloat at = align < 0 ? x : align == 0 ? x - s.width / 2 : x - s.width, mid = top + line * i + line / 2;
        [a drawAtPoint:NSMakePoint(round(at * 2) / 2, round((mid - s.height / 2) * 2) / 2)];
        if (gSeen) gSeen(lines[i], NSMakeRect(at, top + line * i, s.width, line), NSMakeRect(left, allowedTop, width, allowedHeight), NSView.focusView.bounds);
    }
    return height;
}

CGFloat MMWindowBlockHeight(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, CGFloat width) {
    CGFloat fit = MMWindowFitSize(text, size, floor, weight, width);
    return MMWindowLineHeight(fit) * MMWindowLines(text, fit, weight, width).count;
}

NSArray<NSString *> *MMWindowSize2(uint64_t bytes, BOOL disk) { return MMWindowSizeParts(bytes, disk); }
NSString *MMWindowBytes(uint64_t bytes, BOOL disk) { return MMWindowSizeText(bytes, disk); }
NSString *MMWindowWhole(uint64_t bytes, BOOL disk) { return MMWindowWholeText(bytes, disk); }

NSString *MMWindowCPU(double percent) {
    if (percent < 0.05) return nil;
    return percent < 9.95 ? [NSString stringWithFormat:@"%.1f", percent] : [NSString stringWithFormat:@"%.0f", percent];
}

NSAttributedString *MMWindowNumber(uint64_t bytes, BOOL disk, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat unitSize) {
    NSArray<NSString *> *p = MMWindowSize2(bytes, disk);
    return MMWindowJoin(@[MMWindowText(p[0], size, weight, color),
                          MMWindowText([MMWindowThin stringByAppendingString:p[1]], unitSize, NSFontWeightRegular, MMWindowColor(MMWindowInkText2))]);
}

NSArray<NSNumber *> *MMWindowHourValues(NSArray *values, NSInteger *filled) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:values.count];
    NSInteger n = 0;
    for (id v in values) {
        BOOL ok = [v isKindOfClass:NSNumber.class];
        [out addObject:ok ? v : @(NAN)];
        n += ok;
    }
    if (filled) *filled = n;
    return out;
}

NSArray *MMWindowHourSpan(NSArray *values, NSInteger *first, NSInteger *last, NSInteger *filled) {
    NSInteger a = -1, b = -1, n = 0;
    for (NSInteger i = 0; i < (NSInteger)values.count; i++) {
        if (![values[i] isKindOfClass:NSNumber.class]) continue;
        if (a < 0) a = i;
        b = i; n++;
    }
    if (first) *first = a;
    if (last) *last = b;
    if (filled) *filled = n;
    return n >= MMWindowHourLeast ? [values subarrayWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))] : nil;
}

void MMWindowDrawHour(NSArray *values, NSRect rect, NSColor *color, MMWindowHourLook look) {
    BOOL graph = look == MMWindowHourGraph, small = look == MMWindowHourRow;
    // Only the filled part is drawn, across the whole width, so a young hour is a short line and never a stroke at the edge.
    NSArray *span = MMWindowHourSpan(values, NULL, NULL, NULL);
    if (!span) return;
    NSArray<NSNumber *> *v = MMWindowHourValues(span, NULL);
    double lo = INFINITY, hi = -INFINITY;
    for (NSNumber *n in v) { double d = n.doubleValue; if (isnan(d)) continue; lo = MIN(lo, d); hi = MAX(hi, d); }
    double span2 = hi - lo, top, bottom;
    if (graph) {
        // The line uses the height, with room above for the dot. A flat hour sits in the middle.
        double least = MAX(hi, 1) * 0.004;
        if (span2 < least) { double mid = (hi + lo) / 2; lo = mid - least * 1.5; hi = mid + least * 1.5; span2 = hi - lo; }
        top = NSMinY(rect) + 5; bottom = NSMaxY(rect) - rect.size.height * 0.14;
    } else {
        // A small line shows a wobble as flat: its scale is at least a quarter of its largest value.
        double wide = MAX(MAX(span2, hi * 0.25), 1), base = lo - (wide - span2) / 2 - wide * 0.08;
        lo = base; span2 = wide * 1.16;
        top = NSMinY(rect) + 1; bottom = NSMaxY(rect) - 1;
    }
    CGFloat left = NSMinX(rect) + 1, width = rect.size.width - (graph ? 4 : 2.6);
    NSBezierPath *line = [NSBezierPath bezierPath], *fill = [NSBezierPath bezierPath];
    NSPoint last = NSZeroPoint, first = NSZeroPoint;
    BOOL open = NO, any = NO;
    NSInteger count = (NSInteger)v.count;
    for (NSInteger i = 0; i < count; i++) {
        double d = v[i].doubleValue;
        if (isnan(d)) { if (open) { [fill lineToPoint:NSMakePoint(last.x, NSMaxY(rect))]; [fill lineToPoint:NSMakePoint(first.x, NSMaxY(rect))]; [fill closePath]; open = NO; } continue; }
        NSPoint p = NSMakePoint(left + width * i / MAX(count - 1, 1), bottom - (bottom - top) * (d - lo) / span2);
        if (!open) { [line moveToPoint:p]; [fill moveToPoint:p]; first = p; open = YES; }
        else { [line lineToPoint:p]; [fill lineToPoint:p]; }
        last = p; any = YES;
    }
    if (open) { [fill lineToPoint:NSMakePoint(last.x, NSMaxY(rect))]; [fill lineToPoint:NSMakePoint(first.x, NSMaxY(rect))]; [fill closePath]; }
    if (!any) return;
    [[color colorWithAlphaComponent:color.alphaComponent * (MMWindowContrast() ? 0.26 : graph ? 0.15 : 0.18)] setFill];
    [fill fill];
    line.lineWidth = small ? 1.2 : 1.5; line.lineJoinStyle = NSLineJoinStyleRound; line.lineCapStyle = NSLineCapStyleRound;
    [color setStroke];
    [line stroke];
    CGFloat dot = graph ? 2.4 : 1.6;
    [color setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(last.x - dot, last.y - dot, dot * 2, dot * 2)] fill];
}
