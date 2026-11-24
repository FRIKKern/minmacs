// Ask MinMacs, tier 0: a question typed into the window's middle, or given to `minmacs ask`, answered from what
// MinMacs already knows, with no model call. The window's middle shows the answer in place of the log.
//
//   the question ──► MMAskTier0 ──► MMWindowAnswer ──► the window's middle, or `minmacs ask [--json]`
//   the log's rows ──┘    ^            │
//   the window's model ───┘            └──► an `ask` row of the log: {question, kind, answer, answeredBy, by}
//
// It matches words and the names of rows and of what the log acted on. No NLP library, no network, no model:
// tier 1 will plug in where the answer's kind is "unknown". It never acts. A keep or an undo comes back as the
// existing button and verb, and only a person's press on it, or the verb run by whoever asked, does anything.
// Nothing here imports AppKit, and nothing runs on main in the app.
#import <Foundation/Foundation.h>
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

@class MMLog, MMLogEntry, MMSnapshot, MMFinding, MMVerbSpec;

/// The table of asks, one row per ask with its answer: {question, kind, answer, answeredBy, by}. The question stays
/// on this Mac: nothing sends it anywhere.
extern NSString *const MMLogAskTable;                    // @"ask"
/// The longest question taken, in characters. A longer one is cut there.
extern const NSUInteger MMAskMost;                       // 1000

/// What a keep of a row needs: its expert, the key the expert's keeps are given by, its name and the verb that keeps it.
@interface MMAskTarget : NSObject
@property (copy) NSString *expert, *stableKey, *name;
/// The verb that keeps it: "minmacs keep 3000", "minmacs keep <path>".
@property (copy, nullable) NSString *command;
@end

/// A server, a worktree or a cache that can be kept, from its finding. nil for anything else.
MMAskTarget *_Nullable MMAskTargetOf(MMFinding *_Nullable f);
/// How long a keep from an answer lasts, as the expert's own menu keeps it: 4 hours for a server, 7 days otherwise.
NSTimeInterval MMAskKeepFor(NSString *expert);

/// What the answer is made from.
@interface MMAskWorld : NSObject
/// The window's model: its rows and the plan of Fix Everything.
@property (strong) MMWindowModel *model;
/// The log's rows, newest first, as -[MMLog rows:before:limit:] gives them.
@property (copy) NSArray<MMLogEntry *> *rows;
/// Row key to what a keep of it needs. A row with none can still be kept from the window, which asks the snapshot.
@property (copy) NSDictionary<NSString *, MMAskTarget *> *targets;
/// The row whose story shows while the question was asked, for "keep this" and "what is it". nil for none.
@property (copy, nullable) NSString *row;
@property (strong) NSDate *now;
/// The newest rows of the log's tables.
+ (NSArray<MMLogEntry *> *)rowsOf:(MMLog *)log;
/// The keep targets of the model's rows, from the snapshot's findings.
+ (NSDictionary<NSString *, MMAskTarget *> *)targetsOf:(MMWindowModel *)m snapshot:(nullable MMSnapshot *)s;
@end

/// The question as it is asked: one line, trimmed, at most MMAskMost characters. nil when nothing is left.
NSString *_Nullable MMAskQuestion(NSString *_Nullable raw);

/// The answer. Pure: the same question and world give the same answer. It reads nothing and acts on nothing.
MMWindowAnswer *MMAskTier0(NSString *question, MMAskWorld *world);

/// The ask's row in the log, through MMLogWhenOpen. by is "window" or "cli".
void MMAskLog(MMWindowAnswer *answer, NSString *by);

/// The answer as `minmacs ask --json` prints it: {question, kind, answer, answeredBy, entries, suggest, examples, row}.
NSDictionary *MMAskJSON(MMWindowAnswer *answer);

/// `minmacs ask "<question>" [--json]`. The shell adds it with MMAddVerb.
MMVerbSpec *MMAskVerbSpec(void);

/// The server, worktree or cache `minmacs keep` names: a port, ":3000" or "3000", a path, or a cache's name. nil for
/// none. MMKeepCLI.m.
MMFinding *_Nullable MMKeepFind(MMSnapshot *s, NSString *arg);
/// `minmacs keep <port|path|cache name> [--days <n>]`: the keep an answer offers, through MMKeep, in the app.
MMVerbSpec *MMKeepVerbSpec(void);

NS_ASSUME_NONNULL_END
