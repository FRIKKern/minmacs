// The rest of the memory as the window's group, MMWindowFeed.h: what no server, agent, app or helper row holds, by
// category, Core/MMRest.h. The categories come from the sample the snapshot already holds; only the category whose
// story shows has its processes' details read, and only while it shows, D11.
#import "Shell/MMWindowFeed.h"
#import "Core/MMRest.h"
#import <os/lock.h>

static NSString *RowKey(NSString *category) { return [@"rest:" stringByAppendingString:category]; }

/// One process as a row of its category's story. Its details only when its story shows.
static MMWindowRow *ProcRow(MMRestProc *p, NSString *category, MMSample *sample, BOOL story) {
    MMWindowRow *r = [MMWindowRow new];
    // A row in its category's tree: "insides:" keys, as every row of a row's insides has, MMWindowInsides.h.
    r.key = [NSString stringWithFormat:@"insides:%@|%d", RowKey(category), p.pid];
    r.kind = MMWindowSystem; r.iconHint = category;
    r.name = p.shownName;
    r.bytes = p.bytes; r.unmeasured = !p.measured;
    r.cpuPercent = p.cpuPercent;
    r.quiet = p.cpuPercent < 0.5;
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    void (^add)(MMWindowFact *) = ^(MMWindowFact *f) { if (f) [facts addObject:f]; };
    // The raw name stands first where a plain one shows: the fold reads it so.
    if (p.human.length && ![p.human isEqualToString:p.name]) add(MMWindowFactRawName(p.name));
    add(MMWindowFactPid(p.pid));
    if (!p.measured) add(MMWindowFactOtherUser());
    if (story) {
        NSDictionary *d = MMRestDetails(sample, p.pid, nil);
        add(MMWindowFactLaunchedBy(d[@"launchedBy"]));
        add(MMWindowFactParent(d[@"parent"], [d[@"parentPid"] intValue]));
        if ([d[@"startSec"] doubleValue] > 0) add(MMWindowFactUp(NSDate.date.timeIntervalSince1970 - [d[@"startSec"] doubleValue]));
        add(MMWindowFactPath([d[@"path"] stringByAbbreviatingWithTildeInPath]));
    }
    r.facts = facts;
    return r;
}

/// The processes whose details a story reads: as many as the story can list, and the folds' members with them.
static const NSUInteger kStoryMost = 60;

