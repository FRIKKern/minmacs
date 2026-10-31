// The Performance tab as a model: the ring, the two sides, the fixes and the look-back, so the sheet UI only draws it.
// It maps design 132-a on the ui-prototypes branch to what Core measures today. Every number below names its source.
// It is built on demand from one MMSnapshot, off main, such as on the graph queue or in a verb. It holds no text
// but the names and keys its rows and fixes come from, so a calm Mac shows only numbers.
//
// What 132-a draws and Core does not measure, so the model leaves it out:
// - The memory a stopped process still holds for a moment, 132-a's "Letting go". No fact follows it.
// - Memory per browser tab, and the noise tabs fix. Core reads a tab's URL and host, never its memory, and a tab trim
//   gives back 0 memory in the gains log. The tabs group counts localhost tabs only.
// - Helpers outside a finished workstream. Core finds a helper only for a Wrap Up subject.
// - Leftover worktrees that nobody holds. WorkForest lists every checkout as a worktree row, so the disk side has
//   worktrees and caches and clutter.
// - The time a fix takes, a fix's live progress, the state words on rows and the rule that is Off.
// - CPU and network beside the ring. MMHistory and MMNet hold them, and minmacs history and net show them.
// - The day chart of the look-back. The gains log has the days, and minmacs gains shows them.
#import <Foundation/Foundation.h>
#import "Core/Graph/MMGraph.h"
#import "Core/Act/MMAct.h"

@class MMHistoryView, MMGains;
@protocol MMExpertPolicy, MMAction;

/// The two sides. Memory and disk are two numbers and are never summed.
typedef NS_ENUM(NSInteger, MMPerformanceSide) { MMPerformanceMemory = 1, MMPerformanceDisk = 2 };
/// What a row's number counts. Every memory and disk row counts bytes. A tabs row counts its tabs, since Core
/// reads no tab's memory: the browser's own row holds it.
typedef NS_ENUM(NSInteger, MMPerformanceUnit) { MMPerformanceBytes = 0, MMPerformanceTabs = 1 };

/// The group keys, as 132-a orders them. Memory: servers, agents, apps, tabs, helpers. Disk: worktrees, clutter.
/// Other is the ring's rest, the part no group holds.
extern NSString *const MMPerformanceServers, *const MMPerformanceAgents, *const MMPerformanceApps,
    *const MMPerformanceTabsGroup, *const MMPerformanceHelpers, *const MMPerformanceWorktrees,
    *const MMPerformanceClutter, *const MMPerformanceOther;
/// The rows a group shows folded, 132-a's constants: servers 6, agents 1, apps 2, tabs 0, helpers 0, worktrees 12,
/// clutter 10. The model holds every row. Folding is the view's job.
NSInteger MMPerformanceFold(NSString *group);

/// One part on one side: a finding, or a Wrap Up part that is not in the snapshot's findings.
@interface MMPerformanceRow : NSObject
/// The finding id. A helper or tabs part adds "|" and its instance key, since two can share a finding id.
@property (readonly, copy) NSString *key;
@property (readonly, copy) NSString *findingID, *expert, *group;
@property (readonly, copy) NSString *name;              // the finding's title
@property (readonly) MMPerformanceSide side;
/// The one number. Memory rows: the finding's cost.ramBytes. Disk rows: cost.diskFreed. Tabs rows: the tabs.
@property (readonly) uint64_t number;
@property (readonly) MMPerformanceUnit unit;
/// YES for an agent whose state is waiting on the person, from MMAgent.state.
@property (readonly) BOOL needsYou;
- (NSDictionary *)json;
@end

/// One group of rows, biggest number first.
@interface MMPerformanceGroup : NSObject
@property (readonly, copy) NSString *key;
@property (readonly) MMPerformanceSide side;
@property (readonly) NSInteger fold;
@property (readonly) NSArray<MMPerformanceRow *> *rows;
- (NSDictionary *)json;
@end

