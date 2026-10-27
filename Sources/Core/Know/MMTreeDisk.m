// MMTreeDisk, part of P16. See MMTreeDisk.h. Ported from WalkDisk in WorkForest's Trees.m, with an autorelease pool
// per walk and Core's queue in place of the global queues WorkForest 0.1 used.
#import "Core/Know/MMTreeDisk.h"
#import "Core/Know/MMSizer.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Runtime/MMRuntime.h"
#include <fts.h>
#include <sys/stat.h>
#include <unistd.h>

NSNotificationName const MMTreeDiskDidChangeNotification = @"MMTreeDiskDidChangeNotification";

static const NSTimeInterval kFresh = 15 * 60;

@interface MMTreeDiskFacts ()
@property (readwrite) uint64_t allocated, freed, cacheBytes;
@property (readwrite) NSInteger files;
@property (readwrite) NSDate *touched, *created, *at;
@end

@implementation MMTreeDiskFacts
static id Num(NSDate *d) { return d ? @(d.timeIntervalSince1970) : @0; }
static NSDate *Date(id n) { return [n isKindOfClass:NSNumber.class] && [n doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[n doubleValue]] : nil; }
- (NSDictionary *)json {
    return @{@"allocated": @(self.allocated), @"freed": @(self.freed), @"cache": @(self.cacheBytes), @"files": @(self.files),
             @"touched": Num(self.touched), @"created": Num(self.created), @"at": Num(self.at)};
}
+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    MMTreeDiskFacts *f = [MMTreeDiskFacts new];
    f.allocated = [j[@"allocated"] unsignedLongLongValue]; f.freed = [j[@"freed"] unsignedLongLongValue];
    f.cacheBytes = [j[@"cache"] unsignedLongLongValue]; f.files = [j[@"files"] integerValue];
    f.touched = Date(j[@"touched"]); f.created = Date(j[@"created"]); f.at = Date(j[@"at"]);
    return f;
}
@end

/// One walk: allocated size, the part in cache folders, the file count and the newest change outside .git and caches.
/// Nested worktrees and repos are skipped, so a main checkout does not count the worktrees inside it.
static MMTreeDiskFacts *Walk(NSString *root, NSSet<NSString *> *caches) {
    BOOL dir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&dir] || !dir) return nil;
    char *paths[] = {(char *)root.fileSystemRepresentation, NULL};
    FTS *fts = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return nil;
    uint64_t disk = 0, cache = 0; NSInteger files = 0; double newest = 0;
    double limit = NSDate.date.timeIntervalSince1970 + 60;
    short cacheLevel = -1;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info == FTS_D) {
            if (cacheLevel < 0 && e->fts_statp) {
                double m = e->fts_statp->st_mtimespec.tv_sec;
                if (m > newest && m <= limit) newest = m;
            }
            if (e->fts_level > 0) {
                if (!strcmp(e->fts_name, ".git")) { fts_set(fts, e, FTS_SKIP); continue; }
                char git[PATH_MAX];
                snprintf(git, sizeof git, "%s/.git", e->fts_path);
                if (cacheLevel < 0 && access(git, F_OK) == 0) { fts_set(fts, e, FTS_SKIP); continue; }
                if (cacheLevel < 0 && [caches containsObject:@(e->fts_name)]) cacheLevel = e->fts_level;
            }
            continue;
        }
        if (e->fts_info == FTS_DP) { if (e->fts_level == cacheLevel) cacheLevel = -1; continue; }
        if (!e->fts_statp || e->fts_info == FTS_NS || e->fts_info == FTS_ERR || e->fts_info == FTS_DNR) continue;
        uint64_t b = (uint64_t)e->fts_statp->st_blocks * 512;
        disk += b; files++;
        if (cacheLevel >= 0) cache += b;
        else if (e->fts_info == FTS_F || e->fts_info == FTS_SL) {
            double m = e->fts_statp->st_mtimespec.tv_sec;
            if (m > newest && m <= limit) newest = m;
        }
    }
    fts_close(fts);
    MMTreeDiskFacts *f = [MMTreeDiskFacts new];
    f.allocated = disk; f.cacheBytes = cache; f.files = files;
    f.touched = newest > 0 ? [NSDate dateWithTimeIntervalSince1970:newest] : nil;
    f.created = [NSFileManager.defaultManager attributesOfItemAtPath:[root stringByAppendingPathComponent:@".git"] error:nil].fileCreationDate;
    f.freed = [MMSizer quick:root].freedIfDeleted;
    f.at = NSDate.date;
    return f;
}

@implementation MMTreeDisk {
    MMFactCache *_cache;
    dispatch_queue_t _queue;
    NSMutableSet<NSString *> *_pending;
    NSArray<NSString *> *_caches;
}

+ (instancetype)shared {
    static MMTreeDisk *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMTreeDisk new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _cache = [[MMFactCache alloc] initWithName:@"treedisk" maxAge:0 persist:YES];
        _queue = MMQueue(@"core", @"disk", QOS_CLASS_UTILITY);
        _pending = [NSMutableSet new];
        _caches = @[@"node_modules", @".next", @".nuxt", @".svelte-kit", @".turbo", @".parcel-cache", @".vite", @".cache", @"dist",
                    @"build", @"out", @"coverage", @".output", @"target", @"_build", @"deps", @".venv", @"venv", @"__pycache__",
                    @".pytest_cache", @".mypy_cache", @".gradle", @"Pods", @"DerivedData", @".expo", @".angular", @".elixir_ls",
                    @".dart_tool"];
    }
    return self;
}

- (NSArray<NSString *> *)cacheNames { @synchronized (self) { return _caches; } }
- (void)setCacheNames:(NSArray<NSString *> *)names { @synchronized (self) { _caches = [names copy] ?: @[]; } }

/// The checkout folder's own change time. Adding, removing or renaming a file at its top moves it, so a walk older
/// than that change is stale at once, before the 15 minutes pass.
static NSString *Stamp(NSString *path) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return @"";
    return [NSString stringWithFormat:@"%ld.%ld", (long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec];
}

/// Walks now and keeps the answer. Any queue but main.
- (MMTreeDiskFacts *)walk:(NSString *)path {
    NSString *stamp = Stamp(path);
    MMTreeDiskFacts *f;
    @autoreleasepool { f = Walk(path, [NSSet setWithArray:self.cacheNames]); }
    [_cache valueFor:path fingerprint:stamp orCompute:^id { return f.json; } wait:YES];
    return f;
}

- (MMTreeDiskFacts *)factsFor:(NSString *)path read:(MMTreeDiskRead)read {
    if (!path.length) return nil;
    if (read == MMTreeDiskNow) return [self walk:path];
    MMTreeDiskFacts *old = [MMTreeDiskFacts fromJSON:[_cache peek:path]];
    BOOL fresh = old.at && -old.at.timeIntervalSinceNow < kFresh && ![_cache changed:path fingerprint:Stamp(path)];
    if (fresh) return old;
    if (read == MMTreeDiskFresh) return [self walk:path];
    @synchronized (_pending) {
        if ([_pending containsObject:path]) return old;
        [_pending addObject:path];
    }
    dispatch_async(_queue, ^{
        [self walk:path];
        @synchronized (self->_pending) { [self->_pending removeObject:path]; }
        [NSNotificationCenter.defaultCenter postNotificationName:MMTreeDiskDidChangeNotification object:self userInfo:@{@"path": path}];
    });
    return old;
}

- (void)forget:(NSSet<NSString *> *)livePaths { [_cache forget:livePaths ?: [NSSet set]]; }

@end
