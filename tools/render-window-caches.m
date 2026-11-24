// Near-identical rows as one, DESIGN rule 16. The owner wrote: "We need smarter way to deal with the cache, its much
// the same and feels like spam right now." Caches held 169 rows of one registry row, each "657 old and empty". These
// checks hold the made-up day "caches", which has them, to one row with its totals, its story and whole rows.
// tools/render.m includes this file after render-window-projects.m, whose helpers it uses. It is not built on its own.

/// Every string a view draws, in order.
static NSArray<NSString *> *CachesDrawn(NSView *v) {
    NSMutableArray<NSString *> *seen = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) { if (text.length) [seen addObject:text]; });
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:[v bitmapImageRepForCachingDisplayInRect:v.bounds]];
    MMWindowWatchDraws(nil);
    return seen;
}

static void WindowCachesChecks(void) {
    MMWindowModel *m = MMWindowFixture(@"caches");
    MMWindowGroup *caches = m.diskGroups[1];
    MMWindowRow *fam = [m row:@"kin:noonoo:tmpdir-families"], *scratch = [m row:@"kin:noonoo:claude-code-scratch"];
    uint64_t sum = 0;
    for (MMWindowRow *r in fam.members) sum += r.bytes;
    Check(caches.rows.count == 7 && fam.members.count == 169 && scratch.members.count == 4 && fam.bytes == sum && [fam.name isEqualToString:@"Temp folders left by tools"],
          @"window caches: 169 temp-folder families are one row named in plain words, its size their sum, and four sessions' scratch another",
          [NSString stringWithFormat:@"%lu rows, %lu and %lu members, %@", (unsigned long)caches.rows.count, (unsigned long)fam.members.count, (unsigned long)scratch.members.count, fam.name]);
    Check([fam.state isEqualToString:@"in use"] && fam.inFix && !fam.quiet && [scratch.state isEqualToString:@"in use"],
          @"window caches: one row's word is in use when a member is, and it still goes with Fix Everything for the rest", fam.state ?: @"none");
    Check(MMWindowFixture(@"busy").diskGroups[1].rows.count == 5 && ![MMWindowFixture(@"busy") row:@"kin:noonoo:tmpdir-families"],
          @"window caches: the busy day, with no kin of three, shows each cache as before", @"");
    NSString *line = MMWindowRowSecondLine(fam, 280), *line2 = MMWindowRowSecondLine(scratch, 280);
    Check([line isEqualToString:@"45,282 folders in 169 groups"] && [line2 isEqualToString:@"4 sessions"],
          @"window caches: the row's second line is its totals", [NSString stringWithFormat:@"%@ / %@", line, line2]);

    // The story: the split after the lead, the facts, and the biggest members under a hairline.
    MMWindowView *v = PolishView(@"caches");
    v.pointedRow = fam.key;
    NSArray<NSString *> *told = CachesDrawn(WordViews(v, MMWindowMiddleView.class).firstObject);
    NSString *all = [told componentsJoinedByString:@" | "];
    BOOL members = [told containsObject:@"The 5 biggest of its 169 groups"] && [told containsObject:@"MMArgs-* folders"] && [told containsObject:@"MMRepoIndex-* folders"];
    BOOL split = [all containsString:@"Goes with Fix Everything."] && [all containsString:@"166 groups can go, 3 in use."];
    BOOL why = [told containsObject:@"Why some stay"] && [told containsObject:@"a running process has a file open in it"] && [told containsObject:@"45,282 folders in 169 groups"];
    BOOL usedIn = [all containsString:@"MMSizer-* folders · in use"];
    Check(members && split && why && usedIn, @"window caches: the story says how many can go, why the rest stay, and names the five biggest with their words", all);
    Check(![all containsString:@"…"] && ![all containsString:@"..."], @"window caches: the story holds no ellipsis", @"");

    // Members that share the row's own name are told apart by the session they are for.
    v.pointedRow = scratch.key;
    NSArray<NSString *> *scratchTold = CachesDrawn(WordViews(v, MMWindowMiddleView.class).firstObject);
    Check([scratchTold containsObject:@"Its 4 sessions"] && [scratchTold containsObject:@"session 3f9a21c0"] && [scratchTold containsObject:@"session c02f9e1a · in use"],
          @"window caches: members with one name are named by their session in the story", [scratchTold componentsJoinedByString:@" | "]);
    v.pointedRow = fam.key;

    // The list: each row whole, the family row among the first, the 169 never drawn one by one.
    MMWindowListView *disk = WindowLists(v).lastObject;
    NSArray<NSString *> *shown = [disk shownKeys:1];
    NSInteger families = 0;
    for (NSString *n in disk.drawnNames) if ([n hasSuffix:@"-* folders"]) families++;
    Check([shown containsObject:fam.key] && families == 0, @"window caches: the list shows the one row and none of its members",
          [NSString stringWithFormat:@"%@ %ld", [shown componentsJoinedByString:@","], (long)families]);
    NSArray *tops = disk.rowTops[1];
    CGFloat box = disk.groupFrames[1].rectValue.size.height - 24;
    BOOL whole = NO;
    for (NSNumber *t in tops) if (fabs(t.doubleValue - box) < 0.5 || box >= [tops.lastObject doubleValue] - 0.5) whole = YES;
    Check(whole, @"window caches: the Caches group ends on a whole row", [NSString stringWithFormat:@"box %g, rows end at %@", box, [tops componentsJoinedByString:@","]]);
}
