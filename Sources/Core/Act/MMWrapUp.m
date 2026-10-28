// Wrap Up: one undoable step for a finished workstream, PLAN.md section 6, issue #27. See MMAct.h.
// New code. Each expert hands over the parts it owns through -[MMExpert wrapUpParts:snapshot:]. Core orders them,
// checks every part on fresh facts, writes one record of kind "wrapup", and runs each part through MMRunActionPart
// with that record as its parent. -[MMUndo restore:] takes the parts back newest first.
#import "Core/Act/MMAct.h"
#import "Core/MMExpert.h"
#import "Core/Act/MMWorktreeAct.h"
#import "Core/Runtime/MMRuntime.h"
#include <stdlib.h>
#include <os/lock.h>
#include <time.h>

static NSString *Real(NSString *path) {
    if (!path.length) return path;
    char buf[PATH_MAX];
    return realpath(path.fileSystemRepresentation, buf) ? @(buf) : path.stringByStandardizingPath;
}

/// Issue #54. Real for a subject made from a snapshot, read once per path for that snapshot and for at most 2 seconds.
/// WorkForest plans every merged worktree on each build, and each plan resolved every worktree and finding path,
/// 155,000 realpath calls a build with 300 worktrees. The check before an action passes no snapshot, so it reads
/// realpath every time.
static NSString *RealFor(NSString *path, MMSnapshot *s) {
    if (!s || !path.length) return Real(path);
    static NSMutableDictionary<NSString *, NSString *> *memo;
    static __weak MMSnapshot *memoFor;
    static uint64_t memoAt;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    NSString *hit;
    os_unfair_lock_lock(&lock);
    if (memoFor != s || now - memoAt > 2 * NSEC_PER_SEC || memo.count > 20000) { memo = [NSMutableDictionary new]; memoFor = s; memoAt = now; }
    hit = memo[path];
    os_unfair_lock_unlock(&lock);
    if (hit) return hit;
    NSString *r = Real(path);
    os_unfair_lock_lock(&lock);
    if (memoFor == s) memo[path] = r;
    os_unfair_lock_unlock(&lock);
    return r;
}

/// path is folder or inside it. No string is made, since a build asks this about 400,000 times with 300 worktrees.
static BOOL PathIn(NSString *path, NSString *folder) {
    if (!path.length || !folder.length || ![path hasPrefix:folder]) return NO;
    return path.length == folder.length || [path characterAtIndex:folder.length] == '/';
}

NSString *MMWrapUpStepName(MMWrapUpStep step) {
    switch (step) {
        case MMWrapUpServers: return @"servers";
        case MMWrapUpHelpers: return @"helpers";
        case MMWrapUpCaches: return @"caches";
        case MMWrapUpConfig: return @"config";
        case MMWrapUpWorktree: return @"worktree";
    }
    return @"part";
}

static NSString *AgentWords(NSString *harness) {
    NSDictionary *names = @{@"claude-code": @"Claude Code", @"codex": @"Codex", @"cursor": @"Cursor", @"pi": @"pi"};
    return names[harness ?: @""] ?: harness ?: @"An agent";
}

#pragma mark - Untracked config files

static NSMutableDictionary<NSString *, NSNumber *> *ConfigAnswers(void) {
    static NSMutableDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
    return d;
}

static NSNumber *ConfigCheck(NSString *path) {
    NSArray<NSString *> *files = MMWorktreeUntrackedFiles(path);
    if (!files) return nil;
    for (NSString *f in files) if (!MMWorktreeIsConfigFile(f)) return @NO;
    return @YES;
}

