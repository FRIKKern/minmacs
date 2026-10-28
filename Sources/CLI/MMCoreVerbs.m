// Core's own verbs: version, help, status, work, review, investigate, tidy, where, restore and mode.
// Each reads the snapshot and the Store through Core. None samples, scans or asks the model on its own.
// Experts add hosts, apps and their other verbs through -[MMExpert verbs].
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#import "Core/Runtime/MMWorker.h"

// From MMInvestigateCLI.m.
int MMInvestigateVerb(MMArgs *a);
int MMInvestigateToolsVerb(MMArgs *a);

#pragma mark - Words

static NSString *Pad(NSString *s, NSUInteger n) {
    s = s ?: @"";
    return s.length >= n ? [s stringByAppendingString:@" "] : [s stringByPaddingToLength:n withString:@" " startingAtIndex:0];
}

static NSString *AgentStateWord(MMAgentState st) {
    switch (st) {
        case MMAgentWorking: return @"working";
        case MMAgentWaiting: return @"waiting";
        case MMAgentIdle: return @"idle";
        default: return @"unknown";
    }
}

static NSString *PlaceKindWord(MMPlaceKind k) {
    switch (k) {
        case MMPlaceCmux: return @"cmux";
        case MMPlaceTmux: return @"tmux";
        case MMPlaceTerminal: return @"terminal";
        case MMPlaceITerm: return @"iterm";
        case MMPlaceApp: return @"app";
        default: return @"unknown";
    }
}

static NSString *UndoStateWord(MMUndoState s) {
    switch (s) {
        case MMUndoPending: return @"pending";
        case MMUndoDone: return @"done";
        case MMUndoFailed: return @"failed";
        case MMUndoRestored: return @"restored";
    }
    return @"unknown";
}

static id Or(id v) { return v ?: NSNull.null; }

#pragma mark - JSON shapes

static NSDictionary *FindingJSON(MMFinding *f) {
    MMCost c = f.cost;
    NSMutableDictionary *j = [@{@"id": f.findingID ?: @"", @"expert": f.expert ?: @"", @"kind": f.kind ?: @"",
                                @"title": f.title ?: @"", @"kept": @(f.kept), @"keepReasons": f.keepReasons ?: @[],
                                @"ramBytes": @(c.ramBytes), @"diskFreed": @(c.diskFreed)} mutableCopy];
    if (c.cpuPercent >= 0) j[@"cpuPercent"] = @(round(c.cpuPercent * 10) / 10);
    if (f.path) j[@"path"] = f.path;
    if (f.owner) j[@"owner"] = f.owner.ownerID;
    if (f.proposal) j[@"proposal"] = f.proposal.verb ?: @"";
    if (f.facts.count) j[@"facts"] = MMJSONSafe(f.facts);
    return j;
}

static NSDictionary *WorkstreamJSON(MMWorkstream *w) {
    NSMutableDictionary *j = [NSMutableDictionary new];
    j[@"id"] = w.owner.ownerID ?: @"";
    j[@"name"] = w.owner.name ?: @"";
    j[@"path"] = Or(w.owner.path);
    j[@"agentState"] = AgentStateWord(w.agentState);
    if (w.session) j[@"session"] = @{@"agent": Or(w.session.agent), @"id": Or(w.session.sessionID), @"title": Or(w.session.title),
                                     @"cwd": Or(w.session.cwd), @"branch": Or(w.session.branch), @"pid": @(w.session.pid),
                                     @"liveStatus": Or(w.session.liveStatus)};
    if (w.agent) j[@"agent"] = @{@"harness": Or(w.agent.harnessID), @"pid": @(w.agent.key.pid), @"state": AgentStateWord(w.agent.state),
                                 @"why": Or(w.agent.why)};
    if (w.worktree) j[@"worktree"] = @{@"path": Or(w.worktree.path), @"repo": Or(w.worktree.repo), @"branch": Or(w.worktree.branch)};
    NSMutableArray *fs = [NSMutableArray new];
    for (MMFinding *f in w.findings) [fs addObject:FindingJSON(f)];
    j[@"findings"] = fs;
    return j;
}

