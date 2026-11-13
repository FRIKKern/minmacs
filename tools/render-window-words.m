// What the menu window draws, checked string by string, issue #62: no drawn string holds an ellipsis, none is cut
// by its box or its view, a row's second line is whole facts, and every made-up row speaks the feed's own words.
// tools/render-window-polish.m includes this file. It is not built on its own.

/// Every made-up day, the real-shaped one and the three of extremes among them.
static NSArray<NSString *> *WordFixtures(void) {
    return @[@"quiet", @"busy", @"peak", @"young", @"calm", @"empty", @"long", @"running", @"done", @"memory-only", @"disk-only", @"real",
             @"extreme", @"extreme-running", @"extreme-done"];
}

static NSMutableArray<NSString *> *gWordFaults, *gWordSeen;
static NSString *gWordWhere;

/// Draws a view into a throwaway bitmap, with every string it draws read as it goes.
static void WordDraw(NSView *v, NSString *where) {
    gWordWhere = where;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
}

static NSMutableArray *WordViews(NSView *v, Class kind) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *sub in v.subviews) { if ([sub isKindOfClass:kind]) [out addObject:sub]; [out addObjectsFromArray:WordViews(sub, kind)]; }
    return out;
}

/// The words the feed can put on a row, Shell/MMWindowRows.m and MMWindowFeed.m. test/window.sh holds each to those files.
static NSDictionary<NSNumber *, NSArray<NSString *> *> *FeedStates(void) {
    return @{@(MMWindowServer): @[@"kept", @"idle"], @(MMWindowAgent): @[@"asks", @"working", @"idle"], @(MMWindowApp): @[@"kept", @"will close"],
             @(MMWindowHelper): @[@"left behind"], @(MMWindowTabs): @[@"will close"], @(MMWindowWorktree): @[@"changed", @"merged", @"kept"], @(MMWindowCache): @[@"kept", @"in use"]};
}
static NSDictionary<NSNumber *, NSArray<NSString *> *> *FeedLabels(void) {
    return @{@(MMWindowServer): @[@"Port", @"Project", @"Runs in", @"Started by", @"Idle", @"Last used", @"Up", @"Kept", @"Stays"],
             @(MMWindowAgent): @[@"Agent", @"Project", @"State", @"Why", @"Stays"], @(MMWindowApp): @[@"Used by", @"Serves", @"Stays"],
             @(MMWindowHelper): @[@"Left by", @"Folder", @"Stays"], @(MMWindowTabs): @[@"Open", @"On", @"Left by", @"Stays"],
             @(MMWindowWorktree): @[@"Branch", @"Merged", @"Files", @"Not pushed", @"Quiet", @"Folder", @"Stays"],
             @(MMWindowCache): @[@"Kind", @"Project", @"Last used", @"Folder", @"Stays"]};
}

