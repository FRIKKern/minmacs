// The clutter catalog. Patterns P28 to P30 of SYNTHESIS.md section 1.3.
// The catalog is data in registry/clutter/*.json beside registry/agents/, checked against registry/clutter-schema.json.
// Ported from Noo-Noo 0.7: the leak signatures of internal/leaks, the safety walls of internal/core/safety.go,
// the build targets of internal/modules/dev and the trend math of internal/trend.
// Scans run on MMQueue(@"core", @"clutter"), at most as often as each row's "every" says, and never on the 5-second tick.
#import <Foundation/Foundation.h>
#import "Core/Know/MMSizer.h"

/// P28. The class of one clutter kind. Decision 1 decides how each class is removed:
/// a tool row through the tool's own command, build output and leftover temp folders to the Trash.
typedef NS_ENUM(NSInteger, MMClutterClass) {
    MMClutterCache,     // a cache an app rebuilds, such as ~/Library/Caches/<app>
    MMClutterTool,      // owned by a tool with its own cleanup command, such as the pnpm store
    MMClutterBuild,     // build output inside a project, such as .next or DerivedData
    MMClutterData,      // user data an owner keeps, such as Claude Code transcripts; report only
    MMClutterLeak,      // a leftover from an agent or tool that is gone, such as a temp folder
    MMClutterReport,    // shown with its size and the owner's own command, never acted on, such as the Trash
};
NSString *MMClutterClassName(MMClutterClass c);          // cache, tool, build, data, leak, report

/// P28. One row of registry/clutter/*.json.
/// Starts from NN's knowledge, seeded from the 52 rows of research track D, plus three leak rows of NN's signatures.
@interface MMClutterKind : NSObject
@property (readonly, copy) NSString *kindID, *title, *group;
@property (readonly) MMClutterClass klass;
@property (readonly) NSArray<NSString *> *paths;        // globs with ~ and ${...} expanded, see P30
@property (readonly) NSArray<NSString *> *names;        // folder names found inside the projects, such as node_modules
@property (readonly) NSArray<NSString *> *beside;       // one of these must sit next to a named folder, such as package.json
@property (readonly) NSArray<NSString *> *never;        // protected paths this row must never touch
@property (readonly) NSArray<NSString *> *quitFirst;    // bundle ids to quit before the cache is cleared
@property (readonly, copy) NSString *cleanup, *dryRun;  // the tool's command and its dry-run form, for MMClutterTool
@property (readonly) NSArray<NSString *> *cleanupArgs, *dryRunArgs;   // the same as argv; dryRunArgs nil when there is none
@property (readonly, copy) NSString *ownerSetting;      // for MMClutterData: "Claude Code keeps transcripts for 30 days"
@property (readonly, copy) NSString *owner;             // how the owner is found: project, session, derived-data, ...
@property (readonly, copy) NSString *rebuild, *advice, *workaround;
@property (readonly) BOOL reportOnly;                   // such as the root-owned simulator dyld cache
@property (readonly) BOOL skipWhenTracked;              // dist and build are skipped when git tracks them
@property (readonly) BOOL walk;                         // NO for a mount that must never be walked, such as simulator runtimes
/// NN's leak signature: "agent-scratch", "open", "aged" or "family". nil for a row with none.
@property (readonly, copy) NSString *signature;
@property (readonly) NSTimeInterval minAge;             // the newest file must be this old before a leak goes
@property (readonly) NSTimeInterval every;              // the shortest time between two scans of this row
@property (readonly) NSDictionary *json;
@end

/// What holds an item back right now. Read on the scan and again right before every action.
typedef NS_ENUM(NSInteger, MMClutterState) {
    MMClutterFree,      // its row lets it go and nothing holds it
    MMClutterLive,      // in use: a file open, a session alive, written too recently
    MMClutterKept,      // never acted on: data, report only, tracked by git, owned by root
};

/// The growth of one row's total size, from Noo-Noo's trend math: one point per day, a least-squares fit,
/// and the ratio of the newest point to the first point of the last week.
typedef struct {
    BOOL ok;                     // NO with fewer than two days
    double bytesPerDay;          // the slope; negative when it shrinks
    NSInteger windowDays, points;
    double firstBytes, lastBytes;
    double weekRatio;            // newest over the first point of the last 7 days, 0 when unknown
} MMClutterTrend;