static NSDictionary *RecordJSON(MMUndoRecord *r) {
    return @{@"rid": r.rid ?: @"", @"expert": Or(r.expert), @"kind": Or(r.kind), @"subject": Or(r.subject), @"why": Or(r.why),
             @"by": Or(r.by), @"state": UndoStateWord(r.state), @"at": Or(r.at), @"canRestore": @(r.canRestore),
             @"freedBytes": @(r.freedBytes), @"error": Or(r.error)};
}

#pragma mark - Expert arguments

/// The experts a verb's first word names, or every expert when it names none. nil when the word names no expert.
static NSArray<id<MMExpert>> *ExpertsFrom(NSString *word) {
    if (!word.length) return MMExperts();
    NSString *w = word.lowercaseString;
    NSString *legacy = MMLegacyNames()[w];
    for (id<MMExpert> e in MMExperts())
        if ([e.expertID isEqualToString:w] || [e.name.lowercaseString isEqualToString:w] || [e.expertID isEqualToString:legacy]) return @[e];
    return nil;
}

#pragma mark - The verbs

static int Version(MMArgs *a) {
    if (a.json) { [a printJSON:@{@"version": @MM_VERSION, @"phase": MMPhase}]; return 0; }
    [a print:@"MinMacs %s (%@)", MM_VERSION, MMPhase];
    return 0;
}

/// A verb an expert keeps from its standalone 1.x app, such as LocoHost's list. Its usage starts with the old name.
static BOOL IsLegacyVerb(id<MMExpert> e, MMVerbSpec *v) {
    NSString *old = [e respondsToSelector:@selector(legacyName)] ? e.legacyName : nil;
    return old.length && [v.usage hasPrefix:[old stringByAppendingString:@" "]];
}

/// The verbs help lists for program, by section. minmacs lists the verbs `minmacs <verb>` runs: Core's, then each
/// expert's 2.0 verbs that no Core verb of the same name hides. A legacy name such as locohost lists its expert's
/// verbs first, the 1.x ones too, then the rest it runs.
static NSArray<NSArray *> *HelpSections(NSString *program) {
    NSMutableArray *sections = [NSMutableArray new];
    NSMutableSet *shown = [NSMutableSet new];
    void (^add)(NSString *, NSArray<MMVerbSpec *> *, BOOL (^)(MMVerbSpec *)) = ^(NSString *title, NSArray *verbs, BOOL (^keep)(MMVerbSpec *)) {
        NSMutableArray *out = [NSMutableArray new];
        for (MMVerbSpec *v in verbs) {
            if ([v.verb hasPrefix:@"_"] || [shown containsObject:v.verb] || !keep(v)) continue;
            // Only the spec this program runs for the word, so a verb is never listed under a name that runs another.
            // An expert may make its specs again on each call, so the usage says which one runs.
            MMVerbSpec *runs = MMFindVerb(program, v.verb);
            if (runs != v && ![runs.usage isEqualToString:v.usage]) continue;
            [shown addObject:v.verb];
            [out addObject:v];
        }
        if (out.count) [sections addObject:@[title ?: @"", out]];
    };
    id<MMExpert> own = nil;
    for (id<MMExpert> e in MMExperts())
        if ([e respondsToSelector:@selector(legacyName)] && [e.legacyName.lowercaseString isEqualToString:program]) own = e;
    if (own) add(own.name, [own verbs], ^BOOL(MMVerbSpec *v) { return YES; });
    add(nil, MMCoreVerbs(), ^BOOL(MMVerbSpec *v) { return YES; });
    for (id<MMExpert> e in MMExperts()) {
        if (e == own) continue;
        add(e.name, [e verbs], ^BOOL(MMVerbSpec *v) { return !IsLegacyVerb(e, v); });
    }
    return sections;
}

static int Help(MMArgs *a) {
    NSString *program = a.program ?: @"minmacs";
    NSArray *sections = HelpSections(program);
    if (a.json) {
        NSMutableArray *v = [NSMutableArray new];
        for (NSArray *sec in sections) for (MMVerbSpec *s in sec[1])
            [v addObject:@{@"verb": s.verb, @"usage": s.usage ?: s.verb, @"mutates": @(s.mutates), @"section": [sec[0] length] ? sec[0] : @"MinMacs"}];
        [a printJSON:@{@"program": program, @"verbs": v}];
        return 0;
    }
    [a print:@"usage: %@ <verb> [--json] [--dry-run]", program];
    for (NSArray *sec in sections) {
        if ([sec[0] length]) [a print:@"%@", sec[0]];
        for (MMVerbSpec *s in sec[1]) [a print:@"  %@", s.usage];
    }
    return 0;
}

