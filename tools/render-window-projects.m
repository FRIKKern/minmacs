// The Worktrees group by project. The owner asked: "We want Worktrees to be grouped by project - so when there are
// more than 1 project, it will show most active per project when vertical space is running out." These checks hold
// the list to it at every height a side can have, and to DESIGN's rules 8, 9 and 14: whole rows, no ellipsis, lines
// that say how many wait and add up, and a scrolled group that keeps its place. tools/render.m includes this file
// after render-window-polish.m, whose helpers it uses. It is not built on its own.

/// The number a "3 more in barkbot" line starts with.
static NSInteger ProjectsCount(NSString *line) { return [[line componentsSeparatedByString:@" "].firstObject integerValue]; }

/// What is wrong with the Worktrees group of a list at rest, or nil. `dropped` says whether a project shows none of its rows.
static NSString *ProjectsFault(MMWindowListView *l, NSString *where, BOOL *dropped, BOOL *foot) {
    MMWindowGroup *g = l.groups.firstObject;
    NSArray<NSString *> *shown = [l shownKeys:0], *lines = [l moreLines:0];
    CGFloat box = l.groupFrames.firstObject.rectValue.size.height - 24;
    // Whole rows: the box ends where a row ends, at one of the heights the group may take.
    if (![[l steps:0] containsObject:@(box)] || ![l.rowTops.firstObject containsObject:@(box)]) return [NSString stringWithFormat:@"%@: box %g ends on no row", where, box];
    // Honest lines: what they say waits is what does not show, and none is cut.
    NSInteger said = 0;
    for (NSString *line in lines) {
        said += ProjectsCount(line);
        if ([line containsString:@"…"] || [line containsString:@"..."]) return [NSString stringWithFormat:@"%@: %@", where, line];
    }
    if (said != (NSInteger)(g.rows.count - shown.count)) return [NSString stringWithFormat:@"%@: the lines say %ld wait, %lu do", where, (long)said, (unsigned long)(g.rows.count - shown.count)];
    for (NSString *name in l.drawnNames) if ([name containsString:@"…"] || [name containsString:@"..."]) return [NSString stringWithFormat:@"%@: %@", where, name];
    *foot = lines.count == 1 && [lines.firstObject containsString:@" projects"];
    // Each project shows its own rows from its most active down, and no row waits that is more active than a row that
    // shows beyond a project's first: the room left after the first rows goes to the most active.
    *dropped = NO;
    MMWindowRow *leastShown = nil, *mostWaiting = nil;
    for (NSString *p in MMWindowProjectsOf(g.rows)) {
        NSArray<MMWindowRow *> *rows = [g.rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMWindowRow *r, id b) { return [(r.project ?: @"") isEqualToString:p]; }]];
        NSUInteger k = 0;
        while (k < rows.count && [shown containsObject:rows[k].key]) k++;
        for (NSUInteger j = k; j < rows.count; j++) if ([shown containsObject:rows[j].key]) return [NSString stringWithFormat:@"%@: %@ shows %@ before a more active row", where, p, rows[j].key];
        if (k == 0) *dropped = YES;
        for (NSUInteger j = 1; j < k; j++) if (!leastShown || MMWindowActivityOrder(rows[j], leastShown) == NSOrderedDescending) leastShown = rows[j];
        if (k < rows.count && (!mostWaiting || MMWindowActivityOrder(rows[k], mostWaiting) == NSOrderedAscending)) mostWaiting = rows[k];
    }
    if (leastShown && mostWaiting && !*foot && MMWindowActivityOrder(mostWaiting, leastShown) == NSOrderedAscending)
        return [NSString stringWithFormat:@"%@: %@ waits while the less active %@ shows", where, mostWaiting.key, leastShown.key];
    return nil;
}

