// Child processes, git, and repo and worktree discovery. Patterns P23 to P26 of SYNTHESIS.md section 1.3.
// Nothing here runs on main in the app. The CLI may call it on its own thread.
#import <Foundation/Foundation.h>

/// P23. How a child process ended.
typedef struct { int status; BOOL timedOut; BOOL didRun; } MMRunResult;   // status is -1 when it did not run

/// P23. Runs path with args, feeds input on stdin and waits at most timeout seconds.
/// Starts from WFGitInput in WF Common.m:78. A child past the limit gets SIGTERM, then SIGKILL after one second,
/// and the pipes are closed half a second later, so no reader is left behind. Its output is then not returned.
/// env is added to a clean environment, not to ours. outData and errData may be NULL.
MMRunResult MMRun(NSString *path, NSArray<NSString *> *args, NSData *input, NSDictionary<NSString *, NSString *> *env,
                  NSString *cwd, NSTimeInterval timeout, NSData **outData, NSData **errData);
/// P23. The runner under MMRun, for a task the caller set up with its own path, arguments, environment and cwd.
/// It sets the task's stdin, stdout and stderr. The review broker runs claude and codex through it.
MMRunResult MMRunTask(NSTask *task, NSData *input, NSTimeInterval timeout, NSData **outData, NSData **errData);

/// P24. git, read-only by default, with LC_ALL=C, GIT_OPTIONAL_LOCKS=0, no prompts and no pager.
/// Starts from WF Common.m:71-105. Returns stdout without the trailing newline, or nil when git could not run
/// or timed out. status is git's exit status, -1 when it did not run. status may be NULL.
/// It runs through MMRun and never on main: called on main it returns nil with status -1.
/// GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM pass through from our environment, so a test keeps the person's config out.
NSString *MMGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status);
/// nil when no real git is installed, so the Xcode stub never prompts. $MINMACS_GIT names another git.
NSString *MMGitPath(void);

/// P25. Who made a worktree. Decision 6: MinMacs acts on Claude Code's agent worktrees once their session ended,
/// and only shows Cursor's and Conductor's.
typedef NS_ENUM(NSInteger, MMWorktreeMaker) { MMMakerPerson, MMMakerClaudeCode, MMMakerCursor, MMMakerConductor };

/// P25. One checkout: a repo's main checkout or a linked worktree.
@interface MMWorktree : NSObject
@property (readonly, copy) NSString *path, *repo, *branch;   // repo: the main checkout's path
@property (readonly) BOOL isMain;
@property (readonly) BOOL locked;                       // `git worktree lock`, which counts as in use
@property (readonly, copy) NSString *lockReason;
@property (readonly) MMWorktreeMaker maker;
@property (readonly, copy) NSString *makerSession;      // Claude Code's ownership marker, its session id
@property (readonly) BOOL missing;                      // listed by git, gone from disk
@end

/// P26. How a branch reached the default branch. MMMergedNone means it did not, as far as the checks can tell.
/// Starts from WF Trees.m:134-290 and NN worktrees.go:192, plus worktrunk's simulated merge with `git merge-tree`.
typedef NS_ENUM(NSInteger, MMMergeKind) {
    MMMergedNone, MMMergedAncestor, MMMergedTree, MMMergedPatch, MMMergedSquash, MMMergedPR, MMMergedMergeTree,
};

/// P26. The git facts of one worktree, keyed by HEAD in the fact cache of P27.
/// branch, head, the default branch, the upstream and the stash count are read from git's own files.
/// The rest come from git through MMGit, on a Know queue. A count of -1 means git could not tell, which counts as dirty.
@interface MMGitFacts : NSObject
@property (readonly, copy) NSString *branch;            // nil when HEAD is detached
@property (readonly, copy) NSString *head, *defaultBranch, *upstream;   // upstream: "origin/x", nil when none is set
@property (readonly) MMMergeKind merged;
@property (readonly) NSInteger dirty, untracked, stashes, notInDefault;
@property (readonly) NSInteger unpushed;                // commits on HEAD that no remote ref holds
@property (readonly) NSInteger ahead, behind;           // against the upstream, 0 when there is none
/// P26. Remote containment, its own fact: HEAD is reachable from some remote ref.
/// Decision 7: a squash-merged HEAD on no remote goes in Eager only, after a git bundle.
@property (readonly) BOOL onRemote;
@property (readonly) BOOL upstreamGone;                 // the remote branch was deleted
@property (readonly) NSDate *lastCommit;
/// The facts as JSON, with merged as a word: none, ancestor, tree, patch, squash, pr or merge-tree.
- (NSDictionary *)json;
@end

