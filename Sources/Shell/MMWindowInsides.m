// An app row's insides, MMWindowInsides.h. The owner asked: "When we press e.g. cmux, an application we should know a
// lot about, we should have all the top-level details in place: its sessions, and what is happening inside each."
// And: "big ambitions for understanding significant apps, but strong measures so it doesn't hurt performance", D11.
#import "Shell/MMWindowInsides.h"
#import "Shell/MMWindowFeed.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }

static BOOL Inside(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    NSString *f = folder.length > 1 && [folder hasSuffix:@"/"] ? [folder substringToIndex:folder.length - 1] : folder;
    return [path isEqualToString:f] || [path hasPrefix:[f stringByAppendingString:@"/"]];
}

static pid_t PidOf(MMFinding *f) {
    pid_t pid = (pid_t)[Num(f.facts[@"pid"]) intValue];
    if (pid > 0 || !f.procs.count) return pid;
    MMProcKey k = {0, 0};
    [f.procs.firstObject getValue:&k size:sizeof k];
    return k.pid;
}

NSString *MMWindowInsidesApp(MMWindowRow *row) {
    return row.kind == MMWindowApp && [row.iconHint isEqualToString:MMAppInsidesCmux] ? MMAppInsidesCmux : nil;
}

/// A shell alone, waiting for the person: nothing of theirs runs in the tab.
static BOOL IsShell(NSString *name) {
    NSString *n = [name hasPrefix:@"-"] ? [name substringFromIndex:1] : name;
    return [@[@"zsh", @"bash", @"fish", @"sh", @"login", @"tcsh", @"ksh", @"nu", @"dash", @"elvish", @"xonsh"] containsObject:n ?: @""];
}

#pragma mark What the snapshot knows

/// What the snapshot knows that a tab can name: agents and servers by pid, worktrees by folder, rows by key.
@interface MMInsidesWorld : NSObject
@property (strong) MMWindowModel *m;
@property (strong) MMSample *sample;
@property (strong) NSMutableDictionary<NSNumber *, MMWindowRow *> *agents, *servers;
@property (strong) NSArray<MMFinding *> *worktrees;
@end
@implementation MMInsidesWorld
@end

static MMInsidesWorld *World(MMWindowModel *m, MMSnapshot *s) {
    MMInsidesWorld *w = [MMInsidesWorld new];
    w.m = m; w.sample = s.facts.sample;
    w.agents = [NSMutableDictionary new]; w.servers = [NSMutableDictionary new];
    for (MMFinding *f in [s findingsFor:@"minmacs"]) {
        if (![f.kind isEqualToString:@"agent"]) continue;
        MMWindowRow *row = [m row:f.findingID];
        pid_t pid = PidOf(f);
        if (row && pid > 0) w.agents[@(pid)] = row;
    }
    for (MMFinding *f in [s findingsFor:@"locohost"]) {
        if (![f.kind isEqualToString:@"server"]) continue;
        MMWindowRow *row = [m row:f.findingID];
        pid_t pid = PidOf(f);
        if (row && pid > 0) w.servers[@(pid)] = row;
    }
    w.worktrees = [[s findingsFor:@"workforest"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMFinding *f, id b) {
        return [f.kind isEqualToString:@"worktree"] && (f.path.length || Str(f.facts[@"path"])) && [m row:f.findingID];
    }]];
    return w;
}

/// The deepest worktree that holds folder, or nil.
static MMFinding *WorktreeOf(MMInsidesWorld *w, NSString *folder) {
    MMFinding *best = nil;
    for (MMFinding *f in w.worktrees) {
        NSString *p = f.path ?: Str(f.facts[@"path"]);
        if (Inside(folder, p) && (!best || p.length > (best.path ?: Str(best.facts[@"path"])).length)) best = f;
    }
    return best;
}

/// An agent's word as the window says it: "asks you", its quiet word, or what cmux says of it.
static NSString *AgentWord(MMWindowRow *agent, NSString *cmux) {
    if (agent.needsYou) return @"asks you";
    return agent.state.length ? agent.state : cmux.length ? cmux.lowercaseString : nil;
}
static NSString *Recently(MMWindowRow *agent) {
    for (MMWindowFact *f in agent.facts) if ([f.label isEqualToString:@"Recently"]) return f.value;
    return nil;
}
static MMWindowFact *Linked(NSString *label, NSString *value, NSString *link) {
    if (!value.length) return nil;
    MMWindowFact *f = [MMWindowFact label:label value:value];
    f.link = link;
    return f;
}
static void Add(NSMutableArray *out, id x) { if (x) [out addObject:x]; }

