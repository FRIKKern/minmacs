// The arrow keys of the whole window, MMWindowViewParts.h: they move the active row between the two sides.
#import "UI/Window/MMWindowViewParts.h"
#import "UI/Window/MMWindowTree.h"

@implementation MMWindowView (Keys)

/// The arrow keys move the active row: up and down in its side, group after group, left and right to the row of
/// the other side at its height. With none active, the first row of the side the key points to. Scrolls it in view.
- (BOOL)arrow:(unsigned short)code {
    if (code < 123 || code > 126) return NO;
    // → opens a row with insides and ← closes it, or goes up to the row it is in, MMWindowTree.m.
    if ([self treeArrow:code]) return YES;
    NSArray<NSString *> *left = _left.rowKeys, *right = _right.rowKeys;
    BOOL onLeft = _active && [left containsObject:_active], onRight = _active && [right containsObject:_active];
    NSString *next = nil;
    if (!onLeft && !onRight) next = code == 124 ? right.firstObject ?: left.firstObject : left.firstObject ?: right.firstObject;
    else if (code == 125 || code == 126) {
        NSArray<NSString *> *side = onLeft ? left : right;
        NSInteger at = (NSInteger)[side indexOfObject:_active] + (code == 125 ? 1 : -1);
        next = side[(NSUInteger)MIN(MAX(at, 0), (NSInteger)side.count - 1)];
    } else if ((code == 123 && onRight) || (code == 124 && onLeft)) {
        MMWindowListView *from = onLeft ? _left : _right, *to = onLeft ? _right : _left;
        CGFloat y = NSMidY([from frameOfRow:_active]), best = CGFLOAT_MAX;
        for (NSString *k in to.rowKeys) {
            NSRect f = [to frameOfRow:k];
            if (NSIsEmptyRect(f) || fabs(NSMidY(f) - y) >= best) continue;
            best = fabs(NSMidY(f) - y); next = k;
        }
        next = next ?: to.rowKeys.firstObject ?: _active;
    } else next = _active;
    if (next) { [_left reveal:next]; [_right reveal:next]; }
    // The keyboard picks what the middle tells: the row under the pointer gives it back once the pointer moves again.
    _hovered = nil;
    self.activeRow = next;
    return YES;
}

@end
