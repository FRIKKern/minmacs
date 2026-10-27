// Folder watching with FSEvents. Pattern P15 of SYNTHESIS.md section 1.2.
#import <Foundation/Foundation.h>

/// P15. One FSEvents stream over a set of roots, with a saved event id.
/// New code. The last event id is saved to Store/<name>.eventid, and a new watch replays from there, never from 0.
/// Passing 0 replayed 494,887 events in 93 seconds in research track B.
/// Folders named in skip, such as node_modules and .git/objects, are filtered in the callback,
/// because FSEvents takes at most 8 exclusion paths.
/// rescan is YES when FSEvents set MustScanSubDirs for a folder. Then only that folder is walked again.
/// changed runs on MMQueue(@"core", name), never on main.
@interface MMFolderWatch : NSObject
+ (instancetype)watch:(NSArray<NSString *> *)roots name:(NSString *)name skip:(NSArray<NSString *> *)skip
              changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed;
@property (readonly, copy) NSString *name;
@property (readonly) NSArray<NSString *> *roots;
- (void)stop;
@end
