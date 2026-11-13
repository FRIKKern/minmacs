// The window that opens from the MinMacs icon, issue #62: prototype 195-a, Dock Below, with 197-b's Settings in place
// (branch ui-prototypes, docs/2.0/ui-prototypes/p/195-a.html and p/197-b.html).
//
//   +-----------------------------------------------------------------+
//   | 2 agents ask you             (folded away when nobody asks)     |
//   +------------------+--------------------------+-------------------+
//   | Servers      20  | Memory in use, last hour | Worktrees     16  |
//   | Agents       16  | Disk free, last hour     | Caches         5  |
//   | Apps, helpers 15 | (or a pointed row's story)|                   |
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

/// One fact of a row's story, such as "Port" and "3000", or "Idle" and "3 d".
@interface MMWindowFact : NSObject
@property (copy) NSString *label, *value;
+ (instancetype)label:(NSString *)label value:(NSString *)value;
@end

/// How a row's story opens: one line that says whether it stays, goes or waits, and why. The window draws the lead
/// in bold with a mark: a dot for what stays, an orange triangle for what goes, a white diamond for what asks.
typedef NS_ENUM(NSInteger, MMWindowFateKind) { MMWindowFateStays = 0, MMWindowFateGoes, MMWindowFateAsks };
@interface MMWindowFate : NSObject
@property MMWindowFateKind kind;
@property (copy) NSString *lead;                        // "Stays.", "Goes with Fix Everything.", "Asks you.", "Working."
@property (copy, nullable) NSString *note;              // the sentence after it: "In use."
@end

/// One thing that holds memory or disk.
@interface MMWindowRow : NSObject
@property (copy) NSString *key;                         // stable across snapshots, so hover and scroll stay
@property MMWindowKind kind;
@property (copy, nullable) NSString *iconHint;
@property (copy) NSString *name;                        // ":3000 Next.js", "Tune the ranking", "fix-auth-redirect"
@property (copy, nullable) NSString *state;             // one quiet word: "merged", "kept", "will close"
@property double cpuPercent;                            // of one core; below 0 when not known, then not drawn
@property uint64_t bytes;                               // the one number
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
/// The name as every view draws it: a tabs row leads with its count, "3 Browser".
@property (readonly) NSString *shownName;
/// NO for a tabs row that holds no bytes: its count in the name is its number, and no size of 0 is drawn or read out.
@property (readonly) BOOL showsSize;
@end

/// One group with a still header: its title, its count and its rows, biggest first. Each group scrolls on its own.
@interface MMWindowGroup : NSObject
@property (copy) NSString *key, *title;                 // "servers", "Servers"
@property MMWindowSide side;
@property (copy) NSArray<MMWindowRow *> *rows;
/// The one quiet line under the header when the group has no rows: "No worktrees found".
@property (copy, nullable) NSString *emptyNote;
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
@property BOOL needsYou;                                // runs only on its own press, so Fix Everything skips it
@end

/// Where a run of Fix Everything stands. nil on the model when none runs and none just ended.
@interface MMWindowRun : NSObject
@property BOOL running;                                 // NO once it ended; the window shows the end, then lets go
@property (copy, nullable) NSString *step;              // "Stopping :3001", shown in the button while it runs
@property NSInteger done, total;                        // fixes landed, fixes planned
@property uint64_t memoryBack, diskBack;                // what has come back so far
@property uint64_t memoryPlanned, diskPlanned;          // what the run set out to give back; the two lines fill to these
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
@property (copy) NSString *switchID, *title;            // "lid", "Keep working with the lid closed"
@property BOOL on;
@property (copy, nullable) NSString *note;
/// The switch changes nothing on this Mac, such as the lid switch on a Mac with no lid. It is drawn as not
/// available, takes no press, and its note says why.
@property BOOL inert;
@end

