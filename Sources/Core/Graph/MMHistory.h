// The last hour, in memory only. One value a minute for 60 minutes, for the 2.0 UI to draw later.
// New code, for the "Proposed facts" of the ui-prototypes pages: load and memory strips, server pulses and agent lanes.
// Nothing here is ever written to disk. A restart starts an empty hour.
//
// Which pass fills each ring. There is no timer of its own:
// - The Mac ring, whole-Mac CPU percent and memory used: each graph build, from two host_statistics calls the build
//   makes. The CPU percent is the share of all cores busy since the build before, so 100 means every core.
// - The disk ring, free bytes on the home volume: each graph build, from MMPower.diskFree of the Senses pass.
// - One ring per live agent tree: each graph build, from MMAgent.treeCPU and treeFootprint of the registry's agents
//   in that build's Senses sample. Its state changes come from MMAgent.state in the same build.
// - One ring per server tree: each graph build, from the cost of LocoHost's server findings, keyed by the first
//   MMProcKey the finding names.
// - Subagent starts: each SubagentStart hook event that MMAgentEvents reads from cmux events, on its events queue.
// A build that the graph skips because its facts did not change adds nothing. The graph builds at least every 30
// seconds, so a minute with a running pass holds at least one value. A minute with no build holds none.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"
#import "Core/Know/MMRegistry.h"

@class MMSnapshot;

/// The hard caps. Every ring is a fixed array, so the store never grows past them.
enum {
    MMHistoryMinutes = 60,         // one slot a minute
    MMHistoryMaxRings = 200,       // every ring: the Mac, the disk, and the trees
    MMHistoryMaxStates = 32,       // state changes kept per agent, the newest
    MMHistoryMaxSubagents = 256,   // subagent starts kept, the newest
};
/// A tree whose process is gone keeps its ring this long, then the ring is dropped.
extern const NSTimeInterval MMHistoryGoneKeep;

typedef NS_ENUM(uint8_t, MMHistoryKind) { MMHistoryMac = 1, MMHistoryDisk, MMHistoryAgent, MMHistoryServer };
/// "mac", "disk", "agent" or "server".
NSString *MMHistoryKindName(MMHistoryKind kind);

/// One minute of one ring. passes is 0 when no pass filled that minute, and then both values are -1.
/// cpuPercent is the mean of the passes in the minute, and -1 for the disk ring.
/// megabytes is memory used for the Mac, free space for the disk and the tree's footprint for a tree. The store keeps
/// CPU in tenths of a percent and megabytes whole, 8 bytes a minute.
typedef struct {
    uint32_t minute;               // minutes since 1970
    uint16_t passes;
    float cpuPercent;
    float megabytes;
} MMHistoryMinute;

/// One state change of one agent. The store keeps whole seconds.
typedef struct { NSTimeInterval at; MMAgentState state; } MMHistoryStateChange;

/// One tree a pass saw, for -noteTrees:at:. A graph build makes these from its agents and server findings.
@interface MMHistoryTreeSample : NSObject
@property MMHistoryKind kind;                        // agent or server
@property MMProcKey key;
@property double cpuPercent;                         // 100 is one core
@property uint64_t footprint;                        // bytes
@property MMAgentState state;                        // agents only
@property (copy) NSString *label;                    // the harness, or the server's title
@property (copy) NSString *ident;                    // the session id, or the server's finding id
@end

/// One ring in a read-only copy. minuteAt: 0 is the oldest of the hour and 59 the copy's own minute.
@interface MMHistoryRing : NSObject
@property (readonly) MMHistoryKind kind;
@property (readonly) MMProcKey key;                  // zero for the Mac and the disk
@property (readonly, copy) NSString *label, *ident;
@property (readonly) NSTimeInterval firstSeen, lastSeen;
@property (readonly) NSTimeInterval goneAt;          // 0 while the process runs
- (MMHistoryMinute)minuteAt:(NSUInteger)i;           // a gap when the slot holds an older minute or none
/// The agent's state changes within the hour, oldest first.
- (NSArray<NSValue *> *)stateChanges;               // MMHistoryStateChange values
- (NSDictionary *)json;
@end

