// The MinMacs expert on the shared core. Issue #21.
// Findings come from MMFacts only: the sample's processes and sockets, the registry's agents and the sessions.
// The app list is the one AppKit keeps in NSWorkspace, as Core's MMOwningApp reads it. Nothing here samples or scans.
// Quit, force quit and trim run through MMRunAction, which checks fresh, applies MustKeep and writes the undo record first.
// Ported from main.m, Scanner.m and Agents.m on branch legacy: MakePlan, ServingReason, QuitApps, ForceQuitApps,
// RestoreAll, IsBucket and workingAgentOwning:.
#import <AppKit/AppKit.h>
#import <sys/socket.h>
#import "Experts/MinMacs/MMMinMacs.h"
#import "Experts/MinMacs/MMMinMacsSpecs.h"
#import "UI/MMFormat.h"

static NSString *const kExpert = @"minmacs";

@implementation MMMinMacsApp
@end
@implementation MMMinMacsAgent
@end
@implementation MMMinMacsInput
@end

#pragma mark - Words

static NSString *Pct(double v) { return [NSString stringWithFormat:@"%.0f%%", MAX(0, v)]; }
static NSString *Uses(uint64_t mem, double cpu) { return [NSString stringWithFormat:@"%@ · %@ CPU", MMBytes(mem), Pct(cpu)]; }
static NSString *KeyString(pid_t pid, uint64_t start) { return [NSString stringWithFormat:@"%d:%llu", pid, start]; }
static MMProcKey KeyFrom(NSString *s) {
    NSArray *p = [s componentsSeparatedByString:@":"];
    MMProcKey k = { 0, 0 };
    if (p.count == 2) { k.pid = [p[0] intValue]; k.startSec = (uint64_t)[p[1] longLongValue]; }
    return k;
}
static NSValue *KeyValue(MMProcKey k) { return [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]; }
static NSString *Joined(NSArray<NSString *> *names) {
    if (names.count <= 1) return names.firstObject ?: @"";
    if (names.count == 2) return [NSString stringWithFormat:@"%@ and %@", names[0], names[1]];
    return [NSString stringWithFormat:@"%@ and %@", [[names subarrayWithRange:NSMakeRange(0, names.count - 1)] componentsJoinedByString:@", "], names.lastObject];
}
static NSString *StateWord(MMAgentState s) {
    switch (s) {
        case MMAgentWorking: return @"working";
        case MMAgentWaiting: return @"waits on you";
        case MMAgentIdle: return @"idle";
        case MMAgentUnknown: return @"not known";
    }
    return @"not known";
}
static MMRowMark AgentMark(MMAgentState s) {
    switch (s) {
        case MMAgentWorking: return MMRowMarkWorking;
        case MMAgentWaiting: return MMRowMarkBlocked;
        case MMAgentIdle: return MMRowMarkQuiet;
        case MMAgentUnknown: return MMRowMarkUnknown;
    }
    return MMRowMarkUnknown;
}

#pragma mark - Reading the facts

/// 1.2's IsBucket: regular apps, plus menu bar apps that are not Apple's own. Helpers roll up into their app.
static BOOL IsBucket(NSRunningApplication *ra) {
    NSString *bid = ra.bundleIdentifier;
    if (!bid) return NO;
    if ([bid containsString:@".helper"] || [bid containsString:@".Helper"] || [bid containsString:@".framework."] ||
        [bid hasPrefix:@"com.apple.WebKit"]) return NO;
    if (ra.activationPolicy == NSApplicationActivationPolicyRegular) return ![bid isEqualToString:@"com.apple.loginwindow"];
    if (ra.activationPolicy == NSApplicationActivationPolicyAccessory) return ![bid hasPrefix:@"com.apple."];
    return NO;
}

static BOOL Loopback(const MMSocket *s) {
    if (s->family == AF_INET) return s->localAddr[0] == 127;
    if (s->family == AF_INET6) {
        static const uint8_t one[16] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
        if (!memcmp(s->localAddr, one, 16)) return YES;
        static const uint8_t mapped[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff};
        return !memcmp(s->localAddr, mapped, 12) && s->localAddr[12] == 127;
    }
    return NO;
}

/// 1.2's ServingReason, on the sample's arguments and sockets. nil when nothing serves an agent.
static NSString *DebuggingIn(NSArray<NSString *> *args) {
    for (NSString *a in args) {
        if ([a hasPrefix:@"--remote-debugging-port"]) {
            NSRange eq = [a rangeOfString:@"="];
            return eq.location == NSNotFound ? @"remote debugging is on" : [@"remote debugging on port " stringByAppendingString:[a substringFromIndex:eq.location + 1]];
        }
        if ([a hasPrefix:@"--remote-debugging-pipe"]) return @"an automation tool drives it";
    }
    return nil;
}

@interface MMMinMacsExpert ()
@property (strong) id<MMExpertPolicy> policyObject;
/// The records Restore can bring back, read on the graph queue on every rebuild, so the menu never reads the log on main.
@property (atomic, copy) NSArray<MMUndoRecord *> *restorableRecords;
@end

static NSArray<MMUndoRecord *> *Restorable(void);

/// The keep checks Act asks before every plan and every action.
@interface MMMinMacsPolicy : NSObject <MMExpertPolicy>
@property (weak) MMMinMacsExpert *expert;
@end

/// Quit and force quit of one app instance, through MMQuitApps.
@interface MMMinMacsQuit : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property MMStopStep step;
@property (weak) MMMinMacsExpert *expert;
@end

/// Closing a browser's noise tabs through the tab bridge.
@interface MMMinMacsTrim : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property (copy) NSString *onlyHost;
@end

/// Decides from the rules file, before any model: close list goes, keep list and spared apps stay.
@interface MMMinMacsListRule : NSObject <MMRule>
@end

@implementation MMMinMacsExpert {
    MMVerdictWords *_words;
}

+ (instancetype)shared {
    static MMMinMacsExpert *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMMinMacsExpert new]; });
    return e;
}

- (instancetype)init {
    if ((self = [super init])) {
        _words = [MMVerdictWords keep:@"keep" go:@"quit" unsure:@"unsorted"];
        MMMinMacsPolicy *p = [MMMinMacsPolicy new];
        p.expert = self;
        _policyObject = p;
    }
    return self;
}

- (NSString *)expertID { return kExpert; }
- (NSString *)name { return @"MinMacs"; }
- (NSString *)symbol { return @"gauge.with.dots.needle.33percent"; }
- (NSString *)legacyName { return @"minmacs"; }
- (MMVerdictWords *)words { return _words; }
- (id<MMExpertPolicy>)policy { return self.policyObject; }
- (NSTimeInterval)grace { return MMPrefDouble(@"minmacs.grace", 8); }

#pragma mark Input

- (MMMinMacsInput *)inputFrom:(MMFacts *)facts {
    MMMinMacsInput *(^custom)(MMFacts *) = self.inputFrom;
    return custom ? custom(facts) : [self rollUp:facts];
}

