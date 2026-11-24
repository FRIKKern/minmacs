// The append-only log in SQLite, pattern P38 and decision 5. Noo-Noo's audit.go writes one JSONL line per action.
// This keeps the same idea in one SQLite file: a row is never changed, and a new state is a new row with the same rid.
// Triggers refuse UPDATE and DELETE on the rows table, so no code path can rewrite history.
#import "Core/Store/MMLog.h"
#import "Core/Store/MMStore.h"
#import "Core/Runtime/MMRuntime.h"
#import <sqlite3.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <sys/stat.h>

@interface MMLogEntry ()
@property (readwrite) int64_t row;
@property (readwrite, copy) NSString *rid, *table, *expert, *subject, *state;
@property (readwrite) NSDate *at;
@property (readwrite) NSDictionary *body;
@end
@implementation MMLogEntry
- (NSString *)description {
    return [NSString stringWithFormat:@"%lld %@ %@ %@ %@ %@", self.row, self.table, self.rid, self.expert, self.subject, self.state];
}
@end

// WAL mode is set on its own, outside a transaction, since SQLite allows no other way.
static const char *kWAL = "PRAGMA journal_mode=WAL;";
// A WAL past 4 MB is cut back after a checkpoint.
static const char *kSizeLimit = "PRAGMA journal_size_limit=4194304;";
// The tables, in one IMMEDIATE transaction. IMMEDIATE takes the write lock first, so two processes that make the
// schema at once wait for each other through the busy timeout. A deferred transaction would read first and then
// ask for the write lock, and SQLite refuses that at once, without waiting, when another process is mid-write.
static const char *kSchema =
    "BEGIN IMMEDIATE;"
    "CREATE TABLE IF NOT EXISTS rows ("
    "  row INTEGER PRIMARY KEY AUTOINCREMENT, rid TEXT NOT NULL, tbl TEXT NOT NULL,"
    "  expert TEXT, subject TEXT, state TEXT, at REAL NOT NULL, body TEXT);"
    "CREATE INDEX IF NOT EXISTS rows_rid ON rows(rid, row);"
    "CREATE INDEX IF NOT EXISTS rows_tbl ON rows(tbl, row);"
    "CREATE TRIGGER IF NOT EXISTS rows_no_update BEFORE UPDATE ON rows BEGIN SELECT RAISE(ABORT, 'the log is append-only'); END;"
    "CREATE TRIGGER IF NOT EXISTS rows_no_delete BEFORE DELETE ON rows BEGIN SELECT RAISE(ABORT, 'the log is append-only'); END;"
    "CREATE TABLE IF NOT EXISTS points ("
    "  series TEXT NOT NULL, bucket INTEGER NOT NULL, at REAL NOT NULL, value REAL NOT NULL,"
    "  PRIMARY KEY (series, bucket));"
    "COMMIT;";

/// How long a schema step or an append retries a lock that SQLite refused without waiting.
static const NSTimeInterval kLockPatience = 10;

static BOOL Busy(int rc) { rc &= 0xff; return rc == SQLITE_BUSY || rc == SQLITE_LOCKED; }

/// Runs sql, and again while the file is locked, until kLockPatience has passed.
/// On a new file, setting WAL mode needs an exclusive lock. When two processes ask at once, SQLite answers one of
/// them "database is locked" at once instead of calling the busy handler, so a plain exec loses that race.
static int ExecPatiently(sqlite3 *db, const char *sql, char **err) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kLockPatience];
    for (;;) {
        if (err && *err) { sqlite3_free(*err); *err = NULL; }
        int rc = sqlite3_exec(db, sql, NULL, NULL, err);
        if (!Busy(rc) || until.timeIntervalSinceNow < 0) return rc;
        sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);   // a schema transaction that stopped part way
        usleep(20000 + arc4random_uniform(30000));
    }
}

@implementation MMLog {
    sqlite3 *_db;
    dispatch_queue_t _q;
}

// The shared log. Opening it may wait up to 15 seconds for another process's lock: the 5-second busy timeout,
// then kLockPatience. So the app opens it on its own queue, and main only reads the pointer once it is set.
static MMLog *gShared;                       // under gSharedLock, which guards the pointer only, never the open
static os_unfair_lock gSharedLock = OS_UNFAIR_LOCK_INIT;
static atomic_bool gOffMainOnly;             // set by MMLogOpenOffMain
static atomic_uint gMainOpens;
static atomic_uint gMainWrites;

static dispatch_queue_t OpenQueue(void) { return MMQueue(@"core", @"log.open", QOS_CLASS_UTILITY); }

static MMLog *SharedIfOpen(void) {
    os_unfair_lock_lock(&gSharedLock);
    MMLog *s = gShared;
    os_unfair_lock_unlock(&gSharedLock);
    return s;
}

