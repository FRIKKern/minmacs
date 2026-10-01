#import "Hosts.h"
#import <libproc.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

NSString *const MMCmuxBundleID = @"com.cmuxterm.app";

static const off_t kTailBytes = 2 * 1024 * 1024;   // never read more of workstream.jsonl than this
static const NSTimeInterval kFresh = 60;           // a working event counts for this long

#pragma mark - Key-filtered JSON scanner
// A cursor over bytes. Every value whose key is not wanted is stepped over, never copied.

typedef struct { const char *p, *end; } Cur;
static NSMutableArray *Blank(int n) { NSMutableArray *a = [NSMutableArray new]; while (n--) [a addObject:NSNull.null]; return a; }

static void WS(Cur *c) { while (c->p < c->end && (*c->p == ' ' || *c->p == '\t' || *c->p == '\n' || *c->p == '\r')) c->p++; }

/// Steps over a string. Leaves the raw bytes between the quotes in [*s, *e). NO if malformed.
static BOOL StrSpan(Cur *c, const char **s, const char **e, BOOL *escaped) {
    if (c->p >= c->end || *c->p != '"') return NO;
    c->p++; *s = c->p; *escaped = NO;
    while (c->p < c->end) {
        if (*c->p == '\\') { *escaped = YES; c->p += 2; continue; }
        if (*c->p == '"') { *e = c->p; c->p++; return YES; }
        c->p++;
    }
    return NO;
}

/// Steps over any value: string, number, literal, or a whole object/array (by depth, skipping strings).
static BOOL SkipValue(Cur *c) {
    WS(c);
    if (c->p >= c->end) return NO;
    if (*c->p == '"') { const char *s, *e; BOOL x; return StrSpan(c, &s, &e, &x); }
    if (*c->p == '{' || *c->p == '[') {
        int depth = 0;
        while (c->p < c->end) {
            char ch = *c->p;
            if (ch == '"') { const char *s, *e; BOOL x; if (!StrSpan(c, &s, &e, &x)) return NO; continue; }
            c->p++;
            if (ch == '{' || ch == '[') depth++;
            else if ((ch == '}' || ch == ']') && --depth == 0) return YES;
        }
        return NO;
    }
    while (c->p < c->end && *c->p != ',' && *c->p != '}' && *c->p != ']' && *c->p != ' ' && *c->p != '\n' && *c->p != '\r') c->p++;
    return YES;
}

/// Parses one object, keeping only the values of `names`. A kept value is an NSString or an NSNumber
/// (nested values under a wanted key are skipped, not kept). out[i] stays NSNull when a key is absent.
static BOOL ParseKeys(Cur *c, const char *const *names, int n, NSMutableArray *out) {
    WS(c);
    if (c->p >= c->end || *c->p != '{') return NO;
    c->p++;
    for (;;) {
        WS(c);
        if (c->p >= c->end) return NO;
        if (*c->p == '}') { c->p++; return YES; }
        if (*c->p == ',') { c->p++; continue; }
        const char *ks, *ke; BOOL kx;
        if (!StrSpan(c, &ks, &ke, &kx)) return NO;
        WS(c);
        if (c->p >= c->end || *c->p != ':') return NO;
        c->p++; WS(c);
        int want = -1;
        if (!kx) for (int i = 0; i < n; i++) if ((size_t)(ke - ks) == strlen(names[i]) && !memcmp(ks, names[i], ke - ks)) { want = i; break; }
        if (want >= 0 && c->p < c->end && *c->p == '"') {
            const char *vs, *ve; BOOL vx;
            const char *start = c->p;
            if (!StrSpan(c, &vs, &ve, &vx)) return NO;
            if (!vx) out[want] = [[NSString alloc] initWithBytes:vs length:ve - vs encoding:NSUTF8StringEncoding];
            else out[want] = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:start length:c->p - start]
                                                             options:NSJSONReadingFragmentsAllowed error:nil];
        } else if (want >= 0 && c->p < c->end && (*c->p == '-' || (*c->p >= '0' && *c->p <= '9'))) {
            char buf[40]; size_t len = 0;
            while (c->p < c->end && len < sizeof buf - 1 && strchr("0123456789+-.eE", *c->p)) buf[len++] = *c->p++;
            buf[len] = 0;
            out[want] = @(strtod(buf, NULL));
        } else if (!SkipValue(c)) return NO;
    }
}

