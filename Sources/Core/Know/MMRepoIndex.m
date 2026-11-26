// MMRepoIndex and MMWorktree, pattern P25. The walk runs in the worker of P4 through MMSharedWorker(),
// so a slow disk never holds up the app. worktreeAt: reads .git files with no spawn, from ReadGit in LH Ports.m:265.
//
// Git facts, P26, are event driven. One FSEvents stream per root marks the worktrees a change touched:
// a change among a worktree's files drops its status layer and marks its size stale, and a change in a git dir
// marks the worktrees that use it. An update pass on the git queue reads the fingerprints of the marked
// worktrees from git's files and runs git only where one moved. Nothing is read on a timer, and a graph rebuild
// reads the facts from memory. The caches persist with each stream's saved event id, so a restart replays the
// changes it missed and runs git only for the worktrees they touched.
#import "Core/Know/MMGit.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#import "Core/Senses/MMFolders.h"
#import "Core/Store/MMStore.h"
#include <os/lock.h>
#include <stdatomic.h>
#include <sys/stat.h>

// MMGitFacts.m
NSDictionary<NSString *, NSString *> *MMGitDirsOf(NSString *path);
NSDictionary *MMGitReadFiles(NSString *gitDir, NSString *common);
NSString *MMGitStatusFingerprint(NSDictionary *files);
NSString *MMGitHistoryFingerprint(NSDictionary *files, BOOL isMain);
NSDictionary *MMGitStatusOf(NSString *dir, NSMutableDictionary *counts);
NSDictionary *MMGitHistoryOf(NSString *dir, NSDictionary *files, BOOL isMain, MMFactCache *patchIds, NSMutableDictionary *counts);
@interface MMGitFacts (MMValue)
+ (instancetype)fromValue:(NSDictionary *)value;
@end

NSNotificationName const MMRepoIndexDidChangeNotification = @"MMRepoIndexDidChangeNotification";
NSNotificationName const MMRepoIndexFactsDidChangeNotification = @"MMRepoIndexFactsDidChangeNotification";

static const NSTimeInterval kWalkGap = 10;      // at most one walk this often while folders change
static const NSInteger kRootDepth = 4;          // as deep as the worker walks below a root
static const NSTimeInterval kSizeGap = 60;      // a stale size is walked again at most this often per worktree

/// The folders a walk never enters, from WorkForest's caches list.
static NSArray<NSString *> *SkipNames(void) {
    return @[@"node_modules", @".next", @".nuxt", @".svelte-kit", @".turbo", @".parcel-cache", @".vite", @".cache", @"dist",
             @"build", @"out", @"coverage", @".output", @"target", @"_build", @"deps", @".venv", @"venv", @"__pycache__",
             @".pytest_cache", @".mypy_cache", @".gradle", @"Pods", @"DerivedData", @".expo", @".angular", @".elixir_ls",
             @".dart_tool"];
}

/// path is folder or inside it, as text. It allocates nothing: the holder lookups run it per checkout.
static BOOL PathIn(NSString *path, NSString *folder) {
    NSUInteger n = folder.length;
    if (!path.length || !n || ![path hasPrefix:folder]) return NO;
    return path.length == n || [folder characterAtIndex:n - 1] == '/' || [path characterAtIndex:n] == '/';
}

/// With MINMACS_HOME set, as in a test or the bench, git and size walks run only inside MINMACS_HOME or one of
/// the index's roots. Issue #54 found the bench's real process table led the index to run git in the person's
/// repos. Its review found 3 more git cache entries outside the fixture roots and outside the home folder.
static BOOL ReadableAt(NSString *path, NSArray<NSString *> *roots) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (!home.length) return YES;
    NSString *p = path.stringByStandardizingPath;
    if (PathIn(p, home.stringByStandardizingPath)) return YES;
    for (NSString *r in roots) if (PathIn(p, r.stringByStandardizingPath)) return YES;
    return NO;
}

#pragma mark - Worktrees

@interface MMWorktree ()
@property (readwrite, copy) NSString *path, *realPath, *repo, *branch, *lockReason, *makerSession;
@property (readwrite) BOOL isMain, locked, missing;
@property (readwrite) MMWorktreeMaker maker;
@end

@implementation MMWorktree

/// Decision 6: who made a worktree, from where it lives.
static MMWorktreeMaker MakerOf(NSString *path) {
    NSString *home = NSHomeDirectory();
    if ([path containsString:@"/.claude/worktrees/"]) return MMMakerClaudeCode;
    if (PathIn(path, [home stringByAppendingPathComponent:@".cursor/worktrees"])) return MMMakerCursor;
    if (PathIn(path, [home stringByAppendingPathComponent:@"conductor/workspaces"])) return MMMakerConductor;
    return MMMakerPerson;
}

+ (instancetype)path:(NSString *)path real:(NSString *)real repo:(NSString *)repo branch:(NSString *)branch locked:(BOOL)locked {
    MMWorktree *w = [MMWorktree new];
    w.path = path; w.repo = repo; w.branch = branch; w.locked = locked;
    w.realPath = real ?: path;
    w.isMain = [path isEqualToString:repo];
    w.maker = MakerOf(path);
    return w;
}

+ (instancetype)path:(NSString *)path repo:(NSString *)repo branch:(NSString *)branch locked:(BOOL)locked {
    char real[PATH_MAX];   // once per checkout, on the queue that stores it: the walk's reply or a read of .git
    return [self path:path real:path.length && realpath(path.fileSystemRepresentation, real) ? @(real) : path
                 repo:repo branch:branch locked:locked];
}

- (NSString *)description { return [NSString stringWithFormat:@"<MMWorktree %@ %@>", self.path, self.branch ?: @"detached"]; }

@end

NSString *MMWorktreeFolderFor(MMWorktree *w, NSString *path) {
    if (PathIn(path, w.path)) return w.path;
    return PathIn(path, w.realPath) ? w.realPath : nil;
}

BOOL MMWorktreeIsAt(MMWorktree *w, NSString *path) {
    return path.length && ([path isEqualToString:w.path] || [path isEqualToString:w.realPath]);
}

