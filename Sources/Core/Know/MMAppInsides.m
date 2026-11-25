// What an app knows of its insides, asked only on demand, MMAppInsides.h.
#import "Core/Know/MMAppInsides.h"
#import "Core/Runtime/MMRuntime.h"

NSNotificationName const MMAppInsidesDidChangeNotification = @"MMAppInsidesDidChange";

static id Or(id v) { return v ?: NSNull.null; }

@implementation MMInsidesNode
- (NSDictionary *)json {
    NSMutableArray *kids = [NSMutableArray new];
    for (MMInsidesNode *c in self.children) [kids addObject:c.json];
    return @{@"kind": self.kind ?: @"", @"ref": self.ref ?: @"", @"uid": Or(self.uid), @"title": self.title ?: @"", @"pid": @(self.pid),
             @"tty": Or(self.tty), @"type": Or(self.type), @"url": Or(self.url), @"cpuPercent": @(round(self.cpuPercent * 10) / 10),
             @"bytes": @(self.bytes), @"selected": @(self.selected), @"status": Or(self.status), @"children": kids};
}
/// The parts that say what it is, not what it uses now.
- (void)stampInto:(NSMutableString *)s {
    [s appendFormat:@"%@|%@|%@|%d|%@|%d|%@|%@(", self.kind, self.ref, self.title, self.pid, self.status ?: @"", self.selected, self.url ?: @"", self.type ?: @""];
    for (MMInsidesNode *c in self.children) [c stampInto:s];
    [s appendString:@")"];
}
@end

@implementation MMInsidesAnswer
- (NSString *)stamp {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%ld|%@|", (long)self.known, self.why ?: @""];
    [self.root stampInto:s];
    return s;
}
- (NSDictionary *)json {
    NSString *known = @[@"nothing", @"found", @"unreachable", @"older"][(NSUInteger)MAX(0, MIN(self.known, MMInsidesOlder))];
    return @{@"app": self.app ?: @"", @"known": known, @"looking": @(self.looking), @"why": Or(self.why),
             @"at": self.at ? @(self.at.timeIntervalSince1970) : NSNull.null, @"root": Or(self.root.json)};
}
@end

@implementation MMAppInsides {
    // All under @synchronized (self). A read runs on the queue, outside the lock.
    NSMutableDictionary<NSString *, MMInsidesAnswer *> *_answers;   // by bundle id
    NSMutableDictionary<NSString *, NSDate *> *_asked;              // when each app's last read began
    NSMutableSet<NSString *> *_running;
    NSMutableDictionary<NSString *, NSNumber *> *_stats;
}

+ (instancetype)shared {
    static MMAppInsides *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMAppInsides new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _limit = 1; _every = 5;
        _answers = [NSMutableDictionary new]; _asked = [NSMutableDictionary new]; _running = [NSMutableSet new]; _stats = [NSMutableDictionary new];
    }
    return self;
}

+ (id<MMAppInsidesReader>)readerFor:(NSString *)bundleID {
    if ([bundleID isEqualToString:MMAppInsidesCmux]) return [MMCmuxInsides new];
    return nil;
}

static dispatch_queue_t Queue(void) { return MMQueue(@"core", @"insides", QOS_CLASS_UTILITY); }

- (void)count:(NSString *)what { @synchronized (self) { _stats[what] = @([_stats[what] integerValue] + 1); } }
- (NSDictionary *)stats { @synchronized (self) { return [_stats copy]; } }

- (MMInsidesAnswer *)knownFor:(NSString *)bundleID {
    if (!bundleID) return nil;
    @synchronized (self) {
        MMInsidesAnswer *a = _answers[bundleID];
        BOOL looking = [_running containsObject:bundleID];
        if (!looking || !a) return a ?: (looking ? [self lookingFor:bundleID] : nil);
        MMInsidesAnswer *x = [MMInsidesAnswer new];
        x.known = a.known; x.root = a.root; x.at = a.at; x.why = a.why; x.app = a.app; x.looking = YES;
        return x;
    }
}

- (MMInsidesAnswer *)lookingFor:(NSString *)bundleID {
    MMInsidesAnswer *x = [MMInsidesAnswer new];
    x.app = [MMAppInsides readerFor:bundleID].appName ?: @""; x.looking = YES;
    return x;
}

/// Keeps a's answer unless it is the same insides as the one kept. YES when what is known changed.
- (BOOL)take:(MMInsidesAnswer *)a for:(NSString *)bundleID {
    @synchronized (self) {
        MMInsidesAnswer *old = _answers[bundleID];
        if (old && [old.stamp isEqualToString:a.stamp]) { old.at = a.at ?: old.at; [self count:@"reused"]; return NO; }
        _answers[bundleID] = a;
        return YES;
    }
}

- (BOOL)want:(NSString *)bundleID {
    id<MMAppInsidesReader> reader = [MMAppInsides readerFor:bundleID];
    if (!reader) return NO;
    NSDate *now = NSDate.date;
    @synchronized (self) {
        NSDate *at = _asked[bundleID];
        if ([_running containsObject:bundleID] || (at && [now timeIntervalSinceDate:at] < self.every)) { [self count:@"skips"]; return NO; }
        _asked[bundleID] = now;
        [_running addObject:bundleID];
    }
    NSTimeInterval limit = self.limit;
    dispatch_async(Queue(), ^{
        [self count:@"reads"];
        MMInsidesAnswer *a = [reader readWithin:limit];
        [self count:a.known == MMInsidesFound ? @"answers" : a.known == MMInsidesOlder ? @"older" : @"unreachable"];
        [self take:a for:bundleID];
        @synchronized (self) { [self->_running removeObject:bundleID]; }
        // The look ended either way: the story no longer says it is looking.
        [NSNotificationCenter.defaultCenter postNotificationName:MMAppInsidesDidChangeNotification object:bundleID];
    });
    return YES;
}

- (MMInsidesAnswer *)readNow:(NSString *)bundleID {
    id<MMAppInsidesReader> reader = [MMAppInsides readerFor:bundleID];
    if (!reader || NSThread.isMainThread) return nil;
    [self count:@"reads"];
    MMInsidesAnswer *a = [reader readWithin:self.limit];
    [self count:a.known == MMInsidesFound ? @"answers" : a.known == MMInsidesOlder ? @"older" : @"unreachable"];
    [self take:a for:bundleID];
    return [self knownFor:bundleID] ?: a;
}

- (void)forget {
    @synchronized (self) { [_answers removeAllObjects]; [_asked removeAllObjects]; }
}

@end
