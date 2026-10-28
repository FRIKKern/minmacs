// MMSessions and MMAgentEvents, patterns P19 to P22. P64, MMHookIngest, stays a declaration: no hooks ship, decision 11.
// The index starts from Sessions in WorkForest's Trees.m and the session reads in LocoHost's Intel.m.
// New in 2.0: Claude Code's status files, TESTS.md question 9, and Codex's SQLite, question 10, in place of
// walking 30 days of rollout folders. cmux events follow research track E and TESTS.md question 8.
#import "Core/Know/MMSessions.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import "Core/Know/MMFactCache.h"
#import <sqlite3.h>
#import <sys/sysctl.h>
#import <time.h>
#import <dirent.h>
#import <sys/stat.h>
#import <CoreServices/CoreServices.h>
#import <stdatomic.h>


static const NSTimeInterval kSessionWindow = 30 * 86400;   // older transcripts are left out, as WorkForest does

@interface MMFactCache (MMKnowSave)
- (void)save;
@end

@interface MMSession ()
@property (readwrite, copy) NSString *agent, *sessionID, *title, *cwd, *branch, *transcript, *liveStatus;
@property (readwrite) NSDate *started, *lastActive;
@property (readwrite) pid_t pid;
@end

@implementation MMSession
- (BOOL)stillWorking {
    return [@[@"busy", @"waiting", @"inProgress"] containsObject:self.liveStatus ?: @""];
}
@end

#pragma mark Helpers

static NSDictionary<NSString *, NSString *> *Env(void) { return NSProcessInfo.processInfo.environment; }

static NSString *ClaudeDir(void) {
    NSString *d = Env()[@"CLAUDE_CONFIG_DIR"];
    return d.length ? d : [NSHomeDirectory() stringByAppendingPathComponent:@".claude"];
}
static NSString *CodexDir(void) {
    NSString *d = Env()[@"CODEX_HOME"];
    return d.length ? d : [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
}
/// pi's own variables: PI_CODING_AGENT_SESSION_DIR, else PI_CODING_AGENT_DIR/sessions, else ~/.pi/agent/sessions.
static NSString *PiSessionsDir(void) {
    NSString *s = Env()[@"PI_CODING_AGENT_SESSION_DIR"];
    if (s.length) return s;
    NSString *a = Env()[@"PI_CODING_AGENT_DIR"];
    return [a.length ? a : [NSHomeDirectory() stringByAppendingPathComponent:@".pi/agent"] stringByAppendingPathComponent:@"sessions"];
}

static NSData *Head(NSString *path, NSUInteger max) {
    NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *d = [f readDataUpToLength:max error:nil];
    [f closeFile];
    return d;
}

static NSString *Text(NSData *d) {
    return d ? ([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding]) : nil;
}

/// The last bytes of a file, for keys an agent appends late, such as Claude Code's aiTitle.
static NSString *TailText(NSString *path, unsigned long long max) {
    NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:path];
    unsigned long long end = [f seekToEndOfFile];
    [f seekToFileOffset:end > max ? end - max : 0];
    NSData *d = [f readDataToEndOfFile];
    [f closeFile];
    return Text(d);
}

static NSString *Match(NSString *s, NSString *pattern, BOOL last) {
    if (!s) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *all = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    NSTextCheckingResult *m = last ? all.lastObject : all.firstObject;
    return m && [m rangeAtIndex:1].location != NSNotFound ? [s substringWithRange:[m rangeAtIndex:1]] : nil;
}

/// A JSON string value as written, with its escapes undone.
static NSString *Unescape(NSString *raw) {
    if (!raw) return nil;
    NSString *wrapped = [NSString stringWithFormat:@"[\"%@\"]", raw];
    NSArray *a = [NSJSONSerialization JSONObjectWithData:[wrapped dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [a.firstObject isKindOfClass:NSString.class] ? a.firstObject : raw;
}

static NSDate *ISODate(NSString *s) {
    static NSISO8601DateFormatter *f, *g; static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSISO8601DateFormatter new];
        f.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        g = [NSISO8601DateFormatter new];
    });
    return s ? ([f dateFromString:s] ?: [g dateFromString:s]) : nil;
}

