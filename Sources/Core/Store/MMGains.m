// The kept log of what came back, MMGains.h. One table, gains, in minmacs.sqlite beside MMLog's rows.
// Unlike the log's rows it is not append-only: a row is marked undone, a Trash row is settled, and old rows drop.
// It has its own connection on its own queue, so it never waits behind the log's queue.
#import "Core/Store/MMGains.h"
#import "Core/Store/MMStore.h"
#import "Core/Runtime/MMRuntime.h"
#import <sqlite3.h>
#import <sys/stat.h>
#import <errno.h>

NSString *const MMGainServer = @"server", *const MMGainApp = @"app", *const MMGainTab = @"tab", *const MMGainHelper = @"helper",
    *const MMGainCache = @"cache", *const MMGainWorktree = @"worktree", *const MMGainWorkstream = @"workstream";
NSString *const MMGainByYou = @"you", *const MMGainByAuto = @"auto", *const MMGainByRun = @"run";
NSString *const MMGainDiskNone = @"none", *const MMGainDiskFreed = @"freed", *const MMGainDiskTrash = @"trash",
    *const MMGainDiskPutBack = @"put-back";
const NSInteger MMGainsKeepDays = 30;

// Version 0 is a minmacs.sqlite with no gains table, as every build before this one left it. The step to version 1
// adds the table and its index and records the version, in one IMMEDIATE transaction, so two processes that open
// an old file at once wait for each other. The log's own tables are not touched.
static const char *kWAL = "PRAGMA journal_mode=WAL;";
static const char *kSchema =
    "BEGIN IMMEDIATE;"
    "CREATE TABLE IF NOT EXISTS gains ("
    "  rid TEXT PRIMARY KEY, run TEXT, kind TEXT NOT NULL, part TEXT, who TEXT NOT NULL, by TEXT, expert TEXT, subject TEXT,"
    "  workstream TEXT, at REAL NOT NULL, memory INTEGER NOT NULL DEFAULT 0, disk INTEGER NOT NULL DEFAULT 0,"
    "  disk_state TEXT NOT NULL, trashed TEXT, items INTEGER NOT NULL DEFAULT 1, undone_at REAL, settled_at REAL);"
    "CREATE INDEX IF NOT EXISTS gains_at ON gains(at);"
    "CREATE TABLE IF NOT EXISTS gains_schema (version INTEGER NOT NULL);"
    "INSERT INTO gains_schema (version) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM gains_schema);"
    "COMMIT;";

static BOOL Busy(int rc) { rc &= 0xff; return rc == SQLITE_BUSY || rc == SQLITE_LOCKED; }

/// Runs sql again while the file is locked, for up to 10 seconds, as MMLog does for its schema.
static int ExecPatiently(sqlite3 *db, const char *sql) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    for (;;) {
        char *err = NULL;
        int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
        if (rc != SQLITE_OK && !Busy(rc)) NSLog(@"MinMacs: gains schema: %s", err ?: sqlite3_errmsg(db));
        sqlite3_free(err);
        if (!Busy(rc) || until.timeIntervalSinceNow < 0) return rc;
        sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
        usleep(20000 + arc4random_uniform(30000));
    }
}

#pragma mark - One row

@interface MMGain ()
@property (readwrite, copy) NSString *rid, *run, *kind, *part, *who, *by, *expert, *subject, *workstream, *diskState;
@property (readwrite) NSDate *at;
@property (readwrite) uint64_t memoryBytes, diskBytes;
@property (readwrite) NSInteger items;
@property (readwrite) BOOL undone;
@property (copy) NSArray *trashed;
@end

