// Ask MinMacs, tier 0, MMAsk.h: the rules that read a question and the answer each gives. Every answer is made of
// what the log, the rows and the plan already hold, in the words the window already uses. What no rule answers says
// so, with questions it can answer. MMAskCLI.m has the verb, the JSON and the ask row.
#import "Shell/MMAsk.h"
#import "Shell/MMWindowLogParts.h"
#import "Core/MMCore.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }

#pragma mark - Words

/// Small letters, curly quotes made plain, and every character but letters, digits and : . - _ / # made a space.
static NSString *Norm(NSString *s) {
    NSMutableString *out = [NSMutableString new];
    NSString *low = s.lowercaseString ?: @"";
    NSCharacterSet *keep = [NSCharacterSet characterSetWithCharactersInString:@":.-_/#'"];
    for (NSUInteger i = 0; i < low.length; i++) {
        unichar c = [low characterAtIndex:i];
        if (c == 0x2019 || c == 0x2018) c = '\'';
        BOOL ok = [NSCharacterSet.alphanumericCharacterSet characterIsMember:c] || [keep characterIsMember:c];
        [out appendFormat:@"%C", (unichar)(ok ? c : ' ')];
    }
    return out;
}

/// The words of a text, with what ends a sentence taken off each: "next.js." is "next.js", "what's" is "whats".
static NSArray<NSString *> *Words(NSString *s) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *w0 in [Norm(s) componentsSeparatedByString:@" "]) {
        NSString *w = [w0 stringByReplacingOccurrencesOfString:@"'" withString:@""];
        while (w.length && [@".:-/" containsString:[w substringFromIndex:w.length - 1]]) w = [w substringToIndex:w.length - 1];
        if (w.length) [out addObject:w];
    }
    return out;
}

/// A word as a name is compared: ":3000" and "3000" are one port.
static NSString *Bare(NSString *w) { return [w hasPrefix:@":"] ? [w substringFromIndex:1] : w; }

/// Words that say nothing about which thing is meant.
static NSSet<NSString *> *Filler(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[@"the", @"a", @"an", @"my", @"your", @"this", @"that", @"it", @"please", @"on", @"port", @"of", @"for", @"me",
                                  @"you", @"did", @"do", @"does", @"is", @"was", @"to", @"at", @"server", @"servers", @"app", @"apps", @"worktree",
                                  @"worktrees", @"agent", @"agents", @"cache", @"caches", @"called", @"named", @"one", @"thing", @"just", @"now",
                                  @"again", @"why", @"what", @"whats", @"tell", @"about", @"show", @"so", @"up", @"down", @"there", @"here", @"from",
                                  @"kept", @"stays", @"stay", @"still", @"running", @"alive", @"around", @"left"]];
    });
    return s;
}

static NSArray<NSString *> *Meant(NSArray<NSString *> *words) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *w in words) if (![Filler() containsObject:w]) [out addObject:w];
    return out;
}

/// How well what was asked for names this text: 100 the same, 80 one run of its words, 60 each of its words, 50 the
/// text is inside what was asked. 0 for no match. A word of three letters or more may be the start of a word.
static NSInteger Score(NSArray<NSString *> *asked, NSString *text) {
    if (!asked.count || !text.length) return 0;
    NSArray<NSString *> *have = Words(text);
    NSString *a = [asked componentsJoinedByString:@" "], *h = [have componentsJoinedByString:@" "];
    if ([Bare(a) isEqualToString:Bare(h)]) return 100;
    if ([[NSString stringWithFormat:@" %@ ", h] containsString:[NSString stringWithFormat:@" %@ ", a]]) return 80;
    BOOL each = YES;
    for (NSString *w in asked) {
        BOOL found = NO;
        for (NSString *x in have) if ([Bare(x) isEqualToString:Bare(w)] || (w.length >= 3 && [Bare(x) hasPrefix:Bare(w)])) { found = YES; break; }
        if (!found) { each = NO; break; }
    }
    if (each) return 60;
    if (h.length >= 3 && [[NSString stringWithFormat:@" %@ ", a] containsString:[NSString stringWithFormat:@" %@ ", h]]) return 50;
    return 0;
}

static BOOL Has(NSArray<NSString *> *words, NSArray<NSString *> *any) {
    for (NSString *w in any) if ([words containsObject:w]) return YES;
    return NO;
}

