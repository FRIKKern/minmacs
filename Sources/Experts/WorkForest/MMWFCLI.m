// WorkForest's verbs: `minmacs trees <command>`, and WorkForest 0.1's commands through the workforest name.
// Ported from RunCLI in WorkForest 0.1's main.m. Every verb prints through MMArgs, and every change runs through
// MMRunAction or MMUndo. A command that changes things needs the app, unless it is given --dry-run.
#import "Experts/WorkForest/MMWorkForest.h"
#import "CLI/MMArgs.h"
#import "Core/Know/MMTreeDisk.h"
#import "Core/Act/MMWorktreeAct.h"
#import "UI/MMFormat.h"

static NSString *const kExpert = @"workforest";

/// Card specs are main thread only, and a verb in the app runs on the socket queue. Links without Sources/CLI.
static void OnMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_sync(dispatch_get_main_queue(), block);
}

static NSString *Real(NSString *path) {
    char buf[PATH_MAX];
    return path.length && realpath(path.fileSystemRepresentation, buf) ? @(buf) : path.stringByStandardizingPath;
}

/// A path from the person: ~ expanded, relative to the folder they ran the CLI in, symlinks resolved.
static NSString *Absolute(NSString *path, MMArgs *a) {
    if (!path.length) return nil;
    path = path.stringByExpandingTildeInPath;
    if (!path.isAbsolutePath) path = [a.cwd ?: NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
    return Real(path);
}

static NSString *Pad(NSString *s, NSUInteger n) {
    s = s ?: @"";
    if (s.length > n) s = MMCut(s, n);
    return [s stringByPaddingToLength:n + 1 withString:@" " startingAtIndex:0];
}

/// The snapshot a verb reads. A snapshot built for this verb walks disk facts fresh; the app's own is used as it is.
static MMSnapshot *Snapshot(MMArgs *a) {
    if (!(a.inApp && MMGraph.shared.latest)) MMWFReadNow = YES;
    return a.snapshot;
}

static NSArray<MMFinding *> *Findings(MMSnapshot *s) { return [s findingsFor:kExpert]; }

static MMFinding *FindingAt(MMSnapshot *s, NSString *path) {
    MMFinding *best = nil;
    for (MMFinding *f in Findings(s))
        if (([path isEqualToString:f.path] || [path hasPrefix:[f.path stringByAppendingString:@"/"]]) && f.path.length > best.path.length) best = f;
    return best;
}

static NSInteger ModeArg(MMArgs *a) {
    NSString *m = [a option:@"--mode"];
    return m ? MMModeFrom(m.lowercaseString) : MMModeFor(kExpert);
}

static NSDictionary *TreeJSON(MMFinding *f, MMSnapshot *s, MMReview *r) {
    MMWFTree *t = MMWFTreeOf(f);
    NSMutableDictionary *j = [t.json mutableCopy];
    MMVerdict *v = r.verdicts[f.findingID];
    if (v) j[@"review"] = @{@"verdict": v.word ?: @"unsure", @"confidence": @(v.confidence), @"about": v.about ?: @"", @"reason": v.reason ?: @"",
                            @"keep_evidence": v.keepEvidence ?: @"", @"judged": @(v.judged), @"decidedBy": v.decidedBy ?: @"",
                            @"at": @(r.at.timeIntervalSince1970)};
    j[@"category"] = MMWFCategory(t, v.word);
    j[@"keep"] = MMMustKeep(f, s.facts, r, MMWFModePolicy()) ?: NSNull.null;
    j[@"id"] = f.findingID;
    return j;
}

static NSArray *PlanJSON(NSArray<MMPlanEntry *> *plan) {
    NSMutableArray *o = [NSMutableArray new];
    for (MMPlanEntry *p in plan) {
        MMWFTree *t = MMWFTreeOf(p.finding);
        [o addObject:@{@"path": t.path ?: @"", @"branch": t.branch ?: NSNull.null, @"remove": @(p.act), @"why": p.why ?: @"",
                       @"diskBytes": @(t.diskBytes), @"freedBytes": @(t.freedBytes), @"id": p.finding.findingID}];
    }
    return o;
}

static NSArray<MMFinding *> *Scope(MMArgs *a, MMSnapshot *s) {
    NSArray *linked = MMWFReviewable(Findings(s));
    NSString *p = [a option:@"--path"];
    if (!p) return linked;
    MMFinding *f = FindingAt(s, Absolute(p, a));
    return f && [linked containsObject:f] ? @[f] : @[];
}

static NSString *ModelOf(MMReview *r) {
    NSString *m = nil;
    for (MMUsage *u in r.calls) if (u.model.length) m = u.model;
    return m;
}

#pragma mark - Commands

static int List(MMArgs *a) {
    MMSnapshot *s = Snapshot(a);
    MMReview *r = [s reviewFor:kExpert];
    BOOL all = [a has:@"--all"];
    NSMutableArray *shown = [NSMutableArray new];
    for (MMFinding *f in Findings(s)) if (all || [MMWFReviewable(@[f]) count]) [shown addObject:f];
    NSInteger m = ModeArg(a);
    if (m < 0) { [a error:@"modes are idle, proactive and eager"]; return [a usageError]; }
    if (a.json) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMFinding *f in shown) [o addObject:TreeJSON(f, s, r)];
        [a printJSON:@{@"trees": o, @"mode": MMModeName((MMMode)m),
                       @"plan": PlanJSON(MMPlan(MMWFReviewable(Findings(s)), s.facts, r, (MMMode)m, MMWFModePolicy())),
                       @"candidates": [MMWFCandidates(Findings(s), s.facts, r) valueForKey:@"path"],
                       @"watchedLongEnough": @(MMWatchedLongEnough(kExpert)), @"inApp": @(a.inApp)}];
        return 0;
    }
    if (!shown.count) {
        [a print:@"No worktrees found under %@.", [[MMRepoIndex.shared.roots valueForKey:@"lastPathComponent"] componentsJoinedByString:@", "]];
        return 0;
    }
    [a print:@"  %@%@%@%@%@", Pad(@"worktree", 44), Pad(@"branch", 30), Pad(@"quiet", 7), Pad(@"frees", 9), @"state"];
    uint64_t freed = 0;
    NSMutableSet *repos = [NSMutableSet new];
    for (MMFinding *f in shown) {
        MMWFTree *t = MMWFTreeOf(f);
        freed += t.freedBytes;
        if (t.repo) [repos addObject:t.repo];
        NSString *cat = MMWFCategory(t, r.verdicts[f.findingID].word);
        NSString *mark = [cat isEqualToString:@"active"] ? @"●" : [cat isEqualToString:@"merged"] ? @"◆" : [cat isEqualToString:@"stale"] ? @"◇" : @"○";
        [a print:@"%@ %@%@%@%@%@", mark, Pad([NSString stringWithFormat:@"%@/%@", t.repoName, t.isMain ? @"" : t.name], 44), Pad(t.branch ?: @"(detached)", 30),
                 Pad(MMShortDuration(t.quiet), 7), Pad(t.sized ? MMBytes(t.freedBytes) : @"?", 9), MMWFStateWords(t)];
    }
    [a print:@""];
    [a print:@"%@ in %@, %@ freed if all were removed.", MMPlural(shown.count, @"worktree"), MMPlural(repos.count, @"repo"), MMBytes(freed)];
    if (r) [a print:@"Last review %@ by %@%@.", MMAgo(r.at), ModelOf(r) ?: @"the model", r.error ? [@", failed: " stringByAppendingString:r.error] : @""];
    return 0;
}

