// The clutter catalog of P28 to P30: rows as data, the paths they name on this Mac, their state, size, owner and trend.
// Ported from Noo-Noo 0.7:
//   the leak signatures and their liveness gates, internal/leaks/leaks.go, family.go and module.go
//   the safety walls, internal/core/safety.go, made stricter: only a path a listed row names may ever be touched
//   the build targets and their pruned walk, internal/modules/dev/dev.go
//   the trend math, internal/trend/trend.go and internal/heuristics/cache_velocity.go
// Nothing here runs a tool to find a path, deletes a file or runs on main. Scans run on MMQueue(@"core", @"clutter").
#import "Core/Know/MMClutter.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMSessions.h"
#import "Core/Senses/MMSenses.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#include <fnmatch.h>
#include <fts.h>
#include <glob.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <unistd.h>

NSNotificationName const MMClutterDidChangeNotification = @"MMClutterDidChangeNotification";

static const NSTimeInterval kMinEvery = 600;          // no row is scanned more often than every 10 minutes
static const NSTimeInterval kTimerEvery = 300;        // the timer looks for due rows every 5 minutes
static const NSTimeInterval kTrendDays = 30;          // the trend window, as `noo-noo trends --days 30`
static const NSUInteger kWalkMax = 200000;            // a leak tree past this many entries cannot be proven quiet
static const NSInteger kProjectDepth = 6;             // how deep build rows look below a checkout
/// A scratch entry of a session that ended. The session folder is the item then, so the entry is left out of a scan.
static NSString *const kWholeSession = @"its session ended, so the whole session folder goes instead";

NSString *MMClutterClassName(MMClutterClass c) {
    switch (c) {
        case MMClutterCache: return @"cache";
        case MMClutterTool: return @"tool";
        case MMClutterBuild: return @"build";
        case MMClutterData: return @"data";
        case MMClutterLeak: return @"leak";
        case MMClutterReport: return @"report";
    }
    return @"report";
}
static MMClutterClass ClassFrom(NSString *s) {
    NSArray *names = @[@"cache", @"tool", @"build", @"data", @"leak", @"report"];
    NSUInteger i = [names indexOfObject:s ?: @""];
    return i == NSNotFound ? MMClutterReport : (MMClutterClass)i;
}

#pragma mark - Paths

static NSString *Env(NSString *k) {
    NSString *v = NSProcessInfo.processInfo.environment[k];
    return v.length ? v : nil;
}
/// The path with doubled and trailing slashes gone. Never stringByStandardizingPath, which turns /private/var into /var.
static NSString *Clean(NSString *p) {
    if (!p.length) return p;
    NSString *c = [NSString pathWithComponents:p.pathComponents];
    return c.length ? c : p;
}
static NSString *Real(NSString *p) {
    if (!p.length) return p;
    char buf[PATH_MAX];
    return realpath(p.fileSystemRepresentation, buf) ? @(buf) : Clean(p);
}
/// One span in words, for reasons: "3 hours", "2 days".
static NSString *Span(NSTimeInterval s) {
    if (s < 0) s = 0;
    NSInteger n; NSString *w;
    if (s < 90) { n = (NSInteger)s; w = @"second"; }
    else if (s < 90 * 60) { n = (NSInteger)(s / 60); w = @"minute"; }
    else if (s < 36 * 3600) { n = (NSInteger)(s / 3600); w = @"hour"; }
    else { n = (NSInteger)(s / 86400); w = @"day"; }
    return [NSString stringWithFormat:@"%ld %@%@", (long)n, w, n == 1 ? @"" : @"s"];
}
static BOOL Inside(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    if ([folder isEqualToString:@"/"]) return [path hasPrefix:@"/"] && path.length > 1;
    return [path hasPrefix:[folder stringByAppendingString:@"/"]];
}
static BOOL InsideOrSame(NSString *path, NSString *folder) { return [path isEqualToString:folder] || Inside(path, folder); }

NSString *MMClutterRoot(void) {
    NSString *home = Env(@"MINMACS_HOME");
    if (!home) return @"";
    NSString *root = Env(@"MINMACS_CLUTTER_ROOT");
    if (!root) return nil;
    root = Real(root);
    return Inside(root, Real(home)) ? root : nil;   // a test root must sit inside the test's own home
}

NSString *MMClutterHome(void) {
    NSString *root = MMClutterRoot();
    if (!root) return nil;
    return root.length ? [root stringByAppendingPathComponent:@"home"] : Real(NSHomeDirectory());
}

/// An env var's folder. In a test only when it points inside MINMACS_HOME, so the person's own caches never count.
static NSString *EnvPath(NSString *k) {
    NSString *v = Env(k);
    if (!v || ![v hasPrefix:@"/"]) return nil;
    NSString *root = MMClutterRoot();
    if (root.length && !Inside(Real(v), Real(Env(@"MINMACS_HOME")))) return nil;
    return Clean(v);
}

