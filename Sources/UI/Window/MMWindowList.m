// One side of the window: its groups under each other, each with a still header and rows that scroll on their own.
// The whole side is one view drawn in one drawRect, so opening the window lays out no row views.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

// A header, a row, the gap between groups, and the two fades: 22 points at the foot where rows wait below, 16 under
// the header once the group is scrolled. A side with room to spare makes its rows taller, up to 50 points, and from
// 36 on a row has a second line. With more than 84 points still left, the side closes with what its whole number is.
static const CGFloat kHead = 24, kRow = 24, kGap = 2, kFade = 22, kTopFade = 16, kTall = 36, kTallest = 50, kSumLeast = 84, kSumRow = 22;

/// How far a group can scroll: to the whole row that brings its last row fully into the box. A box is a whole number
/// of rows high, so at both ends, and at every rest between them, every row shown is whole.
static CGFloat MaxOffset(MMWindowGroup *g, CGFloat boxHeight, CGFloat rowHeight) {
    return MAX(0, ceil((rowHeight * g.rows.count - boxHeight) / rowHeight) * rowHeight);
}

/// A row's second line, where its side has the room: why it stays or goes for a cache or an app, and for the others
/// its first facts that the name does not say already. Nothing is made up: a row with neither has one line.
static NSString *SecondLine(MMWindowRow *row) {
    BOOL byWhy = row.kind == MMWindowCache || row.kind == MMWindowApp || row.kind == MMWindowHelper || row.kind == MMWindowTabs;
    NSString *note = row.fate.note;
    if (byWhy && note.length) return [note hasSuffix:@"."] ? [note substringToIndex:note.length - 1] : note;
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    for (MMWindowFact *f in row.storyFacts) {
        if (!f.value.length || [row.name rangeOfString:f.value options:NSCaseInsensitiveSearch].location != NSNotFound) continue;
        [parts addObject:[NSString stringWithFormat:@"%@ %@", f.label, f.value]];
        if (parts.count == 2) break;
    }
    return parts.count ? [parts componentsJoinedByString:@" · "] : nil;
}

/// What a row shows beside its name and its number, and the name as drawn.
typedef struct { BOOL state, cpu, hour; CGFloat edge; } RowFit;

/// From the right: the number, the row's own hour, CPU, the quiet state word. The name gets the rest and is never cut:
/// the state word yields first, then CPU, then the hour line. A name longer than the whole row loses whole words.
static NSString *FitRow(MMWindowRow *row, MMWindowSide side, BOOL hasHour, CGFloat nameLeft, CGFloat right, RowFit *fit) {
    NSString *name = row.shownName;
    CGFloat need = MMWindowWidth(MMWindowText(name, 13, NSFontWeightRegular, NSColor.whiteColor));
    CGFloat afterSize = right - (side == MMWindowDisk ? 58 : 50) - 6;
    BOOL hour = hasHour && MMWindowHourSpan(row.hour, NULL, NULL, NULL) != nil, cpu = side == MMWindowMemory && row.cpuPercent >= 0;
    CGFloat afterHour = afterSize - (hasHour ? 40 : 0), afterCPU = afterHour - (side == MMWindowMemory ? 46 : 0);
    CGFloat stateWidth = row.state.length ? MMWindowWidth(MMWindowText(row.state, 11.5, NSFontWeightRegular, NSColor.whiteColor)) + 8 : 0;
    RowFit f = {NO, cpu, hour, afterCPU};
    if (stateWidth > 0 && afterCPU - stateWidth - nameLeft >= need) { f.state = YES; f.edge = afterCPU - stateWidth; }
    else if (afterCPU - nameLeft >= need) f.edge = afterCPU;
    else if ((hour ? afterHour : afterSize) - nameLeft >= need) { f.cpu = NO; f.edge = hour ? afterHour : afterSize; }
    else { f.cpu = NO; f.hour = NO; f.edge = afterSize; name = MMWindowShorten(name, 13, NSFontWeightRegular, afterSize - nameLeft); }
    if (fit) *fit = f;
    return name;
}

