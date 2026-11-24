// The log in the middle of the menu window, and `minmacs log`: one plain sentence per thing MinMacs did or decided,
// and per setting that changed, made from the rows of minmacs.sqlite. Core/Store/MMLog.h holds the rows.
//
//   MMLog rows:before:limit: ──► MMWindowLogFrom ──► MMWindowLog ──► the window's middle, on main
//   undo, review, investigate,       off main            plain values
//   setting, keep, quiet and run rows
//
// The window's controller reads it on its own queue, only while the window is open, and again only when
// MMLogStamp moved. Nothing here runs on main, and nothing here acts: an entry says what happened in words.
#import <Foundation/Foundation.h>
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

@class MMLog, MMLogEntry, MMVerbSpec;

/// The tables the log shows, in no order: undo, review, investigate, setting, keep, quiet and run.
NSArray<NSString *> *MMWindowLogTables(void);

/// The entries of these rows, newest first. rows come newest first, as -[MMLog rows:before:limit:] gives them.
/// At most `most` entries, and none older than `maxAge` seconds before now when maxAge is above 0. watchingLeft is
/// how long the first day of watching still runs, MMWatchingLeft, for the note. Pure: the same rows give the same log.
MMWindowLog *MMWindowLogFrom(NSArray<MMLogEntry *> *rows, NSDate *now, NSUInteger most, NSTimeInterval maxAge, NSTimeInterval watchingLeft);

/// Reads the newest rows of the log's tables, a page at a time before the oldest row read, until `most` entries
/// stand, the rows are older than maxAge or there are no more. Never on main in the app.
MMWindowLog *MMWindowLogRead(MMLog *log, NSDate *now, NSUInteger most, NSTimeInterval maxAge);
/// How many times this process read the log for the window or the verb, for the checks.
NSUInteger MMWindowLogReads(void);

/// The log with what the window's own Undo presses changed since it was read, for the controller: an entry whose
/// record in `undoing` is being taken back shows no press and says so, and one whose Undo did not go through says why,
/// from `problems`, rid to what -[MMUndo restore:] answered. The entries of log are never changed: an entry that
/// differs is a new one. Pure, and the same log when nothing differs.
MMWindowLog *MMWindowLogWithUndo(MMWindowLog *log, NSSet<NSString *> *undoing, NSDictionary<NSString *, NSString *> *problems);

/// What the window shows: the newest 300 entries, and none older than 30 days.
extern const NSUInteger MMWindowLogMost;
extern const NSTimeInterval MMWindowLogDays;

/// One entry as `minmacs log --json` prints it.
NSDictionary *MMWindowLogEntryJSON(MMWindowLogEntry *e);

/// `minmacs log [--limit <n>] [--json]`. The shell adds it with MMAddVerb.
MMVerbSpec *MMLogVerbSpec(void);

NS_ASSUME_NONNULL_END