+ (instancetype)shared {
    // In the app main never opens the log: it gets the log once the open queue has it, and nil before.
    if (NSThread.isMainThread && atomic_load(&gOffMainOnly)) return SharedIfOpen();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MMLog *s = [[MMLog alloc] initWithPath:[MMSupportDir() stringByAppendingPathComponent:@"minmacs.sqlite"]];
        os_unfair_lock_lock(&gSharedLock);
        gShared = s;
        os_unfair_lock_unlock(&gSharedLock);
    });
    return SharedIfOpen();
}

void MMLogOpenOffMain(void) {
    atomic_store(&gOffMainOnly, true);
    dispatch_async(OpenQueue(), ^{ (void)[MMLog shared]; });
}

void MMLogWhenOpen(MMLogWork work) {
    if (!work) return;
    if (!NSThread.isMainThread || !atomic_load(&gOffMainOnly)) { work(MMLog.shared); return; }
    dispatch_async(OpenQueue(), ^{ work(MMLog.shared); });
}

NSUInteger MMLogMainThreadOpens(void) { return atomic_load(&gMainOpens); }
NSUInteger MMLogMainThreadWrites(void) { return atomic_load(&gMainWrites); }

- (instancetype)initWithPath:(NSString *)path {
    if (!(self = [super init])) return nil;
    if (NSThread.isMainThread) atomic_fetch_add(&gMainOpens, 1);
    _q = MMQueue(@"core", @"log", QOS_CLASS_UTILITY);   // one queue for every log in this process
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (sqlite3_open_v2(path.fileSystemRepresentation, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        NSLog(@"MinMacs: cannot open the log at %@: %s", path, _db ? sqlite3_errmsg(_db) : "no memory");
        sqlite3_close(_db); _db = NULL;
        return self;
    }
    // The app and the CLI write at the same time. WAL lets readers run beside a writer, and the timeout waits out a lock.
    sqlite3_busy_timeout(_db, 5000);
    const char *steps[] = {kWAL, kSizeLimit, kSchema};
    for (size_t i = 0; i < sizeof steps / sizeof *steps; i++) {
        char *err = NULL;
        if (ExecPatiently(_db, steps[i], &err) != SQLITE_OK) NSLog(@"MinMacs: log schema: %s", err ?: sqlite3_errmsg(_db));
        sqlite3_free(err);
    }
    return self;
}

- (void)dealloc { if (_db) sqlite3_close(_db); }

static void BindText(sqlite3_stmt *st, int i, NSString *s) {
    if (s) sqlite3_bind_text(st, i, s.UTF8String, -1, SQLITE_TRANSIENT); else sqlite3_bind_null(st, i);
}

static NSString *Text(sqlite3_stmt *st, int i) {
    const unsigned char *t = sqlite3_column_text(st, i);
    return t ? @((const char *)t) : nil;
}

static MMLogEntry *EntryFrom(sqlite3_stmt *st) {
    MMLogEntry *e = [MMLogEntry new];
    e.row = sqlite3_column_int64(st, 0);
    e.rid = Text(st, 1); e.table = Text(st, 2); e.expert = Text(st, 3); e.subject = Text(st, 4); e.state = Text(st, 5);
    e.at = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(st, 6)];
    NSString *body = Text(st, 7);
    id j = body ? [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    e.body = [j isKindOfClass:NSDictionary.class] ? j : @{};
    return e;
}

static const char *kColumns = "row, rid, tbl, expert, subject, state, at, body";

- (MMLogEntry *)append:(NSString *)table rid:(NSString *)rid expert:(NSString *)expert subject:(NSString *)subject
                 state:(NSString *)state body:(NSDictionary *)body {
    if (!_db || !table.length) return nil;
    NSString *r = rid.length ? rid : NSUUID.UUID.UUIDString.lowercaseString;
    NSData *json = body && [NSJSONSerialization isValidJSONObject:body] ? [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingSortedKeys error:nil] : nil;
    NSString *bodyText = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    double at = NSDate.date.timeIntervalSince1970;
    if (NSThread.isMainThread && atomic_load(&gOffMainOnly)) atomic_fetch_add(&gMainWrites, 1);
    __block MMLogEntry *e = nil;
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO rows (rid, tbl, expert, subject, state, at, body) VALUES (?,?,?,?,?,?,?) RETURNING %s", kColumns];
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) { NSLog(@"MinMacs: log append: %s", sqlite3_errmsg(self->_db)); return; }
        BindText(st, 1, r); BindText(st, 2, table); BindText(st, 3, expert); BindText(st, 4, subject); BindText(st, 5, state);
        sqlite3_bind_double(st, 6, at); BindText(st, 7, bodyText);
        // A lock SQLite refused without waiting wrote nothing, so the insert runs again.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kLockPatience];
        int rc;
        while (Busy(rc = sqlite3_step(st)) && until.timeIntervalSinceNow > 0) { sqlite3_reset(st); usleep(20000 + arc4random_uniform(30000)); }
        if (rc == SQLITE_ROW) e = EntryFrom(st);
        else NSLog(@"MinMacs: log append: %s", sqlite3_errmsg(self->_db));
        // Stepped to the end, so the insert commits here and the WAL checkpoint can run.
        while (sqlite3_step(st) == SQLITE_ROW) {}
        sqlite3_finalize(st);
    });
    return e;
}