/// "“:3000”", for the words of an answer.
static NSString *Quoted(NSArray<NSString *> *asked) { return [NSString stringWithFormat:@"“%@”", [asked componentsJoinedByString:@" "]]; }

static NSString *Sentence(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return s;
    s = [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]];
    return [s hasSuffix:@"."] ? s : [s stringByAppendingString:@"."];
}

#pragma mark - Rows

static NSArray<MMWindowRow *> *AllRows(MMWindowModel *m) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups ?: @[], m.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) [out addObjectsFromArray:g.rows ?: @[]];
    return out;
}

static NSString *GroupOf(MMWindowModel *m, MMWindowRow *row) {
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups ?: @[], m.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) if ([g.rows containsObject:row]) return g.title;
    return nil;
}

/// The kind the words name, as "server" does, or -1.
static NSInteger KindHint(NSArray<NSString *> *words) {
    if (Has(words, @[@"server", @"servers", @"port"])) return MMWindowServer;
    if (Has(words, @[@"agent", @"agents", @"session"])) return MMWindowAgent;
    if (Has(words, @[@"worktree", @"worktrees", @"branch"])) return MMWindowWorktree;
    if (Has(words, @[@"cache", @"caches"])) return MMWindowCache;
    if (Has(words, @[@"app", @"apps"])) return MMWindowApp;
    return -1;
}

/// The row the words name best, or the row whose story shows for "it" and "this". A hint of a kind wins a tie.
static MMWindowRow *RowNamed(NSArray<NSString *> *words, MMAskWorld *w) {
    NSArray<NSString *> *asked = Meant(words);
    if (!asked.count) return w.row ? [w.model row:w.row] : nil;
    NSInteger hint = KindHint(words), best = 0;
    MMWindowRow *found = nil;
    for (MMWindowRow *r in AllRows(w.model)) {
        NSInteger s = MAX(Score(asked, r.shownName), MAX(Score(asked, r.nameInProject), Score(asked, r.name)));
        if (hint >= 0 && (NSInteger)r.kind == hint && s) s += 5;
        if (hint == MMWindowApp && (r.kind == MMWindowHelper || r.kind == MMWindowTabs) && s) s += 5;
        if (s > best) { best = s; found = r; }
    }
    return found;
}

#pragma mark - The log

static NSString *Clock(NSDate *d) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat = @"HH:mm";
    return [f stringFromDate:d];
}

/// The kinds of action each verb of a question means.
static NSArray<NSString *> *KindsOfVerb(NSString *w) {
    if ([@[@"quit", @"close", @"closed", @"closing", @"quitting"] containsObject:w]) return @[@"quit", @"tabs", @"trim"];
    if ([@[@"stop", @"stopped", @"stopping", @"kill", @"killed", @"end", @"ended", @"shut"] containsObject:w]) return @[@"stop"];
    if ([@[@"remove", @"removed", @"removing", @"delete", @"deleted", @"trash", @"trashed", @"clean", @"cleaned", @"wrap", @"wrapped", @"move", @"moved"] containsObject:w])
        return @[@"remove", @"trash", @"clean", @"tool", @"wrapup"];
    return nil;
}

static NSArray<NSString *> *ActionKinds(void) { return @[@"stop", @"quit", @"trash", @"remove", @"clean", @"tool", @"wrapup", @"tabs", @"trim"]; }

/// The past of an action, for a part of a Wrap Up, which the log tells inside its Wrap Up's entry.
static NSString *PartSentence(MMUndoRecord *r) {
    NSString *s = r.subject.length ? r.subject : @"something";
    NSString *verb = @{@"stop": @"Stopped", @"quit": @"Quit", @"remove": @"Removed the worktree", @"tabs": @"Closed",
                       @"clean": @"Ran the cleanup of", @"tool": @"Ran the cleanup of"}[r.kind ?: @""];
    if ([r.kind isEqualToString:@"trash"]) return [NSString stringWithFormat:@"Moved %@ to the Trash, in a Wrap Up.", s];
    return [NSString stringWithFormat:@"%@ %@, in a Wrap Up.", verb ?: @"Acted on", s];
}

