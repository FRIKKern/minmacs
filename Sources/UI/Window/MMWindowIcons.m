// The window's small marks, drawn here: one per kind of row, and the gear and the power icon.
// None is a copy of a logo. An app shows its own icon, which macOS gives; until it arrives the app has a drawn mark.
#import "UI/Window/MMWindowParts.h"

static NSColor *RGB(CGFloat r, CGFloat g, CGFloat b) { return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }

#pragma mark Apps' own icons

static NSMutableDictionary<NSString *, id> *gAppIcons;   // bundle id to NSImage, or NSNull while it loads or when there is none
static void (^gOnLoad)(void);

void MMWindowIconsOnLoad(void (^block)(void)) { gOnLoad = [block copy]; }

/// The app's icon when it is already here. The first ask looks it up on a later turn of the main run loop, one app a
/// turn, so the first frame never waits and AppKit stays on main, invariant 3. Measured on the development Mac: about
/// 0.5 ms an app once the first lookup of the process is done, so no turn holds main for long.
static NSImage *AppIcon(NSString *bundleID) {
    if (!bundleID.length) return nil;
    if (!gAppIcons) gAppIcons = [NSMutableDictionary new];
    id have = gAppIcons[bundleID];
    if (have) return have == NSNull.null ? nil : have;
    gAppIcons[bundleID] = NSNull.null;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundleID];
        NSImage *icon = url ? [NSWorkspace.sharedWorkspace iconForFile:url.path] : nil;
        if (!icon) return;
        icon.size = NSMakeSize(32, 32);
        gAppIcons[bundleID] = icon;
        if (gOnLoad) gOnLoad();
    });
    return nil;
}

#pragma mark Marks

/// Runs the block with an 18 by 18 box, y down, laid over the rect.
static void InBox(NSRect rect, void (^draw)(void)) {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *t = [NSAffineTransform transform];
    [t translateXBy:rect.origin.x yBy:rect.origin.y];
    [t scaleXBy:rect.size.width / 18 yBy:rect.size.height / 18];
    [t concat];
    draw();
    [NSGraphicsContext restoreGraphicsState];
}

static void Tile(NSColor *fill) {
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 16, 16) xRadius:4.2 yRadius:4.2] fill];
}

static void Letter(NSString *s, NSColor *color) {
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightBold], NSForegroundColorAttributeName: color}];
    NSSize z = a.size;
    [a drawAtPoint:NSMakePoint(9 - z.width / 2, 9 - z.height / 2)];
}

static NSBezierPath *Stroke(CGFloat width) {
    NSBezierPath *p = [NSBezierPath bezierPath];
    p.lineWidth = width; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    return p;
}

/// A server: a tile in a color picked by the framework's name, with its first letter.
static void DrawServer(NSString *hint) {
    static NSArray<NSColor *> *tiles;
    if (!tiles) tiles = @[RGB(255, 71, 133), RGB(60, 60, 72), RGB(253, 96, 32), RGB(124, 92, 255), RGB(48, 132, 255),
                          RGB(232, 148, 30), RGB(20, 160, 140), RGB(200, 70, 190)];
    NSString *name = hint.length ? hint : @"";
    NSUInteger h = 0;
    for (NSUInteger i = 0; i < name.length; i++) h = h * 31 + [name characterAtIndex:i];
    Tile(name.length ? tiles[h % tiles.count] : RGB(70, 72, 88));
    Letter(name.length ? [name substringToIndex:1].uppercaseString : @":", NSColor.whiteColor);
}

/// An agent: a four-pointed spark on a dark disc.
static void DrawAgent(void) {
    [RGB(58, 38, 52) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1, 1, 16, 16)] fill];
    NSBezierPath *p = [NSBezierPath bezierPath];
    CGFloat c = 9, far = 6.2, near = 1.7;
    for (NSInteger i = 0; i < 8; i++) {
        CGFloat a = (CGFloat)(M_PI / 4 * i - M_PI / 2), r = i % 2 ? near : far;
        NSPoint q = NSMakePoint(c + r * cos(a), c + r * sin(a));
        if (i) [p lineToPoint:q]; else [p moveToPoint:q];
    }
    [p closePath];
    [RGB(238, 133, 181) setFill];
    [p fill];
}

/// A worktree: a branch that leaves the trunk.
static void DrawWorktree(void) {
    Tile(RGB(27, 58, 38));
    NSColor *ink = RGB(91, 214, 122);
    [ink setStroke];
    NSBezierPath *p = Stroke(1.4);
    [p moveToPoint:NSMakePoint(6.3, 6.8)]; [p lineToPoint:NSMakePoint(6.3, 11.2)];
    [p moveToPoint:NSMakePoint(11.7, 8.2)];
    [p curveToPoint:NSMakePoint(7.4, 11.8) controlPoint1:NSMakePoint(11.7, 10.6) controlPoint2:NSMakePoint(9.6, 11.2)];
    [p stroke];
    for (NSValue *v in @[[NSValue valueWithPoint:NSMakePoint(6.3, 5.4)], [NSValue valueWithPoint:NSMakePoint(6.3, 12.6)], [NSValue valueWithPoint:NSMakePoint(11.7, 6.8)]]) {
        NSPoint c = v.pointValue;
        NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 1.3, c.y - 1.3, 2.6, 2.6)];
        o.lineWidth = 1.3;
        [o stroke];
    }
}

