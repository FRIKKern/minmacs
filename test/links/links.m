// The cross-link check for test/links.sh, issue #26. It registers LocoHost and WorkForest, builds the cold CLI's
// snapshot from the fixture repos and servers, and clicks through from each side the way a person does: it builds a
// card from its spec with the kit, picks the card's link row, and opens what the link opens through the shell's
// MMLinkMenu. The linked card must be the first row below the header. It also renders both cards to PNG.
// Usage: links <worktree> <port in it> <render folder>. Prints one JSON object.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Shell/MMShell.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/WorkForest/MMWorkForest.h"

extern BOOL MMLHInCLI;

static NSString *gExpert, *gKey;

/// The card of a finding as the kit builds it, its link rows, and what picking each one asks to open.
static NSDictionary *Click(MMCardSpec *spec, NSMutableArray<NSMenu *> *keep) {
    NSMenu *m = [MMCardFromSpec(spec) menu];
    [keep addObject:m];
    NSMutableArray *links = [NSMutableArray new];
    for (NSInteger i = 0; i < m.numberOfItems; i++) {
        NSMenuItem *item = [m itemAtIndex:i];
        if (!MMLinkOfItem(item)) continue;
        gExpert = nil; gKey = nil;
        [m performActionForItemAtIndex:i];   // as a click on the row does
        [links addObject:@{@"index": @(i), @"title": item.title ?: @"", @"expert": gExpert ?: @"", @"key": gKey ?: @""}];
    }
    NSMutableArray *facts = [NSMutableArray new];
    for (MMCardFact *f in spec.facts) [facts addObject:@{@"label": f.label ?: @"", @"value": f.value ?: @"", @"link": f.linkFindingID ?: @""}];
    return @{@"title": spec.title ?: @"", @"facts": facts, @"links": links};
}

/// What a link opens: the index of the focused row in the menu, and that row's card.
static NSDictionary *Open(NSString *expert, NSString *key, MMSnapshot *s, BOOL oneIcon, NSMutableArray<NSMenu *> *keep) {
    NSMenu *m = MMLinkMenu(expert, key, s, oneIcon, nil);
    if (!m) return @{@"error": @"no menu"};
    [keep addObject:m];
    NSMenuItem *row = MMFocusedRow(m);
    NSInteger at = row ? [m indexOfItem:row] : -1;
    // The first section title, which in One Icon mode names the linked expert's part.
    NSString *first = @"";
    for (NSMenuItem *i in m.itemArray) if (i.isSectionHeader) { first = i.title; break; }
    MMCardSpec *card = nil;
    MMFinding *f = [s finding:key];
    id<MMExpert> e = MMExpertNamed(expert);
    if (f && e) card = [e cardFor:f snapshot:s];
    NSInteger cardItems = 0;
    for (NSMenuItem *i in row.submenu.itemArray) if (i.view) cardItems++;
    return @{@"focusedAt": @(at), @"firstSection": first, @"rowHasCard": cardItems == 1 ? @YES : @NO, @"menuProblems": MMMenuProblems(m),
             @"card": card ? Click(card, keep) : @{}};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child is this same binary
        if (argc < 4) { fprintf(stderr, "usage: links <worktree> <port> <render folder>\n"); return 2; }
        [NSApplication sharedApplication];
        MMRegisterExpert(MMLocoHost.shared);
        MMRegisterExpert(MMWorkForestExpert.shared);
        MMLHInCLI = YES;
        MMSetLinkOpener(^(NSString *expert, NSString *key) { gExpert = expert; gKey = key; });
        NSString *tree = @(argv[1]), *out = @(argv[3]);
        NSInteger port = atoi(argv[2]);
        MMSnapshot *s = MMCLISettledSnapshot(NO);
        // What the graph queue prepares for each snapshot in the app: the menus and cards read it on main, and main
        // builds no Wrap Up plan and resolves no server folder.
        dispatch_semaphore_t prepared = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [s prepareFor:MMExperts()]; dispatch_semaphore_signal(prepared); });
        dispatch_semaphore_wait(prepared, DISPATCH_TIME_FOREVER);
        NSMutableArray<NSMenu *> *keep = [NSMutableArray new];
        NSMutableDictionary *r = [NSMutableDictionary new];

        MMFinding *server = nil, *wt = nil;
        for (MMFinding *f in [s findingsFor:@"locohost"]) if ([f.facts[@"ports"] containsObject:@(port)]) server = f;
        for (MMFinding *f in [s findingsFor:@"workforest"]) if ([f.path.lastPathComponent isEqualToString:tree.lastPathComponent]) wt = f;
        r[@"server"] = server.findingID ?: @""; r[@"worktree"] = wt.findingID ?: @"";
        if (!server || !wt) { printf("%s\n", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:r options:0 error:nil] encoding:NSUTF8StringEncoding].UTF8String); return 1; }

        // From LocoHost's side: the server's card, its Worktree link, and what the link opens.
        MMCardSpec *lc = [MMLocoHost.shared cardFor:server snapshot:s];
        NSDictionary *fromServer = Click(lc, keep);
        r[@"serverCard"] = fromServer;
        NSDictionary *l = [fromServer[@"links"] firstObject];
        if (l) {
            r[@"serverOpens"] = Open(l[@"expert"], l[@"key"], s, NO, keep);
            r[@"serverOpensOneIcon"] = Open(l[@"expert"], l[@"key"], s, YES, keep);
        }
        // From WorkForest's side: the worktree's card, a link per server inside, and what each opens.
        MMCardSpec *wc = [MMWorkForestExpert.shared cardFor:wt snapshot:s];
        NSDictionary *fromTree = Click(wc, keep);
        r[@"treeCard"] = fromTree;
        NSMutableArray *opens = [NSMutableArray new];
        for (NSDictionary *x in fromTree[@"links"]) [opens addObject:Open(x[@"expert"], x[@"key"], s, NO, keep)];
        r[@"treeOpens"] = opens;

        // Both cards, rendered as the kit draws them, in every appearance.
        NSMutableArray *pngs = [NSMutableArray new], *problems = [NSMutableArray new];
        NSDictionary *cards = @{@"server": lc, @"worktree": wc};
        for (NSString *name in cards) {
            MMCard *c = MMCardFromSpec(cards[name]);
            for (NSString *p in [c layoutProblems]) [problems addObject:[NSString stringWithFormat:@"%@: %@", name, p]];
            NSDictionary *aps = MMRenderAppearances();
            for (NSString *mode in aps) {
                NSString *path = [out stringByAppendingFormat:@"/links-card-%@-%@.png", name, mode];
                NSArray *cut = MMRenderMenu([MMCardFromSpec(cards[name]) menu], path, aps[mode]);
                if (cut) [pngs addObject:path.lastPathComponent];
                for (NSString *x in cut) [problems addObject:[NSString stringWithFormat:@"%@ %@: cut %@", name, mode, x]];
            }
        }
        r[@"pngs"] = pngs; r[@"cardProblems"] = problems;
        NSData *d = [NSJSONSerialization dataWithJSONObject:MMJSONSafe(r) options:NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
}
