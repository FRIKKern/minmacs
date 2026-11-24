// A worktree's story with its git in plain words and its pull request, as the person's gh told it, DESIGN rule 2.
// The busy day's worktrees are given what the feed writes for them, Shell/MMWindowRows.m: the last commit, where the
// branch stands against main, who made it, and a pull request open with checks passing, merged, none, or still being
// looked for. tools/render.m includes this file. It is not built on its own.

/// The busy day, with one worktree's story told as the feed tells it now. which: open, merged, none, looking.
static MMWindowModel *PullsModel(NSString *which, NSString **key) {
    MMWindowModel *m = MMWindowFixture(@"busy");
    NSDictionary *rows = @{@"open": @"worktree:dogfood", @"merged": @"worktree:fix-auth-redirect", @"none": @"worktree:media-scope", @"looking": @"worktree:speed-3-base"};
    *key = rows[which];
    MMWindowRow *row = [m row:*key];
    BOOL merged = [which isEqualToString:@"merged"];
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    for (MMWindowFact *f in row.facts) {
        [facts addObject:f];
        if (![f.label isEqualToString:@"Branch"]) continue;
        // Under the branch, as the feed orders them.
        NSArray *git = merged ? @[MMWindowFactLastCommit(@"Send the person back where they came from after login", @"9f3c2a1be04d", 6 * 86400 + 400),
                                  MMWindowFactMerged(@"squash", @"origin/main"), MMWindowFactRemote(@"gone")]
                              : @[MMWindowFactLastCommit(@"Read the review answer before the plan runs", @"4be81c07aa52", 40),
                                  MMWindowFactAgainst(3, 1, @"origin/main")];
        for (MMWindowFact *g in git) if (g) [facts addObject:g];
    }
    MMWindowFact *made = MMWindowFactMadeBy(@"claude-code", merged ? nil : @"Tune the ranking");
    [facts insertObject:made atIndex:MAX((NSInteger)facts.count - 1, 0)];
    row.facts = facts;
    MMWindowPull *p = [MMWindowPull new];
    if ([which isEqualToString:@"open"]) {
        p.known = MMWindowPullFound; p.number = 142; p.state = @"open"; p.review = @"review requested"; p.checksPassing = 6;
        p.title = @"Read the review answer before the plan runs, and say so in the log"; p.url = @"https://github.com/acme/minmacs/pull/142";
    } else if (merged) {
        p.known = MMWindowPullFound; p.number = 98; p.state = @"merged"; p.mergedAgo = 2 * 86400 + 300;
        p.title = @"Fix the auth redirect"; p.url = @"https://github.com/acme/atlas/pull/98";
    } else if ([which isEqualToString:@"none"]) p.known = MMWindowPullNone;
    else p.known = MMWindowPullLooking;
    row.pull = p;
    return m;
}

static NSString *PullsYN(BOOL b) { return b ? @"yes" : @"no"; }

static MMWindowMiddleView *PullsMiddle(MMWindowView *v) { return WordViews(v, MMWindowMiddleView.class).firstObject; }