static NSDate *Millis(id v) { return [v isKindOfClass:NSNumber.class] && [v doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[v doubleValue] / 1000] : nil; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

/// The start time of a running pid in seconds, from the process table. 0 when no such process runs.
static uint64_t StartSec(pid_t pid) {
    struct kinfo_proc k; size_t len = sizeof k;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (pid <= 0 || sysctl(mib, 4, &k, &len, NULL, 0) != 0 || len != sizeof k || k.kp_proc.p_pid != pid) return 0;
    return (uint64_t)k.kp_proc.p_starttime.tv_sec;
}

/// procStart as Claude Code writes it, such as "Wed Oct 21 09:13:03 2026". The files on this Mac hold UTC: a session
/// that ps shows starting at 11:13:03 local time, UTC+2, holds 09:13:03. utc picks the reading. 0 when it does not parse.
static uint64_t ParseProcStart(NSString *s, BOOL utc) {
    if (!s.length) return 0;
    struct tm tm; memset(&tm, 0, sizeof tm);
    if (!strptime(s.UTF8String, "%a %b %d %H:%M:%S %Y", &tm)) return 0;
    tm.tm_isdst = -1;
    time_t t = utc ? timegm(&tm) : mktime(&tm);
    return t > 0 ? (uint64_t)t : 0;
}

/// YES when procStart names the process that runs now, read as UTC or as local time, within a second.
static BOOL SameStart(uint64_t running, NSString *procStart) {
    if (!running) return NO;
    uint64_t u = ParseProcStart(procStart, YES), l = ParseProcStart(procStart, NO);
    if (!u && !l) return YES;   // no procStart to check: the pid runs, which is all the file says
    for (int i = 0; i < 2; i++) {
        uint64_t c = i ? l : u;
        if (c && (running > c ? running - c : c - running) <= 1) return YES;
    }
    return NO;
}

/// The modification time and size of path from one stat, with no extended attributes read. NO when it is missing.
static BOOL StatOf(NSString *path, NSTimeInterval *mtime, unsigned long long *size) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return NO;
    if (mtime) *mtime = st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9;
    if (size) *size = (unsigned long long)st.st_size;
    return YES;
}

static NSString *FileFingerprint(NSString *path, NSDate **mtime) {
    NSTimeInterval m; unsigned long long size;
    if (!StatOf(path, &m, &size)) return nil;
    if (mtime) *mtime = [NSDate dateWithTimeIntervalSince1970:m];
    return [NSString stringWithFormat:@"%.0f:%llu", m, size];
}

/// The names in one folder, with readdir. Hidden names are left out, as contentsOfDirectoryAtPath leaves none.
static NSArray<NSString *> *Names(NSString *dir) {
    DIR *d = opendir(dir.fileSystemRepresentation);
    if (!d) return @[];
    NSMutableArray *out = [NSMutableArray new];
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        NSString *n = [NSFileManager.defaultManager stringWithFileSystemRepresentation:e->d_name length:strlen(e->d_name)];
        if (n) [out addObject:n];
    }
    closedir(d);
    return out;
}

#pragma mark Claude Code

/// One transcript's facts, read once per change of size or time through the fact cache.
static NSDictionary *ClaudeTranscriptFacts(NSString *path) {
    NSString *head = Text(Head(path, 64 * 1024));
    NSMutableDictionary *f = [NSMutableDictionary new];
    f[@"id"] = path.lastPathComponent.stringByDeletingPathExtension;
    NSString *cwd = Unescape(Match(head, @"\"cwd\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", NO));
    if (cwd) f[@"cwd"] = cwd;
    NSString *branch = Unescape(Match(head, @"\"gitBranch\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", NO));
    if (branch) f[@"branch"] = branch;
    NSDate *start = ISODate(Match(head, @"\"timestamp\":\\s*\"([^\"]+)\"", NO));
    if (start) f[@"started"] = @(start.timeIntervalSince1970);
    NSString *title = Unescape(Match(TailText(path, 512 * 1024), @"\"aiTitle\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", YES));
    if (title) f[@"title"] = title;
    return f;
}

#pragma mark pi