NSNumber *MMWrapUpConfigOnly(NSString *path, NSString *head, NSInteger untracked, BOOL wait) {
    if (!path.length) return nil;
    if (untracked == 0) return @YES;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%ld", path, head ?: @"-", (long)untracked];
    NSNumber *have;
    @synchronized (ConfigAnswers()) { have = ConfigAnswers()[key]; }
    if (have) return have.integerValue < 0 ? nil : have;
    if (wait && !NSThread.isMainThread) {
        NSNumber *n = ConfigCheck(path);
        if (n) @synchronized (ConfigAnswers()) { ConfigAnswers()[key] = n; }
        return n;
    }
    @synchronized (ConfigAnswers()) {
        if (ConfigAnswers().count > 256) [ConfigAnswers() removeAllObjects];
        ConfigAnswers()[key] = @(-1);   // asked, not answered yet
    }
    dispatch_async(MMQueue(@"core", @"wrapup", QOS_CLASS_UTILITY), ^{
        NSNumber *n = ConfigCheck(path);
        @synchronized (ConfigAnswers()) { if (n) ConfigAnswers()[key] = n; else [ConfigAnswers() removeObjectForKey:key]; }
        if (n) [MMGraph.shared rebuild:@"wrap up config files"];
    });
    return nil;
}

#pragma mark - The subject

@interface MMWrapUpSubject ()
@property (readwrite, copy) NSString *path, *given, *whyNot;
@property (readwrite) MMWorktree *worktree;
@property (readwrite) MMGitFacts *git;
@property (readwrite) NSArray<MMSession *> *sessions;
@property (readwrite) NSArray<MMFinding *> *findings;
@property (readwrite) NSArray<NSValue *> *stopped;
@property (readwrite) BOOL configPart;
@property (weak) MMSnapshot *made;              // the snapshot it was made from, nil for a check on fresh facts
@end

@implementation MMWrapUpSubject

- (BOOL)holds:(NSString *)path {
    if (!path.length) return NO;
    if (PathIn(path, self.path) || PathIn(path, self.given) || PathIn(path, self.worktree.path)) return YES;
    return PathIn(RealFor(path, self.made), self.path);
}

+ (instancetype)subjectAt:(NSString *)path facts:(MMFacts *)facts snapshot:(MMSnapshot *)s {
    MMWrapUpSubject *x = [MMWrapUpSubject new];
    x.made = s;
    x.given = path.stringByStandardizingPath;
    x.path = RealFor(x.given, s);
    x.stopped = @[];
    for (MMWorktree *w in facts.worktrees) {
        if (!w.path.length) continue;
        if ([w.path isEqualToString:x.given] || [w.path isEqualToString:x.path] || [RealFor(w.path, s) isEqualToString:x.path]) { x.worktree = w; break; }
    }
    x.git = x.worktree ? [facts gitFor:x.worktree] : nil;
    NSMutableArray<MMSession *> *sessions = [NSMutableArray new];
    for (MMSession *e in facts.sessions) if ([x holds:e.cwd]) [sessions addObject:e];
    [sessions sortUsingComparator:^NSComparisonResult(MMSession *a, MMSession *b) {
        NSDate *p = a.lastActive ?: a.started, *q = b.lastActive ?: b.started;
        if (p && q) return [q compare:p];
        return p ? NSOrderedAscending : q ? NSOrderedDescending : NSOrderedSame;
    }];
    x.sessions = sessions;
    x.whyNot = [x reasonIn:facts];
    // Issue #54: the findings only for a finished workstream, the one a plan asks the experts about. A build plans
    // every merged worktree, and scanning every finding for each one took most of the build with 300 worktrees.
    NSMutableArray<MMFinding *> *held = [NSMutableArray new];
    if (!x.whyNot)
        for (MMFinding *f in s.findings) if ([x holds:f.owner.path] || [x holds:f.ownerPath] || [x holds:f.path]) [held addObject:f];
    x.findings = held;
    return x;
}

