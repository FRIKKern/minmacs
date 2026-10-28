// The graph builder: workstreams, owners and the one published snapshot. Issue #16, patterns P31 to P33.
//
// Threads. Every build runs on the serial queue MMQueue(@"core", @"graph"), no.guerrilla.minmacs.core.graph. A finished snapshot goes to
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
// Like MMFinding.m, this file sends messages to Senses and Know objects and never names their classes,
// so tests can hand it facts built from objects of their own.
#import "Core/Graph/MMGraph.h"
#import "Core/MMExpert.h"
#import "Core/Runtime/MMRuntime.h"
#import <stdatomic.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <os/signpost.h>
#import <time.h>

static const NSUInteger kAncestorHops = 20;
static const uint64_t kHeartbeatNs = 30ull * NSEC_PER_SEC;   // a new sample builds at least this often

#pragma mark - Costs, issue #52

/// The tick's signposts, in the same subsystem and category as the Senses pass.
static os_log_t TickLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "tick"); });
    return log;
}
static uint64_t ThreadNs(void) { return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID); }

static os_unfair_lock gCostLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *gCosts;
static void AddCost(NSString *key, uint64_t value) {
    os_unfair_lock_lock(&gCostLock);
    if (!gCosts) gCosts = [NSMutableDictionary new];
    gCosts[key] = @([gCosts[key] unsignedLongLongValue] + value);
    os_unfair_lock_unlock(&gCostLock);
}

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

#pragma mark - The facts digest, issue #52

/// A 64-bit mix, so a sum of mixed values does not depend on the order things are listed in.
static uint64_t Mix(uint64_t x) {
    x ^= x >> 33; x *= 0xff51afd7ed558ccdull; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ull; x ^= x >> 33;
    return x;
}
static uint64_t MixObj(id o) { return Mix((uint64_t)(uintptr_t)(__bridge void *)o); }
static uint64_t MixAll(NSArray *a) { uint64_t h = a.count; for (id o in a) h += Mix(MixObj(o) ^ 0x2545f491); return h; }
static uint64_t MixStr(NSString *s) { return s ? Mix(s.hash ^ ((uint64_t)s.length << 40)) : 0x5bd1e995ull; }

/// CPU in the bands a reader can tell apart: idle, a little, some, busy, very busy. A process that moves inside a
/// band does not move the digest.
static uint64_t CPUBand(double cpu) {
    if (cpu < 0) return 7;
    return cpu < 1 ? 0 : cpu < 5 ? 1 : cpu < 15 ? 2 : cpu < 40 ? 3 : cpu < 100 ? 4 : 5;
}
/// Memory in steps of 16 MB.
static uint64_t MemBand(uint64_t bytes) { return bytes >> 24; }

/// What the experts and the owner rules read from one set of facts, at the precision a menu shows it.
/// The sample: every process's pid, start, parent, name, CPU band and memory band, and the socket table.
/// Power and pressure, every agent's state, and the identity of the session, worktree, git and clutter
/// objects, which Know replaces only when they changed. Two facts with the same digest give the same findings,
/// except for CPU and memory inside a band and for ages, which the heartbeat rebuild catches.
/// Facts built by hand in a test may hold objects that answer only some messages, so each class is asked once.
typedef struct { Class cls; BOOL ok; } MMDigestClass;
static BOOL Answers(id o, SEL const *sels, size_t n, MMDigestClass *seen) {
    Class c = object_getClass(o);
    if (c == seen->cls) return seen->ok;
    BOOL ok = YES;
    for (size_t i = 0; i < n && ok; i++) ok = [o respondsToSelector:sels[i]];
    seen->cls = c; seen->ok = ok;
    return ok;
}

