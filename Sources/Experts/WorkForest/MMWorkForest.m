// WorkForest on the shared core. See MMWorkForest.h.
// Ported from WorkForest 0.1: WFMustKeep, WFPlan and WFCandidates in Forest.m, the review facts and prompts in Review.m,
// WFRemove and WFRestore, and the app's watchEvents, decide and notify in main.m. The modes, the judge, the undo record
// and the git facts are Core's now, so this file only says what WorkForest knows.
#import <AppKit/AppKit.h>
#import "Experts/WorkForest/MMWorkForest.h"
#import "Core/Know/MMTreeDisk.h"
#import "Core/Act/MMWorktreeAct.h"
#import "UI/MMFormat.h"
#include <stdlib.h>

static NSString *const kExpert = @"workforest";
static const NSTimeInterval kEventGap = 30 * 60;   // reviews woken by events are at least this far apart

_Thread_local BOOL MMWFReadNow = NO;

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }

static dispatch_queue_t ActQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = MMQueue(kExpert, @"act", QOS_CLASS_UTILITY); });
    return q;
}

/// The path as the kernel and git name it: /private/var, not /var. A path that does not exist stays as given.
static NSString *Real(NSString *path) {
    if (!path.length) return path;
    char buf[PATH_MAX];
    return realpath(path.fileSystemRepresentation, buf) ? @(buf) : path.stringByStandardizingPath;
}

static BOOL Within(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

MMRules *MMWFRules(void) {
    static MMRules *r; static dispatch_once_t once;
    dispatch_once(&once, ^{ r = [MMRules rulesFor:kExpert defaults:@{
        @"protect": @[],
        // Long-lived branches. A worktree on one of these is a checkout someone keeps on purpose.
        @"protect.branches": @[@"main", @"master", @"develop", @"development", @"dev", @"staging", @"production", @"prod", @"release", @"trunk"],
    }]; });
    return r;
}

#pragma mark - Trees from facts

static NSString *MakerWord(MMWorktreeMaker m) {
    switch (m) {
        case MMMakerClaudeCode: return @"claude-code";
        case MMMakerCursor: return @"cursor";
        case MMMakerConductor: return @"conductor";
        default: return @"person";
    }
}

static NSString *MergedWord(MMMergeKind k) {
    switch (k) {
        case MMMergedAncestor: return @"ancestor";
        case MMMergedTree: return @"tree";
        case MMMergedPatch: return @"patch";
        case MMMergedSquash: return @"squash";
        case MMMergedPR: return @"pr";
        case MMMergedMergeTree: return @"merge-tree";
        default: return nil;
    }
}

/// Process names with a working directory inside each tree, by tree path, deepest tree first. Reads the shared sample.
static NSDictionary<NSString *, NSArray<NSString *> *> *ProcessesIn(NSArray<NSString *> *paths, MMSample *s) {
    if (!paths.count || !s) return @{};
    NSArray *sorted = [paths sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length > b.length ? NSOrderedAscending : a.length < b.length ? NSOrderedDescending : [a compare:b];
    }];
    NSMutableDictionary *out = [NSMutableDictionary new];
    uid_t me = getuid(); pid_t self = getpid();
    for (NSNumber *n in s.procs) {
        MMProc *p = s.procs[n];
        if (p.pid <= 1 || p.pid == self || p.uid != me || p.ppid == self) continue;
        if ([p.name isEqualToString:@"git"]) continue;   // short git commands, ours and the person's
        NSString *cwd = [s cwdOf:p.pid];
        if (cwd.length < 2) continue;
        for (NSString *t in sorted) {
            if (!Within(cwd, t)) continue;
            NSMutableArray *l = out[t] ?: (out[t] = [NSMutableArray new]);
            if (![l containsObject:p.name ?: @"?"]) [l addObject:p.name ?: @"?"];
            break;
        }
    }
    return out;
}

/// The newest session that ran inside each tree, deepest tree first.
static NSDictionary<NSString *, MMSession *> *SessionsIn(NSArray<NSString *> *paths, NSArray<MMSession *> *sessions) {
    NSArray *sorted = [paths sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length > b.length ? NSOrderedAscending : a.length < b.length ? NSOrderedDescending : [a compare:b];
    }];
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (MMSession *x in sessions) {
        NSString *cwd = Real(x.cwd);
        for (NSString *t in sorted) {
            if (!Within(cwd, t)) continue;
            MMSession *old = out[t];
            if (!old || [x.lastActive compare:old.lastActive] == NSOrderedDescending) out[t] = x;
            break;
        }
    }
    return out;
}

static NSDictionary *SessionJSON(MMSession *s) {
    if (!s) return nil;
    NSMutableDictionary *j = [@{@"agent": MMWFAgentName(s.agent), @"harness": s.agent ?: @"", @"live": @(s.stillWorking)} mutableCopy];
    if (s.title.length) j[@"title"] = MMClip(s.title, 120);
    if (s.sessionID.length) j[@"id"] = s.sessionID;
    if (s.lastActive) j[@"lastActiveAt"] = @(s.lastActive.timeIntervalSince1970);
    if (s.started) j[@"startedAt"] = @(s.started.timeIntervalSince1970);
    return j;
}

static MMWFTree *TreeFrom(MMWorktree *w, MMFacts *facts, NSArray *procs, MMSession *session, MMTreeDiskRead read, NSArray *protectedBranches) {
    MMWFTree *t = [MMWFTree new];
    t.path = Real(w.path); t.repo = Real(w.repo ?: w.path); t.branch = w.branch;
    t.findingID = [NSString stringWithFormat:@"%@:worktree:%@", kExpert, t.path];
    t.isMain = w.isMain || [t.path isEqualToString:t.repo];
    t.locked = w.locked;
    t.missing = w.missing || ![NSFileManager.defaultManager fileExistsAtPath:t.path];
    t.maker = MakerWord(w.maker); t.makerSession = w.makerSession;
    MMGitFacts *g = [facts gitFor:w];
    if (g) {
        t.gitKnown = YES;
        t.head = g.head; t.defaultBranch = g.defaultBranch;
        t.upstream = g.upstreamGone ? @"gone" : g.upstream.length ? g.upstream : @"none";
        t.merged = t.isMain ? nil : MergedWord(g.merged);
        t.dirty = g.dirty; t.untracked = g.untracked; t.stashes = g.stashes; t.unpushed = g.unpushed;
        t.notInDefault = g.notInDefault; t.onRemote = g.onRemote; t.lastCommit = g.lastCommit;
    }
    MMTreeDiskFacts *d = t.missing ? nil : [MMTreeDisk.shared factsFor:t.path read:read];
    if (d) {
        t.sized = YES;
        t.diskBytes = d.allocated; t.freedBytes = d.freed; t.cacheBytes = d.cacheBytes; t.files = d.files;
        t.touched = d.touched; t.created = d.created;
    }
    t.processes = procs ?: @[];
    t.session = SessionJSON(session);
    t.isProtected = !t.isMain && t.branch.length && [protectedBranches containsObject:t.branch];
    return t;
}

