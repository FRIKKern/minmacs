// A row's menu, like the Dock's menu for an app: a right-click, a control-click, the Menu key, Shift-F10 and
// VoiceOver's Show Menu open a real NSMenu of the row's items, MMWindowRow.menu. An NSMenu draws in its own window, so
// no PNG shows it: these checks read the menu the window builds, item by item, and what a pick sends. tools/render.m
// includes this file after render-window-ask.m and uses its Check, PolishView, PolishHost, WindowLists and PressList.
// It is not built on its own.

/// The host of PolishHost, which also counts the picks of a row's menu.
@interface MenuHost : PolishHost
@property NSMutableArray<NSString *> *picks;
@property NSMutableArray<NSString *> *goes;
@end
@implementation MenuHost
- (instancetype)init { if ((self = [super init])) { _picks = [NSMutableArray new]; _goes = [NSMutableArray new]; } return self; }
- (void)windowRow:(NSString *)rowKey item:(NSString *)action { [self.picks addObject:[NSString stringWithFormat:@"%@ %@", rowKey, action]]; }
- (void)windowGoTo:(NSString *)rowKey { [self.goes addObject:rowKey]; }
@end

static MMWindowMenuItem *MenuOf(NSString *action, NSString *title, BOOL alternate, BOOL group) {
    MMWindowMenuItem *i = [MMWindowMenuItem action:action title:title];
    i.alternate = alternate; i.startsGroup = group;
    return i;
}

/// The busy day with the menus the feed gives a server and an app, and an agent with none.
static MMWindowModel *MenuModel(void) {
    MMWindowModel *m = MMWindowFixture(@"busy");
    MMWindowMenuItem *agent = MenuOf(@"show-row", @"Show Agent", NO, YES);
    agent.link = @"agent:4";
    [m row:@"server:6006"].menu = @[MenuOf(@"open-url", @"Open in Browser", NO, NO), MenuOf(@"copy-url", @"Copy URL", NO, NO),
                                    MenuOf(@"stop", @"Stop", NO, YES), MenuOf(@"force-stop", @"Force Stop", YES, NO),
                                    MenuOf(@"keep", @"Keep for 4 Hours", NO, NO), agent, MenuOf(@"reveal", @"Show in Finder", NO, NO)];
    [m row:@"server:3000"].menu = @[MenuOf(@"stop", @"Stop", NO, NO), MenuOf(@"force-stop", @"Force Stop", YES, NO)];
    return m;
}

/// A menu as one line: items by " | ", a separator as " / ", an alternate as "[Option Title]".
static NSString *MenuLine(NSMenu *menu) {
    if (!menu) return @"(none)";
    NSMutableString *out = [NSMutableString new];
    BOOL gap = NO;
    for (NSMenuItem *i in menu.itemArray) {
        if (i.isSeparatorItem) { gap = YES; continue; }
        if (i.isAlternate) {
            [out appendFormat:@" [%@%@]", i.keyEquivalentModifierMask == NSEventModifierFlagOption ? @"Option " : @"?", i.title];
            continue;
        }
        if (out.length) [out appendString:gap ? @" / " : @" | "];
        [out appendString:i.title];
        gap = NO;
    }
    return out;
}

static NSEvent *MenuKeyEvent(unsigned short code, NSEventModifierFlags flags, unichar ch) {
    NSString *s = [NSString stringWithCharacters:&ch length:1];
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags | NSEventModifierFlagFunction timestamp:0 windowNumber:0
                             context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:code];
}

