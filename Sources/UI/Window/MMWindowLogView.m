// The log under the middle's strip, MMWindowParts.h: what MinMacs did and decided, and each setting that changed,
// newest first and grouped by day. It draws what the model's log holds and nothing else: no disk, no query.
// Only whole entries stand in it, so no text is ever cut by its edge, DESIGN.md rule 8: the fingers move it an
// entry at a time, and its foot says how many wait above and below. An entry keeps one type size and wraps, so the
// entries of a list read alike.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kSide = 14, kTop = 10, kFoot = 22, kGap = 9, kDay = 22;
static const CGFloat kSentence = 12, kDetail = 10.5;
static const CGFloat kWheel = 26;                     // how far the fingers move for one entry

@implementation MMWindowLogView {
    CGFloat _wheel;                                   // what the fingers moved since the last whole entry
    NSMutableArray<NSString *> *_drawn;
    NSMutableArray<NSArray *> *_spoken;               // each drawn entry's words and rect, for VoiceOver
    NSString *_foot;
}

- (NSArray<NSString *> *)drawnSentences { return [_drawn copy] ?: @[]; }
- (NSString *)footLine { return _foot; }

- (void)setLog:(MMWindowLog *)log {
    if (_log == log) return;
    // The entry at the top stays where it was when it is still there, so a new log does not move what is read.
    NSString *top = _first > 0 && _first < (NSInteger)_log.entries.count ? _log.entries[(NSUInteger)_first].key : nil;
    _log = log;
    NSInteger at = 0;
    if (top) for (NSInteger i = 0; i < (NSInteger)log.entries.count; i++) if ([log.entries[(NSUInteger)i].key isEqualToString:top]) { at = i; break; }
    _first = MIN(at, [self lastFirst]);
    self.needsDisplay = YES;
}

- (void)setFirst:(NSInteger)first {
    NSInteger f = MIN(MAX(first, 0), [self lastFirst]);
    if (f == _first) return;
    _first = f;
    self.needsDisplay = YES;
}

- (void)rest { _first = 0; _wheel = 0; self.needsDisplay = YES; }

- (CGFloat)width { return self.bounds.size.width - 2 * kSide; }

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
         + MMWindowBlockHeight(e.detail, kDetail, kDetail, NSFontWeightRegular, self.width) + kGap;
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

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    _drawn = [NSMutableArray new]; _spoken = [NSMutableArray new]; _foot = nil;
    MMWindowLog *log = self.log;
    if (!log) return;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    CGFloat x = kSide, w = self.width, y = kTop, bottom = self.bounds.size.height - kFoot;
    NSArray<MMWindowLogEntry *> *entries = log.entries;
    if (log.note.length) {
        // With no entry the note is what the log says, so it stands a size larger.
        CGFloat size = entries.count ? 11 : 12;
        y += MMWindowDrawBlock(log.note, size, 10, NSFontWeightRegular, entries.count ? t3 : t2, x, y, w, -1, -1, 0) + 14;
    }
    NSInteger first = MIN(_first, (NSInteger)entries.count), shown = 0;
    for (NSInteger i = first; i < (NSInteger)entries.count; i++) {
        MMWindowLogEntry *e = entries[(NSUInteger)i];
        BOOL header = [self headerAt:i from:first];
        if (y + [self heightOf:i header:header] - kGap > bottom) break;
        CGFloat top = y;
        if (header) {
            if (i > first) y += 4;
            MMWindowDraw(MMWindowText(e.day, 11, NSFontWeightSemibold, t2), x, y + 7, -1);
            y += kDay - (i > first ? 4 : 0);
        }
        y += MMWindowDrawBlock(e.sentence, kSentence, kSentence, NSFontWeightRegular, text, x, y, w, -1, -1, 0) + 2;
        y += MMWindowDrawBlock(e.detail, kDetail, kDetail, NSFontWeightRegular, t3, x, y, w, -1, -1, 0) + kGap;
        [_drawn addObject:e.sentence];
        [_spoken addObject:@[[NSString stringWithFormat:@"%@, %@, %@", e.day, e.sentence, e.detail], [NSValue valueWithRect:NSMakeRect(x, top, w, y - top)]]];
        shown++;
    }
    NSInteger below = (NSInteger)entries.count - first - shown;
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
- (NSArray *)accessibilityChildren {
    NSMutableArray *out = [NSMutableArray new];
    for (NSArray *s in _spoken) {
        NSRect screen = self.window ? NSAccessibilityFrameInView(self, [s[1] rectValue]) : NSZeroRect;
        [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen label:s[0] parent:self]];
    }
    if (_foot) [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:NSZeroRect label:_foot parent:self]];
    return out;
}

@end
