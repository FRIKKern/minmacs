// A row's menu, like the Dock's menu for an app: MMWindowParts.h. A right-click, a control-click, the Menu key,
// Shift-F10 and VoiceOver's Show Menu open it on a row. It is a real NSMenu of the row's items, MMWindowRow.menu, which
// the feed made for what works on that row now. Opening it makes the row active and acts on nothing. A pick sends
// its item to the host, which runs it with "window" as who acted; "show-row" makes another row active here.
#import "UI/Window/MMWindowViewParts.h"

void (^MMWindowMenuPops)(NSMenu *menu, NSView *view, NSPoint at) = nil;

/// What an item of the menu stands for: the row and its model item.
@interface MMWindowMenuPick : NSObject
@property (copy) NSString *row;
@property (strong) MMWindowMenuItem *item;
@end
@implementation MMWindowMenuPick
@end

@implementation MMWindowView (Menu)

/// Wired once, from -initWithFrame: through the lists' blocks.
- (void)wireMenus {
    __weak typeof(self) me = self;
    for (MMWindowListView *l in @[_left, _right]) {
        l.onMenu = ^NSMenu *(NSString *key) { return [me menuForRow:key]; };
        l.onShowMenu = ^BOOL(NSString *key) { return [me showMenuForRow:key]; };
    }
}

- (NSMenu *)menuForRow:(NSString *)key {
    if (_quiet || _flips > 0 || self.showsSettings || self.showsWelcome || !key) return nil;
    MMWindowRow *row = [self.model row:key];
    if (!row) return nil;
    // As a press would: the row becomes the active one, blue, with its story. A menu on the active row keeps it.
    if (![_active isEqualToString:key]) { _hovered = nil; self.activeRow = key; }
    if (!row.menu.count) return nil;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:row.shownName];
    menu.autoenablesItems = NO;
    for (MMWindowMenuItem *i in row.menu) {
        // An alternate never stands alone: it shows in the place of the item before it while Option is held.
        if (i.alternate && !menu.itemArray.lastObject) continue;
        if (i.startsGroup && menu.numberOfItems) [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *m = [[NSMenuItem alloc] initWithTitle:i.title action:@selector(pickRowMenu:) keyEquivalent:@""];
        m.target = self;
        MMWindowMenuPick *pick = [MMWindowMenuPick new];
        pick.row = key; pick.item = i;
        m.representedObject = pick;
        m.toolTip = i.help;
        if (i.alternate) { m.alternate = YES; m.keyEquivalentModifierMask = NSEventModifierFlagOption; }
        else m.keyEquivalentModifierMask = 0;
        [menu addItem:m];
    }
    return menu;
}

/// The person's pick. The row is read again from the model that shows now: a row that left it takes no pick.
- (void)pickRowMenu:(NSMenuItem *)sender {
    MMWindowMenuPick *pick = [sender.representedObject isKindOfClass:MMWindowMenuPick.class] ? sender.representedObject : nil;
    if (!pick || ![self.model row:pick.row]) return;
    NSString *action = pick.item.action;
    if ([action isEqualToString:@"show-row"]) { if (pick.item.link) [self showRow:pick.item.link]; return; }
    if ([action isEqualToString:@"go-to"]) { [self goTo:pick.row]; return; }
    if ([self.host respondsToSelector:@selector(windowRow:item:)]) [self.host windowRow:pick.row item:action];
}

- (BOOL)showMenuForRow:(NSString *)key {
    NSMenu *menu = [self menuForRow:key];
    if (!menu) return NO;
    MMWindowListView *list = NSIsEmptyRect([_left frameOfRow:key]) ? _right : _left;
    [list reveal:key];
    NSRect f = [list frameOfRow:key];
    // Under the row's name, as a menu a keyboard opens stands under what it is for.
    NSPoint at = NSMakePoint(NSMinX(f) + 28, NSMaxY(f));
    if (MMWindowMenuPops) MMWindowMenuPops(menu, list, at);
    else [menu popUpMenuPositioningItem:nil atLocation:at inView:list];
    return YES;
}

- (BOOL)menuKey:(NSEvent *)e {
    NSEventModifierFlags flags = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagCapsLock);
    // 110 is the Menu key of a PC keyboard, 109 is F10.
    BOOL menuKey = e.keyCode == 110 && !flags, shiftF10 = e.keyCode == 109 && flags == NSEventModifierFlagShift;
    if (!menuKey && !shiftF10) return NO;
    NSString *key = _active ?: _hovered;
    if (key) [self showMenuForRow:key];
    return YES;
}

@end
