// Settings in place, as 197-b: the area under the top line turns into cards, one per rule and one for this Mac's switches.
// Each choice is a row with its title and what it does. A press applies at once, through the host.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kExplainX = 72, kOptionW = 308;

static NSAttributedString *Wrapped(NSString *s, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.lineBreakMode = NSLineBreakByWordWrapping;
    return [[NSAttributedString alloc] initWithString:s ?: @"" attributes:@{
        NSFontAttributeName: MMWindowFont(size, weight), NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: p}];
}

static CGFloat WrappedHeight(NSAttributedString *s, CGFloat width) {
    return ceil([s boundingRectWithSize:NSMakeSize(width, 1000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

/// One choice of a rule, or one switch: a real button that draws its own row.
@interface MMWindowOption : NSButton
@property (copy) NSString *label, *explain;
@property BOOL picked, isSwitch;
@property (strong) NSColor *accent;
@property (copy) NSString *ownerID;
@property NSInteger index;
@end

@implementation MMWindowOption {
    BOOL _hover;
    NSTrackingArea *_tracking;
}

- (CGFloat)wanted {
    if (self.isSwitch) {
        CGFloat h = 10 + WrappedHeight(Wrapped(self.label, 13, NSFontWeightMedium, NSColor.whiteColor), kOptionW - 16 - 50);
        if (self.explain.length) h += 4 + WrappedHeight(Wrapped(self.explain, 11.5, NSFontWeightRegular, NSColor.whiteColor), kOptionW - 16);
        return h + 10;
    }
    return MAX(26, 10 + WrappedHeight(Wrapped(self.explain, 12, NSFontWeightRegular, NSColor.whiteColor), kOptionW - kExplainX - 8));
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)e { _hover = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)e { _hover = NO; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2);
    if (self.isSwitch) {
        CGFloat titleW = kOptionW - 16 - 50;
        NSAttributedString *title = Wrapped(self.label, 13, NSFontWeightMedium, text);
        CGFloat th = WrappedHeight(title, titleW);
        [title drawWithRect:NSMakeRect(8, 5, titleW, th) options:NSStringDrawingUsesLineFragmentOrigin];
        // The switch: the knob sits right and the track fills when it is on, so the state shows in place as well as color.
        NSRect track = NSMakeRect(NSMaxX(b) - 8 - 36, 4, 36, 20);
        [(self.picked ? [NSColor colorWithSRGBRed:0.357 green:0.608 blue:1 alpha:1] : [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.16]) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:track xRadius:10 yRadius:10] fill];
        [NSColor.whiteColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(self.picked ? NSMaxX(track) - 18 : NSMinX(track) + 2, track.origin.y + 2, 16, 16)] fill];
        if (self.explain.length)
            [Wrapped(self.explain, 11.5, NSFontWeightRegular, t2) drawWithRect:NSMakeRect(8, 5 + th + 4, kOptionW - 16, b.size.height) options:NSStringDrawingUsesLineFragmentOrigin];
        return;
    }
    if (self.picked || _hover) {
        [[NSColor colorWithWhite:1 alpha:self.picked ? (MMWindowContrast() ? 0.14 : 0.07) : 0.035] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:b xRadius:9 yRadius:9] fill];
    }
    // The picked choice has a filled mark with a white center. The others have an empty ring.
    NSRect mark = NSMakeRect(8, 6, 14, 14);
    if (self.picked) {
        [self.accent setFill];
        [[NSBezierPath bezierPathWithOvalInRect:mark] fill];
        [NSColor.whiteColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(mark, 4, 4)] fill];
    } else {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(mark, 0.75, 0.75)];
        ring.lineWidth = 1.5;
        [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.6 : 0.3] setStroke];
        [ring stroke];
    }
    MMWindowDraw(MMWindowText(self.label, 12, NSFontWeightMedium, self.picked ? NSColor.whiteColor : text), 30, 13, -1);
    [Wrapped(self.explain, 12, NSFontWeightRegular, self.picked ? text : t2) drawWithRect:NSMakeRect(kExplainX, 5, kOptionW - kExplainX - 8, b.size.height) options:NSStringDrawingUsesLineFragmentOrigin];
}

- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:9 yRadius:9] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

@end

#pragma mark The cards

@implementation MMWindowSettingsView {
    NSMutableArray<MMWindowOption *> *_options;
    NSMutableArray<NSValue *> *_cards;      // each card's frame; the last one is This Mac when there are switches
    MMWindowButton *_done;
    NSString *_built;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _options = [NSMutableArray new]; _cards = [NSMutableArray new];
        _done = [MMWindowButton kind:MMWindowButtonPill title:@"Done" target:self action:@selector(done:)];
        _done.frame = NSMakeRect(frame.size.width - 76, 8, 58, 24);
        _done.toolTip = @"Done  esc";
        [self addSubview:_done];
    }
    return self;
}

- (void)done:(id)sender { if (self.onDone) self.onDone(); }

- (void)setSettings:(MMWindowSettings *)settings {
    _settings = settings;
    // The cards are built again only when something they show changed.
    NSMutableString *sig = [NSMutableString new];
    for (MMWindowRule *r in settings.rules) {
        [sig appendFormat:@"%@|%@|%ld|%@;", r.ruleID, r.title, (long)r.picked, r.note ?: @""];
        for (MMWindowChoice *c in r.choices) [sig appendFormat:@"%@=%@,", c.title, c.explain];
    }
    for (MMWindowSwitch *s in settings.switches) [sig appendFormat:@"%@|%@|%d|%@;", s.switchID, s.title, s.on, s.note ?: @""];
    [sig appendFormat:@"%d", MMWindowContrast()];
    if ([sig isEqualToString:_built]) return;
    _built = sig;
    [self build];
}

