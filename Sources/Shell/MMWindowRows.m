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

static void Add(NSMutableArray<MMWindowFact *> *out, NSString *label, NSString *value) {
    if (value.length) [out addObject:[MMWindowFact label:label value:value]];
}

static NSString *Ports(id v) {
    if (![v isKindOfClass:NSArray.class] || ![v count]) return nil;
    NSMutableArray *a = [NSMutableArray new];
    for (id p in v) [a addObject:[NSString stringWithFormat:@":%@", p]];
    return [a componentsJoinedByString:@", "];
}

static NSArray<MMWindowFact *> *FactsOf(MMFinding *f, MMWindowKind kind) {
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    NSDictionary *x = f.facts;
    NSString *stays = f.keepReasons.firstObject;
    switch (kind) {
        case MMWindowServer: {
            if ([Num(x[@"port"]) integerValue] > 0) Add(out, @"Port", [Num(x[@"port"]) stringValue]);
            Add(out, @"Project", Str(x[@"project"]));
            Add(out, @"Runs in", Str(x[@"where"]) ?: Str(x[@"whereApp"]));
            Add(out, @"Started by", Str(x[@"agent"]) ?: Str(x[@"launcher"]));
            NSDate *last = Date(x[@"lastActive"]);
            if (last) Add(out, [Str(x[@"state"]) isEqualToString:@"idle"] ? @"Idle" : @"Last used",
                          [Str(x[@"state"]) isEqualToString:@"idle"] ? MMDuration(-last.timeIntervalSinceNow) : MMAgo(last));
            if ([Num(x[@"uptimeSeconds"]) doubleValue] > 0) Add(out, @"Up", MMDuration([x[@"uptimeSeconds"] doubleValue]));
            NSDate *kept = Date(x[@"keptUntil"]);
            if (kept && kept.timeIntervalSinceNow > 0) Add(out, @"Kept", [@"for " stringByAppendingString:MMDuration(kept.timeIntervalSinceNow)]);
            break;
        }
        case MMWindowAgent:
            Add(out, @"Project", Str(x[@"project"]).lastPathComponent);
            Add(out, @"State", Str(x[@"state"]));
            Add(out, @"Why", Str(x[@"why"]));
            break;
        case MMWindowApp:
            Add(out, @"Used by", Str(x[@"agent"]));
            Add(out, @"Serves", Ports(x[@"ports"]));
            Add(out, @"Stays", stays ?: Str(x[@"reason"]));
            stays = nil;
            break;
        case MMWindowHelper:
            Add(out, @"Left by", Str(x[@"worktree"]).lastPathComponent);
            Add(out, @"Folder", Folder(Str(x[@"cwd"])));
            break;
        case MMWindowTabs: {
            NSArray *urls = [x[@"urls"] isKindOfClass:NSArray.class] ? x[@"urls"] : @[];
            if (urls.count) Add(out, @"Open", MMPlural((NSInteger)urls.count, @"tab"));
            Add(out, @"On", Ports(x[@"ports"]));
            Add(out, @"Left by", Str(x[@"worktree"]).lastPathComponent);
            break;
        }
        case MMWindowWorktree: {
            Add(out, @"Branch", Str(x[@"branch"]));
            if (Str(x[@"merged"])) Add(out, @"Merged", @"yes");
            NSInteger dirty = [Num(x[@"dirty"]) integerValue], untracked = [Num(x[@"untracked"]) integerValue];
            NSMutableArray *ch = [NSMutableArray new];
            if (dirty > 0) [ch addObject:[NSString stringWithFormat:@"%ld changed", (long)dirty]];
            if (untracked > 0) [ch addObject:[NSString stringWithFormat:@"%ld new", (long)untracked]];
            Add(out, @"Files", [ch componentsJoinedByString:@", "]);
            if ([Num(x[@"unpushed"]) integerValue] > 0) Add(out, @"Not pushed", MMPlural([x[@"unpushed"] integerValue], @"commit"));
            if (Num(x[@"quietDays"])) Add(out, @"Quiet", MMDuration([x[@"quietDays"] doubleValue] * 86400));
            Add(out, @"Folder", Folder(f.path ?: Str(x[@"path"])));
            break;
        }
        case MMWindowCache:
            Add(out, @"Kind", Str(x[@"kindTitle"]));
            Add(out, @"Project", Str(x[@"owner"]));
            if (Date(x[@"lastUsed"])) Add(out, @"Last used", MMAgo(Date(x[@"lastUsed"])));
            Add(out, @"Folder", Folder(f.path ?: Str(x[@"path"])));
            Add(out, @"Stays", stays ?: Str(x[@"keep"]) ?: Str(x[@"why"]));
            stays = nil;
            break;
    }
    Add(out, @"Stays", stays);
    return out;
}

#pragma mark - The row

MMWindowRow *MMWindowRowFrom(MMPerformanceRow *r, MMSnapshot *s) {
    MMFinding *f = r.finding ?: [s finding:r.findingID];
    MMWindowRow *row = [MMWindowRow new];
    row.key = r.key;
    row.kind = KindOf(f, r.group);
    row.name = f ? MMWindowNameOf(f) : r.name ?: @"";
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
    // Core keeps an hour for an agent's tree and a server's tree, keyed by the first process the finding names.
    if ((row.kind == MMWindowServer || row.kind == MMWindowAgent) && f.procs.count) {
        MMProcKey k = {0, 0};
        [f.procs.firstObject getValue:&k size:sizeof k];
        row.hour = MMWindowRingHour([s.history treeFor:k]);
    }
    row.facts = FactsOf(f, row.kind);
    return row;
}
