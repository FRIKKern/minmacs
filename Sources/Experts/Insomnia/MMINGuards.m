// Insomnia's prefs, guards, input and decision. Everything here is a pure function of its arguments,
// except +[MMINPrefs current], which reads the prefs. The engine in MMInsomniaExpert.m applies what MMINDecide says.
// Ported from Insomnia's main.m: the pref getters at 221-255, -syncLid at 648, -pauseReason at 631 and
// -evaluateAgents at 478, with MinMacs' agents in place of `minmacs agents --json`.
#import "Experts/Insomnia/MMInsomnia.h"
#import "UI/MMFormat.h"

#pragma mark - Prefs

static BOOL Bool(NSString *key, BOOL dflt) { return MMPrefBool(key, dflt); }
static NSInteger Int(NSString *key, NSInteger dflt) {
    id v = MMPref(key);
    return [v isKindOfClass:NSNumber.class] ? [v integerValue] : dflt;
}

@implementation MMINPrefs (MMINStore)
+ (instancetype)current {
    MMINPrefs *d = [MMINPrefs defaults], *p = [MMINPrefs new];
    p.manual = Bool(@"insomnia.awake", d.manual);
    p.agents = Bool(@"insomnia.agents", d.agents);
    p.lid = Bool(@"insomnia.lid", d.lid);
    p.screenOff = Bool(@"insomnia.lid.screenOff", d.screenOff);
    p.thermalGuard = Bool(@"insomnia.lid.thermalGuard", d.thermalGuard);
    p.minBattery = Int(@"insomnia.lid.minBattery", d.minBattery);
    p.graceMinutes = MAX(0, Int(@"insomnia.lid.graceMinutes", d.graceMinutes));
    p.offlineMinutes = MAX(0, Int(@"insomnia.lid.offlineMinutes", d.offlineMinutes));
    NSInteger q = Int(@"insomnia.agents.quietMinutes", d.quietMinutes);
    p.quietMinutes = q > 0 ? q : d.quietMinutes;
    return p;
}
@end

#pragma mark - Guards

MMINClocks *MMINAdvance(MMINClocks *old, MMPower *p, MMINPrefs *prefs, NSDate *now) {
    MMINClocks *c = old ? [old copy] : [MMINClocks new];
    if (p.onAC) c.unpluggedAt = nil;
    else if (!c.unpluggedAt) c.unpluggedAt = now;
    if (p.online) c.offlineAt = nil;
    else if (!c.offlineAt) c.offlineAt = now;
    // The bag guard: hot while shut on battery sets a hold that only the charger or an open lid clears,
    // so a laptop that cools and heats again in the bag cannot switch back and forth.
    if (p.onAC || !p.lidClosed || !prefs.thermalGuard) c.thermalHold = NO;
    else if (p.thermal >= NSProcessInfoThermalStateSerious) c.thermalHold = YES;
    return c;
}

NSString *MMINPauseReason(MMPower *p, MMINPrefs *prefs, MMINClocks *c, NSDate *now) {
    if (!p || p.onAC) return nil;
    // The words leave out the numbers, which the header and the lid card's facts show once each.
    if (p.batteryPercent >= 0 && p.batteryPercent <= prefs.minBattery) return @"low battery";
    NSTimeInterval unplugged = c.unpluggedAt ? [now timeIntervalSinceDate:c.unpluggedAt] : 0;
    if (prefs.graceMinutes > 0 && unplugged > prefs.graceMinutes * 60) return @"unplugged too long";
    if (c.thermalHold) return @"hot with the lid closed";
    NSTimeInterval offline = c.offlineAt ? [now timeIntervalSinceDate:c.offlineAt] : 0;
    if (prefs.offlineMinutes > 0 && offline > prefs.offlineMinutes * 60) return @"offline too long";
    return nil;
}

BOOL MMINLowBattery(MMPower *p, MMINPrefs *prefs) {
    return p && !p.onAC && p.batteryPercent >= 0 && p.batteryPercent <= prefs.minBattery;
}

#pragma mark - Input

static NSString *HarnessName(NSString *harness, NSDictionary *names) {
    if (names[harness]) return names[harness];
    NSDictionary *known = @{@"claude-code": @"Claude Code", @"codex": @"Codex", @"cursor": @"Cursor", @"pi": @"pi"};
    return known[harness] ?: harness ?: @"Agent";
}

