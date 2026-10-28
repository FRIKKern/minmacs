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
/// Trends, such as "noonoo.disk.~/Library/Caches". Points sit in their own table, outside the append-only rows.
/// One point per bucket is kept, and a newer value in the same bucket replaces it.
- (void)addPoint:(NSString *)series value:(double)value at:(NSDate *)at bucket:(NSTimeInterval)bucket;
- (NSData *)points:(NSString *)series since:(NSDate *)since;   // packed MMTrendPoint values, oldest first
@end

/// How many queries this process ran on the main thread. A menu reads what the graph already holds, so the checks
/// hold menus and cards to zero.
NSUInteger MMLogMainThreadQueries(void);
/// Issue #52. A short string that changes whenever any process writes to the shared log: the size and change time
/// of minmacs.sqlite and its WAL file. Two stats and no query, so a rebuild can keep what it read until this moves.
NSString *MMLogStamp(void);
