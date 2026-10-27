// Renders fixture menus and hover cards built with the menu kit to PNG, in light, dark and Increase Contrast.
// Nothing is scanned and no model is asked: the subjects are made up here. LocoHost's menu and cards come from its own
// spec code in Sources/Experts/LocoHost, fed fixture servers. The WorkForest one is still built with the kit by hand.
// The two describe one Mac, so a server and its worktree say the same thing on both sides.
// The drawing and the menu checks live in Sources/UI/MMRender, so an expert's own tests can use them too.
// Usage: render <output folder>. tools/render.sh builds and runs it.
// It also writes checks.txt, one line per DESIGN.md check, each starting with ok or FAIL.
#import <Cocoa/Cocoa.h>
#import "UI/MMUI.h"
#import "UI/MMSettings.h"
#import "UI/MMSpecKit.h"
#import "Experts/LocoHost/MMLHHost.h"

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

/// One fixture server for the LocoHost subject.
static MMLHHost *Server(NSString *key, NSString *folder, NSInteger port, NSString *framework, uint64_t mb, MMLHState state, NSTimeInterval up) {
    MMLHHost *h = [MMLHHost new];
    h.findingID = [@"locohost:server:" stringByAppendingString:key]; h.stableKey = key; h.key = [NSString stringWithFormat:@"%ld:1", (long)port];
    h.pid = (pid_t)(40000 + port); h.name = @"node"; h.kind = @"dev"; h.framework = framework;
    h.cwd = [@"/Users/dev/code" stringByAppendingPathComponent:folder]; h.ports = @[@(port)]; h.bind = @"127.0.0.1";
    h.memory = mb << 20; h.state = state; h.started = [NSDate dateWithTimeIntervalSinceNow:-up]; h.firstSeen = h.started;
    h.args = @[@"node", @"vite"]; h.launcher = @"pnpm dev · cmux";
    return h;
}

