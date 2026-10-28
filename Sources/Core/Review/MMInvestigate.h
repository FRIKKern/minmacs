// Investigate: one deeper agent run, only when the person asks, about one finding or one workstream.
// PLAN.md section 4 item 5 and research F9: a custom system prompt and only Read, Grep and Glob, scoped to the
// subject's folders. Issue #35.
// Claude Code's own Read tool opens any path it is given, whatever folder the call runs in. So Investigate turns every
// built-in tool off and serves its own Read, Grep and Glob from this binary over MCP, `minmacs _investigate-tools`.
// Each tool resolves symlinks and .. with realpath before it checks the path, refuses anything outside the folders,
// and checks the opened file again through F_GETPATH. Walks never follow a symlink.
// The cost is shown before a run, as an estimate in tokens and the model, and the person confirms it.
// The answer is saved to the log with the subject's id, and cards read it from memory, never from disk on main.
#import <Foundation/Foundation.h>
#import "Core/Graph/MMGraph.h"
#import "Core/Review/MMReview.h"

/// The model Investigate asks. It needs tools, so only Claude can run it, and the codex fallback does not apply.
extern NSString *const MMInvestigateModel;             // @"haiku"
/// The turn limit passed to claude as --max-turns, so one run cannot read without end.
extern const NSInteger MMInvestigateMaxTurns;           // 12
/// The estimate before any run has been measured: research F 4.4 found first turns that write 3k to 35k tokens.
extern const NSInteger MMInvestigateDefaultEstimate;   // 35,000 uncached tokens

/// The real path of path when it lies inside one of folders, or nil with *reason. A relative path starts at the
/// first folder, and ~ is the home folder. Symlinks and .. are resolved with realpath before the check, so a link
/// inside a folder that points out is refused. A path that does not exist is refused. folders must be real paths.
NSString *MMInvestigateScoped(NSArray<NSString *> *folders, NSString *path, NSString **reason);

/// The folders a run may read for a list of candidates: each one resolved with realpath, a file replaced by its
/// folder, and one inside another dropped. The root, the home folder and any folder above it are dropped,
/// so a run never reads the whole disk or the whole home folder.
NSArray<NSString *> *MMInvestigateFolders(NSArray<NSString *> *candidates);

/// One saved Investigate run, or one that is running now.
@interface MMInvestigation : NSObject
@property (copy) NSString *subjectID;                   // a findingID, a workstream's ownerID or "folder:<path>"
@property (copy) NSString *title, *question;
@property (copy) NSString *answer, *error;              // one of the two is set once the run ends
@property (copy) NSString *model;
@property (copy) NSArray<NSString *> *folders;
@property MMUsage *usage;
@property NSDate *at;                                   // when it started
@property NSInteger toolCalls, refused;                 // the tool server's own count, read from its audit file
@property NSInteger bytesRead;                          // what the tools handed the model
@property BOOL running;
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

/// What a run will likely cost, shown before it runs.
@interface MMInvestigateEstimate : NSObject
@property (copy) NSString *model;                       // "haiku"
@property NSInteger tokens;                             // uncached tokens: the median of the last five runs, or the default
@property NSInteger basedOn;                            // how many past runs the median uses, 0 for the default
/// "About 35,000 tokens on Haiku, an estimate before the first run." in sentence case.
- (NSString *)sentence;
- (NSDictionary *)json;
@end

/// One subject to investigate, from a finding, a workstream or a folder.
@interface MMInvestigateSubject : NSObject
@property (copy) NSString *subjectID, *title, *expert;
@property (copy) NSArray<NSString *> *folders;          // from MMInvestigateFolders, never empty for a usable subject
@property (copy) NSString *question;                    // the default question for this kind of subject
/// The finding's own folder, its owner's and its workstream's worktree. nil when none is a folder it may read.
+ (instancetype)finding:(MMFinding *)f snapshot:(MMSnapshot *)s;
+ (instancetype)workstream:(MMWorkstream *)w;
+ (instancetype)folder:(NSString *)path;
/// A findingID, a workstream's ownerID or a path, resolved against s. A path names the finding at that path first,
/// then the workstream that holds it, then the folder itself. nil when nothing matches.
+ (instancetype)named:(NSString *)name snapshot:(MMSnapshot *)s cwd:(NSString *)cwd;
@end

/// The saved runs and the one running per subject. Every read answers from memory, so menus and cards may call
/// it on main. The log is read once, off main, when the broker starts, or on the first read off main.
@interface MMInvestigations : NSObject
+ (instancetype)shared;
/// The newest run for subjectID, running or done, or nil.
- (MMInvestigation *)latestFor:(NSString *)subjectID;
- (MMInvestigateEstimate *)estimate;
/// Reads the log into memory. Blocks. Never on main. The broker calls it once on the review queue.
- (void)load;
/// Runs one Investigate now, saves it and returns it. Blocks. Never on main. question nil asks the default.
/// It counts against MMBudget as "investigate". A second run for a subject that is running returns nil with *error.
- (MMInvestigation *)run:(MMInvestigateSubject *)subject question:(NSString *)question error:(NSString **)error;
/// The same on MMQueue(@"core", @"investigate"), one run at a time. done runs on main. The subject is marked as
/// running before the run queues, so a second start for it, while one waits or runs, calls done with nil and an error.
/// The graph is asked to rebuild when the run queues and when it ends, so the card shows it.
- (void)start:(MMInvestigateSubject *)subject question:(NSString *)question done:(void (^)(MMInvestigation *run, NSString *error))done;
/// Resolves the subject of a finding or workstream id and the estimate on MMQueue(@"core", @"investigate-prepare"),
/// since both read the disk, and calls done on main with them. That queue never waits on a run. subject is nil when it has no folder to look in.
- (void)prepare:(NSString *)subjectID snapshot:(MMSnapshot *)s
           done:(void (^)(MMInvestigateSubject *subject, MMInvestigateEstimate *estimate))done;
/// The card action's flow. Resolves the subject and the estimate off main, then calls confirm on main with a title,
/// the cost and the model in words, and the default question. confirm returns the question, empty for the default,
/// or nil to cancel. Only a confirmed run starts. failed runs on main when nothing can be read or the run fails.
- (void)ask:(NSString *)subjectID snapshot:(MMSnapshot *)s
    confirm:(NSString *(^)(NSString *title, NSString *text, NSString *placeholder))confirm
     failed:(void (^)(NSString *error))failed;
/// The cost sentence and the folders, as the confirm alert and the CLI say them.
- (NSString *)costText:(MMInvestigateSubject *)subject estimate:(MMInvestigateEstimate *)estimate;
/// Puts a run in memory without a model call, for the render tool and the checks.
- (void)remember:(MMInvestigation *)run;
@end

/// The tool server that `minmacs _investigate-tools --folder <path>... [--audit <file>]` runs, MCP over stdio.
/// It reads JSON-RPC lines from readLine until it returns nil, and writes each reply through write.
/// It serves Read, Grep and Glob scoped to folders, which must be real paths, and nothing else.
/// Each call appends one JSON line to audit: the tool, the path, ok or the refusal, and the bytes returned.
/// Returns 0 at end of input.
typedef NSString *(^MMInvestigateReadLine)(void);       // the next line of input, nil at the end
typedef void (^MMInvestigateWriteLine)(NSString *line);  // one line of output
int MMInvestigateServeTools(NSArray<NSString *> *folders, NSString *audit, MMInvestigateReadLine readLine, MMInvestigateWriteLine write);
