// Fix Everything, issue #62: runs the fixes of one MMPerformance in order, one step at a time, off main.
//
//   for each fix, in p.fixes order
//     needsYou ............... skipped; it runs only on its own press
//     a Wrap Up .............. MMRunWrapUp(plan, "manual")
//     any other kind ......... MMRunAction(action, fix.policy, review nil, "manual") for each action
//   then MMRepoIndex refresh when a worktree went, and MMGraph rebuild
//
// Invariant 1 holds because nothing here acts by itself: MMRunAction and MMRunWrapUp check each thing on fresh facts,
// run MustKeep and write the undo record first. A thing that changed since the snapshot stays, and the end note
// counts it.
//
// The policy is fix.policy, the one the fix was chosen with. For servers that is the mode policy, which keeps a
// server that is in use on the fresh check. The Servers menu's own Stop uses a policy that checks only that it is the
// same process, since there the person points at one server. Fix Everything names none, so "Stop 3 idle servers"
// stops only those still idle when their turn comes. For worktrees, apps and caches both policies check the same
// things when no review is given.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// One thing a run tried, for the end note and the checks.
@interface MMFixResult : NSObject
@property (copy) NSString *fix, *kind;                  // the fix's key and kind
@property (copy) NSString *name;                        // the thing, as the window names it
@property (copy) NSString *outcome;                     // "done", "kept", "blocked" or "failed"
@property (copy, nullable) NSString *why, *rid;
@end

@interface MMFixRunner : NSObject
- (instancetype)initWithPerformance:(MMPerformance *)p;
/// Called on the runner's queue before each step and once at the end, with a new MMWindowRun each time.
@property (copy, nullable) void (^onProgress)(MMWindowRun *run);
/// Runs every fix on no.guerrilla.minmacs.core.fix-everything and returns at once. Does nothing while one runs.
- (void)start;
/// Runs on the calling queue and returns the ended run. Never on main: it returns an ended run with nothing done.
- (MMWindowRun *)run;
/// Asks the run to end after the step it is in. Any queue. Asked before the run began, it ends the run before its
/// first step. A fix stopped between two of its things is not done: the end note counts the things not reached.
- (void)stop;
@property (readonly) BOOL running;
/// When the last step finished, before the rebuild the run asks for. nil until then. A snapshot built after this
/// saw what the run did.
@property (nullable) NSDate *endedAt;
/// What each step did, once the run ended.
@property (readonly, copy) NSArray<MMFixResult *> *results;
@end

/// "Stopping :3001", "Quitting Chat", "Removing fix-auth", and for a cache "Cleaning up DerivedData" under the Smart
/// removal choice, "Moving DerivedData to the Trash" under Trash and "Deleting DerivedData" under Delete.
NSString *MMFixStepText(NSString *fixKind, NSString *name);

NS_ASSUME_NONNULL_END
