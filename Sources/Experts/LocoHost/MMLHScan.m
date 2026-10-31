// LocoHost's hosts from Core's facts. See MMLHScan.h.
// What changed from LocoHost 0.1: the sample, sockets, args and cwd come from Senses, so this file never lists
// processes or sockets itself. Agent names are registry lookups. Sessions are Know's. Git and the allowlisted
// project files go through Core's fact cache on its own queue. The HTTP title probe is gone.
#import <AppKit/AppKit.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <arpa/inet.h>
#import <sys/stat.h>
#import "Experts/LocoHost/MMLHScan.h"
#import "UI/MMFormat.h"

static NSString *const kExpert = @"locohost";

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }

/// getenv, which costs a lookup where NSProcessInfo copies the whole environment. A rebuild reads these.
static NSString *Env(const char *key) {
    const char *v = getenv(key);
    return v && *v ? @(v) : nil;
}
static double EnvMinutes(NSString *key, double dflt) {
    NSString *env = Env(key.UTF8String);
    return (env.length ? env.doubleValue : dflt) * 60;
}
NSTimeInterval MMLHIdleSeconds(void) {
    NSString *env = Env("LOCOHOST_IDLE_MINUTES");
    return (env.length ? env.doubleValue : (double)MMPrefInt(@"locohost.idleMinutes", 30)) * 60;
}
NSTimeInterval MMLHMinUptime(void) { return EnvMinutes(@"LOCOHOST_MIN_UPTIME_MINUTES", 30); }
NSTimeInterval MMLHProactiveQuiet(void) { return EnvMinutes(@"LOCOHOST_PROACTIVE_MINUTES", 6 * 60); }

#pragma mark - Rules

MMRules *MMLHRules(void) {
    static MMRules *r; static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [MMRules rulesFor:kExpert defaults:@{
            // Never closed by Close Idle. Databases and infrastructure that many projects share.
            @"protect.names": @[@"postgres", @"mysqld", @"mariadbd", @"redis-server", @"valkey-server", @"mongod", @"memcached",
                                @"epmd", @"ollama", @"com.docker.backend", @"vpnkit-bridge", @"OrbStack Helper", @"clickhouse",
                                @"meilisearch", @"typesense-server", @"minio", @"mailpit", @"MailHog", @"caddy", @"nginx", @"httpd",
                                @"LM Studio", @"tailscaled", @"cloudflared"],
            @"protect.ports": @[], @"protect.paths": @[],
            // Listeners that are not localhosts you started. Listed apart, never acted on.
            @"ignore.names": @[@"rapportd", @"sharingd", @"ControlCenter", @"Spotify", @"OneDrive", @"Dropbox", @"Discord",
                               @"Slack", @"zoom.us", @"Microsoft Teams", @"Figma", @"Raycast", @"identityservicesd", @"remoted",
                               @"AirPlayXPCHelper", @"WiFiAgent", @"Creative Cloud", @"Adobe Desktop Service", @"Steam",
                               @"1Password", @"Google Drive", @"Code Helper", @"Code Helper (Plugin)", @"Cursor Helper",
                               @"Cursor Helper (Plugin)", @"Insomnia", @"MinMacs"],
            // Apps inside .app bundles whose listeners are dev infrastructure, so they are shown anyway.
            @"ignore.devApps": @[@"Docker*", @"OrbStack*", @"Ollama*", @"Postgres*", @"LM Studio*", @"Herd*", @"DBngin*", @"MAMP*", @"Local*"]}];
    });
    return r;
}

/// A path entry protects every folder below it. Wildcards match as MMRules does.
static BOOL PathProtected(NSString *cwd) {
    if (!cwd.length) return NO;
    for (id e in [MMLHRules() entries:@"protect.paths"]) {
        NSString *p = [e isKindOfClass:NSString.class] ? [e stringByExpandingTildeInPath] : nil;
        if (p.length && ![p containsString:@"*"] && ([cwd isEqualToString:p] || [cwd hasPrefix:[p stringByAppendingString:@"/"]])) return YES;
    }
    return [MMLHRules() list:@"protect.paths" key:nil matches:cwd] || [MMLHRules() list:@"protect.paths" key:nil matches:cwd.stringByAbbreviatingWithTildeInPath];
}

BOOL MMLHProtects(MMLHHost *h) {
    MMRules *r = MMLHRules();
    if ([r list:@"protect.names" key:nil matches:h.name]) return YES;
    for (NSNumber *p in h.ports) if ([r list:@"protect.ports" key:nil matches:p.stringValue]) return YES;
    return PathProtected(h.cwd) || (h.wrapperCwd.length && PathProtected(h.wrapperCwd));
}

static BOOL Ignores(NSString *name, NSString *exec, NSString *appBundle) {
    MMRules *r = MMLHRules();
    if ([r list:@"ignore.names" key:nil matches:name]) return YES;
    for (NSString *p in @[@"/System/", @"/usr/libexec/", @"/usr/sbin/", @"/Library/Apple/"]) if ([exec hasPrefix:p]) return YES;
    // Part of a running app: ignored unless the app is dev infrastructure. An interpreter that ships as an app bundle,
    // such as Python.app, is started from a shell, belongs to no running app, and is not ignored.
    if (!appBundle) return NO;
    return ![r list:@"ignore.devApps" key:nil matches:appBundle];
}

#pragma mark - Launchers

static NSSet *Wrappers(void) { return [NSSet setWithArray:@[@"npm", @"pnpm", @"yarn", @"bun", @"bunx", @"npx", @"pnpx"]]; }
static NSSet *Shells(void) { return [NSSet setWithArray:@[@"sh", @"bash", @"zsh", @"dash", @"fish"]]; }
static NSSet *Multiplexers(void) { return [NSSet setWithArray:@[@"tmux", @"screen", @"zellij", @"abduco", @"dtach"]]; }

