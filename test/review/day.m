// The day replay of issue #36. test/review.sh builds it with every source but main.m and the shell, and runs it
// against the fake claude of test/review, which counts tokens from the bytes of each call with fakecount.py.
//   rvday broker <day.json> <out.json> [--fresh] [--plain]   every expert's review through the broker, hourly as in 2.0;
//                                                      --fresh skips the fingerprint cache, --plain sends no ws blocks
//   rvday legacy <day.json> <legacy.json> <out.json>   the 1.x baseline: LocoHost and WorkForest as their 0.1 apps asked
// day.json comes from dayfix.py: the findings the graph holds at each hourly tick. Both modes build each expert's
// request with the expert's own code, so the facts per finding are the same. The broker mode then runs it through
// MMReviewBroker with the experts' rules. The legacy mode sends every finding at the old cadence, pretty-printed, with
// the old prompt and its prose schema, in batches of 25 with a summary call, as WorkForest 0.1 and LocoHost 0.1 did.
// The output holds the usage per expert, the triage counts, and each finding's verdict word per tick, for the comparison.
// The real claude and codex are never run: MINMACS_CLAUDE names the fake, and the test checks that it did.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Core/Know/MMGit.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/LocoHost/MMLHScan.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/MinMacs/MMMinMacs.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/Insomnia/MMInsomnia.h"

#pragma mark - Stand-ins for the facts and the snapshot. The experts and the broker only send them messages.

@interface RDWorktree : NSObject
@property (copy) NSString *path;
@end
@implementation RDWorktree @end

@interface RDGit : NSObject
@property (copy) NSString *head;
@end
@implementation RDGit @end

@interface RDSession : NSObject
@property (copy) NSString *cwd;
@property NSDate *lastActive;
@property BOOL stillWorking;
@end
@implementation RDSession @end

@interface RDFacts : NSObject
@property NSArray *worktrees, *sessions;
@property NSDictionary<NSString *, RDGit *> *git;
@end
@implementation RDFacts
- (RDGit *)gitFor:(RDWorktree *)w { return self.git[w.path]; }
- (uint64_t)generation { return 1; }
- (id)sample { return nil; }
- (id)power { return nil; }
- (NSArray *)agents { return @[]; }
- (NSArray *)clutter { return @[]; }
@end

@interface RDSnapshot : NSObject
@property RDFacts *facts;
@property NSArray<MMFinding *> *findings;
@end
@implementation RDSnapshot
- (NSArray<MMFinding *> *)findingsFor:(NSString *)expert {
    NSMutableArray *l = [NSMutableArray new];
    for (MMFinding *f in self.findings) if ([f.expert isEqualToString:expert]) [l addObject:f];
    return l;
}
- (NSArray *)workstreams { return @[]; }
- (uint64_t)generation { return 1; }
@end

#pragma mark - The fixture

static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

/// {"$ago": s} becomes the seconds-since-1970 of a moment s seconds before now, everywhere in v.
static id Timed(id v, double now) {
    if (Dict(v)) {
        if ([v count] == 1 && [v[@"$ago"] isKindOfClass:NSNumber.class]) return @(now - [v[@"$ago"] doubleValue]);
        NSMutableDictionary *d = [NSMutableDictionary new];
        for (NSString *k in v) { id x = Timed(v[k], now); if (x && x != NSNull.null) d[k] = x; }
        return d;
    }
    if ([v isKindOfClass:NSArray.class]) {
        NSMutableArray *a = [NSMutableArray new];
        for (id x in v) [a addObject:Timed(x, now) ?: NSNull.null];
        return a;
    }
    return v;
}

static MMOwner *Owner(NSDictionary *j) {
    if (!Dict(j)) return nil;
    return [MMOwner kind:(MMOwnerKind)[j[@"kind"] integerValue] key:j[@"key"] name:j[@"name"] path:Str(j[@"path"]) parent:nil];
}

