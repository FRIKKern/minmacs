#import "MMRender.h"
#import "MMMenuKit.h"
#import "MMSpecMenu.h"

@interface MMRenderFlipped : NSView @end
@implementation MMRenderFlipped - (BOOL)isFlipped { return YES; } @end

NSDictionary<NSString *, NSAppearance *> *MMRenderAppearances(void) {
    NSBundle *system = [NSBundle bundleWithPath:@"/System/Library/CoreServices/SystemAppearance.bundle"];
    NSDictionary *names = @{@"light": @"Aqua", @"dark": @"DarkAqua", @"contrast-light": @"AquaAX", @"contrast-dark": @"DarkAquaAX"};
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *mode in names) {
        NSAppearance *ap = [[NSAppearance alloc] initWithAppearanceNamed:names[mode] bundle:system];
        // A wrong bundle gives back plain Aqua under the asked name's place, so the name is checked too.
        if ([ap.name isEqualToString:names[mode]]) out[mode] = ap;
    }
    return out;
}

BOOL MMRenderView(NSView *v, NSString *path, NSAppearance *ap) {
    NSSize size = v.frame.size;
    NSBox *bg = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    // The fill is resolved here, because a box under a loaded Increase Contrast appearance draws it white.
    __block NSColor *fill = nil;
    [ap performAsCurrentDrawingAppearance:^{ fill = [NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }];
    bg.boxType = NSBoxCustom; bg.borderWidth = 0; bg.fillColor = fill; bg.contentViewMargins = NSZeroSize;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:bg.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.appearance = ap; w.contentView = bg;
    [bg.contentView addSubview:v];
    [w layoutIfNeeded]; [bg layoutSubtreeIfNeeded];
    // Always 2x, so a PNG has the same pixels on a 1x display as on a Retina one.
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)ceil(size.width * 2)
        pixelsHigh:(NSInteger)ceil(size.height * 2) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = size;
    [ap performAsCurrentDrawingAppearance:^{ [bg cacheDisplayInRect:bg.bounds toBitmapImageRep:rep]; }];
    BOOL ok = [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    [v removeFromSuperview];
    return ok;
}

static NSTextField *Label(NSAttributedString *s) {
    NSTextField *t = [NSTextField labelWithAttributedString:s];
    t.lineBreakMode = NSLineBreakByTruncatingTail;
    return t;
}

static CGFloat TextWidth(NSAttributedString *s) { return ceil([s boundingRectWithSize:NSMakeSize(4000, 100) options:0].size.width); }

/// The items laid out top to bottom. `cut` collects the titles that do not fit.
static NSView *Stack(NSArray<NSMenuItem *> *items, NSMutableArray *cut) {
    CGFloat W = MMMenuWidth, x0 = 22, right = 22;   // the state column on the left, the submenu arrow on the right
    MMRenderFlipped *c = [[MMRenderFlipped alloc] initWithFrame:NSMakeRect(0, 0, W, 10)];
    CGFloat y = 4;
    for (NSMenuItem *i in items) {
        if (i.isAlternate || i.isHidden) continue;
        if (i.view) {
            BOOL stack = [i.view isKindOfClass:NSStackView.class];   // the card lays itself out; header and text views use frames
            if (stack) [i.view layoutSubtreeIfNeeded];
            CGFloat h = MAX(i.view.frame.size.height, stack ? i.view.fittingSize.height : 0);
            NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(0, y, W, h)];
            i.view.translatesAutoresizingMaskIntoConstraints = YES; i.view.frame = NSMakeRect(0, 0, W, h);
            [holder addSubview:i.view]; [c addSubview:holder];
            y += h; continue;
        }
        if (i.isSeparatorItem) {
            NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(10, y + 4, W - 20, 1)]; line.boxType = NSBoxSeparator;
            [c addSubview:line]; y += 9; continue;
        }
        if (i.isSectionHeader) {
            NSTextField *t = Label([[NSAttributedString alloc] initWithString:i.title attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]);
            [t sizeToFit]; t.frame = NSMakeRect(14, y + 6, W - 28, t.frame.size.height);
            [c addSubview:t]; y += t.frame.size.height + 8; continue;
        }
        NSFont *mf = [NSFont menuFontOfSize:0];
        NSMutableAttributedString *title = [(i.attributedTitle ?: [[NSAttributedString alloc] initWithString:i.title attributes:@{NSFontAttributeName: mf}]) mutableCopy];
        if (!i.attributedTitle && !i.enabled) [title addAttribute:NSForegroundColorAttributeName value:MMDimmedColor() range:NSMakeRange(0, title.length)];
        NSString *key = i.keyEquivalent.length ? [@"⌘" stringByAppendingString:i.keyEquivalent.uppercaseString] : nil;
        CGFloat avail = W - x0 - right - (key ? 30 : 0);
        NSTextField *t = Label(title);
        t.frame = NSMakeRect(x0, y + 3, avail, ceil(mf.ascender - mf.descender + mf.leading) + 2);
        [c addSubview:t];
        if (TextWidth(title) > avail) [cut addObject:i.title];
        CGFloat h = t.frame.size.height + 6;
        NSTextField *(^side)(NSString *) = ^NSTextField *(NSString *s) {
            NSTextField *k = Label([[NSAttributedString alloc] initWithString:s attributes:@{NSFontAttributeName: mf, NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]);
            [k sizeToFit]; k.frame = NSMakeRect(W - 14 - k.frame.size.width, y + 3, k.frame.size.width, k.frame.size.height); return k;
        };
        if (i.submenu) [c addSubview:side(@"›")];
        else if (key) [c addSubview:side(key)];
        NSString *sub = nil;
        if (@available(macOS 14.4, *)) sub = i.subtitle;
        if (sub.length) {
            NSAttributedString *ss = [[NSAttributedString alloc] initWithString:sub attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
            NSTextField *st = Label(ss);
            // A row's facts start under its name, past the mark column.
            st.frame = NSMakeRect(x0 + ([title.string containsString:@"\t"] ? 18 : 0), y + h - 3, avail, 14);
            [c addSubview:st]; h += 14;
            if (TextWidth(ss) > avail) [cut addObject:[i.title stringByAppendingString:@" subtitle"]];
        }
        y += h;
    }
    c.frame = NSMakeRect(0, 0, W, y + 4);
    return c;
}

NSArray<NSString *> *MMRenderMenu(NSMenu *menu, NSString *path, NSAppearance *ap) {
    MMLoadCards(menu);   // a card built on hover is drawn as the person sees it
    NSMutableArray *cut = [NSMutableArray new];
    BOOL ok = MMRenderView(Stack(menu.itemArray, cut), path, ap);
    // The views were borrowed for the drawing. Taken out again, they belong to their items alone, so the menu still opens.
    for (NSMenuItem *i in menu.itemArray) [i.view removeFromSuperview];
    return ok ? cut : nil;
}

#pragma mark Menu checks

/// The text a person reads on one item: a view's text fields, or the title and subtitle.
static NSString *Visible(NSMenuItem *i) {
    if (i.view) {
        NSMutableArray *s = [NSMutableArray new];
        NSMutableArray *todo = [NSMutableArray arrayWithObject:i.view];
        while (todo.count) {
            NSView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:NSTextField.class]) [s addObject:((NSTextField *)v).stringValue];
            [todo addObjectsFromArray:v.subviews];
        }
        return [s componentsJoinedByString:@" "];
    }
    NSString *t = i.attributedTitle.string ?: i.title;
    if (@available(macOS 14.4, *)) if (i.subtitle.length) t = [t stringByAppendingFormat:@" %@", i.subtitle];
    return t;
}

