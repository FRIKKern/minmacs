// One side of the window: its groups under each other, each with a still header and rows that scroll on their own.
// The whole side is one view drawn in one drawRect, so opening the window lays out no row views. MMWindowRow.m draws a row.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

// A header, a row, the gap between groups, and the two fades: 22 points at the foot where rows wait below, 16 under
// the header once the group is scrolled. A side with room to spare makes its rows taller, up to 50 points, and from
// 36 on a row has a second line. With more than 84 points still left, the side closes with what it holds in all.
static const CGFloat kHead = 24, kRow = 24, kGap = 2, kFade = 22, kTopFade = 16, kTall = 36, kTallest = 50, kSumLeast = 84, kSumRow = 22;

static BOOL HasHour(MMWindowGroup *g) {
    for (MMWindowRow *r in g.rows) if (MMWindowHourSpan(r.hour, NULL, NULL, NULL)) return YES;
    return NO;
}

@implementation MMWindowListView {
    NSMutableDictionary<NSString *, NSNumber *> *_offsets;   // how far each group is scrolled, by its key
    NSMutableArray<NSValue *> *_frames;                       // each group's frame, header included
    NSMutableArray<NSArray<NSNumber *> *> *_tops;             // each group's rows: where each starts, and where the last ends
    NSString *_scrolling;                                     // the group whose scroller shows
    NSMutableDictionary<NSString *, NSString *> *_anchors;    // the first row shown of each scrolled group, by the group's key
    NSTrackingArea *_tracking;
    CGFloat _rowHeight;                                       // 24, or more on a side with room to spare
    CGFloat _sumTop;                                          // where the side's closing lines start, or below 0 for none
    NSSet<NSString *> *_known;                                // the rows of the model before this one, to tell a new row
    NSInteger _flashed;
}

- (NSInteger)flashed { return _flashed; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _groups = @[]; _offsets = [NSMutableDictionary new]; _anchors = [NSMutableDictionary new]; _frames = [NSMutableArray new]; _tops = [NSMutableArray new];
        _rowHeight = kRow; _sumTop = -1;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityListRole;
    }
    return self;
}

- (void)setGroups:(NSArray<MMWindowGroup *> *)groups { [self setGroups:groups ring:_ring]; }
- (void)setRing:(MMWindowRing *)ring { [self setGroups:_groups ring:ring]; }

/// A new model: the groups and the Mac's numbers together, laid out once.
- (void)setGroups:(NSArray<MMWindowGroup *> *)groups ring:(MMWindowRing *)ring {
    _groups = [groups copy] ?: @[]; _ring = ring;
    [self place];
    [self flashNew];
    self.accessibilityLabel = _groups.firstObject.side == MMWindowDisk ? @"What holds disk" : @"What holds memory";
    self.needsDisplay = YES;
}

/// A row that was not in the model before this one gets a short light under it, where it shows. A model that comes
/// after none, or after one with no rows at all, lights nothing: then every row is new. Nor does a list that is hidden.
- (void)flashNew {
    NSMutableSet<NSString *> *now = [NSMutableSet new];
    BOOL may = _known.count > 0 && !self.isHiddenOrHasHiddenAncestor;
    _flashed = 0;
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSRect box = [self boxOf:i];
        CGFloat off = _offsets[g.key].doubleValue;
        for (NSInteger r = 0; r < (NSInteger)g.rows.count; r++) {
            NSString *key = g.rows[r].key;
            [now addObject:key];
            if (!may || [_known containsObject:key] || _flashed >= 8) continue;
            NSRect row = [self rowRect:r in:i box:box offset:off];
            if (!NSContainsRect(box, row)) continue;
            MMWindowFlash(self, row);
            _flashed++;
        }
    }
    _known = now;
}

- (void)setHotKey:(NSString *)hotKey {
    if (_hotKey == hotKey || [_hotKey isEqualToString:hotKey]) return;
    _hotKey = [hotKey copy];
    self.needsDisplay = YES;
}

#pragma mark Layout

