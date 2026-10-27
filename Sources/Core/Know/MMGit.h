// Child processes, git, and repo and worktree discovery. Patterns P23 to P26 of SYNTHESIS.md section 1.3.
// Nothing here runs on main in the app. The CLI may call it on its own thread.
#import <Foundation/Foundation.h>

/// P23. How a child process ended.
typedef struct { int status; BOOL timedOut; BOOL didRun; } MMRunResult;   // status is -1 when it did not run

/// P23. Runs path with args, feeds input on stdin and waits at most timeout seconds.
/// Starts from WFGitInput in WF Common.m:78. A child past the limit gets SIGTERM, then SIGKILL after one second.
/// env is added to a clean environment, not to ours. outData and errData may be NULL.
MMRunResult MMRun(NSString *path, NSArray<NSString *> *args, NSData *input, NSDictionary<NSString *, NSString *> *env,
                  NSString *cwd, NSTimeInterval timeout, NSData **outData, NSData **errData);

/// P24. git, read-only by default, with LC_ALL=C, GIT_OPTIONAL_LOCKS=0, no prompts and no pager.
/// Starts from WF Common.m:71-105. Returns stdout without the trailing newline, or nil when git could not run
/// or timed out. status is git's exit status, -1 when it did not run. status may be NULL.
NSString *MMGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status);
NSString *MMGitPath(void);                              // nil when no real git is installed, so the Xcode stub never prompts

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
@interface MMGitFacts : NSObject
@property (readonly, copy) NSString *head, *defaultBranch, *upstream;
@property (readonly) MMMergeKind merged;
@property (readonly) NSInteger dirty, untracked, stashes, unpushed, notInDefault;
/// P26. Remote containment, its own fact: HEAD is reachable from some remote ref.
/// Decision 7: a squash-merged HEAD on no remote goes in Eager only, after a git bundle.
@property (readonly) BOOL onRemote;
@property (readonly) BOOL upstreamGone;                 // the remote branch was deleted
@property (readonly) NSDate *lastCommit;
@end

/// P25. Every repo and worktree under the scan roots, plus a path lookup with no spawn.
/// Starts from Walk in WF Trees.m:57 and ReadGit in LH Ports.m:265.
/// The roots are the person's folders plus <repo>/.claude/worktrees/*, ~/.cursor/worktrees/*/* and
/// ~/conductor/workspaces/*/*. The walk itself runs in the worker of P4.
@interface MMRepoIndex : NSObject
+ (instancetype)shared;
@property (copy) NSArray<NSString *> *roots;
- (void)refresh:(NSSet<NSString *> *)changedDirs;       // nil walks every root; FSEvents passes what changed
- (NSArray<MMWorktree *> *)worktrees;
/// The worktree that holds path, read from .git files with no spawn. nil outside any repo.
- (MMWorktree *)worktreeAt:(NSString *)path;
/// Through MMFactCache, keyed by HEAD. wait NO returns the cached facts, possibly stale, or nil.
- (MMGitFacts *)factsFor:(MMWorktree *)w wait:(BOOL)wait;
@end