static BOOL HasHour(MMWindowGroup *g) {
    for (MMWindowRow *r in g.rows) if (MMWindowHourSpan(r.hour, NULL, NULL, NULL)) return YES;
    return NO;
}

@implementation MMWindowListView {
    NSMutableDictionary<NSString *, NSNumber *> *_offsets;   // how far each group is scrolled, by its key
    NSMutableArray<NSValue *> *_frames;                       // each group's frame, header included
    NSString *_scrolling;                                     // the group whose scroller shows
    NSTrackingArea *_tracking;
    CGFloat _rowHeight;                                       // 24, or more on a side with room to spare
    CGFloat _sumTop;                                          // where the side's closing lines start, or below 0 for none
    NSSet<NSString *> *_known;                                // the rows of the model before this one, to tell a new row
    NSInteger _flashed;
}

- (NSInteger)flashed { return _flashed; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _groups = @[]; _offsets = [NSMutableDictionary new]; _frames = [NSMutableArray new];
        _rowHeight = kRow; _sumTop = -1;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityListRole;
    }
    return self;
}

- (void)setGroups:(NSArray<MMWindowGroup *> *)groups {
    _groups = [groups copy] ?: @[];
    [self place];
    [self flashNew];
    self.accessibilityLabel = _groups.firstObject.side == MMWindowDisk ? @"What holds disk" : @"What holds memory";
    self.needsDisplay = YES;
}

/// A row that was not in the model before this one gets a short light under it, where it shows. The first model
/// of an open window lights nothing: then every row is new.
- (void)flashNew {
    NSMutableSet<NSString *> *now = [NSMutableSet new];
    _flashed = 0;
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSRect box = [self boxOf:i];
        CGFloat off = _offsets[g.key].doubleValue;
        for (NSInteger r = 0; r < (NSInteger)g.rows.count; r++) {
            NSString *key = g.rows[r].key;
            [now addObject:key];
            NSRect row = NSMakeRect(5, box.origin.y + r * _rowHeight - off, self.bounds.size.width - 10, _rowHeight);
            if (!_known || [_known containsObject:key] || !NSContainsRect(box, row) || _flashed >= 8) continue;
            MMWindowFlash(self, row);
            _flashed++;
        }
    }
    _known = now;
}

- (void)setRing:(MMWindowRing *)ring { _ring = ring; [self place]; self.needsDisplay = YES; }

- (void)setHotKey:(NSString *)hotKey {
    if (_hotKey == hotKey || [_hotKey isEqualToString:hotKey]) return;
    _hotKey = [hotKey copy];
    self.needsDisplay = YES;
}

#pragma mark Layout

