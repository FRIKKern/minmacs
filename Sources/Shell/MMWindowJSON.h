// The window's model as JSON, for `minmacs window --json` and the checks. Sources/UI/Window/MMWindowModel.h holds the
// classes; they stay plain values there, and the printing lives here with the feed.
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// "server", "agent", "app", "helper", "tabs", "worktree" or "cache".
NSString *MMWindowKindName(MMWindowKind kind);

@interface MMWindowHour (MMJSON)
- (NSDictionary *)json;        // {title, explain, side, values}
@end
@interface MMWindowFact (MMJSON)
- (NSDictionary *)json;        // {label, value}
@end
@interface MMWindowRow (MMJSON)
- (NSDictionary *)json;        // {key, kind, iconHint, name, state, cpuPercent, bytes, tabs, needsYou, inFix, hour, facts}
@end
@interface MMWindowGroup (MMJSON)
- (NSDictionary *)json;        // {key, title, side, rows}
@end
@interface MMWindowRing (MMJSON)
- (NSDictionary *)json;        // {memory: {used, total, slices}, disk: {free, total, slices}}
@end
@interface MMWindowFix (MMJSON)
- (NSDictionary *)json;        // {key, title, memoryBack, diskBack, needsYou}
@end
@interface MMWindowRun (MMJSON)
- (NSDictionary *)json;        // {running, step, done, total, memoryBack, diskBack, memoryPlanned, diskPlanned, endTitle, endNote}
@end
@interface MMWindowSettings (MMJSON)
- (NSDictionary *)json;        // {rules: [{ruleID, title, choices, picked, note}], switches: [{switchID, title, on, note}]}
@end
@interface MMWindowModel (MMJSON)
/// {generation, asks, memoryHour, diskHour, memory, disk, ring, fixes, fixEverything, run, settings}.
/// Memory and disk are apart in every part of it, and no value is a sum of the two.
- (NSDictionary *)json;
@end

NS_ASSUME_NONNULL_END
