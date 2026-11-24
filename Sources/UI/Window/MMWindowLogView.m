// The log under the middle's strip, MMWindowParts.h: what MinMacs did and decided, and each setting that changed,
// newest first and grouped by day. It draws what the model's log holds and nothing else: no disk, no query.
// Only whole entries stand in it, so no text is ever cut by its edge, DESIGN.md rule 8: the fingers move it an
// entry at a time, and its foot says how many wait above and below. An entry keeps one type size and wraps, so the
// entries of a list read alike.
// An entry whose record can still be taken back has an Undo press at the right of its quiet line: a real button, so
// Tab, Space, a tooltip and VoiceOver come with it. A press goes to onUndo with the record's rid, and nothing else
// here acts. An entry with more to say, such as what a run skipped, has it as its tooltip and in what VoiceOver reads.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kSide = 14, kTop = 10, kFoot = 22, kGap = 9, kDay = 22;
static const CGFloat kSentence = 12, kDetail = 10.5;
static const CGFloat kWheel = 26;                     // how far the fingers move for one entry
static const CGFloat kUndoGap = 8, kUndoPad = 7, kUndoHigh = 17;

/// Where one shown entry stands, worked out once for drawing, the presses and VoiceOver alike.
@interface MMWindowLogPlace : NSObject
@property NSInteger index;
@property BOOL header;
@property CGFloat top, textTop, bottom;               // the entry with its day, its sentence, and its foot
@property NSRect undo;                                // the press, or NSZeroRect
@end
@implementation MMWindowLogPlace
@end

@implementation MMWindowLogView {
    CGFloat _wheel;                                   // what the fingers moved since the last whole entry
    NSMutableArray<NSString *> *_drawn;
    NSMutableArray<NSArray *> *_spoken;               // each shown entry's words and rect, for VoiceOver
    NSMutableDictionary<NSString *, MMWindowButton *> *_undos;   // the shown presses, by entry key
    NSString *_foot;
}

- (NSArray<NSString *> *)drawnSentences { return [_drawn copy] ?: @[]; }
- (NSString *)footLine { return _foot; }
- (NSArray<MMWindowButton *> *)undoButtons {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowLogPlace *p in [self places]) {
        MMWindowButton *b = _undos[self.log.entries[(NSUInteger)p.index].key];
        if (b) [out addObject:b];
    }
    return out;
}

- (void)setLog:(MMWindowLog *)log {
    if (_log == log) return;
    // The entry at the top stays where it was when it is still there, so a new log does not move what is read.
    NSString *top = _first > 0 && _first < (NSInteger)_log.entries.count ? _log.entries[(NSUInteger)_first].key : nil;
    _log = log;
    NSInteger at = 0;
    if (top) for (NSInteger i = 0; i < (NSInteger)log.entries.count; i++) if ([log.entries[(NSUInteger)i].key isEqualToString:top]) { at = i; break; }
    _first = MIN(at, [self lastFirst]);
    [self moved];
}

- (void)setFirst:(NSInteger)first {
    NSInteger f = MIN(MAX(first, 0), [self lastFirst]);
    if (f == _first) return;
    _first = f;
    [self moved];
}

- (void)rest { _first = 0; _wheel = 0; [self moved]; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self moved]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self moved]; }

/// What shows changed: the presses, the tooltips and what VoiceOver reads follow, then the drawing.
- (void)moved { [self placePresses]; self.needsDisplay = YES; }

- (CGFloat)width { return self.bounds.size.width - 2 * kSide; }

/// The Undo press of an entry: its width, or 0 for an entry with none.
- (CGFloat)undoWidth:(MMWindowLogEntry *)e {
    if (!e.canUndo || !e.undoRid.length) return 0;
    return ceil(MMWindowWidth(MMWindowText(@"Undo", kDetail, NSFontWeightSemibold, NSColor.whiteColor))) + 2 * kUndoPad;
}

/// The quiet line wraps short of the press, so the two never meet.
- (CGFloat)detailWidth:(MMWindowLogEntry *)e {
    CGFloat u = [self undoWidth:e];
    return u > 0 ? self.width - u - kUndoGap : self.width;
}

/// Where the entries start: under the note, when there is one.
- (CGFloat)entriesTop {
    NSString *note = self.log.note;
    if (!note.length) return kTop;
    CGFloat size = self.log.entries.count ? 11 : 12;
    return kTop + MMWindowBlockHeight(note, size, 10, NSFontWeightRegular, self.width) + 14;
}