static void WindowWordChecks(void) {
    // Every string of every day, in every state a pointer can bring: the menu, each row's story with the dock beside
    // it, the pointer on Fix Everything, and Settings. A fault is an ellipsis, a string wider or taller than the box
    // it was given, or one that leaves its view.
    gWordFaults = [NSMutableArray new]; gWordSeen = [NSMutableArray new];
    __block NSInteger strings = 0;
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        strings++;
        [gWordSeen addObject:text];
        NSString *fault = nil;
        if ([text containsString:@"…"] || [text containsString:@"..."]) fault = @"ellipsis";
        else if (!NSIsEmptyRect(allowed) && (NSWidth(used) > NSWidth(allowed) + 1 || NSMaxY(used) > NSMaxY(allowed) + 1 || NSMinY(used) < NSMinY(allowed) - 1)) fault = @"past its box";
        else if (!NSIsEmptyRect(bounds) && (NSMinX(used) < NSMinX(bounds) - 1 || NSMaxX(used) > NSMaxX(bounds) + 1 || NSMinY(used) < NSMinY(bounds) - 1 || NSMaxY(used) > NSMaxY(bounds) + 1)) fault = @"past its view";
        if (fault && gWordFaults.count < 12) [gWordFaults addObject:[NSString stringWithFormat:@"%@, %@: %@", gWordWhere, fault, text.length > 60 ? [text substringToIndex:60] : text]];
    });
    NSInteger states = 0;
    BOOL smallest = NO;
    for (NSString *name in WordFixtures()) {
        MMWindowView *v = PolishView(name);
        MMWindowModel *m = v.model;
        NSView *middle = WordViews(v, MMWindowMiddleView.class).firstObject, *dock = PolishDock(v);
        WordDraw(v, name); states++;
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) {
            // Every row of the days where a row can go wrong, and the first and last of each group elsewhere.
            BOOL every = [name isEqualToString:@"real"] || [name isEqualToString:@"long"] || [name isEqualToString:@"peak"];
            for (NSUInteger i = 0; i < g.rows.count; i++) {
                if (!every && i > 1 && i + 1 < g.rows.count) continue;
                [gWordSeen removeAllObjects];
                v.pointedRow = g.rows[i].key;
                NSString *where = [NSString stringWithFormat:@"%@ %@", name, g.rows[i].key];
                WordDraw(middle, where); WordDraw(dock, where); states++;
                if ([name isEqualToString:@"peak"] && i + 1 == g.rows.count && [g.key isEqualToString:@"worktrees"]) smallest = [gWordSeen containsObject:@"The smallest of 18 worktrees"];
            }
        }
        // The scrolled lists too: the last row of each group is in view after the pointing above.
        for (NSView *list in WindowLists(v)) WordDraw(list, [name stringByAppendingString:@" scrolled"]);
        v.pointedRow = nil;
        v.pointsAtFix = YES;
        WordDraw(dock, [name stringByAppendingString:@" fix"]); states++;
        v.pointsAtFix = NO;
        v.showsSettings = YES;
        WordDraw(v, [name stringByAppendingString:@" settings"]); states++;
        for (NSView *option in PolishSettings(v).subviews) WordDraw(option, [name stringByAppendingString:@" settings"]);
    }
    // Increase Contrast and the welcome draw through the same helpers.
    MMWindowForceContrast(YES);
    WordDraw(PolishView(@"extreme"), @"extreme contrast");
    MMWindowForceContrast(NO);
    WordDraw(PolishView(@"welcome"), @"welcome");
    MMWindowWatchDraws(nil);
    Check(gWordFaults.count == 0 && strings > 20000 && states > 300,
          @"window words: on every day and in every state no drawn string holds an ellipsis, none is wider or taller than its box, and none leaves its view",
          [NSString stringWithFormat:@"%ld strings in %ld states. %@", (long)strings, (long)states, [gWordFaults componentsJoinedByString:@" | "]]);
    Check(smallest, @"window words: the last of a group is its smallest, not its 18th biggest", @"");

    // Every name is drawn whole: its lines, put together, are the name. A long one wraps, and its row is taller for it.
    NSMutableArray<NSString *> *broken = [NSMutableArray new];
    NSInteger wrapped = 0;
    for (NSString *name in WordFixtures()) {
        MMWindowView *v = PolishView(name);
        MMWindowModel *m = v.model;
        NSMutableArray<NSString *> *whole = [NSMutableArray new], *drawn = [NSMutableArray new];
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) [whole addObjectsFromArray:[g.rows valueForKey:@"shownName"]];
        for (MMWindowListView *l in WindowLists(v)) {
            [drawn addObjectsFromArray:l.drawnNames];
            for (NSUInteger gi = 0; gi < l.groups.count; gi++) for (NSUInteger ri = 0; ri < l.groups[gi].rows.count; ri++) {
                NSInteger lines = (NSInteger)[MMWindowRowName(l.groups[gi].rows[ri], l.groups[gi].side, YES, 36, 306, NULL) count];
                CGFloat height = l.rowTops[gi][ri + 1].doubleValue - l.rowTops[gi][ri].doubleValue;
                if (lines > 1) wrapped++;
                if (height < l.rowHeight + MMWindowNameLine * (lines - 1) - 0.5) [broken addObject:[NSString stringWithFormat:@"%@ row too low: %@", name, l.groups[gi].rows[ri].shownName]];
            }
        }
        for (NSUInteger i = 0; i < whole.count && i < drawn.count; i++) {
            NSString *joined = [[drawn[i] stringByReplacingOccurrencesOfString:@"\n" withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (![joined isEqualToString:[whole[i] stringByReplacingOccurrencesOfString:@" " withString:@""]]) [broken addObject:[NSString stringWithFormat:@"%@: %@", name, whole[i]]];
        }
        if (whole.count != drawn.count) [broken addObject:[name stringByAppendingString:@": rows missing"]];
    }
    Check(broken.count == 0 && wrapped >= 4, @"window words: every row's name is drawn whole, and a name too long for one line wraps and makes its row taller",
          [NSString stringWithFormat:@"%ld wrapped. %@", (long)wrapped, [broken componentsJoinedByString:@" | "]]);
    // What gives way to a name: the state word first, then the row's own hour, then CPU.
    MMWindowRow *tight = [MMWindowRow new];
    tight.kind = MMWindowServer; tight.key = @"s"; tight.state = @"idle"; tight.cpuPercent = 2; tight.bytes = 5 << 20;
    tight.hour = MMWindowFixture(@"busy").memoryGroups[0].rows[0].hour;
    NSMutableArray<NSString *> *gives = [NSMutableArray new];
    NSMutableString *growing = [@":3000 Vite" mutableCopy];
    for (NSInteger i = 0; i < 40; i++) {
        tight.name = growing;
        MMWindowRowFit fit;
        MMWindowRowName(tight, MMWindowMemory, YES, 36, 306, &fit);
        NSString *now = [NSString stringWithFormat:@"%d%d%d/%ld", fit.state, fit.hour, fit.cpu, (long)MIN(fit.lines, 2)];
        if (![gives.lastObject isEqualToString:now]) [gives addObject:now];
        [growing appendString:@" of it"];
    }
    Check([[gives componentsJoinedByString:@" "] isEqualToString:@"111/1 011/1 001/1 000/1 000/2"],
          @"window words: a longer name takes the room of the state word, then of the hour, then of CPU, and only then wraps", [gives componentsJoinedByString:@" "]);

    // A row's second line is whole facts: a long path shows its last folders, a fact that does not fit is left out,
    // and the line never holds a bare label or ends on a dot.
    MMWindowRow *server = [MMWindowRow new];
    server.kind = MMWindowServer; server.key = @"server:1"; server.name = @":56784 BEAM";
    server.facts = @[[MMWindowFact label:@"Port" value:@"56784"],
                     [MMWindowFact label:@"Project" value:@"/Volumes/Work/dev-caches/tmp/agent-code/agent-501/scratchpad/orchestrate/wt/desk-a-hint/api"],
                     [MMWindowFact label:@"Started by" value:@"Claude Code"]];
    NSString *line = MMWindowRowSecondLine(server, 270), *narrow = MMWindowRowSecondLine(server, 120), *none = MMWindowRowSecondLine(server, 30);
    NSMutableArray<NSString *> *lineFaults = [NSMutableArray new];
    for (NSString *name in WordFixtures()) {
        MMWindowModel *m = MMWindowFixture(name);
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) for (NSNumber *w in @[@270, @200, @120]) {
            NSString *l = MMWindowRowSecondLine(r, w.doubleValue);
            if (!l) continue;
            BOOL bad = [l hasSuffix:@"·"] || [l hasSuffix:@" "] || [l containsString:@"…"] || MMWindowWidth(MMWindowText(l, 11, NSFontWeightRegular, NSColor.whiteColor)) > w.doubleValue + 1;
            for (MMWindowFact *f in r.facts) if ([l isEqualToString:f.label] || [l hasSuffix:[@" · " stringByAppendingString:f.label]]) bad = YES;
            if (bad) [lineFaults addObject:[NSString stringWithFormat:@"%@ %@: %@", name, r.key, l]];
        }
    }
    Check([line isEqualToString:@"Project scratchpad/orchestrate/wt/desk-a-hint/api"] && [narrow isEqualToString:@"Project api"] && none == nil && lineFaults.count == 0,
          @"window words: a row's second line is whole facts only: a long path shows its last folders, and no line is a bare label or ends on a dot",
          [NSString stringWithFormat:@"%@ / %@ / %@. %@", line, narrow, none, [lineFaults componentsJoinedByString:@" | "]]);

    // The made-up rows speak as the feed does: only its state words, only its fact labels.
    NSMutableArray<NSString *> *foreign = [NSMutableArray new];
    for (NSString *name in WordFixtures()) {
        MMWindowModel *m = MMWindowFixture(name);
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) {
            if (r.state && ![FeedStates()[@(r.kind)] containsObject:r.state]) [foreign addObject:[NSString stringWithFormat:@"%@ %@ state %@", name, r.key, r.state]];
            for (MMWindowFact *f in r.facts) if (![FeedLabels()[@(r.kind)] containsObject:f.label]) [foreign addObject:[NSString stringWithFormat:@"%@ %@ fact %@", name, r.key, f.label]];
        }
        for (MMWindowFix *f in m.fixes) {
            BOOL known = NO;
            for (NSString *lead in @[@"Wrap Up ", @"Stop ", @"Quit ", @"Remove ", @"Move ", @"Delete ", @"Clean up ", @"Clean ", @"Run "]) if ([f.title hasPrefix:lead]) known = YES;
            if (!known) [foreign addObject:[NSString stringWithFormat:@"%@ fix %@", name, f.title]];
        }
        if (m.asks && ![m.asks isEqualToString:@"1 agent asks you"] && ![m.asks hasSuffix:@" agents ask you"]) [foreign addObject:[NSString stringWithFormat:@"%@ asks %@", name, m.asks]];
    }
    Check(foreign.count == 0, @"window words: every made-up row has a state word, fact labels and a fix title the feed can make", [[foreign subarrayWithRange:NSMakeRange(0, MIN(foreign.count, 8))] componentsJoinedByString:@" | "]);
}
