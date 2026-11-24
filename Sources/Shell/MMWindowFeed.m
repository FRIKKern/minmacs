// The window's model from one snapshot, MMWindowFeed.h. Facts only: a value Core does not hold is left out.
#import "Shell/MMWindowFeed.h"
#import "UI/MMFormat.h"

static NSString *const kApps = @"apps", *const kCaches = @"caches";

NSArray *MMWindowRingHour(MMHistoryRing *ring) {
    if (!ring) return nil;
    NSMutableArray *v = [NSMutableArray arrayWithCapacity:MMHistoryMinutes];
    for (NSUInteger i = 0; i < MMHistoryMinutes; i++) {
        MMHistoryMinute m = [ring minuteAt:i];
        if (!m.passes || m.megabytes < 0) [v addObject:NSNull.null];
        else [v addObject:@((uint64_t)((double)m.megabytes * 1048576.0))];
    }
    return v;
}

static MMWindowHour *Hour(MMHistoryRing *ring, MMWindowSide side, NSString *title, NSString *explain) {
    NSArray *values = MMWindowRingHour(ring);
    if (!values) return nil;
    MMWindowHour *h = [MMWindowHour new];
    h.side = side; h.title = title; h.explain = explain; h.values = values;
    return h;
}

static MMWindowHour *Week(NSArray *values, MMWindowSide side, NSTimeInterval firstAt, uint64_t whole) {
    if (!values) return nil;
    BOOL disk = side == MMWindowDisk;
    MMWindowHour *h = [MMWindowHour new];
    h.side = side; h.title = MMWindowHourTitle(disk); h.explain = MMWindowHourExplain(disk, whole); h.values = values; h.firstAt = firstAt;
    return h;
}

#pragma mark - Fixes

static NSString *TreeName(MMWrapUpPlan *plan) {
    NSString *branch = plan.subject.worktree.branch;
    return branch.length ? branch : plan.subject.path.lastPathComponent ?: @"";
}

NSString *MMWindowFixTitle(MMPerformanceFix *fix) { return MMWindowFixTitleShown(fix, (NSInteger)fix.actions.count); }

NSString *MMWindowFixTitleShown(MMPerformanceFix *fix, NSInteger n) {
    NSString *kind = fix.kind;
    if ([kind isEqualToString:@"wrapup"]) return [@"Wrap Up " stringByAppendingString:TreeName(fix.wrapUp)];
    // One cleanup is named by what it cleans. The rest count what they act on, worded in the model.
    if ([kind isEqualToString:@"clean"] && n == 1 && fix.actions.count == 1) return [@"Clean " stringByAppendingString:MMWindowNameOf(fix.actions.firstObject.finding)];
    return MMWindowFixCountTitle(kind ?: @"", n) ?: MMCapitalized(kind ?: @"");
}

#pragma mark - The model

/// Biggest first, then by key, so the order holds between snapshots. A tabs row has no bytes and sorts by its tabs
/// among the rows with none. A row whose size is not measured yet has no number to sort by and comes after the rest.
static NSArray<MMWindowRow *> *Sorted(NSArray<MMWindowRow *> *rows) {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
}

/// Helpers of one name left by one worktree stand as one row only when no one's process tree holds another's, so their
/// memory adds up: one that does keeps its kin's rows apart. Without a sample nothing says, and they stay apart.
static void HelpersApart(NSArray<MMWindowRow *> *rows, NSDictionary<NSString *, MMFinding *> *findings, MMSample *sample) {
    NSMutableDictionary<NSString *, NSMutableArray<MMWindowRow *> *> *by = [NSMutableDictionary new];
    for (MMWindowRow *r in rows) if (r.kind == MMWindowHelper && r.kin) {
        if (!by[r.kin.key]) by[r.kin.key] = [NSMutableArray new];
        [by[r.kin.key] addObject:r];
    }
    for (NSString *k in by) {
        NSArray<MMWindowRow *> *kin = by[k];
        if ((NSInteger)kin.count < MMWindowCollapseLeast) continue;
        BOOL apart = sample != nil;
        NSMutableSet<NSNumber *> *seen = [NSMutableSet new];
        for (MMWindowRow *r in kin) {
            MMFinding *f = findings[r.key];
            if (!apart || !f.procs.count) { apart = NO; break; }
            for (NSValue *v in f.procs) {
                MMProcKey pk = {0, 0};
                [v getValue:&pk size:sizeof pk];
                for (NSNumber *t in [sample treeOf:pk.pid limit:500]) {
                    if ([seen containsObject:t]) { apart = NO; break; }
                    [seen addObject:t];
                }
            }
        }
        if (!apart) for (MMWindowRow *r in kin) r.kin = nil;
    }
}