/// The tool a process runs as: argv[0]'s basename, or the package manager script that node or bun runs.
static NSString *ToolName(NSString *name, NSArray<NSString *> *args) {
    NSString *base = [[args.firstObject componentsSeparatedByString:@" "].firstObject lastPathComponent] ?: name;
    if (!base.length) base = name ?: @"";
    if (!([base isEqualToString:@"node"] || [base isEqualToString:@"bun"]) || args.count < 2) return base;
    NSString *s = args[1].lastPathComponent;
    if ([@[@"js", @"cjs", @"mjs"] containsObject:s.pathExtension]) s = s.stringByDeletingPathExtension;
    return [Wrappers() containsObject:s] ? s : base;
}

/// "pnpm dev --port 3300": the wrapper and the first three words after it.
static NSString *WrapperLabel(NSString *tool, NSArray<NSString *> *args) {
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *a in args) [words addObjectsFromArray:[a componentsSeparatedByString:@" "]];
    NSUInteger at = [words indexOfObjectPassingTest:^BOOL(NSString *w, NSUInteger i, BOOL *stop) {
        return [[w.lastPathComponent stringByDeletingPathExtension] isEqualToString:tool]; }];
    if (at == NSNotFound) return tool;
    NSArray *rest = [words subarrayWithRange:NSMakeRange(at + 1, MIN(3, words.count - at - 1))];
    return [[@[tool] arrayByAddingObjectsFromArray:rest] componentsJoinedByString:@" "];
}

#pragma mark - Git and project files

static NSString *HeadText(NSString *path, NSUInteger max) {
    NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *d = [f readDataUpToLength:max error:nil];
    [f closeFile];
    return d ? ([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding]) : nil;
}

static NSString *Match(NSString *s, NSString *pattern) {
    if (!s) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    return m && [m rangeAtIndex:1].location != NSNotFound ? [s substringWithRange:[m rangeAtIndex:1]] : nil;
}

/// The first heading and the first paragraph of prose, skipping badges, images, HTML and code.
static NSString *ReadmeIntro(NSString *text) {
    NSMutableArray *para = [NSMutableArray new];
    NSString *heading = nil;
    BOOL inCode = NO;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([l hasPrefix:@"```"]) { inCode = !inCode; if (para.count) break; continue; }
        if (inCode) continue;
        if ([l hasPrefix:@"#"]) {
            if (!heading) heading = [l stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
            if (para.count) break;
            continue;
        }
        if (!l.length) { if (para.count) break; continue; }
        if ([l hasPrefix:@"!["] || [l hasPrefix:@"[!["] || [l hasPrefix:@"<"] || [l hasPrefix:@"|"] || [l hasPrefix:@"---"] || [l hasPrefix:@"[!"]) continue;
        [para addObject:l];
    }
    NSString *p = para.count ? [para componentsJoinedByString:@" "] : nil;
    return heading && p ? [NSString stringWithFormat:@"%@: %@", heading, p] : heading ?: p;
}

/// The package.json script a server runs: the word after the runner, else a script whose text is in the command.
static NSString *ScriptName(NSArray<NSString *> *wrapperArgs, NSString *command, NSDictionary *scripts) {
    if (!Dict(scripts)) return nil;
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *a in wrapperArgs) [words addObjectsFromArray:[a componentsSeparatedByString:@" "]];
    for (NSUInteger i = 1; i < words.count; i++) {
        NSString *w = words[i];
        if ([w hasPrefix:@"-"] || [w isEqualToString:@"run"] || [w hasSuffix:@".js"] || [w hasSuffix:@".cjs"]) continue;
        if (Str(scripts[w])) return w;
        break;
    }
    for (NSString *k in [scripts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *v = Str(scripts[k]);
        if (v.length > 3 && [command containsString:v]) return k;
    }
    return nil;
}