/// Every tree in these facts. read says how fresh the disk facts must be.
static NSArray<MMWFTree *> *TreesFrom(MMFacts *facts, MMTreeDiskRead read, NSString *only) {
    NSMutableArray *ws = [NSMutableArray new], *paths = [NSMutableArray new];
    for (MMWorktree *w in facts.worktrees) {
        if (!w.path.length) continue;
        NSString *p = Real(w.path);
        if (only && ![p isEqualToString:only]) continue;
        if ([paths containsObject:p]) continue;
        [ws addObject:w]; [paths addObject:p];
    }
    if (!ws.count) return @[];
    NSDictionary *procs = ProcessesIn(paths, facts.sample);
    NSDictionary *sessions = SessionsIn(paths, facts.sessions);
    NSArray *branches = [MMWFRules() entries:@"protect.branches"] ?: @[];
    NSMutableArray *out = [NSMutableArray new];
    for (NSUInteger i = 0; i < ws.count; i++)
        [out addObject:TreeFrom(ws[i], facts, procs[paths[i]], sessions[paths[i]], read, branches)];
    return out;
}

MMWFTree *MMWFTreeOf(MMFinding *f) { return [MMWFTree fromJSON:f.facts]; }

static NSString *Bucket(NSTimeInterval age) {
    return age < 3600 ? @"h" : age < 86400 ? @"d" : age < 7 * 86400 ? @"w" : age < 30 * 86400 ? @"m" : @"q";
}

/// What must change for the model to look again: HEAD, the git state, what runs inside, the session, and how quiet it is.
static NSString *Fingerprint(MMWFTree *t) {
    NSDate *s = [t.session[@"lastActiveAt"] isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[t.session[@"lastActiveAt"] doubleValue]] : nil;
    return [NSString stringWithFormat:@"%@|%@|%@|d%ld|u%ld|p%ld|r%d|x%d|s%@|q%@|k%d|l%d", t.head ?: @"-", t.merged ?: @"-", t.upstream ?: @"-",
            (long)t.dirty, (long)t.untracked, (long)t.unpushed, t.onRemote, t.processes.count > 0, s ? Bucket(-s.timeIntervalSinceNow) : @"-",
            t.lastWork ? Bucket(t.quiet) : @"-", t.isProtected, t.locked];
}

static MMFinding *FindingFor(MMWFTree *t) {
    return [MMFinding expert:kExpert kind:@"worktree" stableKey:t.path build:^(MMFindingBuilder *b) {
        b.instanceKey = t.head.length ? t.head : t.path;
        b.title = t.isMain ? t.repoName : [NSString stringWithFormat:@"%@/%@", t.repoName, t.name];
        b.path = t.path;
        b.cost = (MMCost){ .cpuPercent = -1, .diskFreed = t.freedBytes, .diskAllocated = t.diskBytes };
        b.evidence = @[[MMEvidence label:@"Git" value:MMWFStateWords(t) raw:t.merged],
                       [MMEvidence label:@"Last work" value:t.lastWork ? [MMDuration(t.quiet) stringByAppendingString:@" ago"] : @"" raw:t.lastWork]];
        // Decision 7: commits on no remote need a git bundle, which only Eager may take on its own.
        if (!t.isMain && !t.missing)
            b.proposal = [MMProposal verb:@"remove" title:@"Remove Worktree"
                            reversibility:t.gitKnown && !t.onRemote ? MMReversibleBundle : MMReversibleRestart];
        NSString *keep = t.isMain ? nil : MMWFWorkKeeps(t);
        if (keep) b.keepReasons = @[keep];
        b.facts = t.json;
        b.fingerprint = Fingerprint(t);
    }];
}

#pragma mark - Policies

/// The tree a finding names, read again from these facts, with its disk walked now. nil when it is gone.
static MMWFTree *FreshTree(MMFinding *f, MMFacts *facts) {
    MMWFTree *t = TreesFrom(facts, NSThread.isMainThread ? MMTreeDiskCached : MMTreeDiskNow, Real(f.path)).firstObject;
    if (t || !f.path.length) return t;
    // The index has not listed it yet, as for a worktree restored a moment ago: Know reads its .git files.
    MMWorktree *w = [MMRepoIndex.shared worktreeAt:f.path];
    if (!w || ![Real(w.path) isEqualToString:Real(f.path)]) return nil;
    return TreeFrom(w, facts, ProcessesIn(@[Real(w.path)], facts.sample)[Real(w.path)], SessionsIn(@[Real(w.path)], facts.sessions)[Real(w.path)],
                    NSThread.isMainThread ? MMTreeDiskCached : MMTreeDiskNow, [MMWFRules() entries:@"protect.branches"] ?: @[]);
}

/// The facts the last build read. A plan on the snapshot's own facts reads each finding's tree, with no new walk.
static __weak MMFacts *gBuiltFacts;

static MMWFTree *TreeFor(MMFinding *f, MMFacts *facts) {
    // Main never reads disk or processes. The menu plans on the facts each finding was built from,
    // and MMRunAction checks fresh off main before anything is removed.
    if (NSThread.isMainThread || (facts && facts == gBuiltFacts)) return MMWFTreeOf(f);
    return FreshTree(f, facts);
}

@interface MMWFKeeps : NSObject <MMExpertPolicy>
@property BOOL manual;
@end

@implementation MMWFKeeps

/// Why a worktree stays whatever the mode. Ported from WFWorkKeeps in WorkForest 0.1's Forest.m.
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    MMWFTree *t = TreeFor(f, facts);
    if (!t) return @"cannot verify: the worktree is gone or moved since it was listed";
    MMWFTree *was = MMWFTreeOf(f);
    if (was.head.length && t.head.length && ![was.head isEqualToString:t.head]) return @"cannot verify: its HEAD moved since it was listed";
    return MMWFWorkKeeps(t);
}

- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r {
    if (self.manual) return nil;
    MMWFTree *t = MMWFTreeOf(f);
    if (t.lastWork && r.at && [t.lastWork compare:r.at] == NSOrderedDescending) return @"worked on after the last review";
    return nil;
}

- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r {
    MMVerdict *v = r.verdicts[f.findingID];
    if (v.kind == MMVerdictKeep && v.keepEvidence.length) return [@"evidence: " stringByAppendingString:v.keepEvidence];
    if (m != MMModeProactive) return nil;
    MMWFTree *t = MMWFTreeOf(f);
    if (!t.done) return @"not merged and the remote branch still exists";
    if (t.quiet < MMWFProactiveQuiet())
        return [NSString stringWithFormat:@"quiet %@, and Proactive waits %@", MMDuration(t.quiet), MMDuration(MMWFProactiveQuiet())];
    return nil;
}
@end

