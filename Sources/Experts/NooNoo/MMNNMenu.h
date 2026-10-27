// Noo-Noo's menu and cards as specs, from a plain view of the clutter. Pure: it reads no disk, graph or clock
// beyond what the view holds, so tools/render.m draws it from fixture rows and the expert draws it from the graph.
#import <Foundation/Foundation.h>
#import "Core/MMExpert.h"

/// Where a row sits in the menu.
typedef NS_ENUM(NSInteger, MMNNSection) {
    MMNNFinished,       // build output of a finished project: merged, its remote branch deleted, or its owner gone
    MMNNLeftovers,      // leftovers from agents and tools that nothing uses
    MMNNCaches,         // caches, tool stores and build output of active projects
    MMNNKept,           // in use now, or data its owner keeps
};

/// One clutter item as the menu shows it.
@interface MMNNRow : NSObject
@property (copy) NSString *findingID, *kindID;
@property (copy) NSString *name;                        // "node_modules", "pip cache"
@property (copy) NSString *kindTitle;                   // the row's title
@property (copy) NSString *owner;                       // "checkout-flow", or nil
@property (copy) NSString *ownerState;                  // "squash-merged", "remote branch deleted", or nil while active
@property (copy) NSString *ownerLinkExpert, *ownerLinkID;   // WorkForest's card of the owner's worktree
@property (copy) NSString *path;                        // shown with ~
@property MMNNSection section;
@property uint64_t freed, allocated;
@property (strong) NSDate *lastUsed;
@property BOOL live, kept;                              // live: in use now; kept: never acted on
@property (copy) NSString *why;                         // why it stays, or why it may go
@property (copy) NSString *rebuild, *ownerSetting;
@property (copy) NSString *actionTitle;                 // "Move to Trash", "Clean with pnpm"; nil when it never applies
@property (copy) NSString *undoWords;                   // "Undo moves it back from the Trash."
@property BOOL goesOnItsOwn;                            // the mode takes it at the next review
@property NSInteger members;                            // folders in a temp family, 1 otherwise
@property BOOL folder;                                  // a named build folder inside a project, such as node_modules
@end

/// What the menu acts with. Every block runs on main. Any of them may be nil, as in the render tool.
@interface MMNNHandlers : NSObject
@property (copy) void (^clean)(NSArray<NSString *> *findingIDs);
@property (copy) void (^keep)(NSString *findingID);
@property (copy) void (^reveal)(NSString *findingID);
@property (copy) void (^restoreLast)(void);
@property (copy) void (^scanNow)(void);
@end

/// The whole menu's input.
@interface MMNNView : NSObject
@property (copy) NSArray<MMNNRow *> *rows;
@property (copy) NSString *growthLine;                  // "The pnpm store grew 9.0 GB in 14 days.", or nil
@property uint64_t trashBytes;                          // what the Trash holds, 0 when unknown
@property (copy) NSString *modeName;                    // "Proactive"
@property NSTimeInterval watchingLeft;                  // seconds before the mode may act, 0 once it may
@property NSInteger restorable;                         // records Undo can take back
@property (strong) NSDate *lastClean, *lastScan;
@end

MMMenuSpec *MMNNMenuFor(MMNNView *view, MMNNHandlers *handlers);
MMCardSpec *MMNNCardFor(MMNNRow *row, MMNNView *view, MMNNHandlers *handlers);
/// The status item's accessibility state, such as "3 finished projects, 6.1 GB to free".
NSString *MMNNAccessibility(MMNNView *view);
/// The growth line for a row's trend: ok, bytes per day, window in days, first and last bytes, the week ratio.
/// nil when it does not grow fast: less than minBytes over the window, or slower than doubling in a week and
/// than minBytes a week. Ported from NN's cache_velocity heuristic and trend fit.
NSString *MMNNGrowthLine(NSString *title, BOOL ok, double bytesPerDay, NSInteger windowDays, double firstBytes,
                         double lastBytes, double weekRatio, double minBytes);