/// What the project's own files say, read from an allowlist: the package.json name, description and scripts,
/// the README's first heading and paragraph, mix.exs and pyproject.toml names, and the names of config files.
/// .env files and other contents are never opened. Ported from Project in LocoHost's Intel.m.
static NSDictionary *ReadProject(NSArray<NSString *> *folders, NSArray<NSString *> *wrapperArgs, NSString *command) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableDictionary *p = [NSMutableDictionary new];
    NSMutableOrderedSet *configs = [NSMutableOrderedSet new];
    NSArray *configNames = @[@"vite.config.", @"next.config.", @"astro.config.", @"svelte.config.", @"nuxt.config.", @"remix.config.",
                             @"webpack.config.", @"tailwind.config.", @"tsconfig.json", @"docker-compose.yml", @"compose.yaml", @"Procfile",
                             @"manage.py", @"Gemfile", @"Cargo.toml", @"go.mod", @"wrangler.toml", @"netlify.toml", @"vercel.json",
                             @"turbo.json", @"pnpm-workspace.yaml", @"mix.exs", @"pyproject.toml", @"requirements.txt", @"playwright.config."];
    for (NSString *dir in folders) {
        NSString *pkg = [dir stringByAppendingPathComponent:@"package.json"];
        if (!p[@"name"] && [fm fileExistsAtPath:pkg]) {
            NSString *text = HeadText(pkg, 512 * 1024);
            NSDictionary *j = Dict(text ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil);
            if (Str(j[@"name"]).length) p[@"name"] = MMCut(j[@"name"], 80);
            if (Str(j[@"description"]).length) p[@"description"] = MMCut(j[@"description"], 300);
            NSString *script = ScriptName(wrapperArgs, command, j[@"scripts"]);
            if (script) { p[@"scriptName"] = script; p[@"script"] = MMCut([NSString stringWithFormat:@"%@: %@", script, j[@"scripts"][script]], 200); }
        }
        if (!p[@"readme"]) for (NSString *n in @[@"README.md", @"readme.md", @"Readme.md", @"README.markdown", @"README"]) {
            NSString *text = HeadText([dir stringByAppendingPathComponent:n], 16384);
            if (!text) continue;
            NSString *intro = ReadmeIntro(text);
            if (intro.length) p[@"readme"] = MMCut(intro, 300);
            break;
        }
        NSString *mix = HeadText([dir stringByAppendingPathComponent:@"mix.exs"], 16384);
        if (mix && !p[@"app"]) {
            NSString *app = Match(mix, @"app:\\s*:(\\w+)");
            if (app) p[@"app"] = app;
            NSString *desc = Match(mix, @"description:\\s*\"([^\"]*)\"");
            if (!p[@"description"] && desc.length) p[@"description"] = MMCut(desc, 300);
        }
        NSString *py = HeadText([dir stringByAppendingPathComponent:@"pyproject.toml"], 16384);
        if (py) {
            NSString *name = Match(py, @"^name\\s*=\\s*\"([^\"]+)\""), *desc = Match(py, @"^description\\s*=\\s*\"([^\"]+)\"");
            if (!p[@"name"] && name.length) p[@"name"] = MMCut(name, 80);
            if (!p[@"description"] && desc.length) p[@"description"] = MMCut(desc, 300);
        }
        // Only the names of config files, never their contents.
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil])
            for (NSString *c in configNames) if ([c hasSuffix:@"."] ? [f hasPrefix:c] : [f isEqualToString:c]) [configs addObject:f];
    }
    if (configs.count) p[@"configs"] = [configs.array subarrayWithRange:NSMakeRange(0, MIN(12, configs.count))];
    return p;
}

/// The checkout of a folder no walk covered, from MMRepoIndex's read of the .git files above it. A miss computes in
/// the background, so a rebuild never waits on a file read.
static MMFactCache *TreeCache(void) {
    static MMFactCache *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[MMFactCache alloc] initWithName:@"locohost.tree" maxAge:30 persist:NO]; });
    return c;
}

NSString *MMLHMergeWords(MMGitFacts *g, BOOL isMain) {
    if (!g || isMain) return nil;
    switch (g.merged) {
        case MMMergedSquash: return @"squash-merged";
        case MMMergedPR: return @"merged through a pull request";
        case MMMergedNone: return @"not merged";
        default: return @"merged";
    }
}

NSString *MMLHCanon(NSString *p) {
    for (NSString *x in @[@"/private/var/", @"/private/tmp/"]) if ([p hasPrefix:x]) return [p substringFromIndex:8];
    return p;
}

NSDictionary *MMLHGitOf(NSString *raw, MMFacts *facts, MMLHRead read) {
    if (!raw.length) return @{};
    // The kernel names a process's folder /private/var/x, and the repo index keeps /var/x.
    NSString *folder = MMLHCanon(raw);
    MMWorktree *wt = nil;
    for (MMWorktree *w in facts.worktrees) {
        NSString *p = MMLHCanon(w.path);
        if (p.length && ([folder isEqualToString:p] || [folder hasPrefix:[p stringByAppendingString:@"/"]]) && p.length > MMLHCanon(wt.path).length) wt = w;
    }
    BOOL walked = wt != nil;
    if (!wt) {
        id x = [TreeCache() valueFor:folder fingerprint:@"" orCompute:^id{ return [MMRepoIndex.shared worktreeAt:folder] ?: NSNull.null; }
                                wait:read == MMLHReadNow];
        wt = [x isKindOfClass:MMWorktree.class] ? x : nil;
    }
    if (!wt) return @{};
    NSMutableDictionary *g = [NSMutableDictionary new];
    g[@"repo"] = wt.repo.lastPathComponent ?: wt.path.lastPathComponent; g[@"root"] = wt.path;
    NSString *root = MMLHCanon(wt.path);
    g[@"subdir"] = [folder hasPrefix:[root stringByAppendingString:@"/"]] ? [folder substringFromIndex:root.length + 1] : @"";
    if (!wt.isMain) g[@"worktree"] = wt.path.lastPathComponent;
    // The git facts the index holds, from memory, for a worktree under the roots. A worktree it has not read yet has
    // a branch and no facts. A checkout outside the roots has only what its .git files say: asking the index for its
    // facts would run seven git commands for each such server's checkout, at launch and for each new one, and
    // WorkForest lists no card for it to link to. Issue #58's bench saw those runs as wakeups.
    MMGitFacts *gf = [facts gitFor:wt];
    if (!gf && walked) gf = [MMRepoIndex.shared factsFor:wt wait:NO];
    NSString *branch = wt.branch ?: gf.branch;
    if (branch) g[@"branch"] = branch;
    else if (gf.head.length >= 7) g[@"branch"] = [@"detached " stringByAppendingString:[gf.head substringToIndex:7]];
    if (gf.lastCommit) g[@"touched"] = @(gf.lastCommit.timeIntervalSince1970);
    NSString *merged = MMLHMergeWords(gf, wt.isMain);
    if (merged) g[@"merged"] = merged;
    return g;
}

static MMFactCache *ProjectCache(void) {
    static MMFactCache *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[MMFactCache alloc] initWithName:@"locohost.project" maxAge:300 persist:NO]; });
    return c;
}

#pragma mark - Sessions

