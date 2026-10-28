// The sheet: what MinMacs shows when you click its icon, chosen as prototype 54-a, Day Lanes
// (docs/2.0/ui-prototypes on branch ui-prototypes, p/54-a.html). It replaces the native menu of each expert.
// A 760 x 580 sheet hangs from the one MinMacs icon, with three tabs: Workstreams, Performance and Settings.
// Advanced mode in Settings unfolds Agents, Servers, Worktrees and Disk, and Performance is called Apps there.
//
// This file is the model only: plain data built on the graph queue, with no AppKit, so the sheet, the render tool,
// the CLI and the tests read the same thing. MMSheetBuilder collects what each expert adds through
// -[MMExpert sheet:snapshot:], then -build gives one immutable MMSheet. Main reads -[MMSnapshot preparedFor:@"sheet"].
// Every sentence here is shown as is, so every string follows the plain words of docs/DESIGN.md.
#import <Foundation/Foundation.h>
#import "Core/MMExpert.h"

NS_ASSUME_NONNULL_BEGIN

@class MMSnapshot;

/// The three modes every rule has. Off does nothing. Ask shows what it would do and waits for a press.
/// Auto acts on its own when the rule's time comes, after the fresh check and with an undo record, as Act does today.
/// MMSheetModeFrom maps the older modes: Idle is Off, Proactive is Ask, Eager is Auto.
typedef NS_ENUM(NSInteger, MMSheetMode) { MMSheetModeOff = 0, MMSheetModeAsk = 1, MMSheetModeAuto = 2 };
MMSheetMode MMSheetModeFrom(NSInteger oldMode);
NSInteger MMOldModeFrom(MMSheetMode mode);
NSString *MMSheetModeWord(MMSheetMode mode);             // "Off", "Ask", "Auto"

/// The tabs. The first three always show. The four advanced ones show only while Advanced mode is on.
typedef NS_ENUM(NSInteger, MMSheetTab) {
    MMSheetTabWorkstreams = 0, MMSheetTabPerformance, MMSheetTabSettings,
    MMSheetTabAgents, MMSheetTabServers, MMSheetTabWorktrees, MMSheetTabDisk
};
NSString *MMSheetTabName(MMSheetTab tab, BOOL advanced); // Performance reads "Apps" while Advanced is on

#pragma mark - Workstreams: today as lanes

/// What an agent did in one stretch of today.
typedef NS_ENUM(NSInteger, MMLaneKind) {
    MMLaneWorking = 0,                                  // a thick bar in the agent's color
    MMLaneIdle,                                         // a thin gray line
    MMLaneWaiting,                                      // white and pulsing: it waits for you
    MMLaneReady                                         // a dotted line in the workstream color after it finished
};

/// One stretch of a lane's track. end nil means it runs until now.
@interface MMLaneSpan : NSObject
@property MMLaneKind kind;
@property (strong) NSDate *start;
@property (strong, nullable) NSDate *end;
+ (instancetype)kind:(MMLaneKind)kind start:(NSDate *)start end:(nullable NSDate *)end;
@end

/// The server line under a track: busy while it serves requests, dashed while it waits unused.
@interface MMServerSpan : NSObject
@property BOOL busy;
@property (strong) NSDate *start;
@property (strong, nullable) NSDate *end;
@end

/// A mark on the track, such as the PR opening or merging, or the agent finishing.
typedef NS_ENUM(NSInteger, MMLaneMarkKind) { MMLaneMarkPROpen = 0, MMLaneMarkPRMerged, MMLaneMarkFinished };
@interface MMLaneMark : NSObject
@property MMLaneMarkKind kind;
@property (strong) NSDate *at;
@property (copy, nullable) NSString *label;             // shown on hover, such as "PR #212 merged"
@end

/// One thing a workstream holds, in the Holds column and the lane's card.
typedef NS_ENUM(NSInteger, MMHoldKind) { MMHoldAgent = 0, MMHoldServer, MMHoldPR, MMHoldWorktree, MMHoldCache, MMHoldBrowser };
@interface MMHold : NSObject
@property MMHoldKind kind;
@property (copy) NSString *label;                       // ":3000", "PR #212", "1.8 GB"
@property (copy, nullable) NSString *detail;            // "next dev, in use", "merged"
@property MMRowMark mark;                               // busy, idle, waiting, finished; a shape as well as a color
@property (copy, nullable) NSString *expert, *findingID;// where it comes from, so actions and cards reach the owner
@property BOOL subagent;                                // a small dot beside its agent
@end

