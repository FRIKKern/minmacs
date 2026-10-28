#import "MMCard.h"
#import "MMFormat.h"

static const CGFloat kPad = 16, kTextSize = 12.5, kFactSize = 12, kLabelSize = 11.5;
static const CGFloat kItemText = 24;   // where a native menu item's title text starts, past the state column

#pragma mark Links

static void (^gOpener)(NSString *expert, NSString *key);
void MMSetLinkOpener(void (^opener)(NSString *expert, NSString *key)) { gOpener = [opener copy]; }
void MMOpenLink(NSString *expert, NSString *key) { if (gOpener && expert.length && key.length) gOpener(expert, key); }

/// The target of every link row. The row carries its link as its representedObject.
@interface MMLinkTarget : NSObject
+ (instancetype)shared;
- (void)openLink:(NSMenuItem *)sender;
@end
@implementation MMLinkTarget
+ (instancetype)shared { static MMLinkTarget *t; static dispatch_once_t once; dispatch_once(&once, ^{ t = [MMLinkTarget new]; }); return t; }
- (void)openLink:(NSMenuItem *)sender {
    NSDictionary *l = MMLinkOfItem(sender);
    MMOpenLink(l[@"expert"], l[@"key"]);
}
@end

NSDictionary<NSString *, NSString *> *MMLinkOfItem(NSMenuItem *item) {
    if (item.action != @selector(openLink:) || item.target != MMLinkTarget.shared) return nil;
    NSDictionary *l = item.representedObject;
    return [l isKindOfClass:NSDictionary.class] ? l : nil;
}

@implementation MMCard {
    NSMutableArray<NSArray *> *_facts;          // @[label, value, linked]
    NSMutableArray<NSDictionary *> *_links;
    NSMutableArray<NSMenuItem *> *_actions, *_more;
    NSInteger _offered;                         // non-empty facts offered, to report when more than five came
}

- (instancetype)init {
    if ((self = [super init])) { _facts = [NSMutableArray new]; _links = [NSMutableArray new]; _actions = [NSMutableArray new]; _more = [NSMutableArray new]; }
    return self;
}

static CGFloat Inner(void) { return MMMenuWidth - 2 * kPad; }
static CGFloat ValueWidth(void) { return Inner() - MMLabelColumn - 10; }

- (void)fact:(NSString *)label value:(NSString *)value {
    if (![value isKindOfClass:NSString.class] || !value.length) return;
    _offered++;
    if (_facts.count < MMMaxCardFacts) [_facts addObject:@[label ?: @"", value, @NO]];
}

- (void)link:(NSString *)label value:(NSString *)value expert:(NSString *)expert key:(NSString *)key {
    if (![value isKindOfClass:NSString.class] || !value.length) return;
    _offered++;
    if (_facts.count >= MMMaxCardFacts) return;
    [_facts addObject:@[label ?: @"", value, @YES]];
    [_links addObject:@{@"label": label ?: @"", @"value": value, @"expert": expert ?: @"", @"key": key ?: @""}];
}

/// A link row: the label right-aligned in the card's label column and the value where the card's values start,
/// both measured from where a native item's title begins.
- (NSArray<NSMenuItem *> *)linkItems {
    NSMutableArray *out = [NSMutableArray new];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:kPad + MMLabelColumn - kItemText options:@{}],
                    [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:kPad + MMLabelColumn + 10 - kItemText options:@{}]];
    ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSFont *vf = [NSFont systemFontOfSize:kFactSize];
    for (NSDictionary *l in _links) {
        NSString *value = MMFitWidth(l[@"value"], vf, ValueWidth());
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"\t%@\t", l[@"label"]] attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:kLabelSize], NSForegroundColorAttributeName: NSColor.secondaryLabelColor, NSParagraphStyleAttributeName: ps}];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{
            NSFontAttributeName: vf, NSForegroundColorAttributeName: NSColor.linkColor, NSParagraphStyleAttributeName: ps}]];
        NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ %@", l[@"label"], l[@"value"]] action:@selector(openLink:) keyEquivalent:@""];
        i.attributedTitle = t;
        i.target = MMLinkTarget.shared;
        i.representedObject = @{@"expert": l[@"expert"], @"key": l[@"key"]};
        i.toolTip = l[@"value"];
        [out addObject:i];
    }
    return out;
}

- (NSArray<NSDictionary *> *)links { return [_links copy]; }
- (void)action:(NSMenuItem *)item { if (item) [_actions addObject:item]; }
- (void)more:(NSMenuItem *)item { if (item) [_more addObject:item]; }