@implementation MMGain
- (NSDictionary *)json {
    BOOL freed = [self.diskState isEqualToString:MMGainDiskFreed], inTrash = [self.diskState isEqualToString:MMGainDiskTrash];
    return @{@"rid": self.rid ?: @"", @"run": self.run ?: NSNull.null, @"kind": self.kind ?: @"", @"part": self.part ?: NSNull.null,
             @"who": self.who ?: @"", @"by": self.by ?: @"", @"expert": self.expert ?: @"", @"subject": self.subject ?: @"",
             @"workstream": self.workstream ?: NSNull.null, @"at": @(self.at.timeIntervalSince1970),
             @"memoryBack": @(self.undone ? 0 : self.memoryBytes), @"diskBack": @(freed && !self.undone ? self.diskBytes : 0),
             @"diskInTrash": @(inTrash && !self.undone ? self.diskBytes : 0), @"diskState": self.diskState ?: MMGainDiskNone,
             @"items": @(self.items), @"undone": @(self.undone)};
}
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@ %@ mem %llu disk %llu %@", self.rid, self.kind, self.who, self.memoryBytes, self.diskBytes, self.diskState]; }
@end

/// A running total: actions counts a run of several once, by its run id.
@interface MMGainTotal : NSObject
@property NSMutableSet *actions;
@property NSInteger items;
@property uint64_t memory, disk, trash;
@end
@implementation MMGainTotal
- (instancetype)init { if ((self = [super init])) _actions = [NSMutableSet new]; return self; }
- (void)add:(MMGain *)g {
    [self.actions addObject:g.run ?: g.rid];
    self.items += g.items;
    self.memory += g.memoryBytes;
    if ([g.diskState isEqualToString:MMGainDiskFreed]) self.disk += g.diskBytes;
    if ([g.diskState isEqualToString:MMGainDiskTrash]) self.trash += g.diskBytes;
}
- (NSDictionary *)json {
    return @{@"actions": @(self.actions.count), @"items": @(self.items), @"memoryBack": @(self.memory),
             @"diskBack": @(self.disk), @"diskInTrash": @(self.trash)};
}
@end

static NSDictionary *TotalsJSON(NSDictionary<NSString *, MMGainTotal *> *by) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    [by enumerateKeysAndObjectsUsingBlock:^(NSString *k, MMGainTotal *t, BOOL *stop) { out[k] = [t json]; }];
    return out;
}

#pragma mark - The table

@implementation MMGains {
    sqlite3 *_db;
    dispatch_queue_t _q;
}

+ (instancetype)shared {
    static MMGains *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [[MMGains alloc] initWithPath:[MMSupportDir() stringByAppendingPathComponent:@"minmacs.sqlite"]]; });
    return g;
}

- (instancetype)initWithPath:(NSString *)path {
    if (!(self = [super init])) return nil;
    _q = MMQueue(@"core", @"gains", QOS_CLASS_UTILITY);
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (sqlite3_open_v2(path.fileSystemRepresentation, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        NSLog(@"MinMacs: cannot open the gains table at %@: %s", path, _db ? sqlite3_errmsg(_db) : "no memory");
        sqlite3_close(_db); _db = NULL;
        return self;
    }
    sqlite3_busy_timeout(_db, 5000);
    ExecPatiently(_db, kWAL);
    if (ExecPatiently(_db, kSchema) != SQLITE_OK) { sqlite3_close(_db); _db = NULL; }
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

/// Runs one statement to its end on the queue, retrying a lock SQLite refused without waiting. bind fills it.
- (BOOL)run:(const char *)sql bind:(void (^)(sqlite3_stmt *st))bind {
    if (!_db) return NO;
    __block BOOL ok = NO;
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &st, NULL) != SQLITE_OK) { NSLog(@"MinMacs: gains: %s", sqlite3_errmsg(self->_db)); return; }
        if (bind) bind(st);
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
        int rc;
        while (Busy(rc = sqlite3_step(st)) && until.timeIntervalSinceNow > 0) { sqlite3_reset(st); usleep(20000 + arc4random_uniform(30000)); }
        ok = rc == SQLITE_DONE || rc == SQLITE_ROW;
        if (!ok) NSLog(@"MinMacs: gains: %s", sqlite3_errmsg(self->_db));
        sqlite3_finalize(st);
    });
    return ok;
}

