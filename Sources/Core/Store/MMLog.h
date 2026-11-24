// The SQLite log: undo, restore, review history and trends. Pattern P38 of SYNTHESIS.md section 1.5, and decision 5.
// One file, <support folder>/minmacs.sqlite, in WAL mode with a busy timeout,
// so the app and the CLI write to it safely at the same time. macOS ships libsqlite3, and build.sh links it.
#import <Foundation/Foundation.h>

/// P38. One row of the log. Rows are never changed. A new state is a new row with the same rid.
@interface MMLogEntry : NSObject
@property (readonly) int64_t row;                       // SQLite rowid, in write order
@property (readonly, copy) NSString *rid;               // the record id that ties a record's rows together
@property (readonly, copy) NSString *table;             // "undo", "review", "verdict", "usage"
@property (readonly, copy) NSString *expert, *subject, *state;
@property (readonly) NSDate *at;
@property (readonly) NSDictionary *body;                // the record as JSON
@end

/// One point of a trend, such as a folder's size once a day.
typedef struct { NSTimeInterval at; double value; } MMTrendPoint;

/// P38. The append-only log. Starts from NN's audit JSONL, audit.go:44, kept in SQLite instead, per decision 5.
/// Every method is safe from any queue and from the CLI while the app runs.
@interface MMLog : NSObject
/// The log in the support folder. Opening it may wait up to 15 seconds for another process's lock.
/// After MMLogOpenOffMain, on the main thread it never opens the log: it returns it once it is open, else nil.
+ (instancetype)shared;
/// The same log at another path, for tests and for the CLI's --home.
- (instancetype)initWithPath:(NSString *)path;
/// Appends a row and returns it. rid nil makes a new one.
- (MMLogEntry *)append:(NSString *)table rid:(NSString *)rid expert:(NSString *)expert subject:(NSString *)subject
                 state:(NSString *)state body:(NSDictionary *)body;
/// The newest row of each rid, newest first. expert or subject nil means all; since nil means no limit in time.
- (NSArray<MMLogEntry *> *)latest:(NSString *)table expert:(NSString *)expert subject:(NSString *)subject
                            since:(NSDate *)since limit:(NSUInteger)limit;
/// Every row of one record, oldest first, such as an undo record from pending to done to restored.
- (NSArray<MMLogEntry *> *)history:(NSString *)rid;
/// The newest rows of these tables that came before row `before`, newest first, at most `limit`. `before` 0 means
/// from the newest row. One range read of the (tbl, row) index per table, each of `limit` rows at most, so what it
/// costs does not grow with the log, unlike -latest:, which groups the whole table. The menu window's log and
/// `minmacs log` read through this.
- (NSArray<MMLogEntry *> *)rows:(NSArray<NSString *> *)tables before:(int64_t)before limit:(NSUInteger)limit;
/// Trends, such as "noonoo.disk.~/Library/Caches". Points sit in their own table, outside the append-only rows.
/// One point per bucket is kept, and a newer value in the same bucket replaces it.
- (void)addPoint:(NSString *)series value:(double)value at:(NSDate *)at bucket:(NSTimeInterval)bucket;
- (NSData *)points:(NSString *)series since:(NSDate *)since;   // packed MMTrendPoint values, oldest first
/// Deletes the points of one series older than `before`, and returns how many went. Only the rows table is
/// append-only: points are a trend's working set, and a series that keeps a few days prunes what is past them.
- (NSUInteger)prunePoints:(NSString *)series before:(NSDate *)before;
@end

/// Opens the shared log on its own queue now, and from then on +shared on main never opens it.
/// MMCoreStart calls this first. A CLI run never does, so its main thread opens the log when it needs it.
void MMLogOpenOffMain(void);
/// Runs work with the shared log: at once off main or in a CLI, or on the queue that opens it when the app calls
/// it on main.
/// For work that must reach the log from main, such as the legacy import at launch.
typedef void (^MMLogWork)(MMLog *log);
void MMLogWhenOpen(MMLogWork work);
/// How many logs this process opened on the main thread. The app holds this to zero.
NSUInteger MMLogMainThreadOpens(void);

/// How many rows this process wrote on the main thread, while MMLogOpenOffMain holds. The app holds this to zero:
/// a write from main goes through MMLogWhenOpen.
NSUInteger MMLogMainThreadWrites(void);

#pragma mark Settings and keeps

/// The table of setting changes, one row per change: {key, old, new, by}. Append-only, as every row.
extern NSString *const MMLogSettingTable;               // @"setting"
/// The table of keeps, one row per keep given or ended: {key, name, until, by}.
extern NSString *const MMLogKeepTable;                  // @"keep"
/// The one writer of a setting row. key is the pref, such as "locohost.mode", or "core.login" for the login item.
/// old and now are plain values, nil for none. by says who: "window", "settings", "cli", "migration", "welcome".
/// A change to the same value writes nothing. Safe from any queue: from main in the app the write goes to the log's
/// own queue, MMLogWhenOpen, so main never touches SQLite.
void MMLogSetting(NSString *key, id old, id now, NSString *by);
/// MMSetPref, and its row through MMLogSetting with the value it held before.
void MMSetSetting(NSString *key, id value, NSString *by);

#pragma mark Runs

/// The table of runs, one row per Fix Everything run and per automatic mode pass that planned anything:
/// {what, by, planned, done, skipped: [{subject, why, as}], gains: {memory, disk}}. Append-only, as every row.
extern NSString *const MMLogRunTable;                   // @"run"
/// What a run is: "fix-everything", or the expert whose mode pass it was, such as "locohost".
extern NSString *const MMLogRunFixEverything;           // @"fix-everything"
/// One thing a run planned and did not do. subject names it as the window does, why says why in plain words, and
/// as is one of "asks" (an agent asks the person), "press" (it waits for the person's own press), "kept" (MustKeep
/// held it on fresh facts), "blocked" (it could not start), "failed" or "stopped" (the run was stopped before it).
NSDictionary *MMLogRunSkip(NSString *subject, NSString *why, NSString *as);
/// The one writer of a run row. planned and done count things, a Wrap Up as one. by is the words MMRunAction takes:
/// "manual" for Fix Everything, the mode's name for a mode pass. Memory and disk back are two numbers. Safe from any
/// queue: from main in the app the write goes to the log's own queue.
void MMLogRun(NSString *what, NSString *by, NSInteger planned, NSInteger done, NSArray<NSDictionary *> *skipped, uint64_t memoryBack, uint64_t diskBack);

/// How many queries this process ran on the main thread. A menu reads what the graph already holds, so the checks
/// hold menus and cards to zero.
NSUInteger MMLogMainThreadQueries(void);
/// Issue #52. A short string that changes whenever any process writes to the shared log: the size and change time
/// of minmacs.sqlite and its WAL file. Two stats and no query, so a rebuild can keep what it read until this moves.
NSString *MMLogStamp(void);
