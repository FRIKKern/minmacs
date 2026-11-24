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
@property BOOL lidInert;                                // this Mac has no lid, so the switch changes nothing here
@property BOOL awakeShown;                              // a keep-awake expert runs, so Keep awake now and While agents work show
@property BOOL awakeOn, agentsOn;                       // insomnia.awake and insomnia.agents
@property NSInteger agentsHolding, quietMinutes;        // agents that keep the Mac awake now; minutes a quiet agent still holds
@property BOOL loginOn;
@property (copy, nullable) NSString *loginNote;
@property (strong, nullable) MMWindowRun *run;
/// How far the look for worktrees and for caches went, for the line of an empty group. Worktrees: nowhere with no
/// folder to look in, which is MMRepoIndex's roots being empty, and not yet until its first walk ended. Caches:
/// nowhere where the catalog scans nothing, in a test home with no clutter root, and not yet before its first scan.
@property MMWindowLooked worktreesLooked, cachesLooked;
/// The welcome, from MMWindowWelcomeNow, while the person has not pressed Start. The controller sets it. nil in the CLI.
@property (strong, nullable) MMWindowWelcome *welcome;
/// The log for the middle, Shell/MMWindowLog.h. The controller reads it while open. nil in the CLI.
@property (strong, nullable) MMWindowLog *log;
/// The lid switch as the keep-awake expert holds it now, and Open at login as given. Any queue.
/// It reads the expert's last published state, or its pref before the first pass. It never runs pmset.
/// The two looks are read from the repo index and the clutter catalog as they stand, with no walk and no scan.
+ (instancetype)readWithLogin:(BOOL)loginOn;
@end

/// The whole model. Pure: the same snapshot, performance and extras give the same model. Never on main in the app,
/// since the settings part reads prefs. p must be built from s.
MMWindowModel *MMWindowModelFrom(MMSnapshot *s, MMPerformance *p, MMWindowExtras *_Nullable extras);

#pragma mark Rows, MMWindowRows.m

/// The row of one MMPerformanceRow, with its finding's facts as the story. inFix is left NO; the feed sets it.
/// An agent is named by its session's title, else by its project folder, so fifteen rows do not all read "Claude Code".
MMWindowRow *MMWindowRowFrom(MMPerformanceRow *r, MMSnapshot *s);
/// The name the window shows for a finding: ":3000 Next.js" for a server, the branch for a worktree, else its title.
NSString *MMWindowNameOf(MMFinding *f);
/// 60 values, bytes or NSNull, oldest first. megabytes of the ring are MiB. nil when ring is nil.
NSArray *_Nullable MMWindowRingHour(MMHistoryRing *_Nullable ring);

#pragma mark Fixes

/// "Wrap Up fix-auth-redirect", "Stop 3 idle servers", "Quit 2 apps", "Remove 2 merged worktrees",
/// "Move 10 leftovers to the Trash", "Clean pnpm store".
NSString *MMWindowFixTitle(MMPerformanceFix *fix);

#pragma mark Settings, MMWindowRules.m

/// The expert whose mode a rule sets, such as "locohost" for "servers". nil for an unknown id.
NSString *_Nullable MMWindowRuleExpert(NSString *ruleID);
/// Settings: one rule per expert that has modes, picked from MMModeFor, and the lid and login switches.
MMWindowSettings *MMWindowSettingsFrom(MMPerformance *_Nullable p, MMWindowExtras *_Nullable extras);

#pragma mark The welcome, MMWindowRules.m

/// @"core.welcomed": YES once the person pressed Start in the welcome. The welcome shows while it has no value.
extern NSString *const MMWindowWelcomedKey;
/// @"core.login": the key the log's setting rows give Open at login. No pref holds it: the system's login item does.
extern NSString *const MMWindowLoginKey;
/// @"core.loginNotAsked": YES from a first launch that left the login item alone, since the welcome asks. Start and
/// any -setLogin: take it away. While it holds, a login item that is off is nobody's answer yet.
extern NSString *const MMWindowLoginNotAskedKey;
/// The welcome of the first launch, or nil once Start was pressed or while the Mac runs unattended, MMUnattended. There is no removal choice to make: everything
/// MinMacs removes keeps a way back, Core/Act/MMRemoval.h. The switch starts on for a person new to MinMacs. For one
/// who used it before, which is when core.launched is set and the mark above is not, it starts where
/// the login item stands now, loginNow, so an untouched Start changes nothing for them.
/// Each fact is read from what makes it true: the day of watching from MMWatchingLeft, where each rule stands from
/// MMModeFor, and awake while agents work from the keep-awake expert's pref.
MMWindowWelcome *_Nullable MMWindowWelcomeNow(BOOL loginNow);
/// Start was pressed: marks the welcome done. It does not touch the login item, which the shell owns.
void MMWindowWelcomeDone(void);

NS_ASSUME_NONNULL_END
