// The graph builder: workstreams, owners and the one published snapshot. Issue #16, patterns P31 to P33.
//
// Threads. Every build runs on the serial queue no.guerrilla.minmacs.core.graph. A finished snapshot goes to
// -latest at once, an atomic pointer that any queue may read, and to -current on main through dispatch_async.
// Main never waits on the graph queue, and the graph queue never waits on main. A snapshot is immutable,
// so a reader needs no lock.
//
// Owners. Each finding gets one owner, picked in this order. The first rule that matches wins.
//   1. The back-link ownerPath, then path, then the cwd of the finding's first process: the deepest
//      worktree that holds it. With a live session there, that worktree's workstream. Otherwise the worktree.
//   2. The nearest agent at or above one of the finding's processes, at most 20 hops up:
//      that agent's workstream, or its session when it has no worktree.
//   3. The owner the expert gave as a hint.
//   4. A path outside every worktree: a project owner for that folder.
//   5. Processes only: an app owner, named by the top process below launchd.
//   6. Nothing else: the one unknown owner.
// A workstream's key is its worktree path, never a session id or pid. A restarted session in the same
// worktree keeps the same workstream, so keeps and verdicts that name the owner survive.
//
// Like MMFinding.m, this file sends messages to Senses and Know objects and never names their classes.
#import "Core/Graph/MMGraph.h"
#import "Core/MMExpert.h"
#import <stdatomic.h>

static const NSUInteger kAncestorHops = 20;

static NSString *ProcKeyString(MMProcKey k) { return [NSString stringWithFormat:@"%d:%llu", k.pid, (unsigned long long)k.startSec]; }

/// YES when path is folder or inside it.
static BOOL PathIn(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    if ([path isEqualToString:folder]) return YES;
    NSString *f = [folder hasSuffix:@"/"] ? folder : [folder stringByAppendingString:@"/"];
    return [path hasPrefix:f];
}

/// The process the sample knows at this key, or nil when that pid now runs something else.
static MMProc *LiveProc(MMSample *s, MMProcKey k) {
    MMProc *p = [s proc:k.pid];
    return p && (k.startSec == 0 || p.startSec == k.startSec) ? p : nil;
}

#pragma mark - Workstream

@interface MMWorkstream ()
@property (readwrite) MMOwner *owner;
@property (readwrite) MMSession *session;
@property (readwrite) MMAgent *agent;
@property (readwrite) MMAgentState agentState;
@property (readwrite) MMWorktree *worktree;
@property (readwrite) MMGitFacts *git;
@property (readwrite) NSArray<MMFinding *> *findings;
@property (readwrite) NSArray<MMClutterItem *> *clutter;
@property (copy) NSString *fingerprintText;
@property (copy) NSString *folder;                      // the worktree path, or the session's cwd without one
@end

