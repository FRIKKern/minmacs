// Settings in place: the area under the top line turns into three cards, each with its own color and mark, so each
// reads at a glance: "Keep this Mac awake" in amber, "Clean up on its own" in green, "This Mac" in gray. A card holds
// rows as System Settings does: a small tile, a short title and the switch, one line high. A row has a second line
// only when it says a state, such as "Awake now for 2 agents". What a switch does is its tooltip and VoiceOver's help,
// not a sentence under it. That the cleanup rules still only watch is said once, in a badge on their card's head.
// The removal choice is not drawn: one line says removed things go to the Trash. A press applies at once, through the host.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kHead = 48, kRow = 44, kRowWithNote = 54, kTile = 24, kCardPad = 6;

static NSColor *RGB(CGFloat r, CGFloat g, CGFloat b) { return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }

/// Each card's color: warm for keeping awake, green for cleaning up, gray for the Mac itself.
static NSColor *CardTint(NSString *card) {
    if ([card isEqualToString:MMWindowAwakeCard]) return RGB(255, 176, 64);
    if ([card isEqualToString:MMWindowCleanupCard]) return MMWindowGroupColor(@"worktree");
    return MMWindowGroupColor(@"");
}

static NSString *CardMark(NSString *card) {
    if ([card isEqualToString:MMWindowAwakeCard]) return @"cup";
    if ([card isEqualToString:MMWindowCleanupCard]) return @"sparkles";
    return @"display";
}

static NSString *RowMark(NSString *ownerID) {
    return @{@"awake": @"sun", @"agents": @"spark", @"lid": @"laptop", @"login": @"power", @"rule:servers": @"server",
             @"rule:apps": @"memory", @"rule:worktrees": @"branch", @"rule:caches": @"layers"}[ownerID ?: @""] ?: @"display";
}

/// One switch row: a real button that draws its tile, its title, its state line when it has one, and the switch.
@interface MMWindowOption : NSButton
@property (copy) NSString *label;
@property (copy, nullable) NSString *note;              // the one state line under the title, or nil
@property BOOL picked, isSwitch, inert;
@property (strong) NSColor *accent;                     // the card's color
@property (copy) NSString *ownerID, *mark;
@property NSInteger index;
@end

@implementation MMWindowOption {
    BOOL _hover;
    NSTrackingArea *_tracking;
}

- (CGFloat)wanted { return self.note.length ? kRowWithNote : kRow; }

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
    if (_hover && !self.inert) {
        [[NSColor colorWithWhite:1 alpha:0.04] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:b xRadius:8 yRadius:8] fill];
    }
    CGFloat mid = floor(NSMidY(b));
    MMWindowDrawSettingMark(self.mark, NSMakeRect(10, mid - kTile / 2, kTile, kTile), self.accent, NO, self.inert);
    // The switch: the knob sits right and the track fills when it is on, so the state shows in place as well as color.
    NSRect track = NSMakeRect(NSMaxX(b) - 10 - 36, mid - 10, 36, 20);
    CGFloat textX = 10 + kTile + 12, textW = NSMinX(track) - 12 - textX;
    NSColor *titleColor = MMWindowColor(self.inert ? MMWindowInkText3 : MMWindowInkText);
    if (self.note.length) {
        MMWindowDrawBlock(self.label, 13, 11, NSFontWeightMedium, titleColor, textX, mid - 8, textW, -1, 0, 18);
        MMWindowDrawBlock(self.note, 11.5, 10, NSFontWeightRegular, MMWindowColor(MMWindowInkText2), textX, mid + 9, textW, -1, 0, 16);
    } else {
        MMWindowDrawBlock(self.label, 13, 11, NSFontWeightMedium, titleColor, textX, mid, textW, -1, 0, 20);
    }
    // A switch that changes nothing here is drawn as not available: its title steps back, its track is an outline.
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
}

- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

@end

#pragma mark The cards

