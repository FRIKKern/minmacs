// The review broker, patterns P41 and P43 to P47, and the daily budget of decision 10.
// Ported from WorkForest's Review.m: batches in parallel, the judge through the same batches, and the summary
// with totals from code. New here: rules first, the fingerprint cache, one block per workstream and the budget.
#import "Core/Review/MMReview.h"
#import "Core/Review/MMInvestigate.h"
#import "Core/Store/MMLog.h"
#import "Core/Runtime/MMRuntime.h"

const double MMMinConfidence = 0.6;
const double MMSureConfidence = 0.8;

// From MMModel.m.
id MMCompactFacts(id v, NSString *key);
NSData *MMReviewJSON(id obj);

@interface MMModel (MMBroker)
+ (MMAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
            input:(NSDictionary *)input effort:(NSString *)effort ttl:(NSString *)ttl;
@end

@interface MMUsage (MMBroker)
- (MMUsage *)adding:(MMUsage *)o;
@end

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }

static NSString *Now(void) {
    return [NSISO8601DateFormatter stringFromDate:NSDate.date timeZone:NSTimeZone.localTimeZone formatOptions:NSISO8601DateFormatWithInternetDateTime];
}

/// The model's id for a finding: its findingID with the home folder as ~.
static NSString *IDFor(MMFinding *f) {
    NSString *home = NSHomeDirectory();
    return home.length > 1 ? [f.findingID stringByReplacingOccurrencesOfString:home withString:@"~"] : f.findingID;
}

#pragma mark - Storage

// Rows go to the SQLite log of P38, one row per review, verdict or usage record.

static void StoreAppend(NSString *table, NSString *expert, NSDictionary *body) {
    [MMLog.shared append:table rid:nil expert:expert subject:nil state:nil body:body];
}

/// Bodies of one table, newest first. expert nil means all, since nil means no limit, limit 0 means all.
static NSArray<NSDictionary *> *StoreRows(NSString *table, NSString *expert, NSDate *since, NSUInteger limit) {
    NSMutableArray *rows = [NSMutableArray new];
    for (MMLogEntry *e in [MMLog.shared latest:table expert:expert subject:nil since:since limit:limit])
        if (Dict(e.body)) [rows addObject:e.body];
    return rows;
}

#pragma mark - Verdict words, P41

@interface MMVerdictWords ()
@property (readwrite, copy) NSString *keep, *go, *unsure;
@end

@implementation MMVerdictWords

+ (instancetype)keep:(NSString *)keep go:(NSString *)go unsure:(NSString *)unsure {
    MMVerdictWords *w = [MMVerdictWords new];
    w.keep = keep; w.go = go; w.unsure = unsure;
    return w;
}

- (NSString *)wordFor:(MMVerdictKind)kind {
    return kind == MMVerdictKeep ? self.keep : kind == MMVerdictGo ? self.go : self.unsure;
}

- (MMVerdictKind)kindFor:(NSString *)word {
    if (![word isKindOfClass:NSString.class]) return MMVerdictUnsure;
    if ([word isEqualToString:self.keep]) return MMVerdictKeep;
    if ([word isEqualToString:self.go]) return MMVerdictGo;
    return MMVerdictUnsure;
}

@end

static MMVerdictWords *WordsFor(MMReviewRequest *q) { return q.words ?: [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }

#pragma mark - Verdict

@interface MMVerdict ()
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)j;
- (MMVerdict *)copyVerdict;
@end

@interface MMReview ()
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)j;
@end

static NSString *const kKinds[] = {@"unsure", @"keep", @"go"};

@implementation MMVerdict

- (NSDictionary *)json {
    NSMutableDictionary *j = [@{@"kind": kKinds[self.kind], @"confidence": @(self.confidence), @"judged": @(self.judged)} mutableCopy];
    j[@"word"] = self.word; j[@"finding"] = self.findingID; j[@"fingerprint"] = self.fingerprint;
    j[@"about"] = self.about; j[@"reason"] = self.reason; j[@"keep_evidence"] = self.keepEvidence; j[@"decided_by"] = self.decidedBy;
    return j;
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (!Dict(j)) return nil;
    MMVerdict *v = [MMVerdict new];
    NSString *k = Str(j[@"kind"]);
    v.kind = [k isEqualToString:@"keep"] ? MMVerdictKeep : [k isEqualToString:@"go"] ? MMVerdictGo : MMVerdictUnsure;
    v.confidence = [j[@"confidence"] doubleValue]; v.judged = [j[@"judged"] boolValue];
    v.word = Str(j[@"word"]); v.findingID = Str(j[@"finding"]); v.fingerprint = Str(j[@"fingerprint"]);
    v.about = Str(j[@"about"]); v.reason = Str(j[@"reason"]); v.keepEvidence = Str(j[@"keep_evidence"]); v.decidedBy = Str(j[@"decided_by"]);
    return v;
}

