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

static BOOL PathIn(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    return [path isEqualToString:folder] || [path hasPrefix:[folder hasSuffix:@"/"] ? folder : [folder stringByAppendingString:@"/"]];
}

/// With MINMACS_HOME set, as in a test or the bench, git and size walks never run in the person's home folder,
/// unless the path lies inside MINMACS_HOME or one of the index's roots. Fixtures live under TMPDIR or in the test
/// home. Issue #54 found the bench's real process table led the index to run git in the person's repos.
static BOOL ReadableAt(NSString *path, NSArray<NSString *> *roots) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (!home.length) return YES;
    NSString *p = path.stringByStandardizingPath, *mine = NSHomeDirectory().stringByStandardizingPath;
    if (!PathIn(p, mine)) return YES;
    if (PathIn(p, home.stringByStandardizingPath)) return YES;
    for (NSString *r in roots) if (PathIn(p, r.stringByStandardizingPath)) return YES;
    return NO;
}

#pragma mark - Worktrees

@interface MMWorktree ()
@property (readwrite, copy) NSString *path, *repo, *branch, *lockReason, *makerSession;
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

+ (instancetype)path:(NSString *)path repo:(NSString *)repo branch:(NSString *)branch locked:(BOOL)locked {
    MMWorktree *w = [MMWorktree new];
    w.path = path; w.repo = repo; w.branch = branch; w.locked = locked;
    w.isMain = [path isEqualToString:repo];
    w.maker = MakerOf(path);
    return w;
}

- (NSString *)description { return [NSString stringWithFormat:@"<MMWorktree %@ %@>", self.path, self.branch ?: @"detached"]; }

@end

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
static dispatch_queue_t FreshQueue(void) { return MMQueue(@"core", @"git.fresh", QOS_CLASS_UTILITY); }

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