static uint64_t FactsDigest(MMFacts *f) {
    uint64_t h = 0, i = 1;
    MMSample *s = f.sample;
    uid_t me = getuid();
    static SEL procSels[7];
    static SEL agentSels[8];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL ps[7] = { @selector(pid), @selector(ppid), @selector(uid), @selector(startSec), @selector(name),
                      @selector(cpuPercent), @selector(footprint) };
        SEL as[8] = { @selector(key), @selector(state), @selector(signal), @selector(sessionID), @selector(cwd),
                      @selector(treeCPU), @selector(treeFootprint), @selector(hosted) };
        memcpy(procSels, ps, sizeof ps); memcpy(agentSels, as, sizeof as);
    });
    MMDigestClass pc = { Nil, NO }, ac = { Nil, NO };
    for (MMProc *p in s.procs.objectEnumerator) {
        if (!Answers(p, procSels, 7, &pc)) { h += Mix(MixObj(p)); continue; }
        if (p.uid != me && p.pid != 1) continue;   // no expert reads another user's processes, which Senses cannot measure
        h += Mix(((uint64_t)p.pid << 32) ^ (uint64_t)p.ppid ^ Mix(p.startSec) ^ MixStr(p.name) ^
                 (CPUBand(p.cpuPercent) << 56) ^ Mix(MemBand(p.footprint) + 0x9e37));
    }
    if ([(NSObject *)s respondsToSelector:@selector(sockets:)]) {
        NSUInteger n = 0;
        const MMSocket *sv = [s sockets:&n];
        for (NSUInteger k = 0; sv && k < n; k++) {
            const uint8_t *b = (const uint8_t *)(const void *)&sv[k];
            uint64_t x = 0xcbf29ce484222325ull;                 // FNV-1a over the socket's bytes
            for (size_t j = 0; j < sizeof(MMSocket); j++) { x ^= b[j]; x *= 0x100000001b3ull; }
            h += Mix(x);
        }
    }
    MMPower *pw = f.power;
    static SEL powerSels[11];
    static dispatch_once_t powerOnce;
    dispatch_once(&powerOnce, ^{
        SEL ws[11] = { @selector(onAC), @selector(lidClosed), @selector(lowPowerMode), @selector(lidOverride), @selector(online),
                       @selector(batteryPercent), @selector(thermal), @selector(memoryPressure), @selector(diskFree),
                       @selector(assertionsByPid), @selector(at) };
        memcpy(powerSels, ws, sizeof ws);
    });
    MMDigestClass wc = { Nil, NO };
    if (pw && Answers(pw, powerSels, 11, &wc)) {
        h ^= Mix(++i * ((uint64_t)pw.onAC | (uint64_t)pw.lidClosed << 1 | (uint64_t)pw.lowPowerMode << 2 |
                        (uint64_t)pw.lidOverride << 3 | (uint64_t)pw.online << 4 | (uint64_t)(pw.batteryPercent + 1) << 8 |
                        (uint64_t)pw.thermal << 16 | (uint64_t)pw.memoryPressure << 24 | (pw.diskFree >> 30) << 32));
        uint64_t a = 0;
        for (NSNumber *pid in pw.assertionsByPid)
            for (NSDictionary *x in pw.assertionsByPid[pid])
                a += Mix(pid.unsignedLongLongValue ^ MixStr([x isKindOfClass:NSDictionary.class] ? [x[@"AssertName"] description] : nil));
        h ^= Mix(a + ++i);
    } else if (pw) {
        h ^= Mix(MixObj(pw) + ++i);
    }
    uint64_t ag = 0;
    for (MMAgent *a in f.agents) {
        if (!Answers(a, agentSels, 8, &ac)) { ag += Mix(MixObj(a)); continue; }
        uint64_t x = Mix(((uint64_t)a.key.pid << 32) ^ a.key.startSec) ^ Mix((uint64_t)a.state << 8 | (uint64_t)a.signal) ^
                     MixStr(a.sessionID) ^ MixStr(a.cwd) ^ Mix(CPUBand(a.treeCPU) << 20 | MemBand(a.treeFootprint) << 24);
        for (MMAgent *o in a.hosted) x ^= Mix(MixObj(o));
        ag += Mix(x);
    }
    h ^= Mix(ag + ++i);
    // Know replaces a session, worktree, git fact or clutter item with a new object when it changes, and its arrays
    // may be copied on the way, so each element's identity is summed in its place.
    h ^= Mix(MixAll(f.sessions) + ++i);
    h ^= Mix(MixAll(f.worktrees) + ++i);
    h ^= Mix(MixAll(f.clutter) + ++i);
    uint64_t g = 0;
    for (MMWorktree *w in f.worktrees) g += MixObj([f gitFor:w]);
    h ^= Mix(g + ++i);
    return h;
}

