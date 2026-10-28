// Act: modes, the day of watching, keeps, MustKeep, plans, MMRunAction, stopping, quitting, keep-awake and the notifier.
// Modes, WFMustKeep, WFPlan and WFKeptUntil come from WorkForest's Forest.m. Stopping and the notifier come from
// LocoHost's StopHostsBy and notify. Quitting comes from QuitApps in MinMacs 1.2. Keep-awake uses Insomnia's assertion pair.
#import <sys/stat.h>
#import <AppKit/AppKit.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <UserNotifications/UserNotifications.h>
#import <sys/mount.h>
#import <sys/sysctl.h>
#import "Core/Act/MMAct.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"

static const double kSureConfidence = 0.8;               // Proactive acts only on a go this sure
static const double kMinConfidence = 0.6;                // Eager acts on a go this sure, or one the judge made
static const NSTimeInterval kReviewFresh = 6 * 3600;     // a mode acts only on a review this recent
static const NSTimeInterval kWatchDay = 24 * 3600;       // the day of watching
static const NSTimeInterval kNotifyGap = 600;            // one notification per review: reviews are 10 minutes apart

static NSString *Plural(NSInteger n, NSString *word) { return [NSString stringWithFormat:@"%ld %@%@", (long)n, word, n == 1 ? @"" : @"s"]; }
static NSString *Span(NSTimeInterval s) {
    if (s < 0) s = 0;
    if (s < 90) return Plural((NSInteger)s, @"second");
    if (s < 90 * 60) return Plural((NSInteger)(s / 60), @"minute");
    if (s < 36 * 3600) return Plural((NSInteger)(s / 3600), @"hour");
    return Plural((NSInteger)(s / 86400), @"day");
}

#pragma mark - Modes

NSString *MMModeName(MMMode mode) {
    switch (mode) {
        case MMModeIdle: return @"idle";
        case MMModeProactive: return @"proactive";
        case MMModeEager: return @"eager";
    }
    return @"proactive";
}
NSInteger MMModeFrom(NSString *name) {
    NSUInteger i = [@[@"idle", @"proactive", @"eager"] indexOfObject:name.lowercaseString ?: @""];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
MMMode MMModeFor(NSString *expert) {
    id v = MMPref([expert stringByAppendingString:@".mode"]);
    NSInteger m = [v isKindOfClass:NSString.class] ? MMModeFrom(v) : -1;
    return m < 0 ? MMModeProactive : (MMMode)m;
}
void MMSetMode(NSString *expert, MMMode mode) { MMSetPref([expert stringByAppendingString:@".mode"], MMModeName(mode)); }

#pragma mark - The day of watching

static NSString *SincePath(void) { return [MMSupportDir() stringByAppendingPathComponent:@"watching-since"]; }
/// When MinMacs started watching, at its first launch. nil before that, so no mode acts on a CLI that was tried once.
static NSDate *Since(void) {
    NSString *s = [NSString stringWithContentsOfFile:SincePath() encoding:NSUTF8StringEncoding error:nil];
    return s.doubleValue > 0 ? [NSDate dateWithTimeIntervalSince1970:s.doubleValue] : nil;
}
void MMStartWatching(void) {
    if (Since()) return;
    [[NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970] writeToFile:SincePath() atomically:YES
                                                                                encoding:NSUTF8StringEncoding error:nil];
}
// The expert is not used yet: every expert starts watching at the app's first launch.
BOOL MMWatchedLongEnough(NSString *expert) { NSDate *d = Since(); return d && -d.timeIntervalSinceNow >= kWatchDay; }
NSTimeInterval MMWatchingLeft(NSString *expert) { NSDate *d = Since(); return d ? MAX(0, kWatchDay + d.timeIntervalSinceNow) : kWatchDay; }

static NSString *WatchingWords(NSString *expert) {
    return Since() ? [NSString stringWithFormat:@"MinMacs watches for %@ more before it acts on its own", Span(MMWatchingLeft(expert))]
                   : @"MinMacs has not started watching, and acts on its own a day after it first runs";
}

#pragma mark - Keeps

static NSString *KeepsPath(NSString *expert) { return [MMExpertDir(expert) stringByAppendingPathComponent:@"keeps.json"]; }
static _Atomic NSUInteger gKeepMainReads;
NSUInteger MMKeepMainThreadReads(void) { return gKeepMainReads; }
/// The last keeps read off main, per expert. keptUntil: on main answers from here and never reads the file.
static NSMutableDictionary<NSString *, NSDictionary *> *KeepCache(void) {
    static NSMutableDictionary *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [NSMutableDictionary new]; });
    return c;
}
static NSMutableDictionary *ReadKeeps(NSString *path);
static NSMutableDictionary *KeepsAll(NSString *expert) {
    if (NSThread.isMainThread) gKeepMainReads++;
    // The file is parsed again only when it changed, issue #52. A rebuild asks once per finding.
    static NSMutableDictionary<NSString *, NSArray *> *parsed;   // expert to [stamp, keeps]
    NSString *path = KeepsPath(expert);
    struct stat st;
    NSString *stamp = stat(path.fileSystemRepresentation, &st) == 0
        ? [NSString stringWithFormat:@"%llu:%ld.%ld:%lld", (unsigned long long)st.st_ino, (long)st.st_mtimespec.tv_sec,
                                     st.st_mtimespec.tv_nsec, (long long)st.st_size] : @"-";
    @synchronized (KeepCache()) {
        if (!parsed) parsed = [NSMutableDictionary new];
        NSArray *p = parsed[expert];
        if ([p.firstObject isEqualToString:stamp]) return [p.lastObject mutableCopy];
    }
    NSMutableDictionary *all = ReadKeeps(path);
    @synchronized (KeepCache()) { KeepCache()[expert] = [all copy]; parsed[expert] = @[stamp, [all copy]]; }
    return all;
}

