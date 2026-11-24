// The window that opens from the MinMacs icon, issue #62: prototype 195-a, Dock Below, with 197-b's Settings in place
// (branch ui-prototypes, docs/2.0/ui-prototypes/p/195-a.html and p/197-b.html).
//
//   +-----------------------------------------------------------------+
//   | 2 agents ask you             (folded away when nobody asks)     |
//   +------------------+--------------------------+-------------------+
//   | Servers      20  | Memory ~^~    Disk ___   | Worktrees     16  |
//   | Agents       16  | Today                    | Caches         5  |
//   | Apps, helpers 15 | Stopped :3000 Next.js.   |                   |
//   |                  | (or a pointed row's story)|                   |
//   +------------------+--------------------------+-------------------+
//   | ring  42.4 / 64 GB   [ Fix Everything ]   3.9 GB memory back    |
//   |       182 GB free    7 fixes, x first     31.1 GB disk back     |
//   +-----------------------------------------------------------------+
//   |                                                    gear  power  |
//   +-----------------------------------------------------------------+
//
// This file is the view model only: plain values, no AppKit and no Core type, so the window, the render tool and the
// checks read the same thing. Sources/Shell builds one from each snapshot, off main (MMWindowFeed), and hands it to
// the window on main. The window draws what the model holds and nothing else: no disk, no process, no graph.
// Memory and disk are two numbers everywhere and are never summed. Every string is shown as is.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The two sides. Memory rows sit on the left, disk rows on the right.
typedef NS_ENUM(NSInteger, MMWindowSide) { MMWindowMemory = 1, MMWindowDisk = 2 };

/// What a row is, for its icon. The window draws a small mark of its own for each, never a logo.
typedef NS_ENUM(NSInteger, MMWindowKind) {
    MMWindowServer = 0,    // iconHint is the framework's name, such as "next", or nil
    MMWindowAgent,         // iconHint is the harness id, such as "claude-code"
    MMWindowApp,           // iconHint is the bundle id, so the window shows the app's own icon
    MMWindowHelper,
    MMWindowTabs,
    MMWindowWorktree,
    MMWindowCache
};

#pragma mark - Sizes

/// One rule for every size the window shows, as its number and its unit: megabytes whole, gigabytes with one decimal
/// that stays when it is a zero ("1.0"), a second decimal under 10 GB when it says more ("1.86", but "1.3"), whole
/// from 100 GB up ("182"), and terabytes from 1000 GB, with one decimal ("1.0 TB").
/// Memory counts in 1024s, as the Mac names its memory. With `disk`, a size counts in thousands, as the Finder names
/// a disk and what is on it: the disk's whole, its free space and every size on the disk side come from here.
NSArray<NSString *> *MMWindowSizeParts(uint64_t bytes, BOOL disk);
/// The same on one line: "1.86 GB".
NSString *MMWindowSizeText(uint64_t bytes, BOOL disk);
/// What a thing can hold, such as the Mac's memory or a disk: the same, with a round number's ".0" left out: "64 GB".
NSString *MMWindowWholeText(uint64_t bytes, BOOL disk);

/// What a graph's height means, in plain words, with the side's whole: "Higher means more of the 64 GB is in use",
/// "Lower means less room left on the 994 GB disk". And the graph's title: "Memory in use", "Disk free".
NSString *MMWindowHourExplain(BOOL disk, uint64_t whole);
NSString *MMWindowHourTitle(BOOL disk);

#pragma mark - The last hour

/// One filled line: 60 values, oldest first, one a minute. A minute with no value holds NSNull.
/// The window draws the filled part across the graph's width, with both ends in words and how far it moved.
/// With fewer than five filled minutes it shows the newest value and says the line fills in as the hour passes.
@interface MMWindowHour : NSObject
@property (copy) NSString *title;                       // "Memory in use", "Disk free"
@property (copy) NSString *explain;                     // "Higher means more of the 64 GB is in use"
@property (copy) NSArray *values;                       // NSNumber bytes or NSNull, 60 of them
@property MMWindowSide side;
@end

#pragma mark - Rows

/// One fact of a row's story. In the story the label stands left and the value beside it: "Files" and "3 changed,
/// 1 new". Said alone, on a row's second line, it is its phrase: "3 files changed, 1 new". A fact with no phrase is
/// not for the second line: a port the name already says, a folder too long for a line.
@interface MMWindowFact : NSObject
@property (copy) NSString *label, *value;
@property (copy, nullable) NSString *phrase;
+ (instancetype)label:(NSString *)label value:(NSString *)value;
@end

/// How long, by the window's one rule: "40 s", "12 min", "2 h 36 min", "3 d 4 h", "12 d". nil under ten seconds:
/// then the words say "just now", never a zero.
#pragma mark - Counted words