@implementation MMWorkstream
- (NSString *)fingerprint { return self.fingerprintText; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ %@", self.owner.ownerID, self.session.sessionID ?: self.agent.harnessID]; }
@end

#pragma mark - Snapshot

@interface MMSnapshot ()
@property (readwrite) uint64_t generation;
@property (readwrite) NSDate *builtAt;
@property (readwrite) MMFacts *facts;
@property (readwrite) NSArray<MMWorkstream *> *workstreams;
@property (readwrite) NSArray<MMFinding *> *findings;
@property (readwrite) NSDictionary<NSString *, NSString *> *awakeHolds;
@property NSDictionary<NSString *, MMFinding *> *byID;
@property NSDictionary<NSString *, NSArray<MMFinding *> *> *byExpert;
@property NSDictionary<NSString *, MMReview *> *reviews;
@property NSInteger working;
@end

/// One live agent session while a build runs: a session, an agent, or both.
@interface MMLink : NSObject
@property MMSession *session;
@property MMAgent *agent;
@property (copy) NSString *cwd, *linkKey;
@property MMWorktree *worktree;
@end
@implementation MMLink @end

/// The state of one build. Lives only on the queue that builds.
@interface MMBuild : NSObject
@property MMFacts *facts;
@property NSArray<MMWorktree *> *trees;                 // deepest first
@property NSMutableDictionary<NSString *, MMOwner *> *owners;   // by ownerID, one object per owner
@property NSMutableDictionary<NSString *, MMOwner *> *ownerOfTree;      // worktree path to its owner
@property NSMutableDictionary<NSNumber *, MMOwner *> *ownerOfAgentPid;
@property NSMutableArray<MMWorkstream *> *streams;
@end
@implementation MMBuild

- (MMOwner *)owner:(MMOwnerKind)kind key:(NSString *)key name:(NSString *)name path:(NSString *)path parent:(MMOwner *)parent {
    MMOwner *o = [MMOwner kind:kind key:key name:name path:path parent:parent];
    MMOwner *have = self.owners[o.ownerID];
    if (have) return have;
    self.owners[o.ownerID] = o;
    return o;
}

- (MMWorktree *)treeAt:(NSString *)path {
    for (MMWorktree *w in self.trees) if (PathIn(path, w.path)) return w;
    return nil;
}

@end

/// Higher ranks lead a worktree's workstream: a working agent, then any agent, then a session that still works.
static NSInteger LinkRank(MMLink *l) {
    if (l.agent.state == MMAgentWorking) return 3;
    if (l.agent) return 2;
    if (l.session.stillWorking) return 1;
    return 0;
}

/// The order that picks a workstream's lead. It reads nothing that changes while both sessions run:
/// rank, then the earliest start, then the key. So the same live sessions always give the same lead.
static NSComparisonResult LinkOrder(MMLink *a, MMLink *b) {
    NSInteger ra = LinkRank(a), rb = LinkRank(b);
    if (ra != rb) return ra > rb ? NSOrderedAscending : NSOrderedDescending;
    NSDate *sa = a.session.started, *sb = b.session.started;
    if (sa && sb && ![sa isEqualToDate:sb]) return [sa compare:sb];
    if (sa && !sb) return NSOrderedAscending;
    if (sb && !sa) return NSOrderedDescending;
    return [a.linkKey compare:b.linkKey];
}

static NSString *AgeBucket(NSDate *when, NSDate *now) {
    if (!when) return @"-";
    NSTimeInterval age = [now timeIntervalSinceDate:when];
    return age < 15 * 60 ? @"0" : age < 2 * 3600 ? @"1" : age < 86400 ? @"2" : @"3";
}

/// Powers of four from 1 MB, so small changes in size do not move the fingerprint.
static NSString *SizeBucket(uint64_t bytes) {
    if (bytes < (1ull << 20)) return @"0";
    int b = 0;
    for (uint64_t v = bytes >> 20; v >= 4; v >>= 2) b++;
    return [NSString stringWithFormat:@"%d", b + 1];
}

@implementation MMSnapshot

+ (NSArray<MMLink *> *)linksIn:(MMFacts *)facts {
    MMSample *s = facts.sample;
    NSMutableDictionary<NSString *, MMAgent *> *agentBySession = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, MMAgent *> *agentByPid = [NSMutableDictionary new];
    for (MMAgent *a in facts.agents) {
        if (a.sessionID.length && !agentBySession[a.sessionID]) agentBySession[a.sessionID] = a;
        agentByPid[@(a.key.pid)] = a;
    }
    NSMutableArray<MMLink *> *links = [NSMutableArray new];
    NSMutableSet<NSNumber *> *usedAgents = [NSMutableSet new];
    for (MMSession *x in facts.sessions) {
        MMAgent *a = (x.sessionID.length ? agentBySession[x.sessionID] : nil) ?: (x.pid > 0 ? agentByPid[@(x.pid)] : nil);
        BOOL running = x.pid > 0 && [s proc:x.pid] != nil;
        if (!a && !running && !x.stillWorking) continue;   // an ended session owns nothing
        MMLink *l = [MMLink new];
        l.session = x; l.agent = a;
        l.cwd = x.cwd.length ? x.cwd : a.cwd;
        l.linkKey = x.sessionID.length ? x.sessionID : [NSString stringWithFormat:@"%@@%@", x.agent, l.cwd];
        if (a) [usedAgents addObject:@(a.key.pid)];
        [links addObject:l];
    }
    // An agent with no session record, such as one whose harness keeps none, still links its folder.
    for (MMAgent *a in facts.agents) {
        if ([usedAgents containsObject:@(a.key.pid)]) continue;
        MMLink *l = [MMLink new];
        l.agent = a; l.cwd = a.cwd;
        l.linkKey = a.sessionID.length ? a.sessionID : [NSString stringWithFormat:@"%@@%@", a.harnessID, a.cwd];
        [links addObject:l];
    }
    return links;
}

/// Groups live sessions into workstreams and records the owner of each worktree and each agent pid.
+ (void)linkWorkstreams:(MMBuild *)b {
    NSArray<MMLink *> *links = [self linksIn:b.facts];
    NSMutableDictionary<NSString *, NSMutableArray<MMLink *> *> *byFolder = [NSMutableDictionary new];
    for (MMLink *l in links) {
        l.worktree = [b treeAt:l.cwd];
        NSString *folder = l.worktree ? l.worktree.path : [@"session:" stringByAppendingString:l.linkKey];
        if (!byFolder[folder]) byFolder[folder] = [NSMutableArray new];
        [byFolder[folder] addObject:l];
    }
    for (NSString *folder in [byFolder.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<MMLink *> *group = [byFolder[folder] sortedArrayUsingComparator:^NSComparisonResult(MMLink *x, MMLink *y) { return LinkOrder(x, y); }];
        MMLink *lead = group.firstObject;
        MMWorkstream *w = [MMWorkstream new];
        w.session = lead.session; w.agent = lead.agent; w.worktree = lead.worktree;
        w.agentState = lead.agent ? lead.agent.state : (lead.session.stillWorking ? MMAgentWorking : MMAgentUnknown);
        if (lead.worktree) {
            w.folder = lead.worktree.path;
            w.git = [b.facts gitFor:lead.worktree];
            w.owner = [b owner:MMOwnerWorkstream key:lead.worktree.path name:lead.worktree.path.lastPathComponent
                          path:lead.worktree.path parent:nil];
            b.ownerOfTree[lead.worktree.path] = w.owner;
        } else {
            w.folder = lead.cwd;
            NSString *name = lead.session.title.length ? lead.session.title : (lead.cwd.lastPathComponent ?: lead.linkKey);
            w.owner = [b owner:MMOwnerSession key:lead.linkKey name:name path:lead.cwd parent:nil];
        }
        for (MMLink *l in group) {
            // A second session in the same worktree is its own owner under the workstream.
            MMOwner *o = l == lead ? w.owner
                : [b owner:MMOwnerSession key:l.linkKey name:(l.session.title.length ? l.session.title : l.linkKey)
                      path:l.cwd parent:w.owner];
            // Processes under the agent, or under the session's own process when no agent row matched, go to o.
            pid_t pid = l.agent ? l.agent.key.pid : l.session.pid;
            if (pid > 1 && !b.ownerOfAgentPid[@(pid)]) b.ownerOfAgentPid[@(pid)] = o;
        }
        [b.streams addObject:w];
    }
}

/// Rule 1 for one path: the workstream of the deepest worktree that holds it, or the worktree itself.
+ (MMOwner *)treeOwnerFor:(NSString *)path build:(MMBuild *)b {
    MMWorktree *t = [b treeAt:path];
    if (!t) return nil;
    MMOwner *o = b.ownerOfTree[t.path];
    if (o) return o;
    return [b owner:MMOwnerWorktree key:t.path name:t.path.lastPathComponent path:t.path parent:nil];
}

+ (MMOwner *)ownerOf:(MMFinding *)f build:(MMBuild *)b {
    MMSample *s = b.facts.sample;
    MMProc *first = nil;
    for (NSValue *v in f.procs) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        if ((first = LiveProc(s, k))) break;
    }
    NSString *cwd = first ? [s cwdOf:first.pid] : nil;
    // 1. Worktrees.
    for (NSString *p in @[f.ownerPath ?: @"", f.path ?: @"", cwd ?: @""]) {
        MMOwner *o = p.length ? [self treeOwnerFor:p build:b] : nil;
        if (o) return o;
    }
    // 2. The nearest agent above a process.
    for (NSValue *v in f.procs) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        if (!LiveProc(s, k)) continue;
        MMOwner *o = b.ownerOfAgentPid[@(k.pid)];
        if (o) return o;
        for (NSNumber *a in [s ancestorsOf:k.pid limit:kAncestorHops])
            if ((o = b.ownerOfAgentPid[a])) return o;
    }
    // 3. The expert's hint, made canonical so equal owners are one object.
    if (f.owner) return [b owner:f.owner.kind key:f.owner.key name:f.owner.name path:f.owner.path parent:f.owner.parent];
    // 4. A folder outside every worktree.
    NSString *folder = f.ownerPath.length ? f.ownerPath : f.path.length ? f.path : cwd;
    if (folder.length && ![folder isEqualToString:@"/"])
        return [b owner:MMOwnerProject key:folder name:folder.lastPathComponent path:folder parent:nil];
    // 5. The top process below launchd.
    if (first) {
        pid_t top = first.pid;
        for (NSNumber *a in [s ancestorsOf:first.pid limit:kAncestorHops]) if (a.intValue > 1) top = a.intValue;
        NSString *name = [s proc:top].name ?: first.name;
        if (name.length) return [b owner:MMOwnerApp key:name name:name path:nil parent:nil];
    }
    // 6. Nothing to go on.
    return [b owner:MMOwnerProject key:@"" name:@"Unknown" path:nil parent:nil];
}

