// The support folder, prefs, rules files and state files. Patterns P34 to P37.
// Ported from LocoHost's LHSupportDir and SaveActivity, WorkForest's WFRules and WFPref, and MinMacs 1.2's wildcards.
#import "Core/Store/MMStore.h"
#import <sys/file.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

NSString *const MMPrefsDomain = @"no.guerrilla.minmacs";
NSString *const MMReviewModelKey = @"review.model";
NSString *const MMOneIconKey = @"core.oneIcon";

#pragma mark Folders

/// MINMACS_HOME read with getenv, which sees a change made after launch as NSProcessInfo does, without copying
/// the whole environment on every call. Issue #52: the tick asks for the support folder many times a rebuild.
static NSString *HomeEnv(void) {
    const char *h = getenv("MINMACS_HOME");
    return h && *h ? [NSFileManager.defaultManager stringWithFileSystemRepresentation:h length:strlen(h)] : nil;
}

static NSString *MakeDir(NSString *dir) {
    // One stat when the folder is there, issue #52: the tick asks for these paths many times a rebuild.
    struct stat st;
    if (stat(dir.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) return dir;
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

/// A file's identity and change time from one stat, with no extended attributes read. nil when it is missing.
static NSString *FileStamp(NSString *path) {
    struct stat st;
    if (!path || stat(path.fileSystemRepresentation, &st) != 0) return nil;
    return [NSString stringWithFormat:@"%llu:%ld.%ld:%lld", (unsigned long long)st.st_ino, (long)st.st_mtimespec.tv_sec,
                                      st.st_mtimespec.tv_nsec, (long long)st.st_size];
}

NSString *MMSupportDir(void) {
    // Read each time, so a test that sets MINMACS_HOME after launch still gets its own folder.
    NSString *env = HomeEnv();
    if (env.length) return MakeDir(env);
    return MakeDir([NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"]);
}

NSString *MMExpertDir(NSString *expert) {
    return MakeDir([MMSupportDir() stringByAppendingPathComponent:expert.length ? expert : @"core"]);
}

NSArray<NSString *> *MMRemoveStaleFiles(void) {
    NSMutableArray *gone = [NSMutableArray new];
    // repos.eventid: the one FSEvents id of the first repo watch. Each root's stream keeps repos.<hash>.eventid now.
    for (NSString *name in @[@"repos.eventid"]) {
        NSString *path = [MMSupportDir() stringByAppendingPathComponent:name];
        struct stat st;
        // Only a plain file of that name, never a folder or a link someone put there.
        if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        if (unlink(path.fileSystemRepresentation) == 0) [gone addObject:name];
    }
    return gone;
}

#pragma mark Prefs

NSString *MMPrefsTarget(void) {
    NSString *env = HomeEnv();
    if (!env.length) return MMPrefsDomain;
    // The test prefs stay inside MINMACS_HOME, in a plist that MMPref and MMSetPref read and write themselves.
    return [MakeDir([env stringByAppendingPathComponent:@"Preferences"]) stringByAppendingPathComponent:@"no.guerrilla.minmacs.plist"];
}

/// The test plist, or nil for the person's own domain. With MINMACS_HOME set every read and write goes to this
/// file alone, under an flock, and never through CFPreferences or cfprefsd, so no test can reach the real domain.
static NSString *FilePrefsPath(void) {
    NSString *t = MMPrefsTarget();
    return [t hasPrefix:@"/"] ? t : nil;
}

/// Runs body with the test plist locked, shared to read and exclusive to write.
static void WithPrefsFile(NSString *path, BOOL write, void (^body)(void)) {
    int fd = open([path stringByAppendingString:@".lock"].fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (fd >= 0) flock(fd, write ? LOCK_EX : LOCK_SH);
    @try { body(); }
    @finally { if (fd >= 0) { flock(fd, LOCK_UN); close(fd); } }
}

/// The test plist, parsed again only when its inode, change time or size moved. MMSetPref writes it atomically,
/// so every write gives a new inode.
static NSString *gKeptPrefsPath, *gKeptPrefsStamp;
static NSDictionary *gKeptPrefs;
static NSDictionary *KeptPrefs(NSString *path) {
    NSString *stamp = FileStamp(path);
    @synchronized (NSFileManager.class) {
        if (stamp && gKeptPrefs && [gKeptPrefsPath isEqualToString:path] && [gKeptPrefsStamp isEqualToString:stamp]) return gKeptPrefs;
    }
    return nil;
}

static NSDictionary *ReadPrefsFile(NSString *path) {
    NSString *stamp = FileStamp(path);
    NSDictionary *have = KeptPrefs(path);
    if (have) return have;
    NSData *d = [NSData dataWithContentsOfFile:path];
    id j = d ? [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:nil] : nil;
    NSDictionary *out = [j isKindOfClass:NSDictionary.class] ? j : @{};
    @synchronized (NSFileManager.class) { gKeptPrefs = out; gKeptPrefsPath = path; gKeptPrefsStamp = stamp; }
    return out;
}

id MMPref(NSString *key) {
    if (!key.length) return nil;
    NSString *path = FilePrefsPath();
    if (path) {
        // The parse of an unchanged file needs no lock: the stamp says nothing wrote it since.
        NSDictionary *kept = KeptPrefs(path);
        if (kept) return kept[key];
        __block id v = nil;
        WithPrefsFile(path, NO, ^{ v = ReadPrefsFile(path)[key]; });
        return v;
    }
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)MMPrefsDomain));
}

void MMSetPref(NSString *key, id value) {
    if (!key.length) return;
    NSString *path = FilePrefsPath();
    if (path) {
        WithPrefsFile(path, YES, ^{
            NSMutableDictionary *all = [ReadPrefsFile(path) mutableCopy];
            if (value) all[key] = value; else [all removeObjectForKey:key];
            NSData *d = [NSPropertyListSerialization dataWithPropertyList:all format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            [d writeToFile:path atomically:YES];
        });
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)MMPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MMPrefsDomain);
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
/// Every set: in this process, by any instance, so another instance's cache is checked again at once.
static _Atomic uint64_t gRulesWrites;

void MMRulesCheckNow(void) { atomic_fetch_add(&gRulesWrites, 1); }

@implementation MMRules {
    MMStateFile *_file;
    NSDictionary *_defaults;
    NSDictionary *_cache;
    NSString *_cacheStamp;                 // inode, change time and size of the file when _cache was read
    uint64_t _checkedAt;                   // when the stamp was last read, in CLOCK_UPTIME_RAW ns
    uint64_t _checkedWrites;               // gRulesWrites then
}

+ (instancetype)rulesFor:(NSString *)expert defaults:(NSDictionary<NSString *, NSArray *> *)defaults {
    MMStateFile *file = [MMStateFile fileNamed:@"rules" expert:expert];
    NSDictionary *wanted = [defaults copy] ?: @{};
    // Issue #54: the same rules again, while the file is the one the last call merged into. WorkForest asks for
    // its protect list once per worktree on each build, and each call took the file's lock and parsed it,
    // 300 times a build with 300 worktrees. A changed or missing file merges its defaults again, as before.
    static NSMutableDictionary<NSString *, NSArray *> *made;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ made = [NSMutableDictionary new]; });
    id stamp = FileStamp(file.path) ?: NSNull.null;
    @synchronized (made) {
        NSArray *hit = made[file.path];
        if (hit && [hit[0] isEqual:wanted] && [hit[2] isEqual:stamp]) return hit[1];
    }
    MMRules *r = [self new];
    r->_file = file;
    r->_defaults = wanted;
    // Writes only when a default is new or the file is missing, so a read-only start leaves the file alone.
    [r->_file update:^id(id disk) {
        BOOL changed = ![disk isKindOfClass:NSDictionary.class];
        NSMutableDictionary *j = [r merged:disk changed:&changed];
        if (changed) atomic_fetch_add(&gRulesWrites, 1);
        return changed ? j : nil;
    }];
    id after = FileStamp(file.path);
    @synchronized (made) {
        if (made.count > 64) [made removeAllObjects];
        if (after) made[file.path] = @[wanted, r, after]; else [made removeObjectForKey:file.path];
    }
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
        // The file is checked at most once a second, issue #52: a rebuild asks every list for every server.
        // A change through set: drops the cache at once, so only an edit from outside waits up to a second.
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW), writes = atomic_load(&gRulesWrites);
        if (_cache && now - _checkedAt < NSEC_PER_SEC && writes == _checkedWrites) return _cache;
        _checkedAt = now; _checkedWrites = writes;
        NSString *stamp = FileStamp(_file.path);
        if (!_cache || !(stamp == _cacheStamp || [stamp isEqual:_cacheStamp])) {
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
        atomic_fetch_add(&gRulesWrites, 1);
    }
}

@end
