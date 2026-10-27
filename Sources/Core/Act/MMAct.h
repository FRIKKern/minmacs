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
+ (NSDate *)keptUntil:(NSString *)stableKey expert:(NSString *)expert;   // nil when not kept or the keep has passed
+ (void)keep:(NSString *)stableKey expert:(NSString *)expert until:(NSDate *)until;   // nil ends the keep
/// P50. The protect list in the expert's rules file of P36, matched with its wildcards.
+ (BOOL)isProtected:(NSString *)value expert:(NSString *)expert;
@end

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
/// by is "manual", "proactive", "eager" or "cli". Blocks. Never on main.
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

/// P55. The one notifier. It sends at most one notification per review across all experts,
/// and only after an action nobody asked for. An error goes in an alert, never here.
/// Starts from -notify:mode: in LocoHost and WorkForest, plus a UNNotificationAction for Undo.
/// It asks for permission the first time it is needed, never at launch. The title is short, in title case, with no
/// final period. The body is full sentences. undoRid adds one Undo action that restores that record.
/// The interruption level is passive unless the disk is nearly full.
void MMNotify(NSString *expert, NSString *title, NSString *body, NSString *undoRid);
