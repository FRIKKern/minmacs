// Noo-Noo on the shared core. Issues #28, #29 and #30.
// Findings come from MMFacts only: the clutter items Know's catalog found, the worktrees and their git facts, and the
// sessions. Finished projects come first: build output whose worktree is merged, lost its remote branch or is gone.
// Every action runs through MMRunAction with MMClutterAction, which checks fresh, writes the undo record first,
// and moves to the Trash or runs the tool's own command after a recovery copy. Nothing is deleted for good.
// Ported from Noo-Noo 0.7: the dev, caches and leaks modules, the trend and cache velocity math, and its CLI verbs.
#import <AppKit/AppKit.h>
#import "Experts/NooNoo/MMNooNoo.h"
#import "CLI/MMArgs.h"
#import "UI/MMFormat.h"

static NSString *const kExpert = @"noonoo";
static NSString *const kKind = @"clutter";
static const NSTimeInterval kKeepFor = 7 * 86400;

static dispatch_queue_t ActQueue(void) { return MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED); }

#pragma mark - Words

static NSString *MergeWord(MMMergeKind k) {
    switch (k) {
        case MMMergedNone: return nil;
        case MMMergedSquash: case MMMergedPatch: return @"squash-merged";
        case MMMergedPR: return @"merged through a pull request";
        default: return @"merged";
    }
}

/// How finished an owner is, for the order "Finished projects first": merged, then remote branch deleted,
/// then gone, then an agent session that ended. 0 while it is active.
static NSInteger FinishedRank(NSString *state) {
    if (!state.length) return 0;
    NSArray *order = @[@"agent session ended", @"gone", @"worktree gone", @"remote branch deleted", @"merged through a pull request", @"squash-merged", @"merged"];
    NSUInteger i = [order indexOfObject:state];
    return i == NSNotFound ? 1 : (NSInteger)i + 1;
}

static NSString *Tilde(NSString *p) { return p.stringByAbbreviatingWithTildeInPath; }

static BOOL Within(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

static NSString *SectionName(MMNNSection s) { return @[@"finished", @"leftovers", @"caches", @"kept"][s]; }

#pragma mark - The expert

@interface MMNNPolicyObject : NSObject <MMExpertPolicy>
@end

@interface MMNNOwnerRule : NSObject <MMRule>
@end

@implementation MMNooNooExpert {
    MMVerdictWords *_words;
    NSDictionary *_keeps;               // stableKey to until, read once per rebuild when the file changed
    NSDate *_keepsMtime;
    NSArray<MMUndoRecord *> *_undo;     // the restorable records, read at most once a minute on the graph queue
    NSDate *_undoRead, *_reviewRead;
    BOOL _hooked;
    NSDate *_actedOn;
    double _growthMin;
}

+ (instancetype)shared {
    static MMNooNooExpert *e; static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [MMNooNooExpert new]; });
    return e;
}

- (instancetype)init {
    if ((self = [super init])) {
        _words = [MMVerdictWords keep:@"keep" go:@"clean" unsure:@"unsure"];
        _catalog = MMClutterCatalog.shared;
    }
    return self;
}

- (NSString *)expertID { return kExpert; }
- (NSString *)name { return @"Noo-Noo"; }
- (NSString *)symbol { return @"trash.square"; }
- (NSString *)legacyName { return @"noo-noo"; }
- (MMVerdictWords *)words { return _words; }
- (id<MMExpertPolicy>)policy { return MMNNPolicy(); }

#pragma mark Owners

/// The worktree that holds path, deepest first, from the facts.
static MMWorktree *TreeOf(NSString *path, MMFacts *facts) {
    MMWorktree *best = nil;
    for (MMWorktree *w in facts.worktrees) if (Within(path, w.path) && w.path.length > best.path.length) best = w;
    return best;
}

/// The working agent session inside folder, from the facts, or nil.
static MMSession *AgentIn(NSString *folder, MMFacts *facts) {
    if (!folder.length) return nil;
    for (MMSession *s in facts.sessions) if (s.stillWorking && (Within(s.cwd, folder) || Within(folder, s.cwd))) return s;
    return nil;
}

/// What the owner's state says about build output: merged, its remote branch deleted, gone, or its agent session ended.
static NSString *OwnerState(MMClutterItem *i, MMFacts *facts, MMWorktree **treeOut) {
    if (i.ownerGone) return @"gone";
    NSString *owner = i.ownerPath ?: i.path;
    MMWorktree *w = TreeOf(owner, facts);
    if (treeOut) *treeOut = w;
    if (!w) return nil;
    if (w.missing) return @"worktree gone";
    MMGitFacts *g = [facts gitFor:w];
    NSString *merged = g ? MergeWord(g.merged) : nil;
    if (merged && !w.isMain) return merged;
    if (g.upstreamGone && !w.isMain) return @"remote branch deleted";
    if (w.maker == MMMakerClaudeCode && w.makerSession.length) {
        BOOL live = NO;
        for (MMSession *s in facts.sessions) if ([s.sessionID isEqualToString:w.makerSession] && (s.pid > 0 || s.stillWorking)) live = YES;
        if (!live) return @"agent session ended";
    }
    return nil;
}

static MMNNSection SectionOf(MMClutterItem *i, NSString *ownerState) {
    if (i.state != MMClutterFree) return MMNNKept;
    if (i.kind.klass == MMClutterBuild && ownerState.length) return MMNNFinished;
    if (i.kind.klass == MMClutterLeak || i.ownerGone) return MMNNLeftovers;
    return MMNNCaches;
}

