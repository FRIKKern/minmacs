#import "MMSpecMenu.h"
#import "Core/MMExpert.h"

const NSUInteger MMOneIconRows = 3;

/// Holds an action's block for the menu item that runs it. The item keeps it as its representedObject.
@interface MMSpecTarget : NSObject
@property (copy) void (^run)(BOOL option);
@property BOOL option;
- (void)fire:(id)sender;
@end
@implementation MMSpecTarget
- (void)fire:(id)sender { if (self.run) self.run(self.option); }
@end

static NSMenuItem *Bound(NSMenuItem *i, MMActionSpec *a, BOOL option) {
    MMSpecTarget *t = [MMSpecTarget new];
    t.run = a.run; t.option = option;
    i.target = t; i.representedObject = t;
    return i;
}

NSMenuItem *MMItemFromAction(MMActionSpec *a) {
    if (a.disabledReason.length) return MMDimmedItem(a.title ?: @"", a.disabledReason);
    return Bound(MMActionItem(a.title ?: @"", a.tail, @selector(fire:), nil), a, NO);
}

NSMenuItem *MMAlternateFromAction(MMActionSpec *a) {
    if (!a.optionTitle.length || a.disabledReason.length) return nil;
    return Bound(MMAlternateItem(a.optionTitle, nil, @selector(fire:), nil), a, YES);
}

static void AddAction(NSMutableArray *items, MMActionSpec *a) {
    [items addObject:MMItemFromAction(a)];
    NSMenuItem *alt = MMAlternateFromAction(a);
    if (alt) [items addObject:alt];
}

MMCard *MMCardFromSpec(MMCardSpec *spec) {
    MMCard *c = [MMCard new];
    c.title = spec.title; c.statusWord = spec.statusWord; c.statusText = spec.statusText;
    c.mark = (MMMark)spec.mark; c.noteBy = spec.noteBy; c.note = spec.note;
    for (MMCardFact *f in spec.facts) {
        if (f.linkExpert.length) [c link:f.label value:f.value expert:f.linkExpert key:f.linkFindingID];
        else [c fact:f.label value:f.value];
    }
    // The card shows the first four actions and puts the rest under More. An alternate does not count.
    NSMutableArray *items = [NSMutableArray new];
    for (MMActionSpec *a in spec.actions) AddAction(items, a);
    for (NSMenuItem *i in items) [c action:i];
    return c;
}

/// A row spec as a kit row. A name may carry its tag after a tab, such as "checkout-flow\t:3000". The kit cuts the
/// name at the tail and never the tag. cards nil draws the row without its card.
static NSMenuItem *RowFrom(MMRowSpec *r, MMCardProvider cards) {
    NSString *name = r.name ?: @"", *tag = nil;
    NSRange tab = [name rangeOfString:@"\t" options:NSBackwardsSearch];
    if (tab.location != NSNotFound) { tag = [name substringFromIndex:tab.location + 1]; name = [name substringToIndex:tab.location]; }
    NSMenuItem *i = MMRowItem(name, tag, r.facts ?: @[], (MMMark)r.mark);
    MMCardSpec *card = r.findingID.length && cards ? cards(r.findingID) : nil;
    if (card) i.submenu = [MMCardFromSpec(card) menu];
    return i;
}

static NSString *const kFocusedTag = @"minmacs.focused";

NSMenuItem *MMFocusedRow(NSMenu *menu) {
    for (NSMenuItem *i in menu.itemArray) if ([i.identifier isEqualToString:kFocusedTag]) return i;
    return nil;
}

/// The row of focusID with its card, or nil when the finding has no card. A finding with no row in the spec gets
/// a row named by its card's title.
static NSMenuItem *FocusRow(MMMenuSpec *spec, MMCardProvider cards, NSString *focusID, id *found) {
    *found = nil;
    if (!focusID.length || !cards) return nil;
    for (MMSectionSpec *s in spec.sections) for (MMRowSpec *r in s.rows) if ([r.findingID isEqualToString:focusID]) { *found = r; break; }
    NSMenuItem *i = nil;
    if (*found) i = RowFrom(*found, cards);
    else {
        MMCardSpec *card = cards(focusID);
        if (card) { i = MMRowItem(card.title ?: @"", nil, @[], (MMMark)card.mark); i.submenu = [MMCardFromSpec(card) menu]; }
    }
    if (!i.submenu) return nil;
    i.identifier = kFocusedTag;
    return i;
}

NSMenu *MMMenuFromSpec(MMMenuSpec *spec, MMCardProvider cards, NSString *notice, id footerTarget) {
    return MMMenuFromSpecFocused(spec, cards, notice, footerTarget, nil);
}