id<MMExpertPolicy> MMWFModePolicy(void) {
    static MMWFKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMWFKeeps new]; });
    return p;
}

id<MMExpertPolicy> MMWFManualPolicy(void) {
    static MMWFKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMWFKeeps new]; p.manual = YES; });
    return p;
}

#pragma mark - Removing

@interface MMWFRemove : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end

@implementation MMWFRemove

- (NSString *)kind { return @"remove"; }

- (NSString *)recheck {
    MMWFTree *t = MMWFTreeOf(self.finding);
    if (t.isMain) return @"a main checkout is never removed";
    if (![NSFileManager.defaultManager fileExistsAtPath:[t.path stringByAppendingPathComponent:@".git"]]) return @"it is already gone";
    return nil;
}

- (NSString *)dryRun {
    MMWFTree *t = MMWFTreeOf(self.finding);
    NSMutableArray *steps = [NSMutableArray new];
    if (!t.onRemote) [steps addObject:@"take a git bundle of the commits on no remote"];
    [steps addObject:@"save its ignored files except caches"];
    [steps addObject:@"run git worktree remove with no --force"];
    [steps addObject:t.merged.length && t.branch.length ? [NSString stringWithFormat:@"delete the merged branch %@ with git branch -d", t.branch]
                                                         : [NSString stringWithFormat:@"keep the branch %@", t.branch ?: @"(detached)"]];
    return [NSString stringWithFormat:@"would remove %@: %@. Restore recreates it at %@.", t.path.stringByAbbreviatingWithTildeInPath,
            [steps componentsJoinedByString:@", "], t.head.length >= 8 ? [t.head substringToIndex:8] : @"its commit"];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMWFTree *t = MMWFTreeOf(self.finding);
    MMUndo *u = MMUndo.shared;
    NSDictionary *where = @{@"repo": t.repo ?: @"", @"worktree": t.path ?: @"", @"head": t.head ?: @"", @"branch": t.branch ?: @""};
    [u note:record payload:@{@"removed": @{@"path": t.path ?: @"", @"repo": t.repo ?: @"", @"branch": t.branch ?: @"", @"head": t.head ?: @"",
                                           @"merged": t.merged ?: @"", @"diskBytes": @(t.diskBytes), @"freedBytes": @(t.freedBytes)}}];
    // Decision 7 and PLAN.md Act: a git bundle whenever commits exist on no remote. No bundle, no removal.
    NSString *bundleError = nil;
    NSString *bundle = !t.onRemote ? [u bundle:t.path record:record error:&bundleError] : nil;
    if (!t.onRemote && !bundle && ![bundleError hasPrefix:@"every commit is on a remote"]) {
        if (error) *error = [@"no git bundle, so it stays: " stringByAppendingString:bundleError ?: @"the bundle failed"];
        return NO;
    }
    if (!bundle) [u note:record payload:@{@"worktree": where}];
    NSArray *files = MMWorktreeIgnoredFiles(t.path, MMTreeDisk.shared.cacheNames);
    if (!files) {
        if (error) *error = @"git could not list its ignored files, so it stays";
        return NO;
    }
    NSString *err = nil;
    if (files.count && ![u recover:files from:t.path record:record error:&err]) {
        if (error) *error = [@"its ignored files could not be saved: " stringByAppendingString:err ?: @""];
        return NO;
    }
    BOOL deleted = NO;
    if (!MMWorktreeRemove(t.repo, t.path, t.branch, t.merged.length > 0, &deleted, &err)) {
        if (error) *error = err;
        return NO;
    }
    [u note:record payload:@{@"branchDeleted": @(deleted)}];
    return YES;
}
@end

id<MMAction> MMWFRemoveAction(MMFinding *f) {
    MMWFRemove *a = [MMWFRemove new];
    a.finding = f;
    return a;
}

#pragma mark - Review

MMReview *MMWFLastReview(void) { return [MMReview lastFor:kExpert]; }

NSArray<MMFinding *> *MMWFReviewable(NSArray<MMFinding *> *findings) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in findings) {
        MMWFTree *t = MMWFTreeOf(f);
        if (t && !t.isMain && !t.missing) [out addObject:f];
    }
    return out;
}

NSArray<MMFinding *> *MMWFCandidates(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r) {
    NSMutableArray *c = [NSMutableArray new];
    if (!r || r.error.length) return c;
    for (MMFinding *f in MMWFReviewable(findings)) {
        MMVerdict *v = r.verdicts[f.findingID];
        if (v.kind != MMVerdictGo || v.confidence < MMMinConfidence || v.keepEvidence.length) continue;
        if (MMMustKeep(f, facts, r, MMWFModePolicy())) continue;
        [c addObject:f];
    }
    return c;
}

static NSString *const kSystem =
    @"You review the git worktrees on a developer's Mac and decide which ones are still wanted. The developer runs many coding agents "
    @"at once, each in its own worktree, so worktrees pile up after the agent finishes and the branch is merged or abandoned.\n\n"
    @"For every worktree return: id copied exactly, verdict (active, stale or unsure), confidence from 0 to 1, "
    @"about: at most 12 words saying what the worktree is, such as \"checkout flow fix for acme-web, merged 9 days ago\", "
    @"reason: one sentence naming the facts that decided it, and keep_evidence: the one concrete fact that shows the work is still wanted, "
    @"such as uncommitted files changed 2 hours ago, a session active 3 hours ago, or a server running in it. Leave it empty when there is none. "
    @"That it exists, an unmerged branch nobody touched for weeks, or a recent fetch is not evidence.\n\n"
    @"Facts: merged says how the branch reached default_branch: ancestor (its commits are in it), tree (same files), "
    @"patch (rebased or cherry-picked), squash (one squash commit has its whole change), pr (a merged pull request), "
    @"merge-tree (it merges with no change). upstream gone means the remote branch was deleted, usually after a merge. "
    @"unpushed_commits are on no remote and not in the default branch. on_remote says whether HEAD is on some remote. "
    @"newest_file_days_ago is the newest file outside .git and caches; quiet_days is the time since the last commit, file change or agent activity. "
    @"processes and servers run inside the worktree right now. agent_session is the latest agent session that ran in it; "
    @"when it is missing, none was found, and you must not invent one.\n\n"
    @"Evidence, strongest first:\n"
    @"- uncommitted or untracked files, a process or server inside, or an agent session active in the last day: active.\n"
    @"- merged (any kind) or upstream gone, and quiet for days: stale.\n"
    @"- not merged, unpushed commits, quiet for weeks: unsure, unless the session says the work was dropped.\n"
    @"- several worktrees for the same repo and task: the quiet ones are likely stale.\n"
    @"Say stale only when you would bet the developer will not miss it. Removing a worktree keeps its branch unless it is merged, "
    @"and MinMacs can recreate it, but untracked work in it would be lost. Return exactly one entry for every id.\n\n"
    @"summary: two or three plain sentences: which worktrees are merged or abandoned, which repos hold the most of them, "
    @"and which you would remove. MinMacs writes the totals itself, so do not count worktrees, repos or disk.";