NSString *MMWorktreeOtherForm(MMWorktree *w, NSString *path) {
    NSString *from = MMWorktreeFolderFor(w, path);
    NSString *to = from == w.path ? w.realPath : w.path;
    if (!from || !to.length || [from isEqualToString:to] || [from hasSuffix:@"/"]) return path;
    return [to stringByAppendingString:[path substringFromIndex:from.length]];
}

static NSString *Up(NSString *p);   // below: the folder above p

/// The checkouts of one array by name, so a holder lookup walks up path's folders, a few dictionary reads, rather
/// than every checkout. Made once per array: the index and the facts hand out the same array until the next walk.
@interface MMWorktreeNames : NSObject
@property (copy) NSDictionary<NSString *, MMWorktree *> *named;            // path or realPath: the first such entry
@property (copy) NSDictionary<NSString *, NSArray<MMWorktree *> *> *real;  // realPath: its entries, in order
@end
@implementation MMWorktreeNames
@end

static MMWorktreeNames *NamesOf(NSArray<MMWorktree *> *trees) {
    static NSMapTable<NSArray *, MMWorktreeNames *> *made;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    // By the array's address, not -isEqual:, which would compare every checkout of two lists of one length.
    if (!made) made = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                               valueOptions:NSPointerFunctionsStrongMemory capacity:4];
    MMWorktreeNames *x = [made objectForKey:trees];
    os_unfair_lock_unlock(&lock);
    if (x) return x;
    NSMutableDictionary *named = [NSMutableDictionary new], *real = [NSMutableDictionary new];
    for (MMWorktree *w in trees) {
        if (w.path.length && !named[w.path]) named[w.path] = w;
        if (w.realPath.length && !named[w.realPath]) named[w.realPath] = w;
        if (!w.realPath.length) continue;
        if (!real[w.realPath]) real[w.realPath] = [NSMutableArray new];
        [real[w.realPath] addObject:w];
    }
    x = [MMWorktreeNames new];
    x.named = named; x.real = real;
    os_unfair_lock_lock(&lock);
    [made setObject:x forKey:trees];
    os_unfair_lock_unlock(&lock);
    return x;
}

MMWorktree *MMWorktreeHolding(NSArray<MMWorktree *> *trees, NSString *path) {
    // path in resolved form, through the deepest name of a checkout that holds it. Then the deepest checkout by its
    // resolved path, so a checkout that only .git/worktrees names, nested in one walked by a link, still wins. Of two
    // entries of one folder, the one named the way path is, as the graph picks. A mutable array may change under a
    // cache, so it is scanned, below.
    if (!path.length) return nil;
    if (![trees isKindOfClass:NSMutableArray.class]) {
        MMWorktreeNames *x = NamesOf(trees);
        NSString *real = nil;
        for (NSString *p = path; p.length && !real; p = Up(p)) {
            MMWorktree *w = x.named[p];
            if (w) real = [p isEqualToString:w.path] ? MMWorktreeOtherForm(w, path) : path;
        }
        for (NSString *p = real; p.length; p = Up(p)) {
            NSArray<MMWorktree *> *c = x.real[p];
            if (!c) continue;
            for (MMWorktree *w in c) if (PathIn(path, w.path)) return w;
            return c.firstObject;
        }
        return nil;
    }
    NSString *real = nil;
    for (MMWorktree *w in trees) {
        NSString *f = MMWorktreeFolderFor(w, path);
        if (f) { real = [f isEqualToString:w.path] ? MMWorktreeOtherForm(w, path) : path; break; }
    }
    if (!real) return nil;
    MMWorktree *best = nil;
    for (MMWorktree *w in trees) {
        if (!PathIn(real, w.realPath)) continue;
        if (!best || w.realPath.length > best.realPath.length) best = w;
        // Of two entries of one folder, the one named the way path is, as the graph picks.
        else if ([w.realPath isEqualToString:best.realPath] && PathIn(path, w.path) && !PathIn(path, best.path)) best = w;
    }
    return best;
}

/// The folder above p, nil at the top.
static NSString *Up(NSString *p) {
    NSRange r = [p rangeOfString:@"/" options:NSBackwardsSearch];
    return r.location == NSNotFound || r.location == 0 ? nil : [p substringToIndex:r.location];
}

/// The pairs [kept, real] of the roots and the checkouts as one table, kept to real; of two pairs with one kept folder
/// the first. Made once per walk, so a path resolves by walking up its folders, not by trying every pair.
static NSDictionary<NSString *, NSString *> *PairMap(NSArray<NSArray<NSString *> *> *pairs) {
    NSMutableDictionary *m = [NSMutableDictionary new];
    for (NSArray<NSString *> *p in pairs) if (p[0].length && ![p[0] hasSuffix:@"/"] && !m[p[0]]) m[p[0]] = p[1];
    return m;
}

/// The resolved form of path, as text: the deepest pair's kept folder that holds it swapped for its resolved one.
/// FSEvents names resolved paths.
static NSString *Resolved(NSString *path, NSDictionary<NSString *, NSString *> *pairs) {
    if (!pairs.count) return path;
    for (NSString *p = path; p.length; p = Up(p)) {
        NSString *real = pairs[p];
        if (real) return [real stringByAppendingString:[path substringFromIndex:p.length]];
    }
    return path;
}

/// A changed folder as FSEvents or a caller names it, in its resolved form. A path as kept resolves through the pairs.
/// One no pair holds is resolved already, as FSEvents names it: standardized, with the /private that standardizing drops.
static NSString *ResolvedForm(NSString *raw, NSDictionary<NSString *, NSString *> *pairs) {
    NSString *s = raw.stringByStandardizingPath, *r = Resolved(s, pairs);
    if (![r isEqualToString:s] || !raw.isAbsolutePath) return r;
    return [raw hasPrefix:@"/private/"] && ![s hasPrefix:@"/private/"] ? [@"/private" stringByAppendingString:s] : s;
}

NSString *MMReadLine(NSString *path);   // MMGitFacts.m: a small file's text, trimmed, read with open and read
static NSString *ReadLine(NSString *path) { return MMReadLine(path); }