/// Apps with their helpers, from one sample. A process belongs to the app macOS holds responsible for it,
/// else to the nearest app above it, at most 12 hops up, as 1.2's MMScanner did.
- (MMMinMacsInput *)rollUp:(MMFacts *)facts {
    MMSample *s = facts.sample;
    MMMinMacsInput *in = [MMMinMacsInput new];
    in.memoryPressure = facts.power.memoryPressure ?: 1;
    in.thermal = facts.power ? facts.power.thermal : NSProcessInfoThermalStateNominal;
    NSMutableDictionary<NSNumber *, MMMinMacsApp *> *byPid = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSMutableArray *> *pidsOf = [NSMutableDictionary new];
    pid_t me = getpid();
    for (NSRunningApplication *ra in NSWorkspace.sharedWorkspace.runningApplications) {
        pid_t pid = ra.processIdentifier;
        if (pid <= 1 || pid == me || ra.terminated || !IsBucket(ra)) continue;
        MMProc *p = [s proc:pid];
        if (!p) continue;                                  // not in this sample, so nothing to say about it
        MMMinMacsApp *a = [MMMinMacsApp new];
        a.pid = pid; a.startSec = p.startSec; a.bundleID = ra.bundleIdentifier;
        a.name = ra.localizedName.length ? ra.localizedName : ra.bundleIdentifier;
        a.bundlePath = ra.bundleURL.path;
        byPid[@(pid)] = a;
        pidsOf[@(pid)] = [NSMutableArray new];
    }
    double total = 0;
    for (MMProc *p in s.procs.allValues) {
        if (p.cpuPercent > 0) total += p.cpuPercent;
        if (p.pid == me) continue;
        MMMinMacsApp *owner = byPid[@(MMResponsiblePid(p.pid))];
        pid_t cur = p.pid;
        for (int hops = 0; !owner && hops < 12 && cur > 1; hops++) {
            if ((owner = byPid[@(cur)])) break;
            MMProc *parent = [s proc:cur];
            if (!parent) break;
            cur = parent.ppid;
        }
        if (!owner) continue;
        owner.cpuPercent += MAX(0, p.cpuPercent);
        owner.memory += p.footprint;
        owner.energyRank = MAX(owner.energyRank, p.energyRank);
        owner.processCount++;
        [pidsOf[@(owner.pid)] addObject:@(p.pid)];
    }
    in.totalCPU = total;

    // Loopback listeners, from the sample's socket table.
    NSMutableDictionary<NSNumber *, NSMutableOrderedSet *> *ports = [NSMutableDictionary new];
    NSUInteger n = 0;
    const MMSocket *socks = [s sockets:&n];
    for (NSUInteger i = 0; socks && i < n; i++) {
        if (socks[i].state != MMSocketListen || !Loopback(&socks[i])) continue;
        NSMutableOrderedSet *set = ports[@(socks[i].pid)] ?: (ports[@(socks[i].pid)] = [NSMutableOrderedSet new]);
        [set addObject:@(socks[i].localPort)];
    }

    // Agent-aware sparing, from the registry's agents and the sessions. 1.2's workingAgentOwning:
    // an app is spared when a working agent has it in its process tree. Waiting on the person counts as working.
    NSMutableArray<MMMinMacsAgent *> *agents = [NSMutableArray new];
    NSMutableDictionary<NSNumber *, NSArray *> *workerOf = [NSMutableDictionary new];   // pid -> [name, folder]
    NSMutableDictionary<NSString *, NSString *> *rowName = [NSMutableDictionary new];
    for (MMAgent *a in facts.agents) {
        NSString *name = a.row.name.length ? a.row.name : a.harnessID;
        if (a.harnessID) rowName[a.harnessID] = name;
        MMMinMacsAgent *m = [MMMinMacsAgent new];
        m.name = name; m.harnessID = a.harnessID; m.sessionID = a.sessionID; m.project = a.cwd; m.why = a.why;
        m.state = a.state; m.key = a.key; m.cpuPercent = a.treeCPU; m.memory = a.treeFootprint;
        [agents addObject:m];
        NSMutableArray<MMAgent *> *working = [NSMutableArray new];
        if (a.state == MMAgentWorking || a.state == MMAgentWaiting) [working addObject:a];
        for (MMAgent *h in a.hosted) if (h.state == MMAgentWorking || h.state == MMAgentWaiting) [working addObject:h];
        for (MMAgent *w in working)
            for (NSNumber *pid in [s treeOf:w.key.pid limit:500])
                if (!workerOf[pid]) workerOf[pid] = @[w.row.name.length ? w.row.name : (w.harnessID ?: @"An agent"), w.cwd ?: @""];
    }
    for (MMSession *ss in facts.sessions) {
        if (ss.pid <= 1 || !ss.stillWorking) continue;
        NSString *name = rowName[ss.agent ?: @""] ?: ss.agent ?: @"An agent";
        for (NSNumber *pid in [s treeOf:ss.pid limit:500]) if (!workerOf[pid]) workerOf[pid] = @[name, ss.cwd ?: @""];
    }
    in.agents = agents;

    NSMutableArray *apps = [NSMutableArray new];
    for (MMMinMacsApp *a in byPid.allValues) {
        a.pids = pidsOf[@(a.pid)];
        NSMutableOrderedSet *ps = [NSMutableOrderedSet new];
        for (NSNumber *pid in a.pids) if (ports[pid]) [ps unionOrderedSet:ports[pid]];
        a.loopbackPorts = ps.array;
        a.debugging = DebuggingIn([s argsOf:a.pid]);
        NSArray *w = workerOf[@(a.pid)];
        if (w) { a.agentName = w[0]; a.agentPath = [w[1] length] ? w[1] : nil; }
        [apps addObject:a];
    }
    in.apps = apps;
    return in;
}

#pragma mark Findings

typedef NS_ENUM(NSInteger, MMMinMacsGroup) { MMGroupQuit, MMGroupTrim, MMGroupSpared, MMGroupKept, MMGroupUnsorted };
static NSString *GroupName(MMMinMacsGroup g) {
    return @[@"quit", @"trim", @"spared", @"kept", @"unsorted"][g];
}
static MMMinMacsGroup GroupOf(MMFinding *f) {
    NSUInteger i = [@[@"quit", @"trim", @"spared", @"kept", @"unsorted"] indexOfObject:f.facts[@"group"] ?: @""];
    return i == NSNotFound ? MMGroupUnsorted : (MMMinMacsGroup)i;
}

/// "findingID|pid:start" of every app instance MinMacs asked to quit, from one read of the undo log.
static NSSet<NSString *> *QuitAsked(void) {
    NSMutableSet *out = [NSMutableSet new];
    for (MMUndoRecord *r in [MMUndo.shared recent:kExpert limit:200]) {
        NSDictionary *rl = r.payload[@"relaunch"];
        if ([r.kind isEqualToString:@"quit"] && [rl isKindOfClass:NSDictionary.class] && [rl[@"pid"] isKindOfClass:NSString.class])
            [out addObject:[NSString stringWithFormat:@"%@|%@", r.findingID, rl[@"pid"]]];
    }
    return out;
}
static BOOL AskedIn(NSSet *asked, MMFinding *f) {
    return f.instanceKey.length && [asked containsObject:[NSString stringWithFormat:@"%@|%@", f.findingID, f.instanceKey]];
}

static BOOL QuitBrowsers(void) { return MMPrefBool(@"minmacs.quitBrowsers", NO); }

/// The reason a close-list app is spared, as 1.2's MakePlan gives it: serving first, then a working agent.
static NSString *SpareReason(MMMinMacsApp *a, MMMinMacsRules *rules) {
    if (![rules ignoresServing:a.bundleID]) {
        if (a.debugging) return a.debugging;
        if (a.loopbackPorts.count)
            return [@"serving on 127.0.0.1:" stringByAppendingString:[[a.loopbackPorts valueForKey:@"stringValue"] componentsJoinedByString:@", :"]];
    }
    if (a.agentName) return [a.agentName stringByAppendingString:@" started it and is working"];
    return nil;
}

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    MMMinMacsInput *in = [self inputFrom:facts];
    MMMinMacsRules *rules = MMMinMacsRules.shared;
    BOOL quitBrowsers = QuitBrowsers();
    // One read of the undo log per rebuild, here on the graph queue, so the menu and cards never read it on main.
    NSSet *asked = QuitAsked();
    self.restorableRecords = Restorable();
    NSArray *apps = [in.apps sortedArrayUsingComparator:^NSComparisonResult(MMMinMacsApp *x, MMMinMacsApp *y) {
        if (x.memory != y.memory) return x.memory > y.memory ? NSOrderedAscending : NSOrderedDescending;
        return [x.bundleID compare:y.bundleID];
    }];
    NSMutableArray *out = [NSMutableArray new];
    for (MMMinMacsApp *a in apps) {
        if (!a.bundleID.length) continue;
        MMMinMacsVerdict v = [rules verdictFor:a.bundleID];
        MMMinMacsGroup g; NSString *reason = nil; MMProposal *proposal = nil;
        if (v == MMMinMacsKeep) { g = MMGroupKept; reason = @"it is on the keep list"; }
        else if (v == MMMinMacsUnsorted) g = MMGroupUnsorted;
        else if ((reason = SpareReason(a, rules))) g = MMGroupSpared;
        else if (!quitBrowsers && MMMinMacsIsBrowser(a.bundleID)) {
            g = MMGroupTrim;
            if (MMMinMacsCanTrim(a.bundleID)) proposal = [MMProposal verb:@"trim" title:@"Trim Tabs" reversibility:MMReversibleRelaunch];
            else reason = @"MinMacs cannot read this browser's tabs";
        } else {
            g = MMGroupQuit;
            proposal = [MMProposal verb:@"quit" title:@"Quit" reversibility:MMReversibleRelaunch];
        }
        NSString *instance = KeyString(a.pid, a.startSec);
        NSMutableDictionary *fx = [@{@"bundleID": a.bundleID, @"name": a.name ?: a.bundleID, @"pid": @(a.pid),
                                     @"group": GroupName(g), @"verdict": MMMinMacsVerdictName(v),
                                     @"memoryBytes": @(a.memory), @"cpu": @(round(a.cpuPercent)), @"processes": @(a.processCount),
                                     @"browser": @(MMMinMacsIsBrowser(a.bundleID)), @"canTrim": @(MMMinMacsCanTrim(a.bundleID)),
                                     @"pressure": @(in.memoryPressure), @"thermal": @(in.thermal)} mutableCopy];
        if (reason) fx[@"reason"] = reason;
        if (a.bundlePath) fx[@"bundlePath"] = a.bundlePath;
        if (a.agentName) fx[@"agent"] = a.agentName;
        if (a.loopbackPorts.count) fx[@"ports"] = a.loopbackPorts;
        if ([asked containsObject:[NSString stringWithFormat:@"%@:app:%@|%@", kExpert, a.bundleID, instance]]) fx[@"quitAsked"] = @YES;
        double energy = a.energyRank;
        [out addObject:[MMFinding expert:kExpert kind:@"app" stableKey:a.bundleID build:^(MMFindingBuilder *b) {
            b.instanceKey = instance;
            b.title = a.name ?: a.bundleID;
            b.ownerPath = g == MMGroupSpared ? a.agentPath : nil;
            b.cost = (MMCost){ .ramBytes = a.memory, .cpuPercent = a.cpuPercent, .energyRank = energy };
            b.evidence = @[[MMEvidence label:@"Uses" value:Uses(a.memory, a.cpuPercent) raw:@(a.memory)]];
            b.keepReasons = g == MMGroupSpared || g == MMGroupKept || (g == MMGroupTrim && reason) ? @[reason] : @[];
            b.proposal = proposal;
            MMProcKey k = { a.pid, a.startSec };
            b.procs = @[KeyValue(k)];
            b.facts = fx;
            // What must change for the review to look again: the group, the rule and a size bucket.
            b.fingerprint = [NSString stringWithFormat:@"%@|%@|%llu", GroupName(g), reason ?: @"", a.memory >> 28];
        }]];
    }
    for (MMMinMacsAgent *m in in.agents) {
        NSString *stable = [NSString stringWithFormat:@"%@:%@", m.harnessID ?: @"agent", m.sessionID.length ? m.sessionID : (m.project ?: @"")];
        [out addObject:[MMFinding expert:kExpert kind:@"agent" stableKey:stable build:^(MMFindingBuilder *b) {
            b.instanceKey = KeyString(m.key.pid, m.key.startSec);
            b.title = m.name;
            b.cost = (MMCost){ .ramBytes = m.memory, .cpuPercent = m.cpuPercent };
            b.procs = @[KeyValue(m.key)];
            b.facts = @{@"harnessID": m.harnessID ?: @"", @"name": m.name ?: @"", @"state": StateWord(m.state),
                        @"project": m.project ?: @"", @"why": m.why ?: @"", @"memoryBytes": @(m.memory), @"cpu": @(round(m.cpuPercent)),
                        @"pid": @(m.key.pid)};
            b.fingerprint = StateWord(m.state);
        }]];
    }
    return out;
}