/// What the lane says comes next, live. line is the strong first line, sub the gray second line.
typedef NS_ENUM(NSInteger, MMNextStyle) { MMNextPlain = 0, MMNextAsks, MMNextReady, MMNextQuiet };
@interface MMLaneNext : NSObject
@property MMNextStyle style;
@property (copy) NSString *line;                        // "Asks you", "Ready 2 h", "Working"
@property (copy, nullable) NSString *sub;               // "Allow npm run build?", "waits for your press", "Auto wraps it up in 22 h"
@property (strong, nullable) NSDate *at;                // when the next automatic step runs; the sheet counts down to it
@end

/// One workstream as one lane.
typedef NS_ENUM(NSInteger, MMLaneState) { MMLaneStateWorking = 0, MMLaneStateWaiting, MMLaneStateIdle, MMLaneStateReady, MMLaneStateKept };
@interface MMLane : NSObject
@property (copy) NSString *laneID;                      // the workstream owner's key, stable across snapshots
@property (copy) NSString *name;                        // "speed-3", "fix auth redirect"
@property (copy) NSString *where;                       // "cmux tab speed-3", "Codex app", "Cursor, barkpark-studio window"
@property (copy) NSString *tool;                        // the agent's harness id, for its icon: "claude-code", "codex", "cursor"
@property MMLaneState state;
@property (copy) NSArray<MMLaneSpan *> *spans;          // since the day started, oldest first
@property (copy) NSArray<MMServerSpan *> *servers;
@property (copy) NSArray<MMLaneMark *> *marks;
@property (strong, nullable) NSDate *readySince;        // set when its agent finished and its branch is merged
@property (strong) MMLaneNext *next;
@property (copy) NSArray<MMHold *> *holds;
@property uint64_t freeBytes;                           // what Wrap Up frees, shown in the Holds column of a ready lane
@property (copy) NSArray<MMActionSpec *> *actions;      // on hover: Go to Tab, Wrap Up, Stop Servers, Open PR, Keep, Open in Editor
@property (strong, nullable) MMCardSpec *card;          // on hover of its name: everything it holds
@end

/// One thing no workstream owns, as a calm chip under the lanes.
@interface MMLeftover : NSObject
@property (copy) NSString *leftoverID, *name;           // ":6006 storybook", "DerivedData of gone projects"
@property (copy, nullable) NSString *detail;            // "idle 3 d", "stale"
@property uint64_t bytes;
@property BOOL kept;
@property (copy, nullable) NSString *expert, *findingID;
@property (strong, nullable) MMCardSpec *card;
@end

#pragma mark - Rules: Off, Ask, Auto where you choose them

/// One rule, such as Wrap Up, Close apps or Leftovers. The sheet draws its three-way switch, explains the mode
/// in place, and counts down to the next automatic step. In Workstreams the Wrap Up rule sits in the Next
/// column header as a chip that opens this rule in a popover.
@interface MMSheetRule : NSObject
@property (copy) NSString *ruleID;                      // "wrapup", "apps", "leftovers", "agents", "servers", "worktrees", "disk"
@property (copy) NSString *title;                       // "Wrap Up"
@property MMSheetMode mode;
@property (copy) NSString *explain;                     // what this mode does, in one or two plain sentences
@property (copy, nullable) NSString *preview;           // what it would do next: "Next: Auto wraps up fix auth redirect in 22 h."
@property (strong, nullable) NSDate *nextAt;
@property (copy, nullable) NSArray<NSString *> *valueTitles;   // the "after" choices, such as "2 h", "1 day", "1 week"
@property NSInteger value;                              // index into valueTitles
@property (copy) NSString *expert;                      // who owns the setting: the change goes there
@end

#pragma mark - Performance

/// One app or agent row in Performance. An agent's row sits under the app it runs in and links to its lane.
@interface MMPerfRow : NSObject
@property (copy) NSString *name;
@property (copy, nullable) NSString *bundleID;          // for the app's own icon
@property uint64_t memory;
@property double cpu;                                   // percent of one core
@property (copy, nullable) NSString *reason;            // "Claude Code works", "serving :51789", "you keep it"
@property (copy, nullable) NSString *laneID;            // an agent links to its lane
@property (copy) NSArray<MMPerfRow *> *agents;          // the agents that run inside this app
@property (copy, nullable) NSString *expert, *findingID;
@property (copy) NSArray<MMActionSpec *> *actions;
@end

/// The apps by fate: Will close, Unsorted, Kept, Spared.
@interface MMPerfGroup : NSObject
@property (copy) NSString *title;
@property (copy) NSArray<MMPerfRow *> *rows;
@end

