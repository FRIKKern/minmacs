// Renders fixture menus and hover cards built with the menu kit to PNG, in light, dark and Increase Contrast.
// Nothing is scanned and no model is asked: the subjects are made up here, one like LocoHost and one like WorkForest.
// The two describe one Mac, so a server and its worktree say the same thing on both sides.
// The drawing and the menu checks live in Sources/UI/MMRender, so an expert's own tests can use them too.
// Usage: render <output folder>. tools/render.sh builds and runs it.
// It also writes checks.txt, one line per DESIGN.md check, each starting with ok or FAIL.
#import <Cocoa/Cocoa.h>
#import "UI/MMUI.h"

#pragma mark Checks

static NSMutableArray<NSString *> *gChecks;
static void Check(BOOL ok, NSString *what, NSString *detail) {
    [gChecks addObject:ok ? [@"ok    " stringByAppendingString:what] : [NSString stringWithFormat:@"FAIL  %@: %@", what, detail ?: @""]];
}

#pragma mark Menu checks

/// The DESIGN.md rules a whole menu can be checked against, from MMMenuProblems.
static void CheckMenu(NSMenu *menu, NSString *name) {
    NSArray *p = MMMenuProblems(menu);
    Check(p.count == 0, [name stringByAppendingString:@": the menu follows DESIGN.md rules 3 and 4"], [p componentsJoinedByString:@"; "]);
}

/// The x of the first value in a card's fact grid, so the render can check the column lines up across cards.
static CGFloat ValueColumn(NSMenuItem *cardItem) {
    NSMutableArray *todo = [NSMutableArray arrayWithObject:cardItem.view];
    while (todo.count) {
        NSView *v = todo.lastObject; [todo removeLastObject];
        if ([v isKindOfClass:NSGridView.class]) {
            NSGridView *g = (NSGridView *)v;
            NSView *x = [g cellAtColumnIndex:1 rowIndex:0].contentView;
            return [x convertPoint:NSZeroPoint toView:cardItem.view].x;
        }
        [todo addObjectsFromArray:v.subviews];
    }
    return -1;
}

#pragma mark Fixtures

/// A subject: its menu and its cards by name, each with the row it hangs under.
@interface Subject : NSObject
@property (copy) NSString *name;
@property (strong) NSMenu *menu;
@property (strong) NSMutableDictionary<NSString *, MMCard *> *cards;
@property (strong) NSMutableArray<NSString *> *order;
@property (strong) NSMutableDictionary<NSString *, NSMenu *> *cardMenus;   // a menu item lives in one menu, so each card's menu is built once
@end
@implementation Subject @end

static NSMenuItem *Act(NSString *title) { return MMActionItem(title, nil, @selector(copy:), nil); }

static MMCard *Card(NSString *title, MMMark mark, NSString *word, NSString *text) {
    MMCard *c = [MMCard new];
    c.title = title; c.mark = mark; c.statusWord = word; c.statusText = text;
    return c;
}

/// Adds a row that opens a card.
static NSMenuItem *Row(Subject *s, NSString *key, NSString *name, NSString *tag, NSArray *facts, MMMark mark, MMCard *card) {
    NSMenuItem *r = MMRowItem(name, tag, facts, mark);
    if (card) { r.submenu = [card menu]; s.cards[key] = card; s.cardMenus[key] = r.submenu; [s.order addObject:key]; }
    return r;
}