/// pnpm's store-dir from its rc file, the only config pnpm reads it from besides the command line.
static NSString *PnpmStoreFromRC(NSString *home) {
    NSString *rc = [NSString stringWithContentsOfFile:[home stringByAppendingPathComponent:@"Library/Preferences/pnpm/rc"]
                                             encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [rc componentsSeparatedByString:@"\n"]) {
        NSString *l = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![l hasPrefix:@"store-dir"]) continue;
        NSRange eq = [l rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *v = [[l substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([v hasPrefix:@"~/"]) v = [home stringByAppendingPathComponent:[v substringFromIndex:2]];
        if ([v hasPrefix:@"/"]) return Clean(v);
    }
    return nil;
}

NSString *MMCachePathOf(NSString *tool) {
    NSString *home = MMClutterHome();
    if (!home || !tool.length) return nil;
    NSString *(^h)(NSString *) = ^NSString *(NSString *rel) { return [home stringByAppendingPathComponent:rel]; };
    NSString *xdg = EnvPath(@"XDG_CACHE_HOME");
    if ([tool isEqualToString:@"npm"]) return EnvPath(@"npm_config_cache") ?: EnvPath(@"NPM_CONFIG_CACHE") ?: h(@".npm");
    if ([tool isEqualToString:@"pnpm"]) return EnvPath(@"PNPM_STORE_DIR") ?: PnpmStoreFromRC(home) ?: h(@"Library/pnpm/store");
    if ([tool isEqualToString:@"yarn"]) return EnvPath(@"YARN_CACHE_FOLDER") ?: h(@"Library/Caches/Yarn");
    if ([tool isEqualToString:@"bun"]) return EnvPath(@"BUN_INSTALL_CACHE_DIR") ?: h(@".bun/install/cache");
    if ([tool isEqualToString:@"playwright"]) return EnvPath(@"PLAYWRIGHT_BROWSERS_PATH") ?: h(@"Library/Caches/ms-playwright");
    if ([tool isEqualToString:@"puppeteer"]) return EnvPath(@"PUPPETEER_CACHE_DIR") ?: h(@".cache/puppeteer");
    if ([tool isEqualToString:@"pip"]) return EnvPath(@"PIP_CACHE_DIR") ?: h(@"Library/Caches/pip");
    if ([tool isEqualToString:@"uv"]) return EnvPath(@"UV_CACHE_DIR") ?: (xdg ? [xdg stringByAppendingPathComponent:@"uv"] : h(@".cache/uv"));
    if ([tool isEqualToString:@"go"]) return EnvPath(@"GOCACHE") ?: h(@"Library/Caches/go-build");
    if ([tool isEqualToString:@"gomod"]) {
        NSString *gopath = [Env(@"GOPATH") componentsSeparatedByString:@":"].firstObject;
        NSString *fromPath = gopath.length && EnvPath(@"GOPATH") ? [gopath stringByAppendingPathComponent:@"pkg/mod"] : nil;
        return EnvPath(@"GOMODCACHE") ?: fromPath ?: h(@"go/pkg/mod");
    }
    if ([tool isEqualToString:@"gradle"]) return EnvPath(@"GRADLE_USER_HOME") ?: h(@".gradle");
    if ([tool isEqualToString:@"cargo"]) return EnvPath(@"CARGO_HOME") ?: h(@".cargo");
    if ([tool isEqualToString:@"brew"]) return EnvPath(@"HOMEBREW_CACHE") ?: h(@"Library/Caches/Homebrew");
    if ([tool isEqualToString:@"colima"]) return EnvPath(@"COLIMA_HOME") ?: h(@".colima");
    if ([tool isEqualToString:@"ollama"]) return EnvPath(@"OLLAMA_MODELS") ?: h(@".ollama/models");
    if ([tool isEqualToString:@"hf"]) return EnvPath(@"HF_HOME") ?: (xdg ? [xdg stringByAppendingPathComponent:@"huggingface"] : h(@".cache/huggingface"));
    return nil;
}

NSString *MMClutterExpand(NSString *pattern) {
    NSString *root = MMClutterRoot(), *home = MMClutterHome();
    if (!root || !home || !pattern.length) return nil;
    NSString *p = pattern;
    if ([p hasPrefix:@"/"]) p = [root stringByAppendingString:p];                 // rebased in a test, as is on a Mac
    else if ([p isEqualToString:@"~"] || [p hasPrefix:@"~/"]) p = [home stringByAppendingString:[p substringFromIndex:1]];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\$\\{([a-z]+)(?::([a-z-]+))?\\}" options:0 error:nil];
    NSTextCheckingResult *m;
    while ((m = [re firstMatchInString:p options:0 range:NSMakeRange(0, p.length)])) {
        NSString *name = [p substringWithRange:[m rangeAtIndex:1]];
        NSString *arg = [m rangeAtIndex:2].location != NSNotFound ? [p substringWithRange:[m rangeAtIndex:2]] : nil;
        NSString *v = nil;
        if ([name isEqualToString:@"cache"]) v = MMCachePathOf(arg);
        else if ([name isEqualToString:@"claude"]) v = EnvPath(@"CLAUDE_CONFIG_DIR") ?: [home stringByAppendingPathComponent:@".claude"];
        else if ([name isEqualToString:@"codex"]) v = EnvPath(@"CODEX_HOME") ?: [home stringByAppendingPathComponent:@".codex"];
        else if ([name isEqualToString:@"support"]) v = Real(MMSupportDir());
        if (!v.length) return nil;
        p = [p stringByReplacingCharactersInRange:m.range withString:v];
    }
    return p;
}

/// "a/{b,c}/d" as "a/b/d" and "a/c/d". One level of braces, as the rows use them.
static NSArray<NSString *> *Braces(NSString *p) {
    NSRange open = [p rangeOfString:@"{"], close = [p rangeOfString:@"}"];
    if (open.location == NSNotFound || close.location == NSNotFound || close.location < open.location) return @[p];
    NSString *head = [p substringToIndex:open.location], *tail = [p substringFromIndex:close.location + 1];
    NSString *mid = [p substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *alt in [mid componentsSeparatedByString:@","]) [out addObjectsFromArray:Braces([NSString stringWithFormat:@"%@%@%@", head, alt, tail])];
    return out;
}

static NSArray<NSString *> *Glob(NSString *pattern) {
    NSMutableArray *out = [NSMutableArray new];
    glob_t g = {0};
    if (glob(pattern.fileSystemRepresentation, GLOB_NOSORT, NULL, &g) == 0)
        for (size_t i = 0; i < g.gl_pathc; i++) [out addObject:@(g.gl_pathv[i])];
    globfree(&g);
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

static BOOL Match(NSString *pattern, NSString *path) {
    return fnmatch(pattern.fileSystemRepresentation, path.fileSystemRepresentation, FNM_PATHNAME) == 0;
}

NSString *MMClutterToolPath(NSString *name) {
    if (!name.length || [name containsString:@"/"]) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (Env(@"MINMACS_HOME")) {
        // A test runs only the fakes it put inside its own home, never a real tool.
        NSString *dir = Env(@"MINMACS_TOOLS");
        if (!dir || !Inside(Real(dir), Real(Env(@"MINMACS_HOME")))) return nil;
        NSString *p = [dir stringByAppendingPathComponent:name];
        return [fm isExecutableFileAtPath:p] ? p : nil;
    }
    NSString *home = NSHomeDirectory();
    NSArray *dirs = @[@"/usr/bin", @"/opt/homebrew/bin", @"/usr/local/bin", [home stringByAppendingPathComponent:@".local/bin"],
                      [home stringByAppendingPathComponent:@"Library/pnpm"], [home stringByAppendingPathComponent:@".cargo/bin"],
                      [home stringByAppendingPathComponent:@"go/bin"], @"/usr/local/go/bin",
                      [home stringByAppendingPathComponent:@"miniconda3/bin"], [home stringByAppendingPathComponent:@"anaconda3/bin"]];
    for (NSString *d in dirs) {
        NSString *p = [d stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

#pragma mark - Kinds

@interface MMClutterKind ()
@property (readwrite, copy) NSString *kindID, *title, *group, *cleanup, *dryRun, *ownerSetting, *owner, *rebuild, *advice, *workaround, *signature;
@property (readwrite) MMClutterClass klass;
@property (readwrite) NSArray<NSString *> *paths, *names, *beside, *never, *quitFirst, *cleanupArgs, *dryRunArgs;
@property (readwrite) BOOL reportOnly, skipWhenTracked, walk;
@property (readwrite) NSTimeInterval minAge, every;
@property (readwrite) NSDictionary *json;
@property NSString *reportOnlyWhen;
@property NSDictionary *session, *family;
@property NSArray<NSString *> *leafCache, *neverCache;
@end

static NSArray<NSString *> *Strings(id v) {
    if (![v isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray new];
    for (id x in v) if ([x isKindOfClass:NSString.class] && [x length]) [out addObject:x];
    return out;
}
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

@implementation MMClutterKind
+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:NSDictionary.class] || !Str(j[@"id"]) || !Str(j[@"class"])) return nil;
    MMClutterKind *k = [MMClutterKind new];
    k.json = j; k.kindID = j[@"id"]; k.title = Str(j[@"title"]) ?: j[@"id"]; k.group = Str(j[@"group"]) ?: @"";
    k.klass = ClassFrom(j[@"class"]);
    k.paths = Strings(j[@"paths"]); k.names = Strings(j[@"names"]); k.beside = Strings(j[@"beside"]);
    k.never = Strings(j[@"never"]); k.quitFirst = Strings(j[@"quitFirst"]);
    k.cleanupArgs = Strings(j[@"cleanup"]).count ? Strings(j[@"cleanup"]) : nil;
    k.dryRunArgs = Strings(j[@"dryRun"]).count ? Strings(j[@"dryRun"]) : nil;
    k.cleanup = k.cleanupArgs ? [k.cleanupArgs componentsJoinedByString:@" "] : nil;
    k.dryRun = k.dryRunArgs ? [k.dryRunArgs componentsJoinedByString:@" "] : nil;
    // A tool row with no command of its own is shown, never acted on.
    if (k.klass == MMClutterTool && !k.cleanupArgs) k.klass = MMClutterReport;
    k.ownerSetting = Str(j[@"ownerSetting"]); k.owner = Str(j[@"owner"]); k.rebuild = Str(j[@"rebuild"]);
    k.advice = Str(j[@"advice"]); k.workaround = Str(j[@"workaround"]); k.signature = Str(j[@"signature"]);
    k.reportOnlyWhen = Str(j[@"reportOnlyWhen"]);
    k.reportOnly = k.klass == MMClutterReport || k.klass == MMClutterData || [j[@"reportOnly"] boolValue];
    k.skipWhenTracked = [j[@"skipWhenTracked"] boolValue];
    k.walk = j[@"walk"] ? [j[@"walk"] boolValue] : YES;
    k.minAge = MAX(0, [j[@"minAge"] doubleValue]);
    k.every = MAX(kMinEvery, [j[@"every"] doubleValue]);
    k.session = [j[@"session"] isKindOfClass:NSDictionary.class] ? j[@"session"] : nil;
    k.family = [j[@"family"] isKindOfClass:NSDictionary.class] ? j[@"family"] : nil;
    return k;
}
- (BOOL)isFamily { return [self.signature isEqualToString:@"family"]; }
- (BOOL)isScratch { return [self.signature isEqualToString:@"agent-scratch"]; }
/// The leaf patterns this row may act on, expanded for this Mac. A session row adds its scratch entries.
- (NSArray<NSString *> *)leafPatterns {
    @synchronized (self) { if (self.leafCache) return self.leafCache; }
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in self.paths) {
        NSString *e = MMClutterExpand(p);
        if (!e) continue;
        for (NSString *b in Braces(e)) {
            [out addObject:b];
            if (self.isScratch && Str(self.session[@"scratchDir"])) [out addObject:[NSString stringWithFormat:@"%@/%@/*", b, self.session[@"scratchDir"]]];
        }
    }
    @synchronized (self) { self.leafCache = out; }
    return out;
}
- (NSArray<NSString *> *)neverPaths {
    @synchronized (self) { if (self.neverCache) return self.neverCache; }
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in self.never) { NSString *e = MMClutterExpand(p); if (e) [out addObjectsFromArray:Braces(e)]; }
    @synchronized (self) { self.neverCache = out; }
    return out;
}
@end

#pragma mark - Items

@interface MMClutterItem ()
@property (readwrite) MMClutterKind *kind;
@property (readwrite, copy) NSString *path, *ownerPath, *sessionID, *why;
@property (readwrite) NSArray<NSString *> *members;
@property (readwrite) BOOL ownerGone;
@property (readwrite) MMSize size;
@property (readwrite) NSDate *lastUsed;
@property (readwrite) MMClutterState state;
@property (readwrite) MMClutterTrend trend;
@end

static NSString *StateName(MMClutterState s) { return s == MMClutterFree ? @"free" : s == MMClutterLive ? @"live" : @"kept"; }

@implementation MMClutterItem
- (NSString *)key { return [NSString stringWithFormat:@"%@:%@", self.kind.kindID, self.path]; }
- (NSString *)description { return [NSString stringWithFormat:@"<MMClutterItem %@ %@>", self.key, StateName(self.state)]; }
- (NSDictionary *)json {
    NSMutableDictionary *j = [@{@"kind": self.kind.kindID ?: @"", @"path": self.path ?: @"", @"members": self.members ?: @[],
                                @"allocated": @(self.size.allocated), @"freed": @(self.size.freedIfDeleted), @"files": @(self.size.files),
                                @"state": StateName(self.state), @"ownerGone": @(self.ownerGone)} mutableCopy];
    if (self.ownerPath) j[@"ownerPath"] = self.ownerPath;
    if (self.sessionID) j[@"sessionID"] = self.sessionID;
    if (self.why) j[@"why"] = self.why;
    if (self.lastUsed) j[@"lastUsed"] = @(self.lastUsed.timeIntervalSince1970);
    MMClutterTrend t = self.trend;
    if (t.ok || t.points) j[@"trend"] = @{@"ok": @(t.ok), @"bytesPerDay": @(t.bytesPerDay), @"windowDays": @(t.windowDays), @"points": @(t.points),
                                          @"firstBytes": @(t.firstBytes), @"lastBytes": @(t.lastBytes), @"weekRatio": @(t.weekRatio)};
    return j;
}
+ (instancetype)fromJSON:(NSDictionary *)j kind:(MMClutterKind *)k {
    if (!k || !Str(j[@"path"])) return nil;
    MMClutterItem *i = [MMClutterItem new];
    i.kind = k; i.path = j[@"path"]; i.members = Strings(j[@"members"]).count ? Strings(j[@"members"]) : @[i.path];
    i.ownerPath = Str(j[@"ownerPath"]); i.sessionID = Str(j[@"sessionID"]); i.why = Str(j[@"why"]);
    i.ownerGone = [j[@"ownerGone"] boolValue];
    i.size = (MMSize){ [j[@"allocated"] unsignedLongLongValue], [j[@"freed"] unsignedLongLongValue], [j[@"files"] integerValue], 0 };
    if ([j[@"lastUsed"] doubleValue] > 0) i.lastUsed = [NSDate dateWithTimeIntervalSince1970:[j[@"lastUsed"] doubleValue]];
    NSString *st = Str(j[@"state"]);
    i.state = [st isEqualToString:@"free"] ? MMClutterFree : [st isEqualToString:@"live"] ? MMClutterLive : MMClutterKept;
    NSDictionary *t = [j[@"trend"] isKindOfClass:NSDictionary.class] ? j[@"trend"] : nil;
    if (t) i.trend = (MMClutterTrend){ [t[@"ok"] boolValue], [t[@"bytesPerDay"] doubleValue], [t[@"windowDays"] integerValue],
                                       [t[@"points"] integerValue], [t[@"firstBytes"] doubleValue], [t[@"lastBytes"] doubleValue], [t[@"weekRatio"] doubleValue] };
    return i;
}
@end

#pragma mark - Trends

NSString *MMClutterSeries(NSString *kindID) { return [@"noonoo.disk." stringByAppendingString:kindID ?: @""]; }

MMClutterTrend MMClutterTrendOf(NSData *data, NSDate *now) {
    MMClutterTrend t = {0};
    NSUInteger n = data.length / sizeof(MMTrendPoint);
    const MMTrendPoint *pts = data.bytes;
    // DayBucket: one point per UTC day, the last sample of the day wins.
    NSMutableDictionary<NSNumber *, NSNumber *> *byDay = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSNumber *> *atOfDay = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < n; i++) {
        NSNumber *day = @((long long)floor(pts[i].at / 86400));
        if (atOfDay[day] && atOfDay[day].doubleValue > pts[i].at) continue;
        byDay[day] = @(pts[i].value); atOfDay[day] = @(pts[i].at);
    }
    NSArray<NSNumber *> *days = [byDay.allKeys sortedArrayUsingSelector:@selector(compare:)];
    t.points = (NSInteger)days.count;
    if (days.count) { t.firstBytes = byDay[days.firstObject].doubleValue; t.lastBytes = byDay[days.lastObject].doubleValue; }
    // The velocity of cache_velocity.go: the newest point over the oldest of the last 7 days.
    double weekStart = floor(((now ?: NSDate.date).timeIntervalSince1970 - 7 * 86400) / 86400);
    for (NSNumber *d in days) if (d.doubleValue >= weekStart) {
        double first = byDay[d].doubleValue;
        if (first > 0 && ![d isEqual:days.lastObject]) t.weekRatio = t.lastBytes / first;
        break;
    }
    if (days.count < 2) return t;
    // LinearFit: least squares with x in days since the first bucket.
    double x0 = days.firstObject.doubleValue, sx = 0, sy = 0, sxy = 0, sxx = 0, cnt = (double)days.count;
    for (NSNumber *d in days) {
        double x = d.doubleValue - x0, y = byDay[d].doubleValue;
        sx += x; sy += y; sxy += x * y; sxx += x * x;
    }
    double denom = cnt * sxx - sx * sx;
    if (denom == 0) return t;
    t.ok = YES;
    t.bytesPerDay = (cnt * sxy - sx * sy) / denom;
    t.windowDays = MAX(1, (NSInteger)llround(days.lastObject.doubleValue - x0));
    return t;
}

#pragma mark - Open files

NSSet<NSString *> *MMOpenUnder(NSArray<NSString *> *roots) {
    NSMutableSet *hit = [NSMutableSet new];
    if (!roots.count) return hit;
    NSMutableDictionary<NSString *, NSString *> *byReal = [NSMutableDictionary new];
    for (NSString *r in roots) byReal[Real(r)] = r;
    NSArray *reals = byReal.allKeys;
    void (^see)(const char *) = ^(const char *cpath) {
        if (!cpath || !cpath[0]) return;
        NSString *p = @(cpath);
        for (NSString *r in reals) if (InsideOrSame(p, r)) [hit addObject:byReal[r]];
    };
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return hit;
    pid_t *pids = calloc((size_t)count + 64, sizeof(pid_t));
    count = proc_listallpids(pids, (int)(((size_t)count + 64) * sizeof(pid_t)));
    uid_t me = getuid();
    for (int i = 0; i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;
        struct proc_bsdshortinfo bi;
        if (proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bi, sizeof bi) != sizeof bi || bi.pbsi_uid != me) continue;
        char exe[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pid, exe, sizeof exe) > 0) see(exe);
        struct proc_vnodepathinfo vp;
        if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vp, sizeof vp) == sizeof vp) see(vp.pvi_cdir.vip_path);
        int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (bytes <= 0) continue;
        struct proc_fdinfo *fds = malloc((size_t)bytes);
        bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytes);
        for (int f = 0; f < bytes / (int)sizeof(struct proc_fdinfo); f++) {
            if (fds[f].proc_fdtype != PROX_FDTYPE_VNODE) continue;
            struct vnode_fdinfowithpath vi;
            if (proc_pidfdinfo(pid, fds[f].proc_fd, PROC_PIDFDVNODEPATHINFO, &vi, sizeof vi) == sizeof vi) see(vi.pvip.vip_path);
        }
        free(fds);
    }
    free(pids);
    return hit;
}

