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
/// HOME, XDG_CONFIG_HOME and GIT_CONFIG_GLOBAL, _SYSTEM and _NOSYSTEM pass through from our environment, so git reads
/// the files MMGitOutside.m reads, and a test keeps the person's config out.
NSString *MMGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status);
/// nil when no real git is installed, so the Xcode stub never prompts. $MINMACS_GIT names another git.
NSString *MMGitPath(void);
/// What every git child gets on top of MMRun's clean environment: LC_ALL=C, GIT_OPTIONAL_LOCKS=0, no prompts,
/// no pager, and XDG_CONFIG_HOME and GIT_CONFIG_GLOBAL, _SYSTEM and _NOSYSTEM from ours; MMRun passes HOME. For a
/// caller that runs git through MMRun itself.
NSDictionary<NSString *, NSString *> *MMGitEnvironment(void);
/// YES on core.git.fresh, the queue of factsFor:wait:YES: the read before an action, which takes no memo's answer and
/// no answer kept for a second. A key set on that queue, so no name is compared.
BOOL MMGitOnFreshRead(void);

/// P25. Who made a worktree. Decision 6: MinMacs acts on Claude Code's agent worktrees once their session ended,
/// and only shows Cursor's and Conductor's.
typedef NS_ENUM(NSInteger, MMWorktreeMaker) { MMMakerPerson, MMMakerClaudeCode, MMMakerCursor, MMMakerConductor };

/// P25. One checkout: a repo's main checkout or a linked worktree.
@interface MMWorktree : NSObject
@property (readonly, copy) NSString *path, *repo, *branch;   // repo: the main checkout's path
/// path with every link resolved, read once when the index stores the checkout, or path itself for a folder that is
/// gone. The kernel names a process's folder this way and WorkForest names its finding this way, while path stays as
/// the root gave it: /tmp for /private/tmp, or a root that is a link to another volume. Every reader that asks which
/// checkout holds a path tries both, as text, through the functions below, and reads no file. Issue #101.
@property (readonly, copy) NSString *realPath;
@property (readonly) BOOL isMain;
@property (readonly) BOOL locked;                       // `git worktree lock`, which counts as in use
@property (readonly, copy) NSString *lockReason;
@property (readonly) MMWorktreeMaker maker;
@property (readonly, copy) NSString *makerSession;      // Claude Code's ownership marker, its session id
@property (readonly) BOOL missing;                      // listed by git, gone from disk
@end

/// Issue #101. The form of w's folder that holds path: path as kept when it holds it, else realPath, else nil.
/// Text only. A checkout under a root that is a link, or under /tmp, is one folder by two names.
NSString *MMWorktreeFolderFor(MMWorktree *w, NSString *path);
/// YES when path is w's own folder, in either form.
BOOL MMWorktreeIsAt(MMWorktree *w, NSString *path);
/// path, which w holds in one form, in w's other form: the same file named through realPath or through path.
/// path itself when w does not hold it or both forms are one.
NSString *MMWorktreeOtherForm(MMWorktree *w, NSString *path);
/// The deepest checkout in trees, by its resolved path, whose folder holds path in either form; of two entries of one
/// folder, the one named the way path is, else the first. nil when none does.
MMWorktree *MMWorktreeHolding(NSArray<MMWorktree *> *trees, NSString *path);

/// P26. How a branch reached the default branch. MMMergedNone means it did not, as far as the checks can tell.
/// Starts from WF Trees.m:134-290 and NN worktrees.go:192, plus worktrunk's simulated merge with `git merge-tree`.
typedef NS_ENUM(NSInteger, MMMergeKind) {
    MMMergedNone, MMMergedAncestor, MMMergedTree, MMMergedPatch, MMMergedSquash, MMMergedPR, MMMergedMergeTree,
};

/// P26. The git facts of one worktree, keyed by HEAD in the fact cache of P27.
/// branch, head, the default branch, the upstream and the stash count are read from git's own files.
/// The rest come from git through MMGit, on a Know queue. A count of -1 means git could not tell, which counts as dirty.
/// Issue #116: git's files are read as bytes. A name that is not UTF-8 shows with U+FFFD and never resolves, and a file
/// that is there and cannot be read leaves its facts not known: stashes -1, no head with unpushed and notInDefault -1,
/// no default branch, and an upstream that is not gone.
@interface MMGitFacts : NSObject
@property (readonly, copy) NSString *branch;            // nil when HEAD is detached, or cannot be read
@property (readonly, copy) NSString *head, *defaultBranch, *upstream;   // upstream: "origin/x", nil when none is set
@property (readonly) MMMergeKind merged;
@property (readonly) NSInteger dirty, untracked, stashes, notInDefault;
@property (readonly) NSInteger unpushed;                // commits on HEAD that no remote ref holds
@property (readonly) NSInteger ahead, behind;           // against the upstream, 0 when there is none
/// P26. Remote containment, its own fact: HEAD is reachable from some remote ref.
/// Decision 7: a squash-merged HEAD on no remote goes in Eager only, after a git bundle.
@property (readonly) BOOL onRemote;
@property (readonly) BOOL upstreamGone;                 // the remote branch was deleted
@property (readonly) BOOL upstreamUnknown;              // the upstream or its tip cannot be read, so it is not gone
@property (readonly) NSDate *lastCommit;
/// The last commit's subject line, cut at 200 characters, read in the same git run as its time. nil when not known.
@property (readonly, copy) NSString *subject;
/// Commits on the default branch that HEAD does not hold, from the same count as notInDefault. -1 when not known.
@property (readonly) NSInteger behindDefault;
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
/// With MINMACS_HOME set, git facts and sizes are read only inside MINMACS_HOME and the roots.
@interface MMRepoIndex : NSObject
+ (instancetype)shared;
@property (copy) NSArray<NSString *> *roots;
/// nil walks every root. FSEvents passes what changed: only a .git folder, or a folder near a root outside every
/// known checkout, starts a walk, and walks are at least 10 seconds apart. Never blocks.
- (void)refresh:(NSSet<NSString *> *)changedDirs;
/// The last walk, deepest path first. A folder reached by two paths, as a root that is a link gives a linked worktree,
/// is held under both, since the graph names owners by the form a process or session gives. Issue #101.
- (NSArray<MMWorktree *> *)worktrees;
/// YES once a walk of the roots has ended with an answer, so an empty list means none were found. NO before that,
/// while the first walk runs, and after a walk the worker failed. Any queue, never blocks.
- (BOOL)walked;
/// The worktree that holds path: a walked one, by its path as kept and then by its resolved one, else one read from
/// .git files with no spawn. nil outside any repo.
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
#ifdef MM_TESTS
/// Compiled only with -DMM_TESTS. Runs where one worktree's facts are brought up to date: with step "read" right
/// before the cached status and its drop are read, and with "write" after git ran, right before the facts are
/// kept. A check lands a change at either point through it, issue #84.
typedef void (^MMRepoIndexStep)(NSString *step, NSString *path);
extern MMRepoIndexStep MMRepoIndexTestStep;
#endif
/// Posted when a walk finds other worktrees, branches or locks than the last one, or when an update pass on the
/// git queue reads a moved branch or lock from a worktree's .git files.
extern NSNotificationName const MMRepoIndexDidChangeNotification;
/// Posted on the git queue when an update changed the facts of at least one worktree.
extern NSNotificationName const MMRepoIndexFactsDidChangeNotification;
