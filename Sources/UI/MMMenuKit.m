#import "MMMenuKit.h"
#import "MMFormat.h"

// LocoHost used 330 and 50, WorkForest 340 and 62. One value now, wide enough for both.
const CGFloat MMMenuWidth = 360;
const CGFloat MMMenuInset = 14;
const CGFloat MMLabelColumn = 64;

static const CGFloat kTextSize = 12.5;

#pragma mark Marks

NSString *MMMarkGlyph(MMMark m) {
    switch (m) {
        case MMMarkWorking: return @"●";
        case MMMarkRecent:  return @"◐";
        case MMMarkQuiet:   return @"○";
        case MMMarkGoes:    return @"◇";
        case MMMarkBlocked: return @"◆";
        case MMMarkUnknown: return @"◌";
        case MMMarkNone:    return @"";
    }
    return @"";
}

/// A system color in dark appearances, and a darker shade of it in light ones.
/// The plain system green, yellow and orange read at about 2 to 1 on a light menu, too faint for a bold word.
static NSColor *Readable(NSColor *system, CGFloat r, CGFloat g, CGFloat b) {
    NSColor *light = [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
        // An appearance loaded from the system bundle, as the render tool does, can match Aqua or nothing
        // while its own name says DarkAqua, so either one saying Dark is enough.
        NSString *m = [a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua,
            NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua]] ?: @"";
        return [m containsString:@"Dark"] || [a.name containsString:@"Dark"] ? system : light;
    }];
}

NSColor *MMMarkColor(MMMark m) {
    static NSColor *green, *yellow, *orange;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        green = Readable(NSColor.systemGreenColor, 0.11, 0.52, 0.21);
        yellow = Readable(NSColor.systemYellowColor, 0.62, 0.45, 0.0);
        orange = Readable(NSColor.systemOrangeColor, 0.78, 0.36, 0.0);
    });
    switch (m) {
        case MMMarkWorking: return green;
        case MMMarkRecent:  return yellow;
        case MMMarkGoes:    return orange;
        case MMMarkBlocked: return NSColor.systemRedColor;
        case MMMarkQuiet: case MMMarkUnknown: case MMMarkNone: return NSColor.secondaryLabelColor;
    }
    return NSColor.secondaryLabelColor;
}

NSString *MMMarkWord(MMMark m) {
    switch (m) {
        case MMMarkWorking: return @"in use";
        case MMMarkRecent:  return @"used recently";
        case MMMarkQuiet:   return @"quiet";
        case MMMarkGoes:    return @"goes next";
        case MMMarkBlocked: return @"waits on you";
        case MMMarkUnknown: return @"not known yet";
        case MMMarkNone:    return @"";
    }
    return @"";
}

#pragma mark Text

CGFloat MMLinesHeight(NSFont *font, NSInteger lines) {
    return ceil(lines * (font.ascender - font.descender + font.leading) + 1);
}

NSTextField *MMParaRich(NSAttributedString *text, CGFloat width, NSInteger lines) {
    NSTextField *t = [NSTextField wrappingLabelWithString:@""];
    t.attributedStringValue = text ?: [NSAttributedString new];
    t.preferredMaxLayoutWidth = width;
    t.maximumNumberOfLines = lines; t.cell.truncatesLastVisibleLine = YES; t.lineBreakMode = NSLineBreakByWordWrapping;
    CGFloat h = [t.cell cellSizeForBounds:NSMakeRect(0, 0, width, 4000)].height;
    if (lines > 0) {
        // The tallest font in the text sets the line height, so a bold head does not cut the last line.
        __block NSFont *tallest = [NSFont systemFontOfSize:kTextSize];
        [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(NSFont *f, NSRange r, BOOL *stop) {
            if (f && f.ascender - f.descender > tallest.ascender - tallest.descender) tallest = f;
        }];
        h = MIN(h, MMLinesHeight(tallest, lines));
    }
    [t.widthAnchor constraintEqualToConstant:width].active = YES; [t.heightAnchor constraintEqualToConstant:h].active = YES;
    t.frame = NSMakeRect(0, 0, width, h);
    return t;
}

NSTextField *MMPara(NSString *text, NSFont *font, NSColor *color, CGFloat width, NSInteger lines) {
    return MMParaRich([[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color}], width, lines);
}

NSAttributedString *MMRich(NSString *bold, NSColor *boldColor, NSString *rest, CGFloat size) {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:bold ?: @"" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:NSFontWeightSemibold], NSForegroundColorAttributeName: boldColor}];
    if (rest.length) [a appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:rest] attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:size], NSForegroundColorAttributeName: NSColor.labelColor}]];
    return a;
}