/// Each group gets the height its rows need. When they do not all fit, the long ones share what the short ones leave,
/// in whole rows: no group ever ends on half a row. What is left over goes between the groups.
- (void)place {
    [_frames removeAllObjects];
    _rowHeight = kRow; _sumTop = -1;
    NSInteger n = (NSInteger)_groups.count;
    if (!n) return;
    CGFloat H = self.bounds.size.height, room = H - kGap * (n - 1) - kHead * n, gap = kGap;
    NSInteger fits = (NSInteger)floor(room / kRow), total = 0, rows = 0;
    NSMutableArray<NSNumber *> *give = [NSMutableArray new];
    // A group with no rows keeps one line under its header, for the words that say so.
    for (MMWindowGroup *g in _groups) { NSInteger want = MAX((NSInteger)g.rows.count, 1); [give addObject:@(want)]; total += want; rows += (NSInteger)g.rows.count; }
    if (total <= fits) {
        CGFloat spare = room - total * kRow;
        if (spare > kRow && rows > 0) _rowHeight = MIN(kTallest, kRow + floor(spare / rows));
    } else {
        // The short groups get all their rows. The long ones share the rest, a row at a time.
        NSArray<NSNumber *> *order = [give sortedArrayUsingSelector:@selector(compare:)];
        NSInteger left = MAX(fits, 0), cap = 0;
        for (NSInteger i = 0; i < n; i++) {
            cap = left / (n - i);
            if (order[i].integerValue <= cap) left -= order[i].integerValue; else break;
        }
        NSInteger used = 0;
        for (NSInteger i = 0; i < n; i++) { give[i] = @(MIN(give[i].integerValue, cap)); used += give[i].integerValue; }
        for (NSInteger i = 0; i < n && used < fits; i++) if (give[i].integerValue < (NSInteger)_groups[i].rows.count) { give[i] = @(give[i].integerValue + 1); used++; }
        if (n > 1) gap += floor((room - used * kRow) / (n - 1));
    }
    CGFloat y = 0;
    for (NSInteger i = 0; i < n; i++) {
        MMWindowGroup *g = _groups[i];
        CGFloat h = kHead + (g.rows.count ? give[i].integerValue * _rowHeight : kRow);
        [_frames addObject:[NSValue valueWithRect:NSMakeRect(0, y, self.bounds.size.width, h)]];
        y += h + gap;
        // A group that grew or shrank keeps its place, as far as its rows still reach.
        _offsets[g.key] = @(MIN(MAX(_offsets[g.key].doubleValue, 0), MaxOffset(g, h - kHead, _rowHeight)));
    }
    CGFloat sum = kHead + kSumRow * self.sumLines.count;
    // With rows above, the closing lines stand at the side's foot, as 195-a's. A side with no rows at all has them
    // right under its notes, so the notes and the number read as one block and no blank stands between them.
    if (self.ring && H - (y - gap) > MAX(kSumLeast, sum + 8)) _sumTop = rows ? H - sum - 2 : y - gap + 10;
}

/// What closes a side that has room left: its whole number, what these rows hold of it, and the rest. Label and value.
- (NSArray<NSArray<NSString *> *> *)sumLines {
    MMWindowRing *ring = self.ring;
    if (!ring) return @[];
    BOOL disk = _groups.firstObject.side == MMWindowDisk;
    uint64_t held = 0, used = disk ? (ring.diskTotal > ring.diskFree ? ring.diskTotal - ring.diskFree : 0) : ring.memoryUsed;
    for (MMWindowGroup *g in _groups) for (MMWindowRow *r in g.rows) held += r.bytes;
    NSMutableArray<NSArray<NSString *> *> *out = [NSMutableArray new];
    // "182 of 994 GB": the unit once, where both numbers share it.
    NSArray<NSString *> *part = MMWindowSize2(disk ? ring.diskFree : ring.memoryUsed);
    NSString *whole = MMWindowWhole(disk ? ring.diskTotal : ring.memoryTotal);
    [out addObject:@[disk ? @"Free" : @"In use", [NSString stringWithFormat:[whole hasSuffix:part[1]] ? @"%@ of %@" : @"%@ %@ of %@", part[0], [whole hasSuffix:part[1]] ? whole : part[1], whole]]];
    if (held > 0 && held <= used) {
        [out addObject:@[@"By these holders", MMWindowBytes(held)]];
        [out addObject:@[@"macOS and the rest", MMWindowBytes(used - held)]];
    } else if (disk) [out addObject:@[@"In use", MMWindowBytes(used)]];
    return out;
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
    NSInteger r = (NSInteger)floor((p.y - box.origin.y + _offsets[g.key].doubleValue) / _rowHeight);
    return r >= 0 && r < (NSInteger)g.rows.count ? g.rows[r] : nil;
}

- (void)reveal:(NSString *)key {
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSInteger at = [g.rows indexOfObjectPassingTest:^BOOL(MMWindowRow *r, NSUInteger idx, BOOL *stop) { return [r.key isEqualToString:key]; }];
        if (at == NSNotFound) continue;
        CGFloat boxH = [self boxOf:i].size.height, off = _offsets[g.key].doubleValue, row = _rowHeight, top = at * row;
        if (top < off) off = top;
        if (top + row > off + boxH - kFade) off = MIN(ceil((top + row + kFade - boxH) / row) * row, MaxOffset(g, boxH, row));
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
    if (_sumTop >= 0) [self drawSum];
}

