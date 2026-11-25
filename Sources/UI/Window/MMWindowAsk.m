// Ask MinMacs in the middle of the window, MMWindowParts.h: the one-line field at its foot, and an answer in the log's
// place. Both draw what the model holds and nothing else: no disk, no query, no model call. A press on the answer's
// button goes to the window's host, which runs the keep or the restore the rest of MinMacs uses: nothing here acts.
// Only whole entries stand in an answer, no text is cut and none ends on an ellipsis, DESIGN.md rule 8.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kSide = 14, kTop = 10, kFoot = 22, kGap = 9, kWheel = 26;
static const CGFloat kPill = 28, kLink = 17, kButton = 24;

#pragma mark - The field

@interface MMWindowAskText : NSTextField
@end
@implementation MMWindowAskText
- (BOOL)becomeFirstResponder { BOOL ok = [super becomeFirstResponder]; self.superview.needsDisplay = YES; return ok; }
- (void)textDidEndEditing:(NSNotification *)n { [super textDidEndEditing:n]; self.superview.needsDisplay = YES; }
/// Tab reaches it while the window takes presses, as it reaches the window's buttons.
- (BOOL)canBecomeKeyView { return self.isEditable && MMWindowTakesPresses(self); }
@end

@interface MMWindowAskBar () <NSTextFieldDelegate>
@end

@implementation MMWindowAskBar

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _field = [MMWindowAskText new];
        _field.bezeled = NO; _field.bordered = NO; _field.drawsBackground = NO;
        _field.focusRingType = NSFocusRingTypeNone;
        _field.font = MMWindowFont(12.5, NSFontWeightRegular);
        _field.textColor = NSColor.whiteColor;
        _field.usesSingleLineMode = YES;
        _field.cell.scrollable = YES; _field.cell.wraps = NO;
        _field.placeholderAttributedString = MMWindowText(MMWindowAskTitle, 12.5, NSFontWeightRegular, MMWindowColor(MMWindowInkText3));
        _field.delegate = self;
        _field.accessibilityLabel = MMWindowAskTitle;
        _field.accessibilityHelp = @"Type a question and press Return. MinMacs answers from what it knows, asks Claude what it cannot, and acts on nothing.";
        _field.toolTip = @"Ask what MinMacs did, would do or knows. Return asks, Escape clears.";
        [self addSubview:_field];
        [self layField];
    }
    return self;
}

- (NSRect)pill { return NSMakeRect(kSide, 8, self.bounds.size.width - 2 * kSide, kPill); }
- (void)layField { NSRect p = [self pill]; _field.frame = NSMakeRect(NSMinX(p) + 12, round(NSMidY(p) - 9), p.size.width - 24, 18); }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self layField]; }

- (BOOL)focused {
    NSText *editor = _field.currentEditor;
    return editor && self.window.firstResponder == editor;
}

- (void)mouseDown:(NSEvent *)e { [self.window makeFirstResponder:_field]; }

- (void)typeKey:(NSEvent *)key {
    if (![self.window makeFirstResponder:_field]) return;
    NSText *editor = _field.currentEditor;
    editor.selectedRange = NSMakeRange(editor.string.length, 0);
    [editor keyDown:key];
}

- (void)rest {
    if (self.focused) {
        NSView *top = self;
        while (top.superview) top = top.superview;
        [self.window makeFirstResponder:top];
    }
    _field.stringValue = @"";
    self.needsDisplay = YES;
}

/// Return asks and Escape clears: the field editor's commands, so an input method that is composing keeps its own
/// Return and Escape, and the question goes only once it is written.
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)command {
    if (command == @selector(insertNewline:)) {
        NSString *q = [_field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (q.length && self.onAsk) { _field.stringValue = @""; self.onAsk(q); }
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        if (_field.stringValue.length) _field.stringValue = @"";
        else if (self.onEscape) self.onEscape();
        return YES;
    }
    return NO;
}

- (void)drawRect:(NSRect)dirty {
    NSRect p = [self pill];
    BOOL on = self.focused, contrast = MMWindowContrast();
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(p, 0.5, 0.5) xRadius:kPill / 2 - 0.5 yRadius:kPill / 2 - 0.5];
    [[NSColor colorWithWhite:1 alpha:contrast ? 0.12 : on ? 0.09 : 0.06] setFill]; [pill fill];
    [[NSColor colorWithWhite:1 alpha:contrast ? (on ? 0.85 : 0.5) : on ? 0.36 : 0.14] setStroke];
    pill.lineWidth = on ? 1.5 : 1; [pill stroke];
}