/// The header line of a pi session: {"type":"session","id":...,"cwd":...,"timestamp":...}, as LocoHost's Intel reads it.
static NSDictionary *PiFacts(NSString *path) {
    NSString *head = Text(Head(path, 16 * 1024));
    NSString *first = [head componentsSeparatedByString:@"\n"].firstObject;
    NSDictionary *j = first ? [NSJSONSerialization JSONObjectWithData:[first dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    NSMutableDictionary *f = [NSMutableDictionary new];
    if ([j isKindOfClass:NSDictionary.class] && [j[@"type"] isEqual:@"session"]) {
        if (Str(j[@"id"])) f[@"id"] = j[@"id"];
        if (Str(j[@"cwd"])) f[@"cwd"] = j[@"cwd"];
        NSDate *t = ISODate(Str(j[@"timestamp"]));
        if (t) f[@"started"] = @(t.timeIntervalSince1970);
    }
    if (!f[@"id"]) {
        // <time>_<uuid>.jsonl
        NSString *base = path.lastPathComponent.stringByDeletingPathExtension;
        NSRange u = [base rangeOfString:@"_" options:NSBackwardsSearch];
        f[@"id"] = u.location == NSNotFound ? base : [base substringFromIndex:u.location + 1];
    }
    return f;
}

#pragma mark Codex

/// A path as a SQLite URI path: only the characters a URI gives meaning to are escaped.
static NSString *URIPath(NSString *path) {
    NSMutableString *s = [NSMutableString new];
    for (NSUInteger i = 0; i < path.length; i++) {
        unichar c = [path characterAtIndex:i];
        if (c == '%' || c == '?' || c == '#' || c == ' ') [s appendFormat:@"%%%02X", c];
        else [s appendFormat:@"%C", c];
    }
    return s;
}

/// TESTS.md question 10. mode=ro needs the -shm file, which exists while Codex has the database open.
/// Without it a read-only connection cannot create one, so immutable=1 is used, which is safe while nothing writes.
static sqlite3 *OpenCodexDB(NSString *path, NSString **modeOut) {
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return NULL;
    BOOL shm = [NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingString:@"-shm"]];
    NSString *mode = shm ? @"mode=ro" : @"immutable=1";
    if (modeOut) *modeOut = mode;
    NSString *uri = [NSString stringWithFormat:@"file:%@?%@", URIPath(path), mode];
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(uri.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    sqlite3_busy_timeout(db, 200);
    return db;
}

static NSString *Col(sqlite3_stmt *st, int i) {
    const unsigned char *t = sqlite3_column_text(st, i);
    return t ? @((const char *)t) : nil;
}

/// Every thread updated in the window, with its newest turn's status. Read-only, and it never walks rollout folders.
static NSArray<MMSession *> *CodexSessions(NSString **modeOut) {
    NSString *home = CodexDir();
    sqlite3 *db = OpenCodexDB([home stringByAppendingPathComponent:@"state_5.sqlite"], modeOut);
    if (!db) return @[];
    NSMutableArray<MMSession *> *out = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMSession *> *byID = [NSMutableDictionary new];
    sqlite3_stmt *st = NULL;
    long long since = (long long)(NSDate.date.timeIntervalSince1970 - kSessionWindow);
    const char *q = "SELECT id, cwd, title, git_branch, rollout_path, created_at, updated_at FROM threads "
                    "WHERE archived = 0 AND updated_at >= ? ORDER BY updated_at DESC LIMIT 1000";
    if (sqlite3_prepare_v2(db, q, -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(st, 1, since);
        while (sqlite3_step(st) == SQLITE_ROW) {
            MMSession *s = [MMSession new];
            s.agent = @"codex";
            s.sessionID = Col(st, 0);
            s.cwd = Col(st, 1);
            s.title = Str(Col(st, 2));
            s.branch = Str(Col(st, 3));
            s.transcript = Str(Col(st, 4));
            s.started = [NSDate dateWithTimeIntervalSince1970:(double)sqlite3_column_int64(st, 5)];
            s.lastActive = [NSDate dateWithTimeIntervalSince1970:(double)sqlite3_column_int64(st, 6)];
            if (!s.sessionID) continue;
            [out addObject:s];
            byID[s.sessionID] = s;
        }
    }
    sqlite3_finalize(st);
    sqlite3_close(db);

    db = OpenCodexDB([home stringByAppendingPathComponent:@"thread_history_1.sqlite"], NULL);
    if (db && byID.count) {
        // The newest turn of each thread. A live turn is written as inProgress and updated in place.
        const char *tq = "SELECT t.thread_id, t.status, t.started_at, t.completed_at FROM thread_turns t "
                         "WHERE t.rollout_ordinal = (SELECT MAX(rollout_ordinal) FROM thread_turns WHERE thread_id = t.thread_id)";
        st = NULL;
        if (sqlite3_prepare_v2(db, tq, -1, &st, NULL) == SQLITE_OK) {
            while (sqlite3_step(st) == SQLITE_ROW) {
                MMSession *s = byID[Col(st, 0) ?: @""];
                if (!s) continue;
                s.liveStatus = Col(st, 1);
                double t = MAX(sqlite3_column_double(st, 2), sqlite3_column_double(st, 3));
                if (t > s.lastActive.timeIntervalSince1970) s.lastActive = [NSDate dateWithTimeIntervalSince1970:t];
            }
        }
        sqlite3_finalize(st);
    }
    if (db) sqlite3_close(db);
    return out;
}

#pragma mark The index

NSNotificationName const MMSessionsDidChangeNotification = @"MMSessionsDidChangeNotification";

static NSString *Plain(NSString *p);

static const NSTimeInterval kSessionsMaxAge = 60;    // a watched index is read again at least this often
static const NSTimeInterval kFullReadEvery = 600;    // and every folder is listed again at least this often

@implementation MMSessions {
    NSArray<MMSession *> *_all;          // replaced whole on each refresh, so a read never sees half of one
    NSDictionary<NSNumber *, MMSession *> *_byPid;
    NSDictionary<NSString *, MMSession *> *_byID;
    MMFactCache<NSDictionary *> *_facts;
    // Issue #52. The watch: set up and torn down under @synchronized (self); _dirty is set by the stream.
    FSEventStreamRef _stream;
    dispatch_queue_t _watchQ;
    NSArray<NSString *> *_watchRoots, *_watchDirs;
    NSMutableSet<NSString *> *_missingDirs;              // watched folders that did not exist when the watch began
    NSArray<NSString *> *_unwatched;     // under @synchronized (self): missing folders with no folder to watch from
    BOOL _wantWatch;                     // under @synchronized (self): startWatching ran and stopWatching did not
    _Atomic bool _dirty;
    NSDate *_readAt;                     // under @synchronized (self): when the folders were last read
    NSDictionary<NSNumber *, NSNumber *> *_liveStarts;   // under @synchronized (self): live status file pid to start
    NSUInteger _reads, _skips;
    // Issue #52. What each session folder held when it was last listed, so a change lists only its own folder.
    // Keys are Plain paths. Touched only inside a read, which runs on one queue at a time under _readLock.
    NSMutableSet<NSString *> *_dirtyDirs;                // under @synchronized (self): folders FSEvents named
    BOOL _allDirty;                                      // under @synchronized (self)
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *_subdirs;      // a root to its folder names
    NSMutableDictionary<NSString *, NSArray<NSArray *> *> *_listing;       // a folder to [[path, mtime], ...]
    NSDate *_fullAt;
    NSLock *_readLock;
}

/// The .jsonl files in dir's folders written after since. A folder FSEvents did not name keeps its last listing,
/// unless all is YES. Each file is one stat, never an attributes call.
- (NSArray<NSString *> *)jsonlIn:(NSString *)dir since:(NSDate *)since all:(BOOL)all dirty:(NSSet<NSString *> *)dirty {
    NSString *root = Plain(dir.stringByStandardizingPath);
    NSArray<NSString *> *subs = _subdirs[root];
    if (all || !subs || [dirty containsObject:root]) { subs = Names(dir); _subdirs[root] = subs; }
    NSMutableArray *out = [NSMutableArray new];
    NSTimeInterval after = since.timeIntervalSince1970;
    for (NSString *sub in subs) {
        NSString *d = [dir stringByAppendingPathComponent:sub];
        NSString *key = [root stringByAppendingPathComponent:sub];
        NSArray<NSArray *> *files = _listing[key];
        if (all || !files || [dirty containsObject:key]) {
            NSMutableArray *list = [NSMutableArray new];
            for (NSString *f in Names(d)) {
                if (![f hasSuffix:@".jsonl"]) continue;
                NSString *p = [d stringByAppendingPathComponent:f];
                NSTimeInterval m;
                if (StatOf(p, &m, NULL)) [list addObject:@[p, @(m)]];
            }
            files = list;
            _listing[key] = files;
        }
        for (NSArray *e in files) if ([e[1] doubleValue] > after) [out addObject:e[0]];
    }
    // Folders that are gone leave the listing.
    NSSet *now = [NSSet setWithArray:subs];
    for (NSString *k in _listing.allKeys)
        if ([k.stringByDeletingLastPathComponent isEqualToString:root] && ![now containsObject:k.lastPathComponent]) [_listing removeObjectForKey:k];
    return out;
}

- (NSUInteger)readCount { @synchronized (self) { return _reads; } }
- (NSUInteger)skipCount { @synchronized (self) { return _skips; } }

static void SessionsChanged(ConstFSEventStreamRef stream, void *info, size_t n, void *paths,
                            const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    [(__bridge MMSessions *)info noteChanges:n paths:(char **)paths flags:flags];
}

/// FSEvents names /var and /tmp by their real paths under /private. Both sides drop that, so they compare.
static NSString *Plain(NSString *p) {
    if ([p hasPrefix:@"/private/var/"] || [p hasPrefix:@"/private/tmp/"]) p = [p substringFromIndex:8];
    return [p hasSuffix:@"/"] && p.length > 1 ? [p substringToIndex:p.length - 1] : p;
}

/// YES when a change at path can move the index: Claude Code's project or status folders, Codex's databases in its
/// home folder itself, or a pi session folder. Codex's rollout folders and the rest of ~/.claude are left out.
/// dirs holds those four folders as startWatching found them. A folder that was missing then counts once it exists.
static BOOL Matters(NSString *path, NSArray<NSString *> *dirs, NSMutableSet<NSString *> *missing) {
    NSString *p = Plain(path);
    for (NSUInteger i = 0; i < dirs.count; i++) {
        NSString *d = dirs[i];
        if ([p isEqualToString:d]) return YES;
        if (i != 2 && [p hasPrefix:[d stringByAppendingString:@"/"]]) return YES;   // inside, except under Codex's home
    }
    for (NSString *d in missing.allObjects)
        if ([d hasPrefix:[p stringByAppendingString:@"/"]] && [NSFileManager.defaultManager fileExistsAtPath:d]) {
            [missing removeObject:d];
            return YES;
        }
    return NO;
}

- (void)noteChanges:(size_t)n paths:(char **)paths flags:(const FSEventStreamEventFlags *)flags {
    NSArray<NSString *> *dirs;
    NSMutableSet<NSString *> *missing;
    @synchronized (self) { dirs = _watchDirs; missing = _missingDirs; }
    if (dirs.count != 4) return;
    BOOL any = NO;
    for (size_t i = 0; i < n && !any; i++) {
        if (flags[i] & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged |
                        kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)) { any = YES; break; }
        any = Matters(@(paths[i]), dirs, missing);   // the watch queue is serial, so missing needs no lock
    }
    if (!any) return;
    @synchronized (self) {
        for (size_t i = 0; i < n; i++) {
            if (flags[i] & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged |
                            kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)) _allDirty = YES;
            [_dirtyDirs addObject:Plain(@(paths[i]))];
        }
    }
    atomic_store(&_dirty, true);
    [NSNotificationCenter.defaultCenter postNotificationName:MMSessionsDidChangeNotification object:self];
}

- (void)startWatching {
    @synchronized (self) {
        _wantWatch = YES;
        if (_stream) return;
        NSMutableArray *roots = [NSMutableArray new];
        NSMutableArray *unwatched = [NSMutableArray new];
        NSString *home = Plain(NSHomeDirectory().stringByStandardizingPath);
        NSString *claude = ClaudeDir().stringByStandardizingPath;
        NSArray *paths = @[[claude stringByAppendingPathComponent:@"projects"], [claude stringByAppendingPathComponent:@"sessions"],
                           CodexDir().stringByStandardizingPath, PiSessionsDir().stringByStandardizingPath];
        NSMutableArray *dirs = [NSMutableArray new];
        NSMutableSet *missing = [NSMutableSet new];
        for (NSString *r in paths) {
            [dirs addObject:Plain(r)];
            // A folder that does not exist yet is watched from the nearest folder above it that does.
            NSString *d = r;
            if (![NSFileManager.defaultManager fileExistsAtPath:d]) [missing addObject:Plain(r)];
            while (d.length > 1 && ![NSFileManager.defaultManager fileExistsAtPath:d]) d = d.stringByDeletingLastPathComponent;
            // Never from the home folder or above it: FSEvents would wake this process for every change under it.
            // Such a folder is checked with a stat on each refresh, and the watch starts again once it exists.
            NSString *pd = Plain(d);
            if (d.length <= 1 || [home isEqualToString:pd] || [home hasPrefix:[pd stringByAppendingString:@"/"]]) {
                [unwatched addObject:Plain(r)];
                continue;
            }
            if (![roots containsObject:d]) [roots addObject:d];
        }
        _unwatched = [unwatched copy];
        if (!roots.count) return;
        _watchQ = MMQueue(@"core", @"sessions.watch", QOS_CLASS_UTILITY);
        FSEventStreamContext ctx = { .info = (__bridge void *)self };
        _stream = FSEventStreamCreate(NULL, SessionsChanged, &ctx, (__bridge CFArrayRef)roots, kFSEventStreamEventIdSinceNow,
                                      1.0, kFSEventStreamCreateFlagNoDefer);
        if (!_stream) return;
        FSEventStreamSetDispatchQueue(_stream, _watchQ);
        if (!FSEventStreamStart(_stream)) { FSEventStreamInvalidate(_stream); FSEventStreamRelease(_stream); _stream = NULL; return; }
        _watchRoots = roots; _watchDirs = [dirs copy]; _missingDirs = missing;
        atomic_store(&_dirty, true);   // the first refresh reads everything
    }
}

- (void)stopWatching {
    FSEventStreamRef s;
    @synchronized (self) { s = _stream; _stream = NULL; _watchRoots = nil; _watchDirs = nil; _missingDirs = nil; _unwatched = nil; _wantWatch = NO; }
    if (!s) return;
    FSEventStreamStop(s);
    FSEventStreamInvalidate(s);
    dispatch_sync(_watchQ, ^{ FSEventStreamRelease(s); });   // no callback runs once this returns
}

/// YES when the last read still holds: the watch runs, no change came, every live status file's process runs with
/// the start time it had, and the read is less than a minute old.
- (BOOL)stillFresh {
    NSDictionary<NSNumber *, NSNumber *> *live;
    @synchronized (self) {
        if (!_stream || !_readAt || -_readAt.timeIntervalSinceNow >= kSessionsMaxAge) return NO;
        live = _liveStarts;
    }
    if (atomic_load(&_dirty)) return NO;
    for (NSNumber *pid in live) if (StartSec(pid.intValue) != live[pid].unsignedLongLongValue) return NO;
    return YES;
}

+ (instancetype)shared {
    static MMSessions *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMSessions new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _all = @[]; _byPid = @{}; _byID = @{};
        _facts = [[MMFactCache alloc] initWithName:@"sessions" maxAge:0 persist:YES];
        _dirtyDirs = [NSMutableSet new]; _allDirty = YES;
        _subdirs = [NSMutableDictionary new]; _listing = [NSMutableDictionary new];
        _readLock = [NSLock new];
    }
    return self;
}