static NSString *BranchIn(NSString *gitDir) {
    NSString *head = ReadLine([gitDir stringByAppendingPathComponent:@"HEAD"]);
    return [head hasPrefix:@"ref: refs/heads/"] ? [head substringFromIndex:16] : nil;
}

/// The checkout at dir, read from its .git, or nil when dir holds no .git.
static MMWorktree *CheckoutAt(NSString *dir) {
    NSString *dotgit = [dir stringByAppendingPathComponent:@".git"];
    struct stat st;   // stat, not NSFileManager, issue #54: once per worktree on every update pass
    if (stat(dotgit.fileSystemRepresentation, &st) != 0) return nil;
    if (S_ISDIR(st.st_mode)) return [MMWorktree path:dir repo:dir branch:BranchIn(dotgit) locked:NO];
    NSString *line = ReadLine(dotgit);
    if (![line hasPrefix:@"gitdir: "]) return nil;
    NSString *gitDir = [line substringFromIndex:8];
    if (!gitDir.isAbsolutePath) gitDir = [dir stringByAppendingPathComponent:gitDir];
    gitDir = gitDir.stringByStandardizingPath;
    NSString *common = ReadLine([gitDir stringByAppendingPathComponent:@"commondir"]);
    if (!common.length) return nil;   // a submodule, which is not a worktree
    if (!common.isAbsolutePath) common = [gitDir stringByAppendingPathComponent:common];
    common = common.stringByStandardizingPath;
    NSString *repo = [common.lastPathComponent isEqualToString:@".git"] ? common.stringByDeletingLastPathComponent : common;
    BOOL locked = stat([gitDir stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, &st) == 0;
    return [MMWorktree path:dir repo:repo branch:BranchIn(gitDir) locked:locked];
}


#pragma mark - The index

static dispatch_queue_t ReposQueue(void) { return MMQueue(@"core", @"repos", QOS_CLASS_UTILITY); }
static dispatch_queue_t GitQueue(void) { return MMQueue(@"core", @"git", QOS_CLASS_UTILITY); }
static const void *const kFreshKey = &kFreshKey;
/// core.git.fresh, with kFreshKey set on it, which MMGitOnFreshRead finds there.
static dispatch_queue_t FreshQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = MMQueue(@"core", @"git.fresh", QOS_CLASS_UTILITY);
        dispatch_queue_set_specific(q, kFreshKey, (void *)kFreshKey, NULL);
    });
    return q;
}
BOOL MMGitOnFreshRead(void) { return dispatch_get_specific(kFreshKey) == kFreshKey; }

/// The folders an FSEvents callback drops before it reaches the index. FSEvents takes at most 8 exclusion paths,
/// so MMFolderWatch filters these names in the callback, per research track B.
static NSArray<NSString *> *WatchSkip(void) {
    return @[@"node_modules", @".git/objects", @"DerivedData", @".next", @"target", @".turbo", @".cache"];
}

/// A short stable name for a root, for its stream's saved event id: FNV-1a over the path.
static NSString *RootHash(NSString *root) {
    uint64_t h = 1469598103934665603ULL;
    for (const char *c = root.fileSystemRepresentation; c && *c; c++) { h ^= (uint8_t)*c; h *= 1099511628211ULL; }
    return [NSString stringWithFormat:@"%016llx", h];
}

/// YES when the folder is a git dir or lies in one: the part up to and with "/.git" lands in gitRoot.
static BOOL InGitDir(NSString *dir, NSString **gitRoot, NSString **rest) {
    NSRange r = [dir rangeOfString:@"/.git"];
    while (r.location != NSNotFound) {
        NSUInteger end = NSMaxRange(r);
        if (end == dir.length || [dir characterAtIndex:end] == '/') {
            *gitRoot = [dir substringToIndex:end];
            *rest = [dir substringFromIndex:end];
            return YES;
        }
        r = [dir rangeOfString:@"/.git" options:0 range:NSMakeRange(end, dir.length - end)];
    }
    return NO;
}

#ifdef MM_TESTS
MMRepoIndexStep MMRepoIndexTestStep;
#endif

@implementation MMRepoIndex {
    NSArray<NSString *> *_roots;
    NSArray<NSString *> *_realRoots;   // each root resolved by the last walk, in the same order
    NSArray<MMWorktree *> *_trees;     // deepest path first
    NSDictionary<NSString *, NSString *> *_pairs;              // kept to resolved, of each root and checkout
    NSArray<NSString *> *_pairRoots;                           // the resolved roots of the walk that made _pairs
    NSDictionary<NSString *, NSDictionary *> *_realDirs;       // path: {gitDir, common}, resolved as text
    BOOL _walking, _again;              // a walk is in flight; another was asked for meanwhile
    NSDate *_lastWalk;
    BOOL _walked;                      // a walk ended with an answer
    // Git facts and sizes.
    MMFactCache *_git, *_patchIds, *_sizes;                     // persisted; nil until first used off main
    NSMutableDictionary<NSString *, NSDictionary *> *_dirs;    // path: {gitDir, common}
    NSMutableDictionary<NSString *, id> *_facts;               // path: MMGitFacts, or NSNull when the path holds none
    NSMutableDictionary<NSString *, MMWorktree *> *_marked;    // fingerprints to read in the next pass
    NSMutableSet<NSString *> *_dropped;                        // status layers a change dropped
    NSObject *_statusLock;                                     // a drop, and updateOne's read or write of the status, one at a time
    NSMutableDictionary<NSString *, NSDate *> *_sizeAsked;
    NSMutableArray *_dones;
    BOOL _updating, _updateAgain;
    NSMutableDictionary<NSString *, NSNumber *> *_counts;
    NSArray<MMFolderWatch *> *_watches;
    NSUInteger _watchGen;                                      // moves on every stop
    NSMutableArray<NSArray *> *_early;                         // changes that came before the first walk: [dirs, subtrees]
}

+ (instancetype)shared {
    static MMRepoIndex *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMRepoIndex new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _dirs = [NSMutableDictionary new]; _facts = [NSMutableDictionary new]; _marked = [NSMutableDictionary new];
        _dropped = [NSMutableSet new]; _sizeAsked = [NSMutableDictionary new]; _dones = [NSMutableArray new];
        _counts = [NSMutableDictionary new]; _early = [NSMutableArray new]; _statusLock = [NSObject new];
    }
    return self;
}

