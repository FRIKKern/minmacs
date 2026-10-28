// LocoHost's model: one server, and the words, menu and cards built from it.
// Everything here is pure. It reads a host and a view of the review and the plan, and returns text and specs,
// so the render tool draws the same menu and cards from fixture hosts that the app draws from the graph.
// Ported from LHHost in LocoHost's Ports.h and the menu and card code in its main.m.
#import <Foundation/Foundation.h>
#import "Core/MMExpert.h"

/// Active: a new connection or real CPU work in the last two samples. Recent: quiet for less than the quiet threshold.
typedef NS_ENUM(NSInteger, MMLHState) { MMLHActive = 0, MMLHRecent = 1, MMLHIdle = 2 };

/// One process that listens on at least one TCP port, with its whole process tree rolled up.
@interface MMLHHost : NSObject
@property pid_t pid, ppid;
@property uint64_t startSec;
@property (copy) NSString *key;                      // "pid:start", stable while the process lives
@property (copy) NSString *stableKey;                // decision 8: project folder and script, else folder and port
@property (copy) NSString *findingID;                // "locohost:server:<stableKey>"
@property (copy) NSString *name, *execPath, *cwd;
@property (copy) NSArray<NSString *> *args;
@property (strong) NSDate *started;
@property (copy) NSArray<NSNumber *> *ports;         // sorted
@property (copy) NSString *bind;                     // the primary port's address: 127.0.0.1, ::1 or *
@property (readonly) NSInteger port;                 // the lowest port below 49152, else the lowest
@property (copy) NSString *kind;                     // dev, service or other
@property (copy) NSString *framework;
@property (copy) NSString *repo, *repoRoot, *subdir, *branch, *worktree;
@property (strong) NSDate *repoTouched;              // the last commit of its checkout
@property (copy) NSString *merged;                   // its worktree in words: merged, squash-merged, not merged; nil for a main checkout
@property double cpuPercent, energyRank;             // the tree's CPU now, and its energy rank in this sample
@property uint64_t memory;                           // the tree's footprint
@property NSInteger processCount;
@property (copy) NSArray<NSNumber *> *treePids;
@property (copy) NSArray<NSNumber *> *treeStarts;    // the start time of each pid in treePids, same order
@property (copy) NSString *launcher;                 // "pnpm dev · Claude Code · cmux"
@property (copy) NSString *agent;                    // the registry name of a live agent above it, else nil
@property pid_t agentPid;
@property BOOL orphaned;                             // the shell, terminal or agent that started it is gone
@property pid_t wrapperPid;                          // a package manager runner above it, 0 for none
@property uint64_t wrapperStart;
@property (copy) NSArray<NSString *> *wrapperArgs;
@property (copy) NSString *wrapperCwd;
@property NSInteger connections, newConnections;
@property BOOL busy;
@property (copy) NSArray<NSString *> *clients;       // apps connected to it right now
@property (strong) NSDate *firstSeen, *lastActive;
@property double idleCPUSeconds;                     // CPU time burned since the last activity
@property (copy) NSArray<NSNumber *> *duplicates;    // ports of other dev servers on the same folder and branch
@property MMLHState state;
@property BOOL isProtected;
@property (copy) NSString *script;                   // the package.json script it runs, such as "dev"
@property (copy) NSDictionary *projectFacts;         // name, description, script, readme, configs
@property (copy) NSDictionary *session;              // agent, title, id, startedAt, lastActiveAt, match
@property (copy) NSString *placeLabel, *placeTab, *placeApp;   // where it runs, from Know's Where

@property (readonly) NSString *project;              // repo or worktree with subdir, else the folder
@property (readonly) NSString *shortName;            // what a row shows: the worktree or project for dev, else the framework
@property (readonly) NSString *url;
@property (readonly) NSString *command;              // the wrapper's command when there is one, else its own
@property (readonly) NSString *restartDir;           // where the restart command runs
@property (readonly) NSString *restartCommand;       // cd into the folder and run the command again
@property (readonly) BOOL isDev;

