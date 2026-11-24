// What the welcome's view and its controls share, MMWindowWelcome.m and MMWindowWelcomeControl.m. Only they import this.
#import "UI/Window/MMWindowParts.h"

__unused static NSColor *Soft(CGFloat alpha) { return [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.96 alpha:MMWindowContrast() ? MIN(1, alpha + 0.3) : alpha]; }
__unused static NSColor *Accent(void) { return [NSColor colorWithSRGBRed:1 green:0.604 blue:0.302 alpha:1]; }

__unused static NSAttributedString *Para(NSString *s, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat line, NSTextAlignment align) {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.lineBreakMode = NSLineBreakByWordWrapping; p.alignment = align;
    p.minimumLineHeight = line; p.maximumLineHeight = line;
    return [[NSAttributedString alloc] initWithString:s ?: @"" attributes:@{
        NSFontAttributeName: MMWindowFont(size, weight), NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: p}];
}

__unused static CGFloat Height(NSAttributedString *s, CGFloat width) {
    return ceil([s boundingRectWithSize:NSMakeSize(width, 2000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

/// Through the window's own drawing, so the checks read every string of the welcome too.
__unused static void DrawIn(NSAttributedString *s, NSRect r) { MMWindowDrawIn(s, r); }

typedef NS_ENUM(NSInteger, MMWelcomeKind) { MMWelcomeSwitch = 0, MMWelcomeStart };

/// The switch or Start: a real button that draws itself, so a press, Space and VoiceOver work.
@interface MMWelcomeControl : NSButton
@property MMWelcomeKind kind;
@property (copy) NSString *label, *explain;
@property (nonatomic) BOOL on;
@property (nonatomic) CGFloat knob;                     // 0 off, 1 on: where the switch's knob sits
@property NSRect home;                                  // its frame once it has risen in
/// One step of the switch's knob toward where its state has it. YES while it still moves.
- (BOOL)slide:(NSTimeInterval)dt;
@end