#pragma mark A tab

/// One tab as a row, with its agent and servers as their own rows under it. Its CPU and memory are of its processes
/// as MinMacs's sample has them, else as cmux measured them.
static MMWindowRow *TabRow(MMInsidesWorld *w, MMInsidesNode *tab, MMInsidesNode *space, MMInsidesNode *pane, NSString *window, NSInteger depth, NSString *parent, BOOL *idle) {
    MMSample *sample = w.sample;
    double cpu = 0; uint64_t bytes = 0;
    BOOL sampled = NO;
    for (NSNumber *pid in tab.pids) { MMProc *p = [sample proc:pid.intValue]; if (p) { cpu += p.cpuPercent; bytes += p.footprint; sampled = YES; } }
    if (!sampled) { cpu = tab.cpuPercent; bytes = tab.bytes; }
    MMWindowRow *agent = nil;
    NSMutableArray<MMWindowRow *> *servers = [NSMutableArray new];
    for (NSNumber *pid in tab.pids) {
        if (!agent && w.agents[pid]) agent = w.agents[pid];
        if (w.servers[pid] && ![servers containsObject:w.servers[pid]]) [servers addObject:w.servers[pid]];
    }
    pid_t fg = tab.pid > 0 ? tab.pid : tab.pids.firstObject.intValue;
    NSString *fgName = [sample proc:fg].name;
    if (!fgName.length) for (MMInsidesNode *n in tab.children) if (n.pid == fg) fgName = n.title;
    NSString *cwd = fg > 0 ? [sample cwdOf:fg] : nil;
    MMFinding *tree = WorktreeOf(w, cwd);
    BOOL browser = [tab.type isEqualToString:@"browser"];
    *idle = !agent && !servers.count && !browser && (IsShell(fgName) || !fgName.length) && cpu < 0.5;

    NSString *key = [@"insides:cmux:tab:" stringByAppendingString:tab.ref];
    NSString *name = tab.title.length ? tab.title : fgName.length ? fgName : @"tab";
    NSString *state = agent ? AgentWord(agent, tab.status) : browser ? @"browser" : fgName;
    MMWindowRow *row = MMWindowInsidesRow(key, MMWindowHelper, name, state, cpu, bytes, depth, parent);
    row.needsYou = agent.needsYou;
    row.goTo = @"cmux";
    row.menu = @[[MMWindowMenuItem action:@"go-to" title:@"Go to cmux"]];
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    Add(facts, MMWindowFactRunsIn([NSString stringWithFormat:@"cmux, %@", space.title.length ? space.title : @"a workspace"]));
    if (agent) {
        NSString *word = AgentWord(agent, tab.status);
        Add(facts, Linked(@"Agent", word ? [NSString stringWithFormat:@"%@ · %@", agent.shownName, word] : agent.shownName, agent.key));
        Add(facts, Linked(@"Recently", Recently(agent), nil));
    } else if (fgName.length) Add(facts, Linked(@"Runs", fgName, nil));
    if (tree) Add(facts, MMWindowFactWorktree(MMWindowNameOf(tree), tree.findingID));
    else if (cwd.length && ![cwd isEqualToString:@"/"]) Add(facts, MMWindowFactFolder(cwd.stringByAbbreviatingWithTildeInPath));
    for (MMWindowRow *srv in servers) Add(facts, MMWindowFactServer(srv.shownName, srv.key));
    if (tab.url.length) Add(facts, Linked(@"Shows", tab.url, nil));
    if (tab.pids.count > 1) Add(facts, Linked(@"Processes", MMWindowCount((NSInteger)tab.pids.count, @"process", @"processes"), nil));
    row.facts = facts;
    NSMutableArray<MMWindowRow *> *under = [NSMutableArray new];
    if (agent) [under addObject:MMWindowInsidesSame(agent, depth + 1, key)];
    for (MMWindowRow *srv in servers) [under addObject:MMWindowInsidesSame(srv, depth + 1, key)];
    if (under.count) MMWindowRowSetInsides(row, under);
    NSMutableDictionary *info = [@{@"kind": @"tab", @"title": tab.title ?: @"", @"ref": tab.ref, @"window": window ?: @"", @"workspace": space.ref ?: @"",
                                   @"pane": pane.ref ?: @"", @"pid": @(fg), @"process": fgName ?: @"", @"idle": @(*idle), @"goTo": @YES} mutableCopy];
    if (cwd) info[@"cwd"] = cwd;
    if (tab.tty) info[@"tty"] = tab.tty;
    if (tab.status) info[@"status"] = tab.status;
    if (tree) info[@"worktree"] = tree.findingID;
    if (agent) info[@"agent"] = @{@"key": agent.key, @"name": agent.shownName, @"state": AgentWord(agent, tab.status) ?: NSNull.null, @"recently": Recently(agent) ?: NSNull.null};
    if (servers.count) { NSMutableArray *k = [NSMutableArray new]; for (MMWindowRow *srv in servers) [k addObject:srv.key]; info[@"servers"] = k; }
    MMWindowRowSetInsidesInfo(row, info);
    return row;
}