static NSString *RowName(MMClutterItem *i) {
    if (i.kind.names.count) return i.path.lastPathComponent;
    if ([i.kind.signature isEqualToString:@"family"]) return [NSString stringWithFormat:@"%@ folders", i.path.lastPathComponent];
    return i.kind.title;
}

/// For a row whose paths end in a wildcard, the part the wildcard matched, so two items of one row read apart:
/// a session id cut to 8 characters, a project folder, a browser revision.
static NSString *WildPart(MMClutterItem *i) {
    if (i.kind.names.count || [i.kind.signature isEqualToString:@"family"]) return nil;
    BOOL wild = NO;
    NSString *last = i.path.lastPathComponent;
    for (NSString *p in i.kind.paths) {
        if ([p.lastPathComponent isEqualToString:last]) return nil;   // a literal path of the row, such as _cacache
        if ([p.lastPathComponent rangeOfString:@"*"].location != NSNotFound) wild = YES;
    }
    if (!wild) return nil;
    if (last.length == 36 && [[NSUUID alloc] initWithUUIDString:last]) return [@"session " stringByAppendingString:[last substringToIndex:8]];
    return last;
}

#pragma mark Findings

/// Timed keeps, read from the keeps file only when it changed.
- (NSDictionary *)keepsNow {
    NSString *path = [MMExpertDir(kExpert) stringByAppendingPathComponent:@"keeps.json"];
    NSDate *m = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    @synchronized (self) {
        if (_keeps && ((!m && !_keepsMtime) || [m isEqualToDate:_keepsMtime])) return _keeps;
    }
    NSData *d = m ? [NSData dataWithContentsOfFile:path] : nil;
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSDictionary *k = [j isKindOfClass:NSDictionary.class] ? j : @{};
    @synchronized (self) { _keeps = k; _keepsMtime = m; }
    return k;
}

- (void)forgetUndo { @synchronized (self) { _undoRead = nil; } }

/// The records Undo can take back, newest first. Read on the graph queue, at most once a minute.
- (NSArray<MMUndoRecord *> *)undoNow {
    @synchronized (self) { if (_undoRead && -_undoRead.timeIntervalSinceNow < 60) return _undo ?: @[]; }
    NSMutableArray *out = [NSMutableArray new];
    for (MMUndoRecord *r in [MMUndo.shared recent:kExpert limit:50]) if (r.state == MMUndoDone && r.canRestore) [out addObject:r];
    @synchronized (self) { _undo = out; _undoRead = NSDate.date; }
    return out;
}

/// The broker saves each review to the log. The graph carries the newest one, so menus read it without a query.
- (void)syncReview {
    @synchronized (self) { if (_reviewRead && -_reviewRead.timeIntervalSinceNow < 60) return; _reviewRead = NSDate.date; }
    MMReview *r = [MMReview lastFor:kExpert];
    if (r) [MMGraph.shared saveReview:r forExpert:kExpert];
}