static NSString *const kJudge =
    @"You are the judge in WorkForest's Eager mode. Each git worktree below is quiet, has no uncommitted work, nothing running in it "
    @"and no recent agent session, and a first review was not sure enough to remove it. The burden of proof is on the worktree: "
    @"keep it only when a concrete fact shows that someone still wants it. Removal keeps the branch unless it is merged, "
    @"and MinMacs can recreate the worktree at the same commit.\n\n"
    @"Evidence that counts: work that is not merged and was committed in the last two weeks, an agent session that ran in it in the last few days, "
    @"a branch name that says the work is ongoing or parked on purpose (wip, keep, parked, draft), "
    @"or a worktree that is the only place a branch is checked out while its pull request is still open.\n"
    @"Not evidence: that it exists, that its branch has commits nobody touched for weeks, that it might be useful someday, "
    @"or caches such as node_modules.\n\n"
    @"first is the first review, for reference. Weigh the facts, not its verdict. For every worktree return: id copied exactly, "
    @"decision (active to keep it, stale to remove it), confidence from 0 to 1, evidence (the deciding fact for active, empty for stale), "
    @"and reason (one plain sentence naming the facts). Return exactly one entry for every id.";

static id DaysAgo(NSDate *d) { return d ? @(round(-d.timeIntervalSinceNow / 8640) / 10) : nil; }

/// What the review sends about one worktree, redacted by Core. docs/REVIEW.md lists each field.
/// No file contents, no .env, no first prompt, no transcript path and no environment.
static NSDictionary *ReviewFacts(MMFinding *f, NSArray<NSString *> *servers) {
    MMWFTree *t = MMWFTreeOf(f);
    NSMutableDictionary *x = [NSMutableDictionary new];
    x[@"repo"] = t.repoName; x[@"folder"] = t.name; x[@"branch"] = t.branch;
    x[@"locked"] = @(t.locked); x[@"detached"] = @(t.detached); x[@"protected"] = @(t.isProtected);
    x[@"made_by"] = [t.maker isEqualToString:@"person"] ? nil : t.maker;
    if (t.gitKnown) {
        x[@"default_branch"] = t.defaultBranch;
        x[@"dirty_files"] = @(t.dirty); x[@"untracked_files"] = @(t.untracked); x[@"stashes"] = @(t.stashes);
        x[@"unpushed_commits"] = @(t.unpushed); x[@"commits_not_in_default"] = @(t.notInDefault);
        x[@"merged"] = t.merged; x[@"upstream"] = t.upstream; x[@"on_remote"] = @(t.onRemote);
        x[@"last_commit_days_ago"] = DaysAgo(t.lastCommit);
    } else x[@"git_facts"] = @"not read yet";
    x[@"created_days_ago"] = DaysAgo(t.created); x[@"newest_file_days_ago"] = DaysAgo(t.touched); x[@"quiet_days"] = DaysAgo(t.lastWork);
    if (t.sized) { x[@"disk_mb"] = @(t.diskBytes >> 20); x[@"freed_mb"] = @(t.freedBytes >> 20); x[@"cache_mb"] = @(t.cacheBytes >> 20); x[@"files"] = @(t.files); }
    x[@"processes"] = t.processes ?: @[];
    x[@"servers"] = servers ?: @[];
    NSDictionary *s = t.session;
    if (s) {
        NSMutableDictionary *a = [NSMutableDictionary new];
        a[@"agent"] = s[@"agent"]; a[@"title"] = MMClip(Str(s[@"title"]), 200); a[@"working_now"] = s[@"live"];
        if (s[@"lastActiveAt"]) a[@"last_active_minutes_ago"] = @((long)round((NSDate.date.timeIntervalSince1970 - [s[@"lastActiveAt"] doubleValue]) / 60));
        if (s[@"startedAt"]) a[@"started_minutes_ago"] = @((long)round((NSDate.date.timeIntervalSince1970 - [s[@"startedAt"] doubleValue]) / 60));
        x[@"agent_session"] = a;
    }
    return x;
}

/// LocoHost's servers inside each worktree, as ":3000 Vite", read from the snapshot. No spawn, no locohost list.
static NSDictionary<NSString *, NSArray<NSDictionary *> *> *ServersIn(MMSnapshot *s, NSArray<MMFinding *> *trees) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSArray *hosts = [s findingsFor:@"locohost"];
    if (!hosts.count) return out;
    NSArray *sorted = [trees sortedArrayUsingComparator:^NSComparisonResult(MMFinding *a, MMFinding *b) {
        return a.path.length > b.path.length ? NSOrderedAscending : a.path.length < b.path.length ? NSOrderedDescending : NSOrderedSame;
    }];
    for (MMFinding *h in hosts) {
        NSString *cwd = Real(h.path ?: Str(h.facts[@"cwd"]));
        for (MMFinding *t in sorted) {
            if (!Within(cwd, t.path)) continue;
            NSArray *ports = List(h.facts[@"ports"]);
            NSString *value = [NSString stringWithFormat:@":%@ %@", ports.firstObject ?: @"?", Str(h.facts[@"framework"]) ?: @"server"];
            NSMutableArray *l = out[t.findingID] ?: (out[t.findingID] = [NSMutableArray new]);
            [l addObject:@{@"label": @"Server", @"value": value, @"expert": @"locohost", @"findingID": h.findingID ?: @""}];
            break;
        }
    }
    return out;
}

MMReviewRequest *MMWFReviewRequest(NSArray<MMFinding *> *findings, MMSnapshot *s, NSString *trigger, MMMode mode, NSString *model) {
    NSArray *linked = MMWFReviewable(findings);
    if (!linked.count) return nil;
    NSDictionary *servers = ServersIn(s, linked);
    MMReviewRequest *q = [MMReviewRequest new];
    q.expert = kExpert; q.trigger = trigger ?: @"manual";
    q.model = model.length ? model : MMPrefString(MMReviewModelKey, @"auto");
    q.findings = linked; q.facts = s.facts;
    q.system = kSystem; q.judgeSystem = kJudge;
    q.words = [MMVerdictWords keep:@"active" go:@"stale" unsure:@"unsure"];
    q.factsFor = ^NSDictionary *(MMFinding *f) { return ReviewFacts(f, [servers[f.findingID] valueForKey:@"value"]); };
    // Issue #34: the session and the repo facts of a workstream go once in its block.
    q.sharedKeys = @[@"agent_session", @"default_branch", @"repo"];
    q.judge = mode == MMModeEager;
    q.mode = mode;
    const char *batch = getenv("WORKFOREST_BATCH");   // tests use small batches
    if (batch && atoi(batch) > 0) q.batchSize = (NSUInteger)atoi(batch);
    return q;
}

