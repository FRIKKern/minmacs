// The log's entries from its rows, MMWindowLog.h. Every sentence is in the window's words, DESIGN.md "Words": plain
// names, no old app's name, no claim of a result, and "Undo" only where the record can still be taken back.
#import <stdatomic.h>
#import "Shell/MMWindowLogParts.h"
#import "Shell/MMWindowFeed.h"
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"

const NSUInteger MMWindowLogMost = 300;
const NSTimeInterval MMWindowLogDays = 30 * 86400;
static const NSUInteger kPage = 600;                 // rows per read
static const NSUInteger kMostRows = 6000;            // what one read of the window looks at, at the most

NSArray<NSString *> *MMWindowLogTables(void) { return @[@"undo", @"review", @"investigate", MMLogSettingTable, MMLogKeepTable, MMLogQuietTable, MMLogRunTable]; }

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }
static BOOL IsBool(id v) { return v && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID(); }

#pragma mark - Words

/// Who acted, as the quiet line says it. nil for a who the log does not know, so nothing made up stands there.
NSString *MMWindowLogWho(NSString *by, NSString *why) {
    if ([by isEqualToString:@"manual"]) return [why isEqualToString:@"Fix Everything"] ? @"by you, in Fix Everything" : @"by you";
    NSDictionary *w = @{@"window": @"by you in the window", @"settings": @"by you in Settings",
                        @"welcome": @"by you in the welcome", @"cli": @"from the command line", @"migration": @"by the move from the old apps",
                        @"proactive": @"on its own, Careful", @"eager": @"on its own, Eager", @"guard": @"by its own rule", @"run": @"in a Wrap Up"};
    return w[by ?: @""];
}

static NSString *Clock(NSDate *d) {
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat = @"HH:mm"; });
    @synchronized (f) { f.timeZone = NSTimeZone.localTimeZone; return [f stringFromDate:d]; }
}

static NSString *DayOf(NSDate *d, NSDate *now) {
    NSCalendar *cal = NSCalendar.currentCalendar;
    if ([cal isDate:d inSameDayAsDate:now]) return @"Today";
    if ([cal isDate:d inSameDayAsDate:[now dateByAddingTimeInterval:-86400]]) return @"Yesterday";
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"]; f.dateFormat = @"EEEE d MMMM"; });
    @synchronized (f) { f.timeZone = NSTimeZone.localTimeZone; return [f stringFromDate:d]; }
}

static NSString *Cap(NSString *s) { return s.length ? [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]] : s; }