static BOOL InApp(void) { return NSBundle.mainBundle.bundleIdentifier.length > 0 && !NSProcessInfo.processInfo.environment[@"MINMACS_HOME"]; }

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSDictionary *keeps = [self keepsNow];
    double now = NSDate.date.timeIntervalSince1970;
    MMMode mode = MMModeFor(kExpert);
    BOOL watched = MMWatchedLongEnough(kExpert);
    @synchronized (self) { _growthMin = MMPrefDouble(@"noonoo.growthMinBytes", 1024.0 * 1024 * 1024); }
    (void)[self undoNow];
    NSMutableArray *rows = [NSMutableArray new];
    for (MMClutterItem *i in facts.clutter) {
        MMWorktree *tree = nil;
        NSString *ownerState = i.kind.klass == MMClutterBuild || i.ownerGone ? OwnerState(i, facts, &tree) : nil;
        if (!tree && i.ownerPath) tree = TreeOf(i.ownerPath, facts);
        [rows addObject:@[i, ownerState ?: @"", tree ?: NSNull.null]];
    }
    // Finished projects first, the most finished first, then by what deleting frees.
    [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSInteger ra = FinishedRank(a[1]), rb = FinishedRank(b[1]);
        if (ra != rb) return ra > rb ? NSOrderedAscending : NSOrderedDescending;
        MMClutterItem *x = a[0], *y = b[0];
        if (x.size.freedIfDeleted != y.size.freedIfDeleted) return x.size.freedIfDeleted > y.size.freedIfDeleted ? NSOrderedAscending : NSOrderedDescending;
        return [x.key compare:y.key];
    }];
    NSMutableArray *out = [NSMutableArray new];
    for (NSArray *row in rows) {
        MMClutterItem *i = row[0];
        NSString *ownerState = [row[1] length] ? row[1] : nil;
        MMWorktree *tree = row[2] == NSNull.null ? nil : row[2];
        MMClutterKind *k = i.kind;
        MMNNSection section = SectionOf(i, ownerState);
        NSMutableArray *keep = [NSMutableArray new];
        if (i.state != MMClutterFree) [keep addObject:i.why ?: @"it is in use"];
        MMSession *agent = AgentIn(i.ownerPath ?: tree.path, facts);
        if (agent) [keep addObject:[NSString stringWithFormat:@"an agent works in %@", (i.ownerPath ?: tree.path).lastPathComponent]];
        double until = [keeps[i.key] doubleValue];
        if (until > now) [keep addObject:[NSString stringWithFormat:@"kept by you until %@", [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:until] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle]]];
        if (keep.count && section != MMNNKept) section = MMNNKept;
        MMProposal *proposal = nil;
        if (!k.reportOnly) {
            proposal = k.klass == MMClutterTool
                ? [MMProposal verb:@"clean" title:[@"Clean with " stringByAppendingString:k.cleanupArgs.firstObject] reversibility:MMReversibleToolCommand]
                : [MMProposal verb:@"remove" title:@"Move to Trash" reversibility:MMReversibleTrash];
        }
        BOOL goes = proposal && !keep.count && watched && mode != MMModeIdle && k.klass != MMClutterTool &&
                    (section == MMNNFinished || section == MMNNLeftovers || (mode == MMModeEager && k.klass == MMClutterCache));
        MMClutterTrend t = i.trend;
        NSMutableDictionary *fx = [@{@"kindID": k.kindID, @"kindTitle": k.title, @"class": MMClutterClassName(k.klass), @"path": i.path,
                                     @"members": @(i.members.count), @"state": i.state == MMClutterFree ? @"free" : i.state == MMClutterLive ? @"live" : @"kept",
                                     @"section": SectionName(section), @"allocated": @(i.size.allocated), @"freed": @(i.size.freedIfDeleted),
                                     @"name": RowName(i), @"goes": @(goes), @"reportOnly": @(k.reportOnly), @"folder": @(k.names.count > 0),
                                     @"trend": @{@"ok": @(t.ok), @"bytesPerDay": @(t.bytesPerDay), @"windowDays": @(t.windowDays),
                                                 @"firstBytes": @(t.firstBytes), @"lastBytes": @(t.lastBytes), @"weekRatio": @(t.weekRatio)}} mutableCopy];
        if (i.why) fx[@"why"] = i.why;
        if (keep.count) fx[@"keep"] = keep.firstObject;
        if (ownerState) fx[@"ownerState"] = ownerState;
        if (i.ownerPath) fx[@"ownerPath"] = i.ownerPath;
        NSString *ownerName = i.ownerPath.lastPathComponent ?: tree.path.lastPathComponent ?: WildPart(i);
        if (ownerName.length) fx[@"owner"] = ownerName;
        if (tree.path) fx[@"worktree"] = tree.path;
        if (i.lastUsed) fx[@"lastUsed"] = @(i.lastUsed.timeIntervalSince1970);
        if (k.rebuild) fx[@"rebuild"] = k.rebuild;
        if (k.cleanup) fx[@"cleanup"] = k.cleanup;
        if (k.ownerSetting) fx[@"ownerSetting"] = k.ownerSetting;
        if (i.sessionID) fx[@"sessionID"] = i.sessionID;
        [out addObject:[MMFinding expert:kExpert kind:kKind stableKey:i.key build:^(MMFindingBuilder *b) {
            b.instanceKey = i.key;
            b.title = ownerName.length && k.names.count ? [NSString stringWithFormat:@"%@ in %@", RowName(i), ownerName] : RowName(i);
            b.path = [k.signature isEqualToString:@"family"] ? i.path.stringByDeletingLastPathComponent : i.path;
            b.ownerPath = i.ownerPath ?: tree.path;
            b.cost = (MMCost){ .cpuPercent = -1, .diskFreed = i.size.freedIfDeleted, .diskAllocated = i.size.allocated };
            NSMutableArray *ev = [NSMutableArray arrayWithObject:[MMEvidence label:@"Size" value:MMBytes(i.size.freedIfDeleted) raw:@(i.size.freedIfDeleted)]];
            if (i.lastUsed) [ev addObject:[MMEvidence label:@"Last used" value:MMAgo(i.lastUsed) raw:i.lastUsed]];
            if (ownerState) [ev addObject:[MMEvidence label:@"Owner" value:ownerState raw:ownerState
                                                linkExpert:@"workforest" findingID:tree.path ? [@"workforest:worktree:" stringByAppendingString:Tilde(tree.path)] : nil]];
            b.evidence = ev;
            b.keepReasons = keep;
            b.proposal = proposal;
            b.facts = fx;
            // What must change for the review to look again: the state, the owner and a size bucket of 256 MB.
            b.fingerprint = [NSString stringWithFormat:@"%@|%@|%@|%llu", k.kindID, fx[@"state"], ownerState ?: @"", i.size.freedIfDeleted >> 28];
        }]];
    }
    if (InApp()) {
        [self syncReview];
        BOOL hook = NO;
        @synchronized (self) { if (!_hooked) { _hooked = YES; hook = YES; } }
        if (hook) dispatch_async(dispatch_get_main_queue(), ^{ [MMGraph.shared observe:^(MMSnapshot *s) { [self watch:s]; }]; });
    }
    return out;
}

- (MMClutterItem *)itemFor:(MMFinding *)f facts:(MMFacts *)facts {
    for (MMClutterItem *i in facts.clutter ?: self.catalog.items) if ([i.key isEqualToString:f.stableKey]) return i;
    return nil;
}

#pragma mark Actions

- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step {
    if (![f.expert isEqualToString:kExpert] || !f.proposal || step != MMStopTerm) return nil;
    MMClutterItem *i = [self itemFor:f facts:nil];
    return i ? [MMClutterAction actionFor:f item:i catalog:self.catalog] : nil;
}

/// Wrap Up, issue #27: one part per cache or build folder the worktree owns, by back-link or by place, that goes to
/// the Trash. A tool's own cleanup is for the whole Mac, not one workstream, so it is never a part.
- (NSArray<MMWrapUpPart *> *)wrapUpParts:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    NSMutableArray *parts = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) {
        if (!f.proposal || f.proposal.reversibility != MMReversibleTrash) continue;
        if (![subject holds:f.ownerPath] && ![subject holds:f.path]) continue;
        id<MMAction> a = [self actionFor:f step:MMStopTerm];
        NSString *title = [NSString stringWithFormat:@"Move %@ to the Trash", f.facts[@"name"] ?: f.title];
        MMWrapUpPart *p = a ? [MMWrapUpPart step:MMWrapUpCaches expert:kExpert title:title action:a policy:self.policy] : nil;
        if (p) [parts addObject:p];
    }
    return parts;
}

