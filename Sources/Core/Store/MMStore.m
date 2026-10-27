// The support folder, prefs, rules files and state files. Patterns P34 to P37.
// Ported from LocoHost's LHSupportDir and SaveActivity, WorkForest's WFRules and WFPref, and MinMacs 1.2's wildcards.
#import "Core/Store/MMStore.h"
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

NSString *const MMPrefsDomain = @"no.guerrilla.minmacs";
NSString *const MMReviewModelKey = @"review.model";
NSString *const MMOneIconKey = @"core.oneIcon";

#pragma mark Folders

static NSString *MakeDir(NSString *dir) {
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

NSString *MMSupportDir(void) {
    // Read each time, so a test that sets MINMACS_HOME after launch still gets its own folder.
    NSString *env = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (env.length) return MakeDir(env);
    return MakeDir([NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"]);
}

NSString *MMExpertDir(NSString *expert) {
    return MakeDir([MMSupportDir() stringByAppendingPathComponent:expert.length ? expert : @"core"]);
}

#pragma mark Prefs

NSString *MMPrefsTarget(void) {
    NSString *env = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (!env.length) return MMPrefsDomain;
    // CFPreferences takes an absolute plist path in place of a domain. The test prefs stay inside MINMACS_HOME.
    return [MakeDir([env stringByAppendingPathComponent:@"Preferences"]) stringByAppendingPathComponent:@"no.guerrilla.minmacs.plist"];
}

static BOOL IsFileTarget(NSString *t) { return [t hasPrefix:@"/"]; }

id MMPref(NSString *key) {
    if (!key.length) return nil;
    CFStringRef t = (__bridge CFStringRef)MMPrefsTarget();
    // A plist target has no cfprefsd to share changes between processes, so it is read fresh.
    if (IsFileTarget((__bridge NSString *)t)) CFPreferencesAppSynchronize(t);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, t));
}

void MMSetPref(NSString *key, id value) {
    if (!key.length) return;
    CFStringRef t = (__bridge CFStringRef)MMPrefsTarget();
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, t);
    CFPreferencesAppSynchronize(t);
}