- (NSDictionary *)factsFor:(NSString *)path reader:(NSDictionary *(^)(NSString *))reader mtime:(NSDate **)mtime {
    NSString *fp = FileFingerprint(path, mtime);
    if (!fp) return nil;
    return [_facts valueFor:path fingerprint:fp orCompute:^NSDictionary *{ return reader(path); } wait:YES];
}

/// YES when a folder that startWatching could not watch from above now exists, so the watch must start again.
- (BOOL)unwatchedAppeared {
    NSArray<NSString *> *unwatched;
    @synchronized (self) { if (!_wantWatch) return NO; unwatched = _unwatched; }
    struct stat st;
    for (NSString *d in unwatched) if (stat(d.fileSystemRepresentation, &st) == 0) return YES;
    return NO;
}

- (void)refresh {
    if ([self unwatchedAppeared]) {
        [self stopWatching];
        [self startWatching];
        @synchronized (self) { _allDirty = YES; }   // the new folder has never been listed
    }
    if ([self stillFresh]) { @synchronized (self) { _skips++; } return; }
    [self read:NO];
}

- (void)refreshAll { [self read:YES]; }

/// One read. all lists every folder again. Otherwise, while the watch runs, only the folders FSEvents named are.
- (void)read:(BOOL)wantAll {
    [_readLock lock];
    @try { [self readLocked:wantAll]; } @finally { [_readLock unlock]; }
}