static const char *kColumns = "rid, run, kind, part, who, by, expert, subject, workstream, at, memory, disk, disk_state, trashed, items, undone_at";

static MMGain *GainFrom(sqlite3_stmt *st) {
    MMGain *g = [MMGain new];
    g.rid = Text(st, 0); g.run = Text(st, 1); g.kind = Text(st, 2); g.part = Text(st, 3); g.who = Text(st, 4); g.by = Text(st, 5);
    g.expert = Text(st, 6); g.subject = Text(st, 7); g.workstream = Text(st, 8);
    g.at = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(st, 9)];
    g.memoryBytes = (uint64_t)MAX(sqlite3_column_int64(st, 10), 0);
    g.diskBytes = (uint64_t)MAX(sqlite3_column_int64(st, 11), 0);
    g.diskState = Text(st, 12) ?: MMGainDiskNone;
    NSString *t = Text(st, 13);
    id j = t ? [NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    g.trashed = [j isKindOfClass:NSArray.class] ? j : @[];
    g.items = (NSInteger)sqlite3_column_int64(st, 14);
    g.undone = sqlite3_column_type(st, 15) != SQLITE_NULL;
    return g;
}

- (NSArray<MMGain *> *)select:(NSString *)where args:(NSArray *)args {
    if (!_db) return @[];
    NSMutableArray *out = [NSMutableArray new];
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM gains WHERE %@ ORDER BY at DESC, rowid DESC", kColumns, where];
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) { NSLog(@"MinMacs: gains: %s", sqlite3_errmsg(self->_db)); return; }
        for (NSUInteger i = 0; i < args.count; i++) {
            if ([args[i] isKindOfClass:NSNumber.class]) sqlite3_bind_double(st, (int)i + 1, [args[i] doubleValue]); else BindText(st, (int)i + 1, args[i]);
        }
        while (sqlite3_step(st) == SQLITE_ROW) [out addObject:GainFrom(st)];
        sqlite3_finalize(st);
    });
    return out;
}

