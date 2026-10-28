// The review broker's test tool. test/review.sh builds it from Sources/Core and runs it against the fake CLIs.
//   rv unit                         checks without a model; prints name<TAB>want<TAB>got lines
//   rv review <fixture.json> [flags] runs one review and prints it as JSON; exit 1 when the review has an error
//       --model m --trigger t --batch n --parallel n --budget n --judge --rules --mode n
//   rv investigate <folder> <question>
//   rv wake                         the wake queue, in process; prints name<TAB>want<TAB>got lines
//       --shared k1,k2 sets the request's sharedKeys
// A fixture is {"expert", "words": [keep, go, unsure], "system", "findings": [...], "facts": {...}}. Each finding has id,
// title, fingerprint, instance, facts, keep_reasons and an owner {kind, key, name, path, parent}. The fixture's facts
// hold worktrees [{path, head}] and sessions [{cwd, ago, working}] for MMReviewContext.
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
@property MMCost cost;
@property (readonly) BOOL kept;
@end
@implementation RVFinding
- (BOOL)kept { return self.keepReasons.count > 0; }
@end

@interface RVWorktree : NSObject
@property (copy) NSString *path;
@end
@implementation RVWorktree @end

@interface RVGit : NSObject
@property (copy) NSString *head;
@end
@implementation RVGit @end

@interface RVSession : NSObject
@property (copy) NSString *cwd;
@property NSDate *lastActive;
@property BOOL stillWorking;
@end
@implementation RVSession @end

/// The facts MMReviewContext reads: worktrees, their git HEAD and the sessions.
@interface RVFacts : NSObject
@property NSArray *worktrees, *sessions;
@property NSDictionary *git;
@end
@implementation RVFacts
- (RVGit *)gitFor:(RVWorktree *)w { return self.git[w.path]; }
@end

static RVFacts *Facts(NSDictionary *j) {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    RVFacts *x = [RVFacts new];
    NSMutableArray *ws = [NSMutableArray new], *ss = [NSMutableArray new];
    NSMutableDictionary *git = [NSMutableDictionary new];
    for (NSDictionary *w in j[@"worktrees"]) {
        RVWorktree *t = [RVWorktree new]; t.path = w[@"path"]; [ws addObject:t];
        RVGit *g = [RVGit new]; g.head = w[@"head"]; git[t.path] = g;
    }
    for (NSDictionary *w in j[@"sessions"]) {
        RVSession *t = [RVSession new]; t.cwd = w[@"cwd"]; t.stillWorking = [w[@"working"] boolValue];
        t.lastActive = [NSDate dateWithTimeIntervalSinceNow:-[w[@"ago"] doubleValue]];
        [ss addObject:t];
    }
    x.worktrees = ws; x.sessions = ss; x.git = git;
    return x;
}

