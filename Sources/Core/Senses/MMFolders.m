// One FSEvents stream over a set of roots, with a saved event id. Pattern P15.
// The id lives in <support folder>/<name>.eventid. A watch with no saved id starts from now and saves
// the current id at once, so the next watch replays from there. It never passes 0.
#import "Core/Senses/MMFolders.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import <CoreServices/CoreServices.h>

static const CFTimeInterval kLatency = 0.5;
static const NSTimeInterval kSaveEvery = 2;   // seconds between event id writes while events flow
static char kQueueKey;                         // marks a watch queue, so stop can tell it runs on one
enum { kReplayKept = 256 };                    // how many of a replay's last event ids are kept, to tell a second delivery

@interface MMFolderWatch ()
@property (readwrite, copy) NSString *name;
@property (readwrite) NSArray<NSString *> *roots;
@property (copy) NSArray<NSString *> *skip;
@property (copy) void (^changed)(NSSet<NSString *> *dirs, BOOL rescan);
- (void)handle:(size_t)n paths:(char **)paths flags:(const FSEventStreamEventFlags *)flags
           ids:(const FSEventStreamEventId *)ids;
@end

static void Changed(ConstFSEventStreamRef s, void *info, size_t n, void *paths,
                    const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    [(__bridge MMFolderWatch *)info handle:n paths:(char **)paths flags:flags ids:ids];
}

@implementation MMFolderWatch {
    FSEventStreamRef _stream;
    dispatch_queue_t _q;
    FSEventStreamEventId _lastId;
    NSDate *_savedAt;
    // Issue #84: FSEvents may deliver an event of the replay a second time, with the same id, one latency after the
    // replay ended. In 100 restarts right after one change it did so 7 times. Each delivery dropped the worktree's
    // status, so git status ran twice for one change.
    BOOL _replaying;                               // from a start with a saved id until HistoryDone
    FSEventStreamEventId _replayed[kReplayKept];   // the ids the replay delivered last, as a ring
    size_t _replayedCount;                         // how many it delivered; 0 once the stream is past them
    FSEventStreamEventId _replayedMax;
}

- (NSString *)idPath {
    return [MMSupportDir() stringByAppendingPathComponent:[self.name stringByAppendingPathExtension:@"eventid"]];
}

- (FSEventStreamEventId)savedId {
    NSString *s = [NSString stringWithContentsOfFile:self.idPath encoding:NSUTF8StringEncoding error:nil];
    return (FSEventStreamEventId)strtoull(s.UTF8String ?: "0", NULL, 10);
}

- (void)saveId:(FSEventStreamEventId)eid {
    if (!eid) return;
    [[NSString stringWithFormat:@"%llu\n", eid] writeToFile:self.idPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    _savedAt = NSDate.date;
}

+ (instancetype)watch:(NSArray<NSString *> *)roots name:(NSString *)name skip:(NSArray<NSString *> *)skip
              changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed {
    MMFolderWatch *w = [MMFolderWatch new];
    w.roots = [roots copy] ?: @[]; w.name = name; w.skip = skip ?: @[]; w.changed = changed;
    return [w start] ? w : nil;
}

- (BOOL)start {
    if (!self.roots.count || !self.name.length) return NO;
    _q = MMQueue(@"core", self.name, QOS_CLASS_UTILITY);
    dispatch_queue_set_specific(_q, &kQueueKey, (__bridge void *)_q, NULL);
    FSEventStreamEventId since = [self savedId];
    if (!since) { since = kFSEventStreamEventIdSinceNow; [self saveId:FSEventsGetCurrentEventId()]; }
    _replaying = since != kFSEventStreamEventIdSinceNow;
    FSEventStreamContext ctx = { .info = (__bridge void *)self };
    _stream = FSEventStreamCreate(NULL, Changed, &ctx, (__bridge CFArrayRef)self.roots, since, kLatency,
                                  kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot);
    if (!_stream) return NO;
    FSEventStreamSetDispatchQueue(_stream, _q);
    if (!FSEventStreamStart(_stream)) { FSEventStreamInvalidate(_stream); FSEventStreamRelease(_stream); _stream = NULL; return NO; }
    return YES;
}

/// YES when the replay already delivered the event with this id, so this delivery is its second. Only the same id
/// counts, never a lower one, so no change is ever left out. The replay's own events are noted here.
/// A root change has id 0 and is never a second delivery.
- (BOOL)deliveredBefore:(FSEventStreamEventId)eid {
    if (!eid) return NO;
    if (_replaying) {
        _replayed[_replayedCount++ % kReplayKept] = eid;
        if (eid > _replayedMax) _replayedMax = eid;
        return NO;
    }
    if (!_replayedCount) return NO;
    if (eid > _replayedMax) { _replayedCount = 0; return NO; }   // the stream is past the replay
    for (size_t k = 0, n = MIN(_replayedCount, (size_t)kReplayKept); k < n; k++) if (_replayed[k] == eid) return YES;
    return NO;
}

/// YES when path lies inside a skipped folder, such as node_modules or .git/objects.
- (BOOL)skips:(NSString *)path {
    NSString *p = [path hasSuffix:@"/"] ? path : [path stringByAppendingString:@"/"];
    for (NSString *s in self.skip)
        if ([p rangeOfString:[NSString stringWithFormat:@"/%@/", s]].location != NSNotFound) return YES;
    return NO;
}

- (void)handle:(size_t)n paths:(char **)paths flags:(const FSEventStreamEventFlags *)flags
           ids:(const FSEventStreamEventId *)ids {
    NSMutableSet *dirs = [NSMutableSet new];
    BOOL rescan = NO;
    for (size_t i = 0; i < n; i++) {
        if (ids[i] > _lastId) _lastId = ids[i];
        FSEventStreamEventFlags f = flags[i];
        if (f & kFSEventStreamEventFlagHistoryDone) { _replaying = NO; continue; }
        if (f & kFSEventStreamEventFlagEventIdsWrapped) _replayedCount = 0;
        if ([self deliveredBefore:ids[i]]) continue;
        NSString *path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:paths[i] length:strlen(paths[i])];
        if (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
        if ([self skips:path]) continue;
        if (f & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
                 kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)) rescan = YES;
        [dirs addObject:path];
    }
    if (!_savedAt || -_savedAt.timeIntervalSinceNow >= kSaveEvery) [self saveId:_lastId];
    if (dirs.count && self.changed) self.changed(dirs, rescan);
}

- (void)stop {
    if (!_stream) return;
    FSEventStreamRef s = _stream;
    _stream = NULL;
    FSEventStreamStop(s);
    FSEventStreamInvalidate(s);
    // Callbacks run on _q, so waiting on it means none is running when the id is saved and the stream freed.
    void (^finish)(void) = ^{
        FSEventStreamEventId latest = FSEventStreamGetLatestEventId(s);
        [self saveId:MAX(latest, self->_lastId)];
        FSEventStreamRelease(s);
    };
    if (dispatch_get_specific(&kQueueKey) == (__bridge void *)_q) finish(); else dispatch_sync(_q, finish);
}

- (void)dealloc { [self stop]; }

#ifdef MM_TESTS
+ (instancetype)replayingWatchNamed:(NSString *)name changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed {
    MMFolderWatch *w = [MMFolderWatch new];
    w.roots = @[]; w.name = name; w.skip = @[]; w.changed = changed;
    w->_replaying = YES;
    return w;
}
#endif

@end