static NSArray<MMFinding *> *FindingsAt(NSDictionary *tick, double now) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *j in tick[@"findings"]) {
        [out addObject:[MMFinding expert:j[@"expert"] kind:j[@"kind"] stableKey:j[@"stableKey"] build:^(MMFindingBuilder *b) {
            b.instanceKey = Str(j[@"instance"]); b.title = Str(j[@"title"]); b.path = Str(j[@"path"]);
            b.owner = Owner(j[@"owner"]);
            b.facts = Timed(j[@"facts"], now);
            b.fingerprint = Str(j[@"fingerprint"]);
            b.keepReasons = j[@"keep"];
            b.cost = (MMCost){ .cpuPercent = -1, .diskFreed = [j[@"freed"] unsignedLongLongValue] };
            if (Str(j[@"proposal"])) b.proposal = [MMProposal verb:j[@"proposal"] title:j[@"proposal"] reversibility:MMReversibleTrash];
        }]];
    }
    return out;
}

static RDFacts *FactsAt(NSDictionary *tick, double now) {
    RDFacts *x = [RDFacts new];
    NSMutableArray *ws = [NSMutableArray new], *ss = [NSMutableArray new];
    NSMutableDictionary *git = [NSMutableDictionary new];
    for (NSDictionary *j in tick[@"worktrees"]) {
        RDWorktree *w = [RDWorktree new]; w.path = j[@"path"]; [ws addObject:w];
        RDGit *g = [RDGit new]; g.head = j[@"head"]; git[w.path] = g;
    }
    for (NSDictionary *j in tick[@"sessions"]) {
        RDSession *s = [RDSession new];
        s.cwd = j[@"cwd"]; s.lastActive = [NSDate dateWithTimeIntervalSince1970:now - [j[@"ago"] doubleValue]];
        s.stillWorking = [j[@"working"] boolValue];
        [ss addObject:s];
    }
    x.worktrees = ws; x.sessions = ss; x.git = git;
    return x;
}

static NSArray<id<MMExpert>> *Experts(void) {
    return @[MMMinMacsExpert.shared, MMLocoHost.shared, MMWorkForestExpert.shared, MMNooNooExpert.shared, MMInsomniaExpert.shared];
}

/// The expert's own request for these findings, as the broker's wake would build it.
static MMReviewRequest *RequestFor(id<MMExpert> e, RDSnapshot *s) {
    NSString *eid = e.expertID;
    if ([eid isEqualToString:@"locohost"])
        return MMLHReviewRequest([s findingsFor:eid], (MMFacts *)(id)s.facts, @"schedule", MMModeFor(eid), nil);
    if ([eid isEqualToString:@"workforest"])
        return MMWFReviewRequest([s findingsFor:eid], (MMSnapshot *)(id)s, @"schedule", MMModeFor(eid), nil);
    return [e reviewRequest:@"schedule" snapshot:(MMSnapshot *)(id)s];
}

#pragma mark - Totals

@interface RDTotal : NSObject
@property NSInteger reviews, calls, findings, sent, noRequest, byContext;
@property NSInteger input, cacheWrite, cacheRead, output, thinking;
@property double cost;
@property NSMutableDictionary<NSString *, NSNumber *> *decided;
@end
@implementation RDTotal
- (instancetype)init { if ((self = [super init])) _decided = [NSMutableDictionary new]; return self; }
- (void)add:(MMUsage *)u {
    self.calls++;
    self.input += u.input; self.cacheWrite += u.cacheWrite5m + u.cacheWrite1h; self.cacheRead += u.cacheRead;
    self.output += u.output; self.thinking += u.thinking; self.cost += u.listCostUSD;
}
- (NSDictionary *)json {
    NSInteger uncached = self.input + self.cacheWrite + self.output;
    return @{@"reviews": @(self.reviews), @"calls": @(self.calls), @"findings": @(self.findings), @"sent": @(self.sent),
             @"no_request": @(self.noRequest), @"sent_by_context": @(self.byContext), @"decided": self.decided, @"input": @(self.input), @"cache_write": @(self.cacheWrite),
             @"cache_read": @(self.cacheRead), @"output": @(self.output), @"thinking": @(self.thinking), @"uncached": @(uncached),
             @"as_counted_before": @(uncached + self.cacheRead), @"list_cost_usd": @(round(self.cost * 1e6) / 1e6)};
}
@end