// Every phrase with a count in it, worded once, so one of a thing is never "1 fixes". MMWindowCounts.m.
/// "1 fix", "2 fixes": the count and the one of two forms that goes with it.
NSString *MMWindowCount(NSInteger n, NSString *one, NSString *many);
NSString *MMWindowFixes(NSInteger n);
/// The top line, "1 agent asks you", "2 agents ask you". nil when nobody asks.
NSString *_Nullable MMWindowAsksLine(NSInteger agents);
/// The end of a run, "1 fix done", "1 of 2 fixes done".
NSString *MMWindowEndTitle(NSInteger done, NSInteger total);
/// "Skipped 1 agent that asks you and 2 blocked.", or nil when nothing was skipped.
NSString *_Nullable MMWindowSkippedNote(NSInteger asks, NSInteger needYou, NSInteger kept, NSInteger blocked, NSInteger notReached, NSInteger notRun);
/// A fix's title by its kind and how many it acts on, "Stop 1 idle server", "Move 2 leftovers to the Trash". nil for
/// a kind with no count in its title.
NSString *_Nullable MMWindowFixCountTitle(NSString *kind, NSInteger n);
/// What the dock's numbers stand for while the pointer rests on Fix Everything, "After the fix", "After all 2 fixes".
NSString *_Nullable MMWindowAfterTitle(NSInteger fixes);
/// A group's header where rows wait out of view, "1 more below", "3 more above". nil when all show.
NSString *_Nullable MMWindowMoreLine(NSInteger below, NSInteger above);
/// Under a project in the Worktrees group, where its rows wait out of view: "3 more in barkbot". `project` nil or empty
/// says "3 more". Where a line a project does not fit, one line at the group's foot: "12 more in 4 projects".
NSString *MMWindowProjectMoreLine(NSInteger hidden, NSString *_Nullable project);
NSString *MMWindowProjectsMoreLine(NSInteger hidden, NSInteger projects);
/// What `count` things hold together when `unmeasured` of them have no size yet: "456 MB" with none missing,
/// "456 MB so far" with some, and "measuring" when none is measured. `size` is the measured sum as its words.
NSString *MMWindowSumText(NSString *size, NSInteger count, NSInteger unmeasured);
/// What a fix gives back on disk: "456 MB", "456 MB or more" when a part is not measured yet, and "not measured yet"
/// when nothing of it is. `size` is the measured sum as its words, and `nothing` says that sum is 0.
NSString *MMWindowBackText(NSString *size, BOOL nothing, BOOL partial);
/// Where a row stands in its group, "The biggest of 16 worktrees". With rows not measured yet it counts the measured
/// ones only and says so, "2nd biggest of 5 worktrees measured so far", and a row not measured has no place: "16 worktrees".
/// `place` counts from 1 among the measured rows, and `title` is the group's, in small letters.
NSString *MMWindowPlaceLine(NSInteger place, NSInteger count, NSInteger unmeasured, BOOL rowMeasured, NSString *title);
/// A tabs row's name, "1 localhost tab in Safari", "14 localhost tabs in Google Chrome".
NSString *MMWindowTabsName(NSInteger tabs, NSString *_Nullable browser);

NSString *_Nullable MMWindowSpan(NSTimeInterval seconds);