static NSMutableDictionary *ReadKeeps(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
    return [j isKindOfClass:NSMutableDictionary.class] ? j : [NSMutableDictionary new];
}

/// The protect list in the expert's rules file, through MMRules. MMRules does not expand ~ in an entry,
/// so a path is also matched in its ~ form.
static BOOL ProtectedIn(NSString *expert, NSString *value) {
    MMRules *r = [MMRules rulesFor:expert defaults:@{}];
    NSString *short_ = [value hasPrefix:@"/"] ? value.stringByAbbreviatingWithTildeInPath : nil;
    return [r list:@"protect" key:nil matches:value] ||
           (short_.length && ![short_ isEqualToString:value] && [r list:@"protect" key:nil matches:short_]);
}

@implementation MMKeep
+ (NSDate *)keptUntil:(NSString *)stableKey expert:(NSString *)expert {
    if (!stableKey.length || !expert.length) return nil;
    NSNumber *n;
    // A menu asks on main, and main never waits on disk. The graph queue reads the file on every rebuild, so in the
    // app main answers from that read. A CLI asks on its main thread with nothing read yet, and reads the file.
    NSDictionary *cached = nil;
    if (NSThread.isMainThread) { @synchronized (KeepCache()) { cached = KeepCache()[expert]; } }
    if (cached) n = cached[stableKey];
    else { @synchronized (self) { n = KeepsAll(expert)[stableKey]; } }
    return [n isKindOfClass:NSNumber.class] && n.doubleValue > NSDate.date.timeIntervalSince1970 ? [NSDate dateWithTimeIntervalSince1970:n.doubleValue] : nil;
}
+ (void)keep:(NSString *)stableKey expert:(NSString *)expert until:(NSDate *)until {
    if (!stableKey.length || !expert.length) return;
    @synchronized (self) {
        NSMutableDictionary *all = KeepsAll(expert);
        double now = NSDate.date.timeIntervalSince1970;
        for (NSString *k in all.allKeys) if ([all[k] doubleValue] <= now) [all removeObjectForKey:k];
        if (until) all[stableKey] = @(until.timeIntervalSince1970); else [all removeObjectForKey:stableKey];
        [[NSJSONSerialization dataWithJSONObject:all options:0 error:nil] writeToFile:KeepsPath(expert) atomically:YES];
        @synchronized (KeepCache()) { KeepCache()[expert] = [all copy]; }
    }
}
/// The expert's list, then the shared list in core/rules.json, which every expert honors.
+ (BOOL)isProtected:(NSString *)value expert:(NSString *)expert {
    if (!value.length) return NO;
    return (expert.length && ProtectedIn(expert, value)) || ProtectedIn(@"core", value);
}
@end

