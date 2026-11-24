// A worktree's pull request, from the person's own logged-in `gh` CLI. docs/PRIVACY.md, "Pull requests", says what
// goes to GitHub.
//
//   window, main ──story of a worktree row──► MMWindowController, core.window ──want──► MMPulls, workforest.prs
//                                                                                        one gh at a time, 5 s
//   the feed, core.window ◄──knownFor: memory only, no spawn──┘◄── MMPullsDidChangeNotification ──┘
//
// Only on demand: the window asks while a worktree's story shows, and nothing else does. No tick, no snapshot and no
// verb asks gh. Each answer is kept per repo and branch for five minutes, and asked again sooner only when the
// branch's head moved. A failure backs off. With gh missing or not logged in, or the pref workforest.pullRequests off,
// nothing is asked and nothing is known, quietly.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The pref that lets the window ask gh, on by default. `minmacs trees prs on|off` and Settings set it.
extern NSString *const MMPullsPrefKey;                  // @"workforest.pullRequests"
/// Posted on the workforest.prs queue when what is known of a branch changed: an answer came, or a look ended.
extern NSNotificationName const MMPullsDidChangeNotification;

/// One pull request, as gh gives it.
@interface MMPull : NSObject
@property NSInteger number;
@property (copy) NSString *title, *url;
@property (copy) NSString *stateWord;                   // open, merged or closed
@property BOOL draft;
/// approved, changes requested or review requested. nil when the repo asks for no review.
@property (copy, nullable) NSString *review;
/// The checks of its newest commit, from statusCheckRollup.
@property NSInteger checksPassing, checksFailing, checksPending;
@property (strong, nullable) NSDate *mergedAt, *updatedAt;
- (NSDictionary *)json;
+ (nullable instancetype)fromJSON:(NSDictionary *)json;
@end

typedef NS_ENUM(NSInteger, MMPullKnown) {
    MMPullNothing = 0,      // nothing to show: not asked, gh missing or not logged in, a failure, or the pref off
    MMPullLooking,          // gh is being asked now, for at most the timeout
    MMPullNone,             // gh answered: this branch has no pull request
    MMPullFound,            // gh answered with one
};

@interface MMPullAnswer : NSObject
@property MMPullKnown known;
@property (strong, nullable) MMPull *pull;
@property (strong, nullable) NSDate *checkedAt;         // when gh answered
@property (copy, nullable) NSString *head;              // the branch's head gh was asked at
- (NSDictionary *)json;                                 // {known, pull, checkedAt}
@end

/// gh's answer to `pr list --json ...`: an array of at most one. nil when it is not that, so a failure shows nothing.
MMPullAnswer *_Nullable MMPullParse(NSData *_Nullable json);
/// The arguments gh is run with for a branch. PRIVACY.md lists them, and `./test.sh docs` holds it to that.
NSArray<NSString *> *MMPullArguments(NSString *branch);

@interface MMPulls : NSObject
+ (instancetype)shared;
/// The pref, on when it was never set.
+ (BOOL)enabled;
/// What is known for this branch at this head, from memory and the kept answers alone: never spawns, never blocks.
/// An answer at an older head stands while gh is asked again for the new one, so the story does not flicker. A look
/// older than the timeout reads as nothing.
- (MMPullAnswer *)knownFor:(NSString *)repo branch:(NSString *)branch head:(nullable NSString *)head;
/// Asks gh in folder, on workforest.prs, when nothing fresh is known and gh is there and logged in. Never on main,
/// since it looks for gh on disk; it never waits for gh. Only the newest ask runs: one that waits while another
/// runs and is no longer the newest is dropped. YES when a look began, so the caller shows "Looking".
- (BOOL)want:(NSString *)folder repo:(NSString *)repo branch:(NSString *)branch head:(nullable NSString *)head;
/// How long gh may take, 5 s. And how long an answer stays fresh, 5 minutes.
@property NSTimeInterval timeout, fresh;
/// For the checks: calls, answers, failures, timeouts and skips since launch.
- (NSDictionary<NSString *, NSNumber *> *)stats;
#ifdef MM_TESTS
/// Forgets every answer, look and back-off, in memory only, and the kept file's place.
- (void)forget;
#endif
@end

NS_ASSUME_NONNULL_END
