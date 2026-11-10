// One side of the window: its groups under each other, each with a still header and rows that scroll on their own.
// The whole side is one view drawn in one drawRect, so opening the window lays out no row views.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

static const CGFloat kHead = 24, kRow = 24, kGap = 2, kFade = 22;

@implementation MMWindowListView {
    NSMutableDictionary<NSString *, NSNumber *> *_offsets;   // how far each group is scrolled, by its key
    NSMutableArray<NSValue *> *_frames;                       // each group's frame, header included
    NSString *_scrolling;                                     // the group whose scroller shows
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _groups = @[]; _offsets = [NSMutableDictionary new]; _frames = [NSMutableArray new];
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityListRole;
    }
    return self;
}

- (void)setGroups:(NSArray<MMWindowGroup *> *)groups {
    _groups = [groups copy] ?: @[];
    [self place];
    self.accessibilityLabel = _groups.firstObject.side == MMWindowDisk ? @"What holds disk" : @"What holds memory";
    self.needsDisplay = YES;
}

- (void)setHotKey:(NSString *)hotKey {
    if (_hotKey == hotKey || [_hotKey isEqualToString:hotKey]) return;
    _hotKey = [hotKey copy];
    self.needsDisplay = YES;
}

#pragma mark Layout

/// Each group gets the height its rows need. When they do not all fit, the long ones share what the short ones leave.
- (void)place {
    [_frames removeAllObjects];
    NSInteger n = (NSInteger)_groups.count;
    if (!n) return;
    CGFloat room = self.bounds.size.height - kGap * (n - 1), cap = room;
    NSMutableArray<NSNumber *> *want = [NSMutableArray new];
    CGFloat sum = 0;
    for (MMWindowGroup *g in _groups) { CGFloat h = kHead + kRow * g.rows.count; [want addObject:@(h)]; sum += h; }
    if (sum > room) {
        // Find the height at which the tall groups are cut so that the sum fills the side.
        NSArray<NSNumber *> *sorted = [want sortedArrayUsingSelector:@selector(compare:)];
        CGFloat left = room;
        for (NSInteger i = 0; i < n; i++) {
            cap = left / (n - i);
            if (sorted[i].doubleValue <= cap) left -= sorted[i].doubleValue; else break;
        }
    }
    CGFloat y = 0;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat h = floor(MIN(want[i].doubleValue, cap));
        [_frames addObject:[NSValue valueWithRect:NSMakeRect(0, y, self.bounds.size.width, h)]];
        y += h + kGap;
        // A group that grew or shrank keeps its place, as far as its rows still reach.
        MMWindowGroup *g = _groups[i];
        CGFloat max = MAX(0, kRow * g.rows.count - (h - kHead));
        _offsets[g.key] = @(MIN(MAX(_offsets[g.key].doubleValue, 0), max));
    }
}

- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self place]; }

- (NSRect)boxOf:(NSInteger)i { NSRect f = _frames[i].rectValue; return NSMakeRect(f.origin.x, f.origin.y + kHead, f.size.width, f.size.height - kHead); }

- (NSInteger)groupAt:(NSPoint)p {
    for (NSInteger i = 0; i < (NSInteger)_frames.count; i++) if (NSPointInRect(p, _frames[i].rectValue)) return i;
    return -1;
}

- (MMWindowRow *)rowAt:(NSPoint)p {
    NSInteger i = [self groupAt:p];
    if (i < 0 || p.x < 5 || p.x > self.bounds.size.width - 5) return nil;
    NSRect box = [self boxOf:i];
    if (!NSPointInRect(p, box)) return nil;
    MMWindowGroup *g = _groups[i];
    NSInteger r = (NSInteger)floor((p.y - box.origin.y + _offsets[g.key].doubleValue) / kRow);
    return r >= 0 && r < (NSInteger)g.rows.count ? g.rows[r] : nil;
}

- (void)reveal:(NSString *)key {
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSInteger at = [g.rows indexOfObjectPassingTest:^BOOL(MMWindowRow *r, NSUInteger idx, BOOL *stop) { return [r.key isEqualToString:key]; }];
        if (at == NSNotFound) continue;
        CGFloat boxH = [self boxOf:i].size.height, off = _offsets[g.key].doubleValue, top = at * kRow;
        if (top < off) off = top;
        if (top + kRow > off + boxH - kFade) off = MIN(top + kRow + kFade - boxH, MAX(0, kRow * g.rows.count - boxH));
        _offsets[g.key] = @(MAX(off, 0));
        self.needsDisplay = YES;
        return;
    }
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirty {
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        if (NSIntersectsRect(dirty, _frames[i].rectValue)) [self drawGroup:i];
    }
}