#pragma mark - MustKeep

static NSString *ReviewKeeps(MMFinding *f, MMReview *r, id<MMExpertPolicy> policy) {
    if (r.expert.length && f.expert.length && ![r.expert isEqualToString:f.expert]) return @"the review is for another expert";
    if (r.error.length) return @"the last review failed";
    if (!r.at) return @"the review has no time";
    if (-r.at.timeIntervalSinceNow > kReviewFresh) return [NSString stringWithFormat:@"the last review is %@ old", Span(-r.at.timeIntervalSinceNow)];
    MMVerdict *v = r.verdicts[f.findingID];
    if (!v) return @"not in the last review";
    if (v.fingerprint.length && f.fingerprint.length && ![v.fingerprint isEqualToString:f.fingerprint]) return @"changed since the last review";
    NSString *own = [policy reviewKeeps:f review:r];
    return own.length ? own : nil;
}

NSString *MMMustKeep(MMFinding *f, MMFacts *facts, MMReview *r, id<MMExpertPolicy> policy) {
    if (!f) return @"cannot verify: there is no finding";
    if (!policy) return @"cannot verify: the expert has no rules";
    if (!facts) return @"cannot verify: fresh facts could not be gathered";
    NSString *work = [policy workKeeps:f facts:facts];
    if (work.length) return work;
    if (f.keepReasons.count) return f.keepReasons.firstObject;
    if (r) { NSString *rk = ReviewKeeps(f, r, policy); if (rk) return rk; }
    NSDate *until = [MMKeep keptUntil:f.stableKey expert:f.expert];
    if (until) return [NSString stringWithFormat:@"kept by you for %@ more", Span(until.timeIntervalSinceNow)];
    if ([MMKeep isProtected:f.stableKey expert:f.expert] || [MMKeep isProtected:f.path expert:f.expert]) return @"protected";
    return nil;
}

#pragma mark - Plans

@interface MMPlanEntry ()
@property (readwrite) MMFinding *finding;
@property (readwrite) BOOL act;
@property (readwrite, copy) NSString *why;
@end
@implementation MMPlanEntry
@end

/// What a mode does to a finding that MustKeep lets go. Sets *act and returns why.
static NSString *ModeDecides(MMFinding *f, MMReview *r, MMMode m, id<MMExpertPolicy> policy, BOOL *act) {
    *act = NO;
    if (!f.proposal) return @"nothing to do";
    if (m == MMModeIdle) return @"Idle mode only reports";
    if (!r) return @"no review yet";
    if (f.proposal.needsForce) return @"it needs a second request, and a mode never makes one";
    if ([policy respondsToSelector:@selector(modeKeeps:mode:review:)]) {
        NSString *own = [policy modeKeeps:f mode:m review:r];
        if (own.length) return own;
    }
    MMVerdict *v = r.verdicts[f.findingID];
    NSString *about = v.reason.length ? v.reason : (v.about ?: @"");
    if (m == MMModeProactive) {
        // Decision 7: what needs a git bundle is removed in Eager only.
        if (f.proposal.reversibility == MMReversibleBundle) return @"it holds commits on no remote; Proactive keeps it, and Eager may act after a git bundle";
        if (v.kind != MMVerdictGo) return v.kind == MMVerdictKeep ? [@"the review keeps it: " stringByAppendingString:about] : @"the review is not sure";
        if (v.keepEvidence.length) return [@"evidence: " stringByAppendingString:v.keepEvidence];
        if (v.confidence < kSureConfidence) return [NSString stringWithFormat:@"the review is %.0f%% sure; Proactive needs %.0f%%", v.confidence * 100, kSureConfidence * 100];
        *act = YES;
        return about.length ? about : @"the review lets it go";
    }
    if (v.kind == MMVerdictGo && !v.keepEvidence.length && (v.judged || v.confidence >= kMinConfidence)) {
        *act = YES;
        return about.length ? about : @"the review lets it go";
    }
    if (v.kind == MMVerdictGo && v.keepEvidence.length) return [@"evidence: " stringByAppendingString:v.keepEvidence];
    if (v.kind == MMVerdictGo) return r.judgeError.length ? [@"the judge failed: " stringByAppendingString:r.judgeError]
                                                         : [NSString stringWithFormat:@"the review is %.0f%% sure", v.confidence * 100];
    return v.kind == MMVerdictKeep ? [@"the review keeps it: " stringByAppendingString:about] : @"the review is not sure";
}

