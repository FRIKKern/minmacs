#import "MMSettings.h"

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
}

- (instancetype)init {
    if ((self = [super init])) { _model = @"auto"; _experts = @[]; }
    return self;
}

- (NSWindow *)window { return _window; }
- (MMSettingsPane)pane { return _pane; }

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

- (NSView *)viewFor:(MMSettingsPane)pane {
    NSView *v = pane == MMSettingsOverview ? [self overview] : pane == MMSettingsExperts ? [self expertsPane] : [self general];
    [v layoutSubtreeIfNeeded];
    NSSize s = v.fittingSize;
    v.translatesAutoresizingMaskIntoConstraints = YES;
    v.frame = NSMakeRect(0, 0, MMSettingsWidth, s.height);
    return v;
}

- (void)show:(MMSettingsPane)pane {
    if (!_window) {
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, MMSettingsWidth, 300)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:YES];
        _window.releasedWhenClosed = NO;
        _window.delegate = self;
        _window.toolbarStyle = NSWindowToolbarStylePreference;
        NSToolbar *t = [[NSToolbar alloc] initWithIdentifier:@"minmacs.settings"];
        t.delegate = self;
        t.displayMode = NSToolbarDisplayModeIconAndLabel;
        _window.toolbar = t;
        [_window center];
    }
    [self select:pane];
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
}

- (void)reload { if (_window) [self select:_pane]; }

- (void)select:(MMSettingsPane)pane {
    _pane = pane;
    NSView *v = [self viewFor:pane];
    NSRect old = _window.frame;
    NSRect content = [_window frameRectForContentRect:NSMakeRect(0, 0, MMSettingsWidth, v.frame.size.height)];
    // The window grows and shrinks from its top edge, as a settings window does.
    content.origin = NSMakePoint(old.origin.x, NSMaxY(old) - content.size.height);
    _window.contentView = v;
    [_window setFrame:content display:YES animate:_window.isVisible];
    _window.title = MMSettingsPaneTitle(pane);
    _window.toolbar.selectedItemIdentifier = MMSettingsPaneTitle(pane);
}

- (NSArray<NSToolbarItemIdentifier> *)paneIDs {
    return @[MMSettingsPaneTitle(MMSettingsOverview), MMSettingsPaneTitle(MMSettingsExperts), MMSettingsPaneTitle(MMSettingsGeneral)];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { return [self paneIDs]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { return [self paneIDs]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)t { return [self paneIDs]; }

- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSToolbarItemIdentifier)ident willBeInsertedIntoToolbar:(BOOL)flag {
    MMSettingsPane pane = (MMSettingsPane)[[self paneIDs] indexOfObject:ident];
    NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    i.label = ident;
    i.image = [NSImage imageWithSystemSymbolName:PaneSymbol(pane) accessibilityDescription:ident];
    i.target = self; i.action = @selector(paneClicked:);
    return i;
}

- (void)paneClicked:(NSToolbarItem *)i {
    NSUInteger p = [[self paneIDs] indexOfObject:i.itemIdentifier];
    if (p != NSNotFound) [self select:(MMSettingsPane)p];
}

@end
