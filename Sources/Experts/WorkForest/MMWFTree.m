// WorkForest's model, words, keeps, menu and cards. See MMWFTree.h. Pure: no git, no disk, no processes.
#import "Experts/WorkForest/MMWFTree.h"
#import "UI/MMFormat.h"
#import "UI/MMInvestigateUI.h"

static id Or(id v) { return v ?: NSNull.null; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static id Time(NSDate *d) { return d ? @(d.timeIntervalSince1970) : NSNull.null; }
static NSDate *Date(id v) { return [v isKindOfClass:NSNumber.class] && [v doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[v doubleValue]] : nil; }

#pragma mark - The tree

@implementation MMWFTree

- (NSString *)name { return self.path.lastPathComponent; }
- (NSString *)repoName { return self.repo.lastPathComponent ?: @""; }
- (BOOL)detached { return !self.branch.length; }
- (BOOL)done { return self.merged.length > 0 || [self.upstream isEqualToString:@"gone"]; }

- (NSDate *)lastWork {
    NSDate *d = self.lastCommit ?: self.created;
    if (self.touched && (!d || [self.touched compare:d] == NSOrderedDescending)) d = self.touched;
    NSDate *s = Date(self.session[@"lastActiveAt"]);
    if (s && (!d || [s compare:d] == NSOrderedDescending)) d = s;
    return d;
}

- (NSTimeInterval)quiet { return self.lastWork ? MAX(0, -self.lastWork.timeIntervalSinceNow) : 0; }

- (NSDictionary *)json {
    return @{@"path": Or(self.path), @"repo": Or(self.repo), @"branch": Or(self.branch), @"findingID": Or(self.findingID),
             @"main": @(self.isMain), @"locked": @(self.locked), @"missing": @(self.missing), @"maker": Or(self.maker),
             @"makerSession": Or(self.makerSession), @"gitKnown": @(self.gitKnown), @"head": Or(self.head),
             @"defaultBranch": Or(self.defaultBranch), @"merged": Or(self.merged), @"upstream": Or(self.upstream),
             @"dirty": @(self.dirty), @"untracked": @(self.untracked), @"stashes": @(self.stashes), @"unpushed": @(self.unpushed),
             @"notInDefault": @(self.notInDefault), @"onRemote": @(self.onRemote), @"lastCommitAt": Time(self.lastCommit),
             @"sized": @(self.sized), @"diskBytes": @(self.diskBytes), @"freedBytes": @(self.freedBytes), @"cacheBytes": @(self.cacheBytes),
             @"files": @(self.files), @"touchedAt": Time(self.touched), @"createdAt": Time(self.created),
             @"processes": self.processes ?: @[], @"session": Or(self.session), @"protected": @(self.isProtected),
             @"quietDays": self.lastWork ? @(round(self.quiet / 8640) / 10) : NSNull.null};
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (!Dict(j) || !Str(j[@"path"])) return nil;
    MMWFTree *t = [MMWFTree new];
    t.path = j[@"path"]; t.repo = Str(j[@"repo"]); t.branch = Str(j[@"branch"]); t.findingID = Str(j[@"findingID"]);
    t.isMain = [j[@"main"] boolValue]; t.locked = [j[@"locked"] boolValue]; t.missing = [j[@"missing"] boolValue];
    t.maker = Str(j[@"maker"]); t.makerSession = Str(j[@"makerSession"]);
    t.gitKnown = [j[@"gitKnown"] boolValue]; t.head = Str(j[@"head"]); t.defaultBranch = Str(j[@"defaultBranch"]);
    t.merged = Str(j[@"merged"]); t.upstream = Str(j[@"upstream"]);
    t.dirty = [j[@"dirty"] integerValue]; t.untracked = [j[@"untracked"] integerValue]; t.stashes = [j[@"stashes"] integerValue];
    t.unpushed = [j[@"unpushed"] integerValue]; t.notInDefault = [j[@"notInDefault"] integerValue]; t.onRemote = [j[@"onRemote"] boolValue];
    t.lastCommit = Date(j[@"lastCommitAt"]);
    t.sized = [j[@"sized"] boolValue]; t.diskBytes = [j[@"diskBytes"] unsignedLongLongValue];
    t.freedBytes = [j[@"freedBytes"] unsignedLongLongValue]; t.cacheBytes = [j[@"cacheBytes"] unsignedLongLongValue];
    t.files = [j[@"files"] integerValue]; t.touched = Date(j[@"touchedAt"]); t.created = Date(j[@"createdAt"]);
    t.processes = List(j[@"processes"]) ?: @[]; t.session = Dict(j[@"session"]); t.isProtected = [j[@"protected"] boolValue];
    return t;
}

@end

#pragma mark - Words

/// "squash-merged", "merged" for a merge by ancestry.
static NSString *MergedWord(NSString *m) {
    if (!m.length) return nil;
    if ([m isEqualToString:@"ancestor"]) return @"merged";
    if ([m isEqualToString:@"merge-tree"]) return @"merges cleanly";
    if ([m isEqualToString:@"pr"]) return @"pull request merged";
    return [m stringByAppendingString:@"-merged"];
}

static NSString *DefaultName(MMWFTree *t) { return t.defaultBranch.lastPathComponent ?: @"the default branch"; }

NSString *MMWFStateWords(MMWFTree *t) {
    if (t.missing) return @"folder missing";
    if (!t.gitKnown) return @"git facts not read yet";
    NSMutableArray *p = [NSMutableArray new];
    if (t.merged.length) [p addObject:MergedWord(t.merged)];
    if ([t.upstream isEqualToString:@"gone"]) [p addObject:@"remote branch deleted"];
    else if ([t.upstream isEqualToString:@"none"] && !t.isMain && !t.detached) [p addObject:@"never pushed"];
    if (t.dirty > 0) [p addObject:MMPlural(t.dirty, @"change")];
    if (t.dirty < 0) [p addObject:@"changes unknown"];
    if (t.untracked > 0) [p addObject:MMPlural(t.untracked, @"untracked file")];
    if (t.unpushed > 0 && !t.merged.length) [p addObject:[NSString stringWithFormat:@"%@ only here", MMPlural(t.unpushed, @"commit")]];
    if (t.detached) [p addObject:@"detached"];
    if (t.locked) [p addObject:@"locked"];
    if (!t.merged.length && t.notInDefault > 0) [p addObject:[NSString stringWithFormat:@"%@ not in %@", MMPlural(t.notInDefault, @"commit"), DefaultName(t)]];
    return p.count ? [p componentsJoinedByString:@" · "] : @"clean";
}

NSString *MMWFShortState(MMWFTree *t) {
    if (t.missing) return @"folder missing";
    if (!t.gitKnown) return @"not read yet";
    if (t.dirty > 0) return MMPlural(t.dirty, @"change");
    if (t.untracked > 0) return [NSString stringWithFormat:@"%ld untracked", (long)t.untracked];
    if (t.unpushed > 0 && !t.merged.length) return [NSString stringWithFormat:@"%@ only here", MMPlural(t.unpushed, @"commit")];
    if (t.merged.length) return MergedWord(t.merged);
    if ([t.upstream isEqualToString:@"gone"]) return @"remote branch deleted";
    if (t.locked) return @"locked";
    if (t.notInDefault > 0) return [NSString stringWithFormat:@"%@ not in %@", MMPlural(t.notInDefault, @"commit"), DefaultName(t)];
    return @"clean";
}

NSString *MMWFAgentName(NSString *h) {
    NSDictionary *names = @{@"claude-code": @"Claude Code", @"codex": @"Codex", @"pi": @"pi", @"cursor": @"Cursor", @"conductor": @"Conductor"};
    return names[h ?: @""] ?: h ?: @"an agent";
}

NSString *MMWFModeLabel(NSString *mode) { return mode.length ? mode.capitalizedString : @"Proactive"; }

#pragma mark - Keeps

static NSTimeInterval EnvHours(const char *key, double hours) {
    const char *v = getenv(key);
    return (v && *v ? atof(v) : hours) * 3600;
}
NSTimeInterval MMWFRecent(void) { return EnvHours("WORKFOREST_RECENT_HOURS", 24); }
NSTimeInterval MMWFProactiveQuiet(void) { return EnvHours("WORKFOREST_PROACTIVE_HOURS", 7 * 24); }

NSString *MMWFWorkKeeps(MMWFTree *t) {
    if (t.isMain) return @"the main checkout";
    if (t.missing) return @"its folder is missing; prune tidies git's record of it";
    if ([t.maker isEqualToString:@"cursor"]) return @"Cursor made it, and MinMacs only shows Cursor's worktrees";
    if ([t.maker isEqualToString:@"conductor"]) return @"Conductor made it, and MinMacs only shows Conductor's worktrees";
    if (t.isProtected) return [NSString stringWithFormat:@"%@ is a long-lived branch", t.branch];
    if (t.locked) return @"locked";
    if (!t.gitKnown) return @"cannot verify: its git facts are not known yet";
    if (t.dirty < 0) return @"git status failed, so its changes are unknown";
    if (t.dirty > 0) return [NSString stringWithFormat:@"%@ not committed", MMPlural(t.dirty, @"change")];
    if (t.untracked > 0) return [NSString stringWithFormat:@"%@ not committed", MMPlural(t.untracked, @"untracked file")];
    if (t.detached && (t.unpushed != 0 || !t.onRemote) && !t.merged.length)
        return t.unpushed < 0 ? @"detached, and its commits could not be counted"
                              : [NSString stringWithFormat:@"detached with %@ no branch holds", MMPlural(MAX(t.unpushed, 1), @"commit")];
    if (t.unpushed < 0 && !t.merged.length) return @"its commits could not be counted";
    if (t.unpushed > 0 && !t.merged.length)
        return [NSString stringWithFormat:@"%@ on no remote and not in %@", MMPlural(t.unpushed, @"commit"), DefaultName(t)];
    if (t.processes.count) return [NSString stringWithFormat:@"%@ running inside", t.processes.firstObject];
    NSDate *s = Date(t.session[@"lastActiveAt"]);
    if ([t.session[@"live"] boolValue]) return [NSString stringWithFormat:@"%@ session is working in it", MMWFAgentName(Str(t.session[@"agent"]))];
    if (s && -s.timeIntervalSinceNow < MMWFRecent())
        return [NSString stringWithFormat:@"%@ session active %@ ago", MMWFAgentName(Str(t.session[@"agent"])), MMDuration(-s.timeIntervalSinceNow)];
    if (!t.sized) return @"its files are not read yet";
    if (t.touched && -t.touched.timeIntervalSinceNow < MMWFRecent()) return [NSString stringWithFormat:@"files changed %@ ago", MMDuration(-t.touched.timeIntervalSinceNow)];
    if (t.created && -t.created.timeIntervalSinceNow < MMWFRecent()) return [NSString stringWithFormat:@"made %@ ago", MMDuration(-t.created.timeIntervalSinceNow)];
    return nil;
}

NSString *MMWFCategory(MMWFTree *t, NSString *verdict) {
    if (t.missing) return @"missing";
    NSString *work = MMWFWorkKeeps(t);
    BOOL inUse = work && !t.isProtected && !t.locked && ![work hasPrefix:@"cannot verify"] && ![work hasPrefix:@"its files"] &&
                 ![work hasPrefix:@"Cursor"] && ![work hasPrefix:@"Conductor"];
    if (inUse) return @"active";
    if (t.done) return @"merged";
    if ([verdict isEqualToString:@"stale"] || t.quiet > 14 * 86400) return @"stale";
    return @"quiet";
}

#pragma mark - Menu

@implementation MMWFView
@end

static void Act(MMWFView *v, NSString *what, NSString *key, BOOL option) { if (v.act) v.act(what, key, option); }

static MMActionSpec *Action(MMWFView *v, NSString *title, NSString *tail, NSString *what, NSString *key) {
    __weak MMWFView *weak = v;
    return [MMActionSpec title:title tail:tail run:^(BOOL option) { Act(weak, what, key, option); }];
}

static BOOL Goes(MMWFTree *t, MMWFView *v) {
    NSDictionary *p = v.plan[t.findingID];
    return [p[@"remove"] boolValue] || [Str(p[@"why"]) hasPrefix:@"would act"] || [v.candidates containsObject:t.findingID];
}

static uint64_t Frees(MMWFTree *t) { return t.freedBytes ?: t.diskBytes; }

/// The start every worktree folder of a repo shares, up to a dash, such as "acme-web-": left out of the rows.
static NSDictionary<NSString *, NSString *> *Prefixes(NSArray<MMWFTree *> *trees) {
    NSMutableDictionary<NSString *, NSMutableArray *> *byRepo = [NSMutableDictionary new];
    for (MMWFTree *t in trees) if (!t.isMain && t.repo) [(byRepo[t.repo] ?: (byRepo[t.repo] = [NSMutableArray new])) addObject:t.name ?: @""];
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *repo in byRepo) {
        NSArray *names = byRepo[repo];
        if (names.count < 2) continue;
        NSString *common = names.firstObject;
        for (NSString *n in names) common = [common commonPrefixWithString:n options:0];
        NSRange dash = [common rangeOfString:@"-" options:NSBackwardsSearch];
        if (dash.location != NSNotFound && dash.location >= 2) out[repo] = [common substringToIndex:dash.location + 1];
    }
    return out;
}

