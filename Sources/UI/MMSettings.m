#import "MMSettings.h"
#import "Core/MMExpert.h"   // the MMPrefSpec data class only; this file draws it and never needs the rest of Core

const CGFloat MMSettingsWidth = 540;
static const CGFloat kInset = 24;
static const CGFloat kButtonWidth = 110;

@implementation MMSettingsExpert
+ (instancetype)expert:(NSString *)expert name:(NSString *)name symbol:(NSString *)symbol {
    MMSettingsExpert *e = [self new];
    e.expert = expert; e.name = name; e.symbol = symbol; e.iconVisible = YES;
    return e;
}
@end

NSArray<NSString *> *MMSettingsModels(void) { return @[@"auto", @"haiku", @"sonnet", @"opus", @"luna"]; }

NSString *MMSettingsModelTitle(NSString *model) {
    NSDictionary *t = @{@"auto": @"Auto: Haiku, Then Luna", @"haiku": @"Haiku", @"sonnet": @"Sonnet", @"opus": @"Opus", @"luna": @"Luna"};
    return t[model.lowercaseString ?: @""] ?: model;
}

NSArray<NSString *> *MMSettingsModes(void) { return @[@"idle", @"proactive", @"eager"]; }

NSString *MMSettingsPaneTitle(MMSettingsPane pane) {
    switch (pane) {
        case MMSettingsOverview: return @"Overview";
        case MMSettingsExperts: return @"Experts";
        case MMSettingsGeneral: return @"General";
    }
    return @"";
}

static NSString *PaneSymbol(MMSettingsPane pane) {
    switch (pane) {
        case MMSettingsOverview: return @"square.grid.2x2";
        case MMSettingsExperts: return @"slider.horizontal.3";
        case MMSettingsGeneral: return @"gearshape";
    }
    return @"gearshape";
}

#pragma mark Small views

static NSTextField *Label(NSString *s, NSFont *font, NSColor *color) {
    NSTextField *t = [NSTextField labelWithString:s ?: @""];
    t.font = font; t.textColor = color;
    t.lineBreakMode = NSLineBreakByTruncatingTail;
    return t;
}

/// Text that wraps at the pane's width, for the sentences that explain a setting.
static NSTextField *Note(NSString *s, CGFloat width) {
    NSTextField *t = [NSTextField wrappingLabelWithString:s ?: @""];
    t.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    t.textColor = NSColor.secondaryLabelColor;
    t.preferredMaxLayoutWidth = width;
    t.selectable = NO;
    // A fixed width, so the label wraps and its height grows to hold every line.
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [t.widthAnchor constraintEqualToConstant:width].active = YES;
    return t;
}

static NSFont *Body(void) { return [NSFont systemFontOfSize:NSFont.systemFontSize]; }

/// A pane: a vertical stack at the window's width, with the window's margins.
static NSStackView *Pane(NSArray<NSView *> *views) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = 16;
    s.edgeInsets = NSEdgeInsetsMake(20, kInset, 24, kInset);
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [s.widthAnchor constraintEqualToConstant:MMSettingsWidth].active = YES;
    return s;
}

static NSBox *Line(void) {
    NSBox *b = [NSBox new];
    b.boxType = NSBoxSeparator;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:MMSettingsWidth - 2 * kInset].active = YES;
    return b;
}

@interface MMSettings () <NSToolbarDelegate, NSWindowDelegate>
@end

@implementation MMSettings {
    NSWindow *_window;
    MMSettingsPane _pane;
    NSString *_expertPane;
}

- (instancetype)init {
    if ((self = [super init])) { _model = @"auto"; _experts = @[]; }
    return self;
}

- (NSWindow *)window { return _window; }
- (MMSettingsPane)pane { return _pane; }
- (NSString *)expertPane { return _expertPane; }

- (MMSettingsExpert *)expertNamed:(NSString *)id {
    for (MMSettingsExpert *e in _experts) if ([e.expert isEqualToString:id]) return e;
    return nil;
}

#pragma mark Overview

