// Renders fixture menus and hover cards built with the menu kit to PNG, in light, dark and Increase Contrast.
// Nothing is scanned and no model is asked: the subjects are made up here. LocoHost's menu and cards come from its own
// spec code in Sources/Experts/LocoHost, fed fixture servers, and WorkForest's from Sources/Experts/WorkForest, fed fixture worktrees.
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
#import "Experts/WorkForest/MMWFTree.h"

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

/// One fixture worktree for the WorkForest subject. Its git facts are known and its disk is walked.
static MMWFTree *Tree(NSString *repo, NSString *folder, NSString *branch, uint64_t mb, uint64_t cacheMB, NSTimeInterval quiet) {
    MMWFTree *t = [MMWFTree new];
    t.repo = [@"/Users/dev/code" stringByAppendingPathComponent:repo];
    t.path = [[t.repo stringByAppendingString:@".worktrees"] stringByAppendingPathComponent:folder];
    t.findingID = [@"workforest:worktree:" stringByAppendingString:t.path];
    t.branch = branch; t.maker = @"person"; t.gitKnown = YES; t.head = @"4f1c2d9e8a7b";
    t.defaultBranch = @"origin/main"; t.upstream = [@"origin/" stringByAppendingString:branch ?: @""]; t.onRemote = YES;
    t.sized = YES; t.diskBytes = mb << 20; t.freedBytes = mb << 20; t.cacheBytes = cacheMB << 20; t.files = 1200;
    t.lastCommit = [NSDate dateWithTimeIntervalSinceNow:-quiet]; t.touched = t.lastCommit; t.created = [NSDate dateWithTimeIntervalSinceNow:-quiet - 86400];
    return t;
}

