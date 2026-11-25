// Ask MinMacs, tier 1, MMAsk.h: what the rules cannot answer goes to Claude, through the reviews' own `claude -p` on
// the person's login, MMModel's askClaude, with every tool off. It runs only on a person's or a verb's ask that the
// rules had no answer for, with the pref ask.claude on. What it sends is small and plain, MMAskContext, and listed
// in PRIVACY.md "Ask MinMacs". The answer is words. It never acts: an ACTION line becomes the rules' own button.
#import "Shell/MMAsk.h"
#import "Shell/MMWindowLog.h"
#import "Core/MMCore.h"

const NSUInteger MMAskContextMost = 8192;
const NSUInteger MMAskTurnsKept = 3;
NSString *const MMAskAskingLine = @"Asking Claude";
static const NSUInteger kLogLines = 20;           // the newest entries of the log, as sentences
static const NSUInteger kRowsMost = 5000;         // the bytes the rows may take, so the log always gets room
static const NSUInteger kAnswerMost = 700;        // the longest answer shown, in whole sentences

BOOL MMAskUsesClaude(void) { return MMPrefBool(MMAskClaudeKey, YES); }

NSTimeInterval MMAskClaudeTimeout(void) {
    double t = [NSProcessInfo.processInfo.environment[@"MINMACS_ASK_TIMEOUT"] doubleValue];
    return t > 0 && t < 30 ? t : 30;
}

@implementation MMAskTurn
+ (instancetype)question:(NSString *)q answer:(NSString *)a { MMAskTurn *t = [MMAskTurn new]; t.question = q ?: @""; t.answer = a ?: @""; return t; }
@end

#pragma mark - What is sent

/// One line as it may be sent: on one line, with secrets redacted, the home folder as ~ and anything that looks like a
/// path, "/Users/sam/x" or "~/code", as "a path". A row's name holds none, but a log sentence may.
static NSString *Plain(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    s = MMRedact(s) ?: @"";
    static NSRegularExpression *path; static dispatch_once_t once;
    dispatch_once(&once, ^{ path = [NSRegularExpression regularExpressionWithPattern:@"(?<![\\w:.])~?/[^\\s,;”\"']+" options:0 error:nil]; });
    s = [path stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"a path"];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSString *KindWord(MMWindowKind k) {
    switch (k) {
        case MMWindowServer: return @"server";
        case MMWindowAgent: return @"agent";
        case MMWindowApp: return @"app";
        case MMWindowHelper: return @"helper";
        case MMWindowTabs: return @"tabs";
        case MMWindowWorktree: return @"worktree";
        case MMWindowCache: return @"cache";
    }
    return @"thing";
}

/// ":3000 Next.js · server · 312 MB · idle · Goes with Fix Everything. Idle for 6 h."
static NSString *RowLine(MMWindowRow *r, MMWindowSide side) {
    NSMutableArray *parts = [NSMutableArray arrayWithObjects:r.shownName ?: r.name ?: @"", KindWord(r.kind), nil];
    if (r.showsSize) [parts addObject:MMWindowSizeText(r.bytes, side == MMWindowDisk)];
    else if (r.sizeWord.length) [parts addObject:r.sizeWord];
    if (r.state.length) [parts addObject:r.state];
    MMWindowFate *fate = r.fate;
    NSString *line = fate.lead.length ? (fate.note.length ? [NSString stringWithFormat:@"%@ %@", fate.lead, fate.note] : fate.lead) : nil;
    if (line.length) [parts addObject:line];
    return [@"- " stringByAppendingString:Plain([parts componentsJoinedByString:@" · "])];
}

static NSUInteger Bytes(NSString *s) { return [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]; }

/// Adds lines to out while they fit in room bytes. Returns how many did not fit.
static NSUInteger Fill(NSMutableString *out, NSArray<NSString *> *lines, NSUInteger room) {
    NSUInteger used = 0, left = 0;
    for (NSString *l in lines) {
        NSUInteger b = Bytes(l) + 1;
        if (left || used + b > room) { left++; continue; }
        [out appendFormat:@"%@\n", l]; used += b;
    }
    return left;
}

static NSString *Cut(NSString *s, NSUInteger most) {
    if (s.length <= most) return s;
    NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:most];
    return [[s substringToIndex:r.location] stringByAppendingString:@" [cut]"];
}