#pragma mark - Rules

/// P47. A rule that decides a worktree with no model call.
@interface MMWFRule : NSObject <MMRule>
@property (copy) NSString *ruleID;
@property (copy) MMVerdict *(^decide)(MMWFTree *t);
@end
@implementation MMWFRule
- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts { MMWFTree *t = MMWFTreeOf(f); return t && self.decide ? self.decide(t) : nil; }
@end

static MMVerdict *Active(NSString *reason) {
    MMVerdict *v = [MMVerdict new];
    v.kind = MMVerdictKeep; v.word = @"active"; v.confidence = 1; v.reason = reason; v.keepEvidence = @"";
    return v;
}

#pragma mark - Removal records and WorkForest 0.1

NSString *MMWFLegacyHome(void) {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (env[@"WORKFOREST_HOME"].length) return env[@"WORKFOREST_HOME"];
    if (env[@"MINMACS_HOME"].length) return nil;   // a test never reads the person's WorkForest folder
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/WorkForest"];
}

/// WorkForest 0.1 wrote "you" or the mode's label as who removed it. 2.0 says manual or the mode's name.
static NSString *LegacyBy(NSString *by) {
    NSString *b = by.lowercaseString;
    return [@[@"idle", @"proactive", @"eager"] containsObject:b ?: @""] ? b : @"manual";
}

NSInteger MMWFImportLegacy(void) {
    NSString *home = MMWFLegacyHome();
    if (!home.length) return 0;
    NSData *d = [NSData dataWithContentsOfFile:[home stringByAppendingPathComponent:@"removed.json"]];
    NSArray *records = d ? List([NSJSONSerialization JSONObjectWithData:d options:0 error:nil]) : nil;
    if (!records.count) return 0;
    MMStateFile *state = [MMStateFile fileNamed:@"legacy-removed" expert:kExpert];
    __block NSInteger added = 0;
    [state update:^id(id disk) {
        NSMutableDictionary *map = [Dict(disk) mutableCopy] ?: [NSMutableDictionary new];
        for (NSDictionary *r in records.reverseObjectEnumerator) {
            NSString *lid = Str(Dict(r)[@"id"]), *path = Str(r[@"path"]), *repo = Str(r[@"repo"]);
            if (!lid.length || !path.length || !repo.length || map[lid]) continue;
            NSString *branch = Str(r[@"branch"]);
            NSMutableDictionary *payload = [NSMutableDictionary new];
            payload[@"legacyID"] = lid;
            payload[@"worktree"] = @{@"repo": repo, @"worktree": path, @"head": Str(r[@"head"]) ?: @"", @"branch": branch ?: @""};
            payload[@"removed"] = @{@"path": path, @"repo": repo, @"branch": branch ?: @"", @"head": Str(r[@"head"]) ?: @"",
                                    @"merged": Str(r[@"merged"]) ?: @"", @"diskBytes": r[@"diskBytes"] ?: @0, @"at": r[@"at"] ?: @0};
            payload[@"branchDeleted"] = r[@"branchDeleted"] ?: @NO;
            NSArray *saved = List(r[@"saved"]) ?: @[];
            // The saved files stay where WorkForest 0.1 put them. Restore copies them back and leaves them there.
            if (saved.count) payload[@"recovery"] = @{@"dir": [[[home stringByAppendingPathComponent:@"removed"] stringByAppendingPathComponent:lid]
                                                                 stringByAppendingPathComponent:@"files"],
                                                       @"root": path, @"saved": saved, @"skipped": List(r[@"skipped"]) ?: @[]};
            MMUndoRecord *rec = [MMUndo.shared begin:kExpert kind:@"remove" finding:[NSString stringWithFormat:@"%@:worktree:%@", kExpert, path]
                                             subject:path.stringByAbbreviatingWithTildeInPath why:Str(r[@"why"]) ?: @"removed by WorkForest 0.1"
                                                  by:LegacyBy(Str(r[@"by"])) parent:nil payload:payload];
            [MMUndo.shared finish:rec ok:YES freed:0 error:nil];
            map[lid] = rec.rid;
            added++;
        }
        return added ? map : nil;
    }];
    return added;
}

NSArray<NSDictionary *> *MMWFRemoved(NSUInteger limit) {
    NSMutableArray *out = [NSMutableArray new];
    // The menu asks for six on main, so the log is read with a bound, as LocoHost reads it.
    for (MMUndoRecord *r in [MMUndo.shared recent:kExpert limit:limit ? MAX(limit * 4, (NSUInteger)20) : 0]) {
        if (![r.kind isEqualToString:@"remove"] || r.state == MMUndoPending) continue;
        NSDictionary *p = r.payload, *rm = Dict(p[@"removed"]);
        NSString *path = Str(rm[@"path"]) ?: Str(Dict(p[@"worktree"])[@"worktree"]) ?: Str(Dict(p[@"bundle"])[@"worktree"]);
        NSDictionary *rec = Dict(p[@"recovery"]);
        static NSString *const states[] = {@"pending", @"done", @"failed", @"restored"};
        double at = [rm[@"at"] doubleValue] > 0 ? [rm[@"at"] doubleValue] : r.at.timeIntervalSince1970;
        NSMutableDictionary *j = [@{@"rid": r.rid ?: @"", @"id": r.rid ?: @"", @"path": path ?: @"", @"branch": Str(rm[@"branch"]) ?: NSNull.null,
                                    @"at": @(at), @"by": r.by ?: @"manual", @"why": r.why ?: @"", @"saved": List(rec[@"saved"]) ?: @[],
                                    @"skipped": List(rec[@"skipped"]) ?: @[], @"state": states[r.state], @"branchDeleted": p[@"branchDeleted"] ?: @NO,
                                    @"bundle": p[@"bundle"] ? @YES : @NO, @"error": r.error ?: NSNull.null,
                                    @"taken": @(path.length && [NSFileManager.defaultManager fileExistsAtPath:path])} mutableCopy];
        if (Str(p[@"legacyID"])) j[@"legacyID"] = p[@"legacyID"];
        [out addObject:j];
        if (limit && out.count >= limit) break;
    }
    return out;
}