+ (MMSnapshot *)snapshotFrom:(MMFacts *)facts experts:(NSArray<id<MMExpert>> *)experts
                     reviews:(NSDictionary<NSString *, MMReview *> *)reviews holds:(NSDictionary<NSString *, NSString *> *)holds {
    MMBuild *b = [MMBuild new];
    b.facts = facts;
    b.owners = [NSMutableDictionary new];
    b.ownerOfTree = [NSMutableDictionary new];
    b.ownerOfAgentPid = [NSMutableDictionary new];
    b.streams = [NSMutableArray new];
    NSMutableArray<MMWorktree *> *trees = [NSMutableArray new];
    for (MMWorktree *w in facts.worktrees) if (w.path.length && !w.missing) [trees addObject:w];
    // Deepest first, then by path, so a nested checkout wins and the order never depends on the input.
    [trees sortUsingComparator:^NSComparisonResult(MMWorktree *x, MMWorktree *y) {
        if (x.path.length != y.path.length) return x.path.length > y.path.length ? NSOrderedAscending : NSOrderedDescending;
        return [x.path compare:y.path];
    }];
    b.trees = trees;
    [self linkWorkstreams:b];

    // Findings in expert order, then each expert's own order. The first of two equal ids stays.
    NSMutableArray<MMFinding *> *all = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMFinding *> *byID = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSMutableArray *> *byExpert = [NSMutableDictionary new];
    for (id<MMExpert> e in experts) {
        NSMutableArray *mine = [NSMutableArray new];
        byExpert[e.expertID ?: @""] = mine;
        for (MMFinding *raw in [e findingsFrom:facts]) {
            if (byID[raw.findingID]) continue;
            MMFinding *f = [raw withOwner:[self ownerOf:raw build:b]];
            byID[f.findingID] = f;
            [all addObject:f];
            [mine addObject:f];
        }
    }

    NSDate *now = facts.sample.at ?: [NSDate date];
    NSInteger working = 0;
    for (MMAgent *a in facts.agents) if (a.state == MMAgentWorking) working++;
    for (MMWorkstream *w in b.streams) {
        NSMutableArray *fs = [NSMutableArray new];
        // A clutter item can also be a finding, so the size is the larger of the two sums, never both.
        uint64_t found = 0, items = 0;
        for (MMFinding *f in all) if ([f.owner isWithin:w.owner]) { [fs addObject:f]; found += f.cost.diskFreed; }
        NSMutableArray *cl = [NSMutableArray new];
        for (MMClutterItem *c in facts.clutter)
            if (PathIn(c.ownerPath.length ? c.ownerPath : c.path, w.folder)) { [cl addObject:c]; items += c.size.freedIfDeleted; }
        uint64_t bytes = MAX(found, items);
        w.findings = [fs copy];
        w.clutter = [cl copy];
        w.fingerprintText = [NSString stringWithFormat:@"%@|%ld%@|%@", w.git.head ?: @"-", (long)w.agentState,
                             AgeBucket(w.session.lastActive, now), SizeBucket(bytes)];
    }

    NSMutableDictionary *alive = [NSMutableDictionary new];
    [holds enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *reason, BOOL *stop) {
        NSArray *parts = [key componentsSeparatedByString:@":"];
        MMProcKey k = { (pid_t)[parts.firstObject intValue], (uint64_t)[parts.lastObject longLongValue] };
        if (parts.count == 2 && LiveProc(facts.sample, k)) alive[key] = reason;
    }];

    MMSnapshot *snap = [MMSnapshot new];
    snap.generation = facts.generation;
    snap.builtAt = [NSDate date];
    snap.facts = facts;
    snap.workstreams = [b.streams copy];
    snap.findings = [all copy];
    snap.byID = [byID copy];
    NSMutableDictionary *frozen = [NSMutableDictionary new];
    [byExpert enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSMutableArray *v, BOOL *stop) { frozen[k] = [v copy]; }];
    snap.byExpert = [frozen copy];
    snap.reviews = [reviews copy] ?: @{};
    snap.awakeHolds = [alive copy];
    snap.working = working;
    return snap;
}

