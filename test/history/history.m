// Checks for the last hour in memory, Graph/MMHistory.h. Built by test/history.sh with all of Sources but main.m.
// Every sample is a fixture: values and times passed by hand, fake agents and a fake LocoHost expert for the graph,
// and a fake cmux CLI for the events. It starts no process but the fake cmux, and reads no file outside MINMACS_HOME.
// Usage: history rings | graph | events. Prints one line per check: name, want and got, split by tabs.
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"

static void Check(NSString *name, id want, id got) {
    printf("%s\t%s\t%s\n", name.UTF8String, [[want description] UTF8String], [[got description] UTF8String]);
    fflush(stdout);
}

static void Spin(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!(done && done()) && [until timeIntervalSinceNow] > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// A fixed minute, far from the edges of uint32 minutes.
static const NSTimeInterval T0 = 1800000000;   // 2027-01-15, the start of a minute
static NSTimeInterval At(double minutes) { return T0 + minutes * 60; }

static MMHistoryTreeSample *Tree(MMHistoryKind kind, pid_t pid, uint64_t start, double cpu, uint64_t mb, MMAgentState st) {
    MMHistoryTreeSample *x = [MMHistoryTreeSample new];
    x.kind = kind; x.key = (MMProcKey){ pid, start }; x.cpuPercent = cpu; x.footprint = mb << 20; x.state = st;
    x.label = kind == MMHistoryAgent ? @"claude-code" : @":3000 next app";
    x.ident = [NSString stringWithFormat:@"%@-%d", kind == MMHistoryAgent ? @"session" : @"locohost:server:/fixture#dev", pid];
    return x;
}

static NSString *Mins(MMHistoryRing *r, NSUInteger from, NSUInteger to, BOOL cpu) {
    NSMutableArray *a = [NSMutableArray new];
    for (NSUInteger i = from; i <= to; i++) {
        MMHistoryMinute m = [r minuteAt:i];
        [a addObject:m.passes ? [NSString stringWithFormat:@"%g", round((cpu ? m.cpuPercent : m.megabytes) * 10) / 10] : @"-"];
    }
    return [a componentsJoinedByString:@","];
}

static uint64_t Footprint(void) {
    task_vm_info_data_t vm; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &n) == KERN_SUCCESS ? vm.phys_footprint : 0;
}

#pragma mark - The rings, from values given by hand