NSString *MMWFRecordFor(NSString *key, NSString *cwd) {
    if (!key.length) return nil;
    NSString *path = key.isAbsolutePath ? key : [cwd ?: NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:key];
    path = path.stringByStandardizingPath;
    // A path that is gone resolves through its nearest existing parent, as /var resolves to /private/var.
    NSString *real = Real(path);
    if ([real isEqualToString:path.stringByStandardizingPath] && ![NSFileManager.defaultManager fileExistsAtPath:path])
        real = [Real(path.stringByDeletingLastPathComponent) stringByAppendingPathComponent:path.lastPathComponent];
    for (NSDictionary *r in MMWFRemoved(0)) {
        if ([r[@"rid"] isEqualToString:key] || [r[@"legacyID"] isEqual:key]) return r[@"rid"];
    }
    for (NSDictionary *r in MMWFRemoved(0)) {
        if (![r[@"state"] isEqualToString:@"done"]) continue;
        if ([r[@"path"] isEqualToString:real] || [r[@"path"] isEqualToString:path]) return r[@"rid"];
    }
    return nil;
}

#pragma mark - The expert

static NSDictionary *VerdictJSON(MMVerdict *v) {
    static NSString *const kinds[] = {@"unsure", @"keep", @"go"};
    return @{@"word": v.word ?: @"unsure", @"kind": kinds[v.kind], @"confidence": @(v.confidence), @"about": v.about ?: @"",
             @"reason": v.reason ?: @"", @"judged": @(v.judged), @"decidedBy": v.decidedBy ?: @"", @"keepEvidence": v.keepEvidence ?: @""};
}

static NSString *ModelWords(MMReview *r) {
    NSString *m = nil;
    for (MMUsage *u in r.calls) if (u.model.length) m = u.model;
    if (!m.length) return nil;
    if ([m hasPrefix:@"gpt-"]) return [@"GPT" stringByAppendingString:[m substringFromIndex:3].capitalizedString];
    return MMCapitalized(m);
}

@implementation MMWorkForestExpert {
    MMWFView *_view;                          // main only, for the snapshot in _viewGen
    uint64_t _viewGen;
    MMReview *_review;                        // graph queue: the newest review seen in the log
    NSDate *_reviewRead;
    BOOL _hooked, _reviewing, _learned, _removing;
    NSMutableDictionary<NSString *, NSNumber *> *_known;   // main: findingID to the quiet marks it has passed
    NSString *_pending;                       // main: what should wake the next review
    NSDate *_lastEvent, *_actedOn;
}

+ (instancetype)shared {
    static MMWorkForestExpert *e; static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMWorkForestExpert new]; });
    return e;
}

- (NSString *)expertID { return kExpert; }
- (NSString *)name { return @"WorkForest"; }
- (NSString *)symbol { return @"tree"; }
- (NSString *)legacyName { return @"workforest"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"active" go:@"stale" unsure:@"unsure"]; }

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSArray<MMWFTree *> *trees = TreesFrom(facts, MMWFReadNow ? MMTreeDiskFresh : MMTreeDiskCached, nil);
    NSMutableArray *out = [NSMutableArray new];
    for (MMWFTree *t in trees) [out addObject:FindingFor(t)];
    gBuiltFacts = facts;
    if (!MMWFReadNow) {
        [self syncReview];
        if (trees.count) [MMTreeDisk.shared forget:[NSSet setWithArray:[trees valueForKey:@"path"]]];
        if (!_hooked) { _hooked = YES; dispatch_async(dispatch_get_main_queue(), ^{ [self hook]; }); }
    }
    return out;
}

/// The broker saves each review to the log. The graph carries the newest one, so menus read it without a query.
/// Runs on the graph queue, at most once a minute.
- (void)syncReview {
    if (_reviewRead && -_reviewRead.timeIntervalSinceNow < 60) return;
    _reviewRead = NSDate.date;
    MMReview *r = MMWFLastReview();
    if (r.at && (!_review || ![r.at isEqualToDate:_review.at])) {
        _review = r;
        [MMGraph.shared saveReview:r forExpert:kExpert];
    }
}

- (id<MMExpertPolicy>)policy { return MMWFModePolicy(); }

- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return f.proposal ? MMWFRemoveAction(f) : nil; }

- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return ReviewFacts(f, nil); }

- (NSArray<id<MMRule>> *)rules {
    MMWFRule *work = [MMWFRule new];
    work.ruleID = @"workforest.holds-work";
    work.decide = ^MMVerdict *(MMWFTree *t) {
        if (!t.gitKnown) return nil;
        if (t.dirty > 0 || t.untracked > 0) return Active(@"It holds changes that are not committed.");
        if (t.unpushed > 0 && !t.merged.length) return Active(@"It holds commits that are on no remote.");
        if (t.processes.count) return Active([NSString stringWithFormat:@"%@ runs inside it.", t.processes.firstObject]);
        if ([t.session[@"live"] boolValue]) return Active(@"An agent session is working in it.");
        return nil;
    };
    MMWFRule *held = [MMWFRule new];
    held.ruleID = @"workforest.locked-or-protected";
    held.decide = ^MMVerdict *(MMWFTree *t) {
        if (t.locked) return Active(@"It is locked with git worktree lock.");
        if (t.isProtected) return Active(@"Its branch is a protected one.");
        return nil;
    };
    return @[work, held];
}

- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s {
    return MMWFReviewRequest([s findingsFor:kExpert], s, trigger, MMModeFor(kExpert), nil);
}

- (NSArray<MMWFTree *> *)treesIn:(MMSnapshot *)s {
    NSMutableArray *trees = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) { MMWFTree *t = MMWFTreeOf(f); if (t) [trees addObject:t]; }
    return trees;
}

/// The menu's view, made on the graph queue once per snapshot: MMPlan, the keeps, the rules and Recently Removed
/// from the undo log, so main reads none of them. The review is the one the snapshot carries.
- (id)prepareFor:(MMSnapshot *)s { return [self makeView:s review:[s reviewFor:kExpert]]; }

/// On main, what the graph queue prepared. A snapshot made by hand, as in a test, has none, and then main builds it.
/// Any other queue, such as the CLI's, builds it and reads the log for the review.
- (MMWFView *)viewFor:(MMSnapshot *)s {
    if (NSThread.isMainThread) {
        MMWFView *p = [s preparedFor:kExpert];
        if ([p isKindOfClass:MMWFView.class]) { p.reviewing = _reviewing; return p; }
        if (_view && _viewGen == s.generation && s.generation) return _view;
        MMWFView *v = [self makeView:s review:[s reviewFor:kExpert]];
        _view = v; _viewGen = s.generation;
        return v;
    }
    return [self makeView:s review:[s reviewFor:kExpert] ?: MMWFLastReview()];
}