MMINInput *MMINInputFrom(MMFacts *facts) {
    MMINInput *in = [MMINInput new];
    NSMutableArray *workers = [NSMutableArray new];
    NSMutableSet *pids = [NSMutableSet new];
    NSMutableDictionary *names = [NSMutableDictionary new];
    for (MMAgent *a in facts.agents) {
        if (a.key.pid <= 1) continue;
        MMINWorker *w = [MMINWorker new];
        w.kind = @"agent"; w.key = a.key;
        w.harness = a.harnessID; w.sessionID = a.sessionID; w.cwd = a.cwd; w.why = a.why;
        w.name = a.row.name ?: HarnessName(a.harnessID, names);
        if (a.harnessID && a.row.name) names[a.harnessID] = a.row.name;
        w.working = a.state == MMAgentWorking;
        w.stableKey = [NSString stringWithFormat:@"%@:%@", a.harnessID ?: @"agent", a.sessionID.length ? a.sessionID : a.cwd.length ? a.cwd : w.name];
        [workers addObject:w];
        [pids addObject:@(a.key.pid)];
    }
    // A session whose pid the registry did not match still counts, by its own live status.
    for (MMSession *s in facts.sessions) {
        if (s.pid <= 1 || [pids containsObject:@(s.pid)]) continue;
        MMProc *p = [facts.sample proc:s.pid];
        if (!p) continue;
        MMINWorker *w = [MMINWorker new];
        w.kind = @"session"; w.key = p.key;
        w.harness = s.agent; w.sessionID = s.sessionID; w.cwd = s.cwd;
        w.name = HarnessName(s.agent, names);
        w.working = s.stillWorking && ![s.liveStatus isEqualToString:@"waiting"];
        w.why = s.liveStatus.length ? [@"status " stringByAppendingString:s.liveStatus] : nil;
        w.stableKey = [NSString stringWithFormat:@"%@:%@", s.agent ?: @"session", s.sessionID.length ? s.sessionID : s.cwd ?: @(s.pid).stringValue];
        [workers addObject:w];
        [pids addObject:@(s.pid)];
    }
    in.workers = workers;
    uid_t me = getuid();
    for (MMProc *p in facts.sample.procs.objectEnumerator)
        if (p.uid == me && [p.name isEqualToString:@"Insomnia"]) { in.otherApp = YES; break; }
    return in;
}

#pragma mark - Decision

static MMProcKey KeyFrom(NSString *s) {
    NSArray *parts = [s componentsSeparatedByString:@":"];
    MMProcKey k = { 0, 0 };
    if (parts.count == 2) { k.pid = (pid_t)[parts[0] intValue]; k.startSec = (uint64_t)[parts[1] longLongValue]; }
    return k;
}

