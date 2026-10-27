// MMRepoIndex and MMWorktree, pattern P25. The walk runs in the worker of P4 through MMSharedWorker(),
// so a slow disk never holds up the app. worktreeAt: reads .git files with no spawn, from ReadGit in LH Ports.m:265.
// Git facts, P26, come in phase 2 with WorkForest. Until then factsFor:wait: returns nil, which every reader
// treats as "not known yet".
#import "Core/Know/MMGit.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#import "Core/Store/MMStore.h"

NSNotificationName const MMRepoIndexDidChangeNotification = @"MMRepoIndexDidChangeNotification";

static const NSTimeInterval kWalkGap = 10;      // at most one walk this often while folders change
static const NSInteger kRootDepth = 4;          // as deep as the worker walks below a root

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

@implementation MMGitFacts
@end

static NSString *ReadLine(NSString *path) {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *BranchIn(NSString *gitDir) {
    NSString *head = ReadLine([gitDir stringByAppendingPathComponent:@"HEAD"]);
    return [head hasPrefix:@"ref: refs/heads/"] ? [head substringFromIndex:16] : nil;
}

/// The checkout at dir, read from its .git, or nil when dir holds no .git.
static MMWorktree *CheckoutAt(NSString *dir) {
    NSString *dotgit = [dir stringByAppendingPathComponent:@".git"];
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:dotgit isDirectory:&isDir]) return nil;
    if (isDir) return [MMWorktree path:dir repo:dir branch:BranchIn(dotgit) locked:NO];
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
    BOOL locked = [NSFileManager.defaultManager fileExistsAtPath:[gitDir stringByAppendingPathComponent:@"locked"]];
    return [MMWorktree path:dir repo:repo branch:BranchIn(gitDir) locked:locked];
}

#pragma mark - The index

@implementation MMRepoIndex {
    NSArray<NSString *> *_roots;
    NSArray<MMWorktree *> *_trees;     // deepest path first
    BOOL _walking, _again;              // a walk is in flight; another was asked for meanwhile
    NSDate *_lastWalk;
}

+ (instancetype)shared {
    static MMRepoIndex *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMRepoIndex new]; });
    return s;
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

/// YES when a change in dir can add or remove a checkout: a .git folder, or a folder near a root that is not inside
/// a known checkout. Edits inside a project change nothing here.
- (BOOL)matters:(NSString *)dir {
    if ([dir.lastPathComponent isEqualToString:@".git"] || [dir containsString:@"/.git/worktrees"]) return YES;
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
                           MMQueue(@"core", @"repos", QOS_CLASS_UTILITY), ^{ [self walk]; });
            return;
        }
        _walking = YES;
    }
    dispatch_async(MMQueue(@"core", @"repos", QOS_CLASS_UTILITY), ^{ [self walk]; });
}

/// One walk in the worker. _walking is YES while it runs.
- (void)walk {
    NSArray *roots = self.roots;
    if (!roots.count) { [self finish:@[]]; return; }
    [MMSharedWorker() findWorktrees:roots skip:SkipNames() reply:^(NSArray<NSDictionary *> *found, NSError *error) {
        if (!found) {   // the worker failed: keep what was known
            @synchronized (self) { self->_walking = NO; self->_lastWalk = NSDate.date; }
            return;
        }
        NSMutableArray *trees = [NSMutableArray new];
        for (NSDictionary *e in found) {
            if (![e isKindOfClass:NSDictionary.class] || ![e[@"path"] isKindOfClass:NSString.class]) continue;
            [trees addObject:[MMWorktree path:e[@"path"] repo:e[@"repo"] ?: e[@"path"]
                                       branch:[e[@"branch"] isKindOfClass:NSString.class] ? e[@"branch"] : nil
                                       locked:[e[@"locked"] boolValue]]];
        }
        [self finish:trees];
    }];
}

- (void)finish:(NSArray<MMWorktree *> *)trees {
    NSArray *sorted = [trees sortedArrayUsingComparator:^NSComparisonResult(MMWorktree *a, MMWorktree *b) {
        if (a.path.length != b.path.length) return a.path.length > b.path.length ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    BOOL again, changed;
    @synchronized (self) {
        changed = ![[_trees valueForKey:@"path"] isEqual:[sorted valueForKey:@"path"]] ||
                  ![[_trees valueForKey:@"branch"] isEqual:[sorted valueForKey:@"branch"]];
        _trees = sorted;
        _lastWalk = NSDate.date;
        _walking = NO;
        again = _again;
        _again = NO;
    }
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:MMRepoIndexDidChangeNotification object:self];
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

- (MMGitFacts *)factsFor:(MMWorktree *)w wait:(BOOL)wait { return nil; }

@end