- (MMWFView *)makeView:(MMSnapshot *)s review:(MMReview *)r {
    MMWFView *v = [MMWFView new];
    NSArray<MMFinding *> *findings = [s findingsFor:kExpert];
    v.trees = [self treesIn:s];
    MMMode mode = MMModeFor(kExpert);
    v.mode = MMModeName(mode);
    v.reviewAt = r.at; v.reviewError = r.error; v.summaryWords = r.summaryWords; v.model = ModelWords(r);
    v.reviewing = _reviewing;
    NSMutableDictionary *verdicts = [NSMutableDictionary new];
    for (NSString *k in r.verdicts) verdicts[k] = VerdictJSON(r.verdicts[k]);
    v.verdicts = verdicts;
    NSMutableDictionary *plan = [NSMutableDictionary new];
    for (MMPlanEntry *e in MMPlan(MMWFReviewable(findings), s.facts, r, mode, MMWFModePolicy()))
        plan[e.finding.findingID] = @{@"remove": @(e.act), @"why": e.why ?: @""};
    v.plan = plan;
    v.candidates = [MMWFCandidates(findings, s.facts, r) valueForKey:@"findingID"];
    NSMutableDictionary *kept = [NSMutableDictionary new];
    for (MMFinding *f in findings) { NSDate *d = [MMKeep keptUntil:f.stableKey expert:kExpert]; if (d) kept[f.findingID] = d; }
    v.keptUntil = kept;
    NSMutableSet *protectedPaths = [NSMutableSet new];
    for (MMFinding *f in findings) if ([MMKeep isProtected:f.stableKey expert:kExpert] || [MMKeep isProtected:f.path expert:kExpert]) [protectedPaths addObject:f.findingID];
    v.protectedPaths = protectedPaths;
    v.links = ServersIn(s, findings);
    v.removed = MMWFRemoved(6);
    v.watchingLeft = MMWatchingLeft(kExpert);
    __weak MMWorkForestExpert *weak = self;
    v.act = ^(NSString *what, NSString *key, BOOL option) { [weak act:what key:key option:option snapshot:s]; };
    return v;
}

- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return MMWFMenu([self viewFor:s]); }

- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s {
    MMWFTree *t = MMWFTreeOf(f);
    return t ? MMWFCard(t, [self viewFor:s]) : nil;
}

- (NSString *)badgeFor:(MMSnapshot *)s { return MMWFBadge([self viewFor:s]); }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return MMWFAccessibilityState([self viewFor:s]); }

- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return MMWFReviewable([s findingsFor:kExpert]).count == 0; }

- (NSArray<MMVerbSpec *> *)verbs { return MMWFVerbs(); }

- (BOOL)openURL:(NSURL *)url {
    NSString *c = url.host.lowercaseString ?: @"";
    if ([c isEqualToString:@"review"]) { [self act:@"review" key:nil option:NO snapshot:MMGraph.shared.current]; return YES; }
    if ([c isEqualToString:@"clean-up"]) { [self act:@"clean-up" key:nil option:NO snapshot:MMGraph.shared.current]; return YES; }
    if ([c isEqualToString:@"rescan"]) { [MMRepoIndex.shared refresh:nil]; return YES; }
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

static BOOL Confirm(NSString *title, NSString *text, NSString *button) {
    NSAlert *a = [NSAlert new];
    a.messageText = title; a.informativeText = text ?: @"";
    [a addButtonWithTitle:button]; [a addButtonWithTitle:@"Cancel"];
    [NSApp activateIgnoringOtherApps:YES];
    return [a runModal] == NSAlertFirstButtonReturn;
}

/// Removes on the act queue, each one checked fresh by MMRunAction, then says what stayed.
- (void)remove:(NSArray<MMFinding *> *)fs why:(NSString *)why {
    if (_removing || !fs.count) return;
    _removing = YES;
    dispatch_async(ActQueue(), ^{
        NSMutableArray *failed = [NSMutableArray new];
        for (MMFinding *f in fs) {
            NSString *err = nil;
            MMUndoRecord *r = MMRunAction(MMWFRemoveAction(f), MMWFManualPolicy(), nil, @"manual", why, &err);
            if (!r || r.state != MMUndoDone) [failed addObject:[NSString stringWithFormat:@"%@: %@", f.title, err ?: r.error ?: @"it was not removed"]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self->_removing = NO; self->_view = nil; });
        if (failed.count) Alert([NSString stringWithFormat:@"%@ Kept", MMCapitalized(MMPlural(failed.count, @"worktree"))], [failed componentsJoinedByString:@"\n"]);
        [MMRepoIndex.shared refresh:nil];
        [MMGraph.shared rebuild:@"workforest remove"];
    });
}

/// Main thread. Anything that changes a worktree runs on the act queue, through MMRunAction or MMUndo.
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s {
    MMFinding *f = key ? [s finding:key] : nil;
    MMWFTree *t = f ? MMWFTreeOf(f) : nil;
    if ([what isEqualToString:@"review"]) {
        _reviewing = YES; _view = nil;
        [MMReviewBroker.shared wake:@"manual" expert:kExpert];
    } else if ([what isEqualToString:@"clean-up"]) {
        NSArray *c = MMWFCandidates([s findingsFor:kExpert], s.facts, [s reviewFor:kExpert]);
        if (!c.count) return;
        NSMutableString *list = [NSMutableString new];
        for (MMFinding *x in c) [list appendFormat:@"%@\n", x.title];
        [list appendString:@"\nEach is checked again first. Branches stay unless merged, ignored files such as .env are saved, "
                           @"and Recently Removed can restore each one."];
        if (Confirm([NSString stringWithFormat:@"Remove %@?", MMPlural(c.count, @"Stale Worktree")], list, @"Remove Them")) [self remove:c why:@"Clean Up"];
    } else if ([what isEqualToString:@"restore"] && key) {
        dispatch_async(ActQueue(), ^{
            NSString *problem = [MMUndo.shared restore:key];
            if (problem) Alert(@"Could Not Restore", MMSentence(problem));
            [MMRepoIndex.shared refresh:nil];
            [MMGraph.shared rebuild:@"workforest restore"];
        });
    } else if ([what isEqualToString:@"prune"]) {
        NSMutableSet *repos = [NSMutableSet new];
        for (MMWFTree *x in [self treesIn:s]) if (x.missing && x.repo) [repos addObject:x.repo];
        dispatch_async(ActQueue(), ^{
            for (NSString *r in repos) MMWorktreePrune(r, nil);
            [MMRepoIndex.shared refresh:nil];
        });
    } else if (!t) {
        return;
    } else if ([what isEqualToString:@"remove"]) {
        if (Confirm([NSString stringWithFormat:@"Remove the Worktree %@?", t.name],
                    @"It is checked again first. The branch stays unless it is merged, ignored files such as .env are saved, "
                    @"and Recently Removed can restore it.", @"Remove")) [self remove:@[f] why:@"removed from the menu"];
    } else if ([what isEqualToString:@"reveal"]) {
        [NSWorkspace.sharedWorkspace selectFile:nil inFileViewerRootedAtPath:t.path];
    } else if ([what isEqualToString:@"terminal"]) {
        NSURL *term = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
        if (term) [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:t.path]] withApplicationAtURL:term
                                         configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    } else if ([what isEqualToString:@"copy-path"]) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:t.path forType:NSPasteboardTypeString];
    } else if ([what isEqualToString:@"keep"]) {
        // The keeps and rules files are read and written on the act queue, so main never waits on disk.
        // The rebuild after it carries the change to the menu.
        NSString *stable = f.stableKey;
        dispatch_async(ActQueue(), ^{
            BOOL kept = [MMKeep keptUntil:stable expert:kExpert] != nil;
            [MMKeep keep:stable expert:kExpert until:kept ? nil : [NSDate dateWithTimeIntervalSinceNow:7 * 86400]];
            [MMGraph.shared rebuild:@"workforest keep"];
        });
        _view = nil;
    } else if ([what isEqualToString:@"protect"]) {
        NSString *path = t.path;
        dispatch_async(ActQueue(), ^{
            BOOL on = ![MMKeep isProtected:path expert:kExpert];
            [MMWFRules() set:on value:path inList:@"protect" key:nil];
            [MMGraph.shared rebuild:@"workforest protect"];
        });
        _view = nil;
    }
}