- (MMVerdict *)copyVerdict { return [MMVerdict fromJSON:[self json]]; }

@end

#pragma mark - Review, P41

@implementation MMReview

- (NSDictionary *)json {
    NSMutableDictionary *v = [NSMutableDictionary new];
    for (NSString *k in self.verdicts) v[k] = [self.verdicts[k] json];
    NSMutableArray *calls = [NSMutableArray new];
    for (MMUsage *u in self.calls) [calls addObject:u.json];
    NSMutableDictionary *j = [@{@"at": @(self.at.timeIntervalSince1970), @"mode": @(self.mode), @"verdicts": v, @"calls": calls,
                                @"actions": self.actions ?: @[]} mutableCopy];
    j[@"expert"] = self.expert; j[@"trigger"] = self.trigger; j[@"summary"] = self.summary; j[@"error"] = self.error;
    j[@"judge_error"] = self.judgeError; j[@"note"] = self.note; j[@"summary_words"] = self.summaryWords;
    return j;
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (!Dict(j)) return nil;
    MMReview *r = [MMReview new];
    r.expert = Str(j[@"expert"]); r.trigger = Str(j[@"trigger"]); r.summary = Str(j[@"summary"]);
    r.error = Str(j[@"error"]); r.judgeError = Str(j[@"judge_error"]); r.note = Str(j[@"note"]); r.summaryWords = Str(j[@"summary_words"]);
    r.at = [NSDate dateWithTimeIntervalSince1970:[j[@"at"] doubleValue]];
    r.mode = [j[@"mode"] integerValue];
    NSMutableDictionary *v = [NSMutableDictionary new];
    NSDictionary *vj = Dict(j[@"verdicts"]) ?: @{};
    for (NSString *k in vj) { MMVerdict *x = [MMVerdict fromJSON:vj[k]]; if (x) v[k] = x; }
    r.verdicts = v;
    NSMutableArray *calls = [NSMutableArray new];
    for (id c in List(j[@"calls"]) ?: @[]) { MMUsage *u = [MMUsage fromJSON:c]; if (u) [calls addObject:u]; }
    r.calls = calls;
    r.actions = List(j[@"actions"]) ?: @[];
    return r;
}

- (MMVerdict *)verdictFor:(MMFinding *)f {
    MMVerdict *v = self.verdicts[f.findingID];
    if (!v) return nil;
    return (v.fingerprint == f.fingerprint || [v.fingerprint isEqualToString:f.fingerprint]) ? v : nil;
}

- (void)save { StoreAppend(@"review", self.expert, [self json]); }

+ (instancetype)lastFor:(NSString *)expert {
    return [self fromJSON:StoreRows(@"review", expert, nil, 1).firstObject];
}

+ (NSArray<MMReview *> *)historyFor:(NSString *)expert since:(NSDate *)since {
    NSMutableArray *l = [NSMutableArray new];
    for (NSDictionary *j in StoreRows(@"review", expert, since, 0)) { MMReview *r = [self fromJSON:j]; if (r) [l addObject:r]; }
    return l;
}

@end

#pragma mark - Budget, decision 10

@implementation MMBudget

+ (instancetype)shared {
    static MMBudget *b; static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [MMBudget new]; b.dailyUncached = 652000; });
    return b;
}

static NSDate *StartOfToday(void) { return [NSCalendar.currentCalendar startOfDayForDate:NSDate.date]; }

- (NSDictionary<NSString *, MMUsage *> *)todayByExpert {
    NSMutableDictionary *by = [NSMutableDictionary new];
    for (NSDictionary *row in StoreRows(@"usage", nil, StartOfToday(), 0)) {
        MMUsage *u = [MMUsage fromJSON:Dict(row[@"usage"])];
        NSString *e = Str(row[@"expert"]) ?: @"";
        if (u) by[e] = by[e] ? [by[e] adding:u] : u;
    }
    return by;
}

- (NSInteger)uncachedToday {
    NSInteger n = 0;
    for (MMUsage *u in self.todayByExpert.allValues) n += u.uncached;
    return n;
}