static MMWindowGroup *Group(NSString *key, NSString *title, MMWindowLooked looked, MMWindowSide side, NSArray<MMPerformanceGroup *> *from,
                            NSArray<NSString *> *keys, MMSnapshot *s, NSSet<NSString *> *inFix) {
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMFinding *> *findings = [NSMutableDictionary new];
    for (MMPerformanceGroup *g in from) {
        if (![keys containsObject:g.key]) continue;
        for (MMPerformanceRow *r in g.rows) {
            MMWindowRow *row = MMWindowRowFrom(r, s);
            row.inFix = [inFix containsObject:r.key];
            // The quiet word for what Fix Everything ends, where no fact gave a word of its own.
            if (row.inFix && !row.state && (row.kind == MMWindowApp || row.kind == MMWindowTabs)) row.state = @"will close";
            // A helper may go when Fix Everything ends it.
            if (row.kind == MMWindowHelper) row.kin.canGo = row.inFix;
            if (r.finding) findings[row.key] = r.finding;
            [rows addObject:row];
        }
    }
    HelpersApart(rows, findings, s.facts.sample);
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = key; g.title = title; g.emptyNote = MMWindowEmptyNote(key, looked); g.side = side;
    // The worktrees come by project, the most active first: the owner asked for the most active of each project.
    g.byProject = [key isEqualToString:MMPerformanceWorktrees];
    // Rows that read alike stand as one, DESIGN rule 16, and that row sorts by its size among the others.
    g.rows = g.byProject ? MMWindowByProject(rows) : Sorted(MMWindowCollapsed(rows));
    return g;
}

/// The ring's slices in ring order. The window has one group for apps and helpers, so their parts are one slice.
static NSArray<MMWindowSlice *> *Slices(MMPerformanceSideRing *ring) {
    NSMutableArray<MMWindowSlice *> *out = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMWindowSlice *> *by = [NSMutableDictionary new];
    for (NSString *k in ring.order) {
        NSString *key = [k isEqualToString:MMPerformanceHelpers] || [k isEqualToString:MMPerformanceTabsGroup] ? kApps
                      : [k isEqualToString:MMPerformanceClutter] ? kCaches : k;
        MMWindowSlice *x = by[key];
        if (!x) { x = [MMWindowSlice new]; x.group = key; by[key] = x; [out addObject:x]; }
        x.bytes += [ring.parts[k] unsignedLongLongValue];
    }
    return out;
}

