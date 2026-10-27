// Removing a git worktree the safe way. Part of P52, beside the undo engine in MMUndo.h.
// Starts from WFRemove and SaveIgnored in WF Forest.m:486-539. Git runs with no --force, so git itself refuses a
// worktree with changes, and a branch is deleted with -d only, which git refuses for a branch it cannot see merged.
#import <Foundation/Foundation.h>

/// P52. The ignored files in a worktree that are not caches, such as .env.local, as paths relative to it.
/// Git would delete them with the worktree, so the action saves them to the recovery folder first.
/// A path with any component in cacheNames, or named .DS_Store, is left out. nil when git could not list them.
NSArray<NSString *> *MMWorktreeIgnoredFiles(NSString *worktree, NSArray<NSString *> *cacheNames);

/// P52. `git worktree remove <worktree>` in repo, never with --force. When deleteBranch is YES and branch is set,
/// `git branch -d <branch>` follows, and *branchDeleted says whether git deleted it.
/// Returns NO with *error when git refused, and the worktree is then unchanged. Blocks. Never on main.
BOOL MMWorktreeRemove(NSString *repo, NSString *worktree, NSString *branch, BOOL deleteBranch,
                      BOOL *branchDeleted, NSString **error);

/// P52. `git worktree prune` in repo, which tidies git's record of worktrees whose folder is gone. It removes no file.
/// Returns NO when git failed. *output holds what git said.
BOOL MMWorktreePrune(NSString *repo, NSString **output);