- (double)listCostToday {
    double c = 0;
    for (MMUsage *u in self.todayByExpert.allValues) c += u.listCostUSD;
    return c;
}

- (BOOL)allows:(NSString *)trigger {
    if ([trigger isEqualToString:@"manual"]) return YES;
    NSDictionary *by = self.todayByExpert;
    NSInteger uncached = 0; double cost = 0;
    for (MMUsage *u in by.allValues) { uncached += u.uncached; cost += u.listCostUSD; }
    if (self.dailyUncached > 0 && uncached >= self.dailyUncached) return NO;
    if (self.dailyListCostUSD > 0 && cost >= self.dailyListCostUSD) return NO;
    return YES;
}

- (void)record:(MMUsage *)usage expert:(NSString *)expert {
    if (!usage) return;
    StoreAppend(@"usage", expert, @{@"at": @(NSDate.date.timeIntervalSince1970), @"expert": expert ?: @"", @"usage": usage.json});
}

@end

#pragma mark - Request

@implementation MMReviewRequest

- (instancetype)init {
    if ((self = [super init])) { _model = @"auto"; _trigger = @"manual"; _batchSize = 25; _parallel = 3; }
    return self;
}

@end

#pragma mark - Prompts and schemas

/// F6. The routine schema of one finding, in the expert's words. The enum lists keep, go, unsure in that order.
static NSDictionary *ItemSchema(MMVerdictWords *w) {
    return @{@"type": @"object", @"additionalProperties": @NO,
             @"required": @[@"about", @"confidence", @"id", @"keep_evidence", @"reason", @"verdict"],
             @"properties": @{@"id": @{@"type": @"string"}, @"verdict": @{@"type": @"string", @"enum": @[w.keep, w.go, w.unsure]},
                              @"confidence": @{@"type": @"number"}, @"about": @{@"type": @"string"},
                              @"reason": @{@"type": @"string"}, @"keep_evidence": @{@"type": @"string"}}};
}

static NSDictionary *ReviewSchema(MMReviewRequest *q) {
    NSDictionary *item = q.schema ?: ItemSchema(WordsFor(q));
    return @{@"type": @"object", @"additionalProperties": @NO, @"required": @[@"items", @"summary"],
             @"properties": @{@"items": @{@"type": @"array", @"items": item}, @"summary": @{@"type": @"string"}}};
}

static NSDictionary *JudgeSchema(MMVerdictWords *w) {
    return @{@"type": @"object", @"additionalProperties": @NO, @"required": @[@"items"], @"properties": @{@"items": @{@"type": @"array", @"items": @{
        @"type": @"object", @"additionalProperties": @NO, @"required": @[@"confidence", @"decision", @"evidence", @"id", @"reason"],
        @"properties": @{@"id": @{@"type": @"string"}, @"decision": @{@"type": @"string", @"enum": @[w.keep, w.go]},
                         @"confidence": @{@"type": @"number"}, @"evidence": @{@"type": @"string"}, @"reason": @{@"type": @"string"}}}}}};
}

static NSDictionary *SummarySchema(void) {
    return @{@"type": @"object", @"additionalProperties": @NO, @"required": @[@"summary"], @"properties": @{@"summary": @{@"type": @"string"}}};
}

/// The judge's prompt, from WF and LH kJudge, in the expert's words.
static NSString *JudgeSystem(MMReviewRequest *q) {
    if (q.judgeSystem.length) return q.judgeSystem;
    MMVerdictWords *w = WordsFor(q);
    return [NSString stringWithFormat:
        @"You are the judge in %@'s Eager mode. Each finding below is quiet, has nothing that must keep it, "
        @"and a first review was not sure enough to act on it. The burden of proof is on the finding: "
        @"decide %@ only when a concrete fact shows that someone still needs it. Otherwise decide %@. "
        @"Every action MinMacs takes can be undone.\n\n"
        @"Evidence that counts: recent activity, an agent session active in the last hours, work that exists nowhere else, "
        @"or a name or message that says the work is ongoing or parked on purpose.\n"
        @"Not evidence: that it exists, that it is still running, activity from days ago, or that it might be useful someday.\n\n"
        @"first is the first pass, for reference. Weigh the facts, not its verdict. "
        @"For every finding return: id (copied exactly), decision (%@ or %@), confidence from 0 to 1, "
        @"evidence (the deciding fact for %@, empty otherwise), and reason (one plain sentence of at most 25 words naming the facts). "
        @"Return exactly one entry for every id.", q.expert ?: @"MinMacs", w.keep, w.go, w.keep, w.go, w.keep];
}