#pragma mark - Reused findings, issue #52

/// Stands in for one expert in a build. It hands out the findings it was given, or asks the expert and keeps what
/// came back. Every other message goes to the expert.
@interface MMFindingsReuse : NSProxy
@property (strong) id<MMExpert> expert;
@property (strong) NSArray<MMFinding *> *findings;      // set to reuse, filled after a call otherwise
@property BOOL reused;
@end

@implementation MMFindingsReuse
- (NSString *)expertID { return self.expert.expertID; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    if (self.reused) return self.findings;
    self.findings = [self.expert findingsFrom:facts] ?: @[];
    return self.findings;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject *)self.expert methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)inv { [inv invokeWithTarget:self.expert]; }
- (BOOL)respondsToSelector:(SEL)sel { return [self.expert respondsToSelector:sel]; }
- (BOOL)conformsToProtocol:(Protocol *)p { return [self.expert conformsToProtocol:p]; }
@end

/// What the graph kept of one expert's last findings.
@interface MMKeptFindings : NSObject
@property uint64_t digest, atNs;
@property (strong) NSArray<MMFinding *> *findings;
@end
@implementation MMKeptFindings
@end

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
@property NSDictionary<NSString *, id> *prepared;
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
    NSComparisonResult byKey = [a.linkKey compare:b.linkKey];
    if (byKey != NSOrderedSame) return byKey;
    // Two agents with no session record in one folder share a key. Their processes decide.
    MMProcKey ka = a.agent.key, kb = b.agent.key;
    if (ka.startSec != kb.startSec) return ka.startSec < kb.startSec ? NSOrderedAscending : NSOrderedDescending;
    return ka.pid < kb.pid ? NSOrderedAscending : ka.pid > kb.pid ? NSOrderedDescending : NSOrderedSame;
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
        NSString *eid = e.expertID ?: @"";
        byExpert[eid] = mine;
        os_signpost_id_t sp = os_signpost_id_generate(TickLog());
        os_signpost_interval_begin(TickLog(), sp, "findings", "%{public}@", eid);
        uint64_t c0 = ThreadNs();
        NSArray<MMFinding *> *raws = [e findingsFrom:facts];
        AddCost([@"findings." stringByAppendingString:eid], ThreadNs() - c0);
        os_signpost_interval_end(TickLog(), sp, "findings", "%{public}@ %lu", eid, (unsigned long)raws.count);
        for (MMFinding *raw in raws) {
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

- (id)preparedFor:(NSString *)expert { return expert ? self.prepared[expert] : nil; }

- (void)prepareFor:(NSArray<id<MMExpert>> *)experts {
    if (self.prepared) return;
    NSMutableDictionary *p = [NSMutableDictionary new];
    for (id<MMExpert> e in experts) {
        if (![e respondsToSelector:@selector(prepareFor:)] || !e.expertID) continue;
        id v = [e prepareFor:self];
        if (v) p[e.expertID] = v;
    }
    self.prepared = [p copy];
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
    BOOL _stopped;                                      // under @synchronized (self): -stop was called after -start
    atomic_bool _forced;                                // a rebuild asked for a reason other than a new sample
    uint64_t _lastDigest;                               // graph queue only: the digest of the last build's facts
    uint64_t _lastBuiltNs;                              // graph queue only
    NSMutableDictionary<NSString *, MMKeptFindings *> *_kept;   // graph queue only: each expert's last findings
    NSArray<id<MMExpert>> *_experts;                    // set on main before -start, read on the graph queue
    uint64_t _generation;                               // graph queue only
    NSMutableDictionary<NSString *, NSString *> *_holds;        // graph queue only
    NSMutableDictionary<NSString *, NSDate *> *_holdSince;      // graph queue only, when each hold came in
    NSMutableDictionary<NSString *, MMReview *> *_reviews;      // graph queue only
    MMSnapshot *_current;                               // main only
    NSMutableDictionary<NSNumber *, void (^)(MMSnapshot *)> *_observers;   // under @synchronized (_observers)
    NSUInteger _nextToken;                              // under @synchronized (_observers)
}

+ (instancetype)shared {
    static MMGraph *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [MMGraph new]; });
    return g;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = MMQueue(@"core", @"graph", QOS_CLASS_UTILITY);
        _experts = @[];
        _holds = [NSMutableDictionary new];
        _holdSince = [NSMutableDictionary new];
        _reviews = [NSMutableDictionary new];
        _observers = [NSMutableDictionary new];
        _kept = [NSMutableDictionary new];
        atomic_init(&_pending, false);
        atomic_init(&_forced, true);
    }
    return self;
}