@end

#pragma mark - The answer

/// Where one shown entry stands, worked out once for drawing and the presses alike.
@interface MMWindowAnswerPlace : NSObject
@property NSInteger index;
@property CGFloat top, bottom;
@end
@implementation MMWindowAnswerPlace
@end

@implementation MMWindowAnswerView {
    NSMutableArray<MMWindowButton *> *_buttons;      // every press of the answer that shows
    NSMutableArray<NSString *> *_lines;
    CGFloat _wheel;
}

- (BOOL)isFlipped { return YES; }
- (CGFloat)width { return self.bounds.size.width - 2 * kSide; }
- (NSArray<MMWindowButton *> *)presses { return [_buttons copy] ?: @[]; }
- (NSArray<NSString *> *)drawnLines { return [_lines copy] ?: @[]; }

- (void)setAnswer:(MMWindowAnswer *)answer {
    if (_answer == answer) return;
    if (answer.serial != _answer.serial) _first = 0;
    _answer = answer;
    [self moved];
}
- (void)setFirst:(NSInteger)first {
    NSInteger f = MIN(MAX(first, 0), MAX((NSInteger)self.answer.entries.count - 1, 0));
    if (f == _first) return;
    _first = f; [self moved];
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self moved]; }
- (void)moved { [self placePresses]; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)e {}

static CGFloat Width(NSString *title, CGFloat size, NSFontWeight weight) { return ceil(MMWindowWidth(MMWindowText(title, size, weight, NSColor.whiteColor))); }
static CGFloat BackWidth(void) { return Width(MMWindowAskBack, 10.5, NSFontWeightSemibold) + 14; }

/// The top part, from the question to the button or the examples, with each press's rect. Drawn when draw is YES.
- (CGFloat)head:(BOOL)draw suggest:(NSRect *)suggest examples:(NSMutableArray<NSValue *> *)examples {
    MMWindowAnswer *a = self.answer;
    CGFloat x = kSide, w = self.width, y = kTop;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSString *asked = [NSString stringWithFormat:@"You asked “%@”", a.question];
    CGFloat qw = w - BackWidth() - 10;
    y += draw ? MMWindowDrawBlock(asked, 11, 11, NSFontWeightRegular, t3, x, y, qw, -1, -1, 0) : MMWindowBlockHeight(asked, 11, 11, NSFontWeightRegular, qw);
    y = MAX(y, kTop + kLink) + 8;
    y += draw ? MMWindowDrawBlock(a.answer, 13, 13, NSFontWeightMedium, text, x, y, w, -1, -1, 0) : MMWindowBlockHeight(a.answer, 13, 13, NSFontWeightMedium, w);
    // Who answered and what it took, in quiet type: "Answered by Claude · 1,240 tokens".
    if (a.byline.length) { y += 5; y += draw ? MMWindowDrawBlock(a.byline, 10.5, 10.5, NSFontWeightRegular, t3, x, y, w, -1, -1, 0) : MMWindowBlockHeight(a.byline, 10.5, 10.5, NSFontWeightRegular, w); }
    MMWindowSuggest *s = a.suggest;
    if (s) {
        y += 10;
        if (s.note.length) y += draw ? MMWindowDrawBlock(s.note, 11.5, 11.5, NSFontWeightRegular, t2, x, y, w, -1, -1, 0) : MMWindowBlockHeight(s.note, 11.5, 11.5, NSFontWeightRegular, w);
        else { if (suggest) *suggest = NSMakeRect(x, y, MIN(Width(s.title, 12, NSFontWeightRegular) + 28, w), kButton); y += kButton; }
    }
    if (a.examples.count) {
        y += 12;
        NSString *try = @"It can answer questions like these:";
        y += (draw ? MMWindowDrawBlock(try, 11, 11, NSFontWeightRegular, t3, x, y, w, -1, -1, 0) : MMWindowBlockHeight(try, 11, 11, NSFontWeightRegular, w)) + 6;
        for (NSString *e in a.examples) {
            CGFloat ew = Width(e, 10.5, NSFontWeightSemibold) + 14;
            if (ew > w) continue;                    // a press never holds a cut text
            [examples addObject:[NSValue valueWithRect:NSMakeRect(x, y, ew, kLink)]];
            y += kLink + 6;
        }
    }
    return y + 14;
}

