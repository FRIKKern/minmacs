// The window's two layer animations, 195-a's: the slow breath of the glow around Fix Everything at rest, and the
// short flash under a row that is new. Both run in the window server, so no timer ticks and nothing is drawn again
// for them. Neither runs under Reduce Motion, and neither is there for a view with no layer, as in the render tool.
// The Core Animation classes are found by name: tools that link Cocoa alone still link, and AppKit always loads them.
#import "UI/Window/MMWindowParts.h"
#import <QuartzCore/QuartzCore.h>

static Class Named(NSString *name) { return NSClassFromString(name); }

/// A rect of a view as its layer's sublayers need it. In a window AppKit lays the sublayers of a flipped view's
/// layer out top down, as the view itself counts, though the layer does not say it is flipped: seen in a window
/// ordered in off screen, where a rect turned over landed a row too low. So the view's own rect is the one.
static CGRect InLayer(NSView *view, NSRect rect) { return NSRectToCGRect(rect); }

static id Fade(NSString *path, CGFloat from, CGFloat to, NSTimeInterval seconds, BOOL easeBoth) {
    CABasicAnimation *a = [Named(@"CABasicAnimation") animationWithKeyPath:path];
    a.fromValue = @(from); a.toValue = @(to); a.duration = seconds;
    a.timingFunction = easeBoth ? [Named(@"CAMediaTimingFunction") functionWithControlPoints:0.42 :0 :0.58 :1]
                                : [Named(@"CAMediaTimingFunction") functionWithControlPoints:0.3 :0.7 :0.2 :1];
    return a;
}

CALayer *MMWindowBreathLayer(NSView *view, NSBitmapImageRep *glow, NSRect rect, NSTimeInterval period) {
    if (!view.layer || !glow || MMWindowReduceMotion() || !Named(@"CALayer")) return nil;
    CALayer *layer = [Named(@"CALayer") layer];
    layer.frame = InLayer(view, rect);
    layer.contents = (__bridge id)glow.CGImage;
    layer.opacity = 0;
    layer.zPosition = -1;
    CABasicAnimation *breath = Fade(@"opacity", 0, 1, period / 2, YES);
    breath.autoreverses = YES; breath.repeatCount = HUGE_VALF;
    [layer addAnimation:breath forKey:@"breath"];
    [view.layer addSublayer:layer];
    return layer;
}

void MMWindowFlash(NSView *view, NSRect rect) {
    if (!view.layer || !view.window.isVisible || MMWindowReduceMotion() || !Named(@"CALayer")) return;
    CALayer *layer = [Named(@"CALayer") layer];
    layer.frame = InLayer(view, rect);
    layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.12].CGColor;
    layer.cornerRadius = 6;
    layer.opacity = 0;
    layer.name = @"flash";
    [layer addAnimation:Fade(@"opacity", 1, 0, 0.7, NO) forKey:@"flash"];
    [view.layer addSublayer:layer];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [layer removeFromSuperlayer]; });
}
