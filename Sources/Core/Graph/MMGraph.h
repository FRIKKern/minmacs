// The graph: one immutable snapshot of every finding and its owner, made by one builder.
// Patterns P31 to P33 of SYNTHESIS.md section 1.4, plus the finding and owner types every expert shares.
// The builder runs on MMQueue(@"core", @"graph"). Main is the only writer of -current, so menus read without locks.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"
#import "Core/Know/MMRegistry.h"
#import "Core/Know/MMSessions.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMClutter.h"

@class MMReview;
@protocol MMExpert;

/// The kinds of owner a finding can have.
typedef NS_ENUM(NSInteger, MMOwnerKind) {
    MMOwnerWorkstream,   // one session with its worktree, servers, processes and caches, P32
    MMOwnerSession,      // an agent session with no worktree of its own
    MMOwnerWorktree,     // a checkout with no live session
    MMOwnerProject,      // a folder that is not a git checkout, or a clutter back-link of P29
    MMOwnerApp,          // a running app, through the responsible pid of P9
};

/// Who a finding belongs to. An owner links one expert's finding to another's, such as a server to its worktree.
/// New code. Owners compare by kind and key.
@interface MMOwner : NSObject <NSCopying>
@property (readonly) MMOwnerKind kind;
@property (readonly, copy) NSString *key;               // a path, a session id or a bundle id
@property (readonly, copy) NSString *name;              // short, for a row's owner fact
@property (readonly, copy) NSString *path;              // nil for an app
@property (readonly) MMOwner *parent;                   // a worktree's workstream, nil at the top
+ (instancetype)kind:(MMOwnerKind)kind key:(NSString *)key name:(NSString *)name path:(NSString *)path parent:(MMOwner *)parent;
/// "workstream:/path/to/tree", the kind and key in one string. Stable across restarts of the session.
- (NSString *)ownerID;
/// YES when other is this owner or one of its parents.
- (BOOL)isWithin:(MMOwner *)other;
@end

/// What a finding costs right now. A field that does not apply is 0, or -1 for cpuPercent.
typedef struct {
    uint64_t ramBytes;           // footprint of the finding's processes
    double cpuPercent;           // 100 is one core
    double energyRank;           // 0 to 1, never joules or watts
    uint64_t diskFreed;          // what removing it frees, the Sizer's freedIfDeleted
    uint64_t diskAllocated;      // what du says, shown only beside diskFreed
} MMCost;

/// One fact that backs a finding, such as "last request 3h ago". The review reads these, and cards show them.
@interface MMEvidence : NSObject
@property (readonly, copy) NSString *label, *value;     // "Last request", "3h ago"
@property (readonly) id raw;                            // the fact as a number, date or string, for --json and the review
@property (readonly, copy) NSString *linkExpert, *linkFindingID;   // set when the fact belongs to another expert's finding
+ (instancetype)label:(NSString *)label value:(NSString *)value raw:(id)raw;
+ (instancetype)label:(NSString *)label value:(NSString *)value raw:(id)raw
           linkExpert:(NSString *)expert findingID:(NSString *)findingID;
@end

/// How an action on a finding is undone. Principle 5: an action without a way back is never proposed.
typedef NS_ENUM(NSInteger, MMReversibility) {
    MMReversibleNotNeeded,   // nothing is lost, such as keep-awake or a server that restarts on demand
    MMReversibleRestart,     // the undo record holds the command, cwd and env to start it again
    MMReversibleTrash,       // the item goes to the Trash, and restore moves it back
    MMReversibleBundle,      // a worktree with a git bundle and saved files, restored at its commit
    MMReversibleToolCommand, // the tool's own cleanup command; its dry-run output is the record
    MMReversibleRelaunch,    // an app is quit and reopened with its saved state
};

/// What the expert proposes to do with a finding. A proposal is data. Act turns it into an MMAction.
@interface MMProposal : NSObject
@property (readonly, copy) NSString *verb;              // the expert's own word: "stop", "remove", "clean", "quit"
@property (readonly, copy) NSString *title;             // the menu title, such as "Stop Server"
@property (readonly) MMReversibility reversibility;
@property (readonly) BOOL needsForce;                   // a second request, such as SIGKILL after SIGTERM
+ (instancetype)verb:(NSString *)verb title:(NSString *)title reversibility:(MMReversibility)r;
+ (instancetype)verb:(NSString *)verb title:(NSString *)title reversibility:(MMReversibility)r needsForce:(BOOL)force;
@end