static _Atomic NSUInteger gMainQueries;
NSUInteger MMLogMainThreadQueries(void) { return gMainQueries; }

/// Runs a query with text and double arguments and collects the rows.
- (NSArray<MMLogEntry *> *)select:(NSString *)sql args:(NSArray *)args {
    if (NSThread.isMainThread) gMainQueries++;
    if (!_db) return @[];
    NSMutableArray *out = [NSMutableArray new];
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) { NSLog(@"MinMacs: log query: %s", sqlite3_errmsg(self->_db)); return; }
        for (NSUInteger i = 0; i < args.count; i++) {
            id a = args[i];
            if ([a isKindOfClass:NSNumber.class]) sqlite3_bind_double(st, (int)i + 1, [a doubleValue]); else BindText(st, (int)i + 1, a);
        }
        while (sqlite3_step(st) == SQLITE_ROW) [out addObject:EntryFrom(st)];
        sqlite3_finalize(st);
    });
    return out;
}

- (NSArray<MMLogEntry *> *)latest:(NSString *)table expert:(NSString *)expert subject:(NSString *)subject
                            since:(NSDate *)since limit:(NSUInteger)limit {
    // The newest row of each rid in the table, then the filters on that row, so a record whose state moved shows once.
    NSMutableString *sql = [NSMutableString stringWithFormat:
        @"SELECT %s FROM rows WHERE row IN (SELECT MAX(row) FROM rows WHERE tbl = ? GROUP BY rid)", kColumns];
    NSMutableArray *args = [NSMutableArray arrayWithObject:table ?: @""];
    if (expert) { [sql appendString:@" AND expert = ?"]; [args addObject:expert]; }
    if (subject) { [sql appendString:@" AND subject = ?"]; [args addObject:subject]; }
    if (since) { [sql appendString:@" AND at >= ?"]; [args addObject:@(since.timeIntervalSince1970)]; }
    [sql appendString:@" ORDER BY row DESC"];
    if (limit) [sql appendFormat:@" LIMIT %lu", (unsigned long)limit];
    return [self select:sql args:args];
}

- (NSArray<MMLogEntry *> *)history:(NSString *)rid {
    return [self select:[NSString stringWithFormat:@"SELECT %s FROM rows WHERE rid = ? ORDER BY row", kColumns] args:@[rid ?: @""]];
}

- (NSArray<MMLogEntry *> *)rows:(NSArray<NSString *> *)tables before:(int64_t)before limit:(NSUInteger)limit {
    if (!tables.count || !limit) return @[];
    // One part per table, each a range read of rows_tbl from `before` down, at most `limit` rows. The parts are put
    // together and the newest `limit` of them kept, so the read never looks at more than tables x limit rows.
    NSMutableArray *parts = [NSMutableArray new], *args = [NSMutableArray new];
    double top = before > 0 ? (double)before : 9.0e18;
    for (NSString *t in tables) {
        [parts addObject:[NSString stringWithFormat:@"SELECT * FROM (SELECT %s FROM rows WHERE tbl = ? AND row < ? ORDER BY row DESC LIMIT %lu)",
                                                    kColumns, (unsigned long)limit]];
        [args addObject:t]; [args addObject:@(top)];
    }
    NSString *sql = [NSString stringWithFormat:@"%@ ORDER BY row DESC LIMIT %lu", [parts componentsJoinedByString:@" UNION ALL "], (unsigned long)limit];
    return [self select:sql args:args];
}

- (void)addPoint:(NSString *)series value:(double)value at:(NSDate *)at bucket:(NSTimeInterval)bucket {
    if (!_db || !series.length) return;
    double t = (at ?: NSDate.date).timeIntervalSince1970;
    long long b = bucket > 0 ? (long long)floor(t / bucket) : (long long)floor(t);
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, "INSERT OR REPLACE INTO points (series, bucket, at, value) VALUES (?,?,?,?)", -1, &st, NULL) != SQLITE_OK) return;
        BindText(st, 1, series); sqlite3_bind_int64(st, 2, b); sqlite3_bind_double(st, 3, t); sqlite3_bind_double(st, 4, value);
        if (sqlite3_step(st) != SQLITE_DONE) NSLog(@"MinMacs: log point: %s", sqlite3_errmsg(self->_db));
        sqlite3_finalize(st);
    });
}