/// The side's closing lines, at its foot: "This disk", free of the whole, what these rows hold, and the rest.
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

- (void)drawGroup:(NSInteger)i {
    MMWindowGroup *g = _groups[i];
    NSRect f = _frames[i].rectValue, box = [self boxOf:i];
    CGFloat off = _offsets[g.key].doubleValue, row = _rowHeight, content = row * g.rows.count;
    NSInteger below = (NSInteger)g.rows.count - (NSInteger)floor((off + box.size.height + 0.5) / row);
    NSInteger above = (NSInteger)ceil((off - 0.5) / row);
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    BOOL disk = g.side == MMWindowDisk;

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
        if (g.emptyNote.length) MMWindowDraw(MMWindowFit(g.emptyNote, 12, NSFontWeightRegular, t3, f.size.width - 28), 14, box.origin.y + kRow / 2, -1);
        return;
    }

    BOOL hasHour = HasHour(g);
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, box);
    // Where a fade is due, the rows go into a layer of their own, so it thins the rows and not the glass.
    BOOL fadeFoot = content - off > box.size.height + 0.5, fadeHead = off > 0.5;
    if (fadeFoot || fadeHead) CGContextBeginTransparencyLayer(cg, NULL);
    NSInteger first = MAX(0, (NSInteger)floor(off / row)), last = MIN((NSInteger)g.rows.count - 1, (NSInteger)floor((off + box.size.height - 0.5) / row));
    for (NSInteger r = first; r <= last; r++)
        [self drawRow:g.rows[r] in:NSMakeRect(5, box.origin.y + r * row - off, f.size.width - 10, row) side:g.side hour:hasHour];
    // Where rows wait below, the last row shown fades as a whole. Once scrolled, so does the edge under the header.
    if (fadeFoot) Fade(cg, NSMaxY(box) - kFade, NSMaxY(box));
    if (fadeHead) Fade(cg, NSMinY(box) + kTopFade, NSMinY(box));
    if (fadeFoot || fadeHead) CGContextEndTransparencyLayer(cg);
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
    // Nothing going on in it, no fix touches it and it asks nothing: its name steps back, so the busy rows lead.
    BOOL calm = row.quiet && !row.inFix && !row.needsYou && !hot;
    NSString *second = r.size.height >= kTall ? SecondLine(row) : nil;
    CGFloat mid = second ? NSMidY(r) - 6.5 : NSMidY(r), right = NSMaxX(r) - 9;
    NSColor *text = hot ? NSColor.whiteColor : MMWindowColor(MMWindowInkText);
    NSColor *quiet = hot ? [NSColor colorWithWhite:1 alpha:0.84] : MMWindowColor(MMWindowInkText2);
    NSColor *nameInk = calm ? [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.62] : text;
    if (hot) {
        [MMWindowColor(MMWindowInkHot) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
    }
    MMWindowDrawIcon(row, NSMakeRect(r.origin.x + 9, NSMidY(r) - 8, 16, 16), hot ? MMWindowColor(MMWindowInkHot) : [NSColor colorWithSRGBRed:0.12 green:0.115 blue:0.16 alpha:1]);

    // From the right: the number with its gray unit, the row's own hour, CPU, the quiet state word. The name gets the rest.
    // A tabs row with no bytes has its count in its name, and no size.
    if (row.showsSize) {
        NSArray<NSString *> *size = MMWindowSize2(row.bytes);
        NSAttributedString *number = MMWindowJoin(@[MMWindowText(size[0], 13, NSFontWeightRegular, text),
                                                    MMWindowText([MMWindowThin stringByAppendingString:size[1]], 11, NSFontWeightRegular, quiet)]);
        MMWindowDraw(number, right, mid, 1);
    }
    CGFloat nameLeft = r.origin.x + 31;
    RowFit fit;
    NSString *name = FitRow(row, side, hasHour, nameLeft, right, &fit);
    CGFloat edge = right - (side == MMWindowDisk ? 58 : 50) - 6;
    if (hasHour) {
        NSColor *ink = hot ? NSColor.whiteColor : MMWindowColor(side == MMWindowDisk ? MMWindowInkDisk : MMWindowInkMemory);
        if (fit.hour) MMWindowDrawHour(row.hour, NSMakeRect(edge - 34, mid - 7, 34, 14), calm ? [ink colorWithAlphaComponent:0.62] : ink, MMWindowHourRow);
        edge -= 40;
    }
    NSString *cpu = fit.cpu ? MMWindowCPU(row.cpuPercent) : nil;
    if (cpu) {
        // From 3 % of a core on, the number is as bright as the name.
        NSColor *ink = row.cpuPercent >= 3 ? text : quiet;
        MMWindowDraw(MMWindowJoin(@[MMWindowText(cpu, 12, NSFontWeightRegular, ink), MMWindowText([MMWindowThin stringByAppendingString:@"%"], 11, NSFontWeightRegular, quiet)]), edge, mid, 1);
    }
    if (fit.state) MMWindowDraw(MMWindowText(row.state, 11.5, NSFontWeightRegular, quiet), edge - (side == MMWindowMemory ? 46 : 0), mid, 1);
    MMWindowDraw(MMWindowText(name, 13, NSFontWeightRegular, nameInk), nameLeft, mid, -1);
    if (second) MMWindowDraw(MMWindowText(MMWindowShorten(second, 11, NSFontWeightRegular, right - nameLeft), 11, NSFontWeightRegular,
                                          hot ? [NSColor colorWithWhite:1 alpha:0.78] : MMWindowColor(MMWindowInkText3)), nameLeft, NSMidY(r) + 9, -1);
}

