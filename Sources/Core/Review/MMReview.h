// The review broker: one place that asks the model, for every expert. Patterns P39 to P47 of SYNTHESIS.md section 1.6.
// It runs on the person's own claude or codex login, with no API keys. Only Investigate gets tools: MinMacs's own
// Read, Grep and Glob over MCP, scoped to the subject's folders, Review/MMInvestigate.h.
// Rules decide first, the fingerprint cache sends only findings whose facts moved, and batches go out in parallel.
#import <Foundation/Foundation.h>
#import "Core/Graph/MMGraph.h"

/// P40. The usage of one model call, split as the CLI reports it.
/// New code. Both apps add cache reads at full weight today, WF Review.m:220-223.
/// Decision 10 measures review cost as two numbers: uncached tokens and list cost.
@interface MMUsage : NSObject
@property (readonly) NSInteger input, cacheWrite5m, cacheWrite1h, cacheRead, output;
@property (readonly) NSInteger thinking;                // a part of output, never added to it again
/// input + cacheWrite5m + cacheWrite1h + output. Cache reads are left out. The closest proxy for what counts
/// against a subscription. Research track F found no source on how a subscription weighs cache reads.
@property (readonly) NSInteger uncached;
@property (readonly) double listCostUSD;                // the list price the CLI reports; a subscription is not billed per call
@property (readonly) double seconds;
@property (readonly, copy) NSString *model;
- (NSDictionary *)json;
+ (instancetype)fromJSON:(NSDictionary *)json;
@end

/// P39. One model answer, parsed against the schema.
@interface MMAnswer : NSObject
@property (readonly) NSDictionary *json;                // nil when the call failed
@property (readonly, copy) NSString *model;             // the one that answered: haiku, gpt-6-luna, ...
@property (readonly, copy) NSString *error, *note;      // note: why the first choice was skipped, "Haiku: usage limit reached"
@property (readonly) MMUsage *usage;
@end