/// Where each row of a group starts, with the end of the last one: a row is `row` points high, and a name that wraps
/// adds a line for each line more.
- (NSArray<NSNumber *> *)topsOf:(MMWindowGroup *)g row:(CGFloat)row {
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithCapacity:g.rows.count + 1];
    BOOL hasHour = HasHour(g);
    CGFloat y = 0, left = 5 + 31, right = self.bounds.size.width - 5 - 9;
    for (MMWindowRow *r in g.rows) {
        [tops addObject:@(y)];
        // Every name is measured with the real font. The widths are kept, so a model that brings the same names costs little.
        MMWindowRowFit fit = {NO, NO, NO, 0, 1};
        MMWindowRowName(r, g.side, hasHour, left, right, &fit);
        y += row + MMWindowNameLine * (fit.lines - 1);
    }
    [tops addObject:@(y)];
    return tops;
}

/// How far a group can scroll: to the row that brings its last row fully into the box.
- (CGFloat)maxOffset:(NSInteger)i box:(CGFloat)boxHeight {
    NSArray<NSNumber *> *tops = _tops[i];
    CGFloat end = tops.lastObject.doubleValue;
    for (NSNumber *t in tops) if (end - t.doubleValue <= boxHeight + 0.5) return t.doubleValue;
    return 0;
}

/// The row start nearest to an offset: a group rests with a whole row under its header.
- (CGFloat)snap:(CGFloat)off in:(NSInteger)i {
    CGFloat best = 0;
    for (NSNumber *t in _tops[i]) if (fabs(t.doubleValue - off) < fabs(best - off)) best = t.doubleValue;
    return best;
}

/// Remembers which row a scrolled group shows first, or forgets it at the top.
- (void)anchor:(NSInteger)i at:(CGFloat)off {
    MMWindowGroup *g = _groups[i];
    NSUInteger r = [_tops[i] indexOfObject:@(off)];
    if (off > 0 && r != NSNotFound && r < g.rows.count) _anchors[g.key] = g.rows[r].key; else [_anchors removeObjectForKey:g.key];
}

/// Rows differ in height, so a scrolled box does not always end on a row's foot. At rest the rows that show share
/// what is left under the last whole one, each a little taller, so the group has no blank strip at its foot and a
/// pointer there is on a row that is drawn. Zero while the group moves and where every row shows.
- (CGFloat)stretch:(NSInteger)i shown:(NSRange)shown box:(NSRect)box offset:(CGFloat)off {
    MMWindowGroup *g = _groups[i];
    if ([_scrolling isEqualToString:g.key] || !shown.length || shown.length == g.rows.count) return 0;
    CGFloat blank = box.size.height - (_tops[i][NSMaxRange(shown)].doubleValue - off);
    return blank > 0.5 ? blank / shown.length : 0;
}

- (NSRect)rowRect:(NSInteger)r in:(NSInteger)i box:(NSRect)box offset:(CGFloat)off {
    NSRange shown = [self shown:i moving:[_scrolling isEqualToString:_groups[i].key]];
    return [self rowRect:r in:i box:box offset:off shown:shown stretch:[self stretch:i shown:shown box:box offset:off]];
}

/// The same for a caller that goes through many rows of one group and has asked what shows once.
- (NSRect)rowRect:(NSInteger)r in:(NSInteger)i box:(NSRect)box offset:(CGFloat)off shown:(NSRange)shown stretch:(CGFloat)stretch {
    NSArray<NSNumber *> *tops = _tops[i];
    CGFloat more = r >= (NSInteger)shown.location && r < (NSInteger)NSMaxRange(shown) ? stretch : 0;
    return NSMakeRect(5, box.origin.y + tops[r].doubleValue - off + more * (r - (NSInteger)shown.location), self.bounds.size.width - 10, tops[r + 1].doubleValue - tops[r].doubleValue + more);
}