/// What the newest review of the record's expert, before the action, said of its finding: "The review said: ...".
static NSString *VerdictOf(MMUndoRecord *r, NSArray<MMLogEntry *> *rows) {
    if (!r.findingID.length || !r.at) return nil;
    for (MMLogEntry *e in rows) {
        if (![e.table isEqualToString:@"review"] || [e.at timeIntervalSinceDate:r.at] > 60) continue;
        if (r.expert.length && e.expert.length && ![e.expert isEqualToString:r.expert]) continue;
        NSDictionary *v = Dict(Dict(e.body[@"verdicts"])[r.findingID]);
        if (!v) continue;
        NSString *reason = Str(v[@"reason"]);
        return reason ? [@"The review said: " stringByAppendingString:Sentence(reason)] : nil;
    }
    return nil;
}

/// "why did you stop :3000": the log's entries of the records that acted on it, newest first, each with its own why,
/// who acted and what the review said. Five at the most.
static MMWindowAnswer *Why(NSArray<NSString *> *words, MMAskWorld *w, MMWindowAnswer *a) {
    a.kind = @"why";
    NSArray<NSString *> *kinds = nil, *rest = words;
    for (NSUInteger i = 0; i < words.count; i++) {
        NSArray *k = KindsOfVerb(words[i]);
        if (k) { kinds = k; rest = [words subarrayWithRange:NSMakeRange(i + 1, words.count - i - 1)]; break; }
    }
    NSArray<NSString *> *asked = Meant(rest);
    if (!asked.count && w.row) {
        MMWindowRow *r = [w.model row:w.row];
        if (r) asked = Words(r.shownName);
    }
    if (!asked.count) {
        a.answer = @"Name what it acted on, such as “Why did you stop :3000”.";
        return a;
    }
    // Each record once, by its newest row, and the rows of each record, to find its entry in the log.
    MMWindowLog *log = MMWindowLogFrom(w.rows, w.now, 100000, 0, 0);
    NSMutableDictionary<NSNumber *, MMWindowLogEntry *> *byRow = [NSMutableDictionary new];
    for (MMWindowLogEntry *e in log.entries) byRow[@(e.row)] = e;
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *rowsOf = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, MMUndoRecord *> *records = [NSMutableDictionary new];
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    for (MMLogEntry *e in w.rows) {
        if (![e.table isEqualToString:@"undo"] || !e.rid.length) continue;
        if (!rowsOf[e.rid]) rowsOf[e.rid] = [NSMutableArray new];
        [rowsOf[e.rid] addObject:@(e.row)];
        if (records[e.rid]) continue;
        MMUndoRecord *r = [MMUndoRecord fromBody:e.body hasParts:NO];
        if (!r) continue;
        records[e.rid] = r; [order addObject:e.rid];
    }
    NSMutableArray<MMWindowAnswerEntry *> *out = [NSMutableArray new];
    NSInteger found = 0;
    for (NSString *rid in order) {
        MMUndoRecord *r = records[rid];
        if (![ActionKinds() containsObject:r.kind ?: @""] || (kinds && ![kinds containsObject:r.kind])) continue;
        if (Score(asked, r.subject) < 50) continue;
        found++;
        if (out.count >= 5) continue;
        MMWindowLogEntry *le = nil;
        for (NSNumber *n in rowsOf[rid]) if ((le = byRow[n])) break;
        MMUndoRecord *parent = r.parentRid.length ? records[r.parentRid] : nil;
        NSString *why = r.why.length ? r.why : parent.why;
        NSString *by = r.parentRid.length && parent ? parent.by : r.by;
        NSMutableArray *says = [NSMutableArray new];
        if (why.length && ![why isEqualToString:@"Fix Everything"]) [says addObject:[@"Its reason: " stringByAppendingString:Sentence(why)]];
        NSString *verdict = VerdictOf(r, w.rows) ?: (parent ? VerdictOf(parent, w.rows) : nil);
        if (verdict) [says addObject:verdict];
        MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
        x.sentence = le.sentence ?: PartSentence(r);
        x.why = says.count ? [says componentsJoinedByString:@" "] : nil;
        NSString *who = MMWindowLogWho(by, why);
        x.detail = le.detail ?: (r.at ? (who ? [NSString stringWithFormat:@"%@ · %@", Clock(r.at), who] : Clock(r.at)) : who);
        if (r.findingID.length && [w.model row:r.findingID]) x.row = r.findingID;
        else x.logKey = le.key;
        [out addObject:x];
    }
    a.entries = out;
    NSString *what = Quoted(asked);
    if (!found) a.answer = [NSString stringWithFormat:@"The log holds nothing MinMacs did to %@.", what];
    else a.answer = [NSString stringWithFormat:@"The log holds %@ on %@, newest first, each with its own reason.%@", MMWindowCount(found, @"action", @"actions"), what,
                     found > (NSInteger)out.count ? [NSString stringWithFormat:@" The newest %lu are here.", (unsigned long)out.count] : @""];
    return a;
}