/// P39. A model call on the person's login: Haiku through `claude -p` first, Luna through codex when Claude
/// is missing, signed out or out of usage. Each call gets its own temp folder, so parallel calls never share a file.
/// Starts from WF Review.m:146-351, which fixed LocoHost's fixed temp file names.
/// input is sent as compact JSON with sorted keys, stable facts first, and null, false and zero fields dropped.
/// Blocks. Never on main.
@interface MMModel : NSObject
+ (NSString *)claudePath;                               // $MINMACS_CLAUDE, the review.claudePath pref, or the usual paths
+ (NSString *)codexPath;                                // $MINMACS_CODEX, the review.codexPath pref, or the usual paths
+ (MMAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
            input:(NSDictionary *)input effort:(NSString *)effort;   // effort "low" by default, research F3
@end

/// P41. The three verdicts Core stores. Decision 9: each expert keeps its own words in menus, prompts and --json.
typedef NS_ENUM(NSInteger, MMVerdictKind) { MMVerdictUnsure = 0, MMVerdictKeep = 1, MMVerdictGo = 2 };

/// P41. One expert's words for the three verdicts, such as LocoHost's in_use, idle and unsure,
/// or WorkForest's active, stale and unsure. The schema and the prompt use the words, and Core maps them back.
@interface MMVerdictWords : NSObject
@property (readonly, copy) NSString *keep, *go, *unsure;
+ (instancetype)keep:(NSString *)keep go:(NSString *)go unsure:(NSString *)unsure;
- (NSString *)wordFor:(MMVerdictKind)kind;
/// The kind for an expert's word. Any word it does not know maps to MMVerdictUnsure.
- (MMVerdictKind)kindFor:(NSString *)word;
@end

/// P41. What the review decided about one finding.
@interface MMVerdict : NSObject
@property MMVerdictKind kind;
@property (copy) NSString *word;                        // the expert's own word for kind
@property double confidence;
@property BOOL judged;                                  // the Eager judge of P44 decided it
@property (copy) NSString *findingID, *fingerprint;     // the fingerprint the verdict was made for
/// The instance the verdict was made for, such as pid:start. A verdict never carries to another instance, for any expert.
@property (copy) NSString *instanceKey;
/// MMReviewContext when the verdict was made: HEAD, an activity bucket and a size bucket. The cache carries a verdict
/// only while this and the fingerprint both hold.
@property (copy) NSString *context;
@property (copy) NSString *about, *reason, *keepEvidence;
@property (copy) NSString *decidedBy;                   // a rule id of P47, "model" or "judge"
@end

/// P41. One finished review of one expert. Saved to the log of P38, so history and the CLI share it.
/// Starts from LHReview and WFReview, LH Review.h and WF Review.h.
@interface MMReview : NSObject
@property (copy) NSString *expert, *trigger;            // trigger: schedule, new finding, age mark, memory pressure, manual
@property (copy) NSString *summary;                     // P45: numbers from code, words from the model
@property (copy) NSString *error, *judgeError;          // a failed judge keeps every finding it was asked about
@property (copy) NSString *note;                        // why the first model was skipped, "Haiku: usage limit reached"
@property (copy) NSString *summaryWords;                // the model's part of summary, kept while nothing moves
@property NSDate *at;
@property NSInteger mode;                               // the MMMode the review ran under
@property NSDictionary<NSString *, MMVerdict *> *verdicts;   // by findingID, carried over for findings that did not move
@property NSArray<MMUsage *> *calls;
@property NSArray<NSDictionary *> *actions;             // what the mode did after this review
/// Triage of this review: how many findings each rule decided, by ruleID, plus "cache", "model" and "judge".
@property NSDictionary<NSString *, NSNumber *> *decided;
@property NSInteger sent;                               // findings sent to the model, the judge left out
/// nil when the review has none, when the fingerprint moved since, or when the verdict names another instance.
- (MMVerdict *)verdictFor:(MMFinding *)f;
- (void)save;                                           // appends to the log
+ (instancetype)lastFor:(NSString *)expert;
+ (NSArray<MMReview *> *)historyFor:(NSString *)expert since:(NSDate *)since;
@end

/// P42. Removes values that look like secrets: key=value pairs with a secret-sounding key, the value after a --token
/// style flag, passwords in URLs, and long opaque strings. Starts from WFRedact, WF Common.m:29. nil in, nil out.
NSString *MMRedact(NSString *s);
/// P42. One line, redacted, the home folder as ~, at most max characters. nil for empty text.
NSString *MMClip(NSString *s, NSUInteger max);

/// P47. A rule decides a finding without the model. Rules are data where they can be, and code where they must.
/// New code. The broker counts how many findings each rule decides, so the share rules decide is a measured number.
@protocol MMRule <NSObject>
@property (readonly, copy) NSString *ruleID;            // "locohost.listen-only-no-traffic"
- (MMVerdict *)decide:(MMFinding *)f facts:(MMFacts *)facts;   // nil when the rule cannot tell
@end

/// The key Core adds to every expert's fingerprint, so the cache holds the same rule for all five: the git HEAD of the
/// worktree the finding sits in, the activity bucket of the newest session there, and a size bucket of what it frees.
/// Activity buckets: under 15 minutes, 2 hours and a day, then older, with "w" while a turn runs.
/// Size buckets: powers of four from 1 MB. Reads facts only, never the disk.
NSString *MMReviewContext(MMFinding *f, MMFacts *facts);

/// P47. Core's own rule, after the expert's rules: a finding with a work keep is kept, with its first keep reason.
extern NSString *const MMWorkKeepsRuleID;               // "core.work-keeps"

/// The daily review budget, measured as decision 10 says. The target is a fifth of today's 3.26M tokens a day,
/// and a bad day at a quarter is acceptable.
@interface MMBudget : NSObject
+ (instancetype)shared;
@property NSInteger dailyUncached;                      // 652,000 by default, a fifth of 3.26M
@property double dailyListCostUSD;                      // 0 means no cost limit
- (NSInteger)uncachedToday;
- (double)listCostToday;
- (NSDictionary<NSString *, MMUsage *> *)todayByExpert;
/// NO once the day is over budget. A scheduled review then waits. A manual review always runs.
- (BOOL)allows:(NSString *)trigger;
- (void)record:(MMUsage *)usage expert:(NSString *)expert;   // the broker calls this after every call
@end

/// One request to the broker: what to review, how, and in whose words.
@interface MMReviewRequest : NSObject
@property (copy) NSString *expert, *trigger, *model;    // model "auto" tries Haiku, then Luna
@property NSArray<MMFinding *> *findings;
@property MMFacts *facts;
@property (copy) NSString *system;                      // the expert's prompt
/// The schema of one finding's answer. nil gives the routine one in the expert's words: id, verdict, confidence,
/// about, reason and keep_evidence. The broker wraps it as {items, summary}.
@property NSDictionary *schema;
@property MMVerdictWords *words;
@property (copy) NSDictionary *(^factsFor)(MMFinding *f);   // what is sent per finding, redacted; docs/REVIEW.md lists it
/// Keys of factsFor that belong to the workstream, such as agent_session and branch. Where every finding of one block
/// has the same value, the broker sends it once in the block's ws. Facts every finding of a call shares go in all.
@property (copy) NSArray<NSString *> *sharedKeys;
@property NSUInteger batchSize, parallel;               // 25 and 3 by default, as WF Batches
@property BOOL judge;                                   // Eager: a second look at findings the review keeps
@property NSInteger mode;                               // the MMMode the review runs under, saved with it
@property (copy) NSString *judgeSystem;                 // the expert's judge prompt; nil uses Core's, in the expert's words
/// YES sends every finding to the model, past the fingerprint cache. Rules still decide first.
/// For a review the person asks for with --fresh, and for tests that review the same facts twice.
@property BOOL ignoreCache;
@end

/// P43 to P47. The one broker. Starts from WF Review.m. Every review runs on MMQueue(@"core", @"review").
@interface MMReviewBroker : NSObject
+ (instancetype)shared;
- (void)registerRules:(NSArray<id<MMRule>> *)rules expert:(NSString *)expert;
/// P46. Asks for a review. Wakes are coalesced, at least minGap apart per expert. A manual wake skips the gap.
- (void)wake:(NSString *)reason expert:(NSString *)expert;
@property NSTimeInterval minGap;                        // 10 minutes
/// P46. Ages in seconds that wake one review when a finding crosses them, such as a server up for a day.
- (void)setAgeMarks:(NSArray<NSNumber *> *)seconds expert:(NSString *)expert;
/// The expert's hook for a wake: it builds the request from the current snapshot. Runs on the review queue.
- (void)setRequestMaker:(MMReviewRequest *(^)(NSString *trigger, MMSnapshot *s))maker expert:(NSString *)expert;
/// P43, P44 and P47. Rules first, then the model for findings whose fingerprint moved, in batches in parallel,
/// then the judge when the request asks for it. Blocks, and saves the review before it returns.
- (MMReview *)run:(MMReviewRequest *)request;
/// P44. The judge on its own. The burden of proof is on the finding: it stays only with a concrete fact that
/// someone still needs it. A failed judge keeps. Starts from WF's judge through Batches, WF Review.m:410.
- (void)judge:(NSArray<MMFinding *> *)findings request:(MMReviewRequest *)request into:(MMReview *)review;
/// P45. Starts from WF Review.m:457. The counts come from code and the model only adds words around them.
- (NSString *)summarize:(MMReview *)review counts:(NSDictionary<NSString *, NSNumber *> *)counts request:(MMReviewRequest *)request;
/// PLAN.md section 4 and research F9. Investigate, only when the person asks: one call with a custom system prompt
/// and only MinMacs's own Read, Grep and Glob, scoped to the workstream's folders. It counts against MMBudget like
/// a review. MMInvestigations in Review/MMInvestigate.h runs it, for findings too, and saves it.
/// Returns the answer in words, or nil with *error. Blocks. Never on main.
- (NSString *)investigate:(MMWorkstream *)workstream question:(NSString *)question
                    usage:(MMUsage **)usage error:(NSString **)error;
/// How many findings each rule decided, since launch. Keyed by ruleID, plus "model" and "judge".
- (NSDictionary<NSString *, NSNumber *> *)decidedCounts:(NSString *)expert;
@end

extern const double MMMinConfidence;                    // 0.6: below it a verdict counts as unsure
extern const double MMSureConfidence;                   // 0.8: at or above it a mode may act on its own