- (CGFloat)heightOf:(MMWindowAnswerEntry *)e {
    CGFloat w = self.width, h = MMWindowBlockHeight(e.sentence, 12, 12, NSFontWeightRegular, w);
    if (e.why.length) h += 2 + MMWindowBlockHeight(e.why, 11, 11, NSFontWeightRegular, w);
    if (e.detail.length) h += 2 + MMWindowBlockHeight(e.detail, 10.5, 10.5, NSFontWeightRegular, w);
    return h + kGap;
}

/// The whole entries that fit under the head from the first one shown.
- (NSArray<MMWindowAnswerPlace *> *)places {
    NSMutableArray *out = [NSMutableArray new];
    NSArray<MMWindowAnswerEntry *> *entries = self.answer.entries;
    CGFloat y = [self head:NO suggest:NULL examples:nil], bottom = self.bounds.size.height - kFoot;
    for (NSInteger i = MIN(_first, (NSInteger)entries.count); i < (NSInteger)entries.count; i++) {
        CGFloat h = [self heightOf:entries[(NSUInteger)i]];
        if (y + h - kGap > bottom) break;
        MMWindowAnswerPlace *p = [MMWindowAnswerPlace new];
        p.index = i; p.top = y; p.bottom = y + h - kGap;
        [out addObject:p];
        y += h;
    }
    return out;
}

- (MMWindowButton *)press:(MMWindowButtonKind)kind title:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    MMWindowButton *b = [MMWindowButton kind:kind title:title target:self action:action];
    b.frame = frame;
    __weak typeof(self) me = self;
    b.onHover = ^{ me.needsDisplay = YES; };
    [self addSubview:b]; [_buttons addObject:b];
    return b;
}

/// Back to the log, the answer's button or the examples, and a press for each shown entry that leads somewhere. Real
/// buttons, so Tab, Space and VoiceOver reach them, in the order they are read.
- (void)placePresses {
    BOOL had = NO;
    for (MMWindowButton *b in _buttons) { if (self.window.firstResponder == b) had = YES; [b removeFromSuperview]; }
    if (had) { NSView *top = self; while (top.superview) top = top.superview; [self.window makeFirstResponder:top]; }
    _buttons = [NSMutableArray new]; _backButton = nil; _suggestButton = nil;
    [self removeAllToolTips];
    MMWindowAnswer *a = self.answer;
    if (!a) return;
    CGFloat w = self.width;
    _backButton = [self press:MMWindowButtonLink title:MMWindowAskBack action:@selector(pressBack:) frame:NSMakeRect(kSide + w - BackWidth(), kTop - 1, BackWidth(), kLink)];
    _backButton.toolTip = _backButton.accessibilityHelp = @"Shows the log again. Escape does it too.";
    NSRect s = NSZeroRect;
    NSMutableArray<NSValue *> *examples = [NSMutableArray new];
    [self head:NO suggest:&s examples:examples];
    if (!NSIsEmptyRect(s)) {
        _suggestButton = [self press:MMWindowButtonOutline title:a.suggest.title action:@selector(pressSuggest:) frame:s];
        _suggestButton.toolTip = _suggestButton.accessibilityHelp = a.suggest.help;
    }
    for (NSUInteger i = 0; i < examples.count; i++) {
        NSString *q = a.examples[i];
        MMWindowButton *b = [self press:MMWindowButtonLink title:q action:@selector(pressExample:) frame:examples[i].rectValue];
        b.identifier = q;
        b.accessibilityLabel = [@"Ask: " stringByAppendingString:q];
    }
    for (MMWindowAnswerPlace *p in [self places]) {
        MMWindowAnswerEntry *e = a.entries[(NSUInteger)p.index];
        if (!e.row.length && !e.logKey.length) continue;
        MMWindowButton *b = [self press:MMWindowButtonClear title:e.sentence action:@selector(pressEntry:) frame:NSMakeRect(kSide - 6, p.top - 3, w + 12, p.bottom - p.top + 6)];
        b.tag = p.index;
        b.accessibilityLabel = [@[e.sentence, e.why ?: @"", e.detail ?: @""] componentsJoinedByString:@" "];
        b.toolTip = b.accessibilityHelp = e.row.length ? @"Shows its story, and makes it the active row." : @"Shows this entry in the log.";
    }
    if (self.window) [self.window recalculateKeyViewLoop];
}