- (NSData *)points:(NSString *)series since:(NSDate *)since {
    NSMutableData *out = [NSMutableData new];
    if (!_db) return out;
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT at, value FROM points WHERE series = ? AND at >= ? ORDER BY at", -1, &st, NULL) != SQLITE_OK) return;
        BindText(st, 1, series ?: @""); sqlite3_bind_double(st, 2, since ? since.timeIntervalSince1970 : -INFINITY);
        while (sqlite3_step(st) == SQLITE_ROW) {
            MMTrendPoint p = { sqlite3_column_double(st, 0), sqlite3_column_double(st, 1) };
            [out appendBytes:&p length:sizeof p];
        }
        sqlite3_finalize(st);
    });
    return out;
}

- (NSUInteger)prunePoints:(NSString *)series before:(NSDate *)before {
    if (!_db || !series.length || !before) return 0;
    __block NSUInteger gone = 0;
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, "DELETE FROM points WHERE series = ? AND at < ?", -1, &st, NULL) != SQLITE_OK) return;
        BindText(st, 1, series); sqlite3_bind_double(st, 2, before.timeIntervalSince1970);
        if (sqlite3_step(st) == SQLITE_DONE) gone = (NSUInteger)sqlite3_changes(self->_db);
        else NSLog(@"MinMacs: log prune: %s", sqlite3_errmsg(self->_db));
        sqlite3_finalize(st);
    });
    return gone;
}

@end

#pragma mark - Settings and keeps

NSString *const MMLogSettingTable = @"setting";
NSString *const MMLogKeepTable = @"keep";

/// A value as a row holds it: text, a number or a yes and no, and null for none.
static id Plain(id v) {
    if (!v || v == NSNull.null) return NSNull.null;
    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) return v;
    return [v description] ?: NSNull.null;
}

void MMLogSetting(NSString *key, id old, id now, NSString *by) {
    if (!key.length) return;
    id o = Plain(old), n = Plain(now);
    if ([o isEqual:n]) return;
    NSString *expert = [key componentsSeparatedByString:@"."].firstObject;
    NSDictionary *body = @{@"key": key, @"old": o, @"new": n, @"by": by.length ? by : @"unknown"};
    MMLogWhenOpen(^(MMLog *log) { [log append:MMLogSettingTable rid:nil expert:expert subject:key state:@"set" body:body]; });
}

void MMSetSetting(NSString *key, id value, NSString *by) {
    if (!key.length) return;
    id old = MMPref(key);
    MMSetPref(key, value);
    MMLogSetting(key, old, value, by);
}

#pragma mark - Runs

NSString *const MMLogRunTable = @"run";
NSString *const MMLogRunFixEverything = @"fix-everything";

NSDictionary *MMLogRunSkip(NSString *subject, NSString *why, NSString *as) {
    return @{@"subject": subject.length ? subject : @"something", @"why": why.length ? why : @"it did not run", @"as": as.length ? as : @"blocked"};
}

void MMLogRun(NSString *what, NSString *by, NSInteger planned, NSInteger done, NSArray<NSDictionary *> *skipped, uint64_t memoryBack, uint64_t diskBack) {
    if (!what.length) return;
    NSDictionary *body = @{@"what": what, @"by": by.length ? by : @"unknown", @"planned": @(MAX(planned, 0)), @"done": @(MAX(done, 0)),
                           @"skipped": skipped ?: @[], @"gains": @{@"memory": @(memoryBack), @"disk": @(diskBack)}};
    NSString *expert = [what isEqualToString:MMLogRunFixEverything] ? @"core" : what;
    MMLogWhenOpen(^(MMLog *log) { [log append:MMLogRunTable rid:nil expert:expert subject:what state:@"ended" body:body]; });
}

NSString *MMLogStamp(void) {
    NSString *base = [MMSupportDir() stringByAppendingPathComponent:@"minmacs.sqlite"];
    NSMutableString *out = [NSMutableString new];
    for (NSString *p in @[base, [base stringByAppendingString:@"-wal"]]) {
        struct stat st;
        if (stat(p.fileSystemRepresentation, &st) != 0) { [out appendString:@"-|"]; continue; }
        [out appendFormat:@"%lld.%ld:%lld|", (long long)st.st_ctimespec.tv_sec, st.st_ctimespec.tv_nsec, (long long)st.st_size];
    }
    return out;
}