/// WorkForest's own menu and cards, built by Sources/Experts/WorkForest/MMWFTree.m from fixture worktrees, and drawn by
/// the kit through Sources/UI/MMSpecKit. The same code draws the app's menu from the graph. The fixture is the Mac the
/// LocoHost subject shows: the checkout server runs in the checkout-flow worktree.
static Subject *WorkForestLike(void) {
    Subject *s = [Subject new]; s.name = @"workforest"; s.cards = [NSMutableDictionary new]; s.cardMenus = [NSMutableDictionary new]; s.order = [NSMutableArray new];
    MMWFTree *promo = Tree(@"acme-web", @"acme-web-promo-banner", @"feat/promo-banner", 4900, 3900, 6 * 86400 + 3 * 3600);
    promo.merged = @"squash"; promo.upstream = @"gone"; promo.notInDefault = 2;
    MMWFTree *docs = Tree(@"acme-web", @"acme-web-docs-refresh", @"docs/refresh", 540, 380, 13 * 86400);
    docs.merged = @"ancestor";
    MMWFTree *checkout = Tree(@"acme-web", @"acme-web-checkout-flow", @"feat/checkout-flow", 905, 610, 3 * 3600);
    checkout.processes = @[@"node", @"zsh"]; checkout.notInDefault = 4;
    checkout.session = @{@"agent": @"Claude Code", @"title": @"Checkout flow", @"lastActiveAt": @(NSDate.date.timeIntervalSince1970 - 20 * 60), @"live": @YES};
    MMWFTree *search = Tree(@"acme-web", @"acme-web-search-facets", @"feat/search-facets", 820, 610, 2 * 3600);
    search.dirty = 3; search.notInDefault = 2;
    search.session = @{@"agent": @"Claude Code", @"title": @"Facet filters", @"lastActiveAt": @(NSDate.date.timeIntervalSince1970 - 2 * 3600)};
    MMWFTree *hooks = Tree(@"orbit-api", @"billing-webhooks", @"fix/billing-webhooks", 1300, 900, 36 * 3600);
    hooks.processes = @[@"node"]; hooks.notInDefault = 1;
    MMWFTree *limits = Tree(@"orbit-api", @"rate-limits", @"wip/rate-limits", 310, 120, 9 * 86400);
    limits.notInDefault = 5;
    NSMutableArray *trees = [@[promo, docs, checkout, search, hooks, limits] mutableCopy];
    NSArray *names = @[@"onboarding-copy", @"pricing-table", @"sso-okta", @"dark-mode", @"image-cdn", @"cart-refactor", @"i18n-nb"];
    for (NSUInteger k = 0; k < names.count; k++) {
        // dark-mode has been quiet for three weeks, so it is stale.
        MMWFTree *q = Tree(k % 2 ? @"orbit-api" : @"acme-web", k % 2 ? names[k] : [@"acme-web-" stringByAppendingString:names[k]],
                           [@"feat/" stringByAppendingString:names[k]], 120 + 40 * k, 60, (k == 3 ? 21 : 4 + k) * 86400);
        q.notInDefault = 1 + k % 3;
        [trees addObject:q];
    }
    for (NSString *repo in @[@"acme-web", @"orbit-api"]) {
        MMWFTree *m = Tree(repo, repo, @"main", 2400, 1800, 3600);
        m.path = m.repo; m.isMain = YES; m.findingID = [@"workforest:worktree:" stringByAppendingString:m.path];
        [trees addObject:m];
    }

    MMWFView *v = [MMWFView new];
    v.trees = trees;
    v.mode = @"eager"; v.model = @"Haiku"; v.reviewAt = [NSDate dateWithTimeIntervalSinceNow:-9 * 60];
    v.summaryWords = @"The promo banner branch is squash-merged and its remote branch is deleted. The docs refresh is merged and untouched "
                     @"for two weeks. Both go at the next review. The rate limits branch is parked on purpose, so it stays.";
    NSString *promoWhy = @"Squash-merged, and its remote branch is deleted";
    v.verdicts = @{
        promo.findingID: @{@"word": @"stale", @"kind": @"go", @"confidence": @0.92, @"about": @"Promo banner for acme-web, squash-merged",
                           @"reason": promoWhy, @"decidedBy": @"model"},   // repeats the status, so the card leaves it out
        docs.findingID: @{@"word": @"stale", @"kind": @"go", @"confidence": @0.9, @"about": @"Docs refresh for acme-web", @"reason": @"Merged and untouched for 13 days.", @"decidedBy": @"model"},
        checkout.findingID: @{@"word": @"active", @"kind": @"keep", @"confidence": @1, @"reason": @"node runs inside it.", @"decidedBy": @"workforest.holds-work"},
        hooks.findingID: @{@"word": @"active", @"kind": @"keep", @"confidence": @0.9, @"about": @"Webhook retries for orbit-api",
                           @"reason": @"The retry tests added in the last commit still fail, so the work is not done.", @"decidedBy": @"model"},
        limits.findingID: @{@"word": @"active", @"kind": @"keep", @"confidence": @0.85, @"judged": @YES, @"about": @"Rate limits per API key for orbit-api, parked on purpose",
                            @"reason": @"Most of the work is still ahead.",
                            @"keepEvidence": @"the branch name says the work is parked", @"decidedBy": @"judge"}};
    v.plan = @{promo.findingID: @{@"remove": @YES, @"why": promoWhy},
               docs.findingID: @{@"remove": @YES, @"why": @"Merged and untouched for 13 days."},
               checkout.findingID: @{@"remove": @NO, @"why": @"node running inside"},
               search.findingID: @{@"remove": @NO, @"why": @"3 changes not committed"},
               hooks.findingID: @{@"remove": @NO, @"why": @"node running inside"},
               limits.findingID: @{@"remove": @NO, @"why": @"evidence: the branch name says the work is parked"}};
    v.candidates = @[promo.findingID, docs.findingID];
    v.links = @{checkout.findingID: @[@{@"label": @"Server", @"value": @":3000 Vite, in use", @"expert": @"locohost", @"findingID": @"locohost:server:~/code/acme-web.worktrees/checkout-flow#dev"}],
                hooks.findingID: @[@{@"label": @"Server", @"value": @":4000 Next.js", @"expert": @"locohost", @"findingID": @"locohost:server:~/code/orbit-api#dev"}]};
    v.removed = @[@{@"rid": @"r1", @"path": @"/Users/dev/code/acme-web.worktrees/acme-web-old-landing", @"branch": @"feat/old-landing",
                    @"at": @(NSDate.date.timeIntervalSince1970 - 3 * 86400), @"by": @"proactive", @"saved": @[@".env.local"]}];
    v.act = ^(NSString *what, NSString *key, BOOL option) {};

    MMMenuSpec *spec = MMWFMenu(v);
    {
        NSArray *(^titles)(MMCardSpec *) = ^NSArray *(MMCardSpec *c) { return [c.actions valueForKey:@"title"]; };
        MMWFView *pv = [MMWFView new]; pv.trees = trees; pv.mode = @"eager"; pv.protectedPaths = [NSSet setWithObject:docs.findingID];
        MMWFTree *dev = Tree(@"acme-web", @"acme-web-develop", @"develop", 100, 0, 30 * 86400); dev.isProtected = YES;
        BOOL ok = [titles(MMWFCard(docs, pv)) containsObject:@"Unprotect"] && [titles(MMWFCard(promo, pv)) containsObject:@"Protect"] &&
                  ![titles(MMWFCard(dev, pv)) containsObject:@"Protect"] && ![titles(MMWFCard(dev, pv)) containsObject:@"Unprotect"];
        Check(ok, @"workforest: Protect follows the protect list, and a long-lived branch has none", [titles(MMWFCard(docs, pv)) componentsJoinedByString:@", "]);
    }
    Check([spec.headerUnit isEqualToString:@"in worktrees"] && spec.sections.count == 4,
          @"workforest: the menu is MMWFMenu's spec, with four sections", [NSString stringWithFormat:@"%lu sections", (unsigned long)spec.sections.count]);
    NSDictionary *cardKeys = @{promo.findingID: @"promo", checkout.findingID: @"checkout", search.findingID: @"search", hooks.findingID: @"hooks",
                               limits.findingID: @"limits"};
    MMWFTree *(^treeFor)(NSString *) = ^MMWFTree *(NSString *fid) {
        for (MMWFTree *t in trees) if ([t.findingID isEqualToString:fid]) return t;
        return nil;
    };
    NSMenu *m = MMMenuForSpec(spec, ^MMCardSpec *(NSString *findingID) {
        return cardKeys[findingID] ? MMWFCard(treeFor(findingID), v) : nil;
    }, nil);
    // The rows the menu drew, so each card is checked and drawn from the same menu item the person opens.
    NSMutableDictionary<NSString *, NSString *> *byName = [NSMutableDictionary new];
    for (MMSectionSpec *sec in spec.sections) for (MMRowSpec *r in sec.rows) if (cardKeys[r.findingID]) byName[r.name] = r.findingID;
    for (NSMenuItem *i in m.itemArray) {
        if (!i.submenu || i.view) continue;
        NSString *fid = nil;
        for (NSString *name in byName) if ([i.title hasSuffix:name] || [i.title containsString:[name stringByAppendingString:@"\n"]]) fid = byName[name];
        if (!fid || s.cards[cardKeys[fid]]) continue;
        NSString *k = cardKeys[fid];
        s.cards[k] = MMCardForSpec(MMWFCard(treeFor(fid), v));
        s.cardMenus[k] = i.submenu;
        [s.order addObject:k];
    }
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

    NSArray<Subject *> *subjects = @[LocoHostLike(), WorkForestLike(), MinMacsLike()];
    NSArray *experts = @[@[@"LocoHost", @"server.rack", @"2 idle servers", @"2"], @[@"WorkForest", @"tree", @"2 worktrees to remove", @""],
                         @[@"MinMacs", @"gauge.with.dots.needle.33percent", @"3 apps to quit", @""]];
    for (NSArray *e in experts) {
        NSString *label = MMStatusLabel(e[0], e[2]);
        NSString *word = [NSString stringWithFormat:@"\\b%@\\b", [NSRegularExpression escapedPatternForString:e[1]]];
        Check([label rangeOfString:word options:NSRegularExpressionSearch].location == NSNotFound && [label hasPrefix:e[0]] &&
              [MMStatusImage(e[1], label).accessibilityDescription isEqualToString:label], [NSString stringWithFormat:@"%@: the status label names the expert, not the symbol", e[0]], label);
        Check(MMStatusImage(e[1], label) != nil, [NSString stringWithFormat:@"%@: the symbol %@ exists", e[0], e[1]], @"no such symbol");
        Check([MMStatusAutosaveName(e[0]) isEqualToString:[@"minmacs." stringByAppendingString:[e[0] lowercaseString]]],
              [NSString stringWithFormat:@"%@: autosaveName is minmacs.<expert>", e[0]], MMStatusAutosaveName(e[0]));
    }

    // The card check itself: a card given six facts shows five and says so, so a check that passes is not empty.
    {
        MMCard *six = Card(@"Six facts", MMMarkQuiet, @"Stays.", @"A fixture that breaks the five-fact rule on purpose.");
        for (NSString *k in @[@"One", @"Two", @"Three", @"Four", @"Five", @"Six"]) [six fact:k value:@"a value"];
        NSArray *p = [six layoutProblems];
        Check([p isEqualToArray:@[@"6 facts given, five shown"]], @"the card check reports a sixth fact", [p componentsJoinedByString:@"; "]);
    }

    for (Subject *s in subjects) {
        CheckMenu(s.menu, s.name);
        CGFloat column = -1; NSMutableArray *off = [NSMutableArray new];
        for (NSString *k in s.order) {
            MMCard *c = s.cards[k];
            NSArray *p = [c layoutProblems];
            Check(p.count == 0, [NSString stringWithFormat:@"%@ card %@: follows the card rules", s.name, k], [p componentsJoinedByString:@"; "]);
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