#pragma mark - Reader

/// What the latest events of one session add up to.
typedef NS_ENUM(NSInteger, MMCmuxClass) {
    MMCNothing = 0,     // stop, session start/end, anything unknown: says nothing
    MMCWorking,         // prompt submitted, tool use
    MMCBlockedPermission, MMCBlockedQuestion, MMCBlockedPlan, MMCBlockedNotify,
};

static BOOL IsBlocked(MMCmuxClass k) { return k >= MMCBlockedPermission; }

@interface MMCmuxEvent : NSObject
@property MMCmuxClass klass;
@property (strong) NSDate *at;
@end
@implementation MMCmuxEvent @end

@interface MMCmuxSession : NSObject
@property (copy) NSString *sessionID;
@property pid_t pid;
@property double updatedAt;
@end
@implementation MMCmuxSession @end

@implementation MMCmuxReader {
    // Both files are re-read only when they changed since the last call.
    struct timespec _hookMTime; off_t _hookSize; NSArray<MMCmuxSession *> *_sessions; NSString *_hookPath;
    struct timespec _wsMTime;   off_t _wsSize;   NSDictionary<NSString *, MMCmuxEvent *> *_events; NSString *_wsPath;
}

+ (BOOL)cmuxRunning { return [NSRunningApplication runningApplicationsWithBundleIdentifier:MMCmuxBundleID].count > 0; }

/// Reads at most `max` bytes from the end of a file. The buffer is wiped by the caller after use.
static NSMutableData *ReadTail(NSString *path, off_t max, struct timespec *mtime, off_t *size, BOOL *truncated) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return nil;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return nil; }
    *mtime = st.st_mtimespec; *size = st.st_size;
    off_t from = st.st_size > max ? st.st_size - max : 0;
    *truncated = from > 0;
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)(st.st_size - from)];
    ssize_t got = pread(fd, d.mutableBytes, d.length, from);
    close(fd);
    if (got < 0) return nil;
    d.length = (NSUInteger)got;
    return d;
}
static void Wipe(NSMutableData *d) { memset_s(d.mutableBytes, d.length, 0, d.length); }