@interface MMWindowSettings : NSObject
@property (copy) NSArray<MMWindowRule *> *rules;
@property (copy) NSArray<MMWindowSwitch *> *switches;
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
/// A card with choices of its own, such as the removal choice: each entry is a title and its sentence.
MMWindowRule *MMWindowChoiceCard(NSString *ruleID, NSString *title, NSInteger picked, NSArray<NSArray<NSString *> *> *choices, NSString *_Nullable note);
/// The note of a rule that does not act on its own while fixes of its kind wait: "1 ready. It waits for your press."
NSString *MMWindowReadyNote(NSInteger ready);
/// The note of a rule that would act but still only watches: "It only watches for 5h more, then it may act."
NSString *MMWindowWatchingNote(NSString *left);
/// The two switches of the card "This Mac". An inert lid switch is the one of a Mac with no lid.
MMWindowSwitch *MMWindowLidSwitch(BOOL on, BOOL inert, NSString *_Nullable note);
MMWindowSwitch *MMWindowLoginSwitch(BOOL on, NSString *_Nullable note);
/// "This Mac has no lid, so it changes nothing here."
extern NSString *const MMWindowNoLidNote;

#pragma mark - The welcome

/// The first time the window opens, prototype 199-a: the welcome alone, in the same window. It holds every string the
/// welcome shows and the two choices as they stand before the person touches them. Nothing is applied until Start.
@interface MMWindowWelcome : NSObject
@property (copy) NSString *title;                       // "Welcome to MinMacs"
@property (copy) NSString *say;                         // what MinMacs is, in two sentences
@property (copy) NSString *loginTitle;                  // "Open at login"
@property (copy) NSString *loginOnNote, *loginOffNote;  // what each state of the switch means
@property BOOL loginOn;                                 // where the switch stands before the person touches it
@property (copy) NSString *removalTitle;                // "When MinMacs removes things"
@property (copy) NSArray<MMWindowChoice *> *removal;    // Smart, Trash, Delete, with Core's sentence each
@property NSInteger removalPicked;                      // Smart, until the person picks
@property (copy) NSString *later;                       // "Both can be changed later in Settings."
@property (copy) NSArray<MMWindowFact *> *facts;        // a few calm facts: label is the title, value the sentence
@property (copy) NSString *start;                       // "Start"
/// A welcome with the words that never change, the switch on, and these choices and facts.
+ (instancetype)welcomeWithRemoval:(NSArray<MMWindowChoice *> *)removal picked:(NSInteger)picked facts:(NSArray<MMWindowFact *> *)facts;
@end

/// What Open at login means in each state, for the welcome and for Settings: "MinMacs starts when you sign in." and
/// "MinMacs starts only when you open it."
NSString *MMWindowLoginNote(BOOL on);
/// The title of the removal choice, in the welcome and on its Settings card.
extern NSString *const MMWindowRemovalTitle;
/// What the window and the menus say before the first numbers: "MinMacs is taking its first look. It takes a few seconds."
extern NSString *const MMWindowLookingNote;

#pragma mark - The whole window

@interface MMWindowModel : NSObject
@property uint64_t generation;                          // the snapshot's; the window drops an older model
/// The top line, only when something needs the person: "2 agents ask you". nil folds the line away, and the lists
/// get its height.
@property (copy, nullable) NSString *asks;
@property (strong, nullable) MMWindowHour *memoryHour, *diskHour;
@property (copy) NSArray<MMWindowGroup *> *memoryGroups, *diskGroups;
@property (strong) MMWindowRing *ring;
/// In Fix Everything's order. Empty when there is nothing to fix: then the button is dimmed in place.
@property (copy) NSArray<MMWindowFix *> *fixes;
@property (strong, nullable) MMWindowRun *run;
/// What came back today, from the look-back. Two numbers. The dock shows a side only when it is above zero, and
/// only while there is nothing to fix. The same rule holds for what Fix Everything gives back: a zero side is not shown.
@property uint64_t memoryBackToday, diskBackToday;
@property (strong) MMWindowSettings *settings;
/// The welcome, until the person pressed Start once. nil ever after. A model with a welcome and generation 0 was made
/// before the first snapshot: only its welcome is real, and the window shows nothing else of it.
@property (strong, nullable) MMWindowWelcome *welcome;
- (nullable MMWindowRow *)row:(NSString *)key;
/// What Fix Everything gives back: the fixes that do not need the person, each side summed on its own.
- (uint64_t)memoryBack;
- (uint64_t)diskBack;
- (NSInteger)fixCount;
@end

NS_ASSUME_NONNULL_END
