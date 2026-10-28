// Insomnia on the shared core. See MMInsomnia.h.
// Ported from Insomnia's main.m: -apply:, -reconcile, -syncLid, -acquireAssertions, -enableLid: and the URL commands.
// The assertions are Core's MMAwake, one pair per working agent's pid, which ends on that pid's exit.
// The lid override is written through MMLidOverride inside MMRunAction, off main with a time limit.
// One pass runs on no.guerrilla.minmacs.insomnia.power, so main never waits on a process or the prefs.
#import <AppKit/AppKit.h>
#import "Experts/Insomnia/MMInsomnia.h"
#import "UI/MMFormat.h"
#include <sys/sysctl.h>

static NSString *const kExpert = @"insomnia";
static const NSTimeInterval kWriteMemory = 15;      // a written lid value counts until a sample shows it
static const NSTimeInterval kRetryAfter = 300;      // a failed lid write waits this long before the same write again

static dispatch_queue_t PowerQueue(void) { return MMQueue(kExpert, @"power", QOS_CLASS_UTILITY); }
static dispatch_queue_t ActQueue(void) { return MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED); }

/// MinMacs' own process, for the hold Keep Mac Awake takes. Read once from the kernel.
static MMProcKey SelfKey(void) {
    static MMProcKey k; static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct kinfo_proc kp; size_t len = sizeof kp;
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
        k.pid = getpid();
        if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len == sizeof kp) k.startSec = (uint64_t)kp.kp_proc.p_starttime.tv_sec;
    });
    return k;
}

static MMProcKey KeyFrom(NSString *s) {
    NSArray *parts = [s componentsSeparatedByString:@":"];
    MMProcKey k = { 0, 0 };
    if (parts.count == 2) { k.pid = (pid_t)[parts[0] intValue]; k.startSec = (uint64_t)[parts[1] longLongValue]; }
    return k;
}

static MMFinding *Subject(NSString *kind, NSString *key, NSString *title, NSDictionary *facts) {
    return [MMFinding expert:kExpert kind:kind stableKey:key build:^(MMFindingBuilder *b) {
        b.title = title; b.facts = facts;
        b.proposal = [MMProposal verb:kind title:title reversibility:MMReversibleNotNeeded];
    }];
}

#pragma mark - Actions

@class MMInsomniaExpert;

/// Writes the lid override. The finding names the value it wants.
@interface MMINLidAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property BOOL want;
@end
@implementation MMINLidAction
- (NSString *)kind { return @"lid"; }
- (NSString *)recheck { return [MMLidOverride unavailableReason]; }
- (NSString *)dryRun { return [NSString stringWithFormat:@"sudo -n /usr/bin/pmset -a disablesleep %d", self.want]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    [MMUndo.shared note:record payload:@{@"lid": @(self.want), @"command": [self dryRun]}];
    return [MMLidOverride set:self.want error:error];
}
@end

/// Holds the Mac awake until one process exits, for `insomnia hold <pid>`. The hold ends on that exit, so the
/// record cannot be restored: it holds the pid, its start time and the reason, for the history.
@interface MMINHoldAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property MMProcKey key;
@property (copy) NSString *why;
@end
@implementation MMINHoldAction
- (NSString *)kind { return @"hold"; }
- (NSString *)recheck { return self.key.pid > 1 ? nil : @"no process"; }
- (NSString *)dryRun { return [NSString stringWithFormat:@"keeps the Mac awake until pid %d exits: %@", self.key.pid, self.why]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    [MMUndo.shared note:record payload:@{@"pid": @(self.key.pid), @"process": MMProcKeyString(self.key), @"reason": self.why ?: @""}];
    [MMGraph.shared holdAwake:self.why pid:self.key];
    return YES;
}
@end

/// Changes one pref, the person's own switch or number.
@interface MMINSetting : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property (copy) NSString *key;
@property (strong) id value, old;
@end
@implementation MMINSetting
- (NSString *)kind { return @"setting"; }
- (NSString *)recheck { return self.key.length && self.value ? nil : @"no value"; }
- (NSString *)dryRun { return [NSString stringWithFormat:@"%@ becomes %@", self.key, self.value]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    [MMUndo.shared note:record payload:@{@"key": self.key, @"from": self.old ?: NSNull.null, @"to": self.value}];
    MMSetPref(self.key, self.value);
    return YES;
}
@end