static BOOL Same(struct timespec a, off_t as, struct timespec b, off_t bs) { return as == bs && a.tv_sec == b.tv_sec && a.tv_nsec == b.tv_nsec; }
static BOOL Stat(NSString *path, struct timespec *mt, off_t *size) {
    struct stat st; if (stat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return NO;
    *mt = st.st_mtimespec; *size = st.st_size; return YES;
}

- (NSArray<MMCmuxSession *> *)sessionsIn:(NSString *)dir {
    NSString *path = [dir stringByAppendingPathComponent:@"claude-hook-sessions.json"];
    struct timespec mt; off_t size; BOOL trunc;
    if (!Stat(path, &mt, &size)) return @[];
    if ([path isEqualToString:_hookPath] && Same(mt, size, _hookMTime, _hookSize)) return _sessions;
    NSMutableData *raw = ReadTail(path, 4 * 1024 * 1024, &mt, &size, &trunc);   // the file is about 10 KB
    if (!raw || trunc) return @[];
    NSMutableArray *out = [NSMutableArray new];
    static const char *const entryKeys[] = { "pid", "sessionId", "surfaceId", "workspaceId", "updatedAt" };
    Cur c = { raw.bytes, (const char *)raw.bytes + raw.length };
    WS(&c);
    if (c.p < c.end && *c.p == '{') {
        c.p++;
        for (;;) {
            WS(&c);
            if (c.p >= c.end || *c.p == '}') break;
            if (*c.p == ',') { c.p++; continue; }
            const char *ks, *ke; BOOL kx;
            if (!StrSpan(&c, &ks, &ke, &kx)) break;
            WS(&c); if (c.p >= c.end || *c.p != ':') break; c.p++; WS(&c);
            if (!kx && ke - ks == 8 && !memcmp(ks, "sessions", 8) && c.p < c.end && *c.p == '{') {
                c.p++;
                for (;;) {
                    WS(&c);
                    if (c.p >= c.end || *c.p == '}') { if (c.p < c.end) c.p++; break; }
                    if (*c.p == ',') { c.p++; continue; }
                    const char *es, *ee; BOOL ex;
                    if (!StrSpan(&c, &es, &ee, &ex)) break;       // the entry's own key (a session id) is not kept
                    WS(&c); if (c.p >= c.end || *c.p != ':') break; c.p++;
                    NSMutableArray *v = Blank(5);
                    if (!ParseKeys(&c, entryKeys, 5, v)) break;
                    // surfaceId and workspaceId are read as the task says but this reader has no use for them yet.
                    if ([v[0] isKindOfClass:NSNumber.class] && [v[1] isKindOfClass:NSString.class] && [v[0] intValue] > 0) {
                        MMCmuxSession *s = [MMCmuxSession new];
                        s.pid = [v[0] intValue]; s.sessionID = v[1];
                        s.updatedAt = [v[4] isKindOfClass:NSNumber.class] ? [v[4] doubleValue] : 0;
                        [out addObject:s];
                    }
                }
            } else if (!SkipValue(&c)) break;
        }
    }
    Wipe(raw);
    _hookPath = path; _hookMTime = mt; _hookSize = size; _sessions = out;
    return out;
}

static NSDate *ParseTime(NSString *s) {
    static NSISO8601DateFormatter *plain, *frac;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [NSISO8601DateFormatter new];
        frac = [NSISO8601DateFormatter new]; frac.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return [plain dateFromString:s] ?: [frac dateFromString:s];
}

static MMCmuxClass ClassOf(NSString *kind) {
    if ([kind isEqualToString:@"permissionRequest"]) return MMCBlockedPermission;
    if ([kind isEqualToString:@"question"])          return MMCBlockedQuestion;
    if ([kind isEqualToString:@"exitPlan"] || [kind isEqualToString:@"exitPlanMode"]) return MMCBlockedPlan;
    if ([kind isEqualToString:@"notification"])      return MMCBlockedNotify;
    if ([kind isEqualToString:@"userPrompt"] || [kind isEqualToString:@"toolUse"]) return MMCWorking;
    return MMCNothing;   // stop, sessionStart, sessionEnd, and kinds this reader does not know
}

/// Latest event per workstream, from the last 2 MB of the log.
- (NSDictionary<NSString *, MMCmuxEvent *> *)eventsIn:(NSString *)dir {
    NSString *path = [dir stringByAppendingPathComponent:@"workstream.jsonl"];
    struct timespec mt; off_t size; BOOL trunc;
    if (!Stat(path, &mt, &size)) return @{};
    if ([path isEqualToString:_wsPath] && Same(mt, size, _wsMTime, _wsSize)) return _events;
    NSMutableData *raw = ReadTail(path, kTailBytes, &mt, &size, &trunc);
    if (!raw) return @{};

    static const char *const keys[] = { "kind", "createdAt", "workstreamId" };
    NSMutableDictionary<NSString *, NSString *> *lastTime = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSNumber *> *lastClass = [NSMutableDictionary new];
    const char *p = raw.bytes, *end = p + raw.length;
    if (trunc) { const char *nl = memchr(p, '\n', end - p); p = nl ? nl + 1 : end; }   // the first line is cut in half
    while (p < end) {
        const char *nl = memchr(p, '\n', end - p);
        const char *lineEnd = nl ?: end;
        Cur c = { p, lineEnd };
        NSMutableArray *v = Blank(3);
        if (ParseKeys(&c, keys, 3, v) && [v[0] isKindOfClass:NSString.class] && [v[1] isKindOfClass:NSString.class] && [v[2] isKindOfClass:NSString.class]) {
            NSString *ws = v[2];
            MMCmuxClass prev = (MMCmuxClass)[lastClass[ws] integerValue], k;
            if ([v[0] isEqualToString:@"toolResult"]) {
                // In cmux's log this kind is the Notification hook. After a stop it is the idle prompt ("waiting for your input"),
                // which is not a block. In the middle of a turn it is the agent asking for attention.
                k = IsBlocked(prev) ? prev : prev == MMCWorking ? MMCBlockedNotify : MMCNothing;
            } else k = ClassOf(v[0]);
            lastClass[ws] = @(k); lastTime[ws] = v[1];
        }
        p = nl ? nl + 1 : end;
    }
    Wipe(raw);
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *ws in lastClass) {
        NSDate *t = ParseTime(lastTime[ws]);
        if (!t) continue;
        MMCmuxEvent *e = [MMCmuxEvent new]; e.klass = (MMCmuxClass)[lastClass[ws] integerValue]; e.at = t;
        out[ws] = e;
    }
    _wsPath = path; _wsMTime = mt; _wsSize = size; _events = out;
    return out;
}

