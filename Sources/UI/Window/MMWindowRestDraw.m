// The rest of the memory as the window draws it: each category's calm tint, shared by its mark, its slice of the
// ring and its line in the story, and its small mark. Drawn, never a logo. The tints are grays and soft hues, so the
// rest stays quieter than the groups a person acts on.
#import "UI/Window/MMWindowParts.h"

static NSColor *Soft(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:MMWindowContrast() ? 0.95 : 0.62];
}

static NSString *CategoryOf(NSString *key) {
    NSString *k = [key hasPrefix:@"insides:"] ? [key substringFromIndex:8] : key ?: @"";
    if ([k hasPrefix:@"rest:"]) k = [k substringFromIndex:5];
    NSRange bar = [k rangeOfString:@"|"];
    return bar.location == NSNotFound ? k : [k substringToIndex:bar.location];
}

NSColor *MMWindowRestTint(NSString *rowKey) {
    NSString *k = CategoryOf(rowKey);
    if ([k isEqualToString:@"macos"]) return Soft(178, 180, 198);
    if ([k isEqualToString:@"desktop"]) return Soft(176, 164, 226);
    if ([k isEqualToString:@"spotlight"]) return Soft(146, 178, 214);
    if ([k isEqualToString:@"siri"]) return Soft(206, 156, 214);
    if ([k isEqualToString:@"media"]) return Soft(218, 186, 146);
    if ([k isEqualToString:@"cloud"]) return Soft(150, 196, 232);
    if ([k isEqualToString:@"apple"]) return Soft(196, 196, 212);
    if ([k isEqualToString:@"browsers"]) return Soft(140, 202, 194);
    if ([k isEqualToString:@"developer"]) return Soft(168, 206, 150);
    if ([k isEqualToString:@"security"]) return Soft(222, 166, 166);
    return Soft(136, 138, 156);
}

static NSBezierPath *Line(CGFloat width) {
    NSBezierPath *p = [NSBezierPath bezierPath];
    p.lineWidth = width; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    return p;
}