/// Every expert with its state, whether or not its icon fits in the menu bar. The system hides icons that
/// do not fit and still reports them visible, so this pane is how a person reaches an expert whose icon is gone.
- (NSView *)overview {
    CGFloat textWidth = MMSettingsWidth - 2 * kInset;
    NSMutableArray *rows = [NSMutableArray new];
    for (MMSettingsExpert *e in _experts) {
        NSImage *img = [NSImage imageWithSystemSymbolName:e.symbol ?: @"circle" accessibilityDescription:e.name];
        img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular]];
        NSImageView *iv = [NSImageView imageViewWithImage:img ?: [NSImage new]];
        iv.contentTintColor = NSColor.secondaryLabelColor;
        [iv.widthAnchor constraintEqualToConstant:28].active = YES;

        NSTextField *name = Label(e.name, [NSFont boldSystemFontOfSize:NSFont.systemFontSize], NSColor.labelColor);
        NSString *line = e.headline.length ? e.headline : @"Nothing to show yet";
        if (!e.iconVisible) line = [line stringByAppendingString:@" · icon hidden"];
        NSTextField *head = Label(line, Body(), NSColor.secondaryLabelColor);
        NSMutableArray *text = [NSMutableArray arrayWithObjects:name, head, nil];
        // The row is the symbol, the words and the button, with 12 points between them.
        if (e.summary.length) [text addObject:Note(e.summary, textWidth - 28 - 12 - 12 - kButtonWidth)];
        NSStackView *words = [NSStackView stackViewWithViews:text];
        words.orientation = NSUserInterfaceLayoutOrientationVertical;
        words.alignment = NSLayoutAttributeLeading;
        words.spacing = 2;
        [words setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSButton *open = [NSButton buttonWithTitle:@"Show Menu" target:self action:@selector(openMenu:)];
        open.identifier = e.expert;
        open.enabled = self.onOpenMenu != nil;
        open.translatesAutoresizingMaskIntoConstraints = NO;
        [open.widthAnchor constraintEqualToConstant:kButtonWidth].active = YES;

        NSStackView *row = [NSStackView stackViewWithViews:@[iv, words, open]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeTop;
        row.spacing = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row.widthAnchor constraintEqualToConstant:textWidth].active = YES;
        // The words take a fixed width, so every button sits at the right edge.
        words.translatesAutoresizingMaskIntoConstraints = NO;
        [words.widthAnchor constraintEqualToConstant:textWidth - 28 - 12 - 12 - kButtonWidth].active = YES;
        if (rows.count) [rows addObject:Line()];
        [rows addObject:row];
    }
    if (!rows.count) [rows addObject:Label(@"No expert is running yet.", Body(), NSColor.secondaryLabelColor)];
    [rows addObject:Note(@"macOS hides menu bar icons that do not fit and still reports them as shown, so every expert is listed here. "
                         @"Open MinMacs again to come back to this pane.", textWidth)];
    return Pane(rows);
}

- (void)openMenu:(NSButton *)b { if (self.onOpenMenu) self.onOpenMenu(b.identifier, b); }

#pragma mark Experts