/// The summary prompt of WF kSummary, for any expert.
static NSString *SummarySystem(MMReviewRequest *q) {
    return [NSString stringWithFormat:
        @"You write the summary at the top of %@'s menu in MinMacs, a menu bar app on a developer's Mac. "
        @"Below is one line per finding with the review's verdict. Write two or three plain sentences: what stands out, "
        @"what is left over, and what you would act on. MinMacs writes the totals itself, so do not count. Name projects and branches, not paths.",
        q.expert ?: @"an expert"];
}

#pragma mark - Broker

@interface MMReviewBroker ()
@property NSMutableDictionary<NSString *, NSArray<id<MMRule>> *> *rules;
@property NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *ageMarks;
@property NSMutableDictionary<NSString *, MMReviewRequest *(^)(NSString *, MMSnapshot *)> *makers;
@property NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *counts;
@property NSMutableDictionary<NSString *, NSDate *> *lastWake;
@property NSMutableSet<NSString *> *pending;
@property dispatch_queue_t queue;
@end

static void *kOnReviewQueue = &kOnReviewQueue;

@implementation MMReviewBroker

+ (instancetype)shared {
    static MMReviewBroker *b; static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [MMReviewBroker new]; });
    return b;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _rules = [NSMutableDictionary new]; _ageMarks = [NSMutableDictionary new]; _makers = [NSMutableDictionary new];
    _counts = [NSMutableDictionary new]; _lastWake = [NSMutableDictionary new]; _pending = [NSMutableSet new];
    _minGap = 600;
    _queue = MMQueue(@"core", @"review", QOS_CLASS_UTILITY);
    dispatch_queue_set_specific(_queue, kOnReviewQueue, kOnReviewQueue, NULL);
    return self;
}

- (void)registerRules:(NSArray<id<MMRule>> *)rules expert:(NSString *)expert {
    @synchronized (self) { self.rules[expert] = [rules copy] ?: @[]; }
}

- (void)setAgeMarks:(NSArray<NSNumber *> *)seconds expert:(NSString *)expert {
    @synchronized (self) { self.ageMarks[expert] = [seconds copy] ?: @[]; }
}

- (void)setRequestMaker:(MMReviewRequest *(^)(NSString *, MMSnapshot *))maker expert:(NSString *)expert {
    @synchronized (self) { if (maker) self.makers[expert] = [maker copy]; else [self.makers removeObjectForKey:expert]; }
}

- (void)count:(NSString *)key expert:(NSString *)expert by:(NSInteger)n {
    if (!n) return;
    @synchronized (self) {
        NSMutableDictionary *c = self.counts[expert ?: @""] ?: (self.counts[expert ?: @""] = [NSMutableDictionary new]);
        c[key] = @([c[key] integerValue] + n);
    }
}

- (NSDictionary<NSString *, NSNumber *> *)decidedCounts:(NSString *)expert {
    @synchronized (self) { return [self.counts[expert ?: @""] copy] ?: @{}; }
}

#pragma mark P46, the wake queue

- (void)wake:(NSString *)reason expert:(NSString *)expert {
    dispatch_async(self.queue, ^{
        BOOL manual = [reason isEqualToString:@"manual"];
        NSDate *last = self.lastWake[expert];
        NSTimeInterval since = last ? -last.timeIntervalSinceNow : INFINITY;
        if (!manual && since < self.minGap) {
            // Coalesced: one review runs when the gap has passed, however many wakes came in.
            if ([self.pending containsObject:expert]) return;
            [self.pending addObject:expert];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.minGap - since) * NSEC_PER_SEC)), self.queue, ^{
                [self.pending removeObject:expert];
                [self fire:reason expert:expert];
            });
            return;
        }
        [self fire:reason expert:expert];
    });
}

/// Runs on the review queue.
- (void)fire:(NSString *)reason expert:(NSString *)expert {
    self.lastWake[expert] = NSDate.date;
    MMReviewRequest *(^maker)(NSString *, MMSnapshot *);
    @synchronized (self) { maker = self.makers[expert]; }
    if (!maker) return;
    MMSnapshot *s = MMGraph.shared.latest;
    MMReviewRequest *q = maker(reason, s);
    if (!q) return;
    if (!q.expert) q.expert = expert;
    if (!q.trigger.length || [q.trigger isEqualToString:@"manual"]) q.trigger = reason;
    [self runHere:q];
}