NSArray<MMPlanEntry *> *MMPlan(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r, MMMode m,
                               id<MMExpertPolicy> policy) {
    NSMutableArray *plan = [NSMutableArray new];
    for (MMFinding *f in findings) {
        BOOL act = NO;
        NSString *why = MMMustKeep(f, facts, r, policy);
        if (!why) why = ModeDecides(f, r, m, policy, &act);
        if (act && !MMWatchedLongEnough(f.expert)) { act = NO; why = [NSString stringWithFormat:@"would act (%@), but %@", why, WatchingWords(f.expert)]; }
        MMPlanEntry *e = [MMPlanEntry new];
        e.finding = f; e.act = act; e.why = why;
        [plan addObject:e];
    }
    return plan;
}

#pragma mark - Running one action

static uint64_t FreeBytes(NSString *path) {
    struct statfs s;
    NSString *p = path.length ? path : NSHomeDirectory();
    while (p.length > 1 && statfs(p.fileSystemRepresentation, &s) != 0) p = p.stringByDeletingLastPathComponent;
    if (statfs(p.fileSystemRepresentation, &s) != 0) return 0;
    return (uint64_t)s.f_bavail * s.f_bsize;
}

MMUndoRecord *MMRunAction(id<MMAction> action, id<MMExpertPolicy> policy, MMReview *review,
                          NSString *by, NSString *why, NSString **error) {
    NSString *problem = nil;
    MMFinding *f = action.finding;
    BOOL byMode = [by isEqualToString:@"proactive"] || [by isEqualToString:@"eager"];
    if (NSThread.isMainThread) problem = @"an action never runs on the main thread";
    else if (!action || !f) problem = @"cannot verify: there is no finding";
    if (!problem && byMode) {
        // A mode run is checked again too: the mode, the day of watching and the review may have changed since the plan.
        if (![MMModeName(MMModeFor(f.expert)) isEqualToString:by]) problem = [NSString stringWithFormat:@"kept: the mode is now %@", MMModeName(MMModeFor(f.expert))];
        else if (!MMWatchedLongEnough(f.expert)) problem = [@"kept: " stringByAppendingString:WatchingWords(f.expert)];
        else if (!review) problem = @"kept: no review yet";
        else if (f.proposal.needsForce) problem = @"kept: a mode never makes a second request";
    }
    if (!problem) {
        NSString *r = [action recheck];
        if (r.length) problem = [@"cannot run now: " stringByAppendingString:r];
    }
    if (!problem) {
        MMFacts *fresh = [MMGraph.shared freshFactsFor:f];
        NSString *keep = MMMustKeep(f, fresh, review, policy);
        if (keep) problem = [@"kept: " stringByAppendingString:keep];
    }
    if (problem) {
        if (error) *error = problem;
        return nil;
    }
    MMUndoRecord *record = [MMUndo.shared begin:f.expert kind:action.kind finding:f.findingID subject:f.title
                                            why:why by:by parent:nil payload:nil];
    uint64_t before = FreeBytes(f.path);
    NSString *err = nil;
    BOOL ok = NO;
    @try { ok = [action perform:record error:&err]; }
    @catch (NSException *e) { ok = NO; err = e.reason ?: e.name; }
    uint64_t after = FreeBytes(f.path);
    int64_t freed = after > before ? (int64_t)(after - before) : 0;
    [MMUndo.shared finish:record ok:ok freed:freed error:ok ? nil : (err ?: @"the action failed")];
    if (!ok && error) *error = err ?: @"the action failed";
    return [MMUndo.shared record:record.rid] ?: record;
}