/// The finding with this id in facts read now, or nil when it is gone.
- (MMFinding *)finding:(NSString *)findingID in:(MMFacts *)facts {
    for (MMFinding *f in [self findingsFrom:facts]) if ([f.findingID isEqualToString:findingID]) return f;
    return nil;
}

- (BOOL)quitAskedFor:(MMFinding *)f { return AskedIn(QuitAsked(), f); }

#pragma mark Actions

- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step {
    if (![f.expert isEqualToString:kExpert] || ![f.kind isEqualToString:@"app"]) return nil;
    if ([f.proposal.verb isEqualToString:@"trim"] && step == MMStopTerm) {
        MMMinMacsTrim *t = [MMMinMacsTrim new];
        t.finding = f;
        return t;
    }
    MMMinMacsQuit *q = [MMMinMacsQuit new];
    q.finding = f; q.step = step; q.expert = self;
    return q;
}

/// Runs block off main and waits. On main the run loop keeps turning, so AppKit callbacks still arrive.
static void RunOffMain(dispatch_block_t block) {
    if (!NSThread.isMainThread) { block(); return; }
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_async(g, MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED), block);
    while (dispatch_group_wait(g, DISPATCH_TIME_NOW) != 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

/// One action the person asked for, by menu or CLI. Returns the finished record, or nil with *error.
- (MMUndoRecord *)run:(id<MMAction>)action by:(NSString *)by error:(NSString **)error {
    __block MMUndoRecord *r = nil;
    __block NSString *err = nil;
    RunOffMain(^{ r = MMRunAction(action, self.policy, nil, by, by, &err); });
    if (error) *error = err ?: r.error;
    return r;
}

/// Menu actions: run off main, then rebuild the graph. A failure the person should see goes in an alert.
- (void)menuRun:(NSArray<id<MMAction>> *)actions {
    dispatch_async(MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED), ^{
        NSMutableArray *problems = [NSMutableArray new];
        for (id<MMAction> a in actions) {
            NSString *err = nil;
            MMUndoRecord *r = MMRunAction(a, self.policy, nil, @"manual", @"asked from the menu", &err);
            if (!r || r.state == MMUndoFailed) [problems addObject:[NSString stringWithFormat:@"%@: %@", a.finding.title, err ?: r.error ?: @"it failed"]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [MMGraph.shared rebuild:@"minmacs.action"];
            if (!problems.count || !NSApp) return;
            NSAlert *alert = [NSAlert new];
            alert.messageText = problems.count == 1 ? @"MinMacs Could Not Do It" : [NSString stringWithFormat:@"MinMacs Could Not Do %ld Things", (long)problems.count];
            alert.informativeText = [problems componentsJoinedByString:@"\n"];
            [alert runModal];
        });
    });
}

#pragma mark Review

- (NSDictionary *)reviewFactsFor:(MMFinding *)f {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NSString *k in @[@"group", @"verdict", @"processes", @"browser", @"state", @"pressure"]) if (f.facts[k]) d[k] = f.facts[k];
    d[@"memoryMB"] = @(f.cost.ramBytes >> 20);
    d[@"cpu"] = @(round(MAX(0, f.cost.cpuPercent)));
    if (f.facts[@"reason"]) d[@"reason"] = MMClip(f.facts[@"reason"], 120);
    return d;
}

- (NSArray<id<MMRule>> *)rules { return @[[MMMinMacsListRule new]]; }

- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s {
    NSMutableArray *fs = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) if (f.proposal) [fs addObject:f];
    if (!fs.count) return nil;
    MMReviewRequest *r = [MMReviewRequest new];
    r.expert = kExpert; r.trigger = trigger; r.model = MMPrefString(MMReviewModelKey, @"auto");
    r.findings = fs; r.facts = s.facts; r.words = self.words; r.mode = MMModeFor(kExpert);
    r.system = @"You review running Mac apps for a developer. Each item is one app with its group from the person's rules, "
               @"its memory and CPU. Say quit only for an app nothing uses now. Say keep when anything suggests it is in use.";
    __weak MMMinMacsExpert *me = self;
    r.factsFor = ^NSDictionary *(MMFinding *f) { return [me reviewFactsFor:f]; };
    return r;
}

#pragma mark Snapshots

- (MMSnapshot *)snapshotNow {
    MMSnapshot *s = MMGraph.shared.latest;
    if (s) return s;
    id<MMFactSource> source = MMGraph.shared.source;
    MMFacts *facts = [source factsFor:0];
    return facts ? [MMSnapshot snapshotFrom:facts experts:@[self] reviews:nil holds:nil] : nil;
}

static NSArray<MMFinding *> *AppsIn(MMSnapshot *s, MMMinMacsGroup g) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) if ([f.kind isEqualToString:@"app"] && GroupOf(f) == g) [out addObject:f];
    return out;
}
static NSArray<MMFinding *> *AgentsIn(MMSnapshot *s) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) if ([f.kind isEqualToString:@"agent"]) [out addObject:f];
    return out;
}
static uint64_t MemOf(NSArray<MMFinding *> *fs) { uint64_t m = 0; for (MMFinding *f in fs) m += f.cost.ramBytes; return m; }
static double CPUOf(NSArray<MMFinding *> *fs) { double c = 0; for (MMFinding *f in fs) c += MAX(0, f.cost.cpuPercent); return c; }
static NSArray<MMFinding *> *AllApps(MMSnapshot *s) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) if ([f.kind isEqualToString:@"app"]) [out addObject:f];
    return out;
}

/// The MinMacs records that Restore can bring back: done quits and trims, newest first.
static NSArray<MMUndoRecord *> *Restorable(void) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMUndoRecord *r in [MMUndo.shared recent:kExpert limit:200])
        if (r.state == MMUndoDone && r.canRestore && ([r.kind isEqualToString:@"quit"] || [r.kind isEqualToString:@"trim"])) [out addObject:r];
    return out;
}

#pragma mark Menu

