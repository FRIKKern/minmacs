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

void MMWindowDraw(NSAttributedString *line, CGFloat x, CGFloat midY, NSInteger align) {
    NSSize s = line.size;
    CGFloat left = align < 0 ? x : align == 0 ? x - s.width / 2 : x - s.width;
    [line drawAtPoint:NSMakePoint(round(left * 2) / 2, round((midY - s.height / 2) * 2) / 2)];
}

NSAttributedString *MMWindowFit(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat width) {
    NSFont *f = MMWindowFont(size, weight);
    return MMWindowText(MMFitWidth(text ?: @"", f, MAX(width, 10)), size, weight, color);
}

NSArray<NSString *> *MMWindowSize2(uint64_t bytes) {
    NSArray<NSString *> *p = [MMBytes(bytes) componentsSeparatedByString:@" "];
    NSString *n = p.firstObject ?: @"0";
    // "64.0" reads as "64": a round size has no decimal to show.
    if ([n hasSuffix:@".0"]) n = [n substringToIndex:n.length - 2];
    return @[n, p.count > 1 ? p[1] : @""];
}

NSString *MMWindowBytes(uint64_t bytes) { return [MMWindowSize2(bytes) componentsJoinedByString:@" "]; }

NSAttributedString *MMWindowNumber(uint64_t bytes, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat unitSize) {
    NSArray<NSString *> *p = MMWindowSize2(bytes);
    return MMWindowJoin(@[MMWindowText(p[0], size, weight, color),
                          MMWindowText([@" " stringByAppendingString:p[1]], unitSize, NSFontWeightRegular, MMWindowColor(MMWindowInkText2))]);
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

void MMWindowDrawHour(NSArray *values, NSRect rect, NSColor *color, CGFloat lineWidth, BOOL dot) {
    NSInteger filled = 0;
    NSArray<NSNumber *> *v = MMWindowHourValues(values, &filled);
    if (filled < 2) return;
    double lo = INFINITY, hi = -INFINITY;
    for (NSNumber *n in v) { double d = n.doubleValue; if (isnan(d)) continue; lo = MIN(lo, d); hi = MAX(hi, d); }
    // A flat hour sits in the middle. Otherwise the line uses the height, with room above for the dot.
    double span = hi - lo, pad = dot ? 5 : 1.5;
    double least = MAX(hi, 1) * (dot ? 0.004 : 0.06);   // a row's small line shows a wobble as flat; the large graph shows it
    if (span < least) { double mid = (hi + lo) / 2; span = least; lo = mid - span * 1.5; hi = mid + span * 1.5; span = hi - lo; }
    CGFloat usable = rect.size.height - pad - (dot ? rect.size.height * 0.14 : 1.5);
    NSBezierPath *line = [NSBezierPath bezierPath], *fill = [NSBezierPath bezierPath];
    NSPoint last = NSZeroPoint, first = NSZeroPoint;
    BOOL open = NO, any = NO;
    NSInteger count = (NSInteger)v.count;
    for (NSInteger i = 0; i < count; i++) {
        double d = v[i].doubleValue;
        if (isnan(d)) { if (open) { [fill lineToPoint:NSMakePoint(last.x, NSMaxY(rect))]; [fill lineToPoint:NSMakePoint(first.x, NSMaxY(rect))]; [fill closePath]; open = NO; } continue; }
        NSPoint p = NSMakePoint(NSMinX(rect) + 1 + (rect.size.width - 4) * i / MAX(count - 1, 1), NSMinY(rect) + pad + usable * (1 - (d - lo) / span));
        if (!open) { [line moveToPoint:p]; [fill moveToPoint:p]; first = p; open = YES; }
        else { [line lineToPoint:p]; [fill lineToPoint:p]; }
        last = p; any = YES;
    }
    if (open) { [fill lineToPoint:NSMakePoint(last.x, NSMaxY(rect))]; [fill lineToPoint:NSMakePoint(first.x, NSMaxY(rect))]; [fill closePath]; }
    if (!any) return;
    [[color colorWithAlphaComponent:MMWindowContrast() ? 0.26 : 0.15] setFill];
    [fill fill];
    line.lineWidth = lineWidth; line.lineJoinStyle = NSLineJoinStyleRound; line.lineCapStyle = NSLineCapStyleRound;
    [color setStroke];
    [line stroke];
    if (dot) { [color setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(last.x - 2.4, last.y - 2.4, 4.8, 4.8)] fill]; }
}
