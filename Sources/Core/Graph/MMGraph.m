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
#import "Core/Graph/MMHistory.h"
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

/// YES when path is folder or inside it. No string is made: a build asks this for every finding against every worktree.
static BOOL PathIn(NSString *path, NSString *folder) {
    if (!path.length || !folder.length || ![path hasPrefix:folder]) return NO;
    return path.length == folder.length || [folder hasSuffix:@"/"] || [path characterAtIndex:folder.length] == '/';
}

/// folder without its trailing slashes, "/" kept.
static NSString *NoSlash(NSString *folder) {
    while (folder.length > 1 && [folder hasSuffix:@"/"]) folder = [folder substringToIndex:folder.length - 1];
    return folder;
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

static uint64_t KnowDigest(MMFacts *f, BOOL sessionFields);
static NSString *AgeBucket(NSDate *when, NSDate *now);
static uint64_t FactsDigest(MMFacts *f) {
    uint64_t h = 0;
    MMSample *s = f.sample;
    uid_t me = getuid();
    static SEL procSels[7];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL ps[7] = { @selector(pid), @selector(ppid), @selector(uid), @selector(startSec), @selector(name),
                      @selector(cpuPercent), @selector(footprint) };
        memcpy(procSels, ps, sizeof ps);
    });
    MMDigestClass pc = { Nil, NO };
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
    return h + KnowDigest(f, NO);
}

/// The facts digest's part that is not the process table or the sockets: power and pressure, every agent's state,
/// and the identity of the worktree, git and clutter objects. Sessions by identity, or with sessionFields by what the
/// graph reads of them: the session index makes new session objects at every read, and an agent at work moves its
/// last write every second, which only moves an age bucket of a workstream's fingerprint.
static uint64_t KnowDigest(MMFacts *f, BOOL sessionFields) {
    uint64_t h = 0, i = 1;
    MMDigestClass ac = { Nil, NO };
    static SEL agentSels[8];
    static dispatch_once_t agentOnce;
    dispatch_once(&agentOnce, ^{
        SEL as[8] = { @selector(key), @selector(state), @selector(signal), @selector(sessionID), @selector(cwd),
                      @selector(treeCPU), @selector(treeFootprint), @selector(hosted) };
        memcpy(agentSels, as, sizeof as);
    });
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
        // The free disk space in GB, or for the graph's own digest only on which side of what a snapshot's reader tells
        // apart, WorkForest's 15 GB and the Performance model's 100 GB: other work on the Mac moves it by GBs. A
        // snapshot's power facts may be up to 30 seconds old, and its readers take Senses' own when newer.
        uint64_t disk = sessionFields ? (uint64_t)(pw.diskFree < 15000000000ull) | (uint64_t)(pw.diskFree < 100000000000ull) << 1
                                      : pw.diskFree >> 30;
        h ^= Mix(++i * ((uint64_t)pw.onAC | (uint64_t)pw.lidClosed << 1 | (uint64_t)pw.lowPowerMode << 2 |
                        (uint64_t)pw.lidOverride << 3 | (uint64_t)pw.online << 4 | (uint64_t)(pw.batteryPercent + 1) << 8 |
                        (uint64_t)pw.thermal << 16 | (uint64_t)pw.memoryPressure << 24 | disk << 32));
        // The assertions are the registry's, which reads them into the agents above. No snapshot reader reads them.
        uint64_t a = 0;
        if (!sessionFields)
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
        // Its tree's CPU and memory only in the facts digest: the owner rules and workstreams read none of it, and a
        // working agent's tree moves at every pass. MinMacs's agent rows read it at the heartbeat build.
        uint64_t x = Mix(((uint64_t)a.key.pid << 32) ^ a.key.startSec) ^ Mix((uint64_t)a.state << 8 | (uint64_t)a.signal) ^
                     MixStr(a.sessionID) ^ MixStr(a.cwd) ^ (sessionFields ? 0 : Mix(CPUBand(a.treeCPU) << 20 | MemBand(a.treeFootprint) << 24));
        for (MMAgent *o in a.hosted) x ^= Mix(MixObj(o));
        ag += Mix(x);
    }
    h ^= Mix(ag + ++i);
    // Know replaces a session, worktree, git fact or clutter item with a new object when it changes, and its arrays
    // may be copied on the way, so each element's identity is summed in its place.
    if (sessionFields) {
        static SEL sessionSels[8];
        static dispatch_once_t sessionOnce;
        dispatch_once(&sessionOnce, ^{
            SEL ss[8] = { @selector(sessionID), @selector(pid), @selector(cwd), @selector(agent), @selector(title),
                          @selector(stillWorking), @selector(started), @selector(lastActive) };
            memcpy(sessionSels, ss, sizeof ss);
        });
        MMDigestClass sc = { Nil, NO };
        MMSample *sample = f.sample;
        NSDate *now = sample.at ?: [NSDate date];
        uint64_t x = f.sessions.count;
        for (MMSession *z in f.sessions) {
            if (!Answers(z, sessionSels, 8, &sc)) { x += Mix(MixObj(z)); continue; }
            BOOL running = z.pid > 0 && [sample proc:z.pid] != nil;
            x += Mix(MixStr(z.sessionID) ^ Mix(MixStr(z.cwd) + 1) ^ Mix(MixStr(z.agent) + 2) ^ Mix(MixStr(z.title) + 3) ^
                     Mix(((uint64_t)(uint32_t)z.pid << 2 | (uint64_t)running << 1 | (uint64_t)z.stillWorking) + 4) ^
                     Mix((uint64_t)(z.started.timeIntervalSince1970 * 1000) + 5) ^ Mix(MixStr(AgeBucket(z.lastActive, now)) + 6));
        }
        h ^= Mix(x + ++i);
    } else {
        h ^= Mix(MixAll(f.sessions) + ++i);
    }
    h ^= Mix(MixAll(f.worktrees) + ++i);
    h ^= Mix(MixAll(f.clutter) + ++i);
    uint64_t g = 0;
    for (MMWorktree *w in f.worktrees) g += MixObj([f gitFor:w]);
    h ^= Mix(g + ++i);
    return h;
}