- (NSString *)noiseExample {
    for (NSString *h in MMMinMacsRules.shared.noiseHosts) return h;
    return @"youtube.com";
}

/// What the menu reads from the prefs and the support folder, read on the graph queue once per snapshot:
/// the mode and whether the day of watching is over.
- (id)prepareFor:(MMSnapshot *)s {
    return @{@"mode": @(MMModeFor(kExpert)), @"watched": @(MMWatchedLongEnough(kExpert))};
}

- (MMMenuSpec *)menuFor:(MMSnapshot *)s {
    NSDictionary *prepared = NSThread.isMainThread ? [s preparedFor:kExpert] : nil;
    if (![prepared isKindOfClass:NSDictionary.class]) prepared = [self prepareFor:s];
    MMMode menuMode = (MMMode)[prepared[@"mode"] integerValue];
    BOOL watched = [prepared[@"watched"] boolValue];
    NSArray *quit = AppsIn(s, MMGroupQuit), *trim = AppsIn(s, MMGroupTrim), *spared = AppsIn(s, MMGroupSpared);
    NSArray *unsorted = AppsIn(s, MMGroupUnsorted), *agents = AgentsIn(s), *apps = AllApps(s);
    NSInteger working = 0;
    for (MMFinding *a in agents) if ([a.facts[@"state"] isEqual:@"working"] || [a.facts[@"state"] isEqual:@"waits on you"]) working++;
    MMPower *power = s.facts.power;

    MMMenuSpec *m = MMMinMacsMenu();
    m.headerBig = MMBytes(MemOf(apps));
    m.headerUnit = @"in apps";
    NSMutableArray *line = [NSMutableArray arrayWithObjects:MMPlural((NSInteger)apps.count, @"app"), [Pct(CPUOf(apps)) stringByAppendingString:@" CPU"], nil];
    if (working) [line addObject:[MMPlural(working, @"agent") stringByAppendingString:@" working"]];
    [line addObject:MMCapitalized(MMModeName(menuMode))];
    m.headerLine = [line componentsJoinedByString:@" · "];

    // The summary explains. The header and the action tails already give the counts and sizes.
    NSMutableArray<NSString *> *say = [NSMutableArray new];
    if (!watched) [say addObject:[NSString stringWithFormat:@"Watching %@. Quits nothing on its own.", MMPlural((NSInteger)apps.count, @"app")]];
    if (power.memoryPressure >= 2) [say addObject:@"Memory pressure is high, so quitting apps helps now."];
    if (power.thermal >= NSProcessInfoThermalStateSerious) [say addObject:@"The Mac runs hot."];
    if (quit.count) {
        NSArray *names = [[quit subarrayWithRange:NSMakeRange(0, MIN(2, quit.count))] valueForKey:@"title"];
        [say addObject:quit.count == 1 ? [NSString stringWithFormat:@"%@ is on the close list, and nothing uses it.", names[0]]
                     : quit.count == 2 ? [NSString stringWithFormat:@"%@ are on the close list, and nothing uses them.", Joined(names)]
                                       : [NSString stringWithFormat:@"%@ lead the close list, and nothing uses them.", Joined(names)]];
    }
    if (spared.count) {
        MMFinding *f = spared.firstObject;
        NSString *why = f.facts[@"agent"] ? [NSString stringWithFormat:@"%@ started it and is working", f.facts[@"agent"]] : @"an agent or tool may use it";
        [say addObject:[NSString stringWithFormat:@"%@ stays, because %@.", f.title, why]];
    }
    if (trim.count) {
        MMFinding *f = trim.firstObject;
        [say addObject:[f.facts[@"canTrim"] boolValue]
            ? [NSString stringWithFormat:@"%@ keeps running, and Trim Tabs closes only noise tabs such as %@.", f.title, [self noiseExample]]
            : [NSString stringWithFormat:@"%@ keeps running, since MinMacs cannot read its tabs.", f.title]];
    }
    if (!say.count) [say addObject:@"Nothing on the close list is open."];
    m.summary = [say componentsJoinedByString:@" "];

    __weak MMMinMacsExpert *me = self;
    NSMutableArray *actions = [NSMutableArray new];
    if (quit.count) {
        NSArray *targets = quit;
        [actions addObject:MMMinMacsAction(@"Quit Apps", [NSString stringWithFormat:@"%@, %@", MMPlural((NSInteger)quit.count, @"app"), MMBytes(MemOf(quit))], nil, ^(BOOL option) {
            NSMutableArray *acts = [NSMutableArray new];
            for (MMFinding *f in targets) [acts addObject:[me actionFor:f step:MMStopTerm]];
            [me menuRun:acts];
        })];
    }
    NSMutableArray *trimmable = [NSMutableArray new];
    for (MMFinding *f in trim) if (f.proposal) [trimmable addObject:f];
    if (trimmable.count) {
        [actions addObject:MMMinMacsAction(@"Trim Tabs", MMPlural((NSInteger)trimmable.count, @"browser"), nil, ^(BOOL option) {
            NSMutableArray *acts = [NSMutableArray new];
            for (MMFinding *f in trimmable) [acts addObject:[me actionFor:f step:MMStopTerm]];
            [me menuRun:acts];
        })];
    }
    m.actions = actions;

    NSMutableArray *sections = [NSMutableArray new];
    NSMutableArray *rows = [NSMutableArray new];
    for (MMFinding *f in quit) {
        BOOL stuck = [f.facts[@"quitAsked"] boolValue];
        [rows addObject:MMMinMacsRow(f.title, @[MMBytes(f.cost.ramBytes), [Pct(f.cost.cpuPercent) stringByAppendingString:@" CPU"], stuck ? @"did not quit" : @""],
                                     stuck ? MMRowMarkBlocked : MMRowMarkGoes, f.findingID)];
    }
    if (rows.count) [sections addObject:MMMinMacsSection(@"Will quit", rows)];
    rows = [NSMutableArray new];
    for (MMFinding *f in trim)
        [rows addObject:MMMinMacsRow(f.title, @[MMBytes(f.cost.ramBytes), [Pct(f.cost.cpuPercent) stringByAppendingString:@" CPU"],
                                               [f.facts[@"canTrim"] boolValue] ? @"trims noise tabs" : @"tabs cannot be read"], MMRowMarkQuiet, f.findingID)];
    if (rows.count) [sections addObject:MMMinMacsSection(@"Browsers", rows)];
    rows = [NSMutableArray new];
    for (MMFinding *f in spared) {
        NSArray *ports = f.facts[@"ports"];
        NSString *why = f.facts[@"agent"] ? [f.facts[@"agent"] stringByAppendingString:@" works"]
                      : ports.count ? [@"serving :" stringByAppendingString:[ports.firstObject stringValue]] : @"remote debugging";
        [rows addObject:MMMinMacsRow(f.title, @[MMBytes(f.cost.ramBytes), [Pct(f.cost.cpuPercent) stringByAppendingString:@" CPU"], why], MMRowMarkWorking, f.findingID)];
    }
    if (rows.count) [sections addObject:MMMinMacsSection(@"Spared", rows)];
    rows = [NSMutableArray new];
    for (MMFinding *f in agents) {
        NSString *project = [f.facts[@"project"] lastPathComponent];
        MMAgentState st = MMAgentUnknown;
        for (MMAgentState x = MMAgentUnknown; x <= MMAgentIdle; x++) if ([StateWord(x) isEqual:f.facts[@"state"]]) st = x;
        [rows addObject:MMMinMacsRow(f.title, @[project ?: @"", MMBytes(f.cost.ramBytes), StateWord(st)], AgentMark(st), f.findingID)];
    }
    if (rows.count) [sections addObject:MMMinMacsSection(@"Agents", rows)];
    rows = [NSMutableArray new];
    for (MMFinding *f in unsorted)
        [rows addObject:MMMinMacsRow(f.title, @[MMBytes(f.cost.ramBytes), [Pct(f.cost.cpuPercent) stringByAppendingString:@" CPU"]], MMRowMarkQuiet, f.findingID)];
    if (rows.count) [sections addObject:MMMinMacsSection(@"Unsorted", rows)];
    m.sections = [sections subarrayWithRange:NSMakeRange(0, MIN(4, sections.count))];

    NSMutableArray *more = [NSMutableArray new];
    NSArray<MMUndoRecord *> *back = NSThread.isMainThread ? self.restorableRecords ?: @[] : Restorable();
    if (back.count) {
        [more addObject:MMMinMacsAction([NSString stringWithFormat:@"Restore %@", MMPlural((NSInteger)back.count, @"Closed Item")],
                                        MMAgo(back.firstObject.at), nil, ^(BOOL option) {
            dispatch_async(MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED), ^{
                [me restore:nil dryRun:NO];
                dispatch_async(dispatch_get_main_queue(), ^{ [MMGraph.shared rebuild:@"minmacs.restore"]; });
            });
        })];
    }
    [more addObject:MMMinMacsAction(@"Edit Rules…", nil, nil, ^(BOOL option) {
        [MMMinMacsRules.shared reload];
        [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:MMMinMacsRules.shared.path]];
    })];
    m.more = more;
    return m;
}