- (NSArray<MMFinding *> *)findingsFor:(NSString *)expert { return self.byExpert[expert] ?: @[]; }
- (MMFinding *)finding:(NSString *)findingID { return findingID ? self.byID[findingID] : nil; }

- (MMWorkstream *)workstreamAt:(NSString *)path {
    MMWorkstream *best = nil;
    for (MMWorkstream *w in self.workstreams)
        if (PathIn(path, w.folder) && w.folder.length > best.folder.length) best = w;
    return best;
}

- (NSArray<MMFinding *> *)findingsOwnedBy:(MMOwner *)owner expert:(NSString *)expert {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in expert ? [self findingsFor:expert] : self.findings) if ([f.owner isWithin:owner]) [out addObject:f];
    return [out copy];
}

- (NSInteger)workingAgents { return self.working; }
- (MMReview *)reviewFor:(NSString *)expert { return expert ? self.reviews[expert] : nil; }

@end

#pragma mark - Graph

@interface MMGraph ()
@property (readwrite, atomic) MMSnapshot *latest;
@end

@implementation MMGraph {
    dispatch_queue_t _queue;
    atomic_bool _pending;                               // a rebuild is queued and has not started
    NSArray<id<MMExpert>> *_experts;                    // set on main before -start, read on the graph queue
    uint64_t _generation;                               // graph queue only
    NSMutableDictionary<NSString *, NSString *> *_holds;        // graph queue only
    NSMutableDictionary<NSString *, MMReview *> *_reviews;      // graph queue only
    MMSnapshot *_current;                               // main only
    NSMutableDictionary<NSNumber *, void (^)(MMSnapshot *)> *_observers;   // main only
    NSUInteger _nextToken;
}