- (void)readLocked:(BOOL)wantAll {
    atomic_store(&_dirty, false);   // a change from now on asks for another read
    NSSet<NSString *> *dirty;
    BOOL everything;
    @synchronized (self) {
        everything = wantAll || _allDirty || !_stream || !_fullAt || -_fullAt.timeIntervalSinceNow >= kFullReadEvery;
        dirty = [_dirtyDirs copy];
        [_dirtyDirs removeAllObjects];
        _allDirty = NO;
    }
    if (everything) _fullAt = NSDate.date;
    NSDate *since = [NSDate dateWithTimeIntervalSinceNow:-kSessionWindow];
    NSMutableDictionary<NSNumber *, NSNumber *> *liveStarts = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, MMSession *> *byID = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, MMSession *> *byPid = [NSMutableDictionary new];
    NSMutableSet<NSString *> *live = [NSMutableSet new];
    NSMutableDictionary<NSString *, NSString *> *claudeFiles = [NSMutableDictionary new];   // session id: transcript

    // P19. Claude Code transcripts: <config>/projects/<folder>/<session>.jsonl.
    NSString *claude = ClaudeDir();
    for (NSString *f in [self jsonlIn:[claude stringByAppendingPathComponent:@"projects"] since:since all:everything dirty:dirty]) {
        NSDate *m = nil;
        NSDictionary *facts = [self factsFor:f reader:^NSDictionary *(NSString *p) { return ClaudeTranscriptFacts(p); } mtime:&m];
        if (!facts[@"id"]) continue;
        [live addObject:f];
        MMSession *s = [MMSession new];
        s.agent = @"claude-code"; s.sessionID = facts[@"id"]; s.cwd = facts[@"cwd"]; s.branch = facts[@"branch"];
        s.title = facts[@"title"]; s.transcript = f; s.lastActive = m;
        s.started = facts[@"started"] ? [NSDate dateWithTimeIntervalSince1970:[facts[@"started"] doubleValue]] : m;
        MMSession *old = byID[s.sessionID];
        if (!old || [s.lastActive compare:old.lastActive] == NSOrderedDescending) byID[s.sessionID] = s;
        claudeFiles[s.sessionID] = f;
    }

    // P20. Live status files: <config>/sessions/<pid>.json. A file counts for its pid only while that pid runs
    // with the start time the file names, so a file left by a crash, or a reused pid, is never read as live.
    NSString *sdir = [claude stringByAppendingPathComponent:@"sessions"];
    for (NSString *name in Names(sdir)) {
        if (![name.pathExtension isEqualToString:@"json"]) continue;
        NSData *d = [NSData dataWithContentsOfFile:[sdir stringByAppendingPathComponent:name]];
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if (![j isKindOfClass:NSDictionary.class]) continue;
        pid_t pid = [j[@"pid"] isKindOfClass:NSNumber.class] ? [j[@"pid"] intValue] : name.stringByDeletingPathExtension.intValue;
        NSString *sid = Str(j[@"sessionId"]);
        if (!sid) continue;
        uint64_t running = StartSec(pid);
        BOOL alive = SameStart(running, Str(j[@"procStart"]));
        if (alive) liveStarts[@(pid)] = @(running);
        MMSession *s = byID[sid] ?: [MMSession new];
        s.agent = @"claude-code"; s.sessionID = sid;
        s.cwd = Str(j[@"cwd"]) ?: s.cwd;
        s.title = s.title ?: Str(j[@"name"]);
        s.started = Millis(j[@"startedAt"]) ?: s.started;
        NSDate *upd = Millis(j[@"statusUpdatedAt"]) ?: Millis(j[@"updatedAt"]);
        if (upd && (!s.lastActive || [upd compare:s.lastActive] == NSOrderedDescending)) s.lastActive = upd;
        s.lastActive = s.lastActive ?: s.started;
        s.transcript = s.transcript ?: claudeFiles[sid];
        if (alive) {
            s.pid = pid;
            // TESTS.md question 9: busy, waiting, idle and shell. Any other word is kept and reads unknown.
            s.liveStatus = Str(j[@"status"]);
            byPid[@(pid)] = s;
        }
        byID[sid] = s;
    }

    // P21. Codex threads and their newest turns.
    for (MMSession *s in CodexSessions(NULL)) byID[s.sessionID] = s;

    // pi: <sessions>/--<folder>--/<time>_<id>.jsonl.
    for (NSString *f in [self jsonlIn:PiSessionsDir() since:since all:everything dirty:dirty]) {
        NSDate *m = nil;
        NSDictionary *facts = [self factsFor:f reader:^NSDictionary *(NSString *p) { return PiFacts(p); } mtime:&m];
        if (!facts[@"id"]) continue;
        [live addObject:f];
        MMSession *s = [MMSession new];
        s.agent = @"pi"; s.sessionID = facts[@"id"]; s.cwd = facts[@"cwd"]; s.transcript = f; s.lastActive = m;
        s.started = facts[@"started"] ? [NSDate dateWithTimeIntervalSince1970:[facts[@"started"] doubleValue]] : m;
        byID[s.sessionID] = s;
    }

    [_facts forget:live];
    [_facts save];   // the index is read again at the next launch, so it is written now
    NSArray *all = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(MMSession *a, MMSession *b) {
        NSComparisonResult r = [b.lastActive ?: NSDate.distantPast compare:a.lastActive ?: NSDate.distantPast];
        return r != NSOrderedSame ? r : [a.sessionID compare:b.sessionID];
    }];
    @synchronized (self) { _all = all; _byPid = byPid; _byID = byID; _liveStarts = liveStarts; _readAt = NSDate.date; _reads++; }
}

