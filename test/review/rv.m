// The review broker's test tool. test/review.sh builds it from Sources/Core and runs it against the fake CLIs.
//   rv unit                         checks without a model; prints name<TAB>want<TAB>got lines
//   rv review <fixture.json> [flags] runs one review and prints it as JSON; exit 1 when the review has an error
//       --model m --trigger t --batch n --parallel n --budget n --judge --rules --mode n
//   rv wake                         the wake queue, in process; prints name<TAB>want<TAB>got lines
// A fixture is {"expert", "words": [keep, go, unsure], "system", "findings": [...]}. Each finding has id, title,
// fingerprint, facts, keep_reasons and an owner {kind, key, name, path, parent}.
#import <Foundation/Foundation.h>
#import "Core/Review/MMReview.h"

#pragma mark - Stand-ins for the graph's types. The broker only sends them messages.

@interface RVOwner : NSObject
@property MMOwnerKind kind;
@property (copy) NSString *key, *name, *path;
@property RVOwner *parent;
@end
@implementation RVOwner @end

@interface RVFinding : NSObject
@property (copy) NSString *findingID, *expert, *kind, *stableKey, *instanceKey, *title, *path, *fingerprint;
@property RVOwner *owner;
@property NSDictionary *facts;
@property NSArray<NSString *> *keepReasons;
@property (readonly) BOOL kept;
@end
@implementation RVFinding
- (BOOL)kept { return self.keepReasons.count > 0; }
@end

/// A rule as an expert would write one: a finding whose facts say kind service is kept.
@interface RVServiceRule : NSObject <MMRule>
@end
@implementation RVServiceRule
- (NSString *)ruleID { return @"test.service-keeps"; }
- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts {
    if (![f.facts[@"kind"] isEqual:@"service"]) return nil;
    MMVerdict *v = [MMVerdict new];
    v.kind = MMVerdictKeep; v.confidence = 0.9; v.reason = @"a shared service stays";
    return v;
}
@end

static RVOwner *Owner(NSDictionary *j) {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    RVOwner *o = [RVOwner new];
    o.kind = [j[@"kind"] integerValue]; o.key = j[@"key"]; o.name = j[@"name"]; o.path = j[@"path"];
    o.parent = Owner(j[@"parent"]);
    return o;
}

static NSArray<MMFinding *> *Findings(NSArray *list, NSString *expert) {
    NSMutableArray *l = [NSMutableArray new];
    for (NSDictionary *j in list) {
        RVFinding *f = [RVFinding new];
        f.findingID = j[@"id"]; f.expert = expert; f.title = j[@"title"]; f.fingerprint = j[@"fingerprint"];
        f.facts = j[@"facts"] ?: @{}; f.keepReasons = j[@"keep_reasons"] ?: @[]; f.owner = Owner(j[@"owner"]);
        [l addObject:(MMFinding *)(id)f];
    }
    return l;
}

static NSString *const kKinds[] = {@"unsure", @"keep", @"go"};

static NSDictionary *ReviewJSON(MMReview *r) {
    NSMutableDictionary *v = [NSMutableDictionary new];
    for (NSString *k in r.verdicts) {
        MMVerdict *x = r.verdicts[k];
        v[k] = @{@"kind": kKinds[x.kind], @"word": x.word ?: @"", @"confidence": @(x.confidence), @"judged": @(x.judged),
                 @"decided_by": x.decidedBy ?: @"", @"fingerprint": x.fingerprint ?: @"", @"reason": x.reason ?: @"",
                 @"keep_evidence": x.keepEvidence ?: @"", @"about": x.about ?: @""};
    }
    NSMutableArray *calls = [NSMutableArray new];
    for (MMUsage *u in r.calls) [calls addObject:u.json];
    return @{@"expert": r.expert ?: @"", @"trigger": r.trigger ?: @"", @"summary": r.summary ?: @"", @"error": r.error ?: NSNull.null,
             @"judge_error": r.judgeError ?: NSNull.null, @"note": r.note ?: NSNull.null, @"mode": @(r.mode), @"verdicts": v,
             @"calls": calls, @"decided": [MMReviewBroker.shared decidedCounts:r.expert],
             @"uncached_today": @(MMBudget.shared.uncachedToday), @"list_cost_today": @(MMBudget.shared.listCostToday)};
}