/// One card as laid out: its frame, title, color, mark, badge and rows, and a line of its own at its foot.
@interface MMWindowSettingsCard : NSObject
@property NSRect frame;
@property (copy) NSString *title, *mark;
@property (copy, nullable) NSString *badge, *badgeHelp, *footer;
@property (strong) NSColor *tint;
@property (strong) NSMutableArray<MMWindowOption *> *rows;
@end
@implementation MMWindowSettingsCard
@end

@implementation MMWindowSettingsView {
    NSMutableArray<MMWindowOption *> *_options;
    NSMutableArray<MMWindowSettingsCard *> *_cards;
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
    // While Settings is away nothing is built: the menu opens without paying for cards nobody sees. They are built
    // when Settings comes, before its first frame.
    if (self.hidden) { _built = nil; return; }
    // The cards are built again only when something they show changed.
    NSMutableString *sig = [NSMutableString new];
    for (MMWindowRule *r in settings.rules) [sig appendFormat:@"%@|%ld|%@;", r.ruleID, (long)r.picked, r.note ?: @""];
    for (MMWindowSwitch *s in settings.switches)
        [sig appendFormat:@"%@|%@|%@|%d|%d|%@|%@;", s.switchID, s.card, s.title, s.on, s.inert, s.note ?: @"", s.help ?: @""];
    [sig appendFormat:@"%@|%d", settings.startsIn ?: @"", MMWindowContrast()];
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

- (MMWindowSettingsCard *)card:(NSString *)title {
    MMWindowSettingsCard *c = [MMWindowSettingsCard new];
    c.title = title; c.tint = CardTint(title); c.mark = CardMark(title); c.rows = [NSMutableArray new];
    return c;
}

/// Keep this Mac awake, Clean up on its own, then This Mac. Each card is as tall as its rows. Two columns: each card
/// goes under the shorter one, so the cards stand from the top with no card stretched to fill the window.
- (void)build {
    for (NSView *v in _options) [v removeFromSuperview];
    [_options removeAllObjects]; [_cards removeAllObjects];
    [self removeAllToolTips];
    MMWindowSettings *st = self.settings;
    NSMutableDictionary<NSString *, MMWindowSettingsCard *> *byTitle = [NSMutableDictionary new];
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    MMWindowSettingsCard *(^cardFor)(NSString *) = ^MMWindowSettingsCard *(NSString *title) {
        MMWindowSettingsCard *c = byTitle[title];
        if (!c) { c = [self card:title]; byTitle[title] = c; [order addObject:title]; }
        return c;
    };
    for (MMWindowSwitch *sw in st.switches) if ([(sw.card ?: MMWindowMacCard) isEqualToString:MMWindowAwakeCard]) {
        MMWindowOption *o = [self option:sw.title note:sw.note picked:sw.on owner:sw.switchID card:cardFor(MMWindowAwakeCard)];
        o.inert = sw.inert; o.enabled = !sw.inert;
        [self explain:o help:sw.help];
    }
    // One switch a rule. The removal choice has no switch and is not drawn.
    for (MMWindowRule *rule in st.rules) {
        NSString *title = MMWindowRuleSwitchTitle(rule.ruleID);
        if (!title) continue;
        MMWindowSettingsCard *c = cardFor(MMWindowCleanupCard);
        MMWindowOption *o = [self option:title note:rule.note picked:MMWindowRuleIsOn(rule.ruleID, rule.picked)
                                   owner:[@"rule:" stringByAppendingString:rule.ruleID] card:c];
        NSString *help = MMWindowRuleSwitchNote(rule.ruleID, rule.picked);
        [self explain:o help:st.startsIn.length ? [NSString stringWithFormat:@"%@ %@.", help ?: @"", st.startsIn] : help];
        c.badge = st.startsIn; c.badgeHelp = MMWindowStartsHelp;
    }
    for (MMWindowSwitch *sw in st.switches) if (![(sw.card ?: MMWindowAwakeCard) isEqualToString:MMWindowAwakeCard]) {
        MMWindowOption *o = [self option:sw.title note:sw.note picked:sw.on owner:sw.switchID card:cardFor(sw.card ?: MMWindowMacCard)];
        o.inert = sw.inert; o.enabled = !sw.inert;
        [self explain:o help:sw.help];
    }
    // Everything MinMacs removes goes to the Trash: one line at the foot of This Mac, where the removal choice was.
    cardFor(MMWindowMacCard).footer = MMWindowTrashLine;

    CGFloat top = 44, gap = 12, w = floor((self.bounds.size.width - 28 - gap) / 2);
    CGFloat columns[2] = {top, top};
    for (NSString *title in order) {
        MMWindowSettingsCard *c = byTitle[title];
        CGFloat h = kHead + kCardPad;
        for (MMWindowOption *o in c.rows) h += o.wanted;
        if (c.footer.length) h += kRow;
        NSInteger col = columns[1] < columns[0] ? 1 : 0;
        c.frame = NSMakeRect(14 + col * (w + gap), columns[col], w, h);
        columns[col] += h + gap;
        CGFloat y = NSMinY(c.frame) + kHead;
        for (MMWindowOption *o in c.rows) {
            o.frame = NSMakeRect(NSMinX(c.frame) + kCardPad, y, w - 2 * kCardPad, o.wanted);
            y += o.wanted;
        }
        if (c.badge.length) [self addToolTipRect:[self badgeRect:c] owner:c.badgeHelp userData:NULL];
        [_cards addObject:c];
    }
    self.needsDisplay = YES;
}

- (MMWindowOption *)option:(NSString *)label note:(NSString *)note picked:(BOOL)picked owner:(NSString *)owner card:(MMWindowSettingsCard *)card {
    MMWindowOption *o = [[MMWindowOption alloc] initWithFrame:NSZeroRect];
    o.title = @""; o.bordered = NO;
    [o setButtonType:NSButtonTypeMomentaryChange];
    o.label = label; o.note = note; o.picked = picked; o.isSwitch = YES; o.ownerID = owner;
    o.accent = card.tint; o.mark = RowMark(owner);
    o.accessibilityRole = NSAccessibilityCheckBoxRole;
    o.accessibilityValue = picked ? @1 : @0;
    o.accessibilityLabel = note.length ? [NSString stringWithFormat:@"%@. %@", label, note] : label;
    o.target = self; o.action = @selector(pressed:);
    [self addSubview:o];
    [_options addObject:o];
    [card.rows addObject:o];
    return o;
}

/// What a switch does is not drawn: it is the row's tooltip and what VoiceOver says after its name.
- (void)explain:(MMWindowOption *)o help:(NSString *)help {
    if (!help.length) return;
    o.toolTip = help;
    o.accessibilityHelp = help;
}

- (NSRect)badgeRect:(MMWindowSettingsCard *)c {
    CGFloat bw = ceil(MMWindowWidth(MMWindowText(c.badge, 11.5, NSFontWeightSemibold, NSColor.whiteColor))) + 20;
    return NSMakeRect(NSMaxX(c.frame) - 16 - bw, NSMinY(c.frame) + kHead / 2 - 11, bw, 22);
}

/// A press shows at once and goes to the host, which applies it. The next model confirms it.
- (void)pressed:(MMWindowOption *)o {
    if ([o.ownerID hasPrefix:@"rule:"]) {
        // A rule's switch: on turns it to the mode that acts on its own, off to Off.
        NSString *ruleID = [o.ownerID substringFromIndex:5];
        NSInteger choice = o.picked ? 0 : MMWindowRuleOnChoice(ruleID);
        for (MMWindowRule *r in self.settings.rules) if ([r.ruleID isEqualToString:ruleID]) r.picked = choice;
        [self.host windowSetRule:ruleID picked:choice];
    } else {
        BOOL on = !o.picked;
        for (MMWindowSwitch *s in self.settings.switches) if ([s.switchID isEqualToString:o.ownerID]) s.on = on;
        [self.host windowSetSwitch:o.ownerID on:on];
    }
    NSString *focus = o.ownerID;
    self.settings = self.settings;
    for (MMWindowOption *n in _options) if ([n.ownerID isEqualToString:focus]) [self.window makeFirstResponder:n];
}

- (void)drawRect:(NSRect)dirty {
    BOOL hc = MMWindowContrast();
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2);
    NSAttributedString *head = MMWindowText(@"Settings", 15, NSFontWeightSemibold, NSColor.whiteColor);
    MMWindowDraw(head, 18, 20, -1);
    MMWindowDraw(MMWindowText(@"Each change applies at once.", 12, NSFontWeightRegular, t2), 18 + MMWindowWidth(head) + 12, 20.5, -1);
    for (MMWindowSettingsCard *c in _cards) {
        NSRect card = c.frame;
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(card, 0.5, 0.5) xRadius:14 yRadius:14];
        [MMWindowColor(MMWindowInkCard) setFill]; [p fill];
        // A wash of the card's color, so the three cards tell apart before a word is read.
        [[c.tint colorWithAlphaComponent:hc ? 0.07 : 0.045] setFill]; [p fill];
        [[c.tint colorWithAlphaComponent:hc ? 0.5 : 0.16] setStroke]; p.lineWidth = 1; [p stroke];
        CGFloat mid = NSMinY(card) + kHead / 2;
        MMWindowDrawSettingMark(c.mark, NSMakeRect(NSMinX(card) + 16, mid - 11, 22, 22), c.tint, YES, NO);
        CGFloat titleX = NSMinX(card) + 16 + 22 + 10, titleRight = NSMaxX(card) - 16;
        if (c.badge.length) {
            NSRect badge = [self badgeRect:c];
            [[c.tint colorWithAlphaComponent:hc ? 0.32 : 0.16] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:11 yRadius:11] fill];
            MMWindowDraw(MMWindowText(c.badge, 11.5, NSFontWeightSemibold, hc ? NSColor.whiteColor : c.tint), NSMidX(badge), NSMidY(badge), 0);
            titleRight = NSMinX(badge) - 10;
        }
        MMWindowDrawBlock(c.title, 14, 12, NSFontWeightSemibold, text, titleX, mid, titleRight - titleX, -1, 0, 22);
        // Hairlines between the rows, from under the titles to the card's edge, as System Settings draws them.
        [[NSColor colorWithWhite:1 alpha:hc ? 0.24 : 0.07] setFill];
        CGFloat lineX = NSMinX(card) + kCardPad + 10 + kTile + 12, y = NSMinY(card) + kHead;
        NSRectFillUsingOperation(NSMakeRect(NSMinX(card) + 16, y - 0.5, card.size.width - 32, 1), NSCompositingOperationSourceOver);
        for (NSUInteger i = 0; i < c.rows.count; i++) {
            y += c.rows[i].wanted;
            if (i + 1 < c.rows.count || c.footer.length)
                NSRectFillUsingOperation(NSMakeRect(lineX, y - 0.5, NSMaxX(card) - 16 - lineX, 1), NSCompositingOperationSourceOver);
        }
        if (!c.footer.length) continue;
        // The foot line is no switch: a quiet mark and the sentence, level with the rows above it.
        CGFloat fm = floor(y + kRow / 2);
        MMWindowDrawSettingMark(@"trash", NSMakeRect(NSMinX(card) + kCardPad + 10, fm - kTile / 2, kTile, kTile), c.tint, NO, NO);
        MMWindowDrawBlock(c.footer, 13, 11, NSFontWeightRegular, t2, lineX, fm, NSMaxX(card) - 16 - lineX, -1, 0, 20);
    }
}

@end
