// Act: modes, MustKeep, plans, actions, stopping, keep-awake and the one notifier.
// Patterns P48 to P51, P54 and P55 of SYNTHESIS.md section 1.7. Undo, the Trash, bundles and tool commands are in MMUndo.h.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Review/MMReview.h"
#import "Core/Act/MMUndo.h"

/// P48. How much an expert does on its own. Idle acts on nothing. Proactive acts on what is clearly safe.
/// Eager also acts on what the judge lets go. Starts from WF Forest.m:22-56.
typedef NS_ENUM(NSInteger, MMMode) { MMModeIdle = 0, MMModeProactive = 1, MMModeEager = 2 };
MMMode MMModeFor(NSString *expert);                     // the <expert>.mode pref, Proactive by default
void MMSetMode(NSString *expert, MMMode mode);
NSString *MMModeName(MMMode mode);                      // idle, proactive, eager
NSInteger MMModeFrom(NSString *name);                   // -1 when unknown
/// P48. YES once MinMacs has watched for a day after its first launch. No mode acts on its own before that.
BOOL MMWatchedLongEnough(NSString *expert);
void MMStartWatching(void);                             // once, at the app's first launch
NSTimeInterval MMWatchingLeft(NSString *expert);        // seconds until modes may act, 0 once they may

/// P49. The keep checks of one expert. Starts from WFWorkKeeps and WFMustKeep, WF Forest.m:110 and WF Forest.h.
/// Work keeps read fresh facts and hold whatever the mode or the review says. Review keeps read the review.
@protocol MMExpertPolicy <NSObject>
/// Why f must stay on fresh facts, or nil when it is free to decide. "Cannot verify" is a reason to keep.
/// Act calls this again right before every action, whatever asked for it.
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts;
/// Why the review keeps f: no recent review, the review failed, work after the review, not in the review. nil when free.
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r;
@optional
/// The expert's own rule for mode m, such as WorkForest's "Proactive waits 7 quiet days". nil when the mode may act.
/// MMPlan asks this only for a finding that MustKeep and the review let go.
- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r;
@end

/// P49. MustKeep: the work keeps, then the review keeps when r is given, then a timed keep and the protect list of P50.
/// nil when the mode may decide.
NSString *MMMustKeep(MMFinding *f, MMFacts *facts, MMReview *r, id<MMExpertPolicy> policy);

/// P49. One line of a plan: act on the finding or keep it, and why.
@interface MMPlanEntry : NSObject
@property (readonly) MMFinding *finding;
@property (readonly) BOOL act;
@property (readonly, copy) NSString *why;
@end
/// P49. What mode m does to each finding. Starts from WFPlan, WF Forest.h. Idle acts on nothing.
NSArray<MMPlanEntry *> *MMPlan(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r, MMMode m,
                               id<MMExpertPolicy> policy);

/// P50. A timed keep, the person's word that a finding stays for a while, keyed by its stableKey.
/// Starts from WFKeptUntil, WF Forest.m:95, which keys by path. A stable key keeps a server's keep across restarts.
@interface MMKeep : NSObject
/// nil when not kept or the keep has passed. Off main it reads the file. On main it answers from the last read, so a
/// menu never waits on disk, and reads the file only when nothing was read yet, as in a CLI.
/// An expert reads it in -findingsFrom:, on the graph queue in the app.
+ (NSDate *)keptUntil:(NSString *)stableKey expert:(NSString *)expert;
+ (void)keep:(NSString *)stableKey expert:(NSString *)expert until:(NSDate *)until;   // nil ends the keep
/// P50. The protect list in the expert's rules file of P36, matched with its wildcards.
+ (BOOL)isProtected:(NSString *)value expert:(NSString *)expert;
@end

/// How many times this process read a keeps file on the main thread, for the checks that menus never do.
NSUInteger MMKeepMainThreadReads(void);

/// P51 to P53. One action, checked fresh right before it runs.
@protocol MMAction <NSObject>
@property (readonly) MMFinding *finding;
@property (readonly, copy) NSString *kind;              // "stop", "remove", "trash", "tool", "quit"
/// nil to go ahead, else why it cannot run now. A dimmed menu item shows this as its gray tail.
- (NSString *)recheck;
/// What would happen, for --dry-run and the confirm text. A tool command's dry-run output goes here.
- (NSString *)dryRun;
/// Does it. The record was written before this call, and perform fills its payload.
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error;
@end

/// P51. Runs one action the safe way, in this order:
/// recheck, then MMMustKeep on -[MMGraph freshFactsFor:], then the undo record, then perform, then finish.
/// review is the review a mode acted on, so work after it keeps. Pass nil for an action the person asked for.
/// by says who asked: "manual" from a menu, "cli" from the command line, "proactive" or "eager" from a mode,
/// or "guard" from an expert's own rule that follows the state, such as Insomnia's lid override. Blocks. Never on main.
/// Returns the finished record, or nil with *error when the action did not start.
MMUndoRecord *MMRunAction(id<MMAction> action, id<MMExpertPolicy> policy, MMReview *review,
                          NSString *by, NSString *why, NSString **error);