/// Every field, for the finding's facts and --json. Dates are seconds since 1970.
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

/// A shell word quoted when it needs it.
NSString *MMLHQuote(NSString *s);
/// What kind of server this is, from its name, command line and ports. Ported from Detect in LocoHost's Ports.m.
void MMLHDetect(NSString *name, NSArray<NSString *> *args, NSArray<NSNumber *> *ports, NSString **framework, NSString **kind);

#pragma mark Words

NSString *MMLHStateName(MMLHState s);                    // active, recent, idle
/// "requests from Safari", "working, CPU", "quiet 3h, open in Safari".
NSString *MMLHStateWords(MMLHHost *h);
/// "since last use 3h: 12m CPU, holds 905 MB".
NSString *MMLHWasteWords(MMLHHost *h);
/// "Claude Code session “Fix login”, last active 20m ago", or "no agent session found".
NSString *MMLHSessionWords(NSDictionary *session);
/// The menu bar's mode word: "Idle", "Proactive", "Eager".
NSString *MMLHModeLabel(NSString *mode);

#pragma mark The menu and cards

/// What the menu and cards need besides the hosts: the review, the plan and what was stopped.
/// The app fills it from the snapshot, and the render tool from fixtures.
@interface MMLHView : NSObject
@property (copy) NSArray<MMLHHost *> *hosts;
@property (copy) NSString *mode;                         // idle, proactive or eager
@property (copy) NSString *model;                        // the review's model in words, such as "Haiku"
@property (strong) NSDate *reviewAt;
@property (copy) NSString *reviewError, *summaryWords;
@property BOOL reviewing;
/// By findingID: {word, kind (keep, go, unsure), confidence, about, reason, judged, decidedBy}.
@property (copy) NSDictionary<NSString *, NSDictionary *> *verdicts;
/// By findingID: {stop, why}. Only dev servers have one.
@property (copy) NSDictionary<NSString *, NSDictionary *> *plan;
@property (copy) NSArray<NSString *> *candidates;        // findingIDs Close Idle stops
/// Recently stopped: {rid, port, framework, project, at, by, taken}. taken is YES when the port is in use again.
@property (copy) NSArray<NSDictionary *> *stopped;
/// By findingID: a fact that belongs to another expert, {label, value, expert, findingID}.
@property (copy) NSDictionary<NSString *, NSDictionary *> *links;
@property (copy) NSDictionary<NSString *, NSDate *> *keptUntil;   // by findingID
/// By findingID: the last Investigate run as -[MMInvestigation json], read from memory. Issue #35.
@property (copy) NSDictionary<NSString *, NSDictionary *> *investigations;
@property NSTimeInterval idleSeconds, watchingLeft;
/// The locohost.reviewMinutes pref, read on the graph queue, so the app's watch on main reads no pref.
@property NSInteger reviewMinutes;
@property NSInteger otherCount;                          // listeners of macOS and apps, never shown as rows
/// What an action asks for: stop, go, open, reveal, keep, copy-url, copy-restart, protect, restart, close-idle, review.
/// key is a findingID or, for restart, a record id. option is the Option alternate.
@property (copy) void (^act)(NSString *what, NSString *key, BOOL option);
@end

/// The worktree a server runs in and whether it is merged: "checkout-flow, merged", "acme-web, main checkout".
/// The value of the card's link to WorkForest.
NSString *MMLHWorktreeWords(MMLHHost *h);

/// The main menu, to DESIGN.md: header, summary, Close Idle and Review Now, the sections, and More.
MMMenuSpec *MMLHMenu(MMLHView *v);
/// The hover card of one host.
MMCardSpec *MMLHCard(MMLHHost *h, MMLHView *v);
/// The number beside the icon: the servers Close Idle would stop. nil when there are none.
NSString *MMLHBadge(MMLHView *v);
/// "2 idle servers", "3 servers", "no servers".
NSString *MMLHAccessibilityState(MMLHView *v);
