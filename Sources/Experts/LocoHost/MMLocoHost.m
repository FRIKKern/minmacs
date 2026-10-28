// LocoHost on the shared core. See MMLocoHost.h.
// Ported from LocoHost's main.m: Candidates, MustKeep, Plan, the judge subjects, AutoStop, watchEvents, the menu and
// the card. The modes, the judge and the undo record are Core's now, so this file only says what LocoHost knows.
#import <AppKit/AppKit.h>
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/LocoHost/MMLHScan.h"
#import "UI/MMFormat.h"
#import "UI/MMInvestigateUI.h"

static NSString *const kExpert = @"locohost";
static const NSTimeInterval kGrace = 6;                  // seconds a server gets to stop after SIGTERM
static const NSTimeInterval kSessionFresh = 60 * 60;     // an agent session active this recently keeps its server
static const NSTimeInterval kNewServer = 120;            // a server must run this long before it wakes a review

/// YES while the CLI runs a verb: file reads wait, and Where is asked only by the verbs that need it.
BOOL MMLHInCLI = NO;

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }

static MMLHHost *HostOf(MMFinding *f) { return [MMLHHost fromJSON:f.facts]; }

static dispatch_queue_t ActQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = MMQueue(kExpert, @"act", QOS_CLASS_UTILITY); });
    return q;
}

#pragma mark - Findings

static MMProcKey Key(pid_t pid, uint64_t start) { MMProcKey k = { pid, start }; return k; }

/// The processes a stop signals: the server's tree, then the package manager runner above it. Never MinMacs or pid 1.
static NSArray<NSValue *> *StopKeys(MMLHHost *h) {
    NSMutableArray *keys = [NSMutableArray new];
    for (NSUInteger i = 0; i < h.treePids.count; i++) {
        pid_t p = h.treePids[i].intValue;
        if (p <= 1 || p == getpid()) continue;
        MMProcKey k = Key(p, i < h.treeStarts.count ? h.treeStarts[i].unsignedLongLongValue : 0);
        [keys addObject:[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
    }
    if (h.wrapperPid > 1 && h.wrapperPid != getpid()) {
        MMProcKey k = Key(h.wrapperPid, h.wrapperStart);
        [keys addObject:[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
    }
    return keys;
}

static NSString *Bucket(NSDate *d) {
    if (!d) return @"-";
    NSTimeInterval age = -d.timeIntervalSinceNow;
    return age < 15 * 60 ? @"0" : age < 2 * 3600 ? @"1" : age < 86400 ? @"2" : @"3";
}

/// What must change for the model to look again: the instance, its state, who has it open, duplicates,
/// the protect list, whether its agent session is fresh, and how long it has been quiet, in buckets.
static NSString *Fingerprint(MMLHHost *h) {
    NSDate *sessionLast = h.session[@"lastActiveAt"] ? [NSDate dateWithTimeIntervalSince1970:[h.session[@"lastActiveAt"] doubleValue]] : nil;
    return [NSString stringWithFormat:@"%@|%@|%@|c%d|d%lu|p%d|s%@|q%@", h.key, h.kind, MMLHStateName(h.state), h.clients.count > 0,
            (unsigned long)h.duplicates.count, h.isProtected, sessionLast ? Bucket(sessionLast) : @"-", Bucket(h.lastActive ?: h.firstSeen)];
}

/// keptUntil is the person's timed keep, read on the graph queue, so the menu never reads the keeps file on main.
static MMFinding *FindingFor(MMLHHost *h, NSDate *keptUntil) {
    return [MMFinding expert:kExpert kind:@"server" stableKey:h.stableKey build:^(MMFindingBuilder *b) {
        b.instanceKey = h.key;
        b.title = [NSString stringWithFormat:@":%ld %@ %@", (long)h.port, h.framework ?: @"", h.project];
        b.path = h.restartDir.length ? h.restartDir : h.cwd;
        b.cost = (MMCost){ .ramBytes = h.memory, .cpuPercent = h.cpuPercent, .energyRank = h.energyRank };
        NSMutableArray *ev = [NSMutableArray new];
        [ev addObject:[MMEvidence label:@"State" value:MMLHStateWords(h) raw:MMLHStateName(h.state)]];
        [ev addObject:[MMEvidence label:@"Started by" value:h.launcher ?: @"" raw:h.launcher]];
        if (h.isDev) [ev addObject:[MMEvidence label:@"Agent" value:MMLHSessionWords(h.session) raw:h.session]];
        b.evidence = ev;
        b.proposal = [MMProposal verb:@"stop" title:@"Stop Server" reversibility:MMReversibleRestart];
        b.procs = StopKeys(h);
        NSMutableDictionary *facts = [h.json mutableCopy];
        if (keptUntil) facts[@"keptUntil"] = @(keptUntil.timeIntervalSince1970);
        b.facts = facts;
        b.fingerprint = Fingerprint(h);
    }];
}

#pragma mark - Policies

/// The host a finding names, read again from these facts. nil when that process no longer listens.
static MMLHHost *FreshHost(MMFinding *f, MMFacts *facts) {
    for (MMLHHost *h in [MMLHScanner.shared hostsFrom:facts ignored:NULL read:MMLHInCLI ? MMLHReadNow : MMLHReadCached])
        if ([h.key isEqualToString:f.instanceKey]) return h;
    return nil;
}

@interface MMLHModeKeeps : NSObject <MMExpertPolicy>
@end
@implementation MMLHModeKeeps

/// Why a host stays whatever the mode. Ported from MustKeep in LocoHost's main.m.
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    MMLHHost *h = FreshHost(f, facts);
    if (!h) return @"cannot verify: it restarted or stopped since the plan";
    if (!h.isDev) return @"not a dev server";
    if (h.isProtected) return @"protected";
    if (h.state != MMLHIdle) return h.lastActive ? [NSString stringWithFormat:@"used %@", MMAgo(h.lastActive)] : @"in use";
    NSTimeInterval up = -h.started.timeIntervalSinceNow;
    if (up < MMLHMinUptime()) return [NSString stringWithFormat:@"started only %@ ago", MMDuration(up)];
    NSNumber *last = h.session[@"lastActiveAt"];
    if (last && NSDate.date.timeIntervalSince1970 - last.doubleValue < kSessionFresh)
        return [NSString stringWithFormat:@"its agent session was active %@", MMAgo([NSDate dateWithTimeIntervalSince1970:last.doubleValue])];
    return nil;
}

- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r {
    double last = [f.facts[@"lastActive"] isKindOfClass:NSNumber.class] ? [f.facts[@"lastActive"] doubleValue] : 0;
    if (last && r.at && last > r.at.timeIntervalSince1970) return @"used after the last review";
    return nil;
}

- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r {
    MMVerdict *v = r.verdicts[f.findingID];
    if (v.kind == MMVerdictKeep && v.keepEvidence.length) return [@"evidence: " stringByAppendingString:v.keepEvidence];
    if (m != MMModeProactive) return nil;
    MMLHHost *h = HostOf(f);
    if (h.agent.length && !h.orphaned) return [NSString stringWithFormat:@"%@ still runs above it", h.agent];
    NSTimeInterval quiet = -(h.lastActive ?: h.firstSeen ?: h.started).timeIntervalSinceNow;
    if (quiet < MMLHProactiveQuiet())
        return [NSString stringWithFormat:@"quiet %@, and Proactive waits %@", MMDuration(quiet), MMDuration(MMLHProactiveQuiet())];
    return nil;
}
@end

/// For an action the person asked for: only that the server is still the one the menu or the CLI showed.
@interface MMLHManualKeeps : NSObject <MMExpertPolicy>
@end
@implementation MMLHManualKeeps
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    return FreshHost(f, facts) ? nil : @"cannot verify: it restarted or stopped since it was listed";
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

id<MMExpertPolicy> MMLHModePolicy(void) {
    static MMLHModeKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMLHModeKeeps new]; });
    return p;
}

