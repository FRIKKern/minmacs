// The feed of the menu window, issue #62: one MMWindowModel from one snapshot and its MMPerformance.
// It reads facts only and holds no view. MMWindowController calls it off main, once per snapshot generation, while
// the window is open. `minmacs window` prints what it makes.
//
//   MMSnapshot ──► MMPerformance ──┐
//   s.history  ────────────────────┼──► MMWindowModelFrom ──► MMWindowModel ──► the window, on main
//   MMWindowExtras (lid, login, run)┘
//
// The files: MMWindowFeed.m puts the model together, MMWindowRows.m makes one row from one finding,
// MMWindowRules.m makes Settings, and MMWindowJSON.m prints every model class.
// None of them names AppKit or an expert's class, so the checks link them with Sources/Core alone.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// What the model shows that no snapshot holds: the two switches and a run of Fix Everything.
@interface MMWindowExtras : NSObject
@property BOOL lidOn;
@property (copy, nullable) NSString *lidNote;
@property BOOL loginOn;
@property (copy, nullable) NSString *loginNote;
@property (strong, nullable) MMWindowRun *run;
/// The lid switch as the keep-awake expert holds it now, and Open at login as given. Any queue.
/// It reads the expert's last published state, or its pref before the first pass. It never runs pmset.
+ (instancetype)readWithLogin:(BOOL)loginOn;
@end

/// The whole model. Pure: the same snapshot, performance and extras give the same model. Never on main in the app,
/// since the settings part reads prefs. p must be built from s.
MMWindowModel *MMWindowModelFrom(MMSnapshot *s, MMPerformance *p, MMWindowExtras *_Nullable extras);

#pragma mark Rows, MMWindowRows.m

/// The row of one MMPerformanceRow, with its finding's facts as the story. inFix is left NO; the feed sets it.
MMWindowRow *MMWindowRowFrom(MMPerformanceRow *r, MMSnapshot *s);
/// The name the window shows for a finding: ":3000 Next.js" for a server, the branch for a worktree, else its title.
NSString *MMWindowNameOf(MMFinding *f);
/// 60 values, bytes or NSNull, oldest first. megabytes of the ring are MiB. nil when ring is nil.
NSArray *_Nullable MMWindowHourValues(MMHistoryRing *_Nullable ring);

#pragma mark Fixes

/// "Wrap Up fix-auth-redirect", "Stop 3 idle servers", "Quit 2 apps", "Remove 2 merged worktrees",
/// "Move 10 leftovers to the Trash", "Clean pnpm store".
NSString *MMWindowFixTitle(MMPerformanceFix *fix);

#pragma mark Settings, MMWindowRules.m

/// The rule ids in the order Settings shows them: servers, apps, worktrees, caches.
NSArray<NSString *> *MMWindowRuleIDs(void);
/// The expert whose mode a rule sets, such as "locohost" for "servers". nil for an unknown id.
NSString *_Nullable MMWindowRuleExpert(NSString *ruleID);
/// The three choices in order, for MMModeIdle, MMModeProactive and MMModeEager: "Off", "Careful", "Eager".
NSArray<NSString *> *MMWindowChoiceTitles(void);
/// Settings: one rule per expert that has modes, picked from MMModeFor, and the lid and login switches.
MMWindowSettings *MMWindowSettingsFrom(MMPerformance *_Nullable p, MMWindowExtras *_Nullable extras);

NS_ASSUME_NONNULL_END