#pragma mark P43, P44, P47: the run

- (MMReview *)run:(MMReviewRequest *)q {
    if (dispatch_get_specific(kOnReviewQueue)) return [self runHere:q];
    __block MMReview *r;
    dispatch_sync(self.queue, ^{ r = [self runHere:q]; });
    return r;
}

/// The top owner of a finding, the workstream when it has one. Findings with the same top owner share a block.
static MMOwner *TopOwner(MMFinding *f) {
    MMOwner *o = f.owner;
    while (o.parent) o = o.parent;
    return o;
}

static NSString *BlockKey(MMFinding *f) {
    MMOwner *o = TopOwner(f);
    return o ? [NSString stringWithFormat:@"%ld:%@", (long)o.kind, o.key ?: @""] : @"";
}

/// What the model gets for one batch: one block per workstream, the owner named once, then each finding's facts.
/// extra adds fields per finding, such as the judge's first review. MMModel compacts and redacts it all.
static NSDictionary *BatchInput(NSArray<MMFinding *> *batch, MMReviewRequest *q, NSDictionary *(^extra)(MMFinding *)) {
    NSMutableArray *blocks = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byKey = [NSMutableDictionary new];
    for (MMFinding *f in batch) {
        NSString *k = BlockKey(f);
        NSMutableDictionary *b = byKey[k];
        if (!b) {
            b = [NSMutableDictionary new];
            MMOwner *o = TopOwner(f);
            if (o) b[@"w"] = o.path ?: o.name ?: o.key;
            b[@"f"] = [NSMutableArray new];
            byKey[k] = b; [blocks addObject:b];
        }
        NSMutableDictionary *x = [(q.factsFor ? q.factsFor(f) : f.facts) ?: @{} mutableCopy];
        x[@"id"] = IDFor(f);
        NSDictionary *more = extra ? extra(f) : nil;
        if (more) [x addEntriesFromDictionary:more];
        [b[@"f"] addObject:x];
    }
    return @{@"blocks": blocks, @"now": Now()};   // sorted keys put now last, after the facts that stay the same
}

/// F4. Five minutes when this expert's last review was more than an hour ago, so one-shot facts are written at
/// 1.25 times input. One hour otherwise, so the system prompt stays cached between reviews.
static NSString *TTLFor(MMReview *prev) {
    return prev.at && -prev.at.timeIntervalSinceNow < 3600 ? @"1h" : @"5m";
}

/// WF Batches, Review.m:410. One call per batch of q.batchSize, q.parallel at a time. Every call's usage goes to
/// r.calls and the budget. Each answer goes through parse. Returns the indexes of the batches that failed.
- (NSIndexSet *)batches:(NSArray<MMFinding *> *)findings request:(MMReviewRequest *)q review:(MMReview *)r
                 system:(NSString *)system schema:(NSDictionary *)schema ttl:(NSString *)ttl
                  input:(NSDictionary *(^)(NSArray<MMFinding *> *))input
                  parse:(void (^)(NSDictionary *so, NSArray<MMFinding *> *batch))parse
                 errors:(NSMutableArray<NSString *> *)errors
             batchesOut:(NSArray<NSArray<MMFinding *> *> **)batchesOut {
    NSUInteger size = q.batchSize ?: 25;
    // Findings of one workstream stay together, so their block is sent once. A batch takes whole blocks while they fit,
    // and only a block larger than a batch is split.
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray *> *blocks = [NSMutableDictionary new];
    for (MMFinding *f in findings) {
        NSString *k = BlockKey(f);
        if (!blocks[k]) { blocks[k] = [NSMutableArray new]; [order addObject:k]; }
        [blocks[k] addObject:f];
    }
    NSMutableArray *batches = [NSMutableArray new];
    NSMutableArray *cur = [NSMutableArray new];
    for (NSString *k in order) {
        NSArray *b = blocks[k];
        if (cur.count && cur.count + b.count > size) { [batches addObject:cur]; cur = [NSMutableArray new]; }
        for (MMFinding *f in b) {
            [cur addObject:f];
            if (cur.count == size) { [batches addObject:cur]; cur = [NSMutableArray new]; }
        }
    }
    if (cur.count) [batches addObject:cur];
    if (batchesOut) *batchesOut = batches;
    NSMutableIndexSet *failed = [NSMutableIndexSet new];
    NSMutableArray *calls = [r.calls mutableCopy] ?: [NSMutableArray new];
    dispatch_semaphore_t gate = dispatch_semaphore_create((long)MAX(1, q.parallel ?: 3));
    dispatch_apply(batches.count, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t i) {
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        MMAnswer *a = [MMModel ask:q.model system:system schema:schema input:input(batches[i]) effort:@"low" ttl:ttl];
        dispatch_semaphore_signal(gate);
        [MMBudget.shared record:a.usage expert:q.expert];
        @synchronized (r) {
            [calls addObject:a.usage];
            if (a.note && !r.note) r.note = a.note;
            if (a.json) parse(a.json, batches[i]);
            else {
                [failed addIndex:i];
                [errors addObject:batches.count > 1 ? [NSString stringWithFormat:@"batch %zu of %lu: %@", i + 1, (unsigned long)batches.count, a.error]
                                                    : a.error ?: @"the model did not answer"];
            }
        }
    });
    r.calls = calls;
    return failed;
}

