// Today's record per workstream, for the lanes of the sheet (Sources/Core/MMSheet.h).
// The graph queue hands each new snapshot to -record:. The log keeps one row per change of state, never one per
// tick: an agent that works for an hour is one row. It lives in MMLog's database, table day, and keeps 8 days.
#import <Foundation/Foundation.h>
#import "Core/MMSheet.h"

NS_ASSUME_NONNULL_BEGIN

@class MMSnapshot;

@interface MMDayLog : NSObject
+ (instancetype)shared;
/// Graph queue. Compares each workstream's agent state, servers and git with the last record and writes a row
/// only for what changed: working, idle, waiting for you, finished, a server busy or idle, a PR opened or merged.
- (void)record:(MMSnapshot *)snapshot;
/// The stretches of one workstream since a time, oldest first, the last one open. Any queue but main.
- (NSArray<MMLaneSpan *> *)spansFor:(NSString *)workstreamKey since:(NSDate *)since;
- (NSArray<MMServerSpan *> *)serverSpansFor:(NSString *)workstreamKey since:(NSDate *)since;
- (NSArray<MMLaneMark *> *)marksFor:(NSString *)workstreamKey since:(NSDate *)since;
/// When the workstream was first seen ready to wrap up, or nil.
- (nullable NSDate *)readySince:(NSString *)workstreamKey;
@end

NS_ASSUME_NONNULL_END
