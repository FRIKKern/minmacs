// The checks that came from the owner's first look at the real menu window, issue #62. tools/render.m includes this
// file, so it is part of the render tool and uses its Check. It is not built on its own.

static NSArray<MMWindowListView *> *WindowLists(NSView *v) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *sub in v.subviews) {
        if ([sub isKindOfClass:MMWindowListView.class]) [out addObject:sub];
        [out addObjectsFromArray:WindowLists(sub)];
    }
    return out;
}

/// What the first look at the real window found, each as a check: no row's name is cut, a young hour draws no line,
/// an empty group says so, the top band folds away when nobody asks, and a group rests on a whole row.
static void WindowLookChecks(void) {
    for (NSString *name in @[@"busy", @"peak", @"young", @"calm", @"long"]) {
        MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        MMWindowModel *m = MMWindowFixture(name);
        v.model = m;
        NSMutableArray<NSString *> *drawn = [NSMutableArray new], *whole = [NSMutableArray new], *bad = [NSMutableArray new];
        for (MMWindowListView *l in WindowLists(v)) [drawn addObjectsFromArray:l.drawnNames];
        for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) [whole addObjectsFromArray:[g.rows valueForKey:@"shownName"]];
        NSInteger shortened = 0;
        for (NSUInteger i = 0; i < drawn.count && i < whole.count; i++) {
            NSString *d = drawn[i], *w = whole[i];
            if ([d isEqualToString:w]) continue;
            shortened++;
            // A shortened name is whole words from the start of the real one, with no ellipsis.
            BOOL words = d.length >= 8 && [w hasPrefix:d] && [@" -/._" containsString:[w substringWithRange:NSMakeRange(d.length, 1)]];
            if (!words || [d containsString:@"…"] || [d containsString:@"..."]) [bad addObject:[NSString stringWithFormat:@"%@ -> %@", w, d]];
        }
        for (NSString *d in drawn) if ([d containsString:@"…"]) [bad addObject:d];
        BOOL isLong = [name isEqualToString:@"long"];
        Check(drawn.count == whole.count && drawn.count > 0 && bad.count == 0 && (isLong ? shortened >= 1 && shortened <= 4 : shortened == 0),
              [NSString stringWithFormat:@"window %@: no row's name is cut with an ellipsis%@", name, isLong ? @", and a name longer than the row loses whole words only" : @", and every name is whole"],
              [NSString stringWithFormat:@"%ld shortened of %lu. %@", (long)shortened, (unsigned long)drawn.count, [bad componentsJoinedByString:@" | "]]);
    }

    // The hour: one minute draws no line and twelve draw the filled part, with honest ends.
    NSInteger a, b, n;
    MMWindowModel *young = MMWindowFixture(@"young"), *calm = MMWindowFixture(@"calm"), *busy = MMWindowFixture(@"busy");
    NSArray *span = MMWindowHourSpan(young.memoryHour.values, &a, &b, &n);
    Check(span == nil && n == 1 && b == 59, @"window young: one filled minute is no line, and the newest value is still there", [NSString stringWithFormat:@"%ld filled", (long)n]);
    span = MMWindowHourSpan(calm.memoryHour.values, &a, &b, &n);
    Check(span.count == 12 && a == 48 && b == 59, @"window calm: twelve filled minutes draw as twelve, from 11 min ago to now", [NSString stringWithFormat:@"%lu values from %ld to %ld", (unsigned long)span.count, (long)a, (long)b]);
    span = MMWindowHourSpan(busy.memoryHour.values, &a, &b, &n);
    Check(span.count == 60 && a == 0, @"window busy: a full hour draws all sixty minutes", @"");
    BOOL rowLine = NO;
    for (MMWindowGroup *g in young.memoryGroups) for (MMWindowRow *r in g.rows) if (MMWindowHourSpan(r.hour, NULL, NULL, NULL)) rowLine = YES;
    Check(!rowLine && MMWindowHourLeast == 5, @"window young: no row shows an hour line before five filled minutes", @"");

    // Nobody asks, nothing on disk, nothing to fix.
    Check(young.asks == nil && young.fixCount == 0 && young.diskGroups.count == 2 && young.diskGroups[0].rows.count == 0 && young.diskGroups[1].rows.count == 0 &&
          [young.diskGroups[0].emptyNote isEqualToString:@"No worktrees found"] && [young.diskGroups[1].emptyNote isEqualToString:@"No caches or leftovers found"],
          @"window young: nobody asks, nothing to fix, and each empty disk group says so in words", @"");
    Check(calm.fixCount == 0 && calm.memoryBackToday > 0 && calm.diskBackToday > 0 && young.memoryBackToday == 0 && young.diskBackToday == 0,
          @"window calm: nothing to fix, with memory and disk back today as two numbers", @"");
    for (NSArray<MMWindowGroup *> *side in @[busy.memoryGroups, busy.diskGroups]) for (MMWindowGroup *g in side)
        Check(g.emptyNote.length > 0, [NSString stringWithFormat:@"window: the %@ group has words for when it is empty", g.key], @"");

    // The top band folds away when nobody asks, and the window keeps its size.
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.model = busy;
    CGFloat with = WindowLists(v).firstObject.frame.size.height, top = WindowLists(v).firstObject.superview.frame.origin.y;
    v.model = young;
    MMWindowListView *left = WindowLists(v).firstObject;
    Check(with == 538 && top == 40 && left.frame.size.height == 566 && left.superview.frame.origin.y == 12 && NSEqualSizes(v.frame.size, MMWindowSize),
          @"window: with nobody asking the top band folds away and the lists get its height", [NSString stringWithFormat:@"%g then %g", with, left.frame.size.height]);
    v.model = busy;
    Check(WindowLists(v).firstObject.frame.size.height == 538, @"window: the band comes back when an agent asks", @"");

    // A group rests on a whole row: after the pointer goes to its last row, and at its top once the window closed.
    left = WindowLists(v).firstObject;
    BOOL atTop = YES, wholeRow = YES;
    for (NSNumber *o in left.offsets.allValues) if (o.doubleValue != 0) atTop = NO;
    for (MMWindowGroup *g in busy.memoryGroups) [left reveal:g.rows.lastObject.key];
    for (NSNumber *o in left.offsets.allValues) if (o.doubleValue <= 0 || fmod(o.doubleValue, 24) != 0) wholeRow = NO;
    Check(atTop && wholeRow && left.offsets.count == 3, @"window: every group opens at its first row, and scrolled to its end it still rests on a whole row",
          [left.offsets.allValues componentsJoinedByString:@" "]);
    [left rest];
    Check(left.offsets.count == 0, @"window: a closed window forgets its scrolling, so it opens at the top again", @"");
}