#pragma mark Cards

/// "uses the most energy" for the app with the highest rank, a softer word for the next two, nil for the rest.
static NSString *EnergyWords(MMFinding *f, MMSnapshot *s) {
    if (f.cost.energyRank <= 0) return nil;
    NSArray *apps = [AllApps(s) sortedArrayUsingComparator:^NSComparisonResult(MMFinding *x, MMFinding *y) {
        return x.cost.energyRank > y.cost.energyRank ? NSOrderedAscending : x.cost.energyRank < y.cost.energyRank ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger i = [apps indexOfObject:f];
    if (i == 0) return @"uses the most energy";
    if (i != NSNotFound && i < 3) return @"in the top three";
    return nil;
}

- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s {
    if ([f.kind isEqualToString:@"agent"]) return [self agentCard:f];
    MMCardSpec *c = MMMinMacsCard();
    MMMinMacsGroup g = GroupOf(f);
    NSString *bid = f.facts[@"bundleID"];
    // From the finding, so the card reads no undo log on main. The Force Quit action checks the log again.
    BOOL stuck = g == MMGroupQuit && [f.facts[@"quitAsked"] boolValue];
    c.title = f.title;
    switch (g) {
        case MMGroupQuit:
            c.mark = stuck ? MMRowMarkBlocked : MMRowMarkGoes;
            c.statusWord = stuck ? @"Did not quit." : @"Goes on Quit Apps.";
            c.statusText = stuck ? @"It may be asking to save. Force Quit closes it now, and unsaved changes are lost."
                                 : @"It is on the close list, and nothing uses it. Restore opens it again.";
            break;
        case MMGroupTrim:
            c.mark = MMRowMarkQuiet; c.statusWord = @"Stays.";
            c.statusText = [f.facts[@"canTrim"] boolValue]
                ? [NSString stringWithFormat:@"Browsers are trimmed, not quit. Trim Tabs closes noise tabs such as %@.", [self noiseExample]]
                : @"MinMacs cannot read this browser's tabs, so it leaves it running.";
            break;
        case MMGroupSpared:
            c.mark = MMRowMarkWorking; c.statusWord = @"Stays.";
            c.statusText = f.facts[@"agent"] ? [NSString stringWithFormat:@"%@ started it and is working. MinMacs looks again once the agent is idle.", f.facts[@"agent"]]
                                             : [f.facts[@"ports"] count]
                ? [NSString stringWithFormat:@"It serves on 127.0.0.1:%@, so an agent or tool may use it.", [[f.facts[@"ports"] valueForKey:@"stringValue"] componentsJoinedByString:@", :"]]
                : @"Remote debugging is on, so an automation tool may drive it.";
            break;
        case MMGroupKept:
            c.mark = MMRowMarkQuiet; c.statusWord = @"Stays.";
            c.statusText = @"It is on the keep list, so MinMacs never quits it.";
            break;
        case MMGroupUnsorted:
            c.mark = MMRowMarkQuiet; c.statusWord = @"Stays.";
            c.statusText = @"It is on no list, so MinMacs only lists it. Quit on MinMacs puts it on the close list.";
            break;
    }
    NSMutableArray *facts = [NSMutableArray new];
    [facts addObject:MMMinMacsFact(@"Uses", Uses(f.cost.ramBytes, f.cost.cpuPercent))];
    NSString *energy = EnergyWords(f, s);
    if (energy) [facts addObject:MMMinMacsFact(@"Energy", energy)];
    [facts addObject:MMMinMacsFact(@"Processes", [f.facts[@"processes"] stringValue])];
    NSString *list = @{@"keep": @"keep list", @"close": @"close list", @"unsorted": @"none"}[f.facts[@"verdict"]];
    [facts addObject:MMMinMacsFact(@"List", list)];
    if (f.owner.kind == MMOwnerWorkstream || f.owner.kind == MMOwnerWorktree) {
        NSString *path = f.owner.kind == MMOwnerWorkstream ? f.owner.key : f.owner.path;
        MMCardFact *link = MMMinMacsFact(@"Worktree", f.owner.name);
        link.linkExpert = @"workforest"; link.linkFindingID = [@"workforest:worktree:" stringByAppendingString:path ?: @""];
        [facts addObject:link];
    }
    c.facts = [facts subarrayWithRange:NSMakeRange(0, MIN(5, facts.count))];

    __weak MMMinMacsExpert *me = self;
    NSMutableArray *actions = [NSMutableArray new];
    // The status already says why it stays, so the dimmed Quit only names the rule in a few words.
    NSString *keep = g == MMGroupSpared ? @"in use" : g == MMGroupKept ? @"on the keep list" : f.keepReasons.count ? MMCut(f.keepReasons.firstObject, 40) : nil;
    if (stuck) [actions addObject:MMMinMacsAction(@"Force Quit", nil, nil, ^(BOOL o) { [me menuRun:@[[me actionFor:f step:MMStopKill]]]; })];
    else [actions addObject:MMMinMacsAction(@"Quit", nil, keep, ^(BOOL o) { [me menuRun:@[[me actionFor:f step:MMStopTerm]]]; })];
    if (g == MMGroupTrim && f.proposal) [actions addObject:MMMinMacsAction(@"Trim Tabs", nil, nil, ^(BOOL o) { [me menuRun:@[[me actionFor:f step:MMStopTerm]]]; })];
    MMMinMacsVerdict v = (MMMinMacsVerdict)MAX(0, MMMinMacsVerdictFrom(f.facts[@"verdict"]));
    void (^sort)(MMMinMacsVerdict) = ^(MMMinMacsVerdict to) {
        [MMMinMacsRules.shared setVerdict:to forBundleID:bid];
        [MMGraph.shared rebuild:@"minmacs.rules"];
    };
    if (v != MMMinMacsKeep) [actions addObject:MMMinMacsAction(@"Always Keep", nil, nil, ^(BOOL o) { sort(MMMinMacsKeep); })];
    if (v != MMMinMacsClose) [actions addObject:MMMinMacsAction(@"Quit on MinMacs", nil, nil, ^(BOOL o) { sort(MMMinMacsClose); })];
    if (v != MMMinMacsUnsorted) [actions addObject:MMMinMacsAction(@"Leave Unsorted", nil, nil, ^(BOOL o) { sort(MMMinMacsUnsorted); })];
    BOOL ignores = [MMMinMacsRules.shared ignoresServing:bid];
    if ((g == MMGroupSpared && !f.facts[@"agent"]) || (ignores && [f.facts[@"ports"] count])) {
        [actions addObject:MMMinMacsAction(ignores ? @"Spare When Serving" : @"Close Even When Serving", nil, nil, ^(BOOL o) {
            [MMMinMacsRules.shared setIgnoresServing:!ignores forBundleID:bid];
            [MMGraph.shared rebuild:@"minmacs.rules"];
        })];
    }
    c.actions = actions;
    return c;
}

- (MMCardSpec *)agentCard:(MMFinding *)f {
    MMCardSpec *c = MMMinMacsCard();
    NSString *state = f.facts[@"state"];
    MMAgentState st = MMAgentUnknown;
    for (MMAgentState x = MMAgentUnknown; x <= MMAgentIdle; x++) if ([StateWord(x) isEqual:state]) st = x;
    NSString *project = [f.facts[@"project"] length] ? [f.facts[@"project"] stringByAbbreviatingWithTildeInPath] : nil;
    c.title = project ? [NSString stringWithFormat:@"%@ in %@", f.title, [project lastPathComponent]] : f.title;
    c.mark = AgentMark(st);
    c.statusWord = @{@"working": @"Works.", @"waits on you": @"Waits on you.", @"idle": @"Idle."}[state] ?: @"Not known.";
    c.statusText = st == MMAgentWorking || st == MMAgentWaiting ? @"MinMacs spares every app it starts while it works."
                                                               : @"Apps it started are quit like any other app on the close list.";
    NSMutableArray *facts = [NSMutableArray new];
    if (project) [facts addObject:MMMinMacsFact(@"Project", project)];
    [facts addObject:MMMinMacsFact(@"Uses", Uses(f.cost.ramBytes, f.cost.cpuPercent))];
    if ([f.facts[@"why"] length]) [facts addObject:MMMinMacsFact(@"Signal", f.facts[@"why"])];
    if (f.owner.kind == MMOwnerWorkstream || f.owner.kind == MMOwnerWorktree) {
        MMCardFact *link = MMMinMacsFact(@"Worktree", f.owner.name);
        link.linkExpert = @"workforest";
        link.linkFindingID = [@"workforest:worktree:" stringByAppendingString:(f.owner.kind == MMOwnerWorkstream ? f.owner.key : f.owner.path) ?: @""];
        [facts addObject:link];
    }
    c.facts = facts;
    c.actions = @[];
    return c;
}

- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }

- (NSString *)accessibilityStateFor:(MMSnapshot *)s {
    NSUInteger quit = AppsIn(s, MMGroupQuit).count;
    return quit ? [MMPlural((NSInteger)quit, @"app") stringByAppendingString:@" to quit"] : MMPlural((NSInteger)AllApps(s).count, @"app");
}

- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return AllApps(s).count == 0; }