static void Rings(void) {
    MMHistory *h = [MMHistory new];
    MMHistoryView *v = [h viewAt:At(0)];
    Check(@"an empty store has no rings and no Mac ring", @"0 nil", [NSString stringWithFormat:@"%lu %@", (unsigned long)v.rings, v.mac ? @"set" : @"nil"]);

    // A minute with no pass. Minutes 0 and 1 get passes, 2 gets none, 3 gets one.
    [h noteMacCPU:20 memoryUsed:1000ull << 20 diskFree:5000ull << 20 at:At(0) + 5];
    [h noteMacCPU:40 memoryUsed:2000ull << 20 diskFree:5000ull << 20 at:At(0) + 35];
    [h noteMacCPU:10 memoryUsed:3000ull << 20 diskFree:4000ull << 20 at:At(1) + 5];
    [h noteMacCPU:70 memoryUsed:4000ull << 20 diskFree:3000ull << 20 at:At(3) + 5];
    v = [h viewAt:At(3) + 10];
    Check(@"the Mac ring holds the mean of each minute's passes", @"30,10,-,70", Mins(v.mac, 56, 59, YES));
    Check(@"  and memory used the same way, in MB", @"1500,3000,-,4000", Mins(v.mac, 56, 59, NO));
    Check(@"the disk ring holds free space a minute", @"5000,4000,-,3000", Mins(v.disk, 56, 59, NO));
    Check(@"a minute with no pass has no passes and no values", @"0 -1 -1",
          [NSString stringWithFormat:@"%u %g %g", [v.mac minuteAt:58].passes, [v.mac minuteAt:58].cpuPercent, [v.mac minuteAt:58].megabytes]);
    Check(@"  and the minutes before the first pass are gaps too", @"0", @([v.mac minuteAt:0].passes));
    NSDictionary *j = v.json;
    Check(@"in JSON a minute with no pass is null", @"[30, 10, <null>, 70]",
          [NSString stringWithFormat:@"[%@]", [[[j[@"mac"][@"cpuPercent"] subarrayWithRange:NSMakeRange(56, 4)] valueForKey:@"description"]
                                               componentsJoinedByString:@", "]]);
    Check(@"  every ring holds 60 minutes", @"60 60", [NSString stringWithFormat:@"%lu %lu",
          (unsigned long)[j[@"mac"][@"cpuPercent"] count], (unsigned long)[j[@"disk"][@"freeMB"] count]]);
    // An hour later the old minutes have left the window, though the slots still hold them.
    v = [h viewAt:At(63) + 10];
    Check(@"an hour on, minutes older than the hour are gaps", @"0", @(({ NSUInteger n = 0; for (NSUInteger i = 0; i < 60; i++) n += [v.mac minuteAt:i].passes; n; })));
    [h noteMacCPU:55 memoryUsed:1ull << 20 diskFree:0 at:At(60) + 5];
    v = [h viewAt:At(60) + 10];
    Check(@"a slot used again an hour later holds only the new minute", @"55 1", [NSString stringWithFormat:@"%g %u", [v.mac minuteAt:59].cpuPercent, [v.mac minuteAt:59].passes]);
    Check(@"  and a pass with no disk value leaves the disk ring alone", @"0", @([v.disk minuteAt:59].passes));

    // A reused pid: the same pid with a new start time is another process, so it starts a new ring.
    h = [MMHistory new];
    [h noteTrees:@[Tree(MMHistoryServer, 4242, 100, 50, 100, MMAgentUnknown)] at:At(0) + 5];
    [h noteTrees:@[Tree(MMHistoryServer, 4242, 100, 30, 300, MMAgentUnknown)] at:At(1) + 5];
    [h noteTrees:@[Tree(MMHistoryServer, 4242, 200, 5, 20, MMAgentUnknown)] at:At(2) + 5];
    v = [h viewAt:At(2) + 10];
    MMHistoryRing *old = [v treeFor:(MMProcKey){ 4242, 100 }], *reused = [v treeFor:(MMProcKey){ 4242, 200 }];
    Check(@"a reused pid starts a ring of its own", @"2 yes yes", [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)v.trees.count,
          old ? @"yes" : @"no", reused ? @"yes" : @"no"]);
    Check(@"  the old process keeps its own minutes", @"50,30,-", Mins(old, 57, 59, YES));
    Check(@"  the new one starts empty and holds only its own", @"-,-,5 -,-,20", [NSString stringWithFormat:@"%@ %@", Mins(reused, 57, 59, YES), Mins(reused, 57, 59, NO)]);
    Check(@"  the old one is marked gone when the new one came", @(At(2) + 5), @(old.goneAt));
    Check(@"  the new one is live", @0, @(reused.goneAt));

    // A gone process keeps its ring for 10 minutes, then it is dropped.
    h = [MMHistory new];
    [h noteTrees:@[Tree(MMHistoryAgent, 500, 50, 10, 64, MMAgentWorking), Tree(MMHistoryServer, 600, 60, 1, 32, 0)] at:At(0) + 5];
    [h noteTrees:@[Tree(MMHistoryServer, 600, 60, 1, 32, 0)] at:At(1) + 5];
    v = [h viewAt:At(1) + 10];
    MMHistoryRing *agent = [v treeFor:(MMProcKey){ 500, 50 }];
    Check(@"a tree missing from a pass is gone at that pass", @(At(1) + 5), @(agent.goneAt));
    Check(@"  its ring stays, with its minutes", @"10,-", Mins(agent, 58, 59, YES));
    Check(@"  in JSON gone is the time it went", @(round(At(1) + 5)), agent.json[@"gone"]);
    [h noteTrees:@[Tree(MMHistoryServer, 600, 60, 1, 32, 0)] at:At(10) + 4];
    v = [h viewAt:At(10) + 5];
    Check(@"  it is still held at 9 minutes 59 seconds", @"yes", [v treeFor:(MMProcKey){ 500, 50 }] ? @"yes" : @"no");
    [h noteTrees:@[Tree(MMHistoryServer, 600, 60, 1, 32, 0)] at:At(11) + 5];
    v = [h viewAt:At(11) + 6];
    Check(@"  and dropped at 10 minutes", @"no 1 1", [NSString stringWithFormat:@"%@ %lu %lu", [v treeFor:(MMProcKey){ 500, 50 }] ? @"yes" : @"no",
          (unsigned long)v.dropped, (unsigned long)v.trees.count]);
    // A process seen again before its ring is dropped picks the ring up again.
    [h noteTrees:@[] at:At(12) + 5];
    [h noteTrees:@[Tree(MMHistoryServer, 600, 60, 2, 32, 0)] at:At(13) + 5];
    v = [h viewAt:At(13) + 6];
    Check(@"a tree back before 10 minutes is live again in the same ring", @"0 1,-,2", [NSString stringWithFormat:@"%g %@",
          [v treeFor:(MMProcKey){ 600, 60 }].goneAt, Mins([v treeFor:(MMProcKey){ 600, 60 }], 57, 59, YES)]);

    // Agent state changes, with times. A state that holds adds nothing.
    h = [MMHistory new];
    MMAgentState states[] = { MMAgentWorking, MMAgentWorking, MMAgentWaiting, MMAgentWorking, MMAgentIdle, MMAgentIdle };
    for (int i = 0; i < 6; i++) [h noteTrees:@[Tree(MMHistoryAgent, 700, 70, 5, 64, states[i])] at:At(i) + 1];
    agent = [[h viewAt:At(6)] treeFor:(MMProcKey){ 700, 70 }];
    NSMutableArray *seen = [NSMutableArray new];
    for (NSDictionary *c in agent.json[@"states"]) [seen addObject:[NSString stringWithFormat:@"%@@%d", c[@"state"], (int)(([c[@"at"] doubleValue] - T0 - 1) / 60)]];
    Check(@"each agent's state changes are kept with their times", @"working@0 waiting@2 working@3 idle@4", [seen componentsJoinedByString:@" "]);
    for (int i = 0; i < 80; i++) [h noteTrees:@[Tree(MMHistoryAgent, 700, 70, 5, 64, i % 2 ? MMAgentWorking : MMAgentIdle)] at:At(6) + i];
    agent = [[h viewAt:At(8)] treeFor:(MMProcKey){ 700, 70 }];
    Check(@"  at most 32 changes are kept per agent, the newest", @"32 working", [NSString stringWithFormat:@"%lu %@",
          (unsigned long)agent.stateChanges.count, [agent.json[@"states"] lastObject][@"state"]]);
    agent = [[h viewAt:At(70)] treeFor:(MMProcKey){ 700, 70 }];
    Check(@"  changes older than the hour are left out of a copy", @"0", @(agent.stateChanges.count));
    Check(@"a server ring has no states", @"nil", old.json[@"states"] ?: @"nil");

    // Subagent starts for the last hour.
    h = [MMHistory new];
    [h noteSubagentStart:@"claude-code" session:@"s-old" at:At(-70)];
    [h noteSubagentStart:@"claude-code" session:@"s-1" at:At(1)];
    [h noteSubagentStart:@"claude-code" session:@"s-1" at:At(1)];
    [h noteSubagentStart:@"codex" session:@"s-2" at:At(2)];
    v = [h viewAt:At(3)];
    Check(@"subagent starts within the hour, once each, oldest first", @"s-1 s-2",
          [[v.subagentStarts valueForKey:@"session"] componentsJoinedByString:@" "]);
    for (int i = 0; i < 300; i++) [h noteSubagentStart:@"claude-code" session:[NSString stringWithFormat:@"c-%d", i] at:At(3) + i];
    v = [h viewAt:At(10)];
    Check(@"  at most 256 starts are kept, the newest", @"256 c-44 c-299", [NSString stringWithFormat:@"%lu %@ %@",
          (unsigned long)v.subagentStarts.count, v.subagentStarts.firstObject[@"session"], v.subagentStarts.lastObject[@"session"]]);

    // The caps: 200 rings at most, the Mac and the disk among them.
    NSMutableArray *many = [NSMutableArray new];
    for (int i = 0; i < 250; i++) [many addObject:Tree(i % 2 ? MMHistoryServer : MMHistoryAgent, 10000 + i, 1, 1, 1, MMAgentWorking)];
    uint64_t f0 = Footprint();
    h = [MMHistory new];
    for (int m = 0; m < 60; m++) @autoreleasepool {
        [h noteMacCPU:m memoryUsed:1ull << 30 diskFree:1ull << 30 at:At(m)];
        [h noteTrees:many at:At(m)];
        for (int k = 0; k < 4; k++) [h noteSubagentStart:@"claude-code" session:[NSString stringWithFormat:@"%d-%d", m, k] at:At(m) + k];
    }
    // Every state slot full as well.
    for (int i = 0; i < 40; i++) @autoreleasepool {
        for (MMHistoryTreeSample *x in many) x.state = i % 2 ? MMAgentIdle : MMAgentWorking;
        [h noteTrees:many at:At(59) + i];
    }
    v = [h viewAt:At(59) + 50];
    Check(@"250 trees give 200 rings: 198 trees, the Mac and the disk", @"200 198", [NSString stringWithFormat:@"%lu %lu", (unsigned long)v.rings, (unsigned long)v.trees.count]);
    Check(@"  the trees past the cap are counted as refused", @"yes", v.refused >= 52 ? @"yes" : @(v.refused));
    Check(@"  every kept ring is full for the hour", @"60", @(({ NSUInteger n = 0; for (NSUInteger i = 0; i < 60; i++) n += [v.trees.lastObject minuteAt:i].passes > 0; n; })));
    Check(@"the store is under 1 MB at the caps", @"yes", v.storeBytes < 1048576 ? @"yes" : @(v.storeBytes));
    Check(@"  and so is a copy of it", @"yes", v.copyBytes < 1048576 ? @"yes" : @(v.copyBytes));
    uint64_t f1 = Footprint();
    int64_t grew = (int64_t)f1 - (int64_t)f0;        // signed, so a footprint that shrank reads as growth below 0
    Check(@"  the footprint grew under 1 MB with the full store and a copy", @"yes", grew < 1048576 ? @"yes" : @(grew));
    printf("info\tstore %lu bytes, copy %lu bytes, footprint %+lld bytes\n", (unsigned long)v.storeBytes, (unsigned long)v.copyBytes, grew);
    // When a tree goes, the next new one takes its ring, so live trees are never pushed out.
    [many removeObjectsInRange:NSMakeRange(198, many.count - 198)];   // the 198 trees the store holds
    [many removeObjectAtIndex:0];
    [many addObject:Tree(MMHistoryServer, 30000, 1, 1, 1, 0)];
    [h noteTrees:many at:At(60)];
    Check(@"  a new tree while 198 live trees fill the store is refused", @"no", [[h viewAt:At(60) + 1] treeFor:(MMProcKey){ 30000, 1 }] ? @"yes" : @"no");
    [h noteTrees:many at:At(60) + 5];
    v = [h viewAt:At(60) + 6];
    Check(@"a full store makes room by dropping the oldest gone ring", @"yes no",
          [NSString stringWithFormat:@"%@ %@", [v treeFor:(MMProcKey){ 30000, 1 }] ? @"yes" : @"no", [v treeFor:(MMProcKey){ 10000, 1 }] ? @"yes" : @"no"]);
}