static int Explain(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    MMSnapshot *s = Snapshot(a);
    MMFinding *f = FindingAt(s, Absolute(arg, a));
    if (!f) { [a error:@"no worktree at %@", arg]; return MMExitFailed; }
    MMReview *r = [s reviewFor:kExpert];
    MMWFTree *t = MMWFTreeOf(f);
    if (a.json) {
        NSMutableDictionary *j = [TreeJSON(f, s, r) mutableCopy];
        j[@"sentToModel"] = [MMWorkForestExpert.shared reviewFactsFor:f];
        [a printJSON:j];
        return 0;
    }
    __block MMCardSpec *c;
    OnMain(^{ c = [MMWorkForestExpert.shared cardFor:f snapshot:s]; });
    [a print:@"%@  %@  %@", t.path.stringByAbbreviatingWithTildeInPath, t.branch ?: @"detached", t.isMain ? @"main checkout" : @"linked worktree"];
    [a print:@""];
    [a print:@"  %@", c.title];
    [a print:@"  %@ %@", c.statusWord, c.statusText];
    for (MMCardFact *x in c.facts) [a print:@"  %@%@", Pad(x.label, 10), x.value];
    if (c.note.length) [a print:@"  %@: %@", c.noteBy, c.note];
    MMVerdict *v = r.verdicts[f.findingID];
    if (!v) [a print:@"  Not in a review yet. Run %@ review.", [a.program isEqualToString:@"workforest"] ? @"workforest" : @"minmacs trees"];
    return 0;
}