/// P51. The two steps of stopping. Force is a second request, such as the Option alternate of Stop.
typedef NS_ENUM(NSInteger, MMStopStep) { MMStopTerm, MMStopKill };

/// P51. Stops processes: SIGTERM on the first request and SIGKILL only on a second one.
/// Starts from StopHostsBy, LH main.m:301, and QuitApps, MM main.m:141 on branch legacy.
/// Pid and start time are checked before each signal, so a reused pid is never signaled.
/// Never signals pid 1, a pid of another uid, or MinMacs itself. Waits up to grace seconds for each to exit.
/// Returns the keys still alive after the wait.
NSArray<NSValue *> *MMStop(NSArray<NSValue *> *keys, MMStopStep step, NSTimeInterval grace);
/// P51. Quits apps through NSRunningApplication terminate, and forceTerminate only on MMStopKill.
/// Apps are named by MMProcKey, not bundle id, so an app the person opened again since is never quit.
/// Returns the keys still running after the wait.
NSArray<NSValue *> *MMQuitApps(NSArray<NSValue *> *keys, MMStopStep step, NSTimeInterval grace);

/// P54. A keep-awake assertion tied to a working agent.
/// Starts from IN main.m:542-545, plus a caffeinate -w style end on the pid's exit through kqueue NOTE_EXIT.
/// Decision 4: Insomnia keeps the Mac awake only while an agent works.
@interface MMAwake : NSObject
+ (void)holdFor:(MMProcKey)agent reason:(NSString *)why;    // released when that process exits
+ (void)release:(MMProcKey)agent;
+ (void)releaseAll;
+ (NSDictionary<NSString *, NSString *> *)held;         // MMProcKeyString to reason
@end

/// P54. The lid override, `pmset -a disablesleep`, which only root may set. It runs the commands Insomnia runs,
/// IN main.m:675-711, through the sudoers rule /etc/sudoers.d/insomnia that allows exactly
/// `/usr/bin/pmset -a disablesleep 1` and `... 0`. The state is read from IOKit in MMPower.lidOverride, never here.
/// Every call runs a child with a time limit, so each returns NO at once on the main thread.
/// With MINMACS_HOME set the commands run only through MINMACS_INSOMNIA_CMD, a fake that gets the full command line
/// as its arguments. Without that fake they refuse, so a test never runs sudo or pmset.
@interface MMLidOverride : NSObject
/// `sudo -n /usr/bin/pmset -a disablesleep 1` or `0`.
+ (BOOL)set:(BOOL)on error:(NSString **)error;
/// YES when the rule lets the write run with no password: `sudo -n -l /usr/bin/pmset -a disablesleep 1`.
+ (BOOL)ruleInstalled;
/// Writes the rule after one administrator prompt, through osascript, and checks it with visudo. Blocks while the
/// prompt is up, at most two minutes.
+ (BOOL)installRule:(NSString **)error;
/// `pmset displaysleepnow`: the display sleeps, and opening the lid wakes it. Through powerd, as any user.
+ (BOOL)sleepDisplay;
/// `disablesleep 0` for an app that quits: started, never waited for. Safe on main.
+ (void)clearWithoutWaiting;
/// Why the commands cannot run in this process, or nil when they can.
+ (NSString *)unavailableReason;
@end

/// P55. The one notifier. It sends at most one notification per review across all experts,
/// and only after an action nobody asked for. An error goes in an alert, never here.
/// Starts from -notify:mode: in LocoHost and WorkForest, plus a UNNotificationAction for Undo.
/// It asks for permission the first time it is needed, never at launch. The title is short, in title case, with no
/// final period. The body is full sentences. undoRid adds one Undo action that restores that record.
/// The interruption level is passive unless the disk is nearly full.
void MMNotify(NSString *expert, NSString *title, NSString *body, NSString *undoRid);

/// P55. Where MMNotify sends. The app uses UNUserNotificationCenter. Tests pass a fake, so they never ask for permission.
@protocol MMNotifier <NSObject>
/// passive is NO only when the disk is nearly full. undoRid is nil when there is nothing to undo.
- (void)post:(NSString *)title body:(NSString *)body undoRid:(NSString *)undoRid passive:(BOOL)passive expert:(NSString *)expert;
@end
void MMUseNotifier(id<MMNotifier> notifier);           // nil goes back to the system notifier

#pragma mark - Wrap Up

/// P51 and P52 for one finished workstream, PLAN.md section 6. Issue #27.
/// MMRunAction for one part of a multi-part action: the same steps, with the record written as a part of parentRid.
/// index is the part's place in the run, kept in the record's payload as "part", so restore takes the parts back
/// in reverse order. Blocks. Never on main.
MMUndoRecord *MMRunActionPart(id<MMAction> action, id<MMExpertPolicy> policy, NSString *by, NSString *why,
                              NSString *parentRid, NSInteger index, NSString **error);