@interface MMSheetPerformance : NSObject
@property double cpuPercent;                            // the whole Mac, 0 to 100
@property double cpuFreed;                              // the part MinMacs Now would free
@property uint64_t memoryUsed, memoryTotal, memoryFreed;
@property (copy) NSString *pressure;                    // "normal", "warn", "critical", in plain words
@property (copy) NSArray<MMPerfGroup *> *groups;
@property (strong, nullable) MMActionSpec *now;         // "MinMacs Now · 3 apps, 2.5 GB"
@property (strong, nullable) MMActionSpec *restore;     // "Restore · 3 apps"
@end

#pragma mark - Advanced tabs

/// One advanced tab as groups of rows, with its own rule line at the top and an optional graph.
@interface MMSheetRow : NSObject
@property (copy) NSString *name;
@property (copy, nullable) NSString *detail;            // the gray part after the name
@property (copy, nullable) NSString *value, *value2;    // right-aligned, such as "412 MB" and "busy"
@property MMRowMark mark;
@property (copy, nullable) NSString *laneID;
@property (copy, nullable) NSString *expert, *findingID;
@property (copy) NSArray<MMActionSpec *> *actions;
@property (strong, nullable) MMCardSpec *card;
/// For Servers: requests a minute over the last hour, 60 values, oldest first. The sheet draws a heartbeat line.
@property (copy, nullable) NSArray<NSNumber *> *heartbeat;
@end

@interface MMSheetGroup : NSObject
@property (copy) NSString *title;
@property (copy) NSArray<MMSheetRow *> *rows;
@end

@interface MMSheetList : NSObject
@property MMSheetTab tab;
@property (copy) NSString *headline;                    // "14 worktrees · 6.2 GB merged"
@property (strong, nullable) MMSheetRule *rule;
@property (copy) NSArray<MMSheetGroup *> *groups;
@end

#pragma mark - Settings

@interface MMSheetSettings : NSObject
@property (copy) NSArray<MMSheetRule *> *rules;         // Wrap Up, Close apps, Leftovers
@property BOOL lidOn;                                   // "Keep working with the lid closed"
@property (copy) NSString *lidNote;                     // "It stops at 20 % battery, off Wi-Fi or when the Mac runs hot."
@property BOOL oneIcon, openAtLogin, advanced;
@end

#pragma mark - The whole sheet

@interface MMSheet : NSObject
@property (strong) NSDate *builtAt, *dayStart;          // dayStart is 9:00 today, or the first activity if earlier
@property (copy) NSString *headLine;                    // "4 agents working · lid can close"
@property (copy) NSArray<MMLane *> *lanes;              // waiting first, then working, idle, ready, kept
@property (copy) NSArray<MMLeftover *> *leftovers;
@property (strong, nullable) MMActionSpec *wrapUpAll;   // "Wrap Up 2 Workstreams · 4.4 GB"
@property (strong, nullable) MMActionSpec *cleanUpLeftovers;   // "Clean Up Leftovers · 31 GB"
@property (strong) MMSheetRule *wrapUpRule;
@property (strong) MMSheetPerformance *performance;
@property (strong) MMSheetSettings *settings;
@property (copy) NSDictionary<NSNumber *, MMSheetList *> *advanced;   // keyed by MMSheetTab
@property NSUInteger waitingCount;                      // the dot on the icon when anything waits for you
@property (copy) NSString *accessibilityLabel;          // "MinMacs, 1 agent waits for you, 2 workstreams ready"
@end

/// Collects the parts while the graph queue prepares a snapshot. Core adds the lanes from workstreams and the day log.
/// Each expert adds what it owns through -[MMExpert sheet:snapshot:]: LocoHost the servers, WorkForest the worktrees,
/// Noo-Noo the caches and leftovers, MinMacs the apps, Insomnia the lid. Not thread safe: one queue builds one sheet.
@interface MMSheetBuilder : NSObject
@property (readonly) MMSnapshot *snapshot;
- (instancetype)initWithSnapshot:(MMSnapshot *)snapshot;
/// The lane of the workstream that owns this owner key, or nil. An expert adds holds, marks and actions to it.
- (nullable MMLane *)laneFor:(NSString *)workstreamKey;
- (void)addHold:(MMHold *)hold toLane:(NSString *)laneID;
- (void)addAction:(MMActionSpec *)action toLane:(NSString *)laneID;
- (void)addLeftover:(MMLeftover *)leftover;
- (void)addRule:(MMSheetRule *)rule;
- (void)setPerformance:(MMSheetPerformance *)performance;
- (void)setList:(MMSheetList *)list;
- (void)setLid:(BOOL)on note:(NSString *)note;
- (MMSheet *)build;
@end

/// Builds the whole sheet for a snapshot on the calling queue, never on main: Core's lanes, then every expert's part.
MMSheet *MMSheetFrom(MMSnapshot *snapshot, NSArray<id<MMExpert>> *experts);

NS_ASSUME_NONNULL_END