static int Review(MMArgs *a) {
    NSInteger m = ModeArg(a);
    if (m < 0) { [a error:@"modes are idle, proactive and eager"]; return [a usageError]; }
    MMSnapshot *s = Snapshot(a);
    NSArray *scope = Scope(a, s);
    MMReviewRequest *q = MMWFReviewRequest(scope, s, @"manual", (MMMode)m, [a option:@"--model"]);
    if (!q) { [a print:@"No linked worktrees to review."]; return 0; }
    q.ignoreCache = [a has:@"--fresh"];
    if (a.dryRun) {
        NSMutableArray *facts = [NSMutableArray new];
        for (MMFinding *f in q.findings) [facts addObject:q.factsFor(f)];
        if (a.json) [a printJSON:@{@"would": @"review", @"model": q.model ?: @"auto", @"worktrees": facts}];
        else [a print:@"Would review %@ with %@.", MMPlural(q.findings.count, @"worktree"), q.model ?: @"auto"];
        return 0;
    }
    if (!a.json) [a error:@"reviewing %@ with %@…", MMPlural(q.findings.count, @"worktree"), q.model ?: @"auto"];
    MMReview *r = [MMReviewBroker.shared run:q];
    if (a.json) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMFinding *f in q.findings) [o addObject:TreeJSON(f, s, r)];
        [a printJSON:@{@"trees": o, @"model": ModelOf(r) ?: q.model ?: @"auto", @"note": r.note ?: NSNull.null, @"summary": r.summary ?: NSNull.null,
                       @"error": r.error ?: NSNull.null, @"judgeError": r.judgeError ?: NSNull.null, @"mode": MMModeName((MMMode)m)}];
        return r.error ? MMExitFailed : 0;
    }
    if (r.error) { [a error:@"The review failed: %@", r.error]; return MMExitFailed; }
    if (r.note) [a error:@"%@, so %@ answered.", r.note, ModelOf(r) ?: @"another model"];
    for (MMFinding *f in q.findings) {
        MMVerdict *v = r.verdicts[f.findingID];
        [a print:@"%@%@%3.0f%%%@  %@", Pad(f.title, 44), Pad(v.word ?: @"-", 7), v.confidence * 100, v.judged ? @" judged" : @"", v.reason ?: @"no verdict"];
    }
    if (r.summary.length) { [a print:@""]; [a print:@"%@", r.summary]; }
    return 0;
}