#pragma mark Status and restore

- (NSDictionary *)statusJSON:(MMSnapshot *)s {
    NSArray *apps = AllApps(s), *quit = AppsIn(s, MMGroupQuit);
    NSMutableDictionary *agents = [@{@"working": @0, @"waiting": @0, @"idle": @0, @"unknown": @0} mutableCopy];
    for (MMFinding *a in AgentsIn(s)) {
        NSString *k = @{@"working": @"working", @"waits on you": @"waiting", @"idle": @"idle"}[a.facts[@"state"]] ?: @"unknown";
        agents[k] = @([agents[k] integerValue] + 1);
    }
    return @{@"expert": kExpert, @"apps": @(apps.count), @"memoryBytes": @(MemOf(apps)), @"cpu": @(round(CPUOf(apps))),
             @"quit": @(quit.count), @"quitMemoryBytes": @(MemOf(quit)), @"trim": @(AppsIn(s, MMGroupTrim).count),
             @"spared": @(AppsIn(s, MMGroupSpared).count), @"agents": agents, @"restorable": @(Restorable().count),
             @"mode": MMModeName(MMModeFor(kExpert))};
}

- (NSString *)statusLine:(MMSnapshot *)s {
    NSDictionary *j = [self statusJSON:s];
    NSMutableArray *parts = [NSMutableArray arrayWithObjects:MMPlural([j[@"apps"] integerValue], @"app"), MMBytes([j[@"memoryBytes"] unsignedLongLongValue]), nil];
    if ([j[@"quit"] integerValue]) [parts addObject:[NSString stringWithFormat:@"%ld to quit", (long)[j[@"quit"] integerValue]]];
    if ([j[@"spared"] integerValue]) [parts addObject:[NSString stringWithFormat:@"%ld spared", (long)[j[@"spared"] integerValue]]];
    NSInteger working = [j[@"agents"][@"working"] integerValue] + [j[@"agents"][@"waiting"] integerValue];
    if (working) [parts addObject:[MMPlural(working, @"agent") stringByAppendingString:@" working"]];
    if ([j[@"restorable"] integerValue]) [parts addObject:[NSString stringWithFormat:@"%ld to restore", (long)[j[@"restorable"] integerValue]]];
    return [@"MinMacs: " stringByAppendingString:[parts componentsJoinedByString:@", "]];
}

- (NSArray<NSDictionary *> *)restore:(NSString *)rid dryRun:(BOOL)dryRun {
    NSArray<MMUndoRecord *> *records;
    if (rid.length) {
        MMUndoRecord *r = [MMUndo.shared record:rid];
        if (!r || ![r.expert isEqualToString:kExpert]) return @[@{@"rid": rid, @"ok": @NO, @"problem": @"no MinMacs record with that id"}];
        records = @[r];
    } else records = Restorable();
    NSMutableArray *out = [NSMutableArray new];
    for (MMUndoRecord *r in records) {
        NSMutableDictionary *res = [@{@"rid": r.rid, @"subject": r.subject ?: @"", @"kind": r.kind ?: @""} mutableCopy];
        NSArray *tabs = [r.payload[@"tabs"] isKindOfClass:NSArray.class] ? r.payload[@"tabs"] : @[];
        NSDictionary *rl = [r.payload[@"relaunch"] isKindOfClass:NSDictionary.class] ? r.payload[@"relaunch"] : @{};
        if (dryRun) {
            res[@"ok"] = @YES;
            res[@"would"] = [r.kind isEqualToString:@"trim"] ? [NSString stringWithFormat:@"reopen %@ in %@", MMPlural((NSInteger)tabs.count, @"tab"), r.subject]
                                                             : [@"open " stringByAppendingString:r.subject ?: @"the app"];
            [out addObject:res];
            continue;
        }
        NSString *problem = nil;
        if ([r.kind isEqualToString:@"trim"] && tabs.count) {
            NSMutableArray *urls = [NSMutableArray new];
            for (NSDictionary *t in tabs) if ([t[@"url"] isKindOfClass:NSString.class]) [urls addObject:t[@"url"]];
            problem = [MMMinMacsTabBridgeNow() open:urls bundleID:rl[@"bundleID"] appPath:rl[@"url"]];
        }
        if (!problem) problem = [MMUndo.shared restore:r.rid];
        res[@"ok"] = @(problem == nil);
        if (problem) res[@"problem"] = problem;
        [out addObject:res];
    }
    return out;
}

#pragma mark Verbs

static void Print(NSString *s) { printf("%s\n", s.UTF8String); }
static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    Print([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"{}");
}
static NSString *Opt(NSArray *w, NSString *name) {
    NSUInteger i = [w indexOfObject:name];
    return i != NSNotFound && i + 1 < w.count ? w[i + 1] : nil;
}
static NSArray<NSString *> *Plain(NSArray<NSString *> *w) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSUInteger i = 0; i < w.count; i++) {
        if ([w[i] isEqualToString:@"--only-host"]) { i++; continue; }
        if (![w[i] hasPrefix:@"--"]) [out addObject:w[i]];
    }
    return out;
}

static NSDictionary *AppJSON(MMFinding *f) {
    NSMutableDictionary *j = [@{@"name": f.title ?: @"", @"bundleID": f.facts[@"bundleID"] ?: @"", @"pid": f.facts[@"pid"] ?: @0,
                                @"cpu": f.facts[@"cpu"] ?: @0, @"memoryBytes": @(f.cost.ramBytes), @"processes": f.facts[@"processes"] ?: @0,
                                @"group": f.facts[@"group"] ?: @"", @"id": f.findingID} mutableCopy];
    if (f.facts[@"reason"]) j[@"reason"] = f.facts[@"reason"];
    return j;
}

static void PrintGroup(NSString *title, NSArray<MMFinding *> *fs, BOOL reasons) {
    if (!fs.count) return;
    Print([NSString stringWithFormat:@"%@: %lu", title, (unsigned long)fs.count]);
    for (MMFinding *f in fs) {
        NSString *row = [NSString stringWithFormat:@"  %5@  %8@  %-28@ %@", Pct(f.cost.cpuPercent), MMBytes(f.cost.ramBytes), MMCut(f.title, 28), f.facts[@"bundleID"]];
        if (reasons && f.facts[@"reason"]) row = [row stringByAppendingFormat:@"  %@", f.facts[@"reason"]];
        Print(row);
    }
}

/// The app findings a target names: a bundle id or a pid, or every app on the close list for --all.
static NSArray<MMFinding *> *Targets(MMSnapshot *s, NSString *target, BOOL all, BOOL trim) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in AllApps(s)) {
        if (all) { if (GroupOf(f) == (trim ? MMGroupTrim : MMGroupQuit) && (!trim || f.proposal)) [out addObject:f]; continue; }
        if ([f.facts[@"bundleID"] isEqual:target] || [[f.facts[@"pid"] stringValue] isEqual:target]) [out addObject:f];
    }
    return out;
}