- (NSView *)expertsPane {
    CGFloat textWidth = MMSettingsWidth - 2 * kInset;
    NSGridView *g = [NSGridView gridViewWithNumberOfColumns:3 rows:0];
    g.rowSpacing = 10; g.columnSpacing = 18;
    NSTextField *h1 = Label(@"Show Icon", [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightMedium], NSColor.secondaryLabelColor);
    NSTextField *h2 = Label(@"Mode", [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightMedium], NSColor.secondaryLabelColor);
    [g addRowWithViews:@[[NSGridCell emptyContentView], h1, h2]];
    for (MMSettingsExpert *e in _experts) {
        NSTextField *name = Label(e.name, Body(), NSColor.labelColor);
        NSButton *show = [NSButton checkboxWithTitle:@"" target:self action:@selector(iconChanged:)];
        show.identifier = e.expert;
        show.state = e.iconVisible ? NSControlStateValueOn : NSControlStateValueOff;
        show.enabled = self.onIcon != nil;
        show.accessibilityLabel = [NSString stringWithFormat:@"Show the %@ icon", e.name];
        NSView *mode;
        if (e.mode) {
            NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            for (NSString *m in MMSettingsModes()) [p addItemWithTitle:m.capitalizedString];
            NSUInteger i = [MMSettingsModes() indexOfObject:e.mode.lowercaseString];
            [p selectItemAtIndex:i == NSNotFound ? 1 : (NSInteger)i];
            p.identifier = e.expert; p.target = self; p.action = @selector(modeChanged:);
            p.enabled = self.onMode != nil;
            p.accessibilityLabel = [NSString stringWithFormat:@"%@ mode", e.name];
            p.translatesAutoresizingMaskIntoConstraints = NO;
            [p.widthAnchor constraintEqualToConstant:130].active = YES;
            mode = p;
        } else {
            mode = Label(@"Follows the agents", Body(), NSColor.secondaryLabelColor);
        }
        [g addRowWithViews:@[name, show, mode]];
    }
    [g columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [g columnAtIndex:1].xPlacement = NSGridCellPlacementCenter;
    [g columnAtIndex:2].xPlacement = NSGridCellPlacementLeading;
    [g columnAtIndex:0].width = 150;
    g.rowAlignment = NSGridRowAlignmentFirstBaseline;
    // The column titles sit close above the rows they name.
    [g rowAtIndex:0].rowAlignment = NSGridRowAlignmentNone;
    [g rowAtIndex:0].yPlacement = NSGridCellPlacementBottom;

    NSTextField *modes = Note(@"Idle reports and acts on nothing. Proactive acts on clear cases only, such as a merged worktree "
                              @"untouched for a week. Eager acts on everything a review cannot show is still in use. "
                              @"No mode acts on its own during the first day.", textWidth);
    NSTextField *icons = Note(@"A hidden icon keeps its expert running. Its findings stay in the Overview pane, the CLI and notifications.", textWidth);
    return Pane(@[g, Line(), modes, icons]);
}

- (void)iconChanged:(NSButton *)b {
    BOOL on = b.state == NSControlStateValueOn;
    [self expertNamed:b.identifier].iconVisible = on;
    if (self.onIcon) self.onIcon(b.identifier, on);
}

- (void)modeChanged:(NSPopUpButton *)p {
    NSString *m = MMSettingsModes()[(NSUInteger)MAX(0, p.indexOfSelectedItem)];
    [self expertNamed:p.identifier].mode = m;
    if (self.onMode) self.onMode(p.identifier, m);
}

#pragma mark An expert's own pane

/// The control of one pref: a menu of its choices, or a checkbox for a switch. Its identifier is "<expert>:<key>".
- (NSView *)controlFor:(MMPrefSpec *)p expert:(MMSettingsExpert *)e {
    NSString *ident = [NSString stringWithFormat:@"%@:%@", e.expert, p.key];
    if (!p.values) {
        NSButton *b = [NSButton checkboxWithTitle:p.switchTitle ?: p.title ?: @"" target:self action:@selector(prefToggled:)];
        b.state = p.value.boolValue ? NSControlStateValueOn : NSControlStateValueOff;
        b.identifier = ident; b.enabled = self.onPref != nil;
        b.accessibilityLabel = p.title;
        return b;
    }
    NSPopUpButton *m = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger i = 0; i < p.values.count; i++)
        [m addItemWithTitle:i < p.valueTitles.count ? p.valueTitles[i] : p.values[i].stringValue];
    NSUInteger at = p.value ? [p.values indexOfObject:p.value] : NSNotFound;
    // A value the CLI set that the choices do not hold is shown as it is, so the menu never claims another one.
    if (at == NSNotFound && p.value) { [m addItemWithTitle:p.value.stringValue]; at = (NSUInteger)m.numberOfItems - 1; }
    [m selectItemAtIndex:at == NSNotFound ? 0 : (NSInteger)at];
    m.identifier = ident; m.target = self; m.action = @selector(prefChosen:);
    m.enabled = self.onPref != nil;
    m.accessibilityLabel = p.title;
    m.translatesAutoresizingMaskIntoConstraints = NO;
    [m.widthAnchor constraintEqualToConstant:150].active = YES;
    return m;
}

