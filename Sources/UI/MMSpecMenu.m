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

static NSMenuItem *RowFrom(MMRowSpec *r, MMCardProvider cards) {
    NSMenuItem *i = MMRowItem(r.name ?: @"", nil, r.facts, (MMMark)r.mark);
    MMCardSpec *card = r.findingID.length && cards ? cards(r.findingID) : nil;
    if (card) i.submenu = [MMCardFromSpec(card) menu];
    return i;
}

NSMenu *MMMenuFromSpec(MMMenuSpec *spec, MMCardProvider cards, NSString *notice, id footerTarget) {
    NSMenu *m = [NSMenu new];
    m.autoenablesItems = NO;
    [m addItem:MMHeaderItem(spec.headerBig ?: @"", spec.headerUnit, nil, spec.headerLine)];
    [m addItem:NSMenuItem.separatorItem];
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
        for (MMRowSpec *r in s.rows) [rows addObject:RowFrom(r, cards)];
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

NSMenu *MMOneIconMenu(NSArray<MMOneIconPart *> *parts, NSString *notice, id footerTarget) {
    NSMenu *m = [NSMenu new];
    m.autoenablesItems = NO;
    if (notice.length) { [m addItem:MMTextItem(notice, 1)]; [m addItem:NSMenuItem.separatorItem]; }
    for (MMOneIconPart *p in parts) {
        [m addItem:MMSectionItem(p.name)];
        NSString *line = MMHeaderLine(p.spec);
        [m addItem:MMTextItem(line.length ? line : @"Nothing found yet.", 2)];   // two lines, so the header line is never cut
        NSUInteger shown = 0;
        for (MMSectionSpec *s in p.spec.sections) for (MMRowSpec *r in s.rows) {
            if (shown++ >= MMOneIconRows) break;
            [m addItem:RowFrom(r, p.cards)];
        }
    }
    MMAddFooter(m, footerTarget);
    MMRemoveSymbols(m);
    return m;
}