NSMenu *MMMenuFromSpecFocused(MMMenuSpec *spec, MMCardProvider cards, NSString *notice, id footerTarget, NSString *focusID) {
    NSMenu *m = [NSMenu new];
    m.autoenablesItems = NO;
    [m addItem:MMHeaderItem(spec.headerBig ?: @"", spec.headerUnit, nil, spec.headerLine)];
    [m addItem:NSMenuItem.separatorItem];
    id focused = nil;
    NSMenuItem *focus = FocusRow(spec, cards, focusID, &focused);
    if (focus) { [m addItem:focus]; [m addItem:NSMenuItem.separatorItem]; }
    BOOL text = NO;
    if (spec.summary.length) { [m addItem:MMTextItem(spec.summary, MMMaxSummaryLines)]; text = YES; }
    if (notice.length) { [m addItem:MMTextItem(notice, 1)]; text = YES; }
    if (text) [m addItem:NSMenuItem.separatorItem];
    NSMutableArray *actions = [NSMutableArray new];
    NSUInteger n = 0;
    for (MMActionSpec *a in spec.actions) { if (n++ >= MMMaxMenuActions) break; AddAction(actions, a); }
    for (NSMenuItem *i in actions) [m addItem:i];
    NSUInteger sections = 0;
    for (MMSectionSpec *s in spec.sections) {
        if (sections >= MMMaxSections) break;
        NSMutableArray *rows = [NSMutableArray new];
        for (MMRowSpec *r in s.rows) if (!focus || r != focused) [rows addObject:RowFrom(r, cards)];
        if (!rows.count) continue;
        MMAddSection(m, s.title, rows);
        sections++;
    }
    if (spec.more.count) {
        NSMutableArray *more = [NSMutableArray new];
        for (MMActionSpec *a in spec.more) AddAction(more, a);
        [m addItem:NSMenuItem.separatorItem];
        [m addItem:MMMoreItem(more)];
    }
    MMAddFooter(m, footerTarget);
    MMRemoveSymbols(m);
    return m;
}

@implementation MMOneIconPart
@end

NSString *MMHeaderLine(MMMenuSpec *spec) {
    NSMutableArray *parts = [NSMutableArray new];
    NSString *big = [@[spec.headerBig ?: @"", spec.headerUnit ?: @""] componentsJoinedByString:@" "];
    big = [big stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (big.length) [parts addObject:big];
    if (spec.headerLine.length) [parts addObject:spec.headerLine];
    return [parts componentsJoinedByString:@" · "];
}

/// One expert's part of the One Icon menu: its name as a section title, its header line, then its top rows.
/// cards nil leaves the rows without cards, for a part under More, where a card would sit two levels deep.
static void AddPart(NSMenu *m, MMOneIconPart *p, MMCardProvider cards) {
    [m addItem:MMSectionItem(p.name)];
    NSString *line = MMHeaderLine(p.spec);
    [m addItem:MMTextItem(line.length ? line : @"Nothing found yet.", 2)];   // two lines, so the header line is never cut
    NSUInteger shown = 0;
    id focused = nil;
    NSMenuItem *focus = FocusRow(p.spec, cards, p.focusID, &focused);
    if (focus) { [m addItem:focus]; shown++; }
    for (MMSectionSpec *s in p.spec.sections) for (MMRowSpec *r in s.rows) {
        if (focus && r == focused) continue;
        if (shown++ >= MMOneIconRows) break;
        [m addItem:RowFrom(r, cards)];
    }
}

NSMenu *MMOneIconMenu(NSArray<MMOneIconPart *> *parts, NSString *notice, id footerTarget) {
    NSMenu *m = [NSMenu new];
    m.autoenablesItems = NO;
    if (notice.length) { [m addItem:MMTextItem(notice, 1)]; [m addItem:NSMenuItem.separatorItem]; }
    // DESIGN.md rule 3 allows four sections. The experts past the fourth go under More, each as its title, its header
    // line and its top rows, with no cards there, so no card is ever two levels deep.
    NSUInteger n = 0;
    NSMenu *more = nil;
    // A link opens the part it names first, so its card is the first row below that part's header line.
    NSMutableArray *ordered = [parts mutableCopy];
    for (MMOneIconPart *p in parts) if (p.focusID.length) { [ordered removeObject:p]; [ordered insertObject:p atIndex:0]; break; }
    for (MMOneIconPart *p in ordered) {
        if (n++ < MMMaxSections) { AddPart(m, p, p.cards); continue; }
        if (!more) { more = [NSMenu new]; more.autoenablesItems = NO; }
        AddPart(more, p, nil);
    }
    if (more) {
        NSMenuItem *i = MMMoreItem(@[]);
        i.submenu = more;
        [m addItem:NSMenuItem.separatorItem];
        [m addItem:i];
    }
    MMAddFooter(m, footerTarget);
    MMRemoveSymbols(m);
    return m;
}