- (NSArray<MMSession *> *)all { @synchronized (self) { return _all; } }
- (MMSession *)forPid:(pid_t)pid { @synchronized (self) { return _byPid[@(pid)]; } }
- (MMSession *)withID:(NSString *)sessionID { @synchronized (self) { return sessionID ? _byID[sessionID] : nil; } }

static BOOL Inside(NSString *cwd, NSString *folder) {
    if (!cwd.length || !folder.length) return NO;
    NSString *f = [folder hasSuffix:@"/"] && folder.length > 1 ? [folder substringToIndex:folder.length - 1] : folder;
    return [cwd isEqualToString:f] || [cwd hasPrefix:[f stringByAppendingString:@"/"]];
}

- (MMSession *)latestIn:(NSString *)folder {
    for (MMSession *s in self.all) if (Inside(s.cwd, folder)) return s;   // all is newest first
    return nil;
}

/// The session that was open at t in one of the folders: it started at most 5 seconds after t and was written
/// to at most a minute before, as LocoHost's Intel counts it. A session in the folder itself beats one inside it,
/// then the one that started last.
- (MMSession *)openAt:(NSDate *)t inFolders:(NSArray<NSString *> *)folders {
    MMSession *best = nil; BOOL bestExact = NO;
    for (MMSession *s in self.all) {
        if (!s.started || !s.lastActive) continue;
        if ([s.started timeIntervalSinceDate:t] > 5 || [s.lastActive timeIntervalSinceDate:t] < -60) continue;
        BOOL exact = NO, inside = NO;
        for (NSString *f in folders) { if ([s.cwd isEqualToString:f]) exact = YES; if (Inside(s.cwd, f)) inside = YES; }
        if (!inside) continue;
        if (!best || (exact && !bestExact) || (exact == bestExact && [s.started compare:best.started] == NSOrderedDescending)) { best = s; bestExact = exact; }
    }
    return best;
}