/// A sentence from words that may end on a period of their own.
static NSString *Sentence(NSString *s) {
    s = [Cap(s) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [s hasSuffix:@"."] ? s : [s stringByAppendingString:@"."];
}

/// The rule a mode key belongs to, "Stop idle servers" for locohost.mode.
NSString *MMWindowLogRuleTitle(NSString *expert) {
    for (NSString *rid in MMWindowRuleIDs()) if ([MMWindowRuleExpert(rid) isEqualToString:expert]) return MMWindowRuleTitle(rid);
    return nil;
}

static NSString *ModeWord(id v) {
    NSInteger m = MMModeFrom(Str(v));
    return m >= 0 && m < (NSInteger)MMWindowChoiceTitles().count ? MMWindowChoiceTitles()[(NSUInteger)m] : nil;
}

static NSString *OnOff(id v) { return IsBool(v) || [v isKindOfClass:NSNumber.class] ? ([v boolValue] ? @"on" : @"off") : nil; }

/// What a setting's name is in the window, and how its values read. nil names a key the window has no words for.
static NSString *SettingSentence(NSString *key, id old, id now) {
    if ([key hasSuffix:@".mode"]) {
        NSString *title = MMWindowLogRuleTitle([key substringToIndex:key.length - 5]), *a = ModeWord(old), *b = ModeWord(now);
        if (title && a && b) return [NSString stringWithFormat:@"%@ changed from %@ to %@.", title, a, b];
        if (title && b) return [NSString stringWithFormat:@"%@ was set to %@.", title, b];
        return nil;
    }
    if ([key isEqualToString:MMReviewModelKey]) {
        NSString *a = Str(old) ?: @"auto", *b = Str(now);
        if (a && b) return [NSString stringWithFormat:@"The model reviews ask changed from %@ to %@.", a, b];
        return b ? [NSString stringWithFormat:@"The model reviews ask was set to %@.", b] : nil;
    }
    if ([key isEqualToString:MMWindowLoginKey]) return [NSString stringWithFormat:@"Open at login turned %@.", OnOff(now) ?: @"off"];
    if ([key isEqualToString:MMWindowWelcomedKey]) return @"Start was pressed in the welcome. The welcome does not come back.";
    return nil;
}

/// A keep-awake setting, which the keep-awake expert writes as an undo record of kind setting.
static NSString *AwakeSetting(NSDictionary *p) {
    NSString *key = Str(p[@"key"]);
    NSString *title = @{@"insomnia.lid": @"Keep working with the lid closed", @"insomnia.agents": @"Keep the Mac awake while agents work"}[key ?: @""];
    NSString *a = OnOff(p[@"from"]), *b = OnOff(p[@"to"]);
    if (title && b) return a ? [NSString stringWithFormat:@"%@ turned %@, from %@.", title, b, a] : [NSString stringWithFormat:@"%@ turned %@.", title, b];
    return @"A keep-awake setting changed.";
}

/// What an action did, by its kind, and how Undo takes it back. done is the past, todo what it set out to do, back
/// what a restore did when its action is out of reach, and again what the quiet line says of a restore beside its
/// action's time: "12:00, started again 12:05".
static void ActionWords(MMUndoRecord *r, NSInteger parts, NSString **done, NSString **todo, NSString **undo, NSString **back, NSString **again) {
    NSString *s = r.subject.length ? r.subject : @"something";
    NSString *k = r.kind ?: @"";
    *again = @{@"stop": @"started again", @"quit": @"opened again", @"trash": @"moved back", @"remove": @"brought back", @"clean": @"put back",
               @"tool": @"put back", @"wrapup": @"brought back", @"tabs": @"opened again", @"trim": @"opened again", @"lid": @"set back",
               @"setting": @"set back"}[k] ?: @"taken back";
    if ([k isEqualToString:@"stop"]) { *done = [@"Stopped " stringByAppendingString:s]; *todo = [@"stop " stringByAppendingString:s]; *undo = @"Undo starts it again."; *back = [@"Started again: " stringByAppendingString:s]; }
    else if ([k isEqualToString:@"quit"]) { *done = [@"Quit " stringByAppendingString:s]; *todo = [@"quit " stringByAppendingString:s]; *undo = @"Undo opens it again."; *back = [@"Opened again: " stringByAppendingString:s]; }
    else if ([k isEqualToString:@"trash"]) { *done = [NSString stringWithFormat:@"Moved %@ to the Trash", s]; *todo = [NSString stringWithFormat:@"move %@ to the Trash", s]; *undo = @"Undo moves it back."; *back = [@"Moved back from the Trash: " stringByAppendingString:s]; }
    else if ([k isEqualToString:@"remove"]) { *done = [@"Removed the worktree " stringByAppendingString:s]; *todo = [@"remove the worktree " stringByAppendingString:s]; *undo = @"Undo brings it back."; *back = [@"Brought back the worktree " stringByAppendingString:s]; }
    else if ([k isEqualToString:@"clean"] || [k isEqualToString:@"tool"]) { *done = [@"Ran the cleanup of " stringByAppendingString:s]; *todo = [@"run the cleanup of " stringByAppendingString:s]; *undo = @"Undo puts the recovery copy back."; *back = [NSString stringWithFormat:@"Put back what the cleanup of %@ took", s]; }
    else if ([k isEqualToString:@"wrapup"]) {
        NSString *name = [s hasPrefix:@"Wrap Up "] ? [s substringFromIndex:8] : s;
        *done = parts > 0 ? [NSString stringWithFormat:@"Wrapped up %@ in %@", name, MMWindowCount(parts, @"step", @"steps")] : [@"Wrapped up " stringByAppendingString:name];
        *todo = [@"wrap up " stringByAppendingString:name]; *undo = @"Undo brings it all back."; *back = [NSString stringWithFormat:@"Brought back what the Wrap Up of %@ took", name];
    }
    else if ([k isEqualToString:@"tabs"]) { *done = [@"Closed " stringByAppendingString:s]; *todo = [@"close " stringByAppendingString:s]; *undo = @"Undo opens them again."; *back = [@"Opened again: " stringByAppendingString:s]; }
    else if ([k isEqualToString:@"trim"]) { *done = [@"Closed the noise tabs of " stringByAppendingString:s]; *todo = [@"close the noise tabs of " stringByAppendingString:s]; *undo = @"Undo opens them again."; *back = [NSString stringWithFormat:@"Opened the tabs of %@ again", s]; }
    else if ([k isEqualToString:@"lid"]) {
        BOOL on = MMRecordFlag(r.payload, @"lid");
        *done = on ? @"The Mac now keeps running with the lid shut" : @"The Mac sleeps again when the lid shuts";
        *todo = on ? @"keep the Mac running with the lid shut" : @"let the Mac sleep when the lid shuts"; *undo = @"Undo sets it back."; *back = @"The lid setting was set back";
    }
    else if ([k isEqualToString:@"setting"]) { *done = AwakeSetting(r.payload); *todo = @"change a keep-awake setting"; *undo = @"Undo sets it back."; *back = @"A keep-awake setting was set back"; }
    else if ([k isEqualToString:@"quiet"]) { *done = [s stringByAppendingString:@" began"]; *todo = [@"keep quiet: " stringByAppendingString:s]; *undo = @""; *back = @"The quiet hold ended"; }
    else if ([k isEqualToString:@"hold"]) { *done = [@"Kept the Mac awake for " stringByAppendingString:s]; *todo = [@"keep the Mac awake for " stringByAppendingString:s]; *undo = @""; *back = @"The hold ended"; }
    else { *done = [@"Acted on " stringByAppendingString:s]; *todo = [@"act on " stringByAppendingString:s]; *undo = @"It can be undone."; *back = [@"Took back what was done to " stringByAppendingString:s]; }
    // A record an older MinMacs wrote under its Delete choice: the thing was deleted, not moved, so the words say so.
    if (r.deletedNow && !r.canRestore && ([k isEqualToString:@"trash"] || [k isEqualToString:@"remove"] || [k isEqualToString:@"clean"]))
        *done = [@"Deleted " stringByAppendingString:s];
}

static NSInteger Tokens(NSArray *calls) {
    NSInteger n = 0;
    for (NSDictionary *c in calls) n += [Dict(c)[@"uncached"] integerValue];
    return n;
}

static NSString *ReviewNoun(NSString *expert) {
    return @{@"locohost": @"servers", @"minmacs": @"apps and agents", @"workforest": @"worktrees", @"noonoo": @"caches and leftovers", @"insomnia": @"what keeps the Mac awake"}[expert ?: @""] ?: @"what it watches";
}

/// A scheduled review that acted on nothing and did not fail: these fold into one line.
static BOOL Quiet(MMLogEntry *e) {
    NSDictionary *b = e.body;
    return [e.table isEqualToString:@"review"] && [Str(b[@"trigger"]) isEqualToString:@"schedule"] && !Str(b[@"error"]) && List(b[@"actions"]).count == 0;
}

#pragma mark - Entries

MMWindowLogEntry *MMWindowLogEntryOf(MMLogEntry *row, NSString *kind, NSString *sentence, NSString *who, NSDate *now) {
    MMWindowLogEntry *e = [MMWindowLogEntry new];
    e.key = [NSString stringWithFormat:@"%@:%lld", row.table, row.row];
    e.kind = kind; e.sentence = sentence; e.who = who;
    e.at = row.at.timeIntervalSince1970; e.row = row.row;
    e.time = Clock(row.at); e.day = DayOf(row.at, now);
    return e;
}

/// The quiet line's time of an action that was taken back: "12:00, started again 12:05", with the day when the
/// restore came on another one.
static NSString *BackTime(NSDate *at, NSDate *back, NSString *again, NSDate *now) {
    NSString *day = DayOf(back, now);
    if ([day isEqualToString:DayOf(at, now)]) return [NSString stringWithFormat:@"%@, %@ %@", Clock(at), again, Clock(back)];
    BOOL near = [day isEqualToString:@"Today"] || [day isEqualToString:@"Yesterday"];
    return [NSString stringWithFormat:@"%@, %@ %@%@ at %@", Clock(at), again, near ? @"" : @"on ", near ? day.lowercaseString : day, Clock(back)];
}

/// One undo row's entry. ended holds the records whose done or failed row is in reach, and backAt when each record
/// read so far, newest first, was taken back: a restore is told in its action's entry, with both times.
static MMWindowLogEntry *UndoEntry(MMLogEntry *row, NSDictionary<NSString *, NSNumber *> *parts, NSSet<NSString *> *newer, NSSet<NSString *> *ended,
                                   NSDictionary<NSString *, NSDate *> *backAt, NSDate *now) {
    MMUndoRecord *r = [MMUndoRecord fromBody:row.body hasParts:[parts[row.rid] integerValue] > 0];
    if (!r || r.parentRid.length) return nil;               // a part is told with its Wrap Up
    NSString *done = @"", *todo = @"", *undo = @"", *back = @"", *again = @"";
    ActionWords(r, [parts[r.rid] integerValue], &done, &todo, &undo, &back, &again);
    NSDate *backed = r.rid ? backAt[r.rid] : nil;
    NSString *who = MMWindowLogWho(r.by, r.why);
    // A quiet hold that ended is told once, by its end row, from its start to its end.
    if ([r.kind isEqualToString:@"quiet"] && r.state == MMUndoDone) {
        if ([newer containsObject:[r.rid stringByAppendingString:@"#quiet-ended"]]) return nil;
        NSString *s = r.subject.length ? r.subject : @"Quiet";
        // A hold taken by an older MinMacs named its pid in parentheses, which the window's words never hold.
        s = [s stringByReplacingOccurrencesOfString:@" \\(pid ([0-9]+)\\)" withString:@", pid $1"
                                            options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
        NSString *comma = [s rangeOfString:@", pid "].location != NSNotFound ? @"," : @"";
        return MMWindowLogEntryOf(row, @"quiet", [NSString stringWithFormat:@"%@%@ since %@. It lasts while that process runs.", s, comma, Clock(row.at)], who, now);
    }
    switch (r.state) {
        case MMUndoRestored:
            // The action's own entry tells it, with both times. Only a restore whose action is out of reach stands alone.
            if ([ended containsObject:r.rid]) return nil;
            return MMWindowLogEntryOf(row, @"restored", Sentence(back), who, now);
        case MMUndoFailed: {
            NSString *err = r.error.length ? [@" " stringByAppendingString:Sentence(r.error)] : @"";
            MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"failed", [NSString stringWithFormat:@"Could not %@.%@", todo, err], who, now);
            if (backed) e.time = BackTime(row.at, backed, again, now);
            return e;
        }
        case MMUndoPending:
            // A pending row with a later row of its record is the start of that record, told by the later row.
            if ([newer containsObject:r.rid]) return nil;
            return MMWindowLogEntryOf(row, @"began", [NSString stringWithFormat:@"Began to %@. No end is written yet.", todo], who, now);
        case MMUndoDone: {
            if (backed) {
                MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"restored", Sentence(done), who, now);
                e.time = BackTime(row.at, backed, again, now);
                return e;
            }
            // Undo only for a record that can still be taken back, that restore would not refuse, and that keeps a way
            // back: never for a deleted thing, a tool's own cleanup or a damaged record.
            BOOL can = r.canRestore && !r.damage && r.rid.length && undo.length;
            NSString *tail = can ? [@" " stringByAppendingString:undo]
                           : r.deletedNow && !r.canRestore ? @" It cannot be brought back." : @"";
            MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"action", [Sentence(done) stringByAppendingString:tail], who, now);
            e.canUndo = can;
            if (can) { e.undoRid = r.rid; e.undoHelp = undo; }
            return e;
        }
    }
    return nil;
}