/// Why this is not a finished workstream in these facts, or nil.
- (NSString *)reasonIn:(MMFacts *)facts {
    MMWorktree *w = self.worktree;
    if (!w) return [NSString stringWithFormat:@"no worktree at %@ in the last scan", self.given.stringByAbbreviatingWithTildeInPath];
    if (w.isMain || [RealFor(w.repo, self.made) isEqualToString:self.path]) return @"a main checkout is never wrapped up";
    if (w.missing) return @"its folder is gone";
    if (!self.git) return @"cannot verify: its git facts are not known yet";
    if (self.git.merged == MMMergedNone) return @"its branch is not merged";
    for (MMAgent *a in facts.agents) {
        if ([self holds:a.cwd]) return [NSString stringWithFormat:@"%@ still runs in it", AgentWords(a.harnessID)];
        for (MMAgent *h in a.hosted) if ([self holds:h.cwd]) return [NSString stringWithFormat:@"%@ still runs in it", AgentWords(h.harnessID)];
    }
    if (!self.sessions.count) return @"no agent session ran in it";
    for (MMSession *e in self.sessions) {
        if (e.stillWorking) return [NSString stringWithFormat:@"%@ still works in it", AgentWords(e.agent)];
        if (e.pid > 0 && [facts.sample proc:e.pid]) return [NSString stringWithFormat:@"its %@ session still runs", AgentWords(e.agent)];
    }
    return nil;
}

/// A finding that names the worktree, so -[MMGraph freshFactsFor:] reads its git facts with wait YES.
- (MMFinding *)finding {
    NSString *p = self.worktree.path ?: self.path;
    return [MMFinding expert:@"core" kind:@"workstream" stableKey:p build:^(MMFindingBuilder *b) {
        b.path = p; b.title = p.lastPathComponent;
    }];
}
@end

#pragma mark - Parts and plans

@interface MMWrapUpPart ()
@property (readwrite) MMWrapUpStep step;
@property (readwrite, copy) NSString *expert, *title, *whyNot;
@property (readwrite) id<MMAction> action;
@property (readwrite) id<MMExpertPolicy> policy;
@end

@implementation MMWrapUpPart
+ (instancetype)step:(MMWrapUpStep)step expert:(NSString *)expert title:(NSString *)title
              action:(id<MMAction>)action policy:(id<MMExpertPolicy>)policy {
    if (!action.finding) return nil;
    MMWrapUpPart *p = [MMWrapUpPart new];
    p.step = step; p.expert = expert ?: action.finding.expert; p.title = title ?: action.finding.title;
    p.action = action; p.policy = policy;
    return p;
}
@end

@interface MMWrapUpPlan ()
@property (readwrite) MMWrapUpSubject *subject;
@property (readwrite) NSArray<MMWrapUpPart *> *parts;
@property (readwrite, copy) NSString *whyNot;
@end

@implementation MMWrapUpPlan

- (uint64_t)freedBytes {
    BOOL tree = NO;
    for (MMWrapUpPart *p in self.parts) if (p.step == MMWrapUpWorktree) tree = YES;
    uint64_t n = 0;
    // What the worktree frees counts its caches too, so a cache inside it is counted once.
    for (MMWrapUpPart *p in self.parts) {
        MMFinding *f = p.action.finding;
        if (tree && p.step != MMWrapUpWorktree && [self.subject holds:f.path]) continue;
        n += f.cost.diskFreed;
    }
    return n;
}

- (NSUInteger)servers {
    NSUInteger n = 0;
    for (MMWrapUpPart *p in self.parts) if (p.step == MMWrapUpServers) n++;
    return n;
}

- (NSDictionary *)json:(BOOL)dryRuns {
    NSMutableArray *parts = [NSMutableArray new];
    for (MMWrapUpPart *p in self.parts) {
        NSMutableDictionary *j = [@{@"step": MMWrapUpStepName(p.step), @"expert": p.expert ?: @"", @"title": p.title ?: @"",
                                    @"findingID": p.action.finding.findingID ?: @"", @"kind": p.action.kind ?: @""} mutableCopy];
        j[@"whyNot"] = p.whyNot ?: NSNull.null;
        if (dryRuns) j[@"dryRun"] = [p.action dryRun] ?: NSNull.null;
        [parts addObject:j];
    }
    return @{@"path": self.subject.path ?: @"", @"ready": [NSNumber numberWithBool:self.whyNot == nil], @"whyNot": self.whyNot ?: NSNull.null,
             @"freedBytes": @(self.freedBytes), @"branch": self.subject.worktree.branch ?: NSNull.null, @"parts": parts};
}
@end