#pragma mark - Walks

typedef struct { NSTimeInterval newest; NSUInteger entries; BOOL special, tooBig, failed; } MMTreeFacts;

/// NN treeFacts: the newest mtime in the tree and whether it holds a socket, FIFO or device. Never follows a symlink.
static MMTreeFacts TreeFacts(NSString *path) {
    MMTreeFacts t = {0};
    char *argv[] = { (char *)path.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) { t.failed = YES; return t; }
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info == FTS_DP) continue;
        if (e->fts_info == FTS_DNR || e->fts_info == FTS_ERR || e->fts_info == FTS_NS) { t.failed = YES; continue; }
        if (++t.entries > kWalkMax) { t.tooBig = YES; break; }
        struct stat *st = e->fts_statp;
        if (!st) continue;
        double m = st->st_mtimespec.tv_sec + st->st_mtimespec.tv_nsec / 1e9;
        if (m > t.newest) t.newest = m;
        if (S_ISSOCK(st->st_mode) || S_ISFIFO(st->st_mode) || S_ISCHR(st->st_mode) || S_ISBLK(st->st_mode)) t.special = YES;
    }
    fts_close(fts);
    return t;
}

/// The newest mtime of a folder and its first level, for rows that only show when they were last used.
static NSTimeInterval ShallowNewest(NSString *path) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return 0;
    double newest = st.st_mtimespec.tv_sec;
    if (S_ISDIR(st.st_mode))
        for (NSString *c in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil]) {
            struct stat cs;
            if (lstat([path stringByAppendingPathComponent:c].fileSystemRepresentation, &cs) == 0 && cs.st_mtimespec.tv_sec > newest) newest = cs.st_mtimespec.tv_sec;
        }
    return newest;
}

