// Noo-Noo's menu and cards, to docs/DESIGN.md: a header of what deleting frees, one summary, two actions,
// four sections of at most six rows, and cards that say why an item stays or how it goes and comes back.
#import "Experts/NooNoo/MMNNMenu.h"
#import "UI/MMFormat.h"

@implementation MMNNRow
@end
@implementation MMNNHandlers
@end
@implementation MMNNView
@end

static NSString *SectionTitle(MMNNSection s) {
    switch (s) {
        case MMNNFinished: return @"Finished projects";
        case MMNNLeftovers: return @"Leftovers";
        case MMNNCaches: return @"Caches and build output";
        case MMNNKept: return @"Kept";
    }
    return @"Kept";
}

/// A row title inside a sentence, after "The": "simulator devices", but "Go build cache" and "pnpm store" as they are.
static NSString *InSentence(NSString *title) {
    NSString *first = [title componentsSeparatedByString:@" "].firstObject;
    NSSet *common = [NSSet setWithArray:@[@"Agent", @"Build", @"Device", @"Old", @"Simulator", @"Temp", @"Trash"]];
    if (![common containsObject:first]) return title;
    return [[title substringToIndex:1].lowercaseString stringByAppendingString:[title substringFromIndex:1]];
}

static BOOL Actable(MMNNRow *r) { return r.actionTitle.length && !r.live && !r.kept; }

/// What deleting frees, and du's figure beside it only when it says much more. DESIGN.md: a size is what deleting frees.
static NSString *SizeWords(MMNNRow *r) {
    if (r.allocated > r.freed * 2 && r.allocated - r.freed > (64ull << 20))
        return [NSString stringWithFormat:@"%@ freed, %@ on disk", MMBytes(r.freed), MMBytes(r.allocated)];
    return MMBytes(r.freed);
}

static NSString *StateFact(MMNNRow *r) {
    if (r.live && [r.why hasPrefix:@"it was written"] && r.lastUsed) return [@"used " stringByAppendingString:MMAgo(r.lastUsed)];
    if (r.live) return @"in use";
    if (r.kept) return r.ownerSetting.length ? @"its owner keeps it" : @"kept";
    if (r.ownerState.length) return r.ownerState;
    return r.lastUsed ? [@"used " stringByAppendingString:MMAgo(r.lastUsed)] : nil;
}

static MMRowMark MarkOf(MMNNRow *r) {
    if (r.live && [r.why hasPrefix:@"it was written"]) return MMRowMarkRecent;   // new, not in use
    if (r.live) return MMRowMarkWorking;
    if (r.kept) return MMRowMarkQuiet;
    if (r.goesOnItsOwn) return MMRowMarkGoes;
    return r.section == MMNNFinished || r.section == MMNNLeftovers ? MMRowMarkGoes : MMRowMarkQuiet;
}

static NSArray<MMNNRow *> *RowsIn(MMNNView *v, MMNNSection s) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMNNRow *r in v.rows) if (r.section == s) [out addObject:r];
    return out;
}

static uint64_t FreedOf(NSArray<MMNNRow *> *rows) {
    uint64_t n = 0;
    for (MMNNRow *r in rows) if (Actable(r)) n += r.freed;
    return n;
}

static NSArray<NSString *> *IDsOf(NSArray<MMNNRow *> *rows) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMNNRow *r in rows) if (Actable(r) && r.findingID) [out addObject:r.findingID];
    return out;
}

static NSInteger OwnersOf(NSArray<MMNNRow *> *rows) {
    NSMutableSet *s = [NSMutableSet new];
    for (MMNNRow *r in rows) if (Actable(r)) [s addObject:r.owner ?: r.path ?: @""];
    return (NSInteger)s.count;
}

NSString *MMNNGrowthLine(NSString *title, BOOL ok, double bytesPerDay, NSInteger windowDays, double firstBytes,
                         double lastBytes, double weekRatio, double minBytes) {
    if (!ok || windowDays < 2 || !title.length) return nil;
    double grew = lastBytes - firstBytes;
    if (grew < minBytes || bytesPerDay <= 0) return nil;
    if (weekRatio < 2 && bytesPerDay * 7 < minBytes) return nil;
    return [NSString stringWithFormat:@"The %@ grew %@ in %ld days.", InSentence(title), MMBytes((uint64_t)grew), (long)windowDays];
}

