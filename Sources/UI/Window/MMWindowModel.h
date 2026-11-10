// The window that opens from the MinMacs icon, issue #62: prototype 195-a, Dock Below, with 197-b's Settings in place
// (branch ui-prototypes, docs/2.0/ui-prototypes/p/195-a.html and p/197-b.html).
//
//   +-----------------------------------------------------------------+
//   | 2 agents ask you                                                |
//   +------------------+--------------------------+-------------------+
//   | Servers      20  | Memory in use, last hour | Worktrees     16  |
//   | Agents       16  | Disk free, last hour     | Caches         5  |
//   | Apps, helpers 15 | (or a pointed row's story)|                   |
//   +------------------+--------------------------+-------------------+
//   | ring  42.4 / 64 GB   [ Fix Everything ]   3.9 GB memory back    |
//   |       182 GB free    7 fixes, x first     31.1 GB disk back     |
//   +-----------------------------------------------------------------+
//   |                                                    gear  power  |
//   +-----------------------------------------------------------------+
//
// This file is the view model only: plain values, no AppKit and no Core type, so the window, the render tool and the
// checks read the same thing. Sources/Shell builds one from each snapshot, off main (MMWindowFeed), and hands it to
// the window on main. The window draws what the model holds and nothing else: no disk, no process, no graph.
// Memory and disk are two numbers everywhere and are never summed. Every string is shown as is.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The two sides. Memory rows sit on the left, disk rows on the right.
typedef NS_ENUM(NSInteger, MMWindowSide) { MMWindowMemory = 1, MMWindowDisk = 2 };

/// What a row is, for its icon. The window draws a small mark of its own for each, never a logo.
typedef NS_ENUM(NSInteger, MMWindowKind) {
    MMWindowServer = 0,    // iconHint is the framework's name, such as "next", or nil
    MMWindowAgent,         // iconHint is the harness id, such as "claude-code"
    MMWindowApp,           // iconHint is the bundle id, so the window shows the app's own icon
    MMWindowHelper,
    MMWindowTabs,
    MMWindowWorktree,
    MMWindowCache
};

#pragma mark - The last hour

/// One filled line: 60 values, oldest first, one a minute. A minute with no value holds NSNull.
/// The window draws the line, the first and last value and how far it moved, and nothing when fewer than two
/// minutes are filled.
@interface MMWindowHour : NSObject
@property (copy) NSString *title;                       // "Memory in use", "Disk free"
@property (copy) NSString *explain;                     // "Higher means more of the 64 GB is in use"
@property (copy) NSArray *values;                       // NSNumber bytes or NSNull, 60 of them
@property MMWindowSide side;
@end

#pragma mark - Rows

/// One fact of a row's story, such as "Port" and "3000", or "Idle" and "3 d".
@interface MMWindowFact : NSObject
@property (copy) NSString *label, *value;
+ (instancetype)label:(NSString *)label value:(NSString *)value;
@end

/// One thing that holds memory or disk.
@interface MMWindowRow : NSObject
@property (copy) NSString *key;                         // stable across snapshots, so hover and scroll stay
@property MMWindowKind kind;
@property (copy, nullable) NSString *iconHint;
@property (copy) NSString *name;                        // ":3000 Next.js", "Tune the ranking", "fix-auth-redirect"
@property (copy, nullable) NSString *state;             // one quiet word: "merged", "kept", "will close"
@property double cpuPercent;                            // of one core; below 0 when not known, then not drawn
@property uint64_t bytes;                               // the one number
@property NSInteger tabs;                               // for MMWindowTabs, the count shown in the name
@property BOOL needsYou;                                // an agent that asks: a white diamond on its icon
@property BOOL inFix;                                   // Fix Everything touches it: a small orange mark
/// The row's own last hour, 60 NSNumber bytes or NSNull, or nil when Core keeps none. Only agents and servers have one.
@property (copy, nullable) NSArray *hour;
/// The story the middle shows while the pointer rests on the row: who owns it, where it is, why it stays.
@property (copy) NSArray<MMWindowFact *> *facts;
/// The name as every view draws it: a tabs row leads with its count, "3 Browser".
@property (readonly) NSString *shownName;
/// NO for a tabs row that holds no bytes: its count in the name is its number, and no size of 0 is drawn or read out.
@property (readonly) BOOL showsSize;
@end