- (int)apps:(NSArray<NSString *> *)w {
    BOOL json = [w containsObject:@"--json"], dry = [w containsObject:@"--dry-run"], force = [w containsObject:@"--force"],
         all = [w containsObject:@"--all"];
    NSArray *plain = Plain(w);
    NSString *sub = plain.firstObject ?: @"list", *arg = plain.count > 1 ? plain[1] : nil, *arg2 = plain.count > 2 ? plain[2] : nil;
    MMMinMacsRules *rules = MMMinMacsRules.shared;

    if ([sub isEqualToString:@"rules"]) { Print(rules.path); return 0; }
    if ([sub isEqualToString:@"classify"]) {
        if (!arg) { fprintf(stderr, "usage: minmacs apps classify <url|host>\n"); return 2; }
        NSString *h = ([NSURL URLWithString:arg].host ?: arg).lowercaseString;
        if ([h hasPrefix:@"www."]) h = [h substringFromIndex:4];
        Print([rules tabVerdictForHost:h]);
        return 0;
    }
    NSInteger to = MMMinMacsVerdictFrom(sub);
    if (to >= 0) {
        if (!arg) { fprintf(stderr, "usage: minmacs apps %s <bundle-id>\n", sub.UTF8String); return 2; }
        if (dry) { Print([NSString stringWithFormat:@"would set %@ to %@", arg, sub]); return 0; }
        [rules setVerdict:(MMMinMacsVerdict)to forBundleID:arg];
        Print([NSString stringWithFormat:@"%@: %@", arg, MMMinMacsVerdictName([rules verdictFor:arg])]);
        return 0;
    }
    if ([sub isEqualToString:@"serving"]) {
        if (!arg2 || !([arg isEqualToString:@"on"] || [arg isEqualToString:@"off"])) { fprintf(stderr, "usage: minmacs apps serving on|off <bundle-id>\n"); return 2; }
        if (dry) { Print([NSString stringWithFormat:@"would turn serving %@ for %@", arg, arg2]); return 0; }
        [rules setIgnoresServing:[arg isEqualToString:@"off"] forBundleID:arg2];
        Print([NSString stringWithFormat:@"%@: serving %@", arg2, [rules ignoresServing:arg2] ? @"off" : @"on"]);
        return 0;
    }
    if (![@[@"list", @"plan", @"quit", @"trim"] containsObject:sub]) {
        fprintf(stderr, "usage: minmacs apps [list | quit <bundle-id|pid> [--force] | quit --all | trim [<bundle-id>] [--only-host <host>] |\n"
                        "                     keep|close|unsorted <bundle-id> | serving on|off <bundle-id> | classify <url> | rules] [--json] [--dry-run]\n");
        return 2;
    }
    MMSnapshot *s = [self snapshotNow];
    if (!s) { fprintf(stderr, "minmacs: Core is not running, so there are no facts to read\n"); return 1; }

    if ([sub isEqualToString:@"list"] || [sub isEqualToString:@"plan"]) {
        NSArray *quit = AppsIn(s, MMGroupQuit);
        if (json) {
            NSArray *(^enc)(NSArray *) = ^NSArray *(NSArray *fs) { NSMutableArray *o = [NSMutableArray new]; for (MMFinding *f in fs) [o addObject:AppJSON(f)]; return o; };
            NSMutableArray *agents = [NSMutableArray new];
            for (MMFinding *a in AgentsIn(s)) [agents addObject:a.facts];
            PrintJSON(@{@"quit": enc(quit), @"trim": enc(AppsIn(s, MMGroupTrim)), @"spared": enc(AppsIn(s, MMGroupSpared)),
                        @"keep": enc(AppsIn(s, MMGroupKept)), @"unsorted": enc(AppsIn(s, MMGroupUnsorted)), @"agents": agents,
                        @"reclaimableMemoryBytes": @(MemOf(quit)), @"reclaimableCPU": @(round(CPUOf(quit))),
                        @"thermal": @(s.facts.power.thermal), @"memoryPressure": @(s.facts.power.memoryPressure ?: 1)});
            return 0;
        }
        PrintGroup(@"Will quit", quit, NO);
        PrintGroup(@"Browsers, trimmed not quit", AppsIn(s, MMGroupTrim), YES);
        PrintGroup(@"Spared, in use by an agent or tool", AppsIn(s, MMGroupSpared), YES);
        PrintGroup(@"Kept", AppsIn(s, MMGroupKept), NO);
        PrintGroup(@"Unsorted, never touched", AppsIn(s, MMGroupUnsorted), NO);
        for (MMFinding *a in AgentsIn(s))
            Print([NSString stringWithFormat:@"Agent %@: %@, %@", a.title, a.facts[@"state"], [a.facts[@"project"] length] ? [a.facts[@"project"] stringByAbbreviatingWithTildeInPath] : @"no folder"]);
        Print([NSString stringWithFormat:@"Reclaimable by quitting: %@ CPU, %@", Pct(CPUOf(quit)), MMBytes(MemOf(quit))]);
        return 0;
    }

    BOOL trim = [sub isEqualToString:@"trim"];
    if (!arg && !all && !trim) { fprintf(stderr, "minmacs: name an app by bundle id or pid, or pass --all\n"); return 2; }
    NSArray<MMFinding *> *targets = Targets(s, arg, all || (trim && !arg), trim);
    if (!targets.count) {
        if (json) PrintJSON(@{@"results": @[]}); else Print(trim ? @"no browser to trim" : @"nothing to quit");
        return arg && !all ? 1 : 0;
    }
    NSMutableArray *results = [NSMutableArray new];
    int status = 0;
    for (MMFinding *f in targets) {
        id<MMAction> a = [self actionFor:f step:force && !trim ? MMStopKill : MMStopTerm];
        if (trim && [a isKindOfClass:MMMinMacsTrim.class]) ((MMMinMacsTrim *)a).onlyHost = Opt(w, @"--only-host").lowercaseString;
        if (!a || (trim && ![a isKindOfClass:MMMinMacsTrim.class])) {
            [results addObject:@{@"id": f.findingID, @"ok": @NO, @"problem": @"it is not a browser MinMacs can trim"}];
            status = MAX(status, 1);
            continue;
        }
        if (dry) {
            __block NSString *what = nil, *why = nil;
            RunOffMain(^{ why = [a recheck]; what = why ? nil : [a dryRun]; });
            [results addObject:@{@"id": f.findingID, @"ok": @(why == nil), @"would": what ?: @"", @"problem": why ?: @""}];
            continue;
        }
        NSString *err = nil;
        MMUndoRecord *r = [self run:a by:@"cli" error:&err];
        BOOL ok = r && r.state == MMUndoDone;
        NSMutableDictionary *res = [@{@"id": f.findingID, @"ok": @(ok), @"title": f.title ?: @""} mutableCopy];
        if (r) res[@"rid"] = r.rid;
        if (!ok) res[@"problem"] = err ?: r.error ?: @"it failed";
        if ([r.payload[@"closed"] isKindOfClass:NSArray.class]) res[@"closed"] = r.payload[@"closed"];
        [results addObject:res];
        // 1.2's exit codes: 3 when an app ignored Quit, 1 when MinMacs kept it.
        status = MAX(status, r ? (ok ? 0 : 3) : 1);
    }
    if (json) PrintJSON(@{@"results": results});
    else for (NSDictionary *res in results) {
        if (dry) Print([res[@"ok"] boolValue] ? res[@"would"] : [NSString stringWithFormat:@"would not run: %@", res[@"problem"]]);
        else if ([res[@"ok"] boolValue]) Print(trim ? [NSString stringWithFormat:@"trimmed %@: closed %@", res[@"title"], MMPlural((NSInteger)[res[@"closed"] count], @"tab")]
                                                    : [NSString stringWithFormat:@"%@ %@", force ? @"force quit" : @"quit", res[@"title"]]);
        else Print([NSString stringWithFormat:@"%@: %@", res[@"title"] ?: res[@"id"], res[@"problem"]]);
    }
    return status;
}

- (int)status:(NSArray<NSString *> *)w {
    MMSnapshot *s = [self snapshotNow];
    if (!s) { fprintf(stderr, "minmacs: Core is not running, so there are no facts to read\n"); return 1; }
    if ([w containsObject:@"--json"]) PrintJSON([self statusJSON:s]); else Print([self statusLine:s]);
    return 0;
}

- (int)restoreVerb:(NSArray<NSString *> *)w {
    BOOL json = [w containsObject:@"--json"], dry = [w containsObject:@"--dry-run"];
    NSString *rid = Plain(w).firstObject;
    __block NSArray *results = nil;
    RunOffMain(^{ results = [self restore:rid dryRun:dry]; });
    NSInteger bad = 0;
    for (NSDictionary *r in results) bad += ![r[@"ok"] boolValue];
    if (json) PrintJSON(@{@"expert": kExpert, @"results": results});
    else {
        for (NSDictionary *r in results)
            Print(dry ? [@"would " stringByAppendingString:r[@"would"] ?: @""]
                      : [r[@"ok"] boolValue] ? [@"restored " stringByAppendingString:r[@"subject"]]
                                             : [NSString stringWithFormat:@"%@: %@", [r[@"subject"] length] ? r[@"subject"] : r[@"rid"], r[@"problem"]]);
        if (!dry) Print([NSString stringWithFormat:@"MinMacs restored %ld of %@", (long)(results.count - bad), MMPlural((NSInteger)results.count, @"item")]);
    }
    return bad ? 1 : 0;
}