+ (instancetype)shared {
    static MMGraph *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [MMGraph new]; });
    return g;
}

- (instancetype)init {
    if ((self = [super init])) {
        // The label MMQueue(@"core", @"graph", ...) gives. This file makes its own queue so it links before Runtime lands.
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL,
                                                                                         DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
        attr = dispatch_queue_attr_make_with_qos_class(attr, QOS_CLASS_UTILITY, 0);
        _queue = dispatch_queue_create("no.guerrilla.minmacs.core.graph", attr);
        _experts = @[];
        _holds = [NSMutableDictionary new];
        _reviews = [NSMutableDictionary new];
        _observers = [NSMutableDictionary new];
        atomic_init(&_pending, false);
    }
    return self;
}

- (void)addExpert:(id<MMExpert>)expert {
    if (!expert) return;
    @synchronized (self) { _experts = [_experts arrayByAddingObject:expert]; }
}

- (NSArray<id<MMExpert>> *)experts { @synchronized (self) { return _experts; } }

- (void)start { [self rebuild:@"start"]; }

- (void)rebuild:(NSString *)why {
    if (atomic_exchange(&_pending, true)) return;       // one is queued already; it will see these facts too
    dispatch_async(_queue, ^{
        atomic_store(&self->_pending, false);           // a signal from now on asks for one more build
        [self buildNow];
    });
}

