#import "MMStatusItem.h"

const CGFloat MMStatusSymbolSize = 14;

NSString *MMStatusAutosaveName(NSString *expert) {
    NSMutableString *s = [NSMutableString stringWithString:@"minmacs."];
    for (NSUInteger k = 0; k < expert.length; k++) {
        unichar c = [expert characterAtIndex:k];
        if ([NSCharacterSet.alphanumericCharacterSet characterIsMember:c] && c < 128) [s appendFormat:@"%C", c];
    }
    return s.lowercaseString;
}

NSString *MMStatusLabel(NSString *expert, NSString *state) {
    return state.length ? [NSString stringWithFormat:@"%@, %@", expert, state] : (expert ?: @"");
}

NSImage *MMStatusImage(NSString *symbol, NSString *label) {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
    img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:MMStatusSymbolSize weight:NSFontWeightRegular]];
    img.template = YES;
    img.accessibilityDescription = label;   // the symbol configuration copy can drop it
    return img;
}

NSString *MMStatusBadge(NSString *badge) {
    NSString *b = [badge stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    // DESIGN.md allows a number beside the icon and nothing else, such as "3" or "99+".
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:@"0123456789+"].invertedSet;
    return b.length && b.length <= 3 && [b rangeOfCharacterFromSet:other].location == NSNotFound ? b : nil;
}

NSStatusItem *MMMakeStatusItem(NSString *expert, NSString *symbol) {
    NSStatusItem *i = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    i.autosaveName = MMStatusAutosaveName(expert);
    i.behavior = NSStatusItemBehaviorRemovalAllowed;
    MMUpdateStatusItem(i, expert, symbol, nil, nil);
    return i;
}

void MMUpdateStatusItem(NSStatusItem *item, NSString *expert, NSString *symbol, NSString *state, NSString *badge) {
    NSString *label = MMStatusLabel(expert, state), *b = MMStatusBadge(badge);
    item.button.image = MMStatusImage(symbol, label);
    item.button.imagePosition = NSImageLeft;
    item.button.title = b ? [@" " stringByAppendingString:b] : @"";
    if (b) item.button.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    item.length = b ? NSVariableStatusItemLength : NSSquareStatusItemLength;
    item.button.accessibilityLabel = label;
    item.button.toolTip = label;
}