/// One pref as a grid of its own: the label right-aligned in a 150-point column, the control and its note beside it.
/// A grid per pref keeps every gap the same; one grid for a whole group let NSGridView stretch a row.
- (NSGridView *)gridFor:(MMPrefSpec *)p expert:(MMSettingsExpert *)e {
    CGFloat noteWidth = MMSettingsWidth - 2 * kInset - 150 - 12;
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@[Label([(p.title ?: @"") stringByAppendingString:@":"], Body(), NSColor.labelColor),
                                                             [self controlFor:p expert:e]]];
    if (p.note.length) [rows addObject:@[[NSGridCell emptyContentView], Note(p.note, noteWidth)]];
    NSGridView *g = [NSGridView gridViewWithViews:rows];
    g.rowSpacing = 6; g.columnSpacing = 12;
    [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [g columnAtIndex:0].width = 150;
    g.rowAlignment = NSGridRowAlignmentFirstBaseline;
    // A grid hugs its rows, so the stack never stretches one of them to fill its own height.
    [g setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
    return g;
}

/// One group: its title, then each pref, 12 points apart.
- (NSStackView *)groupFor:(NSArray<MMPrefSpec *> *)prefs title:(NSString *)title expert:(MMSettingsExpert *)e {
    NSMutableArray *views = [NSMutableArray new];
    for (MMPrefSpec *p in prefs) [views addObject:[self gridFor:p expert:e]];
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = 12;
    if (title.length) {
        [s insertView:Label(title, [NSFont boldSystemFontOfSize:NSFont.systemFontSize], NSColor.labelColor) atIndex:0 inGravity:NSStackViewGravityTop];
        [s setCustomSpacing:14 afterView:s.views.firstObject];
    }
    return s;
}

- (NSView *)prefsPane:(MMSettingsExpert *)e {
    NSMutableArray *views = [NSMutableArray new];
    NSMutableArray<MMPrefSpec *> *group = [NSMutableArray new];
    __block NSString *title = nil;
    void (^flush)(void) = ^{
        if (!group.count) return;
        if (views.count) [views addObject:Line()];
        [views addObject:[self groupFor:[group copy] title:title expert:e]];
        [group removeAllObjects];
    };
    for (MMPrefSpec *p in e.prefs) {
        if (p.section.length && ![p.section isEqualToString:title ?: @""]) { flush(); title = p.section; }
        [group addObject:p];
    }
    flush();
    return Pane(views);
}

- (MMPrefSpec *)prefFor:(NSString *)ident expert:(MMSettingsExpert **)expert {
    NSRange r = [ident rangeOfString:@":"];
    if (r.location == NSNotFound) return nil;
    MMSettingsExpert *e = [self expertNamed:[ident substringToIndex:r.location]];
    NSString *key = [ident substringFromIndex:NSMaxRange(r)];
    if (expert) *expert = e;
    for (MMPrefSpec *p in e.prefs) if ([p.key isEqualToString:key]) return p;
    return nil;
}

- (void)prefChosen:(NSPopUpButton *)m {
    MMSettingsExpert *e = nil;
    MMPrefSpec *p = [self prefFor:m.identifier expert:&e];
    NSInteger i = m.indexOfSelectedItem;
    if (!p || i < 0 || (NSUInteger)i >= p.values.count) return;   // the item that shows a value set elsewhere
    p.value = p.values[(NSUInteger)i];
    if (self.onPref) self.onPref(e.expert, p.key, p.value);
}

- (void)prefToggled:(NSButton *)b {
    MMSettingsExpert *e = nil;
    MMPrefSpec *p = [self prefFor:b.identifier expert:&e];
    if (!p) return;
    p.value = @(b.state == NSControlStateValueOn);
    if (self.onPref) self.onPref(e.expert, p.key, p.value);
}

#pragma mark General

- (NSView *)general {
    CGFloat textWidth = MMSettingsWidth - 2 * kInset - 150 - 12;
    NSPopUpButton *model = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSString *m in MMSettingsModels()) [model addItemWithTitle:MMSettingsModelTitle(m)];
    NSUInteger i = [MMSettingsModels() indexOfObject:_model.lowercaseString ?: @""];
    [model selectItemAtIndex:i == NSNotFound ? 0 : (NSInteger)i];
    model.target = self; model.action = @selector(modelChanged:);
    model.enabled = self.onModel != nil;
    model.accessibilityLabel = @"Review model";

    NSButton *one = [NSButton checkboxWithTitle:@"Show One Icon" target:self action:@selector(oneIconChanged:)];
    one.state = _oneIcon ? NSControlStateValueOn : NSControlStateValueOff;
    one.enabled = self.onOneIcon != nil;
    NSButton *login = [NSButton checkboxWithTitle:@"Open at Login" target:self action:@selector(loginChanged:)];
    login.state = _openAtLogin ? NSControlStateValueOn : NSControlStateValueOff;
    login.enabled = self.onOpenAtLogin != nil;

    NSGridView *g = [NSGridView gridViewWithViews:@[
        @[Label(@"Review model:", Body(), NSColor.labelColor), model],
        @[[NSGridCell emptyContentView], Note(@"Reviews run on your own Claude Code or Codex login. Auto asks Haiku first and Luna when Haiku is out of reach.", textWidth)],
        @[Label(@"Menu bar:", Body(), NSColor.labelColor), one],
        @[[NSGridCell emptyContentView], Note(@"One menu with a section for each expert, in place of five icons.", textWidth)],
        @[Label(@"Startup:", Body(), NSColor.labelColor), login],
        @[[NSGridCell emptyContentView], Note(@"The CLI answers faster when MinMacs is already running.", textWidth)]]];
    g.rowSpacing = 6; g.columnSpacing = 12;
    [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [g columnAtIndex:0].width = 150;
    g.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [g rowAtIndex:2].topPadding = 12;
    [g rowAtIndex:4].topPadding = 12;
    return Pane(@[g]);
}

- (void)modelChanged:(NSPopUpButton *)p {
    _model = MMSettingsModels()[(NSUInteger)MAX(0, p.indexOfSelectedItem)];
    if (self.onModel) self.onModel(_model);
}
- (void)oneIconChanged:(NSButton *)b { _oneIcon = b.state == NSControlStateValueOn; if (self.onOneIcon) self.onOneIcon(_oneIcon); }
- (void)loginChanged:(NSButton *)b { _openAtLogin = b.state == NSControlStateValueOn; if (self.onOpenAtLogin) self.onOpenAtLogin(_openAtLogin); }

#pragma mark Panes and the window

/// The experts with a pane of their own, in the order of the Overview.
- (NSArray<MMSettingsExpert *> *)prefExperts {
    NSMutableArray *out = [NSMutableArray new];
    for (MMSettingsExpert *e in _experts) if (e.prefs.count) [out addObject:e];
    return out;
}

- (NSView *)sized:(NSView *)v {
    [v layoutSubtreeIfNeeded];
    NSSize s = v.fittingSize;
    v.translatesAutoresizingMaskIntoConstraints = YES;
    v.frame = NSMakeRect(0, 0, MMSettingsWidth, s.height);
    return v;
}

- (NSView *)viewForExpert:(NSString *)expert {
    MMSettingsExpert *e = [self expertNamed:expert];
    return e.prefs.count ? [self sized:[self prefsPane:e]] : nil;
}

- (NSView *)viewFor:(MMSettingsPane)pane {
    NSView *v = pane == MMSettingsOverview ? [self overview] : pane == MMSettingsExperts ? [self expertsPane] : [self general];
    return [self sized:v];
}

- (void)makeWindow {
    if (_window) return;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, MMSettingsWidth, 300)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                            backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.toolbarStyle = NSWindowToolbarStylePreference;
    [_window center];
}

