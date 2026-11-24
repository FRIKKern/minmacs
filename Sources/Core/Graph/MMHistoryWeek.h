// The last 7 days of the whole Mac, one point an hour, for the window's strip and `minmacs history --days 7`.
// Nothing samples here. MMHistory hands over each hour that ended, onHour, as the mean of the minutes the graph builds
// filled in it, and this file writes it to the log's points table, off main, on its own queue: one INSERT OR REPLACE
// per series an hour, bucketed by the hour, so a second hand-over of one hour replaces the first. Each write prunes the
// points older than MMHistoryWeekKeepDays, so each series holds at most 8 x 24 points. The points outlive a restart.
// An hour the Mac was off or asleep for, or MinMacs was not running, has no point, and a reader shows a gap there.
#import <Foundation/Foundation.h>
#import "Core/Graph/MMHistory.h"
#import "Core/Store/MMLog.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const MMHistoryWeekMemory;             // @"core.memory.used", bytes
extern NSString *const MMHistoryWeekDisk;               // @"core.disk.free", bytes
enum { MMHistoryWeekDays = 7, MMHistoryWeekKeepDays = 8 };

/// MMCoreStart calls this: the shared store's onHour writes to the shared log. MMCoreStop calls the stop.
void MMHistoryWeekStart(void);
void MMHistoryWeekStop(void);
/// The hand-over that writes to `log`, or to MMLog.shared when nil, on the queue no.guerrilla.minmacs.core.history.week.
MMHistoryHourDone MMHistoryWeekKeeper(MMLog *_Nullable log);
/// One hour's write as the keeper runs it: a point for each side that has a value, then the prune of both series.
void MMHistoryWeekWrite(MMLog *log, NSTimeInterval hourStart, double memoryUsed, double diskFree, NSTimeInterval now);
/// One series over the last `days` days: days x 24 values, NSNumber bytes or NSNull, oldest first. The last is the hour
/// before the one `now` is in, the newest that can have ended. firstAt gets the start of the first hour.
NSArray *MMHistoryWeekHours(MMLog *log, NSString *series, NSTimeInterval now, NSInteger days, NSTimeInterval *_Nullable firstAt);
/// What `minmacs history --days <n> --json` prints: {days, hours, stepSeconds, keepDays, from, to, memoryUsedMB,
/// diskFreeMB, held: {memory, disk}, points: [{at, memoryUsedMB, diskFreeMB}]}. The two arrays hold one value an
/// hour, null where none was kept. points lists only the hours that hold one.
NSDictionary *MMHistoryWeekJSON(MMLog *log, NSTimeInterval now, NSInteger days);
/// For the checks and for a reader's cache: the hours this process wrote, and how many of them on main, which stays
/// zero; and how many times this process read the points.
NSUInteger MMHistoryWeekWrites(void);
NSUInteger MMHistoryWeekMainWrites(void);
NSUInteger MMHistoryWeekReads(void);

NS_ASSUME_NONNULL_END