/// The caches read their files when made, so they are made on first use off main.
- (BOOL)loadCaches {
    @synchronized (self) {
        if (_git) return YES;
        if (NSThread.isMainThread) return NO;
        _git = [[MMFactCache alloc] initWithName:@"git" maxAge:0 persist:YES];
        _patchIds = [[MMFactCache alloc] initWithName:@"git.patchids" maxAge:0 persist:YES];
        _sizes = [[MMFactCache alloc] initWithName:@"sizes" maxAge:0 persist:YES];
        return YES;
    }
}

- (void)saveCaches {
    MMFactCache *git, *patchIds, *sizes;
    @synchronized (self) { git = _git; patchIds = _patchIds; sizes = _sizes; }
    [git saveNow]; [patchIds saveNow]; [sizes saveNow];
}

- (void)count:(NSString *)key by:(NSInteger)n {
    @synchronized (_counts) { _counts[key] = @([_counts[key] integerValue] + n); }
}

- (NSDictionary<NSString *, NSNumber *> *)stats {
    @synchronized (_counts) { return [_counts copy]; }
}

/// The default roots. MINMACS_ROOTS, colon separated, wins. With MINMACS_HOME set and no MINMACS_ROOTS there are
/// none, so a test never walks the person's folders. Otherwise the core rules' roots list, with WorkForest's
/// defaults, plus the folders where Cursor and Conductor keep their worktrees.
static NSArray<NSString *> *DefaultRoots(void) {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    NSMutableArray *out = [NSMutableArray new];
    if (env[@"MINMACS_ROOTS"].length) {
        for (NSString *r in [env[@"MINMACS_ROOTS"] componentsSeparatedByString:@":"]) if (r.length) [out addObject:r.stringByStandardizingPath];
        return out;
    }
    if (env[@"MINMACS_HOME"].length) return out;
    NSArray *defaults = @[@"~/Documents/GitHub", @"~/Developer", @"~/code", @"~/src", @"~/Projects", @"~/repos", @"~/dev",
                          @"~/.cursor/worktrees", @"~/conductor/workspaces"];
    NSArray *listed = [[MMRules rulesFor:@"core" defaults:@{@"roots": defaults}] entries:@"roots"];
    for (id r in listed) {
        if (![r isKindOfClass:NSString.class]) continue;
        NSString *p = [r stringByExpandingTildeInPath].stringByStandardizingPath;
        BOOL dir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&dir] && dir && ![out containsObject:p]) [out addObject:p];
    }
    return out;
}

- (NSArray<NSString *> *)roots {
    @synchronized (self) {
        if (!_roots) _roots = DefaultRoots();
        return _roots;
    }
}

- (void)setRoots:(NSArray<NSString *> *)roots {
    @synchronized (self) { _roots = [roots copy]; }
}

- (NSArray<MMWorktree *> *)worktrees { @synchronized (self) { return _trees ?: @[]; } }

/// The roots and each one resolved, for ReadableAt: a checkout found through .git/worktrees under a root that is a
/// link is named by the resolved path git wrote.
- (NSArray<NSString *> *)readRoots {
    NSArray *roots = self.roots;
    @synchronized (self) { return _realRoots.count ? [roots arrayByAddingObjectsFromArray:_realRoots] : roots; }
}

/// path as text in its resolved form, through the pairs of the last walk.
- (NSString *)resolved:(NSString *)path {
    NSDictionary *pairs;
    @synchronized (self) { pairs = _pairs; }
    return Resolved(path, pairs);
}
- (BOOL)walked { @synchronized (self) { return _walked; } }

#pragma mark Walks

/// YES when a change in dir can add or remove a checkout: a .git folder, or a folder near a root that is not inside
/// a known checkout. Edits inside a project change nothing here.
- (BOOL)matters:(NSString *)dir {
    // Issue #101: every path here is compared in its resolved form, which FSEvents gives for a root that is a link.
    // The pairs, the git dirs and the resolved roots come from one finished walk, read in one lock.
    NSArray *realRoots;
    NSDictionary *real, *pairs;
    @synchronized (self) { pairs = _pairs; real = _realDirs; realRoots = _pairRoots; }
    if (!realRoots) realRoots = self.roots;   // before the first walk ends
    dir = ResolvedForm(dir, pairs);
    if ([dir hasSuffix:@"/.git/worktrees"]) return YES;   // git worktree add, remove or prune
    if ([dir.lastPathComponent isEqualToString:@".git"]) {
        // A known repo's .git changes on every commit and index write, which adds no checkout.
        for (NSDictionary *d in real.allValues) if ([d[@"common"] isEqualToString:dir]) return NO;
        return YES;
    }
    if ([dir containsString:@"/.git/"]) return NO;
    for (MMWorktree *w in self.worktrees) if (PathIn(dir, w.realPath)) return NO;
    for (NSString *r in realRoots) {
        if (!PathIn(dir, r)) continue;
        NSInteger depth = (NSInteger)[dir substringFromIndex:r.length].pathComponents.count - 1;
        if (depth < kRootDepth) return YES;
    }
    return NO;
}

- (void)refresh:(NSSet<NSString *> *)changedDirs {
    if (changedDirs) {
        BOOL any = NO;
        for (NSString *d in changedDirs) if ([self matters:d]) { any = YES; break; }
        if (!any) return;
    }
    @synchronized (self) {
        if (_walking) { _again = YES; return; }
        NSTimeInterval since = _lastWalk ? -_lastWalk.timeIntervalSinceNow : INFINITY;
        if (changedDirs && since < kWalkGap) {
            // Folders still change. One walk runs when the gap has passed.
            _walking = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kWalkGap - since) * NSEC_PER_SEC)),
                           ReposQueue(), ^{ [self walk]; });
            return;
        }
        _walking = YES;
    }
    dispatch_async(ReposQueue(), ^{ [self walk]; });
}