/// summary and auto: the mode's plan, and with auto and no --dry-run, the removals it decides.
static int Plan(MMArgs *a, BOOL act) {
    NSInteger m = ModeArg(a);
    if (m < 0) { [a error:@"modes are idle, proactive and eager"]; return [a usageError]; }
    MMMode mode = (MMMode)m;
    BOOL dry = !act || a.dryRun;
    if (!dry) {
        int needs = [a needsApp];
        if (needs) return needs;
        // A mode acts only when it is the mode set, as MMRunAction checks again right before it removes anything.
        if (mode != MMModeFor(kExpert)) {
            [a error:@"the mode is %@, so %@ does not act. Set it first with: mode workforest %@", MMModeName(MMModeFor(kExpert)), MMModeName(mode), MMModeName(mode)];
            return MMExitUsage;
        }
    }
    MMSnapshot *s = Snapshot(a);
    MMReview *r = [s reviewFor:kExpert];
    if (act && [a has:@"--review"]) {
        MMReviewRequest *q = MMWFReviewRequest(Findings(s), s, @"manual", mode, [a option:@"--model"]);
        if (q) r = [MMReviewBroker.shared run:q];
    }
    NSArray *scope = Scope(a, s);
    NSArray<MMPlanEntry *> *plan = MMPlan(scope, s.facts, r, mode, MMWFModePolicy());
    NSMutableArray *actions = [NSMutableArray new];
    int status = 0;
    if (!dry) for (MMPlanEntry *p in plan) {
        if (!p.act) continue;
        NSString *err = nil;
        MMUndoRecord *rec = MMRunAction(MMWFRemoveAction(p.finding), MMWFModePolicy(), r, MMModeName(mode), p.why, &err);
        BOOL done = rec && rec.state == MMUndoDone;
        MMWFTree *t = MMWFTreeOf(p.finding);
        [actions addObject:@{@"path": t.path ?: @"", @"branch": t.branch ?: @"", @"removed": @(done), @"id": rec.rid ?: NSNull.null,
                             @"error": err ?: rec.error ?: NSNull.null, @"why": p.why ?: @""}];
        if (!done) status = 3;
    }
    if (a.json) {
        [a printJSON:@{@"mode": MMModeName(mode), @"summary": r.summary ?: NSNull.null, @"plan": PlanJSON(plan), @"actions": actions,
                       @"reviewAt": r.at ?: NSNull.null, @"dryRun": @(dry)}];
        return status;
    }
    if (!act) { [a print:@"%@", r.summary.length ? r.summary : @"No summary yet. Run a review first."]; [a print:@""]; }
    [a print:@"%@ mode%@:", MMWFModeLabel(MMModeName(mode)), act && dry ? @", dry run" : @""];
    for (MMPlanEntry *p in plan) {
        MMWFTree *t = MMWFTreeOf(p.finding);
        [a print:@"  %@%@%@%@", Pad(p.act ? @"remove" : @"keep", 7), Pad(p.finding.title, 44), Pad(t.sized ? MMBytes(t.freedBytes) : @"?", 9), p.why ?: @""];
    }
    if (!plan.count) [a print:@"  no linked worktrees"];
    for (NSDictionary *x in actions)
        [a print:@"%@ %@%@", [x[@"removed"] boolValue] ? @"removed" : @"kept", [x[@"path"] stringByAbbreviatingWithTildeInPath],
                 [x[@"removed"] boolValue] ? [NSString stringWithFormat:@", restore with: restore %@", x[@"id"]] : [NSString stringWithFormat:@": %@", x[@"error"]]];
    return status;
}

static int Remove(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    MMSnapshot *s = Snapshot(a);
    NSString *path = Absolute(arg, a);
    MMFinding *f = FindingAt(s, path);
    if (!f || ![f.path isEqualToString:path]) { [a error:@"not removed: no linked worktree at %@", arg]; return MMExitFailed; }
    id<MMAction> action = MMWFRemoveAction(f);
    if (a.dryRun) {
        NSString *keep = MMMustKeep(f, s.facts, nil, MMWFManualPolicy());
        if (a.json) [a printJSON:@{@"path": path, @"would": [action dryRun], @"kept": keep ?: NSNull.null}];
        else [a print:@"%@", keep ? [@"kept: " stringByAppendingString:keep] : [action dryRun]];
        return keep ? MMExitFailed : 0;
    }
    if (![a has:@"--yes"]) { [a error:@"remove asks no questions on the command line. Add --yes to remove %@.", arg]; return MMExitUsage; }
    int needs = [a needsApp];
    if (needs) return needs;
    NSString *err = nil;
    MMUndoRecord *rec = MMRunAction(action, MMWFManualPolicy(), nil, @"cli", @"removed from the command line", &err);
    if (!rec || rec.state != MMUndoDone) { [a error:@"not removed: %@", err ?: rec.error ?: @"it failed"]; return MMExitFailed; }
    BOOL deleted = [rec.payload[@"branchDeleted"] boolValue];
    if (a.json) [a printJSON:@{@"id": rec.rid, @"path": path, @"branchDeleted": @(deleted), @"saved": rec.payload[@"recovery"][@"saved"] ?: @[]}];
    else [a print:@"removed %@, id %@, %@", path.stringByAbbreviatingWithTildeInPath, rec.rid, deleted ? @"merged branch deleted" : @"branch kept"];
    return 0;
}

static int Restore(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    MMWFImportLegacy();
    NSString *rid = MMWFRecordFor(arg, a.cwd);
    if (!rid) { [a error:@"restore failed: no removed worktree with that id or path"]; return MMExitFailed; }
    MMUndoRecord *rec = [MMUndo.shared record:rid];
    if (a.dryRun) {
        if (a.json) [a printJSON:@{@"rid": rid, @"subject": rec.subject ?: @"", @"canRestore": @(rec.canRestore && rec.state == MMUndoDone)}];
        else [a print:@"would restore %@", rec.subject ?: rid];
        return 0;
    }
    int needs = [a needsApp];
    if (needs) return needs;
    NSString *problem = [MMUndo.shared restore:rid];
    if (problem) { [a error:@"restore failed: %@", problem]; return MMExitFailed; }
    if (a.json) [a printJSON:@{@"rid": rid, @"restored": @YES}]; else [a print:@"restored %@", rec.subject ?: rid];
    return 0;
}