/// Runs block off main and waits. On main the run loop keeps turning, so AppKit callbacks still arrive.
static void RunOffMain(dispatch_block_t block) {
    if (!NSThread.isMainThread) { block(); return; }
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_async(g, ActQueue(), block);
    while (dispatch_group_wait(g, DISPATCH_TIME_NOW) != 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

- (MMUndoRecord *)clean:(MMFinding *)f by:(NSString *)by error:(NSString **)error {
    id<MMAction> a = [self actionFor:f step:MMStopTerm];
    if (!a) { if (error) *error = f.proposal ? @"it is gone from the last scan" : @"Noo-Noo only reports it"; return nil; }
    __block MMUndoRecord *r = nil;
    __block NSString *err = nil;
    RunOffMain(^{ r = MMRunAction(a, self.policy, nil, by, [@"asked from the " stringByAppendingString:[by isEqualToString:@"cli"] ? @"CLI" : @"menu"], &err); });
    [self forgetUndo];
    if (error) *error = err ?: (r.state == MMUndoFailed ? r.error : nil);
    return r;
}

- (MMFinding *)findingWithID:(NSString *)fid {
    return [MMGraph.shared.latest finding:fid] ?: [[self snapshotNow] finding:fid];
}

/// Menu actions: run off main, then rebuild the graph. A failure the person should see goes in an alert.
- (void)menuClean:(NSArray<NSString *> *)ids {
    MMSnapshot *s = MMGraph.shared.current;
    NSMutableArray *fs = [NSMutableArray new];
    for (NSString *fid in ids) { MMFinding *f = [s finding:fid]; if (f) [fs addObject:f]; }
    dispatch_async(ActQueue(), ^{
        NSMutableArray *problems = [NSMutableArray new];
        for (MMFinding *f in fs) {
            NSString *err = nil;
            MMUndoRecord *r = [self clean:f by:@"manual" error:&err];
            if (!r || r.state == MMUndoFailed) [problems addObject:[NSString stringWithFormat:@"%@: %@", f.title, err ?: @"it failed"]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [MMGraph.shared rebuild:@"noonoo.action"];
            if (!problems.count || !NSApp) return;
            NSAlert *alert = [NSAlert new];
            alert.messageText = problems.count == 1 ? @"Noo-Noo Could Not Clean It" : [NSString stringWithFormat:@"Noo-Noo Could Not Clean %lu Items", (unsigned long)problems.count];
            alert.informativeText = [problems componentsJoinedByString:@"\n"];
            [alert runModal];
        });
    });
}

- (void)keepForAWeek:(NSString *)fid {
    MMFinding *f = [MMGraph.shared.current finding:fid];
    if (!f) return;
    NSString *key = f.stableKey;
    dispatch_async(ActQueue(), ^{
        // Core's timed keep, in <noonoo>/keeps.json, which findingsFrom reads once per rebuild when it changed.
        [MMKeep keep:key expert:kExpert until:[NSDate dateWithTimeIntervalSinceNow:kKeepFor]];
        [MMGraph.shared rebuild:@"noonoo.keep"];
    });
}

- (MMNNHandlers *)handlers {
    MMNNHandlers *h = [MMNNHandlers new];
    __weak MMNooNooExpert *me = self;
    h.clean = ^(NSArray<NSString *> *ids) { [me menuClean:ids]; };
    h.keep = ^(NSString *fid) { [me keepForAWeek:fid]; };
    h.reveal = ^(NSString *fid) {
        MMFinding *f = [MMGraph.shared.current finding:fid];
        NSString *p = f.facts[@"path"];
        if ([p hasSuffix:@"*"]) p = p.stringByDeletingLastPathComponent;
        if (p.length) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:p]]];
    };
    h.restoreLast = ^{
        dispatch_async(ActQueue(), ^{
            MMUndoRecord *last = [me undoNow].firstObject;
            if (last) (void)[MMUndo.shared restore:last.rid];
            [me forgetUndo];
            [MMGraph.shared rebuild:@"noonoo.undo"];
        });
    };
    h.scanNow = ^{
        MMClutterCatalog *c = me.catalog;
        dispatch_async(MMQueue(@"core", @"clutter", QOS_CLASS_UTILITY), ^{ [c forgetScanTimes]; [c scanDue]; });
    };
    return h;
}

#pragma mark The app: the mode after a review