@interface RVWorkstream : NSObject
@property RVWorktree *worktree;
@property RVOwner *owner;
@end
@implementation RVWorkstream @end

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
        f.findingID = j[@"id"]; f.expert = expert; f.title = j[@"title"]; f.fingerprint = j[@"fingerprint"]; f.instanceKey = j[@"instance"];
        f.cost = (MMCost){ .cpuPercent = -1, .diskFreed = [j[@"freed"] unsignedLongLongValue] };
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
                 @"keep_evidence": x.keepEvidence ?: @"", @"about": x.about ?: @"", @"context": x.context ?: @"", @"instance": x.instanceKey ?: @""};
    }
    NSMutableArray *calls = [NSMutableArray new];
    for (MMUsage *u in r.calls) [calls addObject:u.json];
    return @{@"expert": r.expert ?: @"", @"trigger": r.trigger ?: @"", @"summary": r.summary ?: @"", @"error": r.error ?: NSNull.null,
             @"judge_error": r.judgeError ?: NSNull.null, @"note": r.note ?: NSNull.null, @"mode": @(r.mode), @"verdicts": v,
             @"calls": calls, @"decided": [MMReviewBroker.shared decidedCounts:r.expert], @"review_decided": r.decided ?: @{}, @"sent": @(r.sent),
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

    // Issue #33: the instance key holds for every expert, as LocoHost 0.1 keyed verdicts by pid and start time.
    f.fingerprint = @"a"; f.instanceKey = @"100:1"; v.instanceKey = @"100:1";
    Out(@"a verdict holds for its own instance", @"yes", [r verdictFor:(MMFinding *)(id)f] ? @"yes" : @"no");
    f.instanceKey = @"200:2";
    Out(@"a verdict made for another instance is dropped", @"no", [r verdictFor:(MMFinding *)(id)f] ? @"yes" : @"no");
    v.instanceKey = nil;
    Out(@"a verdict saved with no instance holds on its fingerprint", @"yes", [r verdictFor:(MMFinding *)(id)f] ? @"yes" : @"no");
    MMVerdict *keep = [MMVerdict new]; keep.instanceKey = @"7:7"; keep.context = @"g1|a0|z0";
    MMReview *saved = [MMReview new]; saved.expert = @"rvunit"; saved.at = NSDate.date; saved.verdicts = @{@"x": keep};
    saved.decided = @{@"cache": @2}; saved.sent = 3;
    [saved save];
    MMReview *read = [MMReview lastFor:@"rvunit"];
    MMVerdict *back = read.verdicts[@"x"];
    Out(@"the triage counts survive the log", @"2 3", [NSString stringWithFormat:@"%@ %ld", read.decided[@"cache"], (long)read.sent]);
    Out(@"the instance and the context survive the log", @"7:7 g1|a0|z0", [NSString stringWithFormat:@"%@ %@", back.instanceKey, back.context]);

    // MMReviewContext: HEAD, the activity bucket of the newest session, and a size bucket.
    RVOwner *ws = [RVOwner new]; ws.kind = MMOwnerWorkstream; ws.key = @"/var/rv/tree"; ws.path = @"/var/rv/tree";
    RVFinding *g = [RVFinding new]; g.findingID = @"test:x:2"; g.owner = ws; g.cost = (MMCost){ .diskFreed = 300ull << 20 };
    RVFacts *facts = Facts(@{@"worktrees": @[@{@"path": @"/private/var/rv/tree", @"head": @"0123456789abcdef0123"}],
                             @"sessions": @[@{@"cwd": @"/var/rv/tree/sub", @"ago": @5400, @"working": @NO},
                                            @{@"cwd": @"/var/rv/tree", @"ago": @60, @"working": @YES},
                                            @{@"cwd": @"/var/rv/other", @"ago": @1, @"working": @YES}]});
    MMFinding *gf = (MMFinding *)(id)g;
    Out(@"the context: HEAD, a working session a minute old, 300 MB", @"g0123456789ab|aw0|z5", MMReviewContext(gf, (MMFacts *)(id)facts));
    [facts.sessions[1] setStillWorking:NO]; [facts.sessions[1] setLastActive:[NSDate dateWithTimeIntervalSinceNow:-3 * 3600]];
    Out(@"the newest session decides the activity bucket", @"g0123456789ab|a1|z5", MMReviewContext(gf, (MMFacts *)(id)facts));
    g.cost = (MMCost){ .diskFreed = 1200ull << 20 };
    Out(@"a size past the next power of four moves the bucket", @"g0123456789ab|a1|z6", MMReviewContext(gf, (MMFacts *)(id)facts));
    g.owner = nil; g.path = nil;
    Out(@"a finding with no folder has no HEAD and no session", @"g-|a-|z6", MMReviewContext(gf, (MMFacts *)(id)facts));
    Out(@"no facts give the empty context", @"g-|a-|z0", MMReviewContext((MMFinding *)(id)f, nil));
    Out(@"Core's rule for work keeps", @"core.work-keeps", MMWorkKeepsRuleID);
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
    q.facts = (MMFacts *)(id)Facts(fx[@"facts"]);
    for (int i = 3; i < argc; i++) {
        NSString *a = @(argv[i]), *next = i + 1 < argc ? @(argv[i + 1]) : nil;
        if ([a isEqualToString:@"--model"] && next) { q.model = next; i++; }
        else if ([a isEqualToString:@"--trigger"] && next) { q.trigger = next; i++; }
        else if ([a isEqualToString:@"--batch"] && next) { q.batchSize = (NSUInteger)next.integerValue; i++; }
        else if ([a isEqualToString:@"--parallel"] && next) { q.parallel = (NSUInteger)next.integerValue; i++; }
        else if ([a isEqualToString:@"--budget"] && next) { MMBudget.shared.dailyUncached = next.integerValue; i++; }
        else if ([a isEqualToString:@"--mode"] && next) { q.mode = next.integerValue; i++; }
        else if ([a isEqualToString:@"--judge"]) q.judge = YES;
        else if ([a isEqualToString:@"--shared"] && next) { q.sharedKeys = [next componentsSeparatedByString:@","]; i++; }
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

static int Investigate(int argc, const char *argv[]) {
    if (argc < 4) return 2;
    RVWorkstream *w = [RVWorkstream new];
    w.worktree = [RVWorktree new]; w.worktree.path = @(argv[2]);
    MMUsage *u = nil; NSString *e = nil;
    NSString *text = [MMReviewBroker.shared investigate:(MMWorkstream *)(id)w question:@(argv[3]) usage:&u error:&e];
    Print(@{@"text": text ?: NSNull.null, @"error": e ?: NSNull.null, @"uncached": @(u.uncached),
            @"investigate_today": @(MMBudget.shared.todayByExpert[@"investigate"].uncached)});
    return text ? 0 : 1;
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
    if (argc < 2) { fprintf(stderr, "usage: rv unit | review | investigate | wake\n"); return 2; }
    NSString *cmd = @(argv[1]);
    if ([cmd isEqualToString:@"unit"]) return Unit();
    if ([cmd isEqualToString:@"review"]) return Review(argc, argv);
    if ([cmd isEqualToString:@"investigate"]) return Investigate(argc, argv);
    if ([cmd isEqualToString:@"wake"]) return Wake();
    fprintf(stderr, "rv: unknown command\n");
    return 2;
}}