/// The session that was open when the server started, from Know's index: it began at most 5 seconds after the server
/// and was written to at most a minute before. A session in one of the server's folders beats one inside them.
/// The same rule as -[MMSessions openAt:inFolders:], run on the facts so it reads no file.
static MMSession *SessionAt(NSDate *t, NSArray<NSString *> *folders, NSArray<MMSession *> *sessions) {
    MMSession *best = nil; BOOL bestExact = NO;
    for (MMSession *s in sessions) {
        if (!s.started || !s.lastActive || !s.cwd.length || !t) continue;
        if ([s.started timeIntervalSinceDate:t] > 5 || [s.lastActive timeIntervalSinceDate:t] < -60) continue;
        BOOL exact = NO, inside = NO;
        for (NSString *f in folders) {
            if ([s.cwd isEqualToString:f]) exact = YES;
            if ([s.cwd isEqualToString:f] || [s.cwd hasPrefix:[f stringByAppendingString:@"/"]]) inside = YES;
        }
        if (!inside) continue;
        if (!best || (exact && !bestExact) || (exact == bestExact && [s.started compare:best.started] == NSOrderedDescending)) { best = s; bestExact = exact; }
    }
    return best;
}

static NSString *AgentName(NSString *harness) {
    for (MMAgentRow *r in MMRegistry.shared.rows) if ([r.harnessID isEqualToString:harness]) return r.name;
    return harness;
}

#pragma mark - Sockets

static BOOL Loopback(const MMSocket *s, BOOL remote) {
    const uint8_t *a = remote ? s->remoteAddr : s->localAddr;
    if (s->family == AF_INET) return a[0] == 127;
    for (int i = 0; i < 15; i++) if (a[i]) return NO;
    return a[15] == 1;
}

static NSString *LocalAddr(const MMSocket *s) {
    char buf[INET6_ADDRSTRLEN] = {0};
    if (s->family == AF_INET) {
        if (!s->localAddr[0] && !s->localAddr[1] && !s->localAddr[2] && !s->localAddr[3]) return @"*";
        inet_ntop(AF_INET, s->localAddr, buf, sizeof buf);
    } else {
        BOOL any = YES;
        for (int i = 0; i < 16; i++) if (s->localAddr[i]) any = NO;
        if (any) return @"*";
        inet_ntop(AF_INET6, s->localAddr, buf, sizeof buf);
    }
    return @(buf);
}

#pragma mark - Scanner

/// What LocoHost remembers about one server between samples, in memory.
@interface MMLHTrack : NSObject
@property (copy) NSSet<NSString *> *conns;
@property NSInteger streak;
@property double cpuSeconds;                    // tree CPU time seen since LocoHost first saw it
@property (strong) NSDate *lastAt, *since;
@property (strong) NSArray *detectArgs, *detectPorts;   // what MMLHDetect read, and what it said
@property (copy) NSString *framework, *kind;
@end
@implementation MMLHTrack
@end

@implementation MMLHScanner {
    NSMutableDictionary<NSString *, MMLHTrack *> *_track;
    NSMutableDictionary *_activity;             // {since, hosts: {key: {firstSeen, lastSeen, lastActive, idleCPU}}}
    MMStateFile *_file;
    NSDate *_lastSampleAt, *_lastSave;
    __weak MMSample *_cachedSample;
    NSArray<MMLHHost *> *_cachedHosts;
    NSArray<NSDictionary *> *_cachedIgnored;
    NSUInteger _savedCount;
}

+ (instancetype)shared {
    static MMLHScanner *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MMLHScanner new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _track = [NSMutableDictionary new];
        _file = [MMStateFile fileNamed:@"activity" expert:kExpert];
        _activity = [self load];
    }
    return self;
}

- (NSMutableDictionary *)load {
    NSDictionary *disk = Dict([_file read]);
    NSMutableDictionary *a = disk ? (NSMutableDictionary *)CFBridgingRelease(CFPropertyListCreateDeepCopy(NULL, (__bridge CFDictionaryRef)disk, kCFPropertyListMutableContainers))
                                  : [NSMutableDictionary new];
    if (![a[@"hosts"] isKindOfClass:NSMutableDictionary.class]) a[@"hosts"] = [NSMutableDictionary new];
    return a;
}

- (NSDate *)watchingSince {
    @synchronized (self) {
        double s = [_activity[@"since"] doubleValue];
        return s ? [NSDate dateWithTimeIntervalSince1970:s] : NSDate.date;
    }
}

/// Merges with what is on disk, so the CLI and the app never erase each other's observations. From SaveActivity.
- (void)save {
    NSDictionary *mine = [_activity copy];
    __block NSDictionary *merged = nil;
    [_file update:^id(id diskValue) {
        NSMutableDictionary *disk = [Dict(diskValue) mutableCopy] ?: [NSMutableDictionary new];
        NSMutableDictionary *hosts = [Dict(disk[@"hosts"]) mutableCopy] ?: [NSMutableDictionary new];
        double now = NSDate.date.timeIntervalSince1970;
        for (NSString *k in mine[@"hosts"]) {
            NSDictionary *a = mine[@"hosts"][k];
            NSMutableDictionary *b = [Dict(hosts[k]) mutableCopy];
            if (!b) { hosts[k] = a; continue; }
            // The waste counter belongs to whichever side saw the latest activity.
            if ([a[@"lastActive"] doubleValue] >= [b[@"lastActive"] doubleValue]) b[@"idleCPU"] = a[@"idleCPU"] ?: @0;
            for (NSString *f in @[@"lastActive", @"lastSeen"]) if ([a[f] doubleValue] > [b[f] doubleValue]) b[f] = a[f];
            if (a[@"firstSeen"] && (!b[@"firstSeen"] || [a[@"firstSeen"] doubleValue] < [b[@"firstSeen"] doubleValue])) b[@"firstSeen"] = a[@"firstSeen"];
            hosts[k] = b;
        }
        // A week after a host was last seen, it is forgotten.
        for (NSString *k in hosts.allKeys) if (now - [hosts[k][@"lastSeen"] doubleValue] > 7 * 86400) [hosts removeObjectForKey:k];
        double since = MIN([mine[@"since"] doubleValue] ?: now, [disk[@"since"] doubleValue] ?: now);
        disk[@"since"] = @(since);
        disk[@"hosts"] = hosts;
        merged = disk;
        return disk;
    }];
    if (merged) {
        NSMutableDictionary *a = (NSMutableDictionary *)CFBridgingRelease(CFPropertyListCreateDeepCopy(NULL, (__bridge CFDictionaryRef)merged, kCFPropertyListMutableContainers));
        if (![a[@"hosts"] isKindOfClass:NSMutableDictionary.class]) a[@"hosts"] = [NSMutableDictionary new];
        _activity = a;
    }
}

