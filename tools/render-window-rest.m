// The rest of the memory, "macOS and background". The owner wrote: "What is left of the memory. Please be smart about
// it, I know a lot of processes in there. Categorize it well so it is not spammy. Make it feel beautiful and give the
// user an oversight." These checks hold the made-up days "rest", "rest-calm" and "rest-growing", the measured 16 GB Mac
// of many agents, to calm category rows, a story that lists processes whole, and a ring of eight slices at most.
// tools/render.m includes this file after render-window-caches.m, whose helpers it uses. It is not built on its own.
#import "UI/Window/MMWindowTree.h"
#import "UI/Window/MMWindowInsides.h"

static NSArray<NSArray *> *WindowRestShots(void) {
    return @[@[@"rest", @"main", @""], @[@"rest", @"macos", @"rest:macos"], @[@"rest", @"spotlight", @"rest:spotlight"],
             @[@"rest", @"browsers", @"rest:browsers"], @[@"rest-calm", @"main", @""], @[@"rest-growing", @"main", @""],
             @[@"rest-growing", @"spotlight", @"rest:spotlight"]];
}

static MMWindowGroup *RestGroupOf(MMWindowModel *m) {
    for (MMWindowGroup *g in m.memoryGroups) if ([g.key isEqualToString:MMWindowRestGroup]) return g;
    return nil;
}

static void WindowRestChecks(void) {
    MMWindowModel *m = MMWindowFixture(@"rest");
    MMWindowGroup *rest = RestGroupOf(m);
    Check(rest && [rest.title isEqualToString:@"macOS and background"] && rest.rows.count == 11 && [rest.rows.lastObject.key isEqualToString:MMWindowRestElseKey],
          @"window rest: macOS and background has one row a category, Everything else last", [NSString stringWithFormat:@"%lu rows", (unsigned long)rest.rows.count]);
    BOOL busiest = YES;
    for (NSUInteger i = 1; i + 1 < rest.rows.count; i++) if (rest.rows[i].bytes > rest.rows[i - 1].bytes) busiest = NO;
    Check(busiest, @"window rest: the categories come busiest first", [[rest.rows valueForKey:@"name"] componentsJoinedByString:@", "]);
    BOOL calm = YES;
    for (MMWindowRow *r in rest.rows) if (![r.state isEqualToString:MMWindowRestCountWord(MMWindowRestProcessCount(r))]) calm = NO;
    Check(calm, @"window rest: a calm category's quiet word is its count", @"");
    MMWindowRow *grew = [MMWindowFixture(@"rest-growing") row:@"rest:spotlight"];
    Check([grew.state isEqualToString:@"up 1.4 GB"] && [[grew.facts.firstObject value] isEqualToString:@"up 1.4 GB this hour"], @"window rest: a category that grew fast says so, quietly, in its count's place", grew.state ?: @"none");

    // The ring: eight slices at most, the smallest merged into Everything else.
    NSArray<MMWindowSlice *> *arcs = MMWindowRestArcs(rest.rows);
    uint64_t sum = 0, all = 0;
    for (MMWindowSlice *s in arcs) sum += s.bytes;
    for (MMWindowRow *r in rest.rows) all += r.bytes;
    Check(arcs.count <= 8 && arcs.count == 8 && sum == all && [arcs.lastObject.group isEqualToString:MMWindowRestElseKey],
          @"window rest: the ring gives the rest 8 slices at most, the smallest merged into Everything else, with nothing lost",
          [NSString stringWithFormat:@"%lu slices", (unsigned long)arcs.count]);

    // The story: its sentence, its facts and its processes, biggest first, folded, whole, at most 12 and a tail.
    MMWindowView *v = PolishView(@"rest");
    v.pointedRow = @"rest:spotlight";
    NSArray<NSString *> *told = CachesDrawn(WordViews(v, MMWindowMiddleView.class).firstObject);
    NSString *all2 = [told componentsJoinedByString:@" | "];
    Check([told containsObject:@"Spotlight and its indexers, which read new and changed files so search finds them."] && [told containsObject:@"12 Spotlight indexers"]
          && [all2 containsString:@"Its 18 processes, biggest first"] && [all2 containsString:@"3 that macOS runs as another user, not measured"],
          @"window rest: a category's story says what it is, then its processes, alike ones folded", all2);
    v.pointedRow = @"rest:macos";
    told = CachesDrawn(WordViews(v, MMWindowMiddleView.class).firstObject);
    all2 = [told componentsJoinedByString:@" | "];
    NSInteger lines = 0;
    MMWindowRow *mac = [m row:@"rest:macos"];
    for (MMWindowRow *line in MMWindowRestListOf(mac, MMWindowRestMostLines).lines) if ([told containsObject:line.name]) lines++;
    Check(lines >= 8 && lines <= 12 && [all2 containsString:@"Kernel and system memory"] && [all2 containsString:@"and "] && [all2 containsString:@"280 that macOS runs as another user"],
          @"window rest: macOS's story lists at most 12 lines with the kernel's own, then what is left in one line", all2);
    Check(![all2 containsString:@"…"] && ![all2 containsString:@"..."], @"window rest: the story holds no ellipsis", @"");

    // Room: the left side shows each group's first rows, and the rest says how many more wait.
    MMWindowListView *left = WindowLists(v).firstObject;
    NSArray<NSString *> *shown = [left shownKeys:3];
    Check(shown.count >= 1 && shown.count < rest.rows.count && [shown.firstObject isEqualToString:rest.rows.firstObject.key],
          @"window rest: with too little room the group shows its biggest categories and how many more", [shown componentsJoinedByString:@","]);

    // VoiceOver reads each category with its size and count.
    NSString *spoken = nil;
    for (NSAccessibilityElement *el in left.accessibilityChildren) if ([el.accessibilityLabel hasPrefix:@"macOS and background, Spotlight"]) spoken = el.accessibilityLabel;
    Check([spoken containsString:@"18 processes"] && [spoken containsString:@"MB"], @"window rest: VoiceOver reads a category with its size and count", spoken ?: @"none");
    MMWindowView *g = PolishView(@"rest-growing");
    MMWindowListView *gl = WindowLists(g).firstObject;
    spoken = nil;
    for (NSAccessibilityElement *el in gl.accessibilityChildren) if ([el.accessibilityLabel hasPrefix:@"macOS and background, Spotlight"]) spoken = el.accessibilityLabel;
    Check([spoken containsString:@"up 1.4 GB"] && [spoken containsString:@"18 processes"], @"window rest: VoiceOver reads a grown category's count too", spoken ?: @"none");

    // The calm day: fewer categories, every one calm.
    MMWindowGroup *calmRest = RestGroupOf(MMWindowFixture(@"rest-calm"));
    Check(calmRest.rows.count == 7 && MMWindowRestArcs(calmRest.rows).count == 7, @"window rest-calm: seven categories, seven slices", @"");
}

