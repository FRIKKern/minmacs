// An agent row's story, MMWindowFeed.h: what it has been doing, where it is, its worktrees and what it holds. The
// owner asked: "On Agent we want to see what they been doing, where they are, what worktrees, their milestones etc,
// what cache it hold". Every fact comes from the snapshot as it is: the session Know read from the transcript's head
// and tail, the MinMacs finding, WorkForest's worktrees, LocoHost's servers and Noo-Noo's caches, and from Know's
// memory of where it runs.
// Nothing here reads a file, runs a process or asks gh. A fact that is missing leaves its line out. Nothing is guessed.
#import "Shell/MMWindowFeed.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static void Add(NSMutableArray<MMWindowFact *> *out, MMWindowFact *fact) { if (fact) [out addObject:fact]; }

/// YES when path is folder or lies inside it.
static BOOL Inside(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    NSString *f = folder.length > 1 && [folder hasSuffix:@"/"] ? [folder substringToIndex:folder.length - 1] : folder;
    return [path isEqualToString:f] || [path hasPrefix:[f stringByAppendingString:@"/"]];
}

static BOOL HomeOrTop(NSString *path) { NSString *p = path.stringByStandardizingPath; return [p isEqualToString:NSHomeDirectory()] || [p isEqualToString:@"/"]; }

static pid_t PidOf(MMFinding *f) {
    pid_t pid = (pid_t)[Num(f.facts[@"pid"]) intValue];
    if (pid > 0 || !f.procs.count) return pid;
    MMProcKey k = {0, 0};
    [f.procs.firstObject getValue:&k size:sizeof k];
    return k.pid;
}

/// A worktree's pull request: a `pullRequest` its facts hold, the pull itself {number, title, state, url, milestone}
/// or an answer that holds one under `pull`, else what MMPulls already knows. A milestone may be its title or an
/// object with one. Nothing is asked here: only what is already known is said.
/// What the window's pull requests know of a worktree's branch, MMPulls in Core/Know, from memory and its kept answers
/// alone: it never runs gh, and the agent's story never asks it to. The worktree's own story asks, on demand.
static MMWindowFact *KnownPullOf(NSDictionary *x) {
    NSString *repo = Str(x[@"repo"]), *branch = Str(x[@"branch"]);
    if (!repo || !branch || [Num(x[@"main"]) boolValue]) return nil;
    MMPull *pull = [MMPulls.shared knownFor:repo branch:branch head:Str(x[@"head"])].pull;
    return pull ? MMWindowFactPullRequest(pull.number, pull.stateWord, pull.draft, pull.milestone) : nil;
}

static MMWindowFact *PullOf(NSDictionary *x) {
    NSDictionary *pr = Dict(x[@"pullRequest"]);
    if (!pr) return KnownPullOf(x);
    if (Dict(pr[@"pull"])) pr = Dict(pr[@"pull"]);
    if ([Num(pr[@"number"]) integerValue] <= 0) return nil;
    id milestone = pr[@"milestone"];
    NSString *ms = Str(milestone) ?: Str(Dict(milestone)[@"title"]);
    BOOL draft = [Num(pr[@"draft"]) boolValue] || [Num(pr[@"isDraft"]) boolValue];
    return MMWindowFactPullRequest([pr[@"number"] integerValue], Str(pr[@"state"]), draft, ms);
}

/// What a session did lately, from the times Know kept of its tail: the tool uses and the files an edit tool wrote in
/// the last hour, or since the tail's first line where that is later.
static MMWindowFact *RecentlyOf(MMSession *session, NSTimeInterval now) {
    if (![session respondsToSelector:@selector(toolUseTimes)] || !session.toolUseTimes) return nil;
    NSTimeInterval from = now - 3600;
    if (session.activityFrom && session.activityFrom.timeIntervalSince1970 > from) from = session.activityFrom.timeIntervalSince1970;
    NSInteger tools = 0, files = 0;
    for (NSNumber *t in session.toolUseTimes) if (t.doubleValue >= from) tools++;
    for (NSNumber *t in session.edits.allValues) if (t.doubleValue >= from) files++;
    return MMWindowFactRecently(tools, files, now - from);
}