/// What a build reads of facts besides what each expert's input digest covers: the Know part above, with sessions by
/// what the workstreams read, and for each finding's processes whether each still runs, the folder of the first that
/// runs and the parents above each, which pick its owner, and which processes held awake still run. When every
/// expert's digest and this one match the last build's, no part of a snapshot can come out otherwise, owners included,
/// so the graph keeps it. The rest of the process table, about 800 processes that come and go on a Mac at work, is
/// left out: no expert and no owner rule reads a process that is none of these.
static uint64_t CoreDigest(MMFacts *f, NSArray<NSArray<MMFinding *> *> *findings, NSDictionary<NSString *, NSString *> *holds) {
    uint64_t h = KnowDigest(f, YES);
    MMSample *s = f.sample;
    for (NSArray<MMFinding *> *list in findings) {
        h = Mix(h + list.count);
        for (MMFinding *x in list) {
            if (!x.procs.count) continue;
            BOOL first = YES;
            uint64_t p = 0;
            for (NSValue *v in x.procs) {
                MMProcKey k; [v getValue:&k size:sizeof k];
                MMProc *live = LiveProc(s, k);
                p = Mix(p + ((uint64_t)(uint32_t)k.pid << 32 ^ k.startSec) + (live ? 1 : 2));
                if (!live) continue;
                if (first) { p ^= Mix(MixStr([s cwdOf:k.pid]) + 3); first = NO; }
                for (NSNumber *a in [s ancestorsOf:k.pid limit:kAncestorHops]) p = Mix(p + a.unsignedLongLongValue);
            }
            h += Mix(p ^ MixObj(x));
        }
    }
    for (NSString *key in holds) {
        NSArray *parts = [key componentsSeparatedByString:@":"];
        MMProcKey k = { (pid_t)[parts.firstObject intValue], (uint64_t)[parts.lastObject longLongValue] };
        h += Mix(MixStr(key) ^ (parts.count == 2 && LiveProc(s, k) ? 7 : 8));
    }
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
/// The worktree's resolved path when it is another text than folder, else nil. Set once while the graph builds and
/// never after, so it is read with no lock: HeldBy runs once for each workstream and clutter item of a build.
@property (nonatomic, copy) NSString *realFolder;
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
@property (readwrite) MMHistoryView *history;
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
@property NSDictionary<NSString *, MMWorktree *> *treeByPath;   // trees by path without a trailing slash, made on first use
@end
@implementation MMBuild

- (MMOwner *)owner:(MMOwnerKind)kind key:(NSString *)key name:(NSString *)name path:(NSString *)path parent:(MMOwner *)parent {
    MMOwner *o = [MMOwner kind:kind key:key name:name path:path parent:parent];
    MMOwner *have = self.owners[o.ownerID];
    if (have) return have;
    self.owners[o.ownerID] = o;
    return o;
}

/// The deepest worktree that holds path. Issue #54: a lookup of path and each folder above it, where a walk over
/// every worktree took 185 of 476 samples of a build with 300 worktrees and 330 findings.
- (MMWorktree *)treeAt:(NSString *)path {
    if (!path.length) return nil;
    if (!self.treeByPath) {
        NSMutableDictionary *by = [NSMutableDictionary new];
        for (MMWorktree *w in self.trees) {
            NSString *k = NoSlash(w.path ?: @"");
            if (k.length && !by[k]) by[k] = w;   // deepest first, so the first of two equal paths stays
        }
        // Then by the resolved path the index read: a process's folder and a WorkForest finding are named by it.
        // A path as kept wins over an equal resolved one.
        for (MMWorktree *w in self.trees) {
            NSString *k = NoSlash(w.realPath ?: @"");
            if (k.length && !by[k]) by[k] = w;
        }
        self.treeByPath = by;
    }
    NSDictionary<NSString *, MMWorktree *> *by = self.treeByPath;
    MMWorktree *w = by[path];
    if (w) return w;
    // Issue #52. The answers of the last builds, while their trees are these very objects: with 650 clutter findings
    // a build walked each one's folders, about 4 ms. The repo index makes a new object for a worktree that changed.
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static NSArray *memoTrees; static NSMutableDictionary *memo;
    os_unfair_lock_lock(&lock);
    if (memoTrees != self.trees && ![memoTrees isEqualToArray:self.trees]) { memoTrees = self.trees; memo = [NSMutableDictionary new]; }
    else memoTrees = self.trees;
    id hit = memo[path];
    os_unfair_lock_unlock(&lock);
    if (hit) return hit == NSNull.null ? nil : hit;
    w = [self walkUp:path in:by];
    os_unfair_lock_lock(&lock);
    if (memoTrees == self.trees) { if (memo.count > 20000) [memo removeAllObjects]; memo[path] = w ?: NSNull.null; }
    os_unfair_lock_unlock(&lock);
    return w;
}

/// Each folder above path, deepest first: the part before each slash.
- (MMWorktree *)walkUp:(NSString *)path in:(NSDictionary<NSString *, MMWorktree *> *)by {
    MMWorktree *w;
    for (NSUInteger i = path.length; i > 0;) {
        NSRange r = [path rangeOfString:@"/" options:NSBackwardsSearch | NSLiteralSearch range:NSMakeRange(0, i)];
        if (r.location == NSNotFound) break;
        if (r.location > 0 && (w = by[[path substringToIndex:r.location]])) return w;
        i = r.location;
    }
    return [path hasPrefix:@"/"] ? by[@"/"] : nil;
}

@end

/// Issue #52. The owned findings of the last build, for a build whose owner rules read the same: the same worktree
/// objects in the same order and the same workstream, session and agent owners, names included. Then a finding with no
/// processes and no owner hint, whose owner comes from its paths alone, is the very finding the last build made of the
/// same raw finding, which an expert that reused its findings hands in again. A finding with processes is owned anew,
/// since its owner reads the sample. The workstream and session owners are the last build's objects, and a finding
/// taken from the last build brings its owners along, so equal owners stay one object: one whose owner this build
/// already made as another object is owned anew. With 650 clutter findings, owning each anew took 2 ms a build.
@interface MMOwnerMemo : NSObject
@property uint64_t context;
@property NSDictionary<NSString *, MMOwner *> *owners;  // by ownerID, the workstream, session and agent owners
@property NSMapTable<MMFinding *, MMFinding *> *owned;  // raw to owned, by identity, from the last build
@property NSMapTable<MMFinding *, MMFinding *> *made;   // what this build made, for the next
@property (weak) MMBuild *build;
+ (instancetype)takeFor:(MMBuild *)b;
- (MMFinding *)ownedFor:(MMFinding *)raw;
- (void)keep:(MMFinding *)owned of:(MMFinding *)raw;
- (void)putBack;
@end

static os_unfair_lock gOwnerMemoLock = OS_UNFAIR_LOCK_INIT;
static MMOwnerMemo *gOwnerMemo;

static uint64_t OwnerMix(MMOwner *o) {
    if (!o) return 0x9e3779b97f4a7c15ull;
    return Mix(MixStr(o.ownerID) ^ Mix(MixStr(o.name) + 1) ^ Mix(MixStr(o.path) + 2) ^ Mix(MixStr(o.parent.ownerID) + 3));
}

@implementation MMOwnerMemo

/// Right after the workstreams are linked, while b.owners holds only theirs.
+ (instancetype)takeFor:(MMBuild *)b {
    uint64_t c = Mix(b.trees.count + 0x51);
    NSUInteger i = 0;
    for (MMWorktree *w in b.trees) c = Mix(c + MixObj(w) + ++i);
    for (NSString *oid in b.owners) c += Mix(OwnerMix(b.owners[oid]) + 4);
    for (NSString *path in b.ownerOfTree) c += Mix(MixStr(path) ^ Mix(MixStr(b.ownerOfTree[path].ownerID) + 5));
    for (NSNumber *pid in b.ownerOfAgentPid) c += Mix(pid.unsignedLongLongValue ^ Mix(MixStr(b.ownerOfAgentPid[pid].ownerID) + 6));
    MMOwnerMemo *m = [MMOwnerMemo new];
    m.context = c; m.build = b;
    m.made = [NSMapTable strongToStrongObjectsMapTable];
    m.owners = [b.owners copy];
    os_unfair_lock_lock(&gOwnerMemoLock);
    MMOwnerMemo *last = gOwnerMemo;
    os_unfair_lock_unlock(&gOwnerMemoLock);
    if (!last || last.context != c || last.owners.count != b.owners.count) return m;
    // The same owners as the last build, field for field: its objects stand in for this build's, wherever they are held.
    NSDictionary<NSString *, MMOwner *> *was = last.owners;
    MMOwner *(^same)(MMOwner *) = ^MMOwner *(MMOwner *o) { return (o ? was[o.ownerID] : nil) ?: o; };
    for (NSString *oid in b.owners.allKeys) b.owners[oid] = same(b.owners[oid]);
    for (NSString *path in b.ownerOfTree.allKeys) b.ownerOfTree[path] = same(b.ownerOfTree[path]);
    for (NSNumber *pid in b.ownerOfAgentPid.allKeys) b.ownerOfAgentPid[pid] = same(b.ownerOfAgentPid[pid]);
    for (MMWorkstream *w in b.streams) w.owner = same(w.owner);
    m.owners = was;
    m.owned = last.owned;
    return m;
}

- (MMFinding *)ownedFor:(MMFinding *)raw {
    if (!self.owned || raw.procs.count || raw.owner) return nil;
    MMFinding *f = [self.owned objectForKey:raw];
    MMBuild *b = self.build;
    if (!f || !b) return nil;
    for (MMOwner *o = f.owner; o; o = o.parent) {
        MMOwner *have = b.owners[o.ownerID];
        if (have && have != o) return nil;
    }
    for (MMOwner *o = f.owner; o; o = o.parent) b.owners[o.ownerID] = o;
    return f;
}

- (void)keep:(MMFinding *)owned of:(MMFinding *)raw {
    if (!raw.procs.count && !raw.owner) [self.made setObject:owned forKey:raw];
}

- (void)putBack {
    self.owned = self.made;
    self.made = nil;
    os_unfair_lock_lock(&gOwnerMemoLock);
    gOwnerMemo = self;
    os_unfair_lock_unlock(&gOwnerMemoLock);
}

@end

/// How much of path the workstream's folder is: the length of the folder, as kept or resolved, that holds path, or 0
/// when neither does. Text only.
static NSUInteger HeldBy(MMWorkstream *w, NSString *path) {
    NSString *folder = w.folder;
    if (PathIn(path, folder)) return folder.length;
    NSString *real = w.realFolder;
    return real && PathIn(path, real) ? real.length : 0;
}

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

/// The clutter items each workstream holds, by HeldBy, in the catalog's order. Issue #52: the answer of the last build
/// while the items are the very same objects and the workstreams' folders the same text, since the catalog replaces
/// an item that changed. With 650 items, asking each workstream about each took most of a millisecond a build.
static NSArray<NSArray<MMClutterItem *> *> *ClutterOf(NSArray<MMWorkstream *> *streams, NSArray<MMClutterItem *> *clutter) {
    NSMutableArray<NSString *> *folders = [NSMutableArray arrayWithCapacity:streams.count * 2];
    for (MMWorkstream *w in streams) { [folders addObject:w.folder ?: @""]; [folders addObject:w.realFolder ?: @""]; }
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static NSArray *memoClutter, *memoFolders, *memoAnswer;
    os_unfair_lock_lock(&lock);
    BOOL same = memoAnswer && memoClutter.count == clutter.count && [memoFolders isEqualToArray:folders];
    for (NSUInteger i = 0; same && i < clutter.count; i++) same = memoClutter[i] == clutter[i];
    NSArray *hit = same ? memoAnswer : nil;
    os_unfair_lock_unlock(&lock);
    if (hit) return hit;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:streams.count];
    for (MMWorkstream *w in streams) {
        NSMutableArray *cl = [NSMutableArray new];
        for (MMClutterItem *c in clutter) if (HeldBy(w, c.ownerPath.length ? c.ownerPath : c.path)) [cl addObject:c];
        [out addObject:[cl copy]];
    }
    os_unfair_lock_lock(&lock);
    memoClutter = [clutter copy]; memoFolders = [folders copy]; memoAnswer = [out copy];
    os_unfair_lock_unlock(&lock);
    return out;
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
            NSString *real = lead.worktree.realPath;
            if (real.length && ![real isEqualToString:w.folder]) w.realFolder = real;
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
    MMOwnerMemo *memo = [MMOwnerMemo takeFor:b];

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
        uint64_t o0 = ThreadNs();
        for (MMFinding *raw in raws) {
            if (byID[raw.findingID]) continue;
            MMFinding *f = [memo ownedFor:raw] ?: [raw withOwner:[self ownerOf:raw build:b]];
            [memo keep:f of:raw];
            byID[f.findingID] = f;
            [all addObject:f];
            [mine addObject:f];
        }
        AddCost(@"owners", ThreadNs() - o0);
    }
    uint64_t w0 = ThreadNs();

    NSDate *now = facts.sample.at ?: [NSDate date];
    NSInteger working = 0;
    for (MMAgent *a in facts.agents) if (a.state == MMAgentWorking) working++;
    // Each finding goes to every workstream its owner or one of the owner's parents is, in the order of all. Issue
    // #52: a walk up each owner, where asking each workstream about each of 680 findings took a millisecond a build.
    NSUInteger ns = b.streams.count;
    NSMutableDictionary<MMOwner *, NSMutableArray<NSNumber *> *> *streamsOf = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < ns; i++) {
        MMOwner *o = b.streams[i].owner;
        if (o) [streamsOf[o] ?: (streamsOf[o] = [NSMutableArray new]) addObject:@(i)];
    }
    NSMutableArray<NSMutableArray<MMFinding *> *> *fsOf = [NSMutableArray arrayWithCapacity:ns];
    uint64_t *found = calloc(ns ? ns : 1, sizeof(uint64_t));
    for (NSUInteger i = 0; i < ns; i++) [fsOf addObject:[NSMutableArray new]];
    for (MMFinding *f in all)
        for (MMOwner *o = f.owner; o && streamsOf.count; o = o.parent)
            for (NSNumber *n in streamsOf[o]) {
                NSUInteger i = n.unsignedIntegerValue;
                if (fsOf[i].lastObject == f) continue;   // once, when two owners above it are the same workstream
                [fsOf[i] addObject:f]; found[i] += f.cost.diskFreed;
            }
    NSArray<NSArray<MMClutterItem *> *> *clOf = ClutterOf(b.streams, facts.clutter);
    for (NSUInteger i = 0; i < ns; i++) {
        MMWorkstream *w = b.streams[i];
        // A clutter item can also be a finding, so the size is the larger of the two sums, never both.
        uint64_t items = 0;
        for (MMClutterItem *c in clOf[i]) items += c.size.freedIfDeleted;
        uint64_t bytes = MAX(found[i], items);
        w.findings = [fsOf[i] copy];
        w.clutter = clOf[i];
        w.fingerprintText = [NSString stringWithFormat:@"%@|%ld%@|%@", w.git.head ?: @"-", (long)w.agentState,
                             AgeBucket(w.session.lastActive, now), SizeBucket(bytes)];
    }
    free(found);

    NSMutableDictionary *alive = [NSMutableDictionary new];
    [holds enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *reason, BOOL *stop) {
        NSArray *parts = [key componentsSeparatedByString:@":"];
        MMProcKey k = { (pid_t)[parts.firstObject intValue], (uint64_t)[parts.lastObject longLongValue] };
        if (parts.count == 2 && LiveProc(facts.sample, k)) alive[key] = reason;
    }];

    [memo putBack];
    AddCost(@"streams", ThreadNs() - w0);
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
    NSUInteger most = 0;
    for (MMWorkstream *w in self.workstreams) {
        NSUInteger held = HeldBy(w, path);
        if (held > most) { best = w; most = held; }
    }
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
        uint64_t p0 = ThreadNs();
        id v = [e prepareFor:self];
        AddCost([@"prepare." stringByAppendingString:e.expertID], ThreadNs() - p0);
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
    _Atomic uint64_t _lastCPUNs, _lastEndNs;            // the last build's CPU time, and when it ended
    uint64_t _lastDigest;                               // graph queue only: the digest of the last build's facts
    uint64_t _lastCoreDigest;                           // graph queue only: CoreDigest of the last build
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
        atomic_init(&_lastCPUNs, 0);
        atomic_init(&_lastEndNs, 0);
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
    AddCost([@"why." stringByAppendingString:why ?: @"?"], 1);   // what asks for builds, issue #52: a count, not a time
    // Only a new sample, the last one without the processes that exited, new git facts or a new read of the sessions
    // may find nothing changed. Every other reason, an app, a power change, the worktrees, clutter, a review or an
    // action, always builds. An exit changes the sample alone, which the facts digest and every expert's input digest
    // read, so it builds when they moved. Issue #52: with agents at work, the exits of their compilers, tests and
    // shells asked for most builds, and each asked every expert anew. Know replaces a git fact or a session with a new
    // object when it changes, and every digest that reads one reads it, so a git or session change builds anew what
    // reads it and hands back the rest: an edit in a worktree moves WorkForest's findings, not MinMacs's.
    if (![why isEqualToString:@"sample"] && ![why isEqualToString:@"exit"] && ![why isEqualToString:@"git"] &&
        ![why isEqualToString:@"sessions"]) atomic_store(&_forced, true);
    if (atomic_exchange(&_pending, true)) return;       // one is queued already; it will see these facts too
    // Issue #54: a build waits until 4 times the last build's CPU time has passed since it ended, at most
    // 2 seconds, so builds take at most a fifth of the graph queue. With 300 worktrees a build took 150 to 250 ms,
    // and a launch asked for one after each of 300 disk walks: 46 builds and 9 seconds of CPU in a 25-second launch.
    // A build under 12.5 ms of CPU waits for nothing, so a Mac with a few worktrees builds at once, as before.
    // CPU time, not wall time, so a busy Mac does not make a small build wait.
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW), end = atomic_load(&_lastEndNs);
    uint64_t gap = MIN(4 * atomic_load(&_lastCPUNs), 2 * NSEC_PER_SEC), since = end && now > end ? now - end : UINT64_MAX;
    dispatch_block_t build = ^{
        atomic_store(&self->_pending, false);           // a signal from now on asks for one more build
        uint64_t c0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
        [self buildNow];
        atomic_store(&self->_lastCPUNs, clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - c0);
        atomic_store(&self->_lastEndNs, clock_gettime_nsec_np(CLOCK_UPTIME_RAW));
    };
    if (gap < 50 * NSEC_PER_MSEC || since >= gap) dispatch_async(_queue, build);
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gap - since)), _queue, build);
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
    c1 = ThreadNs();
    if (facts.generation != gen)                        // the generation is the graph's count, never the source's
        facts = [MMFacts generation:gen sample:facts.sample power:facts.power agents:facts.agents sessions:facts.sessions
                          worktrees:facts.worktrees clutter:facts.clutter git:[self gitOf:facts]];
    // Each expert whose inputs did not change hands back its last findings. A forced build asks every expert.
    NSMutableArray *experts = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSNumber *> *digests = [NSMutableDictionary new];
    BOOL allReused = !forced && self.latest != nil;
    NSMutableArray<NSArray<MMFinding *> *> *reusedLists = [NSMutableArray new];
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
                [reusedLists addObject:k.findings];
            }
        }
        if (!r.reused) allReused = NO;
        [experts addObject:r];
    }
    // Issue #52. The facts moved, but nothing any expert or the owner rules read did: the last snapshot stands, with
    // its owners, workstreams and what each expert prepared, as it would after a skip above. On a Mac at work about
    // 800 processes come and go, so the facts digest moved at every pass and every pass built.
    if (allReused && experts.count && CoreDigest(facts, reusedLists, _holds) == _lastCoreDigest) {
        _lastDigest = digest;
        AddCost(@"skipped", 1);
        AddCost(@"skipped.inputs", 1);
        AddCost(@"digest", ThreadNs() - c1);
        os_signpost_interval_end(TickLog(), sp, "rebuild", "skipped: no expert's inputs moved");
        return;
    }
    for (MMFindingsReuse *r in experts) if (r.reused) AddCost([@"reused." stringByAppendingString:r.expertID ?: @""], 1);
    _lastDigest = digest; _lastBuiltNs = nowNs;
    _generation = gen;
    MMSnapshot *snap = [MMSnapshot snapshotFrom:facts experts:(NSArray<id<MMExpert>> *)experts reviews:_reviews holds:_holds];
    BOOL everyDigest = experts.count > 0;
    NSMutableArray<NSArray<MMFinding *> *> *lists = [NSMutableArray new];
    for (MMFindingsReuse *r in experts) {
        NSString *eid = r.expertID ?: @"";
        [lists addObject:r.findings ?: @[]];
        if (!digests[eid]) everyDigest = NO;
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
    // What the next build compares with, on the findings this one was made from and the holds as they stand now.
    _lastCoreDigest = everyDigest ? CoreDigest(facts, lists, _holds) : 0;
    // The last hour, filled by this build and copied into the snapshot, Graph/MMHistory.h.
    uint64_t h0 = ThreadNs();
    snap.history = [MMHistory.shared fillFrom:snap];
    AddCost(@"history", ThreadNs() - h0);
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