#pragma mark - Stopping

/// Why key must not be signaled, or nil when it may. Read fresh from the kernel each time.
NSString *MMStopWhyNot(MMProcKey key);
NSString *MMStopWhyNot(MMProcKey key) {
    if (key.pid <= 1) return @"pid 1 is never signaled";
    if (key.pid == getpid()) return @"MinMacs never signals itself";
    struct kinfo_proc kp;
    size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, key.pid };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0 || kp.kp_proc.p_stat == SZOMB) return @"it has already exited";
    if ((uint64_t)kp.kp_proc.p_starttime.tv_sec != key.startSec) return @"its pid now belongs to another process";
    if (kp.kp_eproc.e_ucred.cr_uid != getuid()) return @"it belongs to another user";
    if (!MMProcAlive(key)) return @"it has already exited";
    return nil;
}

/// The keys that got SIGTERM or a normal quit, so SIGKILL and force quit come only as a second request.
/// Kept in core/term-sent.json, so a second request from the CLI counts too. Entries older than a day drop off.
static NSString *TermPath(void) { return [MMExpertDir(@"core") stringByAppendingPathComponent:@"term-sent.json"]; }
static NSMutableDictionary *TermAll(void) {
    NSData *d = [NSData dataWithContentsOfFile:TermPath()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil] : nil;
    return [j isKindOfClass:NSMutableDictionary.class] ? j : [NSMutableDictionary new];
}
static NSObject *TermLock(void) { static NSObject *o; static dispatch_once_t once; dispatch_once(&once, ^{ o = [NSObject new]; }); return o; }
static void NoteTerm(MMProcKey key) {
    @synchronized (TermLock()) {
        NSMutableDictionary *all = TermAll();
        double now = NSDate.date.timeIntervalSince1970;
        for (NSString *k in all.allKeys) if (now - [all[k] doubleValue] > 86400) [all removeObjectForKey:k];
        all[MMProcKeyString(key)] = @(now);
        [[NSJSONSerialization dataWithJSONObject:all options:0 error:nil] writeToFile:TermPath() atomically:YES];
    }
}
static BOOL TermSent(MMProcKey key) {
    @synchronized (TermLock()) { return TermAll()[MMProcKeyString(key)] != nil; }
}

static NSArray<NSValue *> *StillAlive(NSArray<NSValue *> *keys, NSTimeInterval grace) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:grace];
    NSMutableArray *left = [keys mutableCopy];
    while (YES) {
        [left filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSValue *v, id _) {
            MMProcKey k; [v getValue:&k size:sizeof k]; return MMProcAlive(k); }]];
        if (!left.count || deadline.timeIntervalSinceNow <= 0) break;
        usleep(50000);
    }
    return left;
}

NSArray<NSValue *> *MMStop(NSArray<NSValue *> *keys, MMStopStep step, NSTimeInterval grace) {
    NSMutableArray *sent = [NSMutableArray new];
    for (NSValue *v in keys) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        if (MMStopWhyNot(k)) continue;                      // checked right before the signal
        if (step == MMStopKill && !TermSent(k)) continue;   // SIGKILL only on a second request
        if (step == MMStopTerm) NoteTerm(k);
        if (kill(k.pid, step == MMStopKill ? SIGKILL : SIGTERM) == 0) [sent addObject:v];
    }
    if (sent.count) (void)StillAlive(sent, grace);
    return StillAlive(keys, 0);
}