/// Each group gets the height its rows need. When they do not all fit, the long ones share what the short ones leave,
/// in whole rows: no group ever ends on half a row. What is left over goes between the groups.
- (void)place {
    [_frames removeAllObjects]; [_tops removeAllObjects];
    _rowHeight = kRow; _sumTop = -1;
    NSInteger n = (NSInteger)_groups.count;
    if (!n) return;
    CGFloat H = self.bounds.size.height, room = H - kGap * (n - 1) - kHead * n, gap = kGap, total = 0;
    NSInteger rows = 0;
    NSMutableArray<NSNumber *> *give = [NSMutableArray new];
    // A group with no rows keeps one line under its header, for the words that say so.
    for (MMWindowGroup *g in _groups) {
        [_tops addObject:[self topsOf:g row:kRow]];
        CGFloat want = g.rows.count ? _tops.lastObject.lastObject.doubleValue : kRow;
        [give addObject:@(want)]; total += want; rows += (NSInteger)g.rows.count;
    }
    if (total <= room) {
        CGFloat spare = room - total;
        if (spare > kRow && rows > 0) {
            _rowHeight = MIN(kTallest, kRow + floor(spare / rows));
            for (NSInteger i = 0; i < n; i++) if (_groups[i].rows.count) { _tops[i] = [self topsOf:_groups[i] row:_rowHeight]; give[i] = _tops[i].lastObject; }
        }
    } else {
        // The short groups get all their rows. The long ones share the rest, each as many whole rows as its share holds.
        NSArray<NSNumber *> *order = [give sortedArrayUsingSelector:@selector(compare:)];
        CGFloat left = MAX(room, 0), cap = 0, used = 0;
        for (NSInteger i = 0; i < n; i++) {
            cap = left / (n - i);
            if (order[i].doubleValue <= cap) left -= order[i].doubleValue; else break;
        }
        NSMutableArray<NSNumber *> *shown = [NSMutableArray new];
        for (NSInteger i = 0; i < n; i++) {
            NSArray<NSNumber *> *tops = _tops[i];
            NSInteger k = _groups[i].rows.count ? 1 : 0;
            while (k < (NSInteger)_groups[i].rows.count && tops[k + 1].doubleValue <= cap) k++;
            [shown addObject:@(k)];
            give[i] = @(_groups[i].rows.count ? tops[k].doubleValue : kRow); used += give[i].doubleValue;
        }
        // What the shares left over goes to the groups that can show one more row with it.
        for (BOOL any = YES; any;) {
            any = NO;
            for (NSInteger i = 0; i < n; i++) {
                NSInteger k = shown[i].integerValue;
                if (k >= (NSInteger)_groups[i].rows.count) continue;
                CGFloat more = _tops[i][k + 1].doubleValue - _tops[i][k].doubleValue;
                if (used + more > room) continue;
                shown[i] = @(k + 1); give[i] = _tops[i][k + 1]; used += more; any = YES;
            }
        }
        if (n > 1) gap += floor(MAX(room - used, 0) / (n - 1));
    }
    CGFloat y = 0;
    for (NSInteger i = 0; i < n; i++) {
        MMWindowGroup *g = _groups[i];
        CGFloat h = kHead + give[i].doubleValue;
        [_frames addObject:[NSValue valueWithRect:NSMakeRect(0, y, self.bounds.size.width, h)]];
        y += h + gap;
        // A scrolled group keeps the row it showed first, whatever grew or went above it. While the fingers still move
        // it, a new model leaves it where they have it. Else it rests on a whole row, as far as its rows still reach.
        CGFloat most = [self maxOffset:i box:h - kHead], was = MIN(MAX(_offsets[g.key].doubleValue, 0), most);
        if (![_scrolling isEqualToString:g.key]) {
            NSString *anchor = _anchors[g.key];
            NSUInteger at = anchor ? [g.rows indexOfObjectPassingTest:^BOOL(MMWindowRow *r, NSUInteger idx, BOOL *stop) { return [r.key isEqualToString:anchor]; }] : NSNotFound;
            was = at != NSNotFound && was > 0 ? MIN(_tops[i][at].doubleValue, most) : [self snap:was in:i];
            [self anchor:i at:was];
        }
        _offsets[g.key] = @(was);
    }
    CGFloat sum = kHead + kSumRow * self.sumLines.count;
    // With rows above, the closing lines stand at the side's foot, as 195-a's. A side with no rows at all has them
    // right under its notes, so the notes and the number read as one block and no blank stands between them.
    if (self.ring && H - (y - gap) > MAX(kSumLeast, sum + 8)) _sumTop = rows ? H - sum - 2 : y - gap + 10;
}