static NSString *RowName(MMWFTree *t, NSDictionary *prefixes) {
    NSString *name = t.name ?: @"";
    NSString *p = prefixes[t.repo ?: @""];
    if (p.length && [name hasPrefix:p] && name.length > p.length) return [name substringFromIndex:p.length];
    NSString *rp = [t.repoName stringByAppendingString:@"-"];
    if ([name hasPrefix:rp] && name.length > rp.length) return [name substringFromIndex:rp.length];
    return name;
}

static MMRowMark MarkFor(MMWFTree *t, MMWFView *v, NSString *category) {
    if (!t.gitKnown || !t.sized) return MMRowMarkUnknown;
    if ([category isEqualToString:@"active"]) return MMRowMarkWorking;
    if (Goes(t, v)) return MMRowMarkGoes;
    return MMRowMarkQuiet;
}

static NSString *VerdictWord(MMWFView *v, MMWFTree *t) { return Str(v.verdicts[t.findingID][@"word"]); }

static MMRowSpec *Row(MMWFTree *t, MMWFView *v, NSString *category, BOOL showRepo, NSDictionary *prefixes) {
    MMRowSpec *r = [MMRowSpec new];
    r.name = RowName(t, prefixes);
    NSMutableArray *facts = [NSMutableArray new];
    if (showRepo) [facts addObject:t.repoName];
    [facts addObject:t.sized ? MMBytes(Frees(t)) : @"sizing"];
    // The state the section does not already say. In Merged, a merge is said; in In use, what keeps it.
    NSString *state = MMWFShortState(t);
    BOOL said = ([category isEqualToString:@"merged"] && t.done && (t.merged.length || [state isEqualToString:@"remote branch deleted"])) ||
                [state isEqualToString:@"clean"];
    if ([category isEqualToString:@"active"] && t.dirty <= 0 && t.untracked <= 0) {
        // In use: what keeps it, a server, a process or an agent, before its git state.
        NSString *server = Str([v.links[t.findingID] firstObject][@"value"]);
        NSDate *last = Date(t.session[@"lastActiveAt"]);
        if (server.length) state = [@"server " stringByAppendingString:[server componentsSeparatedByString:@","].firstObject];
        else if (t.processes.count) state = [t.processes.firstObject stringByAppendingString:@" runs inside"];
        else if (t.session) state = last ? [NSString stringWithFormat:@"%@ %@", MMWFAgentName(Str(t.session[@"agent"])), MMAgo(last)] : MMWFAgentName(Str(t.session[@"agent"]));
    }
    else if (said) state = Goes(t, v) ? @"goes at the next review" : [@"untouched " stringByAppendingString:MMShortDuration(t.quiet)];
    [facts addObject:state];
    r.facts = facts;
    r.mark = MarkFor(t, v, category);
    r.findingID = t.findingID;
    return r;
}