/// One walk in the worker. _walking is YES while it runs.
- (void)walk {
    [self count:@"walks" by:1];
    NSArray *roots = self.roots;
    // Each root resolved once per walk, off main, so a change under a root that is a link maps to its checkouts.
    NSMutableArray *realRoots = [NSMutableArray new];
    for (NSString *r in roots) {
        char real[PATH_MAX];
        [realRoots addObject:realpath(r.fileSystemRepresentation, real) ? @(real) : r];
    }
    @synchronized (self) { _realRoots = realRoots; }
    if (!roots.count) { [self finish:@[]]; return; }
    [MMSharedWorker() findWorktrees:roots skip:SkipNames() reply:^(NSArray<NSDictionary *> *found, NSError *error) {
        if (!found) {   // the worker failed: keep what was known
            @synchronized (self) { self->_walking = NO; self->_lastWalk = NSDate.date; }
            [self count:@"walksDone" by:1];
            return;
        }
        NSMutableArray *trees = [NSMutableArray new];
        NSMutableDictionary *dirs = [NSMutableDictionary new];
        for (NSDictionary *e in found) {
            if (![e isKindOfClass:NSDictionary.class] || ![e[@"path"] isKindOfClass:NSString.class]) continue;
            [trees addObject:[MMWorktree path:e[@"path"] repo:e[@"repo"] ?: e[@"path"]
                                       branch:[e[@"branch"] isKindOfClass:NSString.class] ? e[@"branch"] : nil
                                       locked:[e[@"locked"] boolValue]]];
            if ([e[@"gitDir"] isKindOfClass:NSString.class] && [e[@"common"] isKindOfClass:NSString.class])
                dirs[e[@"path"]] = @{@"gitDir": e[@"gitDir"], @"common": e[@"common"]};
        }
        [self finish:trees dirs:dirs];
    }];
}

- (void)finish:(NSArray<MMWorktree *> *)trees { [self finish:trees dirs:@{}]; }