static void WindowMenuChecks(void) {
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.model = MenuModel();
    MenuHost *host = [MenuHost new];
    v.host = host;
    NSPoint at, other;
    MMWindowListView *l = PressList(v, @"server:6006", &at);
    (void)PressList(v, @"agent:4", &other);

    // A right-click on a row: the row is active, as a press makes it, and the menu is its items, Force Stop under Option.
    NSMenu *menu = [l menuAt:at];
    BOOL active = [v.activeRow isEqualToString:@"server:6006"] && [l.hotKey isEqualToString:@"server:6006"];
    Check(active && [MenuLine(menu) isEqualToString:@"Open in Browser | Copy URL / Stop [Option Force Stop] | Keep for 4 Hours / Show Agent | Show in Finder"],
          @"window menu: a right-click on a row opens its menu and makes the row active, with the alternate under Option", MenuLine(menu));
    Check(host.picks.count == 0 && host.fixes == 0 && host.stops == 0 && host.undos == 0,
          @"window menu: opening the menu acts on nothing", [host.picks componentsJoinedByString:@" | "]);
    // A second right-click on the active row keeps it active: a menu never lets the row go, as a second press would.
    menu = [l menuAt:at];
    Check([v.activeRow isEqualToString:@"server:6006"] && menu, @"window menu: a right-click on the active row keeps it active", v.activeRow ?: @"none");

    // Each item's pick sends its own action for that row, the alternate its own too, and Show Agent makes that row active here.
    for (NSMenuItem *i in menu.itemArray) if (!i.isSeparatorItem && ![i.title isEqualToString:@"Show Agent"]) [menu performActionForItemAtIndex:[menu indexOfItem:i]];
    Check([[host.picks componentsJoinedByString:@" | "] isEqualToString:@"server:6006 open-url | server:6006 copy-url | server:6006 stop | server:6006 force-stop | server:6006 keep | server:6006 reveal"],
          @"window menu: each pick sends its item's action for its row, the alternate as its own", [host.picks componentsJoinedByString:@" | "]);
    NSInteger show = [menu indexOfItemWithTitle:@"Show Agent"];
    NSUInteger picks = host.picks.count;
    if (show >= 0) [menu performActionForItemAtIndex:show];
    Check(show >= 0 && [v.activeRow isEqualToString:@"agent:4"] && host.picks.count == picks,
          @"window menu: Show Agent makes the agent's row the active one, in the window, and sends nothing", v.activeRow ?: @"none");

    // A row with no menu: a right-click still makes it active, and no menu opens.
    v.activeRow = nil;
    NSMenu *none = [PressList(v, @"agent:4", NULL) menuAt:other];
    Check(!none && [v.activeRow isEqualToString:@"agent:4"], @"window menu: a row with no menu opens none, and the right-click still makes it active", v.activeRow ?: @"none");

    // The keyboard: Shift-F10 and the Menu key open the active row's menu under it, and other keys do not.
    __block NSMutableArray<NSString *> *popped = [NSMutableArray new];
    MMWindowMenuPops = ^(NSMenu *m, NSView *view, NSPoint p) { [popped addObject:[NSString stringWithFormat:@"%@ %@", [view isKindOfClass:MMWindowListView.class] ? @"list" : @"?", MenuLine(m)]]; };
    v.activeRow = @"server:3000";
    [v keyDown:MenuKeyEvent(109, NSEventModifierFlagShift, NSF10FunctionKey)];
    [v keyDown:MenuKeyEvent(110, 0, NSMenuFunctionKey)];
    [v keyDown:MenuKeyEvent(109, 0, NSF10FunctionKey)];
    Check([[popped componentsJoinedByString:@" | "] isEqualToString:@"list Stop [Option Force Stop] | list Stop [Option Force Stop]"] && [v.activeRow isEqualToString:@"server:3000"],
          @"window menu: Shift-F10 and the Menu key open the active row's menu, and F10 alone does not", [popped componentsJoinedByString:@" | "]);

    // VoiceOver: Show Menu on a row's element opens that row's menu and makes it the active one.
    [popped removeAllObjects];
    v.activeRow = nil;
    NSAccessibilityElement *el = nil;
    for (MMWindowListView *list in WindowLists(v))
        for (NSAccessibilityElement *e in list.accessibilityChildren) if ([e.accessibilityLabel containsString:[v.model row:@"server:6006"].shownName]) el = e;
    BOOL said = [el accessibilityPerformShowMenu];
    Check(said && popped.count == 1 && [popped.firstObject hasPrefix:@"list Open in Browser"] && [v.activeRow isEqualToString:@"server:6006"],
          @"window menu: VoiceOver's Show Menu on a row opens its menu and makes the row active", [popped componentsJoinedByString:@" | "]);

    // Settings takes no menu, and the welcome none either.
    [popped removeAllObjects];
    v.showsSettings = YES;
    NSMenu *inSettings = [v menuForRow:@"server:6006"];
    v.showsSettings = NO;
    Check(!inSettings, @"window menu: Settings opens no row's menu", MenuLine(inSettings));
    MMWindowMenuPops = nil;
}