NSString *MMAskContext(NSString *question, MMAskWorld *w, MMWindowAnswer *rules, NSArray<MMAskTurn *> *turns) {
    NSMutableString *head = [NSMutableString new];
    [head appendFormat:@"The question: %@\n", Plain(Cut(MMAskQuestion(question) ?: @"", MMAskMost))];
    NSArray<MMAskTurn *> *recent = turns.count > MMAskTurnsKept ? [turns subarrayWithRange:NSMakeRange(turns.count - MMAskTurnsKept, MMAskTurnsKept)] : turns;
    if (recent.count) {
        [head appendString:@"\nAsked before in this window, oldest first:\n"];
        for (MMAskTurn *t in recent) [head appendFormat:@"Q: %@\nA: %@\n", Plain(Cut(t.question, 300)), Plain(Cut(t.answer, 400))];
    }
    MMWindowRing *ring = w.model.ring;
    NSMutableArray *mac = [NSMutableArray new];
    if (ring.memoryTotal) [mac addObject:[NSString stringWithFormat:@"memory %@ of %@ in use", MMWindowSizeText(ring.memoryUsed, NO), MMWindowSizeText(ring.memoryTotal, NO)]];
    if (ring.diskTotal) [mac addObject:[NSString stringWithFormat:@"disk %@ free of %@", MMWindowSizeText(ring.diskFree, YES), MMWindowSizeText(ring.diskTotal, YES)]];
    if (mac.count) [head appendFormat:@"\nThis Mac now: %@.\n", [mac componentsJoinedByString:@", "]];
    NSArray<NSString *> *near = MMAskNear(question, w);
    if (near.count) {
        [head appendString:@"\nThe rules had no answer. Their near matches:\n"];
        for (NSString *n in near) [head appendFormat:@"- %@\n", Plain(n)];
    }
    NSMutableString *out = [head mutableCopy];
    // The rows by group, as the window lists them.
    NSMutableArray<NSString *> *rows = [NSMutableArray new];
    for (NSArray<MMWindowGroup *> *side in @[w.model.memoryGroups ?: @[], w.model.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) {
            if (!g.rows.count) continue;
            [rows addObject:[NSString stringWithFormat:@"%@:", Plain(g.title)]];
            for (MMWindowRow *r in g.rows) [rows addObject:RowLine(r, g.side)];
        }
    NSMutableArray<NSString *> *log = [NSMutableArray new];
    MMWindowLog *l = MMWindowLogFrom(w.rows ?: @[], w.now ?: NSDate.date, 60, 0, 0);
    for (MMWindowLogEntry *e in l.entries) {
        if (log.count >= kLogLines) break;
        if ([e.kind isEqualToString:@"ask"]) continue;          // the turns above say what was asked
        [log addObject:[NSString stringWithFormat:@"- %@ %@ %@", Plain(e.day), Plain(e.time), Plain(e.sentence)]];
    }
    NSUInteger budget = MMAskContextMost - MIN(MMAskContextMost - 256, Bytes(out)) - 160;
    if (rows.count) {
        [out appendString:@"\nThe window's rows, by group: name · kind · size · state · whether it stays, goes or asks\n"];
        NSUInteger left = Fill(out, rows, MIN(kRowsMost, budget));
        if (left) [out appendFormat:@"and %lu more lines not sent\n", (unsigned long)left];
    } else [out appendString:@"\nThe window shows no rows.\n"];
    if (log.count) {
        [out appendString:@"\nThe log, newest first:\n"];
        NSUInteger used = Bytes(out);
        NSUInteger left = Fill(out, log, used + 64 < MMAskContextMost ? MMAskContextMost - used - 64 : 0);
        if (left) [out appendFormat:@"and %lu more entries not sent\n", (unsigned long)left];
    } else [out appendString:@"\nThe log is empty.\n"];
    // Never past the cap, whatever the parts held.
    while (Bytes(out) > MMAskContextMost && out.length) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    return out;
}

static NSString *System(void) {
    return @"You answer one question typed into Ask MinMacs, a macOS menu bar app. MinMacs watches the dev servers, coding agents, apps, "
           @"git worktrees and caches on this Mac, and stops, quits, removes or cleans them, always with a way back. "
           @"You get the question and a short plain summary of what MinMacs knows now. "
           @"Answer in plain text: one to three short sentences, with no markdown, no list, no heading and no emoji. "
           @"Say only what the summary supports, and say so when it does not hold the answer. A greeting gets a short greeting "
           @"and one thing you can help with. You cannot act, and never say that you did. "
           @"Only when one existing action would plainly help, end with one last line in exactly this form: "
           @"ACTION: keep <a server's port, or a worktree's or a cache's name, as the rows show it> or ACTION: undo <what a log entry acted on, or last>. "
           @"Otherwise write no ACTION line.";
}

#pragma mark - The answer

static MMWindowAnswer *From(MMWindowAnswer *rules) {
    MMWindowAnswer *a = [MMWindowAnswer new];
    a.serial = rules.serial; a.question = rules.question ?: @"";
    return a;
}

MMWindowAnswer *MMAskAsking(MMWindowAnswer *rules) {
    MMWindowAnswer *a = From(rules);
    a.kind = @"unknown"; a.answeredBy = @"rules"; a.asking = YES;
    a.answer = MMAskAskingLine;
    MMWindowSuggest *s = [MMWindowSuggest new];
    s.action = @"stop"; s.title = @"Stop"; s.target = @"ask";
    s.help = @"Stops asking Claude. Nothing was done, and nothing will be.";
    a.suggest = s;
    return a;
}

MMWindowAnswer *MMAskStopped(MMWindowAnswer *rules) {
    MMWindowAnswer *a = From(rules);
    a.kind = @"unknown"; a.answeredBy = @"rules";
    a.answer = @"Stopped before Claude answered. Nothing was done.";
    a.model = @"claude";
    a.examples = rules.examples ?: @[];
    return a;
}

/// Words as the middle shows them: one paragraph, no markdown marks and no ellipsis, at most kAnswerMost characters
/// of whole sentences.
static NSString *Shown(NSString *text) {
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *x in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if (x.length) [words addObject:x];
    NSString *s = [words componentsJoinedByString:@" "];
    for (NSString *mark in @[@"**", @"__", @"`", @"# "]) s = [s stringByReplacingOccurrencesOfString:mark withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"…" withString:@"."];
    while ([s containsString:@"..."]) s = [s stringByReplacingOccurrencesOfString:@"..." withString:@"."];
    if (s.length > kAnswerMost) {
        NSString *head = [s substringToIndex:[s rangeOfComposedCharacterSequenceAtIndex:kAnswerMost].location];
        NSRange end = [head rangeOfString:@". " options:NSBackwardsSearch];
        if (end.location != NSNotFound && end.location > 40) s = [head substringToIndex:end.location + 1];
        else {
            NSRange sp = [head rangeOfString:@" " options:NSBackwardsSearch];
            s = [(sp.location != NSNotFound ? [head substringToIndex:sp.location] : head) stringByAppendingString:@"."];
        }
    }
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

/// The rules' own button for an ACTION line: "keep 3001" asks the rules "keep 3001", "undo last" asks "undo the last
/// one". Only keep and undo, and only what a rule finds; nil for anything else.
static MMWindowAnswer *Action(NSString *line, MMAskWorld *w) {
    static NSRegularExpression *re; static dispatch_once_t once;
    dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"^ACTION:\\s*(keep|undo)\\s+(\\S.{0,199})$" options:NSRegularExpressionCaseInsensitive error:nil]; });
    NSTextCheckingResult *m = [re firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!m) return nil;
    NSString *verb = [line substringWithRange:[m rangeAtIndex:1]].lowercaseString;
    NSString *what = [[line substringWithRange:[m rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .\"'<>"]];
    if (!what.length) return nil;
    NSString *q = [verb isEqualToString:@"undo"] && [@[@"last", @"the last one", @"latest"] containsObject:what.lowercaseString]
                      ? @"undo the last one" : [NSString stringWithFormat:@"%@ %@", verb, what];
    MMWindowAnswer *x = MMAskTier0(q, w);
    return [x.kind isEqualToString:verb] && [x.suggest.action isEqualToString:verb] ? x : nil;
}

