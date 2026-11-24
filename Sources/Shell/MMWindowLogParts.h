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

/// Failed records folded so far into one entry, MMWindowLogFold.m.
@class MMWindowLogFold;
/// Identical failures one after another, as a run gives when each thing fails the same way, are one entry: "Could not
/// move 169 groups to the Trash. MinMacs could not write its own list of what it sends to the Trash, so they stay
/// where they are." e is the entry of a failed record's row, read newest first, and last the entry the list ends on.
/// YES when e went into the fold that last is, which then says them all: e is then not listed. NO when e starts a
/// fold of its own, *fold, and is listed. The same kind, the same words why, the same who and the same day fold, and
/// any entry between ends a fold.
BOOL MMWindowLogFoldFailed(MMWindowLogFold *_Nullable *_Nonnull fold, MMWindowLogEntry *e, MMLogEntry *row, NSString *day,
                           MMWindowLogEntry *_Nullable last);

NS_ASSUME_NONNULL_END