- (CGFloat)heightOf:(NSInteger)i header:(BOOL)header {
    MMWindowLogEntry *e = self.log.entries[(NSUInteger)i];
    return (header ? kDay : 0) + MMWindowBlockHeight(e.sentence, kSentence, kSentence, NSFontWeightRegular, self.width) + 2
         + MAX(MMWindowBlockHeight(e.detail, kDetail, kDetail, NSFontWeightRegular, [self detailWidth:e]), [self undoWidth:e] > 0 ? kUndoHigh - 2 : 0) + kGap;
}

- (BOOL)headerAt:(NSInteger)i from:(NSInteger)first {
    return i == first || ![self.log.entries[(NSUInteger)i].day isEqualToString:self.log.entries[(NSUInteger)i - 1].day];
}

/// The last entry that may stand at the top: from it on, every entry fits. Found from the end, a view's height at most.
- (NSInteger)lastFirst {
    NSInteger n = (NSInteger)self.log.entries.count;
    if (n < 2) return 0;
    CGFloat room = self.bounds.size.height - kFoot - [self entriesTop];
    for (NSInteger f = n - 1; f > 0; f--) {
        CGFloat h = 0;
        for (NSInteger i = f; i < n; i++) h += [self heightOf:i header:[self headerAt:i from:f]];
        if (h > room) return MIN(f + 1, n - 1);
    }
    return 0;
}

/// The whole entries that fit from the first one shown, and where each stands.
- (NSArray<MMWindowLogPlace *> *)places {
    NSMutableArray<MMWindowLogPlace *> *out = [NSMutableArray new];
    NSArray<MMWindowLogEntry *> *entries = self.log.entries;
    if (!self.log) return out;
    CGFloat y = [self entriesTop], bottom = self.bounds.size.height - kFoot, w = self.width;
    NSInteger first = MIN(_first, (NSInteger)entries.count);
    for (NSInteger i = first; i < (NSInteger)entries.count; i++) {
        MMWindowLogEntry *e = entries[(NSUInteger)i];
        BOOL header = [self headerAt:i from:first];
        CGFloat h = [self heightOf:i header:header];
        if (y + h - kGap > bottom) break;
        MMWindowLogPlace *p = [MMWindowLogPlace new];
        p.index = i; p.header = header; p.top = y;
        p.textTop = y + (header ? kDay : 0);
        p.bottom = y + h - kGap;
        CGFloat u = [self undoWidth:e];
        if (u > 0) {
            // Level with the quiet line's first line, at the right of the log.
            CGFloat detailTop = p.textTop + MMWindowBlockHeight(e.sentence, kSentence, kSentence, NSFontWeightRegular, w) + 2;
            CGFloat mid = detailTop + MMWindowLineHeight(kDetail) / 2;
            p.undo = NSMakeRect(kSide + w - u, round(mid - kUndoHigh / 2), u, kUndoHigh);
        }
        [out addObject:p];
        y += h;
    }
    return out;
}

/// The Undo presses of the entries that show, a tooltip for each entry with more to say, and VoiceOver's words.
/// A press is kept by its entry's key, so the keyboard stays on it while the log moves.
- (void)placePresses {
    if (!_undos) _undos = [NSMutableDictionary new];
    [self removeAllToolTips];
    _spoken = [NSMutableArray new];
    NSMutableSet<NSString *> *shown = [NSMutableSet new];
    CGFloat x = kSide, w = self.width;
    for (MMWindowLogPlace *p in [self places]) {
        MMWindowLogEntry *e = self.log.entries[(NSUInteger)p.index];
        NSRect rect = NSMakeRect(x, p.top, w, p.bottom - p.top);
        if (e.more.length) [self addToolTipRect:rect owner:e.more userData:NULL];
        NSString *words = [NSString stringWithFormat:@"%@, %@, %@", e.day, e.sentence, e.detail];
        if (e.more.length) words = [NSString stringWithFormat:@"%@. %@", words, e.more];
        [_spoken addObject:@[words, [NSValue valueWithRect:rect]]];
        if (NSIsEmptyRect(p.undo)) continue;
        MMWindowButton *b = _undos[e.key];
        if (!b) {
            b = [MMWindowButton kind:MMWindowButtonLink title:@"Undo" target:self action:@selector(pressUndo:)];
            _undos[e.key] = b;
            [self addSubview:b];
        }
        b.identifier = e.undoRid;
        b.frame = p.undo;
        NSString *what = [e.sentence componentsSeparatedByString:@". "].firstObject ?: e.sentence;
        if ([what hasSuffix:@"."]) what = [what substringToIndex:what.length - 1];
        b.accessibilityLabel = [@"Undo: " stringByAppendingString:what];
        b.toolTip = e.undoHelp;
        b.accessibilityHelp = e.undoHelp;
        [shown addObject:e.key];
    }
    for (NSString *key in _undos.allKeys) {
        if ([shown containsObject:key]) continue;
        MMWindowButton *b = _undos[key];
        // A press that leaves while it holds the keyboard hands it to the window, so Escape and Tab still work.
        if (self.window.firstResponder == b) {
            NSView *top = self;
            while (top.superview) top = top.superview;
            [self.window makeFirstResponder:top];
        }
        [b removeFromSuperview];
        [_undos removeObjectForKey:key];
    }
    if (self.window) [self.window recalculateKeyViewLoop];
}