MMMenuSpec *MMNNMenuFor(MMNNView *v, MMNNHandlers *h) {
    MMMenuSpec *m = [MMMenuSpec new];
    NSArray *finished = RowsIn(v, MMNNFinished), *left = RowsIn(v, MMNNLeftovers), *caches = RowsIn(v, MMNNCaches), *kept = RowsIn(v, MMNNKept);
    uint64_t all = FreedOf(v.rows);
    m.headerBig = MMBytes(all);
    m.headerUnit = @"to free";
    // The header's second line in order of what matters, each part only while the line still fits the kit's width.
    NSMutableArray *parts = [NSMutableArray new];
    NSInteger projects = OwnersOf(finished);
    if (projects) [parts addObject:MMPlural(projects, @"finished project")];
    else [parts addObject:MMPlural((NSInteger)v.rows.count, @"item")];
    if (v.trashBytes) [parts addObject:[NSString stringWithFormat:@"Trash holds %@", MMBytes(v.trashBytes)]];
    if (v.modeName.length) [parts addObject:v.modeName];
    if (projects && IDsOf(left).count) [parts addObject:MMPlural((NSInteger)IDsOf(left).count, @"leftover")];
    NSMutableArray *line = [NSMutableArray new];
    for (NSString *p in parts) {
        NSString *next = [[line arrayByAddingObject:p] componentsJoinedByString:@" · "];
        if (line.count && next.length > 52) continue;
        [line addObject:p];
    }
    m.headerLine = [line componentsJoinedByString:@" · "];

    NSMutableArray *summary = [NSMutableArray new];
    if (v.growthLine.length) [summary addObject:v.growthLine];
    if (v.watchingLeft > 0)
        [summary addObject:[NSString stringWithFormat:@"Watching %@. Acts on nothing until %@.", MMPlural((NSInteger)v.rows.count, @"item"),
                            v.watchingLeft > 12 * 3600 ? @"tomorrow" : [@"in " stringByAppendingString:MMShortDuration(v.watchingLeft)]]];
    else if (finished.count)
        [summary addObject:@"Build output of merged worktrees goes first. It goes to the Trash, and Undo brings it back."];
    else if (!v.rows.count) [summary addObject:@"Nothing to clean. Noo-Noo looks again on its own."];
    m.summary = [summary componentsJoinedByString:@" "];

    NSMutableArray *actions = [NSMutableArray new];
    NSArray *fids = IDsOf(finished), *lids = IDsOf(left);
    if (fids.count)
        [actions addObject:[MMActionSpec title:@"Clean Finished Projects" tail:[NSString stringWithFormat:@"%@, %@", MMPlural((NSInteger)fids.count, @"item"), MMBytes(FreedOf(finished))]
                                           run:^(BOOL option) { if (h.clean) h.clean(fids); }]];
    if (lids.count)
        [actions addObject:[MMActionSpec title:@"Clean Leftovers" tail:[NSString stringWithFormat:@"%@, %@", MMPlural((NSInteger)lids.count, @"item"), MMBytes(FreedOf(left))]
                                           run:^(BOOL option) { if (h.clean) h.clean(lids); }]];
    m.actions = [actions subarrayWithRange:NSMakeRange(0, MIN(2, actions.count))];

    NSMutableArray *sections = [NSMutableArray new];
    for (NSArray *rows in @[finished, left, caches, kept]) {
        if (!rows.count) continue;
        NSMutableArray *specs = [NSMutableArray new];
        for (MMNNRow *r in rows) {
            MMRowSpec *s = [MMRowSpec new];
            s.name = r.name; s.findingID = r.findingID; s.mark = MarkOf(r);
            NSMutableArray *facts = [NSMutableArray new];
            if (r.owner.length) [facts addObject:r.owner];
            [facts addObject:MMBytes(r.freed)];
            NSString *st = StateFact(r);
            if (st.length) [facts addObject:st];
            s.facts = facts;
            [specs addObject:s];
        }
        MMSectionSpec *sec = [MMSectionSpec new];
        sec.title = SectionTitle(((MMNNRow *)rows.firstObject).section); sec.rows = specs;
        [sections addObject:sec];
    }
    m.sections = sections;

    NSMutableArray *more = [NSMutableArray new];
    if (v.restorable > 0)
        [more addObject:[MMActionSpec title:@"Undo Last Clean" tail:v.lastClean ? MMAgo(v.lastClean) : nil run:^(BOOL option) { if (h.restoreLast) h.restoreLast(); }]];
    [more addObject:[MMActionSpec title:@"Scan Now" tail:v.lastScan ? MMAgo(v.lastScan) : nil run:^(BOOL option) { if (h.scanNow) h.scanNow(); }]];
    m.more = more;
    return m;
}