@end

#pragma mark Agent events

@interface MMAgentEvent ()
@property (readwrite, copy) NSString *agent, *event, *sessionID, *cwd;
@property (readwrite) pid_t ppid;
@property (readwrite) NSDate *at;
@end
@implementation MMAgentEvent
@end

/// The cmux CLI. MINMACS_CMUX names another one, which tests use for a fake.
static NSString *CmuxPath(void) {
    NSString *p = Env()[@"MINMACS_CMUX"];
    if (p.length) return p;
    for (NSString *c in @[@"/Applications/cmux.app/Contents/Resources/bin/cmux",
                          [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/cmux.app/Contents/Resources/bin/cmux"]])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:c]) return c;
    return nil;
}

/// The reader is behind a flag in phase 1: the pref core.cmuxEvents, or MINMACS_CMUX_EVENTS=1.
static BOOL EventsWanted(void) {
    if ([Env()[@"MINMACS_CMUX_EVENTS"] isEqualToString:@"1"]) return YES;
    return MMPrefBool(@"core.cmuxEvents", NO);
}

/// TESTS.md question 8: no password is needed in cmux's automation mode, its default. Read from cmux's prefs
/// without running cmux. A fake named by MINMACS_CMUX skips this, so a test never depends on the real cmux.
static BOOL CmuxModeOK(void) {
    if (Env()[@"MINMACS_CMUX"].length) return YES;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("socketControlMode"), CFSTR("com.cmuxterm.app"));
    BOOL ok = !v || (CFGetTypeID(v) == CFStringGetTypeID() && [(__bridge NSString *)v isEqualToString:@"automation"]);
    if (v) CFRelease(v);
    return ok;
}

@implementation MMAgentEvents {
    NSMutableDictionary<NSUUID *, void (^)(MMAgentEvent *)> *_observers;
    NSTask *_task;
    NSMutableData *_buffer;
    BOOL _started;
    NSString *_why;
}

+ (instancetype)shared {
    static MMAgentEvents *e; static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMAgentEvents new]; });
    return e;
}