static NSString *Summary(MMWFView *v, NSInteger linked) {
    if (v.reviewError.length && !v.summaryWords.length) return MMSentence([@"The last review failed: " stringByAppendingString:v.reviewError]);
    if (v.summaryWords.length) return v.summaryWords;
    if (!linked) return @"No linked worktrees right now. WorkForest shows each one as it appears.";
    if (v.watchingLeft > 0)
        return [NSString stringWithFormat:@"Watching %@. Acts on nothing for %@.", MMPlural(linked, @"worktree"), MMDuration(v.watchingLeft)];
    return [NSString stringWithFormat:@"Watching %@. The first review runs within two hours.", MMPlural(linked, @"worktree")];
}

MMMenuSpec *MMWFMenu(MMWFView *v) {
    NSMutableArray<MMWFTree *> *linked = [NSMutableArray new];
    for (MMWFTree *t in v.trees) if (!t.isMain) [linked addObject:t];
    NSMutableSet *repos = [NSMutableSet new];
    for (MMWFTree *t in v.trees) if (t.repo) [repos addObject:t.repo];
    uint64_t total = 0;
    for (MMWFTree *t in linked) total += Frees(t);

    MMMenuSpec *m = [MMMenuSpec new];
    m.headerBig = MMBytes(total);
    m.headerUnit = @"in worktrees";
    NSString *mode = MMWFModeLabel(v.mode);
    if (v.watchingLeft > 0 && ![v.mode isEqualToString:@"idle"]) mode = [NSString stringWithFormat:@"%@ starts in %@", mode, MMShortDuration(v.watchingLeft)];
    m.headerLine = [NSString stringWithFormat:@"%@ in %@ · %@", MMPlural(linked.count, @"worktree"), MMPlural(repos.count, @"repo"), mode];
    m.summary = Summary(v, linked.count);

    NSMutableArray *actions = [NSMutableArray new];
    if (v.candidates.count) {
        uint64_t freed = 0;
        for (MMWFTree *t in linked) if ([v.candidates containsObject:t.findingID]) freed += Frees(t);
        [actions addObject:Action(v, @"Clean Up", [NSString stringWithFormat:@"%@, %@", MMPlural(v.candidates.count, @"worktree"), MMBytes(freed)], @"clean-up", nil)];
    }
    if (linked.count) {
        MMActionSpec *review = Action(v, @"Review Now", v.reviewAt ? MMAgo(v.reviewAt) : nil, @"review", nil);
        if (v.reviewing) review.disabledReason = @"reviewing now";
        [actions addObject:review];
    }
    m.actions = actions;

    NSDictionary *prefixes = Prefixes(v.trees);
    BOOL showRepo = repos.count > 1;
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary new];
    for (MMWFTree *t in linked) {
        NSString *c = MMWFCategory(t, VerdictWord(v, t));
        [(groups[c] ?: (groups[c] = [NSMutableArray new])) addObject:t];
    }
    NSMutableArray *sections = [NSMutableArray new];
    for (NSArray *sec in @[@[@"merged", @"Merged"], @[@"stale", @"Stale"], @[@"active", @"In use"], @[@"quiet", @"Quiet"]]) {
        NSArray *g = [groups[sec[0]] sortedArrayUsingComparator:^NSComparisonResult(MMWFTree *a, MMWFTree *b) {
            uint64_t x = Frees(a), y = Frees(b);
            return x > y ? NSOrderedAscending : x < y ? NSOrderedDescending : [a.path compare:b.path];
        }];
        if (!g.count) continue;
        MMSectionSpec *s = [MMSectionSpec new];
        s.title = sec[1];
        NSMutableArray *rows = [NSMutableArray new];
        for (MMWFTree *t in g) [rows addObject:Row(t, v, sec[0], showRepo, prefixes)];
        s.rows = rows;
        [sections addObject:s];
    }
    m.sections = sections;

    // Recently Removed lives under More: one Restore per removal, newest first, with when and by whom as the tail.
    NSMutableArray *more = [NSMutableArray new];
    for (NSDictionary *x in [v.removed subarrayWithRange:NSMakeRange(0, MIN(v.removed.count, (NSUInteger)6))]) {
        NSString *by = Str(x[@"by"]);
        by = [by isEqualToString:@"manual"] || [by isEqualToString:@"cli"] || [by isEqualToString:@"you"] || !by.length ? @"you" : MMWFModeLabel(by);
        NSString *title = [NSString stringWithFormat:@"Restore %@", MMCut([Str(x[@"path"]) lastPathComponent] ?: @"worktree", 36)];
        MMActionSpec *a = Action(v, title, [NSString stringWithFormat:@"%@ by %@", MMAgo(Date(x[@"at"])), by], @"restore", Str(x[@"rid"]));
        if ([x[@"taken"] boolValue]) a.disabledReason = @"its folder exists again";
        [more addObject:a];
    }
    NSInteger missing = groups[@"missing"].count;
    if (missing) [more addObject:Action(v, @"Prune Missing Folders", MMPlural(missing, @"worktree"), @"prune", nil)];
    m.more = more;
    return m;
}