/// What an expert fills in to make one finding. The finding copies every field, so a later change here
/// never reaches it. An owner set here is only a hint: the graph picks the owner, see MMGraph.
@interface MMFindingBuilder : NSObject
@property (copy) NSString *instanceKey, *title, *path, *fingerprint;
/// A back-link path, such as a clutter item's ownerPath. The graph checks it before path.
@property (copy) NSString *ownerPath;
@property (strong) MMOwner *owner;
@property MMCost cost;
@property (copy) NSArray<MMEvidence *> *evidence;
@property (copy) NSArray<NSString *> *keepReasons;
@property (strong) MMProposal *proposal;
@property (copy) NSArray<NSValue *> *procs;
@property (copy) NSDictionary *facts;
@end

/// One thing an expert found: a server, a worktree, an app, a cache, a keep-awake need.
/// New code. It replaces each app's own subject type: LHHost, WFTree, MMAgent rows in 1.2 and NN's findings.
/// Immutable. A new snapshot makes new findings, and the id stays the same across snapshots.
@interface MMFinding : NSObject
/// expert:kind:stableKey, such as "locohost:server:~/code/app#dev". Stable across restarts of the subject,
/// so keeps and verdicts survive. Decision 8 sets the server key to project folder and script.
@property (readonly, copy) NSString *findingID;
@property (readonly, copy) NSString *expert, *kind, *stableKey;
/// The key of this exact instance, such as pid:start for a process. It changes when the subject restarts.
@property (readonly, copy) NSString *instanceKey;
@property (readonly, copy) NSString *title;
@property (readonly) MMOwner *owner;
@property (readonly) MMCost cost;
@property (readonly) NSArray<MMEvidence *> *evidence;
/// Work keeps on fresh facts, such as "3 uncommitted files" or "an agent works here". Empty when free to decide.
/// "Cannot verify" is a keep reason too.
@property (readonly) NSArray<NSString *> *keepReasons;
@property (readonly) MMProposal *proposal;              // nil when nothing would be done to it
@property (readonly) NSArray<NSValue *> *procs;         // MMProcKey values of its processes, for exits and stop
@property (readonly, copy) NSString *path;              // the folder or file it is about, nil for a process only
/// The review fingerprint: what must change for the model to look again. Facts, activity bucket and size bucket.
@property (readonly, copy) NSString *fingerprint;
@property (readonly) NSDictionary *facts;               // expert-specific facts for --json and the review
@property (readonly) BOOL kept;                         // YES when keepReasons is not empty
@property (readonly, copy) NSString *ownerPath;         // the back-link the expert gave, or nil
/// The one way to make a finding. stableKey must not hold a pid or a start time.
+ (instancetype)expert:(NSString *)expert kind:(NSString *)kind stableKey:(NSString *)stableKey
                 build:(void (^)(MMFindingBuilder *b))build;
/// A copy with the owner the graph picked. The rest stays the same.
- (instancetype)withOwner:(MMOwner *)owner;
@end

/// The builder's input for one snapshot: every fact Core gathered for this generation. Immutable.
/// Experts read only this, so no expert samples, scans or asks the model on its own.
@interface MMFacts : NSObject
@property (readonly) uint64_t generation;
@property (readonly) MMSample *sample;
@property (readonly) MMPower *power;
@property (readonly) NSArray<MMAgent *> *agents;
@property (readonly) NSArray<MMSession *> *sessions;
@property (readonly) NSArray<MMWorktree *> *worktrees;
@property (readonly) NSArray<MMClutterItem *> *clutter;
- (MMGitFacts *)gitFor:(MMWorktree *)w;                 // cached facts, nil until the first scan ends
/// The one way to make facts. Every array is copied. git maps a worktree path to its facts.
/// Tests build facts by hand with this, so the graph needs no Senses or Know code to run.
+ (instancetype)generation:(uint64_t)generation sample:(MMSample *)sample power:(MMPower *)power
                    agents:(NSArray<MMAgent *> *)agents sessions:(NSArray<MMSession *> *)sessions
                 worktrees:(NSArray<MMWorktree *> *)worktrees clutter:(NSArray<MMClutterItem *> *)clutter
                       git:(NSDictionary<NSString *, MMGitFacts *> *)git;
@end

/// Where the builder gets its facts. The app sets one source that reads Senses and Know.
/// Tests set a source that returns facts built by hand.
@protocol MMFactSource <NSObject>
/// Facts for one rebuild. Runs on the graph queue.
- (MMFacts *)factsFor:(uint64_t)generation;
/// Facts read now for one finding, for -freshFactsFor:. Blocks. Never on main.
- (MMFacts *)freshFactsFor:(MMFinding *)finding;
@end

