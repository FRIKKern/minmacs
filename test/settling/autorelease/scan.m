// Does an autorelease pool per work item explain WorkForest's memory spike? Read-only.
// It runs WorkForest's disk walk and git calls the way WorkForest's readAll does: one block per
// worktree on the global utility queue, six at a time, with no pool of its own. Then it runs the same
// work with an @autoreleasepool per block, and with one per directory inside the walk.
// Each run is its own process, so each peak footprint is clean.
//
// Build: clang -fobjc-arc -O2 -Wall -framework Foundation scan.m -o scan
// Usage: scan <none|item|dir> <worktree>...
// The walk only stats files. Git runs read-only commands with GIT_OPTIONAL_LOCKS=0,
// so git status never rewrites an index.
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <fts.h>
#include <mach/mach.h>

static int mode;   // 0 none, 1 a pool per work item, 2 a pool per directory as well

static void footprint(uint64_t *now, uint64_t *peak) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n);
    *now = vi.phys_footprint; *peak = vi.ledger_phys_footprint_peak;
}

// The state of one walk, so one entry can be handled inside or outside a pool.
typedef struct { uint64_t disk, cache; NSInteger files; double newest; short cacheLevel; } Walk;

// One fts entry, with the same Foundation calls as WorkForest's WalkDisk, Trees.m:296-330.
static void Entry(FTS *fts, FTSENT *e, NSSet *caches, Walk *w) {
    if (e->fts_info == FTS_D) {
        if (w->cacheLevel < 0 && e->fts_statp) {
            double m = e->fts_statp->st_mtimespec.tv_sec;
            if (m > w->newest && m <= NSDate.date.timeIntervalSince1970 + 60) w->newest = m;
        }
        if (e->fts_level > 0) {
            NSString *n = @(e->fts_name);
            if ([n isEqualToString:@".git"]) { fts_set(fts, e, FTS_SKIP); return; }
            char git[PATH_MAX];
            snprintf(git, sizeof git, "%s/.git", e->fts_path);
            if (w->cacheLevel < 0 && access(git, F_OK) == 0) { fts_set(fts, e, FTS_SKIP); return; }
            if (w->cacheLevel < 0 && [caches containsObject:n]) w->cacheLevel = e->fts_level;
        }
        return;
    }
    if (e->fts_info == FTS_DP) { if (e->fts_level == w->cacheLevel) w->cacheLevel = -1; return; }
    if (!e->fts_statp || e->fts_info == FTS_NS || e->fts_info == FTS_ERR || e->fts_info == FTS_DNR) return;
    uint64_t b = (uint64_t)e->fts_statp->st_blocks * 512;
    w->disk += b; w->files++;
    if (w->cacheLevel >= 0) w->cache += b;
    else if (e->fts_info == FTS_F || e->fts_info == FTS_SL) {
        double m = e->fts_statp->st_mtimespec.tv_sec;
        if (m > w->newest && m <= NSDate.date.timeIntervalSince1970 + 60) w->newest = m;
    }
}

// WorkForest's full walk. Mode dir drains a pool after every entry.
static NSDictionary *WalkDisk(NSString *root, NSSet *caches) {
    char *paths[] = {(char *)root.fileSystemRepresentation, NULL};
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return nil;
    Walk w = {.cacheLevel = -1};
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (mode == 2) { @autoreleasepool { Entry(fts, e, caches, &w); } }
        else Entry(fts, e, caches, &w);
    }
    fts_close(fts);
    return @{@"disk": @(w.disk), @"cache": @(w.cache), @"files": @(w.files), @"touched": @(w.newest)};
}

// WorkForest's WFGit, Common.m:80-101: NSTask, a pipe read on another global block, then wait.
static NSString *Git(NSString *dir, NSArray *args) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    t.arguments = [@[@"-C", dir] arrayByAddingObjectsFromArray:args];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"GIT_OPTIONAL_LOCKS"] = @"0";
    t.environment = env;
    NSPipe *out = [NSPipe pipe]; t.standardOutput = out; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    __block NSData *d = nil;
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_async(g, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ d = [out.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    [t waitUntilExit];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: scan <none|item|dir> <worktree>...\n"); return 2; }
    mode = !strcmp(argv[1], "item") ? 1 : !strcmp(argv[1], "dir") ? 2 : 0;
    NSMutableArray *trees = [NSMutableArray new];
    for (int i = 2; i < argc; i++) [trees addObject:@(argv[i])];
    NSSet *caches = [NSSet setWithArray:@[@"node_modules", @".next", @".turbo", @"build", @"dist", @"target", @".build", @"DerivedData", @".venv"]];
    __block uint64_t peakSeen = 0, files = 0;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_semaphore_t gate = dispatch_semaphore_create(6);
    dispatch_group_t g = dispatch_group_create();
    NSDate *start = NSDate.date;
    // A sampler reads the footprint every 100 ms, so the curve shows when memory comes back.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_queue_create("sampler", 0));
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ uint64_t n, p; footprint(&n, &p); if (n > peakSeen) peakSeen = n; });
    dispatch_resume(timer);
    for (NSString *t in trees) {
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        dispatch_group_async(g, q, ^{
            void (^work)(void) = ^{
                // ReadFacts runs about a dozen git calls per worktree; these four are the read-only core.
                Git(t, @[@"rev-parse", @"HEAD"]);
                Git(t, @[@"branch", @"--show-current"]);
                Git(t, @[@"log", @"-1", @"--format=%H %ct"]);
                NSDictionary *s = WalkDisk(t, caches);
                Git(t, @[@"status", @"--porcelain"]);
                @synchronized (trees) { files += [s[@"files"] unsignedLongLongValue]; }
            };
            if (mode >= 1) { @autoreleasepool { work(); } } else work();
            dispatch_semaphore_signal(gate);
        });
    }
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    double took = -start.timeIntervalSinceNow;
    uint64_t n0, p0; footprint(&n0, &p0);
    // Wait two seconds, as an idle app would, and read again: memory held by a pool that has not drained
    // stays; memory that malloc keeps after a free shows as dirty but reusable.
    [NSThread sleepForTimeInterval:2];
    uint64_t n1, p1; footprint(&n1, &p1);
    printf("mode %-4s trees %lu files %llu  time %.1f s  peak %.0f MB  sampled peak %.0f MB  end %.0f MB  after 2 s %.0f MB\n",
           argv[1], (unsigned long)trees.count, files, took, p1 / 1048576.0, peakSeen / 1048576.0, n0 / 1048576.0, n1 / 1048576.0);
    return 0;
}
