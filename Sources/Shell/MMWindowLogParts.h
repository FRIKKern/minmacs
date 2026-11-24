// What MMWindowLog.m and MMWindowLogRun.m share: how an entry is made from its row, and the words both use. Not a
// public header: the window, the verb and the checks read MMWindowLog.h.
#import "Shell/MMWindowLog.h"

NS_ASSUME_NONNULL_BEGIN

/// An entry of one row, with its time, day and key.
MMWindowLogEntry *MMWindowLogEntryOf(MMLogEntry *row, NSString *kind, NSString *sentence, NSString *_Nullable who, NSDate *now);
/// Who acted, as the quiet line says it, from the words MMRunAction takes. nil for a who the log does not know.
NSString *_Nullable MMWindowLogWho(NSString *_Nullable by, NSString *_Nullable why);
/// The rule an expert's mode belongs to, "Stop idle servers" for locohost. nil for an expert with no rule.
NSString *_Nullable MMWindowLogRuleTitle(NSString *_Nullable expert);
/// A run row, MMLogRunTable: "Fix Everything: 5 done, 2 skipped. 2 agents ask you.", with each skip and why in more.
MMWindowLogEntry *MMWindowLogRunEntry(MMLogEntry *row, NSDate *now);

NS_ASSUME_NONNULL_END