/// The keep checks. A lid write that turns the override on is checked on fresh power facts against the guards.
@interface MMINPolicy : NSObject <MMExpertPolicy>
@property (weak) MMInsomniaExpert *expert;
@end

#pragma mark - The expert

@interface MMInsomniaExpert ()
@property (readwrite, strong) MMINState *state;      // atomic; written on the power queue
- (MMINClocks *)clocksNow;                           // power queue
- (MMINInput *)inputFor:(MMFacts *)facts;
@end

@implementation MMINPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    if ([f.kind isEqualToString:@"hold"]) {
        // The pid must still be the same process, by its start time, in a sample taken now.
        if (!facts.sample) return @"cannot verify the process";
        MMProc *p = [facts.sample proc:(pid_t)[f.facts[@"pid"] intValue]];
        return p && [MMProcKeyString(p.key) isEqualToString:f.facts[@"process"]] ? nil : @"that process has exited";
    }
    if (![f.kind isEqualToString:@"lid"]) return nil;
    MMInsomniaExpert *e = self.expert;
    // The standalone app may have started since the pass. It owns the override then, both ways.
    if (facts.sample && [e inputFor:facts].otherApp) return @"Insomnia.app runs and sets it";
    if (![f.facts[@"want"] boolValue]) return nil;
    MMPower *p = facts.power;
    if (!p) return @"cannot verify the power facts";
    MMINPrefs *prefs = [MMINPrefs current];
    NSDate *now = e.clock ? e.clock() : NSDate.date;
    NSString *pause = MMINPauseReason(p, prefs, MMINAdvance([e clocksNow], p, prefs, now), now);
    if (pause) return [@"a guard pauses it: " stringByAppendingString:pause];
    if (p.lidOverride) return @"it is already on";
    return nil;
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

@implementation MMInsomniaExpert {
    // Power queue only.
    MMINClocks *_clocks;
    NSMutableDictionary<NSString *, NSDate *> *_last;    // a worker's key to when it last worked
    NSMutableSet<NSString *> *_skipped;                  // keys the person let sleep, until each exits
    NSNumber *_written; NSDate *_writtenAt;              // the last lid value written
    NSNumber *_failed; NSDate *_failedAt; NSString *_failure;
    BOOL _ours, _darkened, _loaded;
    NSString *_label;
    MMSnapshot *_seen;                                   // the snapshot of the last pass
    BOOL _hooked;                                        // graph queue
    // Main only.
    BOOL _started;
    dispatch_source_t _tick;
    MMINPolicy *_policy;
}

+ (instancetype)shared {
    static MMInsomniaExpert *e; static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMInsomniaExpert new]; });
    return e;
}

- (instancetype)init {
    if ((self = [super init])) {
        _last = [NSMutableDictionary new];
        _skipped = [NSMutableSet new];
        _policy = [MMINPolicy new];
        _policy.expert = self;
    }
    return self;
}

- (NSString *)expertID { return kExpert; }
- (NSString *)name { return @"Insomnia"; }
- (NSString *)symbol { return @"cup.and.saucer"; }
- (NSString *)legacyName { return @"insomnia"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"awake" go:@"sleep" unsure:@"unsure"]; }
- (NSDate *)now { return self.clock ? self.clock() : NSDate.date; }

- (MMINInput *)inputFor:(MMFacts *)facts { return self.inputFrom ? self.inputFrom(facts) : MMINInputFrom(facts); }