- (void)build {
    for (NSView *v in _options) [v removeFromSuperview];
    [_options removeAllObjects]; [_cards removeAllObjects];
    NSInteger n = (NSInteger)self.settings.rules.count + (self.settings.switches.count ? 1 : 0);
    if (!n) { self.needsDisplay = YES; return; }
    NSInteger columns = MIN(n, 3), rows = (n + columns - 1) / columns;
    CGFloat top = 40, gap = 10, w = floor((self.bounds.size.width - 28 - gap * (columns - 1)) / columns);
    CGFloat h = floor((self.bounds.size.height - top - 8 - gap * (rows - 1)) / rows);
    for (NSInteger i = 0; i < n; i++) {
        NSRect card = NSMakeRect(14 + (i % columns) * (w + gap), top + (i / columns) * (h + gap), w, h);
        [_cards addObject:[NSValue valueWithRect:card]];
        CGFloat y = card.origin.y + 44;
        if (i < (NSInteger)self.settings.rules.count) {
            MMWindowRule *rule = self.settings.rules[i];
            for (NSInteger c = 0; c < (NSInteger)rule.choices.count; c++) {
                MMWindowOption *o = [self option:rule.choices[c].title explain:rule.choices[c].explain picked:c == rule.picked];
                o.ownerID = rule.ruleID; o.index = c; o.accent = MMWindowGroupColor(rule.ruleID);
                o.accessibilityRole = NSAccessibilityRadioButtonRole;
                o.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", rule.title, o.label, o.explain];
                CGFloat oh = o.wanted;
                o.frame = NSMakeRect(card.origin.x + 8, y, MIN(kOptionW, w - 16), oh);
                y += oh + 2;
            }
        } else {
            for (MMWindowSwitch *s in self.settings.switches) {
                MMWindowOption *o = [self option:s.title explain:s.note ?: @"" picked:s.on];
                o.isSwitch = YES; o.ownerID = s.switchID;
                o.accessibilityRole = NSAccessibilityCheckBoxRole;
                o.accessibilityLabel = s.note.length ? [NSString stringWithFormat:@"%@. %@", s.title, s.note] : s.title;
                CGFloat oh = o.wanted;
                o.frame = NSMakeRect(card.origin.x + 8, y, MIN(kOptionW, w - 16), oh);
                y += oh + 8;
            }
        }
    }
    self.needsDisplay = YES;
}

- (MMWindowOption *)option:(NSString *)label explain:(NSString *)explain picked:(BOOL)picked {
    MMWindowOption *o = [[MMWindowOption alloc] initWithFrame:NSZeroRect];
    o.title = @""; o.bordered = NO;
    [o setButtonType:NSButtonTypeMomentaryChange];
    o.label = label; o.explain = explain; o.picked = picked;
    o.accessibilityValue = picked ? @1 : @0;
    o.target = self; o.action = @selector(pressed:);
    [self addSubview:o];
    [_options addObject:o];
    return o;
}

/// A press shows at once and goes to the host, which applies it. The next model confirms it.
- (void)pressed:(MMWindowOption *)o {
    if (o.isSwitch) {
        BOOL on = !o.picked;
        for (MMWindowSwitch *s in self.settings.switches) if ([s.switchID isEqualToString:o.ownerID]) s.on = on;
        [self.host windowSetSwitch:o.ownerID on:on];
    } else {
        if (o.picked) return;
        for (MMWindowRule *r in self.settings.rules) if ([r.ruleID isEqualToString:o.ownerID]) r.picked = o.index;
        [self.host windowSetRule:o.ownerID picked:o.index];
    }
    NSString *focus = o.ownerID;
    NSInteger index = o.index;
    self.settings = self.settings;
    for (MMWindowOption *n in _options) if ([n.ownerID isEqualToString:focus] && n.index == index) [self.window makeFirstResponder:n];
}

- (void)drawRect:(NSRect)dirty {
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2);
    NSAttributedString *head = MMWindowText(@"Settings", 15, NSFontWeightSemibold, NSColor.whiteColor);
    MMWindowDraw(head, 18, 20, -1);
    MMWindowDraw(MMWindowText(@"Each change applies at once.", 12, NSFontWeightRegular, t2), 18 + MMWindowWidth(head) + 12, 20.5, -1);
    for (NSInteger i = 0; i < (NSInteger)_cards.count; i++) {
        NSRect card = _cards[i].rectValue;
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(card, 0.5, 0.5) xRadius:14 yRadius:14];
        [MMWindowColor(MMWindowInkCard) setFill]; [p fill];
        [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.06] setStroke]; p.lineWidth = 1; [p stroke];
        BOOL rule = i < (NSInteger)self.settings.rules.count;
        MMWindowRule *r = rule ? self.settings.rules[i] : nil;
        MMWindowDraw(MMWindowFit(rule ? r.title : @"This Mac", 13, NSFontWeightSemibold, text, card.size.width - 32), card.origin.x + 16, card.origin.y + 24, -1);
        if (!r.note.length) continue;
        // What the rule would do next sits at the foot of its card.
        NSAttributedString *note = Wrapped(r.note, 11.5, NSFontWeightRegular, t2);
        CGFloat nh = WrappedHeight(note, card.size.width - 32);
        [note drawWithRect:NSMakeRect(card.origin.x + 16, NSMaxY(card) - 14 - nh, card.size.width - 32, nh) options:NSStringDrawingUsesLineFragmentOrigin];
    }
}

@end