static MMWindowLogEntry *ReviewEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = row.body;
    NSString *noun = ReviewNoun(Str(b[@"expert"]) ?: row.expert);
    NSDictionary *verdicts = Dict(b[@"verdicts"]) ?: @{};
    NSInteger kept = 0, go = 0;
    for (id v in verdicts.allValues) {
        NSString *k = Str(Dict(v)[@"kind"]);
        if ([k isEqualToString:@"keep"]) kept++; else if ([k isEqualToString:@"go"]) go++;
    }
    NSInteger acted = (NSInteger)List(b[@"actions"]).count;
    NSString *s;
    if (Str(b[@"error"])) s = [NSString stringWithFormat:@"The review of %@ did not run to its end.", noun];
    else {
        NSMutableString *m = [NSMutableString stringWithFormat:@"Review of %@: looked at %ld, kept %ld", noun, (long)verdicts.count, (long)kept];
        if (go) [m appendFormat:@", %ld can go", (long)go];
        if (acted) [m appendFormat:@", acted on %ld", (long)acted];
        [m appendString:@"."];
        s = m;
    }
    NSString *trigger = Str(b[@"trigger"]);
    NSString *who = [trigger isEqualToString:@"manual"] ? @"asked by you" : [trigger isEqualToString:@"schedule"] ? @"on its hourly round" : trigger ? @"on its own" : nil;
    MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"review", s, who, now);
    e.tokens = Tokens(List(b[@"calls"]));
    return e;
}