/// The facts, each worded in one place, so the feed and the render's made-up days say them alike and every one reads
/// as a person would say it. Each returns nil when there is nothing true to say.
MMWindowFact *_Nullable MMWindowFactPort(NSInteger port);                          // Port, ":3000"
MMWindowFact *_Nullable MMWindowFactProject(NSString *_Nullable project);          // Project, the name or the folder; "in api". nil for the disk's top
MMWindowFact *_Nullable MMWindowFactOwner(NSString *_Nullable project);            // Project, of a cache; "for atlas"
MMWindowFact *_Nullable MMWindowFactRunsIn(NSString *_Nullable where);             // Runs in, "Ghostty, tab 2"; "runs in Ghostty, tab 2"
MMWindowFact *_Nullable MMWindowFactStartedBy(NSString *_Nullable who);            // Started by, "pnpm dev in cmux"; "started by …"
MMWindowFact *_Nullable MMWindowFactIdle(NSTimeInterval seconds);                  // Idle, "2 h 10 min"; "idle for 2 h 10 min"
MMWindowFact *_Nullable MMWindowFactLastUsed(NSTimeInterval ago);                  // Last used, "3 min ago" or "just now"; "used 3 min ago"
MMWindowFact *_Nullable MMWindowFactUp(NSTimeInterval seconds);                    // Running, "2 h 36 min"; "up 2 h 36 min"
MMWindowFact *_Nullable MMWindowFactKept(NSTimeInterval left);                     // Kept, "1 h 20 min more"; "kept for 1 h 20 min more"
MMWindowFact *_Nullable MMWindowFactAgent(NSString *_Nullable harness);            // Agent, "Claude Code"; "Claude Code"
MMWindowFact *_Nullable MMWindowFactSession(NSString *_Nullable title);            // Session, the agent's session title; the same alone
MMWindowFact *_Nullable MMWindowFactState(NSString *_Nullable state);              // State, "working". The story's first line says it
MMWindowFact *_Nullable MMWindowFactUsedBy(NSString *_Nullable agent);             // Used by, "Claude Code"; "used by Claude Code"
MMWindowFact *_Nullable MMWindowFactServes(NSArray *_Nullable ports);              // Serves, "ports 3000, 3001"; "serves ports 3000, 3001"
MMWindowFact *_Nullable MMWindowFactStays(NSString *_Nullable reason);             // Stays, the reason. The story's first line says it
MMWindowFact *_Nullable MMWindowFactLeftBy(NSString *_Nullable worktree);          // Left by, "fix-auth-redirect"; "left by fix-auth-redirect"
MMWindowFact *_Nullable MMWindowFactFolder(NSString *_Nullable folder);            // Folder, the path. Not for the second line
MMWindowFact *_Nullable MMWindowFactOpenTabs(NSInteger tabs);                      // Open, "14 tabs"; "14 tabs open"
MMWindowFact *_Nullable MMWindowFactOnPorts(NSArray *_Nullable ports);             // On, "port 3003"; "on port 3003"
MMWindowFact *_Nullable MMWindowFactBranch(NSString *_Nullable branch);            // Branch, the name. Not for the second line: a linked worktree's row name says it
MMWindowFact *_Nullable MMWindowFactFiles(NSInteger changed, NSInteger added);     // Files, "3 changed, 1 new"; "3 files changed, 1 new"
MMWindowFact *_Nullable MMWindowFactNotPushed(NSInteger commits);                  // Not pushed, "2 commits"; "2 commits not pushed"
MMWindowFact *_Nullable MMWindowFactUntouched(NSTimeInterval seconds);             // Untouched, "12 d"; "untouched for 12 d". "Changed", "just now" under ten seconds
MMWindowFact *_Nullable MMWindowFactKind(NSString *_Nullable kind);                // Kind, "Xcode build output"; the same alone
// A worktree's git, from WorkForest's facts. None of these is for the second line: the row already says its state.
/// Last commit, "Fix the ranking · a1b2c3d · 2 h ago": its subject, short hash and age, each only when known.
MMWindowFact *_Nullable MMWindowFactLastCommit(NSString *_Nullable subject, NSString *_Nullable head, NSTimeInterval ago);
/// Against, "3 ahead, 1 behind main", or "2 ahead of main". nil when both are 0 or not known. -1 is not known.
MMWindowFact *_Nullable MMWindowFactAgainst(NSInteger ahead, NSInteger behind, NSString *_Nullable defaultBranch);
/// Merged, "Squash-merged into main", from WorkForest's merge word: ancestor, tree, patch, squash, pr or merge-tree.
MMWindowFact *_Nullable MMWindowFactMerged(NSString *_Nullable how, NSString *_Nullable defaultBranch);
/// Remote, "Branch deleted on the remote" for gone, "Never pushed" for none. nil for any other upstream.
MMWindowFact *_Nullable MMWindowFactRemote(NSString *_Nullable upstream);
/// Made by, "Claude Code" for the registry id claude-code, with the session it ran when its title is known:
/// "Claude Code · Tune the ranking". nil for the person, who needs no line.
MMWindowFact *_Nullable MMWindowFactMadeBy(NSString *_Nullable maker, NSString *_Nullable session);
/// Holds, of a row that stands for several, MMWindowCollapsed: "45,282 folders in 169 groups" when each member holds
/// things of its own, else "4 projects"; the same alone. nil under two members.
MMWindowFact *_Nullable MMWindowFactHolds(NSInteger members, NSString *one, NSString *many, NSInteger inner, NSString *_Nullable innerOne, NSString *_Nullable innerMany);
/// Now, of such a row: how many of its members can go and how many stay, MMWindowCollapsedSplit. Its story's first line
/// says it after the lead, so it is not for the second line.
MMWindowFact *_Nullable MMWindowFactSplit(NSString *_Nullable split);
/// Why some stay, of such a row: the reason of the biggest member that stays, and how many other reasons there are,
/// "a running process has a file open in it, and 2 other reasons". With `all` the label is "Why they stay". Not for
/// the second line. nil with no reason.
MMWindowFact *_Nullable MMWindowFactWhyStay(NSArray<NSString *> *reasons, BOOL all);

/// A worktree's pull request, as the person's gh told it, for the row's story. The window shows its line, its title
/// and an Open pull request press that opens url in the default browser. Only a worktree row has one, and only while
/// something is known: gh missing, not logged in, a failure or the pref off leave it nil.
typedef NS_ENUM(NSInteger, MMWindowPullKnown) { MMWindowPullLooking = 1, MMWindowPullNone, MMWindowPullFound };
@interface MMWindowPull : NSObject
@property MMWindowPullKnown known;
@property NSInteger number;
@property (copy, nullable) NSString *state;             // open, merged or closed
@property BOOL draft;
@property (copy, nullable) NSString *review;            // approved, changes requested, review requested
@property NSInteger checksPassing, checksFailing, checksPending;
/// How long ago it was merged, in seconds. Below 0 when not merged or not known.
@property NSTimeInterval mergedAgo;
@property (copy, nullable) NSString *title, *url;
/// The title of its milestone, shown as a fact row under the title: "Milestone   Phase 6: Bench and polish". nil for none.
@property (copy, nullable) NSString *milestone;
/// "PR #142 · open · checks passing · review requested", "PR #98 · merged 2 d ago", "Looking for a pull request",
/// "No pull request for this branch". Each part only when it is known.
@property (readonly) NSString *line;
/// YES when the story shows the press: a pull request with a web address.
@property (readonly) BOOL opens;
@end
/// "Open pull request", the press under the title.
extern NSString *const MMWindowOpenPull;