/// A new toolbar when the panes changed, such as an expert that gained prefs.
- (void)syncToolbar {
    NSArray *ids = [self paneTitles];
    if ([[_window.toolbar.items valueForKey:@"itemIdentifier"] isEqualToArray:ids]) return;
    NSToolbar *t = [[NSToolbar alloc] initWithIdentifier:@"minmacs.settings"];
    t.delegate = self;
    t.displayMode = NSToolbarDisplayModeIconAndLabel;
    _window.toolbar = t;
}

- (void)show:(MMSettingsPane)pane {
    [self makeWindow];
    [self syncToolbar];
    [self select:pane expert:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
}

- (void)showExpert:(NSString *)expert {
    [self makeWindow];
    [self syncToolbar];
    if ([self expertNamed:expert].prefs.count) [self select:MMSettingsExperts expert:expert];
    else [self select:MMSettingsExperts expert:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
}

- (void)reload {
    if (!_window) return;
    [self syncToolbar];
    // An expert that lost its prefs takes the window back to the Experts pane.
    [self select:_pane expert:[self expertNamed:_expertPane].prefs.count ? _expertPane : nil];
}

- (void)select:(MMSettingsPane)pane expert:(NSString *)expert {
    _pane = pane; _expertPane = [expert copy];
    MMSettingsExpert *e = expert ? [self expertNamed:expert] : nil;
    NSView *v = e ? [self viewForExpert:expert] : [self viewFor:pane];
    NSString *title = e ? e.name : MMSettingsPaneTitle(pane);
    NSRect old = _window.frame;
    NSRect content = [_window frameRectForContentRect:NSMakeRect(0, 0, MMSettingsWidth, v.frame.size.height)];
    // The window grows and shrinks from its top edge, as a settings window does.
    content.origin = NSMakePoint(old.origin.x, NSMaxY(old) - content.size.height);
    _window.contentView = v;
    [_window setFrame:content display:YES animate:_window.isVisible];
    _window.title = title;
    _window.toolbar.selectedItemIdentifier = title;
}

- (NSArray<NSString *> *)paneTitles {
    NSMutableArray *ids = [NSMutableArray arrayWithObjects:MMSettingsPaneTitle(MMSettingsOverview), MMSettingsPaneTitle(MMSettingsExperts), nil];
    for (MMSettingsExpert *e in [self prefExperts]) [ids addObject:e.name];
    [ids addObject:MMSettingsPaneTitle(MMSettingsGeneral)];
    return ids;
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return [self paneTitles]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return [self paneTitles]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)t { return [self paneTitles]; }

/// The expert whose pane has this title, or nil for the fixed panes.
- (MMSettingsExpert *)expertTitled:(NSString *)title {
    for (MMSettingsExpert *e in [self prefExperts]) if ([e.name isEqualToString:title]) return e;
    return nil;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSToolbarItemIdentifier)ident willBeInsertedIntoToolbar:(BOOL)flag {
    MMSettingsExpert *e = [self expertTitled:ident];
    NSString *symbol = e ? (e.symbol ?: @"circle") : PaneSymbol((MMSettingsPane)[@[MMSettingsPaneTitle(MMSettingsOverview),
        MMSettingsPaneTitle(MMSettingsExperts), MMSettingsPaneTitle(MMSettingsGeneral)] indexOfObject:ident]);
    NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    i.label = ident;
    i.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:ident];
    i.target = self; i.action = @selector(paneClicked:);
    return i;
}

- (void)paneClicked:(NSToolbarItem *)i {
    MMSettingsExpert *e = [self expertTitled:i.itemIdentifier];
    if (e) { [self select:MMSettingsExperts expert:e.expert]; return; }
    for (MMSettingsPane p = MMSettingsOverview; p <= MMSettingsGeneral; p++)
        if ([MMSettingsPaneTitle(p) isEqualToString:i.itemIdentifier]) [self select:p expert:nil];
}

@end