/// A run of quiet reviews, newest first, as one line.
static MMWindowLogEntry *Folded(NSArray<MMLogEntry *> *run, NSDate *now) {
    MMLogEntry *newest = run.firstObject, *oldest = run.lastObject;
    MMWindowLogEntry *e = MMWindowLogEntryOf(newest, @"reviews", [NSString stringWithFormat:@"%@ acted on nothing.", Cap(MMWindowCount((NSInteger)run.count, @"review", @"reviews"))],
                                @"on its hourly round", now);
    e.key = [NSString stringWithFormat:@"reviews:%lld", oldest.row];
    // A run within one minute has one time: "02:58", never "02:58 to 02:58".
    NSString *from = Clock(oldest.at), *to = Clock(newest.at);
    e.time = [from isEqualToString:to] ? to : [NSString stringWithFormat:@"%@ to %@", from, to];
    NSInteger t = 0;
    for (MMLogEntry *r in run) t += Tokens(List(r.body[@"calls"]));
    e.tokens = t;
    return e;
}

static MMWindowLogEntry *InvestigateEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = row.body;
    NSString *what = Str(b[@"title"]) ?: Str(b[@"subject"]) ?: @"a folder";
    NSString *model = Str(b[@"model"]);
    BOOL ok = Str(b[@"answer"]) != nil;
    MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"investigate", ok ? [NSString stringWithFormat:@"Looked into %@.", what]
                                                        : [NSString stringWithFormat:@"Could not look into %@. The model did not answer.", what],
                                model ? [@"with " stringByAppendingString:model] : nil, now);
    e.tokens = [Dict(b[@"usage"])[@"uncached"] integerValue];
    return e;
}