/// How a row's story opens: one line that says whether it stays, goes or waits, and why. The window draws the lead
/// in bold with a mark: a dot for what stays, an orange triangle for what goes, a white diamond for what asks.
typedef NS_ENUM(NSInteger, MMWindowFateKind) { MMWindowFateStays = 0, MMWindowFateGoes, MMWindowFateAsks };
@interface MMWindowFate : NSObject
@property MMWindowFateKind kind;
@property (copy) NSString *lead;                        // "Stays.", "Goes with Fix Everything.", "Asks you.", "Working."
@property (copy, nullable) NSString *note;              // the sentence after it: "In use."
@end

/// What lets near-identical rows stand as one, DESIGN rule 16. A cache's kin is the registry row it was found by, and
/// a helper's is its name and the worktree that left it. Rows of one kin, MMWindowCollapseLeast of them or more and none
/// holding another, are one row in the window, MMWindowCollapsed. The CLI's own verbs keep every member apart.
@interface MMWindowKin : NSObject
@property (copy) NSString *key;                         // "noonoo:tmpdir-families", "helper:node|/code/atlas-trees/wip"
@property (copy) NSString *title;                       // the one row's name, "Temp folders left by tools"
@property (copy) NSString *one, *many;                  // what each member is in it: "group" and "groups"
/// What a member holds when it holds things of its own, as a temp-folder family holds folders: "folder", "folders".
@property (copy, nullable) NSString *innerOne, *innerMany;
@property NSInteger inner;                              // how many of those this member holds
/// Where the member is. Two members of which one holds the other are never summed, so their kin stays apart.
@property (copy, nullable) NSString *path;
/// The member has something that may go now: a cache that is free and kept by nothing, a helper Fix Everything ends.
@property BOOL canGo;
/// Why it stays, in plain words, when it does.
@property (copy, nullable) NSString *why;
@end

/// Three of one kin or more become one row: two rows of one kind still read as two things, a third as a list.
extern const NSInteger MMWindowCollapseLeast;

/// One thing that holds memory or disk.
@interface MMWindowRow : NSObject
@property (copy) NSString *key;                         // stable across snapshots, so hover and scroll stay
@property MMWindowKind kind;
@property (copy, nullable) NSString *iconHint;
@property (copy) NSString *name;                        // ":3000 Next.js", "Tune the ranking", "fix-auth-redirect"
@property (copy, nullable) NSString *state;             // one quiet word: "merged", "kept", "will close"
@property double cpuPercent;                            // of one core; below 0 when not known, then not drawn
@property uint64_t bytes;                               // the one number
/// The size was not measured yet: a worktree whose files have not been walked. bytes is then 0 and no reading, so no
/// view and no verb shows it as a number. Each shows sizeWord where the size would stand. A measured 0 is a reading.
@property BOOL unmeasured;
@property NSInteger tabs;                               // for MMWindowTabs, the count shown in the name
@property BOOL needsYou;                                // an agent that asks: a white diamond on its icon
@property BOOL inFix;                                   // Fix Everything touches it: a small orange mark
/// Nothing is going on in it now: an idle server or agent, an app that uses next to no CPU, a helper left behind,
/// a worktree with nothing uncommitted, a cache nothing uses. Its name is drawn a step quieter, so the rows where
/// something happens lead. A row a fix touches or that asks is never drawn quiet, whatever this says.
@property BOOL quiet;
/// The row's own last hour, 60 NSNumber bytes or NSNull, or nil when Core keeps none. Only agents and servers have one.
@property (copy, nullable) NSArray *hour;
/// The story the middle shows while the pointer rests on the row: who owns it, where it is, why it stays.
@property (copy) NSArray<MMWindowFact *> *facts;
/// Read from the row's own fields and never stored: a row that asks leads with "Asks you.", a row Fix Everything
/// touches with "Goes with Fix Everything.", and any other with its fact labelled Stays, whose words are the sentence
/// after it, or, for an agent, with its State. nil when the row holds none of these. An agent's Why is a raw fact of
/// its processes and stays in the fact list.
@property (readonly, nullable) MMWindowFate *fate;
/// The facts under that line: all of them but the ones the line already said.
@property (readonly) NSArray<MMWindowFact *> *storyFacts;
/// The name as every view draws it: a tabs row's is its count and its browser, "3 localhost tabs in Safari".
@property (readonly) NSString *shownName;
/// A worktree's project, its repo's folder name, "minmacs". nil for any other row, and for a worktree with no repo.
@property (copy, nullable) NSString *project;
/// A worktree's name under its project's sub-header, where the header names the project: a linked worktree's
/// branch, "seam-130", or "main checkout". nil keeps the name.
@property (copy, nullable) NSString *nameInProject;
/// When work last happened in a worktree, in seconds since 1970. 0 when not known, and for any other row.
@property NSTimeInterval workedAt;
/// NO for a tabs row that holds no bytes: its count in the name is its number, and no size of 0 is drawn or read out.
/// NO for a row whose size is not measured yet, too.
@property (readonly) BOOL showsSize;
/// The word that stands where the size would while it is not measured, MMWindowMeasuring. nil for any other row.
@property (readonly, nullable) NSString *sizeWord;
/// A worktree's pull request, or nil while nothing is known of one. The feed sets it from MMPulls, memory only.
@property (strong, nullable) MMWindowPull *pull;
/// The kin it may stand with, or nil for a row that always stands alone.
@property (strong, nullable) MMWindowKin *kin;
/// A row that stands for several, MMWindowCollapsed: its members, biggest first. nil for any other row.
@property (copy, nullable) NSArray<MMWindowRow *> *members;
@end