static NSString *ReasonFor(MMCmuxClass k) {
    switch (k) {
        case MMCBlockedPermission: return @"waiting for permission (cmux)";
        case MMCBlockedQuestion:   return @"waiting for an answer (cmux)";
        case MMCBlockedPlan:       return @"waiting on plan approval (cmux)";
        case MMCBlockedNotify:     return @"needs your attention (cmux)";
        default:                   return @"active turn (cmux)";
    }
}

static NSDate *ProcessStart(pid_t pid) {
    struct proc_bsdinfo bi;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, sizeof bi) != sizeof bi) return nil;
    return [NSDate dateWithTimeIntervalSince1970:bi.pbi_start_tvsec];
}

- (void)addOverridesTo:(NSMutableDictionary<NSNumber *, NSString *> *)overrides
               reasons:(NSMutableDictionary<NSNumber *, NSString *> *)reasons
             directory:(NSString *)directory {
    if (!directory.length && ![MMCmuxReader cmuxRunning]) return;
    NSString *dir = directory.length ? directory : [NSHomeDirectory() stringByAppendingPathComponent:@".cmuxterm"];
    NSArray<MMCmuxSession *> *sessions = [self sessionsIn:dir];
    if (!sessions.count) return;
    NSDictionary<NSString *, MMCmuxEvent *> *events = [self eventsIn:dir];
    if (!events.count) return;

    // Per pid, the newest event of any session that pid has carried (resume and fork share a pid).
    NSMutableDictionary<NSNumber *, MMCmuxEvent *> *latest = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSNumber *> *tie = [NSMutableDictionary new];
    for (MMCmuxSession *s in sessions) {
        MMCmuxEvent *e = events[[@"claude-" stringByAppendingString:s.sessionID]] ?: events[s.sessionID];
        if (!e) continue;
        MMCmuxEvent *cur = latest[@(s.pid)];
        NSComparisonResult r = cur ? [e.at compare:cur.at] : NSOrderedDescending;
        if (r == NSOrderedDescending || (r == NSOrderedSame && s.updatedAt > [tie[@(s.pid)] doubleValue])) { latest[@(s.pid)] = e; tie[@(s.pid)] = @(s.updatedAt); }
    }
    NSDate *now = NSDate.date;
    for (NSNumber *pid in latest) {
        MMCmuxEvent *e = latest[pid];
        if (e.klass == MMCNothing) continue;
        // A store row can outlive its process and its pid can be reused: the event must be newer than the process.
        NSDate *started = ProcessStart(pid.intValue);
        if (!started || [e.at compare:[started dateByAddingTimeInterval:-2]] == NSOrderedAscending) continue;
        if (IsBlocked(e.klass)) { overrides[pid] = @"blocked"; reasons[pid] = ReasonFor(e.klass); }
        else if ([now timeIntervalSinceDate:e.at] < kFresh) { overrides[pid] = @"working"; reasons[pid] = ReasonFor(e.klass); }
    }
}

@end