static void Print(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    fwrite(d.bytes, 1, d.length, stdout); printf("\n");
}

static void Out(NSString *name, NSString *want, NSString *got) { printf("%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"nil").UTF8String); }
static NSString *N(double n) { return [NSString stringWithFormat:@"%g", n]; }

static int Unit(void) {
    Out(@"redact passes nil through", @"nil", MMRedact(nil));
    Out(@"redact a --token style flag", @"run --api-key <redacted> now", MMRedact(@"run --api-key SUPERSECRET123 now"));
    Out(@"redact key=value with a secret key", @"API_TOKEN=<redacted>", MMRedact(@"API_TOKEN=ENVSECRET999"));
    Out(@"redact a password in a URL", @"postgres://<redacted>@db/x", MMRedact(@"postgres://user:hunter2@db/x"));
    Out(@"redact a long opaque string", @"key <redacted>", MMRedact(@"key abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP"));
    Out(@"clip writes the home folder as ~", @"~/Documents/app", MMClip([NSHomeDirectory() stringByAppendingPathComponent:@"Documents/app"], 100));
    Out(@"clip makes one line", @"a b c", MMClip(@"a\n b\t\tc ", 100));
    Out(@"clip cuts at max", @"abcd…", MMClip(@"abcdefghij", 5));
    Out(@"clip of empty text is nil", @"nil", MMClip(@"  \n ", 10));

    MMVerdictWords *lh = [MMVerdictWords keep:@"in_use" go:@"idle" unsure:@"unsure"];
    MMVerdictWords *wf = [MMVerdictWords keep:@"active" go:@"stale" unsure:@"unsure"];
    Out(@"LocoHost's go word", @"idle", [lh wordFor:MMVerdictGo]);
    Out(@"WorkForest's keep word", @"active", [wf wordFor:MMVerdictKeep]);
    Out(@"a known word maps to its kind", N(MMVerdictGo), N([wf kindFor:@"stale"]));
    Out(@"another expert's word maps to unsure", N(MMVerdictUnsure), N([wf kindFor:@"idle"]));
    Out(@"nil maps to unsure", N(MMVerdictUnsure), N([lh kindFor:nil]));

    Out(@"the budget defaults to 652,000 uncached tokens", @"652000", N(MMBudget.shared.dailyUncached));
    Out(@"the budget has no cost limit by default", @"0", N(MMBudget.shared.dailyListCostUSD));
    Out(@"a manual review always runs", @"1", N([MMBudget.shared allows:@"manual"]));
    Out(@"the floor confidence", @"0.6", N(MMMinConfidence));
    Out(@"the sure confidence", @"0.8", N(MMSureConfidence));

    MMUsage *u = [MMUsage fromJSON:@{@"input": @10, @"cache_write_5m": @100, @"cache_write_1h": @200, @"cache_read": @1000,
                                     @"output": @50, @"thinking": @30, @"list_cost_usd": @0.25, @"model": @"haiku"}];
    Out(@"uncached is input, cache writes and output", @"360", N(u.uncached));
    Out(@"thinking is not added to output again", @"50", N(u.output));
    Out(@"usage survives JSON", @"360 1000 0.25 haiku", [NSString stringWithFormat:@"%ld %ld %g %@",
        (long)[MMUsage fromJSON:u.json].uncached, (long)[MMUsage fromJSON:u.json].cacheRead, [MMUsage fromJSON:u.json].listCostUSD, [MMUsage fromJSON:u.json].model]);

    RVFinding *f = [RVFinding new];
    f.findingID = @"test:x:1"; f.fingerprint = @"a";
    MMVerdict *v = [MMVerdict new]; v.findingID = f.findingID; v.fingerprint = @"a";
    MMReview *r = [MMReview new]; r.verdicts = @{f.findingID: v};
    Out(@"a verdict holds while the fingerprint holds", @"yes", [r verdictFor:(MMFinding *)(id)f] ? @"yes" : @"no");
    f.fingerprint = @"b";
    Out(@"a moved fingerprint drops the verdict", @"no", [r verdictFor:(MMFinding *)(id)f] ? @"yes" : @"no");
    Out(@"the wake gap is ten minutes", @"600", N(MMReviewBroker.shared.minGap));
    return 0;
}

static int Review(int argc, const char *argv[]) {
    if (argc < 3) { fprintf(stderr, "usage: rv review <fixture.json> [flags]\n"); return 2; }
    NSDictionary *fx = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
    if (![fx isKindOfClass:NSDictionary.class]) { fprintf(stderr, "rv: bad fixture\n"); return 2; }
    MMReviewRequest *q = [MMReviewRequest new];
    q.expert = fx[@"expert"]; q.system = fx[@"system"] ?: @"fixture system prompt";
    NSArray *w = fx[@"words"];
    if (w.count == 3) q.words = [MMVerdictWords keep:w[0] go:w[1] unsure:w[2]];
    q.findings = Findings(fx[@"findings"], q.expert);
    for (int i = 3; i < argc; i++) {
        NSString *a = @(argv[i]), *next = i + 1 < argc ? @(argv[i + 1]) : nil;
        if ([a isEqualToString:@"--model"] && next) { q.model = next; i++; }
        else if ([a isEqualToString:@"--trigger"] && next) { q.trigger = next; i++; }
        else if ([a isEqualToString:@"--batch"] && next) { q.batchSize = (NSUInteger)next.integerValue; i++; }
        else if ([a isEqualToString:@"--parallel"] && next) { q.parallel = (NSUInteger)next.integerValue; i++; }
        else if ([a isEqualToString:@"--budget"] && next) { MMBudget.shared.dailyUncached = next.integerValue; i++; }
        else if ([a isEqualToString:@"--mode"] && next) { q.mode = next.integerValue; i++; }
        else if ([a isEqualToString:@"--judge"]) q.judge = YES;
        else if ([a isEqualToString:@"--rules"]) [MMReviewBroker.shared registerRules:@[[RVServiceRule new]] expert:q.expert];
        else { fprintf(stderr, "rv: unknown flag %s\n", argv[i]); return 2; }
    }
    MMReview *r = [MMReviewBroker.shared run:q];
    NSMutableDictionary *j = [ReviewJSON(r) mutableCopy];
    j[@"last_matches"] = @([[MMReview lastFor:q.expert].summary isEqualToString:r.summary]);
    j[@"history"] = @([MMReview historyFor:q.expert since:nil].count);
    Print(j);
    return r.error ? 1 : 0;
}

/// The wake queue with a short gap: wakes inside the gap give one review after it, and a manual wake runs at once.
static int Wake(void) {
    MMReviewBroker *b = MMReviewBroker.shared;
    b.minGap = 1.0;
    __block NSMutableArray *triggers = [NSMutableArray new];
    [b setRequestMaker:^MMReviewRequest *(NSString *trigger, MMSnapshot *s) {
        @synchronized (triggers) { [triggers addObject:trigger]; }
        return nil;   // no findings, so nothing reaches a model
    } expert:@"waketest"];
    NSString *(^seen)(void) = ^NSString *{ @synchronized (triggers) { return [triggers componentsJoinedByString:@","]; } };
    [b wake:@"schedule" expert:@"waketest"];
    [NSThread sleepForTimeInterval:0.2];
    Out(@"the first wake runs at once", @"schedule", seen());
    [b wake:@"new finding" expert:@"waketest"];
    [b wake:@"age mark" expert:@"waketest"];
    [NSThread sleepForTimeInterval:0.2];
    Out(@"wakes inside the gap wait", @"schedule", seen());
    [b wake:@"manual" expert:@"waketest"];
    [NSThread sleepForTimeInterval:0.2];
    Out(@"a manual wake skips the gap", @"schedule,manual", seen());
    [NSThread sleepForTimeInterval:1.2];
    Out(@"the waiting wakes give one review after the gap", @"schedule,manual,new finding", seen());
    return 0;
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: rv unit | review | wake\n"); return 2; }
    NSString *cmd = @(argv[1]);
    if ([cmd isEqualToString:@"unit"]) return Unit();
    if ([cmd isEqualToString:@"review"]) return Review(argc, argv);
    if ([cmd isEqualToString:@"wake"]) return Wake();
    fprintf(stderr, "rv: unknown command\n");
    return 2;
}}