#pragma mark Findings

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSMutableArray *out = [NSMutableArray new];
    for (MMINWorker *w in [self inputFor:facts].workers) {
        MMProcKey k = w.key;
        NSString *project = w.cwd.lastPathComponent;
        [out addObject:[MMFinding expert:kExpert kind:w.kind stableKey:w.stableKey build:^(MMFindingBuilder *b) {
            b.title = project.length ? [NSString stringWithFormat:@"%@ in %@", w.name, project] : w.name;
            b.instanceKey = MMProcKeyString(k);
            b.path = w.cwd;
            b.procs = @[[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
            b.fingerprint = [NSString stringWithFormat:@"%@|%d", MMProcKeyString(k), w.working];
            b.facts = @{@"name": w.name ?: @"", @"harness": w.harness ?: @"", @"sessionID": w.sessionID ?: @"", @"cwd": w.cwd ?: @"",
                        @"pid": @(k.pid), @"start": @(k.startSec), @"working": @(w.working), @"why": w.why ?: @""};
        }]];
    }
    [out addObject:[MMFinding expert:kExpert kind:@"lid" stableKey:@"override" build:^(MMFindingBuilder *b) { b.title = @"Lid override"; }]];
    if (!_hooked) {
        _hooked = YES;
        // The app has a delegate. The CLI, the render tool and the tests have none, so they never start the engine.
        dispatch_async(dispatch_get_main_queue(), ^{ if (NSApp.delegate) [self start]; });
    }
    return out;
}

- (id<MMExpertPolicy>)policy { return _policy; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
/// Insomnia decides by rules alone and asks no model.
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }

#pragma mark The pass

- (MMINClocks *)clocksNow {
    if (!_loaded) {
        _loaded = YES;
        _clocks = [MMINClocks new];
        id u = MMPref(@"insomnia.unpluggedAt"), o = MMPref(@"insomnia.offlineAt");
        _clocks.unpluggedAt = [u isKindOfClass:NSDate.class] ? u : [u isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[u doubleValue]] : nil;
        _clocks.offlineAt = [o isKindOfClass:NSDate.class] ? o : [o isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[o doubleValue]] : nil;
        _clocks.thermalHold = MMPrefBool(@"insomnia.thermalHold", NO);
        _ours = MMPrefBool(@"insomnia.lid.ours", NO);
    }
    return _clocks;
}

static void SaveDate(NSString *key, NSDate *old, NSDate *now) {
    if (old == now || [old isEqualToDate:now]) return;
    MMSetPref(key, now ? @(now.timeIntervalSince1970) : nil);
}

- (void)saveClocks:(MMINClocks *)c {
    MMINClocks *old = [self clocksNow];
    SaveDate(@"insomnia.unpluggedAt", old.unpluggedAt, c.unpluggedAt);
    SaveDate(@"insomnia.offlineAt", old.offlineAt, c.offlineAt);
    if (old.thermalHold != c.thermalHold) MMSetPref(@"insomnia.thermalHold", c.thermalHold ? @YES : nil);
    _clocks = c;
}

/// The newer of the snapshot's power facts and Senses' own, which a pushed signal refreshes between samples.
static MMPower *PowerFor(MMSnapshot *s) {
    MMPower *a = s.facts.power, *b = MMSenses.shared.power;
    if (!a) return b;
    if (!b) return a;
    return [b.at compare:a.at] == NSOrderedDescending ? b : a;
}

- (MMINState *)reconcile:(MMSnapshot *)s {
    if (NSThread.isMainThread) return nil;
    __block MMINState *st = nil;
    dispatch_sync(PowerQueue(), ^{ st = [self pass:s]; });
    return st;
}

/// One pass. Power queue only.
- (MMINState *)pass:(MMSnapshot *)s {
    // A pass without a new snapshot, after a change of setting, reads the one it saw last.
    if (!s || (_seen && [_seen.builtAt compare:s.builtAt] == NSOrderedDescending)) s = _seen;
    if (!s) return self.state;
    _seen = s;
    NSDate *now = [self now];
    MMINPrefs *prefs = [MMINPrefs current];
    MMPower *power = PowerFor(s);
    MMINInput *input = [self inputFor:s.facts];
    MMINClocks *clocks = MMINAdvance([self clocksNow], power, prefs, now);
    [self saveClocks:clocks];

    // The quiet period: when each worker last worked. A worker that left the snapshot has exited, and its entry goes.
    NSMutableSet *present = [NSMutableSet new];
    for (MMINWorker *w in input.workers) {
        NSString *ks = MMProcKeyString(w.key);
        [present addObject:ks];
        if (w.working && prefs.agents) _last[ks] = now;
    }
    if (!prefs.agents) [_last removeAllObjects];
    for (NSString *k in _last.allKeys) if (![present containsObject:k]) [_last removeObjectForKey:k];
    for (NSString *k in _skipped.allObjects) if (![present containsObject:k] && !s.awakeHolds[k]) [_skipped removeObject:k];

    MMINState *st = MMINDecide(input, power, prefs, clocks, _last, _skipped, s.awakeHolds, s, now);

    // Holds: one pair for Keep Mac Awake, else one pair per holder's pid. MMAwake drops a pair when its pid exits.
    NSMutableDictionary<NSString *, NSString *> *want = [NSMutableDictionary new];
    if (prefs.manual) want[MMProcKeyString(SelfKey())] = @"Keep Mac Awake is on";
    else for (MMINHolder *h in st.holders) if (h.held)
        want[h.keyString] = [h.kind isEqualToString:@"hold"] ? h.why : [NSString stringWithFormat:@"%@ works", h.name];
    NSDictionary *held = MMAwake.held;
    for (NSString *k in held) if (!want[k]) [MMAwake release:KeyFrom(k)];
    for (NSString *k in want) if (![held[k] isEqualToString:want[k]]) [MMAwake holdFor:KeyFrom(k) reason:want[k]];
    st.asserted = MMAwake.held.count;

    // The lid override. IOKit says what is set; a value written in the last seconds counts until a sample shows it.
    BOOL have = power.lidOverride;
    if (_written && [now timeIntervalSinceDate:_writtenAt] < kWriteMemory) have = _written.boolValue;
    BOOL wantLid = st.lidWanted;
    // Clear only an override this expert set or one its lid mode owns, never one another tool set.
    BOOL mayWrite = !input.otherApp && (wantLid || _ours || prefs.lid);
    BOOL retry = !_failed || _failed.boolValue != wantLid || [now timeIntervalSinceDate:_failedAt] >= kRetryAfter;
    if (wantLid != have && mayWrite && retry) {
        NSString *err = nil;
        MMFinding *f = Subject(@"lid", @"override", wantLid ? @"Lid override on" : @"Lid override off", @{@"want": @(wantLid)});
        MMINLidAction *a = [MMINLidAction new];
        a.finding = f; a.want = wantLid;
        MMUndoRecord *r = MMRunAction(a, _policy, nil, @"guard", st.pauseReason ?: (wantLid ? @"something keeps the Mac awake" : @"nothing keeps the Mac awake"), &err);
        if ((r && r.state == MMUndoDone) || [err hasSuffix:@"it is already on"]) {
            have = wantLid; _written = @(wantLid); _writtenAt = now; _failed = nil; _failure = nil;
            if (_ours != wantLid) { _ours = wantLid; MMSetPref(@"insomnia.lid.ours", wantLid ? @YES : nil); }
        } else {
            _failed = @(wantLid); _failedAt = now; _failure = err ?: r.error ?: @"the write failed";
        }
    }
    if (_failure && !st.lidProblem && wantLid != have) st.lidProblem = _failure;
    st.lidLive = have;

    // Shut and kept awake: the panel would stay lit until the display-sleep timer, so it sleeps now. An open lid wakes it.
    if (!power.lidClosed) _darkened = NO;
    else if (have && prefs.screenOff && !_darkened && !input.otherApp) { [MMLidOverride sleepDisplay]; _darkened = YES; }

    self.state = st;
    // The status item's label follows the state. A rebuild only when it changed, so a pass never starts another.
    NSString *label = MMINAccessibilityState(st);
    if (_started && ![label isEqualToString:_label]) [MMGraph.shared rebuild:@"insomnia state"];
    _label = label;
    return st;
}

- (void)skip:(NSString *)keyString {
    if (!keyString.length) return;
    dispatch_async(PowerQueue(), ^{ [self->_skipped addObject:keyString]; [self pass:MMGraph.shared.latest]; });
}

#pragma mark Settings

static NSString *PrefKey(NSString *what) {
    return @{@"manual": @"insomnia.awake", @"agents": @"insomnia.agents", @"lid": @"insomnia.lid", @"screen": @"insomnia.lid.screenOff",
             @"heat": @"insomnia.lid.thermalGuard", @"battery": @"insomnia.lid.minBattery", @"unplugged": @"insomnia.lid.graceMinutes",
             @"offline": @"insomnia.lid.offlineMinutes", @"quiet": @"insomnia.agents.quietMinutes"}[what];
}

- (NSString *)set:(NSString *)what value:(id)value by:(NSString *)by {
    if (NSThread.isMainThread) return @"it never runs on the main thread";
    NSString *key = PrefKey(what);
    if (!key || !value) return [NSString stringWithFormat:@"no setting named %@", what];
    // Lid mode needs the sudoers rule. The first time, macOS asks for the person's password once.
    if ([what isEqualToString:@"lid"] && [value boolValue] && ![MMLidOverride ruleInstalled]) {
        NSString *err = nil;
        if (![MMLidOverride installRule:&err]) return [@"the sudoers rule is not in place: " stringByAppendingString:err ?: @"no answer"];
    }
    __block NSString *problem = nil;
    dispatch_sync(PowerQueue(), ^{
        MMINSetting *a = [MMINSetting new];
        a.key = key; a.value = value; a.old = MMPref(key);
        a.finding = Subject(@"setting", what, [NSString stringWithFormat:@"Insomnia %@", what], @{@"key": key});
        NSString *err = nil;
        MMUndoRecord *r = MMRunAction(a, self->_policy, nil, by, [NSString stringWithFormat:@"%@ set to %@", what, value], &err);
        if (!r || r.state != MMUndoDone) problem = err ?: r.error ?: @"it did not change";
        if ([what isEqualToString:@"lid"]) { self->_failed = nil; self->_failure = nil; }
        if ([what isEqualToString:@"agents"] && ![value boolValue]) [self->_last removeAllObjects];
        [self pass:MMGraph.shared.latest];
    });
    return problem;
}

- (NSString *)hold:(MMProcKey)key reason:(NSString *)why by:(NSString *)by rid:(NSString **)rid {
    if (rid) *rid = nil;
    if (NSThread.isMainThread) return @"it never runs on the main thread";
    NSString *ks = MMProcKeyString(key);
    MMINHoldAction *a = [MMINHoldAction new];
    a.key = key; a.why = why.length ? why : @"held by request";
    a.finding = Subject(@"hold", ks, [NSString stringWithFormat:@"Awake until pid %d exits", key.pid], @{@"pid": @(key.pid), @"process": ks});
    NSString *err = nil;
    MMUndoRecord *r = MMRunAction(a, _policy, nil, by, a.why, &err);
    if (!r || r.state != MMUndoDone) return err ?: r.error ?: @"it did not hold";
    if (rid) *rid = r.rid;
    return nil;
}

#pragma mark The app

- (void)start {
    if (_started || !NSThread.isMainThread) return;
    _started = YES;
    [MMGraph.shared observe:^(MMSnapshot *s) { dispatch_async(PowerQueue(), ^{ [self pass:s]; }); }];
    [MMSenses.shared observe:MMSignalPower | MMSignalLid | MMSignalThermal block:^(MMSignal changed, id detail) {
        dispatch_async(PowerQueue(), ^{ [self pass:MMGraph.shared.latest]; });
    }];
    // The guard clocks and the quiet period run out between samples, so a minute tick checks them.
    _tick = MMTimer(PowerQueue(), 60, 10, ^{ [self pass:MMGraph.shared.latest]; });
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) {
        // Never leave the override behind when no MinMacs runs to own it. The write is started and not waited for.
        MMINState *st = self.state;
        if (st.lidLive && MMPrefBool(@"insomnia.lid.ours", NO)) [MMLidOverride clearWithoutWaiting];
        [MMAwake releaseAll];
    }];
}