#pragma mark - Git

/// `git ls-files -- name` in dir, read-only, through MMGit, so the git is MMGitPath's and the child runs through
/// MMRun. git runs on its own queue, no.guerrilla.minmacs.core.clutter.git, and the caller waits for it. In the app
/// only actions and verbs ask, off main. The cold CLI may ask from its main thread. Its output, or nil with *status
/// not 0, which keeps the folder.
static NSString *GitLsFiles(NSString *dir, NSString *name, int *status) {
    *status = -1;
    if (!MMGitPath()) return nil;
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = MMQueue(@"core", @"clutter.git", QOS_CLASS_UTILITY); });
    __block NSString *out = nil;
    __block int st = -1;
    // dispatch_sync would run the block on the caller's thread, which may be the CLI's main, where MMGit refuses.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(q, ^{ out = MMGit(dir, @[@"ls-files", @"--", name], 10, &st); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    *status = out ? st : -1;
    return out;
}

#pragma mark - Families

/// NN familyKeyOf: the name with one random suffix stripped, as "prefix" plus the separator, or nil.
static NSString *FamilyKey(NSString *name) {
    NSUInteger n = name.length, i = n;
    while (i > 0 && isdigit([name characterAtIndex:i - 1])) i--;
    if (n - i >= 6 && i > 0) return [name substringToIndex:i];   // MkdirTemp("prefix") or "prefix-123456"
    NSRange r = [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-_."] options:NSBackwardsSearch];
    if (r.location == NSNotFound || r.location == 0) return nil;
    NSString *tail = [name substringFromIndex:r.location + 1];
    if (tail.length < 6) return nil;
    BOOL lower = YES, upper = YES;
    for (NSUInteger k = 0; k < tail.length; k++) {
        unichar c = [tail characterAtIndex:k];
        if (!isalnum(c)) return nil;
        if (!islower(c)) lower = NO;
        if (!isupper(c)) upper = NO;
    }
    if (lower || upper) return nil;   // a word, not a random suffix
    return [name substringToIndex:r.location + 1];
}

#pragma mark - The catalog

@implementation MMClutterCatalog {
    NSArray<MMClutterKind *> *_kinds;
    NSDictionary<NSString *, MMClutterKind *> *_byID;
    NSArray<MMClutterItem *> *_items;
    NSMutableDictionary<NSString *, NSNumber *> *_scanned;
    dispatch_source_t _timer;
    BOOL _loaded;
    NSSet<NSString *> *_allNames;
}

+ (NSArray<NSString *> *)defaultRowDirectories {
    if (Env(@"MINMACS_CLUTTER_ROWS")) return [Env(@"MINMACS_CLUTTER_ROWS") componentsSeparatedByString:@":"];
    NSMutableArray *dirs = [NSMutableArray new];
    char buf[PATH_MAX]; uint32_t size = sizeof buf; char real[PATH_MAX];
    if (_NSGetExecutablePath(buf, &size) == 0 && realpath(buf, real)) {
        NSString *contents = [@(real).stringByDeletingLastPathComponent stringByDeletingLastPathComponent];
        [dirs addObject:[contents stringByAppendingPathComponent:@"Resources/registry/clutter"]];
    }
    [dirs addObject:[MMSupportDir() stringByAppendingPathComponent:@"registry/clutter"]];   // the user's rows win
    return dirs;
}

+ (instancetype)shared {
    static MMClutterCatalog *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[MMClutterCatalog alloc] initWithRowDirectories:[self defaultRowDirectories]]; });
    return c;
}

- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs {
    if ((self = [super init])) {
        NSMutableDictionary *byID = [NSMutableDictionary new];
        for (NSString *dir in dirs)
            for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
                if (![f.pathExtension isEqualToString:@"json"]) continue;
                NSData *d = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
                MMClutterKind *k = d ? [MMClutterKind fromJSON:[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]] : nil;
                if (k && [k.kindID isEqualToString:f.stringByDeletingPathExtension]) byID[k.kindID] = k;
            }
        // Families last: a temp folder another row names belongs to that row.
        _kinds = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(MMClutterKind *a, MMClutterKind *b) {
            if (a.isFamily != b.isFamily) return a.isFamily ? NSOrderedDescending : NSOrderedAscending;
            return [a.kindID compare:b.kindID];
        }];
        _byID = [byID copy];
        _items = @[];
        _scanned = [NSMutableDictionary new];
    }
    return self;
}

- (NSArray<MMClutterKind *> *)kinds { return _kinds; }
- (MMClutterKind *)kind:(NSString *)kindID { return kindID ? _byID[kindID] : nil; }

#pragma mark State file

- (NSString *)statePath { return [MMExpertDir(@"core") stringByAppendingPathComponent:@"clutter.json"]; }

/// The last scan from disk, once, so a launch shows yesterday's items without walking again.
- (void)loadIfNeeded {
    @synchronized (self) {
        if (_loaded) return;
        _loaded = YES;
        NSData *d = [NSData dataWithContentsOfFile:self.statePath];
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if (![j isKindOfClass:NSDictionary.class] || ![j[@"root"] isEqual:MMClutterRoot() ?: @"-"]) return;
        NSMutableArray *items = [NSMutableArray new];
        for (NSDictionary *x in j[@"items"]) {
            MMClutterItem *i = [x isKindOfClass:NSDictionary.class] ? [MMClutterItem fromJSON:x kind:_byID[x[@"kind"]]] : nil;
            if (i) [items addObject:i];
        }
        _items = items;
        for (NSString *k in j[@"scanned"]) if (_byID[k]) _scanned[k] = j[@"scanned"][k];
    }
}

- (void)save {
    NSMutableArray *items = [NSMutableArray new];
    NSDictionary *scanned;
    @synchronized (self) {
        for (MMClutterItem *i in _items) [items addObject:i.json];
        scanned = [_scanned copy];
    }
    NSDictionary *j = @{@"root": MMClutterRoot() ?: @"-", @"items": items, @"scanned": scanned};
    [[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] writeToFile:self.statePath atomically:YES];
}

- (NSArray<MMClutterItem *> *)items {
    [self loadIfNeeded];
    @synchronized (self) { return _items; }
}

/// Never reads the state file, since menus ask on main. The fact source's read of items loads it first.
- (NSDate *)lastScan {
    double t = 0;
    @synchronized (self) { for (NSNumber *n in _scanned.allValues) t = MAX(t, n.doubleValue); }
    return t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : nil;
}

- (void)forgetScanTimes { [self loadIfNeeded]; @synchronized (self) { [_scanned removeAllObjects]; } }

#pragma mark Matching

- (NSArray<NSString *> *)currentProjects {
    NSArray *p = self.projectsProvider ? self.projectsProvider() : self.projects;
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *x in p) if (x.length) [out addObject:Real(x)];
    return out;
}

/// The deepest checkout that holds path, strictly inside it.
static NSString *ProjectOf(NSString *path, NSArray<NSString *> *projects) {
    NSString *best = nil;
    for (NSString *p in projects) if (Inside(path, p) && p.length > best.length) best = p;
    return best;
}

- (NSSet<NSString *> *)allNames {
    @synchronized (self) {
        if (!_allNames) {
            NSMutableSet *s = [NSMutableSet new];
            for (MMClutterKind *k in _kinds) [s addObjectsFromArray:k.names];
            _allNames = s;
        }
        return _allNames;
    }
}

/// A named build folder: its name is the row's, it sits inside a checkout with nothing clutter-like or .git between,
/// and one of the row's manifests sits next to it.
- (BOOL)named:(NSString *)path kind:(MMClutterKind *)k projects:(NSArray<NSString *> *)projects {
    if (!k.names.count || ![k.names containsObject:path.lastPathComponent]) return NO;
    NSString *project = ProjectOf(path, projects);
    if (!project) return NO;
    NSSet *names = [self allNames];
    NSArray *between = [[path substringFromIndex:project.length + 1] pathComponents];
    for (NSUInteger i = 0; i + 1 < between.count; i++)
        if ([between[i] isEqualToString:@".git"] || [names containsObject:between[i]]) return NO;
    if (!k.beside.count) return YES;
    NSString *dir = path.stringByDeletingLastPathComponent;
    for (NSString *b in k.beside) if ([NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:b]]) return YES;
    return NO;
}

- (BOOL)familyMember:(NSString *)path kind:(MMClutterKind *)k {
    NSString *name = path.lastPathComponent, *parent = path.stringByDeletingLastPathComponent;
    for (NSString *ex in Strings(k.family[@"exclude"])) if ([name hasPrefix:ex]) return NO;
    if (!FamilyKey(name)) return NO;
    for (NSString *p in k.leafPatterns) if (Match(p, parent)) return YES;
    return NO;
}

- (BOOL)path:(NSString *)path matches:(MMClutterKind *)k projects:(NSArray<NSString *> *)projects {
    if (k.names.count) return [self named:path kind:k projects:projects];
    if (k.isFamily) return [self familyMember:path kind:k];
    for (NSString *p in k.leafPatterns) if (Match(p, path)) return YES;
    return NO;
}

- (MMClutterKind *)kindFor:(NSString *)path projects:(NSArray<NSString *> *)projects {
    if (!path.length) return nil;
    NSString *p = Real(path);
    for (MMClutterKind *k in _kinds) if ([self path:p matches:k projects:projects]) return k;
    return nil;
}
- (MMClutterKind *)kindFor:(NSString *)path { return [self kindFor:path projects:[self currentProjects]]; }

#pragma mark The walls

/// The folders nothing may ever touch, and nothing inside the first group either. Matching ignores case,
/// because APFS does by default, as NN's leakCategoricalCheck.
static NSArray<NSString *> *WalledTrees(void) {
    return @[@"/System", @"/Library", @"/usr", @"/bin", @"/sbin", @"/private/etc", @"/Applications", @"/opt", @"/dev",
             @"/Volumes", @"/cores"];
}
static BOOL InsideCase(NSString *path, NSString *folder) {
    NSString *a = path.lowercaseString, *b = folder.lowercaseString;
    return [a isEqualToString:b] || [a hasPrefix:[b stringByAppendingString:@"/"]];
}

- (NSString *)wallFor:(NSString *)p {
    NSString *home = Real(NSHomeDirectory()), *chome = MMClutterHome(), *root = MMClutterRoot();
    NSMutableArray *roots = [NSMutableArray arrayWithObject:@""];
    if (root.length) [roots addObject:root];
    for (NSString *r in roots)
        for (NSString *w in WalledTrees())
            if (InsideCase(p, [r stringByAppendingString:w])) return [NSString stringWithFormat:@"it is under %@, which MinMacs never touches", w];
    NSMutableArray *homes = [NSMutableArray arrayWithObject:home];
    if (chome && ![chome isEqualToString:home]) [homes addObject:chome];
    for (NSString *h in homes) {
        if ([p.lowercaseString isEqualToString:h.lowercaseString] || Inside(h, p)) return @"it is the home folder or holds it";
        if ([p.stringByDeletingLastPathComponent isEqualToString:h]) return @"it sits right in the home folder";
        for (NSString *top in @[@"Library", @"Library/Caches", @"Library/Application Support", @"Library/Developer", @"Library/Logs",
                                @"Library/Containers", @"Library/Group Containers", @"Library/Preferences", @".cache", @".config", @".local"])
            if ([p.lowercaseString isEqualToString:[h stringByAppendingPathComponent:top].lowercaseString]) return @"it is a folder macOS or many apps share";
    }
    for (NSString *top in @[@"/", @"/private", @"/private/tmp", @"/private/var", @"/private/var/folders", @"/Users"]) {
        for (NSString *r in roots) {
            NSString *w = [r stringByAppendingString:[top isEqualToString:@"/"] && r.length ? @"" : top];
            if (w.length && [p.lowercaseString isEqualToString:w.lowercaseString]) return @"it is a system folder";
        }
    }
    NSString *mmHome = Env(@"MINMACS_HOME") ? Real(Env(@"MINMACS_HOME")) : nil;
    for (NSString *x in @[Real(MMSupportDir()), mmHome ?: @"", root ?: @""])
        if (x.length && (InsideOrSame(x, p))) return @"it holds MinMacs's own folder";
    return nil;
}