static void WindowProjectsChecks(void) {
    // The busy day: five projects, sixteen worktrees, more than the side holds.
    MMWindowModel *busy = MMWindowFixture(@"busy");
    MMWindowGroup *trees = busy.diskGroups.firstObject;
    Check([[MMWindowProjectsOf(trees.rows) componentsJoinedByString:@" "] isEqualToString:@"minmacs barkbot atlas gateway studio"] && trees.rows.count >= 16 && trees.grouped,
          @"window projects: the busy day's worktrees come by project, the project of the most active worktree first", [MMWindowProjectsOf(trees.rows) componentsJoinedByString:@" "]);
    BOOL byActivity = YES;
    for (NSUInteger i = 1; i < trees.rows.count; i++)
        if ([trees.rows[i].project isEqualToString:trees.rows[i - 1].project] && MMWindowActivityOrder(trees.rows[i - 1], trees.rows[i]) == NSOrderedDescending) byActivity = NO;
    Check(byActivity, @"window projects: inside a project the worktrees come by activity, not by disk", @"");

    // Every height a side can have, from the window's own down to where five projects with one row each just fit.
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    NSInteger perProject = 0, atFoot = 0, short_ = 0, all = 0;
    for (NSString *name in @[@"busy", @"peak", @"long", @"measuring"]) {
        MMWindowListView *l = WindowLists(PolishView(name)).lastObject;
        CGFloat w = l.frame.size.width;
        for (CGFloat h = 760; h >= 200; h -= 3) {
            l.frame = NSMakeRect(0, 0, w, h);
            BOOL dropped = NO, foot = NO;
            NSString *fault = ProjectsFault(l, [NSString stringWithFormat:@"%@ at %g", name, h], &dropped, &foot);
            if (fault && faults.count < 8) [faults addObject:fault];
            NSUInteger shownCount = [l shownKeys:0].count, total = l.groups.firstObject.rows.count;
            if (shownCount == total) all++; else if (foot) atFoot++; else perProject++;
            // A project goes unshown only where the side cannot hold five sub-headers with a row each and the line at
            // the foot, with the caches' first row under them: the caches give their rows first.
            CGFloat least = 5 * (22 + 24) + 20 + 24, room = h - 2 * 24 - 2;
            if (dropped) { short_++; if (room >= least) [faults addObject:[NSString stringWithFormat:@"%@ at %g: a project is left out, with %g points for the side", name, h, room]]; }
            if (!dropped && room >= least && [l shownKeys:1].count == 0) [faults addObject:[NSString stringWithFormat:@"%@ at %g: no cache shows", name, h]];
        }
    }
    Check(faults.count == 0 && perProject > 20 && atFoot > 0 && all > 0,
          @"window projects: at every height each project shows its most active worktree first, the room left goes to the most active, the group ends on a whole row, no line is cut, and the lines add up to the rows that wait",
          [NSString stringWithFormat:@"%ld with a line a project, %ld with one line at the foot, %ld with every row, %ld too short for all five. %@",
           (long)perProject, (long)atFoot, (long)all, (long)short_, [faults componentsJoinedByString:@" | "]]);

    // The busy and the peak day as drawn: too little room, and each project still shows its most active worktree.
    for (NSString *name in @[@"busy", @"peak"]) {
        MMWindowListView *l = WindowLists(PolishView(name)).lastObject;
        MMWindowGroup *g = l.groups.firstObject;
        NSArray<NSString *> *shown = [l shownKeys:0], *lines = [l moreLines:0];
        NSMutableArray<NSString *> *missing = [NSMutableArray new];
        for (NSString *p in MMWindowProjectsOf(g.rows)) for (MMWindowRow *r in g.rows) if ([r.project isEqualToString:p]) { if (![shown containsObject:r.key]) [missing addObject:r.key]; break; }
        NSInteger said = 0;
        for (NSString *line in lines) said += ProjectsCount(line);
        Check(shown.count < g.rows.count && missing.count == 0 && lines.count >= 2 && said == (NSInteger)(g.rows.count - shown.count),
              [NSString stringWithFormat:@"window projects %@: with too little room each project shows its most active worktree, and the lines under them say how many wait", name],
              [NSString stringWithFormat:@"%lu of %lu show. %@ / %@", (unsigned long)shown.count, (unsigned long)g.rows.count, [lines componentsJoinedByString:@", "], [missing componentsJoinedByString:@" "]]);
    }

    // VoiceOver goes down the list as it is drawn, and a row under a sub-header says its project.
    MMWindowListView *disk = WindowLists(PolishView(@"busy")).lastObject;
    NSArray *spoken = disk.accessibilityChildren;
    NSArray<NSString *> *drawnOrder = [disk drawnOrder:0];
    BOOL inOrder = spoken.count >= drawnOrder.count;
    for (NSUInteger d = 0; inOrder && d < drawnOrder.count; d++) {
        MMWindowRow *r = [busy row:drawnOrder[d]];
        NSString *label = [spoken[d] accessibilityLabel];
        if (![label hasPrefix:[NSString stringWithFormat:@"Worktrees, %@, %@", r.project, r.nameInProject]]) inOrder = NO;
    }
    Check(inOrder && [[spoken.firstObject accessibilityLabel] hasPrefix:@"Worktrees, minmacs, dogfood, changed"],
          @"window projects: VoiceOver reads the rows in the order they are drawn, each with its project", [spoken.firstObject accessibilityLabel] ?: @"none");

    // One project: the list is flat, as before.
    MMWindowListView *quiet = WindowLists(PolishView(@"quiet")).lastObject;
    MMWindowGroup *one = quiet.groups.firstObject;
    BOOL flat = !one.grouped && one.byProject && [quiet moreLines:0].count == 0 && [[quiet drawnOrder:0] isEqualToArray:[one.rows valueForKey:@"key"]] &&
                [quiet.listNames.firstObject isEqualToString:one.rows.firstObject.shownName];
    NSArray<NSNumber *> *tops = quiet.rowTops.firstObject;
    for (NSUInteger r = 0; flat && r + 1 < tops.count; r++) if (tops[r + 1].doubleValue - tops[r].doubleValue != 24) flat = NO;
    Check(flat && MMWindowProjectsOf(one.rows).count == 1 && one.rows.count == 4, @"window projects: with one project the group is the flat list of before, rows named as before, with no sub-header and no line",
          [quiet.listNames componentsJoinedByString:@", "]);

    // A scrolled group keeps its place, rule 14: the rows that wait show under the fold, each project under its
    // sub-header again, and a new model leaves the first row shown where it was. Closed, the group opens at its top.
    MMWindowView *pv = PolishView(@"peak");
    MMWindowListView *pl = WindowLists(pv).lastObject;
    NSString *last = [pl drawnOrder:0].lastObject;
    [pl reveal:last];
    NSString *first = [pl shownKeys:0].firstObject;
    BOOL lastShows = [[pl shownKeys:0] containsObject:last];
    MMWindowModel *again = MMWindowFixture(@"peak");
    again.diskGroups.firstObject.rows[0].name = @"minmacs · dogfood with a name now long enough to wrap onto a second line of its row";
    again.diskGroups.firstObject.rows[0].nameInProject = @"dogfood with a name now long enough to wrap onto a second line of its row";
    [pl setGroups:again.diskGroups ring:again.ring];
    BOOL kept = [[pl shownKeys:0].firstObject isEqualToString:first] && [pl.offsets[@"worktrees"] doubleValue] > 0;
    [pl rest];
    [pl setGroups:again.diskGroups ring:again.ring];
    BOOL top = [pl.offsets[@"worktrees"] doubleValue] == 0 && [pl moreLines:0].count >= 2;
    Check(lastShows && kept && top, @"window projects: scrolled to its end the group shows every project's rows that waited, keeps its first row when a row above it grows, and opens at its top again",
          [NSString stringWithFormat:@"%d %d %d, first %@", lastShows, kept, top, first]);
}