NSAttributedString *MMTitled(NSString *title, NSString *tail) {
    NSFont *f = [NSFont menuFontOfSize:0];
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:title ?: @"" attributes:@{NSFontAttributeName: f}];
    if (tail.length) [t appendAttributedString:[[NSAttributedString alloc] initWithString:title.length ? [@"   " stringByAppendingString:tail] : tail
                                                                              attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
    return t;
}

NSString *MMFitSentences(NSString *text, NSFont *font, CGFloat width, NSInteger lines) {
    if (!text.length) return @"";
    NSMutableArray *parts = [NSMutableArray new];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationBySentences usingBlock:^(NSString *sub, NSRange r, NSRange er, BOOL *stop) {
        [parts addObject:[text substringWithRange:er]];
    }];
    CGFloat limit = MMLinesHeight(font, lines);
    NSMutableString *out = [NSMutableString new];
    for (NSString *p in parts) {
        NSString *next = [[out stringByAppendingString:p] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        CGFloat h = [next boundingRectWithSize:NSMakeSize(width, 4000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: font}].size.height;
        if (h > limit && out.length) break;
        [out appendString:p];
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *MMFitWidth(NSString *text, NSFont *font, CGFloat width) {
    NSDictionary *a = @{NSFontAttributeName: font};
    if (!text.length || [text sizeWithAttributes:a].width <= width) return text ?: @"";
    NSUInteger lo = 1, hi = text.length;
    while (lo < hi) {   // the longest cut that still fits
        NSUInteger mid = (lo + hi + 1) / 2;
        if ([MMCut(text, mid) sizeWithAttributes:a].width <= width) lo = mid; else hi = mid - 1;
    }
    return MMCut(text, lo);
}

#pragma mark Menu items

/// macOS 26 and later give an item a symbol from its action, made the first time the image is read.
/// Reading it once and then setting nil keeps the item plain through title and key changes.
/// Setting a known action such as copy: afterwards brings the symbol back, so MMRemoveSymbols runs last.
static NSMenuItem *Plain(NSMenuItem *i) { (void)i.image; i.image = nil; return i; }

NSMenuItem *MMHeaderItem(NSString *big, NSString *unit, NSString *side, NSString *line) {
    CGFloat w = MMMenuWidth, in = MMMenuInset;
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, 62)];
    NSMutableAttributedString *top = [[NSMutableAttributedString alloc] initWithString:big ?: @"" attributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: NSColor.labelColor}];
    if (unit.length) [top appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:unit] attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
    CGFloat sideWidth = 0;
    if (side.length) {
        NSTextField *s = [NSTextField labelWithString:side];
        s.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium]; s.textColor = NSColor.secondaryLabelColor;
        s.alignment = NSTextAlignmentRight; [s sizeToFit];
        sideWidth = s.frame.size.width + 8;
        s.frame = NSMakeRect(w - in - s.frame.size.width, 30, s.frame.size.width, 16); [v addSubview:s];
    }
    NSTextField *n = [NSTextField labelWithAttributedString:top];
    n.lineBreakMode = NSLineBreakByTruncatingTail;
    n.frame = NSMakeRect(in, 24, w - 2 * in - sideWidth, 28); [v addSubview:n];
    NSTextField *l = [NSTextField labelWithString:line ?: @""];
    l.font = [NSFont systemFontOfSize:12]; l.textColor = NSColor.secondaryLabelColor; l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.frame = NSMakeRect(in, 8, w - 2 * in, 15); [v addSubview:l];
    NSMutableArray *said = [NSMutableArray new];
    for (NSString *x in @[big ?: @"", unit ?: @"", side ?: @"", line ?: @""]) if (x.length) [said addObject:x];
    v.accessibilityLabel = [said componentsJoinedByString:@", "];
    NSMenuItem *i = [NSMenuItem new]; i.view = v;
    return i;
}

NSMenuItem *MMTextItem(NSString *text, NSInteger lines) {
    CGFloat w = MMMenuWidth - 2 * MMMenuInset;
    NSFont *f = [NSFont systemFontOfSize:kTextSize];
    NSString *fit = lines > 0 ? MMFitSentences(text, f, w, lines) : text;
    NSTextField *t = MMPara(fit, f, NSColor.secondaryLabelColor, w, lines);
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MMMenuWidth, t.frame.size.height + 10)];
    t.frame = NSMakeRect(MMMenuInset, 5, w, t.frame.size.height); [box addSubview:t];
    NSMenuItem *i = [NSMenuItem new]; i.view = box;
    return i;
}

NSMenuItem *MMSectionItem(NSString *title) { return [NSMenuItem sectionHeaderWithTitle:title ?: @""]; }

/// Empty facts left out, at most three.
static NSString *Facts(NSArray<NSString *> *facts) {
    NSMutableArray *f = [NSMutableArray new];
    for (NSString *s in facts) if ([s isKindOfClass:NSString.class] && s.length && f.count < MMMaxRowFacts) [f addObject:s];
    return [f componentsJoinedByString:@" · "];
}

