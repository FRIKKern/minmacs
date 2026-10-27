// WorkForest on the shared core: every git worktree on the Mac, whether it is merged, and what it holds.
// Issue #24. The expert reads worktrees from Core's repo index, git facts from Know, disk facts from Know's walk,
// processes from the Senses sample and sessions from Know, and reviews through the Core broker.
// It never samples, scans, runs git or asks the model on its own. Removal runs through Act with an undo record.
// Sources/Experts/WorkForest/README.md says what was ported and what is left open.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Experts/WorkForest/MMWFTree.h"

@interface MMWorkForestExpert : NSObject <MMExpert>
/// The one WorkForest. main.m registers it through MMBuiltInExpertClasses.
+ (instancetype)shared;
/// The trees behind a snapshot's findings, main checkouts included. Built from each finding's facts.
- (NSArray<MMWFTree *> *)treesIn:(MMSnapshot *)s;
/// The menu's view of a snapshot: the review, the plan under the mode, Clean Up and Recently Removed.
- (MMWFView *)viewFor:(MMSnapshot *)s;
@end

/// YES while a verb builds its own snapshot: disk facts are then read fresh, as WorkForest 0.1's CLI did.
extern BOOL MMWFReadNow;

/// WorkForest's rules file: the protect list of paths, and protect.branches, the long-lived branch names.
MMRules *MMWFRules(void);
/// The tree of one finding, from its facts.
MMWFTree *MMWFTreeOf(MMFinding *f);
/// The keep checks a mode runs on fresh facts, and the one for an action the person asked for.
id<MMExpertPolicy> MMWFModePolicy(void);
id<MMExpertPolicy> MMWFManualPolicy(void);
/// Removes one worktree: a git bundle when commits are on no remote, ignored files saved, `git worktree remove`
/// with no --force, and `git branch -d` when it is merged. Restore recreates it at its commit.
id<MMAction> MMWFRemoveAction(MMFinding *f);
/// What Clean Up removes: free to decide, and called stale by a review that did not fail. Ported from WFCandidates.
NSArray<MMFinding *> *MMWFCandidates(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r);
/// The linked worktrees a review looks at: not missing, not main.
NSArray<MMFinding *> *MMWFReviewable(NSArray<MMFinding *> *findings);
/// The review request for these findings in this mode. The CLI passes a model, the app nil for the Settings choice.
MMReviewRequest *MMWFReviewRequest(NSArray<MMFinding *> *findings, MMSnapshot *s, NSString *trigger, MMMode mode, NSString *model);
/// The newest WorkForest review in the log, or nil.
MMReview *MMWFLastReview(void);

/// Removal records, newest first, as {rid, legacyID, path, branch, at, by, why, saved, skipped, state, branchDeleted}.
/// WorkForest 0.1's removed.json is imported into Core's undo log first, once per record, and never changed.
NSArray<NSDictionary *> *MMWFRemoved(NSUInteger limit);
/// The undo record id for a record id, a WorkForest 0.1 id or a removed worktree's path. nil when none matches.
NSString *MMWFRecordFor(NSString *key, NSString *cwd);
/// Where WorkForest 0.1 kept its state: $WORKFOREST_HOME, else its support folder. nil under MINMACS_HOME alone.
NSString *MMWFLegacyHome(void);
/// Imports WorkForest 0.1's removed.json into the undo log. Returns how many records it added.
NSInteger MMWFImportLegacy(void);

/// The verbs, in MMWFCLI.m.
NSArray<MMVerbSpec *> *MMWFVerbs(void);
