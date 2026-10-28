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

/// P52 for Wrap Up. The untracked files in a worktree that git does not ignore, as paths relative to it.
/// `git worktree remove` refuses while any exist, and Wrap Up never passes --force. nil when git could not list them.
NSArray<NSString *> *MMWorktreeUntrackedFiles(NSString *worktree);
/// YES for a file that holds local settings rather than work, such as .env.local, .envrc, .npmrc or
/// .claude/settings.local.json. Wrap Up moves such files to the Trash before it removes the worktree, and any other
/// untracked file keeps the worktree.
BOOL MMWorktreeIsConfigFile(NSString *relativePath);
