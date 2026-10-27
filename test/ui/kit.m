// Checks the menu kit's formatters, marks, rows, cards and status item helpers without drawing anything.
// Prints one line per check as name<TAB>want<TAB>got, for test/ui/ui.sh to pass to check.
#import <Cocoa/Cocoa.h>
#import "UI/MMUI.h"

static void Out(NSString *name, NSString *want, NSString *got) { printf("%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"nil").UTF8String); }
static NSString *N(NSInteger n) { return [NSString stringWithFormat:@"%ld", (long)n]; }

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    Out(@"bytes in KB", @"12 KB", MMBytes(12 * 1024));
    Out(@"bytes in MB", @"905 MB", MMBytes(905ull << 20));
    Out(@"bytes in GB", @"1.2 GB", MMBytes(1229ull << 20));
    Out(@"bytes just under a GB read as a GB", @"1.0 GB", MMBytes((1ull << 30) - 1));
    Out(@"bytes in TB", @"1.5 TB", MMBytes(1536ull << 30));
    Out(@"a few bytes are never zero", @"1 KB", MMBytes(12));
    Out(@"zero bytes", @"0 KB", MMBytes(0));
    Out(@"duration in seconds", @"45s", MMDuration(45));
    Out(@"duration in hours and minutes", @"3h 4m", MMDuration(3 * 3600 + 4 * 60));
    Out(@"duration in days and hours", @"5d 2h", MMDuration(5 * 86400 + 2 * 3600));
    Out(@"duration past a week drops the hours", @"13d", MMDuration(13 * 86400 + 4 * 3600));
    Out(@"short duration", @"5d", MMShortDuration(5 * 86400 + 17 * 3600));
    Out(@"ago", @"9m ago", MMAgo([NSDate dateWithTimeIntervalSinceNow:-9 * 60]));
    Out(@"ago without a date is empty", @"", MMAgo(nil));
    Out(@"plural of one", @"1 server", MMPlural(1, @"server"));
    Out(@"plural adds s", @"2 servers", MMPlural(2, @"server"));
    Out(@"plural after s adds es", @"3 processes", MMPlural(3, @"process"));
    Out(@"plural after consonant y", @"2 entries", MMPlural(2, @"entry"));
    Out(@"plural after vowel y", @"2 keys", MMPlural(2, @"key"));
    Out(@"plural of zero", @"0 worktrees", MMPlural(0, @"worktree"));
    Out(@"cut at the tail", @"checkout-f…", MMCut(@"checkout-flow-fix", 11));
    Out(@"no cut when it fits", @"short", MMCut(@"short", 11));
    Out(@"sentence", @"Stays.", MMSentence(@"stays"));
    Out(@"capitalized title keeps its end", @"Vite server", MMCapitalized(@"vite server"));

    NSMutableSet *glyphs = [NSMutableSet new];
    for (MMMark m = MMMarkWorking; m <= MMMarkUnknown; m++) [glyphs addObject:MMMarkGlyph(m)];
    Out(@"every mark has its own shape", @"6", N(glyphs.count));

    NSMenuItem *row = MMRowItem(@"checkout-flow", @":3000", @[@"Vite", @"", @"905 MB", @"in Safari", @"extra"], MMMarkWorking);
    // macOS 14 hides the subtitle of an item with an attributed title, so there the facts are in the title.
    NSString *sub = row.attributedTitle.string;
    if (@available(macOS 15.0, *)) sub = row.subtitle;
    Out(@"a row shows three facts, empty ones left out", @"yes", [sub hasSuffix:@"Vite · 905 MB · in Safari"] ? @"yes" : @"no");
    Out(@"a row's name fits the kit's width", @"yes", [row.attributedTitle size].width <= MMMenuWidth - 52 ? @"yes" : @"no");
    Out(@"a row has no symbol", @"none", row.image ? @"image" : @"none");
    NSMenuItem *longRow = MMRowItem([@"" stringByPaddingToLength:120 withString:@"long-name-" startingAtIndex:0], @":5173", @[], MMMarkQuiet);
    Out(@"a long row keeps its tag", @"yes", [longRow.title hasSuffix:@":5173"] && [longRow.title containsString:@"…"] ? @"yes" : @"no");

    NSMenuItem *quit = MMActionItem(@"Quit", nil, @selector(terminate:), nil);
    Out(@"an action with a known selector has no symbol", @"none", quit.image ? @"image" : @"none");
    // A known action set later brings the symbol back on macOS 26 and later. MMRemoveSymbols clears it again.
    NSMenuItem *late = MMActionItem(@"Copy", nil, nil, nil);
    late.action = @selector(copy:);
    NSMenu *lateMenu = [NSMenu new]; [lateMenu addItem:late];
    MMRemoveSymbols(lateMenu);
    Out(@"MMRemoveSymbols clears a symbol an edit brought back", @"none", late.image ? @"image" : @"none");
    NSMenuItem *dim = MMDimmedItem(@"Remove…", @"3 uncommitted files");
    Out(@"a dimmed action is disabled", @"0", N(dim.enabled));
    Out(@"a dimmed action keeps its reason", @"Remove…   3 uncommitted files", dim.attributedTitle.string);
    // The title's ink, its alpha over the menu, against an enabled title's and the reason's, in each appearance the
    // render draws. A dimmed title keeps at most half the ink of an enabled one, and less than the reason beside it.
    NSColor *dimInk = [dim.attributedTitle attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    NSColor *reasonInk = [dim.attributedTitle attribute:NSForegroundColorAttributeName atIndex:dim.attributedTitle.length - 1 effectiveRange:NULL];
    NSDictionary<NSString *, NSAppearance *> *looks = MMRenderAppearances();
    for (NSString *k in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        __block double d = -1, label = -1, reason = -1;
        [looks[k] performAsCurrentDrawingAppearance:^{
            d = [dimInk colorUsingColorSpace:NSColorSpace.sRGBColorSpace].alphaComponent;
            label = [NSColor.labelColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace].alphaComponent;
            reason = [reasonInk colorUsingColorSpace:NSColorSpace.sRGBColorSpace].alphaComponent;
        }];
        Out([NSString stringWithFormat:@"a dimmed title looks dimmed in %@", k], @"yes",
            looks[k] && d >= 0 && d <= label / 2 && d < reason ? @"yes" : [NSString stringWithFormat:@"%.2f of %.2f", d, label]);
    }
    NSMenuItem *alt = MMAlternateItem(@"Force Stop", nil, @selector(copy:), nil);
    Out(@"an alternate needs Option", @"1", N(alt.isAlternate && alt.keyEquivalentModifierMask == NSEventModifierFlagOption));

    NSMenu *m = [NSMenu new];
    NSMutableArray *rows = [NSMutableArray new];
    for (int k = 0; k < 9; k++) [rows addObject:MMRowItem([NSString stringWithFormat:@"row %d", k], nil, @[], MMMarkQuiet)];
    MMAddSection(m, @"Quiet", rows);
    Out(@"a section shows six rows and More", @"8", N(m.numberOfItems));
    Out(@"the rest goes under More", @"3 More", m.itemArray.lastObject.title);
    Out(@"More holds the rest", @"3", N(m.itemArray.lastObject.submenu.numberOfItems));
    Out(@"the section title is a section header", @"1", N(m.itemArray.firstObject.isSectionHeader));
    MMAddFooter(m, nil);
    NSArray *tail = [[m.itemArray subarrayWithRange:NSMakeRange(m.numberOfItems - 3, 3)] valueForKey:@"title"];
    Out(@"the footer", @"Hide Icon, Settings…, Quit MinMacs", [tail componentsJoinedByString:@", "]);

    MMCard *c = [MMCard new];
    c.title = @"a card"; c.statusWord = @"Stays."; c.statusText = @"It is in use."; c.mark = MMMarkWorking;
    for (int k = 0; k < 7; k++) [c fact:[NSString stringWithFormat:@"F%d", k] value:k == 2 ? @"" : @"value"];
    [c link:@"Worktree" value:@"speed-3-base, merged" expert:@"WorkForest" key:@"/x"];
    for (int k = 0; k < 6; k++) [c action:MMActionItem([NSString stringWithFormat:@"Action %d", k], nil, @selector(copy:), nil)];
    [c action:MMAlternateItem(@"Action 5 Now", nil, @selector(copy:), nil)];
    NSMenu *cm = [c menu];
    NSInteger shown = 0;
    for (NSMenuItem *i in cm.itemArray) if (!i.view && !i.isSeparatorItem && !i.submenu && !i.isAlternate) shown++;
    Out(@"a card shows four actions", @"4", N(shown));
    Out(@"the rest of a card's actions go under More", @"3", N(cm.itemArray.lastObject.submenu.numberOfItems));
    Out(@"a link past five facts is left out", @"0", N(c.links.count));
    NSArray *p = [c layoutProblems];
    Out(@"a card reports more than five facts", @"7 facts given, five shown", p.firstObject);
    c.note = @"It is in use.";
    Out(@"a note that repeats the status is left out", @"0", N([c noteAddsSomething]));
    c.note = @"The agent that started it ran an hour ago.";
    Out(@"a note that adds is kept", @"1", N([c noteAddsSomething]));
    MMCard *bad = [MMCard new]; bad.title = @"x"; bad.statusWord = @"● stays"; bad.mark = MMMarkWorking;
    Out(@"a status that starts with a mark is reported", @"the status does not start with a word", [bad layoutProblems].firstObject);

    Out(@"autosaveName", @"minmacs.locohost", MMStatusAutosaveName(@"LocoHost"));
    Out(@"autosaveName drops the dash", @"minmacs.noonoo", MMStatusAutosaveName(@"Noo-Noo"));
    Out(@"accessibility label", @"LocoHost, 2 idle servers", MMStatusLabel(@"LocoHost", @"2 idle servers"));
    Out(@"accessibility label without a state", @"WorkForest", MMStatusLabel(@"WorkForest", @""));
    NSImage *img = MMStatusImage(@"server.rack", @"LocoHost, 2 idle servers");
    Out(@"the icon is a template", @"1", N(img.isTemplate));
    Out(@"the icon fits a square status item", @"1", N(img && img.size.width <= NSStatusBar.systemStatusBar.thickness));
    Out(@"the icon describes the expert, not the symbol", @"LocoHost, 2 idle servers", img.accessibilityDescription);
    Out(@"a badge of three characters", @"12", MMStatusBadge(@"12"));
    Out(@"a badge longer than three is dropped", @"nil", MMStatusBadge(@"1234") ?: @"nil");
    Out(@"a badge of words is dropped", @"nil", MMStatusBadge(@"new") ?: @"nil");
    Out(@"a badge such as 99+ is kept", @"99+", MMStatusBadge(@"99+"));

    NSMenuItem *head = MMHeaderItem(@"1.9 GB", @"in servers", nil, @"7 localhosts");
    Out(@"the header reads as one label with no empty parts", @"1.9 GB, in servers, 7 localhosts", head.view.accessibilityLabel);

    // Each mark color is darker on a light menu than on a dark one, so the bold status word stays readable.
    NSInteger lighter = 0;
    for (MMMark mk = MMMarkWorking; mk <= MMMarkGoes; mk++) {
        if (mk == MMMarkQuiet) continue;
        __block CGFloat onLight = 0, onDark = 0;
        [[NSAppearance appearanceNamed:NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{ onLight = [MMMarkColor(mk) colorUsingColorSpace:NSColorSpace.sRGBColorSpace].brightnessComponent; }];
        [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{ onDark = [MMMarkColor(mk) colorUsingColorSpace:NSColorSpace.sRGBColorSpace].brightnessComponent; }];
        lighter += onLight < onDark;
    }
    Out(@"green, yellow and orange are darker on a light menu", @"3", N(lighter));
    // The render loads its appearances from the system bundle, and those must pick the same shades.
    NSAppearance *loadedDark = MMRenderAppearances()[@"dark"];
    __block CGFloat loaded = 0, named = 0;
    [loadedDark performAsCurrentDrawingAppearance:^{ loaded = [MMMarkColor(MMMarkGoes) colorUsingColorSpace:NSColorSpace.sRGBColorSpace].greenComponent; }];
    [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{ named = [MMMarkColor(MMMarkGoes) colorUsingColorSpace:NSColorSpace.sRGBColorSpace].greenComponent; }];
    Out(@"the render's dark appearance picks the dark shade", @"1", N(loadedDark && fabs(loaded - named) < 0.01));

    // The render check finds what DESIGN.md forbids.
    NSMenu *wrong = [NSMenu new];
    [wrong addItem:MMTextItem(@"Summary.", 3)];
    for (NSString *t in @[@"One", @"Two", @"Three (extra)"]) [wrong addItem:MMActionItem(t, nil, @selector(copy:), nil)];
    NSArray *found = MMMenuProblems(wrong);
    Out(@"the menu check finds parentheses, three actions and no footer", @"3", N(found.count));
    NSMenu *right = [NSMenu new];
    [right addItem:MMTextItem(@"Summary.", 3)];
    MMAddSection(right, @"Quiet", @[MMRowItem(@"a", nil, @[@"b"], MMMarkQuiet)]);
    MMAddFooter(right, nil);
    Out(@"a menu that follows DESIGN.md has no problems", @"", [MMMenuProblems(right) componentsJoinedByString:@"; "]);
    Out(@"every appearance of the render check loads", @"4", N(MMRenderAppearances().count));
    return 0;
}}