static NSString *TokenText(NSInteger n) {
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.numberStyle = NSNumberFormatterDecimalStyle; f.usesGroupingSeparator = YES; f.groupingSeparator = @",";
    return [NSString stringWithFormat:@"%@ %@", [f stringFromNumber:@(n)], n == 1 ? @"token" : @"tokens"];
}

MMWindowAnswer *MMAskFromClaude(MMWindowAnswer *rules, MMAskWorld *w, NSString *text, NSString *error, NSInteger tokens, NSString *model) {
    MMWindowAnswer *a = From(rules);
    a.tokens = MAX(tokens, 0); a.model = model;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *l in [text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) [lines addObject:l];
    while (lines.count && ![lines.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) [lines removeLastObject];
    MMWindowAnswer *action = nil;
    NSString *last = [lines.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([last.uppercaseString hasPrefix:@"ACTION:"]) { action = Action(last, w); [lines removeLastObject]; }
    NSString *shown = text ? Shown([lines componentsJoinedByString:@"\n"]) : nil;
    if (!shown.length) {
        // No words came back: say so, and why, with the rules' examples. Nothing is made up.
        a.kind = @"unknown"; a.answeredBy = @"rules"; a.examples = rules.examples ?: @[];
        NSString *why = error.length ? error : @"it gave no answer";
        if ([why containsString:@"did not answer within"])
            a.answer = [NSString stringWithFormat:@"Claude didn't answer within %.0f seconds, so there is no answer. The rules answer the questions below.", MMAskClaudeTimeout()];
        else {
            why = Shown(Cut(why, 200));
            while ([why hasSuffix:@"."]) why = [why substringToIndex:why.length - 1];
            a.answer = [NSString stringWithFormat:@"Claude isn't reachable: %@. The rules answer the questions below.", why.length ? why : @"it gave no answer"];
        }
        if (a.tokens) a.byline = [@"The try took " stringByAppendingString:TokenText(a.tokens)];
        return a;
    }
    a.kind = @"claude"; a.answeredBy = @"claude";
    a.answer = shown;
    a.byline = [@"Answered by Claude · " stringByAppendingString:TokenText(a.tokens)];
    if (action) { a.suggest = action.suggest; a.entries = action.entries ?: @[]; }
    return a;
}

MMWindowAnswer *MMAskTier1(MMWindowAnswer *rules, MMAskWorld *w, NSArray<MMAskTurn *> *turns, MMModelStop *stop) {
    NSString *context = MMAskContext(rules.question, w, rules, turns);
    MMAnswer *m = [MMModel askClaude:context system:System() timeout:MMAskClaudeTimeout() stop:stop];
    if (stop.stopped || [m.error isEqualToString:@"stopped"]) {
        MMWindowAnswer *a = MMAskStopped(rules);
        a.tokens = m.usage.uncached; a.model = m.model ?: a.model;
        return a;
    }
    NSString *text = [m.json[@"text"] isKindOfClass:NSString.class] ? m.json[@"text"] : nil;
    return MMAskFromClaude(rules, w, text, m.error, m.usage.uncached, m.model);
}
