// Quiet: peace for one task, such as a screen recording or a run of screenshots, D9 part 3.
// While a held process lives, no expert acts on its own, and the Mac and its display stay awake.
//
//   quiet hold <pid> ──► MMQuietHold ──► MMRunAction (kind "quiet": the pid checked fresh by its start time, the record first)
//                                          └─► <support>/quiet/holds.json, and in this process two assertions and an exit watch
//   any process ──► MMQuietWhy ◄── holds.json, each pid checked alive by its start time
//                     ├─► MMPlan: an entry that would act is kept
//                     └─► MMRunAction: a mode's run ("proactive", "eager") is refused
//   pid exits / quiet release ──► the entry leaves holds.json, a row of the log's quiet table, and the assertions end
//
// The holds live in a file so that every MinMacs process obeys them, the app and a cold `locohost auto` alike. Only
// the process that took a hold holds its assertions: the app, which `quiet hold` needs. A release from any process
// edits the file, and the keeper sees the change through a kqueue watch on the folder, so nothing polls.
// Nothing here signals a process. Each hold is PreventUserIdleSystemSleep and PreventUserIdleDisplaySleep, as
// `caffeinate -i -d -w <pid>` takes them, through IOKit, never pmset.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"

/// The log's table of quiet holds that ended: {holdRid, pid, process, reason, since, until, how, by}.
/// how is "released", "exited" or "gone" for a hold whose process ended while no MinMacs kept it. until is null
/// for "gone", since nobody saw the end. The start is the undo record of kind "quiet", holdRid.
extern NSString *const MMLogQuietTable;                // @"quiet"

/// One quiet hold, as holds.json keeps it.
@interface MMQuietHolder : NSObject
@property (readonly) MMProcKey key;                    // the held process
@property (readonly, copy) NSString *reason, *by, *rid;   // rid: the undo record of kind "quiet" that began it
@property (readonly) NSDate *since;
@property (readonly) MMProcKey keeper;                 // the MinMacs process that holds its assertions
/// YES while the keeper runs, so the Mac and the display are held awake. NO when that MinMacs quit: the peace is
/// still kept by every MinMacs process, but nothing holds the Mac awake until the app takes it over at its start.
@property (readonly) BOOL awake;
/// {pid, reason, since, by, rid, awake}: since in seconds since 1970.
- (NSDictionary *)json;
@end

/// The holds whose process still runs, by its start time, oldest first. Reads holds.json again only when it changed.
/// Safe from any queue; never blocks on another process.
NSArray<MMQuietHolder *> *MMQuietHolders(void);
/// nil when no quiet hold is active, else "a quiet hold is active for <reason> (pid N)", naming the oldest and how
/// many more. MMPlan and MMRunAction read it.
NSString *MMQuietWhy(void);

/// Takes a quiet hold for the process with this pid, checked by its start time from the kernel now, through
/// MMRunAction. Never pid 1 or MinMacs itself. Blocks; never on main. by is "cli" or "manual".
/// Returns nil and the record's rid, or why it did not hold. A pid already held keeps its first hold and reason.
NSString *MMQuietHold(pid_t pid, NSString *reason, NSString *by, NSString **rid);
/// Ends every quiet hold of this pid, whatever its start time, and writes a row of the quiet table for each.
/// Returns how many ended. Any process may release: the keeper's watch drops its assertions.
NSUInteger MMQuietRelease(pid_t pid, NSString *by);
/// At the app's start: takes over each hold in holds.json whose process still runs, with this process as its keeper,
/// and ends with a row of kind "gone" each one whose process ended while no MinMacs kept it. MMCoreStart calls it.
void MMQuietResume(void);
/// The holds this process keeps assertions for now, as MMProcKeyString to the reason.
NSDictionary<NSString *, NSString *> *MMQuietKept(void);