NSArray<NSString *> *MMMenuProblems(NSMenu *menu) {
    MMLoadCards(menu);
    NSMutableArray *p = [NSMutableArray new];
    NSArray<NSMenuItem *> *items = menu.itemArray;
    NSMutableArray *images = [NSMutableArray new], *parens = [NSMutableArray new];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:menu];
    while (queue.count) {
        NSMenu *m = queue.lastObject; [queue removeLastObject];
        for (NSMenuItem *i in m.itemArray) {
            if (i.image) [images addObject:i.title];
            NSString *v = Visible(i);
            if ([v containsString:@"("] || [v containsString:@")"]) [parens addObject:v];
            if (i.submenu) [queue addObject:i.submenu];
        }
    }
    if (images.count) [p addObject:[@"items with a symbol: " stringByAppendingString:[images componentsJoinedByString:@", "]]];
    if (parens.count) [p addObject:[@"parentheses in: " stringByAppendingString:[parens componentsJoinedByString:@" | "]]];

    NSInteger sections = 0, rows = 0, worst = 0;
    for (NSMenuItem *i in items) {
        if (i.isSectionHeader) { sections++; rows = 0; continue; }
        if (i.isSeparatorItem) { rows = 0; continue; }
        if (sections && !i.view && ![i.title hasSuffix:@"More"]) worst = MAX(worst, ++rows);
    }
    if (sections > MMMaxSections) [p addObject:[NSString stringWithFormat:@"%ld sections, at most four", (long)sections]];
    if (worst > MMMaxSectionRows) [p addObject:[NSString stringWithFormat:@"a section of %ld rows, at most six", (long)worst]];

    NSArray *tail = items.count >= 3 ? [[items subarrayWithRange:NSMakeRange(items.count - 3, 3)] valueForKey:@"title"] : @[];
    if (![tail isEqualToArray:@[@"Hide Icon", @"Settings…", @"Quit MinMacs"]])
        [p addObject:[@"the footer is not Hide Icon, Settings… and Quit MinMacs: " stringByAppendingString:[tail componentsJoinedByString:@", "]]];

    NSMutableSet *seen = [NSMutableSet new]; NSMutableArray *twice = [NSMutableArray new];
    for (NSMenuItem *i in items) {
        if (i.isSeparatorItem || i.view || i.isAlternate) continue;
        NSString *v = Visible(i);
        if ([seen containsObject:v]) [twice addObject:v];
        [seen addObject:v];
    }
    if (twice.count) [p addObject:[@"lines said twice: " stringByAppendingString:[twice componentsJoinedByString:@", "]]];

    // Main actions: the plain items between the summary and the first section.
    NSInteger actions = 0; BOOL started = NO;
    for (NSMenuItem *i in items) {
        // A menu with no sections ends its actions at More or the footer, which are not actions.
        if (i.isSectionHeader || [i.title isEqualToString:@"More"] || [i.title isEqualToString:@"Hide Icon"]) break;
        if (i.view) { started = YES; continue; }
        // The row a link opened sits right below the header with its card, and is not an action.
        if (started && !i.isSeparatorItem && !i.isAlternate && ![i.identifier isEqualToString:@"minmacs.focused"]) actions++;
    }
    if (actions > MMMaxMenuActions) [p addObject:[NSString stringWithFormat:@"%ld actions, at most two", (long)actions]];
    return p;
}
