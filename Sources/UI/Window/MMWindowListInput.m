// A side's list under the pointer: which row it rests on, which row a press picks, a group scrolled by the fingers
// and how it comes to rest, and a row for VoiceOver each. MMWindowList.m lays the side out and draws it.
// A press here only selects: it names no host and runs nothing.
#import "UI/Window/MMWindowListParts.h"
#import "UI/MMFormat.h"

/// A row as VoiceOver reads it: selected when it is the active row, and a press on it picks it as a click does.
@interface MMWindowRowElement : NSAccessibilityElement
@property (copy) NSString *key;
@property (weak) MMWindowListView *list;
@end

@implementation MMWindowRowElement
- (BOOL)accessibilityPerformPress {
    MMWindowListView *list = self.list;
    if (!list.onPress) return NO;
    list.onPress(self.key);
    return YES;
}
@end

@implementation MMWindowListView (Input)

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

/// A press picks the row under it, and a press on the list's empty space, a header or the gap between groups, picks
/// none. The window decides what that means: MMWindowView -pressRow:.
- (void)pressAt:(NSPoint)p {
    MMWindowRow *row = NSPointInRect(p, self.bounds) ? [self rowAt:p] : nil;
    if (self.onPress) self.onPress(row.key);
}

- (void)mouseDown:(NSEvent *)e { [self pressAt:[self convertPoint:e.locationInWindow fromView:nil]]; }
/// The panel does not take the keyboard from the app in front, so the first press already picks a row.
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
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

#pragma mark Accessibility

/// One element per row, made only when asked for.
- (NSArray *)accessibilityChildren {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)_groups.count && i < (NSInteger)_frames.count; i++) {
        MMWindowGroup *g = _groups[i];
        NSRect box = [self boxOf:i];
        CGFloat off = _offsets[g.key].doubleValue;
        // In the order they are drawn, so VoiceOver goes down the list as the eye does. A row under a project's
        // sub-header says its project, which its name there leaves out.
        for (NSInteger r = 0; r < (NSInteger)g.rows.count; r++) {
            MMWindowRow *row = [self drawn:r in:i];
            NSMutableArray *say = [NSMutableArray arrayWithObjects:g.title, nil];
            if (g.grouped) [say addObject:row.project ?: MMWindowNoProject];
            [say addObject:[self nameOf:row in:g]];
            if (row.state.length) [say addObject:row.state];
            if (row.showsSize) [say addObject:MMWindowBytes(row.bytes, g.side == MMWindowDisk)];
            else if (row.sizeWord) [say addObject:@"size not measured yet"];
            if (row.needsYou) [say addObject:@"asks you"];
            if (row.inFix) [say addObject:@"in Fix Everything"];
            NSString *cpu = MMWindowCPU(row.cpuPercent);
            if (cpu) [say addObject:[NSString stringWithFormat:@"CPU %@ percent", cpu]];
            NSRect rr = NSIntersectionRect([self rowRect:r in:i box:box offset:off], box);
            NSRect screen = self.window ? NSAccessibilityFrameInView(self, rr) : NSZeroRect;
            MMWindowRowElement *el = [MMWindowRowElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:screen
                                                                                label:[say componentsJoinedByString:@", "] parent:self];
            el.key = row.key; el.list = self;
            el.accessibilitySelected = [row.key isEqualToString:self.hotKey];
            [out addObject:el];
        }
    }
    return out;
}

/// The active row, as VoiceOver asks for the list's selection.
- (NSArray *)accessibilitySelectedChildren {
    if (!self.hotKey) return @[];
    for (NSAccessibilityElement *el in self.accessibilityChildren) if (el.isAccessibilitySelected) return @[el];
    return @[];
}

@end