#pragma mark - The graph fills it

@interface TAgent : NSObject
@property (copy) NSString *harnessID, *sessionID, *cwd, *why;
@property MMProcKey key; @property MMAgentState state;
@property double treeCPU; @property uint64_t treeFootprint;
@end
@implementation TAgent @end

@interface TSample : NSObject
@property NSDate *at; @property uint64_t generation; @property NSDictionary *procs;
@end
@implementation TSample
- (id)proc:(pid_t)pid { return nil; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return nil; }
- (NSArray *)childrenOf:(pid_t)pid { return @[]; }
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops { return @[]; }
- (NSArray *)treeOf:(pid_t)pid limit:(NSUInteger)max { return @[@(pid)]; }
@end

/// The fixture world: agents and servers the checks change between builds.
@interface TWorld : NSObject <MMFactSource>
@property NSArray<TAgent *> *agents;
@property NSArray<NSDictionary *> *servers;   // pid, start, cpu, mb
@property uint64_t diskFree;
@end
@implementation TWorld
- (MMFacts *)factsFor:(uint64_t)generation {
    TSample *s = [TSample new]; s.at = NSDate.date; s.generation = generation; s.procs = @{};
    MMPower *p = MMPowerFrom(@{@"diskFree": @(self.diskFree), @"onAC": @YES});
    return [MMFacts generation:generation sample:(MMSample *)s power:p agents:(NSArray *)self.agents sessions:@[] worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

static TWorld *gWorld;

@interface TLocoHost : NSObject <MMExpert>
@end
@implementation TLocoHost
- (NSString *)expertID { return @"locohost"; }
- (NSString *)name { return @"LocoHost"; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return nil; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *d in gWorld.servers)
        [out addObject:[MMFinding expert:@"locohost" kind:@"server" stableKey:[NSString stringWithFormat:@"/fixture/%@#dev", d[@"pid"]]
                                   build:^(MMFindingBuilder *b) {
            MMProcKey k = { [d[@"pid"] intValue], [d[@"start"] unsignedLongLongValue] };
            b.title = [NSString stringWithFormat:@":%@ fixture", d[@"pid"]];
            b.procs = @[[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
            b.cost = (MMCost){ .ramBytes = [d[@"mb"] unsignedLongLongValue] << 20, .cpuPercent = [d[@"cpu"] doubleValue] };
        }]];
    return out;
}
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return nil; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return nil; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return NO; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
@end

static TAgent *Agent(pid_t pid, uint64_t start, MMAgentState st, double cpu, uint64_t mb) {
    TAgent *a = [TAgent new];
    a.harnessID = @"claude-code"; a.sessionID = [NSString stringWithFormat:@"sess-%d", pid]; a.cwd = @"/fixture";
    a.key = (MMProcKey){ pid, start }; a.state = st; a.treeCPU = cpu; a.treeFootprint = mb << 20;
    return a;
}

/// One build through the shared graph, waited for on main until main's snapshot shows what the check set up.
/// A build that was already running when the world changed can land first, so a new generation alone is not
/// enough. 30 seconds, since five agents build on this Mac at once.
static MMSnapshot *Build(MMGraph *g, BOOL (^ready)(MMSnapshot *s)) {
    uint64_t before = g.latest.generation;
    [g rebuild:@"history test"];
    Spin(30, ^BOOL { return g.current.generation > before && ready(g.current); });
    return g.current;
}

/// A JSON value read with no exception when a level is missing or null.
static id Dig(id j, NSArray *path) {
    for (id k in path) {
        if ([k isKindOfClass:NSNumber.class]) j = [j isKindOfClass:NSArray.class] && [j count] > [k unsignedIntegerValue] ? j[[k unsignedIntegerValue]] : nil;
        else j = [j isKindOfClass:NSDictionary.class] ? j[k] : nil;
    }
    return j;
}

static void Graph(void) {
    gWorld = [TWorld new];
    gWorld.agents = @[Agent(900, 90, MMAgentWorking, 12.5, 200)];
    gWorld.servers = @[@{@"pid": @901, @"start": @91, @"cpu": @3, @"mb": @80}];
    gWorld.diskFree = 7000ull << 20;
    MMRegisterExpert([TLocoHost new]);
    MMGraph *g = MMGraph.shared;
    g.source = gWorld;
    [g start];
    MMSnapshot *s1 = Build(g, ^BOOL(MMSnapshot *s) { return [s.history treeFor:(MMProcKey){ 901, 91 }] != nil; });
    Check(@"a graph build hands its snapshot a copy of the hour", @"yes", s1.history ? @"yes" : @"no");
    Check(@"  the build filled the agent's and the server's rings", @"agent server",
          [[s1.history.trees valueForKey:@"kind"] count] == 2 ? [NSString stringWithFormat:@"%@ %@", MMHistoryKindName(s1.history.trees[0].kind), MMHistoryKindName(s1.history.trees[1].kind)] : @(s1.history.trees.count));
    MMHistoryMinute am = [[s1.history treeFor:(MMProcKey){ 900, 90 }] minuteAt:59];
    Check(@"  the agent ring holds its tree CPU and footprint", @"12.5 200", [NSString stringWithFormat:@"%g %g", am.cpuPercent, am.megabytes]);
    MMHistoryMinute sm = [[s1.history treeFor:(MMProcKey){ 901, 91 }] minuteAt:59];
    Check(@"  the server ring holds its finding's cost", @"3 80", [NSString stringWithFormat:@"%g %g", sm.cpuPercent, sm.megabytes]);
    Check(@"  the server ring is named by its finding", @"locohost:server:/fixture/901#dev", [s1.history treeFor:(MMProcKey){ 901, 91 }].ident);
    Check(@"  the disk ring holds the power facts' free space", @"7000", @([s1.history.disk minuteAt:59].megabytes));
    // The Mac's CPU needs two reads of the host's ticks, so a second build fills it.
    gWorld.agents = @[Agent(900, 90, MMAgentIdle, 1, 210)];
    gWorld.servers = @[@{@"pid": @901, @"start": @92, @"cpu": @4, @"mb": @90}];
    [NSThread sleepForTimeInterval:0.3];              // the host counts CPU in ticks of 10 ms
    MMSnapshot *s2 = Build(g, ^BOOL(MMSnapshot *s) {
        return [s.history treeFor:(MMProcKey){ 901, 92 }] != nil && [s.history.mac minuteAt:59].passes > 0;
    });
    MMHistoryMinute mac = [s2.history.mac minuteAt:59];
    Check(@"a second build fills the Mac ring with CPU and memory used", @"yes",
          mac.passes >= 1 && mac.cpuPercent >= 0 && mac.cpuPercent <= 100 && mac.megabytes > 100 ? @"yes" : [NSString stringWithFormat:@"%u %g %g", mac.passes, mac.cpuPercent, mac.megabytes]);
    Check(@"  the agent's state change is in its ring", @"working idle",
          [[[s2.history treeFor:(MMProcKey){ 900, 90 }].json[@"states"] valueForKey:@"state"] componentsJoinedByString:@" "]);
    Check(@"  the server that restarted on the same pid has a new ring, the old one gone", @"yes yes",
          [NSString stringWithFormat:@"%@ %@", [s2.history treeFor:(MMProcKey){ 901, 92 }] ? @"yes" : @"no",
           [s2.history treeFor:(MMProcKey){ 901, 91 }].goneAt > 0 ? @"yes" : @"no"]);
    Check(@"  the first snapshot's copy did not change", @"1 2", [NSString stringWithFormat:@"%lu %lu",
          (unsigned long)[[s1.history treeFor:(MMProcKey){ 900, 90 }] stateChanges].count, (unsigned long)[[s2.history treeFor:(MMProcKey){ 900, 90 }] stateChanges].count]);
    Check(@"MMHistory.latest is the last build's copy", @"yes", MMHistory.shared.latest == s2.history ? @"yes" : @"no");
    // minmacs history in the app, the way core.sock hands it over.
    NSDictionary *r = MMCLIReply(@{@"cli": @[@"history", @"--json"]});
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:[r[@"out"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    Check(@"minmacs history --json in the app reads the snapshot's copy", @"0 1 1 2 1", [NSString stringWithFormat:@"%@ %@ %lu %lu %@",
          r[@"status"], j[@"app"], (unsigned long)[j[@"agents"] count], (unsigned long)[j[@"servers"] count], Dig(j, @[@"agents", @0, @"pid"]) ? @1 : @0]);
    Check(@"  with 60 minutes per ring and the caps", @"60 60 200 600", [NSString stringWithFormat:@"%lu %lu %@ %@",
          (unsigned long)[Dig(j, @[@"mac", @"cpuPercent"]) count], (unsigned long)[Dig(j, @[@"agents", @0, @"footprintMB"]) count], j[@"maxRings"], j[@"goneKeepSeconds"]]);
    r = MMCLIReply(@{@"cli": @[@"history"]});
    Check(@"minmacs history in the app says what it holds", @"yes", [r[@"out"] hasPrefix:@"The last hour: "] ? @"yes" : r[@"out"]);
    [g stop];
}

#pragma mark - Subagent starts from the events reader

static void Events(void) {
    [MMHistory.shared start];
    [MMAgentEvents.shared start];
    Spin(5, ^BOOL { return MMHistory.shared.latest.subagentStarts.count >= 1; });
    NSArray *subs = [MMHistory.shared viewAt:NSDate.date.timeIntervalSince1970].subagentStarts;
    Check(@"a SubagentStart event from cmux lands in the hour", @"claude-code sub-sess", subs.count == 1 ?
          [NSString stringWithFormat:@"%@ %@", subs[0][@"agent"], subs[0][@"session"]] : @(subs.count));
    [MMAgentEvents.shared stop];
    [MMHistory.shared stop];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqualToString:@"rings"]) Rings();
        else if ([mode isEqualToString:@"graph"]) Graph();
        else if ([mode isEqualToString:@"events"]) Events();
        else { fprintf(stderr, "usage: history rings | graph | events\n"); return 2; }
    }
    return 0;
}