/// Busiest first: one that asks, then by CPU, then by memory, then by name, so the order holds between reads.
static NSComparisonResult Busiest(MMWindowRow *a, MMWindowRow *b) {
    if (a.needsYou != b.needsYou) return a.needsYou ? NSOrderedAscending : NSOrderedDescending;
    double ca = round(MAX(a.cpuPercent, 0) * 2), cb = round(MAX(b.cpuPercent, 0) * 2);
    if (ca != cb) return ca > cb ? NSOrderedAscending : NSOrderedDescending;
    if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
    return [a.key compare:b.key];
}

/// The idle shells of a workspace, one row that opens onto them.
static MMWindowRow *IdleRow(NSArray<MMWindowRow *> *idle, NSString *spaceKey, NSInteger depth) {
    NSString *key = [spaceKey stringByAppendingString:@":idle"];
    uint64_t bytes = 0; double cpu = 0;
    for (MMWindowRow *r in idle) { bytes += r.bytes; cpu += MAX(r.cpuPercent, 0); }
    MMWindowRow *row = MMWindowInsidesRow(key, MMWindowHelper, MMWindowIdleShells((NSInteger)idle.count), nil, cpu, bytes, depth, spaceKey);
    row.quiet = YES;
    row.facts = @[[MMWindowFact label:@"Holds" value:[NSString stringWithFormat:@"%@ where only a shell waits", MMWindowCount((NSInteger)idle.count, @"tab", @"tabs")]]];
    NSMutableArray *kids = [NSMutableArray new];
    for (MMWindowRow *r in idle) { MMWindowRowSetDepth(r, depth + 1); MMWindowRowSetParent(r, key); [kids addObject:r]; }
    MMWindowRowSetInsides(row, kids);
    MMWindowRowSetInsidesInfo(row, @{@"kind": @"idle", @"count": @(idle.count)});
    return row;
}

#pragma mark A workspace