MMCardSpec *MMNNCardFor(MMNNRow *r, MMNNView *v, MMNNHandlers *h) {
    if (!r) return nil;
    MMCardSpec *c = [MMCardSpec new];
    // The kit capitalizes a card title, so it starts with "The" and a name such as node_modules keeps its case.
    if (r.folder && r.owner.length) c.title = [NSString stringWithFormat:@"The %@ folder in %@", r.name, r.owner];
    else if (r.owner.length) c.title = [NSString stringWithFormat:@"The %@ of %@", InSentence(r.name), r.owner];
    else c.title = [@"The " stringByAppendingString:InSentence(r.name)];
    c.mark = MarkOf(r);
    if (r.live) {
        c.statusWord = @"Stays.";
        c.statusText = [MMSentence(r.why ?: @"it is in use") stringByAppendingString:@" Noo-Noo looks again at the next scan."];
    } else if (r.kept) {
        c.statusWord = @"Stays.";
        c.statusText = MMSentence(r.ownerSetting ?: r.why ?: @"its row only reports it");
    } else if (r.goesOnItsOwn) {
        c.statusWord = @"Goes at the next review.";
        c.statusText = [NSString stringWithFormat:@"%@ %@", MMSentence(r.ownerState.length ? [@"its project is " stringByAppendingString:r.ownerState] : r.why ?: @"nothing uses it"),
                        r.undoWords ?: @""];
    } else {
        c.statusWord = @"Can go.";
        NSString *why = r.ownerState.length ? [@"its project is " stringByAppendingString:r.ownerState] : r.why;
        c.statusText = [NSString stringWithFormat:@"%@%@", why.length ? [MMSentence(why) stringByAppendingString:@" "] : @"", r.undoWords ?: @""];
    }
    NSMutableArray *facts = [NSMutableArray new];
    // The owner as a fact only when it adds its state or a link, since the title already names it.
    if (r.owner.length && (r.ownerState.length || r.ownerLinkExpert.length)) {
        // The status already says the owner's state, so the fact names the owner and links to it.
        MMCardFact *o = [MMCardFact label:@"Owner" value:r.ownerState.length && r.live ? [NSString stringWithFormat:@"%@, %@", r.owner, r.ownerState] : r.owner];
        o.linkExpert = r.ownerLinkExpert; o.linkFindingID = r.ownerLinkID;
        [facts addObject:o];
    }
    [facts addObject:[MMCardFact label:@"Size" value:SizeWords(r)]];
    if (r.members > 1) [facts addObject:[MMCardFact label:@"Holds" value:MMPlural(r.members, @"folder")]];
    if (r.lastUsed) [facts addObject:[MMCardFact label:@"Last used" value:MMAgo(r.lastUsed)]];
    // The first clause only, so the value fits one line: "Pruned packages download again", not the whole row text.
    NSString *rebuild = [[r.rebuild componentsSeparatedByString:@","].firstObject componentsSeparatedByString:@";"].firstObject;
    if (rebuild.length && !r.kept && ![rebuild.lowercaseString hasPrefix:@"none"]) [facts addObject:[MMCardFact label:@"Rebuild" value:rebuild]];
    // The folder only when it fits the card's value column whole, since a path cut in the middle says nothing.
    if (r.path.length && r.path.length <= 34 && facts.count < 5) [facts addObject:[MMCardFact label:@"Where" value:r.path]];
    c.facts = [facts subarrayWithRange:NSMakeRange(0, MIN(5, facts.count))];

    NSMutableArray *actions = [NSMutableArray new];
    NSString *fid = r.findingID;
    if (r.actionTitle.length && !r.kept) {
        MMActionSpec *a = [MMActionSpec title:r.actionTitle tail:MMBytes(r.freed) run:^(BOOL option) { if (h.clean && fid) h.clean(@[fid]); }];
        if (r.live) { a.tail = nil; a.disabledReason = r.why ?: @"it is in use"; }
        [actions addObject:a];
    }
    if (!r.kept && fid) [actions addObject:[MMActionSpec title:@"Keep for a Week" tail:nil run:^(BOOL option) { if (h.keep) h.keep(fid); }]];
    if (fid) [actions addObject:[MMActionSpec title:@"Show in Finder" tail:nil run:^(BOOL option) { if (h.reveal) h.reveal(fid); }]];
    c.actions = actions;
    return c;
}

NSString *MMNNAccessibility(MMNNView *v) {
    NSArray *finished = RowsIn(v, MMNNFinished);
    NSInteger projects = OwnersOf(finished);
    uint64_t all = FreedOf(v.rows);
    if (projects) return [NSString stringWithFormat:@"%@, %@ to free", MMPlural(projects, @"finished project"), MMBytes(all)];
    return [NSString stringWithFormat:@"%@ to free", MMBytes(all)];
}