MMWindowGroup *MMWindowRestGroupFrom(MMSnapshot *s, MMPerformance *p, MMWindowExtras *x, uint64_t rest, pid_t own) {
    MMSample *sample = s.facts.sample;
    if (!sample) return nil;
    // MinMacs's own row holds its process, as an app row holds its own.
    NSSet<NSNumber *> *claimed = MMRestClaimed(p, sample);
    if (own > 0 && [sample proc:own]) claimed = [claimed setByAddingObjectsFromArray:[sample treeOf:own limit:500]];
    NSArray<MMRestCategory *> *cats = MMRestBuild(sample, claimed, rest, nil);
    if (!cats.count) return nil;
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    for (MMRestCategory *c in cats) {
        NSString *key = c.kind.key;
        MMWindowRow *row = [MMWindowRow new];
        row.key = RowKey(key); row.kind = MMWindowSystem; row.iconHint = key;
        row.name = c.kind.title; row.about = c.kind.about;
        row.bytes = c.bytes; row.cpuPercent = c.cpuPercent;
        row.quiet = c.cpuPercent < 0.5;
        row.hour = x.restHours[key];
        BOOL story = [x.restStory isEqualToString:row.key];
        NSMutableArray<MMWindowRow *> *members = [NSMutableArray arrayWithCapacity:c.procs.count + 1];
        NSUInteger i = 0;
        for (MMRestProc *proc in c.procs) [members addObject:ProcRow(proc, key, sample, story && i++ < kStoryMost)];
        // What no process holds is macOS's: one line of its own, so the list adds up to the row.
        if (c.unheld) {
            MMWindowRow *u = [MMWindowRow new];
            u.key = [NSString stringWithFormat:@"insides:%@|unheld", RowKey(key)]; u.kind = MMWindowSystem; u.iconHint = key;
            u.name = @"Kernel and system memory"; u.bytes = c.unheld; u.quiet = YES;
            u.facts = @[MMWindowFactUnheld(c.unheld)];
            [members addObject:u];
            [members sortUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
        }
        row.members = members;
        NSInteger n = (NSInteger)c.procs.count;
        NSString *growth = MMWindowRestGrowth(row.hour);
        // Calm: the count is its quiet word. Only a category that grew fast says so, in the count's place.
        row.state = MMWindowRestGrowthWord(growth) ?: MMWindowRestCountWord(n);
        NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
        MMWindowFact *count = MMWindowFactRestCount(n, c.unmeasured), *grew = MMWindowFactGrowth(growth);
        if (grew) [facts addObject:grew];
        if (count) [facts addObject:count];
        row.facts = facts;
        MMWindowRestOpens(row);
        [rows addObject:row];
    }
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = MMWindowRestGroup; g.title = MMWindowRestTitle; g.side = MMWindowMemory;
    g.rows = rows;
    return g;
}

#pragma mark - The hour of each category, while the window is open

static os_unfair_lock gHoursLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *gHours;   // key to minute to bytes

void MMWindowRestNote(MMWindowGroup *group, NSTimeInterval at) {
    if (!group.rows.count) return;
    long long minute = (long long)floor(at / 60);
    os_unfair_lock_lock(&gHoursLock);
    if (!gHours) gHours = [NSMutableDictionary new];
    for (MMWindowRow *r in group.rows) {
        NSString *key = r.iconHint ?: @"";
        if (!gHours[key]) gHours[key] = [NSMutableDictionary new];
        gHours[key][@(minute)] = @(r.bytes);
        for (NSNumber *m in gHours[key].allKeys) if (m.longLongValue <= minute - 60) [gHours[key] removeObjectForKey:m];
    }
    os_unfair_lock_unlock(&gHoursLock);
}

NSDictionary<NSString *, NSArray *> *MMWindowRestHours(NSTimeInterval at) {
    long long minute = (long long)floor(at / 60);
    NSMutableDictionary *out = [NSMutableDictionary new];
    os_unfair_lock_lock(&gHoursLock);
    for (NSString *key in gHours) {
        NSMutableArray *v = [NSMutableArray arrayWithCapacity:60];
        NSInteger filled = 0;
        for (long long m = minute - 59; m <= minute; m++) {
            NSNumber *b = gHours[key][@(m)];
            [v addObject:b ?: NSNull.null];
            if (b) filled++;
        }
        if (filled) out[key] = v;
    }
    os_unfair_lock_unlock(&gHoursLock);
    return out;
}

void MMWindowRestForgetHours(void) {
    os_unfair_lock_lock(&gHoursLock);
    gHours = nil;
    os_unfair_lock_unlock(&gHoursLock);
}

#pragma mark - The controller's part

static NSString *gStory;   // the category whose story shows, "rest:spotlight", under gHoursLock

MMWindowModel *MMWindowRestModelFrom(MMSnapshot *s, MMPerformance *p, MMWindowExtras *x) {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    os_unfair_lock_lock(&gHoursLock);
    x.restStory = gStory;
    os_unfair_lock_unlock(&gHoursLock);
    x.restHours = MMWindowRestHours(now);
    MMWindowModel *m = MMWindowModelFrom(s, p, x);
    for (MMWindowGroup *g in m.memoryGroups) if ([g.key isEqualToString:MMWindowRestGroup]) MMWindowRestNote(g, now);
    return m;
}

BOOL MMWindowRestStoryNow(id rowKey) {
    // A category of the rest reads its processes' details only while its story shows, so a new story asks for a model
    // with them, and a story that goes lets them go at the next snapshot.
    // A process row in its category's tree tells its category's story apart: the details are the category's to read.
    NSString *k = [rowKey isKindOfClass:NSString.class] ? ([rowKey hasPrefix:@"insides:rest:"] ? [rowKey substringFromIndex:8] : rowKey) : nil;
    NSString *rest = [k hasPrefix:@"rest:"] ? [k componentsSeparatedByString:@"|"].firstObject : nil;
    os_unfair_lock_lock(&gHoursLock);
    BOOL same = gStory == rest || [gStory isEqualToString:rest];
    if (!same) gStory = rest;
    os_unfair_lock_unlock(&gHoursLock);
    return !same && rest != nil;
}