/// A category open in the list's tree, MMWindowTree.h: Spotlight with its lines, the twelve indexers open under it,
/// and the pointer on one indexer, whose story tells its own details. rest-open-*.png.
static void RenderWindowRestOpen(NSString *dir, NSDictionary<NSString *, NSAppearance *> *appearances, NSMutableArray *unwritten) {
    for (NSString *mode in @[@"dark", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        if (!ap) continue;
        MMWindowForceContrast([mode hasPrefix:@"contrast"]);
        MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        v.drawsBacking = YES;
        v.model = MMWindowFixture(@"rest");
        MMWindowTreeSetOpen(@"rest:spotlight", YES); MMWindowTreeSetOpen(@"insides:rest:spotlight|Spotlight indexer", YES);
        [v treeShow];
        MMWindowListView *left = WindowLists(v).firstObject;
        [left reveal:@"rest:spotlight"];
        MMWindowRow *one = MMWindowInsidesFind(v.model, @"insides:rest:spotlight|Spotlight indexer").members.firstObject;
        v.pointedRow = one.key;
        NSString *path = [dir stringByAppendingFormat:@"/rest-open-%@.png", mode];
        if (!MMRenderView(v, path, ap)) [unwritten addObject:path.lastPathComponent];
        MMWindowForceContrast(NO);
    }
    MMWindowTreeCloseAll();
}

static void WindowRestTreeChecks(void) {
    MMWindowModel *m = MMWindowFixture(@"rest");
    MMWindowRow *spot = [m row:@"rest:spotlight"], *fold = [m row:@"insides:rest:spotlight|Spotlight indexer"];
    NSArray<MMWindowRow *> *kids = MMWindowRowInsides(spot);
    Check(MMWindowTreeOpens(spot) && kids.count == 4 && fold && MMWindowRowInsides(fold).count == 12 && MMWindowRowDepth(MMWindowRowInsides(fold).firstObject) == 2,
          @"window rest: a category opens in the list into its lines, and a fold into the processes it stands for",
          [NSString stringWithFormat:@"%lu %lu", (unsigned long)kids.count, (unsigned long)MMWindowRowInsides(fold).count]);
    MMWindowRow *mac = [m row:@"rest:macos"];
    NSArray<MMWindowRow *> *macKids = MMWindowRowInsides(mac);
    Check(macKids.count == MMWindowRestMostLines + 1 && [macKids.lastObject.name hasSuffix:@"smaller processes"],
          @"window rest: macOS opens into 12 lines and one quiet row for the smaller ones", macKids.lastObject.name ?: @"none");
    MMWindowView *v = PolishView(@"rest");
    MMWindowTreeSetOpen(@"rest:spotlight", YES);
    [v treeShow];
    NSArray<NSString *> *keys = WindowLists(v).firstObject.rowKeys;
    NSUInteger at = [keys indexOfObject:@"rest:spotlight"];
    Check(at != NSNotFound && at + 1 < keys.count && [keys[at + 1] hasPrefix:@"insides:rest:spotlight|"], @"window rest: open, its lines stand right under the category", @"");
    MMWindowTreeCloseAll();
}