/// A cache: a stack of three layers.
static void DrawCache(void) {
    Tile(RGB(64, 48, 20));
    [RGB(242, 181, 68) setStroke];
    NSBezierPath *p = Stroke(1.4);
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat y = 5.6 + 3.4 * i;
        [p moveToPoint:NSMakePoint(5, y)]; [p lineToPoint:NSMakePoint(13, y)];
    }
    [p stroke];
}

/// An app whose own icon is not here: a tile with the first letter of its name.
static void DrawApp(NSString *name) {
    Tile(RGB(40, 62, 108));
    Letter(name.length ? [name substringToIndex:1].uppercaseString : @"A", RGB(170, 200, 255));
}

/// A helper: a small ring, a part of something larger.
static void DrawHelper(void) {
    Tile(RGB(52, 54, 68));
    [RGB(190, 194, 214) setStroke];
    NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.8, 5.8, 6.4, 6.4)];
    o.lineWidth = 1.5;
    [o stroke];
}

/// A group of tabs: one tab over a page.
static void DrawTabs(void) {
    Tile(RGB(40, 62, 108));
    [RGB(170, 200, 255) setStroke];
    NSBezierPath *p = Stroke(1.3);
    [p moveToPoint:NSMakePoint(4.6, 12.8)]; [p lineToPoint:NSMakePoint(4.6, 6)]; [p lineToPoint:NSMakePoint(9, 6)];
    [p lineToPoint:NSMakePoint(9, 8.4)]; [p lineToPoint:NSMakePoint(13.4, 8.4)]; [p lineToPoint:NSMakePoint(13.4, 12.8)];
    [p closePath];
    [p stroke];
}

void MMWindowDrawDiamond(NSRect rect, NSColor *color) {
    CGFloat mx = NSMidX(rect), my = NSMidY(rect), r = MIN(rect.size.width, rect.size.height) * 0.39;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(mx, my - r)]; [p lineToPoint:NSMakePoint(mx + r, my)];
    [p lineToPoint:NSMakePoint(mx, my + r)]; [p lineToPoint:NSMakePoint(mx - r, my)];
    [p closePath];
    [color setFill];
    [p fill];
}

void MMWindowDrawIcon(MMWindowRow *row, NSRect rect, NSColor *backing) {
    NSImage *own = row.kind == MMWindowApp ? AppIcon(row.iconHint) : nil;
    if (own) {
        [own drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    } else {
        InBox(rect, ^{
            switch (row.kind) {
                case MMWindowServer:   DrawServer(row.iconHint); break;
                case MMWindowAgent:    DrawAgent(); break;
                case MMWindowApp:      DrawApp(row.name); break;
                case MMWindowHelper:   DrawHelper(); break;
                case MMWindowTabs:     DrawTabs(); break;
                case MMWindowWorktree: DrawWorktree(); break;
                case MMWindowCache:    DrawCache(); break;
            }
        });
    }
    if (!row.needsYou && !row.inFix) return;
    // The badge sits on the lower right corner, on a disc of the color behind the row, so it reads on any icon.
    CGFloat u = rect.size.width / 16;
    NSRect b = NSMakeRect(NSMaxX(rect) - 6 * u, NSMaxY(rect) - 7 * u, 11 * u, 11 * u);
    [backing setFill];
    [[NSBezierPath bezierPathWithOvalInRect:b] fill];
    if (row.needsYou) { MMWindowDrawDiamond(NSInsetRect(b, 0.5 * u, 0.5 * u), NSColor.whiteColor); return; }
    // What Fix Everything touches: a small orange triangle that points down.
    NSRect t = NSInsetRect(b, 2.2 * u, 2.6 * u);
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(NSMinX(t), NSMinY(t))]; [p lineToPoint:NSMakePoint(NSMaxX(t), NSMinY(t))];
    [p lineToPoint:NSMakePoint(NSMidX(t), NSMaxY(t))];
    [p closePath];
    [MMWindowColor(MMWindowInkFix) setFill];
    [p fill];
}

void MMWindowDrawGear(NSRect rect, NSColor *color) {
    NSPoint c = NSMakePoint(NSMidX(rect), NSMidY(rect));
    CGFloat u = MIN(rect.size.width, rect.size.height) / 15;
    [color setStroke];
    NSBezierPath *teeth = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 5 * u, c.y - 5 * u, 10 * u, 10 * u)];
    teeth.lineWidth = 2.3 * u;
    CGFloat dash[2] = {2.05 * u, 1.877 * u};
    [teeth setLineDash:dash count:2 phase:0];
    [teeth stroke];
    NSBezierPath *body = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 3.9 * u, c.y - 3.9 * u, 7.8 * u, 7.8 * u)];
    body.lineWidth = 1.3 * u;
    [body stroke];
    NSBezierPath *hub = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 1.5 * u, c.y - 1.5 * u, 3 * u, 3 * u)];
    hub.lineWidth = 1.2 * u;
    [hub stroke];
}

void MMWindowDrawPower(NSRect rect, NSColor *color) {
    NSPoint c = NSMakePoint(NSMidX(rect), NSMidY(rect));
    CGFloat u = MIN(rect.size.width, rect.size.height) / 15;
    [color setStroke];
    NSBezierPath *p = Stroke(1.4 * u);
    // An open ring with a bar through the gap at the top. The view is flipped, so the gap is at -90 degrees.
    [p appendBezierPathWithArcWithCenter:NSMakePoint(c.x, c.y + 0.7 * u) radius:4.8 * u startAngle:-54 endAngle:234 clockwise:NO];
    [p moveToPoint:NSMakePoint(c.x, c.y - 5.6 * u)]; [p lineToPoint:NSMakePoint(c.x, c.y - 0.6 * u)];
    [p stroke];
}
