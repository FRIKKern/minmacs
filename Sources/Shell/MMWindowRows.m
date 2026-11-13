// One window row from one finding, MMWindowFeed.h. Each expert's finding carries its own facts as a dictionary, the
// same one its --json prints, so every key read here is one an expert writes. test/window.sh checks they still do.
// A fact that is missing leaves its line out. Nothing is guessed.
#import "Shell/MMWindowFeed.h"
#import "UI/MMFormat.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }
static NSDate *Date(id v) { return Num(v) && [v doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[v doubleValue]] : nil; }
static NSString *Folder(NSString *path) { return path.length ? path.stringByAbbreviatingWithTildeInPath : nil; }

static BOOL Is(MMFinding *f, NSString *expert, NSString *kind) { return [f.expert isEqualToString:expert] && [f.kind isEqualToString:kind]; }

static MMWindowKind KindOf(MMFinding *f, NSString *group) {
    if (Is(f, @"locohost", @"server")) return MMWindowServer;
    if (Is(f, @"minmacs", @"agent")) return MMWindowAgent;
    if ([f.kind isEqualToString:@"helper"]) return MMWindowHelper;
    if ([f.kind isEqualToString:@"tabs"]) return MMWindowTabs;
    if (Is(f, @"workforest", @"worktree")) return MMWindowWorktree;
    if (Is(f, @"noonoo", @"clutter")) return MMWindowCache;
    if ([group isEqualToString:MMPerformanceWorktrees]) return MMWindowWorktree;
    if ([group isEqualToString:MMPerformanceClutter]) return MMWindowCache;
    return MMWindowApp;
}

NSString *MMWindowNameOf(MMFinding *f) {
    NSDictionary *x = f.facts;
    NSString *title = f.title.length ? f.title : f.stableKey ?: @"";
    if (Is(f, @"locohost", @"server")) {
        NSInteger port = [Num(x[@"port"]) integerValue];
        if (port <= 0) return title;
        NSString *what = Str(x[@"framework"]) ?: Str(x[@"project"]);
        return what ? [NSString stringWithFormat:@":%ld %@", (long)port, what] : [NSString stringWithFormat:@":%ld", (long)port];
    }
    if (Is(f, @"workforest", @"worktree")) return Str(x[@"branch"]) ?: f.path.lastPathComponent ?: title;
    return Str(x[@"name"]) ?: title;
}

/// The session an agent's finding stands for: the one its stable key names, or the one its process runs.
static MMSession *SessionOf(MMFinding *f, MMSnapshot *s) {
    NSString *harness = Str(f.facts[@"harnessID"]), *stable = f.stableKey ?: @"";
    NSRange colon = [stable rangeOfString:@":"];
    NSString *sid = colon.location == NSNotFound ? nil : [stable substringFromIndex:colon.location + 1];
    pid_t pid = (pid_t)[Num(f.facts[@"pid"]) intValue];
    MMSession *byPid = nil;
    for (MMSession *x in s.facts.sessions) {
        if (harness && x.agent.length && ![x.agent isEqualToString:harness]) continue;
        if (sid.length && [x.sessionID isEqualToString:sid]) return x;
        if (pid > 0 && x.pid == pid) byPid = x;
    }
    return byPid;
}