/// One build. Graph queue only.
- (void)buildNow {
    id<MMFactSource> source = self.source;
    if (!source) return;
    uint64_t gen = ++_generation;
    MMFacts *facts = [source factsFor:gen];
    if (!facts) return;
    if (facts.generation != gen)                        // the generation is the graph's count, never the source's
        facts = [MMFacts generation:gen sample:facts.sample power:facts.power agents:facts.agents sessions:facts.sessions
                          worktrees:facts.worktrees clutter:facts.clutter git:[self gitOf:facts]];
    MMSnapshot *snap = [MMSnapshot snapshotFrom:facts experts:self.experts reviews:_reviews holds:_holds];
    [_holds setDictionary:snap.awakeHolds];             // holds whose process exited are dropped
    self.latest = snap;
    dispatch_async(dispatch_get_main_queue(), ^{ [self publish:snap]; });
}

- (NSDictionary *)gitOf:(MMFacts *)facts {
    NSMutableDictionary *g = [NSMutableDictionary new];
    for (MMWorktree *w in facts.worktrees) { MMGitFacts *x = [facts gitFor:w]; if (x && w.path) g[w.path] = x; }
    return g;
}

/// Main only. Builds run in order on one queue, so an older snapshot never arrives after a newer one.
/// The check stays in case that ever changes.
- (void)publish:(MMSnapshot *)snap {
    if (_current && snap.generation <= _current.generation) return;
    _current = snap;
    for (NSNumber *t in [_observers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        void (^block)(MMSnapshot *) = _observers[t];
        if (block) block(snap);
    }
}

- (MMSnapshot *)current { return _current; }

- (id)observe:(void (^)(MMSnapshot *snapshot))block {
    NSNumber *token = @(++_nextToken);
    _observers[token] = [block copy];
    return token;
}

- (void)stopObserving:(id)token { if (token) [_observers removeObjectForKey:token]; }

- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    if (NSThread.isMainThread) return nil;              // it blocks, so main never calls it
    return [self.source freshFactsFor:finding];
}

- (void)holdAwake:(NSString *)reason pid:(MMProcKey)key {
    NSString *k = ProcKeyString(key), *r = [reason copy] ?: @"";
    // The rebuild is asked from the graph queue, after the hold is in, so the build it starts sees the hold.
    dispatch_async(_queue, ^{ self->_holds[k] = r; [self rebuild:@"hold awake"]; });
}

- (void)saveReview:(MMReview *)review forExpert:(NSString *)expert {
    if (!expert) return;
    NSString *e = [expert copy];
    dispatch_async(_queue, ^{
        if (review) self->_reviews[e] = review; else [self->_reviews removeObjectForKey:e];
        [self rebuild:@"review saved"];
    });
}

@end
