// What came back: a kept log of memory and disk that finished actions gave back, for "what got better lately".
// Designs 100 to 103 on the ui-prototypes branch. It lives in minmacs.sqlite, the log of MMLog.h, in its own table
// gains, which keeps 30 days. Act writes one row when an action finishes, and restore takes the row back.
//
// What the numbers mean:
// - Memory back is the footprint of the process trees a stop or a quit ended, summed over the finding's processes
//   from the fresh sample read right before the action ran. A pid counts once. A tab trim, a move to the Trash, a
//   removal and a tool's cleanup end no process, so their memory back is 0.
// - Disk back is what MMSizer said deleting frees, the finding's cost.diskFreed. A tool's cleanup with no size from
//   the Sizer counts the statfs delta of its record instead. A move to the Trash frees nothing until the Trash is
//   emptied, so its bytes wait as "in the Trash" and count as back only once every item it moved is gone from the
//   Trash and not back at its old path. An item put back by hand never counts.
//   When the Trash refuses a look, which it may without Full Disk Access, nothing can be verified and the bytes
//   stay in the Trash.
// - Memory back and disk back are two numbers and are never summed.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MMFinding, MMFacts, MMUndoRecord;
@protocol MMAction;

/// The kinds of thing that came back.
extern NSString *const MMGainServer, *const MMGainApp, *const MMGainTab, *const MMGainHelper, *const MMGainCache,
    *const MMGainWorktree, *const MMGainWorkstream;
/// Who did it: you from a menu or the CLI, Auto from a mode or an expert's own rule, or a run of several steps
/// such as Wrap Up, whose parts are each a row.
extern NSString *const MMGainByYou, *const MMGainByAuto, *const MMGainByRun;
/// Where a row's disk bytes stand.
extern NSString *const MMGainDiskNone;      // nothing on disk: a stop, a quit, a trim
extern NSString *const MMGainDiskFreed;     // deleted for good, so the bytes are back
extern NSString *const MMGainDiskTrash;     // in the Trash, not back yet
extern NSString *const MMGainDiskPutBack;   // the item is back at its old path, by hand, so it never counts

/// How many days the table keeps. A row older than this is dropped on the next write or read.
extern const NSInteger MMGainsKeepDays;     // 30

/// One finished action and what it gave back. Immutable once read.
@interface MMGain : NSObject
@property (readonly, copy) NSString *rid;               // the undo record's rid
@property (readonly, copy, nullable) NSString *run;     // the Wrap Up record a part belongs to, or nil
@property (readonly, copy) NSString *kind;              // MMGainServer and the rest; a Wrap Up's parts are workstream
@property (readonly, copy, nullable) NSString *part;    // for a part of a run, what the part itself was, such as server
@property (readonly, copy) NSString *who;               // MMGainByYou, MMGainByAuto or MMGainByRun
@property (readonly, copy) NSString *by;                // the record's own by: manual, cli, proactive, eager, guard
@property (readonly, copy) NSString *expert, *subject;
/// The workstream it belonged to when known: the owner id of its workstream, or of its worktree when the session
/// had ended, as a Wrap Up's is. nil when the finding had no such owner.
@property (readonly, copy, nullable) NSString *workstream;
@property (readonly) NSDate *at;                        // when the action finished
@property (readonly) uint64_t memoryBytes;              // memory back
@property (readonly) uint64_t diskBytes;                // what MMSizer said deleting frees; back only when diskState is freed
@property (readonly, copy) NSString *diskState;         // MMGainDiskNone and the rest
@property (readonly) NSInteger items;                   // tabs closed for a trim, else 1
@property (readonly) BOOL undone;                       // restored since, so it gave its gain back
/// {rid, run, kind, part, who, by, expert, subject, workstream, at, memoryBack, diskBack, diskInTrash, diskState,
/// items, undone}. diskBack is diskBytes when the state is freed and 0 otherwise; diskInTrash is the same for trash.
- (NSDictionary *)json;
@end

/// The table. Every method blocks on disk. In the app call it off main; a CLI may call it on main.
@interface MMGains : NSObject
/// The table in minmacs.sqlite in the support folder.
+ (instancetype)shared;
/// The same table in another file, for tests.
- (instancetype)initWithPath:(NSString *)path;
/// Writes a row. Called by Act through MMGainsRecordAction; tests call it with rows they build.
- (BOOL)add:(NSString *)rid run:(nullable NSString *)run kind:(NSString *)kind part:(nullable NSString *)part
        who:(NSString *)who by:(NSString *)by expert:(NSString *)expert subject:(NSString *)subject
 workstream:(nullable NSString *)workstream at:(NSDate *)at memory:(uint64_t)memory disk:(uint64_t)disk
  diskState:(NSString *)diskState trashed:(nullable NSArray<NSDictionary *> *)trashed items:(NSInteger)items;
/// Restore calls this when a record came back. The row stays, marked undone, and counts nothing.
- (void)takeBack:(NSString *)rid;
/// Rows since a time, newest first, undone rows left out unless asked for. First it drops rows past the 30 days and
/// settles rows in the Trash: each item gone from the Trash and not at its old path makes the row freed.
- (NSArray<MMGain *> *)since:(NSDate *)since undone:(BOOL)undone;
/// The row of one record, or nil.
- (nullable MMGain *)gain:(NSString *)rid;
/// Drops rows older than MMGainsKeepDays before now. Returns how many went.
- (NSInteger)dropOld:(NSDate *)now;
/// The summary `minmacs gains` prints, over days local calendar days that end with now's day, today included:
/// {days, since, now, meaning, today, total, byDay: [{day, start, ...}], byKind: {kind: {...}}, byWho: {...},
///  byWorkstream: {...}, gains: [MMGain json, newest first]}. Each total is {actions, items, memoryBack, diskBack,
/// diskInTrash}. actions counts a run of several as one action. days is cut to 1 to MMGainsKeepDays.
- (NSDictionary *)summary:(NSInteger)days now:(NSDate *)now;
/// The schema version of the table, 1 now. 0 when the file could not be opened.
- (NSInteger)schemaVersion;
@end

/// Act's part. Called by MMRunAction once an action finished, with the finding as it ran and the fresh facts its
/// check read. Writes nothing when the action failed, when it gives nothing back, such as the lid override or a
/// keep-awake hold, or when it was the migration's. Returns the row written, or nil.
MMGain *_Nullable MMGainsRecordAction(id<MMAction> action, MMUndoRecord *record, MMFinding *finding,
                                      uint64_t memoryBefore);
/// The memory back of a stop or a quit: the footprint of each process tree of the finding in the fresh sample,
/// with a pid counted once. Falls back to the finding's cost.ramBytes when the facts have no sample. 0 for any
/// other kind of action.
uint64_t MMGainsMemoryBefore(id<MMAction> action, MMFinding *finding, MMFacts *_Nullable fresh);

NS_ASSUME_NONNULL_END