/// The rows with each kin of MMWindowCollapseLeast members or more, none of which holds another, made one row by
/// MMWindowCollapsedRow, in the place of its first member. Every other row as it came. The order is the caller's.
NSArray<MMWindowRow *> *MMWindowCollapsed(NSArray<MMWindowRow *> *rows);
/// The one row of these members, which share a kin. Its key is "kin:" and the kin's key; its size is the members'
/// sum, true since none holds another; it goes with Fix Everything when any member does, and is quiet when all are.
/// Its quiet word is the one all members share, else "in use" when any is in use, else "kept" when any is kept: a
/// member in use stops none of the others. Its story says how many can go and why the rest stay.
MMWindowRow *MMWindowCollapsedRow(NSArray<MMWindowRow *> *members);
/// The split of such a row's members, "168 groups can go, 1 in use", "3 sessions can go, 1 kept", "4 processes stay".
NSString *MMWindowCollapsedSplit(NSInteger go, NSInteger inUse, NSInteger kept, NSInteger other, NSString *one, NSString *many);
/// Over the members in its story: "Its 4 projects", "The 5 biggest of its 169 groups".
NSString *MMWindowMembersLine(NSInteger shown, NSInteger count, NSString *one, NSString *many);

/// "measuring": a row's size slot while its size is not measured yet.
extern NSString *const MMWindowMeasuring;
/// "Not measured yet": the same, where the window has a line of its own for it.
extern NSString *const MMWindowNotMeasured;
/// The order of a group's rows: the measured ones biggest first, then by tabs, then by key, and after them the rows
/// whose size is not measured yet, by key. The order holds between snapshots.
NSComparisonResult MMWindowRowOrder(MMWindowRow *a, MMWindowRow *b);
/// The order of the worktrees: the newest work first, then as MMWindowRowOrder. A row whose last work is not known
/// comes after the ones whose is.
NSComparisonResult MMWindowActivityOrder(MMWindowRow *a, MMWindowRow *b);
/// The worktrees by project: each project's rows by activity, and the projects by their most active row, newest
/// first. A project is a row's `project`; the rows with none are one project of their own, after the rest.
NSArray<MMWindowRow *> *MMWindowByProject(NSArray<MMWindowRow *> *rows);
/// The projects of these rows in their order, each once. A row with no project counts as the project "".
NSArray<NSString *> *MMWindowProjectsOf(NSArray<MMWindowRow *> *rows);
/// What a project with no name is called under its sub-header: "Other".
extern NSString *const MMWindowNoProject;
/// What a repo's main checkout is called under its project's sub-header: "main checkout".
extern NSString *const MMWindowMainCheckout;

/// How far the look behind a group's empty line went. Only a look that ended may say "found".
typedef NS_ENUM(NSInteger, MMWindowLooked) {
    MMWindowLookedDone = 0,     // the look ended: "No worktrees found"
    MMWindowLookedNotYet,       // the first look still runs: "Looking for worktrees"
    MMWindowLookedNowhere,      // there was nothing to look in, or nothing looks here: "No folders to look in"
};
/// The quiet line of a group with no rows, by its key. It never claims a result the look did not give.
NSString *_Nullable MMWindowEmptyNote(NSString *groupKey, MMWindowLooked looked);

/// One group with a still header: its title, its count and its rows, biggest first. Each group scrolls on its own.
@interface MMWindowGroup : NSObject
@property (copy) NSString *key, *title;                 // "servers", "Servers"
@property MMWindowSide side;
@property (copy) NSArray<MMWindowRow *> *rows;
/// The one quiet line under the header when the group has no rows, from MMWindowEmptyNote: "No worktrees found".
@property (copy, nullable) NSString *emptyNote;
/// How many of its rows have no measured size yet.
@property (readonly) NSInteger unmeasured;
/// The Worktrees group: its rows come by project, MMWindowByProject, and its header says "by activity". With two
/// projects or more the list shows each project under a sub-header of its own.
@property BOOL byProject;
/// YES when the list shows sub-headers: the group comes by project and holds more than one.
@property (readonly) BOOL grouped;
@end

#pragma mark - The ring