- (NSArray<NSString *> *)drawnNames {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowGroup *g in _groups) {
        BOOL hasHour = HasHour(g);
        for (MMWindowRow *row in g.rows) [out addObject:FitRow(row, g.side, hasHour, 5 + 31, self.bounds.size.width - 5 - 9, NULL)];
    }
    return out;
}

- (NSDictionary<NSString *, NSNumber *> *)offsets { return [_offsets copy]; }
- (CGFloat)rowHeight { return _rowHeight; }
- (NSArray<NSValue *> *)groupFrames { return [_frames copy]; }
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
    CGFloat max = MaxOffset(g, [self boxOf:i].size.height, _rowHeight);
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
    _scrolling = nil;
    for (NSString *key in _offsets.allKeys) _offsets[key] = @(round(_offsets[key].doubleValue / _rowHeight) * _rowHeight);
    [self place];
    self.needsDisplay = YES;
}

/// The window closed. The next time it opens, every group starts at its first row.
- (void)rest {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideScroller) object:nil];
    _scrolling = nil; _known = nil;
    [_offsets removeAllObjects];
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
            if (row.showsSize) [say addObject:MMWindowBytes(row.bytes)];
            if (row.needsYou) [say addObject:@"asks you"];
            if (row.inFix) [say addObject:@"in Fix Everything"];
            NSString *cpu = MMWindowCPU(row.cpuPercent);
            if (cpu) [say addObject:[NSString stringWithFormat:@"CPU %@ percent", cpu]];
            NSRect rr = NSIntersectionRect(NSMakeRect(5, box.origin.y + r * _rowHeight - off, box.size.width - 10, _rowHeight), box);
            NSRect screen = self.window ? NSAccessibilityFrameInView(self, rr) : NSZeroRect;
            [out addObject:[NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen
                                                                          label:[say componentsJoinedByString:@", "] parent:self]];
        }
    }
    return out;
}

@end