NSArray<NSValue *> *MMQuitApps(NSArray<NSValue *> *keys, MMStopStep step, NSTimeInterval grace) {
    NSMutableArray *sent = [NSMutableArray new];
    for (NSValue *v in keys) {
        MMProcKey k; [v getValue:&k size:sizeof k];
        if (MMStopWhyNot(k)) continue;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:k.pid];
        if (!app) continue;                                  // not an app; MMStop is for processes
        if (step == MMStopKill && !TermSent(k)) continue;    // force quit only on a second request
        if (step == MMStopTerm) NoteTerm(k);
        if (step == MMStopKill ? [app forceTerminate] : [app terminate]) [sent addObject:v];
    }
    if (sent.count) (void)StillAlive(sent, grace);
    return StillAlive(keys, 0);
}

#pragma mark - Keep-awake

/// One held agent: Insomnia's assertion pair and a kqueue exit source on its pid.
@interface MMAwakeHold : NSObject
@property MMProcKey key;
@property (copy) NSString *reason;
@property IOPMAssertionID idle, system;
@property dispatch_source_t exit;
@end
@implementation MMAwakeHold
@end

static NSMutableDictionary<NSString *, MMAwakeHold *> *Holds(void) {
    static NSMutableDictionary *h; static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [NSMutableDictionary new]; });
    return h;
}
static dispatch_queue_t AwakeQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = MMQueue(@"core", @"awake", QOS_CLASS_UTILITY); });
    return q;
}
static void Drop(MMAwakeHold *h) {
    if (h.exit) dispatch_source_cancel(h.exit);
    if (h.idle) IOPMAssertionRelease(h.idle);
    if (h.system) IOPMAssertionRelease(h.system);
}

@implementation MMAwake
+ (void)holdFor:(MMProcKey)agent reason:(NSString *)why {
    if (agent.pid <= 1 || !MMProcAlive(agent)) return;
    NSString *ks = MMProcKeyString(agent);
    @synchronized (self) {
        MMAwakeHold *old = Holds()[ks];
        if (old) { old.reason = why; return; }
        MMAwakeHold *h = [MMAwakeHold new];
        h.key = agent; h.reason = why ?: @"an agent works";
        // The pair caffeinate -i -s takes: idle sleep always, system sleep on power.
        NSString *name = [@"MinMacs keeps the Mac awake: " stringByAppendingString:h.reason];
        IOPMAssertionID a = 0, b = 0;
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, (__bridge CFStringRef)name, &a);
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep, kIOPMAssertionLevelOn, (__bridge CFStringRef)name, &b);
        h.idle = a; h.system = b;
        h.exit = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)agent.pid, DISPATCH_PROC_EXIT, AwakeQueue());
        dispatch_source_set_event_handler(h.exit, ^{ [MMAwake release:agent]; });
        dispatch_resume(h.exit);
        Holds()[ks] = h;
    }
    // The process may have ended between the first check and the exit source. Then nothing would fire.
    if (!MMProcAlive(agent)) [self release:agent];
}
+ (void)release:(MMProcKey)agent {
    @synchronized (self) {
        NSString *ks = MMProcKeyString(agent);
        MMAwakeHold *h = Holds()[ks];
        if (!h) return;
        [Holds() removeObjectForKey:ks];
        Drop(h);
    }
}
+ (void)releaseAll {
    @synchronized (self) {
        for (MMAwakeHold *h in Holds().allValues) Drop(h);
        [Holds() removeAllObjects];
    }
}
+ (NSDictionary<NSString *, NSString *> *)held {
    NSMutableDictionary *out = [NSMutableDictionary new];
    @synchronized (self) { for (NSString *k in Holds()) out[k] = Holds()[k].reason; }
    return out;
}
@end

#pragma mark - The notifier

