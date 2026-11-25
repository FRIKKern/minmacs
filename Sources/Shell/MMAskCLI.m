// Ask MinMacs, MMAsk.h: what an answer is made from, the ask's row in the log, the JSON and `minmacs ask`.
#import "Shell/MMAsk.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMWindowLog.h"
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"

NSString *const MMLogAskTable = @"ask";
const NSUInteger MMAskMost = 1000;
static const NSUInteger kRows = 2000;                // the newest rows of each of the log's tables an answer reads

@implementation MMAskTarget
@end

NSTimeInterval MMAskKeepFor(NSString *expert) { return [expert isEqualToString:@"locohost"] ? 4 * 3600 : 7 * 86400; }

/// A word of a command as a shell reads it: as it is when it holds nothing a shell treats on its own, else quoted.
static NSString *ShellWord(NSString *s) {
    NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-~:@+,="];
    if (s.length && [s rangeOfCharacterFromSet:plain.invertedSet].location == NSNotFound) return s;
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

MMAskTarget *MMAskTargetOf(MMFinding *f) {
    if (!f.stableKey.length) return nil;
    MMAskTarget *t = [MMAskTarget new];
    t.expert = f.expert; t.stableKey = f.stableKey; t.name = MMWindowNameOf(f);
    BOOL server = [f.expert isEqualToString:@"locohost"] && [f.kind isEqualToString:@"server"];
    if (!server && ![f.expert isEqualToString:@"noonoo"] && !([f.expert isEqualToString:@"workforest"] && [f.kind isEqualToString:@"worktree"])) return nil;
    NSInteger port = [f.facts[@"port"] isKindOfClass:NSNumber.class] ? [f.facts[@"port"] integerValue] : 0;
    // `minmacs keep`, MMKeepCLI.m, by the port of a server and the path of the rest.
    if (server && port > 0) t.command = [NSString stringWithFormat:@"minmacs keep %ld", (long)port];
    else if (!server && f.path.length) t.command = [@"minmacs keep " stringByAppendingString:ShellWord(f.path)];
    return t;
}

@implementation MMAskWorld
+ (NSArray<MMLogEntry *> *)rowsOf:(MMLog *)log { return log ? [log rows:MMWindowLogTables() before:0 limit:kRows] : @[]; }
+ (NSDictionary<NSString *, MMAskTarget *> *)targetsOf:(MMWindowModel *)m snapshot:(MMSnapshot *)s {
    NSMutableDictionary *out = [NSMutableDictionary new];
    if (!s) return out;
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups ?: @[], m.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) {
            MMAskTarget *t = MMAskTargetOf([s finding:r.key]);
            if (t) out[r.key] = t;
        }
    return out;
}
@end

void MMAskLog(MMWindowAnswer *a, NSString *by) {
    if (!a.question.length) return;
    NSMutableDictionary *body = [@{@"question": a.question, @"kind": a.kind ?: @"unknown", @"answer": a.answer ?: @"", @"answeredBy": a.answeredBy ?: @"rules",
                                   @"by": by.length ? by : @"unknown"} mutableCopy];
    // Tier 1: the tokens Claude's call took, as a review's row counts them, and the model that answered.
    if (a.tokens || a.model.length || [a.answeredBy isEqualToString:@"claude"]) body[@"tokens"] = @(a.tokens);
    if (a.model.length) body[@"model"] = a.model;
    MMLogWhenOpen(^(MMLog *log) { [log append:MMLogAskTable rid:nil expert:@"minmacs" subject:a.kind state:@"answered" body:body]; });
}

static id Or(id v) { return v ?: NSNull.null; }

NSDictionary *MMAskJSON(MMWindowAnswer *a) {
    NSMutableArray *entries = [NSMutableArray new];
    for (MMWindowAnswerEntry *e in a.entries)
        [entries addObject:@{@"sentence": e.sentence ?: @"", @"why": Or(e.why), @"detail": Or(e.detail), @"row": Or(e.row), @"logKey": Or(e.logKey)}];
    MMWindowSuggest *s = a.suggest;
    id suggest = s ? @{@"action": s.action ?: @"", @"title": s.title ?: @"", @"target": s.target ?: @"", @"command": Or(s.command)} : NSNull.null;
    return @{@"question": a.question ?: @"", @"kind": a.kind ?: @"unknown", @"answer": a.answer ?: @"", @"answeredBy": a.answeredBy ?: @"rules",
             @"tokens": @(a.tokens), @"entries": entries, @"suggest": suggest, @"examples": a.examples ?: @[], @"row": Or(a.row)};
}

#pragma mark - The verb

static int AskVerb(MMArgs *a) {
    NSString *q = MMAskQuestion([a.words componentsJoinedByString:@" "]);
    if (!q) return [a usageError];
    MMSnapshot *s = a.snapshot;
    MMPerformance *p = [MMPerformance from:s history:a.inApp ? s.history : nil lookBack:[MMPerformanceLookBack read:MMGains.shared now:NSDate.date]];
    MMWindowExtras *x = [MMWindowExtras readWithLogin:NO];
    if (!a.inApp) x.cachesLooked = MMWindowLookedNowhere;
    MMAskWorld *w = [MMAskWorld new];
    w.model = MMWindowModelFrom(s, p, x);
    w.rows = [MMAskWorld rowsOf:MMLog.shared];
    w.targets = [MMAskWorld targetsOf:w.model snapshot:s];
    w.now = NSDate.date;
    MMWindowAnswer *answer = MMAskTier0(q, w);
    // Tier 1: what no rule answers goes to Claude, unless --no-model or the pref ask.claude says not to.
    if ([answer.kind isEqualToString:@"unknown"] && ![a has:@"--no-model"] && MMAskUsesClaude()) answer = MMAskTier1(answer, w, nil, nil);
    // Every ask is a row of the log, so it can be followed. Only an ask Claude answers sends anything, PRIVACY.md.
    MMAskLog(answer, @"cli");
    if (a.json) { [a printJSON:MMAskJSON(answer)]; return 0; }
    [a print:@"%@", answer.answer];
    if (answer.byline.length) [a print:@"  %@", answer.byline];
    for (MMWindowAnswerEntry *e in answer.entries) {
        [a print:@"  %@", e.sentence];
        if (e.why) [a print:@"    %@", e.why];
        if (e.detail) [a print:@"    %@", e.detail];
    }
    // The answer never acts. What it offers is the verb to run, by whoever asked.
    if (answer.suggest) [a print:answer.suggest.command ? @"To do it: %@" : @"%@ from its story in the window.", answer.suggest.command ?: answer.suggest.title];
    for (NSString *e in answer.examples) [a print:@"  %@", e];
    return 0;
}

MMVerbSpec *MMAskVerbSpec(void) {
    MMVerbSpec *v = [MMVerbSpec verb:@"ask" usage:@"ask <question> [--json] [--no-model]   ask MinMacs about what it did, would do or knows, answered from the log and the window; what no rule answers goes to Claude unless --no-model; it never acts"
                             mutates:NO run:^int(MMArgs *a) { return AskVerb(a); }];
    v.reads = MMVerbReadsCachedGit;
    return v;
}