/// The steps of a Wrap Up, in the order they run. Restore runs them backwards.
/// Caches go before the worktree, so a cache inside it comes back from the Trash after git recreates the folder.
typedef NS_ENUM(NSInteger, MMWrapUpStep) {
    MMWrapUpServers = 1,     // LocoHost stops the servers that run in it
    MMWrapUpHelpers = 2,     // MinMacs stops the helpers left in it, such as a headless browser whose parent exited
    MMWrapUpCaches = 3,      // Noo-Noo moves its caches and build output to the Trash
    MMWrapUpConfig = 4,      // WorkForest moves its untracked config files, such as .env.local, to the Trash
    MMWrapUpWorktree = 5,    // WorkForest saves its ignored files such as .env and removes the worktree
};
NSString *MMWrapUpStepName(MMWrapUpStep step);         // servers, helpers, caches, config, worktree

/// A finished workstream: a linked worktree whose branch is merged and whose agent sessions all ended.
/// The graph keeps no workstream for an ended session, so the subject is the worktree, read from facts.
@interface MMWrapUpSubject : NSObject
@property (readonly, copy) NSString *path;              // the worktree, as the kernel names it
@property (readonly) MMWorktree *worktree;
@property (readonly) MMGitFacts *git;
@property (readonly) NSArray<MMSession *> *sessions;    // every session that ran in it, newest first
/// Every finding the worktree holds, from every expert: its owner, back-link, path or first process is inside.
/// Empty when whyNot is set.
@property (readonly) NSArray<MMFinding *> *findings;
/// Why it is not a finished workstream, or nil when it is.
@property (readonly, copy) NSString *whyNot;
/// The processes the server and helper parts end, so the worktree part's check does not count them as work.
@property (readonly) NSArray<NSValue *> *stopped;
/// YES when the plan has a config part, so untracked files are that part's to check and move.
@property (readonly) BOOL configPart;
/// YES when path is the worktree or inside it, as given or as the kernel names it.
- (BOOL)holds:(NSString *)path;
/// The subject at path in these facts. s may be nil, and findings are then empty.
+ (instancetype)subjectAt:(NSString *)path facts:(MMFacts *)facts snapshot:(MMSnapshot *)s;
@end

/// One part: one action with the policy its expert checks it with.
@interface MMWrapUpPart : NSObject
@property (readonly) MMWrapUpStep step;
@property (readonly, copy) NSString *expert, *title;    // "locohost", "Stop :3000 Python http.server"
@property (readonly) id<MMAction> action;
@property (readonly) id<MMExpertPolicy> policy;
/// Why this part cannot run, from the last check, or nil.
@property (readonly, copy) NSString *whyNot;
+ (instancetype)step:(MMWrapUpStep)step expert:(NSString *)expert title:(NSString *)title
              action:(id<MMAction>)action policy:(id<MMExpertPolicy>)policy;
@end

/// What Wrap Up does to one workstream: the subject and its parts, in the order they run.
@interface MMWrapUpPlan : NSObject
@property (readonly) MMWrapUpSubject *subject;
@property (readonly) NSArray<MMWrapUpPart *> *parts;
/// Why it cannot run now: the subject's reason, or the first part whose check failed, named. nil when it may run.
@property (readonly, copy) NSString *whyNot;
@property (readonly) uint64_t freedBytes;               // what the parts' findings say deleting frees
@property (readonly) NSUInteger servers;                // server parts
/// {path, ready, whyNot, freedBytes, parts: [{step, expert, title, findingID, whyNot, dryRun}]}, for --json.
- (NSDictionary *)json:(BOOL)dryRuns;
@end

/// Whether every untracked file in the worktree at path is a config file that the config part may move, from a
/// check through MMWorktreeUntrackedFiles on MMQueue(@"core", @"wrapup"), kept per path, HEAD and untracked count.
/// wait NO never blocks: it returns the kept answer, or nil and queues a check that asks the graph for a rebuild when
/// it ends. A menu calls it that way. wait YES checks now when no answer is kept, even while a queued check runs,
/// and never on main.
NSNumber *MMWrapUpConfigOnly(NSString *path, NSString *head, NSInteger untracked, BOOL wait);

/// Builds the plan for the worktree at path from the snapshot: the subject, then each registered expert's parts
/// through -[MMExpert wrapUpParts:snapshot:], then MustKeep of every part on the snapshot's facts. A part whose
/// processes an earlier part already ends is left out. Reads only the snapshot, so a menu may call it on main.
MMWrapUpPlan *MMWrapUpPlanFor(NSString *path, MMSnapshot *s);
/// Checks the plan on fresh facts: the subject again, then each part's recheck and MustKeep on fresh facts for its
/// finding. Returns nil when every part passes, else why not, and the plan's whyNot says the same. Never on main.
NSString *MMWrapUpCheck(MMWrapUpPlan *plan);
/// Runs the plan as one undoable step. It checks every part fresh first and starts nothing when one fails. Then it
/// writes one record of kind "wrapup" and runs each part through MMRunActionPart, so each part checks fresh right
/// before it runs. A part that fails stops the rest, and the record fails with the part named in its error and in
/// its payload's "failedPart". -[MMUndo restore:] of the record takes back each part that ran, newest first.
/// by is "manual" or "cli". Returns the finished record, or nil with *error when nothing started. Never on main.
MMUndoRecord *MMRunWrapUp(MMWrapUpPlan *plan, NSString *by, NSString **error);