static Subject *LocoHostLike(void) {
    Subject *s = [Subject new]; s.name = @"locohost"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    NSMenu *m = [NSMenu new];
    // The header adds up the rows below: seven servers, 3573 MB in all.
    [m addItem:MMHeaderItem(MMBytes(3573ull << 20), @"in servers", @"12% CPU",
                            [NSString stringWithFormat:@"%@ · 4 in use · 2 quiet · Eager", MMPlural(7, @"localhost")])];
    [m addItem:NSMenuItem.separatorItem];
    // The summary explains. The header and Close Idle already give the counts and the size, so it repeats neither.
    [m addItem:MMTextItem(@"The docs refresh server goes at 18:00, after a quiet afternoon. The admin server has not been used since lunch. "
                          @"Postgres is a shared service, so no mode stops it. Nothing else needs a look.", MMMaxSummaryLines)];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMActionItem(@"Close Idle", [NSString stringWithFormat:@"%@, %@", MMPlural(2, @"server"), MMBytes(1212ull << 20)], @selector(copy:), nil)];
    [m addItem:MMAlternateItem(@"Force Close Idle", nil, @selector(copy:), nil)];
    [m addItem:MMActionItem(@"Review Now", MMAgo([NSDate dateWithTimeIntervalSinceNow:-9 * 60]), @selector(copy:), nil)];

    MMCard *checkout = Card(@"Vite dev server for the acme-web checkout flow", MMMarkWorking, @"Stays.",
                            @"Safari has it open. Eager looks again after 30 minutes of quiet.");
    [checkout fact:@"Where" value:@"cmux, tab “checkout”"];
    [checkout fact:@"Up" value:[NSString stringWithFormat:@"%@, started by pnpm dev", MMDuration(3 * 3600 + 12 * 60)]];
    [checkout fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 4%% CPU", MMBytes(905ull << 20)]];
    [checkout fact:@"Git" value:[NSString stringWithFormat:@"feat/checkout-flow · %@", MMPlural(2, @"uncommitted file")]];
    [checkout link:@"Worktree" value:@"checkout-flow, in use" expert:@"WorkForest" key:@"/Users/dev/code/acme-web.worktrees/checkout-flow"];
    checkout.noteBy = @"Haiku says in use"; checkout.note = @"Safari has it open.";   // repeats the status, so it is left out
    [checkout action:Act(@"Go to “checkout”")];
    [checkout action:Act(@"Open localhost:3000")];
    [checkout action:Act(@"Reveal in Finder")];
    [checkout action:Act(@"Keep for 4 Hours")];
    [checkout action:Act(@"Stop")];
    [checkout action:MMAlternateItem(@"Force Stop", nil, @selector(copy:), nil)];
    [checkout more:Act(@"Copy URL")];
    [checkout more:Act(@"Copy Restart Command")];

    MMCard *orbit = Card(@"Next.js server for orbit-api", MMMarkRecent, @"Stays.",
                         @"Used 4 minutes ago from Safari. Eager looks again after 30 minutes of quiet.");
    [orbit fact:@"Where" value:@"Terminal, tab “orbit-api”"];
    [orbit fact:@"Up" value:[NSString stringWithFormat:@"%@, started by npm run dev", MMDuration(2 * 3600)]];
    [orbit fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 1%% CPU", MMBytes(640ull << 20)]];
    [orbit fact:@"Agent" value:@"Claude Code, “Retry webhooks”, 20m ago"];
    [orbit link:@"Worktree" value:@"billing-webhooks" expert:@"WorkForest" key:@"/Users/dev/code/orbit-api.worktrees/billing-webhooks"];
    orbit.noteBy = @"Haiku says in use"; orbit.note = @"The agent's webhook tests call this server, so stopping it would break their next run.";
    [orbit action:Act(@"Go to “orbit-api”")];
    [orbit action:Act(@"Open localhost:4000")];
    [orbit action:Act(@"Keep for 4 Hours")];
    [orbit action:Act(@"Stop")];

    MMCard *docs = Card(@"Vite dev server for the acme-web docs", MMMarkGoes, @"Goes at 18:00.",
                        @"Quiet for 3 hours, and no agent uses it. Recently Stopped keeps its restart command.");
    [docs fact:@"Where" value:@"cmux, workspace “acme-web”"];
    [docs fact:@"Up" value:[NSString stringWithFormat:@"%@, started by pnpm docs", MMDuration(26 * 3600)]];
    [docs fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 0%% CPU", MMBytes(512ull << 20)]];
    [docs fact:@"Git" value:@"main · up to date"];
    docs.noteBy = @"Haiku says idle"; docs.note = @"Nobody has opened the docs site since it started yesterday.";
    [docs action:MMDimmedItem(@"Go to Tab", @"the tab has closed")];
    [docs action:Act(@"Open localhost:3001")];
    [docs action:Act(@"Keep for 4 Hours")];
    [docs action:Act(@"Stop")];

    // An owned item says who owns it and how to change that.
    MMCard *pg = Card(@"Postgres 16, a shared database service", MMMarkQuiet, @"Stays.",
                      @"No mode stops a shared database. Homebrew runs it, and brew services stop postgresql@16 ends it.");
    [pg fact:@"Where" value:@"Homebrew service"];
    [pg fact:@"Up" value:MMDuration(5 * 86400 + 2 * 3600)];
    [pg fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 0%% CPU", MMBytes(96ull << 20)]];
    [pg fact:@"Git" value:@""];   // empty, so it is left out
    [pg action:Act(@"Copy URL")];
    [pg action:MMDimmedItem(@"Stop", @"Homebrew owns it")];

    NSString *longName = @"acme-web-really-long-feature-branch-name-for-search";
    MMAddSection(m, @"In use", @[
        Row(s, @"checkout", @"checkout-flow", @":3000", @[@"Vite", MMBytes(905ull << 20), @"in Safari"], MMMarkWorking, checkout),
        Row(s, @"orbit", @"orbit-api", @":4000", @[@"Next.js", MMBytes(640ull << 20), @"used 4m ago"], MMMarkRecent, orbit),
        Row(s, @"storybook", @"storybook", @":6006", @[@"Storybook", MMBytes(310ull << 20), @"up 1h"], MMMarkWorking, nil),
        Row(s, @"long", longName, @":5173", @[@"Vite", MMBytes(410ull << 20), @"up 40m"], MMMarkWorking, nil)]);
    // Rows in Quiet do not say quiet again. Each gives what the section does not: when it goes, or when it was last used.
    MMAddSection(m, @"Quiet", @[
        Row(s, @"docs", @"docs", @":3001", @[@"Vite", MMBytes(512ull << 20), @"goes at 18:00"], MMMarkGoes, docs),
        Row(s, @"admin", @"admin", @":3002", @[@"Vite", MMBytes(700ull << 20), @"used 3h ago"], MMMarkQuiet, nil)]);
    MMAddSection(m, @"Services", @[Row(s, @"postgres", @"Postgres", @":5432", @[@"Homebrew", MMBytes(96ull << 20), @"up 5d"], MMMarkQuiet, pg)]);
    [m addItem:NSMenuItem.separatorItem];
    NSMenuItem *stopped = MMActionItem(@"Recently Stopped", nil, nil, nil);
    stopped.submenu = [NSMenu new];
    [stopped.submenu addItem:MMActionItem(@":3004 Vite", @"2h ago by Eager", @selector(copy:), nil)];
    [m addItem:MMMoreItem(@[stopped])];
    MMAddFooter(m, nil);
    s.menu = m;
    return s;
}

static Subject *WorkForestLike(void) {
    Subject *s = [Subject new]; s.name = @"workforest"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    NSMenu *m = [NSMenu new];
    // The header adds up the rows below: thirteen worktrees, 10455 MB in all.
    [m addItem:MMHeaderItem(MMBytes(10455ull << 20), @"in worktrees", nil,
                            [NSString stringWithFormat:@"%@ in %@ · Proactive", MMPlural(13, @"worktree"), MMPlural(2, @"repo")])];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMTextItem(@"The promo banner branch is squash-merged and its remote branch is deleted. "
                          @"The docs refresh is merged and untouched for two weeks. Both go at the next review. "
                          @"The rate limits branch is parked on purpose, so it stays.", MMMaxSummaryLines)];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMActionItem(@"Clean Up", [NSString stringWithFormat:@"%@, %@", MMPlural(2, @"worktree"), MMBytes(5440ull << 20)], @selector(copy:), nil)];
    [m addItem:MMActionItem(@"Review Now", MMAgo([NSDate dateWithTimeIntervalSinceNow:-9 * 60]), @selector(copy:), nil)];

    MMCard *promo = Card(@"Promo banner for acme-web", MMMarkGoes, @"Goes at the next review.",
                         @"Squash-merged and untouched for 6 days. Recently Removed can restore it.");
    [promo fact:@"Branch" value:@"feat/promo-banner in acme-web"];
    [promo fact:@"Last work" value:[NSString stringWithFormat:@"%@ ago · “Promo: show the autumn banner on the cart page”", MMDuration(6 * 86400 + 3 * 3600)]];
    [promo fact:@"Disk" value:[NSString stringWithFormat:@"%@ freed, %@ of it caches", MMBytes(4900ull << 20), MMBytes(3900ull << 20)]];
    [promo fact:@"Git" value:@"remote branch deleted"];
    [promo fact:@"Agent" value:@"none found"];
    [promo fact:@"Running" value:@"nothing"];   // a sixth fact: the card shows five
    promo.noteBy = @"Haiku says stale"; promo.note = @"Squash-merged and untouched for 6 days.";   // repeats the status
    [promo action:Act(@"Open in Finder")];
    [promo action:Act(@"Open in Terminal")];
    [promo action:Act(@"Keep for a Week")];
    [promo action:Act(@"Remove…")];
    [promo more:Act(@"Copy Path")];
    [promo more:Act(@"Protect")];

    MMCard *search = Card(@"Search facets for acme-web, in progress", MMMarkWorking, @"Stays.",
                          @"Work here is not committed yet. The next review looks again after the next commit.");
    [search fact:@"Branch" value:@"feat/search-facets in acme-web"];
    [search fact:@"Last work" value:@"2h ago · “Search: facet counts per category”"];
    [search fact:@"Disk" value:[NSString stringWithFormat:@"%@, %@ of it caches", MMBytes(820ull << 20), MMBytes(610ull << 20)]];
    [search fact:@"Agent" value:@"Claude Code, “Facet filters”, 2h ago"];
    [search link:@"Server" value:@":5173 Vite, in use" expert:@"LocoHost" key:@"5173"];
    [search action:Act(@"Open in Finder")];
    [search action:Act(@"Open in Terminal")];
    [search action:Act(@"Keep for a Week")];
    [search action:MMDimmedItem(@"Remove…", MMPlural(3, @"uncommitted file"))];
    [search more:Act(@"Copy Path")];

    MMCard *hooks = Card(@"Webhook retries for orbit-api", MMMarkWorking, @"Stays.",
                         @"The Next.js server inside was used 4 minutes ago. The next review looks again once it stops.");
    [hooks fact:@"Branch" value:@"fix/billing-webhooks in orbit-api"];
    [hooks fact:@"Last work" value:@"1d 12h ago · “Billing: retry webhooks with backoff”"];
    [hooks fact:@"Disk" value:MMBytes(1300ull << 20)];
    [hooks fact:@"Git" value:@"1 commit not in main"];
    [hooks link:@"Server" value:@":4000 Next.js" expert:@"LocoHost" key:@"4000"];
    hooks.noteBy = @"Haiku says active"; hooks.note = @"The retry tests added in the last commit still fail, so the work is not done.";
    [hooks action:Act(@"Open in Finder")];
    [hooks action:Act(@"Open in Terminal")];
    [hooks action:Act(@"Keep for a Week")];
    [hooks action:MMDimmedItem(@"Remove…", @"a server runs inside")];

    MMCard *limits = Card(@"Rate limits per API key for orbit-api, parked on purpose until the pricing call next week", MMMarkQuiet, @"Stays.",
                          @"The branch name says the work is parked. Proactive removes only merged work.");
    [limits fact:@"Branch" value:@"wip/rate-limits in orbit-api"];
    [limits fact:@"Last work" value:@"9d ago · “WIP: token bucket per API key”"];
    [limits fact:@"Disk" value:MMBytes(310ull << 20)];
    [limits fact:@"Git" value:@"5 commits not in main"];
    limits.noteBy = @"Haiku says active after the judge"; limits.note = @"The last three commits touch only the token bucket, so most of the work is still ahead.";
    [limits action:Act(@"Open in Finder")];
    [limits action:Act(@"Open in Terminal")];
    [limits action:Act(@"Keep for a Week")];
    [limits action:Act(@"Remove…")];

    MMAddSection(m, @"Merged", @[
        Row(s, @"promo", @"promo-banner", nil, @[@"acme-web", MMBytes(4900ull << 20), @"untouched 6d"], MMMarkGoes, promo),
        Row(s, @"docs", @"docs-refresh", nil, @[@"acme-web", MMBytes(540ull << 20), @"untouched 13d"], MMMarkGoes, nil)]);
    MMAddSection(m, @"In use", @[
        Row(s, @"checkout", @"checkout-flow", nil, @[@"acme-web", MMBytes(905ull << 20), @"server :3000"], MMMarkWorking, nil),
        Row(s, @"search", @"search-facets", nil, @[@"acme-web", MMBytes(820ull << 20), MMPlural(3, @"change")], MMMarkWorking, search),
        Row(s, @"hooks", @"billing-webhooks", nil, @[@"orbit-api", MMBytes(1300ull << 20), @"server :4000"], MMMarkWorking, hooks)]);
    // Eight quiet worktrees: six show and two go under More. Rows in Quiet say how long, not "quiet" again.
    NSMutableArray *quiet = [NSMutableArray arrayWithObject:Row(s, @"limits", @"rate-limits", nil, @[@"orbit-api", MMBytes(310ull << 20), @"5 commits not in main"], MMMarkQuiet, limits)];
    NSArray *names = @[@"onboarding-copy", @"pricing-table", @"sso-okta", @"dark-mode", @"image-cdn", @"cart-refactor", @"i18n-nb"];
    for (NSUInteger k = 0; k < names.count; k++)
        [quiet addObject:Row(s, names[k], names[k], nil, @[k % 2 ? @"orbit-api" : @"acme-web", MMBytes((120 + 40 * k) << 20), [NSString stringWithFormat:@"untouched %ldd", (long)(4 + k)]], MMMarkQuiet, nil)];
    MMAddSection(m, @"Quiet", quiet);
    [m addItem:NSMenuItem.separatorItem];
    NSMenuItem *removed = MMActionItem(@"Recently Removed", nil, nil, nil);
    removed.submenu = [NSMenu new];
    [removed.submenu addItem:MMActionItem(@"old-landing", @"3d ago by Proactive", @selector(copy:), nil)];
    [m addItem:MMMoreItem(@[removed, MMActionItem(@"Missing Folders", nil, @selector(copy:), nil)])];
    MMAddFooter(m, nil);
    s.menu = m;
    return s;
}

#pragma mark Status items

/// Each expert's icon at the one point size, its badge beside it as the menu bar shows it, then its accessibility label.
static NSView *StatusStrip(NSArray<NSArray *> *experts) {
    NSView *c = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MMMenuWidth, 12 + 26 * experts.count)];
    CGFloat y = c.frame.size.height - 6 - 22;
    for (NSArray *e in experts) {
        NSString *label = MMStatusLabel(e[0], e[2]);
        NSImageView *iv = [NSImageView imageViewWithImage:MMStatusImage(e[1], label)];
        iv.contentTintColor = NSColor.labelColor;
        iv.frame = NSMakeRect(14, y, 22, 22); [c addSubview:iv];
        NSString *badge = MMStatusBadge(e[3]);
        if (badge) {
            NSTextField *b = [NSTextField labelWithString:badge];
            b.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
            b.frame = NSMakeRect(38, y + 3, 30, 16); [c addSubview:b];
        }
        NSTextField *t = [NSTextField labelWithString:label];
        t.font = [NSFont systemFontOfSize:12]; t.textColor = NSColor.secondaryLabelColor; t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.frame = NSMakeRect(76, y + 3, MMMenuWidth - 90, 16); [c addSubview:t];
        y -= 26;
    }
    return c;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: render <output folder>\n"); return 2; }
    [NSApplication sharedApplication];
    NSString *out = @(argv[1]);
    [NSFileManager.defaultManager createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
    gChecks = [NSMutableArray new];

    NSArray<Subject *> *subjects = @[LocoHostLike(), WorkForestLike()];
    NSArray *experts = @[@[@"LocoHost", @"server.rack", @"2 idle servers", @"2"], @[@"WorkForest", @"tree", @"2 worktrees to remove", @""]];
    for (NSArray *e in experts) {
        NSString *label = MMStatusLabel(e[0], e[2]);
        NSString *word = [NSString stringWithFormat:@"\\b%@\\b", [NSRegularExpression escapedPatternForString:e[1]]];
        Check([label rangeOfString:word options:NSRegularExpressionSearch].location == NSNotFound && [label hasPrefix:e[0]] &&
              [MMStatusImage(e[1], label).accessibilityDescription isEqualToString:label], [NSString stringWithFormat:@"%@: the status label names the expert, not the symbol", e[0]], label);
        Check(MMStatusImage(e[1], label) != nil, [NSString stringWithFormat:@"%@: the symbol %@ exists", e[0], e[1]], @"no such symbol");
        Check([MMStatusAutosaveName(e[0]) isEqualToString:[@"minmacs." stringByAppendingString:[e[0] lowercaseString]]],
              [NSString stringWithFormat:@"%@: autosaveName is minmacs.<expert>", e[0]], MMStatusAutosaveName(e[0]));
    }

    for (Subject *s in subjects) {
        CheckMenu(s.menu, s.name);
        CGFloat column = -1; NSMutableArray *off = [NSMutableArray new];
        for (NSString *k in s.order) {
            MMCard *c = s.cards[k];
            NSArray *p = [c layoutProblems];
            // The promo card is built to break one rule on purpose, six facts, so the check must report it.
            NSArray *expected = [k isEqualToString:@"promo"] ? @[@"6 facts given, five shown"] : @[];
            Check([p isEqualToArray:expected], [NSString stringWithFormat:@"%@ card %@: follows the card rules", s.name, k], [p componentsJoinedByString:@"; "]);
            NSMenuItem *ci = [c cardItem];
            [ci.view layoutSubtreeIfNeeded];
            CGFloat x = ValueColumn(ci);
            if (column < 0) column = x; else if (fabs(x - column) > 0.5) [off addObject:[NSString stringWithFormat:@"%@ at %.1f", k, x]];
        }
        Check(off.count == 0, [s.name stringByAppendingString:@": the fact columns line up from card to card"], [off componentsJoinedByString:@", "]);
        [gChecks addObject:[NSString stringWithFormat:@"info  %@: value column at x = %.1f", s.name, column]];
    }
    for (Subject *s in subjects) {
        MMCard *dropped = s.cards[[s.name isEqualToString:@"locohost"] ? @"checkout" : @"promo"];
        Check(![dropped noteAddsSomething], [s.name stringByAppendingString:@": a note that repeats the status is left out"], dropped.note);
    }
    Check([subjects[0].cards[@"docs"] noteAddsSomething], @"locohost: a note that adds to the status is shown", subjects[0].cards[@"docs"].note);

    NSDictionary<NSString *, NSAppearance *> *appearances = MMRenderAppearances();
    NSMutableArray *unwritten = [NSMutableArray new];
    BOOL first = YES;
    for (NSString *mode in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        Check(ap != nil, [@"the appearance loads: " stringByAppendingString:mode], @"none");
        if (!ap) continue;
        for (Subject *s in subjects) {
            NSString *path = [out stringByAppendingFormat:@"/%@-menu-%@.png", s.name, mode];
            NSArray *cut = MMRenderMenu(s.menu, path, ap);
            if (!cut) [unwritten addObject:path.lastPathComponent];
            // Cut-off text is the same in every appearance, so it is checked once.
            if (first) Check(cut.count == 0, [s.name stringByAppendingString:@" menu: no item is cut off"], [cut componentsJoinedByString:@", "]);
            for (NSString *k in s.order) {
                path = [out stringByAppendingFormat:@"/%@-card-%@-%@.png", s.name, k, mode];
                cut = MMRenderMenu(s.cardMenus[k], path, ap);
                if (!cut) [unwritten addObject:path.lastPathComponent];
                if (first) Check(cut.count == 0, [NSString stringWithFormat:@"%@ card %@: no item is cut off", s.name, k], [cut componentsJoinedByString:@", "]);
            }
        }
        NSString *path = [out stringByAppendingFormat:@"/status-%@.png", mode];
        if (!MMRenderView(StatusStrip(experts), path, ap)) [unwritten addObject:path.lastPathComponent];
        first = NO;
    }
    Check(unwritten.count == 0, @"every PNG is written", [unwritten componentsJoinedByString:@", "]);
    // The menus still work after drawing: every card view went back to its item alone.
    NSInteger loose = 0;
    for (Subject *s in subjects) for (NSString *k in s.order) loose += s.cardMenus[k].itemArray.firstObject.view.superview != nil;
    Check(loose == 0, @"drawing hands every view back to its menu item", [NSString stringWithFormat:@"%ld still placed", (long)loose]);

    [[[gChecks componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:[out stringByAppendingPathComponent:@"checks.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSUInteger failed = [gChecks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'FAIL'"]].count;
    NSUInteger checks = [gChecks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (SELF BEGINSWITH 'info')"]].count;
    printf("rendered to %s, %lu checks, %lu failed\n", out.UTF8String, (unsigned long)checks, (unsigned long)failed);
    return failed ? 1 : 0;
}}