- (void)drawGroup:(NSInteger)i {
    MMWindowGroup *g = _groups[i];
    NSRect f = _frames[i].rectValue, box = [self boxOf:i];
    CGFloat off = _offsets[g.key].doubleValue, content = kRow * g.rows.count;
    NSInteger below = (NSInteger)g.rows.count - (NSInteger)floor((off + box.size.height + 0.5) / kRow);
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);

    // The header stays still: the title, how many, and how many rows wait under the fold.
    NSAttributedString *head = MMWindowJoin(@[MMWindowText(g.title, 11, NSFontWeightBold, t2),
                                              MMWindowText([NSString stringWithFormat:@"   %lu", (unsigned long)g.rows.count], 11, NSFontWeightMedium, t3)]);
    MMWindowDraw(head, 14, f.origin.y + kHead / 2, -1);
    if (below > 0) MMWindowDraw(MMWindowText([NSString stringWithFormat:@"%ld more below", (long)below], 11, NSFontWeightRegular, t2), f.size.width - 14, f.origin.y + kHead / 2, 1);
    if (box.size.height <= 0) return;

    BOOL hasHour = NO;
    for (MMWindowRow *r in g.rows) if (r.hour) { hasHour = YES; break; }
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    BOOL fade = content - off > box.size.height + 0.5;
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, box);
    // The rows go into a layer of their own, so the fade at the bottom edge thins the rows and not the glass.
    CGContextBeginTransparencyLayer(cg, NULL);
    NSInteger first = MAX(0, (NSInteger)floor(off / kRow)), last = MIN((NSInteger)g.rows.count - 1, (NSInteger)floor((off + box.size.height) / kRow));
    for (NSInteger r = first; r <= last; r++)
        [self drawRow:g.rows[r] in:NSMakeRect(5, box.origin.y + r * kRow - off, f.size.width - 10, kRow) side:g.side hour:hasHour];
    if (fade) {
        CGContextSetBlendMode(cg, kCGBlendModeDestinationOut);
        CGFloat parts[8] = {0, 0, 0, 0, 0, 0, 0, 0.82};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef grad = CGGradientCreateWithColorComponents(space, parts, NULL, 2);
        CGContextDrawLinearGradient(cg, grad, CGPointMake(0, NSMaxY(box) - kFade), CGPointMake(0, NSMaxY(box)), 0);
        CGGradientRelease(grad); CGColorSpaceRelease(space);
    }
    CGContextEndTransparencyLayer(cg);
    CGContextRestoreGState(cg);

    // The overlay scroller shows only while the group moves.
    if ([_scrolling isEqualToString:g.key] && content > box.size.height) {
        CGFloat h = MAX(18, box.size.height * box.size.height / content), y = box.origin.y + (box.size.height - h) * off / (content - box.size.height);
        [[NSColor colorWithWhite:1 alpha:0.34] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(f.size.width - 5, y + 1, 3, h - 2) xRadius:1.5 yRadius:1.5] fill];
    }
}