id<MMExpertPolicy> MMLHManualPolicy(void) {
    static MMLHManualKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMLHManualKeeps new]; });
    return p;
}

#pragma mark - Stopping

@interface MMLHStop : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property MMStopStep step;
@end

@implementation MMLHStop

- (NSString *)kind { return @"stop"; }

- (NSString *)recheck {
    MMLHHost *h = HostOf(self.finding);
    if (h.pid <= 1) return @"it has no process";
    if (!MMProcAlive(Key(h.pid, h.startSec))) return @"it has already stopped";
    return nil;
}

- (NSString *)dryRun {
    MMLHHost *h = HostOf(self.finding);
    return [NSString stringWithFormat:@"would stop :%ld %@ in %@ with %@. Restart with: %@", (long)h.port, h.framework, h.project,
            self.step == MMStopKill ? @"SIGKILL, after the SIGTERM it ignored" : [NSString stringWithFormat:@"SIGTERM and %.0f seconds", kGrace],
            h.restartCommand];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMLHHost *h = HostOf(self.finding);
    NSMutableDictionary *restart = [@{@"command": h.command, @"port": @(h.port), @"framework": h.framework ?: @"",
                                      @"project": h.project ?: @""} mutableCopy];
    if (h.restartDir.length) restart[@"cwd"] = h.restartDir;
    [MMUndo.shared note:record payload:@{@"restart": restart}];
    NSArray<NSValue *> *keys = StopKeys(h);
    NSArray<NSValue *> *left;
    if (self.step == MMStopKill) {
        // SIGKILL reaches only what got SIGTERM on an earlier request. What never got one gets it now.
        left = MMStop(keys, MMStopKill, 2);
        if (left.count) left = MMStop(left, MMStopTerm, kGrace);
    } else left = MMStop(keys, MMStopTerm, kGrace);
    if (!MMProcAlive(Key(h.pid, h.startSec))) return YES;
    if (error) *error = self.step == MMStopKill ? @"it is still running after SIGKILL"
                                                : @"it ignored SIGTERM. Force Stop sends SIGKILL, and whatever it held in memory is lost";
    return NO;
}

