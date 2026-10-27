// The clutter catalog. Patterns P28 to P30 of SYNTHESIS.md section 1.3.
// The catalog is data in registry/clutter/*.json beside registry/agents/, with a schema.
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
};

/// P28. One row of registry/clutter/*.json.
/// Starts from NN's knowledge, seeded from the 52 rows of research track D.
@interface MMClutterKind : NSObject
@property (readonly, copy) NSString *kindID, *title;
@property (readonly) MMClutterClass klass;
@property (readonly) NSArray<NSString *> *paths;        // globs with ~ and ${ENV} expanded, see P30
@property (readonly) NSArray<NSString *> *never;        // protected paths this row must never touch
@property (readonly) NSArray<NSString *> *quitFirst;    // bundle ids to quit before the cache is cleared
@property (readonly, copy) NSString *cleanup, *dryRun;  // the tool's command and its dry-run form, for MMClutterTool
@property (readonly, copy) NSString *ownerSetting;      // for MMClutterData: "Claude Code keeps transcripts for 30 days"
@property (readonly) BOOL reportOnly;                   // such as the root-owned simulator dyld cache
@property (readonly) BOOL skipWhenTracked;              // dist and build are skipped when git tracks them
@property (readonly) NSDictionary *json;
@end

/// P28 and P29. One thing found on disk that matches a kind.
@interface MMClutterItem : NSObject
@property (readonly) MMClutterKind *kind;
@property (readonly, copy) NSString *path;
/// P29. The project or install this item belongs to, from a back-link in the tool's own files:
/// DerivedData info.plist WorkspacePath, Playwright .links, pnpm .modules.yaml storeDir, simulator device.plist.
/// New code. nil when the tool keeps no back-link.
@property (readonly, copy) NSString *ownerPath;
@property (readonly) BOOL ownerGone;                    // the back-link points at a path that is gone
@property (readonly) MMSize size;
@property (readonly) NSDate *lastUsed;
@end

/// P28 and P30. The loaded rows, and the paths they resolve to on this Mac.
@interface MMClutterCatalog : NSObject
+ (instancetype)shared;                                 // bundled rows, then the user's rows
@property (readonly) NSArray<MMClutterKind *> *kinds;
- (MMClutterKind *)kind:(NSString *)kindID;
/// The items under each kind's paths. Sizes come from MMSizer quick through the worker.
- (NSArray<MMClutterItem *> *)scan;
@end

/// P30. A tool's cache folder, read from env vars and config files, never by running the tool.
/// New code. Running `yarn cache dir` started Corepack and downloaded Yarn during research track D.
/// tool is a row's id, such as "npm", "pnpm", "yarn", "uv" or "go". nil when nothing says where it is.
NSString *MMCachePathOf(NSString *tool);
