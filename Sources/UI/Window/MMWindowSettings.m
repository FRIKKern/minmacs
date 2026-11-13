// Settings in place, as 197-b: the area under the top line turns into cards, one per rule and one for this Mac's switches.
// Each choice is a row with its title and what it does. A press applies at once, through the host.
#import "UI/Window/MMWindowParts.h"

// A card's choices are 308 points wide. With room in the cards the type is 13 points and the choices stand apart;
// when a card's words would not fit that way, every card goes back to 12 points and stands close.
static const CGFloat kOptionW = 308;
typedef struct { CGFloat size, pad, gap; } Fit;
static const Fit kLarge = {14, 9, 10}, kRoomy = {13, 8, 8}, kEven = {13, 6, 4}, kClose = {12, 5, 2};

static NSAttributedString *Wrapped(NSString *s, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.lineBreakMode = NSLineBreakByWordWrapping;
    // 197-b's lines: 16 points for 12-point text.
    p.minimumLineHeight = p.maximumLineHeight = ceil(size * 1.3);
    return [[NSAttributedString alloc] initWithString:s ?: @"" attributes:@{
        NSFontAttributeName: MMWindowFont(size, weight), NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: p}];
}

static CGFloat WrappedHeight(NSAttributedString *s, CGFloat width) {
    return ceil([s boundingRectWithSize:NSMakeSize(width, 1000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

/// One choice of a rule, or one switch: a real button that draws its own row.
@interface MMWindowOption : NSButton
@property (copy) NSString *label, *explain;
@property BOOL picked, isSwitch, inert;
@property CGFloat explainX;                             // where the explanations start: past the widest title of all, with a gap
@property Fit fit;
@property (strong) NSColor *accent;
@property (copy) NSString *ownerID;
@property NSInteger index;
@end

@implementation MMWindowOption {
    BOOL _hover;
    NSTrackingArea *_tracking;
}

- (CGFloat)wanted {
    Fit f = self.fit;
    if (self.isSwitch) {
        CGFloat h = 10 + WrappedHeight(Wrapped(self.label, 13, NSFontWeightMedium, NSColor.whiteColor), kOptionW - 16 - 50);
        if (self.explain.length) h += 4 + WrappedHeight(Wrapped(self.explain, f.size - 0.5, NSFontWeightRegular, NSColor.whiteColor), kOptionW - 24);
        return h + 10;
    }
    return MAX(26, 2 * f.pad + WrappedHeight(Wrapped(self.explain, f.size, NSFontWeightRegular, NSColor.whiteColor), kOptionW - self.explainX - 8));
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)e { _hover = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)e { _hover = NO; self.needsDisplay = YES; }
- (BOOL)sendAction:(SEL)action to:(id)target { return !self.inert && MMWindowTakesPresses(self) && [super sendAction:action to:target]; }

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    NSRect b = self.bounds;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2);
    Fit f = self.fit;
    if (self.isSwitch) {
        CGFloat titleW = kOptionW - 16 - 50;
        // A switch that changes nothing here is drawn as not available: its title steps back, its track is an outline.
        NSAttributedString *title = Wrapped(self.label, 13, NSFontWeightMedium, self.inert ? MMWindowColor(MMWindowInkText3) : text);
        CGFloat th = WrappedHeight(title, titleW);
        // Each switch is a panel of its own in the card, with its words in the panel's middle.
        [MMWindowColor(MMWindowInkCard) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:b xRadius:10 yRadius:10] fill];
        CGFloat top = floor((b.size.height - self.wanted) / 2) + 5;
        MMWindowDrawIn(title, NSMakeRect(12, top, titleW, th));
        // The switch: the knob sits right and the track fills when it is on, so the state shows in place as well as color.
        NSRect track = NSMakeRect(NSMaxX(b) - 12 - 36, top - 1, 36, 20);
        if (self.inert) {
            NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(track, 0.5, 0.5) xRadius:9.5 yRadius:9.5];
            [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.4 : 0.14] setStroke]; edge.lineWidth = 1; [edge stroke];
            [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.4 : 0.16] setFill];
        } else {
            [(self.picked ? [NSColor colorWithSRGBRed:0.357 green:0.608 blue:1 alpha:1] : [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.16]) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:track xRadius:10 yRadius:10] fill];
            [NSColor.whiteColor setFill];
        }
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(self.picked ? NSMaxX(track) - 18 : NSMinX(track) + 2, track.origin.y + 2, 16, 16)] fill];
        if (self.explain.length)
            MMWindowDrawIn(Wrapped(self.explain, f.size - 0.5, NSFontWeightRegular, t2), NSMakeRect(12, top + th + 4, kOptionW - 24, b.size.height - top - th - 4));
        return;
    }
    if (self.picked || _hover) {
        [[NSColor colorWithWhite:1 alpha:self.picked ? (MMWindowContrast() ? 0.14 : 0.07) : 0.035] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:b xRadius:9 yRadius:9] fill];
    }
    // The picked choice has a filled mark with a white center. The others have an empty ring.
    NSRect mark = NSMakeRect(8, f.pad + 1 + (f.size - 12), 14, 14);
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
    MMWindowDraw(MMWindowText(self.label, f.size, NSFontWeightMedium, self.picked ? NSColor.whiteColor : text), 30, NSMidY(mark), -1);
    MMWindowDrawIn(Wrapped(self.explain, f.size, NSFontWeightRegular, self.picked ? text : t2), NSMakeRect(self.explainX, f.pad, kOptionW - self.explainX - 8, b.size.height - 2 * f.pad));
}

- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.isSwitch ? 10 : 9 yRadius:self.isSwitch ? 10 : 9] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

@end

#pragma mark The cards

@implementation MMWindowSettingsView {
    NSMutableArray<MMWindowOption *> *_options;
    NSMutableArray<NSValue *> *_cards;      // each card's frame; the last one is This Mac when there are switches
    MMWindowButton *_done;
    NSString *_built;
    Fit _fit;
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
    // While Settings is away nothing is built: the menu opens without paying for cards nobody sees. They are built
    // when Settings comes, before its first frame.
    if (self.hidden) { _built = nil; return; }
    // The cards are built again only when something they show changed.
    NSMutableString *sig = [NSMutableString new];
    for (MMWindowRule *r in settings.rules) {
        [sig appendFormat:@"%@|%@|%ld|%@;", r.ruleID, r.title, (long)r.picked, r.note ?: @""];
        for (MMWindowChoice *c in r.choices) [sig appendFormat:@"%@=%@,", c.title, c.explain];
    }
    for (MMWindowSwitch *s in settings.switches) [sig appendFormat:@"%@|%@|%d|%d|%@;", s.switchID, s.title, s.on, s.inert, s.note ?: @""];
    [sig appendFormat:@"%d", MMWindowContrast()];
    if ([sig isEqualToString:_built]) return;
    _built = sig;
    [self build];
}

- (void)viewDidUnhide { [super viewDidUnhide]; if (!_built) self.settings = self.settings; }

- (void)setFrameSize:(NSSize)size {
    BOOL changed = !NSEqualSizes(size, self.frame.size);
    [super setFrameSize:size];
    if (changed && _built) { _built = nil; self.settings = self.settings; }
}

/// The largest type and spacing whose words fit the cards. A window with room gives it to calmer type, not to emptiness.
- (void)build {
    const Fit ladder[] = {kLarge, kRoomy, kEven, kClose};
    for (int i = 0; i < 4; i++) if ([self build:ladder[i]]) return;
}