static MMWindowLogEntry *SettingEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = row.body;
    NSString *s = SettingSentence(Str(b[@"key"]) ?: row.subject ?: @"", b[@"old"], b[@"new"]);
    return MMWindowLogEntryOf(row, @"setting", s ?: @"A setting changed.", MMWindowLogWho(Str(b[@"by"]), nil), now);
}

static MMWindowLogEntry *KeepEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = row.body;
    NSString *name = Str(b[@"name"]) ?: row.subject ?: @"something";
    NSNumber *until = [b[@"until"] isKindOfClass:NSNumber.class] ? b[@"until"] : nil;
    NSString *s;
    if (until) {
        NSString *span = MMWindowSpan(until.doubleValue - row.at.timeIntervalSince1970);
        s = span ? [NSString stringWithFormat:@"Kept %@ for %@. No rule acts on it until then.", name, span] : [NSString stringWithFormat:@"Kept %@.", name];
    } else s = [NSString stringWithFormat:@"%@ is no longer kept. The rules decide for it again.", name];
    // A keep is given from a menu or the command line, so a manual one says where.
    NSString *by = Str(b[@"by"]);
    return MMWindowLogEntryOf(row, @"keep", s, [by isEqualToString:@"manual"] ? @"by you in a menu" : MMWindowLogWho(by, nil), now);
}

/// A quiet hold that ended: "Quiet for a screen recording, pid 4123, 12:03 to 12:41." No parentheses: docs/DESIGN.md.
static MMWindowLogEntry *QuietEndEntry(MMLogEntry *row, NSDate *now) {
    NSDictionary *b = row.body;
    NSString *reason = Str(b[@"reason"]) ?: @"a task";
    NSInteger pid = [b[@"pid"] integerValue];
    NSNumber *since = [b[@"since"] isKindOfClass:NSNumber.class] ? b[@"since"] : nil, *until = [b[@"until"] isKindOfClass:NSNumber.class] ? b[@"until"] : nil;
    NSString *what = [NSString stringWithFormat:@"Quiet for %@, pid %ld", reason, (long)pid];
    NSString *how = Str(b[@"how"]), *s, *who;
    NSString *from = since ? Clock([NSDate dateWithTimeIntervalSince1970:since.doubleValue]) : nil;
    if (from && until) s = [NSString stringWithFormat:@"%@, %@ to %@.", what, from, Clock([NSDate dateWithTimeIntervalSince1970:until.doubleValue])];
    else if (from) s = [NSString stringWithFormat:@"%@ from %@. It ended while MinMacs did not run.", what, from];
    else s = [what stringByAppendingString:@" ended."];
    if ([how isEqualToString:@"released"]) who = MMWindowLogWho(Str(b[@"by"]), nil) ?: @"when it was released";
    else if ([how isEqualToString:@"exited"]) who = @"when its process ended";
    else who = @"when MinMacs started again";
    MMWindowLogEntry *e = MMWindowLogEntryOf(row, @"quiet", s, who, now);
    return e;
}