/// The system notifier. It asks for permission the first time it posts, never at launch, and handles Undo.
@interface MMSystemNotifier : NSObject <MMNotifier, UNUserNotificationCenterDelegate>
@end
@implementation MMSystemNotifier {
    BOOL _asked;
}
- (void)post:(NSString *)title body:(NSString *)body undoRid:(NSString *)undoRid passive:(BOOL)passive expert:(NSString *)expert {
    UNUserNotificationCenter *c = UNUserNotificationCenter.currentNotificationCenter;
    if (!_asked) {
        _asked = YES;
        c.delegate = self;
        UNNotificationAction *undo = [UNNotificationAction actionWithIdentifier:@"undo" title:@"Undo" options:UNNotificationActionOptionNone];
        [c setNotificationCategories:[NSSet setWithObject:[UNNotificationCategory categoryWithIdentifier:@"minmacs.undo" actions:@[undo]
                                                                                       intentIdentifiers:@[] options:0]]];
        [c requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL ok, NSError *e) {}];
    }
    UNMutableNotificationContent *n = [UNMutableNotificationContent new];
    n.title = title; n.body = body;
    n.threadIdentifier = expert ?: @"minmacs";
    n.interruptionLevel = passive ? UNNotificationInterruptionLevelPassive : UNNotificationInterruptionLevelActive;
    if (undoRid) { n.categoryIdentifier = @"minmacs.undo"; n.userInfo = @{@"rid": undoRid}; }
    [c addNotificationRequest:[UNNotificationRequest requestWithIdentifier:NSUUID.UUID.UUIDString content:n trigger:nil] withCompletionHandler:nil];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))done {
    NSString *rid = response.notification.request.content.userInfo[@"rid"];
    if ([response.actionIdentifier isEqualToString:@"undo"] && [rid isKindOfClass:NSString.class])
        dispatch_async(MMQueue(@"core", @"undo", QOS_CLASS_UTILITY), ^{ (void)[MMUndo.shared restore:rid]; });
    done();
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))done {
    done(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}
@end

static id<MMNotifier> gNotifier;
void MMUseNotifier(id<MMNotifier> notifier) { @synchronized (MMUndo.class) { gNotifier = notifier; } }

/// Nearly full: under 5 percent or under 10 GB free on the home volume.
static BOOL DiskNearlyFull(void) {
    uint64_t freeBytes = FreeBytes(NSHomeDirectory()), total = 0;
    struct statfs s;
    if (statfs(NSHomeDirectory().fileSystemRepresentation, &s) == 0) total = (uint64_t)s.f_blocks * s.f_bsize;
#ifdef MM_TESTS
    NSString *fake = NSProcessInfo.processInfo.environment[@"MINMACS_TEST_DISK_FREE"];
    if (fake.length) freeBytes = (uint64_t)fake.longLongValue;
#endif
    return freeBytes < (10ull << 30) || (total && freeBytes * 20 < total);
}

void MMNotify(NSString *expert, NSString *title, NSString *body, NSString *undoRid) {
    if (undoRid) {
        MMUndoRecord *r = [MMUndo.shared record:undoRid];
        if ([r.by isEqualToString:@"manual"] || [r.by isEqualToString:@"cli"]) return;   // the person asked, so they know
    }
    // One per review across every expert: reviews are at least 10 minutes apart, so one per 10 minutes.
    double now = NSDate.date.timeIntervalSince1970, gap = kNotifyGap;
    id g = MMPref(@"act.notifyGap");
    if ([g isKindOfClass:NSNumber.class]) gap = [g doubleValue];
    id last = MMPref(@"act.lastNotify");
    if ([last isKindOfClass:NSNumber.class] && now - [last doubleValue] < gap) return;
    while ([title hasSuffix:@"."]) title = [title substringToIndex:title.length - 1];
    id<MMNotifier> n;
    @synchronized (MMUndo.class) {
        // Only an app bundle can post. The CLI has no bundle id, so it never posts.
        if (!gNotifier && NSBundle.mainBundle.bundleIdentifier.length) gNotifier = [MMSystemNotifier new];
        n = gNotifier;
    }
    if (!n) return;
    MMSetPref(@"act.lastNotify", @(now));
    [n post:title body:body undoRid:undoRid passive:!DiskNearlyFull() expert:expert];
}