#pragma mark Menu

/// Before the first pass: what it would decide, with nothing applied. Made on the graph queue once per snapshot.
- (id)prepareFor:(MMSnapshot *)s { return self.state ? nil : [self firstLook:s]; }

- (MMINState *)firstLook:(MMSnapshot *)s {
    return MMINDecide([self inputFor:s.facts], s.facts.power, [MMINPrefs defaults], [MMINClocks new], nil, nil, s.awakeHolds, s, NSDate.date);
}

- (MMINState *)stateFor:(MMSnapshot *)s {
    MMINState *st = self.state;
    if (st) return st;
    MMINState *p = NSThread.isMainThread ? [s preparedFor:kExpert] : nil;
    return [p isKindOfClass:MMINState.class] ? p : [self firstLook:s];
}

- (MMINView *)viewFor:(MMSnapshot *)s {
    MMINView *v = [MMINView new];
    v.state = [self stateFor:s];
    __weak MMInsomniaExpert *weak = self;
    v.act = ^(NSString *what, NSString *key) { [weak act:what key:key]; };
    return v;
}

- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return MMINMenu([self viewFor:s]); }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return MMINCard([self viewFor:s], f.findingID); }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return MMINAccessibilityState([self stateFor:s]); }

- (BOOL)fieldEmptyIn:(MMSnapshot *)s {
    MMINState *st = [self stateFor:s];
    return st.watched == 0 && !st.holding && !st.prefs.lid;
}