/// known holds the git dirs the worker read on its walk. The others are read here.
- (void)finish:(NSArray<MMWorktree *> *)trees dirs:(NSDictionary<NSString *, NSDictionary *> *)known {
    // Issue #101: a root that is a link gives a linked worktree twice, once from the walk and once from
    // .git/worktrees, where git wrote the resolved path, and a link listed beside its target gives every checkout
    // twice. Both entries stay, as before: the graph names an owner by the entry whose path the process, session or
    // finding names, so dropping either would move ids. The readers that count go by WorkForest's one finding per
    // folder, and a change marks every entry of its folder.
    NSArray *sorted = [trees sortedArrayUsingComparator:^NSComparisonResult(MMWorktree *a, MMWorktree *b) {
        if (a.path.length != b.path.length) return a.path.length > b.path.length ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    NSArray *roots = self.roots, *realRoots;
    @synchronized (self) { realRoots = _realRoots ?: @[]; }
    NSMutableArray<NSArray<NSString *> *> *pairs = [NSMutableArray new];
    for (NSUInteger i = 0; i < roots.count && i < realRoots.count; i++)
        if (![roots[i] isEqualToString:realRoots[i]]) [pairs addObject:@[roots[i], realRoots[i]]];
    for (MMWorktree *w in sorted) if (![w.path isEqualToString:w.realPath]) [pairs addObject:@[w.path, w.realPath]];
    NSDictionary<NSString *, NSString *> *pairMap = PairMap(pairs);
    // The git dirs of every worktree, so a change in one maps to its worktrees with no disk read.
    NSMutableDictionary *dirs = [NSMutableDictionary new];
    NSMutableDictionary *realDirs = [NSMutableDictionary new];
    for (MMWorktree *w in sorted) {
        NSDictionary *d = known[w.path] ?: MMGitDirsOf(w.path);
        if (!d) continue;
        dirs[w.path] = d;
        realDirs[w.path] = @{@"gitDir": Resolved(d[@"gitDir"], pairMap), @"common": Resolved(d[@"common"], pairMap)};
    }
    NSSet *live = [NSSet setWithArray:[sorted valueForKey:@"path"]];
    BOOL again, changed;
    NSArray<NSArray *> *early;
    @synchronized (self) {
        early = [_early copy]; [_early removeAllObjects];
        changed = ![[_trees valueForKey:@"path"] isEqual:[sorted valueForKey:@"path"]] ||
                  ![[_trees valueForKey:@"branch"] isEqual:[sorted valueForKey:@"branch"]] ||
                  ![[_trees valueForKey:@"locked"] isEqual:[sorted valueForKey:@"locked"]];
        _trees = sorted;
        _walked = YES;
        _lastWalk = NSDate.date;
        _walking = NO;
        again = _again;
        _again = NO;
        _dirs = dirs;
        _realDirs = realDirs;
        _pairs = pairMap;
        _pairRoots = realRoots;
        for (NSString *p in _facts.allKeys) if (![live containsObject:p]) [_facts removeObjectForKey:p];
        // Every fingerprint is read again after a walk. git runs only where one moved.
        for (MMWorktree *w in sorted) _marked[w.path] = w;
    }
    // A linked worktree outside every root has no stream, so a change to its files is never seen.
    // Its status is read again on every walk instead.
    for (MMWorktree *w in sorted) {
        BOOL watched = NO;
        for (NSString *r in roots) if (PathIn(w.path, r.stringByStandardizingPath)) { watched = YES; break; }
        for (NSString *r in realRoots) if (!watched && PathIn(w.realPath, r)) watched = YES;   // the stream of a linked root
        if (!watched) [self dropStatus:w];
    }
    if ([self loadCaches] && self.roots.count) {
        [_git forget:live];
        [_sizes forget:live];
    }
    // A restart's replayed changes may come before the first walk. They apply now that the worktrees are known.
    for (NSArray *e in early) [self invalidate:e[0] == NSNull.null ? nil : e[0] subtrees:[e[1] boolValue]];
    [self count:@"walksDone" by:1];
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:MMRepoIndexDidChangeNotification object:self];
    if (sorted.count) [self updateFacts:nil];
    if (again) [self refresh:nil];
}

- (MMWorktree *)worktreeAt:(NSString *)path {
    if (!path.length) return nil;
    NSString *p = path.stringByStandardizingPath;
    NSArray *trees = self.worktrees;
    for (MMWorktree *w in trees) if (PathIn(p, w.path)) return w;
    // Issue #101: a process's folder, or a WorkForest finding's path, names a checkout under a root that is a link by
    // its resolved path. A caller that cuts a subfolder from the answer cuts by MMWorktreeFolderFor.
    MMWorktree *held = MMWorktreeHolding(trees, p) ?: MMWorktreeHolding(trees, [self resolved:p]);
    if (held) return held;
    // Not walked: read the .git files above it.
    for (NSString *dir = p; dir.length > 1; dir = dir.stringByDeletingLastPathComponent) {
        MMWorktree *w = CheckoutAt(dir);
        if (w) return w;
    }
    return nil;
}

#pragma mark Changes

/// A change among the worktree's files: its status layer goes, on disk too, so a restart computes it again.
- (void)dropStatus:(MMWorktree *)w {
    BOOL caches = [self loadCaches];
    // Issue #84: the mark and the cached fingerprint go in one step. updateOne reads both under the same lock, so it
    // sees a drop whole or not at all, and one change costs one git status.
    @synchronized (_statusLock) {
        @synchronized (self) { [_dropped addObject:w.path]; _marked[w.path] = w; }
        NSDictionary *v = caches ? [_git peek:w.path] : nil;
        if ([v isKindOfClass:NSDictionary.class] && v[@"sfp"]) {
            NSMutableDictionary *m = [v mutableCopy];
            [m removeObjectForKey:@"sfp"];
            [_git setValue:m for:w.path fingerprint:@""];
        }
    }
    if (!caches) return;
    NSDictionary *size = [_sizes peek:w.path];
    if (size && ![_sizes changed:w.path fingerprint:@"stale"]) return;
    if (size) [_sizes setValue:size for:w.path fingerprint:@"stale"];
}

/// What one changed folder d, resolved, marks: the checkouts whose git dir it is in, to check, else the deepest
/// checkout that holds it, and with subtrees every one below it, to drop.
static void MarkFor(NSString *d, NSArray<MMWorktree *> *trees, NSDictionary<NSString *, NSDictionary *> *dirsOf, BOOL subtrees,
                    NSMutableDictionary<NSString *, MMWorktree *> *check, NSMutableDictionary<NSString *, MMWorktree *> *drop) {
    NSString *gitRoot = nil, *rest = nil;
    if (InGitDir(d, &gitRoot, &rest)) {
        // A worktree's own git dir under .git/worktrees/<name>, or the repo's shared refs and config.
        NSArray *parts = [rest componentsSeparatedByString:@"/"];   // "", "worktrees", name, ...
        NSString *own = parts.count >= 3 && [parts[1] isEqualToString:@"worktrees"] ?
            [[gitRoot stringByAppendingPathComponent:@"worktrees"] stringByAppendingPathComponent:parts[2]] : nil;
        for (MMWorktree *w in trees) {
            NSDictionary *x = dirsOf[w.path];
            if (own ? [x[@"gitDir"] isEqualToString:own] : [x[@"common"] isEqualToString:gitRoot]) check[w.path] = w;
        }
        return;
    }
    // The deepest checkout that holds it, with every other entry of that folder: d's folders up, in the name table.
    MMWorktreeNames *x = NamesOf(trees);
    for (NSString *p = d; p.length; p = Up(p)) {
        NSArray<MMWorktree *> *c = x.real[p];
        if (!c) continue;
        for (MMWorktree *w in c) drop[w.path] = w;
        break;
    }
    if (subtrees) for (MMWorktree *w in trees) if (PathIn(w.realPath, d)) drop[w.path] = w;
}

- (void)invalidate:(NSSet<NSString *> *)dirs subtrees:(BOOL)subtrees {
    NSArray<MMWorktree *> *trees;
    NSDictionary<NSString *, NSDictionary *> *dirsOf;
    NSDictionary *pairs;
    @synchronized (self) {
        if (!_lastWalk) { [_early addObject:@[dirs ?: NSNull.null, @(subtrees)]]; return; }
        trees = _trees ?: @[];
        dirsOf = _realDirs;
        pairs = _pairs;
    }
    NSMutableDictionary<NSString *, MMWorktree *> *check = [NSMutableDictionary new], *drop = [NSMutableDictionary new];
    if (!dirs) for (MMWorktree *w in trees) drop[w.path] = w;
    for (NSString *raw in dirs) {
        // FSEvents names real paths, such as /private/var or the target of a root that is a link, and the walk keeps
        // the paths the roots gave. Issue #101: both sides are compared resolved, as text.
        NSString *d = ResolvedForm(raw, pairs);
        MarkFor(d, trees, dirsOf, subtrees, check, drop);
        // A /tmp or /var form no pair held names the /private folder a checkout resolves to.
        if ([d hasPrefix:@"/tmp/"] || [d hasPrefix:@"/var/"]) MarkFor([@"/private" stringByAppendingString:d], trees, dirsOf, subtrees, check, drop);
    }
    for (MMWorktree *w in drop.allValues) [self dropStatus:w];
    @synchronized (self) { [_marked addEntriesFromDictionary:check]; }
    if (check.count || drop.count) [self updateFacts:nil];
}

#pragma mark Git facts

/// A change in a known git dir starts no walk, so a branch switch or `git worktree lock` lands here instead.
/// The checkout is read again from its .git files, with no spawn, and replaces the walked one when its branch
/// or its lock moved.
- (void)recheckTree:(NSString *)path dirs:(NSDictionary *)dirs files:(NSDictionary *)files {
    // Issue #54: from what updateOne already read, the branch from HEAD in files and the lock with one stat,
    // where CheckoutAt read .git, commondir and HEAD again for every worktree on every pass.
    NSString *gitDir = dirs[@"gitDir"], *common = dirs[@"common"];
    BOOL isMain = [gitDir isEqualToString:common];
    struct stat st;
    BOOL locked = !isMain && stat([gitDir stringByAppendingPathComponent:@"locked"].fileSystemRepresentation, &st) == 0;
    NSString *branch = files[@"branch"];
    MMWorktree *now = nil;
    @synchronized (self) {
        NSUInteger i = 0;
        for (MMWorktree *x in _trees) {
            if ([x.path isEqualToString:path]) {
                BOOL sameBranch = x.branch == branch || [x.branch isEqualToString:branch];
                if (sameBranch && x.locked == locked) return;
                NSString *repo = isMain ? path : [common.lastPathComponent isEqualToString:@".git"] ? common.stringByDeletingLastPathComponent : common;
                now = [MMWorktree path:path real:x.realPath repo:repo branch:branch locked:locked];   // no realpath in the lock
                NSMutableArray *trees = [_trees mutableCopy];
                trees[i] = now;
                _trees = [trees copy];   // immutable, as the holder lookups' name table wants
                break;
            }
            i++;
        }
    }
    if (now) [NSNotificationCenter.defaultCenter postNotificationName:MMRepoIndexDidChangeNotification object:self];
}

/// Reads one worktree's fingerprints and runs git where one moved. Returns the facts, or nil when the path holds
/// no checkout. ran is YES when git ran, changed when the facts differ from the cached ones.
- (MMGitFacts *)updateOne:(MMWorktree *)w force:(BOOL)force ran:(BOOL *)ran changed:(BOOL *)changed {
    NSString *path = w.path;
    *ran = NO; *changed = NO;
    NSDictionary *dirs;
    @synchronized (self) { dirs = _dirs[path]; }
    BOOL readable = ReadableAt(path, [self readRoots]);
    if (!dirs && readable) dirs = MMGitDirsOf(path);
    if (!dirs || !readable) {
        @synchronized (self) {
            *changed = _facts[path] && _facts[path] != NSNull.null; _facts[path] = NSNull.null;
            [_dropped removeObject:path];
        }
        [_git drop:path];
        return nil;
    }
    [self count:@"fingerprintReads" by:1];
    NSDictionary *files = MMGitReadFiles(dirs[@"gitDir"], dirs[@"common"]);
    [self recheckTree:path dirs:dirs files:files];
#ifdef MM_TESTS
    if (MMRepoIndexTestStep) MMRepoIndexTestStep(@"read", path);
#endif
    // Issue #84: the drop is taken here, in one step with the cached status. Taken at the top of this method, a
    // change that came between the two cost two runs of git status: one for the fingerprint the drop had removed,
    // and one more in the next pass for the drop itself.
    NSDictionary *old;
    @synchronized (_statusLock) {
        old = [_git peek:path];
        @synchronized (self) { if ([_dropped containsObject:path]) { force = YES; [_dropped removeObject:path]; } }
    }
    if (![old isKindOfClass:NSDictionary.class]) old = nil;
    NSString *sfp = MMGitStatusFingerprint(files), *hfp = MMGitHistoryFingerprint(files, w.isMain);
    NSMutableDictionary *counts = [NSMutableDictionary new];
    NSDictionary *status = old[@"status"], *history = old[@"history"];
    BOOL statusOK = !force && status && [old[@"sfp"] isEqualToString:sfp];
    if (!statusOK) { status = MMGitStatusOf(path, counts); [self count:@"statusRuns" by:1]; *ran = YES; }
    if (!history || ![old[@"hfp"] isEqualToString:hfp]) {
        history = MMGitHistoryOf(path, files, w.isMain, _patchIds, counts);
        [self count:@"historyRuns" by:1];
        *ran = YES;
    }
    for (NSString *k in counts) [self count:k by:[counts[k] integerValue]];
    NSMutableDictionary *value = [@{@"files": files, @"status": status, @"history": history, @"hfp": hfp} mutableCopy];
    if ([status[@"dirty"] integerValue] >= 0) value[@"sfp"] = sfp;   // a failed status is asked again next time
    *changed = !old || ![old[@"files"] isEqual:files] || ![old[@"status"] isEqual:status] || ![old[@"history"] isEqual:history];
#ifdef MM_TESTS
    if (MMRepoIndexTestStep) MMRepoIndexTestStep(@"write", path);
#endif
    @synchronized (_statusLock) {
        // A change that came while git ran left its drop for the next pass. Until then the status is kept with no
        // fingerprint, as the drop wrote it, so a restart in between computes it again.
        @synchronized (self) { if ([_dropped containsObject:path]) [value removeObjectForKey:@"sfp"]; }
        if (![value isEqual:old]) [_git setValue:value for:path fingerprint:@""];
    }
    MMGitFacts *g = [MMGitFacts fromValue:value];
    @synchronized (self) { _facts[path] = g ?: NSNull.null; }
    return g;
}

- (void)updateFacts:(void (^)(NSUInteger ran))done {
    @synchronized (self) {
        if (done) [_dones addObject:[done copy]];
        if (_updating) { _updateAgain = YES; return; }
        _updating = YES;
    }
    dispatch_async(GitQueue(), ^{ [self runUpdates]; });
}

/// How many repos an update pass works on at once: half the cores, at most 4, so git children never crowd the Mac.
static size_t UpdateWidth(void) {
    NSUInteger cores = NSProcessInfo.processInfo.activeProcessorCount;
    return (size_t)MAX(1, MIN(4, cores / 2));
}

/// Passes on the git queue until no worktree is marked. A done block runs after the pass that started after it.
- (void)runUpdates {
    [self loadCaches];
    for (;;) {
        NSDictionary<NSString *, MMWorktree *> *marked;
        NSArray *dones;
        @synchronized (self) {
            marked = [_marked copy]; [_marked removeAllObjects];
            dones = [_dones copy]; [_dones removeAllObjects];
            _updateAgain = NO;
        }
        NSDate *t0 = NSDate.date;
        __block _Atomic NSUInteger ran = 0;
        __block _Atomic BOOL anyChanged = NO;
        // Issue #54: the repos in parallel, a few at a time, and each repo's worktrees in turn, so one repo's
        // patch ids are computed once. A cold pass over 300 worktrees in 30 repos ran 2,181 git children one by one.
        NSMutableDictionary<NSString *, NSMutableArray<MMWorktree *> *> *byRepo = [NSMutableDictionary new];
        for (NSString *p in marked) {
            MMWorktree *w = marked[p];
            NSString *repo = w.repo.length ? w.repo : p;
            if (!byRepo[repo]) byRepo[repo] = [NSMutableArray new];
            [byRepo[repo] addObject:w];
        }
        NSArray<NSArray<MMWorktree *> *> *groups = [byRepo.allValues sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            return a.count > b.count ? NSOrderedAscending : a.count < b.count ? NSOrderedDescending : NSOrderedSame;   // largest first
        }];
        // Each lane is a labeled serial queue of its own, core.git.1 to core.git.4. This queue waits for them.
        __block _Atomic NSUInteger next = 0;
        size_t width = MIN(groups.count, UpdateWidth());
        dispatch_group_t lanes = dispatch_group_create();
        for (size_t lane = 1; lane <= width; lane++)
            dispatch_group_async(lanes, MMQueue(@"core", [NSString stringWithFormat:@"git.%zu", lane], QOS_CLASS_UTILITY), ^{
                for (NSUInteger i; (i = atomic_fetch_add(&next, 1)) < groups.count;)
                    for (MMWorktree *w in groups[i]) @autoreleasepool {
                        BOOL r = NO, c = NO;
                        [self updateOne:w force:NO ran:&r changed:&c];
                        if (r) atomic_fetch_add(&ran, 1);
                        if (c) anyChanged = YES;
                    }
            });
        dispatch_group_wait(lanes, DISPATCH_TIME_FOREVER);
        @synchronized (_counts) {
            _counts[@"lastUpdateMs"] = @((NSInteger)llround(-t0.timeIntervalSinceNow * 1000));
            _counts[@"lastUpdateRan"] = @(ran);
            _counts[@"lastUpdateChecked"] = @(marked.count);
            _counts[@"updates"] = @([_counts[@"updates"] integerValue] + 1);
        }
        if (anyChanged) [NSNotificationCenter.defaultCenter postNotificationName:MMRepoIndexFactsDidChangeNotification object:self];
        for (void (^d)(NSUInteger) in dones) d(ran);
        @synchronized (self) {
            if (!_updateAgain && !_marked.count && !_dones.count) { _updating = NO; return; }
        }
    }
}