@implementation MMRepoIndex {
    NSArray<NSString *> *_roots;
    NSArray<MMWorktree *> *_trees;     // deepest path first
    BOOL _walking, _again;              // a walk is in flight; another was asked for meanwhile
    NSDate *_lastWalk;
    // Git facts and sizes.
    MMFactCache *_git, *_patchIds, *_sizes;                     // persisted; nil until first used off main
    NSMutableDictionary<NSString *, NSDictionary *> *_dirs;    // path: {gitDir, common}
    NSMutableDictionary<NSString *, id> *_facts;               // path: MMGitFacts, or NSNull when the path holds none
    NSMutableDictionary<NSString *, MMWorktree *> *_marked;    // fingerprints to read in the next pass
    NSMutableSet<NSString *> *_dropped;                        // status layers a change dropped
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
        _counts = [NSMutableDictionary new]; _early = [NSMutableArray new];
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

#pragma mark Walks

/// YES when a change in dir can add or remove a checkout: a .git folder, or a folder near a root that is not inside
/// a known checkout. Edits inside a project change nothing here.
- (BOOL)matters:(NSString *)dir {
    dir = dir.stringByStandardizingPath;
    if ([dir hasSuffix:@"/.git/worktrees"]) return YES;   // git worktree add, remove or prune
    if ([dir.lastPathComponent isEqualToString:@".git"]) {
        // A known repo's .git changes on every commit and index write, which adds no checkout.
        NSDictionary *dirs;
        @synchronized (self) { dirs = [_dirs copy]; }
        for (NSDictionary *d in dirs.allValues) if ([d[@"common"] isEqualToString:dir]) return NO;
        return YES;
    }
    if ([dir containsString:@"/.git/"]) return NO;
    for (MMWorktree *w in self.worktrees) if (PathIn(dir, w.path)) return NO;
    for (NSString *r in self.roots) {
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
    NSArray *sorted = [trees sortedArrayUsingComparator:^NSComparisonResult(MMWorktree *a, MMWorktree *b) {
        if (a.path.length != b.path.length) return a.path.length > b.path.length ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    // The git dirs of every worktree, so a change in one maps to its worktrees with no disk read.
    NSMutableDictionary *dirs = [NSMutableDictionary new];
    for (MMWorktree *w in sorted) { NSDictionary *d = known[w.path] ?: MMGitDirsOf(w.path); if (d) dirs[w.path] = d; }
    NSSet *live = [NSSet setWithArray:[sorted valueForKey:@"path"]];
    BOOL again, changed;
    NSArray<NSArray *> *early;
    @synchronized (self) {
        early = [_early copy]; [_early removeAllObjects];
        changed = ![[_trees valueForKey:@"path"] isEqual:[sorted valueForKey:@"path"]] ||
                  ![[_trees valueForKey:@"branch"] isEqual:[sorted valueForKey:@"branch"]] ||
                  ![[_trees valueForKey:@"locked"] isEqual:[sorted valueForKey:@"locked"]];
        _trees = sorted;
        _lastWalk = NSDate.date;
        _walking = NO;
        again = _again;
        _again = NO;
        _dirs = dirs;
        for (NSString *p in _facts.allKeys) if (![live containsObject:p]) [_facts removeObjectForKey:p];
        // Every fingerprint is read again after a walk. git runs only where one moved.
        for (MMWorktree *w in sorted) _marked[w.path] = w;
    }
    // A linked worktree outside every root has no stream, so a change to its files is never seen.
    // Its status is read again on every walk instead.
    NSArray *roots = self.roots;
    for (MMWorktree *w in sorted) {
        BOOL watched = NO;
        for (NSString *r in roots) if (PathIn(w.path, r.stringByStandardizingPath)) { watched = YES; break; }
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
    for (MMWorktree *w in self.worktrees) if (PathIn(p, w.path)) return w;
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
    @synchronized (self) { [_dropped addObject:w.path]; _marked[w.path] = w; }
    if (![self loadCaches]) return;
    NSDictionary *v = [_git peek:w.path];
    if ([v isKindOfClass:NSDictionary.class] && v[@"sfp"]) {
        NSMutableDictionary *m = [v mutableCopy];
        [m removeObjectForKey:@"sfp"];
        [_git setValue:m for:w.path fingerprint:@""];
    }
    NSDictionary *size = [_sizes peek:w.path];
    if (size && ![_sizes changed:w.path fingerprint:@"stale"]) return;
    if (size) [_sizes setValue:size for:w.path fingerprint:@"stale"];
}

- (void)invalidate:(NSSet<NSString *> *)dirs subtrees:(BOOL)subtrees {
    NSArray<MMWorktree *> *trees;
    NSDictionary<NSString *, NSDictionary *> *dirsOf;
    @synchronized (self) {
        if (!_lastWalk) { [_early addObject:@[dirs ?: NSNull.null, @(subtrees)]]; return; }
        trees = _trees ?: @[];
        dirsOf = [_dirs copy];
    }
    NSMutableDictionary<NSString *, MMWorktree *> *check = [NSMutableDictionary new], *drop = [NSMutableDictionary new];
    if (!dirs) for (MMWorktree *w in trees) drop[w.path] = w;
    for (NSString *raw in dirs) {
        // FSEvents names real paths, such as /private/var, and the walk keeps standardized ones.
        NSString *d = raw.stringByStandardizingPath;
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
            continue;
        }
        for (MMWorktree *w in trees) if (PathIn(d, w.path)) { drop[w.path] = w; break; }   // deepest first
        if (subtrees) for (MMWorktree *w in trees) if (PathIn(w.path, d)) drop[w.path] = w;
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
                now = [MMWorktree path:path repo:repo branch:branch locked:locked];
                NSMutableArray *trees = [_trees mutableCopy];
                trees[i] = now;
                _trees = trees;
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
    @synchronized (self) {
        dirs = _dirs[path];
        if ([_dropped containsObject:path]) { force = YES; [_dropped removeObject:path]; }
    }
    BOOL readable = ReadableAt(path, self.roots);
    if (!dirs && readable) dirs = MMGitDirsOf(path);
    if (!dirs || !readable) {
        @synchronized (self) { *changed = _facts[path] && _facts[path] != NSNull.null; _facts[path] = NSNull.null; }
        [_git drop:path];
        return nil;
    }
    [self count:@"fingerprintReads" by:1];
    NSDictionary *files = MMGitReadFiles(dirs[@"gitDir"], dirs[@"common"]);
    [self recheckTree:path dirs:dirs files:files];
    NSDictionary *old = [_git peek:path];
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
    if (![value isEqual:old]) [_git setValue:value for:path fingerprint:@""];
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
        const char *label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        if (label && !strcmp(label, dispatch_queue_get_label(FreshQueue()))) work(); else dispatch_sync(FreshQueue(), work);
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
    if (!path.length || (wait && NSThread.isMainThread) || !ReadableAt(path, self.roots)) return nil;
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