- (NSArray<MMVerbSpec *> *)verbs { return MMINVerbs(); }

static void Alert(NSString *title, NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *a = [NSAlert new];
        a.messageText = title; a.informativeText = text ?: @"";
        [NSApp activateIgnoringOtherApps:YES];
        [a runModal];
    });
}

/// From the menu, on main. The change runs on the act queue.
- (void)act:(NSString *)what key:(NSString *)key {
    if ([what isEqualToString:@"skip"]) {
        for (MMINHolder *h in self.state.holders) if ([h.findingID isEqualToString:key]) [self skip:h.keyString];
        return;
    }
    MMINPrefs *p = self.state.prefs ?: [MMINPrefs defaults];
    NSDictionary *now = @{@"manual": @(p.manual), @"agents": @(p.agents), @"lid": @(p.lid), @"screen": @(p.screenOff), @"heat": @(p.thermalGuard)};
    if (!now[what]) return;
    BOOL to = ![now[what] boolValue];
    if ([what isEqualToString:@"lid"] && to) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Keep the Mac awake with the lid closed?";
        a.informativeText = @"It keeps running with the lid shut, also inside a bag, and can get warm.\n\n"
                             "On battery, MinMacs pauses this when the battery gets low, the charger has been out for a while, "
                             "the network has been gone for a while, or the Mac runs hot with the lid shut. "
                             "It clears when nothing keeps the Mac awake and when MinMacs quits. "
                             "The first time, macOS asks for your password to allow the change.";
        [a addButtonWithTitle:@"Keep Awake"];
        [a addButtonWithTitle:@"Cancel"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
    }
    dispatch_async(ActQueue(), ^{
        NSString *problem = [self set:what value:@(to) by:@"manual"];
        if (problem) Alert(@"Could Not Change Insomnia", MMSentence(problem));
    });
}