NSMenuItem *MMRowItem(NSString *name, NSString *tag, NSArray<NSString *> *facts, MMMark mark) {
    NSFont *f = [NSFont menuFontOfSize:0];
    NSString *tail = tag.length ? [@"   " stringByAppendingString:tag] : @"";
    // The menu's state column and the submenu arrow take about 52 points, the mark column 18.
    CGFloat room = MMMenuWidth - 52 - (mark != MMMarkNone ? 18 : 0) - [tail sizeWithAttributes:@{NSFontAttributeName: f}].width;
    NSString *shown = [MMFitWidth(name, f, room) stringByAppendingString:tail], *sub = Facts(facts);
    NSMenuItem *i = Plain([[NSMenuItem alloc] initWithTitle:shown action:nil keyEquivalent:@""]);
    NSMutableAttributedString *t = [NSMutableAttributedString new];
    if (mark != MMMarkNone) {
        // The mark sits in its own column, so names line up whatever the glyph's width.
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:18 options:@{}]];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:[MMMarkGlyph(mark) stringByAppendingString:@"\t"] attributes:@{
            NSFontAttributeName: f, NSForegroundColorAttributeName: MMMarkColor(mark), NSParagraphStyleAttributeName: ps}]];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:shown attributes:@{NSFontAttributeName: f, NSParagraphStyleAttributeName: ps}]];
        i.toolTip = MMMarkWord(mark);
    } else [t appendAttributedString:[[NSAttributedString alloc] initWithString:shown attributes:@{NSFontAttributeName: f}]];
    // On macOS 14 an item with an attributed title shows no subtitle, so there the facts follow the name as a gray tail.
    if (@available(macOS 15.0, *)) {
        i.attributedTitle = t;
        if (sub.length) i.subtitle = MMFitWidth(sub, [NSFont systemFontOfSize:11], room + [tail sizeWithAttributes:@{NSFontAttributeName: f}].width);
    } else {
        CGFloat left = room - [shown sizeWithAttributes:@{NSFontAttributeName: f}].width + [tail sizeWithAttributes:@{NSFontAttributeName: f}].width;
        // A long name keeps its room, and facts that would shrink to an ellipsis are left out.
        left -= [@"    " sizeWithAttributes:@{NSFontAttributeName: f}].width;
        if (sub.length && left >= 40) [t appendAttributedString:MMTitled(@" ", MMFitWidth(sub, f, left))];
        i.attributedTitle = t;
    }
    return i;
}

NSMenuItem *MMActionItem(NSString *title, NSString *tail, SEL action, id target) {
    NSMenuItem *i = Plain([[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""]);
    i.target = target;
    if (tail.length) i.attributedTitle = MMTitled(title, tail);
    return i;
}

NSMenuItem *MMDimmedItem(NSString *title, NSString *reason) {
    NSMenuItem *i = Plain([[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]);
    i.enabled = NO;
    // A disabled item draws its attributed title in the colors given, so the reason stays readable
    // while the action itself looks dimmed.
    NSFont *f = [NSFont menuFontOfSize:0];
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: f, NSForegroundColorAttributeName: NSColor.tertiaryLabelColor}];
    if (reason.length) [t appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:reason] attributes:@{
        NSFontAttributeName: f, NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
    i.attributedTitle = t;
    i.toolTip = reason;
    return i;
}

NSMenuItem *MMAlternateItem(NSString *title, NSString *tail, SEL action, id target) {
    NSMenuItem *i = MMActionItem(title, tail, action, target);
    i.keyEquivalentModifierMask = NSEventModifierFlagOption;
    i.alternate = YES;
    return i;
}

NSMenuItem *MMMoreItem(NSArray<NSMenuItem *> *items) {
    NSMenuItem *i = Plain([[NSMenuItem alloc] initWithTitle:@"More" action:nil keyEquivalent:@""]);
    NSMenu *m = [NSMenu new];
    for (NSMenuItem *x in items) [m addItem:x];
    i.submenu = m;
    return i;
}

void MMRemoveSymbols(NSMenu *menu) {
    for (NSMenuItem *i in menu.itemArray) {
        if (!i.view && !i.isSeparatorItem) Plain(i);
        if (i.submenu) MMRemoveSymbols(i.submenu);
    }
}

#pragma mark Menus

void MMAddSection(NSMenu *menu, NSString *title, NSArray<NSMenuItem *> *rows) {
    if (!rows.count) return;
    [menu addItem:MMSectionItem(title)];
    NSMutableArray *rest = [NSMutableArray new];
    for (NSUInteger k = 0; k < rows.count; k++) {
        if (k < MMMaxSectionRows) [menu addItem:rows[k]];
        else [rest addObject:rows[k]];
    }
    // "3 More", so it reads apart from the expert's own More item lower down.
    if (rest.count) { NSMenuItem *more = MMMoreItem(rest); more.title = [NSString stringWithFormat:@"%lu More", (unsigned long)rest.count]; [menu addItem:more]; }
}

void MMAddFooter(NSMenu *menu, id target) {
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:MMActionItem(@"Hide Icon", nil, NSSelectorFromString(@"hideIcon:"), target)];
    NSMenuItem *s = MMActionItem(@"Settings…", nil, NSSelectorFromString(@"showSettings:"), target);
    s.keyEquivalent = @",";
    [menu addItem:s];
    NSMenuItem *q = MMActionItem(@"Quit MinMacs", nil, @selector(terminate:), nil);
    q.keyEquivalent = @"q";
    [menu addItem:q];
}