@end

id<MMAction> MMLHStopAction(MMFinding *f, MMStopStep step) {
    MMLHStop *a = [MMLHStop new];
    a.finding = f; a.step = step;
    return a;
}

#pragma mark - Close Idle, review and plans

MMReview *MMLHLastReview(void) { return [MMReview lastFor:kExpert]; }

MMVerdict *MMLHVerdictFor(MMFinding *f, MMReview *r) {
    MMVerdict *v = f.findingID ? r.verdicts[f.findingID] : nil;
    // The finding id outlives a restart. A verdict made for an earlier instance says nothing about this one.
    // The fingerprint starts with the instance key, as LocoHost 0.1 keyed its verdicts by pid and start time.
    if (!v || !f.instanceKey.length || ![v.fingerprint hasPrefix:[f.instanceKey stringByAppendingString:@"|"]]) return nil;
    return v;
}

NSArray<MMFinding *> *MMLHCandidates(NSArray<MMFinding *> *findings, MMReview *r) {
    NSMutableArray *c = [NSMutableArray new];
    if (!r || r.error.length) return c;
    for (MMFinding *f in findings) {
        MMLHHost *h = HostOf(f);
        if (!h.isDev || h.isProtected || h.state != MMLHIdle) continue;
        MMVerdict *v = MMLHVerdictFor(f, r);
        if (v.kind != MMVerdictGo || v.confidence < MMMinConfidence) continue;
        if (h.lastActive && [h.lastActive compare:r.at] == NSOrderedDescending) continue;
        [c addObject:f];
    }
    return c;
}

NSDictionary<NSString *, NSDictionary *> *MMLHPlanMap(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r, MMMode m) {
    NSMutableArray *dev = [NSMutableArray new];
    for (MMFinding *f in findings) if ([f.facts[@"kind"] isEqual:@"dev"]) [dev addObject:f];
    NSMutableDictionary *plan = [NSMutableDictionary new];
    for (MMPlanEntry *e in MMPlan(dev, facts, r, m, MMLHModePolicy())) plan[e.finding.findingID] = @{@"stop": @(e.act), @"why": e.why ?: @""};
    return plan;
}

static NSString *const kSystem =
    @"You review the local servers running on a developer's Mac and decide which ones the developer still uses. "
    @"The developer runs many coding agents and git worktrees at once, so servers are often left behind when an agent or terminal finishes.\n\n"
    @"For every finding return: id copied exactly, verdict (in_use, idle or unsure), confidence from 0 to 1, "
    @"about: at most 12 words saying what the server is, such as \"Vite dev server for acme-web, worktree checkout-flow\", "
    @"reason: one sentence naming the facts that decided it, and keep_evidence: the one concrete fact showing that someone still needs it, "
    @"such as a new request 4 minutes ago or an agent session active 10 minutes ago in this folder. Leave keep_evidence empty when there is none. "
    @"Still running, an open tab with no new requests, or recent commits are not evidence.\n\n"
    @"Evidence, strongest first:\n"
    @"- minutes_since_activity counts from the last new connection or real CPU work. Below quiet_after_minutes: in_use.\n"
    @"- connections_now and clients_now are connections held open, often a browser tab with a live-reload socket. "
    @"Open connections with no activity for hours usually mean a forgotten tab, and that alone does not make it in_use.\n"
    @"- a live agent started it, so agent is set and parent_exited is false, and the repo was touched in the last hour: in_use or unsure, never idle.\n"
    @"- parent_exited true, no activity while watched, and the repo untouched for hours: idle.\n"
    @"- two servers for the same folder and branch in duplicates: the one without activity is likely idle.\n"
    @"- watched_minutes small means LocoHost has not watched long enough: prefer unsure unless parent_exited is true and uptime is days.\n"
    @"- project holds the package.json name, description and script, the README's first lines and the names of config files. "
    @"agent_session is the coding agent session that was open when the server started. When it is missing, no session was found, and you must not invent one. "
    @"waste is what the server burned since it was last used.\n\n"
    @"Say idle only when you would bet the developer will not miss it. Closing a server the developer needs costs more than leaving an idle one running. "
    @"Return exactly one entry for every id. summary: two or three plain sentences about what stands out, without counting.";

static id Minutes(id seconds1970) {
    if (![seconds1970 isKindOfClass:NSNumber.class] || [seconds1970 doubleValue] <= 0) return nil;
    return @((long)round((NSDate.date.timeIntervalSince1970 - [seconds1970 doubleValue]) / 60));
}