/// What closes a side that has room left: what it holds in all. Only numbers that are true as they stand: what the
/// rows hold is not summed, since one row can hold another, an app its servers or a worktree its caches.
- (NSArray<NSArray<NSString *> *> *)sumLines {
    MMWindowRing *ring = self.ring;
    if (!ring) return @[];
    BOOL disk = _groups.firstObject.side == MMWindowDisk;
    // "182 of 994 GB": the unit once, where both numbers share it.
    NSArray<NSString *> *part = MMWindowSize2(disk ? ring.diskFree : ring.memoryUsed, disk);
    NSString *whole = MMWindowWhole(disk ? ring.diskTotal : ring.memoryTotal, disk);
    BOOL same = [whole hasSuffix:part[1]];
    NSMutableArray<NSArray<NSString *> *> *out = [NSMutableArray new];
    [out addObject:@[disk ? @"Free" : @"In use", same ? [NSString stringWithFormat:@"%@ of %@", part[0], whole] : [NSString stringWithFormat:@"%@ %@ of %@", part[0], part[1], whole]]];
    if (disk && ring.diskTotal > ring.diskFree) [out addObject:@[@"In use", MMWindowBytes(ring.diskTotal - ring.diskFree, YES)]];
    return out;
}

- (void)setFrameSize:(NSSize)size {
    BOOL changed = !NSEqualSizes(size, self.frame.size);
    [super setFrameSize:size];
    if (changed) [self place];
}

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
    // Only a row that is drawn can be pointed at, where it is drawn.
    NSRange shown = [self shown:i moving:[_scrolling isEqualToString:g.key]];
    CGFloat off = _offsets[g.key].doubleValue;
    for (NSUInteger r = shown.location; r < NSMaxRange(shown); r++) if (NSPointInRect(p, [self rowRect:(NSInteger)r in:i box:box offset:off])) return g.rows[r];
    return nil;
}

- (void)reveal:(NSString *)key {
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSInteger at = [g.rows indexOfObjectPassingTest:^BOOL(MMWindowRow *r, NSUInteger idx, BOOL *stop) { return [r.key isEqualToString:key]; }];
        if (at == NSNotFound) continue;
        NSArray<NSNumber *> *tops = _tops[i];
        CGFloat boxH = [self boxOf:i].size.height, off = _offsets[g.key].doubleValue, top = tops[at].doubleValue, end = tops[at + 1].doubleValue;
        if (top < off) off = top;
        // The row shows whole, with the next one under it where there is one, so it is not the row that fades.
        CGFloat need = at + 2 < (NSInteger)tops.count ? tops[at + 2].doubleValue : end;
        if (need > off + boxH) for (NSNumber *t in tops) if (need - t.doubleValue <= boxH) { off = t.doubleValue; break; }
        _offsets[g.key] = @(MIN(MAX(off, 0), [self maxOffset:i box:boxH]));
        [self anchor:i at:_offsets[g.key].doubleValue];
        self.needsDisplay = YES;
        return;
    }
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        if (NSIntersectsRect(dirty, _frames[i].rectValue)) [self drawGroup:i];
    }
    if (_sumTop >= 0) [self drawSum];
}

/// The side's closing lines: "This disk", free of the whole, and what is in use.
- (void)drawSum {
    NSColor *t2 = MMWindowColor(MMWindowInkText2);
    BOOL disk = _groups.firstObject.side == MMWindowDisk;
    CGFloat w = self.bounds.size.width, y = _sumTop;
    MMWindowDraw(MMWindowText(disk ? @"This disk" : @"Memory", 11, NSFontWeightBold, t2), 14, y + kHead / 2, -1);
    y += kHead;
    for (NSArray<NSString *> *line in self.sumLines) {
        MMWindowDraw(MMWindowText(line[0], 12.5, NSFontWeightRegular, t2), 14, y + kSumRow / 2, -1);
        MMWindowDraw(MMWindowText(line[1], 12.5, NSFontWeightRegular, MMWindowColor(MMWindowInkText)), w - 14, y + kSumRow / 2, 1);
        y += kSumRow;
    }
}

