// The render's made-up logs, MMWindowFixtureParts.h: an empty one, a new Mac's first hour and a busy month of 300
// entries. Every sentence has the shape Shell/MMWindowLog.m gives its entries, so the render draws what the app does.
// The days are counted back from one fixed Tuesday, so the PNGs are the same on every day they are made.
#import "UI/Window/MMWindowFixtureParts.h"

static NSString *DayName(NSInteger back) {
    if (back == 0) return @"Today";
    if (back == 1) return @"Yesterday";
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"]; f.dateFormat = @"EEEE d MMMM";
        f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    // Tuesday 24 November 2026, at noon.
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:1795521600 - back * 86400.0]];
}

static MMWindowLogEntry *E(NSInteger n, NSInteger back, NSInteger minute, NSString *kind, NSString *sentence, NSString *who, NSInteger tokens, BOOL undo) {
    MMWindowLogEntry *e = [MMWindowLogEntry new];
    e.key = [NSString stringWithFormat:@"fixture:%ld", (long)n];
    e.kind = kind; e.sentence = sentence; e.who = who; e.tokens = tokens; e.canUndo = undo;
    if (undo) {
        // As Shell/MMWindowLog.m gives it: the record's rid, and the sentence's own words of how Undo takes it back.
        e.undoRid = [NSString stringWithFormat:@"fixture-rid-%ld", (long)n];
        NSRange at = [sentence rangeOfString:@" Undo "];
        e.undoHelp = at.location == NSNotFound ? nil : [sentence substringFromIndex:at.location + 1];
    }
    e.day = DayName(back);
    e.time = [NSString stringWithFormat:@"%02ld:%02ld", (long)(minute / 60 % 24), (long)(minute % 60)];
    e.at = 1795521600 - back * 86400.0 + minute * 60; e.row = 100000 - n;
    return e;
}

/// A run's entry, as MMWindowLogRunEntry gives it: one line, and each skip with why in its more.
static MMWindowLogEntry *Run(NSInteger n, NSInteger back, NSInteger minute, NSString *sentence, NSString *who, NSString *more) {
    MMWindowLogEntry *e = E(n, back, minute, @"run", sentence, who, 0, NO);
    e.more = more;
    return e;
}

/// An action that was taken back, told once with its two times.
static MMWindowLogEntry *Back(NSInteger n, NSInteger back, NSInteger minute, NSInteger later, NSString *sentence, NSString *again, NSString *who) {
    MMWindowLogEntry *e = E(n, back, minute, @"restored", sentence, who, 0, NO);
    e.time = [NSString stringWithFormat:@"%@, %@ %02ld:%02ld", e.time, again, (long)(later / 60 % 24), (long)(later % 60)];
    return e;
}

static NSString *const kFixSkips = @"Skipped Claude Code in atlas: it asks you. Skipped Codex in notes-export: it asks you. It gave back 2.4 GB memory and 1.86 GB disk.";

/// One of each kind, turned by i, with names short and long, so wrapping and every word are drawn.
static MMWindowLogEntry *Busy(NSInteger i, NSInteger back, NSInteger minute) {
    NSArray<NSString *> *servers = @[@":3000 Next.js atlas", @":5173 Vite site", @":4321 Astro docs", @":6006 Storybook design-system-components-and-the-tokens-they-read"];
    NSArray<NSString *> *trees = @[@"fix-auth-redirect", @"notes-export", @"menu-window-polish-after-the-first-look", @"speed-3-base"];
    NSString *server = servers[(NSUInteger)(i / 13) % servers.count], *tree = trees[(NSUInteger)(i / 7) % trees.count];
    switch (i % 15) {
        case 13: return Run(i, back, minute, @"Fix Everything: 5 done, 2 skipped. 2 agents ask you.", @"by you", kFixSkips);
        case 14: return Back(i, back, minute, minute + 5, [NSString stringWithFormat:@"Stopped %@.", server], @"started again", @"on its own, Careful");
        case 0: return E(i, back, minute, @"action", [NSString stringWithFormat:@"Stopped %@. Undo starts it again.", server], @"on its own, Careful", 0, YES);
        case 1: return E(i, back, minute, @"reviews", @"5 reviews acted on nothing.", @"on its hourly round", 18240 + i * 3, NO);
        case 2: return E(i, back, minute, @"review", @"Review of servers: looked at 7, kept 6, 1 can go.", @"on its hourly round", 4120 + i, NO);
        case 3: return E(i, back, minute, @"action", [NSString stringWithFormat:@"Wrapped up %@ in 4 steps. Undo brings it all back.", tree], @"by you, in Fix Everything", 0, YES);
        case 4: return E(i, back, minute, @"setting", @"Stop idle servers changed from Careful to Eager.", @"by you in the window", 0, NO);
        case 5: return E(i, back, minute, @"action", @"Moved 3 leftovers in atlas to the Trash. Undo moves it back.", @"by you", 0, YES);
        case 6: return E(i, back, minute, @"keep", [NSString stringWithFormat:@"Kept %@ for 7 d. No rule acts on it until then.", tree], @"by you in a menu", 0, NO);
        case 7: return E(i, back, minute, @"action", @"Quit Chat. Undo opens it again.", @"on its own, Eager", 0, YES);
        case 8: return E(i, back, minute, @"failed", @"Could not quit Preview. It did not quit. It may be asking to save.", @"by you, in Fix Everything", 0, NO);
        case 9: return E(i, back, minute, @"restored", [NSString stringWithFormat:@"Started again: %@.", server], @"from the command line", 0, NO);
        case 10: return E(i, back, minute, @"investigate", [NSString stringWithFormat:@"Looked into %@.", tree], @"with opus", 34180, NO);
        case 11: return E(i, back, minute, @"setting", @"The model reviews ask changed from auto to opus.", @"from the command line", 0, NO);
        default: return E(i, back, minute, @"action", [NSString stringWithFormat:@"Removed the worktree %@. Undo brings it back.", tree], @"on its own, Careful", 0, YES);
    }
}