BOOL MMPrefBool(NSString *key, BOOL dflt) {
    id v = MMPref(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : dflt;
}

NSInteger MMPrefInt(NSString *key, NSInteger dflt) {
    id v = MMPref(key);
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : dflt;
}

double MMPrefDouble(NSString *key, double dflt) {
    id v = MMPref(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : dflt;
}

NSString *MMPrefString(NSString *key, NSString *dflt) {
    id v = MMPref(key);
    return [v isKindOfClass:NSString.class] && [v length] ? v : dflt;
}

NSString *MMIconVisibleKey(NSString *expert) {
    return [@"NSStatusItem Visible minmacs." stringByAppendingString:expert.lowercaseString ?: @""];
}

BOOL MMIconVisible(NSString *expert) { return MMPrefBool(MMIconVisibleKey(expert), YES); }

#pragma mark State files

@implementation MMStateFile

+ (instancetype)fileNamed:(NSString *)name expert:(NSString *)expert {
    MMStateFile *f = [self new];
    f->_path = [[MMExpertDir(expert) stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"json"];
    return f;
}

- (id)read {
    NSData *d = [NSData dataWithContentsOfFile:_path];
    return d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
}

/// flock on a lock file beside the state file, so the app and the CLI take turns. The write goes to a
/// temp file in the same folder and is renamed over the old one, so a reader never sees half a file.
- (void)update:(id (^)(id disk))change {
    NSString *lock = [_path stringByAppendingString:@".lock"];
    int fd = open(lock.fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (fd >= 0) flock(fd, LOCK_EX);
    @try {
        id out = change([self read]);
        if (out && [NSJSONSerialization isValidJSONObject:out]) {
            NSData *d = [NSJSONSerialization dataWithJSONObject:out
                                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                          error:nil];
            [d writeToFile:_path atomically:YES];
        }
    } @finally {
        if (fd >= 0) { flock(fd, LOCK_UN); close(fd); }
    }
}

@end

#pragma mark Rules

/// rules.json holds each named list at the top level, and under "_defaults" every default entry it has
/// ever added. A default that is listed there and missing from its list was removed by the person, so it stays out.
@implementation MMRules {
    MMStateFile *_file;
    NSDictionary *_defaults;
    NSDictionary *_cache;
    NSDate *_cacheStamp;
}

+ (instancetype)rulesFor:(NSString *)expert defaults:(NSDictionary<NSString *, NSArray *> *)defaults {
    MMRules *r = [self new];
    r->_file = [MMStateFile fileNamed:@"rules" expert:expert];
    r->_defaults = [defaults copy] ?: @{};
    // Writes only when a default is new or the file is missing, so a read-only start leaves the file alone.
    [r->_file update:^id(id disk) {
        BOOL changed = ![disk isKindOfClass:NSDictionary.class];
        NSMutableDictionary *j = [r merged:disk changed:&changed];
        return changed ? j : nil;
    }];
    return r;
}

/// The file with every new default added once. *changed says whether anything was added.
- (NSMutableDictionary *)merged:(id)disk changed:(BOOL *)changed {
    NSMutableDictionary *j = [disk isKindOfClass:NSMutableDictionary.class] ? disk : [NSMutableDictionary new];
    NSMutableDictionary *seen = [j[@"_defaults"] isKindOfClass:NSMutableDictionary.class] ? j[@"_defaults"] : [NSMutableDictionary new];
    j[@"_defaults"] = seen;
    for (NSString *list in _defaults) {
        NSMutableArray *l = [j[list] isKindOfClass:NSMutableArray.class] ? j[list] : [NSMutableArray new];
        NSMutableArray *s = [seen[list] isKindOfClass:NSMutableArray.class] ? seen[list] : [NSMutableArray new];
        j[list] = l; seen[list] = s;
        for (id v in _defaults[list]) {
            if ([s containsObject:v]) continue;
            [s addObject:v];
            if (![l containsObject:v]) [l addObject:v];
            if (changed) *changed = YES;
        }
    }
    return j;
}

- (NSDictionary *)current {
    @synchronized (self) {
        NSDate *stamp = [NSFileManager.defaultManager attributesOfItemAtPath:_file.path error:nil].fileModificationDate;
        if (!_cache || ![stamp isEqual:_cacheStamp]) {
            _cache = [self merged:[_file read] changed:NULL];
            _cacheStamp = stamp;
        }
        return _cache;
    }
}

static NSString *Field(id entry, NSString *key) {
    id v = key && [entry isKindOfClass:NSDictionary.class] ? entry[key] : entry;
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [v stringValue];
    return nil;
}

/// MinMacs 1.2's Match, Rules.m: *x* is a substring in any case, x* a prefix, and anything else exact.
static BOOL Matches(NSString *pattern, NSString *value) {
    if (!pattern.length || !value) return NO;
    if (pattern.length > 2 && [pattern hasPrefix:@"*"] && [pattern hasSuffix:@"*"])
        return [value.lowercaseString containsString:[pattern substringWithRange:NSMakeRange(1, pattern.length - 2)].lowercaseString];
    if ([pattern hasSuffix:@"*"]) return [value hasPrefix:[pattern substringToIndex:pattern.length - 1]];
    return [value isEqualToString:pattern];
}

- (BOOL)list:(NSString *)list key:(NSString *)key matches:(NSString *)value {
    id l = self.current[list];
    if (![l isKindOfClass:NSArray.class]) return NO;
    for (id e in l) if (Matches(Field(e, key), value)) return YES;
    return NO;
}

- (NSArray *)entries:(NSString *)list {
    id l = self.current[list];
    return [l isKindOfClass:NSArray.class] ? [l copy] : @[];
}

/// MinMacs 1.2's setVerdict: removed every pattern that matched, so keeping one JetBrains app dropped com.jetbrains.*.
/// This removes the one entry equal to value, or with the same key field, and nothing else.
- (void)set:(BOOL)on value:(id)value inList:(NSString *)list key:(NSString *)key {
    if (!value || !list.length) return;
    NSString *ident = Field(value, key);
    @synchronized (self) {
        [_file update:^id(id disk) {
            NSMutableDictionary *j = [self merged:disk changed:NULL];
            NSMutableArray *l = [j[list] isKindOfClass:NSMutableArray.class] ? j[list] : [NSMutableArray new];
            j[list] = l;
            NSIndexSet *same = [l indexesOfObjectsPassingTest:^BOOL(id e, NSUInteger i, BOOL *stop) {
                return [e isEqual:value] || (key && ident && [Field(e, key) isEqualToString:ident]);
            }];
            [l removeObjectsAtIndexes:same];
            if (on) [l addObject:value];
            return j;
        }];
        _cache = nil;
    }
}

@end