/// A verdict that may be carried to the next review while its fingerprint holds.
static BOOL Carries(MMVerdict *v) { return v && ![v.decidedBy isEqualToString:@"judge-failed"]; }

- (MMReview *)runHere:(MMReviewRequest *)q {
    MMReview *r = [MMReview new];
    r.expert = q.expert; r.trigger = q.trigger; r.mode = q.mode; r.at = NSDate.date; r.calls = @[]; r.actions = @[];
    MMVerdictWords *words = WordsFor(q);
    MMReview *prev = [MMReview lastFor:q.expert];
    NSArray<id<MMRule>> *rules;
    @synchronized (self) { rules = self.rules[q.expert ?: @""] ?: @[]; }

    // P47 first, then the fingerprint cache. Only what neither decides goes to the model.
    NSMutableDictionary<NSString *, MMVerdict *> *v = [NSMutableDictionary new];
    NSMutableArray<MMFinding *> *send = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSNumber *> *decided = [NSMutableDictionary new];
    for (MMFinding *f in q.findings) {
        MMVerdict *x = nil;
        for (id<MMRule> rule in rules) {
            x = [rule decide:f facts:q.facts];
            if (!x) continue;
            x.decidedBy = rule.ruleID;
            break;
        }
        if (!x) {
            MMVerdict *old = q.ignoreCache ? nil : [prev verdictFor:f];
            if (Carries(old)) { x = [old copyVerdict]; decided[@"cache"] = @([decided[@"cache"] integerValue] + 1); }
        } else decided[x.decidedBy] = @([decided[x.decidedBy] integerValue] + 1);
        if (!x) { [send addObject:f]; continue; }
        x.findingID = f.findingID; x.fingerprint = f.fingerprint;
        if (!x.word) x.word = [words wordFor:x.kind];
        v[f.findingID] = x;
    }

    NSMutableArray<NSString *> *summaries = [NSMutableArray new];
    NSUInteger batchCount = 0;
    if (send.count && ![MMBudget.shared allows:q.trigger]) {
        r.error = [NSString stringWithFormat:@"The daily review budget is used: %ld of %ld uncached tokens. A manual review still runs.",
                   (long)MMBudget.shared.uncachedToday, (long)MMBudget.shared.dailyUncached];
    } else if (send.count) {
        NSMutableDictionary *byID = [NSMutableDictionary new];
        for (MMFinding *f in send) byID[IDFor(f)] = f;
        NSMutableArray *errors = [NSMutableArray new];
        NSArray *batches = nil;
        __block NSInteger byModel = 0;
        [self batches:send request:q review:r system:q.system schema:ReviewSchema(q) ttl:TTLFor(prev)
                input:^NSDictionary *(NSArray<MMFinding *> *batch) { return BatchInput(batch, q, nil); }
                parse:^(NSDictionary *so, NSArray<MMFinding *> *batch) {
            for (NSDictionary *x in List(so[@"items"]) ?: @[]) {
                MMFinding *f = Dict(x) ? byID[Str(x[@"id"]) ?: @""] : nil;
                if (!f || ![batch containsObject:f]) continue;
                MMVerdict *w = [MMVerdict new];
                w.confidence = MAX(0, MIN(1, [x[@"confidence"] doubleValue]));
                w.kind = [words kindFor:x[@"verdict"]];
                if (w.confidence < MMMinConfidence) w.kind = MMVerdictUnsure;   // below the floor a verdict counts as unsure
                w.word = [words wordFor:w.kind];
                w.about = Str(x[@"about"]); w.reason = Str(x[@"reason"]); w.keepEvidence = Str(x[@"keep_evidence"]) ?: @"";
                w.findingID = f.findingID; w.fingerprint = f.fingerprint; w.decidedBy = @"model";
                if (!v[f.findingID]) byModel++;
                v[f.findingID] = w;
            }
            if (Str(so[@"summary"]).length) [summaries addObject:so[@"summary"]];
        } errors:errors batchesOut:&batches];
        batchCount = batches.count;
        decided[@"model"] = @(byModel);
        if (errors.count) r.error = errors.firstObject;
        NSUInteger answered = 0;
        for (MMFinding *f in send) if (v[f.findingID]) answered++;
        if (!r.error && answered < send.count)
            r.error = [NSString stringWithFormat:@"the answer covered %lu of %lu findings", (unsigned long)answered, (unsigned long)send.count];
    }
    r.verdicts = v;
    for (NSString *k in decided) [self count:k expert:q.expert by:decided[k].integerValue];

    // P44. The judge looks at what the review keeps: free to decide, decided by the model, not judged and not a sure go.
    if (q.judge && !r.error) {
        NSMutableArray *j = [NSMutableArray new];
        for (MMFinding *f in q.findings) {
            MMVerdict *x = v[f.findingID];
            if (!x || f.kept || x.judged || ![x.decidedBy isEqualToString:@"model"]) continue;
            if (x.kind == MMVerdictGo && x.confidence >= MMSureConfidence) continue;
            [j addObject:f];
        }
        if (j.count) [self judge:j request:q into:r];
    }

    // P45. Words from the model, numbers from code.
    NSMutableDictionary *counts = [NSMutableDictionary new];
    for (MMVerdict *x in r.verdicts.allValues) counts[x.word ?: @"none"] = @([counts[x.word ?: @"none"] integerValue] + 1);
    NSUInteger missing = q.findings.count > r.verdicts.count ? q.findings.count - r.verdicts.count : 0;
    if (missing) counts[@"not reviewed"] = @(missing);
    NSString *wordsText = nil;
    if (batchCount == 1 || (r.error && summaries.count)) wordsText = summaries.firstObject;
    else if (batchCount > 1 && summaries.count) {
        r.summaryWords = nil;
        NSString *s = [self summarize:r counts:@{} request:q];
        wordsText = r.summaryWords ?: [summaries componentsJoinedByString:@" "];
        (void)s;
    } else if (batchCount == 0) wordsText = prev.summaryWords;   // no model call, so the last words still hold
    r.summaryWords = wordsText;
    r.summary = [self summaryText:counts words:wordsText];
    [r save];
    return r;
}