#pragma mark - The plan

static NSString *Gains(uint64_t memory, uint64_t disk, BOOL partial) {
    NSMutableArray *parts = [NSMutableArray new];
    if (memory) [parts addObject:[MMWindowSizeText(memory, NO) stringByAppendingString:@" memory"]];
    if (disk) [parts addObject:[MMWindowSizeText(disk, YES) stringByAppendingString:partial ? @" or more disk" : @" disk"]];
    return parts.count ? [parts componentsJoinedByString:@" and "] : nil;
}

/// "what would you clean now": the plan of Fix Everything as the dock holds it, each fix with what it gives back, and
/// what a run would skip and why. It says what a press would do, never that the Mac is clean.
static MMWindowAnswer *Plan(MMAskWorld *w, MMWindowAnswer *a) {
    a.kind = @"plan";
    MMWindowModel *m = w.model;
    NSMutableArray<MMWindowAnswerEntry *> *out = [NSMutableArray new];
    for (MMWindowFix *f in m.fixes) {
        if (f.needsYou) continue;
        MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
        x.sentence = Sentence(f.title);
        NSMutableArray *back = [NSMutableArray new];
        if (f.memoryBack) [back addObject:[NSString stringWithFormat:@"+%@ memory", MMWindowSizeText(f.memoryBack, NO)]];
        if (f.diskBack) [back addObject:[NSString stringWithFormat:@"+%@ %@", MMWindowSizeText(f.diskBack, YES), f.diskPartial ? @"or more disk" : @"disk"]];
        x.detail = back.count ? [back componentsJoinedByString:@" · "] : f.diskPartial ? @"its size is not measured yet" : nil;
        [out addObject:x];
    }
    NSInteger runs = (NSInteger)out.count;
    for (MMWindowFix *f in m.fixes) {
        if (!f.needsYou) continue;
        MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
        x.sentence = Sentence(f.title);
        x.why = @"Skipped, since it waits for your own press.";
        [out addObject:x];
    }
    for (MMWindowRow *r in AllRows(m)) {
        if (!r.needsYou) continue;
        MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
        x.sentence = r.shownName;
        x.why = @"Skipped, since it asks you.";
        x.row = r.key;
        [out addObject:x];
    }
    a.entries = out;
    NSString *gains = Gains(m.memoryBack, m.diskBack, m.diskBackPartial);
    if (!runs) a.answer = out.count ? @"Fix Everything has no fixes to run now. What it would skip is below." : @"Fix Everything has no fixes to run now.";
    else a.answer = [NSString stringWithFormat:@"Fix Everything would run %@%@. Nothing runs until you press it.", MMWindowFixes(runs),
                     gains ? [@" and give back " stringByAppendingString:gains] : @""];
    return a;
}

#pragma mark - A row

/// "what is :3000": the row is made the active one, so its story shows. The answer holds the story's words too.
static MMWindowAnswer *About(NSArray<NSString *> *words, MMAskWorld *w, MMWindowAnswer *a) {
    a.kind = @"about";
    MMWindowRow *r = RowNamed(words, w);
    if (!r) {
        NSArray *asked = Meant(words);
        a.answer = asked.count ? [NSString stringWithFormat:@"Nothing in the window is named %@ now.", Quoted(asked)] : @"Name a server, an agent, a worktree or a cache.";
        return a;
    }
    a.row = r.key;
    NSString *group = GroupOf(w.model, r);
    NSMutableArray *lead = [NSMutableArray arrayWithObject:group ? [NSString stringWithFormat:@"%@, in %@.", r.shownName, group.lowercaseString] : [r.shownName stringByAppendingString:@"."]];
    MMWindowFate *fate = r.fate;
    if (fate.lead.length) [lead addObject:fate.lead];
    if (fate.note.length) [lead addObject:Sentence(fate.note)];
    a.answer = [lead componentsJoinedByString:@" "];
    NSMutableArray<MMWindowAnswerEntry *> *out = [NSMutableArray new];
    for (MMWindowFact *f in r.storyFacts) {
        MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
        x.sentence = [NSString stringWithFormat:@"%@: %@", f.label, f.value];
        if (f.link && [w.model row:f.link]) x.row = f.link;
        [out addObject:x];
    }
    a.entries = out;
    return a;
}

