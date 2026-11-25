// What an app that knows its insides tells about them: cmux its windows, workspaces, panes, tabs and the processes
// in each. Terminal, iTerm, Ghostty or VS Code can follow behind the same seam, MMAppInsidesReader. Only cmux is read
// now, MMCmuxInsides.m. docs/PRIVACY.md, "An app's insides", says what is read and that it stays on this Mac.
//
//   window, main ──story or expanded row──► MMWindowController, core.window ──want──► MMAppInsides, core.insides
//                                                                                     one read at a time, 1 s limit,
//                                                                                     at most once in 5 s
//   the feed, core.window ◄──knownFor: memory only, no spawn──┘◄── MMAppInsidesDidChangeNotification ──┘
//
// Decision D11: big ambitions for understanding significant apps, with strong measures so it costs nothing. Only on
// demand: the window asks while the app row's story shows or while it is expanded, and while the window is open.
// No tick, no snapshot, no digest and no expert asks. A closed window asks nothing; the one answer kept per app is
// small and dropped when the window closes. `minmacs window --json` reads once, when it is run.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on core.insides when what is known of an app changed: an answer came that differs, or a look ended.
extern NSNotificationName const MMAppInsidesDidChangeNotification;
/// cmux's bundle id, the one app with insides for now.
extern NSString *const MMAppInsidesCmux;               // @"com.cmuxterm.app"

/// One thing inside an app: a window, workspace, pane, tab or process, with what is under it.
@interface MMInsidesNode : NSObject
@property (copy) NSString *kind;                        // "window", "workspace", "pane", "tab", "process"
@property (copy) NSString *ref;                         // the app's own handle: "workspace:2", "surface:4", a pid
@property (copy, nullable) NSString *uid;               // the app's UUID where it gives one
@property (copy) NSString *title;                       // as the app names it, its status glyph taken off
@property pid_t pid;                                    // a process, or a tab's foreground process; 0 when none
@property (copy, nullable) NSString *tty;               // a tab's terminal, "ttys003"
@property (copy, nullable) NSString *type;              // a tab's kind: "terminal", "browser"
@property (copy, nullable) NSString *url;               // a browser tab's address, only a localhost one is kept
@property double cpuPercent;                            // as the app measured it, 100 is one core
@property uint64_t bytes;                               // its physical footprint as the app summed it
@property BOOL selected;                                // the selected workspace or tab, the focused pane
@property (copy, nullable) NSString *status;            // the app's own word for an agent here: "Working", "Waiting"
@property (copy) NSArray<MMInsidesNode *> *children;
/// The pids under it: a tab's processes, for matching agents and servers MinMacs knows. Processes only.
@property (copy) NSArray<NSNumber *> *pids;
/// {kind, ref, uid, title, pid, tty, type, url, cpuPercent, bytes, selected, status, children}. Never pids: a
/// process node of its own says each.
- (NSDictionary *)json;
@end

typedef NS_ENUM(NSInteger, MMInsidesKnown) {
    MMInsidesNothing = 0,   // not asked yet, or nothing kept
    MMInsidesFound,         // the app answered: root holds its insides
    MMInsidesUnreachable,   // its CLI or socket is missing, it did not answer in time, or it refused
    MMInsidesOlder,         // it answered in a shape this MinMacs does not read: an older version
};

@interface MMInsidesAnswer : NSObject
@property MMInsidesKnown known;
/// While a read runs: an earlier answer stands and this is YES. The window then says "Looking at cmux".
@property BOOL looking;
@property (strong, nullable) MMInsidesNode *root;       // kind "app", its windows as children
@property (strong, nullable) NSDate *at;                // when the app answered
@property (copy, nullable) NSString *why;               // one line for an unreachable or older app
@property (copy) NSString *app;                         // "cmux"
/// What the tree is made of, without the numbers that move: kinds, handles, titles, pids, status and selection. An
/// answer with the stamp of the one before is the same insides, and the one before stays.
@property (readonly) NSString *stamp;
/// {app, known, looking, why, at, root}. known is nothing, found, unreachable or older.
- (NSDictionary *)json;
@end

/// An app that can tell its insides. A read runs off main, blocks for at most limit seconds and spawns at most once.
@protocol MMAppInsidesReader <NSObject>
@property (readonly) NSString *bundleID, *appName;
- (MMInsidesAnswer *)readWithin:(NSTimeInterval)limit;
@end

/// The cmux reader, MMCmuxInsides.m. One `cmux --json top --all --processes` returns the whole tree.
@interface MMCmuxInsides : NSObject <MMAppInsidesReader>
/// cmux's answer, parsed. An answer that is no JSON object with windows is MMInsidesOlder.
+ (MMInsidesAnswer *)parse:(nullable NSData *)json;
/// The arguments cmux is run with. PRIVACY.md lists them.
+ (NSArray<NSString *> *)arguments;
@end

@interface MMAppInsides : NSObject
+ (instancetype)shared;
/// The reader for an app, or nil for an app with no insides MinMacs reads.
+ (nullable id<MMAppInsidesReader>)readerFor:(nullable NSString *)bundleID;
/// What is known now, from memory alone: never spawns, never blocks. nil when nothing was asked.
- (nullable MMInsidesAnswer *)knownFor:(NSString *)bundleID;
/// Asks the app on core.insides when its last ask began `every` seconds ago or more. Never waits for it. YES when a
/// read began. An answer identical to the one before is kept as it was and posts nothing.
- (BOOL)want:(NSString *)bundleID;
/// Reads now and waits, for the CLI. Off main only.
- (MMInsidesAnswer *)readNow:(NSString *)bundleID;
/// Lets every answer go: the window closed.
- (void)forget;
/// How long a read may take, 1 s, and how often the window may ask, 5 s.
@property NSTimeInterval limit, every;
/// For the checks and the bench: reads, answers, reused, unreachable, older and skips since launch.
- (NSDictionary<NSString *, NSNumber *> *)stats;
@end

NS_ASSUME_NONNULL_END