MMWindowLog *MMWindowLogFrom(NSArray<MMLogEntry *> *rows, NSDate *now, NSUInteger most, NSTimeInterval maxAge, NSTimeInterval watchingLeft) {
    now = now ?: NSDate.date;
    // What each record holds in these rows: how many parts a Wrap Up has, and which records have their done or failed
    // row in reach, so a restore is told in that row's entry.
    NSMutableDictionary<NSString *, NSMutableSet *> *partsOf = [NSMutableDictionary new];
    NSMutableSet<NSString *> *ended = [NSMutableSet new];
    for (MMLogEntry *r in rows) {
        if (![r.table isEqualToString:@"undo"]) continue;
        NSString *parent = Str(r.body[@"parentRid"]);
        if (parent && r.rid) { if (!partsOf[parent]) partsOf[parent] = [NSMutableSet new]; [partsOf[parent] addObject:r.rid]; }
        BOOL inReach = maxAge <= 0 || -[r.at timeIntervalSinceDate:now] <= maxAge;
        if (inReach && r.rid && ([r.state isEqualToString:@"done"] || [r.state isEqualToString:@"failed"])) [ended addObject:r.rid];
    }
    NSMutableDictionary<NSString *, NSNumber *> *parts = [NSMutableDictionary new];
    for (NSString *k in partsOf) parts[k] = @(partsOf[k].count);

    NSMutableArray<MMWindowLogEntry *> *out = [NSMutableArray new];
    NSMutableSet<NSString *> *newer = [NSMutableSet new];
    NSMutableDictionary<NSString *, NSDate *> *backAt = [NSMutableDictionary new];
    // The quiet reviews of one day fold into one line, which stands where the newest of them does, whatever came
    // between them: they acted on nothing, so no entry between them depends on them. The line holds its place in the
    // list from the first of them on, and is made once the day's rows are read.
    NSMutableArray<MMLogEntry *> *quiet = [NSMutableArray new];
    __block NSUInteger slot = 0;
    __block NSString *quietDay = nil;
    void (^flush)(void) = ^{
        if (!quiet.count) return;
        out[slot] = quiet.count == 1 ? ReviewEntry(quiet.firstObject, now) : Folded(quiet, now);
        [quiet removeAllObjects];
    };
    for (MMLogEntry *r in rows) {
        if (out.count >= most) break;
        if (maxAge > 0 && -[r.at timeIntervalSinceDate:now] > maxAge) break;
        NSString *day = DayOf(r.at, now);
        if (quiet.count && ![day isEqualToString:quietDay]) flush();
        if (Quiet(r)) {
            if (!quiet.count) { slot = out.count; quietDay = day; [out addObject:[MMWindowLogEntry new]]; }
            [quiet addObject:r];
            continue;
        }
        MMWindowLogEntry *e = nil;
        if ([r.table isEqualToString:@"undo"]) {
            e = UndoEntry(r, parts, newer, ended, backAt, now);
            if (r.rid) {
                [newer addObject:r.rid];
                if ([r.state isEqualToString:@"restored"] && !backAt[r.rid]) backAt[r.rid] = r.at;
            }
        }
        else if ([r.table isEqualToString:@"review"]) e = ReviewEntry(r, now);
        else if ([r.table isEqualToString:@"investigate"]) e = InvestigateEntry(r, now);
        else if ([r.table isEqualToString:MMLogSettingTable]) e = SettingEntry(r, now);
        else if ([r.table isEqualToString:MMLogKeepTable]) e = KeepEntry(r, now);
        else if ([r.table isEqualToString:MMLogRunTable]) e = MMWindowLogRunEntry(r, now);
        else if ([r.table isEqualToString:MMLogQuietTable]) {
            e = QuietEndEntry(r, now);
            NSString *hold = Str(r.body[@"holdRid"]);
            if (hold) [newer addObject:[hold stringByAppendingString:@"#quiet-ended"]];
        }
        if (e) [out addObject:e];
    }
    flush();
    MMWindowLog *log = [MMWindowLog new];
    log.entries = out;
    log.note = MMWindowLogNote(out.count == 0, watchingLeft > 0 ? MMWindowSpan(watchingLeft) : nil);
    return log;
}