/// "keep fix-auth": the button the row's own menu has, Keep for 7 days or Keep for 4 hours. Nothing is kept here.
static MMWindowAnswer *Keep(NSArray<NSString *> *words, MMAskWorld *w, MMWindowAnswer *a) {
    a.kind = @"keep";
    NSMutableArray *rest = [NSMutableArray new];
    for (NSString *x in words) if (![@[@"keep", @"week", @"days", @"day", @"hours", @"hour", @"7", @"4", @"around", @"safe", @"dont", @"remove", @"stop"] containsObject:x]) [rest addObject:x];
    MMWindowRow *r = RowNamed(rest, w);
    if (!r) {
        NSArray *asked = Meant(rest);
        a.answer = asked.count ? [NSString stringWithFormat:@"Nothing in the window is named %@ now.", Quoted(asked)] : @"Name the server, worktree or cache to keep.";
        return a;
    }
    MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
    x.sentence = r.shownName; x.row = r.key;
    a.entries = @[x];
    BOOL kind = r.kind == MMWindowServer || r.kind == MMWindowWorktree || r.kind == MMWindowCache;
    if (!kind || r.members.count) {
        a.answer = r.members.count ? [NSString stringWithFormat:@"%@ stands for several. Keep one of them from its own story.", r.shownName]
                                   : [NSString stringWithFormat:@"MinMacs keeps servers, worktrees and caches. %@ is none of them.", r.shownName];
        return a;
    }
    NSString *expert = r.kind == MMWindowServer ? @"locohost" : r.kind == MMWindowWorktree ? @"workforest" : @"noonoo";
    BOOL hours = MMAskKeepFor(expert) < 86400;
    MMWindowSuggest *s = [MMWindowSuggest new];
    s.action = @"keep"; s.target = r.key; s.title = hours ? @"Keep for 4 hours" : @"Keep for 7 days";
    s.command = w.targets[r.key].command;
    s.help = [NSString stringWithFormat:@"No rule stops or removes it for %@. Fix Everything leaves it too.", hours ? @"4 hours" : @"7 days"];
    a.suggest = s;
    a.answer = [NSString stringWithFormat:@"A keep means no rule acts on %@ for %@. Nothing changes until you press %@.", r.shownName, hours ? @"4 hours" : @"7 days", s.title];
    return a;
}

/// "undo the last one", "undo :3000": the newest entry of the log that can still be taken back, with its Undo.
static MMWindowAnswer *Undo(NSArray<NSString *> *words, MMAskWorld *w, MMWindowAnswer *a) {
    a.kind = @"undo";
    NSMutableArray *rest = [NSMutableArray new];
    for (NSString *x in words) if (![@[@"undo", @"take", @"back", @"put", @"last", @"latest", @"newest", @"recent", @"most", @"action"] containsObject:x]) [rest addObject:x];
    NSArray<NSString *> *asked = Meant(rest);
    MMWindowLog *log = MMWindowLogFrom(w.rows, w.now, MMWindowLogMost, 0, 0);
    MMWindowLogEntry *found = nil;
    NSInteger best = 0;
    for (MMWindowLogEntry *e in log.entries) {
        if (!e.canUndo || !e.undoRid.length) continue;
        if (!asked.count) { found = e; break; }
        NSInteger s = Score(asked, e.sentence);
        if (s > best) { best = s; found = e; }
    }
    if (!found) {
        a.answer = asked.count ? [NSString stringWithFormat:@"Nothing in the log that can still be taken back matches %@.", Quoted(asked)]
                               : @"Nothing in the log can be taken back now.";
        return a;
    }
    MMWindowAnswerEntry *x = [MMWindowAnswerEntry new];
    x.sentence = found.sentence; x.detail = found.detail; x.logKey = found.key;
    a.entries = @[x];
    MMWindowSuggest *s = [MMWindowSuggest new];
    s.action = @"undo"; s.title = @"Undo"; s.target = found.undoRid;
    s.command = [@"minmacs restore " stringByAppendingString:found.undoRid];
    s.help = found.undoHelp;
    a.suggest = s;
    a.answer = [NSString stringWithFormat:@"%@ can still be taken back. Nothing changes until you press Undo.", asked.count ? @"This" : @"The newest thing"];
    return a;
}