void MMWindowDrawRestMark(NSString *category) {
    NSString *k = CategoryOf(category);
    NSColor *tint = [MMWindowRestTint(k) colorWithAlphaComponent:1];
    [[NSColor colorWithSRGBRed:46 / 255.0 green:47 / 255.0 blue:60 / 255.0 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 16, 16) xRadius:4.2 yRadius:4.2] fill];
    [tint setStroke]; [tint setFill];
    NSBezierPath *p = Line(1.3);
    if ([k isEqualToString:@"macos"]) {
        // A chip: a square with its pins.
        [p appendBezierPathWithRoundedRect:NSMakeRect(5.5, 5.5, 7, 7) xRadius:1.4 yRadius:1.4];
        for (CGFloat at = 7.3; at <= 10.8; at += 3.5) {
            [p moveToPoint:NSMakePoint(at, 3.6)]; [p lineToPoint:NSMakePoint(at, 5.5)];
            [p moveToPoint:NSMakePoint(at, 12.5)]; [p lineToPoint:NSMakePoint(at, 14.4)];
        }
    } else if ([k isEqualToString:@"desktop"]) {
        // A screen with the Dock along its foot.
        [p appendBezierPathWithRoundedRect:NSMakeRect(4, 4.6, 10, 8) xRadius:1.4 yRadius:1.4];
        [p moveToPoint:NSMakePoint(6.4, 10.6)]; [p lineToPoint:NSMakePoint(11.6, 10.6)];
    } else if ([k isEqualToString:@"spotlight"]) {
        // A magnifier.
        [p appendBezierPathWithOvalInRect:NSMakeRect(4.4, 4.4, 6.6, 6.6)];
        [p moveToPoint:NSMakePoint(10.1, 10.1)]; [p lineToPoint:NSMakePoint(13.4, 13.4)];
    } else if ([k isEqualToString:@"siri"]) {
        // A four-point sparkle.
        NSBezierPath *s = [NSBezierPath bezierPath];
        [s moveToPoint:NSMakePoint(9, 3.8)];
        [s curveToPoint:NSMakePoint(14.2, 9) controlPoint1:NSMakePoint(9.6, 7.6) controlPoint2:NSMakePoint(10.4, 8.4)];
        [s curveToPoint:NSMakePoint(9, 14.2) controlPoint1:NSMakePoint(10.4, 9.6) controlPoint2:NSMakePoint(9.6, 10.4)];
        [s curveToPoint:NSMakePoint(3.8, 9) controlPoint1:NSMakePoint(8.4, 10.4) controlPoint2:NSMakePoint(7.6, 9.6)];
        [s curveToPoint:NSMakePoint(9, 3.8) controlPoint1:NSMakePoint(7.6, 8.4) controlPoint2:NSMakePoint(8.4, 7.6)];
        [s fill];
        return;
    } else if ([k isEqualToString:@"media"]) {
        // A photo: a frame with a hill and a sun.
        [p appendBezierPathWithRoundedRect:NSMakeRect(4, 4.8, 10, 8.4) xRadius:1.4 yRadius:1.4];
        [p moveToPoint:NSMakePoint(5.2, 12)]; [p lineToPoint:NSMakePoint(8.2, 8.8)]; [p lineToPoint:NSMakePoint(10.4, 10.8)];
        [p lineToPoint:NSMakePoint(11.4, 9.9)]; [p lineToPoint:NSMakePoint(12.9, 11.6)];
        [p stroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(10.4, 6.2, 1.8, 1.8)] fill];
        return;
    } else if ([k isEqualToString:@"cloud"]) {
        // A cloud.
        [p moveToPoint:NSMakePoint(6, 12.4)];
        [p curveToPoint:NSMakePoint(6.4, 8.2) controlPoint1:NSMakePoint(3.6, 12.4) controlPoint2:NSMakePoint(3.6, 8.4)];
        [p curveToPoint:NSMakePoint(11.6, 7.6) controlPoint1:NSMakePoint(7, 5.2) controlPoint2:NSMakePoint(10.8, 5.2)];
        [p curveToPoint:NSMakePoint(12.2, 12.4) controlPoint1:NSMakePoint(14.4, 7.8) controlPoint2:NSMakePoint(14.6, 12.4)];
        [p closePath];
    } else if ([k isEqualToString:@"apple"]) {
        // Four small app tiles.
        for (CGFloat y = 4.6; y < 10; y += 4.8) for (CGFloat x = 4.6; x < 10; x += 4.8)
            [p appendBezierPathWithRoundedRect:NSMakeRect(x, y, 3.6, 3.6) xRadius:0.9 yRadius:0.9];
    } else if ([k isEqualToString:@"browsers"]) {
        // A globe.
        [p appendBezierPathWithOvalInRect:NSMakeRect(4, 4, 10, 10)];
        [p appendBezierPathWithOvalInRect:NSMakeRect(7, 4, 4, 10)];
        [p moveToPoint:NSMakePoint(4.2, 9)]; [p lineToPoint:NSMakePoint(13.8, 9)];
    } else if ([k isEqualToString:@"developer"]) {
        // Two chevrons.
        [p moveToPoint:NSMakePoint(7.2, 5.6)]; [p lineToPoint:NSMakePoint(4.2, 9)]; [p lineToPoint:NSMakePoint(7.2, 12.4)];
        [p moveToPoint:NSMakePoint(10.8, 5.6)]; [p lineToPoint:NSMakePoint(13.8, 9)]; [p lineToPoint:NSMakePoint(10.8, 12.4)];
    } else if ([k isEqualToString:@"security"]) {
        // A shield.
        [p moveToPoint:NSMakePoint(9, 3.8)]; [p lineToPoint:NSMakePoint(13.4, 5.4)];
        [p curveToPoint:NSMakePoint(9, 14.2) controlPoint1:NSMakePoint(13.4, 10) controlPoint2:NSMakePoint(11.6, 12.6)];
        [p curveToPoint:NSMakePoint(4.6, 5.4) controlPoint1:NSMakePoint(6.4, 12.6) controlPoint2:NSMakePoint(4.6, 10)];
        [p closePath];
    } else {
        // Three dots: more of all sorts.
        for (CGFloat x = 5.2; x < 13; x += 3.8) [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 1.1, 7.9, 2.2, 2.2)] fill];
        return;
    }
    [p stroke];
}