- (void)pressBack:(id)sender { if (self.onBack) self.onBack(); }
- (void)pressSuggest:(id)sender { MMWindowSuggest *s = self.answer.suggest; if (s && !s.note.length && self.onSuggest) self.onSuggest(s); }
- (void)pressExample:(MMWindowButton *)b { if (b.identifier.length && self.onAsk) self.onAsk(b.identifier); }
- (void)pressEntry:(MMWindowButton *)b {
    NSArray<MMWindowAnswerEntry *> *entries = self.answer.entries;
    if (b.tag < 0 || b.tag >= (NSInteger)entries.count) return;
    MMWindowAnswerEntry *e = entries[(NSUInteger)b.tag];
    if (e.row.length) { if (self.onRow) self.onRow(e.row); }
    else if (e.logKey.length && self.onLog) self.onLog(e.logKey);
}

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    _lines = [NSMutableArray new];
    MMWindowAnswer *a = self.answer;
    if (!a) return;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    CGFloat x = kSide, w = self.width;
    [self head:YES suggest:NULL examples:nil];
    [_lines addObject:a.answer];
    NSArray<MMWindowAnswerPlace *> *places = [self places];
    for (MMWindowAnswerPlace *p in places) {
        MMWindowAnswerEntry *e = a.entries[(NSUInteger)p.index];
        for (MMWindowButton *b in _buttons) if (b.kind == MMWindowButtonClear && b.tag == p.index && b.hovered) {
            [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.15 : 0.07] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:b.frame xRadius:6 yRadius:6] fill];
        }
        CGFloat y = p.top;
        y += MMWindowDrawBlock(e.sentence, 12, 12, NSFontWeightRegular, text, x, y, w, -1, -1, 0);
        if (e.why.length) y += 2 + MMWindowDrawBlock(e.why, 11, 11, NSFontWeightRegular, t2, x, y + 2, w, -1, -1, 0);
        if (e.detail.length) MMWindowDrawBlock(e.detail, 10.5, 10.5, NSFontWeightRegular, t3, x, y + 2, w, -1, -1, 0);
        [_lines addObject:e.sentence];
    }
    NSInteger shown = (NSInteger)places.count, first = MIN(_first, (NSInteger)a.entries.count);
    NSString *foot = MMWindowMoreLine((NSInteger)a.entries.count - first - shown, first);
    if (foot) MMWindowDraw(MMWindowText(foot, 10.5, NSFontWeightRegular, t3), x, self.bounds.size.height - kFoot / 2, -1);
}

- (void)scrollWheel:(NSEvent *)e {
    if (self.answer.entries.count < 2) return;
    CGFloat step = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * kWheel;
    _wheel -= step;
    NSInteger move = (NSInteger)(_wheel / kWheel);
    if (!move) return;
    _wheel -= move * kWheel;
    NSInteger before = _first;
    self.first = _first + move;
    if (_first == before) _wheel = 0;
}

- (BOOL)isAccessibilityElement { return NO; }
/// The question and the answer as text, then each press in the order it is read.
- (NSArray *)accessibilityChildren {
    NSMutableArray *out = [NSMutableArray new];
    if (!self.answer) return out;
    NSString *said = [NSString stringWithFormat:@"You asked %@. %@", self.answer.question, self.answer.answer];
    if (self.answer.byline.length) said = [NSString stringWithFormat:@"%@ %@.", said, self.answer.byline];
    if (self.answer.suggest.note.length) said = [NSString stringWithFormat:@"%@ %@", said, self.answer.suggest.note];
    [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:NSZeroRect label:said parent:self]];
    [out addObjectsFromArray:_buttons];
    return out;
}

@end

#pragma mark - The middle

@implementation MMWindowMiddleView (Ask)

- (NSRect)askFrame { return NSMakeRect(0, MAX(self.bounds.size.height - MMWindowAskBand, 0), self.bounds.size.width, MMWindowAskBand); }

- (void)makeAsk {
    self.answerView.hidden = YES;
    [self addSubview:self.answerView]; [self addSubview:self.askBar];
    [self placeAsk];
}

- (void)placeAsk { self.askBar.frame = [self askFrame]; self.answerView.frame = self.logView.frame; }

- (BOOL)showsAnswer { return !self.answerView.hidden; }

- (void)showAnswer {
    MMWindowAnswer *a = self.model.answer;
    // Under a story the answer keeps its place and its presses, hidden, so it is back as it was when the story goes.
    BOOL story = self.row != nil, kept = a && a.serial != self.putAway;
    self.answerView.answer = kept ? a : nil;
    self.answerView.hidden = !kept || story;
    self.logView.hidden = story || kept;
}

- (CGFloat)storyBottom { return self.bounds.size.height - 8 - MMWindowAskBand; }

@end