- (BOOL)noteAddsSomething {
    NSString *note = [self.note stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (!note.length) return NO;
    NSString *said = [@[self.title ?: @"", self.statusWord ?: @"", self.statusText ?: @""] componentsJoinedByString:@" "].lowercaseString;
    // A note that opens the way the status or title already reads says the same thing twice.
    NSString *head = [note substringToIndex:MIN(note.length, 40)];
    if ([head hasSuffix:@"."]) head = [head substringToIndex:head.length - 1];
    return !(note.length > 12 && [said containsString:head]) && ![said containsString:note];
}

- (NSColor *)wordColor {
    // The word takes its mark's color, so the two never disagree. MMMarkColor is dark enough to read on a light menu.
    return self.statusColor ?: MMMarkColor(self.mark);
}

/// The mark, the bold status word and as many whole sentences of the status text as fit in two lines.
- (NSAttributedString *)statusString {
    NSFont *bold = [NSFont systemFontOfSize:kTextSize weight:NSFontWeightSemibold];
    NSAttributedString *(^build)(NSString *) = ^NSAttributedString *(NSString *rest) {
        NSMutableAttributedString *a = [NSMutableAttributedString new];
        if (self.mark != MMMarkNone)
            [a appendAttributedString:[[NSAttributedString alloc] initWithString:[MMMarkGlyph(self.mark) stringByAppendingString:@" "] attributes:@{
                NSFontAttributeName: bold, NSForegroundColorAttributeName: MMMarkColor(self.mark)}]];
        [a appendAttributedString:MMRich(self.statusWord ?: @"", [self wordColor], rest, kTextSize)];
        return a;
    };
    NSString *text = self.statusText ?: @"";
    NSMutableArray *parts = [NSMutableArray new];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationBySentences usingBlock:^(NSString *s, NSRange r, NSRange er, BOOL *stop) {
        [parts addObject:[text substringWithRange:er]];
    }];
    CGFloat limit = MMLinesHeight(bold, MMMaxCardStatusLines);
    NSMutableString *out = [NSMutableString new];
    for (NSString *p in parts) {
        NSString *next = [[out stringByAppendingString:p] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        CGFloat h = [build(next) boundingRectWithSize:NSMakeSize(Inner(), 4000) options:NSStringDrawingUsesLineFragmentOrigin].size.height;
        if (h > limit && out.length) break;
        [out appendString:p];
    }
    return build([out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
}

- (NSString *)noteString {
    NSString *n = MMSentence(self.note);
    return self.noteBy.length ? [NSString stringWithFormat:@"%@: %@", self.noteBy, n] : n;
}

- (NSMenuItem *)cardItem {
    CGFloat inner = Inner();
    NSStackView *s = [NSStackView new];
    s.orientation = NSUserInterfaceLayoutOrientationVertical; s.alignment = NSLayoutAttributeLeading; s.spacing = 8;
    s.edgeInsets = NSEdgeInsetsMake(10, kPad, _links.count ? 2 : 10, kPad);   // link rows follow as items of their own

    [s addArrangedSubview:MMPara(MMCapitalized(self.title), [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor, inner, MMMaxCardTitleLines)];
    [s addArrangedSubview:MMParaRich([self statusString], inner, MMMaxCardStatusLines)];

    // Facts as label and value, in two columns. The label column is the same on every card.
    if (_facts.count > _links.count) {
        NSMutableArray *rows = [NSMutableArray new];
        for (NSArray *f in _facts) {
            if ([f[2] boolValue]) continue;   // a link is a row of its own under the card
            NSTextField *l = [NSTextField labelWithString:f[0]];
            l.font = [NSFont systemFontOfSize:kLabelSize]; l.textColor = NSColor.secondaryLabelColor; l.alignment = NSTextAlignmentRight;
            NSTextField *x = [NSTextField labelWithString:f[1]];
            x.font = [NSFont systemFontOfSize:kFactSize]; x.textColor = NSColor.labelColor;
            x.lineBreakMode = NSLineBreakByTruncatingTail; x.toolTip = f[1];
            [x.widthAnchor constraintLessThanOrEqualToConstant:ValueWidth()].active = YES;
            [rows addObject:@[l, x]];
        }
        NSGridView *g = [NSGridView gridViewWithViews:rows];
        g.rowSpacing = 4; g.columnSpacing = 10;
        [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing; [g columnAtIndex:0].width = MMLabelColumn;
        [g columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
        g.rowAlignment = NSGridRowAlignmentFirstBaseline;
        [s addArrangedSubview:g];
    }
    // With link rows the note follows them, so the facts and the links read as one list.
    if ([self noteAddsSomething] && !_links.count) [s addArrangedSubview:[self noteView]];
    NSSize fit = s.fittingSize;
    s.frame = NSMakeRect(0, 0, MMMenuWidth, fit.height);
    NSMenuItem *i = [NSMenuItem new]; i.view = s;
    return i;
}

- (NSTextField *)noteView {
    NSFont *f = [NSFont systemFontOfSize:kLabelSize];
    CGFloat inner = Inner();
    return MMPara(MMFitSentences([self noteString], f, inner, MMMaxCardNoteLines), f, NSColor.secondaryLabelColor, inner, MMMaxCardNoteLines);
}

- (NSMenu *)menu {
    NSMenu *m = [NSMenu new];
    [m addItem:[self cardItem]];
    for (NSMenuItem *l in [self linkItems]) [m addItem:l];
    if (_links.count && [self noteAddsSomething]) {
        NSStackView *s = [NSStackView new];
        s.orientation = NSUserInterfaceLayoutOrientationVertical; s.alignment = NSLayoutAttributeLeading;
        s.edgeInsets = NSEdgeInsetsMake(6, kPad, 10, kPad);
        [s addArrangedSubview:[self noteView]];
        s.frame = NSMakeRect(0, 0, MMMenuWidth, s.fittingSize.height);
        NSMenuItem *i = [NSMenuItem new]; i.view = s;
        [m addItem:i];
    }
    NSMutableArray *rest = [NSMutableArray new];
    NSInteger shown = 0;
    BOOL lastShown = NO;
    for (NSMenuItem *a in _actions) {
        // An alternate stays with the action before it, wherever that went.
        if (a.isAlternate) { if (lastShown) [m addItem:a]; else [rest addObject:a]; continue; }
        lastShown = shown < MMMaxCardActions;
        if (lastShown) {
            if (shown == 0) [m addItem:NSMenuItem.separatorItem];
            [m addItem:a]; shown++;
        } else [rest addObject:a];
    }
    [rest addObjectsFromArray:_more];
    if (rest.count) {
        if (!shown) [m addItem:NSMenuItem.separatorItem];
        [m addItem:MMMoreItem(rest)];
    }
    return m;
}

- (NSArray<NSString *> *)layoutProblems {
    NSMutableArray *p = [NSMutableArray new];
    CGFloat inner = Inner();
    NSFont *tf = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    CGFloat th = [MMCapitalized(self.title) boundingRectWithSize:NSMakeSize(inner, 4000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: tf}].size.height;
    if (!self.title.length) [p addObject:@"no title"];
    else if (th > MMLinesHeight(tf, MMMaxCardTitleLines)) [p addObject:@"the title is longer than two lines"];
    NSString *w = self.statusWord ?: @"";
    if (!w.length || ![NSCharacterSet.letterCharacterSet characterIsMember:[w characterAtIndex:0]]) [p addObject:@"the status does not start with a word"];
    if (self.mark == MMMarkNone) [p addObject:@"the status has no mark"];
    NSAttributedString *st = [self statusString];
    CGFloat sh = [st boundingRectWithSize:NSMakeSize(inner, 4000) options:NSStringDrawingUsesLineFragmentOrigin].size.height;
    if (sh > MMLinesHeight([NSFont systemFontOfSize:kTextSize weight:NSFontWeightSemibold], MMMaxCardStatusLines)) [p addObject:@"the status is longer than two lines"];
    if (self.statusText.length && ![st.string hasSuffix:[self.statusText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]])
        [p addObject:@"the status lost a sentence to fit two lines"];
    if (_offered > MMMaxCardFacts) [p addObject:[NSString stringWithFormat:@"%ld facts given, five shown", (long)_offered]];
    NSFont *ff = [NSFont systemFontOfSize:kFactSize];
    for (NSArray *f in _facts) {
        NSString *v = f[1];
        if ([v sizeWithAttributes:@{NSFontAttributeName: ff}].width <= ValueWidth()) continue;
        // A long value may lose its tail, but never its first fact.
        NSString *first = v;
        for (NSString *sep in @[@" · ", @", "]) first = [first componentsSeparatedByString:sep].firstObject;
        if ([first sizeWithAttributes:@{NSFontAttributeName: ff}].width > ValueWidth()) [p addObject:[NSString stringWithFormat:@"the %@ fact is cut in its first part", f[0]]];
    }
    NSFont *lf = [NSFont systemFontOfSize:kLabelSize];
    for (NSArray *f in _facts)
        if ([f[0] sizeWithAttributes:@{NSFontAttributeName: lf}].width > MMLabelColumn) [p addObject:[NSString stringWithFormat:@"the label %@ is wider than the label column", f[0]]];
    if (self.note.length && [self noteAddsSomething]) {
        NSString *n = [self noteString];
        if (![MMFitSentences(n, lf, inner, MMMaxCardNoteLines) isEqualToString:[n stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]])
            [p addObject:@"the note is longer than two lines"];
    }
    return p;
}

@end