static void Write(id obj, NSString *path) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    [d writeToFile:path atomically:YES];
}

static void SetClock(double at) { setenv("RV_TEST_CLOCK", [NSString stringWithFormat:@"%.0f", at].UTF8String, 1); }

#pragma mark - Broker mode

/// fresh sends every finding past the fingerprint cache, and plain sends no ws, so each effect is measured alone.
static int Broker(NSDictionary *day, NSString *outPath, BOOL fresh, BOOL plain) {
    MMReviewBroker *b = MMReviewBroker.shared;
    MMBudget.shared.dailyUncached = 0;   // the replay measures the day, so no scheduled review waits on the budget
    for (id<MMExpert> e in Experts()) [b registerRules:[e rules] ?: @[] expert:e.expertID];
    NSDictionary *every = day[@"schedule"][@"broker"];
    NSMutableDictionary<NSString *, RDTotal *> *totals = [NSMutableDictionary new];
    NSMutableDictionary *verdicts = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *last = [NSMutableDictionary new], *lastOwn = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSNumber *> *lastWasModel = [NSMutableDictionary new];
    NSInteger k = 0;
    for (NSDictionary *tick in day[@"ticks"]) {
        double at = [tick[@"at"] doubleValue], now = NSDate.date.timeIntervalSince1970;
        RDSnapshot *s = [RDSnapshot new];
        s.facts = FactsAt(tick, now); s.findings = FindingsAt(tick, now);
        for (id<MMExpert> e in Experts()) {
            NSString *eid = e.expertID;
            NSInteger step = MAX(1, [every[eid] integerValue] / 3600);
            if (k % step) continue;
            RDTotal *t = totals[eid] ?: (totals[eid] = [RDTotal new]);
            NSArray *mine = [s findingsFor:eid];
            t.findings += mine.count;
            SetClock(at);
            MMReviewRequest *q = RequestFor(e, s);
            if (!q) { t.noRequest += mine.count; continue; }
            if (fresh) q.ignoreCache = YES;
            if (plain) q.sharedKeys = nil;
            MMReview *r = [b run:q];
            t.reviews++;
            t.sent += r.sent;
            t.noRequest += mine.count - q.findings.count;
            for (NSString *key in r.decided) t.decided[key] = @(t.decided[key].integerValue + r.decided[key].integerValue);
            for (MMUsage *u in r.calls) [t add:u];
            for (MMFinding *f in q.findings) {
                MMVerdict *v = r.verdicts[f.findingID];
                // A carried verdict keeps the model as its maker. It is the cache's when the last review held the same keys.
                NSString *keys = [NSString stringWithFormat:@"%@|%@|%@", v.fingerprint, v.context, v.instanceKey];
                NSString *by = v.decidedBy ?: @"none";
                if (([by isEqualToString:@"model"] || [by isEqualToString:@"judge"]) && [last[f.findingID] isEqualToString:keys]) by = @"cache";
                // Sent again although the expert's fingerprint and the instance held: Core's context moved.
                NSString *own = [NSString stringWithFormat:@"%@|%@", v.fingerprint, v.instanceKey];
                if ([by isEqualToString:@"model"] && [lastOwn[f.findingID] isEqualToString:own] && lastWasModel[f.findingID].boolValue) t.byContext++;
                last[f.findingID] = keys; lastOwn[f.findingID] = own;
                lastWasModel[f.findingID] = @([v.decidedBy isEqualToString:@"model"] || [v.decidedBy isEqualToString:@"judge"]);
                verdicts[[NSString stringWithFormat:@"%ld|%@", (long)k, f.findingID]] = @{@"word": v.word ?: @"none", @"by": by};
            }
            if (r.error) fprintf(stderr, "rvday: %s at tick %ld: %s\n", eid.UTF8String, (long)k, r.error.UTF8String);
        }
        k++;
    }
    NSMutableDictionary *per = [NSMutableDictionary new];
    for (NSString *eid in totals) per[eid] = totals[eid].json;
    Write(@{@"mode": @"broker", @"experts": per, @"verdicts": verdicts}, outPath);
    return 0;
}

