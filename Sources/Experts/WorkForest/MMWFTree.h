// WorkForest's model: one worktree, and the words, keeps, menu and cards built from it.
// Everything here is pure. It reads a tree and a view of the review and the plan, and returns text and specs,
// so the render tool draws the same menu and cards from fixture trees that the app draws from the graph.
// Ported from WFTree in WorkForest's Trees.h, WFWorkKeeps and the words in Forest.m, and the menu and card in main.m.
#import <Foundation/Foundation.h>
#import "Core/MMExpert.h"

/// One checkout: a repo's main checkout or a linked worktree, with its git facts, its disk and what runs in it.
/// Built from MMFacts by the expert, and from fixtures by the render tool.
@interface MMWFTree : NSObject
@property (copy) NSString *path, *repo, *branch;          // branch nil when detached
@property (copy) NSString *findingID;                    // "workforest:worktree:<path>"
@property BOOL isMain, locked, missing;
@property (copy) NSString *maker;                        // person, claude-code, cursor or conductor
@property (copy) NSString *makerSession;
// Git, from Know's git facts. gitKnown is NO until the first git facts arrive.
@property BOOL gitKnown;
@property (copy) NSString *head, *defaultBranch;
@property (copy) NSString *merged;                       // ancestor, tree, patch, squash, pr, merge-tree; nil when not merged
@property (copy) NSString *upstream;                     // the remote branch, "gone" when it was deleted, "none" when never pushed
@property NSInteger dirty, untracked, stashes, unpushed, notInDefault;   // -1 when git could not tell
@property BOOL onRemote;                                 // HEAD is on some remote ref
@property (strong) NSDate *lastCommit;
// Disk, from Know's walk. sized is NO until the first walk ends.
@property BOOL sized;
@property uint64_t diskBytes, freedBytes, cacheBytes;
@property NSInteger files;
@property (strong) NSDate *touched, *created;
// What runs in it now, from Senses and Know.
@property (copy) NSArray<NSString *> *processes;         // process names with a working directory inside
@property (copy) NSDictionary *session;                  // agent, title, id, lastActiveAt, startedAt, live
@property BOOL isProtected;                              // a protected branch, such as main

@property (readonly) NSString *name;                     // the folder name
@property (readonly) NSString *repoName;
@property (readonly) BOOL detached;
@property (readonly) BOOL done;                          // merged, or its remote branch was deleted
@property (readonly) NSDate *lastWork;                   // the latest of the last commit, the newest file and the agent session
@property (readonly) NSTimeInterval quiet;               // seconds since lastWork
- (NSDictionary *)json;                                  // every field, for the finding's facts and --json
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

#pragma mark Words

/// "squash-merged · remote branch deleted · 2 commits only here", or "clean".
NSString *MMWFStateWords(MMWFTree *t);
/// The one thing a row says about its git state: "3 changes", "squash-merged", "clean".
NSString *MMWFShortState(MMWFTree *t);
/// "Claude Code" for the registry id claude-code, and so on.
NSString *MMWFAgentName(NSString *harnessID);
/// "Idle", "Proactive", "Eager".
NSString *MMWFModeLabel(NSString *mode);

#pragma mark Keeps

/// How long activity keeps a worktree, from WORKFOREST_RECENT_HOURS, a day by default.
NSTimeInterval MMWFRecent(void);
/// How long Proactive waits, from WORKFOREST_PROACTIVE_HOURS, a week by default.
NSTimeInterval MMWFProactiveQuiet(void);
/// Why a worktree stays whatever the mode, on these facts, or nil when the mode may decide.
/// Ported from WFWorkKeeps: main checkout, missing folder, another tool's worktree, locked, git facts not known,
/// uncommitted or untracked files, commits only here, a process inside, a recent agent session, file change or creation.
NSString *MMWFWorkKeeps(MMWFTree *t);
/// active, merged, stale, quiet or missing, for the menu sections. verdict is the review's word for it, or nil.
NSString *MMWFCategory(MMWFTree *t, NSString *verdict);

#pragma mark The menu and cards

/// What the menu and cards need besides the trees: the review, the plan and what was removed.
/// The app fills it from the snapshot, and the render tool from fixtures.
@interface MMWFView : NSObject
@property (copy) NSArray<MMWFTree *> *trees;             // main checkouts included
@property (copy) NSString *mode;                         // idle, proactive or eager
@property (copy) NSString *model;                        // "Haiku"
@property (strong) NSDate *reviewAt;
@property (copy) NSString *reviewError, *summaryWords;
@property BOOL reviewing;
/// By findingID: {word, kind (keep, go, unsure), confidence, about, reason, keepEvidence, judged, decidedBy}.
@property (copy) NSDictionary<NSString *, NSDictionary *> *verdicts;
/// By findingID: {remove, why}.
@property (copy) NSDictionary<NSString *, NSDictionary *> *plan;
@property (copy) NSArray<NSString *> *candidates;        // findingIDs Clean Up removes
/// Recently removed, newest first: {rid, path, branch, at, by, saved, state}.
@property (copy) NSArray<NSDictionary *> *removed;
/// By findingID: facts that belong to another expert, each {label, value, expert, findingID}.
@property (copy) NSDictionary<NSString *, NSArray<NSDictionary *> *> *links;
@property (copy) NSDictionary<NSString *, NSDate *> *keptUntil;   // by findingID
@property NSTimeInterval watchingLeft;
/// What an action asks for: reveal, terminal, keep, remove, protect, copy-path, restore, clean-up, review.
/// key is a findingID or, for restore, a record id.
@property (copy) void (^act)(NSString *what, NSString *key, BOOL option);
@end

/// The main menu, to DESIGN.md: header, summary, Clean Up and Review Now, the sections, and More.
MMMenuSpec *MMWFMenu(MMWFView *v);
/// The hover card of one worktree.
MMCardSpec *MMWFCard(MMWFTree *t, MMWFView *v);
/// The number beside the icon: the worktrees Clean Up would remove. nil when there are none.
NSString *MMWFBadge(MMWFView *v);
/// "2 worktrees to clean up", "13 worktrees", "no worktrees".
NSString *MMWFAccessibilityState(MMWFView *v);