- (NSArray<MMVerbSpec *> *)verbs {
    __weak MMMinMacsExpert *me = self;
    return @[
        MMMinMacsVerb(@"apps", @"apps [list | quit <bundle-id|pid> [--force] | trim [<bundle-id>] | keep|close|unsorted <bundle-id> | serving on|off <bundle-id> | classify <url>] [--json] [--dry-run]",
                      YES, ^int(MMArgs *a) { return [me apps:MMMinMacsWords(a, @"apps")]; }),
        MMMinMacsVerb(@"status", @"status [--json]", NO, ^int(MMArgs *a) { return [me status:MMMinMacsWords(a, @"status")]; }),
        MMMinMacsVerb(@"restore", @"restore [rid] [--json] [--dry-run]", YES, ^int(MMArgs *a) { return [me restoreVerb:MMMinMacsWords(a, @"restore")]; }),
    ];
}

@end

#pragma mark - Policy

@implementation MMMinMacsPolicy

/// On facts read now: the app must run as the same instance, and its group must still let it go.
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    if ([f.kind isEqualToString:@"agent"]) return @"MinMacs never quits an agent";
    MMFinding *now = [self.expert finding:f.findingID in:facts];
    if (!now) return @"it is no longer running";
    if (f.instanceKey.length && ![now.instanceKey isEqualToString:f.instanceKey]) return @"it quit and opened again since";
    if (now.keepReasons.count) return now.keepReasons.firstObject;
    return nil;
}

- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }

/// Proactive never quits an app. Eager quits a close-list app only while memory pressure or heat is high.
/// No mode trims tabs on its own.
- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r {
    if ([f.proposal.verb isEqualToString:@"trim"]) return @"MinMacs trims tabs only when you ask";
    if (m != MMModeEager) return @"Proactive never quits an app on its own";
    // The load when the finding was made, which is at most one tick old.
    if ([f.facts[@"pressure"] integerValue] < 2 && [f.facts[@"thermal"] integerValue] < NSProcessInfoThermalStateSerious)
        return @"Eager quits apps only while memory pressure or heat is high";
    return nil;
}

@end

#pragma mark - Quit

@implementation MMMinMacsQuit

- (NSString *)kind { return @"quit"; }
- (MMProcKey)key { return KeyFrom(self.finding.instanceKey); }

- (NSString *)recheck {
    MMProcKey k = self.key;
    if (k.pid <= 1) return @"cannot verify which process it is";
    if (!MMProcAlive(k)) return @"it has already quit";
    if (self.step == MMStopKill && ![self.expert quitAskedFor:self.finding]) return @"Force Quit comes only after Quit";
    return nil;
}

- (NSString *)dryRun {
    return self.step == MMStopKill ? [NSString stringWithFormat:@"would force quit %@, pid %d. Unsaved changes are lost.", self.finding.title, self.key.pid]
                                   : [NSString stringWithFormat:@"would quit %@, pid %d. Restore opens it again.", self.finding.title, self.key.pid];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMFinding *f = self.finding;
    NSMutableDictionary *rl = [@{@"bundleID": f.facts[@"bundleID"] ?: @"", @"pid": f.instanceKey ?: @"",
                                 @"step": self.step == MMStopKill ? @"kill" : @"term"} mutableCopy];
    if ([f.facts[@"bundlePath"] length]) rl[@"url"] = f.facts[@"bundlePath"];
    [MMUndo.shared note:record payload:@{@"relaunch": rl}];
    NSTimeInterval grace = self.step == MMStopKill ? MIN(5, self.expert.grace) : self.expert.grace;
    NSArray *left = MMQuitApps(@[KeyValue(self.key)], self.step, grace);
    if (!left.count) return YES;
    if (error) *error = self.step == MMStopKill ? @"it still runs after Force Quit"
                                                : [NSString stringWithFormat:@"it did not quit in %.0f seconds. It may be asking to save. Force Quit is the second request", grace];
    return NO;
}

@end

#pragma mark - Trim

@implementation MMMinMacsTrim

- (NSString *)kind { return @"trim"; }

/// The noise tabs the bridge reads now, or nil with *why.
- (NSArray<MMMinMacsTab *> *)targets:(NSArray<MMMinMacsTab *> **)all why:(NSString **)why {
    MMFinding *f = self.finding;
    NSString *err = nil;
    NSArray<MMMinMacsTab *> *tabs = [MMMinMacsTabBridgeNow() tabsOf:KeyFrom(f.instanceKey).pid bundleID:f.facts[@"bundleID"] error:&err];
    if (!tabs) { if (why) *why = err ?: @"its tabs cannot be read"; return nil; }
    if (all) *all = tabs;
    MMMinMacsRules *rules = MMMinMacsRules.shared;
    NSMutableArray *noise = [NSMutableArray new];
    for (MMMinMacsTab *t in tabs) {
        t.verdict = [rules tabVerdictForHost:t.host];
        if (![t.verdict isEqualToString:@"noise"]) continue;
        if (self.onlyHost.length && !([t.host isEqualToString:self.onlyHost] || [t.host hasSuffix:[@"." stringByAppendingString:self.onlyHost]])) continue;
        [noise addObject:t];
    }
    return noise;
}

- (NSString *)recheck {
    MMProcKey k = KeyFrom(self.finding.instanceKey);
    if (k.pid <= 1) return @"cannot verify which process it is";
    if (!MMProcAlive(k)) return @"it has already quit";
    if (!MMMinMacsCanTrim(self.finding.facts[@"bundleID"])) return @"MinMacs cannot read this browser's tabs";
    NSString *why = nil;
    NSArray *noise = [self targets:NULL why:&why];
    if (!noise) return why;
    return noise.count ? nil : @"no noise tabs are open";
}

- (NSString *)dryRun {
    NSArray *all = nil;
    NSArray<MMMinMacsTab *> *noise = [self targets:&all why:NULL];
    NSMutableOrderedSet *hosts = [NSMutableOrderedSet new];
    for (MMMinMacsTab *t in noise) [hosts addObject:t.host];
    return [NSString stringWithFormat:@"would close %lu of %@ in %@: %@", (unsigned long)noise.count, MMPlural((NSInteger)all.count, @"tab"),
            self.finding.title, [hosts.array componentsJoinedByString:@", "]];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMFinding *f = self.finding;
    NSString *why = nil;
    NSArray<MMMinMacsTab *> *noise = [self targets:NULL why:&why];
    if (!noise.count) { if (error) *error = why ?: @"no noise tabs are open"; return NO; }
    NSMutableDictionary *rl = [@{@"bundleID": f.facts[@"bundleID"] ?: @""} mutableCopy];
    if ([f.facts[@"bundlePath"] length]) rl[@"url"] = f.facts[@"bundlePath"];
    [MMUndo.shared note:record payload:@{@"relaunch": rl, @"pid": f.instanceKey ?: @""}];
    NSArray<MMMinMacsTab *> *closed = [MMMinMacsTabBridgeNow() close:noise pid:KeyFrom(f.instanceKey).pid bundleID:f.facts[@"bundleID"]];
    // Only the tabs that closed go in the record, so Restore never opens a tab twice.
    NSMutableArray *tabs = [NSMutableArray new], *hosts = [NSMutableArray new];
    for (MMMinMacsTab *t in closed) { [tabs addObject:@{@"url": t.url ?: @"", @"host": t.host ?: @"", @"title": t.title ?: @""}]; [hosts addObject:t.host ?: @""]; }
    [MMUndo.shared note:record payload:@{@"tabs": tabs, @"closed": hosts}];
    if (closed.count) return YES;
    if (error) *error = @"no tab closed. Each one had moved on since it was read";
    return NO;
}

@end

#pragma mark - Rule

@implementation MMMinMacsListRule

- (NSString *)ruleID { return @"minmacs.lists"; }

- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts {
    MMVerdict *v = [MMVerdict new];
    v.findingID = f.findingID; v.fingerprint = f.fingerprint; v.decidedBy = self.ruleID; v.confidence = 1;
    if ([f.kind isEqualToString:@"agent"]) { v.kind = MMVerdictKeep; v.reason = @"an agent"; }
    else switch (GroupOf(f)) {
        case MMGroupQuit: case MMGroupTrim: v.kind = MMVerdictGo; v.reason = @"on the close list, and nothing uses it"; break;
        case MMGroupSpared: case MMGroupKept: v.kind = MMVerdictKeep; v.reason = f.keepReasons.firstObject ?: @"kept"; break;
        case MMGroupUnsorted: v.kind = MMVerdictUnsure; v.reason = @"on no list"; break;
    }
    v.word = [MMMinMacsExpert.shared.words wordFor:v.kind];
    v.about = f.title;
    return v;
}

@end
