// The Worktrees group by project, as the owner asked: with more than one project, each project shows its most
// active worktree first when the room runs out. MMWindowList.m lays the side out and draws it, and asks this file how
// a group with projects can show: its plans, each a number of rows a project, the order its rows are drawn in, the
// sub-headers and the lines that say how many rows wait. DESIGN.md, the menu window, rule 15.
#import "UI/Window/MMWindowListParts.h"

@implementation MMWindowListView (Projects)

// A plan is an NSData: for each project, how many of its rows show at the group's top, its most active ones, then a
// BOOL that says whether the rows that wait are told in one line at the group's foot, not under each project.

- (MMWindowRow *)drawn:(NSInteger)r in:(NSInteger)i { return _groups[i].rows[_order[i][r].unsignedIntegerValue]; }

- (NSString *)nameOf:(MMWindowRow *)row in:(MMWindowGroup *)g {
    return g.grouped && row.nameInProject.length ? row.nameInProject : row.shownName;
}

/// How high a row of a group is: `row` points, and a name that wraps adds a line for each line more.
- (CGFloat)heightOf:(MMWindowRow *)r in:(MMWindowGroup *)g hasHour:(BOOL)hasHour row:(CGFloat)row {
    // Every name is measured with the real font. The widths are kept, so a model that brings the same names costs little.
    NSInteger lines = (NSInteger)MMWindowRowNameAs(r, [self nameOf:r in:g], g.side, hasHour, NSMakeRect(5, 0, self.bounds.size.width - 10, row), NULL).count;
    return row + MMWindowNameLine * (lines - 1);
}

NSArray<NSArray<NSNumber *> *> *MMWindowListProjectsOf(MMWindowGroup *g) {
    NSMutableArray<NSArray<NSNumber *> *> *out = [NSMutableArray new];
    for (NSString *p in MMWindowProjectsOf(g.rows)) {
        NSMutableArray<NSNumber *> *rows = [NSMutableArray new];
        for (NSUInteger r = 0; r < g.rows.count; r++) if ([(g.rows[r].project ?: @"") isEqualToString:p]) [rows addObject:@(r)];
        [out addObject:rows];
    }
    return out;
}

/// The ways a group with projects can show, smallest first, each one row more than the one before, as the heights of
/// their tops in `heights`. First the most active projects alone, each with its first row, and one line at the foot
/// for the rest. Then every project with its first row, and the line at the foot. Then the same with a line under each
/// project whose rows wait, and from there one row more each time, the most active row that waits, until all show.
- (NSArray<NSData *> *)plansOf:(MMWindowGroup *)g projects:(NSArray<NSArray<NSNumber *> *> *)projects heights:(NSArray<NSNumber *> *)rowH out:(NSMutableArray<NSNumber *> *)heights {
    NSInteger n = (NSInteger)projects.count;
    NSMutableArray<NSData *> *plans = [NSMutableArray new];
    CGFloat (^height)(const NSInteger *, BOOL) = ^CGFloat(const NSInteger *shown, BOOL foot) {
        CGFloat h = 0;
        NSInteger waiting = 0, told = 0;
        for (NSInteger p = 0; p < n; p++) {
            if (shown[p] > 0) h += MMListSub;
            for (NSInteger k = 0; k < shown[p]; k++) h += rowH[projects[p][k].unsignedIntegerValue].doubleValue;
            if (shown[p] < (NSInteger)projects[p].count) { waiting++; if (shown[p] > 0) told++; }
        }
        return h + (foot ? (waiting ? MMListMore : 0) : MMListMore * told);
    };
    void (^add)(const NSInteger *, BOOL) = ^(const NSInteger *shown, BOOL foot) {
        CGFloat h = height(shown, foot);
        // A plan no higher than the one before it takes that one's place: it shows more, or tells it under each project.
        while (heights.count && heights.lastObject.doubleValue >= h - 0.5) { [heights removeLastObject]; [plans removeLastObject]; }
        NSMutableData *d = [NSMutableData dataWithBytes:shown length:sizeof(NSInteger) * (NSUInteger)n];
        [d appendBytes:&foot length:sizeof foot];
        [plans addObject:d]; [heights addObject:@(h)];
    };
    NSInteger *shown = calloc((size_t)n, sizeof(NSInteger));
    for (NSInteger q = 1; q <= n; q++) { shown[q - 1] = 1; add(shown, YES); }
    for (;;) {
        add(shown, NO);
        // The most active row that waits, of any project: each project's rows wait in their own order.
        NSInteger best = -1;
        for (NSInteger p = 0; p < n; p++) {
            if (shown[p] >= (NSInteger)projects[p].count) continue;
            MMWindowRow *next = g.rows[projects[p][shown[p]].unsignedIntegerValue];
            if (best < 0 || MMWindowActivityOrder(next, g.rows[projects[best][shown[best]].unsignedIntegerValue]) == NSOrderedAscending) best = p;
        }
        if (best < 0) break;
        shown[best]++;
    }
    free(shown);
    return plans;
}