NSArray<MMWindowFact *> *MMWindowAgentFacts(MMFinding *f, MMSession *session, NSString *shownName, MMSnapshot *s, NSString **goTo) {
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    NSDictionary *x = f.facts;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    MMSample *sample = s.facts.sample;
    pid_t pid = PidOf(f);
    NSArray<NSNumber *> *tree = pid > 0 && sample ? [sample treeOf:pid limit:500] : @[];
    // Its folder: where its process runs now, else where its session began.
    NSString *cwd = Str(x[@"project"]) ?: Str(session.cwd);
    if (HomeOrTop(cwd)) cwd = nil;

    // Its worktrees: the one whose folder holds its folder, the deepest, then any whose own facts name its session or
    // hold one of its processes' folders.
    NSMutableArray<MMFinding *> *trees = [NSMutableArray new];
    MMFinding *home = nil;
    NSArray<MMFinding *> *worktrees = [[s findingsFor:@"workforest"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MMFinding *w, id b) {
        return [w.kind isEqualToString:@"worktree"] && (w.path.length || Str(w.facts[@"path"]));
    }]];
    for (MMFinding *w in worktrees) {
        NSString *p = w.path ?: Str(w.facts[@"path"]);
        if (Inside(cwd, p) && (!home || p.length > (home.path ?: Str(home.facts[@"path"])).length)) home = w;
    }
    if (home) [trees addObject:home];
    for (MMFinding *w in worktrees) {
        if ([trees containsObject:w]) continue;
        NSString *p = w.path ?: Str(w.facts[@"path"]);
        BOOL named = session.sessionID.length && [Str(Dict(w.facts[@"session"])[@"id"]) isEqualToString:session.sessionID];
        BOOL holds = NO;
        for (NSNumber *child in tree) if (Inside([sample cwdOf:child.intValue], p)) { holds = YES; break; }
        if (named || holds) [trees addObject:w];
    }

    // What it has been doing: its harness, where, its session's title where the row's name is not it, how long its
    // process runs and what it did in the last hour. The first line says when it was last active.
    Add(out, MMWindowFactAgent(Str(x[@"name"])));
    Add(out, MMWindowFactProject(cwd.stringByAbbreviatingWithTildeInPath));
    // Its branch: its worktree's as git has it now, else the one its session began on in its folder. "HEAD" is git's
    // word for no branch, and says nothing to a person.
    NSString *branch = Str(home.facts[@"branch"]) ?: (cwd ? Str(session.branch) : nil);
    if (![branch isEqualToString:@"HEAD"]) Add(out, MMWindowFactBranch(branch));
    NSArray *words = [Str(session.title) ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *title = [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    if (title.length && title.length <= 160 && ![title isEqualToString:shownName]) Add(out, MMWindowFactSession(title));
    MMProc *proc = pid > 0 ? [sample proc:pid] : nil;
    // How long it runs: the start its live status file names for its process. A session with no live process says none.
    if (session.pid > 0 && session.started && now > session.started.timeIntervalSince1970) Add(out, MMWindowFactUp(now - session.started.timeIntervalSince1970));
    if (session.lastActive) Add(out, MMWindowFactLastActive(now - session.lastActive.timeIntervalSince1970));
    Add(out, RecentlyOf(session, now));

    // Where it is on screen, with Go to when Know can bring that place forward. A finding that names its place says
    // it; else Know's last answer, which the controller asks for while the window is open. Memory only.
    NSString *where = Str(x[@"where"]), *whereApp = Str(x[@"whereApp"]);
    BOOL whereGo = [Num(x[@"whereGo"]) boolValue];
    if (!where && f.procs.count) {
        MMProcKey k = {0, 0};
        [f.procs.firstObject getValue:&k size:sizeof k];
        MMPlace *place = MMWhereKnown(k);
        where = Str(place.label); whereApp = Str(place.app); whereGo = place && MMPlaceGoable(place);
    }
    Add(out, MMWindowFactRunsIn(where));
    if (goTo) *goTo = where && whereGo ? (whereApp ?: where) : nil;

    for (MMFinding *w in trees) {
        Add(out, MMWindowFactWorktree(MMWindowNameOf(w), w.findingID));
        Add(out, PullOf(w.facts));
    }

    // What it holds: the ports its own process serves, the servers in its process tree, the caches of its session,
    // and the processes under it.
    Add(out, MMWindowFactServes([x[@"ports"] isKindOfClass:NSArray.class] ? x[@"ports"] : nil));
    NSSet<NSNumber *> *mine = [NSSet setWithArray:tree];
    for (MMFinding *srv in [s findingsFor:@"locohost"]) {
        if (![srv.kind isEqualToString:@"server"]) continue;
        pid_t sp = PidOf(srv);
        if (sp <= 0 || sp == pid || ![mine containsObject:@(sp)]) continue;
        Add(out, MMWindowFactServer(MMWindowNameOf(srv), srv.findingID));
    }
    if (session.sessionID.length) {
        NSMutableArray<MMFinding *> *caches = [NSMutableArray new];
        for (MMFinding *c in [s findingsFor:@"noonoo"]) {
            if (![c.kind isEqualToString:@"clutter"]) continue;
            NSString *path = Str(c.facts[@"path"]) ?: c.path;
            if ([Str(c.facts[@"sessionID"]) isEqualToString:session.sessionID] || [path.pathComponents containsObject:session.sessionID]) [caches addObject:c];
        }
        // Sizes count honestly: a cache inside another one named here is part of that one's size.
        for (MMFinding *c in caches) {
            NSString *path = Str(c.facts[@"path"]) ?: c.path;
            BOOL within = NO;
            for (MMFinding *o in caches) if (o != c && ![(Str(o.facts[@"path"]) ?: o.path) isEqualToString:path] && Inside(path, Str(o.facts[@"path"]) ?: o.path)) within = YES;
            if (within) continue;
            Add(out, MMWindowFactCache(Str(c.facts[@"kindTitle"]) ?: MMWindowNameOf(c), c.cost.diskFreed, YES, c.findingID));
        }
    }
    if (tree.count > 1) {
        uint64_t all = [sample treeFootprint:pid], own = proc.footprint;
        Add(out, MMWindowFactProcesses((NSInteger)tree.count - 1, all > own ? all - own : 0));
    }
    Add(out, MMWindowFactState(Str(x[@"state"])));
    return out;
}

void MMWindowResolveLinks(MMWindowModel *m) {
    NSMutableSet<NSString *> *top = [NSMutableSet new];
    NSMutableDictionary<NSString *, NSString *> *shownAs = [NSMutableDictionary new];
    NSArray<MMWindowGroup *> *groups = [m.memoryGroups ?: @[] arrayByAddingObjectsFromArray:m.diskGroups ?: @[]];
    for (MMWindowGroup *g in groups)
        for (MMWindowRow *r in g.rows) { [top addObject:r.key]; for (MMWindowRow *member in r.members) shownAs[member.key] = r.key; }
    // A link names the row the window shows: a member of a row that stands for several is that row, DESIGN rule 16,
    // and a row the window does not show is named without a press.
    for (MMWindowGroup *g in groups)
        for (MMWindowRow *r in g.rows)
            for (MMWindowFact *f in r.facts) if (f.link && ![top containsObject:f.link]) f.link = shownAs[f.link];
}