#pragma mark The app: what wakes a review, and the mode after it

/// Installs the app's watchers once, on main, after the graph built WorkForest's first findings.
- (void)hook {
    _known = [NSMutableDictionary new];
    [MMGraph.shared observe:^(MMSnapshot *s) { [self watch:s]; }];
    [NSNotificationCenter.defaultCenter addObserverForName:MMTreeDiskDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        [MMGraph.shared rebuild:@"workforest disk"];
    }];
    dispatch_async(ActQueue(), ^{ if (MMWFImportLegacy()) dispatch_async(dispatch_get_main_queue(), ^{ self->_view = nil; }); });
}

/// Ported from watchEvents and decide in WorkForest 0.1's main.m. Main thread, once per snapshot.
/// A worktree not seen before and a worktree whose quiet time passes a week, a month or three months wake a review,
/// at most every 30 minutes, and the schedule wakes one every two hours.
- (void)watch:(MMSnapshot *)s {
    NSArray<MMFinding *> *findings = MMWFReviewable([s findingsFor:kExpert]);
    MMReview *r = [s reviewFor:kExpert];
    if (_reviewing && r.at && -r.at.timeIntervalSinceNow < 60) { _reviewing = NO; _view = nil; }
    BOOL first = !_learned;
    _learned = YES;
    static const double marks[] = {7 * 86400, 30 * 86400, 90 * 86400};
    for (MMFinding *f in findings) {
        MMWFTree *t = MMWFTreeOf(f);
        NSInteger passed = 0; while (passed < 3 && t.quiet >= marks[passed]) passed++;
        if (!_known[f.findingID]) {
            _known[f.findingID] = @(passed);
            if (!first) _pending = [@"new worktree " stringByAppendingString:f.title];
            continue;
        }
        if (passed > _known[f.findingID].integerValue) {
            _known[f.findingID] = @(passed);
            _pending = [NSString stringWithFormat:@"%@ quiet %@", f.title, MMDuration(marks[passed - 1])];
        }
    }
    if (s.facts.power.diskFree > 0 && s.facts.power.diskFree < 15ull * 1000 * 1000 * 1000)
        _pending = [NSString stringWithFormat:@"low disk: %@ free", MMBytes(s.facts.power.diskFree)];
    NSInteger every = MMPrefInt(@"workforest.reviewMinutes", 120);
    if (every > 0 && findings.count && !_reviewing && !_removing) {
        if (!r || -r.at.timeIntervalSinceNow >= every * 60) [MMReviewBroker.shared wake:@"schedule" expert:kExpert];
        else if (_pending && (!_lastEvent || -_lastEvent.timeIntervalSinceNow >= kEventGap)) {
            _lastEvent = NSDate.date;
            [MMReviewBroker.shared wake:_pending expert:kExpert];
            _pending = nil;
        }
    }
    // A new review: the mode acts on fresh facts, through MMRunAction, and one notification says what it did.
    if (r.at && (!_actedOn || [r.at compare:_actedOn] == NSOrderedDescending)) {
        _actedOn = r.at;
        MMMode mode = MMModeFor(kExpert);
        if (mode == MMModeIdle || r.error.length || _removing) return;
        NSMutableArray *todo = [NSMutableArray new];
        // The plan the graph queue made for this snapshot, so main never runs MMPlan.
        MMWFView *prepared = [s preparedFor:kExpert];
        if ([prepared isKindOfClass:MMWFView.class] && [prepared.mode isEqualToString:MMModeName(mode)]) {
            for (MMFinding *f in findings) {
                NSDictionary *e = prepared.plan[f.findingID];
                if ([e[@"remove"] boolValue]) [todo addObject:@[f, e[@"why"] ?: @""]];
            }
        } else for (MMPlanEntry *e in MMPlan(findings, s.facts, r, mode, MMWFModePolicy())) if (e.act) [todo addObject:@[e.finding, e.why ?: @""]];
        if (!todo.count) return;
        _removing = YES;
        dispatch_async(ActQueue(), ^{ [self autoRemove:todo review:r mode:mode]; });
    }
}

/// Act queue. Each removal reads its worktree again first. One notification says what went.
- (void)autoRemove:(NSArray<NSArray *> *)todo review:(MMReview *)r mode:(MMMode)mode {
    uint64_t freed = 0;
    NSString *lastRid = nil;
    NSMutableArray *lines = [NSMutableArray new];
    for (NSArray *t in todo) {
        MMFinding *f = t[0];
        NSString *err = nil;
        MMUndoRecord *rec = MMRunAction(MMWFRemoveAction(f), MMWFModePolicy(), r, MMModeName(mode), t[1], &err);
        if (!rec || rec.state != MMUndoDone) continue;
        MMWFTree *tree = MMWFTreeOf(f);
        freed += rec.freedBytes > 0 ? (uint64_t)rec.freedBytes : tree.freedBytes;
        lastRid = rec.rid;
        [lines addObject:[NSString stringWithFormat:@"%@ %@", tree.repoName, tree.branch ?: tree.name]];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ self->_removing = NO; self->_view = nil; });
    if (!lines.count) return;
    NSString *title = [NSString stringWithFormat:@"Removed %@, Freed %@", MMCapitalized(MMPlural(lines.count, @"worktree")).capitalizedString, MMBytes(freed)];
    NSString *body = [NSString stringWithFormat:@"%@ removed %@. Undo recreates %@ at its commit with its saved files.",
                      MMWFModeLabel(MMModeName(mode)), [lines componentsJoinedByString:@", "], lines.count == 1 ? @"it" : @"the last one"];
    MMNotify(kExpert, title, body, lastRid);
    [MMRepoIndex.shared refresh:nil];
    [MMGraph.shared rebuild:@"workforest mode"];
}

@end