/// A never path protects itself, everything inside it, and every folder that holds it.
static BOOL NeverHits(NSString *never, NSString *p) {
    for (NSString *a = p; a.length > 1; a = a.stringByDeletingLastPathComponent) if (Match(never, a)) return YES;
    if ([never rangeOfString:@"*"].location == NSNotFound && [never rangeOfString:@"?"].location == NSNotFound) return Inside(never, p);
    for (NSString *g in Glob(never)) if (Inside(g, p)) return YES;
    return NO;
}

- (NSString *)whyNot:(NSString *)path kind:(MMClutterKind *)kind {
    if (!path.length || ![path hasPrefix:@"/"]) return @"it is not a full path";
    if ([path.pathComponents containsObject:@".."] || [path.pathComponents containsObject:@"."]) return @"the path holds . or ..";
    NSString *raw = Clean(path);
    NSString *w = [self wallFor:raw];
    if (w) return w;
    struct stat st;
    if (lstat(raw.fileSystemRepresentation, &st) != 0) return @"it is gone";
    if (S_ISLNK(st.st_mode)) return @"it is a symlink, and MinMacs never follows one";
    if (st.st_uid != getuid()) return @"it belongs to another user";
    NSString *p = Real(raw);
    if ((w = [self wallFor:p])) return w;
    for (MMClutterKind *any in _kinds)
        for (NSString *n in any.neverPaths) if (NeverHits(n, p)) return @"its owner keeps it, and the row says never";
    NSArray *projects = [self currentProjects];
    MMClutterKind *first = [self kindFor:p projects:projects];
    MMClutterKind *k = kind ?: first;
    if (!k) return @"no clutter row lists it";
    if (![self path:p matches:k projects:projects]) return [NSString stringWithFormat:@"the %@ row does not list it", k.title];
    // The row that claims it first decides, so a path two rows match is judged once.
    if (first && first != k) return [NSString stringWithFormat:@"it belongs to the %@ row", first.title];
    if (k.reportOnly) return k.ownerSetting ?: @"its row only reports it";
    if (k.skipWhenTracked) {
        // dist and build are part of a project when git tracks them, research track D recommendation 6.
        int status = -1;
        NSString *out = GitLsFiles(p.stringByDeletingLastPathComponent, p.lastPathComponent, &status);
        if (status != 0) return @"git could not say whether it tracks it";
        if (out.length) return @"git tracks it, so it is part of the project";
    }
    return nil;
}

#pragma mark Discovery

/// The named build folders under one checkout, pruned at the first match as NN's dev module does.
- (void)walkProject:(NSString *)project kinds:(NSArray<MMClutterKind *> *)kinds projects:(NSArray<NSString *> *)projects into:(NSMutableArray *)out {
    NSSet *names = [self allNames];
    NSMutableSet *mine = [NSMutableSet new];
    for (MMClutterKind *k in kinds) [mine addObjectsFromArray:k.names];
    char *argv[] = { (char *)project.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_NOSTAT, NULL);
    if (!fts) return;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info != FTS_D) continue;
        if (e->fts_level == 0) continue;
        NSString *name = @(e->fts_name), *p = @(e->fts_path);
        if (e->fts_level > kProjectDepth || [name isEqualToString:@".git"]) { fts_set(fts, e, FTS_SKIP); continue; }
        // Another checkout inside this one is walked on its own.
        if (![p isEqualToString:project] && [projects containsObject:p]) { fts_set(fts, e, FTS_SKIP); continue; }
        if ([names containsObject:name]) {
            if ([mine containsObject:name]) [out addObject:p];
            fts_set(fts, e, FTS_SKIP);
        }
    }
    fts_close(fts);
}