- (NSArray<MMLHHost *> *)hostsFrom:(MMFacts *)facts ignored:(NSArray<NSDictionary *> **)ignoredOut read:(MMLHRead)read {
    MMSample *s = facts.sample;
    if (!s) { if (ignoredOut) *ignoredOut = @[]; return @[]; }
    @synchronized (self) {
        if (_cachedSample == s && _cachedHosts) { if (ignoredOut) *ignoredOut = _cachedIgnored; return _cachedHosts; }
        NSArray *ignored = nil;
        NSArray *hosts = [self build:facts ignored:&ignored read:read];
        _cachedSample = s; _cachedHosts = hosts; _cachedIgnored = ignored;
        if (ignoredOut) *ignoredOut = ignored;
        return hosts;
    }
}

/// One pass over the sample's sockets. Runs under the lock.
- (NSArray<MMLHHost *> *)build:(MMFacts *)facts ignored:(NSArray **)ignoredOut read:(MMLHRead)read {
    MMSample *s = facts.sample;
    NSDate *date = s.at ?: NSDate.date;
    // Only a newer sample moves the counters, so fresh facts and a rebuild on an older sample never count twice.
    BOOL advance = !_lastSampleAt || [date compare:_lastSampleAt] == NSOrderedDescending;
    double dt = advance && _lastSampleAt ? [date timeIntervalSinceDate:_lastSampleAt] : 0;
    if (advance) _lastSampleAt = date;
    pid_t me = getpid();
    NSTimeInterval idleSeconds = MMLHIdleSeconds();

    NSUInteger sc = 0;
    const MMSocket *sv = [s sockets:&sc];
    // Listeners by pid. A forked worker that shares its parent's port rolls up into the parent.
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSString *> *> *listen = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < sc; i++) if (sv[i].state == MMSocketListen) {
        NSMutableDictionary *m = listen[@(sv[i].pid)] ?: (listen[@(sv[i].pid)] = [NSMutableDictionary new]);
        NSString *prev = m[@(sv[i].localPort)], *a = LocalAddr(&sv[i]);
        m[@(sv[i].localPort)] = (!prev || [a isEqualToString:@"*"]) ? a : prev;
    }
    for (NSNumber *pid in listen.allKeys) {
        NSSet *mine = [NSSet setWithArray:listen[pid].allKeys];
        for (NSNumber *a in [s ancestorsOf:pid.intValue limit:6])
            if (listen[a] && [[NSSet setWithArray:listen[a].allKeys] intersectsSet:mine]) { [listen removeObjectForKey:pid]; break; }
    }

    // MinMacs's own connections are not activity: the app, a CLI run, and `ready --http` from any of them.
    NSMutableSet<NSNumber *> *ours = [NSMutableSet setWithObject:@(me)];
    for (MMProc *p in s.procs.objectEnumerator) if ([p.name isEqualToString:@"MinMacs"] || [p.name isEqualToString:@"locohost"]) [ours addObject:@(p.pid)];
    NSMutableSet<NSNumber *> *ourLocalPorts = [NSMutableSet new];
    for (NSUInteger i = 0; i < sc; i++)
        if ([ours containsObject:@(sv[i].pid)] && sv[i].state == MMSocketEstablished) [ourLocalPorts addObject:@(sv[i].localPort)];

    NSMutableArray<MMLHHost *> *hosts = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *ignored = [NSMutableArray new];
    NSMutableDictionary *act = _activity[@"hosts"];
    for (NSNumber *pidN in listen) {
        pid_t pid = pidN.intValue;
        MMProc *p = [s proc:pid];
        if (pid == me || !p) continue;
        NSArray *ports = [listen[pidN].allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSArray<NSString *> *args = [s argsOf:pid];
        NSString *exec = args.firstObject ?: @"";
        NSRunningApplication *owner = MMOwningApp(s, pid);
        NSString *appPath = owner.bundleURL.path;
        NSString *appBundle = appPath && [exec hasPrefix:[appPath stringByAppendingString:@"/"]] ? appPath.lastPathComponent : nil;
        if (Ignores(p.name, exec, appBundle)) { [ignored addObject:@{@"pid": @(pid), @"name": p.name ?: @"", @"ports": ports}]; continue; }

        MMLHHost *h = [MMLHHost new];
        h.pid = pid; h.ppid = p.ppid; h.startSec = p.startSec; h.name = p.name; h.execPath = exec;
        h.key = [NSString stringWithFormat:@"%d:%llu", pid, (unsigned long long)p.startSec];
        h.started = [NSDate dateWithTimeIntervalSince1970:p.startSec];
        h.args = args; h.cwd = [s cwdOf:pid]; h.ports = ports;
        h.bind = listen[pidN][@(h.port)];
        // The framework comes from the args and ports, which stay put while the process lives, and a sample
        // carries the args object from the last one. MMLHDetect lowercases and searches the whole command line.
        MMLHTrack *known = _track[h.key];
        if (known.framework && (known.detectArgs == args || [known.detectArgs isEqual:args]) && [known.detectPorts isEqual:ports]) {
            h.framework = known.framework; h.kind = known.kind;
        } else {
            NSString *fw, *kind; MMLHDetect(p.name, args, ports, &fw, &kind); h.framework = fw; h.kind = kind;
        }

        // The tree: the listener and everything below it.
        NSArray<NSNumber *> *tree = [s treeOf:pid limit:500];
        NSMutableArray *starts = [NSMutableArray new];
        double energy = 0;
        for (NSNumber *t in tree) { MMProc *q = [s proc:t.intValue]; [starts addObject:@(q.startSec)]; energy = MAX(energy, q.energyRank); }
        h.treePids = tree; h.treeStarts = starts;
        h.cpuPercent = MAX(0, [s treeCPU:pid]); h.memory = [s treeFootprint:pid]; h.processCount = tree.count; h.energyRank = energy;

        // Who started it: package manager wrappers right above, then an agent, a shell, a multiplexer or an app.
        NSMutableArray *via = [NSMutableArray new];
        NSString *wrapper = nil;
        BOOL inWrappers = YES, owned = NO, exclusive = YES;
        NSArray<NSNumber *> *chain = [s ancestorsOf:pid limit:20];
        for (NSUInteger i = 0; i < chain.count; i++) {
            pid_t ap = chain[i].intValue;
            MMProc *a = [s proc:ap];
            if (!a || ap <= 1) break;
            NSArray *aargs = [s argsOf:ap];
            NSString *tool = ToolName(a.name, aargs);
            MMProc *above = i + 1 < chain.count ? [s proc:chain[i + 1].intValue] : nil;
            // The `sh -c` a package manager runs a script through belongs to the wrapper above it.
            BOOL scriptShell = inWrappers && [Shells() containsObject:tool] && above && above.pid > 1 &&
                               [Wrappers() containsObject:ToolName(above.name, [s argsOf:above.pid])];
            if (inWrappers && ([Wrappers() containsObject:tool] || scriptShell)) {
                // Signaled on stop only while each step down to the server is its only child.
                if (exclusive && [s childrenOf:ap].count == 1) {
                    if (!scriptShell) { h.wrapperPid = ap; h.wrapperStart = a.startSec; h.wrapperArgs = aargs; h.wrapperCwd = [s cwdOf:ap]; }
                } else exclusive = NO;
                if (!scriptShell) wrapper = WrapperLabel(tool, aargs);
                continue;
            }
            inWrappers = NO;
            owned = YES;   // a live shell, agent, multiplexer or app holds it
            if (!h.agent) {
                MMAgentRow *row = [MMRegistry.shared rowMatching:a sample:s];
                if (row) { h.agent = row.name; h.agentPid = ap; }
                else if ([[aargs componentsJoinedByString:@" "] containsString:@"/.claude/shell-snapshots/"]) { h.agent = AgentName(@"claude-code"); h.agentPid = ap; }
            }
            if ([Multiplexers() containsObject:tool]) { [via addObject:tool]; break; }
            if (MMAppWithPid(s, ap)) break;
        }
        if (!h.agent) {
            MMAgent *ag = [MMRegistry.shared agentAbove:pid in:facts.agents sample:s];
            if (ag && ag.key.pid != pid) { h.agent = ag.row.name ?: AgentName(ag.harnessID); h.agentPid = ag.key.pid; }
        }
        if (wrapper) [via insertObject:wrapper atIndex:0];
        if (h.agent && ![via containsObject:h.agent]) [via addObject:h.agent];
        pid_t resp = MMResponsiblePidIn(s, pid);
        NSRunningApplication *ra = resp != pid ? MMAppWithPid(s, resp) : nil;
        if (ra.localizedName && ![via containsObject:ra.localizedName]) [via addObject:ra.localizedName];
        // launchd adopts a process whose parent exits. One an app or a terminal started, which macOS still names
        // as responsible, that has no shell, agent or app above it now, lost its parent. A brew service is responsible
        // for itself.
        h.orphaned = !owned && resp != pid && ![h.kind isEqualToString:@"service"];
        if (h.orphaned) [via addObject:@"parent exited"];
        else if (!owned) [via addObject:@"launchd"];
        h.launcher = [via componentsJoinedByString:@" · "];

        // Git, through the one function that knows where git facts come from.
        NSString *gitDir = h.wrapperCwd.length ? h.wrapperCwd : h.cwd;
        if (![h.kind isEqualToString:@"service"] && gitDir.length) {   // a brew service's data folder sits inside Homebrew's own repo
            NSDictionary *g = MMLHGitOf(gitDir, facts, read);
            h.repo = Str(g[@"repo"]); h.repoRoot = Str(g[@"root"]); h.subdir = Str(g[@"subdir"]);
            h.branch = Str(g[@"branch"]); h.worktree = Str(g[@"worktree"]);
            h.repoTouched = g[@"touched"] ? [NSDate dateWithTimeIntervalSince1970:[g[@"touched"] doubleValue]] : nil;
            h.merged = Str(g[@"merged"]);
        }

        // The project's own files, for dev servers only.
        NSMutableOrderedSet *folders = [NSMutableOrderedSet new];
        for (NSString *d in @[h.cwd ?: @"", h.wrapperCwd ?: @"", h.repoRoot ?: @""]) if (d.length > 1) [folders addObject:d];
        if (h.isDev && folders.count) {
            NSArray *fs = folders.array, *wargs = h.wrapperArgs ?: @[];
            NSString *cmd = [h.command stringByAppendingFormat:@" %@", [h.args componentsJoinedByString:@" "]];
            NSString *pkey = [[fs componentsJoinedByString:@"|"] stringByAppendingFormat:@"|%@", wargs.count ? [wargs componentsJoinedByString:@" "] : cmd];
            NSDictionary *proj = [ProjectCache() valueFor:pkey fingerprint:@"" orCompute:^id{ return ReadProject(fs, wargs, cmd); } wait:read == MMLHReadNow];
            NSMutableDictionary *pf = [Dict(proj) mutableCopy];
            h.script = Str(pf[@"scriptName"]);
            [pf removeObjectForKey:@"scriptName"];
            h.projectFacts = pf.count ? pf : nil;
            MMSession *x = SessionAt(h.started, fs, facts.sessions);
            if (x) {
                NSMutableDictionary *sd = [@{@"agent": AgentName(x.agent) ?: @"an agent", @"id": x.sessionID ?: @"",
                                             @"startedAt": @(x.started.timeIntervalSince1970), @"lastActiveAt": @(x.lastActive.timeIntervalSince1970),
                                             @"match": [fs containsObject:x.cwd] ? @"session runs in this folder" : @"session runs inside this folder"} mutableCopy];
                if (x.title.length) sd[@"title"] = MMCut(x.title, 200);
                if (x.liveStatus.length) sd[@"status"] = x.liveStatus;
                h.session = sd;
            }
        }

        // Connections: server-side established sockets on its ports, minus the ones MinMacs opened.
        // An open connection can be a browser tab nobody looks at. A new one is a request someone just made.
        NSSet *portSet = [NSSet setWithArray:ports], *treeSet = [NSSet setWithArray:tree];
        NSMutableSet *connNow = [NSMutableSet new];
        for (NSUInteger i = 0; i < sc; i++)
            if (sv[i].state == MMSocketEstablished && [treeSet containsObject:@(sv[i].pid)] && [portSet containsObject:@(sv[i].localPort)] &&
                !(Loopback(&sv[i], YES) && [ourLocalPorts containsObject:@(sv[i].remotePort)]))
                [connNow addObject:[NSString stringWithFormat:@"%u-%u", sv[i].localPort, sv[i].remotePort]];
        MMLHTrack *t = _track[h.key];
        BOOL firstLook = !t;
        if (!t) { t = [MMLHTrack new]; t.since = date; _track[h.key] = t; }
        t.detectArgs = h.args; t.detectPorts = h.ports; t.framework = h.framework; t.kind = h.kind;
        NSMutableSet *fresh = [connNow mutableCopy];
        if (firstLook) [fresh removeAllObjects]; else [fresh minusSet:t.conns ?: [NSSet set]];   // the first look has nothing to compare with
        if (!advance) [fresh removeAllObjects];
        NSCountedSet *clients = [NSCountedSet new];
        for (NSUInteger i = 0; i < sc; i++) {
            if (sv[i].state != MMSocketEstablished || !Loopback(&sv[i], YES) || [ours containsObject:@(sv[i].pid)] || [treeSet containsObject:@(sv[i].pid)]) continue;
            if (![portSet containsObject:@(sv[i].remotePort)]) continue;
            // An app's helper, such as a browser's network process, counts as the app. A command line process counts
            // as itself, even though macOS names the terminal it was started in as responsible.
            NSString *cexec = [s argsOf:sv[i].pid].firstObject ?: @"", *cn = nil;
            if ([cexec containsString:@".app/"] || [cexec containsString:@".xpc/"])
                cn = MMAppWithPid(s, MMResponsiblePidIn(s, sv[i].pid)).localizedName;
            [clients addObject:cn ?: [s proc:sv[i].pid].name ?: @"?"];
        }
        h.connections = connNow.count; h.newConnections = fresh.count;
        NSMutableArray *cl = [NSMutableArray new];
        for (NSString *c in clients) [cl addObject:[clients countForObject:c] > 1 ? [NSString stringWithFormat:@"%@ ×%lu", c, (unsigned long)[clients countForObject:c]] : c];
        h.clients = [cl sortedArrayUsingSelector:@selector(compare:)];

        // CPU counts as work when it is well above this server's own average, two samples in a row.
        // BEAM and file watchers spin at a steady low level that means nothing.
        double watched = MAX(1, [date timeIntervalSinceDate:t.since]);
        double baseline = t.cpuSeconds / watched * 100;
        BOOL hot = dt > 0 && h.cpuPercent >= MAX(10.0, 3 * baseline);
        if (advance) {
            t.streak = hot ? t.streak + 1 : 0;
            t.cpuSeconds += h.cpuPercent / 100 * dt;
            t.conns = connNow; t.lastAt = date;
        }
        h.busy = t.streak >= 2;
        BOOL busy = fresh.count > 0 || h.busy;
        NSMutableDictionary *a = act[h.key];
        if (![a isKindOfClass:NSMutableDictionary.class]) { a = [NSMutableDictionary dictionaryWithDictionary:@{@"firstSeen": @(date.timeIntervalSince1970)}]; act[h.key] = a; }
        if (advance) {
            a[@"lastSeen"] = @(date.timeIntervalSince1970);
            if (busy) { a[@"lastActive"] = @(date.timeIntervalSince1970); a[@"idleCPU"] = @0; }
            else a[@"idleCPU"] = @([a[@"idleCPU"] doubleValue] + h.cpuPercent / 100 * dt);
        }
        h.idleCPUSeconds = [a[@"idleCPU"] doubleValue];
        h.firstSeen = [NSDate dateWithTimeIntervalSince1970:[a[@"firstSeen"] doubleValue]];
        h.lastActive = a[@"lastActive"] ? [NSDate dateWithTimeIntervalSince1970:[a[@"lastActive"] doubleValue]] : nil;
        NSDate *quietSince = h.lastActive ?: h.firstSeen;
        h.state = busy ? MMLHActive : ([date timeIntervalSinceDate:quietSince] >= idleSeconds ? MMLHIdle : MMLHRecent);
        h.isProtected = MMLHProtects(h);
        [hosts addObject:h];
    }
    if (!_activity[@"since"]) _activity[@"since"] = @(date.timeIntervalSince1970);
    // Servers that are gone leave the memory, so the tracker does not grow with every restart.
    NSMutableSet *live = [NSMutableSet new];
    for (MMLHHost *h in hosts) [live addObject:h.key];
    for (NSString *k in _track.allKeys) if (![live containsObject:k]) [_track removeObjectForKey:k];
    if (advance && (read == MMLHReadNow || !_lastSave || -_lastSave.timeIntervalSinceNow > 30 || hosts.count != _savedCount)) {
        [self save]; _lastSave = NSDate.date; _savedCount = hosts.count;
    }

    [hosts sortUsingComparator:^NSComparisonResult(MMLHHost *x, MMLHHost *y) { return [@(x.port) compare:@(y.port)]; }];
    // Two dev servers on the same folder and branch: usually one was started again and the first one forgotten.
    for (MMLHHost *h in hosts) {
        if (!h.isDev || !h.cwd.length || [h.cwd isEqualToString:@"/"]) continue;
        NSMutableArray *same = [NSMutableArray new];
        for (MMLHHost *o in hosts)
            if (o != h && o.isDev && [o.cwd isEqualToString:h.cwd] && (o.branch == h.branch || [o.branch isEqualToString:h.branch])) [same addObject:@(o.port)];
        if (same.count) h.duplicates = same;
    }
    // Decision 8: a server is known by its project folder and script, else its folder and port.
    // A second server with the same folder and script adds its port, so two findings never share an id.
    NSMutableSet *taken = [NSMutableSet new];
    for (MMLHHost *h in hosts) {
        NSString *folder = (h.repoRoot.length ? h.repoRoot : h.restartDir.length ? h.restartDir : h.cwd).stringByAbbreviatingWithTildeInPath ?: @"";
        if (h.repoRoot.length && h.subdir.length) folder = [folder stringByAppendingPathComponent:h.subdir];
        if (!folder.length || [folder isEqualToString:@"/"]) folder = h.name ?: @"?";
        NSString *k = h.script.length ? [NSString stringWithFormat:@"%@#%@", folder, h.script] : [NSString stringWithFormat:@"%@:%ld", folder, (long)h.port];
        if ([taken containsObject:k]) k = [NSString stringWithFormat:@"%@:%ld", k, (long)h.port];
        [taken addObject:k];
        h.stableKey = k;
        h.findingID = [@"locohost:server:" stringByAppendingString:k];
    }
    [ignored sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [[x[@"ports"] firstObject] compare:[y[@"ports"] firstObject]]; }];
    if (ignoredOut) *ignoredOut = ignored;
    return hosts;
}