#pragma mark - Legacy mode

/// One call the way the 0.1 apps made it: pretty-printed input, the old prompt and schema, no effort flag, so the
/// fake counts the default effort. Returns the structured answer and adds the usage to t.
static NSDictionary *OldCall(NSString *system, NSDictionary *schema, NSDictionary *input, RDTotal *t) {
    NSData *prompt = [NSJSONSerialization dataWithJSONObject:input options:NSJSONWritingPrettyPrinted | NSJSONWritingWithoutEscapingSlashes error:nil];
    NSString *schemaText = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:schema options:NSJSONWritingSortedKeys error:nil]
                                                 encoding:NSUTF8StringEncoding];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:MMModel.claudePath];
    task.arguments = @[@"-p", @"--model", @"haiku", @"--output-format", @"json", @"--tools", @"", @"--no-session-persistence",
                       @"--system-prompt", system, @"--json-schema", schemaText, @"--effort", @"medium"];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    [env removeObjectForKey:@"CLAUDE_CODE_PROMPT_CACHE_TTL"];
    task.environment = env;
    NSData *out = nil;
    MMRunResult rr = MMRunTask(task, prompt, 120, &out, NULL);
    NSDictionary *j = rr.status == 0 && out ? Dict([NSJSONSerialization JSONObjectWithData:out options:0 error:nil]) : nil;
    if (!j) { fprintf(stderr, "rvday: a legacy call failed\n"); return nil; }
    NSDictionary *u = Dict(j[@"usage"]), *split = Dict(u[@"cache_creation"]), *details = Dict(u[@"output_tokens_details"]);
    MMUsage *usage = [MMUsage fromJSON:@{@"input": u[@"input_tokens"] ?: @0, @"cache_write_5m": split[@"ephemeral_5m_input_tokens"] ?: @0,
                                         @"cache_write_1h": split[@"ephemeral_1h_input_tokens"] ?: @0, @"cache_read": u[@"cache_read_input_tokens"] ?: @0,
                                         @"output": u[@"output_tokens"] ?: @0, @"thinking": details[@"thinking_tokens"] ?: @0,
                                         @"list_cost_usd": j[@"total_cost_usd"] ?: @0, @"model": @"haiku"}];
    [t add:usage];
    return Dict(j[@"structured_output"]);
}

static NSString *Tilde(NSString *s) {
    NSString *home = NSHomeDirectory();
    return home.length > 1 ? [s stringByReplacingOccurrencesOfString:home withString:@"~"] : s;
}