static int Removed(MMArgs *a) {
    MMWFImportLegacy();
    NSArray *all = MMWFRemoved(50);
    if (a.json) { [a printJSON:all]; return 0; }
    if (!all.count) { [a print:@"Nothing removed."]; return 0; }
    for (NSDictionary *r in all) {
        NSString *by = r[@"by"];
        [a print:@"%@%@%@%@ by %@, %@", Pad(r[@"rid"], 13), Pad([r[@"path"] stringByAbbreviatingWithTildeInPath], 44),
                 Pad([r[@"branch"] isKindOfClass:NSString.class] ? r[@"branch"] : @"detached", 26),
                 MMAgo([NSDate dateWithTimeIntervalSince1970:[r[@"at"] doubleValue]]), by, r[@"state"]];
        NSArray *saved = r[@"saved"];
        if ([r[@"why"] length] || saved.count)
            [a print:@"             %@%@", r[@"why"], saved.count ? [NSString stringWithFormat:@". Saved %@", [saved componentsJoinedByString:@", "]] : @""];
    }
    return 0;
}

static int Keep(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    NSString *path = Absolute(arg, a);
    BOOL off = [a has:@"--off"];
    NSInteger days = [a option:@"--days"] ? [a option:@"--days"].integerValue : 7;
    if (a.dryRun) {
        if (a.json) [a printJSON:@{@"path": path, @"kept": @(!off), @"days": @(off ? 0 : days), @"dryRun": @YES}];
        else [a print:off ? @"would stop keeping %@" : @"would keep %@ for %ld days", path.stringByAbbreviatingWithTildeInPath, (long)days];
        return 0;
    }
    // A keep changes what the modes may remove, so it runs in the app, as remove and restore do.
    int needs = [a needsApp];
    if (needs) return needs;
    [MMKeep keep:path expert:kExpert until:off ? nil : [NSDate dateWithTimeIntervalSinceNow:days * 86400]];
    if (a.json) [a printJSON:@{@"path": path, @"kept": @(!off), @"days": @(off ? 0 : days)}];
    else [a print:off ? @"%@ is no longer kept" : @"%@ is kept for %ld days", path.stringByAbbreviatingWithTildeInPath, (long)days];
    return 0;
}

static int Protect(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    NSString *path = Absolute(arg, a);
    BOOL off = [a has:@"--off"];
    if (a.dryRun) {
        if (a.json) [a printJSON:@{@"path": path, @"protected": @(!off), @"dryRun": @YES}];
        else [a print:off ? @"would stop protecting %@" : @"would protect %@", path.stringByAbbreviatingWithTildeInPath];
        return 0;
    }
    int needs = [a needsApp];
    if (needs) return needs;
    [MMWFRules() set:!off value:path inList:@"protect" key:nil];
    if (a.json) [a printJSON:@{@"path": path, @"protected": @(!off)}];
    else [a print:off ? @"%@ is no longer protected" : @"%@ is protected", path.stringByAbbreviatingWithTildeInPath];
    return 0;
}

static int Prune(MMArgs *a, NSString *arg) {
    if (!arg) return [a usageError];
    MMWorktree *w = [MMRepoIndex.shared worktreeAt:Absolute(arg, a)];
    if (!w.repo.length) { [a error:@"not in a git repo"]; return MMExitFailed; }
    if (a.dryRun) { [a print:@"would run git worktree prune in %@", w.repo.stringByAbbreviatingWithTildeInPath]; return 0; }
    int needs = [a needsApp];
    if (needs) return needs;
    NSString *out = nil;
    BOOL ok = MMWorktreePrune(w.repo, &out);
    [a print:@"%@", out.length ? out : @"nothing to prune"];
    return ok ? 0 : MMExitFailed;
}

static int RulesCommand(MMArgs *a) {
    MMWFRules();   // makes the file with its defaults
    NSString *path = [MMExpertDir(kExpert) stringByAppendingPathComponent:@"rules.json"];
    NSArray *roots = MMRepoIndex.shared.roots ?: @[];
    if (a.json) { [a printJSON:@{@"rules": path, @"roots": roots}]; return 0; }
    [a print:@"%@", path];
    for (NSString *r in roots) [a print:@"  scans %@%@", r.stringByAbbreviatingWithTildeInPath, [NSFileManager.defaultManager fileExistsAtPath:r] ? @"" : @", missing"];
    return 0;
}