/// One slice of the ring: a group's share of memory in use, or of the disk in use.
@interface MMWindowSlice : NSObject
@property (copy) NSString *group;                       // a group key, or "other"
@property uint64_t bytes;
@end

/// Memory by holder inside, the disk as the outer track.
@interface MMWindowRing : NSObject
@property uint64_t memoryUsed, memoryTotal;
@property uint64_t diskFree, diskTotal;
@property (copy) NSArray<MMWindowSlice *> *memory, *disk;
@end

#pragma mark - Fix Everything

/// One fix as the dock names it.
@interface MMWindowFix : NSObject
@property (copy) NSString *key, *title;                 // "wrapup:/path", "Wrap Up fix-auth-redirect"
@property uint64_t memoryBack, diskBack;
/// Something it removes has no measured size yet, so diskBack holds only what was measured: it is "or more", no total.
@property BOOL diskPartial;
@property BOOL needsYou;                                // runs only on its own press, so Fix Everything skips it
@end

/// Where a run of Fix Everything stands. nil on the model when none runs and none just ended.
@interface MMWindowRun : NSObject
@property BOOL running;                                 // NO once it ended; the window shows the end, then lets go
@property (copy, nullable) NSString *step;              // "Stopping :3001", shown in the button while it runs
/// The step without the name it acts on, "Stopping". When a name is too long for the button, the button says this
/// alone, and never a cut name. The count stands beside the button.
@property (copy, nullable) NSString *stepAction;
@property NSInteger done, total;                        // fixes landed, fixes planned
@property uint64_t memoryBack, diskBack;                // what has come back so far
@property uint64_t memoryPlanned, diskPlanned;          // what the run set out to give back
/// YES while a fix that has not landed has a part not measured yet, issue #83: diskPlanned is then no total, and
/// diskShare does not count toward it. Once such a fix landed, what it gave back is counted into diskPlanned.
@property BOOL diskPlannedPartial;
/// What came back of what was planned, 0 to 1, each side on its own. 0 while the plan is no total.
- (double)memoryShare;
- (double)diskShare;
@property (copy, nullable) NSString *endTitle;          // "7 fixes done"
@property (copy, nullable) NSString *endNote;           // "Skipped 2 agents that ask you and 4 blocked. Deleted 3, moved 2 to the Trash."
@end

#pragma mark - Settings

/// One choice of a rule with what it does, in plain words.
@interface MMWindowChoice : NSObject
@property (copy) NSString *title;                       // "Off", "Ask", "Auto"
@property (copy) NSString *explain;                     // "Stops a server after 2 h idle."
@end

/// One rule: its name, its choices and the one picked. A change applies at once.
@interface MMWindowRule : NSObject
@property (copy) NSString *ruleID, *title;              // "servers", "Stop idle servers"
@property (copy) NSArray<MMWindowChoice *> *choices;
@property NSInteger picked;                             // -1 while nothing is chosen yet: then no choice is drawn picked, and a press on any picks it
@property (copy, nullable) NSString *note;              // what it would do next: "1 ready. It waits for your press."
@end

/// One switch, such as the lid or Open at login.
@interface MMWindowSwitch : NSObject
@property (copy) NSString *switchID, *title;            // "lid", "Lid closed"
@property (copy) NSString *card;                        // the card it stands in: MMWindowAwakeCard or MMWindowMacCard
@property BOOL on;
/// The one short line under the title, only when it says a state: "Awake now for 2 agents". nil for most switches.
@property (copy, nullable) NSString *note;
/// What the switch does, in a sentence. Not drawn: the switch's tooltip and VoiceOver read it.
@property (copy, nullable) NSString *help;
/// The switch changes nothing on this Mac, such as the lid switch on a Mac with no lid. It is drawn as not
/// available, takes no press, and its note says why.
@property BOOL inert;
@end

@interface MMWindowSettings : NSObject
@property (copy) NSArray<MMWindowRule *> *rules;
@property (copy) NSArray<MMWindowSwitch *> *switches;
/// The badge in the head of "Clean up on its own" while the rules that are on still only watch: "Starts in 23 h".
/// nil once they may act, or when no rule acts on its own. It stands once, not on every rule.
@property (copy, nullable) NSString *startsIn;
@end