- (void)addExpert:(id<MMExpert>)expert {
    if (!expert) return;
    @synchronized (self) { _experts = [_experts arrayByAddingObject:expert]; }
}

- (NSArray<id<MMExpert>> *)experts { @synchronized (self) { return _experts; } }

- (void)start {
    @synchronized (self) { _stopped = NO; }
    [self rebuild:@"start"];
}

- (void)stop { @synchronized (self) { _stopped = YES; } }

- (BOOL)stopped { @synchronized (self) { return _stopped; } }

- (void)rebuild:(NSString *)why {
    if (self.stopped) return;
    // Only a new sample may find nothing changed. Every other reason, an exit, an app, a power change, Know or an
    // action, always builds.
    if (![why isEqualToString:@"sample"]) atomic_store(&_forced, true);
    if (atomic_exchange(&_pending, true)) return;       // one is queued already; it will see these facts too
    dispatch_async(_queue, ^{
        atomic_store(&self->_pending, false);           // a signal from now on asks for one more build
        [self buildNow];
    });
}

/// One build. Graph queue only.
- (void)buildNow {
    id<MMFactSource> source = self.source;
    if (!source || self.stopped) return;
    os_signpost_id_t sp = os_signpost_id_generate(TickLog());
    os_signpost_interval_begin(TickLog(), sp, "rebuild");
    uint64_t c0 = ThreadNs();
    BOOL forced = atomic_exchange(&_forced, false);
    uint64_t gen = _generation + 1;
    MMFacts *facts = [source factsFor:gen];
    uint64_t c1 = ThreadNs();
    AddCost(@"facts", c1 - c0);
    if (!facts) { os_signpost_interval_end(TickLog(), sp, "rebuild", "no facts"); return; }
    // Issue #52. A new sample whose facts match the last build's, at the precision the menus show, keeps the last
    // snapshot. A build at least every heartbeat moves ages and the CPU and memory inside a band.
    uint64_t digest = FactsDigest(facts), nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    BOOL same = !forced && self.latest && digest == _lastDigest && nowNs - _lastBuiltNs < kHeartbeatNs;
    AddCost(@"digest", ThreadNs() - c1);
    if (same) {
        AddCost(@"skipped", 1);
        os_signpost_interval_end(TickLog(), sp, "rebuild", "skipped: the facts did not change");
        return;
    }
    _lastDigest = digest; _lastBuiltNs = nowNs;
    _generation = gen;
    c1 = ThreadNs();
    if (facts.generation != gen)                        // the generation is the graph's count, never the source's
        facts = [MMFacts generation:gen sample:facts.sample power:facts.power agents:facts.agents sessions:facts.sessions
                          worktrees:facts.worktrees clutter:facts.clutter git:[self gitOf:facts]];
    // Each expert whose inputs did not change hands back its last findings. A forced build asks every expert.
    NSMutableArray *experts = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSNumber *> *digests = [NSMutableDictionary new];
    for (id<MMExpert> e in self.experts) {
        NSString *eid = e.expertID ?: @"";
        MMFindingsReuse *r = [MMFindingsReuse alloc];
        r.expert = e;
        if ([e respondsToSelector:@selector(inputDigestFrom:)]) {
            uint64_t d0 = ThreadNs();
            uint64_t d = [e inputDigestFrom:facts];
            AddCost([@"digest." stringByAppendingString:eid], ThreadNs() - d0);
            digests[eid] = @(d);
            MMKeptFindings *k = _kept[eid];
            if (!forced && k.findings && k.digest == d && nowNs - k.atNs < kHeartbeatNs) {
                r.findings = k.findings; r.reused = YES;
                AddCost([@"reused." stringByAppendingString:eid], 1);
            }
        }
        [experts addObject:r];
    }
    MMSnapshot *snap = [MMSnapshot snapshotFrom:facts experts:(NSArray<id<MMExpert>> *)experts reviews:_reviews holds:_holds];
    for (MMFindingsReuse *r in experts) {
        NSString *eid = r.expertID ?: @"";
        if (r.reused || !digests[eid]) { if (!digests[eid]) [_kept removeObjectForKey:eid]; continue; }
        MMKeptFindings *k = [MMKeptFindings new];
        k.digest = digests[eid].unsignedLongLongValue; k.atNs = nowNs; k.findings = r.findings;
        _kept[eid] = k;
    }
    // A hold whose process the sample lacks is dropped only when the sample was taken after the hold.
    // An older sample cannot know a process that started a moment ago.
    NSDate *sampledAt = facts.sample.at;
    NSMutableDictionary *kept = [snap.awakeHolds mutableCopy];
    for (NSString *k in _holds)
        if (!kept[k] && (!sampledAt || [sampledAt compare:_holdSince[k]] == NSOrderedAscending)) kept[k] = _holds[k];
    snap.awakeHolds = [kept copy];
    [_holds setDictionary:kept];
    for (NSString *k in _holdSince.allKeys) if (!kept[k]) [_holdSince removeObjectForKey:k];
    // What each menu reads, made here so main never reads the keeps, rules, prefs or undo log.
    [snap prepareFor:self.experts];
    // A build that was running when -stop came publishes nothing. The check and the store share -stop's lock,
    // so once -stop returns no snapshot lands.
    @synchronized (self) {
        if (_stopped) return;
        self.latest = snap;
    }
    AddCost(@"snapshot", ThreadNs() - c1);
    AddCost(@"builds", 1);
    os_signpost_interval_end(TickLog(), sp, "rebuild", "generation %llu, %lu findings", gen, (unsigned long)snap.findings.count);
    dispatch_async(dispatch_get_main_queue(), ^{
        uint64_t m0 = ThreadNs();
        [self publish:snap];
        AddCost(@"publish", ThreadNs() - m0);
    });
}