/// Main thread, once per snapshot. A new review: the mode's plan runs on fresh facts, through MMRunAction,
/// and one notification says what it did.
- (void)watch:(MMSnapshot *)s {
    MMReview *r = [s reviewFor:kExpert];
    if (!r.at || (_actedOn && [r.at compare:_actedOn] != NSOrderedDescending)) return;
    _actedOn = r.at;
    MMMode mode = MMModeFor(kExpert);
    if (mode == MMModeIdle || r.error.length) return;
    NSArray *findings = [s findingsFor:kExpert];
    MMFacts *facts = s.facts;
    dispatch_async(ActQueue(), ^{
        NSMutableArray *done = [NSMutableArray new];
        uint64_t freed = 0;
        NSString *lastRid = nil;
        for (MMPlanEntry *e in MMPlan(findings, facts, r, mode, self.policy)) {
            if (!e.act) continue;
            id<MMAction> a = [self actionFor:e.finding step:MMStopTerm];
            NSString *err = nil;
            MMUndoRecord *rec = a ? MMRunAction(a, self.policy, r, MMModeName(mode), e.why, &err) : nil;
            if (rec.state != MMUndoDone) continue;
            [done addObject:e.finding.title];
            freed += e.finding.cost.diskFreed;
            lastRid = rec.rid;
        }
        [self forgetUndo];
        if (!done.count) return;
        NSString *title = [NSString stringWithFormat:@"Moved %@ to the Trash", MMPlural((NSInteger)done.count, @"Item").capitalizedString];
        NSString *body = [NSString stringWithFormat:@"%@ moved %@ to the Trash, about %@. Undo moves %@ back.",
                          MMCapitalized(MMModeName(mode)), [done componentsJoinedByString:@", "], MMBytes(freed), done.count == 1 ? @"it" : @"the last one"];
        MMNotify(kExpert, title, body, lastRid);
        [MMGraph.shared rebuild:@"noonoo.mode"];
    });
}

#pragma mark Review

- (NSDictionary *)reviewFactsFor:(MMFinding *)f {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NSString *k in @[@"kindID", @"class", @"section", @"state", @"ownerState", @"members"]) if (f.facts[k]) d[k] = f.facts[k];
    d[@"freedMB"] = @(f.cost.diskFreed >> 20);
    if (f.facts[@"lastUsed"]) d[@"idleDays"] = @(floor((NSDate.date.timeIntervalSince1970 - [f.facts[@"lastUsed"] doubleValue]) / 86400));
    if (f.facts[@"why"]) d[@"why"] = MMClip(f.facts[@"why"], 120);
    return d;
}

- (NSArray<id<MMRule>> *)rules { return @[[MMNNOwnerRule new]]; }

- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s {
    NSMutableArray *fs = [NSMutableArray new];
    for (MMFinding *f in [s findingsFor:kExpert]) if (f.proposal) [fs addObject:f];
    if (!fs.count) return nil;
    MMReviewRequest *r = [MMReviewRequest new];
    r.expert = kExpert; r.trigger = trigger; r.model = MMPrefString(MMReviewModelKey, @"auto");
    r.findings = fs; r.facts = s.facts; r.words = self.words; r.mode = MMModeFor(kExpert);
    r.system = @"You review developer clutter on a Mac: caches, build output and leftovers. Each item names its row, "
               @"its owner's state and what deleting frees. Say clean only for an item nothing needs now. Say keep when anything suggests it is in use.";
    __weak MMNooNooExpert *me = self;
    r.factsFor = ^NSDictionary *(MMFinding *f) { return [me reviewFactsFor:f]; };
    return r;
}

#pragma mark Snapshots

- (MMSnapshot *)snapshotNow {
    MMSnapshot *s = MMGraph.shared.latest;
    if (s) return s;
    id<MMFactSource> src = MMGraph.shared.source;
    MMFacts *facts = src ? [src factsFor:1] : nil;
    if (!facts) facts = [MMFacts generation:1 sample:nil power:nil agents:@[] sessions:MMSessions.shared.all ?: @[] worktrees:@[]
                                    clutter:self.catalog.items git:@{}];
    MMReview *r = [MMReview lastFor:kExpert];
    return [MMSnapshot snapshotFrom:facts experts:@[self] reviews:r ? @{kExpert: r} : @{} holds:nil];
}

#pragma mark Menu

- (MMNNRow *)rowFor:(MMFinding *)f {
    NSDictionary *x = f.facts;
    MMNNRow *r = [MMNNRow new];
    r.findingID = f.findingID; r.kindID = x[@"kindID"]; r.name = x[@"name"]; r.kindTitle = x[@"kindTitle"];
    r.owner = x[@"owner"]; r.ownerState = x[@"ownerState"]; r.path = Tilde(x[@"path"]);
    NSUInteger s = [@[@"finished", @"leftovers", @"caches", @"kept"] indexOfObject:x[@"section"] ?: @""];
    r.section = s == NSNotFound ? MMNNKept : (MMNNSection)s;
    r.freed = f.cost.diskFreed; r.allocated = f.cost.diskAllocated;
    if ([x[@"lastUsed"] doubleValue] > 0) r.lastUsed = [NSDate dateWithTimeIntervalSince1970:[x[@"lastUsed"] doubleValue]];
    r.live = [x[@"state"] isEqual:@"live"] || (f.keepReasons.count && ![x[@"reportOnly"] boolValue] && [x[@"state"] isEqual:@"free"]);
    r.kept = [x[@"reportOnly"] boolValue] || [x[@"state"] isEqual:@"kept"];
    r.why = f.keepReasons.firstObject ?: x[@"why"];
    r.rebuild = x[@"rebuild"]; r.ownerSetting = x[@"ownerSetting"];
    r.actionTitle = f.proposal.title;
    r.undoWords = f.proposal.reversibility == MMReversibleToolCommand ? @"A recovery copy is made first, and Undo copies back what the tool removed."
                                                                       : @"It goes to the Trash, and Undo moves it back.";
    r.goesOnItsOwn = [x[@"goes"] boolValue];
    r.members = [x[@"members"] integerValue];
    r.folder = [x[@"folder"] boolValue];
    if (x[@"worktree"] && x[@"ownerState"]) { r.ownerLinkExpert = @"workforest"; r.ownerLinkID = [@"workforest:worktree:" stringByAppendingString:Tilde(x[@"worktree"])]; }
    return r;
}

