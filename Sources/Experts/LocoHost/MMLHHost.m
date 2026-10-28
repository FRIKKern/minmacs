// LocoHost's model, words, menu and cards. Pure: no sampling, no files, no model. See MMLHHost.h.
#import "Experts/LocoHost/MMLHHost.h"
#import "UI/MMFormat.h"
#import "UI/MMInvestigateUI.h"

#pragma mark - Host

@implementation MMLHHost

- (NSInteger)port {
    for (NSNumber *p in self.ports) if (p.integerValue < 49152) return p.integerValue;
    return [self.ports.firstObject integerValue];
}

- (BOOL)isDev { return [self.kind isEqualToString:@"dev"]; }

- (NSString *)project {
    NSString *top = self.worktree ?: self.repo;   // a worktree by its folder name, which is what Finder shows
    if (top) return self.subdir.length ? [NSString stringWithFormat:@"%@/%@", top, self.subdir] : top;
    if (!self.cwd.length || [self.cwd isEqualToString:@"/"]) return self.name ?: @"";
    return self.cwd.stringByAbbreviatingWithTildeInPath;
}

- (NSString *)shortName {
    if (!self.isDev) return self.framework ?: self.name ?: @"";
    if (self.worktree || self.repo) return self.project;
    return self.cwd.length > 1 ? self.cwd.lastPathComponent : (self.name ?: @"");
}

- (NSString *)url {
    NSString *h = [self.bind isEqualToString:@"::1"] ? @"[::1]" : @"localhost";
    return [NSString stringWithFormat:@"http://%@:%ld", h, (long)self.port];
}

- (NSString *)command {
    NSArray<NSString *> *a = self.wrapperArgs.count ? self.wrapperArgs : self.args;
    if (!a.count) return self.name ?: @"";
    // npm and others rewrite their process title into argv[0] and blank the rest.
    if ([a[0] containsString:@" "] && [[a subarrayWithRange:NSMakeRange(1, a.count - 1)] indexOfObjectPassingTest:^BOOL(NSString *x, NSUInteger i, BOOL *stop) { return x.length > 0; }] == NSNotFound)
        return a[0];
    NSUInteger extra = [a indexOfObject:@"-extra"];                // BEAM: what follows -extra is what was run
    if (!self.wrapperArgs.count && [self.name isEqualToString:@"beam.smp"] && extra != NSNotFound && extra + 1 < a.count)
        a = [a subarrayWithRange:NSMakeRange(extra + 1, a.count - extra - 1)];
    if (a.count > 1 && [@[@"node", @"bun"] containsObject:a[0].lastPathComponent] &&
        [@[@"npm", @"pnpm", @"yarn", @"npx", @"pnpx", @"bun"] containsObject:[a[1].lastPathComponent stringByDeletingPathExtension]])
        a = [@[[a[1].lastPathComponent stringByDeletingPathExtension]] arrayByAddingObjectsFromArray:[a subarrayWithRange:NSMakeRange(2, a.count - 2)]];
    NSMutableArray *q = [NSMutableArray new];
    for (NSString *s in a) [q addObject:MMLHQuote(s)];
    return [q componentsJoinedByString:@" "];
}

- (NSString *)restartDir { return self.wrapperArgs.count ? self.wrapperCwd : self.cwd; }

- (NSString *)restartCommand {
    NSString *dir = self.restartDir;
    return dir.length ? [NSString stringWithFormat:@"cd %@ && %@", MMLHQuote(dir), self.command] : self.command;
}