/// P32. A workstream: one session with its worktree, servers, processes, caches and keep-awake need.
/// New code, from PLAN.md section 3 and research track F section 5.
@interface MMWorkstream : NSObject
@property (readonly) MMOwner *owner;                    // kind MMOwnerWorkstream
@property (readonly) MMSession *session;
@property (readonly) MMAgent *agent;                    // the agent running the session now, or nil
@property (readonly) MMAgentState agentState;
@property (readonly) MMWorktree *worktree;
@property (readonly) MMGitFacts *git;
@property (readonly) NSArray<MMFinding *> *findings;    // from every expert, owned by this workstream or below
@property (readonly) NSArray<MMClutterItem *> *clutter;
/// HEAD, an activity bucket and a size bucket. The review skips a workstream whose fingerprint did not move.
- (NSString *)fingerprint;
@end

/// P31. One immutable snapshot with a generation number. Safe to read from any queue.
/// New code. It removes the @synchronized (self) that WF shares between scan workers and main, WF Trees.m:634-636.
@interface MMSnapshot : NSObject
@property (readonly) uint64_t generation;
@property (readonly) NSDate *builtAt;
@property (readonly) MMFacts *facts;
@property (readonly) NSArray<MMWorkstream *> *workstreams;
@property (readonly) NSArray<MMFinding *> *findings;
- (NSArray<MMFinding *> *)findingsFor:(NSString *)expert;
- (MMFinding *)finding:(NSString *)findingID;
/// P33. Reads that replace calls between apps.
/// They replace WF's `locohost list --json` spawn in LocoHosts, WF Trees.m:396, and IN's MinMacsWorking, IN main.m:165.
- (MMWorkstream *)workstreamAt:(NSString *)path;        // the workstream whose worktree holds path
- (NSArray<MMFinding *> *)findingsOwnedBy:(MMOwner *)owner expert:(NSString *)expert;   // expert nil means all
- (NSInteger)workingAgents;
- (MMReview *)reviewFor:(NSString *)expert;             // the last saved review, nil before the first
/// P33. The pids Insomnia holds the Mac awake for, as "pid:start" to the reason. A pid that exited is gone.
@property (readonly) NSDictionary<NSString *, NSString *> *awakeHolds;
/// Builds one snapshot from facts, on the calling thread. The graph queue calls it on every rebuild.
/// Pure: the same facts and experts give the same snapshot, owners included. reviews and holds may be nil.
+ (MMSnapshot *)snapshotFrom:(MMFacts *)facts experts:(NSArray<id<MMExpert>> *)experts
                     reviews:(NSDictionary<NSString *, MMReview *> *)reviews holds:(NSDictionary<NSString *, NSString *> *)holds;
@end

/// P31 and P33. The one builder and the one place snapshots are published.
@interface MMGraph : NSObject
+ (instancetype)shared;
/// Where the builder reads facts. Set once at launch, before -start. Rebuilds wait until it is set.
@property (strong) id<MMFactSource> source;
/// Experts register once at launch, before -start. The builder asks each for findings on every rebuild.
- (void)addExpert:(id<MMExpert>)expert;
- (void)start;
/// Ends publishing. After it returns no build sets -latest or reaches an observer, a build that was running included,
/// and -rebuild: does nothing until the next -start. MMCoreStop calls it.
- (void)stop;
/// Asks for a rebuild. Calls are coalesced, so many signals in one tick give one rebuild.
- (void)rebuild:(NSString *)why;
@property (readonly) MMSnapshot *current;               // main thread only, never nil after the first build
@property (readonly, atomic) MMSnapshot *latest;        // any queue
/// Calls block on main with each new current snapshot. Returns a token for -stopObserving:.
/// Both take a lock, so any queue may call them. A block is never called after -stopObserving: returns on main.
- (id)observe:(void (^)(MMSnapshot *snapshot))block;
- (void)stopObserving:(id)token;
/// Principle 5. Facts gathered now for one finding: a new sample, its worktree's git facts with wait YES,
/// and its sessions. Act checks every action on these, never on the snapshot, which may be 5 seconds old.
/// Starts from [WFScanner fresh:] in WFRemove, WF Forest.m:274. Blocks. Never on main.
- (MMFacts *)freshFactsFor:(MMFinding *)finding;
/// P33. Replaces insomnia://on. Insomnia holds the Mac awake for this pid until it exits. Reason shows on its card.
- (void)holdAwake:(NSString *)reason pid:(MMProcKey)key;
/// The broker saves each expert's newest review here. The next snapshot carries it.
- (void)saveReview:(MMReview *)review forExpert:(NSString *)expert;
@end