- (MMNNView *)viewFor:(MMSnapshot *)s {
    MMNNView *v = [MMNNView new];
    NSMutableArray *rows = [NSMutableArray new];
    NSString *growth = nil;
    double best = 0, minBytes;
    @synchronized (self) { minBytes = _growthMin > 0 ? _growthMin : 1024.0 * 1024 * 1024; }
    NSMutableSet *seenKinds = [NSMutableSet new];
    for (MMFinding *f in [s findingsFor:kExpert]) {
        NSDictionary *x = f.facts;
        if ([x[@"kindID"] isEqual:@"trash"]) { v.trashBytes += [x[@"allocated"] unsignedLongLongValue]; continue; }
        [rows addObject:[self rowFor:f]];
        NSDictionary *t = x[@"trend"];
        if (![seenKinds containsObject:x[@"kindID"]]) {
            [seenKinds addObject:x[@"kindID"]];
            NSString *line = MMNNGrowthLine(x[@"kindTitle"], [t[@"ok"] boolValue], [t[@"bytesPerDay"] doubleValue], [t[@"windowDays"] integerValue],
                                            [t[@"firstBytes"] doubleValue], [t[@"lastBytes"] doubleValue], [t[@"weekRatio"] doubleValue], minBytes);
            if (line && [t[@"bytesPerDay"] doubleValue] > best) { best = [t[@"bytesPerDay"] doubleValue]; growth = line; }
        }
    }
    v.rows = rows;
    v.growthLine = growth;
    MMMode mode = MMModeFor(kExpert);
    v.modeName = MMCapitalized(MMModeName(mode));
    v.watchingLeft = mode == MMModeIdle ? 0 : MMWatchingLeft(kExpert);
    NSArray *undo;
    @synchronized (self) { undo = _undo; }
    v.restorable = (NSInteger)undo.count;
    v.lastClean = ((MMUndoRecord *)undo.firstObject).at;
    v.lastScan = self.catalog.lastScan;
    return v;
}

- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return MMNNMenuFor([self viewFor:s], [self handlers]); }

- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s {
    if (![f.expert isEqualToString:kExpert]) return nil;
    return MMNNCardFor([self rowFor:f], nil, [self handlers]);
}

- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return MMNNAccessibility([self viewFor:s]); }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return [s findingsFor:kExpert].count == 0; }

#pragma mark Verbs

/// The findings a target names: a finding id, an item path, or a row id. --finished and --leftovers take a section.
- (NSArray<MMFinding *> *)targets:(NSArray<NSString *> *)words args:(MMArgs *)a in:(MMSnapshot *)s {
    NSMutableArray *out = [NSMutableArray new];
    NSArray *fs = [s findingsFor:kExpert];
    for (MMFinding *f in fs) {
        if ([a has:@"--finished"] && [f.facts[@"section"] isEqual:@"finished"] && f.proposal) { [out addObject:f]; continue; }
        if ([a has:@"--leftovers"] && [f.facts[@"section"] isEqual:@"leftovers"] && f.proposal) { [out addObject:f]; continue; }
        for (NSString *w in words) {
            NSString *p = [w hasPrefix:@"/"] || [w hasPrefix:@"~"] ? w.stringByExpandingTildeInPath : nil;
            NSString *fp = f.facts[@"path"];
            // A member of a temp family names the family: same folder, and the name starts with the family's prefix.
            BOOL member = p && [fp hasSuffix:@"*"] && [p.stringByDeletingLastPathComponent isEqualToString:fp.stringByDeletingLastPathComponent] &&
                          [p.lastPathComponent hasPrefix:[fp.lastPathComponent substringToIndex:fp.lastPathComponent.length - 1]];
            if ([f.findingID isEqualToString:w] || [f.stableKey isEqualToString:w] || [f.facts[@"kindID"] isEqual:w] || member ||
                (p && ([fp isEqual:p] || [fp.stringByResolvingSymlinksInPath isEqual:p.stringByResolvingSymlinksInPath]))) {
                [out addObject:f]; break;
            }
        }
    }
    return out;
}

static NSDictionary *ItemJSON(MMFinding *f) {
    NSMutableDictionary *j = [NSMutableDictionary new];
    for (NSString *k in @[@"kindID", @"class", @"section", @"state", @"path", @"owner", @"ownerState", @"why", @"keep", @"members", @"allocated", @"freed", @"lastUsed", @"trend"])
        if (f.facts[k]) j[k] = f.facts[k];
    j[@"id"] = f.findingID; j[@"title"] = f.title ?: @"";
    if (f.proposal) j[@"action"] = f.proposal.title;
    return j;
}