/// P28 and P29. One thing found on disk that matches a kind.
@interface MMClutterItem : NSObject
@property (readonly) MMClutterKind *kind;
@property (readonly, copy) NSString *path;              // a family is named root/prefix-*, its members are in members
@property (readonly) NSArray<NSString *> *members;      // what a family holds, or the one path
/// P29. The project or install this item belongs to, from a back-link in the tool's own files:
/// DerivedData info.plist WorkspacePath, Playwright .links, pnpm .modules.yaml storeDir, simulator device.plist.
/// For build output the checkout that holds it. nil when the tool keeps no back-link.
@property (readonly, copy) NSString *ownerPath;
@property (readonly) BOOL ownerGone;                    // the back-link points at a path that is gone
@property (readonly, copy) NSString *sessionID;         // an agent session the item belongs to, or nil
@property (readonly) MMSize size;
@property (readonly) NSDate *lastUsed;                  // the newest modification in the tree
@property (readonly) MMClutterState state;
@property (readonly, copy) NSString *why;               // why it is live or kept, or why it may go
@property (readonly) MMClutterTrend trend;              // the growth of this item's row
/// "node-modules:/path/to/node_modules", stable across scans.
- (NSString *)key;
- (NSDictionary *)json;
@end

/// Posted on the catalog's queue after a scan changed the items.
extern NSNotificationName const MMClutterDidChangeNotification;

/// P28 and P30. The loaded rows, and the paths they resolve to on this Mac.
@interface MMClutterCatalog : NSObject
+ (instancetype)shared;                                 // bundled rows, then the user's rows
/// Rows from these folders, later folders winning. Tests pass their own.
- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs;
@property (readonly) NSArray<MMClutterKind *> *kinds;
- (MMClutterKind *)kind:(NSString *)kindID;
/// The checkouts that build rows look in. MMCoreStart hands over the repo index's worktrees before every scan.
@property (copy) NSArray<NSString *> *projects;
@property (copy) NSArray<NSString *> *(^projectsProvider)(void);
/// YES in the app, where sizes come from MMSharedWorker. The CLI and tests size in process.
@property BOOL sizeWithWorker;
/// Scans every row now and returns the items. Blocks. Sizes come from MMSizer quick through the worker.
- (NSArray<MMClutterItem *> *)scan;
/// Scans only the rows whose last scan is older than their "every". Blocks. Returns YES when items changed.
- (BOOL)scanDue;
/// The items of the last scans, kept in Store/core/clutter.json across launches. Any queue, never blocks.
@property (readonly) NSArray<MMClutterItem *> *items;
/// When the newest row scan ended, or nil before the first.
@property (readonly) NSDate *lastScan;
/// The item at this path read again from disk, with its state and size, or nil when it is gone. Blocks.
- (MMClutterItem *)inspect:(MMClutterItem *)item;
/// The row that lists path, or nil when no row does.
- (MMClutterKind *)kindFor:(NSString *)path;
/// Why path must not be touched, or nil when it may. Only a path a listed row names may ever be acted on.
/// /System, /Library, /usr, /bin, /sbin, /private/etc, the home folder, its parents and its first level, the
/// support folder, a symlink, a path of another user and anything a row's "never" protects are always refused.
/// kind nil looks the row up with kindFor:.
- (NSString *)whyNot:(NSString *)path kind:(MMClutterKind *)kind;
/// Starts the scan timer on MMQueue(@"core", @"clutter"): due rows a few minutes after launch, then every 5 minutes.
- (void)start;
- (void)stop;
/// Forgets the times of the last scans, so the next scanDue scans every row.
- (void)forgetScanTimes;
@end

/// P30. A tool's cache folder, read from env vars and config files, never by running the tool.
/// New code. Running `yarn cache dir` started Corepack and downloaded Yarn during research track D.
/// tool is a row's id, such as "npm", "pnpm", "yarn", "uv" or "go". nil when nothing says where it is.
NSString *MMCachePathOf(NSString *tool);

/// The home folder the catalog reads. The person's own, or, in a test, $MINMACS_CLUTTER_ROOT/home.
/// With MINMACS_HOME set and no MINMACS_CLUTTER_ROOT inside it, nil, so a test never scans the person's files.
NSString *MMClutterHome(void);
/// "" for the person's Mac, or the folder inside MINMACS_HOME that stands in for / in a test.
NSString *MMClutterRoot(void);
/// A row's path pattern with ~, ${cache:<tool>}, ${claude}, ${codex} and ${support} expanded and, in a test, rebased.
NSString *MMClutterExpand(NSString *pattern);
/// The binary of a tool command, such as xcrun or pnpm, from the usual install folders. In a test only $MINMACS_TOOLS.
NSString *MMClutterToolPath(NSString *name);

/// Noo-Noo's trend math, internal/trend. points holds packed MMTrendPoint values from -[MMLog points:since:],
/// oldest first. One point per day is kept, the last of the day, before the fit.
MMClutterTrend MMClutterTrendOf(NSData *points, NSDate *now);
/// The trend series of one row in the log, such as "noonoo.disk.pnpm-store".
NSString *MMClutterSeries(NSString *kindID);

/// The paths among roots that a process of this user holds open, as its cwd, its executable or an open file.
/// libproc's own reads, the in-process form of NN's `lsof +D`. Blocks, so only scans and actions call it.
NSSet<NSString *> *MMOpenUnder(NSArray<NSString *> *roots);
