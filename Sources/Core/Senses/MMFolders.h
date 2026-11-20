// Folder watching with FSEvents. Pattern P15 of SYNTHESIS.md section 1.2.
#import <Foundation/Foundation.h>

/// P15. One FSEvents stream over a set of roots, with a saved event id.
/// New code. The last event id is saved to Store/<name>.eventid, and a new watch replays from there, never from 0.
/// Passing 0 replayed 494,887 events in 93 seconds in research track B.
/// Folders named in skip, such as node_modules and .git/objects, are filtered in the callback,
/// because FSEvents takes at most 8 exclusion paths.
/// rescan is YES when FSEvents set MustScanSubDirs for a folder. Then only that folder is walked again.
/// changed runs on MMQueue(@"core", name), never on main.
/// FSEvents may deliver an event of the replay a second time, with the same id. The second one is not passed on.
@interface MMFolderWatch : NSObject
+ (instancetype)watch:(NSArray<NSString *> *)roots name:(NSString *)name skip:(NSArray<NSString *> *)skip
              changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed;
@property (readonly, copy) NSString *name;
@property (readonly) NSArray<NSString *> *roots;
- (void)stop;
@end

#ifdef MM_TESTS
#import <CoreServices/CoreServices.h>
/// Compiled only with -DMM_TESTS. A watch with no stream, as one is right after a start with a saved id, and the
/// stream's callback, so a check hands it the batches FSEvents would. Issue #84.
@interface MMFolderWatch (Checks)
+ (instancetype)replayingWatchNamed:(NSString *)name changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed;
- (void)handle:(size_t)n paths:(char **)paths flags:(const FSEventStreamEventFlags *)flags ids:(const FSEventStreamEventId *)ids;
@end
#endif
