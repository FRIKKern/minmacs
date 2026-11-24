// The log's entry of a run, MMLogRunTable, and the window's own Undo presses over a log, MMWindowLog.h. A run is one
// entry: what it did and how many things it skipped in the sentence, each skip and why in the entry's more, and
// `minmacs log --json` gives the skips as the row holds them. Every word is in the window's words, DESIGN.md "Words":
// no aside in parentheses, no claim of a result.
#import "Shell/MMWindowLogParts.h"
#import "Core/MMCore.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSInteger Num(id v) { return [v isKindOfClass:NSNumber.class] ? [v integerValue] : 0; }

/// How many of one kind of skip there were, as a clause: "2 agents ask you", "1 failed".
static NSString *SkipClause(NSString *as, NSInteger n) {
    BOOL one = n == 1;
    if ([as isEqualToString:@"asks"]) return one ? @"1 agent asks you" : [NSString stringWithFormat:@"%ld agents ask you", (long)n];
    if ([as isEqualToString:@"press"]) return [NSString stringWithFormat:@"%ld %@ for your own press", (long)n, one ? @"waits" : @"wait"];
    if ([as isEqualToString:@"kept"]) return [NSString stringWithFormat:@"%ld %@ kept, since %@ in use or changed", (long)n, one ? @"was" : @"were", one ? @"it is" : @"they are"];
    if ([as isEqualToString:@"failed"]) return [NSString stringWithFormat:@"%ld failed", (long)n];
    if ([as isEqualToString:@"stopped"]) return [NSString stringWithFormat:@"%ld %@ not reached, since the run was stopped", (long)n, one ? @"was" : @"were"];
    return [NSString stringWithFormat:@"%ld could not start", (long)n];
}

static NSString *Joined(NSArray<NSString *> *parts) {
    if (parts.count < 2) return parts.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@", [[parts subarrayWithRange:NSMakeRange(0, parts.count - 1)] componentsJoinedByString:@", "], parts.lastObject];
}

static NSString *Cap(NSString *s) { return s.length ? [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]] : s; }
static NSString *Period(NSString *s) { return [s hasSuffix:@"."] ? s : [s stringByAppendingString:@"."]; }

MMWindowLogEntry *MMWindowLogRunEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = [row.body isKindOfClass:NSDictionary.class] ? row.body : @{};
    NSString *what = Str(b[@"what"]) ?: row.subject ?: @"";
    BOOL fix = [what isEqualToString:MMLogRunFixEverything];
    NSString *title = fix ? @"Fix Everything" : MMWindowLogRuleTitle(what) ?: @"A rule of its own";
    NSInteger planned = Num(b[@"planned"]), done = Num(b[@"done"]);
    // Only skips of the row's own shape are read, so a damaged row says less, never something made up.
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *skips = [NSMutableArray new];
    for (id x in [b[@"skipped"] isKindOfClass:NSArray.class] ? b[@"skipped"] : @[]) {
        if (![x isKindOfClass:NSDictionary.class]) continue;
        NSString *subject = Str(x[@"subject"]) ?: @"something", *why = Str(x[@"why"]) ?: @"it did not run", *as = Str(x[@"as"]) ?: @"blocked";
        [skips addObject:@{@"subject": subject, @"why": why, @"as": as}];
    }
    NSString *s;
    if (!planned && !done && !skips.count) s = [title stringByAppendingString:@": nothing was planned."];
    else if (!skips.count) s = [NSString stringWithFormat:@"%@: %ld done.", title, (long)done];
    else {
        NSMutableArray<NSString *> *clauses = [NSMutableArray new];
        for (NSString *as in @[@"asks", @"press", @"kept", @"blocked", @"failed", @"stopped"]) {
            NSInteger n = 0;
            for (NSDictionary *x in skips) {
                BOOL known = [@[@"asks", @"press", @"kept", @"failed", @"stopped"] containsObject:x[@"as"]];
                if ([x[@"as"] isEqualToString:as] || (!known && [as isEqualToString:@"blocked"])) n++;
            }
            if (n) [clauses addObject:SkipClause(as, n)];
        }
        s = [NSString stringWithFormat:@"%@: %ld done, %ld skipped. %@.", title, (long)done, (long)skips.count, Cap(Joined(clauses))];
    }
    // The whole story, for the tooltip and VoiceOver: each skip and why, then what came back.
    NSMutableArray<NSString *> *more = [NSMutableArray new];
    NSUInteger listed = 0;
    for (NSDictionary *x in skips) {
        if (listed++ == 12) { [more addObject:[NSString stringWithFormat:@"And %lu more.", (unsigned long)(skips.count - 12)]]; break; }
        [more addObject:[NSString stringWithFormat:@"Skipped %@: %@", x[@"subject"], Period(x[@"why"])]];
    }
    NSDictionary *gains = [b[@"gains"] isKindOfClass:NSDictionary.class] ? b[@"gains"] : @{};
    uint64_t memory = (uint64_t)MAX(Num(gains[@"memory"]), 0), disk = (uint64_t)MAX(Num(gains[@"disk"]), 0);
    NSMutableArray<NSString *> *back = [NSMutableArray new];
    if (memory) [back addObject:[MMWindowSizeText(memory, NO) stringByAppendingString:@" memory"]];
    if (disk) [back addObject:[MMWindowSizeText(disk, YES) stringByAppendingString:@" disk"]];
    if (back.count) [more addObject:[NSString stringWithFormat:@"It gave back %@.", Joined(back)]];
    NSString *by = Str(b[@"by"]);
    // A press on Fix Everything is the person's own: the sentence names it, so the quiet line says only who.
    NSString *who = [by isEqualToString:@"manual"] ? @"by you" : MMWindowLogWho(by, nil);
    MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"run", s, who, now);
    e.more = more.count ? [more componentsJoinedByString:@" "] : nil;
    e.skipped = skips;
    return e;
}

#pragma mark - The window's own presses

static MMWindowLogEntry *Copy(MMWindowLogEntry *e) {
    MMWindowLogEntry *c = [MMWindowLogEntry new];
    c.key = e.key; c.kind = e.kind; c.sentence = e.sentence; c.time = e.time; c.who = e.who; c.tokens = e.tokens; c.day = e.day;
    c.at = e.at; c.row = e.row; c.canUndo = e.canUndo; c.undoRid = e.undoRid; c.undoHelp = e.undoHelp; c.undoing = e.undoing;
    c.more = e.more; c.skipped = e.skipped;
    return c;
}

MMWindowLog *MMWindowLogWithUndo(MMWindowLog *log, NSSet<NSString *> *undoing, NSDictionary<NSString *, NSString *> *problems) {
    if (!log || (!undoing.count && !problems.count)) return log;
    NSMutableArray<MMWindowLogEntry *> *out = [NSMutableArray new];
    BOOL changed = NO;
    for (MMWindowLogEntry *e in log.entries) {
        NSString *rid = e.canUndo ? e.undoRid : nil;
        if (!rid || (![undoing containsObject:rid] && !problems[rid])) { [out addObject:e]; continue; }
        MMWindowLogEntry *c = Copy(e);
        if ([undoing containsObject:rid]) { c.undoing = YES; c.canUndo = NO; }
        // Undo did not go through: the record still stands, so the press stays, and the sentence says why.
        else c.sentence = [NSString stringWithFormat:@"%@ Undo did not go through: %@", e.sentence, Period(problems[rid])];
        [out addObject:c];
        changed = YES;
    }
    if (!changed) return log;
    MMWindowLog *l = [MMWindowLog new];
    l.entries = out; l.note = log.note;
    return l;
}