static MMWindowRow *SpaceRow(MMInsidesWorld *w, MMInsidesNode *space, NSString *window, NSInteger *agents, NSInteger *idleCount) {
    NSString *key = [@"insides:cmux:ws:" stringByAppendingString:space.uid ?: space.ref];
    NSMutableArray<MMWindowRow *> *busy = [NSMutableArray new], *idle = [NSMutableArray new];
    NSInteger tabs = 0;
    for (MMInsidesNode *pane in space.children) {
        // A pane that holds one tab is that tab. One with several stands as a row with its tabs under it.
        BOOL split = pane.children.count > 1;
        NSString *paneKey = [@"insides:cmux:pane:" stringByAppendingString:pane.ref];
        NSMutableArray<MMWindowRow *> *paneTabs = [NSMutableArray new];
        for (MMInsidesNode *tab in pane.children) {
            BOOL isIdle = NO;
            MMWindowRow *t = TabRow(w, tab, space, pane, window, split ? 3 : 2, split ? paneKey : key, &isIdle);
            tabs++;
            if (MMWindowRowInsidesInfo(t)[@"agent"]) (*agents)++;
            if (isIdle && !split) [idle addObject:t]; else [paneTabs addObject:t];
        }
        if (!split) { [busy addObjectsFromArray:paneTabs]; continue; }
        [paneTabs sortUsingComparator:^NSComparisonResult(MMWindowRow *x, MMWindowRow *y) { return Busiest(x, y); }];
        double cpu = 0; uint64_t bytes = 0;
        for (MMWindowRow *t in paneTabs) { cpu += MAX(t.cpuPercent, 0); bytes += t.bytes; }
        MMWindowRow *p = MMWindowInsidesRow(paneKey, MMWindowHelper, [NSString stringWithFormat:@"Pane with %@", MMWindowCount((NSInteger)paneTabs.count, @"tab", @"tabs")], nil, cpu, bytes, 2, key);
        p.facts = @[[MMWindowFact label:@"Holds" value:MMWindowCount((NSInteger)paneTabs.count, @"tab", @"tabs")]];
        for (MMWindowRow *t in paneTabs) if (t.needsYou) p.needsYou = YES;
        MMWindowRowSetInsides(p, paneTabs);
        MMWindowRowSetInsidesInfo(p, @{@"kind": @"pane", @"ref": pane.ref ?: @""});
        [busy addObject:p];
    }
    [busy sortUsingComparator:^NSComparisonResult(MMWindowRow *x, MMWindowRow *y) { return Busiest(x, y); }];
    [idle sortUsingComparator:^NSComparisonResult(MMWindowRow *x, MMWindowRow *y) { return Busiest(x, y); }];
    *idleCount += (NSInteger)idle.count;
    NSMutableArray<MMWindowRow *> *kids = [busy mutableCopy];
    if (idle.count == 1) [kids addObject:idle.firstObject];
    else if (idle.count > 1) [kids addObject:IdleRow(idle, key, 2)];
    double cpu = 0; uint64_t bytes = 0; BOOL asks = NO;
    for (MMWindowRow *r in kids) { cpu += MAX(r.cpuPercent, 0); bytes += r.bytes; asks = asks || r.needsYou; }
    MMWindowRow *row = MMWindowInsidesRow(key, MMWindowApp, space.title.length ? space.title : @"Workspace", MMWindowCount(tabs, @"tab", @"tabs"), cpu, bytes, 1, nil);
    row.needsYou = asks;
    // Go to selects the workspace at its selected tab: a right-click item only, its story names no place of its own.
    row.goTo = @"cmux";
    row.menu = @[[MMWindowMenuItem action:@"go-to" title:@"Go to cmux"]];
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    for (MMWindowRow *r in busy) {
        NSArray<MMWindowRow *> *list = MMWindowRowInsides(r) && [MMWindowRowInsidesInfo(r)[@"kind"] isEqualToString:@"pane"] ? MMWindowRowInsides(r) : @[r];
        for (MMWindowRow *t in list) Add(facts, Linked(@"Tab", t.state.length ? [NSString stringWithFormat:@"%@ · %@", t.shownName, t.state] : t.shownName, t.key));
    }
    if (idle.count) Add(facts, Linked(@"Idle", MMWindowIdleShells((NSInteger)idle.count), idle.count > 1 ? [key stringByAppendingString:@":idle"] : idle.firstObject.key));
    row.facts = facts;
    MMWindowRowSetInsides(row, kids);
    MMWindowRowSetInsidesInfo(row, @{@"kind": @"workspace", @"title": space.title ?: @"", @"ref": space.ref ?: @"", @"uid": space.uid ?: @"",
                                     @"window": window ?: @"", @"selected": @(space.selected), @"tabs": @(tabs)});
    return row;
}

#pragma mark The process tree, when cmux cannot tell

/// What runs under the app, as the sample knows it: each process the app started with what is under it, the
/// agents among them as their own rows, and the shells that only wait as one row.
static NSArray<MMWindowRow *> *ProcessRows(MMInsidesWorld *w, pid_t app, NSString *parent) {
    MMSample *sample = w.sample;
    if (app <= 0 || !sample) return @[];
    NSMutableArray<MMWindowRow *> *busy = [NSMutableArray new], *idle = [NSMutableArray new];
    for (NSNumber *child in [sample childrenOf:app]) {
        NSArray<NSNumber *> *tree = [sample treeOf:child.intValue limit:400];
        MMWindowRow *agent = nil;
        NSString *name = nil;
        for (NSNumber *p in tree) {
            if (!agent && w.agents[p]) agent = w.agents[p];
            NSString *n = [sample proc:p.intValue].name;
            if (!name && n.length && !IsShell(n)) name = n;
        }
        double cpu = [sample treeCPU:child.intValue];
        NSString *key = [NSString stringWithFormat:@"insides:cmux:proc:%d", child.intValue];
        if (agent) { [busy addObject:MMWindowInsidesSame(agent, 1, parent)]; continue; }
        MMWindowRow *r = MMWindowInsidesRow(key, MMWindowHelper, name ?: [sample proc:child.intValue].name ?: @"process", nil, cpu, [sample treeFootprint:child.intValue], 1, parent);
        r.facts = @[[MMWindowFact label:@"Processes" value:MMWindowCount((NSInteger)tree.count, @"process", @"processes")]];
        MMWindowRowSetInsidesInfo(r, @{@"kind": @"process", @"pid": child, @"processes": @(tree.count)});
        if (!name && cpu < 0.5) [idle addObject:r]; else [busy addObject:r];
    }
    [busy sortUsingComparator:^NSComparisonResult(MMWindowRow *x, MMWindowRow *y) { return Busiest(x, y); }];
    if (idle.count == 1) [busy addObject:idle.firstObject];
    else if (idle.count > 1) [busy addObject:IdleRow(idle, [parent stringByAppendingString:@":procs"], 1)];
    return busy;
}

