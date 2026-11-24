// An agent's story. The owner wrote: "On Agent we want to see what they been doing, where they are, what worktrees,
// their milestones etc, what cache it hold, etc." These checks hold the made-up day "agents": one agent with every
// fact, its Go to press and its links, and one with almost none, whose story says only what is known.
// tools/render.m includes this file after render-window-caches.m, whose CachesDrawn it uses. It is not built on its own.

static void WindowAgentChecks(void) {
    MMWindowView *v = PolishView(@"agents");
    MMWindowMiddleView *middle = WordViews(v, MMWindowMiddleView.class).firstObject;

    v.pointedRow = @"agent:3";
    NSArray<NSString *> *told = CachesDrawn(middle);
    NSString *all = [told componentsJoinedByString:@" | "];
    NSArray *want = @[@"Working. Last active just now.", @"~/code/barkbot-worktrees/lane-c", @"lane-c", @"2 h 36 min", @"42 tool uses, 6 files edited in the last hour",
                      @"cmux, barkbot, lane C", @"barkbot · lane-c", @"#142 · open · milestone: Phase 6", @"port 49211", @":5175 Vite",
                      @"Claude Code scratch · 112 MB", @"14 processes under it · 820 MB"];
    NSMutableArray *missing = [NSMutableArray new];
    for (NSString *w in want) if (![all containsString:w]) [missing addObject:w];
    Check(!missing.count, @"window agents: the full story says what it does, where it is, its worktree and pull request, and what it holds", [missing componentsJoinedByString:@", "]);
    Check(![all containsString:@"…"] && ![all containsString:@"..."], @"window agents: the full story holds no ellipsis", @"");

    // Go to and the three links are real buttons, each where its fact stands, none over another or past the middle.
    NSArray<MMWindowButton *> *presses = middle.storyPresses;
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    BOOL inside = YES, apart = YES;
    for (MMWindowButton *b in presses) {
        [names addObject:b.accessibilityLabel ?: @""];
        if (!NSContainsRect(middle.bounds, b.frame)) inside = NO;
        for (MMWindowButton *o in presses) if (o != b && NSIntersectsRect(o.frame, b.frame)) apart = NO;
    }
    Check(presses.count == 4 && [names containsObject:@"Go to cmux"] && [names containsObject:@"Worktree barkbot · lane-c"] && [names containsObject:@"Server :5175 Vite"]
          && [names containsObject:@"Cache Claude Code scratch · 112 MB"] && inside && apart,
          @"window agents: Go to and a press for its worktree, server and cache, inside the middle and apart", [names componentsJoinedByString:@", "]);

    // A press on the worktree makes that row the active one, and the middle tells its story.
    MMWindowButton *tree = nil;
    for (MMWindowButton *b in presses) if ([b.identifier isEqualToString:@"worktree:lane-c"]) tree = b;
    [tree performClick:nil];
    Check([v.activeRow isEqualToString:@"worktree:lane-c"] && [middle.row.key isEqualToString:@"worktree:lane-c"],
          @"window agents: a press on its worktree makes that row active and shows its story", v.activeRow ?: @"none");
    v.activeRow = nil;

    // The sparse story leaves out what is not known and guesses nothing.
    v.pointedRow = @"agent:2";
    NSString *sparse = [CachesDrawn(middle) componentsJoinedByString:@" | "];
    BOOL none = YES;
    for (NSString *label in @[@"Recently", @"Runs in", @"Worktree", @"Pull request", @"Cache", @"Processes", @"Last active"]) if ([sparse containsString:label]) none = NO;
    Check([sparse containsString:@"Idle."] && [sparse containsString:@"Codex"] && none && middle.storyPresses.count == 0,
          @"window agents: the sparse story says only what is known, with no press", sparse);
    v.pointedRow = nil;
}