/// One line, with no line breaks and no space at either end.
static NSString *OneLine(NSString *t) {
    NSArray *parts = [t componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

/// What tells this agent from the others, most telling first: its session's title, then its project folder.
/// The harness is the row's icon and a line of its story. With neither fact, the harness's name is all there is.
static NSString *AgentName(MMFinding *f, MMSnapshot *s) {
    NSString *title = OneLine(SessionOf(f, s).title ?: @"");
    if (title.length) return title;
    NSString *project = Str(f.facts[@"project"]).stringByStandardizingPath;
    if ([project isEqualToString:NSHomeDirectory()]) return @"Home folder";
    // A folder inside a hidden one, such as ~/.hermes/hermes-agent, is where the harness lives and no project.
    for (NSString *part in project.pathComponents) if ([part hasPrefix:@"."]) return MMWindowNameOf(f);
    NSString *folder = project.lastPathComponent;
    return folder.length && ![folder isEqualToString:@"/"] ? folder : MMWindowNameOf(f);
}

#pragma mark - The quiet word

static NSString *StateOf(MMFinding *f, MMWindowKind kind) {
    NSDictionary *x = f.facts;
    NSString *state = Str(x[@"state"]);
    switch (kind) {
        case MMWindowServer:
            if (Num(x[@"keptUntil"]) || [Num(x[@"protected"]) boolValue]) return @"kept";
            return [state isEqualToString:@"idle"] ? @"idle" : nil;
        case MMWindowAgent:
            if ([state isEqualToString:@"waits on you"]) return @"asks";
            return [state isEqualToString:@"working"] || [state isEqualToString:@"idle"] ? state : nil;
        case MMWindowApp: {
            NSString *g = Str(x[@"group"]);
            return [g isEqualToString:@"kept"] || [g isEqualToString:@"spared"] ? @"kept" : nil;
        }
        case MMWindowHelper: return @"left behind";
        case MMWindowTabs: return nil;
        case MMWindowWorktree:
            if ([Num(x[@"dirty"]) integerValue] + [Num(x[@"untracked"]) integerValue] > 0) return @"changed";
            if (Str(x[@"merged"])) return @"merged";
            return [Num(x[@"protected"]) boolValue] ? @"kept" : nil;
        case MMWindowCache:
            if ([state isEqualToString:@"kept"]) return @"kept";
            return [state isEqualToString:@"live"] ? @"in use" : nil;
    }
    return nil;
}

#pragma mark - The story

static void Add(NSMutableArray<MMWindowFact *> *out, MMWindowFact *fact) { if (fact) [out addObject:fact]; }

/// A row's facts. The words of each are the model's, MMWindowFact… in UI/Window/MMWindowModel.m: one function a fact,
/// so the render's made-up days say them the same way. An agent's why, a raw word about its processes such as
/// "child caffeinate" or "status file busy", is not for a person and is left out.
static NSArray<MMWindowFact *> *FactsOf(MMFinding *f, MMWindowKind kind) {
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    NSDictionary *x = f.facts;
    NSString *stays = f.keepReasons.firstObject;
    NSArray *ports = [x[@"ports"] isKindOfClass:NSArray.class] ? x[@"ports"] : nil;
    switch (kind) {
        case MMWindowServer: {
            Add(out, MMWindowFactPort([Num(x[@"port"]) integerValue]));
            Add(out, MMWindowFactProject(Str(x[@"project"])));
            Add(out, MMWindowFactRunsIn(Str(x[@"where"]) ?: Str(x[@"whereApp"])));
            Add(out, MMWindowFactStartedBy(Str(x[@"agent"]) ?: Str(x[@"launcher"])));
            NSDate *last = Date(x[@"lastActive"]);
            if (last) Add(out, [Str(x[@"state"]) isEqualToString:@"idle"] ? MMWindowFactIdle(-last.timeIntervalSinceNow) : MMWindowFactLastUsed(-last.timeIntervalSinceNow));
            if ([Num(x[@"uptimeSeconds"]) doubleValue] > 0) Add(out, MMWindowFactUp([x[@"uptimeSeconds"] doubleValue]));
            NSDate *kept = Date(x[@"keptUntil"]);
            if (kept && kept.timeIntervalSinceNow > 0) Add(out, MMWindowFactKept(kept.timeIntervalSinceNow));
            break;
        }
        case MMWindowAgent:
            Add(out, MMWindowFactAgent(Str(x[@"name"])));
            Add(out, MMWindowFactProject(Str(x[@"project"]).lastPathComponent));
            Add(out, MMWindowFactState(Str(x[@"state"])));
            break;
        case MMWindowApp:
            Add(out, MMWindowFactUsedBy(Str(x[@"agent"])));
            Add(out, MMWindowFactServes(ports));
            Add(out, MMWindowFactStays(stays ?: Str(x[@"reason"])));
            stays = nil;
            break;
        case MMWindowHelper:
            Add(out, MMWindowFactLeftBy(Str(x[@"worktree"]).lastPathComponent));
            Add(out, MMWindowFactFolder(Folder(Str(x[@"cwd"]))));
            break;
        case MMWindowTabs: {
            NSArray *urls = [x[@"urls"] isKindOfClass:NSArray.class] ? x[@"urls"] : @[];
            Add(out, MMWindowFactOpenTabs((NSInteger)urls.count));
            Add(out, MMWindowFactOnPorts(ports));
            Add(out, MMWindowFactLeftBy(Str(x[@"worktree"]).lastPathComponent));
            break;
        }
        case MMWindowWorktree:
            // Merged is the row's own word, so it is no fact here.
            Add(out, MMWindowFactBranch(Str(x[@"branch"])));
            Add(out, MMWindowFactFiles([Num(x[@"dirty"]) integerValue], [Num(x[@"untracked"]) integerValue]));
            Add(out, MMWindowFactNotPushed([Num(x[@"unpushed"]) integerValue]));
            if (Num(x[@"quietDays"])) Add(out, MMWindowFactUntouched([x[@"quietDays"] doubleValue] * 86400));
            Add(out, MMWindowFactFolder(Folder(f.path ?: Str(x[@"path"]))));
            break;
        case MMWindowCache:
            Add(out, MMWindowFactKind(Str(x[@"kindTitle"])));
            Add(out, MMWindowFactOwner(Str(x[@"owner"])));
            if (Date(x[@"lastUsed"])) Add(out, MMWindowFactLastUsed(-Date(x[@"lastUsed"]).timeIntervalSinceNow));
            Add(out, MMWindowFactFolder(Folder(f.path ?: Str(x[@"path"]))));
            Add(out, MMWindowFactStays(stays ?: Str(x[@"keep"]) ?: Str(x[@"why"])));
            stays = nil;
            break;
    }
    Add(out, MMWindowFactStays(stays));
    return out;
}

#pragma mark - The row

MMWindowRow *MMWindowRowFrom(MMPerformanceRow *r, MMSnapshot *s) {
    MMFinding *f = r.finding ?: [s finding:r.findingID];
    MMWindowRow *row = [MMWindowRow new];
    row.key = r.key;
    row.kind = KindOf(f, r.group);
    row.name = !f ? r.name ?: @"" : row.kind == MMWindowAgent ? AgentName(f, s) : MMWindowNameOf(f);
    row.needsYou = r.needsYou;
    if (r.unit == MMPerformanceTabs) row.tabs = (NSInteger)r.number; else row.bytes = r.number;
    if (!f) return row;
    NSDictionary *x = f.facts;
    switch (row.kind) {
        case MMWindowServer: row.iconHint = Str(x[@"framework"]); break;
        case MMWindowAgent: row.iconHint = Str(x[@"harnessID"]); break;
        case MMWindowApp: case MMWindowTabs: row.iconHint = Str(x[@"bundleID"]); break;
        default: break;
    }
    row.state = StateOf(f, row.kind);
    // CPU is a fact of a process only. A worktree or a cache has none, and its cost holds 0 there, not a reading.
    BOOL runs = row.kind == MMWindowServer || row.kind == MMWindowAgent || row.kind == MMWindowApp || row.kind == MMWindowHelper;
    row.cpuPercent = runs && f.cost.cpuPercent >= 0 ? f.cost.cpuPercent : -1;
    // Quiet: nothing is going on in it now, by its own facts. The window draws such a name a step quieter.
    NSString *state = Str(x[@"state"]);
    switch (row.kind) {
        // Only a fact that is there makes a row quiet: an app whose CPU is not known, a worktree whose files were not
        // counted and a cache with no state are not called quiet.
        case MMWindowServer: case MMWindowAgent: row.quiet = [state isEqualToString:@"idle"]; break;
        case MMWindowApp: row.quiet = row.cpuPercent >= 0 && row.cpuPercent < 0.5; break;
        case MMWindowHelper: case MMWindowTabs: row.quiet = YES; break;
        case MMWindowWorktree: row.quiet = Num(x[@"dirty"]) && Num(x[@"untracked"]) && [Num(x[@"dirty"]) integerValue] + [Num(x[@"untracked"]) integerValue] == 0; break;
        case MMWindowCache: row.quiet = state.length && ![state isEqualToString:@"live"]; break;
    }
    // Core keeps an hour for an agent's tree and a server's tree, keyed by the first process the finding names.
    if ((row.kind == MMWindowServer || row.kind == MMWindowAgent) && f.procs.count) {
        MMProcKey k = {0, 0};
        [f.procs.firstObject getValue:&k size:sizeof k];
        row.hour = MMWindowRingHour([s.history treeFor:k]);
    }
    row.facts = FactsOf(f, row.kind);
    return row;
}
