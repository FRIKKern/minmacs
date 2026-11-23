// Settings in place: the area under the top line turns into cards. "Keep this Mac awake" comes first, then "Clean up
// on its own" with one switch per rule, then the removal choice, then This Mac. A switch is a panel with its title and
// one sentence; a choice is a row with its title and what it does. A press applies at once, through the host.
#import "UI/Window/MMWindowParts.h"

// A card's choices are at least 308 points wide, and as wide as the card. With room in the cards the type is 13 points and the choices stand apart;
// when a card's words would not fit that way, every card goes back to 12 points and stands close.
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
@property CGFloat width;                                // the width it is laid out in, set before -wanted
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
        CGFloat h = 10 + WrappedHeight(Wrapped(self.label, 13, NSFontWeightMedium, NSColor.whiteColor), self.width - 16 - 50);
        if (self.explain.length) h += 4 + WrappedHeight(Wrapped(self.explain, f.size - 0.5, NSFontWeightRegular, NSColor.whiteColor), self.width - 24);
        return h + 10;
    }
    return MAX(26, 2 * f.pad + WrappedHeight(Wrapped(self.explain, f.size, NSFontWeightRegular, NSColor.whiteColor), self.width - self.explainX - 8));
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
        CGFloat titleW = self.width - 16 - 50;
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
            MMWindowDrawIn(Wrapped(self.explain, f.size - 0.5, NSFontWeightRegular, t2), NSMakeRect(12, top + th + 4, self.width - 24, b.size.height - top - th - 4));
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
    MMWindowDrawIn(Wrapped(self.explain, f.size, NSFontWeightRegular, self.picked ? text : t2), NSMakeRect(self.explainX, f.pad, self.width - self.explainX - 8, b.size.height - 2 * f.pad));
}

- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.isSwitch ? 10 : 9 yRadius:self.isSwitch ? 10 : 9] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

@end

#pragma mark The cards

