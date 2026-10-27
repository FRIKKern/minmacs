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
#import "UI/MMSpecMenu.h"
#import "Core/MMExpert.h"
#import "UI/MMSpecKit.h"
#import "Experts/LocoHost/MMLHHost.h"
#import "Experts/NooNoo/MMNNMenu.h"

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

/// The MinMacs expert's menu for the fixture in test/minmacs/tool.m. test/minmacs.sh renders the expert's own output
/// from the same fixture to build/render/minmacs, so the two can be compared line by line.
static Subject *MinMacsLike(void) {
    Subject *s = [Subject new]; s.name = @"minmacs"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    NSMenu *m = [NSMenu new];
    [m addItem:MMHeaderItem(MMBytes(9216ull << 20), @"in apps", nil, [NSString stringWithFormat:@"%@ · 40%% CPU · 1 agent working · Proactive", MMPlural(9, @"app")])];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMTextItem(@"Watching 9 apps. Quits nothing on its own. Memory pressure is high, so quitting apps helps now. "
                          @"Spotify and Slack lead the close list, and nothing uses them. Figma stays, because Claude Code started it and is working.", MMMaxSummaryLines)];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMActionItem(@"Quit Apps", [NSString stringWithFormat:@"%@, %@", MMPlural(3, @"app"), MMBytes(2540ull << 20)], @selector(copy:), nil)];
    [m addItem:MMActionItem(@"Trim Tabs", MMPlural(1, @"browser"), @selector(copy:), nil)];

    MMCard *spotify = Card(@"Spotify", MMMarkGoes, @"Goes on Quit Apps.", @"It is on the close list, and nothing uses it. Restore opens it again.");
    [spotify fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 6%% CPU", MMBytes(1310ull << 20)]];
    [spotify fact:@"Energy" value:@"in the top three"];
    [spotify fact:@"Processes" value:@"9"];
    [spotify fact:@"List" value:@"close list"];
    [spotify action:Act(@"Quit")];
    [spotify action:Act(@"Always Keep")];
    [spotify action:Act(@"Leave Unsorted")];

    MMCard *slack = Card(@"Slack", MMMarkBlocked, @"Did not quit.", @"It may be asking to save. Force Quit closes it now, and unsaved changes are lost.");
    [slack fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 2%% CPU", MMBytes(820ull << 20)]];
    [slack fact:@"Processes" value:@"7"];
    [slack fact:@"List" value:@"close list"];
    [slack action:Act(@"Force Quit")];
    [slack action:Act(@"Always Keep")];
    [slack action:Act(@"Leave Unsorted")];

    MMCard *chrome = Card(@"Google Chrome", MMMarkQuiet, @"Stays.", @"Browsers are trimmed, not quit. Trim Tabs closes noise tabs such as youtube.com.");
    [chrome fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 18%% CPU", MMBytes(2450ull << 20)]];
    [chrome fact:@"Energy" value:@"uses the most energy"];
    [chrome fact:@"Processes" value:@"31"];
    [chrome fact:@"List" value:@"close list"];
    [chrome action:Act(@"Quit")];
    [chrome action:Act(@"Trim Tabs")];
    [chrome action:Act(@"Always Keep")];
    [chrome action:Act(@"Leave Unsorted")];

    MMCard *figma = Card(@"Figma", MMMarkWorking, @"Stays.", @"Claude Code started it and is working. MinMacs looks again once the agent is idle.");
    [figma fact:@"Uses" value:[NSString stringWithFormat:@"%@ · 9%% CPU", MMBytes(1130ull << 20)]];
    [figma fact:@"Energy" value:@"in the top three"];
    [figma fact:@"Processes" value:@"6"];
    [figma fact:@"List" value:@"close list"];
    [figma action:MMDimmedItem(@"Quit", @"in use")];
    [figma action:Act(@"Always Keep")];
    [figma action:Act(@"Leave Unsorted")];

    MMAddSection(m, @"Will quit", @[
        Row(s, @"spotify", @"Spotify", nil, @[MMBytes(1310ull << 20), @"6% CPU"], MMMarkGoes, spotify),
        Row(s, @"slack", @"Slack", nil, @[MMBytes(820ull << 20), @"2% CPU", @"did not quit"], MMMarkBlocked, slack),
        Row(s, @"photos", @"Photos", nil, @[MMBytes(410ull << 20), @"0% CPU"], MMMarkGoes, nil)]);
    MMAddSection(m, @"Browsers", @[Row(s, @"chrome", @"Google Chrome", nil, @[MMBytes(2450ull << 20), @"18% CPU", @"trims noise tabs"], MMMarkQuiet, chrome)]);
    MMAddSection(m, @"Spared", @[
        Row(s, @"figma", @"Figma", nil, @[MMBytes(1130ull << 20), @"9% CPU", @"Claude Code works"], MMMarkWorking, figma),
        Row(s, @"notion", @"Notion", nil, @[MMBytes(640ull << 20), @"1% CPU", @"serving :51789"], MMMarkWorking, nil)]);
    MMAddSection(m, @"Agents", @[
        Row(s, @"claude", @"Claude Code", nil, @[@"acme-web", MMBytes(720ull << 20), @"working"], MMMarkWorking, nil),
        Row(s, @"codex", @"Codex", nil, @[@"orbit-api", MMBytes(180ull << 20), @"idle"], MMMarkQuiet, nil)]);
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:MMMoreItem(@[MMActionItem(@"Restore 1 Closed Item", @"now", @selector(copy:), nil), Act(@"Edit Rules…")])];
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

/// One fixture clutter row for the Noo-Noo subject.
static MMNNRow *Clutter(NSString *fid, NSString *name, NSString *owner, NSString *state, MMNNSection section, uint64_t freedMB, uint64_t onDiskMB, NSTimeInterval idle) {
    MMNNRow *r = [MMNNRow new];
    r.findingID = [@"noonoo:clutter:" stringByAppendingString:fid]; r.kindID = fid; r.name = name; r.owner = owner; r.ownerState = state;
    r.section = section; r.freed = freedMB << 20; r.allocated = onDiskMB << 20; r.members = 1;
    r.lastUsed = [NSDate dateWithTimeIntervalSinceNow:-idle];
    r.actionTitle = @"Move to Trash"; r.undoWords = @"It goes to the Trash, and Undo moves it back.";
    return r;
}

/// Noo-Noo's own menu and cards, built by Sources/Experts/NooNoo/MMNNMenu from fixture rows, and drawn by the kit.
/// The Mac is the one the LocoHost subject shows: the search worktree of acme-web is squash-merged.
static Subject *NooNooLike(void) {
    Subject *s = [Subject new]; s.name = @"noonoo"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    MMNNRow *next = Clutter(@"search-next", @".next", @"search", @"squash-merged", MMNNFinished, 3170, 3170, 6 * 86400);
    next.folder = YES;
    next.ownerLinkExpert = @"workforest"; next.ownerLinkID = @"workforest:worktree:search"; next.rebuild = @"next build, minutes"; next.goesOnItsOwn = YES;
    MMNNRow *nm = Clutter(@"search-nm", @"node_modules", @"search", @"squash-merged", MMNNFinished, 3, 1536, 6 * 86400);
    nm.folder = YES;
    nm.ownerLinkExpert = @"workforest"; nm.ownerLinkID = @"workforest:worktree:search"; nm.rebuild = @"pnpm install from the store, seconds with a warm store"; nm.goesOnItsOwn = YES;
    MMNNRow *onb = Clutter(@"onboarding-nm", @"node_modules", @"old-onboarding", @"remote branch deleted", MMNNFinished, 420, 900, 21 * 86400);
    onb.goesOnItsOwn = YES; onb.folder = YES;
    MMNNRow *scratch = Clutter(@"scratch", @"Claude Code scratch", @"session c55990c5", nil, MMNNLeftovers, 3410, 3410, 2 * 86400);
    scratch.why = @"nothing has used it for 2 days"; scratch.rebuild = @"nothing is lost; a session makes its scratch again"; scratch.goesOnItsOwn = YES;
    MMNNRow *fam = Clutter(@"family", @"server-budget-* folders", nil, nil, MMNNLeftovers, 12, 12, 3 * 86400);
    fam.members = 745; fam.why = @"nothing has used it for 3 days"; fam.goesOnItsOwn = YES;
    MMNNRow *gob = Clutter(@"go-build", @"Go build cache", nil, nil, MMNNCaches, 2980, 2980, 3600);
    gob.rebuild = @"slower next builds";
    MMNNRow *pnpm = Clutter(@"pnpm-store", @"pnpm store", nil, nil, MMNNCaches, 5610, 5610, 2 * 3600);
    pnpm.actionTitle = @"Clean with pnpm"; pnpm.undoWords = @"A recovery copy is made first, and Undo copies back what the tool removed.";
    pnpm.rebuild = @"downloads on the next install";
    MMNNRow *pw = Clutter(@"playwright", @"Playwright browsers", @"chromium-1187", nil, MMNNCaches, 2540, 2540, 9 * 86400);
    MMNNRow *live = Clutter(@"checkout-nm", @"node_modules", @"checkout-flow", nil, MMNNKept, 4, 1610, 60);
    live.live = YES; live.folder = YES; live.why = @"an agent works in checkout-flow";
    MMNNRow *tx = Clutter(@"transcripts", @"Claude Code transcripts", @"acme-web", nil, MMNNKept, 2040, 2040, 600);
    tx.kept = YES; tx.ownerSetting = @"Claude Code keeps transcripts for 30 days, set by cleanupPeriodDays"; tx.actionTitle = nil;

    MMNNView *v = [MMNNView new];
    v.rows = @[next, nm, onb, scratch, fam, gob, pnpm, pw, live, tx];
    v.growthLine = MMNNGrowthLine(@"pnpm store", YES, 9.0 * 1073741824 / 14, 14, 0.6 * 1073741824, 9.6 * 1073741824, 1.9, 1073741824);
    v.trashBytes = 2150ull << 20; v.modeName = @"Proactive";
    v.restorable = 1; v.lastClean = [NSDate dateWithTimeIntervalSinceNow:-26 * 60]; v.lastScan = [NSDate dateWithTimeIntervalSinceNow:-12 * 60];
    MMNNHandlers *h = [MMNNHandlers new];
    NSDictionary *cardKeys = @{next.findingID: @"next", scratch.findingID: @"scratch", pnpm.findingID: @"pnpm", live.findingID: @"live", tx.findingID: @"transcripts"};
    // The kit asks for cards in row order, so the rows that got one are matched to the menu's card items in that order.
    NSMutableArray<MMNNRow *> *asked = [NSMutableArray new];
    NSMenu *m = MMMenuForSpec(MMNNMenuFor(v, h), ^MMCardSpec *(NSString *findingID) {
        if (!cardKeys[findingID]) return nil;
        for (MMNNRow *r in v.rows) if ([r.findingID isEqualToString:findingID]) { [asked addObject:r]; return MMNNCardFor(r, v, h); }
        return nil;
    }, nil);
    NSUInteger n = 0;
    for (NSMenuItem *i in m.itemArray) {
        if (!i.submenu || i.view || !i.submenu.itemArray.firstObject.view || n >= asked.count) continue;
        MMNNRow *r = asked[n++];
        NSString *k = cardKeys[r.findingID];
        s.cards[k] = MMCardForSpec(MMNNCardFor(r, v, h));
        s.cardMenus[k] = i.submenu;
        [s.order addObject:k];
    }
    s.menu = m;
    Check(s.order.count == cardKeys.count, @"noonoo: every fixture card hangs under its row", [NSString stringWithFormat:@"%lu of %lu", (unsigned long)s.order.count, (unsigned long)cardKeys.count]);
    Check([v.growthLine isEqualToString:@"The pnpm store grew 9.0 GB in 14 days."], @"noonoo: the growth line reads as measured", v.growthLine);
    return s;
}

#pragma mark Shell

// The app shell draws every expert's menu from the specs of Core/MMExpert.h through Sources/UI/MMSpecMenu.
// These subjects are specs, as an expert hands them over, so the render checks what the menu bar shows.

static MMRowSpec *SRow(NSString *name, NSArray *facts, MMRowMark mark, NSString *fid) {
    MMRowSpec *r = [MMRowSpec new]; r.name = name; r.facts = facts; r.mark = mark; r.findingID = fid; return r;
}
static MMSectionSpec *SSection(NSString *title, NSArray *rows) { MMSectionSpec *s = [MMSectionSpec new]; s.title = title; s.rows = rows; return s; }
static MMActionSpec *SAct(NSString *title, NSString *tail) { return [MMActionSpec title:title tail:tail run:^(BOOL option) {}]; }

static MMMenuSpec *LocoHostSpec(void) {
    MMMenuSpec *m = [MMMenuSpec new];
    m.headerBig = MMBytes(2117ull << 20); m.headerUnit = @"in servers";
    m.headerLine = [NSString stringWithFormat:@"%@ · 2 in use · 1 quiet · Proactive", MMPlural(3, @"localhost")];
    m.summary = @"The docs server has been quiet since lunch and goes at the next review. The checkout server is in use from Safari.";
    MMActionSpec *close = SAct(@"Close Idle", [NSString stringWithFormat:@"%@, %@", MMPlural(1, @"server"), MMBytes(512ull << 20)]);
    close.optionTitle = @"Force Close Idle";
    m.actions = @[close, SAct(@"Review Now", MMAgo([NSDate dateWithTimeIntervalSinceNow:-9 * 60]))];
    m.sections = @[SSection(@"In use", @[SRow(@"checkout-flow", @[@"Vite", MMBytes(905ull << 20), @"in Safari"], MMRowMarkWorking, @"checkout"),
                                         SRow(@"orbit-api", @[@"Next.js", MMBytes(700ull << 20), @"used 4m ago"], MMRowMarkRecent, nil)]),
                   SSection(@"Quiet", @[SRow(@"docs", @[@"Vite", MMBytes(512ull << 20), @"goes at the next review"], MMRowMarkGoes, @"docs")])];
    m.more = @[SAct(@"Recently Stopped", nil)];
    return m;
}

static MMMenuSpec *MinMacsSpec(void) {
    MMMenuSpec *m = [MMMenuSpec new];
    m.headerBig = MMBytes(9800ull << 20); m.headerUnit = @"of memory in use";
    m.headerLine = @"3 agents working · 2 apps to quit · Proactive";
    m.summary = @"Two apps have been in the background all day. Claude Code works in two sessions.";
    MMActionSpec *quit = SAct(@"Quit Idle Apps", [NSString stringWithFormat:@"%@, %@", MMPlural(2, @"app"), MMBytes(1400ull << 20)]);
    MMActionSpec *trim = SAct(@"Trim Browser Tabs", nil); trim.disabledReason = @"no noise tabs";
    m.actions = @[quit, trim];
    m.sections = @[SSection(@"Agents", @[SRow(@"Claude Code", @[@"checkout-flow", MMBytes(610ull << 20), @"working"], MMRowMarkWorking, nil),
                                         SRow(@"Codex", @[@"orbit-api", MMBytes(220ull << 20), @"waits on you"], MMRowMarkBlocked, nil)]),
                   SSection(@"Apps to quit", @[SRow(@"Keynote", @[@"Apple", MMBytes(900ull << 20), @"idle 6h"], MMRowMarkGoes, @"keynote"),
                                               SRow(@"Photoshop", @[@"Adobe", MMBytes(500ull << 20), @"idle 3h"], MMRowMarkGoes, nil)])];
    return m;
}

static MMCardSpec *SCard(NSString *fid) {
    MMCardSpec *c = [MMCardSpec new];
    if ([fid isEqualToString:@"checkout"]) {
        c.title = @"Vite dev server for the acme-web checkout flow"; c.statusWord = @"Stays."; c.mark = MMRowMarkWorking;
        c.statusText = @"Safari has it open. Proactive looks again after 30 minutes of quiet.";
        MMCardFact *wt = [MMCardFact label:@"Worktree" value:@"checkout-flow, in use"]; wt.linkExpert = @"WorkForest"; wt.linkFindingID = @"workforest:worktree:checkout-flow";
        c.facts = @[[MMCardFact label:@"Where" value:@"cmux, tab “checkout”"], [MMCardFact label:@"Up" value:@"3h 12m, started by pnpm dev"],
                    [MMCardFact label:@"Uses" value:[NSString stringWithFormat:@"%@ · 4%% CPU", MMBytes(905ull << 20)]], wt];
        MMActionSpec *stop = SAct(@"Stop", nil); stop.optionTitle = @"Force Stop";
        c.actions = @[SAct(@"Go to “checkout”", nil), SAct(@"Open localhost:3000", nil), SAct(@"Keep for 4 Hours", nil), stop, SAct(@"Copy URL", nil)];
    } else if ([fid isEqualToString:@"docs"]) {
        c.title = @"Vite dev server for the acme-web docs"; c.statusWord = @"Goes at the next review."; c.mark = MMRowMarkGoes;
        c.statusText = @"Quiet for 3 hours, and no agent uses it. Restore starts it again.";
        c.facts = @[[MMCardFact label:@"Where" value:@"Terminal, tab “docs”"], [MMCardFact label:@"Up" value:@"1d 2h, started by pnpm docs"],
                    [MMCardFact label:@"Git" value:@""]];
        c.noteBy = @"Haiku says idle"; c.note = @"Nobody has opened the docs site since it started yesterday.";
        MMActionSpec *go = SAct(@"Go to Tab", nil); go.disabledReason = @"the tab has closed";
        c.actions = @[go, SAct(@"Keep for 4 Hours", nil), SAct(@"Stop", nil)];
    } else {
        c.title = @"Keynote"; c.statusWord = @"Goes at 18:00."; c.mark = MMRowMarkGoes;
        c.statusText = @"In the background for 6 hours with no window in use.";
        c.facts = @[[MMCardFact label:@"Uses" value:[NSString stringWithFormat:@"%@ · 0%% CPU", MMBytes(900ull << 20)]],
                    [MMCardFact label:@"Energy" value:@"uses little energy"]];
        c.actions = @[SAct(@"Quit", nil), SAct(@"Keep Today", nil)];
    }
    return c;
}

/// The shell's PNGs go in their own folder: each expert's menu and card as the shell builds them, One Icon, the icons.
static void RenderShell(NSString *out, NSDictionary<NSString *, NSAppearance *> *appearances, NSMutableArray *unwritten) {
    NSString *dir = [out stringByAppendingPathComponent:@"shell"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    MMCardProvider cards = ^MMCardSpec *(NSString *fid) { return SCard(fid); };
    MMOneIconPart *mm = [MMOneIconPart new]; mm.name = @"MinMacs"; mm.spec = MinMacsSpec(); mm.cards = cards;
    MMOneIconPart *lh = [MMOneIconPart new]; lh.name = @"LocoHost"; lh.spec = LocoHostSpec(); lh.cards = cards;
    NSDictionary<NSString *, NSMenu *> *menus = @{
        @"shell-locohost-menu": MMMenuFromSpec(LocoHostSpec(), cards, nil, nil),
        @"shell-minmacs-menu": MMMenuFromSpec(MinMacsSpec(), cards, @"MinMacs opens at login. Settings can turn that off.", nil),
        @"shell-one-icon": MMOneIconMenu(@[mm, lh], nil, nil),
    };
    NSDictionary<NSString *, NSMenu *> *cardMenus = @{
        @"shell-card-checkout": [MMCardFromSpec(SCard(@"checkout")) menu],
        @"shell-card-docs": [MMCardFromSpec(SCard(@"docs")) menu],
        @"shell-card-keynote": [MMCardFromSpec(SCard(@"keynote")) menu],
    };
    for (NSString *k in menus) CheckMenu(menus[k], k);
    for (NSString *k in @[@"checkout", @"docs", @"keynote"]) {
        NSArray *p = [MMCardFromSpec(SCard(k)) layoutProblems];
        Check(p.count == 0, [NSString stringWithFormat:@"shell card %@: follows the card rules", k], [p componentsJoinedByString:@"; "]);
    }
    // A card is one level deep in One Icon too: no row's submenu holds another row with a submenu.
    NSInteger deep = 0;
    for (NSMenuItem *i in menus[@"shell-one-icon"].itemArray) for (NSMenuItem *j in i.submenu.itemArray) if (j.submenu && ![j.title isEqualToString:@"More"]) deep++;
    Check(deep == 0, @"shell one icon: experts never nest, a card is one level deep", [NSString stringWithFormat:@"%ld nested", (long)deep]);
    NSInteger sections = 0;
    for (NSMenuItem *i in menus[@"shell-one-icon"].itemArray) sections += i.isSectionHeader;
    Check(sections == 2, @"shell one icon: one section per visible expert", [NSString stringWithFormat:@"%ld sections", (long)sections]);
    NSArray *experts = @[@[@"MinMacs", @"gauge.with.dots.needle.33percent", @"2 apps to quit", @""], @[@"LocoHost", @"server.rack", @"1 idle server", @"1"]];
    for (NSArray *e in experts) Check(MMStatusImage(e[1], MMStatusLabel(e[0], e[2])) != nil, [NSString stringWithFormat:@"shell: the %@ symbol exists", e[0]], e[1]);
    BOOL first = YES;
    for (NSString *mode in @[@"light", @"dark", @"contrast-light", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        if (!ap) continue;
        NSMutableDictionary *all = [menus mutableCopy]; [all addEntriesFromDictionary:cardMenus];
        for (NSString *k in all) {
            NSString *path = [dir stringByAppendingFormat:@"/%@-%@.png", k, mode];
            NSArray *cut = MMRenderMenu(all[k], path, ap);
            if (!cut) [unwritten addObject:path.lastPathComponent];
            if (first) Check(cut.count == 0, [k stringByAppendingString:@": no item is cut off"], [cut componentsJoinedByString:@", "]);
        }
        NSString *path = [dir stringByAppendingFormat:@"/shell-status-%@.png", mode];
        if (!MMRenderView(StatusStrip(experts), path, ap)) [unwritten addObject:path.lastPathComponent];
        first = NO;
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: render <output folder>\n"); return 2; }
    [NSApplication sharedApplication];
    NSString *out = @(argv[1]);
    [NSFileManager.defaultManager createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
    gChecks = [NSMutableArray new];

    NSArray<Subject *> *subjects = @[LocoHostLike(), WorkForestLike(), MinMacsLike(), NooNooLike()];
    NSArray *experts = @[@[@"LocoHost", @"server.rack", @"2 idle servers", @"2"], @[@"WorkForest", @"tree", @"2 worktrees to remove", @""],
                         @[@"MinMacs", @"gauge.with.dots.needle.33percent", @"3 apps to quit", @""],
                         @[@"Noo-Noo", @"trash.square", @"2 finished projects, 17.7 GB to free", @""]];
    for (NSArray *e in experts) {
        NSString *label = MMStatusLabel(e[0], e[2]);
        NSString *word = [NSString stringWithFormat:@"\\b%@\\b", [NSRegularExpression escapedPatternForString:e[1]]];
        Check([label rangeOfString:word options:NSRegularExpressionSearch].location == NSNotFound && [label hasPrefix:e[0]] &&
              [MMStatusImage(e[1], label).accessibilityDescription isEqualToString:label], [NSString stringWithFormat:@"%@: the status label names the expert, not the symbol", e[0]], label);
        Check(MMStatusImage(e[1], label) != nil, [NSString stringWithFormat:@"%@: the symbol %@ exists", e[0], e[1]], @"no such symbol");
        // Noo-Noo's hyphen is not part of its autosave name, which is its expert id, noonoo.
        Check([MMStatusAutosaveName(e[0]) isEqualToString:[@"minmacs." stringByAppendingString:[[e[0] lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""]]],
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
    // The two subjects with a model note. The MinMacs subject has none, since its rules decide every app.
    for (Subject *s in [subjects subarrayWithRange:NSMakeRange(0, 2)]) {
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
    RenderShell(out, appearances, unwritten);
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