/// A read-only copy of the whole hour, as of one fill. Safe from any queue. Nothing in it changes.
/// A fill only copies bytes. The ring objects are made the first time something reads them.
@interface MMHistoryView : NSObject
@property (readonly) NSTimeInterval at;              // when the copy was made
@property (readonly) uint32_t minute;                // the minute of slot 59
@property (readonly) MMHistoryRing *mac, *disk;      // nil before the first fill
@property (readonly) NSArray<MMHistoryRing *> *trees;   // agents, then servers, each oldest first
/// Subagent starts within the hour, oldest first: {"at", "agent", "session"}.
@property (readonly) NSArray<NSDictionary *> *subagentStarts;
@property (readonly) NSUInteger rings;               // every ring held, the Mac and the disk included
@property (readonly) NSUInteger refused;             // tree samples not kept since launch, because 200 rings were live;
                                                     // a tree refused by 10 passes counts 10
@property (readonly) NSUInteger dropped;             // rings of gone trees dropped since launch
@property (readonly) NSUInteger fills;               // passes that filled the store since launch
@property (readonly) NSUInteger storeBytes;          // the store's fixed arrays, as allocated
/// The bytes this copy wrote. Each copy has one buffer with room for the caps. When no view reads it any more it goes
/// back to the store, which keeps two, so a build every 5 seconds reuses the same memory.
@property (readonly) NSUInteger copyBytes;
- (MMHistoryRing *)treeFor:(MMProcKey)key;
/// The shape `minmacs history --json` prints. Values run oldest first, null for a minute with no pass.
- (NSDictionary *)json;
@end

/// The one store. Every method takes a lock for microseconds, so any queue may call it, main included.
@interface MMHistory : NSObject
+ (instancetype)shared;
/// The graph queue calls this once per build, before the snapshot is published, and the snapshot carries the copy
/// it returns. It reads the host's CPU ticks and VM counters, then the agents, servers and disk of snap's facts.
- (MMHistoryView *)fillFrom:(MMSnapshot *)snap;
/// What a fill does, in parts, with the time given. A test or the bench passes fixture values and times.
/// A Mac value below 0 is left out, so the disk can be noted alone.
- (void)noteMacCPU:(double)cpuPercent memoryUsed:(uint64_t)used diskFree:(uint64_t)free at:(NSTimeInterval)t;
/// Fills each tree's ring for the minute of t, and marks every tree ring not in trees as gone at t.
/// A gone ring is dropped MMHistoryGoneKeep after it went. A key that is new starts a ring, so a pid used again
/// with a new start time never adds to the ring of the process before it.
- (void)noteTrees:(NSArray<MMHistoryTreeSample *> *)trees at:(NSTimeInterval)t;
- (void)noteSubagentStart:(NSString *)agent session:(NSString *)sessionID at:(NSTimeInterval)t;
/// A new copy as of t. -fillFrom: makes one per build. A copy at a later t shows the minutes since as gaps.
- (MMHistoryView *)viewAt:(NSTimeInterval)t;
/// The copy the last fill made, or an empty one.
@property (readonly) MMHistoryView *latest;
/// Listens for SubagentStart events on MMAgentEvents. MMCoreStart calls it, MMCoreStop calls stop.
- (void)start;
- (void)stop;
@end

/// The whole Mac now: CPU ticks of every core and memory used as Activity Monitor counts it, app memory plus wired
/// plus compressed. Two host_statistics calls, a few microseconds. MMHistory reads it once per build.
typedef struct { uint64_t busyTicks, totalTicks, memoryUsed; } MMHostLoad;
MMHostLoad MMReadHostLoad(void);