- (MMGitFacts *)factsFor:(MMWorktree *)w wait:(BOOL)wait {
    if (!w.path.length) return nil;
    if (wait) {
        if (NSThread.isMainThread) return nil;
        __block MMGitFacts *g = nil;
        dispatch_block_t work = ^{
            [self loadCaches];
            BOOL r = NO, c = NO;
            g = [self updateOne:w force:YES ran:&r changed:&c];
            if (c) [NSNotificationCenter.defaultCenter postNotificationName:MMRepoIndexFactsDidChangeNotification object:self];
        };
        if (MMGitOnFreshRead()) work(); else dispatch_sync(FreshQueue(), work);
        return g;
    }
    id g;
    BOOL marked;
    @synchronized (self) { g = _facts[w.path]; marked = _marked[w.path] != nil; }
    if (!g && [self loadCaches]) {
        // Facts from the last launch, until this launch has read the fingerprints.
        g = [MMGitFacts fromValue:[_git peek:w.path]];
        @synchronized (self) {
            if (g && !_facts[w.path]) _facts[w.path] = g;
            if (!g) _marked[w.path] = w;
        }
        if (!g) marked = YES;
    }
    if (marked) [self updateFacts:nil];
    return g == NSNull.null ? nil : g;
}

#pragma mark Sizes