static int Walk(MMArgs *a) { return MMWorkerChildMain(); }

/// One expert's line: its header as the menu shows it, its badge and its state.
static NSDictionary *ExpertStatus(id<MMExpert> e, MMSnapshot *s) {
    __block MMMenuSpec *m; __block NSString *badge, *state; __block BOOL empty;
    MMOnMain(^{ m = [e menuFor:s]; badge = [e badgeFor:s]; state = [e accessibilityStateFor:s]; empty = [e fieldEmptyIn:s]; });
    NSString *head = [@[m.headerBig ?: @"", m.headerUnit ?: @""] componentsJoinedByString:@" "];
    head = [head stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return @{@"expert": e.expertID, @"name": e.name ?: e.expertID, @"header": head, @"line": Or(m.headerLine),
             @"summary": Or(m.summary), @"badge": Or(badge), @"state": Or(state), @"fieldEmpty": @(empty),
             @"iconVisible": @(MMIconVisible(e.expertID)), @"mode": MMModeName(MMModeFor(e.expertID)),
             @"findings": @([s findingsFor:e.expertID].count)};
}

static int Status(MMArgs *a) {
    MMSnapshot *s = a.snapshot;
    NSMutableArray *experts = [NSMutableArray new];
    for (id<MMExpert> e in MMExperts()) [experts addObject:ExpertStatus(e, s)];
    NSDictionary *j = @{@"version": @MM_VERSION, @"app": @(a.inApp), @"generation": @(s.generation),
                        @"workingAgents": @([s workingAgents]), @"workstreams": @(s.workstreams.count), @"experts": experts};
    if (a.json) { [a printJSON:j]; return 0; }
    [a print:@"MinMacs %s, %@", MM_VERSION, a.inApp ? @"app running" : @"no app running, read cold"];
    if (!experts.count) [a print:@"No experts are registered."];
    for (NSDictionary *x in experts) {
        NSMutableArray *parts = [NSMutableArray new];
        if ([x[@"header"] length]) [parts addObject:x[@"header"]];
        if (x[@"line"] != NSNull.null && [x[@"line"] length]) [parts addObject:x[@"line"]];
        if (x[@"badge"] != NSNull.null) [parts addObject:[NSString stringWithFormat:@"%@ to act on", x[@"badge"]]];
        if (![x[@"iconVisible"] boolValue]) [parts addObject:@"icon hidden"];
        [a print:@"%@%@", Pad(x[@"name"], 12), parts.count ? [parts componentsJoinedByString:@", "] : @"nothing found"];
    }
    return 0;
}

#pragma mark - Wrap Up

/// Runs block off the main thread and waits. A cold CLI runs its verb on main, where fresh facts are never read.
static void OffMain(dispatch_block_t block) {
    if (!NSThread.isMainThread) { block(); return; }
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_async(g, MMQueue(@"core", @"wrapup", QOS_CLASS_USER_INITIATED), block);
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
}

/// The worktree a Wrap Up id names: a WorkForest finding id, an owner id such as workstream:/path, or a path.
static NSString *WrapUpPath(NSString *key, MMArgs *a, MMSnapshot *s) {
    for (NSString *prefix in @[@"workforest:worktree:", @"core:workstream:", @"workstream:", @"worktree:"])
        if ([key hasPrefix:prefix]) return [key substringFromIndex:prefix.length];
    MMFinding *f = [s finding:key];
    if (f.path.length) return f.path;
    NSString *path = key.isAbsolutePath ? key : [a.cwd ?: NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:key];
    return path.stringByStandardizingPath;
}

static NSString *Bytes(uint64_t n) { return [NSByteCountFormatter stringFromByteCount:(long long)n countStyle:NSByteCountFormatterCountStyleFile]; }

static int WrapUp(MMArgs *a) {
    NSString *key = [a word:1];
    if (!key.length) return [a usageError];
    if (!a.dryRun) { int r = [a needsApp]; if (r) return r; }
    MMSnapshot *s = a.snapshot;
    NSString *path = WrapUpPath(key, a, s);
    MMWrapUpPlan *plan = MMWrapUpPlanFor(path, s);
    __block MMUndoRecord *rec = nil;
    __block NSString *err = nil;
    __block NSDictionary *planJSON = nil;
    // The check reads fresh facts, and the run writes the record and runs each part. Neither runs on main.
    OffMain(^{
        // The fresh check decides, so a size the snapshot had not walked yet does not keep a worktree here.
        // MMRunWrapUp runs the same check before it starts anything.
        if (!plan.subject.whyNot) {
            if (a.dryRun) (void)MMWrapUpCheck(plan);
            else rec = MMRunWrapUp(plan, @"cli", &err);
        }
        planJSON = [plan json:a.dryRun || !rec];
    });
    NSString *name = plan.subject.path.lastPathComponent ?: path.lastPathComponent;
    NSMutableDictionary *j = [planJSON mutableCopy];
    j[@"dryRun"] = @(a.dryRun);
    if (rec) {
        j[@"rid"] = rec.rid;
        j[@"state"] = UndoStateWord(rec.state);
        j[@"error"] = Or(rec.error);
        j[@"freedBytes"] = @(rec.freedBytes);
        if (rec.payload[@"failedPart"]) j[@"failedPart"] = rec.payload[@"failedPart"];
        NSMutableArray *records = [NSMutableArray new];
        for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:500]) if ([r.parentRid isEqualToString:rec.rid]) [records insertObject:RecordJSON(r) atIndex:0];
        j[@"records"] = records;
    } else if (err) j[@"error"] = err;
    int status = plan.whyNot || (!a.dryRun && (!rec || rec.state != MMUndoDone)) ? MMExitFailed : 0;
    if (a.json) { [a printJSON:j]; return status; }
    if (plan.whyNot && !rec) {
        [a print:@"Wrap Up %@ cannot run: %@.", name, plan.whyNot];
        for (MMWrapUpPart *p in plan.parts) if (p.whyNot) [a print:@"  %@%@: %@", Pad(MMWrapUpStepName(p.step), 10), p.title, p.whyNot];
        return status;
    }
    if (a.dryRun) {
        [a print:@"Wrap Up %@ would run %lu parts and free %@:", name, (unsigned long)plan.parts.count, Bytes(plan.freedBytes)];
        for (NSDictionary *p in j[@"parts"])
            [a print:@"  %@%@%@", Pad(p[@"step"], 10), p[@"title"], p[@"dryRun"] != NSNull.null ? [@": " stringByAppendingString:p[@"dryRun"]] : @""];
        [a print:@"Dry run. Nothing was changed."];
        return status;
    }
    if (rec.state == MMUndoDone) [a print:@"Wrapped up %@ in %lu parts. minmacs restore %@ takes it all back.", name, (unsigned long)plan.parts.count, rec.rid];
    else [a print:@"Wrap Up %@ %@. minmacs restore %@ takes back the parts that ran.", name, rec.error ?: err ?: @"failed", rec.rid];
    return status;
}

