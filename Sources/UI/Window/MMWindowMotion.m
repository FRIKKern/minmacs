// The window's layer animations: the slow breath of the glow around Fix Everything at rest, the short flash under a
// row that is new, and Fix Everything's pulse as a press starts a run and its shine as the run ends. All run in the
// window server, so no timer ticks and nothing is drawn again for them. None runs under Reduce Motion, and none is
// there for a view with no layer, as in the render tool.
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

/// Takes a layer away once its one animation is over.
static void Drop(CALayer *layer, NSTimeInterval after) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [layer removeFromSuperlayer]; });
}

static BOOL Moves(NSView *view) { return view.layer && view.window.isVisible && !MMWindowReduceMotion() && Named(@"CALayer"); }

void MMWindowPulse(NSView *view, NSRect pill, NSColor *color) {
    if (!Moves(view)) return;
    CALayer *ring = [Named(@"CALayer") layer];
    ring.frame = InLayer(view, pill);
    ring.cornerRadius = pill.size.height / 2;
    ring.borderWidth = 2;
    ring.borderColor = color.CGColor;
    ring.opacity = 0;
    ring.name = @"pulse";
    CABasicAnimation *fade = Fade(@"opacity", 0.8, 0, 0.6, NO);
    CABasicAnimation *grow = Fade(@"transform.scale", 1, 1.14, 0.6, NO);
    CAAnimationGroup *both = [Named(@"CAAnimationGroup") animation];
    both.animations = @[fade, grow]; both.duration = 0.6;
    [ring addAnimation:both forKey:@"pulse"];
    [view.layer addSublayer:ring];
    Drop(ring, 0.7);
}

void MMWindowShine(NSView *view, NSRect pill) {
    if (!Moves(view) || !Named(@"CAGradientLayer")) return;
    CALayer *clip = [Named(@"CALayer") layer];
    clip.frame = InLayer(view, pill);
    clip.cornerRadius = pill.size.height / 2;
    clip.masksToBounds = YES;
    clip.name = @"shine";
    CAGradientLayer *light = [Named(@"CAGradientLayer") layer];
    CGFloat w = pill.size.width * 0.42;
    light.frame = CGRectMake(-w, 0, w, pill.size.height);
    light.startPoint = CGPointMake(0, 0.5); light.endPoint = CGPointMake(1, 0.5);
    light.colors = @[(__bridge id)[NSColor colorWithWhite:1 alpha:0].CGColor, (__bridge id)[NSColor colorWithWhite:1 alpha:0.55].CGColor,
                     (__bridge id)[NSColor colorWithWhite:1 alpha:0].CGColor];
    [clip addSublayer:light];
    CABasicAnimation *run = [Named(@"CABasicAnimation") animationWithKeyPath:@"position.x"];
    run.fromValue = @(-w / 2); run.toValue = @(pill.size.width + w / 2); run.duration = 0.85;
    run.timingFunction = [Named(@"CAMediaTimingFunction") functionWithControlPoints:0.3 :0 :0.2 :1];
    light.position = CGPointMake(pill.size.width + w / 2, pill.size.height / 2);
    [light addAnimation:run forKey:@"shine"];
    [view.layer addSublayer:clip];
    Drop(clip, 0.95);
}