static NSString *CountsSentence(NSDictionary<NSString *, NSNumber *> *counts) {
    NSArray *keys = [counts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult c = [counts[b] compare:counts[a]];
        return c != NSOrderedSame ? c : [a compare:b];
    }];
    NSInteger total = 0;
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *k in keys) {
        total += counts[k].integerValue;
        [parts addObject:[NSString stringWithFormat:@"%ld %@", (long)counts[k].integerValue, [k stringByReplacingOccurrencesOfString:@"_" withString:@" "]]];
    }
    if (!parts.count) return @"Nothing to review.";
    return [NSString stringWithFormat:@"%ld finding%@: %@.", (long)total, total == 1 ? @"" : @"s", [parts componentsJoinedByString:@", "]];
}

- (NSString *)summaryText:(NSDictionary *)counts words:(NSString *)words {
    NSString *c = CountsSentence(counts);
    return words.length ? [NSString stringWithFormat:@"%@ %@", c, words] : c;
}

#pragma mark P44, the judge

- (void)judge:(NSArray<MMFinding *> *)findings request:(MMReviewRequest *)q into:(MMReview *)r {
    if (!findings.count) return;
    MMVerdictWords *words = WordsFor(q);
    NSMutableDictionary<NSString *, MMVerdict *> *v = [r.verdicts mutableCopy] ?: [NSMutableDictionary new];
    // Batches run in parallel. Each input reads this copy, because parse writes v under a lock while other inputs are built.
    NSDictionary<NSString *, MMVerdict *> *first = [v copy];
    NSMutableDictionary *byID = [NSMutableDictionary new];
    for (MMFinding *f in findings) byID[IDFor(f)] = f;
    NSMutableArray *errors = [NSMutableArray new];
    NSArray *batches = nil;
    __block NSInteger judged = 0;
    NSIndexSet *failed = [self batches:findings request:q review:r system:JudgeSystem(q) schema:JudgeSchema(words) ttl:@"1h"
        input:^NSDictionary *(NSArray<MMFinding *> *batch) {
            return BatchInput(batch, q, ^NSDictionary *(MMFinding *f) {
                MMVerdict *w = first[f.findingID];
                return w ? @{@"first": @{@"verdict": w.word ?: words.unsure, @"confidence": @(w.confidence), @"reason": w.reason ?: @"",
                                         @"keep_evidence": w.keepEvidence ?: @""}} : nil;
            });
        }
        parse:^(NSDictionary *so, NSArray<MMFinding *> *batch) {
            for (NSDictionary *x in List(so[@"items"]) ?: @[]) {
                MMFinding *f = Dict(x) ? byID[Str(x[@"id"]) ?: @""] : nil;
                if (!f || ![batch containsObject:f]) continue;
                NSString *d = Str(x[@"decision"]);
                if (![d isEqualToString:words.keep] && ![d isEqualToString:words.go]) continue;
                MMVerdict *old = v[f.findingID], *w = [MMVerdict new];
                BOOL keep = [d isEqualToString:words.keep];
                w.kind = keep ? MMVerdictKeep : MMVerdictGo;
                w.word = [words wordFor:w.kind];
                w.confidence = MAX(0, MIN(1, [x[@"confidence"] doubleValue]));
                w.keepEvidence = keep ? Str(x[@"evidence"]) ?: @"" : @"";
                w.reason = Str(x[@"reason"]); w.about = old.about;
                w.judged = YES; w.decidedBy = @"judge";
                w.findingID = f.findingID; w.fingerprint = f.fingerprint;
                v[f.findingID] = w;
                judged++;
            }
        } errors:errors batchesOut:&batches];
    // A failed judge keeps every finding it was asked about. The next review asks again.
    [failed enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        for (MMFinding *f in batches[i]) {
            MMVerdict *old = v[f.findingID], *w = [MMVerdict new];
            w.kind = MMVerdictKeep; w.word = words.keep; w.confidence = old.confidence; w.about = old.about;
            w.reason = [NSString stringWithFormat:@"The judge failed, so it stays: %@", errors.firstObject ?: @"no answer"];
            w.keepEvidence = @""; w.decidedBy = @"judge-failed";
            w.findingID = f.findingID; w.fingerprint = f.fingerprint;
            v[f.findingID] = w;
        }
    }];
    if (errors.count) r.judgeError = errors.firstObject;
    r.verdicts = v;
    [self count:@"judge" expert:q.expert by:judged];
}