- (instancetype)init {
    if ((self = [super init])) { _observers = [NSMutableDictionary new]; _buffer = [NSMutableData new]; }
    return self;
}

- (id)observe:(void (^)(MMAgentEvent *))block {
    NSUUID *token = [NSUUID UUID];
    @synchronized (_observers) { _observers[token] = [block copy]; }
    return token;
}

- (void)stopObserving:(id)token {
    if (!token) return;
    @synchronized (_observers) { [_observers removeObjectForKey:token]; }
}

- (NSString *)unavailableReason { @synchronized (self) { return _why; } }

- (void)start {
    @synchronized (self) {
        if (_started) return;
        if (!EventsWanted()) { _why = @"cmux events are off"; return; }
        if (!CmuxPath()) { _why = @"cmux is not installed"; return; }
        if (!CmuxModeOK()) { _why = @"cmux asks for a password outside automation mode"; return; }
        _started = YES; _why = nil;
    }
    dispatch_async(MMQueue(@"core", @"events", QOS_CLASS_UTILITY), ^{ [self launch]; });
}

- (void)stop {
    NSTask *t;
    @synchronized (self) { _started = NO; t = _task; _task = nil; }
    if (t.running) [t terminate];
}

/// One `cmux events` child for the app's life. --reconnect keeps it across cmux restarts, and the cursor file
/// in the support folder resumes where the last launch stopped. When the child ends anyway, it starts again later.
- (void)launch {
    @synchronized (self) { if (!_started || _task) return; }
    NSString *cursor = [MMSupportDir() stringByAppendingPathComponent:@"cmux.cursor"];
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:CmuxPath()];
    t.arguments = @[@"events", @"--category", @"agent", @"--cursor-file", cursor, @"--reconnect", @"--no-heartbeat", @"--no-ack"];
    NSPipe *out = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    t.standardInput = [NSFileHandle fileHandleWithNullDevice];
    __weak MMAgentEvents *weak = self;
    out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData;
        if (!d.length) { h.readabilityHandler = nil; return; }
        dispatch_async(MMQueue(@"core", @"events", QOS_CLASS_UTILITY), ^{ [weak take:d]; });
    };
    t.terminationHandler = ^(NSTask *ended) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), MMQueue(@"core", @"events", QOS_CLASS_UTILITY), ^{
            MMAgentEvents *me = weak;
            if (!me) return;
            @synchronized (me) { if (me->_task == ended) me->_task = nil; }
            [me launch];
        });
    };
    if (![t launchAndReturnError:nil]) { @synchronized (self) { _why = @"cmux events did not start"; } return; }
    @synchronized (self) {
        if (!_started) { [t terminate]; return; }
        _task = t;
    }
}

/// Splits the stream into lines and keeps only the event name, session id, cwd, parent pid and time.
- (void)take:(NSData *)d {
    [_buffer appendData:d];
    NSData *nl = [NSData dataWithBytes:"\n" length:1];
    for (;;) {
        NSRange r = [_buffer rangeOfData:nl options:0 range:NSMakeRange(0, _buffer.length)];
        if (r.location == NSNotFound) break;
        NSData *line = [_buffer subdataWithRange:NSMakeRange(0, r.location)];
        [_buffer replaceBytesInRange:NSMakeRange(0, r.location + 1) withBytes:NULL length:0];
        MMAgentEvent *e = [MMAgentEvents eventFromFrame:line];
        if (!e) continue;
        NSArray *blocks;
        @synchronized (_observers) { blocks = _observers.allValues; }
        for (void (^b)(MMAgentEvent *) in blocks) b(e);
    }
    if (_buffer.length > 1024 * 1024) [_buffer setLength:0];   // a line this long is not an event frame
}

+ (MMAgentEvent *)eventFromFrame:(NSData *)line {
    NSDictionary *j = line.length ? [NSJSONSerialization JSONObjectWithData:line options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    NSString *name = Str(j[@"name"]);
    if (![name hasPrefix:@"agent.hook."]) return nil;
    NSDictionary *p = [j[@"payload"] isKindOfClass:NSDictionary.class] ? j[@"payload"] : @{};
    MMAgentEvent *e = [MMAgentEvent new];
    e.event = [name substringFromIndex:@"agent.hook.".length];
    NSString *src = Str(j[@"source"]) ?: Str(p[@"_source"]);
    e.agent = [src isEqualToString:@"claude"] ? @"claude-code" : src;
    e.sessionID = Str(p[@"session_id"]);
    e.cwd = Str(p[@"cwd"]);
    id pp = p[@"_ppid"];
    e.ppid = [pp respondsToSelector:@selector(intValue)] ? [pp intValue] : 0;
    e.at = ISODate(Str(j[@"occurred_at"])) ?: NSDate.date;
    return e;
}

@end