/// What the review sends about one server, redacted. docs/REVIEW.md lists each field.
/// Only these, as in LocoHost 0.1: no .env file, no other file contents, no environment, no page body, no log path.
static NSDictionary *ReviewFacts(MMFinding *f) {
    MMLHHost *h = HostOf(f);
    NSDictionary *j = f.facts;
    NSMutableDictionary *x = [NSMutableDictionary new];
    x[@"ports"] = h.ports ?: @[]; x[@"bind"] = h.bind; x[@"kind"] = h.kind; x[@"framework"] = h.framework;
    NSArray *a = h.args ?: @[];
    NSUInteger extra = [a indexOfObject:@"-extra"];
    if ([h.name isEqualToString:@"beam.smp"] && extra != NSNotFound)
        a = [@[@"beam.smp", @"…"] arrayByAddingObjectsFromArray:[a subarrayWithRange:NSMakeRange(extra + 1, a.count - extra - 1)]];
    NSString *cmd = [a componentsJoinedByString:@" "];
    if (h.wrapperArgs.count) cmd = [NSString stringWithFormat:@"%@, started by %@", cmd, [h.wrapperArgs componentsJoinedByString:@" "]];
    x[@"command"] = MMClip(cmd, 400);
    x[@"project"] = MMClip(h.project, 120); x[@"branch"] = h.branch; x[@"worktree"] = h.worktree;
    x[@"launcher"] = MMClip(h.launcher, 200); x[@"agent"] = h.agent; x[@"parent_exited"] = @(h.orphaned);
    x[@"uptime_minutes"] = Minutes(j[@"started"]);
    x[@"cpu_percent_now"] = @(round(h.cpuPercent * 10) / 10); x[@"memory_mb"] = @(h.memory >> 20); x[@"processes"] = @(h.processCount);
    x[@"connections_now"] = @(h.connections); x[@"new_connections_now"] = @(h.newConnections);
    x[@"clients_now"] = h.clients ?: @[]; x[@"cpu_busy_now"] = @(h.busy);
    x[@"minutes_since_activity"] = Minutes(j[@"lastActive"]); x[@"watched_minutes"] = Minutes(j[@"firstSeen"]);
    x[@"repo_touched_minutes_ago"] = Minutes(j[@"repoTouched"]);
    x[@"protected"] = @(h.isProtected); x[@"duplicates"] = h.duplicates ?: @[];
    x[@"quiet_after_minutes"] = @((long)(MMLHIdleSeconds() / 60));
    x[@"waste"] = @{@"since": h.lastActive ? @"last activity" : @"LocoHost first saw it",
                    @"cpu_minutes_since": @(round(h.idleCPUSeconds / 6) / 10), @"energy_rank_now": @(round(h.energyRank * 100) / 100),
                    @"memory_mb_held": @(h.memory >> 20)};
    if (h.isDev) {
        NSMutableDictionary *p = [NSMutableDictionary new];
        for (NSString *k in @[@"name", @"description", @"script", @"readme", @"app"]) p[k] = MMClip(Str(h.projectFacts[k]), 300);
        if ([h.projectFacts[@"configs"] isKindOfClass:NSArray.class]) p[@"configs"] = h.projectFacts[@"configs"];
        x[@"project_files"] = p;
        NSDictionary *s = h.session;
        if (s) x[@"agent_session"] = @{@"agent": s[@"agent"] ?: @"", @"title": MMClip(Str(s[@"title"]), 200) ?: @"",
                                        @"started_minutes_ago": Minutes(s[@"startedAt"]) ?: @0,
                                        @"last_active_minutes_ago": Minutes(s[@"lastActiveAt"]) ?: @0, @"match": s[@"match"] ?: @""};
    }
    return x;
}

MMReviewRequest *MMLHReviewRequest(NSArray<MMFinding *> *findings, MMFacts *facts, NSString *trigger, MMMode mode, NSString *model) {
    if (!findings.count) return nil;
    MMReviewRequest *q = [MMReviewRequest new];
    q.expert = kExpert; q.trigger = trigger ?: @"manual";
    q.model = model.length ? model : MMPrefString(MMReviewModelKey, @"auto");
    q.findings = findings; q.facts = facts;
    q.system = kSystem;
    q.words = [MMVerdictWords keep:@"in_use" go:@"idle" unsure:@"unsure"];
    q.factsFor = ^NSDictionary *(MMFinding *f) { return ReviewFacts(f); };
    q.judge = mode == MMModeEager;
    q.mode = mode;
    return q;
}

#pragma mark - Rules

/// P47. A rule that decides a finding with no model call.
@interface MMLHRule : NSObject <MMRule>
@property (copy) NSString *ruleID;
@property (copy) MMVerdict *(^decide)(MMLHHost *h);
@end
@implementation MMLHRule
- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts { return self.decide ? self.decide(HostOf(f)) : nil; }
@end

static MMVerdict *Keep(NSString *about, NSString *reason) {
    MMVerdict *v = [MMVerdict new];
    v.kind = MMVerdictKeep; v.word = @"in_use"; v.confidence = 1; v.about = about; v.reason = reason; v.keepEvidence = @"";
    return v;
}

#pragma mark - Menu view

static NSString *ModelWords(MMReview *r) {
    NSString *m = nil;
    for (MMUsage *u in r.calls) if (u.model.length) m = u.model;
    if (!m.length) return nil;
    if ([m hasPrefix:@"gpt-"]) return [@"GPT" stringByAppendingString:[m substringFromIndex:3].capitalizedString];
    return MMCapitalized(m);
}