MMWindowModel *MMWindowModelFrom(MMSnapshot *s, MMPerformance *p, MMWindowExtras *extras) {
    MMWindowModel *m = [MMWindowModel new];
    m.generation = s.generation;
    m.asks = MMWindowAsksLine(p.needsYou);

    // The ring. Memory and disk stay two numbers.
    MMWindowRing *ring = [MMWindowRing new];
    ring.memoryUsed = p.memory.used; ring.memoryTotal = p.memory.total;
    ring.diskTotal = p.disk.total; ring.diskFree = p.disk.total > p.disk.used ? p.disk.total - p.disk.used : 0;
    ring.memory = Slices(p.memory); ring.disk = Slices(p.disk);
    m.ring = ring;

    // The last hour of the whole Mac. Before the first fill there is no ring, and the window draws no line.
    MMHistoryView *h = s.history;
    m.memoryHour = Hour(h.mac, MMWindowMemory, MMWindowHourTitle(NO), MMWindowHourExplain(NO, ring.memoryTotal));
    m.diskHour = Hour(h.disk, MMWindowDisk, MMWindowHourTitle(YES), MMWindowHourExplain(YES, ring.diskTotal));
    // The last 7 days, one value an hour, as the controller read them from the log's points.
    m.stripWeek = extras.stripWeek;
    m.memoryWeek = Week(extras.memoryWeek, MMWindowMemory, extras.weekFirstAt, ring.memoryTotal);
    m.diskWeek = Week(extras.diskWeek, MMWindowDisk, extras.weekFirstAt, ring.diskTotal);

    // The mark says a press on Fix Everything acts on the row, so a fix that waits for its own press marks none.
    NSMutableSet<NSString *> *inFix = [NSMutableSet new];
    for (MMPerformanceFix *f in p.fixes) if (!f.needsYou) [inFix addObjectsFromArray:f.rows];

    // The groups. Apps, helpers and localhost tabs share one title, and each row keeps its own kind.
    m.memoryGroups = @[
        Group(MMPerformanceServers, @"Servers", MMWindowLookedDone, MMWindowMemory, p.memoryGroups, @[MMPerformanceServers], s, inFix),
        Group(MMPerformanceAgents, @"Agents", MMWindowLookedDone, MMWindowMemory, p.memoryGroups, @[MMPerformanceAgents], s, inFix),
        Group(kApps, @"Apps and helpers", MMWindowLookedDone, MMWindowMemory, p.memoryGroups,
              @[MMPerformanceApps, MMPerformanceHelpers, MMPerformanceTabsGroup], s, inFix)];
    // An empty disk group says what the look behind it gave: found none, still looking, or nothing to look in.
    m.diskGroups = @[
        Group(MMPerformanceWorktrees, @"Worktrees", extras.worktreesLooked, MMWindowDisk, p.diskGroups, @[MMPerformanceWorktrees], s, inFix),
        Group(kCaches, @"Caches", extras.cachesLooked, MMWindowDisk, p.diskGroups, @[MMPerformanceClutter], s, inFix)];

    // The fixes, in Fix Everything's order. A fix counts what it acts on as the window shows it: the members of a row
    // that stands for several, DESIGN rule 16, are that one row, though each member is still its own action and record.
    NSMutableDictionary<NSString *, NSString *> *shownAs = [NSMutableDictionary new];
    for (MMWindowGroup *g in [m.memoryGroups arrayByAddingObjectsFromArray:m.diskGroups])
        for (MMWindowRow *r in g.rows) for (MMWindowRow *member in r.members) shownAs[member.key] = r.key;
    NSMutableArray<MMWindowFix *> *fixes = [NSMutableArray new];
    for (MMPerformanceFix *f in p.fixes) {
        NSMutableSet<NSString *> *shown = [NSMutableSet new];
        for (NSString *k in f.rows) [shown addObject:shownAs[k] ?: k];
        MMWindowFix *x = [MMWindowFix new];
        x.key = f.key; x.title = MMWindowFixTitleShown(f, shown.count < f.rows.count ? (NSInteger)shown.count : (NSInteger)f.actions.count);
        x.memoryBack = f.memoryBack; x.diskBack = f.diskBack; x.needsYou = f.needsYou;
        // A fix that removes a thing not measured yet gives back more disk than its number holds, and says so.
        x.diskPartial = f.diskPartial;
        [fixes addObject:x];
    }
    m.fixes = fixes;
    // An agent's story names its worktrees, servers and caches by the rows the window shows for them.
    MMWindowResolveLinks(m);
    // The total counts each process once, though each fix shows its own.
    m.memoryBackOnce = @(p.memoryBackOnce);

    // What came back today, two numbers, for the dock when there is nothing to fix.
    m.memoryBackToday = p.lookBack.todayMemory; m.diskBackToday = p.lookBack.todayDisk;
    m.diskBackTodayPartial = p.lookBack.todayDiskPartial;

    m.run = extras.run;
    m.welcome = extras.welcome;
    m.log = extras.log;
    m.settings = MMWindowSettingsFrom(p, extras);
    return m;
}