static NSString *KeyString(NSValue *v) { MMProcKey k; [v getValue:&k size:sizeof k]; return MMProcKeyString(k); }

MMWrapUpPlan *MMWrapUpPlanFor(NSString *path, MMSnapshot *s) {
    MMWrapUpPlan *plan = [MMWrapUpPlan new];
    plan.subject = [MMWrapUpSubject subjectAt:path facts:s.facts snapshot:s];
    plan.parts = @[];
    if (plan.subject.whyNot) { plan.whyNot = plan.subject.whyNot; return plan; }
    NSMutableArray<MMWrapUpPart *> *all = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) {
        if (![e respondsToSelector:@selector(wrapUpParts:snapshot:)]) continue;
        for (MMWrapUpPart *p in [e wrapUpParts:plan.subject snapshot:s] ?: @[]) if ([p isKindOfClass:MMWrapUpPart.class]) [all addObject:p];
    }
    // In step order, and within a step in the order the experts gave them.
    [all sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MMWrapUpPart *a, MMWrapUpPart *b) {
        return a.step < b.step ? NSOrderedAscending : a.step > b.step ? NSOrderedDescending : NSOrderedSame;
    }];
    // A part whose processes an earlier part already ends would only fail its recheck, so it is left out.
    NSMutableSet<NSString *> *ended = [NSMutableSet new];
    NSMutableArray<NSValue *> *stopped = [NSMutableArray new];
    NSMutableArray<MMWrapUpPart *> *parts = [NSMutableArray new];
    for (MMWrapUpPart *p in all) {
        NSArray<NSValue *> *procs = p.action.finding.procs;
        if (p.step == MMWrapUpServers || p.step == MMWrapUpHelpers) {
            BOOL fresh = NO;
            for (NSValue *v in procs) if (![ended containsObject:KeyString(v)]) fresh = YES;
            if (procs.count && !fresh) continue;
            for (NSValue *v in procs) if (![ended containsObject:KeyString(v)]) { [ended addObject:KeyString(v)]; [stopped addObject:v]; }
        }
        if (p.step == MMWrapUpConfig) plan.subject.configPart = YES;
        [parts addObject:p];
    }
    plan.subject.stopped = stopped;
    plan.parts = parts;
    BOOL tree = NO;
    for (MMWrapUpPart *p in parts) if (p.step == MMWrapUpWorktree) tree = YES;
    if (!tree) { plan.whyNot = @"no expert removes its worktree"; return plan; }
    for (MMWrapUpPart *p in parts) {
        NSString *keep = MMMustKeep(p.action.finding, s.facts, nil, p.policy);
        if (!keep) continue;
        p.whyNot = keep;
        if (!plan.whyNot) plan.whyNot = [NSString stringWithFormat:@"%@: %@", p.title, keep];
    }
    return plan;
}

NSString *MMWrapUpCheck(MMWrapUpPlan *plan) {
    if (NSThread.isMainThread) return @"cannot verify on the main thread";
    if (!plan.subject) return @"there is no workstream";
    MMWrapUpSubject *was = plan.subject;
    if (was.whyNot) { plan.whyNot = was.whyNot; return was.whyNot; }
    BOOL tree = NO;
    for (MMWrapUpPart *p in plan.parts) if (p.step == MMWrapUpWorktree) tree = YES;
    if (!tree) { plan.whyNot = @"no expert removes its worktree"; return plan.whyNot; }
    MMFacts *facts = [MMGraph.shared freshFactsFor:[was finding]];
    if (!facts) { plan.whyNot = @"cannot verify: fresh facts could not be gathered"; return plan.whyNot; }
    MMWrapUpSubject *now = [MMWrapUpSubject subjectAt:was.given facts:facts snapshot:nil];
    if (now.whyNot) { plan.whyNot = now.whyNot; return plan.whyNot; }
    plan.whyNot = nil;
    for (MMWrapUpPart *p in plan.parts) {
        NSString *why = [p.action recheck];
        if (why.length) why = [@"cannot run now: " stringByAppendingString:why];
        else {
            MMFacts *fresh = [MMGraph.shared freshFactsFor:p.action.finding];
            NSString *keep = MMMustKeep(p.action.finding, fresh, nil, p.policy);
            if (keep) why = [@"kept: " stringByAppendingString:keep];
        }
        p.whyNot = why;
        if (why && !plan.whyNot) plan.whyNot = [NSString stringWithFormat:@"%@: %@", p.title, why];
    }
    return plan.whyNot;
}

