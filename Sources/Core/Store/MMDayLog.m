// Stub of MMDayLog.h, so the contract links. The sheet wave fills it in on MMLog's table day.
#import "Core/Store/MMDayLog.h"

@implementation MMDayLog
+ (instancetype)shared { static MMDayLog *d; static dispatch_once_t once; dispatch_once(&once, ^{ d = [MMDayLog new]; }); return d; }
- (void)record:(MMSnapshot *)snapshot {}
- (NSArray<MMLaneSpan *> *)spansFor:(NSString *)workstreamKey since:(NSDate *)since { return @[]; }
- (NSArray<MMServerSpan *> *)serverSpansFor:(NSString *)workstreamKey since:(NSDate *)since { return @[]; }
- (NSArray<MMLaneMark *> *)marksFor:(NSString *)workstreamKey since:(NSDate *)since { return @[]; }
- (NSDate *)readySince:(NSString *)workstreamKey { return nil; }
@end