@end

/// Issue #52. Know's Where answers from its cache and works out a new answer in the background on every call,
/// which runs sysctls, LaunchServices and the cmux and tmux CLIs. A rebuild asks it once a minute per server.
/// The first ask only starts the work, so a server with no answer yet is asked once more 10 seconds later.
/// In between, the last answer is reused.
static NSMutableDictionary<NSString *, NSArray *> *gAsked;   // pid:start to [place or null, time asked, times asked]
static os_unfair_lock gAskedLock = OS_UNFAIR_LOCK_INIT;

/// Servers asked once in the last 15 seconds that have no answer yet, so they will be asked again.
uint64_t MMLHPlacesPending(void) {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    uint64_t n = 0;
    os_unfair_lock_lock(&gAskedLock);
    for (NSArray *a in gAsked.objectEnumerator)
        if (a.firstObject == NSNull.null && [a.lastObject integerValue] < 2 && now - [a[1] doubleValue] < 15) n++;
    os_unfair_lock_unlock(&gAskedLock);
    return n;
}

static MMPlace *PlaceFor(MMProcKey k, MMSample *s) {
    NSMutableDictionary<NSString *, NSArray *> *asked;
    os_unfair_lock *lockp = &gAskedLock;
    NSString *key = [NSString stringWithFormat:@"%d:%llu", k.pid, (unsigned long long)k.startSec];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    os_unfair_lock_lock(lockp);
    if (!gAsked) gAsked = [NSMutableDictionary new];
    asked = gAsked;
    NSArray *last = asked[key];
    os_unfair_lock_unlock(lockp);
    id place = last.firstObject;
    double age = now - [last[1] doubleValue];
    NSInteger times = [last.lastObject integerValue];
    if (last && age < (place == NSNull.null && times < 2 ? 10 : 60)) return place == NSNull.null ? nil : place;
    MMPlace *p = MMWhereIs(k, s, NO);
    os_unfair_lock_lock(lockp);
    asked[key] = @[p ?: NSNull.null, @(now), @(times + 1)];
    // Servers that are gone leave the memory.
    if (asked.count > 64) for (NSString *x in asked.allKeys) if (now - [asked[x][1] doubleValue] > 300) [asked removeObjectForKey:x];
    os_unfair_lock_unlock(lockp);
    return p;
}

void MMLHFillWhere(MMLHHost *h, MMSample *s, BOOL wait) {
    MMProcKey k = { h.pid, h.startSec };
    MMPlace *p = wait ? MMWhereIs(k, s, YES) : PlaceFor(k, s);
    h.placeLabel = p.label.length ? p.label : nil;
    h.placeTab = p.tab.length ? p.tab : nil;
    h.placeApp = p.app.length ? p.app : nil;
}