MMINState *MMINDecide(MMINInput *input, MMPower *power, MMINPrefs *prefs, MMINClocks *clocks,
                      NSDictionary<NSString *, NSDate *> *last, NSSet<NSString *> *skipped,
                      NSDictionary<NSString *, NSString *> *explicitHolds, MMSnapshot *s, NSDate *now) {
    MMINState *st = [MMINState new];
    st.prefs = prefs; st.clocks = clocks; st.at = now;
    st.onAC = power ? power.onAC : YES; st.lidClosed = power.lidClosed; st.online = power ? power.online : YES;
    st.batteryPercent = power ? power.batteryPercent : -1; st.thermal = power.thermal;
    st.laptop = st.batteryPercent >= 0;
    st.otherApp = input.otherApp;
    st.lowBattery = MMINLowBattery(power, prefs);

    NSMutableArray<MMINHolder *> *holders = [NSMutableArray new];
    NSTimeInterval quiet = prefs.quietMinutes * 60, releaseIn = 0;
    BOOL anyWorking = NO;
    NSInteger watched = 0;
    for (MMINWorker *w in input.workers) {
        watched++;
        if (!prefs.agents) continue;
        NSString *ks = MMProcKeyString(w.key);
        if ([skipped containsObject:ks]) continue;
        NSDate *lastAt = w.working ? now : last[ks];
        NSTimeInterval idle = w.working ? 0 : lastAt ? MAX(0, [now timeIntervalSinceDate:lastAt]) : INFINITY;
        if (!w.working && idle >= quiet) continue;
        MMINHolder *h = [MMINHolder new];
        h.findingID = [NSString stringWithFormat:@"insomnia:%@:%@", w.kind, w.stableKey];
        h.kind = w.kind; h.name = w.name; h.project = w.cwd.lastPathComponent; h.why = w.why;
        h.keyString = ks; h.pid = w.key.pid; h.working = w.working; h.idleFor = w.working ? 0 : idle;
        if (w.working) anyWorking = YES; else releaseIn = MAX(releaseIn, quiet - idle);
        NSString *mm = [NSString stringWithFormat:@"minmacs:agent:%@:%@", w.harness ?: @"", w.sessionID ?: @""];
        if (w.sessionID.length && [s finding:mm]) {
            h.linkExpert = @"minmacs"; h.linkFindingID = mm;
            h.linkValue = [NSString stringWithFormat:@"%@, %@", w.name, w.working ? @"working" : @"idle"];
        }
        [holders addObject:h];
    }
    for (NSString *ks in [explicitHolds.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if ([skipped containsObject:ks]) continue;
        MMProcKey k = KeyFrom(ks);
        if (k.pid <= 1) continue;
        MMINHolder *h = [MMINHolder new];
        h.findingID = [@"insomnia:hold:" stringByAppendingString:ks];
        h.kind = @"hold"; h.keyString = ks; h.pid = k.pid; h.working = YES;
        NSString *name = [s.facts.sample proc:k.pid].name;
        h.name = name.length ? name : [NSString stringWithFormat:@"pid %d", k.pid];
        h.why = explicitHolds[ks].length ? explicitHolds[ks] : @"held by request";
        [holders addObject:h];
    }
    // Working first, then the quiet ones, newest idle first, so the rows read in order of need.
    [holders sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MMINHolder *a, MMINHolder *b) {
        if (a.working != b.working) return a.working ? NSOrderedAscending : NSOrderedDescending;
        if (a.idleFor != b.idleFor) return a.idleFor < b.idleFor ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    // Manual wins: with Keep Mac Awake on, one hold of MinMacs' own does it, and no agent needs its own.
    // On low battery the agent holds end. Keep Mac Awake stays, since the person asked for it.
    BOOL agentHolds = !prefs.manual && !st.lowBattery && holders.count > 0;
    for (MMINHolder *h in holders) h.held = agentHolds;
    st.holders = holders;
    st.watched = watched;
    st.holding = prefs.manual || agentHolds;
    st.releaseIn = agentHolds && !anyWorking ? releaseIn : 0;
    st.pauseReason = MMINPauseReason(power, prefs, clocks, now);
    st.lidWanted = st.holding && prefs.lid && st.laptop && !st.pauseReason && !st.otherApp;
    st.lidLive = power.lidOverride;
    if (st.otherApp) st.lidProblem = @"Insomnia.app sets it";
    return st;
}

static NSString *const kThermal[] = { @"nominal", @"fair", @"serious", @"critical" };

NSDictionary *MMINStateJSON(MMINState *st) {
    NSMutableArray *holders = [NSMutableArray new];
    for (MMINHolder *h in st.holders)
        [holders addObject:@{@"findingID": h.findingID ?: @"", @"kind": h.kind ?: @"", @"name": h.name ?: @"", @"project": h.project ?: @"",
                             @"pid": @(h.pid), @"key": h.keyString ?: @"", @"working": @(h.working), @"idleSeconds": @(round(h.idleFor)),
                             @"held": @(h.held), @"why": h.why ?: @""}];
    MMINPrefs *p = st.prefs;
    NSDate *at = st.at ?: NSDate.date;
    return @{@"holding": @(st.holding), @"state": MMINAccessibilityState(st), @"holders": holders, @"watched": @(st.watched),
             @"lowBattery": @(st.lowBattery), @"releaseInSeconds": @(round(st.releaseIn)), @"asserted": @(st.asserted),
             @"lid": @{@"mode": @(p.lid), @"live": @(st.lidLive), @"wanted": @(st.lidWanted), @"pausedBy": st.pauseReason ?: NSNull.null,
                       @"problem": st.lidProblem ?: NSNull.null, @"otherApp": @(st.otherApp)},
             @"power": @{@"onAC": @(st.onAC), @"battery": @(st.batteryPercent), @"lidClosed": @(st.lidClosed), @"online": @(st.online),
                         @"thermal": st.thermal <= 3 ? kThermal[st.thermal] : @"unknown", @"thermalHold": @(st.clocks.thermalHold),
                         @"unpluggedSeconds": st.clocks.unpluggedAt ? @(round([at timeIntervalSinceDate:st.clocks.unpluggedAt])) : NSNull.null,
                         @"offlineSeconds": st.clocks.offlineAt ? @(round([at timeIntervalSinceDate:st.clocks.offlineAt])) : NSNull.null},
             @"prefs": @{@"manual": @(p.manual), @"agents": @(p.agents), @"lid": @(p.lid), @"screenOff": @(p.screenOff),
                         @"thermalGuard": @(p.thermalGuard), @"minBattery": @(p.minBattery), @"graceMinutes": @(p.graceMinutes),
                         @"offlineMinutes": @(p.offlineMinutes), @"quietMinutes": @(p.quietMinutes)}};
}
