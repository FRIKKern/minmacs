#import "MMSpecKit.h"
#import "MMMenuKit.h"

/// Runs an action spec's block. A menu item holds its target weakly, so the item's representedObject keeps it alive.
@interface MMSpecTrampoline : NSObject
@property (copy) void (^run)(BOOL option);
@property BOOL option;
- (void)fire:(id)sender;
@end

@implementation MMSpecTrampoline
- (void)fire:(id)sender { if (self.run) self.run(self.option); }
@end

static NSMenuItem *Wired(NSMenuItem *i, MMActionSpec *spec, BOOL option) {
    MMSpecTrampoline *t = [MMSpecTrampoline new];
    t.run = spec.run; t.option = option;
    i.target = t; i.action = @selector(fire:); i.representedObject = t;
    return i;
}

NSMenuItem *MMItemForAction(MMActionSpec *spec) {
    if (spec.disabledReason.length) return MMDimmedItem(spec.title ?: @"", spec.disabledReason);
    return Wired(MMActionItem(spec.title ?: @"", spec.tail, nil, nil), spec, NO);
}

/// The item and, when the spec has one, its Option alternate right after it.
static NSArray<NSMenuItem *> *ItemsForAction(MMActionSpec *spec) {
    NSMenuItem *i = MMItemForAction(spec);
    if (!spec.optionTitle.length || spec.disabledReason.length) return @[i];
    return @[i, Wired(MMAlternateItem(spec.optionTitle, nil, nil, nil), spec, YES)];
}

MMCard *MMCardForSpec(MMCardSpec *spec) {
    MMCard *c = [MMCard new];
    c.title = spec.title; c.statusWord = spec.statusWord; c.statusText = spec.statusText;
    c.mark = (MMMark)spec.mark;
    c.noteBy = spec.noteBy; c.note = spec.note;
    for (MMCardFact *f in spec.facts) {
        if (f.linkExpert.length) [c link:f.label value:f.value expert:f.linkExpert key:f.linkFindingID];
        else [c fact:f.label value:f.value];
    }
    for (MMActionSpec *a in spec.actions) for (NSMenuItem *i in ItemsForAction(a)) [c action:i];
    return c;
}

static NSMenuItem *RowItem(MMRowSpec *row, MMCardSpec *(^card)(NSString *)) {
    NSString *name = row.name ?: @"", *tag = nil;
    NSRange tab = [name rangeOfString:@"\t" options:NSBackwardsSearch];
    if (tab.location != NSNotFound) { tag = [name substringFromIndex:tab.location + 1]; name = [name substringToIndex:tab.location]; }
    NSMenuItem *i = MMRowItem(name, tag, row.facts ?: @[], (MMMark)row.mark);
    MMCardSpec *spec = card && row.findingID ? card(row.findingID) : nil;
    if (spec) i.submenu = [MMCardForSpec(spec) menu];
    return i;
}

NSMenu *MMMenuForSpec(MMMenuSpec *spec, MMCardSpec *(^card)(NSString *findingID), id footerTarget) {
    NSMenu *m = [NSMenu new];
    [m addItem:MMHeaderItem(spec.headerBig ?: @"", spec.headerUnit ?: @"", nil, spec.headerLine ?: @"")];
    [m addItem:NSMenuItem.separatorItem];
    if (spec.summary.length) {
        [m addItem:MMTextItem(spec.summary, MMMaxSummaryLines)];
        [m addItem:NSMenuItem.separatorItem];
    }
    NSUInteger shown = 0;
    for (MMActionSpec *a in spec.actions) {
        if (shown++ >= MMMaxMenuActions) break;
        for (NSMenuItem *i in ItemsForAction(a)) [m addItem:i];
    }
    NSUInteger sections = 0;
    for (MMSectionSpec *s in spec.sections) {
        if (!s.rows.count || sections >= MMMaxSections) continue;
        sections++;
        NSMutableArray *rows = [NSMutableArray new];
        for (MMRowSpec *r in s.rows) [rows addObject:RowItem(r, card)];
        MMAddSection(m, s.title ?: @"", rows);
    }
    if (spec.more.count) {
        [m addItem:NSMenuItem.separatorItem];
        NSMutableArray *more = [NSMutableArray new];
        for (MMActionSpec *a in spec.more) [more addObjectsFromArray:ItemsForAction(a)];
        [m addItem:MMMoreItem(more)];
    }
    MMAddFooter(m, footerTarget);
    MMRemoveSymbols(m);
    return m;
}