/// The Settings pane, from the last pass's prefs, so main never reads the prefs itself.
- (NSArray<MMPrefSpec *> *)prefSpecs { return MMINPrefSpecs(self.state.prefs ?: [MMINPrefs defaults]); }

/// A change from the Settings pane, on main. It runs on the act queue through -set:value:by:, so it has a record.
- (void)setPref:(NSString *)key value:(NSNumber *)value {
    if (![@[@"battery", @"unplugged", @"offline", @"heat", @"quiet"] containsObject:key ?: @""] || !value) return;
    dispatch_async(ActQueue(), ^{
        NSString *problem = [self set:key value:value by:@"manual"];
        if (problem) Alert(@"Could Not Change Insomnia", MMSentence(problem));
    });
}

/// minmacs://insomnia/<command>, and insomnia://<command> once the scheme is registered. Insomnia's own commands.
- (BOOL)openURL:(NSURL *)url {
    NSString *c = url.host.lowercaseString ?: @"";
    NSDictionary *map = @{@"on": @[@"manual", @YES], @"off": @[@"manual", @NO], @"agents-on": @[@"agents", @YES],
                          @"agents-off": @[@"agents", @NO], @"lid-on": @[@"lid", @YES], @"lid-off": @[@"lid", @NO]};
    NSArray *m = map[c];
    if ([c isEqualToString:@"toggle"]) m = @[@"manual", @(!self.state.prefs.manual)];
    if (!m) return NO;
    dispatch_async(ActQueue(), ^{ (void)[self set:m[0] value:m[1] by:@"manual"]; });
    return YES;
}

@end