- (NSDictionary<NSString *, NSNumber *> *)costs {
    os_unfair_lock_lock(&gCostLock);
    NSDictionary *c = [gCosts copy] ?: @{};
    os_unfair_lock_unlock(&gCostLock);
    return c;
}

- (NSDictionary *)gitOf:(MMFacts *)facts {
    NSMutableDictionary *g = [NSMutableDictionary new];
    for (MMWorktree *w in facts.worktrees) { MMGitFacts *x = [facts gitFor:w]; if (x && w.path) g[w.path] = x; }
    return g;
}

/// Main only. Builds run in order on one queue, so an older snapshot never arrives after a newer one.
/// The check stays in case that ever changes.
- (void)publish:(MMSnapshot *)snap {
    if (self.stopped) return;
    if (_current && snap.generation <= _current.generation) return;
    _current = snap;
    NSArray<NSNumber *> *tokens;
    @synchronized (_observers) { tokens = [_observers.allKeys sortedArrayUsingSelector:@selector(compare:)]; }
    for (NSNumber *t in tokens) {
        void (^block)(MMSnapshot *);
        // Looked up again, so an observer that stopped while an earlier one ran is not called.
        @synchronized (_observers) { block = _observers[t]; }
        if (block) block(snap);
    }
}

- (MMSnapshot *)current { return _current; }

- (id)observe:(void (^)(MMSnapshot *snapshot))block {
    if (!block) return nil;
    @synchronized (_observers) {
        NSNumber *token = @(++_nextToken);
        _observers[token] = [block copy];
        return token;
    }
}

- (void)stopObserving:(id)token {
    if (!token) return;
    @synchronized (_observers) { [_observers removeObjectForKey:token]; }
}

- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    if (NSThread.isMainThread) return nil;              // it blocks, so main never calls it
    return [self.source freshFactsFor:finding];
}

- (void)holdAwake:(NSString *)reason pid:(MMProcKey)key {
    NSString *k = ProcKeyString(key), *r = [reason copy] ?: @"";
    // The rebuild is asked from the graph queue, after the hold is in, so the build it starts sees the hold.
    NSDate *at = [NSDate date];
    dispatch_async(_queue, ^{ self->_holds[k] = r; self->_holdSince[k] = at; [self rebuild:@"hold awake"]; });
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