/// The words of Settings, written once: the feed in Shell/MMWindowRules.m and the render's fixtures both build their
/// cards from these, so a fixture cannot show a card the app does not have.
/// The rule ids in the order Settings shows them: servers, apps, worktrees, caches.
NSArray<NSString *> *MMWindowRuleIDs(void);
/// The three choices of a rule, in the order of Core's modes Idle, Proactive and Eager: "Off", "Careful", "Eager".
NSArray<NSString *> *MMWindowChoiceTitles(void);
/// "Stop idle servers" for "servers". nil for an unknown id.
NSString *_Nullable MMWindowRuleTitle(NSString *ruleID);
/// What each of the three choices does today, one sentence each. Shell/MMWindowRules.m says which expert rule
/// stands behind each sentence, and test/window.sh checks those.
NSArray<NSString *> *_Nullable MMWindowRuleExplains(NSString *ruleID);
/// One rule's card with these words, the choice picked and the note at its foot.
MMWindowRule *MMWindowRuleCard(NSString *ruleID, NSInteger picked, NSString *_Nullable note);
/// A card with choices of its own: each entry is a title and its sentence.
MMWindowRule *MMWindowChoiceCard(NSString *ruleID, NSString *title, NSInteger picked, NSArray<NSArray<NSString *> *> *choices, NSString *_Nullable note);
/// The note of a rule that does not act on its own while fixes of its kind wait: "1 ready. It waits for your press."
NSString *_Nullable MMWindowReadyNote(NSInteger ready);
/// The badge of the rules that would act but still only watch: "Starts in 23 h", "Starts in 40 min". nil when no
/// time is left. MMWindowStartsHelp says what it means, for its tooltip and VoiceOver.
NSString *_Nullable MMWindowStartsNote(NSTimeInterval left);
extern NSString *const MMWindowStartsHelp;
/// The one line at the foot of This Mac in Settings: everything MinMacs removes goes to the Trash.
extern NSString *const MMWindowTrashLine;
/// The cards of switches. "Keep this Mac awake" stands first in Settings, so keeping the Mac awake is never hunted for.
extern NSString *const MMWindowAwakeCard, *const MMWindowMacCard, *const MMWindowCleanupCard;
/// The three switches of "Keep this Mac awake": Keep awake now (insomnia.awake, as caffeinate does), While agents work
/// (insomnia.agents) and Lid closed (insomnia.lid). `note` is the state line under the title, or nil. An inert lid switch is the one of a Mac with no lid.
MMWindowSwitch *MMWindowAwakeSwitch(BOOL on, NSString *_Nullable note);
MMWindowSwitch *MMWindowAgentsSwitch(BOOL on, NSString *_Nullable note);
MMWindowSwitch *MMWindowLidSwitch(BOOL on, BOOL inert, NSString *_Nullable note);
/// The switch of the card "This Mac".
MMWindowSwitch *MMWindowLoginSwitch(BOOL on, NSString *_Nullable note);
/// Pull requests, in "This Mac": whether the window may ask the person's gh about a worktree's pull request, the pref
/// workforest.pullRequests. MMWindowPullsHelp is its tooltip.
MMWindowSwitch *MMWindowPullsSwitch(BOOL on);
extern NSString *const MMWindowPullsHelp;
/// What Keep awake now and While agents work do, for their tooltips. MMWindowAgentsNote is the state line of While
/// agents work: "Awake now for 2 agents", nil while no agent holds the Mac awake. `holding` is how many do now.
NSString *MMWindowAwakeHelp(void);
NSString *MMWindowAgentsHelp(NSInteger quietMinutes);
NSString *_Nullable MMWindowAgentsNote(BOOL on, NSInteger holding);

/// A rule as one switch in "Clean up on its own", with a short title: "Idle dev servers". On is a mode that acts on
/// its own: Careful, or Eager where Careful acts on nothing, as for apps. Off is Off. A rule set to Eager elsewhere
/// shows on, with Eager's words.
NSString *_Nullable MMWindowRuleSwitchTitle(NSString *ruleID);
BOOL MMWindowRuleIsOn(NSString *ruleID, NSInteger picked);
NSInteger MMWindowRuleOnChoice(NSString *ruleID);
/// What the switch does when on, in the mode picked, or the mode it would turn on to: one short sentence. Not drawn:
/// the switch's tooltip and VoiceOver read it.
NSString *_Nullable MMWindowRuleSwitchNote(NSString *ruleID, NSInteger picked);
/// "This Mac has no lid.", the state line of an inert lid switch.
extern NSString *const MMWindowNoLidNote;

#pragma mark - The welcome

/// The first time the window opens, prototype 199-a: the welcome alone, in the same window. It holds every string the
/// welcome shows and the switch as it stands before the person touches it. Nothing is applied until Start.
@interface MMWindowWelcome : NSObject
@property (copy) NSString *title;                       // "Welcome to MinMacs"
@property (copy) NSString *say;                         // what MinMacs is, in two sentences
@property (copy) NSString *loginTitle;                  // "Open at login"
@property (copy) NSString *loginOnNote, *loginOffNote;  // what each state of the switch means
@property BOOL loginOn;                                 // where the switch stands before the person touches it
@property (copy) NSString *later;                       // "It can be changed later in Settings."
@property (copy) NSArray<MMWindowFact *> *facts;        // a few calm facts: label is the title, value the sentence
@property (copy) NSString *start;                       // "Start"
/// A welcome with the words that never change, the switch on, and these facts.
+ (instancetype)welcomeWithFacts:(NSArray<MMWindowFact *> *)facts;
@end

/// What Open at login means in each state, for the welcome and for Settings: "MinMacs starts when you sign in." and
/// "MinMacs starts only when you open it."
NSString *MMWindowLoginNote(BOOL on);
/// What the window and the menus say before the first numbers: "MinMacs is taking its first look. It takes a few seconds."
extern NSString *const MMWindowLookingNote;

#pragma mark - The log