- (int)clutter:(MMArgs *)a {
    NSString *sub = [a word:0] ?: @"list";
    MMClutterCatalog *c = self.catalog;
    if ([sub isEqualToString:@"check"]) {
        NSString *p = [a word:1];
        if (!p.length) return [a usageError];
        p = [p hasPrefix:@"~"] ? p.stringByExpandingTildeInPath : p;
        NSString *why = [c whyNot:p kind:nil];
        MMClutterKind *k = [c kindFor:p];
        if (a.json) [a printJSON:@{@"path": p, @"allowed": @(why == nil), @"why": why ?: @"", @"kind": k.kindID ?: @""}];
        else [a print:@"%@", why ? [@"never: " stringByAppendingString:why] : [NSString stringWithFormat:@"may go: the %@ row lists it", k.title]];
        return why ? MMExitFailed : MMExitOK;
    }
    if ([sub isEqualToString:@"scan"]) {
        if (a.dryRun) { [a print:@"would scan every clutter row now"]; return MMExitOK; }
        [c forgetScanTimes];
        if (a.inApp && MMGraph.shared.latest) {
            dispatch_async(MMQueue(@"core", @"clutter", QOS_CLASS_UTILITY), ^{ [c scanDue]; });
            [a print:@"Noo-Noo started a scan of every row"];
            return MMExitOK;
        }
        [c scanDue];
        if (a.json) [a printJSON:@{@"items": @(c.items.count)}];
        else [a print:@"Noo-Noo scanned every row and found %@", MMPlural((NSInteger)c.items.count, @"item")];
        return MMExitOK;
    }
    MMSnapshot *s = [self snapshotNow];
    NSArray<MMFinding *> *fs = [s findingsFor:kExpert];
    if ([sub isEqualToString:@"trends"]) {
        NSMutableArray *out = [NSMutableArray new];
        NSMutableSet *seen = [NSMutableSet new];
        for (MMFinding *f in fs) {
            NSDictionary *t = f.facts[@"trend"];
            if ([seen containsObject:f.facts[@"kindID"]] || ![t[@"ok"] boolValue]) continue;
            [seen addObject:f.facts[@"kindID"]];
            [out addObject:@{@"kindID": f.facts[@"kindID"], @"title": f.facts[@"kindTitle"], @"trend": t}];
        }
        MMNNView *v = [self viewFor:s];
        if (a.json) { [a printJSON:@{@"trends": out, @"growthLine": v.growthLine ?: @""}]; return MMExitOK; }
        if (v.growthLine) [a print:@"%@", v.growthLine];
        for (NSDictionary *x in out) {
            NSDictionary *t = x[@"trend"];
            double rate = [t[@"bytesPerDay"] doubleValue];
            [a print:@"  %-28@ %@%@ a day over %@, now %@", MMCut(x[@"title"], 28), rate < 0 ? @"-" : @"+", MMBytes((uint64_t)fabs(rate)),
                     MMPlural([t[@"windowDays"] integerValue], @"day"), MMBytes((uint64_t)[t[@"lastBytes"] doubleValue])];
        }
        if (!out.count) [a print:@"Noo-Noo has fewer than two days of sizes for every row"];
        return MMExitOK;
    }
    if ([sub isEqualToString:@"show"]) {
        NSArray *ts = [self targets:[a.words subarrayWithRange:NSMakeRange(1, a.words.count - 1)] args:a in:s];
        if (!ts.count) { [a error:@"noonoo: nothing matches %@", [a word:1] ?: @""]; return MMExitFailed; }
        if (a.json) { NSMutableArray *j = [NSMutableArray new]; for (MMFinding *f in ts) [j addObject:ItemJSON(f)]; [a printJSON:j]; return MMExitOK; }
        for (MMFinding *f in ts) {
            MMCardSpec *card = [self cardFor:f snapshot:s];   // pure: the card reads only the finding
            [a print:@"%@", card.title];
            [a print:@"%@ %@", card.statusWord, card.statusText];
            for (MMCardFact *x in card.facts) [a print:@"  %-10@ %@", x.label, x.value];
        }
        return MMExitOK;
    }
    if (![sub isEqualToString:@"list"]) return [a usageError];
    MMNNView *v = [self viewFor:s];
    if (a.json) {
        NSMutableArray *items = [NSMutableArray new];
        for (MMFinding *f in fs) [items addObject:ItemJSON(f)];
        [a printJSON:@{@"expert": kExpert, @"items": items, @"growthLine": v.growthLine ?: @"", @"trashBytes": @(v.trashBytes)}];
        return MMExitOK;
    }
    MMMenuSpec *m = MMNNMenuFor(v, nil);
    [a print:@"Noo-Noo: %@ %@ · %@", m.headerBig, m.headerUnit, m.headerLine];
    if (m.summary.length) [a print:@"%@", m.summary];
    for (MMSectionSpec *sec in m.sections) {
        [a print:@"%@", sec.title];
        for (MMRowSpec *r in sec.rows) [a print:@"  %-24@ %@", MMCut(r.name, 24), [r.facts componentsJoinedByString:@" · "]];
    }
    return MMExitOK;
}