MMWindowLog *MMWindowFixtureLog(NSString *kind) {
    MMWindowLog *log = [MMWindowLog new];
    if ([kind isEqualToString:@"empty"]) {
        log.entries = @[];
        log.note = MMWindowLogNote(YES, @"23 h 59 min");
        return log;
    }
    if ([kind isEqualToString:@"new"]) {
        // The first hour: Start in the welcome, the login item it turned on, a rule set, and the first reviews.
        log.entries = @[E(0, 0, 9 * 60 + 41, @"review", @"Review of servers: looked at 7, kept 7.", @"on its hourly round", 3912, NO),
                        E(1, 0, 9 * 60 + 40, @"review", @"Review of apps and agents: looked at 15, kept 15.", @"on its hourly round", 5230, NO),
                        E(2, 0, 9 * 60 + 33, @"setting", @"Remove finished worktrees changed from Careful to Off.", @"by you in the window", 0, NO),
                        E(3, 0, 9 * 60 + 30, @"setting", @"Open at login turned on.", @"by you in the welcome", 0, NO),
                        E(4, 0, 9 * 60 + 30, @"setting", @"Start was pressed in the welcome. The welcome does not come back.", @"by you in the welcome", 0, NO)];
        log.note = MMWindowLogNote(NO, @"23 h 49 min");
        return log;
    }
    if ([kind isEqualToString:@"busy"]) {
        // 300 entries over a month, about ten a day, newest first.
        NSMutableArray *all = [NSMutableArray new];
        for (NSInteger i = 0; i < 300; i++) [all addObject:Busy(i, i / 10, 23 * 60 - (i % 10) * 83)];
        log.entries = all;
        return log;
    }
    if ([kind isEqualToString:@"undo"]) {
        // The Undo presses and the runs: an action that can still be taken back, one taken back, a run of Fix
        // Everything with what it skipped, a mode pass, one whose Undo runs now, and one that cannot come back.
        MMWindowLogEntry *undoing = E(5, 0, 11 * 60 + 2, @"action", @"Quit Chat. Undo opens it again.", @"on its own, Eager", 0, YES);
        undoing.canUndo = NO; undoing.undoing = YES;
        log.entries = @[E(0, 0, 14 * 60 + 2, @"action", @"Stopped :3000 Next.js atlas. Undo starts it again.", @"by you, in Fix Everything", 0, YES),
                        Run(1, 0, 14 * 60 + 2, @"Fix Everything: 5 done, 2 skipped. 2 agents ask you.", @"by you", kFixSkips),
                        Back(2, 0, 12 * 60, 12 * 60 + 5, @"Stopped :5173 Vite site.", @"started again", @"on its own, Careful"),
                        Run(3, 0, 12 * 60, @"Stop idle servers: 2 done, 1 skipped. 1 failed.", @"on its own, Careful",
                            @"Skipped :4321 Astro docs: it ignored SIGTERM and still runs. It gave back 640 MB memory."),
                        E(4, 0, 11 * 60 + 40, @"action", @"Wrapped up menu-window-polish-after-the-first-look in 4 steps. Undo brings it all back.", @"by you", 0, YES),
                        undoing,
                        E(6, 0, 10 * 60 + 12, @"action", @"Deleted old build output in atlas. It cannot be brought back.", @"by you", 0, NO),
                        E(7, 0, 9 * 60 + 58, @"reviews", @"3 reviews acted on nothing.", @"on its hourly round", 12040, NO)];
        return log;
    }
    // A plain day: today and yesterday, a few of each kind.
    NSMutableArray *some = [NSMutableArray new];
    for (NSInteger i = 0; i < 16; i++) [some addObject:Busy(i, i / 8, 18 * 60 - (i % 8) * 71)];
    log.entries = some;
    return log;
}