#pragma mark The app row

static MMWindowRow *NoteRow(NSString *note, NSString *parent) {
    MMWindowRow *r = MMWindowInsidesRow(@"insides:cmux:note", MMWindowHelper, note, nil, -1, 0, 1, parent);
    r.quiet = YES;
    MMWindowRowSetInsidesInfo(r, @{@"kind": @"note"});
    return r;
}

void MMWindowInsidesAttach(MMWindowModel *m, MMSnapshot *s, MMInsidesAnswer *a) {
    MMWindowRow *app = nil;
    for (MMWindowGroup *g in m.memoryGroups) for (MMWindowRow *r in g.rows) if (!app && MMWindowInsidesApp(r)) app = r;
    if (!app) return;
    MMInsidesWorld *w = World(m, s);
    NSString *known = !a ? @"nothing" : @[@"nothing", @"found", @"unreachable", @"older"][(NSUInteger)MAX(0, MIN(a.known, MMInsidesOlder))];
    NSString *why = a.known == MMInsidesUnreachable || a.known == MMInsidesOlder ? a.why : nil;
    MMWindowRowSetInsidesState(app, @{@"app": @"cmux", @"known": known, @"looking": @(a.looking), @"why": why ?: NSNull.null,
                                      @"at": a.at ? @(a.at.timeIntervalSince1970) : NSNull.null});
    NSMutableArray<MMWindowRow *> *kids = [NSMutableArray new];
    NSMutableArray<MMWindowFact *> *section = [NSMutableArray new];
    NSInteger agents = 0, idle = 0, spaces = 0;
    if (a.known == MMInsidesFound) {
        for (MMInsidesNode *win in a.root.children)
            for (MMInsidesNode *space in win.children) { [kids addObject:SpaceRow(w, space, win.ref, &agents, &idle)]; spaces++; }
        [kids sortUsingComparator:^NSComparisonResult(MMWindowRow *x, MMWindowRow *y) { return Busiest(x, y); }];
        // The section under the usual header: each workspace, then each of its tabs that has something going on.
        for (MMWindowRow *space in kids) {
            Add(section, Linked(@"Workspace", [NSString stringWithFormat:@"%@ · %@", space.shownName, space.state ?: @""], space.key));
            for (MMWindowFact *f in space.facts) Add(section, f);
        }
    } else if (why) {
        MMFinding *f = [s finding:app.key];
        [kids addObjectsFromArray:ProcessRows(w, f ? PidOf(f) : 0, app.key)];
    }
    if (a.looking) [section insertObject:[MMWindowFact label:@"Inside" value:MMWindowInsidesLooking(@"cmux")] atIndex:0];
    else if (why) [section insertObject:[MMWindowFact label:@"Inside" value:why] atIndex:0];
    else if (a.known == MMInsidesFound)
        [section insertObject:[MMWindowFact label:@"Inside" value:[NSString stringWithFormat:@"%@, %@ in them, %@", MMWindowCount(spaces, @"workspace", @"workspaces"),
                                                                  MMWindowCount(agents, @"agent", @"agents"), MMWindowIdleShells(idle)]] atIndex:0];
    // Before the first answer, and when cmux could tell nothing, one quiet line stands under the row.
    if (!kids.count) [kids addObject:NoteRow(why ?: MMWindowInsidesLooking(@"cmux"), app.key)];
    for (MMWindowRow *k in kids) if (MMWindowRowDepth(k) == 1) MMWindowRowSetParent(k, app.key);
    MMWindowRowSetInsides(app, kids);
    app.facts = [(app.facts ?: @[]) arrayByAddingObjectsFromArray:section];
}

MMInsidesAnswer *MMWindowInsidesReadOnce(MMWindowModel *m) {
    BOOL has = NO;
    for (MMWindowGroup *g in m.memoryGroups) for (MMWindowRow *r in g.rows) if (MMWindowInsidesApp(r)) has = YES;
    if (!has) return nil;
    __block MMInsidesAnswer *a = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"core", @"insides", QOS_CLASS_UTILITY), ^{ a = [MMAppInsides.shared readNow:MMAppInsidesCmux]; dispatch_semaphore_signal(done); });
    // The read has its own limit; this wait only guards against a queue that never runs it.
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MMAppInsides.shared.limit + 3) * NSEC_PER_SEC)));
    return a;
}