#pragma mark - Card

/// "quiet 6d: squash-merged" reads "squash-merged": the card's Last work line already says how quiet it is.
static NSString *WithoutQuietLead(NSString *why) {
    NSRange colon = [why rangeOfString:@": "];
    return [why hasPrefix:@"quiet "] && colon.location != NSNotFound && colon.location < 16 ? [why substringFromIndex:NSMaxRange(colon)] : why;
}

/// Why it stays or when it goes: a word, then whole sentences that say why and what happens next.
static void Status(MMWFTree *t, MMWFView *v, MMCardSpec *c, NSString *category) {
    c.mark = MarkFor(t, v, category);
    if (t.isMain) { c.statusWord = @"Stays."; c.statusText = @"WorkForest never removes a main checkout."; c.mark = MMRowMarkQuiet; return; }
    if (t.missing) { c.statusWord = @"Folder is gone."; c.statusText = @"Git still lists this worktree. Prune, under More, tidies git's record of it."; return; }
    NSDictionary *p = v.plan[t.findingID];
    NSString *why = Str(p[@"why"]) ?: MMWFWorkKeeps(t) ?: @"";
    if ([p[@"remove"] boolValue]) {
        c.statusWord = @"Goes at the next review.";
        c.statusText = [MMSentence(MMCut(WithoutQuietLead(why), 90)) stringByAppendingString:@" Restore brings it back."];
        return;
    }
    if ([why hasPrefix:@"would act ("]) {
        NSRange end = [why rangeOfString:@"), but " options:NSBackwardsSearch];
        NSString *inner = end.location != NSNotFound ? [why substringWithRange:NSMakeRange(11, end.location - 11)] : why;
        c.statusWord = @"Goes after the first day.";
        c.statusText = [MMSentence(MMCut(WithoutQuietLead(inner), 120)) stringByAppendingString:@" WorkForest watches for a day before any mode acts."];
        return;
    }
    if ([v.mode isEqualToString:@"idle"] && !MMWFWorkKeeps(t)) {
        c.statusWord = @"Stays."; c.statusText = @"Idle mode only reports. Clean Up and Remove are up to you.";
        return;
    }
    NSString *next = @"";
    if ([why containsString:@"not committed"]) next = @" Commit or discard them, and the next review looks again.";
    else if ([why containsString:@"on no remote"]) next = @" Push or merge them first. Until then this is the only copy.";
    else if ([why containsString:@"no branch holds"]) next = @" Put them on a branch first.";
    else if ([why hasSuffix:@"running inside"]) {
        why = [@"a process runs inside: " stringByAppendingString:[why stringByReplacingOccurrencesOfString:@" running inside" withString:@""]];
        next = @" It stays while that runs.";
    }
    else if ([why containsString:@"session"]) next = @" The agent may still be working here.";
    else if ([why hasPrefix:@"files changed"]) next = @" After a quiet day the next review looks again.";
    else if ([why hasPrefix:@"made "]) next = @" New worktrees get a day.";
    else if ([why isEqualToString:@"protected"]) next = @" Unprotect it under More to let the mode decide.";
    else if ([why hasSuffix:@"is a long-lived branch"]) next = @" protect.branches in WorkForest's rules.json lists it.";
    else if ([why hasPrefix:@"locked"]) next = @" git worktree unlock lets the mode decide.";
    else if ([why hasPrefix:@"kept by you"]) next = @" The mode decides again when the keep ends.";
    else if ([why hasPrefix:@"evidence: "]) why = [@"the judge found evidence: " stringByAppendingString:[why substringFromIndex:10]];
    else if ([why hasPrefix:@"no review"] || [why hasPrefix:@"the last review"] || [why hasPrefix:@"changed since"] || [why hasPrefix:@"not in the last"])
        next = @" The next review looks again.";
    if (!why.length) why = @"nothing decided yet";
    c.statusWord = @"Stays.";
    c.statusText = [MMSentence(MMCut(why, 150)) stringByAppendingString:next];
}

