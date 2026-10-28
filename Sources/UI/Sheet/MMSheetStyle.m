// The sheet's colors, fonts and sizes, from 54-a.html's :root. MMSheetUI.h says what each is for.
#import "UI/Sheet/MMSheetUI.h"

const NSSize MMSheetSize = {760, 580};
const NSRect MMSheetBodyFrame = {{28, 20}, {704, 492}};   // flipped views: 68 from the top, 20 from the bottom

static NSColor *RGBA(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a];
}

static BOOL HighContrast(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;
}

NSColor *MMSheetColorFor(MMSheetColor c) {
    BOOL hc = HighContrast();
    switch (c) {
        case MMSheetGlass:      return RGBA(28, 29, 38, hc ? 0.98 : 0.90);
        case MMSheetLine:       return RGBA(255, 255, 255, hc ? 0.22 : 0.07);
        case MMSheetText:       return RGBA(255, 255, 255, hc ? 1.0 : 0.94);
        case MMSheetText2:      return RGBA(235, 235, 245, hc ? 0.82 : 0.62);
        case MMSheetText3:      return RGBA(235, 235, 245, hc ? 0.62 : 0.36);
        case MMSheetRowHover:   return RGBA(44, 44, 58, 1);
        case MMSheetWorkstream: return RGBA(255, 138, 102, 1);
        case MMSheetAgent:      return RGBA(238, 133, 181, 1);
        case MMSheetApp:        return RGBA(91, 155, 255, 1);
        case MMSheetServer:     return RGBA(63, 208, 184, 1);
        case MMSheetWorktree:   return RGBA(76, 201, 107, 1);
        case MMSheetDisk:       return RGBA(242, 181, 68, 1);
    }
    return NSColor.whiteColor;
}

NSColor *MMSheetTabColor(MMSheetTab tab) {
    switch (tab) {
        case MMSheetTabWorkstreams: return MMSheetColorFor(MMSheetWorkstream);
        case MMSheetTabAgents:      return MMSheetColorFor(MMSheetAgent);
        case MMSheetTabPerformance: return MMSheetColorFor(MMSheetApp);
        case MMSheetTabServers:     return MMSheetColorFor(MMSheetServer);
        case MMSheetTabWorktrees:   return MMSheetColorFor(MMSheetWorktree);
        case MMSheetTabDisk:        return MMSheetColorFor(MMSheetDisk);
        case MMSheetTabSettings:    return RGBA(199, 201, 214, 1);
    }
    return NSColor.whiteColor;
}

NSFont *MMSheetFont(CGFloat size, NSFontWeight weight) {
    NSFont *f = [NSFont systemFontOfSize:size weight:weight];
    // Tabular digits, so numbers that tick do not shift the text beside them.
    NSFontDescriptor *d = [f.fontDescriptor fontDescriptorByAddingAttributes:@{
        NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
                                            NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
    return [NSFont fontWithDescriptor:d size:size] ?: f;
}
