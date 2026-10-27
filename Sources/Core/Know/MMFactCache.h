// The fact cache. Pattern P27 of SYNTHESIS.md section 1.3.
// Git facts, sizes and review fingerprints all use this one object.
#import <Foundation/Foundation.h>

/// P27. Values keyed by a subject and checked against a fingerprint, such as HEAD for git facts.
/// Starts from WF facts.json, keyed by HEAD, with LocoHost's read that returns stale now and fresh later.
/// A value whose fingerprint still matches is used until maxAge. With wait NO a miss returns the old value,
/// or nil, and computes in the background on the cache's own queue. With wait YES it computes now.
/// persist YES keeps the cache in Store/<name>.json across launches.
@interface MMFactCache<V> : NSObject
- (instancetype)initWithName:(NSString *)name maxAge:(NSTimeInterval)maxAge persist:(BOOL)persist;
@property (readonly, copy) NSString *name;
- (V)valueFor:(NSString *)key fingerprint:(NSString *)fingerprint orCompute:(V (^)(void))work wait:(BOOL)wait;
/// The cached value whatever its fingerprint, or nil.
- (V)peek:(NSString *)key;
/// YES when key has no value, or its value was made for another fingerprint.
- (BOOL)changed:(NSString *)key fingerprint:(NSString *)fingerprint;
/// Stores value for key now, made for fingerprint. nil removes the key.
- (void)setValue:(V)value for:(NSString *)key fingerprint:(NSString *)fingerprint;
/// Removes key, so the next read computes it again. A persisted cache forgets it across launches too.
- (void)drop:(NSString *)key;
/// Drops every key not in liveKeys, so the cache does not grow with subjects that are gone.
- (void)forget:(NSSet<NSString *> *)liveKeys;
@end