#pragma mark P45, the summary

- (NSString *)summarize:(MMReview *)r counts:(NSDictionary<NSString *, NSNumber *> *)counts request:(MMReviewRequest *)q {
    NSMutableArray *lines = [NSMutableArray new];
    for (MMFinding *f in q.findings) {
        MMVerdict *w = r.verdicts[f.findingID];
        [lines addObject:@{@"id": IDFor(f), @"title": f.title ?: @"", @"verdict": w.word ?: @"none", @"about": w.about ?: @""}];
    }
    MMAnswer *a = [MMModel ask:q.model system:SummarySystem(q) schema:SummarySchema() input:@{@"lines": lines} effort:@"low" ttl:@"1h"];
    [MMBudget.shared record:a.usage expert:q.expert];
    r.calls = [r.calls ?: @[] arrayByAddingObject:a.usage];
    NSString *words = Str(a.json[@"summary"]);
    if (words.length) r.summaryWords = words;
    NSMutableDictionary *all = [counts mutableCopy];
    if (!all.count) for (MMVerdict *x in r.verdicts.allValues) all[x.word ?: @"none"] = @([all[x.word ?: @"none"] integerValue] + 1);
    return [self summaryText:all words:words];
}

#pragma mark Investigate

/// The older entry, kept for its callers: one workstream through MMInvestigations, which MMInvestigate.h describes.
- (NSString *)investigate:(MMWorkstream *)workstream question:(NSString *)question usage:(MMUsage **)usage error:(NSString **)error {
    MMInvestigateSubject *subject = [MMInvestigateSubject workstream:workstream];
    if (!subject) { if (error) *error = @"the workstream has no folder to look in"; return nil; }
    MMInvestigation *r = [MMInvestigations.shared run:subject question:question error:error];
    if (usage) *usage = r.usage;
    return r.answer;
}

@end
