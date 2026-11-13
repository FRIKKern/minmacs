// `minmacs window [--json]`: what the menu window would show now, MMWindowFeed.h. It reads the snapshot, the gains
// table as `performance` does, the mode prefs, the lid setting and the login item's state, and changes nothing.
// It runs no fix: Fix Everything has no verb, since a verb that acts on everything it finds could not be scoped to a
// test's own fixtures.
#import <ServiceManagement/ServiceManagement.h>
#import "Shell/MMWindowCLI.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMWindowJSON.h"
#import "CLI/MMCLI.h"
#import "UI/MMFormat.h"

/// Sizes by the window's one rule, so the verb and the window give one number for one thing: memory in 1024s, the
/// disk and what is on it in thousands.
static NSString *Mem(uint64_t n) { return MMWindowSizeText(n, NO); }
static NSString *Disk(uint64_t n) { return MMWindowSizeText(n, YES); }

static void PrintGroup(MMArgs *a, MMWindowGroup *g) {
    uint64_t sum = 0;
    for (MMWindowRow *r in g.rows) sum += r.bytes;
    BOOL disk = g.side == MMWindowDisk;
    [a print:@"%@  %lu, %@", g.title, (unsigned long)g.rows.count, disk ? Disk(sum) : Mem(sum)];
    for (MMWindowRow *r in g.rows) {
        NSMutableArray *tail = [NSMutableArray new];
        if (r.kind == MMWindowTabs) [tail addObject:MMPlural(r.tabs, @"tab")]; else [tail addObject:disk ? Disk(r.bytes) : Mem(r.bytes)];
        if (r.state) [tail addObject:r.state];
        if (r.needsYou) [tail addObject:@"asks you"];
        if (r.inFix) [tail addObject:@"in a fix"];
        [a print:@"  %@ %@", MMColumn(r.name, 34), [tail componentsJoinedByString:@", "]];
    }
}

static int Window(MMArgs *a) {
    if (a.words.count) return [a usageError];
    MMSnapshot *s = a.snapshot;
    MMPerformance *p = [MMPerformance from:s history:a.inApp ? s.history : nil
                                  lookBack:[MMPerformanceLookBack read:MMGains.shared now:NSDate.date]];
    // Open at login as the system holds it for this app bundle. A read only: nothing is registered here.
    BOOL login = SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:login]);
    if (a.json) {
        NSMutableDictionary *j = [m.json mutableCopy];
        j[@"app"] = @(a.inApp);
        [a printJSON:j];
        return 0;
    }
    if (m.asks) [a print:@"%@", m.asks];
    [a print:@"Memory  %@ in use of %@", Mem(m.ring.memoryUsed), MMWindowWholeText(m.ring.memoryTotal, NO)];
    [a print:@"Disk    %@ free of %@", Disk(m.ring.diskFree), MMWindowWholeText(m.ring.diskTotal, YES)];
    for (MMWindowGroup *g in m.memoryGroups) PrintGroup(a, g);
    for (MMWindowGroup *g in m.diskGroups) PrintGroup(a, g);
    [a print:@"Fix Everything  %@: %@ memory back, %@ disk back", MMPlural(m.fixCount, @"fix"), Mem(m.memoryBack), Disk(m.diskBack)];
    NSInteger i = 0;
    for (MMWindowFix *f in m.fixes)
        [a print:@"%2ld  %@ memory %@, disk %@%@", (long)++i, MMColumn(f.title, 38), Mem(f.memoryBack), Disk(f.diskBack),
                 f.needsYou ? @", needs your own press" : @""];
    // A rule with nothing picked yet, the removal choice before the person made it, says so.
    for (MMWindowRule *r in m.settings.rules)
        [a print:@"Rule    %@ %@", MMColumn(r.title, 30), r.picked >= 0 && r.picked < (NSInteger)r.choices.count ? r.choices[(NSUInteger)r.picked].title : @"not chosen yet"];
    for (MMWindowSwitch *w in m.settings.switches) [a print:@"Switch  %@ %@", MMColumn(w.title, 34), w.on ? @"on" : @"off"];
    return 0;
}

MMVerbSpec *MMWindowVerbSpec(void) {
    MMVerbSpec *v = [MMVerbSpec verb:@"window" usage:@"window [--json]   what the menu window shows: asks, the two sides, the ring, the fixes and Settings"
                             mutates:NO run:^int(MMArgs *a) { return Window(a); }];
    v.reads = MMVerbReadsCachedGit;
    return v;
}