/// One group with a still header: its title, its count and its rows, biggest first. Each group scrolls on its own.
@interface MMWindowGroup : NSObject
@property (copy) NSString *key, *title;                 // "servers", "Servers"
@property MMWindowSide side;
@property (copy) NSArray<MMWindowRow *> *rows;
@end

#pragma mark - The ring

/// One slice of the ring: a group's share of memory in use, or of the disk in use.
@interface MMWindowSlice : NSObject
@property (copy) NSString *group;                       // a group key, or "other"
@property uint64_t bytes;
@end

/// Memory by holder inside, the disk as the outer track.
@interface MMWindowRing : NSObject
@property uint64_t memoryUsed, memoryTotal;
@property uint64_t diskFree, diskTotal;
@property (copy) NSArray<MMWindowSlice *> *memory, *disk;
@end

#pragma mark - Fix Everything

/// One fix as the dock names it.
@interface MMWindowFix : NSObject
@property (copy) NSString *key, *title;                 // "wrapup:/path", "Wrap Up fix-auth-redirect"
@property uint64_t memoryBack, diskBack;
@property BOOL needsYou;                                // runs only on its own press, so Fix Everything skips it
@end

/// Where a run of Fix Everything stands. nil on the model when none runs and none just ended.
@interface MMWindowRun : NSObject
@property BOOL running;                                 // NO once it ended; the window shows the end, then lets go
@property (copy, nullable) NSString *step;              // "Stopping :3001", shown in the button while it runs
@property NSInteger done, total;                        // fixes landed, fixes planned
@property uint64_t memoryBack, diskBack;                // what has come back so far
@property uint64_t memoryPlanned, diskPlanned;          // what the run set out to give back; the two lines fill to these
@property (copy, nullable) NSString *endTitle;          // "7 fixes done"
@property (copy, nullable) NSString *endNote;           // "Skipped 2 agents that ask you and 4 blocked. Deletes went to the Trash."
@end

#pragma mark - Settings

/// One choice of a rule with what it does, in plain words.
@interface MMWindowChoice : NSObject
@property (copy) NSString *title;                       // "Off", "Ask", "Auto"
@property (copy) NSString *explain;                     // "Stops a server after 2 h idle."
@end

/// One rule: its name, its choices and the one picked. A change applies at once.
@interface MMWindowRule : NSObject
@property (copy) NSString *ruleID, *title;              // "servers", "Stop idle servers"
@property (copy) NSArray<MMWindowChoice *> *choices;
@property NSInteger picked;
@property (copy, nullable) NSString *note;              // what it would do next: "1 ready. It waits for your press."
@end

/// One switch, such as the lid or Open at login.
@interface MMWindowSwitch : NSObject
@property (copy) NSString *switchID, *title;            // "lid", "Keep working with the lid closed"
@property BOOL on;
@property (copy, nullable) NSString *note;
@end

@interface MMWindowSettings : NSObject
@property (copy) NSArray<MMWindowRule *> *rules;
@property (copy) NSArray<MMWindowSwitch *> *switches;
@end

#pragma mark - The whole window

@interface MMWindowModel : NSObject
@property uint64_t generation;                          // the snapshot's; the window drops an older model
/// The top line, only when something needs the person: "2 agents ask you". nil hides the line's words.
@property (copy, nullable) NSString *asks;
@property (strong, nullable) MMWindowHour *memoryHour, *diskHour;
@property (copy) NSArray<MMWindowGroup *> *memoryGroups, *diskGroups;
@property (strong) MMWindowRing *ring;
/// In Fix Everything's order. Empty when there is nothing to fix: then the button is dimmed in place.
@property (copy) NSArray<MMWindowFix *> *fixes;
@property (strong, nullable) MMWindowRun *run;
@property (strong) MMWindowSettings *settings;
- (nullable MMWindowRow *)row:(NSString *)key;
/// What Fix Everything gives back: the fixes that do not need the person, each side summed on its own.
- (uint64_t)memoryBack;
- (uint64_t)diskBack;
- (NSInteger)fixCount;
@end

NS_ASSUME_NONNULL_END