static int Legacy(NSDictionary *day, NSDictionary *old, NSString *outPath) {
    NSDictionary *every = day[@"schedule"][@"legacy"];
    NSMutableDictionary<NSString *, RDTotal *> *totals = [NSMutableDictionary new];
    NSMutableDictionary *verdicts = [NSMutableDictionary new];
    NSInteger k = 0;
    for (NSDictionary *tick in day[@"ticks"]) {
        double at = [tick[@"at"] doubleValue], now = NSDate.date.timeIntervalSince1970;
        RDSnapshot *s = [RDSnapshot new];
        s.facts = FactsAt(tick, now); s.findings = FindingsAt(tick, now);
        for (id<MMExpert> e in Experts()) {
            NSString *eid = e.expertID;
            NSDictionary *spec = Dict(old[eid]);
            RDTotal *t = totals[eid] ?: (totals[eid] = [RDTotal new]);
            if (!spec || !every[eid]) { t.noRequest += [s findingsFor:eid].count; continue; }   // the 0.1 app asked no model
            if (k % MAX(1, [every[eid] integerValue] / 3600)) continue;
            MMReviewRequest *q = RequestFor(e, s);
            if (!q) continue;
            SetClock(at);
            t.reviews++;
            t.findings += q.findings.count; t.sent += q.findings.count;
            NSMutableArray *facts = [NSMutableArray new];
            for (MMFinding *f in q.findings) {
                NSMutableDictionary *x = [q.factsFor(f) mutableCopy];
                x[@"id"] = Tilde(f.findingID);
                [facts addObject:x];
            }
            NSString *iso = [NSISO8601DateFormatter stringFromDate:NSDate.date timeZone:NSTimeZone.localTimeZone formatOptions:NSISO8601DateFormatWithInternetDateTime];
            NSUInteger size = [spec[@"batch"] unsignedIntegerValue] ?: facts.count;
            NSMutableDictionary *words = [NSMutableDictionary new];
            NSUInteger batches = 0;
            for (NSUInteger i = 0; i < facts.count; i += size) {
                NSArray *batch = [facts subarrayWithRange:NSMakeRange(i, MIN(size, facts.count - i))];
                NSMutableDictionary *input = [@{@"now": iso, spec[@"list"]: batch} mutableCopy];
                if ([eid isEqualToString:@"locohost"]) { input[@"quiet_after_minutes"] = @((long)(MMLHIdleSeconds() / 60)); input[@"locohost_watching_minutes"] = @720; }
                NSDictionary *so = OldCall(spec[@"system"], spec[@"schema"], input, t);
                for (NSDictionary *a in so[[spec[@"schema"][@"required"] firstObject]]) if (Str(a[@"id"])) words[a[@"id"]] = a;
                batches++;
            }
            if (batches > 1 && Str(spec[@"summary"])) {
                // WorkForest 0.1, Review.m:464: one more call sees every tree as a line and writes the summary.
                NSMutableArray *lines = [NSMutableArray new];
                for (NSDictionary *x in facts) {
                    NSDictionary *a = words[x[@"id"]];
                    [lines addObject:@{@"repo": x[@"repo"] ?: @"", @"branch": x[@"branch"] ?: @"(detached)", @"verdict": a[@"verdict"] ?: @"none",
                                       @"about": a[@"about"] ?: @"", @"merged": x[@"merged"] ?: NSNull.null, @"quiet_days": x[@"quiet_days"] ?: @0,
                                       @"disk_mb": x[@"disk_mb"] ?: @0, @"cache_mb": x[@"cache_mb"] ?: @0}];
                }
                OldCall(spec[@"summary"], @{@"type": @"object", @"additionalProperties": @NO, @"required": @[@"summary"],
                                            @"properties": @{@"summary": @{@"type": @"string"}}}, @{@"lines": lines}, t);
            }
            for (MMFinding *f in q.findings) {
                NSString *w = Str(words[Tilde(f.findingID)][@"verdict"]);
                double c = [words[Tilde(f.findingID)][@"confidence"] doubleValue];
                // The same floor as the broker: below 0.6 a verdict counts as unsure.
                if (w && c < MMMinConfidence) w = [q.words wordFor:MMVerdictUnsure];
                verdicts[[NSString stringWithFormat:@"%ld|%@", (long)k, f.findingID]] = @{@"word": w ?: @"none", @"by": @"model"};
            }
        }
        k++;
    }
    NSMutableDictionary *per = [NSMutableDictionary new];
    for (NSString *eid in totals) per[eid] = totals[eid].json;
    Write(@{@"mode": @"legacy", @"experts": per, @"verdicts": verdicts}, outPath);
    return 0;
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc < 4) { fprintf(stderr, "usage: rvday broker <day.json> <out.json> | legacy <day.json> <legacy.json> <out.json>\n"); return 2; }
    NSDictionary *day = Dict([NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] ?: NSData.data options:0 error:nil]);
    if (!day) { fprintf(stderr, "rvday: bad day fixture\n"); return 2; }
    if (!strcmp(argv[1], "broker")) {
        BOOL fresh = NO, plain = NO;
        for (int i = 4; i < argc; i++) { if (!strcmp(argv[i], "--fresh")) fresh = YES; else if (!strcmp(argv[i], "--plain")) plain = YES; }
        return Broker(day, @(argv[3]), fresh, plain);
    }
    if (!strcmp(argv[1], "legacy") && argc >= 5) {
        NSDictionary *old = Dict([NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[3])] ?: NSData.data options:0 error:nil]);
        return old ? Legacy(day, old, @(argv[4])) : 2;
    }
    return 2;
}}