/// LocoHost's own menu and cards, built by Sources/Experts/LocoHost from fixture servers, and drawn by the kit
/// through Sources/UI/MMSpecKit. The same code draws the app's menu from the graph.
static Subject *LocoHostLike(void) {
    Subject *s = [Subject new]; s.name = @"locohost"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    MMLHHost *checkout = Server(@"~/code/acme-web.worktrees/checkout-flow#dev", @"acme-web.worktrees/checkout-flow", 3000, @"Vite", 905, MMLHActive, 3 * 3600 + 12 * 60);
    checkout.repo = @"acme-web"; checkout.worktree = @"checkout-flow"; checkout.branch = @"feat/checkout-flow"; checkout.repoRoot = checkout.cwd;
    checkout.clients = @[@"Safari"]; checkout.connections = 2; checkout.newConnections = 1; checkout.cpuPercent = 4;
    checkout.placeLabel = @"cmux, checkout"; checkout.placeTab = @"checkout"; checkout.placeApp = @"cmux";
    MMLHHost *orbit = Server(@"~/code/orbit-api#dev", @"orbit-api", 4000, @"Next.js", 640, MMLHRecent, 2 * 3600);
    orbit.repo = @"orbit-api"; orbit.lastActive = [NSDate dateWithTimeIntervalSinceNow:-4 * 60]; orbit.cpuPercent = 1; orbit.launcher = @"npm run dev · Terminal";
    orbit.placeLabel = @"Terminal, orbit-api"; orbit.placeTab = @"orbit-api"; orbit.placeApp = @"Terminal";
    orbit.session = @{@"agent": @"Claude Code", @"title": @"Retry webhooks", @"lastActiveAt": @(NSDate.date.timeIntervalSince1970 - 20 * 60)};
    MMLHHost *storybook = Server(@"~/code/acme-web#storybook", @"acme-web", 6006, @"Storybook", 310, MMLHActive, 3600);
    storybook.repo = @"acme-web";
    MMLHHost *search = Server(@"~/code/acme-web.worktrees/search#dev", @"acme-web.worktrees/acme-web-really-long-feature-branch-name-for-search", 5173, @"Vite", 410, MMLHActive, 40 * 60);
    search.repo = @"acme-web"; search.worktree = @"acme-web-really-long-feature-branch-name-for-search";
    MMLHHost *docs = Server(@"~/code/acme-web/docs#docs", @"acme-web/docs", 3001, @"Vite", 512, MMLHIdle, 26 * 3600);
    docs.repo = @"acme-web"; docs.subdir = @"docs"; docs.branch = @"main"; docs.lastActive = [NSDate dateWithTimeIntervalSinceNow:-3 * 3600];
    docs.launcher = @"pnpm docs · cmux"; docs.placeLabel = @"cmux, acme-web"; docs.placeApp = @"cmux";
    MMLHHost *admin = Server(@"~/code/acme-admin#dev", @"acme-admin", 3002, @"Vite", 700, MMLHIdle, 5 * 3600);
    admin.repo = @"acme-admin"; admin.lastActive = [NSDate dateWithTimeIntervalSinceNow:-3 * 3600];
    MMLHHost *pg = Server(@"postgres:5432", @"/", 5432, @"Postgres", 96, MMLHIdle, 5 * 86400 + 2 * 3600);
    pg.kind = @"service"; pg.name = @"postgres"; pg.cwd = @"/opt/homebrew/var/postgresql@16"; pg.launcher = @"Homebrew";
    pg.placeLabel = @"Homebrew service";

    MMLHView *v = [MMLHView new];
    v.hosts = @[checkout, docs, admin, orbit, search, pg, storybook];
    v.mode = @"eager"; v.model = @"Haiku"; v.reviewAt = [NSDate dateWithTimeIntervalSinceNow:-9 * 60];
    v.summaryWords = @"The docs server goes at the next review, after a quiet afternoon. The admin server has not been used since lunch. "
                     @"Postgres is a shared service, so no mode stops it. Nothing else needs a look.";
    v.verdicts = @{
        checkout.findingID: @{@"word": @"in_use", @"kind": @"keep", @"confidence": @0.95, @"about": @"Vite dev server for the acme-web checkout flow",
                              @"reason": @"In use.", @"decidedBy": @"model"},
        orbit.findingID: @{@"word": @"in_use", @"kind": @"keep", @"confidence": @0.9, @"about": @"Next.js server for orbit-api",
                           @"reason": @"The agent's webhook tests call this server, so stopping it would break their next run.", @"decidedBy": @"model"},
        docs.findingID: @{@"word": @"idle", @"kind": @"go", @"confidence": @0.9, @"about": @"Vite dev server for the acme-web docs",
                          @"reason": @"Nobody has opened the docs site since it started yesterday.", @"decidedBy": @"model"}};
    v.plan = @{checkout.findingID: @{@"stop": @NO, @"why": @"in use"},
               orbit.findingID: @{@"stop": @NO, @"why": @"used 4m ago"},
               docs.findingID: @{@"stop": @YES, @"why": @"quiet 3h, and no agent uses it"},
               admin.findingID: @{@"stop": @NO, @"why": @"the review is not sure"}};
    v.candidates = @[docs.findingID, admin.findingID];
    v.links = @{checkout.findingID: @{@"label": @"Worktree", @"value": @"checkout-flow, in use", @"expert": @"workforest", @"findingID": @"workforest:tree:checkout-flow"}};
    v.stopped = @[@{@"rid": @"r1", @"port": @3004, @"framework": @"Vite", @"at": @(NSDate.date.timeIntervalSince1970 - 2 * 3600), @"by": @"eager"}];
    v.idleSeconds = 30 * 60;
    v.act = ^(NSString *what, NSString *key, BOOL option) {};

    NSDictionary *cardKeys = @{checkout.findingID: @"checkout", orbit.findingID: @"orbit", docs.findingID: @"docs", pg.findingID: @"postgres"};
    NSMenu *m = MMMenuForSpec(MMLHMenu(v), ^MMCardSpec *(NSString *findingID) {
        if (!cardKeys[findingID]) return nil;
        for (MMLHHost *h in v.hosts) if ([h.findingID isEqualToString:findingID]) return MMLHCard(h, v);
        return nil;
    }, nil);
    // The rows the menu drew, so each card is checked and drawn from the same menu item the person opens.
    for (NSMenuItem *i in m.itemArray) {
        if (!i.submenu || i.view) continue;
        for (NSString *fid in cardKeys) {
            MMLHHost *h = nil;
            for (MMLHHost *x in v.hosts) if ([x.findingID isEqualToString:fid]) h = x;
            if (![i.title containsString:[NSString stringWithFormat:@":%ld", (long)h.port]]) continue;
            NSString *k = cardKeys[fid];
            s.cards[k] = MMCardForSpec(MMLHCard(h, v));
            s.cardMenus[k] = i.submenu;
            [s.order addObject:k];
        }
    }
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

#pragma mark Settings

/// The Settings window's fixture: the five experts of one Mac, saying what the two menus above say.
static MMSettings *SettingsLike(void) {
    MMSettings *s = [MMSettings new];
    MMSettingsExpert *mm = [MMSettingsExpert expert:@"minmacs" name:@"MinMacs" symbol:@"gauge.with.dots.needle.33percent"];
    mm.headline = @"9.8 GB of memory in use · 3 agents working"; mm.mode = @"proactive";
    MMSettingsExpert *lh = [MMSettingsExpert expert:@"locohost" name:@"LocoHost" symbol:@"server.rack"];
    lh.headline = [NSString stringWithFormat:@"%@ in servers · %@ · 2 quiet", MMBytes(3573ull << 20), MMPlural(7, @"localhost")]; lh.mode = @"eager";
    lh.summary = @"The docs refresh server goes at 18:00, after a quiet afternoon.";
    MMSettingsExpert *wf = [MMSettingsExpert expert:@"workforest" name:@"WorkForest" symbol:@"tree"];
    wf.headline = [NSString stringWithFormat:@"%@ in %@ · %@ to remove", MMPlural(13, @"worktree"), MMPlural(2, @"repo"), MMBytes(5440ull << 20)]; wf.mode = @"proactive";
    MMSettingsExpert *nn = [MMSettingsExpert expert:@"noonoo" name:@"Noo-Noo" symbol:@"sparkles"];
    nn.headline = [NSString stringWithFormat:@"%@ of caches and build output", MMBytes(21ull << 30)]; nn.mode = @"idle"; nn.iconVisible = NO;
    MMSettingsExpert *in = [MMSettingsExpert expert:@"insomnia" name:@"Insomnia" symbol:@"cup.and.saucer"];
    in.headline = @"Keeps the Mac awake for 2 working agents";
    s.experts = @[mm, lh, wf, nn, in];
    s.model = @"auto"; s.oneIcon = NO; s.openAtLogin = YES;
    s.onIcon = ^(NSString *e, BOOL v) {}; s.onMode = ^(NSString *e, NSString *m) {}; s.onModel = ^(NSString *m) {};
    s.onOneIcon = ^(BOOL on) {}; s.onOpenAtLogin = ^(BOOL on) {}; s.onOpenMenu = ^(NSString *e, NSView *v) {};
    return s;
}

/// Single-line labels whose text is wider than their frame, so the render can say nothing is cut off.
static NSArray<NSString *> *CutLabels(NSView *root) {
    NSMutableArray *cut = [NSMutableArray new];
    NSMutableArray *todo = [NSMutableArray arrayWithObject:root];
    while (todo.count) {
        NSView *v = todo.lastObject; [todo removeLastObject];
        if ([v isKindOfClass:NSTextField.class]) {
            NSTextField *t = (NSTextField *)v;
            BOOL wraps = t.cell.wraps || t.maximumNumberOfLines != 1;
            if (!t.stringValue.length) continue;
            if (!wraps && t.attributedStringValue.size.width > t.frame.size.width + 1) [cut addObject:t.stringValue];
            // A wrapping label needs the height of all its lines at its width.
            CGFloat need = ceil([t.attributedStringValue boundingRectWithSize:NSMakeSize(t.frame.size.width - 4, 10000)
                                                                     options:NSStringDrawingUsesLineFragmentOrigin].size.height);
            if (wraps && need > t.frame.size.height + 1) [cut addObject:t.stringValue];
        }
        [todo addObjectsFromArray:v.subviews];
    }
    return cut;
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
    // The Settings window's three panes, in their own folder, since the window is wider than a menu.
    NSString *sout = [out stringByAppendingPathComponent:@"settings"];
    [NSFileManager.defaultManager createDirectoryAtPath:sout withIntermediateDirectories:YES attributes:nil error:nil];
    MMSettings *settings = SettingsLike();
    BOOL sfirst = YES;
    for (NSString *mode in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        if (!ap) continue;
        for (MMSettingsPane p = MMSettingsOverview; p <= MMSettingsGeneral; p++) {
            NSView *v = [settings viewFor:p];
            NSString *name = MMSettingsPaneTitle(p).lowercaseString;
            if (sfirst) {
                // Laid out inside a window first, so the frames are the ones the PNG shows.
                NSWindow *w = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
                w.releasedWhenClosed = NO; w.contentView = v; [w layoutIfNeeded];
                NSArray *cut = CutLabels(v);
                Check(cut.count == 0, [NSString stringWithFormat:@"settings %@: no label is cut off", name], [cut componentsJoinedByString:@", "]);
                Check(v.frame.size.width == MMSettingsWidth, [NSString stringWithFormat:@"settings %@: the pane has the window's width", name],
                      [NSString stringWithFormat:@"%.0f", v.frame.size.width]);
                w.contentView = nil;
                v = [settings viewFor:p];
            }
            NSString *path = [sout stringByAppendingFormat:@"/settings-%@-%@.png", name, mode];
            if (!MMRenderView(v, path, ap)) [unwritten addObject:path.lastPathComponent];
        }
        sfirst = NO;
    }
    // The overview names every expert, a hidden one too.
    NSMutableArray *named = [NSMutableArray new];
    NSMutableArray *todo = [NSMutableArray arrayWithObject:[settings viewFor:MMSettingsOverview]];
    while (todo.count) {
        NSView *v = todo.lastObject; [todo removeLastObject];
        if ([v isKindOfClass:NSTextField.class]) [named addObject:((NSTextField *)v).stringValue];
        [todo addObjectsFromArray:v.subviews];
    }
    NSMutableArray *missing = [NSMutableArray new];
    for (MMSettingsExpert *e in settings.experts) if (![named containsObject:e.name]) [missing addObject:e.name];
    Check(missing.count == 0 && settings.experts.count == 5, @"settings overview: names all five experts", [missing componentsJoinedByString:@", "]);
    Check([named containsObject:@"21.0 GB of caches and build output · icon hidden"], @"settings overview: says when an icon is hidden", @"no line says icon hidden");
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
