// The window's model from one snapshot, MMWindowFeed.h. Facts only: a value Core does not hold is left out.
#import "Shell/MMWindowFeed.h"
#import "UI/MMFormat.h"

static NSString *const kApps = @"apps", *const kCaches = @"caches";

/// "64 GB" of memory, in binary units as the Mac names its memory.
static NSString *MemoryWhole(uint64_t bytes) { return [NSString stringWithFormat:@"%.0f GB", round((double)bytes / (double)(1ull << 30))]; }
/// "994 GB" of disk, in thousands as the Finder names a disk.
static NSString *DiskWhole(uint64_t bytes) {
    double gb = (double)bytes / 1e9;
    return gb >= 1000 ? [NSString stringWithFormat:@"%.1f TB", gb / 1000] : [NSString stringWithFormat:@"%.0f GB", round(gb)];
}

NSArray *MMWindowHourValues(MMHistoryRing *ring) {
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
    NSArray *values = MMWindowHourValues(ring);
    if (!values) return nil;
    MMWindowHour *h = [MMWindowHour new];
    h.side = side; h.title = title; h.explain = explain; h.values = values;
    return h;
}

#pragma mark - Fixes

static NSString *TreeName(MMWrapUpPlan *plan) {
    NSString *branch = plan.subject.worktree.branch;
    return branch.length ? branch : plan.subject.path.lastPathComponent ?: @"";
}

NSString *MMWindowFixTitle(MMPerformanceFix *fix) {
    NSInteger n = (NSInteger)fix.actions.count;
    NSString *kind = fix.kind;
    if ([kind isEqualToString:@"wrapup"]) return [@"Wrap Up " stringByAppendingString:TreeName(fix.wrapUp)];
    if ([kind isEqualToString:@"stop"]) return [NSString stringWithFormat:@"Stop %@", MMPlural(n, @"idle server")];
    if ([kind isEqualToString:@"quit"]) return [NSString stringWithFormat:@"Quit %@", MMPlural(n, @"app")];
    if ([kind isEqualToString:@"remove"]) return [NSString stringWithFormat:@"Remove %@", MMPlural(n, @"merged worktree")];
    if ([kind isEqualToString:@"trash"]) return [NSString stringWithFormat:@"Move %@ to the Trash", MMPlural(n, @"leftover")];
    if ([kind isEqualToString:@"clean"]) {
        if (n == 1) return [@"Clean " stringByAppendingString:MMWindowNameOf(fix.actions.firstObject.finding)];
        return [NSString stringWithFormat:@"Run %@", MMPlural(n, @"tool cleanup")];
    }
    return MMCapitalized(kind ?: @"");
}

#pragma mark - The model

/// Biggest first, then by key, so the order holds between snapshots. A tabs row has no bytes and sorts by its tabs
/// among the rows with none.
static NSArray<MMWindowRow *> *Sorted(NSArray<MMWindowRow *> *rows) {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) {
        if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
        if (a.tabs != b.tabs) return a.tabs > b.tabs ? NSOrderedAscending : NSOrderedDescending;
        return [a.key compare:b.key];
    }];
}

static MMWindowGroup *Group(NSString *key, NSString *title, MMWindowSide side, NSArray<MMPerformanceGroup *> *from,
                            NSArray<NSString *> *keys, MMSnapshot *s, NSSet<NSString *> *inFix) {
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    for (MMPerformanceGroup *g in from) {
        if (![keys containsObject:g.key]) continue;
        for (MMPerformanceRow *r in g.rows) {
            MMWindowRow *row = MMWindowRowFrom(r, s);
            row.inFix = [inFix containsObject:r.key];
            // The quiet word for what Fix Everything ends, where no fact gave a word of its own.
            if (row.inFix && !row.state && (row.kind == MMWindowApp || row.kind == MMWindowTabs)) row.state = @"will close";
            [rows addObject:row];
        }
    }
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = key; g.title = title; g.side = side; g.rows = Sorted(rows);
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
    if (p.needsYou > 0) m.asks = p.needsYou == 1 ? @"1 agent asks you" : [NSString stringWithFormat:@"%ld agents ask you", (long)p.needsYou];

    // The ring. Memory and disk stay two numbers.
    MMWindowRing *ring = [MMWindowRing new];
    ring.memoryUsed = p.memory.used; ring.memoryTotal = p.memory.total;
    ring.diskTotal = p.disk.total; ring.diskFree = p.disk.total > p.disk.used ? p.disk.total - p.disk.used : 0;
    ring.memory = Slices(p.memory); ring.disk = Slices(p.disk);
    m.ring = ring;

    // The last hour of the whole Mac. Before the first fill there is no ring, and the window draws no line.
    MMHistoryView *h = s.history;
    m.memoryHour = Hour(h.mac, MMWindowMemory, @"Memory in use",
                        [NSString stringWithFormat:@"Higher means more of the %@ is in use", MemoryWhole(ring.memoryTotal)]);
    m.diskHour = Hour(h.disk, MMWindowDisk, @"Disk free",
                      [NSString stringWithFormat:@"Lower means less room left on the %@ disk", DiskWhole(ring.diskTotal)]);

    // The fixes, in Fix Everything's order.
    NSMutableSet<NSString *> *inFix = [NSMutableSet new];
    NSMutableArray<MMWindowFix *> *fixes = [NSMutableArray new];
    for (MMPerformanceFix *f in p.fixes) {
        MMWindowFix *x = [MMWindowFix new];
        x.key = f.key; x.title = MMWindowFixTitle(f);
        x.memoryBack = f.memoryBack; x.diskBack = f.diskBack; x.needsYou = f.needsYou;
        [fixes addObject:x];
        [inFix addObjectsFromArray:f.rows];
    }
    m.fixes = fixes;

    // The groups. Apps, helpers and localhost tabs share one title, and each row keeps its own kind.
    m.memoryGroups = @[
        Group(MMPerformanceServers, @"Servers", MMWindowMemory, p.memoryGroups, @[MMPerformanceServers], s, inFix),
        Group(MMPerformanceAgents, @"Agents", MMWindowMemory, p.memoryGroups, @[MMPerformanceAgents], s, inFix),
        Group(kApps, @"Apps and helpers", MMWindowMemory, p.memoryGroups,
              @[MMPerformanceApps, MMPerformanceHelpers, MMPerformanceTabsGroup], s, inFix)];
    m.diskGroups = @[
        Group(MMPerformanceWorktrees, @"Worktrees", MMWindowDisk, p.diskGroups, @[MMPerformanceWorktrees], s, inFix),
        Group(kCaches, @"Caches", MMWindowDisk, p.diskGroups, @[MMPerformanceClutter], s, inFix)];

    m.run = extras.run;
    m.settings = MMWindowSettingsFrom(p, extras);
    return m;
}