static void Fade(CGContextRef cg, CGFloat from, CGFloat to) {
    // Thins what is drawn so far, from nothing at `from` to most of it at `to`.
    CGContextSetBlendMode(cg, kCGBlendModeDestinationOut);
    CGFloat parts[8] = {0, 0, 0, 0, 0, 0, 0, 0.82};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, parts, NULL, 2);
    CGContextDrawLinearGradient(cg, grad, CGPointMake(0, from), CGPointMake(0, to), 0);
    CGGradientRelease(grad); CGColorSpaceRelease(space);
    CGContextSetBlendMode(cg, kCGBlendModeNormal);
}

/// The rows of a group that show now: the first under the header, and the last that is whole inside the box. While
/// the group moves under the fingers, rows cut by the box's edges show too.
- (NSRange)shown:(NSInteger)i moving:(BOOL)moving {
    MMWindowGroup *g = _groups[i];
    NSArray<NSNumber *> *tops = _tops[i];
    CGFloat off = _offsets[g.key].doubleValue, end = off + [self boxOf:i].size.height;
    NSInteger first = -1, last = -1;
    for (NSInteger r = 0; r < (NSInteger)g.rows.count; r++) {
        CGFloat top = tops[r].doubleValue, bottom = tops[r + 1].doubleValue;
        BOOL in = moving ? bottom > off && top < end : top >= off - 0.5 && bottom <= end + 0.5;
        if (!in) continue;
        if (first < 0) first = r;
        last = r;
    }
    return first < 0 ? NSMakeRange(0, 0) : NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}

- (void)drawGroup:(NSInteger)i {
    MMWindowGroup *g = _groups[i];
    NSRect f = _frames[i].rectValue, box = [self boxOf:i];
    CGFloat off = _offsets[g.key].doubleValue;
    BOOL moving = [_scrolling isEqualToString:g.key], disk = g.side == MMWindowDisk;
    NSRange shown = [self shown:i moving:moving];
    NSInteger below = (NSInteger)g.rows.count - (NSInteger)NSMaxRange(shown), above = (NSInteger)shown.location;
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);

    // The header stays still: the title, how many, and how many rows wait under the fold.
    NSAttributedString *head = MMWindowJoin(@[MMWindowText(g.title, 11, NSFontWeightBold, t2),
                                              MMWindowText([NSString stringWithFormat:@"   %lu", (unsigned long)g.rows.count], 11, NSFontWeightMedium, t3)]);
    MMWindowDraw(head, 14, f.origin.y + kHead / 2, -1);
    // Rows wait under the fold, or, once the group is scrolled to its end, above it. With all of them in view the
    // header says what they are sorted by.
    NSString *more = below > 0 ? [NSString stringWithFormat:@"%ld more below", (long)below] : above > 0 ? [NSString stringWithFormat:@"%ld more above", (long)above]
                   : g.rows.count ? (disk ? @"by disk" : @"by memory") : nil;
    if (more) MMWindowDraw(MMWindowText(more, 11, NSFontWeightRegular, below > 0 || above > 0 ? t2 : t3), f.size.width - 14, f.origin.y + kHead / 2, 1);
    if (box.size.height <= 0) return;
    if (!g.rows.count) {
        if (g.emptyNote.length) MMWindowDrawBlock(g.emptyNote, 12, 10, NSFontWeightRegular, t3, 14, box.origin.y + kRow / 2, f.size.width - 28, -1, 0, 26);
        return;
    }
    if (!shown.length) return;

    BOOL hasHour = HasHour(g);
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, box);
    // Where a fade is due, the rows go into a layer of their own, so it thins the rows and not the glass.
    BOOL fadeFoot = below > 0, fadeHead = off > 0.5;
    if (fadeFoot || fadeHead) CGContextBeginTransparencyLayer(cg, NULL);
    CGFloat foot = NSMaxY(box), stretch = [self stretch:i shown:shown box:box offset:off];
    for (NSUInteger r = shown.location; r < NSMaxRange(shown); r++) {
        NSRect at = [self rowRect:(NSInteger)r in:i box:box offset:off shown:shown stretch:stretch];
        MMWindowDrawRow(g.rows[r], at, g.side, hasHour, [g.rows[r].key isEqualToString:_hotKey], _rowHeight >= kTall);
        foot = NSMaxY(at);
    }
    // Where rows wait below, the last row shown fades as a whole. Once scrolled, so does the edge under the header.
    if (fadeFoot) Fade(cg, (moving ? NSMaxY(box) : foot) - kFade, moving ? NSMaxY(box) : foot);
    if (fadeHead) Fade(cg, NSMinY(box) + kTopFade, NSMinY(box));
    if (fadeFoot || fadeHead) CGContextEndTransparencyLayer(cg);
    CGContextRestoreGState(cg);

    // The overlay scroller shows only while the group moves.
    CGFloat content = _tops[i].lastObject.doubleValue;
    if (moving && content > box.size.height) {
        CGFloat h = MAX(18, box.size.height * box.size.height / content), y = box.origin.y + (box.size.height - h) * off / (content - box.size.height);
        [[NSColor colorWithWhite:1 alpha:0.34] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(f.size.width - 5, y + 1, 3, h - 2) xRadius:1.5 yRadius:1.5] fill];
    }
}