/// The candidate paths of these rows, each claimed by the first row in order that matches it.
- (NSArray<MMClutterItem *> *)discover:(NSArray<MMClutterKind *> *)kinds projects:(NSArray<NSString *> *)projects {
    NSMutableArray<MMClutterItem *> *out = [NSMutableArray new];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<MMClutterKind *> *named = [NSMutableArray new];
    for (MMClutterKind *k in kinds) if (k.names.count) [named addObject:k];
    if (named.count) {
        NSMutableArray *found = [NSMutableArray new];
        for (NSString *proj in projects) [self walkProject:proj kinds:named projects:projects into:found];
        for (NSString *p in [NSOrderedSet orderedSetWithArray:found]) {
            MMClutterKind *k = [self kindFor:p projects:projects];
            if (![named containsObject:k]) continue;
            MMClutterItem *i = [MMClutterItem new];
            i.kind = k; i.path = p; i.members = @[p];
            [out addObject:i];
        }
    }
    for (MMClutterKind *k in kinds) {
        if (k.names.count) continue;
        if (k.isFamily) {
            NSInteger minMembers = MAX(2, [k.family[@"minMembers"] integerValue] ?: 5);
            for (NSString *pat in k.leafPatterns)
                for (NSString *root in Glob(pat)) {
                    NSMutableDictionary<NSString *, NSMutableArray *> *byKey = [NSMutableDictionary new];
                    for (NSString *name in [[fm contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
                        NSString *p = [root stringByAppendingPathComponent:name];
                        struct stat st;
                        if (lstat(p.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode) || st.st_uid != getuid()) continue;
                        if (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode)) continue;
                        if ([self kindFor:p projects:projects] != k) continue;
                        NSString *key = FamilyKey(name);
                        if (!byKey[key]) byKey[key] = [NSMutableArray new];
                        [byKey[key] addObject:p];
                    }
                    for (NSString *key in [byKey.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                        if ((NSInteger)byKey[key].count < minMembers) continue;
                        MMClutterItem *i = [MMClutterItem new];
                        i.kind = k; i.path = [[root stringByAppendingPathComponent:key] stringByAppendingString:@"*"]; i.members = byKey[key];
                        [out addObject:i];
                    }
                }
            continue;
        }
        for (NSString *pat in k.leafPatterns)
            for (NSString *p in Glob(pat)) {
                struct stat st;
                if (lstat(p.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode)) continue;
                if ([self kindFor:p projects:projects] != k) continue;
                MMClutterItem *i = [MMClutterItem new];
                i.kind = k; i.path = p; i.members = @[p];
                [out addObject:i];
            }
    }
    return out;
}

#pragma mark Inspecting

static BOOL IsUUID(NSString *s) {
    return s.length == 36 && [[NSUUID alloc] initWithUUIDString:s] != nil;
}

/// NN SessionRule: a session lives while a process carries its id, its transcript was written lately,
/// or Know's session index has it with a running pid.
- (NSString *)sessionAlive:(NSString *)uuid window:(NSTimeInterval)window sample:(MMSample *)sample {
    MMSession *s = [MMSessions.shared withID:uuid];
    if (s.pid > 0 && kill(s.pid, 0) == 0) return [NSString stringWithFormat:@"its session runs as pid %d", s.pid];
    // NN leaks.go:122-129: a process started with --session-id <uuid>, or --resume <uuid>. A path that merely holds
    // the id, such as an argument to `minmacs clean`, is not the session.
    for (NSNumber *pid in sample.procs) {
        MMProc *p = sample.procs[pid];
        if (p.uid != getuid() || p.pid == getpid()) continue;
        NSArray<NSString *> *args = [sample argsOf:p.pid];
        for (NSUInteger k = 0; k < args.count; k++) {
            NSString *a = args[k], *next = k + 1 < args.count ? args[k + 1] : nil;
            BOOL flag = [a isEqualToString:@"--session-id"] || [a isEqualToString:@"--resume"] || [a isEqualToString:@"-r"];
            if ((flag && [next isEqualToString:uuid]) || [a isEqualToString:[@"--session-id=" stringByAppendingString:uuid]] ||
                [a isEqualToString:[@"--resume=" stringByAppendingString:uuid]])
                return [NSString stringWithFormat:@"pid %d runs its session", p.pid];
        }
    }
    NSString *claude = MMClutterExpand(@"${claude}");
    if (claude) for (NSString *t in Glob([claude stringByAppendingFormat:@"/projects/*/%@.jsonl", uuid])) {
        struct stat st;
        if (stat(t.fileSystemRepresentation, &st) == 0 && NSDate.date.timeIntervalSince1970 - st.st_mtimespec.tv_sec < window)
            return @"its transcript was written in the last 30 minutes";
    }
    return nil;
}

/// Back-links the tool keeps, P29. Each is one file read.
- (void)linkOwner:(MMClutterItem *)i projects:(NSArray<NSString *> *)projects {
    NSString *how = i.kind.owner, *p = i.path;
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([how isEqualToString:@"project"]) i.ownerPath = ProjectOf(p, projects);
    else if ([how isEqualToString:@"derived-data"]) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[p stringByAppendingPathComponent:@"info.plist"]];
        NSString *ws = Str(plist[@"WorkspacePath"]);
        if (ws) { i.ownerPath = ws.stringByDeletingLastPathComponent; i.ownerGone = ![fm fileExistsAtPath:ws]; }
    } else if ([how isEqualToString:@"playwright-links"]) {
        NSString *links = [p.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".links"];
        NSArray *files = [fm contentsOfDirectoryAtPath:links error:nil];
        NSString *live = nil, *any = nil;
        for (NSString *f in files) {
            NSString *target = [[NSString stringWithContentsOfFile:[links stringByAppendingPathComponent:f] encoding:NSUTF8StringEncoding error:nil]
                                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!target.length) continue;
            any = any ?: target;
            if ([fm fileExistsAtPath:target]) { live = target; break; }
        }
        i.ownerPath = live ?: any;
        i.ownerGone = any && !live;
    } else if ([how isEqualToString:@"simulator-device"]) {
        NSDate *last = nil;
        for (NSString *d in [fm contentsOfDirectoryAtPath:p error:nil]) {
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[[p stringByAppendingPathComponent:d] stringByAppendingPathComponent:@"device.plist"]];
            NSDate *b = [plist[@"lastBootedAt"] isKindOfClass:NSDate.class] ? plist[@"lastBootedAt"] : nil;
            if (b && (!last || [b compare:last] == NSOrderedDescending)) last = b;
        }
        if (last) i.lastUsed = last;
    } else if ([how isEqualToString:@"session"]) {
        NSString *uuid = nil;
        for (NSString *c in p.pathComponents) if (IsUUID(c)) uuid = c;
        i.sessionID = uuid;
        NSString *cwd = uuid ? [MMSessions.shared withID:uuid].cwd : nil;
        if (cwd.length) { i.ownerPath = cwd; i.ownerGone = ![fm fileExistsAtPath:cwd]; }
    }
}

/// The state of one item on what the disk and the kernel say now. open is the set MMOpenUnder found, or nil to ask.
- (void)judge:(MMClutterItem *)i open:(NSSet<NSString *> *)open sample:(MMSample *)sample projects:(NSArray<NSString *> *)projects {
    MMClutterKind *k = i.kind;
    i.state = MMClutterFree; i.why = nil;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    // Data and report rows are never acted on, whatever the walls say.
    if (k.reportOnly) { i.state = MMClutterKept; i.why = k.ownerSetting ?: k.advice ?: @"its row only reports it"; return; }
    if ([k.reportOnlyWhen isEqualToString:@"root-owned"]) {
        struct stat st;
        if (lstat(i.path.fileSystemRepresentation, &st) == 0 && st.st_uid != getuid()) { i.state = MMClutterKept; i.why = @"root owns it, so MinMacs only reports it"; return; }
    }
    for (NSString *m in i.members) {
        NSString *w = [self whyNot:m kind:k];
        if (w) { i.state = MMClutterKept; i.why = w; return; }
    }
    NSString *sig = k.signature;
    MMTreeFacts tf = {0};
    BOOL leak = k.klass == MMClutterLeak;
    if (leak) {
        double newest = 0;
        for (NSString *m in i.members) {
            MMTreeFacts t = TreeFacts(m);
            if (t.failed || t.tooBig) { i.state = MMClutterLive; i.why = t.tooBig ? @"it is too large to prove quiet" : @"part of it cannot be read"; return; }
            if (t.special) { i.state = MMClutterLive; i.why = @"it holds a socket or a pipe, so it is not plain scratch"; return; }
            newest = MAX(newest, t.newest);
        }
        tf.newest = newest;
        i.lastUsed = newest > 0 ? [NSDate dateWithTimeIntervalSince1970:newest] : nil;
    } else if (!i.lastUsed) {
        double newest = 0;
        for (NSString *m in i.members) newest = MAX(newest, ShallowNewest(m));
        if (newest > 0) i.lastUsed = [NSDate dateWithTimeIntervalSince1970:newest];
    }
    NSTimeInterval age = tf.newest > 0 ? now - tf.newest : 0;
    if ([sig isEqualToString:@"agent-scratch"]) {
        NSDictionary *s = k.session;
        NSString *scratch = Str(s[@"scratchDir"]);
        NSString *last = i.path.lastPathComponent, *parent = i.path.stringByDeletingLastPathComponent;
        BOOL entry = scratch && [parent.lastPathComponent isEqualToString:scratch] && IsUUID(parent.stringByDeletingLastPathComponent.lastPathComponent);
        NSString *uuid = entry ? parent.stringByDeletingLastPathComponent.lastPathComponent : IsUUID(last) ? last : nil;
        if (uuid) {
            NSString *alive = [self sessionAlive:uuid window:MAX(60, [s[@"transcriptWindow"] doubleValue]) sample:sample];
            if (entry) {
                if (!alive) { i.state = MMClutterLive; i.why = kWholeSession; return; }
                NSTimeInterval idle = MAX(3600, [s[@"entryIdle"] doubleValue]);
                if (age < idle) { i.state = MMClutterLive; i.why = [NSString stringWithFormat:@"its session is alive and it was written %@ ago", Span(age)]; return; }
            } else {
                if (alive) { i.state = MMClutterLive; i.why = alive; return; }
                NSTimeInterval dead = MAX(600, [s[@"deadAfter"] doubleValue]);
                if (age < dead) { i.state = MMClutterLive; i.why = [NSString stringWithFormat:@"it was written %@ ago", Span(age)]; return; }
            }
        } else if (age < k.minAge) { i.state = MMClutterLive; i.why = [NSString stringWithFormat:@"it was written %@ ago", Span(age)]; return; }
    } else if ([sig isEqualToString:@"aged"] || [sig isEqualToString:@"family"]) {
        if (age < k.minAge) { i.state = MMClutterLive; i.why = [NSString stringWithFormat:@"it was written %@ ago", Span(age)]; return; }
        if ([sig isEqualToString:@"family"]) {
            NSInteger minMembers = MAX(2, [k.family[@"minMembers"] integerValue] ?: 5);
            if ((NSInteger)i.members.count < minMembers) { i.state = MMClutterLive; i.why = @"it is no longer a family"; return; }
        }
    }
    // Nothing held open: a process's cwd, executable or open file under it keeps it, in every class.
    NSSet *held = open ?: MMOpenUnder(i.members);
    for (NSString *m in i.members) if ([held containsObject:m]) { i.state = MMClutterLive; i.why = @"a running process has a file open in it"; return; }
    if (leak) i.why = [NSString stringWithFormat:@"nothing has used it for %@", Span(age)];
}