/// Lays the cards out with this type size and spacing. NO when some card's words do not fit it.
/// The grid is three across. Each row is as tall as its tallest card needs, the rows share what is left, so the last
/// row ends at the foot, and inside a card the choices stand apart by its share: no card has a dead half.
- (BOOL)build:(Fit)fit {
    for (NSView *v in _options) [v removeFromSuperview];
    [_options removeAllObjects]; [_cards removeAllObjects];
    NSInteger rules = (NSInteger)self.settings.rules.count, n = rules + (self.settings.switches.count ? 1 : 0);
    if (!n) { self.needsDisplay = YES; return YES; }
    _fit = fit;
    // The explanations of every card start at one place: past the widest title, so "Careful" never touches its words.
    CGFloat widest = 0;
    for (MMWindowRule *rule in self.settings.rules) for (MMWindowChoice *c in rule.choices)
        widest = MAX(widest, MMWindowWidth(MMWindowText(c.title, fit.size, NSFontWeightMedium, NSColor.whiteColor)));
    CGFloat explainX = MIN(30 + widest + 10, 130);
    NSInteger columns = MIN(n, 3), rows = (n + columns - 1) / columns;
    CGFloat top = 40, gap = 10, w = floor((self.bounds.size.width - 28 - gap * (columns - 1)) / columns), head = fit.size > 12 ? 48 : 44;

    // First what each card holds and how tall that is.
    NSMutableArray<NSArray<MMWindowOption *> *> *held = [NSMutableArray new];
    NSMutableArray<NSNumber *> *need = [NSMutableArray new];
    for (NSInteger i = 0; i < n; i++) {
        NSMutableArray<MMWindowOption *> *mine = [NSMutableArray new];
        CGFloat h = head;
        if (i < rules) {
            MMWindowRule *rule = self.settings.rules[i];
            for (NSInteger c = 0; c < (NSInteger)rule.choices.count; c++) {
                MMWindowOption *o = [self option:rule.choices[c].title explain:rule.choices[c].explain picked:c == rule.picked];
                o.ownerID = rule.ruleID; o.index = c; o.accent = MMWindowGroupColor(rule.ruleID);
                o.fit = fit; o.explainX = explainX;
                o.accessibilityRole = NSAccessibilityRadioButtonRole;
                o.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", rule.title, o.label, o.explain];
                [mine addObject:o];
                h += o.wanted + (c ? fit.gap : 0);
            }
            h += rule.note.length ? WrappedHeight(Wrapped(rule.note, fit.size - 1, NSFontWeightRegular, NSColor.whiteColor), w - 32) + 14 + 10 : 12;
        } else {
            for (MMWindowSwitch *s in self.settings.switches) {
                MMWindowOption *o = [self option:s.title explain:s.note ?: @"" picked:s.on];
                o.isSwitch = YES; o.ownerID = s.switchID; o.fit = fit;
                // A switch that changes nothing here takes no press, and VoiceOver reads it as dimmed with its reason.
                o.inert = s.inert; o.enabled = !s.inert;
                o.accessibilityRole = NSAccessibilityCheckBoxRole;
                o.accessibilityLabel = s.note.length ? [NSString stringWithFormat:@"%@. %@", s.title, s.note] : s.title;
                [mine addObject:o];
                h += o.wanted + (mine.count > 1 ? 12 : 0);
            }
            h += 10;
        }
        [held addObject:mine]; [need addObject:@(ceil(h))];
    }
    // Each row as tall as its tallest card, plus an even share of what the window has left.
    CGFloat room = self.bounds.size.height - top - 8 - gap * (rows - 1), wanted = 0;
    NSMutableArray<NSNumber *> *rowNeed = [NSMutableArray new];
    for (NSInteger r = 0; r < rows; r++) {
        CGFloat most = 0;
        for (NSInteger i = r * columns; i < MIN(n, (r + 1) * columns); i++) most = MAX(most, need[i].doubleValue);
        [rowNeed addObject:@(most)]; wanted += most;
    }
    BOOL fits = wanted <= room;
    CGFloat share = floor((room - wanted) / rows), y0 = top;
    for (NSInteger i = 0; i < n; i++) {
        NSInteger r = i / columns;
        if (i % columns == 0 && r > 0) y0 += (fits ? rowNeed[r - 1].doubleValue + share : floor(room / rows)) + gap;
        CGFloat h = fits ? rowNeed[r].doubleValue + share : floor(room / rows);
        NSRect card = NSMakeRect(14 + (i % columns) * (w + gap), y0, w, h);
        [_cards addObject:[NSValue valueWithRect:card]];
        NSArray<MMWindowOption *> *mine = held[i];
        if (i >= rules) {
            // This Mac: its switches are panels that share the card, so the card has no empty middle.
            CGFloat each = floor((NSMaxY(card) - 10 - card.origin.y - head - 8 * ((CGFloat)mine.count - 1)) / MAX((CGFloat)mine.count, 1)), y = card.origin.y + head;
            for (MMWindowOption *o in mine) { o.frame = NSMakeRect(card.origin.x + 8, y, MIN(kOptionW, w - 16), MAX(each, o.wanted)); y += MAX(each, o.wanted) + 8; }
            continue;
        }
        // What a card has beyond its need goes between its choices, up to a calm distance. The cards of one row take
        // the same distance, the least of theirs, so their first choices stand level. The rest is a card's foot.
        CGFloat apart = 14;
        for (NSInteger j = r * columns; j < MIN(rules, (r + 1) * columns); j++) apart = MIN(apart, floor(MAX(0, h - need[j].doubleValue) / MAX((CGFloat)held[j].count, 1)));
        CGFloat y = card.origin.y + head + floor(apart / 2);
        for (MMWindowOption *o in mine) {
            CGFloat oh = o.wanted;
            o.frame = NSMakeRect(card.origin.x + 8, y, MIN(kOptionW, w - 16), oh);
            y += oh + fit.gap + apart;
        }
    }
    self.needsDisplay = YES;
    return fits;
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
        MMWindowDrawBlock(rule ? r.title : @"This Mac", _fit.size + 1, 11, NSFontWeightSemibold, text, card.origin.x + 16, card.origin.y + 24, card.size.width - 32, -1, 0);
        if (!r.note.length) continue;
        // What the rule would do next sits at the foot of its card.
        NSAttributedString *note = Wrapped(r.note, _fit.size - 1, NSFontWeightRegular, t2);
        CGFloat nh = WrappedHeight(note, card.size.width - 32);
        MMWindowDrawIn(note, NSMakeRect(card.origin.x + 16, NSMaxY(card) - 14 - nh, card.size.width - 32, nh));
    }
}

@end