static int Work(MMArgs *a) {
    if ([[a word:0] isEqualToString:@"wrap-up"]) return WrapUp(a);
    MMSnapshot *s = a.snapshot;
    if ([a has:@"--here"] || a.words.count) {
        NSString *path = [a word:0] ?: a.cwd;
        if (![path isAbsolutePath]) path = [a.cwd stringByAppendingPathComponent:path];
        path = path.stringByStandardizingPath;
        MMWorkstream *w = [s workstreamAt:path];
        if (a.json) { [a printJSON:@{@"path": path, @"workstream": w ? WorkstreamJSON(w) : NSNull.null}]; return 0; }
        if (!w) { [a print:@"No workstream holds %@.", path]; return 0; }
        NSDictionary *j = WorkstreamJSON(w);
        [a print:@"%@, agent %@", j[@"name"], j[@"agentState"]];
        for (NSDictionary *f in j[@"findings"]) [a print:@"  %@%@", Pad(f[@"expert"], 11), f[@"title"]];
        return 0;
    }
    NSMutableArray *all = [NSMutableArray new];
    for (MMWorkstream *w in s.workstreams) [all addObject:WorkstreamJSON(w)];
    if (a.json) { [a printJSON:@{@"workingAgents": @([s workingAgents]), @"workstreams": all}]; return 0; }
    if (!all.count) { [a print:@"No workstreams."]; return 0; }
    for (NSDictionary *j in all) {
        NSUInteger n = [j[@"findings"] count];
        [a print:@"%@%@%@", Pad(j[@"name"], 24), Pad(j[@"agentState"], 9), n ? [NSString stringWithFormat:@"%lu found", (unsigned long)n] : @""];
    }
    [a print:@"%lu workstreams, %ld agents working", (unsigned long)all.count, (long)[s workingAgents]];
    return 0;
}