static NSDictionary *VerdictJSON(MMVerdict *v) {
    static NSString *const kinds[] = {@"unsure", @"keep", @"go"};
    return @{@"word": v.word ?: @"unsure", @"kind": kinds[v.kind], @"confidence": @(v.confidence), @"about": v.about ?: @"",
             @"reason": v.reason ?: @"", @"judged": @(v.judged), @"decidedBy": v.decidedBy ?: @"", @"keepEvidence": v.keepEvidence ?: @""};
}

/// Recently Stopped: LocoHost's done stops, newest first, as {rid, port, framework, project, at, by}. Reads the undo log.
static NSArray<NSDictionary *> *StoppedRecords(void) {
    NSMutableArray *stopped = [NSMutableArray new];
    for (MMUndoRecord *rec in [MMUndo.shared recent:kExpert limit:20]) {
        NSDictionary *rs = Dict(rec.payload[@"restart"]);
        if (![rec.kind isEqualToString:@"stop"] || rec.state != MMUndoDone || !rs) continue;
        [stopped addObject:@{@"rid": rec.rid ?: @"", @"port": rs[@"port"] ?: @0, @"framework": rs[@"framework"] ?: @"", @"project": rs[@"project"] ?: @"",
                             @"at": @(rec.at.timeIntervalSince1970), @"by": rec.by ?: @"manual"}];
    }
    return stopped;
}

@implementation MMLocoHost {
    NSArray<NSDictionary *> *_ignored;
    MMLHView *_view;                         // main only, for the snapshot in _viewGen
    uint64_t _viewGen;
    MMReview *_review;                       // graph queue: the newest review seen in the log
    NSArray<NSDictionary *> *_stopped;       // graph queue writes, main reads: Recently Stopped, from the undo log
    NSDate *_reviewRead;
    BOOL _hooked;
    NSMutableDictionary<NSString *, NSNumber *> *_known;   // main: findingID to the age marks it has passed
    NSDate *_actedOn;                        // main: the review the mode last acted on
    BOOL _reviewing, _learned;
}


+ (instancetype)shared {
    static MMLocoHost *e; static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMLocoHost new]; });
    return e;
}

- (NSString *)expertID { return kExpert; }
- (NSString *)name { return @"LocoHost"; }
- (NSString *)symbol { return @"server.rack"; }
- (NSString *)legacyName { return @"locohost"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"in_use" go:@"idle" unsure:@"unsure"]; }
- (NSArray<NSDictionary *> *)ignored { @synchronized (self) { return _ignored ?: @[]; } }

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSArray *ignored = nil;
    NSArray<MMLHHost *> *hosts = [MMLHScanner.shared hostsFrom:facts ignored:&ignored read:MMLHInCLI ? MMLHReadNow : MMLHReadCached];
    @synchronized (self) { _ignored = ignored; }
    NSMutableArray *out = [NSMutableArray new];
    for (MMLHHost *h in hosts) {
        if (!MMLHInCLI && h.isDev) MMLHFillWhere(h, facts.sample, NO);   // Know's last answer; it refreshes in the background
        [out addObject:FindingFor(h, [MMKeep keptUntil:h.stableKey expert:kExpert])];
    }
    // One read of the undo log per rebuild, here on the graph queue, so the menu never reads it on main.
    NSArray *stopped = StoppedRecords();
    @synchronized (self) { _stopped = stopped; }
    if (!MMLHInCLI) [self syncReview];
    if (!_hooked && !MMLHInCLI) {
        _hooked = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ [self hook]; });
    }
    return out;
}

/// The broker saves each review to the log. The graph carries the newest one, so menus read it without a query.
/// Runs on the graph queue, at most once a minute.
- (void)syncReview {
    if (_reviewRead && -_reviewRead.timeIntervalSinceNow < 60) return;
    _reviewRead = NSDate.date;
    MMReview *r = MMLHLastReview();
    if (r.at && (!_review || ![r.at isEqualToDate:_review.at])) {
        _review = r;
        [MMGraph.shared saveReview:r forExpert:kExpert];
    }
}

- (id<MMExpertPolicy>)policy { return MMLHModePolicy(); }

- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return f.proposal ? MMLHStopAction(f, step) : nil; }

- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return ReviewFacts(f); }

- (NSArray<id<MMRule>> *)rules {
    MMLHRule *service = [MMLHRule new];
    service.ruleID = @"locohost.not-a-dev-server";
    service.decide = ^MMVerdict *(MMLHHost *h) {
        if ([h.kind isEqualToString:@"service"]) return Keep([NSString stringWithFormat:@"%@, a shared service", h.framework], @"No mode stops a shared service.");
        if ([h.kind isEqualToString:@"other"]) return Keep([NSString stringWithFormat:@"%@ on a high port", h.framework], @"A high-port listener is listed only.");
        return nil;
    };
    MMLHRule *active = [MMLHRule new];
    active.ruleID = @"locohost.in-use-now";
    active.decide = ^MMVerdict *(MMLHHost *h) {
        return h.state == MMLHActive ? Keep(nil, h.newConnections ? @"A new request came in just now." : @"It does real CPU work right now.") : nil;
    };
    return @[service, active];
}

- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s {
    return MMLHReviewRequest([s findingsFor:kExpert], s.facts, trigger, MMModeFor(kExpert), nil);
}

- (NSArray<MMLHHost *> *)hostsIn:(MMSnapshot *)s {
    NSMutableArray *hosts = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) { MMLHHost *h = HostOf(f); if (h) [hosts addObject:h]; }
    return hosts;
}

/// Main thread, or any queue for the CLI and the render tool. On main it reads only what the snapshot and the last
/// rebuild hold: the keeps are in each finding's facts and Recently Stopped was read on the graph queue.
- (MMLHView *)viewFor:(MMSnapshot *)s {
    if (NSThread.isMainThread && _view && _viewGen == s.generation && s.generation) return _view;
    MMLHView *v = [MMLHView new];
    NSArray<MMFinding *> *findings = [s findingsFor:kExpert];
    v.hosts = [self hostsIn:s];
    MMMode mode = MMModeFor(kExpert);
    v.mode = MMModeName(mode);
    MMReview *r = [s reviewFor:kExpert] ?: (NSThread.isMainThread ? nil : MMLHLastReview());
    v.reviewAt = r.at; v.reviewError = r.error; v.summaryWords = r.summaryWords; v.model = ModelWords(r);
    v.reviewing = _reviewing;
    NSMutableDictionary *verdicts = [NSMutableDictionary new];
    for (MMFinding *f in findings) { MMVerdict *x = MMLHVerdictFor(f, r); if (x) verdicts[f.findingID] = VerdictJSON(x); }
    v.verdicts = verdicts;
    v.plan = MMLHPlanMap(findings, s.facts, r, mode);
    NSMutableArray *cands = [NSMutableArray new];
    for (MMFinding *f in MMLHCandidates(findings, r)) [cands addObject:f.findingID];
    v.candidates = cands;
    NSMutableDictionary *kept = [NSMutableDictionary new];
    double now = NSDate.date.timeIntervalSince1970;
    for (MMFinding *f in findings) {
        NSNumber *until = f.facts[@"keptUntil"];
        if ([until isKindOfClass:NSNumber.class] && until.doubleValue > now) kept[f.findingID] = [NSDate dateWithTimeIntervalSince1970:until.doubleValue];
    }
    v.keptUntil = kept;
    NSMutableDictionary *runs = [NSMutableDictionary new];
    for (MMFinding *f in findings) { MMInvestigation *x = [MMInvestigations.shared latestFor:f.findingID]; if (x) runs[f.findingID] = x.json; }
    v.investigations = runs;   // memory only, so the menu never reads the log on main
    // A server inside a worktree links to WorkForest's card of that worktree.
    NSMutableDictionary *links = [NSMutableDictionary new];
    NSArray *trees = [s findingsFor:@"workforest"];
    for (MMLHHost *h in v.hosts) {
        NSString *root = h.repoRoot;
        for (MMFinding *w in trees) if (root.length && [w.path isEqualToString:root]) {
            links[h.findingID] = @{@"label": @"Worktree", @"value": w.title ?: root.lastPathComponent, @"expert": @"workforest", @"findingID": w.findingID};
            break;
        }
    }
    v.links = links;
    NSMutableSet *listening = [NSMutableSet new];
    for (MMLHHost *h in v.hosts) [listening addObjectsFromArray:h.ports];
    NSArray *records;
    if (NSThread.isMainThread) { @synchronized (self) { records = _stopped ?: @[]; } }
    else records = StoppedRecords();
    NSMutableArray *stopped = [NSMutableArray new];
    for (NSDictionary *x in records) {
        NSMutableDictionary *y = [x mutableCopy];
        y[@"taken"] = @([listening containsObject:x[@"port"] ?: @0]);
        [stopped addObject:y];
    }
    v.stopped = stopped;
    v.idleSeconds = MMLHIdleSeconds();
    v.watchingLeft = MMWatchingLeft(kExpert);
    v.otherCount = self.ignored.count;
    __weak MMLocoHost *weak = self;
    v.act = ^(NSString *what, NSString *key, BOOL option) { [weak act:what key:key option:option snapshot:s]; };
    if (NSThread.isMainThread) { _view = v; _viewGen = s.generation; }
    return v;
}

- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return MMLHMenu([self viewFor:s]); }

- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s {
    MMLHHost *h = HostOf(f);
    return h ? MMLHCard(h, [self viewFor:s]) : nil;
}

- (NSString *)badgeFor:(MMSnapshot *)s { return MMLHBadge([self viewFor:s]); }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return MMLHAccessibilityState([self viewFor:s]); }

- (BOOL)fieldEmptyIn:(MMSnapshot *)s {
    for (MMFinding *f in [s findingsFor:kExpert]) if (![f.facts[@"kind"] isEqual:@"other"]) return NO;
    return YES;
}

- (NSArray<MMVerbSpec *> *)verbs { return MMLHVerbs(); }