/// P25. Every repo and worktree under the scan roots, plus a path lookup with no spawn.
/// Starts from Walk in WF Trees.m:57 and ReadGit in LH Ports.m:265.
/// The roots are the person's folders plus <repo>/.claude/worktrees/*, ~/.cursor/worktrees/*/* and
/// ~/conductor/workspaces/*/*. The walk itself runs in the worker of P4.
/// The default roots are $MINMACS_ROOTS, colon separated, when it is set. With MINMACS_HOME set and no
/// MINMACS_ROOTS there are none, so a test never walks the person's folders. Otherwise the "roots" list in
/// core/rules.json, which starts with WorkForest's roots and the Cursor and Conductor folders.
@interface MMRepoIndex : NSObject
+ (instancetype)shared;
@property (copy) NSArray<NSString *> *roots;
/// nil walks every root. FSEvents passes what changed: only a .git folder, or a folder near a root outside every
/// known checkout, starts a walk, and walks are at least 10 seconds apart. Never blocks.
- (void)refresh:(NSSet<NSString *> *)changedDirs;
- (NSArray<MMWorktree *> *)worktrees;                   // the last walk, deepest path first
/// The worktree that holds path, read from .git files with no spawn. nil outside any repo.
- (MMWorktree *)worktreeAt:(NSString *)path;
/// Through MMFactCache, in two layers that persist across launches. The status layer, dirty and untracked counts,
/// is keyed by HEAD and the index file and dropped by a change inside the worktree. The history layer, upstream,
/// counts and merge kind, is keyed by HEAD, the default branch's tip, the upstream's tip and the fetch time.
/// wait NO returns what is cached, possibly stale, or nil, reads nothing from disk, and queues an update on the
/// git queue when a change marked the worktree. wait YES runs git now for the status and for a moved history,
/// on its own Know queue, and returns nil on main.
- (MMGitFacts *)factsFor:(MMWorktree *)w wait:(BOOL)wait;
/// The quick Sizer tier for the worktree, through the worker, cached across launches. The keys are allocated,
/// freedIfDeleted, files and errors. A change inside the worktree marks its size stale. wait NO returns the last
/// size, or nil, and queues a walk at most once a minute per worktree. wait YES walks now and returns nil on main.
- (NSDictionary *)sizeFor:(MMWorktree *)w wait:(BOOL)wait;
/// Marks the worktrees a change touched. A folder inside a worktree drops its status and marks its size stale.
/// A folder inside a git dir marks the worktrees that use it, whose fingerprints are read again.
/// subtrees YES also marks every worktree under each folder, for an FSEvents rescan. nil marks every worktree.
- (void)invalidate:(NSSet<NSString *> *)dirs subtrees:(BOOL)subtrees;
/// Brings the facts of every marked worktree up to date on the git queue. git runs only where a fingerprint moved
/// or the status was dropped. done, which may be nil, runs on that queue with the number of worktrees git ran for.
- (void)updateFacts:(void (^)(NSUInteger ran))done;
/// One FSEvents stream per root, each with its own saved event id, so a restart replays only what changed.
/// Each change marks worktrees through invalidate and may start a walk through refresh.
- (void)startWatching;
- (void)stopWatching;
/// Counters since launch, for the checks and the bench: walks, walksDone, updates, fingerprintReads, statusRuns,
/// historyRuns, gitRuns, patchIdsComputed, squashChecks, sizeWalks, and lastUpdateMs, lastUpdateRan and
/// lastUpdateChecked for the last pass.
- (NSDictionary<NSString *, NSNumber *> *)stats;
@end
/// Posted when a walk finds other worktrees, branches or locks than the last one, or when an update pass on the
/// git queue reads a moved branch or lock from a worktree's .git files.
extern NSNotificationName const MMRepoIndexDidChangeNotification;
/// Posted on the git queue when an update changed the facts of at least one worktree.
extern NSNotificationName const MMRepoIndexFactsDidChangeNotification;