static int Review(MMArgs *a) {
    NSArray<id<MMExpert>> *experts = ExpertsFrom([a word:0]);
    if (!experts) { [a error:@"no expert named %@", [a word:0]]; return [a usageError]; }
    if ([a has:@"--now"] && !a.dryRun) {
        int r = [a needsApp];
        if (r) return r;
        for (id<MMExpert> e in experts) [MMReviewBroker.shared wake:@"manual" expert:e.expertID];
        if (a.json) { [a printJSON:@{@"started": [experts valueForKey:@"expertID"]}]; return 0; }
        for (id<MMExpert> e in experts) [a print:@"Review started for %@.", e.name];
        return 0;
    }
    MMSnapshot *s = a.snapshot;
    NSMutableArray *out = [NSMutableArray new];
    for (id<MMExpert> e in experts) {
        MMReview *r = [s reviewFor:e.expertID] ?: [MMReview lastFor:e.expertID];
        NSMutableDictionary *j = [@{@"expert": e.expertID, @"name": e.name ?: e.expertID} mutableCopy];
        if (r) {
            NSMutableDictionary *counts = [NSMutableDictionary new];
            MMVerdictWords *words = e.words;
            for (MMVerdict *v in r.verdicts.allValues) {
                NSString *w = v.word ?: [words wordFor:v.kind] ?: @"unsure";
                counts[w] = @([counts[w] integerValue] + 1);
            }
            [j addEntriesFromDictionary:@{@"at": Or(r.at), @"trigger": Or(r.trigger), @"summary": Or(r.summary), @"error": Or(r.error),
                                          @"mode": MMModeName((MMMode)r.mode), @"verdicts": counts}];
        }
        [out addObject:j];
    }
    if (a.json) { [a printJSON:@{@"reviews": out}]; return 0; }
    for (NSDictionary *j in out) {
        if (!j[@"at"]) { [a print:@"%@no review yet", Pad(j[@"name"], 12)]; continue; }
        NSString *when = j[@"at"] == NSNull.null ? @"" : [NSDateFormatter localizedStringFromDate:j[@"at"] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
        NSMutableArray *c = [NSMutableArray new];
        for (NSString *k in [[j[@"verdicts"] allKeys] sortedArrayUsingSelector:@selector(compare:)]) [c addObject:[NSString stringWithFormat:@"%@ %@", j[@"verdicts"][k], k]];
        [a print:@"%@%@, %@%@", Pad(j[@"name"], 12), when, j[@"mode"], c.count ? [@", " stringByAppendingString:[c componentsJoinedByString:@", "]] : @""];
        if (j[@"summary"] != NSNull.null && [j[@"summary"] length]) [a print:@"  %@", j[@"summary"]];
        if (j[@"error"] != NSNull.null && [j[@"error"] length]) [a print:@"  The review failed: %@", j[@"error"]];
    }
    return 0;
}

static int Tidy(MMArgs *a) {
    NSArray<id<MMExpert>> *experts = ExpertsFrom([a word:0]);
    if (!experts) { [a error:@"no expert named %@", [a word:0]]; return [a usageError]; }
    NSInteger forced = [a option:@"--mode"] ? MMModeFrom([a option:@"--mode"]) : -2;
    if (forced == -1) { [a error:@"modes are idle, proactive and eager"]; return [a usageError]; }
    MMSnapshot *s = a.snapshot;
    NSMutableArray *out = [NSMutableArray new];
    int status = 0;
    for (id<MMExpert> e in experts) {
        MMMode mode = forced >= 0 ? (MMMode)forced : MMModeFor(e.expertID);
        MMReview *r = [s reviewFor:e.expertID];
        id<MMExpertPolicy> policy = [e policy];
        NSArray<MMPlanEntry *> *plan = MMPlan([s findingsFor:e.expertID], s.facts, r, mode, policy);
        NSMutableArray *entries = [NSMutableArray new];
        for (MMPlanEntry *p in plan) {
            NSMutableDictionary *j = [@{@"finding": p.finding.findingID ?: @"", @"title": p.finding.title ?: @"", @"act": @(p.act),
                                        @"why": Or(p.why), @"verb": Or(p.finding.proposal.verb)} mutableCopy];
            if (p.act) {
                id<MMAction> action = [e actionFor:p.finding step:MMStopTerm];
                if (!action) { j[@"act"] = @NO; j[@"why"] = @"no action for it"; }
                else if (a.dryRun) j[@"dryRun"] = Or([action dryRun]);
                else {
                    NSString *err = nil;
                    MMUndoRecord *rec = MMRunAction(action, policy, r, @"cli", p.why, &err);
                    j[@"done"] = rec && rec.state == MMUndoDone ? @YES : @NO;
                    if (rec) j[@"rid"] = rec.rid;
                    if (err || rec.error) j[@"error"] = err ?: rec.error;
                    if (![j[@"done"] boolValue]) status = MMExitFailed;
                }
            }
            [entries addObject:j];
        }
        [out addObject:@{@"expert": e.expertID, @"name": e.name ?: e.expertID, @"mode": MMModeName(mode), @"entries": entries}];
    }
    if (a.json) { [a printJSON:@{@"dryRun": @(a.dryRun), @"experts": out}]; return status; }
    for (NSDictionary *x in out) {
        NSArray *acts = [x[@"entries"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"act == YES"]];
        [a print:@"%@, %@: %lu to act on, %lu stay", x[@"name"], x[@"mode"], (unsigned long)acts.count,
                 (unsigned long)([x[@"entries"] count] - acts.count)];
        for (NSDictionary *j in x[@"entries"]) {
            NSString *word = [j[@"act"] boolValue] ? (j[@"verb"] != NSNull.null ? j[@"verb"] : @"act") : @"stays";
            NSString *tail = j[@"error"] ?: (j[@"dryRun"] != nil && j[@"dryRun"] != NSNull.null ? j[@"dryRun"] : (j[@"why"] != NSNull.null ? j[@"why"] : @""));
            if (j[@"done"]) word = [j[@"done"] boolValue] ? @"done" : @"failed";
            [a print:@"  %@%@%@", Pad(word, 8), Pad(j[@"title"], 28), tail];
        }
    }
    if (a.dryRun) [a print:@"Dry run. Nothing was changed."];
    return status;
}

/// The pid that listens on port in the sample, or 0.
static pid_t ListenerOn(MMSample *s, NSInteger port) {
    if (![s respondsToSelector:@selector(sockets:)]) return 0;
    NSUInteger n = 0;
    const MMSocket *socks = [s sockets:&n];
    for (NSUInteger i = 0; i < n; i++) if (socks[i].state == MMSocketListen && socks[i].localPort == port) return socks[i].pid;
    return 0;
}

static int Where(MMArgs *a) {
    NSString *w = [a word:0];
    NSString *portArg = [a option:@"--port"] ?: ([w hasPrefix:@":"] ? [w substringFromIndex:1] : nil);
    NSInteger port = portArg.integerValue;
    pid_t pid = portArg ? 0 : (pid_t)w.intValue;
    if ((portArg && (port <= 0 || port > 65535)) || (!portArg && pid <= 0)) return [a usageError];
    MMSample *s = a.snapshot.facts.sample;
    if (portArg) {
        pid = ListenerOn(s, port);
        if (!pid) {
            if (a.json) [a printJSON:@{@"port": @(port), @"pid": NSNull.null}]; else [a print:@"Nothing of yours listens on :%ld.", (long)port];
            return MMExitFailed;
        }
    }
    MMProc *p = [s respondsToSelector:@selector(proc:)] ? [s proc:pid] : nil;
    if (!p) {
        if (a.json) [a printJSON:@{@"pid": @(pid), @"running": @NO}]; else [a print:@"No process %d runs.", pid];
        return MMExitFailed;
    }
    MMPlace *place = MMWhereIs(p.key, s, YES);
    NSMutableDictionary *j = [@{@"pid": @(pid), @"running": @YES, @"name": Or(p.name), @"kind": PlaceKindWord(place.kind),
                                @"app": Or(place.app), @"label": Or(place.label), @"tab": Or(place.tab), @"tty": Or(place.tty),
                                @"target": Or(place.target)} mutableCopy];
    if (portArg) j[@"port"] = @(port);
    if ([a has:@"--go"] && !a.dryRun && place) {
        BOOL went = NO; NSString *err = nil;
        // MMGoTo can block for seconds. A verb runs off main in the app, on core.sock's queue, so it runs right here.
        NSString *e = nil; went = MMGoTo(place, &e); err = e;
        j[@"went"] = @(went);
        if (err) j[@"error"] = err;
    }
    if (a.json) { [a printJSON:j]; return 0; }
    [a print:@"%@%d %@, %@", portArg ? [NSString stringWithFormat:@":%ld, pid ", (long)port] : @"pid ", pid, p.name,
             place.label.length ? place.label : @"no terminal or app found"];
    if (j[@"error"]) [a print:@"Could not go there: %@", j[@"error"]];
    return 0;
}

static int Restore(MMArgs *a) {
    MMUndo *u = MMUndo.shared;
    NSString *expert = [a option:@"--expert"];
    if (expert && MMLegacyNames()[expert.lowercaseString]) expert = MMLegacyNames()[expert.lowercaseString];
    if ([a has:@"--list"]) {
        NSArray *recs = [u recent:expert limit:(NSUInteger)MAX(1, [a option:@"--limit"].integerValue ?: 20)];
        NSMutableArray *j = [NSMutableArray new];
        for (MMUndoRecord *r in recs) [j addObject:RecordJSON(r)];
        if (a.json) { [a printJSON:@{@"records": j}]; return 0; }
        if (!recs.count) { [a print:@"Nothing to restore."]; return 0; }
        for (MMUndoRecord *r in recs)
            [a print:@"%@%@%@%@%@", Pad(r.rid, 14), Pad(r.expert, 11), Pad(r.kind, 8), Pad(r.canRestore && r.state == MMUndoDone ? @"restorable" : UndoStateWord(r.state), 11), r.subject ?: @""];
        return 0;
    }
    // One record by id, or every restorable record of the newest minute of actions: the last run.
    NSMutableArray<MMUndoRecord *> *targets = [NSMutableArray new];
    NSString *rid = [a word:0];
    if (rid) {
        MMUndoRecord *r = [u record:rid];
        if (!r) { [a error:@"no undo record %@", rid]; return MMExitFailed; }
        [targets addObject:r];
    } else {
        NSArray<MMUndoRecord *> *recent = [u recent:expert limit:200];
        NSDate *newest = nil;
        for (MMUndoRecord *r in recent) {
            if (r.state != MMUndoDone || !r.canRestore || r.parentRid) continue;
            if (!newest) newest = r.at;
            if ([newest timeIntervalSinceDate:r.at] <= 60) [targets addObject:r];
        }
    }
    if (!targets.count) {
        if (a.json) [a printJSON:@{@"restored": @[], @"dryRun": @(a.dryRun)}]; else [a print:@"Nothing to restore."];
        return 0;
    }
    if (!a.dryRun) { int r = [a needsApp]; if (r) return r; }
    NSMutableArray *j = [NSMutableArray new];
    int status = 0;
    for (MMUndoRecord *r in targets) {
        NSMutableDictionary *x = [RecordJSON(r) mutableCopy];
        if (!a.dryRun) {
            NSString *problem = [u restore:r.rid];
            x[@"restored"] = problem ? @NO : @YES;
            if (problem) { x[@"problem"] = problem; status = MMExitFailed; }
        }
        [j addObject:x];
    }
    if (a.json) { [a printJSON:@{@"restored": j, @"dryRun": @(a.dryRun)}]; return status; }
    for (NSDictionary *x in j) {
        NSString *word = a.dryRun ? @"would restore" : [x[@"restored"] boolValue] ? @"restored" : @"could not restore";
        [a print:@"%@ %@%@", word, x[@"subject"] != NSNull.null ? x[@"subject"] : x[@"rid"], x[@"problem"] ? [@": " stringByAppendingString:x[@"problem"]] : @""];
    }
    return status;
}

static int Mode(MMArgs *a) {
    NSString *w = [a word:0].lowercaseString;
    NSString *expert = MMLegacyNames()[w] ?: ([w isEqualToString:@"minmacs"] ? w : nil);
    for (id<MMExpert> e in MMExperts()) if ([e.expertID isEqualToString:w]) expert = w;
    if (!expert) return [a usageError];
    NSString *name = [a word:1];
    if (name) {
        NSInteger m = MMModeFrom(name.lowercaseString);
        if (m < 0) { [a error:@"modes are idle, proactive and eager"]; return [a usageError]; }
        if (!a.dryRun) MMSetMode(expert, (MMMode)m);
    }
    NSString *now = name && a.dryRun ? name.lowercaseString : MMModeName(MMModeFor(expert));
    if (a.json) [a printJSON:@{@"expert": expert, @"mode": now}]; else [a print:@"%@", now];
    return 0;
}

NSArray<MMVerbSpec *> *MMCoreVerbs(void) {
    static NSArray *verbs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        verbs = @[
            [MMVerbSpec verb:@"status" usage:@"status [--json]   what each expert sees, as its menu header says it" mutates:NO run:^(MMArgs *a) { return Status(a); }],
            [MMVerbSpec verb:@"work" usage:@"work [path] [--here] [--json] | work wrap-up <id> [--dry-run] [--json]   each workstream, or Wrap Up of a finished one" mutates:NO run:^(MMArgs *a) { return Work(a); }],
            [MMVerbSpec verb:@"review" usage:@"review [expert] [--now] [--json]   the last review, or a new one with --now" mutates:NO run:^(MMArgs *a) { return Review(a); }],
            [MMVerbSpec verb:@"investigate" usage:@"investigate <finding|workstream|path> [question] [--yes] [--json]   look deeper into one, after you confirm its cost" mutates:NO run:^(MMArgs *a) { return MMInvestigateVerb(a); }],
            [MMVerbSpec verb:@"tidy" usage:@"tidy [expert] [--dry-run] [--mode <mode>] [--json]   what each mode would act on, and act on it" mutates:YES run:^(MMArgs *a) { return Tidy(a); }],
            [MMVerbSpec verb:@"where" usage:@"where <pid> | where --port <port> [--go] [--json]   the terminal tab, pane or app it runs in" mutates:NO run:^(MMArgs *a) { return Where(a); }],
            [MMVerbSpec verb:@"restore" usage:@"restore [rid] [--list] [--expert <expert>] [--limit <n>] [--dry-run] [--json]   undo the last run, or one record" mutates:NO run:^(MMArgs *a) { return Restore(a); }],
            [MMVerbSpec verb:@"mode" usage:@"mode <expert> [idle|proactive|eager] [--json]   show or set an expert's mode" mutates:NO run:^(MMArgs *a) { return Mode(a); }],
            [MMVerbSpec verb:@"version" usage:@"version [--json]   the version" mutates:NO run:^(MMArgs *a) { return Version(a); }],
            [MMVerbSpec verb:@"help" usage:@"help [--json]   every verb" mutates:NO run:^(MMArgs *a) { return Help(a); }],
            [MMVerbSpec verb:@"_walk" usage:@"_walk" mutates:NO run:^(MMArgs *a) { return Walk(a); }],
            [MMVerbSpec verb:@"_investigate-tools" usage:@"_investigate-tools --folder <path> --audit <file>" mutates:NO run:^(MMArgs *a) { return MMInvestigateToolsVerb(a); }],
        ];
    });
    return verbs;
}