/// The trashed items with the inode each has in the Trash now, so an item put back by hand can be told from a new
/// item an app made at the same path.
static NSArray *WithInodes(NSArray<NSDictionary *> *trashed) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *t in trashed) {
        if (![t isKindOfClass:NSDictionary.class] || ![t[@"to"] isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *x = [t mutableCopy];
        struct stat s;
        if (lstat([t[@"to"] fileSystemRepresentation], &s) == 0) { x[@"dev"] = @((long long)s.st_dev); x[@"ino"] = @((unsigned long long)s.st_ino); }
        [out addObject:x];
    }
    return out;
}

- (BOOL)add:(NSString *)rid run:(NSString *)run kind:(NSString *)kind part:(NSString *)part who:(NSString *)who by:(NSString *)by
     expert:(NSString *)expert subject:(NSString *)subject workstream:(NSString *)workstream at:(NSDate *)at
     memory:(uint64_t)memory disk:(uint64_t)disk diskState:(NSString *)diskState trashed:(NSArray<NSDictionary *> *)trashed
      items:(NSInteger)items {
    if (!rid.length || !kind.length || !who.length) return NO;
    NSArray *withInodes = trashed.count ? WithInodes(trashed) : nil;
    NSData *tj = withInodes.count ? [NSJSONSerialization dataWithJSONObject:withInodes options:NSJSONWritingSortedKeys error:nil] : nil;
    NSString *trashText = tj ? [[NSString alloc] initWithData:tj encoding:NSUTF8StringEncoding] : nil;
    double t = (at ?: NSDate.date).timeIntervalSince1970;
    BOOL ok = [self run:"INSERT OR REPLACE INTO gains (rid, run, kind, part, who, by, expert, subject, workstream, at, memory, disk, disk_state, trashed, items)"
                         " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)" bind:^(sqlite3_stmt *st) {
        BindText(st, 1, rid); BindText(st, 2, run); BindText(st, 3, kind); BindText(st, 4, part); BindText(st, 5, who); BindText(st, 6, by);
        BindText(st, 7, expert); BindText(st, 8, subject); BindText(st, 9, workstream); sqlite3_bind_double(st, 10, t);
        sqlite3_bind_int64(st, 11, (sqlite3_int64)MIN(memory, (uint64_t)INT64_MAX)); sqlite3_bind_int64(st, 12, (sqlite3_int64)MIN(disk, (uint64_t)INT64_MAX));
        BindText(st, 13, diskState ?: MMGainDiskNone); BindText(st, 14, trashText); sqlite3_bind_int64(st, 15, MAX(items, 0));
    }];
    [self dropOld:NSDate.date];
    return ok;
}

- (void)takeBack:(NSString *)rid {
    if (!rid.length) return;
    double now = NSDate.date.timeIntervalSince1970;
    [self run:"UPDATE gains SET undone_at = ? WHERE rid = ? AND undone_at IS NULL" bind:^(sqlite3_stmt *st) {
        sqlite3_bind_double(st, 1, now); BindText(st, 2, rid);
    }];
}

- (NSInteger)dropOld:(NSDate *)now {
    if (!_db) return 0;
    double cut = (now ?: NSDate.date).timeIntervalSince1970 - MMGainsKeepDays * 86400.0;
    __block NSInteger gone = 0;
    [self run:"DELETE FROM gains WHERE at < ?" bind:^(sqlite3_stmt *st) { sqlite3_bind_double(st, 1, cut); }];
    dispatch_sync(_q, ^{ gone = sqlite3_changes(self->_db); });
    return gone;
}

/// The new state of a row in the Trash: still trash, freed once every item is gone from the Trash, or put back
/// when an item is at its old path again with the inode it had in the Trash.
static NSString *Settle(MMGain *g) {
    if (!g.trashed.count) return MMGainDiskTrash;
    BOOL putBack = NO;
    for (NSDictionary *t in g.trashed) {
        struct stat s;
        // Only "no such file" says it is gone. A refused look, as the Trash may answer without Full Disk Access,
        // cannot verify, so the bytes stay in the Trash.
        if (lstat([t[@"to"] fileSystemRepresentation], &s) == 0 || errno != ENOENT) return MMGainDiskTrash;
        NSString *from = [t[@"from"] isKindOfClass:NSString.class] ? t[@"from"] : nil;
        if (from && t[@"ino"] && lstat(from.fileSystemRepresentation, &s) == 0 &&
            (unsigned long long)s.st_ino == [t[@"ino"] unsignedLongLongValue] && (long long)s.st_dev == [t[@"dev"] longLongValue]) putBack = YES;
    }
    return putBack ? MMGainDiskPutBack : MMGainDiskFreed;
}

- (void)settleTrash {
    NSArray<MMGain *> *waiting = [self select:@"disk_state = 'trash' AND undone_at IS NULL" args:@[]];
    double now = NSDate.date.timeIntervalSince1970;
    for (MMGain *g in waiting) {
        NSString *state = Settle(g);
        if ([state isEqualToString:MMGainDiskTrash]) continue;
        [self run:"UPDATE gains SET disk_state = ?, settled_at = ? WHERE rid = ? AND disk_state = 'trash'" bind:^(sqlite3_stmt *st) {
            BindText(st, 1, state); sqlite3_bind_double(st, 2, now); BindText(st, 3, g.rid);
        }];
    }
}

- (NSArray<MMGain *> *)since:(NSDate *)since undone:(BOOL)undone {
    [self dropOld:NSDate.date];
    [self settleTrash];
    NSString *where = undone ? @"at >= ?" : @"at >= ? AND undone_at IS NULL";
    return [self select:where args:@[@(since ? since.timeIntervalSince1970 : 0)]];
}

- (MMGain *)gain:(NSString *)rid {
    return [self select:@"rid = ?" args:@[rid ?: @""]].firstObject;
}

- (NSInteger)schemaVersion {
    if (!_db) return 0;
    __block NSInteger v = 0;
    dispatch_sync(_q, ^{
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT MAX(version) FROM gains_schema", -1, &st, NULL) != SQLITE_OK) return;
        if (sqlite3_step(st) == SQLITE_ROW) v = (NSInteger)sqlite3_column_int64(st, 0);
        sqlite3_finalize(st);
    });
    return v;
}

#pragma mark - The summary

- (NSDictionary *)summary:(NSInteger)days now:(NSDate *)now {
    now = now ?: NSDate.date;
    days = MAX(1, MIN(days, MMGainsKeepDays));
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *today = [cal startOfDayForDate:now];
    NSDate *start = [cal dateByAddingUnit:NSCalendarUnitDay value:-(days - 1) toDate:today options:0];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.calendar = cal; fmt.timeZone = cal.timeZone; fmt.dateFormat = @"yyyy-MM-dd";

    NSMutableArray *dayStarts = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMGainTotal *> *byDay = [NSMutableDictionary new];
    for (NSInteger i = 0; i < days; i++) {
        NSDate *d = [cal dateByAddingUnit:NSCalendarUnitDay value:i toDate:start options:0];
        [dayStarts addObject:d];
        byDay[[fmt stringFromDate:d]] = [MMGainTotal new];
    }
    MMGainTotal *total = [MMGainTotal new], *todays = [MMGainTotal new];
    NSMutableDictionary<NSString *, MMGainTotal *> *byKind = [NSMutableDictionary new], *byWho = [NSMutableDictionary new], *byWs = [NSMutableDictionary new];
    for (NSString *k in @[MMGainServer, MMGainApp, MMGainTab, MMGainHelper, MMGainCache, MMGainWorktree, MMGainWorkstream]) byKind[k] = [MMGainTotal new];
    for (NSString *w in @[MMGainByYou, MMGainByAuto, MMGainByRun]) byWho[w] = [MMGainTotal new];
    NSMutableArray *rows = [NSMutableArray new];
    for (MMGain *g in [self since:start undone:NO]) {
        if ([g.at compare:now] == NSOrderedDescending) continue;
        NSString *day = [fmt stringFromDate:g.at];
        if (!byDay[day]) continue;
        [byDay[day] add:g];
        [total add:g];
        if ([[cal startOfDayForDate:g.at] isEqualToDate:today]) [todays add:g];
        if (!byKind[g.kind]) byKind[g.kind] = [MMGainTotal new];
        [byKind[g.kind] add:g];
        if (!byWho[g.who]) byWho[g.who] = [MMGainTotal new];
        [byWho[g.who] add:g];
        NSString *ws = g.workstream ?: @"none";
        if (!byWs[ws]) byWs[ws] = [MMGainTotal new];
        [byWs[ws] add:g];
        [rows addObject:[g json]];
    }
    NSMutableArray *dayList = [NSMutableArray new];
    for (NSDate *d in dayStarts) {
        NSMutableDictionary *x = [[byDay[[fmt stringFromDate:d]] json] mutableCopy];
        x[@"day"] = [fmt stringFromDate:d];
        x[@"start"] = @(d.timeIntervalSince1970);
        [dayList addObject:x];
    }
    return @{@"days": @(days), @"since": @(start.timeIntervalSince1970), @"now": @(now.timeIntervalSince1970),
             @"keepDays": @(MMGainsKeepDays), @"schema": @([self schemaVersion]),
             @"meaning": @{@"memoryBack": @"the footprint of the process trees a stop or a quit ended, read right before it ran",
                           @"diskBack": @"what MMSizer said deleting frees, for items deleted for good or gone from the Trash",
                           @"diskInTrash": @"what MMSizer said deleting frees, for items still in the Trash; not back yet",
                           @"actions": @"finished actions, with a run of several such as Wrap Up counted once"},
             @"today": [todays json], @"total": [total json], @"byDay": dayList,
             @"byKind": TotalsJSON(byKind), @"byWho": TotalsJSON(byWho), @"byWorkstream": TotalsJSON(byWs), @"gains": rows};
}

@end