/// One entry of the log in the middle: one plain sentence in the window's words, and under it a quiet line with the
/// time, who acted and the tokens a model call took. Shell/MMWindowLog.m makes them from the log's rows, off main.
@interface MMWindowLogEntry : NSObject
@property (copy) NSString *key;                         // stable across reads: the record's rid, or the row's number
/// What it is: "action", "restored", "failed", "began", "review", "reviews", "investigate", "setting", "keep",
/// "quiet", "run" or "notice".
@property (copy) NSString *kind;
@property (copy) NSString *sentence;                    // "Stopped :3000 Next.js. Undo starts it again."
@property (copy) NSString *time;                        // "14:02", or "08:00 to 13:00" for folded reviews
@property (copy, nullable) NSString *who;               // "by you in the window", "on its own, Careful". nil when not known
@property NSInteger tokens;                             // uncached tokens of the model calls behind it, 0 for none
@property (copy) NSString *day;                         // "Today", "Yesterday", "Monday 23 November"
@property double at;                                    // seconds since 1970, of its newest row
@property int64_t row;                                  // the log's newest row behind it
/// The record can still be taken back, so the sentence says how and the quiet line has an Undo press.
@property BOOL canUndo;
/// The record an Undo press takes back, set only while canUndo.
@property (copy, nullable) NSString *undoRid;
/// How Undo takes it back, "Undo starts it again.", for the press's tooltip and what VoiceOver says after its name.
@property (copy, nullable) NSString *undoHelp;
/// The press went in and the record is being taken back: no press shows, and the quiet line says so.
@property BOOL undoing;
/// The whole story where the sentence is short, such as each thing a run skipped and why: the entry's tooltip, and
/// what VoiceOver reads after the quiet line. nil for none.
@property (copy, nullable) NSString *more;
/// What a run skipped, each {subject, why, as}, as the run row holds it. Empty for any other entry.
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *skipped;
/// The quiet line: "14:02 · by you in the window · 1,240 tokens", and "taking it back" while undoing.
@property (readonly) NSString *detail;
@end

/// "1,240 tokens", "1 token".
NSString *MMWindowTokens(NSInteger tokens);

/// The log as the middle shows it: newest first, grouped by day, at most 300 entries and none older than 30 days.
@interface MMWindowLog : NSObject
@property (copy) NSArray<MMWindowLogEntry *> *entries;
/// A quiet line over the entries. With none, what MinMacs watches and that the log fills as it acts. In the first day
/// of watching, that it acts on nothing on its own until the day is over. Never a result.
@property (copy, nullable) NSString *note;
@end

/// "Nothing is in the log yet." and the rest of an empty log's words, worded once for the feed and the fixtures.
/// left is how long the first day of watching still runs, 0 once it is over, and as MMWindowSpan says it.
NSString *MMWindowLogNote(BOOL empty, NSString *_Nullable left);

#pragma mark - The whole window

@interface MMWindowModel : NSObject
@property uint64_t generation;                          // the snapshot's; the window drops an older model
/// The top line, only when something needs the person: "2 agents ask you". nil folds the line away, and the lists
/// get its height.
@property (copy, nullable) NSString *asks;
@property (strong, nullable) MMWindowHour *memoryHour, *diskHour;
@property (copy) NSArray<MMWindowGroup *> *memoryGroups, *diskGroups;
@property (strong) MMWindowRing *ring;
/// In Fix Everything's order. Empty when there is nothing to fix: then the button rests in place, calm, and takes no press.
@property (copy) NSArray<MMWindowFix *> *fixes;
@property (strong, nullable) MMWindowRun *run;
/// What came back today, from the look-back. Two numbers. The dock shows a side only when it is above zero, and
/// only while there is nothing to fix. The same rule holds for what Fix Everything gives back: a zero side is not shown.
@property uint64_t memoryBackToday, diskBackToday;
/// YES when a removal of today was not measured: diskBackToday is then no total, and is shown as "or more".
@property BOOL diskBackTodayPartial;
@property (strong) MMWindowSettings *settings;
/// The welcome, until the person pressed Start once. nil ever after. A model with a welcome and generation 0 was made
/// before the first snapshot: only its welcome is real, and the window shows nothing else of it.
@property (strong, nullable) MMWindowWelcome *welcome;
/// The log in the middle, read only while the window is open. nil before the first read, and in `minmacs window`.
@property (strong, nullable) MMWindowLog *log;
- (nullable MMWindowRow *)row:(NSString *)key;
/// What Fix Everything gives back in memory with each process once, MMPerformance's memoryBackOnce, as the feed sets
/// it: a stop of a server and a quit of the app it rolls up into end that server once. nil sums the fixes, as a
/// fixture's model does.
@property (strong, nullable) NSNumber *memoryBackOnce;
/// What Fix Everything gives back: the fixes that do not need the person, each side on its own. Memory is
/// memoryBackOnce when set, else the fixes' sum.
- (uint64_t)memoryBack;
- (uint64_t)diskBack;
/// YES when a fix in that sum has a part not measured yet: then diskBack is no total, and is shown as "or more".
- (BOOL)diskBackPartial;
- (NSInteger)fixCount;
@end

NS_ASSUME_NONNULL_END