- (NSDictionary *)sizeFor:(MMWorktree *)w wait:(BOOL)wait {
    NSString *path = w.path;
    if (!path.length || (wait && NSThread.isMainThread) || !ReadableAt(path, [self readRoots])) return nil;
    if (![self loadCaches]) return nil;   // on main before the caches were read
    NSDictionary *have = [_sizes peek:path];
    BOOL stale = [_sizes changed:path fingerprint:@"ok"];
    if (!wait && !stale) return have;
    if (!wait) {
        @synchronized (self) {
            NSDate *asked = _sizeAsked[path];
            if (asked && -asked.timeIntervalSinceNow < kSizeGap) return have;
            _sizeAsked[path] = NSDate.date;
        }
    }
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    __block NSDictionary *size = nil;
    [self count:@"sizeWalks" by:1];
    MMFactCache *cache = _sizes;
    [MMSharedWorker() sizeTrees:@[path] reply:^(NSDictionary<NSString *, NSDictionary *> *sizes, NSError *error) {
        NSDictionary *s = [sizes[path] isKindOfClass:NSDictionary.class] ? sizes[path] : nil;
        if (s) [cache setValue:s for:path fingerprint:@"ok"];
        size = s;
        dispatch_semaphore_signal(got);
    }];
    if (!wait) return have;
    dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
    return size ?: have;
}

#pragma mark Watching

- (void)startWatching {
    if (NSThread.isMainThread) { dispatch_async(ReposQueue(), ^{ [self startWatching]; }); return; }
    NSUInteger gen;
    @synchronized (self) { if (_watches) return; _watches = @[]; gen = _watchGen; }
    NSMutableArray *watches = [NSMutableArray new];
    __weak MMRepoIndex *weak = self;
    for (NSString *root in self.roots) {
        MMFolderWatch *fw = [MMFolderWatch watch:@[root] name:[@"repos." stringByAppendingString:RootHash(root)] skip:WatchSkip()
                                         changed:^(NSSet<NSString *> *dirs, BOOL rescan) {
            MMRepoIndex *me = weak;
            [me invalidate:dirs subtrees:rescan];
            [me refresh:rescan ? nil : dirs];
        }];
        if (fw) [watches addObject:fw];
    }
    BOOL stopped;
    @synchronized (self) { stopped = gen != _watchGen; if (!stopped) _watches = watches; }
    if (stopped) for (MMFolderWatch *fw in watches) [fw stop];   // stopWatching came while the streams started
}

- (void)stopWatching {
    NSArray *watches;
    @synchronized (self) { watches = _watches; _watches = nil; _watchGen++; }
    for (MMFolderWatch *fw in watches) [fw stop];
}

@end