#pragma mark - The rules

/// Questions it can answer, for the answer to one it cannot: with names from this Mac where there are some.
static NSArray<NSString *> *Examples(MMAskWorld *w) {
    NSString *why = @"Why did you stop :3000?";
    for (MMLogEntry *e in w.rows) {
        if (![e.table isEqualToString:@"undo"]) continue;
        MMUndoRecord *r = [MMUndoRecord fromBody:e.body hasParts:NO];
        NSString *verb = @{@"stop": @"stop", @"quit": @"quit", @"remove": @"remove", @"trash": @"remove"}[r.kind ?: @""];
        if (verb && r.subject.length) { why = [NSString stringWithFormat:@"Why did you %@ %@?", verb, r.subject]; break; }
    }
    MMWindowRow *first = AllRows(w.model).firstObject;
    return @[why, @"What would you clean now?", first ? [NSString stringWithFormat:@"What is %@?", first.shownName] : @"Undo the last one"];
}

NSString *MMAskQuestion(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return nil;
    NSString *one = [[raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    one = [one stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (one.length > MMAskMost) one = [one substringToIndex:[one rangeOfComposedCharacterSequenceAtIndex:MMAskMost].location];
    return one.length ? one : nil;
}

MMWindowAnswer *MMAskTier0(NSString *question, MMAskWorld *world) {
    MMWindowAnswer *a = [MMWindowAnswer new];
    a.question = MMAskQuestion(question) ?: @"";
    a.answeredBy = @"rules";
    world.now = world.now ?: NSDate.date;
    NSArray<NSString *> *words = Words(a.question);
    NSString *first = words.firstObject ?: @"";
    BOOL why = [words containsObject:@"why"];
    if (!why && (Has(words, @[@"undo"]) || [a.question.lowercaseString containsString:@"take back"] || [a.question.lowercaseString containsString:@"take it back"]))
        return Undo(words, world, a);
    if (!why && [first isEqualToString:@"keep"]) return Keep(words, world, a);
    if (why) {
        BOOL verb = NO;
        for (NSString *x in words) if (KindsOfVerb(x)) verb = YES;
        // "why is :3000 kept": no action to look up, so the row's story, whose first line says why it stays or goes.
        if (verb || !RowNamed(words, world)) return Why(words, world, a);
        return About(words, world, a);
    }
    if (Has(words, @[@"clean", @"fix", @"fixes", @"free", @"tidy", @"plan"]) || (Has(words, @[@"would", @"will"]) && Has(words, @[@"stop", @"quit", @"remove"])))
        return Plan(world, a);
    NSArray *about = @[@"what", @"whats", @"tell", @"about", @"show", @"who", @"where", @"explain", @"describe", @"info"];
    if ([about containsObject:first] || [words containsObject:@"about"]) {
        NSMutableArray *rest = [NSMutableArray new];
        for (NSString *x in words) if (![about containsObject:x] && ![@[@"is", @"are", @"me", @"running"] containsObject:x]) [rest addObject:x];
        return About(rest, world, a);
    }
    // No rule knows it. Nothing is made up: the answer says so, with questions it can answer.
    a.kind = @"unknown";
    a.answer = MMWindowAskCannot;
    a.examples = Examples(world);
    return a;
}

NSArray<NSString *> *MMAskNear(NSString *question, MMAskWorld *world) {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    NSArray<NSString *> *asked = Meant(Words(MMAskQuestion(question) ?: @""));
    // Each word on its own, so a row that one word names is near even when the question as a whole names none.
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    for (MMWindowRow *r in AllRows(world.model)) {
        if (rows.count >= 5) break;
        for (NSString *w in asked) {
            if (w.length < 3 && ![w hasPrefix:@":"]) continue;
            if (Score(@[w], r.shownName) || Score(@[w], r.name)) { [rows addObject:r]; break; }
        }
    }
    for (MMWindowRow *r in rows) {
        NSString *group = GroupOf(world.model, r);
        [out addObject:group ? [NSString stringWithFormat:@"A word of the question names %@, in %@.", r.shownName, group.lowercaseString]
                             : [NSString stringWithFormat:@"A word of the question names %@.", r.shownName]];
    }
    NSArray<NSString *> *examples = Examples(world);
    [out addObject:[@"The rules answer questions such as: " stringByAppendingString:[examples componentsJoinedByString:@" "]]];
    return out;
}