- (int)cleanVerb:(MMArgs *)a {
    if ([a has:@"--undo"]) {
        NSString *rid = [a word:0];
        NSArray *recs = [MMUndo.shared recent:kExpert limit:50];
        MMUndoRecord *r = nil;
        for (MMUndoRecord *x in recs) if ((rid && [x.rid isEqualToString:rid]) || (!rid && x.state == MMUndoDone && x.canRestore)) { r = x; break; }
        if (!r) { [a error:@"noonoo: no clean to undo"]; return MMExitFailed; }
        if (a.dryRun) { [a print:@"would undo %@, record %@", r.subject, r.rid]; return MMExitOK; }
        int need = [a needsApp];
        if (need) return need;
        __block NSString *problem = nil;
        RunOffMain(^{ problem = [MMUndo.shared restore:r.rid]; });
        [self forgetUndo];
        if (problem) { [a error:@"noonoo: %@: %@", r.subject, problem]; return MMExitFailed; }
        if (a.json) [a printJSON:@{@"rid": r.rid, @"restored": @YES}]; else [a print:@"Noo-Noo put back %@", r.subject];
        return MMExitOK;
    }
    MMSnapshot *s = [self snapshotNow];
    NSArray<MMFinding *> *ts = [self targets:a.words args:a in:s];
    if (!ts.count) {
        // A path no finding names still gets the walls' answer, so a refusal always says why.
        NSString *p = [a word:0];
        NSString *why = p.length ? [self.catalog whyNot:[p hasPrefix:@"~"] ? p.stringByExpandingTildeInPath : p kind:nil] : nil;
        [a error:@"noonoo: nothing to clean matches %@%@", p ?: @"", why ? [@": " stringByAppendingString:why] : @""];
        return MMExitFailed;
    }
    if (a.dryRun) {
        NSMutableArray *j = [NSMutableArray new];
        for (MMFinding *f in ts) {
            id<MMAction> act = [self actionFor:f step:MMStopTerm];
            __block NSString *why = nil;
            RunOffMain(^{ why = act ? [act recheck] : @"Noo-Noo only reports it"; });
            NSString *keep = why ?: f.keepReasons.firstObject;
            NSString *line = keep ? [NSString stringWithFormat:@"keeps %@: %@", f.title, keep] : [act dryRun];
            [j addObject:@{@"id": f.findingID, @"would": line, @"ok": @(keep == nil)}];
            if (!a.json) [a print:@"%@", line];
        }
        if (a.json) [a printJSON:j];
        return MMExitOK;
    }
    int need = [a needsApp];
    if (need) return need;
    NSMutableArray *results = [NSMutableArray new];
    NSInteger bad = 0;
    for (MMFinding *f in ts) {
        NSString *err = nil;
        MMUndoRecord *r = [self clean:f by:@"cli" error:&err];
        BOOL ok = r && r.state == MMUndoDone;
        bad += !ok;
        [results addObject:@{@"id": f.findingID, @"ok": @(ok), @"rid": r.rid ?: @"", @"problem": err ?: @"", @"freedBytes": @(r.freedBytes)}];
        if (!a.json) [a print:@"%@", ok ? [NSString stringWithFormat:@"cleaned %@, undo with: minmacs clean --undo %@", f.title, r.rid]
                                        : [NSString stringWithFormat:@"%@: %@", f.title, err ?: @"it failed"]];
    }
    if (a.json) [a printJSON:results];
    [MMGraph.shared rebuild:@"noonoo.cli"];
    return bad ? MMExitFailed : MMExitOK;
}

- (NSArray<MMVerbSpec *> *)verbs {
    __weak MMNooNooExpert *me = self;
    return @[
        [MMVerbSpec verb:@"clutter" usage:@"clutter [list | show <id|path> | trends | check <path> | scan] [--json] [--dry-run]" mutates:NO
                     run:^int(MMArgs *a) { return [me clutter:a]; }],
        [MMVerbSpec verb:@"clean" usage:@"clean <id|path|row> ... | --finished | --leftovers | --undo [rid] [--json] [--dry-run]" mutates:YES
                     run:^int(MMArgs *a) { return [me cleanVerb:a]; }],
    ];
}

@end

#pragma mark - Policy

@implementation MMNNPolicyObject

/// On facts read now: the item is still listed and free, and no agent works in its project.
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    MMClutterItem *i = [MMNooNooExpert.shared itemFor:f facts:facts];
    if (!i) return @"it is gone from the last scan";
    if (i.state != MMClutterFree) return i.why ?: @"it is in use";
    if (i.kind.reportOnly) return i.kind.ownerSetting ?: @"its row only reports it";
    MMSession *s = AgentIn(i.ownerPath ?: f.ownerPath, facts);
    if (s) return [NSString stringWithFormat:@"an agent works in %@", (i.ownerPath ?: f.ownerPath).lastPathComponent];
    return nil;
}

- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }

/// Proactive takes finished projects and leftovers. Eager adds caches. A tool's cleanup runs only when you ask.
- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r {
    NSString *sec = f.facts[@"section"];
    if (f.proposal.reversibility == MMReversibleToolCommand) return @"Noo-Noo runs a tool's own cleanup only when you ask";
    if ([sec isEqual:@"finished"] || [sec isEqual:@"leftovers"]) return nil;
    if (m == MMModeEager && [f.facts[@"class"] isEqual:@"cache"]) return nil;
    return m == MMModeEager ? @"Eager cleans finished projects, leftovers and caches only" : @"Proactive cleans finished projects and leftovers only";
}

@end

id<MMExpertPolicy> MMNNPolicy(void) {
    static MMNNPolicyObject *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMNNPolicyObject new]; });
    return p;
}

#pragma mark - The rule

/// Decides every clutter finding from its owner's state and its row, so the model is never asked about clutter.
@implementation MMNNOwnerRule
- (NSString *)ruleID { return @"noonoo.owner-state"; }
- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts {
    if (![f.expert isEqualToString:kExpert]) return nil;
    MMVerdict *v = [MMVerdict new];
    v.findingID = f.findingID; v.fingerprint = f.fingerprint; v.decidedBy = self.ruleID;
    NSString *sec = f.facts[@"section"];
    if (f.keepReasons.count || !f.proposal) {
        v.kind = MMVerdictKeep; v.confidence = 0.95; v.reason = f.keepReasons.firstObject ?: @"its row only reports it";
    } else if ([sec isEqual:@"finished"]) {
        v.kind = MMVerdictGo; v.confidence = 0.95; v.reason = [@"its project is " stringByAppendingString:f.facts[@"ownerState"] ?: @"finished"];
    } else if ([sec isEqual:@"leftovers"]) {
        v.kind = MMVerdictGo; v.confidence = 0.9; v.reason = f.facts[@"why"] ?: @"nothing uses it";
    } else if ([f.facts[@"class"] isEqual:@"cache"]) {
        v.kind = MMVerdictGo; v.confidence = 0.7; v.reason = @"a cache its tool rebuilds";
    } else {
        v.kind = MMVerdictKeep; v.confidence = 0.9; v.reason = @"its project is still active";
    }
    v.word = [MMNooNooExpert.shared.words wordFor:v.kind];
    v.about = v.reason;
    return v;
}
@end