- (void)pressUndo:(MMWindowButton *)b {
    NSString *rid = b.identifier;
    if (rid.length && self.onUndo) self.onUndo(rid);
}

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    _drawn = [NSMutableArray new]; _foot = nil;
    MMWindowLog *log = self.log;
    if (!log) return;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    CGFloat x = kSide, w = self.width;
    NSArray<MMWindowLogEntry *> *entries = log.entries;
    if (log.note.length) {
        // With no entry the note is what the log says, so it stands a size larger.
        CGFloat size = entries.count ? 11 : 12;
        MMWindowDrawBlock(log.note, size, 10, NSFontWeightRegular, entries.count ? t3 : t2, x, kTop, w, -1, -1, 0);
    }
    NSArray<MMWindowLogPlace *> *places = [self places];
    NSInteger first = MIN(_first, (NSInteger)entries.count);
    for (MMWindowLogPlace *p in places) {
        MMWindowLogEntry *e = entries[(NSUInteger)p.index];
        if (p.header) MMWindowDraw(MMWindowText(e.day, 11, NSFontWeightSemibold, t2), x, p.top + (p.index > first ? 4 : 0) + 7, -1);
        CGFloat y = p.textTop;
        y += MMWindowDrawBlock(e.sentence, kSentence, kSentence, NSFontWeightRegular, text, x, y, w, -1, -1, 0) + 2;
        MMWindowDrawBlock(e.detail, kDetail, kDetail, NSFontWeightRegular, t3, x, y, [self detailWidth:e], -1, -1, 0);
        [_drawn addObject:e.sentence];
    }
    NSInteger below = (NSInteger)entries.count - first - (NSInteger)places.count;
    _foot = MMWindowMoreLine(below, first);
    if (_foot) MMWindowDraw(MMWindowText(_foot, 10.5, NSFontWeightRegular, t3), x, self.bounds.size.height - kFoot / 2, -1);
}

#pragma mark Scrolling

- (void)scrollWheel:(NSEvent *)e {
    if (!self.log.entries.count) return;
    CGFloat step = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * kWheel;
    _wheel -= step;
    NSInteger move = (NSInteger)(_wheel / kWheel);
    if (!move) return;
    _wheel -= move * kWheel;
    NSInteger before = _first;
    self.first = _first + move;
    if (_first == before) _wheel = 0;
}

#pragma mark Accessibility

- (BOOL)isAccessibilityElement { return NO; }
/// Each shown entry's words, with its Undo press right after it, then the foot.
- (NSArray *)accessibilityChildren {
    NSMutableArray *out = [NSMutableArray new];
    NSArray<MMWindowLogPlace *> *places = [self places];
    for (NSUInteger i = 0; i < _spoken.count; i++) {
        NSArray *s = _spoken[i];
        NSRect screen = self.window ? NSAccessibilityFrameInView(self, [s[1] rectValue]) : NSZeroRect;
        [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen label:s[0] parent:self]];
        MMWindowButton *b = i < places.count ? _undos[self.log.entries[(NSUInteger)places[i].index].key] : nil;
        if (b) [out addObject:b];
    }
    if (_foot) [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:NSZeroRect label:_foot parent:self]];
    return out;
}

@end