- (BOOL)openURL:(NSURL *)url {
    NSString *c = url.host.lowercaseString ?: @"";
    if ([c isEqualToString:@"review"]) { [self act:@"review" key:nil option:NO snapshot:MMGraph.shared.current]; return YES; }
    if ([c isEqualToString:@"close-idle"]) { [self act:@"close-idle" key:nil option:NO snapshot:MMGraph.shared.current]; return YES; }
    return NO;
}

#pragma mark Actions from the menu

static void Alert(NSString *title, NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *a = [NSAlert new];
        a.messageText = title; a.informativeText = text ?: @"";
        [NSApp activateIgnoringOtherApps:YES];
        [a runModal];
    });
}

static void Copy(NSString *s) {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:s ?: @"" forType:NSPasteboardTypeString];
}

/// Main thread. Anything that signals or restarts runs on the act queue, through MMRunAction or MMUndo.
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s {
    if ([what isEqualToString:@"investigate"] && key) {
        // Issue #35. The cost and the model show first, and only a confirmed run starts.
        [MMInvestigations.shared ask:key snapshot:s confirm:^NSString *(NSString *title, NSString *text, NSString *placeholder) {
            return MMInvestigateConfirm(title, text, placeholder);
        } failed:^(NSString *error) { MMInvestigateFailed(error); }];
        return;
    }
    MMFinding *f = key ? [s finding:key] : nil;
    MMLHHost *h = f ? HostOf(f) : nil;
    if ([what isEqualToString:@"stop"] && f) {
        dispatch_async(ActQueue(), ^{
            NSString *err = nil;
            MMUndoRecord *r = MMRunAction(MMLHStopAction(f, option ? MMStopKill : MMStopTerm), MMLHManualPolicy(), nil, @"manual", @"stopped from the menu", &err);
            if (!r || r.state != MMUndoDone) Alert([NSString stringWithFormat:@"Could Not Stop :%ld", (long)h.port], MMSentence(err ?: r.error));
            [MMGraph.shared rebuild:@"locohost stop"];
        });
    } else if ([what isEqualToString:@"close-idle"]) {
        NSArray *c = MMLHCandidates([s findingsFor:kExpert], [s reviewFor:kExpert]);
        dispatch_async(ActQueue(), ^{
            NSMutableArray *failed = [NSMutableArray new];
            for (MMFinding *x in c) {
                NSString *err = nil;
                MMUndoRecord *r = MMRunAction(MMLHStopAction(x, MMStopTerm), MMLHManualPolicy(), nil, @"manual", @"Close Idle", &err);
                if (!r || r.state != MMUndoDone) [failed addObject:[NSString stringWithFormat:@"%@: %@", x.title, err ?: r.error ?: @"it did not stop"]];
            }
            if (failed.count) Alert(@"Some Servers Did Not Stop", [failed componentsJoinedByString:@"\n"]);
            [MMGraph.shared rebuild:@"locohost close idle"];
        });
    } else if ([what isEqualToString:@"review"]) {
        _reviewing = YES; _view = nil;
        [MMReviewBroker.shared wake:@"manual" expert:kExpert];
    } else if ([what isEqualToString:@"restart"] && key) {
        dispatch_async(ActQueue(), ^{
            NSString *problem = [MMUndo.shared restore:key];
            if (problem) Alert(@"Could Not Restart", MMSentence(problem));
            [MMGraph.shared rebuild:@"locohost restart"];
        });
    } else if (!h) {
        return;
    } else if ([what isEqualToString:@"go"]) {
        MMPlace *p = MMWhereIs(Key(h.pid, h.startSec), s.facts.sample, NO);
        if (!p) return;
        // MMGoTo runs cmux, tmux or AppleScript and can take seconds, so it runs off main. Alert goes back to main.
        dispatch_async(MMQueue(kExpert, @"go", QOS_CLASS_USER_INITIATED), ^{
            NSString *err = nil;
            if (!MMGoTo(p, &err) && err) Alert([NSString stringWithFormat:@"Could Not Go to %@", p.app ?: @"It"], err);
        });
    } else if ([what isEqualToString:@"open"]) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:h.url]];
    } else if ([what isEqualToString:@"reveal"]) {
        [NSWorkspace.sharedWorkspace selectFile:nil inFileViewerRootedAtPath:h.cwd];
    } else if ([what isEqualToString:@"copy-url"]) {
        Copy(h.url);
    } else if ([what isEqualToString:@"copy-restart"]) {
        Copy(h.restartCommand);
    } else if ([what isEqualToString:@"keep"]) {
        // The keeps file is read and written on the act queue. The rebuild after it carries the new keep to the menu.
        BOOL kept = [f.facts[@"keptUntil"] doubleValue] > NSDate.date.timeIntervalSince1970;
        NSString *key = f.stableKey;
        dispatch_async(ActQueue(), ^{
            [MMKeep keep:key expert:kExpert until:kept ? nil : [NSDate dateWithTimeIntervalSinceNow:4 * 3600]];
            [MMGraph.shared rebuild:@"locohost keep"];
        });
        _view = nil;
    } else if ([what isEqualToString:@"protect"]) {
        // Only this port's own entry changes. A pattern that covers it stays for the others, as legacy #43 fixed for apps.
        [MMLHRules() set:!h.isProtected value:@(h.port) inList:@"protect.ports" key:nil];
        [MMGraph.shared rebuild:@"locohost protect"];
    }
}