static void RenderWindowPulls(NSString *dir, NSDictionary<NSString *, NSAppearance *> *appearances, NSMutableArray *unwritten) {
    for (NSString *mode in @[@"dark", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        if (!ap) continue;
        MMWindowForceContrast([mode hasPrefix:@"contrast"]);
        for (NSString *which in @[@"open", @"merged", @"none", @"looking"]) {
            NSString *key = nil;
            MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
            v.drawsBacking = YES;
            v.model = PullsModel(which, &key);
            v.pointedRow = key;
            NSString *path = [dir stringByAppendingFormat:@"/busy-pr-%@-%@.png", which, mode];
            if (!MMRenderView(v, path, ap)) [unwritten addObject:path.lastPathComponent];
        }
        MMWindowForceContrast(NO);
    }
}

static void WindowPullsChecks(void) {
    NSMutableArray<NSString *> *bad = [NSMutableArray new], *told = [NSMutableArray new];
    for (NSString *which in @[@"open", @"merged", @"none", @"looking"]) {
        NSString *key = nil;
        MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        MMWindowModel *m = PullsModel(which, &key);
        v.model = m;
        v.pointedRow = key;
        MMWindowMiddleView *middle = PullsMiddle(v);
        MMWindowRow *row = [m row:key];
        NSMutableArray<NSString *> *lines = [NSMutableArray new];
        NSMutableArray<NSValue *> *rects = [NSMutableArray new];
        __block BOOL cut = NO;
        MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
            [lines addObject:text];
            if (![text isEqualToString:MMWindowOpenPull]) [rects addObject:[NSValue valueWithRect:used]];
            if ([text hasSuffix:@"…"] || [text hasSuffix:@"..."]) cut = YES;
            if (!NSIsEmptyRect(allowed) && NSMaxX(used) > NSMaxX(allowed) + 0.5) cut = YES;
        });
        NSBitmapImageRep *rep = [middle bitmapImageRepForCachingDisplayInRect:middle.bounds];
        [middle cacheDisplayInRect:middle.bounds toBitmapImageRep:rep];
        MMWindowWatchDraws(nil);
        NSString *all = [lines componentsJoinedByString:@" | "];
        BOOL wantsPress = [which isEqualToString:@"open"] || [which isEqualToString:@"merged"];
        BOOL press = !middle.pullButton.hidden && [middle.pullButton.title isEqualToString:MMWindowOpenPull];
        BOOL inside = !press || NSContainsRect(middle.bounds, middle.pullButton.frame);
        BOOL clear = YES;
        for (NSValue *r in rects) if (press && NSIntersectsRect(r.rectValue, NSInsetRect(middle.pullButton.frame, 1, 1))) clear = NO;
        if (cut || press != wantsPress || !inside || !clear || ![all containsString:row.pull.line])
            [bad addObject:[NSString stringWithFormat:@"%@: cut %@ press %@ inside %@ clear %@", which, PullsYN(cut), PullsYN(press), PullsYN(inside), PullsYN(clear)]];
        [told addObject:row.pull.line];
        if ([which isEqualToString:@"open"] && !([all containsString:@"3 ahead, 1 behind main"] && [all containsString:@"Claude Code · Tune the ranking"] && [all containsString:@"4be81c0"]))
            [bad addObject:@"open: the git facts are not all drawn"];
        if ([which isEqualToString:@"merged"] && !([all containsString:@"Squash-merged into main"] && [all containsString:@"Branch deleted on the remote"]))
            [bad addObject:@"merged: the merge and the remote are not drawn"];
    }
    Check(!bad.count, @"window pull requests: the story draws the pull request's line whole, its title, and Open pull request where there is a page, over no other text",
          [bad componentsJoinedByString:@"; "]);
    Check([told isEqualToArray:@[@"PR #142 · open · checks passing · review requested", @"PR #98 · merged 2 d ago", @"No pull request for this branch", @"Looking for a pull request"]],
          @"window pull requests: open with checks passing, merged with when, none and looking, in plain words", [told componentsJoinedByString:@" | "]);
    // The press is for the active row's story too, and the story asks the host once a row, not at every model.
    NSString *key = nil;
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.model = PullsModel(@"open", &key);
    MMWindowMiddleView *middle = PullsMiddle(v);
    __block NSMutableArray<NSString *> *asked = [NSMutableArray new];
    middle.onStory = ^(NSString *k) { [asked addObject:k ?: @"none"]; };
    v.pointedRow = key;
    v.model = PullsModel(@"open", &key);
    v.pointedRow = nil;
    Check([asked isEqualToArray:@[key, @"none"]], @"window pull requests: a story tells the host its row once, and when it goes", [asked componentsJoinedByString:@" | "]);
    // The words the window may show, held to the banned list: no ellipsis, no aside, no old app name.
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *which in @[@"open", @"merged", @"none", @"looking"]) {
        MMWindowModel *m = PullsModel(which, &key);
        for (NSString *s in [MMWindowView shownStrings:m]) if ([s rangeOfString:@"…"].location != NSNotFound || [s rangeOfString:@"("].location != NSNotFound) [words addObject:s];
    }
    Check(!words.count, @"window pull requests: no shown string holds an ellipsis or an aside", [words componentsJoinedByString:@" | "]);
}