- (NSArray<NSString *> *)drawnNames {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowGroup *g in _groups) {
        BOOL hasHour = HasHour(g);
        for (MMWindowRow *row in g.rows) [out addObject:[MMWindowRowName(row, g.side, hasHour, 5 + 31, self.bounds.size.width - 5 - 9, NULL) componentsJoinedByString:@"\n"]];
    }
    return out;
}

- (NSRect)frameOfRow:(NSString *)key {
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSRange shown = [self shown:i moving:[_scrolling isEqualToString:g.key]];
        for (NSUInteger r = shown.location; r < NSMaxRange(shown); r++)
            if ([g.rows[r].key isEqualToString:key]) return [self rowRect:(NSInteger)r in:i box:[self boxOf:i] offset:_offsets[g.key].doubleValue];
    }
    return NSZeroRect;
}

- (NSDictionary<NSString *, NSNumber *> *)offsets { return [_offsets copy]; }
- (CGFloat)rowHeight { return _rowHeight; }
- (NSArray<NSValue *> *)groupFrames { return [_frames copy]; }
- (NSArray<NSArray<NSNumber *> *> *)rowTops { return [_tops copy]; }
- (BOOL)showsSum { return _sumTop >= 0; }

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
    CGFloat max = [self maxOffset:i box:[self boxOf:i].size.height];
    CGFloat step = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * _rowHeight;
    CGFloat off = MIN(MAX(_offsets[g.key].doubleValue - step, 0), max);
    if (off == _offsets[g.key].doubleValue) return;
    _offsets[g.key] = @(off);
    _scrolling = g.key;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideScroller) object:nil];
    [self performSelector:@selector(hideScroller) withObject:nil afterDelay:0.8 inModes:@[NSRunLoopCommonModes]];
    [self setNeedsDisplayInRect:_frames[i].rectValue];
    [self pointAt:p];
}

/// The scroll came to rest: each group settles on a whole row, so no row stays half cut under a header.
- (void)hideScroller {
    // The anchors are of before the fingers moved: each group rests on the whole row nearest to where they left it.
    _scrolling = nil; [_anchors removeAllObjects];
    [self place];
    self.needsDisplay = YES;
}

/// The window closed. The next time it opens, every group starts at its first row.
- (void)rest {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideScroller) object:nil];
    _scrolling = nil; _known = nil;
    [_offsets removeAllObjects]; [_anchors removeAllObjects];
    self.needsDisplay = YES;
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
            NSMutableArray *say = [NSMutableArray arrayWithObjects:g.title, row.shownName, nil];
            if (row.state.length) [say addObject:row.state];
            if (row.showsSize) [say addObject:MMWindowBytes(row.bytes, g.side == MMWindowDisk)];
            if (row.needsYou) [say addObject:@"asks you"];
            if (row.inFix) [say addObject:@"in Fix Everything"];
            NSString *cpu = MMWindowCPU(row.cpuPercent);
            if (cpu) [say addObject:[NSString stringWithFormat:@"CPU %@ percent", cpu]];
            NSRect rr = NSIntersectionRect([self rowRect:r in:i box:box offset:off], box);
            NSRect screen = self.window ? NSAccessibilityFrameInView(self, rr) : NSZeroRect;
            [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen
                                                                          label:[say componentsJoinedByString:@", "] parent:self]];
        }
    }
    return out;
}

@end