@implementation MMWindowSettingsView {
    NSMutableArray<MMWindowOption *> *_options;
    NSMutableArray<NSValue *> *_cards;      // each card's frame
    NSMutableArray<NSString *> *_cardTitles, *_cardNotes;   // each card's title, and the note at its foot or ""
    NSMutableArray<NSNumber *> *_cardRadio; // each card: YES for a card of choices, NO for a card of switches
    MMWindowButton *_done;
    NSString *_built;
    Fit _fit;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _options = [NSMutableArray new]; _cards = [NSMutableArray new];
        _cardTitles = [NSMutableArray new]; _cardNotes = [NSMutableArray new]; _cardRadio = [NSMutableArray new];
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
    for (MMWindowSwitch *s in settings.switches) [sig appendFormat:@"%@|%@|%@|%d|%d|%@;", s.switchID, s.card, s.title, s.on, s.inert, s.note ?: @""];
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
/// Four cards stand two across, more three across. Each row is as tall as its tallest card needs, the rows share what
/// is left, so the last row ends at the foot, and inside a card the choices stand apart by its share: no card has a dead half.
- (BOOL)build:(Fit)fit {
    for (NSView *v in _options) [v removeFromSuperview];
    [_options removeAllObjects]; [_cards removeAllObjects];
    [_cardTitles removeAllObjects]; [_cardNotes removeAllObjects]; [_cardRadio removeAllObjects];
    MMWindowSettings *st = self.settings;
    // What each card holds, in order: its title, its options, its note, and whether its options are choices.
    NSMutableArray<NSString *> *titles = [NSMutableArray new], *notes = [NSMutableArray new];
    NSMutableArray<NSMutableArray<MMWindowOption *> *> *held = [NSMutableArray new];
    NSMutableArray<NSNumber *> *radio = [NSMutableArray new];
    NSMutableArray<MMWindowRule *> *choiceRules = [NSMutableArray new], *switchRules = [NSMutableArray new];
    for (MMWindowRule *r in st.rules) [(MMWindowRuleSwitchTitle(r.ruleID) ? switchRules : choiceRules) addObject:r];
    NSMutableArray<NSString *> *switchCards = [NSMutableArray new];
    for (MMWindowSwitch *sw in st.switches) { NSString *c = sw.card ?: MMWindowMacCard; if (![switchCards containsObject:c]) [switchCards addObject:c]; }
    // Keep this Mac awake first, This Mac last.
    if ([switchCards containsObject:MMWindowAwakeCard]) { [switchCards removeObject:MMWindowAwakeCard]; [switchCards insertObject:MMWindowAwakeCard atIndex:0]; }
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    if ([switchCards containsObject:MMWindowAwakeCard]) [order addObject:MMWindowAwakeCard];
    if (switchRules.count) [order addObject:MMWindowCleanupCard];
    for (MMWindowRule *r in choiceRules) [order addObject:[@"rule:" stringByAppendingString:r.ruleID]];
    for (NSString *c in switchCards) if (![c isEqualToString:MMWindowAwakeCard]) [order addObject:c];
    NSInteger n = (NSInteger)order.count;
    if (!n) { self.needsDisplay = YES; return YES; }
    _fit = fit;
    NSInteger columns = n == 4 ? 2 : MIN(n, 3), rows = (n + columns - 1) / columns;
    CGFloat top = 40, gap = 10, w = floor((self.bounds.size.width - 28 - gap * (columns - 1)) / columns), head = fit.size > 12 ? 48 : 44;
    CGFloat optionW = MAX(w - 16, 120);
    // The explanations of every card of choices start at one place: past the widest title.
    CGFloat widest = 0;
    for (MMWindowRule *rule in choiceRules) for (MMWindowChoice *c in rule.choices)
        widest = MAX(widest, MMWindowWidth(MMWindowText(c.title, fit.size, NSFontWeightMedium, NSColor.whiteColor)));
    CGFloat explainX = MIN(30 + widest + 10, 130);

    NSMutableArray<NSNumber *> *need = [NSMutableArray new];
    for (NSString *key in order) {
        NSMutableArray<MMWindowOption *> *mine = [NSMutableArray new];
        CGFloat h = head;
        NSString *title = key, *note = @"";
        BOOL choices = [key hasPrefix:@"rule:"];
        if (choices) {
            MMWindowRule *rule = nil;
            for (MMWindowRule *r in choiceRules) if ([[@"rule:" stringByAppendingString:r.ruleID] isEqualToString:key]) rule = r;
            title = rule.title; note = rule.note ?: @"";
            for (NSInteger c = 0; c < (NSInteger)rule.choices.count; c++) {
                MMWindowOption *o = [self option:rule.choices[c].title explain:rule.choices[c].explain picked:c == rule.picked];
                o.ownerID = rule.ruleID; o.index = c; o.accent = MMWindowGroupColor(rule.ruleID);
                o.fit = fit; o.explainX = explainX; o.width = optionW;
                o.accessibilityRole = NSAccessibilityRadioButtonRole;
                o.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", rule.title, o.label, o.explain];
                [mine addObject:o];
                h += o.wanted + (c ? fit.gap : 0);
            }
            h += note.length ? WrappedHeight(Wrapped(note, fit.size - 1, NSFontWeightRegular, NSColor.whiteColor), w - 32) + 14 + 10 : 12;
        } else if ([key isEqualToString:MMWindowCleanupCard]) {
            // One switch a rule. Its sentence says what it does on, and the rule's own note follows it.
            for (MMWindowRule *rule in switchRules) {
                BOOL on = MMWindowRuleIsOn(rule.ruleID, rule.picked);
                NSString *explain = MMWindowRuleSwitchNote(rule.ruleID, rule.picked) ?: @"";
                if (rule.note.length) explain = [NSString stringWithFormat:@"%@ %@", explain, rule.note];
                MMWindowOption *o = [self option:MMWindowRuleSwitchTitle(rule.ruleID) explain:explain picked:on];
                o.isSwitch = YES; o.ownerID = [@"rule:" stringByAppendingString:rule.ruleID]; o.fit = fit; o.width = optionW;
                o.accessibilityRole = NSAccessibilityCheckBoxRole;
                o.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", o.label, explain];
                [mine addObject:o];
                h += o.wanted + (mine.count > 1 ? 8 : 0);
            }
            h += 10;
        } else {
            for (MMWindowSwitch *sw in st.switches) {
                if (![(sw.card ?: MMWindowMacCard) isEqualToString:key]) continue;
                MMWindowOption *o = [self option:sw.title explain:sw.note ?: @"" picked:sw.on];
                o.isSwitch = YES; o.ownerID = sw.switchID; o.fit = fit; o.width = optionW;
                // A switch that changes nothing here takes no press, and VoiceOver reads it as dimmed with its reason.
                o.inert = sw.inert; o.enabled = !sw.inert;
                o.accessibilityRole = NSAccessibilityCheckBoxRole;
                o.accessibilityLabel = sw.note.length ? [NSString stringWithFormat:@"%@. %@", sw.title, sw.note] : sw.title;
                [mine addObject:o];
                h += o.wanted + (mine.count > 1 ? 8 : 0);
            }
            h += 10;
        }
        [titles addObject:title ?: @""]; [notes addObject:note];
        [held addObject:mine]; [radio addObject:@(choices)]; [need addObject:@(ceil(h))];
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
        [_cardTitles addObject:titles[i]]; [_cardNotes addObject:notes[i]]; [_cardRadio addObject:radio[i]];
        NSArray<MMWindowOption *> *mine = held[i];
        if (!radio[i].boolValue) {
            // A card of switches: its panels stand one under the other from the top, each as tall as its words, and
            // share what is left only up to a calm height, so a card with room keeps its switches together.
            CGFloat left = NSMaxY(card) - 10 - card.origin.y - head - 8 * ((CGFloat)mine.count - 1), most = 0;
            for (MMWindowOption *o in mine) { left -= o.wanted; most = MAX(most, o.wanted); }
            CGFloat more = MIN(MAX(floor(left / MAX((CGFloat)mine.count, 1)), 0), 18), y = card.origin.y + head;
            for (MMWindowOption *o in mine) { CGFloat oh = o.wanted + more; o.frame = NSMakeRect(card.origin.x + 8, y, optionW, oh); y += oh + 8; }
            continue;
        }
        // What a card of choices has beyond its need goes between its choices, up to a calm distance. The cards of one
        // row take the same distance, the least of theirs, so their first choices stand level. The rest is its foot.
        CGFloat apart = 14;
        for (NSInteger j = r * columns; j < MIN(n, (r + 1) * columns); j++)
            if (radio[j].boolValue) apart = MIN(apart, floor(MAX(0, h - need[j].doubleValue) / MAX((CGFloat)held[j].count, 1)));
        CGFloat y = card.origin.y + head + floor(apart / 2);
        for (MMWindowOption *o in mine) {
            CGFloat oh = o.wanted;
            o.frame = NSMakeRect(card.origin.x + 8, y, optionW, oh);
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
    if (o.isSwitch && [o.ownerID hasPrefix:@"rule:"]) {
        // A rule's switch: on turns it to the mode that acts on its own, off to Off.
        NSString *ruleID = [o.ownerID substringFromIndex:5];
        NSInteger choice = o.picked ? 0 : MMWindowRuleOnChoice(ruleID);
        for (MMWindowRule *r in self.settings.rules) if ([r.ruleID isEqualToString:ruleID]) r.picked = choice;
        [self.host windowSetRule:ruleID picked:choice];
    } else if (o.isSwitch) {
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
        MMWindowDrawBlock(_cardTitles[i], _fit.size + 1, 11, NSFontWeightSemibold, text, card.origin.x + 16, card.origin.y + 24, card.size.width - 32, -1, 0, 32);
        if (!_cardNotes[i].length) continue;
        // What the rule would do next sits at the foot of its card.
        NSAttributedString *note = Wrapped(_cardNotes[i], _fit.size - 1, NSFontWeightRegular, t2);
        CGFloat nh = WrappedHeight(note, card.size.width - 32);
        MMWindowDrawIn(note, NSMakeRect(card.origin.x + 16, NSMaxY(card) - 14 - nh, card.size.width - 32, nh));
    }
}

@end
