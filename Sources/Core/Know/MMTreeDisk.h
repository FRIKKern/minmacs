// What one checkout holds on disk, and when its files last changed. Part of P16, the Sizer, for worktrees.
// WorkForest reads these facts to say what removing a worktree frees and whether someone still works in it.
// Starts from WalkDisk in WF Trees.m:296. One walk per worktree on Core's own queue, never on main.
#import <Foundation/Foundation.h>

/// P16. One walk of one checkout. The walk skips .git, nested repos and worktrees, and follows no symlink.
@interface MMTreeDiskFacts : NSObject
@property (readonly) uint64_t allocated;               // what du says
@property (readonly) uint64_t freed;                   // what deleting frees, from +[MMSizer quick:]
@property (readonly) uint64_t cacheBytes;              // the part in cache folders such as node_modules
@property (readonly) NSInteger files;
/// The newest file or folder change outside .git and the caches. A folder's time counts, so a deleted file shows.
@property (readonly) NSDate *touched;
@property (readonly) NSDate *created;                  // when the checkout's .git was made
@property (readonly) NSDate *at;                       // when the walk ran
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

/// How fresh an answer must be.
typedef NS_ENUM(NSInteger, MMTreeDiskRead) {
    MMTreeDiskCached,      // never blocks: the last walk, possibly stale, or nil; a stale one walks again in the background
    MMTreeDiskFresh,       // blocks when the last walk is older than 15 minutes, or the folder itself changed since
    MMTreeDiskNow,         // always walks now, as right before an action
};

/// P16. The walks, kept in Store/treedisk.json across launches.
@interface MMTreeDisk : NSObject
+ (instancetype)shared;
/// Folder names whose files are rebuildable. Their size counts as cacheBytes and their changes are not work.
@property (copy) NSArray<NSString *> *cacheNames;
- (MMTreeDiskFacts *)factsFor:(NSString *)path read:(MMTreeDiskRead)read;
/// Drops the walks of checkouts that are gone.
- (void)forget:(NSSet<NSString *> *)livePaths;
@end
/// Posted on the disk queue when a background walk finished with new facts.
extern NSNotificationName const MMTreeDiskDidChangeNotification;
