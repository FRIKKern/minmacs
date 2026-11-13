// The Mac as a ring, 195-a's: memory by holder inside, the disk as the thin outer track. The dock draws it large and
// a row's story draws it small. Each row is an arc of its own with a hair of a gap, so the ring reads as many things;
// a row Fix Everything touches is orange. With a row pointed at, that row's arc is white and lifted and the rest step back.
#import "UI/Window/MMWindowParts.h"

static void Arc(NSPoint c, CGFloat radius, CGFloat width, CGFloat from, CGFloat sweep, NSColor *color) {
    if (sweep <= 0) return;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p appendBezierPathWithArcWithCenter:c radius:radius startAngle:from endAngle:from + sweep clockwise:NO];
    p.lineWidth = width;
    [color setStroke];
    [p stroke];
}

static MMWindowGroup *GroupOf(NSArray<MMWindowGroup *> *groups, NSString *key) {
    for (MMWindowGroup *g in groups) if ([g.key isEqualToString:key]) return g;
    return nil;
}

// Both tracks start at the lower left and run three quarters round.
static const CGFloat kStart = 135, kWhole = 270;

/// One track: its slices in order, each cut into its group's rows where the model holds them.
static void Track(NSArray<MMWindowSlice *> *slices, NSArray<MMWindowGroup *> *groups, uint64_t total, NSPoint c, CGFloat radius, CGFloat width,
                  MMWindowRow *lit, BOOL after, NSColor *rest) {
    BOOL hc = MMWindowContrast();
    Arc(c, radius, width, kStart, kWhole, [NSColor colorWithWhite:1 alpha:hc ? 0.2 : 0.07]);
    if (!total) return;
    CGFloat at = kStart, end = kStart + kWhole, back = lit ? 0.22 : 1;
    NSColor *fix = MMWindowColor(MMWindowInkFix);
    for (MMWindowSlice *s in slices) {
        CGFloat sweep = MIN(kWhole * s.bytes / (double)total, end - at);
        if (sweep <= 0) continue;
        if ([s.group isEqualToString:@"other"]) { Arc(c, radius, width, at, sweep, [rest colorWithAlphaComponent:rest.alphaComponent * (lit ? 0.5 : 1)]); at += sweep; continue; }
        NSColor *color = [MMWindowGroupColor(s.group) colorWithAlphaComponent:hc ? 1 : 0.8];
        CGFloat used = 0;
        NSArray<MMWindowRow *> *rows = GroupOf(groups, s.group).rows;
        for (NSUInteger i = 0; i < rows.count && used < sweep; i++) {
            MMWindowRow *r = rows[i];
            CGFloat part = MIN(kWhole * r.bytes / (double)total, sweep - used);
            // An arc under a seventh of a degree is no mark at this size. It still takes its place.
            // The Mac after Fix Everything: what a fix touches has left the ring, and its place is bare track.
            if (part >= 0.144 && !(after && r.inFix)) {
                CGFloat gap = MIN(part * 0.3, i + 1 == rows.count ? 1.8 : 0.43);
                if (lit && [r.key isEqualToString:lit.key]) Arc(c, radius + 2, width + 4, at + used, part - gap, NSColor.whiteColor);
                else Arc(c, radius, width, at + used, part - gap, [(r.inFix ? fix : color) colorWithAlphaComponent:(r.inFix ? 1 : color.alphaComponent) * back]);
            }
            used += part;
        }
        // What the group holds beyond its rows, as one arc.
        if (sweep - used > 0.144) Arc(c, radius, width, at + used, sweep - used, [color colorWithAlphaComponent:color.alphaComponent * back]);
        at += sweep;
    }
}

void MMWindowDrawRing(MMWindowModel *model, NSPoint center, BOOL small, MMWindowRow *_Nullable lit, BOOL after) {
    MMWindowRing *ring = model.ring;
    if (!ring) return;
    BOOL hc = MMWindowContrast();
    // 195-a's ring is 108 points across in the dock: memory at radius 37.6, 7 wide, the disk at 48.1, 2.4 wide.
    // The one in a row's story is 62 across: 20 and 6, 27.5 and 2.5.
    Track(ring.memory, model.memoryGroups, ring.memoryTotal, center, small ? 20 : 37.6, small ? 6 : 7.04, lit, after,
          [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.96 alpha:hc ? 0.45 : 0.2]);
    Track(ring.disk, model.diskGroups, ring.diskTotal, center, small ? 27.5 : 48.1, small ? 2.5 : 2.35, lit, after,
          [NSColor colorWithSRGBRed:242 / 255.0 green:181 / 255.0 blue:68 / 255.0 alpha:hc ? 0.55 : 0.3]);
}
