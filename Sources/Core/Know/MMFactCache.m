// MMFactCache, pattern P27. It starts from WorkForest's facts.json, keyed by HEAD, and LocoHost's LHIntel read,
// which returns the old answer now and computes a fresh one in the background.
#import "Core/Know/MMFactCache.h"

/// The support folder: $MINMACS_HOME, or ~/Library/Application Support/MinMacs. Made on first use.
/// Know's own copy of MMSupportDir from Store, so Know links before Store lands. MMRegistry and MMSessions use it too.
NSString *MMKnowSupportDir(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    NSString *dir = home.length ? home
        : [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
           stringByAppendingPathComponent:@"MinMacs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

/// A labeled serial queue with an autorelease pool per block, as MMQueue in Runtime makes.
/// Know's own copy, so Know links before Runtime lands. Each label is made once.
dispatch_queue_t MMKnowQueue(NSString *job) {
    static NSMutableDictionary<NSString *, dispatch_queue_t> *queues;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queues = [NSMutableDictionary new]; });
    NSString *label = [@"no.guerrilla.minmacs.core." stringByAppendingString:job];
    @synchronized (queues) {
        dispatch_queue_t q = queues[label];
        if (!q) {
            dispatch_queue_attr_t a = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL,
                                                                                         DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
            a = dispatch_queue_attr_make_with_qos_class(a, QOS_CLASS_UTILITY, 0);
            q = dispatch_queue_create(label.UTF8String, a);
            queues[label] = q;
        }
        return q;
    }
}

@implementation MMFactCache {
    NSTimeInterval _maxAge;
    BOOL _persist;
    NSMutableDictionary<NSString *, NSDictionary *> *_entries;   // key: {fp, at, value}
    NSMutableSet<NSString *> *_pending;
    dispatch_queue_t _queue;
    BOOL _saveQueued;
}

- (instancetype)initWithName:(NSString *)name maxAge:(NSTimeInterval)maxAge persist:(BOOL)persist {
    if ((self = [super init])) {
        _name = [name copy];
        _maxAge = maxAge;
        _persist = persist;
        _entries = [NSMutableDictionary new];
        _pending = [NSMutableSet new];
        _queue = MMKnowQueue([@"cache." stringByAppendingString:name]);
        if (persist) [self load];
    }
    return self;
}

- (NSString *)path { return [MMKnowSupportDir() stringByAppendingPathComponent:[_name stringByAppendingPathExtension:@"json"]]; }

- (void)load {
    NSData *d = [NSData dataWithContentsOfFile:self.path];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) return;
    for (NSString *k in j) {
        NSDictionary *e = j[k];
        if (![e isKindOfClass:NSDictionary.class] || ![e[@"fp"] isKindOfClass:NSString.class] || !e[@"value"]) continue;
        _entries[k] = @{ @"fp": e[@"fp"], @"at": [NSDate dateWithTimeIntervalSince1970:[e[@"at"] doubleValue]], @"value": e[@"value"] };
    }
}

/// Writes the cache once per burst of changes, on the cache's queue.
- (void)saveSoon {
    if (!_persist || _saveQueued) return;
    _saveQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), _queue, ^{ [self save]; });
}

/// Writes the cache now when it changed since the last write. Values that JSON cannot hold are left out.
- (void)save {
    if (!_persist) return;
    NSMutableDictionary *out = [NSMutableDictionary new];
    @synchronized (self) {
        if (!_saveQueued) return;
        _saveQueued = NO;
        for (NSString *k in _entries) {
            NSDictionary *e = _entries[k];
            if (![NSJSONSerialization isValidJSONObject:@[e[@"value"]]]) continue;
            out[k] = @{ @"fp": e[@"fp"], @"at": @([e[@"at"] timeIntervalSince1970]), @"value": e[@"value"] };
        }
    }
    [[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] writeToFile:self.path atomically:YES];
}

- (void)store:(id)value key:(NSString *)key fingerprint:(NSString *)fp {
    @synchronized (self) {
        if (value) _entries[key] = @{ @"fp": fp ?: @"", @"at": NSDate.date, @"value": value };
        else [_entries removeObjectForKey:key];
        [self saveSoon];
    }
}

- (id)valueFor:(NSString *)key fingerprint:(NSString *)fingerprint orCompute:(id (^)(void))work wait:(BOOL)wait {
    if (!key) return nil;
    NSDictionary *e;
    @synchronized (self) { e = _entries[key]; }
    BOOL fresh = e && [e[@"fp"] isEqualToString:fingerprint ?: @""] && (_maxAge <= 0 || -[e[@"at"] timeIntervalSinceNow] < _maxAge);
    if (fresh || !work) return e[@"value"];
    if (wait) {
        id v = work();
        [self store:v key:key fingerprint:fingerprint];
        return v;
    }
    @synchronized (self) {
        if (![_pending containsObject:key]) {
            [_pending addObject:key];
            NSString *fp = [fingerprint copy];
            dispatch_async(_queue, ^{
                id v = work();
                [self store:v key:key fingerprint:fp];
                @synchronized (self) { [self->_pending removeObject:key]; }
            });
        }
    }
    return e[@"value"];
}

- (id)peek:(NSString *)key {
    @synchronized (self) { return key ? _entries[key][@"value"] : nil; }
}

- (BOOL)changed:(NSString *)key fingerprint:(NSString *)fingerprint {
    @synchronized (self) {
        NSDictionary *e = key ? _entries[key] : nil;
        return !e || ![e[@"fp"] isEqualToString:fingerprint ?: @""];
    }
}

- (void)forget:(NSSet<NSString *> *)liveKeys {
    @synchronized (self) {
        NSUInteger before = _entries.count;
        for (NSString *k in _entries.allKeys) if (![liveKeys containsObject:k]) [_entries removeObjectForKey:k];
        if (_entries.count != before) [self saveSoon];
    }
}

/// Waits until every background compute and save queued so far has finished. For tests and the CLI.
- (void)drain {
    dispatch_sync(_queue, ^{});
    usleep(250000);
    dispatch_sync(_queue, ^{});
}

@end