/// Sizes through the worker in the app, in process elsewhere. Rows that must not be walked get no size.
- (void)size:(NSArray<MMClutterItem *> *)items {
    NSMutableArray *roots = [NSMutableArray new];
    for (MMClutterItem *i in items) if (i.kind.walk) [roots addObjectsFromArray:i.members];
    NSMutableDictionary<NSString *, NSDictionary *> *sizes = [NSMutableDictionary new];
    if (self.sizeWithWorker && roots.count) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSDictionary *got = nil;
        [MMSharedWorker() sizeTrees:roots reply:^(NSDictionary *s, NSError *e) { got = s; dispatch_semaphore_signal(done); }];
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC)) == 0 && got) [sizes addEntriesFromDictionary:got];
    }
    for (NSString *r in roots) {
        if (sizes[r]) continue;
        MMSize s = [MMSizer quick:r];
        sizes[r] = @{@"allocated": @(s.allocated), @"freedIfDeleted": @(s.freedIfDeleted), @"files": @(s.files), @"errors": @(s.errors)};
    }
    for (MMClutterItem *i in items) {
        MMSize total = {0};
        if (i.kind.walk) for (NSString *m in i.members) {
            NSDictionary *s = sizes[m];
            total.allocated += [s[@"allocated"] unsignedLongLongValue];
            total.freedIfDeleted += [s[@"freedIfDeleted"] unsignedLongLongValue];
            total.files += [s[@"files"] integerValue];
            total.errors += [s[@"errors"] integerValue];
        }
        i.size = total;
    }
}

- (MMSample *)sampleForLiveness {
    MMSenses *s = MMSenses.shared;
    return s.latest ?: [s sampleNow];
}

- (MMClutterItem *)inspect:(MMClutterItem *)old {
    if (!old.kind) return nil;
    NSArray *projects = [self currentProjects];
    MMClutterItem *i = [MMClutterItem new];
    i.kind = old.kind; i.path = old.path;
    if (old.kind.isFamily) {
        // A family is found again from its root, so members that came or went since the scan count.
        NSString *root = old.path.stringByDeletingLastPathComponent, *key = [old.path.lastPathComponent stringByReplacingOccurrencesOfString:@"*" withString:@""];
        NSMutableArray *members = [NSMutableArray new];
        for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *p = [root stringByAppendingPathComponent:name];
            if ([FamilyKey(name) isEqualToString:key] && [self kindFor:p projects:projects] == old.kind) [members addObject:p];
        }
        i.members = members;
    } else {
        struct stat st;
        if (lstat(old.path.fileSystemRepresentation, &st) != 0) return nil;
        i.members = @[old.path];
    }
    if (!i.members.count) return nil;
    [self linkOwner:i projects:projects];
    [self judge:i open:nil sample:[self sampleForLiveness] projects:projects];
    [self size:@[i]];
    i.trend = old.trend;
    return i;
}

#pragma mark Scanning

- (NSArray<MMClutterItem *> *)scanKinds:(NSArray<MMClutterKind *> *)kinds {
    [self loadIfNeeded];
    if (!MMClutterRoot()) return @[];   // a test with no clutter root scans nothing
    NSArray *projects = [self currentProjects];
    NSArray<MMClutterItem *> *found = [self discover:kinds projects:projects];
    MMSample *sample = [self sampleForLiveness];
    NSMutableArray *candidates = [NSMutableArray new];
    for (MMClutterItem *i in found) { [self linkOwner:i projects:projects]; [candidates addObjectsFromArray:i.members]; }
    NSSet *open = MMOpenUnder(candidates);
    for (MMClutterItem *i in found) [self judge:i open:open sample:sample projects:projects];
    found = [found filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMClutterItem *i, id _) { return i.why != kWholeSession; }]];
    [self size:found];
    // Trends: one point a day per row, its total on disk, and the fit over the last 30 days.
    NSDate *now = NSDate.date;
    NSMutableDictionary<NSString *, NSNumber *> *totals = [NSMutableDictionary new];
    for (MMClutterItem *i in found) totals[i.kind.kindID] = @(totals[i.kind.kindID].doubleValue + (double)i.size.allocated);
    NSMutableDictionary<NSString *, NSValue *> *trends = [NSMutableDictionary new];
    for (NSString *kid in totals) {
        if (!_byID[kid].walk) continue;
        [MMLog.shared addPoint:MMClutterSeries(kid) value:totals[kid].doubleValue at:now bucket:86400];
        MMClutterTrend t = MMClutterTrendOf([MMLog.shared points:MMClutterSeries(kid) since:[now dateByAddingTimeInterval:-kTrendDays * 86400]], now);
        trends[kid] = [NSValue valueWithBytes:&t objCType:@encode(MMClutterTrend)];
    }
    for (MMClutterItem *i in found) {
        NSValue *v = trends[i.kind.kindID];
        if (!v) continue;
        MMClutterTrend t; [v getValue:&t size:sizeof t];
        i.trend = t;
    }
    NSSet *scannedIDs = [NSSet setWithArray:[kinds valueForKey:@"kindID"]];
    BOOL changed = NO;
    @synchronized (self) {
        NSMutableArray *keep = [NSMutableArray new];
        for (MMClutterItem *i in _items) if (![scannedIDs containsObject:i.kind.kindID]) [keep addObject:i];
        NSArray *before = [[_items valueForKey:@"json"] copy];
        [keep addObjectsFromArray:found];
        [keep sortUsingComparator:^NSComparisonResult(MMClutterItem *a, MMClutterItem *b) {
            if (a.size.allocated != b.size.allocated) return a.size.allocated > b.size.allocated ? NSOrderedAscending : NSOrderedDescending;
            return [a.key compare:b.key];
        }];
        _items = keep;
        changed = ![before isEqualToArray:[keep valueForKey:@"json"]];
        for (NSString *kid in scannedIDs) _scanned[kid] = @(now.timeIntervalSince1970);
    }
    [self save];
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:MMClutterDidChangeNotification object:self];
    return found;
}

- (NSArray<MMClutterItem *> *)scan {
    [self scanKinds:_kinds];
    return self.items;
}

- (BOOL)scanDue {
    [self loadIfNeeded];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableArray *due = [NSMutableArray new];
    @synchronized (self) {
        for (MMClutterKind *k in _kinds) if (now - _scanned[k.kindID].doubleValue >= k.every) [due addObject:k];
    }
    if (!due.count) return NO;
    NSArray *before = [self.items valueForKey:@"json"];
    [self scanKinds:due];
    return ![before isEqualToArray:[self.items valueForKey:@"json"]];
}

- (void)start {
    @synchronized (self) {
        if (_timer) return;
        dispatch_queue_t q = MMQueue(@"core", @"clutter", QOS_CLASS_UTILITY);
        __weak MMClutterCatalog *weak = self;
        _timer = MMTimer(q, kTimerEvery, 60, ^{
            [MMJob run:@"clutter.scan" expert:@"core" on:q budget:900 work:^(MMJob *job) { [weak scanDue]; }];
        });
    }
}

- (void)stop {
    @synchronized (self) {
        if (_timer) dispatch_source_cancel(_timer);
        _timer = nil;
    }
}

@end