MMUndoRecord *MMRunWrapUp(MMWrapUpPlan *plan, NSString *by, NSString **error) {
    if (NSThread.isMainThread) { if (error) *error = @"an action never runs on the main thread"; return nil; }
    NSString *problem = MMWrapUpCheck(plan);
    if (problem) { if (error) *error = problem; return nil; }
    MMWrapUpSubject *x = plan.subject;
    NSString *name = x.path.lastPathComponent;
    NSMutableArray *list = [NSMutableArray new];
    for (NSUInteger i = 0; i < plan.parts.count; i++) {
        MMWrapUpPart *p = plan.parts[i];
        [list addObject:@{@"part": @(i), @"step": MMWrapUpStepName(p.step), @"expert": p.expert ?: @"", @"title": p.title ?: @"",
                          @"findingID": p.action.finding.findingID ?: @""}];
    }
    MMUndo *u = MMUndo.shared;
    MMUndoRecord *parent = [u begin:@"core" kind:@"wrapup" finding:[@"core:workstream:" stringByAppendingString:x.path]
                            subject:[@"Wrap Up " stringByAppendingString:name] why:@"the agent finished and the branch is merged"
                                 by:by ?: @"manual" parent:nil payload:@{@"path": x.path, @"branch": x.worktree.branch ?: @"", @"parts": list}];
    NSString *why = [@"part of Wrap Up " stringByAppendingString:name];
    NSMutableArray *done = [NSMutableArray new];
    int64_t freed = 0;
    for (NSUInteger i = 0; i < plan.parts.count; i++) {
        MMWrapUpPart *p = plan.parts[i];
        NSString *err = nil;
        MMUndoRecord *r = MMRunActionPart(p.action, p.policy, by ?: @"manual", why, parent.rid, (NSInteger)i, &err);
        if (r) { [done addObject:r.rid]; freed += MAX(r.freedBytes, 0); }
        if (r && r.state == MMUndoDone) continue;
        NSString *what = err ?: r.error ?: @"it failed";
        NSMutableArray *notRun = [NSMutableArray new];
        for (NSUInteger j = i + 1; j < plan.parts.count; j++) [notRun addObject:plan.parts[j].title ?: @""];
        NSMutableDictionary *failed = [@{@"part": @(i), @"step": MMWrapUpStepName(p.step), @"title": p.title ?: @"", @"error": what} mutableCopy];
        if (r.rid) failed[@"rid"] = r.rid;
        [u note:parent payload:@{@"done": done, @"failedPart": failed, @"notRun": notRun}];
        NSString *msg = [NSString stringWithFormat:@"stopped at part %lu of %lu, %@: %@%@", (unsigned long)i + 1, (unsigned long)plan.parts.count,
                         p.title, what, notRun.count ? [NSString stringWithFormat:@". %lu part%@ did not run", (unsigned long)notRun.count, notRun.count == 1 ? @"" : @"s"] : @""];
        [u finish:parent ok:NO freed:freed error:msg];
        if (error) *error = msg;
        return [u record:parent.rid] ?: parent;
    }
    [u note:parent payload:@{@"done": done}];
    [u finish:parent ok:YES freed:freed error:nil];
    return [u record:parent.rid] ?: parent;
}