/// One side of the ring: the whole, what is used, and the used part by group with the rest as other.
/// Memory: total from NSProcessInfo.physicalMemory, used from the snapshot's Mac ring in Graph/MMHistory.h, or from
/// MMReadHostLoad when the snapshot has no filled minute, as a cold CLI's.
/// Disk: total and free from MMPower.diskTotal and diskFree, so used is total less free.
/// The parts count each thing once. In memory a process counts for the first group that holds it, in the order
/// servers, agents, helpers, then apps, when the snapshot has a sample: an agent's tree holds the servers it started,
/// and an app's memory holds the processes it is responsible for. In disk a cache inside a worktree row counts in
/// caches and clutter only, so the worktree's part is its own bytes less those.
/// A footprint holds compressed memory too, so the parts can pass memory used. Then the last parts are cut to fit, and
/// cut holds the bytes taken off. The parts and other always add up to used.
@interface MMPerformanceSideRing : NSObject
@property (readonly) MMPerformanceSide side;
@property (readonly) uint64_t total, used;
@property (readonly) NSDictionary<NSString *, NSNumber *> *parts;   // group key to bytes, other included
@property (readonly) NSArray<NSString *> *order;        // the part keys in ring order, other last
@property (readonly) uint64_t cut;
- (NSDictionary *)json;
@end

/// One fix: one action an expert already offers, or one Wrap Up plan, with what it gives back.
/// Kinds: wrapup, a finished workstream's MMWrapUpPlan; stop, LocoHost's servers that pass MustKeep; quit, MinMacs's
/// apps on the close list; remove, WorkForest's merged worktrees outside every Wrap Up; trash, Noo-Noo's clutter to
/// the Trash; clean, Noo-Noo's tool cleanups, which run only when the person presses them.
@interface MMPerformanceFix : NSObject
/// "wrapup:<path>", or the kind for the others, such as "stop".
@property (readonly, copy) NSString *key, *kind, *expert;
/// Memory back: the cost.ramBytes of each finding it stops or quits, each finding once. 0 for a removal or a cleanup.
@property (readonly) uint64_t memoryBack;
/// Disk back: what deleting frees, cost.diskFreed, or a Wrap Up plan's freedBytes, which counts a cache inside its
/// worktree once.
@property (readonly) uint64_t diskBack;
/// The row keys it touches, each one a row of a group.
@property (readonly) NSArray<NSString *> *rows;
/// YES when it runs only on the person's press, as a tool's own cleanup with no undo does.
@property (readonly) BOOL needsYou;
/// What orders the list, never shown: the larger of memory back as a share of total memory and disk back as a share
/// of the disk's size. 132-a weighs memory more under pressure, 1.5 times at warn and 2.5 at critical, and disk 3
/// times under 100 GB free. Memory and disk stay apart, since the larger share wins and nothing is summed.
@property (readonly) double share;
/// The plan for a wrapup, run with MMRunWrapUp. nil for the other kinds.
@property (readonly) MMWrapUpPlan *wrapUp;
/// The actions for the other kinds, each run with MMRunAction and policy. Empty for a wrapup.
@property (readonly) NSArray<id<MMAction>> *actions;
@property (readonly) id<MMExpertPolicy> policy;
- (NSDictionary *)json;
@end

/// What came back, from the gains log of Store/MMGains.h: this week is its 7-day summary's total, today its today.
/// Numbers only. Memory back and disk back are two numbers.
@interface MMPerformanceLookBack : NSObject
@property (readonly) uint64_t weekMemory, weekDisk, todayMemory, todayDisk;
/// From the dictionary -[MMGains summary:now:] returns, read with 7 days.
+ (instancetype)fromSummary:(NSDictionary *)summary;
/// Reads the table's 7-day summary. Blocks on disk, so in the app it runs off main.
+ (instancetype)read:(MMGains *)gains now:(NSDate *)now;
- (NSDictionary *)json;
@end

/// The whole tab for one snapshot.
@interface MMPerformance : NSObject
@property (readonly) uint64_t generation;
@property (readonly) MMPerformanceSideRing *memory, *disk;
/// Memory groups in 132-a's order, then disk groups. Every group is there, empty or not.
@property (readonly) NSArray<MMPerformanceGroup *> *memoryGroups, *diskGroups;
/// Biggest share first. Fix Everything runs them in this order.
@property (readonly) NSArray<MMPerformanceFix *> *fixes;
@property (readonly) MMPerformanceLookBack *lookBack;
/// The rows that need the person, such as agents that ask.
@property (readonly) NSInteger needsYou;
- (MMPerformanceRow *)row:(NSString *)key;
/// Builds the model. history is the hour the memory ring reads; nil reads s.history. lookBack may be nil for none.
/// Reads the snapshot, each expert's actions and policies, and MMMustKeep for each fix, which reads the keeps file.
+ (instancetype)from:(MMSnapshot *)s history:(MMHistoryView *)history lookBack:(MMPerformanceLookBack *)lookBack;
/// The same with s.history and the look-back read from MMGains.shared now. Blocks on disk.
+ (instancetype)from:(MMSnapshot *)s;
/// The shape `minmacs performance --json` prints.
- (NSDictionary *)json;
@end