static int CleanUp(MMArgs *a) {
    MMSnapshot *s = Snapshot(a);
    MMReview *r = [s reviewFor:kExpert];
    NSArray<MMFinding *> *c = MMWFCandidates(Scope(a, s), s.facts, r);
    if (!r) [a print:@"No review yet. Run a review first."];
    if (!c.count) { [a print:@"Nothing to clean up."]; return 0; }
    for (MMFinding *f in c) [a print:@"  %@%@", Pad(f.title, 44), r.verdicts[f.findingID].reason ?: @""];
    if (a.dryRun) return 0;
    if (![a has:@"--yes"]) { [a error:@"clean-up asks no questions on the command line. Add --yes to remove %@.", MMPlural(c.count, @"worktree")]; return MMExitUsage; }
    int needs = [a needsApp];
    if (needs) return needs;
    int status = 0;
    for (MMFinding *f in c) {
        NSString *err = nil;
        MMUndoRecord *rec = MMRunAction(MMWFRemoveAction(f), MMWFManualPolicy(), nil, @"cli", r.verdicts[f.findingID].reason ?: @"Clean Up", &err);
        BOOL done = rec && rec.state == MMUndoDone;
        [a print:@"%@ %@%@", done ? @"removed" : @"kept", f.title, done ? @"" : [@": " stringByAppendingString:err ?: rec.error ?: @"it failed"]];
        if (!done) status = 3;
    }
    return status;
}

static int Trees(MMArgs *a) {
    NSString *cmd = [a word:0] ?: @"list";
    NSString *arg = [a word:1];
    if ([cmd isEqualToString:@"list"]) return List(a);
    if ([cmd isEqualToString:@"explain"]) return Explain(a, arg);
    if ([cmd isEqualToString:@"review"]) return Review(a);
    if ([cmd isEqualToString:@"plan"]) return Plan(a, NO);
    if ([cmd isEqualToString:@"auto"]) return Plan(a, YES);
    if ([cmd isEqualToString:@"clean-up"]) return CleanUp(a);
    if ([cmd isEqualToString:@"remove"]) return Remove(a, arg);
    if ([cmd isEqualToString:@"restore"]) return Restore(a, arg);
    if ([cmd isEqualToString:@"removed"]) return Removed(a);
    if ([cmd isEqualToString:@"keep"]) return Keep(a, arg);
    if ([cmd isEqualToString:@"protect"]) return Protect(a, arg);
    if ([cmd isEqualToString:@"prune"]) return Prune(a, arg);
    if ([cmd isEqualToString:@"rules"]) return RulesCommand(a);
    if ([cmd isEqualToString:@"fetch"]) {
        [a error:@"MinMacs never fetches. Run git fetch --all --prune in the repo, and the next walk reads the new state."];
        return MMExitFailed;
    }
    // A path alone explains it, as `minmacs hosts 3000` explains one port.
    if ([cmd hasPrefix:@"/"] || [cmd hasPrefix:@"~"] || [cmd hasPrefix:@"."]) return Explain(a, cmd);
    return [a usageError];
}

static NSString *const kUsage =
    @"trees [list|explain <path>|review|plan|auto|clean-up|remove <path>|restore <id|path>|removed|keep <path>|protect <path>|prune <path>|rules] "
    @"[--all] [--mode <mode>] [--model <model>] [--path <path>] [--days <n>] [--off] [--fresh] [--review] [--yes] [--dry-run] [--json]"
    @"   every git worktree, whether it is merged, and what removing it frees";

NSArray<MMVerbSpec *> *MMWFVerbs(void) {
    static NSArray *verbs; static dispatch_once_t once;
    dispatch_once(&once, ^{
        verbs = @[[MMVerbSpec verb:@"trees" usage:kUsage mutates:NO run:^int(MMArgs *a) { return Trees(a); }],
                  [MMVerbSpec verb:@"worktrees" usage:[@"worktrees" stringByAppendingString:[kUsage substringFromIndex:5]] mutates:NO
                               run:^int(MMArgs *a) { return Trees(a); }]];
        // The forms that change a worktree or the rules run in the app. Each also says so itself through needsApp.
        for (MMVerbSpec *v in verbs) v.mutatingForms = @[@"auto", @"clean-up", @"remove", @"restore", @"keep", @"protect", @"prune"];
    });
    return verbs;
}