static id Or(id v) { return v ?: NSNull.null; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static id Time(NSDate *d) { return d ? @(d.timeIntervalSince1970) : NSNull.null; }
static NSDate *Date(id v) { return [v isKindOfClass:NSNumber.class] && [v doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[v doubleValue]] : nil; }

- (NSDictionary *)json {
    NSDate *now = NSDate.date;
    return @{@"key": self.key ?: @"", @"stableKey": self.stableKey ?: @"", @"findingID": self.findingID ?: @"",
             @"pid": @(self.pid), @"ppid": @(self.ppid), @"startSec": @(self.startSec), @"name": self.name ?: @"",
             @"execPath": self.execPath ?: @"", @"cwd": self.cwd ?: @"", @"args": self.args ?: @[],
             @"started": Time(self.started), @"ports": self.ports ?: @[], @"port": @(self.port), @"bind": self.bind ?: @"",
             @"url": self.url, @"kind": self.kind ?: @"other", @"framework": self.framework ?: @"",
             @"project": self.project, @"repo": Or(self.repo), @"repoRoot": Or(self.repoRoot), @"subdir": Or(self.subdir),
             @"branch": Or(self.branch), @"worktree": Or(self.worktree), @"repoTouched": Time(self.repoTouched), @"merged": Or(self.merged),
             @"cpu": @(round(self.cpuPercent * 10) / 10), @"energyRank": @(round(self.energyRank * 100) / 100),
             @"memoryBytes": @(self.memory), @"processes": @(self.processCount),
             @"treePids": self.treePids ?: @[], @"treeStarts": self.treeStarts ?: @[],
             @"command": self.command, @"launcher": self.launcher ?: @"", @"agent": Or(self.agent), @"agentPid": @(self.agentPid),
             @"orphaned": @(self.orphaned), @"wrapperPid": @(self.wrapperPid), @"wrapperStart": @(self.wrapperStart),
             @"wrapperArgs": self.wrapperArgs ?: @[], @"wrapperCwd": Or(self.wrapperCwd),
             @"connections": @(self.connections), @"newConnections": @(self.newConnections), @"busy": @(self.busy),
             @"clients": self.clients ?: @[], @"firstSeen": Time(self.firstSeen), @"lastActive": Time(self.lastActive),
             @"uptimeSeconds": @(self.started ? round([now timeIntervalSinceDate:self.started]) : 0),
             @"lastActiveSecondsAgo": self.lastActive ? @(round([now timeIntervalSinceDate:self.lastActive])) : NSNull.null,
             @"watchedSeconds": @(self.firstSeen ? round([now timeIntervalSinceDate:self.firstSeen]) : 0),
             @"idleCPUSeconds": @(round(self.idleCPUSeconds)), @"duplicates": self.duplicates ?: @[],
             @"state": MMLHStateName(self.state), @"protected": @(self.isProtected), @"script": Or(self.script),
             @"projectFacts": self.projectFacts ?: @{}, @"session": Or(self.session),
             @"where": Or(self.placeLabel), @"whereTab": Or(self.placeTab), @"whereApp": Or(self.placeApp),
             @"restart": self.restartCommand};
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (!Dict(j)) return nil;
    MMLHHost *h = [MMLHHost new];
    h.key = Str(j[@"key"]); h.stableKey = Str(j[@"stableKey"]); h.findingID = Str(j[@"findingID"]);
    h.pid = [j[@"pid"] intValue]; h.ppid = [j[@"ppid"] intValue]; h.startSec = [j[@"startSec"] unsignedLongLongValue];
    h.name = Str(j[@"name"]); h.execPath = Str(j[@"execPath"]); h.cwd = Str(j[@"cwd"]); h.args = List(j[@"args"]);
    h.started = Date(j[@"started"]); h.ports = List(j[@"ports"]); h.bind = Str(j[@"bind"]);
    h.kind = Str(j[@"kind"]); h.framework = Str(j[@"framework"]);
    h.repo = Str(j[@"repo"]); h.repoRoot = Str(j[@"repoRoot"]); h.subdir = Str(j[@"subdir"]);
    h.branch = Str(j[@"branch"]); h.worktree = Str(j[@"worktree"]); h.repoTouched = Date(j[@"repoTouched"]); h.merged = Str(j[@"merged"]);
    h.cpuPercent = [j[@"cpu"] doubleValue]; h.energyRank = [j[@"energyRank"] doubleValue];
    h.memory = [j[@"memoryBytes"] unsignedLongLongValue]; h.processCount = [j[@"processes"] integerValue];
    h.treePids = List(j[@"treePids"]); h.treeStarts = List(j[@"treeStarts"]);
    h.launcher = Str(j[@"launcher"]); h.agent = Str(j[@"agent"]); h.agentPid = [j[@"agentPid"] intValue];
    h.orphaned = [j[@"orphaned"] boolValue]; h.wrapperPid = [j[@"wrapperPid"] intValue];
    h.wrapperStart = [j[@"wrapperStart"] unsignedLongLongValue];
    h.wrapperArgs = List(j[@"wrapperArgs"]); h.wrapperCwd = Str(j[@"wrapperCwd"]);
    h.connections = [j[@"connections"] integerValue]; h.newConnections = [j[@"newConnections"] integerValue];
    h.busy = [j[@"busy"] boolValue]; h.clients = List(j[@"clients"]);
    h.firstSeen = Date(j[@"firstSeen"]); h.lastActive = Date(j[@"lastActive"]);
    h.idleCPUSeconds = [j[@"idleCPUSeconds"] doubleValue]; h.duplicates = List(j[@"duplicates"]);
    NSString *st = Str(j[@"state"]);
    h.state = [st isEqualToString:@"active"] ? MMLHActive : [st isEqualToString:@"recent"] ? MMLHRecent : MMLHIdle;
    h.isProtected = [j[@"protected"] boolValue]; h.script = Str(j[@"script"]);
    h.projectFacts = Dict(j[@"projectFacts"]); h.session = Dict(j[@"session"]);
    h.placeLabel = Str(j[@"where"]); h.placeTab = Str(j[@"whereTab"]); h.placeApp = Str(j[@"whereApp"]);
    return h;
}

@end

NSString *MMLHQuote(NSString *s) {
    static NSCharacterSet *unsafe; static dispatch_once_t once;   // made once: a rebuild quotes every server's args
    dispatch_once(&once, ^{
        unsafe = [[NSCharacterSet characterSetWithCharactersInString:
                   @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,"] invertedSet];
    });
    if (s.length && [s rangeOfCharacterFromSet:unsafe].location == NSNotFound) return s;
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

void MMLHDetect(NSString *name, NSArray<NSString *> *args, NSArray<NSNumber *> *ports, NSString **framework, NSString **kind) {
    NSString *cmd = [[args componentsJoinedByString:@" "] lowercaseString];
    BOOL (^has)(NSString *) = ^BOOL(NSString *s) { return [cmd containsString:s]; };
    NSString *n = name.lowercaseString ?: @"";
    *kind = @"dev";
    NSDictionary<NSString *, NSString *> *services = @{
        @"postgres": @"Postgres", @"mysqld": @"MySQL", @"mariadbd": @"MariaDB", @"redis-server": @"Redis",
        @"valkey-server": @"Valkey", @"mongod": @"MongoDB", @"memcached": @"Memcached", @"epmd": @"Erlang port mapper",
        @"ollama": @"Ollama", @"com.docker.backend": @"Docker", @"com.docker.backe": @"Docker", @"vpnkit-bridge": @"Docker",
        @"orbstack helper": @"OrbStack", @"clickhouse": @"ClickHouse", @"meilisearch": @"Meilisearch",
        @"typesense-server": @"Typesense", @"typesense-serve": @"Typesense", @"minio": @"MinIO", @"mailpit": @"Mailpit",
        @"mailhog": @"MailHog", @"caddy": @"Caddy", @"nginx": @"nginx", @"httpd": @"Apache", @"lm studio": @"LM Studio",
        @"tailscaled": @"Tailscale", @"cloudflared": @"cloudflared"};
    if (services[n]) { *framework = services[n]; *kind = @"service"; return; }
    if ([n isEqualToString:@"beam.smp"]) {
        *framework = has(@"phx.server") ? @"Phoenix" : has(@" mix test") ? @"mix test" : has(@"iex") ? @"IEx" : @"BEAM";
        if (has(@"phx.server") && has(@" iex")) *framework = @"Phoenix with IEx";
    } else if ([n hasPrefix:@"node"] || [n isEqualToString:@"bun"] || [n isEqualToString:@"deno"]) {
        NSArray *rules = @[@[@"next-server", @"Next.js"], @[@"/next/dist", @"Next.js"], @[@".bin/next", @"Next.js"], @[@"next dev", @"Next.js"],
                           @[@"storybook", @"Storybook"], @[@"astro", @"Astro"], @[@"nuxi", @"Nuxt"], @[@"nuxt", @"Nuxt"],
                           @[@"remix", @"Remix"], @[@"sanity", @"Sanity Studio"], @[@"wrangler", @"Wrangler"], @[@"netlify", @"Netlify Dev"],
                           @[@"vercel", @"Vercel Dev"], @[@"vite", @"Vite"], @[@"webpack", @"webpack"], @[@"react-scripts", @"Create React App"],
                           @[@"expo", @"Expo"], @[@"metro", @"Metro"], @[@"docusaurus", @"Docusaurus"], @[@"eleventy", @"Eleventy"],
                           @[@"mcp", @"MCP server"], @[@"nodemon", @"Node, nodemon"], @[@"tsx", @"Node, tsx"], @[@"ts-node", @"Node, ts-node"]];
        NSString *hit = nil;
        for (NSArray *r in rules) if (!hit && has(r[0])) hit = r[1];
        *framework = hit ?: [n isEqualToString:@"bun"] ? @"Bun" : [n isEqualToString:@"deno"] ? @"Deno" : @"Node";
    } else if ([n hasPrefix:@"python"] || [n hasPrefix:@"uvicorn"] || [n hasPrefix:@"gunicorn"]) {
        NSArray *rules = @[@[@"uvicorn", @"Uvicorn"], @[@"gunicorn", @"Gunicorn"], @[@"runserver", @"Django"], @[@"flask", @"Flask"],
                           @[@"http.server", @"Python http.server"], @[@"jupyter", @"Jupyter"], @[@"streamlit", @"Streamlit"],
                           @[@"gradio", @"Gradio"], @[@"mkdocs", @"MkDocs"], @[@"fastapi", @"FastAPI"], @[@"mcp", @"MCP server"]];
        NSString *hit = nil;
        for (NSArray *r in rules) if (!hit && has(r[0])) hit = r[1];
        *framework = hit ?: @"Python";
    } else if ([n hasPrefix:@"ruby"] || [n isEqualToString:@"puma"] || has(@"rails")) {
        *framework = has(@"rails") || has(@"puma") ? @"Rails" : has(@"jekyll") ? @"Jekyll" : @"Ruby";
    } else if ([n hasPrefix:@"php"]) {
        *framework = has(@"artisan") ? @"Laravel" : @"PHP";
    } else if ([n isEqualToString:@"java"]) {
        *framework = has(@"elasticsearch") ? @"Elasticsearch" : has(@"spring") ? @"Spring" : has(@"gradle") ? @"Gradle" : @"Java";
        if (has(@"elasticsearch")) *kind = @"service";
    } else {
        *framework = name ?: @"";
    }
    BOOL onlyEphemeral = YES;   // a server you browse to has a port you picked; random high ports are internal
    for (NSNumber *p in ports) if (p.integerValue < 49152) onlyEphemeral = NO;
    if (onlyEphemeral) *kind = @"other";
}

#pragma mark - Words

NSString *MMLHStateName(MMLHState s) { return s == MMLHActive ? @"active" : s == MMLHRecent ? @"recent" : @"idle"; }

NSString *MMLHModeLabel(NSString *mode) { return mode.length ? MMCapitalized(mode) : @"Proactive"; }

static NSString *Who(MMLHHost *h) {
    return h.clients.count ? [h.clients componentsJoinedByString:@", "] : h.connections ? MMPlural(h.connections, @"connection") : nil;
}

NSString *MMLHStateWords(MMLHHost *h) {
    NSString *who = Who(h);
    if (h.state == MMLHActive) return h.newConnections ? [NSString stringWithFormat:@"requests from %@", who ?: @"a client"] : @"working, CPU";
    NSDate *q = h.lastActive ?: h.firstSeen ?: h.started;
    NSString *quiet = [NSString stringWithFormat:@"quiet %@%@", MMDuration(-q.timeIntervalSinceNow), h.lastActive ? @"" : @"+"];
    return who ? [NSString stringWithFormat:@"%@, open in %@", quiet, who] : quiet;
}

NSString *MMLHWasteWords(MMLHHost *h) {
    NSDate *since = h.lastActive ?: h.firstSeen ?: h.started;
    return [NSString stringWithFormat:@"%@ %@: %@ CPU, holds %@", h.lastActive ? @"since last use" : @"since LocoHost first saw it",
            MMDuration(-since.timeIntervalSinceNow), MMDuration(h.idleCPUSeconds), MMBytes(h.memory)];
}

NSString *MMLHSessionWords(NSDictionary *s) {
    if (!Dict(s)) return @"no agent session found";
    NSString *t = Str(s[@"title"]);
    NSDate *last = Date(s[@"lastActiveAt"]);
    return [NSString stringWithFormat:@"%@ session%@, last active %@", Str(s[@"agent"]) ?: @"an agent",
            t.length ? [NSString stringWithFormat:@" “%@”", t] : @"", last ? MMAgo(last) : @"at an unknown time"];
}

#pragma mark - Menu

@implementation MMLHView
@end

static void Act(MMLHView *v, NSString *what, NSString *key, BOOL option) { if (v.act) v.act(what, key, option); }

static MMActionSpec *Action(MMLHView *v, NSString *title, NSString *tail, NSString *what, NSString *key) {
    __weak MMLHView *weak = v;
    return [MMActionSpec title:title tail:tail run:^(BOOL option) { Act(weak, what, key, option); }];
}

/// The start every dev server's name shares up to a dash, such as "acme-", left out of the rows.
static NSString *CommonPrefix(NSArray<MMLHHost *> *dev) {
    if (dev.count < 2) return nil;
    NSString *common = nil;
    for (MMLHHost *h in dev) common = common ? [common commonPrefixWithString:h.shortName options:0] : h.shortName;
    NSRange dash = [common rangeOfString:@"-" options:NSBackwardsSearch];
    return dash.location != NSNotFound && dash.location >= 3 ? [common substringToIndex:dash.location + 1] : nil;
}

static BOOL Goes(MMLHHost *h, MMLHView *v) {
    return [v.plan[h.findingID][@"stop"] boolValue] || (h.state == MMLHIdle && [v.candidates containsObject:h.findingID]);
}

static MMRowMark MarkFor(MMLHHost *h, MMLHView *v) {
    if (!h.isDev) return MMRowMarkQuiet;
    if (h.state == MMLHActive) return MMRowMarkWorking;
    if (Goes(h, v)) return MMRowMarkGoes;
    return h.state == MMLHRecent ? MMRowMarkRecent : MMRowMarkQuiet;
}

/// The third fact of a row: who has it open, when it goes, when it was used, else how long it has run.
static NSString *ThirdFact(MMLHHost *h, MMLHView *v) {
    if (h.clients.count) return [@"in " stringByAppendingString:MMCut(h.clients.firstObject, 28)];
    if (h.isDev && [v.plan[h.findingID][@"stop"] boolValue]) return @"goes at the next review";
    if (h.isDev && h.state == MMLHActive) return @"in use now";
    if (h.isDev && h.lastActive) return [@"used " stringByAppendingString:MMAgo(h.lastActive)];
    return [@"up " stringByAppendingString:MMShortDuration(-h.started.timeIntervalSinceNow)];
}

/// Who runs a service, for its row: the app or manager that started it. Empty when only launchd is known.
static NSString *Owner(MMLHHost *h) {
    NSString *first = [h.launcher componentsSeparatedByString:@" · "].lastObject ?: @"";
    return [first isEqualToString:@"launchd"] || [first isEqualToString:@"parent exited"] ? @"" : first;
}

/// YES when launchd or Homebrew keeps the service running, so a stop from here would only make it start again.
static BOOL Managed(MMLHHost *h) {
    return [h.kind isEqualToString:@"service"] && ([h.launcher hasSuffix:@"launchd"] || [h.launcher containsString:@"Homebrew"]);
}

static MMRowSpec *Row(MMLHHost *h, MMLHView *v, NSString *prefix) {
    NSString *name = h.shortName;
    if (prefix.length && h.isDev && [name hasPrefix:prefix] && name.length > prefix.length) name = [name substringFromIndex:prefix.length];
    MMRowSpec *r = [MMRowSpec new];
    r.name = [NSString stringWithFormat:@"%@\t:%ld", name, (long)h.port];
    r.facts = @[h.isDev ? h.framework ?: @"" : Owner(h), MMBytes(h.memory), ThirdFact(h, v)];
    r.mark = MarkFor(h, v);
    r.findingID = h.findingID;
    return r;
}

static MMSectionSpec *Section(NSString *title, NSArray<MMLHHost *> *hosts, MMLHView *v, NSString *prefix) {
    MMSectionSpec *s = [MMSectionSpec new];
    s.title = title;
    NSMutableArray *rows = [NSMutableArray new];
    for (MMLHHost *h in hosts) [rows addObject:Row(h, v, prefix)];
    s.rows = rows;
    return s;
}

static NSString *Summary(MMLHView *v, NSInteger servers) {
    if (v.reviewError.length && !v.summaryWords.length) return MMSentence([@"The last review failed: " stringByAppendingString:v.reviewError]);
    if (v.summaryWords.length) return v.summaryWords;
    if (!servers) return @"No localhost runs right now. LocoHost shows each one as it starts.";
    if (v.watchingLeft > 0)
        return [NSString stringWithFormat:@"Watching %@. Acts on nothing for %@.", MMPlural(servers, @"server"), MMDuration(v.watchingLeft)];
    return [NSString stringWithFormat:@"Watching %@. The first review runs within the hour.", MMPlural(servers, @"server")];
}

MMMenuSpec *MMLHMenu(MMLHView *v) {
    NSMutableArray *inUse = [NSMutableArray new], *quiet = [NSMutableArray new], *services = [NSMutableArray new], *other = [NSMutableArray new];
    uint64_t mem = 0;
    for (MMLHHost *h in v.hosts) {
        if ([h.kind isEqualToString:@"other"]) { [other addObject:h]; continue; }
        mem += h.memory;
        if (!h.isDev) { [services addObject:h]; continue; }
        if (h.state == MMLHIdle) [quiet addObject:h]; else [inUse addObject:h];
    }
    NSInteger servers = inUse.count + quiet.count + services.count;
    MMMenuSpec *m = [MMMenuSpec new];
    m.headerBig = MMBytes(mem);
    m.headerUnit = @"in servers";
    NSMutableArray *line = [NSMutableArray arrayWithObject:MMPlural(servers, @"localhost")];
    // The counts match the sections below: a service is listed under Services, not In use.
    [line addObject:[NSString stringWithFormat:@"%lu in use", (unsigned long)inUse.count]];
    if (quiet.count) [line addObject:[NSString stringWithFormat:@"%lu quiet", (unsigned long)quiet.count]];
    [line addObject:MMLHModeLabel(v.mode)];
    m.headerLine = [line componentsJoinedByString:@" · "];
    m.summary = Summary(v, servers);

    NSMutableArray *actions = [NSMutableArray new];
    uint64_t idleMem = 0;
    for (MMLHHost *h in v.hosts) if ([v.candidates containsObject:h.findingID]) idleMem += h.memory;
    if (v.candidates.count)
        [actions addObject:Action(v, @"Close Idle", [NSString stringWithFormat:@"%@, %@", MMPlural(v.candidates.count, @"server"), MMBytes(idleMem)], @"close-idle", nil)];
    if (servers) {
        MMActionSpec *review = Action(v, @"Review Now", v.reviewAt ? MMAgo(v.reviewAt) : nil, @"review", nil);
        if (v.reviewing) review.disabledReason = @"reviewing now";
        [actions addObject:review];
    }
    m.actions = actions;

    NSString *prefix = CommonPrefix([inUse arrayByAddingObjectsFromArray:quiet]);
    NSMutableArray *sections = [NSMutableArray new];
    if (inUse.count) [sections addObject:Section(@"In use", inUse, v, prefix)];
    if (quiet.count) [sections addObject:Section(@"Quiet", quiet, v, prefix)];
    if (services.count) [sections addObject:Section(@"Services", services, v, prefix)];
    if (other.count) [sections addObject:Section(@"Other listeners", other, v, nil)];
    m.sections = sections;

    // Recently Stopped lives under More: one Restart per stop, newest first, with when and by whom as the tail.
    NSMutableArray *more = [NSMutableArray new];
    for (NSDictionary *c in [v.stopped subarrayWithRange:NSMakeRange(0, MIN(v.stopped.count, (NSUInteger)6))]) {
        NSString *by = [Str(c[@"by"]) isEqualToString:@"manual"] || [Str(c[@"by"]) isEqualToString:@"cli"] ? @"you" : MMLHModeLabel(Str(c[@"by"]));
        NSString *title = [NSString stringWithFormat:@"Restart :%@ %@", c[@"port"] ?: @"", Str(c[@"framework"]) ?: @""];
        MMActionSpec *a = Action(v, title, [NSString stringWithFormat:@"%@ by %@", MMAgo(Date(c[@"at"])), by], @"restart", Str(c[@"rid"]));
        if ([c[@"taken"] boolValue]) a.disabledReason = @"the port is in use again";
        [more addObject:a];
    }
    m.more = more;
    return m;
}

#pragma mark - Card

/// "pnpm dev --port 3300 · cmux" reads "pnpm dev · cmux": the full command is in the CLI.
static NSString *ShortLauncher(NSString *launcher) {
    NSMutableArray *by = [[launcher componentsSeparatedByString:@" · "] mutableCopy];
    if (!by.count || ![by[0] length]) return @"unknown";
    NSArray *w = [by[0] componentsSeparatedByString:@" "];
    NSUInteger keep = w.count > 2 && [w[1] isEqualToString:@"run"] ? 3 : 2;   // "npm run dev", "pnpm dev"
    by[0] = [[w subarrayWithRange:NSMakeRange(0, MIN(keep, w.count))] componentsJoinedByString:@" "];
    return [by componentsJoinedByString:@" · "];
}

/// Why it stays or when it goes, as the card's status: a word, then whole sentences.
static void Status(MMLHHost *h, MMLHView *v, MMCardSpec *c) {
    c.mark = MarkFor(h, v);
    NSDictionary *p = v.plan[h.findingID];
    NSString *mode = MMLHModeLabel(v.mode);
    if ([h.kind isEqualToString:@"service"]) {
        c.statusWord = @"Stays.";
        // An owned service says who owns it and where it is stopped, as DESIGN.md asks.
        if ([h.launcher containsString:@"Homebrew"]) c.statusText = @"No mode stops a shared service. Homebrew runs it, and brew services stop ends it.";
        else if (Managed(h)) c.statusText = @"No mode stops a shared service. launchd runs it, and launchctl ends it.";
        else c.statusText = @"No mode stops a shared service such as a database. Stop it yourself if you want it gone.";
        return;
    }
    if (!h.isDev) {
        c.statusWord = @"Stays."; c.statusText = @"LocoHost lists high-port listeners and no mode stops them.";
        return;
    }
    NSString *why = Str(p[@"why"]) ?: @"";
    if ([p[@"stop"] boolValue]) {
        c.statusWord = @"Goes at the next review.";
        c.statusText = [MMSentence(MMCut(why, 200)) stringByAppendingString:@" Recently Stopped keeps its restart command."];
        return;
    }
    if ([v.mode isEqualToString:@"idle"]) {
        c.statusWord = @"Stays."; c.statusText = @"Idle mode only reports. Close Idle and Stop are up to you.";
        return;
    }
    NSString *next = @"";
    if ([why hasPrefix:@"used "] || [why hasPrefix:@"in use"])
        next = [NSString stringWithFormat:@" %@ looks again after %@ of quiet.", mode, MMDuration(v.idleSeconds)];
    else if ([why hasPrefix:@"started only"]) next = @" New servers get 30 minutes.";
    else if ([why hasPrefix:@"its agent session"]) next = @" The agent may still need it.";
    else if ([why hasPrefix:@"used after the last review"] || [why hasPrefix:@"changed since"]) next = @" The next review looks again.";
    else if ([why hasPrefix:@"no review yet"] || [why hasPrefix:@"not in the last review"]) next = @" The next review decides.";
    else if ([why hasPrefix:@"evidence: "]) why = [@"the judge found evidence: " stringByAppendingString:[why substringFromIndex:10]];
    if (!why.length) why = @"nothing decided yet";
    c.statusWord = @"Stays.";
    c.statusText = [MMSentence(MMCut(why, 160)) stringByAppendingString:next];
}

NSString *MMLHWorktreeWords(MMLHHost *h) {
    NSString *name = h.worktree.length ? h.worktree : h.repoRoot.lastPathComponent ?: h.repo ?: @"";
    NSString *state = h.worktree.length ? h.merged : @"main checkout";
    return state.length ? [NSString stringWithFormat:@"%@, %@", name, state] : name;
}

MMCardSpec *MMLHCard(MMLHHost *h, MMLHView *v) {
    MMCardSpec *c = [MMCardSpec new];
    NSDictionary *verdict = v.verdicts[h.findingID];
    NSString *about = Str(verdict[@"about"]);
    NSString *title = about.length > 12 ? about : nil;
    if (!title) {
        NSString *desc = Str(h.projectFacts[@"description"]);
        title = h.isDev ? [NSString stringWithFormat:@"%@ server for %@%@", h.framework ?: @"Dev", h.shortName, desc.length ? [@", " stringByAppendingString:desc] : @""]
                        : [NSString stringWithFormat:@"%@ on port %ld", h.framework ?: h.name ?: @"A listener", (long)h.port];
    }
    c.title = MMCut(MMCapitalized(title), 120);
    Status(h, v, c);

    NSMutableArray *facts = [NSMutableArray new];
    [facts addObject:[MMCardFact label:@"Where" value:h.placeLabel ?: @""]];
    [facts addObject:[MMCardFact label:@"Up" value:[NSString stringWithFormat:@"%@, started by %@", MMDuration(-h.started.timeIntervalSinceNow), ShortLauncher(h.launcher)]]];
    [facts addObject:[MMCardFact label:@"Uses" value:[NSString stringWithFormat:@"%@ · %.0f%% CPU%@", MMBytes(h.memory), h.cpuPercent,
                                                       h.clients.count ? [@" · open in " stringByAppendingString:[h.clients componentsJoinedByString:@", "]] : @""]]];
    NSDictionary *link = v.links[h.findingID];
    if (link) {
        MMCardFact *f = [MMCardFact label:Str(link[@"label"]) ?: @"Worktree" value:Str(link[@"value"]) ?: @""];
        f.linkExpert = Str(link[@"expert"]); f.linkFindingID = Str(link[@"findingID"]);
        [facts addObject:f];
    } else {
        NSString *branch = [h.branch hasPrefix:@"detached"] ? nil : h.branch;   // a detached commit's hash says nothing here
        NSMutableArray *g = [NSMutableArray new];
        if (branch.length) [g addObject:branch];
        if (h.worktree.length) [g addObject:[@"worktree " stringByAppendingString:h.merged.length ? [NSString stringWithFormat:@"%@, %@", h.worktree, h.merged] : h.worktree]];
        [facts addObject:[MMCardFact label:@"Git" value:[g componentsJoinedByString:@" · "]]];
    }
    if (h.isDev) {
        NSDictionary *s = h.session;
        NSString *t = Str(s[@"title"]);
        [facts addObject:[MMCardFact label:@"Agent" value:s ? [NSString stringWithFormat:@"%@%@, %@", Str(s[@"agent"]) ?: @"an agent",
                                                              t.length ? [NSString stringWithFormat:@", “%@”", MMCut(t, 40)] : @"",
                                                              MMAgo(Date(s[@"lastActiveAt"]))] : @"none found"]];
    }
    NSMutableArray *shown = [NSMutableArray new];
    for (MMCardFact *f in facts) if (f.value.length) [shown addObject:f];
    c.facts = shown;

    NSString *reason = Str(verdict[@"reason"]);
    // Only the model's words make a note. A rule's reason repeats what the status already says.
    if (reason.length && [@[@"model", @"judge"] containsObject:Str(verdict[@"decidedBy"]) ?: @""]) {
        NSString *word = [Str(verdict[@"word"]) ?: @"unsure" stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        c.noteBy = [NSString stringWithFormat:@"%@ says %@%@", v.model.length ? v.model : @"The review", word, [verdict[@"judged"] boolValue] ? @" after the judge" : @""];
        c.note = MMSentence(reason);
    }
    NSString *by = nil, *note = nil;   // what the person asked for wins over the review's note
    if (MMInvestigateNote(v.investigations[h.findingID], &by, &note)) { c.noteBy = by; c.note = note; }

    NSMutableArray *actions = [NSMutableArray new];
    if (h.placeTab.length || h.placeApp.length) {
        NSString *to = h.placeTab.length ? [NSString stringWithFormat:@"Go to “%@”", MMCut(h.placeTab, 32)] : [@"Go to " stringByAppendingString:h.placeApp];
        [actions addObject:Action(v, to, nil, @"go", h.findingID)];
    }
    if (![h.kind isEqualToString:@"service"]) [actions addObject:Action(v, [@"Open " stringByAppendingString:[h.url substringFromIndex:7]], nil, @"open", h.findingID)];
    NSDate *kept = v.keptUntil[h.findingID];
    if (h.isDev) [actions addObject:Action(v, kept ? [NSString stringWithFormat:@"Kept for %@ More", MMShortDuration(kept.timeIntervalSinceNow)] : @"Keep for 4 Hours",
                                           nil, @"keep", h.findingID)];
    MMActionSpec *stop = Action(v, @"Stop", nil, @"stop", h.findingID);
    if (Managed(h)) stop.disabledReason = [h.launcher containsString:@"Homebrew"] ? @"Homebrew owns it" : @"launchd owns it";
    else stop.optionTitle = @"Force Stop";
    [actions addObject:stop];
    if (h.cwd.length > 1) {
        NSDictionary *run = v.investigations[h.findingID];
        MMActionSpec *inv = Action(v, @"Investigate…", MMInvestigateTail(run), @"investigate", h.findingID);
        inv.disabledReason = MMInvestigateDisabledReason(run);
        [actions addObject:inv];
    }
    if (h.cwd.length > 1) [actions addObject:Action(v, @"Reveal in Finder", nil, @"reveal", h.findingID)];
    if (![h.kind isEqualToString:@"service"]) [actions addObject:Action(v, @"Copy URL", nil, @"copy-url", h.findingID)];
    [actions addObject:Action(v, @"Copy Restart Command", nil, @"copy-restart", h.findingID)];
    [actions addObject:Action(v, h.isProtected ? @"Unprotect" : @"Protect", nil, @"protect", h.findingID)];
    c.actions = actions;
    return c;
}

NSString *MMLHBadge(MMLHView *v) { return v.candidates.count ? [NSString stringWithFormat:@"%lu", (unsigned long)MIN(v.candidates.count, (NSUInteger)999)] : nil; }

NSString *MMLHAccessibilityState(MMLHView *v) {
    if (v.candidates.count) return MMPlural(v.candidates.count, @"idle server");
    NSInteger n = 0;
    for (MMLHHost *h in v.hosts) if (![h.kind isEqualToString:@"other"]) n++;
    return n ? MMPlural(n, @"server") : @"no servers";
}
