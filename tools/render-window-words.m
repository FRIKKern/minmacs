// What the menu window draws, checked string by string, issue #62: no drawn string holds an ellipsis, none is cut
// by its box or its view, a row's second line is whole facts, and every made-up row speaks the feed's own words.
// tools/render-window-polish.m includes this file. It is not built on its own.

/// Every made-up day, the real-shaped one and the three of extremes among them.
static NSArray<NSString *> *WordFixtures(void) {
    return @[@"quiet", @"busy", @"peak", @"young", @"calm", @"empty", @"long", @"running", @"done", @"memory-only", @"disk-only", @"real",
             @"extreme", @"extreme-running", @"extreme-done"];
}

static NSMutableArray<NSString *> *gWordFaults, *gWordSeen;
static NSMutableArray<NSArray *> *gWordRects;       // the lines of one drawing: text, rect, the view it was drawn in
static NSString *gWordWhere;

static void WordFault(NSString *kind, NSString *text) {
    if (gWordFaults.count < 12) [gWordFaults addObject:[NSString stringWithFormat:@"%@, %@: %@", gWordWhere, kind, text.length > 60 ? [text substringToIndex:60] : text]];
}

/// Draws a view into a throwaway bitmap, with every string it draws read as it goes. Then no two of the strings one
/// view drew may stand on one another: a name must end before the number beside it starts.
static void WordDraw(NSView *v, NSString *where) {
    gWordWhere = where;
    gWordRects = [NSMutableArray new];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSArray<NSArray *> *rects = gWordRects;
    gWordRects = nil;
    for (NSUInteger i = 0; i < rects.count; i++) for (NSUInteger j = i + 1; j < rects.count; j++) {
        if (![rects[i][2] isEqual:rects[j][2]]) continue;       // drawn in two views, each in its own coordinates
        NSRect a = [rects[i][1] rectValue], b = [rects[j][1] rectValue], both = NSIntersectionRect(a, b);
        if (NSEqualRects(a, b) && [rects[i][0] isEqual:rects[j][0]]) continue;       // one string, drawn in two passes of one drawing
        // Two strings on one line that share more than a point of width. Lines of one block touch only at their edges.
        if (both.size.width > 1.5 && both.size.height > MIN(a.size.height, b.size.height) * 0.5)
            WordFault(@"over another string", [NSString stringWithFormat:@"%@ / %@", rects[i][0], rects[j][0]]);
    }
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
    return @{@(MMWindowServer): @[@"Port", @"Project", @"Runs in", @"Started by", @"Idle", @"Last used", @"Running", @"Kept", @"Stays"],
             @(MMWindowAgent): @[@"Agent", @"Project", @"State", @"Stays"], @(MMWindowApp): @[@"Used by", @"Serves", @"Stays"],
             @(MMWindowHelper): @[@"Left by", @"Folder", @"Stays"], @(MMWindowTabs): @[@"Open", @"On", @"Left by", @"Stays"],
             @(MMWindowWorktree): @[@"Branch", @"Files", @"Not pushed", @"Untouched", @"Changed", @"Folder", @"Stays"],
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
        if (gWordRects && text.length && used.size.width > 0) [gWordRects addObject:@[text, [NSValue valueWithRect:used], [NSValue valueWithNonretainedObject:NSView.focusView]]];
        NSString *fault = nil;
        if ([text containsString:@"…"] || [text containsString:@"..."]) fault = @"ellipsis";
        else if (!NSIsEmptyRect(allowed) && (NSWidth(used) > NSWidth(allowed) + 1 || NSMaxY(used) > NSMaxY(allowed) + 1 || NSMinY(used) < NSMinY(allowed) - 1)) fault = @"past its box";
        else if (!NSIsEmptyRect(bounds) && (NSMinX(used) < NSMinX(bounds) - 1 || NSMaxX(used) > NSMaxX(bounds) + 1 || NSMinY(used) < NSMinY(bounds) - 1 || NSMaxY(used) > NSMaxY(bounds) + 1)) fault = @"past its view";
        if (fault) WordFault(fault, text);
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
    // Increase Contrast draws through the same helpers, and so does the welcome, whose strings are read here too.
    MMWindowForceContrast(YES);
    WordDraw(PolishView(@"extreme"), @"extreme contrast");
    MMWindowForceContrast(NO);
    NSInteger before = strings;
    for (NSString *name in @[@"welcome", @"welcome-off", @"welcome-delete", @"welcome-watched"]) {
        MMWindowView *w = PolishView(name);
        w.welcomeView.arrival = 1;
        WordDraw(w, name);
        for (NSView *control in w.welcomeView.controls) WordDraw(control, name);
        for (NSView *sub in w.welcomeView.subviews) for (NSView *control in sub.subviews) WordDraw(control, name);
    }
    NSInteger welcomeStrings = strings - before;
    MMWindowWatchDraws(nil);
    Check(welcomeStrings >= 4 * 12, @"window words: the welcome's strings are read by the same watch", [NSString stringWithFormat:@"%ld strings", (long)welcomeStrings]);
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
                NSInteger lines = (NSInteger)[MMWindowRowName(l.groups[gi].rows[ri], l.groups[gi].side, YES, NSMakeRect(5, 0, 310, 24), NULL) count];
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
        MMWindowRowColumns fit;
        MMWindowRowName(tight, MMWindowMemory, YES, NSMakeRect(5, 0, 310, 24), &fit);
        NSString *now = [NSString stringWithFormat:@"%d%d%d/%ld", !NSIsEmptyRect(fit.state), !NSIsEmptyRect(fit.hour), !NSIsEmptyRect(fit.cpu), (long)MIN(fit.lines, 2)];
        if (![gives.lastObject isEqualToString:now]) [gives addObject:now];
        [growing appendString:@" of it"];
    }
    Check([[gives componentsJoinedByString:@" "] isEqualToString:@"111/1 011/1 001/1 000/1 000/2"],
          @"window words: a longer name takes the room of the state word, then of the hour, then of CPU, and only then wraps", [gives componentsJoinedByString:@" "]);

    // Wide letters: a name of Japanese letters, of capital W, of emoji or of Arabic is measured as it is, so it ends
    // before what stands beside it, or wraps and makes its row taller. The watch above saw none of them over a number.
    MMWindowRow *wideRow = [MMWindowRow new];
    wideRow.kind = MMWindowAgent; wideRow.key = @"w"; wideRow.cpuPercent = 12.5; wideRow.bytes = 600 << 20; wideRow.hour = tight.hour;
    NSMutableArray<NSString *> *wideFaults = [NSMutableArray new];
    for (NSString *n in @[@"日本語のとても長いブランチ名です。", @"日本語のブランチ名です", @"WWWWWWWWWWWWWWWWWW", @"🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀", @"مراجعة كل صفحات الأزرار قبل الإصدار"]) {
        wideRow.name = n;
        MMWindowRowColumns fit;
        NSArray<NSString *> *got = MMWindowRowName(wideRow, MMWindowMemory, YES, NSMakeRect(5, 0, 310, 24), &fit);
        for (NSString *line in got) if (MMWindowWidth(MMWindowText(line, 13, NSFontWeightRegular, NSColor.whiteColor)) > NSWidth(fit.name) + 0.5) [wideFaults addObject:n];
        if (![[got componentsJoinedByString:@""] isEqualToString:[n stringByReplacingOccurrencesOfString:@" " withString:@""]] &&
            ![[got componentsJoinedByString:@" "] isEqualToString:n]) [wideFaults addObject:[@"not whole: " stringByAppendingString:n]];
    }
    Check(wideFaults.count == 0, @"window words: a name of wide letters is measured as it is, and ends before the columns beside it or wraps", [wideFaults componentsJoinedByString:@" | "]);

    // Each fact is worded in one place, and reads as a person would say it: in the story with its label, and alone
    // on a row's second line. A duration has one form, and none is ever a zero.
    NSString *(^said)(MMWindowFact *) = ^NSString *(MMWindowFact *f) { return f ? [NSString stringWithFormat:@"%@: %@ / %@", f.label, f.value, f.phrase] : @"none"; };
    NSString *spans = [@[MMWindowSpan(0) ?: @"none", MMWindowSpan(9) ?: @"none", MMWindowSpan(40), MMWindowSpan(720), MMWindowSpan(9360), MMWindowSpan(7200), MMWindowSpan(277200), MMWindowSpan(12 * 86400.0)] componentsJoinedByString:@" | "];
    Check([spans isEqualToString:@"none | none | 40 s | 12 min | 2 h 36 min | 2 h | 3 d 5 h | 12 d"], @"window facts: one rule for how long, and under ten seconds no number at all", spans);
    NSArray<NSArray<NSString *> *> *facts = @[
        @[said(MMWindowFactPort(3000)), @"Port: :3000 / (null)"], @[said(MMWindowFactPort(0)), @"none"],
        @[said(MMWindowFactProject(@"/Users/sam/code/atlas/apps/web")), @"Project: /Users/sam/code/atlas/apps/web / in web"], @[said(MMWindowFactProject(@"atlas")), @"Project: atlas / in atlas"],
        @[said(MMWindowFactProject(@"/")), @"none"], @[said(MMWindowFactProject(@"~")), @"none"], @[said(MMWindowFactProject(nil)), @"none"],
        @[said(MMWindowFactOwner(@"atlas")), @"Project: atlas / for atlas"], @[said(MMWindowFactOwner(@"")), @"none"],
        @[said(MMWindowFactRunsIn(@"Ghostty, tab 2")), @"Runs in: Ghostty, tab 2 / runs in Ghostty, tab 2"],
        @[said(MMWindowFactStartedBy(@"cmux · parent exited")), @"Started by: a program in cmux that has quit / started in cmux, its starter has quit"],
        @[said(MMWindowFactStartedBy(@"launchd")), @"Started by: launchd / started by launchd"],
        @[said(MMWindowFactStartedBy(@"parent exited")), @"Started by: a program that has quit / its starter has quit"],
        @[said(MMWindowFactStartedBy(@"pnpm dev · cmux")), @"Started by: pnpm dev in cmux / started by pnpm dev in cmux"],
        @[said(MMWindowFactStartedBy(@"pnpm dev · cmux · parent exited")), @"Started by: pnpm dev in cmux, its starter has quit / started by pnpm dev in cmux, its starter has quit"],
        @[said(MMWindowFactStartedBy(@"pnpm dev · launchd")), @"Started by: pnpm dev / started by pnpm dev"],
        @[said(MMWindowFactIdle(7800)), @"Idle: 2 h 10 min / idle for 2 h 10 min"], @[said(MMWindowFactIdle(2)), @"Idle: since just now / idle since just now"],
        @[said(MMWindowFactLastUsed(180)), @"Last used: 3 min ago / used 3 min ago"], @[said(MMWindowFactLastUsed(0)), @"Last used: just now / used just now"],
        @[said(MMWindowFactUp(9360)), @"Running: 2 h 36 min / up 2 h 36 min"], @[said(MMWindowFactUp(1)), @"Running: since just now / started just now"],
        @[said(MMWindowFactKept(4800)), @"Kept: 1 h 20 min more / kept for 1 h 20 min more"], @[said(MMWindowFactKept(0)), @"none"],
        @[said(MMWindowFactAgent(@"Claude Code")), @"Agent: Claude Code / Claude Code"], @[said(MMWindowFactState(@"working")), @"State: working / (null)"],
        @[said(MMWindowFactUsedBy(@"Claude Code")), @"Used by: Claude Code / used by Claude Code"],
        @[said(MMWindowFactServes(@[@3000, @3001])), @"Serves: ports 3000, 3001 / serves ports 3000, 3001"], @[said(MMWindowFactServes(@[])), @"none"],
        @[said(MMWindowFactStays(@"it is on the keep list")), @"Stays: it is on the keep list / (null)"],
        @[said(MMWindowFactLeftBy(@"fix-auth-redirect")), @"Left by: fix-auth-redirect / left by fix-auth-redirect"],
        @[said(MMWindowFactFolder(@"~/code/atlas")), @"Folder: ~/code/atlas / (null)"],
        @[said(MMWindowFactOpenTabs(14)), @"Open: 14 tabs / 14 tabs open"], @[said(MMWindowFactOpenTabs(1)), @"Open: 1 tab / 1 tab open"], @[said(MMWindowFactOpenTabs(0)), @"none"],
        @[said(MMWindowFactOnPorts(@[@3003])), @"On: port 3003 / on port 3003"],
        @[said(MMWindowFactBranch(@"wip")), @"Branch: wip / (null)"],
        @[said(MMWindowFactFiles(3, 1)), @"Files: 3 changed, 1 new / 3 files changed, 1 new"], @[said(MMWindowFactFiles(1, 0)), @"Files: 1 changed / 1 file changed"],
        @[said(MMWindowFactFiles(0, 2)), @"Files: 2 new / 2 new files"], @[said(MMWindowFactFiles(0, 0)), @"none"],
        @[said(MMWindowFactNotPushed(2)), @"Not pushed: 2 commits / 2 commits not pushed"], @[said(MMWindowFactNotPushed(0)), @"none"],
        // The feed gives a worktree's quiet time to the second, so the words may be as fine as the span rule.
        @[said(MMWindowFactUntouched(0)), @"Changed: just now / changed just now"], @[said(MMWindowFactUntouched(0.1 * 86400)), @"Untouched: 2 h 24 min / untouched for 2 h 24 min"],
        @[said(MMWindowFactUntouched(0.9 * 86400)), @"Untouched: 21 h 36 min / untouched for 21 h 36 min"], @[said(MMWindowFactUntouched(86400)), @"Untouched: 1 d / untouched for 1 d"],
        @[said(MMWindowFactUntouched(12 * 86400.0)), @"Untouched: 12 d / untouched for 12 d"],
        @[said(MMWindowFactKind(@"Xcode build output")), @"Kind: Xcode build output / Xcode build output"]];
    NSMutableArray<NSString *> *misworded = [NSMutableArray new];
    for (NSArray<NSString *> *f in facts) if (![f[0] isEqualToString:f[1]]) [misworded addObject:[NSString stringWithFormat:@"%@, want %@", f[0], f[1]]];
    Check(misworded.count == 0 && facts.count >= 36, @"window facts: each of the 22 facts has its own words, with its label in the story and alone on a row's second line, and says nothing when it has nothing true to say",
          [misworded componentsJoinedByString:@" | "]);

    // Every phrase the window shows with a count in it, at 0, 1 and 2: one of a thing is never plural, and a zero
    // says nothing where nothing is the truth.
    NSString *(^three)(NSString *(^)(NSInteger)) = ^NSString *(NSString *(^f)(NSInteger)) { return [@[f(0) ?: @"none", f(1) ?: @"none", f(2) ?: @"none"] componentsJoinedByString:@" | "]; };
    NSArray *(^ports)(NSInteger) = ^NSArray *(NSInteger n) { return [@[@3000, @3001] subarrayWithRange:NSMakeRange(0, (NSUInteger)n)]; };
    NSArray<NSArray<NSString *> *> *counted = @[
        @[three(^(NSInteger n) { return MMWindowAsksLine(n); }), @"none | 1 agent asks you | 2 agents ask you"],
        @[three(^(NSInteger n) { return MMWindowFixes(n); }), @"0 fixes | 1 fix | 2 fixes"],
        @[three(^(NSInteger n) { return MMWindowEndTitle(n, n); }), @"0 fixes done | 1 fix done | 2 fixes done"],
        @[three(^(NSInteger n) { return MMWindowEndTitle(n, 2); }), @"0 of 2 fixes done | 1 of 2 fixes done | 2 fixes done"],
        @[three(^(NSInteger n) { return MMWindowEndTitle(0, n); }), @"0 fixes done | 0 of 1 fix done | 0 of 2 fixes done"],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(n, 0, 0, 0, 0, 0); }), @"none | Skipped 1 agent that asks you. | Skipped 2 agents that ask you."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(0, n, 0, 0, 0, 0); }), @"none | Skipped 1 fix that needs your own press. | Skipped 2 fixes that need your own press."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(0, 0, n, 0, 0, 0); }), @"none | Skipped 1 kept since it changed or is in use. | Skipped 2 kept since they changed or are in use."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(0, 0, 0, n, 0, 0); }), @"none | Skipped 1 blocked. | Skipped 2 blocked."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(0, 0, 0, 0, n, 0); }), @"none | Skipped 1 thing in the fix you stopped partway. | Skipped 2 things in the fix you stopped partway."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(0, 0, 0, 0, 0, n); }), @"none | Skipped 1 fix you stopped. | Skipped 2 fixes you stopped."],
        @[three(^(NSInteger n) { return MMWindowSkippedNote(n, n, 0, 0, 0, 0); }), @"none | Skipped 1 agent that asks you and 1 fix that needs your own press. | Skipped 2 agents that ask you and 2 fixes that need your own press."],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"stop", n, 0); }), @"Stop 0 idle servers | Stop 1 idle server | Stop 2 idle servers"],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"quit", n, 0); }), @"Quit 0 apps | Quit 1 app | Quit 2 apps"],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"remove", n, 0); }), @"Remove 0 merged worktrees | Remove 1 merged worktree | Remove 2 merged worktrees"],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"trash", n, 0); }), @"Clean up 0 leftovers | Clean up 1 leftover | Clean up 2 leftovers"],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"trash", n, 1); }), @"Move 0 leftovers to the Trash | Move 1 leftover to the Trash | Move 2 leftovers to the Trash"],
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"trash", n, 2); }), @"Delete 0 leftovers | Delete 1 leftover | Delete 2 leftovers"],
        // One cleanup is named by what it cleans in the feed, Shell/MMWindowFeed.m; the count form stays right for it anyway.
        @[three(^(NSInteger n) { return MMWindowFixCountTitle(@"clean", n, 0); }), @"Run 0 tool cleanups | Run 1 tool cleanup | Run 2 tool cleanups"],
        @[three(^(NSInteger n) { return MMWindowAfterTitle(n); }), @"none | After the fix | After all 2 fixes"],
        @[three(^(NSInteger n) { return MMWindowMoreLine(n, 0); }), @"none | 1 more below | 2 more below"],
        @[three(^(NSInteger n) { return MMWindowMoreLine(0, n); }), @"none | 1 more above | 2 more above"],
        @[three(^(NSInteger n) { return MMWindowTabsName(n, @"Safari"); }), @"Safari | 1 localhost tab in Safari | 2 localhost tabs in Safari"],
        @[three(^(NSInteger n) { return MMWindowReadyNote(n); }), @"none | 1 ready. It waits for your press. | 2 ready. They wait for your press."],
        @[three(^(NSInteger n) { return MMWindowCount(n, @"minute", @"minutes"); }), @"0 minutes | 1 minute | 2 minutes"],
        @[three(^(NSInteger n) { return MMWindowFactOpenTabs(n).phrase; }), @"none | 1 tab open | 2 tabs open"],
        @[three(^(NSInteger n) { return MMWindowFactFiles(n, 0).phrase; }), @"none | 1 file changed | 2 files changed"],
        @[three(^(NSInteger n) { return MMWindowFactFiles(0, n).phrase; }), @"none | 1 new file | 2 new files"],
        @[three(^(NSInteger n) { return MMWindowFactFiles(n, n).phrase; }), @"none | 1 file changed, 1 new | 2 files changed, 2 new"],
        @[three(^(NSInteger n) { return MMWindowFactNotPushed(n).phrase; }), @"none | 1 commit not pushed | 2 commits not pushed"],
        @[three(^(NSInteger n) { return MMWindowFactServes(ports(n)).phrase; }), @"none | serves port 3000 | serves ports 3000, 3001"],
        @[three(^(NSInteger n) { return MMWindowFactOnPorts(ports(n)).phrase; }), @"none | on port 3000 | on ports 3000, 3001"]];
    NSMutableArray<NSString *> *miscounted = [NSMutableArray new];
    for (NSArray<NSString *> *c in counted) if (![c[0] isEqualToString:c[1]]) [miscounted addObject:[NSString stringWithFormat:@"%@, want %@", c[0], c[1]]];
    // And as the window draws them: a tabs row of one, the dock with one fix and with two.
    MMWindowRow *oneTab = [MMWindowRow new];
    oneTab.kind = MMWindowTabs; oneTab.tabs = 1; oneTab.name = @"Safari";
    NSMutableArray<NSString *> *dockSaid = [NSMutableArray new];
    for (NSNumber *n in @[@0, @1, @2]) {
        MMWindowModel *dm = MMWindowFixture(@"busy");
        dm.fixes = [dm.fixes subarrayWithRange:NSMakeRange(0, n.unsignedIntegerValue)];
        MMWindowView *dv = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        dv.model = dm;
        MMWindowDockView *dd = PolishDock(dv);
        NSMutableArray<NSString *> *drawn = [NSMutableArray new];
        MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) { if ([text containsString:@" first"] || [text containsString:@"fix,"]) [drawn addObject:text]; });
        [dd bitmapImageRepForCachingDisplayInRect:dd.bounds];
        [dd cacheDisplayInRect:dd.bounds toBitmapImageRep:[dd bitmapImageRepForCachingDisplayInRect:dd.bounds]];
        MMWindowWatchDraws(nil);
        dv.pointsAtFix = YES;
        [dockSaid addObject:[NSString stringWithFormat:@"%@ / %@ / %@", dd.fix.accessibilityLabel, n.integerValue ? dd.macLines.firstObject : @"-", drawn.firstObject ?: @"-"]];
    }
    NSString *dockLines = [dockSaid componentsJoinedByString:@" | "];
    Check(miscounted.count == 0 && [oneTab.shownName isEqualToString:@"1 localhost tab in Safari"] &&
          [dockLines isEqualToString:@"Fix Everything, dimmed / - / - | Fix Everything, 1 fix / After the fix / - | Fix Everything, 2 fixes / After all 2 fixes / 2 fixes, Wrap Up fix-auth-redirect first"],
          @"window words: every counted phrase reads right at 0, 1 and 2, one of a thing is never plural, in the model and as the dock draws it",
          [NSString stringWithFormat:@"%@ / %@. %@", oneTab.shownName, dockLines, [miscounted componentsJoinedByString:@" | "]]);

    // A row's second line is whole phrases: one that does not fit is left out, and the line never holds a bare
    // label, ends on a dot or says a zero.
    MMWindowRow *server = [MMWindowRow new];
    server.kind = MMWindowServer; server.key = @"server:1"; server.name = @":56784 BEAM";
    server.facts = @[MMWindowFactPort(56784), MMWindowFactProject(@"/Volumes/Work/dev-caches/tmp/agent-code/agent-501/scratchpad/orchestrate/wt/desk-a-hint/api"),
                     MMWindowFactStartedBy(@"cmux · parent exited"), MMWindowFactUp(120)];
    NSString *line = MMWindowRowSecondLine(server, 270), *narrow = MMWindowRowSecondLine(server, 60), *none = MMWindowRowSecondLine(server, 20);
    NSString *tree = MMWindowRowSecondLine([MMWindowFixture(@"real") row:@"worktree:window-polish"], 270), *merged = MMWindowRowSecondLine([MMWindowFixture(@"real") row:@"worktree:removal-choice"], 270);
    NSString *agent = MMWindowRowSecondLine([MMWindowFixture(@"real") row:@"agent:0"], 270), *cacheLine = MMWindowRowSecondLine([MMWindowFixture(@"real") row:@"cache:0"], 270);
    NSMutableArray<NSString *> *lineFaults = [NSMutableArray new];
    for (NSString *name in WordFixtures()) {
        MMWindowModel *m = MMWindowFixture(name);
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) for (NSNumber *w in @[@270, @200, @120]) {
            NSString *l = MMWindowRowSecondLine(r, w.doubleValue);
            if (!l) continue;
            BOOL bad = [l hasSuffix:@"·"] || [l hasSuffix:@" "] || [l containsString:@"…"] || [l containsString:@"Why"] || [l containsString:@" 0s"] || [l containsString:@" 0 s"] ||
                       MMWindowWidth(MMWindowText(l, 11, NSFontWeightRegular, NSColor.whiteColor)) > w.doubleValue + 1;
            for (MMWindowFact *f in r.facts) if ([l isEqualToString:f.label] || [l hasSuffix:[@" · " stringByAppendingString:f.label]]) bad = YES;
            // The labels that read odd when glued to their value: "Kind Xcode build output", "Files 3 changed", "Running 2 h".
            for (NSString *label in @[@"Port ", @"Project ", @"Kind ", @"Files ", @"Not pushed ", @"Open ", @"On port", @"Last used ", @"Agent ", @"Idle 2", @"Running ", @"Untouched 1", @"Branch ", @"Folder ", @"State ", @"Stays "])
                if ([l hasPrefix:label] || [l containsString:[@" · " stringByAppendingString:label]]) bad = YES;
            if (bad) [lineFaults addObject:[NSString stringWithFormat:@"%@ %@: %@", name, r.key, l]];
        }
    }
    Check([line isEqualToString:@"In api · started in cmux, its starter has quit"] && [narrow isEqualToString:@"In api"] && none == nil &&
          [tree isEqualToString:@"3 files changed, 1 new · 2 commits not pushed"] && [merged isEqualToString:@"Untouched for 12 d"] && [agent isEqualToString:@"Claude Code"] &&
          [cacheLine isEqualToString:@"Xcode build output · for menus"] && lineFaults.count == 0,
          @"window words: a row's second line is whole phrases a person would say, and never a label glued to its value",
          [NSString stringWithFormat:@"%@ / %@ / %@ / %@ / %@ / %@ / %@. %@", line, narrow, none, tree, merged, agent, cacheLine, [lineFaults componentsJoinedByString:@" | "]]);

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