static _Atomic NSUInteger gReads;
NSUInteger MMWindowLogReads(void) { return atomic_load(&gReads); }

MMWindowLog *MMWindowLogRead(MMLog *log, NSDate *now, NSUInteger most, NSTimeInterval maxAge) {
    atomic_fetch_add(&gReads, 1);
    now = now ?: NSDate.date;
    NSMutableArray<MMLogEntry *> *rows = [NSMutableArray new];
    int64_t before = 0;
    // A page at a time, newest first. Hourly reviews fold, so a page may give few entries; the next page starts
    // before the oldest row read, and the reading stops where the entries are enough or the rows too old.
    for (;;) {
        NSArray<MMLogEntry *> *page = [log rows:MMWindowLogTables() before:before limit:kPage];
        [rows addObjectsFromArray:page];
        if (page.count < kPage || rows.count >= kMostRows) break;
        if (maxAge > 0 && -[page.lastObject.at timeIntervalSinceDate:now] > maxAge) break;
        if (MMWindowLogFrom(rows, now, most, maxAge, 0).entries.count >= most) break;
        before = page.lastObject.row;
    }
    return MMWindowLogFrom(rows, now, most, maxAge, MMWatchingLeft(@"minmacs"));
}

NSDictionary *MMWindowLogEntryJSON(MMWindowLogEntry *e) {
    return @{@"key": e.key ?: @"", @"kind": e.kind ?: @"", @"sentence": e.sentence ?: @"", @"time": e.time ?: @"", @"day": e.day ?: @"",
             @"who": e.who ?: NSNull.null, @"tokens": @(e.tokens), @"at": @(e.at), @"row": @(e.row), @"canUndo": @(e.canUndo), @"detail": e.detail,
             @"rid": e.undoRid ?: NSNull.null, @"more": e.more ?: NSNull.null, @"skipped": e.skipped};
}

#pragma mark - The verb

static int LogVerb(MMArgs *a) {
    if (a.words.count) return [a usageError];
    NSString *lim = [a option:@"--limit"];
    if ([a has:@"--limit"] && (!lim || lim.integerValue < 1 || lim.integerValue > 100000)) { [a error:@"--limit takes a number from 1"]; return [a usageError]; }
    NSUInteger most = lim ? (NSUInteger)lim.integerValue : 50;
    MMLog *log = MMLog.shared;
    if (!log) { [a error:@"the log cannot be opened"]; return MMExitFailed; }
    // The verb reads the same entries the window shows, as many as asked for and with no limit in days.
    MMWindowLog *l = MMWindowLogRead(log, NSDate.date, most, 0);
    if (a.json) {
        NSMutableArray *j = [NSMutableArray new];
        for (MMWindowLogEntry *e in l.entries) [j addObject:MMWindowLogEntryJSON(e)];
        [a printJSON:@{@"entries": j, @"note": l.note ?: NSNull.null, @"limit": @(most)}];
        return 0;
    }
    if (l.note) [a print:@"%@", l.note];
    NSString *day = nil;
    for (MMWindowLogEntry *e in l.entries) {
        if (![e.day isEqualToString:day]) { day = e.day; [a print:@"%@", day]; }
        [a print:@"  %@", e.sentence];
        [a print:@"    %@", e.detail];
        if (e.more) [a print:@"    %@", e.more];
    }
    return 0;
}

MMVerbSpec *MMLogVerbSpec(void) {
    MMVerbSpec *v = [MMVerbSpec verb:@"log" usage:@"log [--limit <n>] [--json]   what MinMacs did and decided, and each setting that changed, newest first, 50 entries unless --limit says"
                             mutates:NO run:^int(MMArgs *a) { return LogVerb(a); }];
    v.reads = MMVerbReadsNoWorktrees;
    return v;
}