- (void)drawRow:(MMWindowRow *)row in:(NSRect)r side:(MMWindowSide)side hour:(BOOL)hasHour {
    BOOL hot = [row.key isEqualToString:_hotKey];
    CGFloat mid = NSMidY(r), right = NSMaxX(r) - 9;
    NSColor *text = hot ? NSColor.whiteColor : MMWindowColor(MMWindowInkText);
    NSColor *quiet = hot ? [NSColor colorWithWhite:1 alpha:0.84] : MMWindowColor(MMWindowInkText2);
    if (hot) {
        [MMWindowColor(MMWindowInkHot) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
    }
    MMWindowDrawIcon(row, NSMakeRect(r.origin.x + 9, mid - 8, 16, 16), hot ? MMWindowColor(MMWindowInkHot) : [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1]);

    // From the right: the number with its gray unit, the row's own hour, CPU, the quiet state word. The name gets the rest.
    NSArray<NSString *> *size = MMWindowSize2(row.bytes);
    NSAttributedString *number = MMWindowJoin(@[MMWindowText(size[0], 13, NSFontWeightRegular, text),
                                                MMWindowText([@" " stringByAppendingString:size[1]], 11, NSFontWeightRegular, quiet)]);
    MMWindowDraw(number, right, mid, 1);
    CGFloat edge = right - (side == MMWindowDisk ? 58 : 50) - 6;
    if (hasHour) {
        if (row.hour) MMWindowDrawHour(row.hour, NSMakeRect(edge - 34, mid - 7, 34, 14), hot ? NSColor.whiteColor : MMWindowColor(side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory), 1, NO);
        edge -= 40;
    }
    if (side == MMWindowMemory) {
        if (row.cpuPercent >= 0) {
            NSString *cpu = row.cpuPercent >= 99.5 ? [NSString stringWithFormat:@"%.0f", row.cpuPercent] : [NSString stringWithFormat:@"%.1f", row.cpuPercent];
            MMWindowDraw(MMWindowJoin(@[MMWindowText(cpu, 12, NSFontWeightRegular, quiet), MMWindowText(@" %", 11, NSFontWeightRegular, quiet)]), edge, mid, 1);
        }
        edge -= 46;
    }
    CGFloat nameLeft = r.origin.x + 31;
    NSString *name = row.kind == MMWindowTabs && row.tabs > 0 && ![row.name hasPrefix:@(row.tabs).stringValue]
        ? [NSString stringWithFormat:@"%ld %@", (long)row.tabs, row.name] : row.name;
    if (row.state.length) {
        NSAttributedString *state = MMWindowText(row.state, 11.5, NSFontWeightRegular, quiet);
        CGFloat w = MMWindowWidth(state);
        // The name comes first. A state word that would cut the name is left out, never cut itself.
        if (edge - w - 8 - nameLeft >= MMWindowWidth(MMWindowText(name, 13, NSFontWeightRegular, text))) { MMWindowDraw(state, edge, mid, 1); edge -= w + 8; }
    }
    MMWindowDraw(MMWindowFit(name, 13, NSFontWeightRegular, text, edge - nameLeft), nameLeft, mid, -1);
}

#pragma mark Pointer and scrolling

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)pointAt:(NSPoint)p {
    MMWindowRow *row = NSPointInRect(p, self.bounds) ? [self rowAt:p] : nil;
    if (self.onPoint) self.onPoint(row.key);
}

- (void)mouseMoved:(NSEvent *)e { [self pointAt:[self convertPoint:e.locationInWindow fromView:nil]]; }
- (void)mouseEntered:(NSEvent *)e { [self mouseMoved:e]; }
- (void)mouseExited:(NSEvent *)e { if (self.onPoint) self.onPoint(nil); }

- (void)scrollWheel:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSInteger i = [self groupAt:p];
    if (i < 0) return;
    MMWindowGroup *g = _groups[i];
    CGFloat max = MAX(0, kRow * g.rows.count - [self boxOf:i].size.height);
    CGFloat step = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * kRow;
    CGFloat off = MIN(MAX(_offsets[g.key].doubleValue - step, 0), max);
    if (off == _offsets[g.key].doubleValue) return;
    _offsets[g.key] = @(off);
    _scrolling = g.key;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideScroller) object:nil];
    [self performSelector:@selector(hideScroller) withObject:nil afterDelay:0.8 inModes:@[NSRunLoopCommonModes]];
    [self setNeedsDisplayInRect:_frames[i].rectValue];
    [self pointAt:p];
}

- (void)hideScroller { _scrolling = nil; self.needsDisplay = YES; }

- (void)rest {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideScroller) object:nil];
    _scrolling = nil;
}

#pragma mark Accessibility

/// One element per row, made only when asked for.
- (NSArray *)accessibilityChildren {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSRect box = [self boxOf:i];
        CGFloat off = _offsets[g.key].doubleValue;
        for (NSInteger r = 0; r < (NSInteger)g.rows.count; r++) {
            MMWindowRow *row = g.rows[r];
            NSMutableArray *say = [NSMutableArray arrayWithObjects:g.title, row.name, nil];
            if (row.state.length) [say addObject:row.state];
            [say addObject:MMWindowBytes(row.bytes)];
            if (row.needsYou) [say addObject:@"asks you"];
            if (row.inFix) [say addObject:@"in Fix Everything"];
            NSRect rr = NSIntersectionRect(NSMakeRect(5, box.origin.y + r * kRow - off, box.size.width - 10, kRow), box);
            NSRect screen = self.window ? NSAccessibilityFrameInView(self, rr) : NSZeroRect;
            [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen
                                                                          label:[say componentsJoinedByString:@", "] parent:self]];
        }
    }
    return out;
}

@end