#pragma mark The app: what wakes a review, and the mode after it

/// Installs the app's watchers once, on main, after the graph built LocoHost's first findings.
/// The CLI never gets here, since it builds snapshots by hand and the graph never publishes there.
- (void)hook {
    _known = [NSMutableDictionary new];
    [MMGraph.shared observe:^(MMSnapshot *s) { [self watch:s]; }];
    [MMSenses.shared observe:MMSignalMemory block:^(MMSignal changed, id detail) {
        if (MMSenses.shared.power.memoryPressure > 1) [MMReviewBroker.shared wake:@"memory pressure" expert:kExpert];
    }];
}

/// Ported from watchEvents and tick in LocoHost's main.m. Main thread, once per snapshot.
- (void)watch:(MMSnapshot *)s {
    NSArray<MMFinding *> *findings = [s findingsFor:kExpert];
    MMReview *r = [s reviewFor:kExpert];
    if (_reviewing && r.at && -r.at.timeIntervalSinceNow < 60) { _reviewing = NO; _view = nil; }
    BOOL first = !_learned;
    _learned = YES;
    static const double marks[] = {86400, 3 * 86400, 7 * 86400};
    NSString *wake = nil;
    for (MMFinding *f in findings) {
        if (![f.facts[@"kind"] isEqual:@"dev"]) continue;
        MMLHHost *h = HostOf(f);
        double up = -h.started.timeIntervalSinceNow;
        NSInteger passed = 0; while (passed < 3 && up >= marks[passed]) passed++;
        if (!_known[f.findingID]) {
            if (first || up >= kNewServer) {
                _known[f.findingID] = @(passed);
                if (!first) wake = [NSString stringWithFormat:@"new server :%ld %@", (long)h.port, h.framework];
            }
            continue;
        }
        if (passed > _known[f.findingID].integerValue) {
            _known[f.findingID] = @(passed);
            wake = [NSString stringWithFormat:@":%ld up %@", (long)h.port, MMDuration(marks[passed - 1])];
        }
    }
    NSInteger every = MMPrefInt(@"locohost.reviewMinutes", 60);
    if (every > 0 && findings.count && (!r || -r.at.timeIntervalSinceNow >= every * 60)) wake = @"schedule";
    if (wake && every > 0) [MMReviewBroker.shared wake:wake expert:kExpert];
    // A new review: the mode acts on fresh facts, through MMRunAction, and one notification says what it did.
    if (r.at && (!_actedOn || [r.at compare:_actedOn] == NSOrderedDescending)) {
        _actedOn = r.at;
        MMMode mode = MMModeFor(kExpert);
        if (mode == MMModeIdle || r.error.length) return;
        NSMutableArray *todo = [NSMutableArray new];
        NSDictionary *plan = MMLHPlanMap(findings, s.facts, r, mode);
        for (MMFinding *f in findings) if ([plan[f.findingID][@"stop"] boolValue]) [todo addObject:@[f, plan[f.findingID][@"why"]]];
        if (!todo.count) return;
        dispatch_async(ActQueue(), ^{ [self autoStop:todo review:r mode:mode]; });
    }
}

/// Act queue. Never asks and never force stops: a server that ignores SIGTERM stays and the notification says so.
- (void)autoStop:(NSArray<NSArray *> *)todo review:(MMReview *)r mode:(MMMode)mode {
    uint64_t freed = 0;
    NSInteger stopped = 0;
    NSString *lastRid = nil;
    NSMutableArray *lines = [NSMutableArray new];
    for (NSArray *t in todo) {
        MMFinding *f = t[0];
        NSString *err = nil;
        MMUndoRecord *rec = MMRunAction(MMLHStopAction(f, MMStopTerm), MMLHModePolicy(), r, MMModeName(mode), t[1], &err);
        if (!rec) continue;
        MMLHHost *h = HostOf(f);
        BOOL ok = rec.state == MMUndoDone;
        if (ok) { stopped++; freed += h.memory; lastRid = rec.rid; }
        [lines addObject:[NSString stringWithFormat:@":%ld %@%@", (long)h.port, h.project, ok ? @"" : @" is still running, since it ignored SIGTERM"]];
    }
    if (!lines.count) return;
    NSString *title = [NSString stringWithFormat:@"Stopped %@, Freed %@", MMCapitalized(MMPlural(stopped, @"server")).capitalizedString, MMBytes(freed)];
    NSString *body = [NSString stringWithFormat:@"%@ stopped %@. Undo starts %@ again from its recorded command.",
                      MMLHModeLabel(MMModeName(mode)), [lines componentsJoinedByString:@", "], stopped == 1 ? @"it" : @"the last one"];
    MMNotify(kExpert, title, body, lastRid);
    [MMGraph.shared rebuild:@"locohost mode"];
}

@end