static NSString *DiskWords(MMWFTree *t) {
    if (!t.sized) return @"still measuring";
    NSString *freed = [NSString stringWithFormat:@"%@ freed", MMBytes(Frees(t))];
    // DESIGN.md: du's figure only beside the freed one, when it says more.
    if (t.diskBytes > Frees(t) + (Frees(t) >> 3) && t.diskBytes - Frees(t) > (8ull << 20)) freed = [freed stringByAppendingFormat:@", %@ on disk", MMBytes(t.diskBytes)];
    else if (t.cacheBytes > (1ull << 20)) freed = [freed stringByAppendingFormat:@", %@ of it caches", MMBytes(t.cacheBytes)];
    return freed;
}

MMCardSpec *MMWFCard(MMWFTree *t, MMWFView *v) {
    MMCardSpec *c = [MMCardSpec new];
    NSDictionary *verdict = v.verdicts[t.findingID];
    NSString *category = MMWFCategory(t, Str(verdict[@"word"]));
    NSString *about = Str(verdict[@"about"]);
    NSString *title = about.length > 12 ? about : t.isMain ? [NSString stringWithFormat:@"The main checkout of %@", t.repoName]
                    : [NSString stringWithFormat:@"The %@ worktree of %@", RowName(t, Prefixes(v.trees)), t.repoName];
    c.title = MMCut(MMCapitalized(title), 120);
    Status(t, v, c, category);

    NSMutableArray *facts = [NSMutableArray new];
    [facts addObject:[MMCardFact label:@"Branch" value:t.branch ?: @"a detached commit"]];
    NSString *last = t.lastWork ? [NSString stringWithFormat:@"%@ ago", MMDuration(t.quiet)] : @"";
    NSDictionary *s = t.session;
    if (s && last.length) {
        NSString *st = Str(s[@"title"]);
        last = [last stringByAppendingFormat:@" · %@%@", MMWFAgentName(Str(s[@"agent"])), st.length ? [NSString stringWithFormat:@" “%@”", MMCut(st, 40)] : @""];
    }
    [facts addObject:[MMCardFact label:@"Last work" value:last]];
    [facts addObject:[MMCardFact label:@"Disk" value:DiskWords(t)]];
    [facts addObject:[MMCardFact label:@"Git" value:MMWFStateWords(t)]];
    NSArray *links = v.links[t.findingID];
    if (links.count) {
        NSDictionary *l = links.firstObject;
        MMCardFact *f = [MMCardFact label:Str(l[@"label"]) ?: @"Server" value:Str(l[@"value"]) ?: @""];
        f.linkExpert = Str(l[@"expert"]); f.linkFindingID = Str(l[@"findingID"]);
        [facts addObject:f];
    } else if (t.processes.count) {
        [facts addObject:[MMCardFact label:@"Running" value:[[NSOrderedSet orderedSetWithArray:t.processes].array componentsJoinedByString:@", "]]];
    }
    NSMutableArray *shown = [NSMutableArray new];
    for (MMCardFact *f in facts) if (f.value.length) [shown addObject:f];
    c.facts = shown;

    NSString *reason = Str(verdict[@"reason"]);
    if (reason.length && [@[@"model", @"judge"] containsObject:Str(verdict[@"decidedBy"]) ?: @""]) {
        c.noteBy = [NSString stringWithFormat:@"%@ says %@%@", v.model.length ? v.model : @"The review", Str(verdict[@"word"]) ?: @"unsure",
                    [verdict[@"judged"] boolValue] ? @" after the judge" : @""];
        c.note = MMSentence(reason);
    }
    NSString *by = nil, *note = nil;   // what the person asked for wins over the review's note
    if (MMInvestigateNote(v.investigations[t.findingID], &by, &note)) { c.noteBy = by; c.note = note; }

    NSMutableArray *actions = [NSMutableArray new];
    [actions addObject:Action(v, @"Open in Finder", nil, @"reveal", t.findingID)];
    [actions addObject:Action(v, @"Open in Terminal", nil, @"terminal", t.findingID)];
    if (!t.isMain && !t.missing) {
        NSDate *kept = v.keptUntil[t.findingID];
        [actions addObject:Action(v, kept ? [NSString stringWithFormat:@"Kept for %@ More", MMShortDuration(kept.timeIntervalSinceNow)] : @"Keep for a Week",
                                  nil, @"keep", t.findingID)];
        MMActionSpec *rm = Action(v, @"Remove…", nil, @"remove", t.findingID);
        NSString *keep = MMWFWorkKeeps(t);
        if (keep) rm.disabledReason = MMCut(keep, 40);
        [actions addObject:rm];
    }
    if (!t.missing) {
        NSDictionary *run = v.investigations[t.findingID];
        MMActionSpec *inv = Action(v, @"Investigate…", MMInvestigateTail(run), @"investigate", t.findingID);
        inv.disabledReason = MMInvestigateDisabledReason(run);
        [actions addObject:inv];
    }
    [actions addObject:Action(v, @"Copy Path", nil, @"copy-path", t.findingID)];
    // Protect toggles the path on the protect list. A long-lived branch is kept by protect.branches instead.
    if (!t.isMain && !t.isProtected)
        [actions addObject:Action(v, [v.protectedPaths containsObject:t.findingID] ? @"Unprotect" : @"Protect", nil, @"protect", t.findingID)];
    c.actions = actions;
    return c;
}

NSString *MMWFBadge(MMWFView *v) { return v.candidates.count ? [NSString stringWithFormat:@"%lu", (unsigned long)MIN(v.candidates.count, (NSUInteger)999)] : nil; }

NSString *MMWFAccessibilityState(MMWFView *v) {
    if (v.candidates.count) return [MMPlural(v.candidates.count, @"worktree") stringByAppendingString:@" to clean up"];
    NSInteger n = 0;
    for (MMWFTree *t in v.trees) if (!t.isMain) n++;
    return n ? MMPlural(n, @"worktree") : @"no worktrees";
}
