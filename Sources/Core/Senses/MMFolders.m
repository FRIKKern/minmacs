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
    FSEventStreamContext ctx = { .info = (__bridge void *)self };
    _stream = FSEventStreamCreate(NULL, Changed, &ctx, (__bridge CFArrayRef)self.roots, since, kLatency,
                                  kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot);
    if (!_stream) return NO;
    FSEventStreamSetDispatchQueue(_stream, _q);
    if (!FSEventStreamStart(_stream)) { FSEventStreamInvalidate(_stream); FSEventStreamRelease(_stream); _stream = NULL; return NO; }
    return YES;
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
        if (f & kFSEventStreamEventFlagHistoryDone) continue;
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

@end