/// Lays a group's rows out as drawn: the order, the sub-headers, the lines under projects and where each row starts.
/// A group with projects shows the plan `plan`, and under it the rows that wait, each project under its sub-header again.
- (void)arrange:(NSInteger)i plan:(NSData *)plan projects:(NSArray<NSArray<NSNumber *> *> *)projects heights:(NSArray<NSNumber *> *)rowH {
    MMWindowGroup *g = _groups[i];
    NSMutableArray<NSNumber *> *order = [NSMutableArray new], *leads = [NSMutableArray new];
    NSMutableArray *trails = [NSMutableArray new];
    if (!plan) {
        for (NSUInteger r = 0; r < g.rows.count; r++) { [order addObject:@(r)]; [leads addObject:@0]; [trails addObject:NSNull.null]; }
    } else {
        NSInteger n = (NSInteger)projects.count, waiting = 0, waitingProjects = 0, lastWaiting = -1;
        const NSInteger *shown = plan.bytes;
        BOOL foot = *(const BOOL *)((const char *)plan.bytes + sizeof(NSInteger) * (NSUInteger)n);
        for (NSInteger p = 0; p < n; p++) {
            NSInteger hidden = (NSInteger)projects[p].count - shown[p];
            if (hidden > 0) { waiting += hidden; waitingProjects++; lastWaiting = p; }
        }
        for (NSInteger p = 0; p < n; p++) for (NSInteger k = 0; k < shown[p]; k++) {
            NSInteger hidden = (NSInteger)projects[p].count - shown[p];
            [order addObject:projects[p][k]]; [leads addObject:@(k == 0 ? MMListSub : 0)];
            NSString *name = g.rows[projects[p][0].unsignedIntegerValue].project;
            [trails addObject:!foot && k + 1 == shown[p] && hidden > 0 ? MMWindowProjectMoreLine(hidden, name) : NSNull.null];
        }
        // One line at the foot: the project it is about, or how many projects.
        if (foot && waiting > 0 && trails.count) {
            NSString *only = g.rows[projects[lastWaiting][0].unsignedIntegerValue].project;
            trails[trails.count - 1] = waitingProjects == 1 ? MMWindowProjectMoreLine(waiting, only) : MMWindowProjectsMoreLine(waiting, waitingProjects);
        }
        for (NSInteger p = 0; p < n; p++) for (NSInteger k = shown[p]; k < (NSInteger)projects[p].count; k++) {
            [order addObject:projects[p][k]]; [leads addObject:@(k == shown[p] ? MMListSub : 0)]; [trails addObject:NSNull.null];
        }
    }
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithCapacity:order.count + 1];
    CGFloat y = 0;
    for (NSUInteger d = 0; d < order.count; d++) {
        [tops addObject:@(y)];
        y += leads[d].doubleValue + rowH[order[d].unsignedIntegerValue].doubleValue + (trails[d] == NSNull.null ? 0 : MMListMore);
    }
    [tops addObject:@(y)];
    _order[i] = order; _leads[i] = leads; _trails[i] = trails; _tops[i] = tops;
}

/// Where a row is drawn in its group, counted as drawn, or -1.
- (NSInteger)drawnIndexOf:(NSString *)key in:(NSInteger)i {
    NSArray<NSNumber *> *order = _order[i];
    for (NSUInteger d = 0; d < order.count; d++) if ([[self drawn:(NSInteger)d in:i].key isEqualToString:key]) return (NSInteger)d;
    return -1;
}
/// A project's sub-header in a group with projects: its name and how many worktrees it has, in the quiet type of a
/// group's header, a step smaller, so it reads as part of the group.
- (void)drawProjectOf:(MMWindowRow *)row in:(MMWindowGroup *)g top:(CGFloat)top {
    NSInteger count = 0;
    for (MMWindowRow *r in g.rows) if ([(r.project ?: @"") isEqualToString:row.project ?: @""]) count++;
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSAttributedString *head = MMWindowJoin(@[MMWindowText(row.project ?: MMWindowNoProject, 11, NSFontWeightMedium, t2),
                                              MMWindowText([NSString stringWithFormat:@"   %ld", (long)count], 11, NSFontWeightRegular, t3)]);
    MMWindowDraw(head, 14, top + MMListSub / 2 + 2, -1);
}

@end

@implementation MMWindowListView (ProjectChecks)

- (NSArray<NSString *> *)listNames {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowGroup *g in _groups) for (MMWindowRow *row in g.rows) [out addObject:[self nameOf:row in:g]];
    return out;
}

- (NSArray<NSString *> *)drawnOrder:(NSInteger)i {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger r = 0; i < (NSInteger)_order.count && r < (NSInteger)_order[i].count; r++) [out addObject:[self drawn:r in:i].key];
    return out;
}

- (NSArray<NSString *> *)shownKeys:(NSInteger)i {
    NSMutableArray *out = [NSMutableArray new];
    NSRange shown = [self shown:i moving:[_scrolling isEqualToString:_groups[i].key]];
    for (NSUInteger r = shown.location; r < NSMaxRange(shown); r++) [out addObject:[self drawn:(NSInteger)r in:i].key];
    return out;
}

- (NSArray<NSString *> *)moreLines:(NSInteger)i {
    NSMutableArray *out = [NSMutableArray new];
    NSRange shown = [self shown:i moving:[_scrolling isEqualToString:_groups[i].key]];
    for (NSUInteger r = shown.location; r < NSMaxRange(shown); r++) if (_trails[i][r] != NSNull.null) [out addObject:_trails[i][r]];
    return out;
}

- (NSArray<NSNumber *> *)steps:(NSInteger)i { return _steps[i]; }

@end
