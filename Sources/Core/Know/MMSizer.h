// The clone-aware Sizer. Pattern P16 of SYNTHESIS.md section 1.2. PLAN.md section 3 lists it under Know.
// A size shown is what deleting frees. A pnpm node_modules that du calls 1.5 GB frees 2.8 MB.
#import <Foundation/Foundation.h>

/// P16. What one walk found.
typedef struct {
    uint64_t allocated;          // what du reports
    uint64_t freedIfDeleted;     // private bytes, with a clone id counted once when all its holders are in the set
    NSInteger files, errors;
} MMSize;

/// P16. Three tiers. Starts from NN internal/sizer, with getattrlistbulk as the periodic tier.
/// Walks run in the worker of P4 when the app calls them. The CLI may call them directly.
@interface MMSizer : NSObject
/// Tier 1, every periodic walk: getattrlistbulk with ATTR_CMNEXT_PRIVATESIZE and clone ids.
+ (MMSize)quick:(NSString *)root;
/// Tier 2, right before an action: NN's extent union through F_LOG2PHYS_EXT, over all roots together.
+ (uint64_t)exact:(NSArray<NSString *> *)roots;
/// Tier 3, for the undo record: free space on path's volume from statfs before and after action.
/// Returns the bytes freed, negative when the volume filled. action returns NO when it failed.
+ (int64_t)freedOnVolume:(NSString *)path by:(BOOL (^)(void))action;
@end
