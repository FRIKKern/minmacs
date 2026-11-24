// Every string the window can show for a model, for the render tool's word check: no old app name, no claimed result.
#import "UI/Window/MMWindowParts.h"

static void add0(NSMutableArray *s, NSString *x) { if (x.length) [s addObject:x]; }

@implementation MMWindowView (Words)

+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)m {
    NSMutableArray<NSString *> *s = [NSMutableArray arrayWithArray:@[
        @"Fix Everything", @"No fixes to run", @"Stop", @"memory in use", @"disk free", @"memory", @"disk", @"or more disk", @"today", @"so far",
        @"the last hour", @"an hour ago", @"now", @"Fills in as the hour passes.", @"Today", @"Yesterday", @"min ago", @"more above", @"about the same", @"more below", @"Its last hour", @"by memory", @"by disk", @"by activity", MMWindowMainCheckout, MMWindowNoProject, @"This disk", @"Memory", @"Free", @"In use",
        @"By these holders", @"macOS and the rest", @"Asks you.", @"Goes with Fix Everything.", @"Stays.", @"After the fix", @"After all", @"fixes", @"memory, now", @"memory in use, as now", @"just now", @"biggest", @"minutes",
        @"Settings", @"Each change applies at once.", @"Done", @"This Mac", @"Quit MinMacs", MMWindowLookingNote]];
    for (NSInteger minutes = 1; minutes <= 60; minutes++) [s addObject:MMWindowHourSpanWords(minutes)];
    [s addObjectsFromArray:@[MMWindowAwakeCard, MMWindowMacCard, MMWindowCleanupCard, MMWindowTrashLine, MMWindowStartsHelp, MMWindowAwakeHelp()]];
    for (NSString *rid in MMWindowRuleIDs()) for (NSInteger c = 0; c < 3; c++) { add0(s, MMWindowRuleSwitchTitle(rid)); add0(s, MMWindowRuleSwitchNote(rid, c)); }
    for (NSString *key in @[@"worktrees", @"caches"]) for (NSNumber *looked in @[@(MMWindowLookedNotYet), @(MMWindowLookedNowhere)])
        [s addObject:MMWindowEmptyNote(key, looked.integerValue)];
    void (^add)(NSString *) = ^(NSString *x) { if (x.length) [s addObject:x]; };
    add(m.asks);
    for (MMWindowHour *h in @[m.memoryHour ?: [MMWindowHour new], m.diskHour ?: [MMWindowHour new]]) { add(h.title); add(h.explain); }
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) {
        add(g.title); add(g.emptyNote);
        for (MMWindowRow *r in g.rows) { add(r.name); add(r.nameInProject); add(r.project); add(r.state); for (MMWindowFact *f in r.facts) { add(f.label); add(f.value); }
            if (r.pull) { add(r.pull.line); add(r.pull.title); if (r.pull.opens) add(MMWindowOpenPull); } }
    }
    for (MMWindowFix *f in m.fixes) add(f.title);
    add(m.run.step); add(m.run.endTitle); add(m.run.endNote);
    for (MMWindowRule *r in m.settings.rules) { add(r.title); add(r.note); for (MMWindowChoice *c in r.choices) { add(c.title); add(c.explain); } }
    for (MMWindowSwitch *w in m.settings.switches) { add(w.title); add(w.note); add(w.help); }
    add(m.settings.startsIn);
    add(m.log.note);
    for (MMWindowLogEntry *e in m.log.entries) { add(e.sentence); add(e.detail); add(e.day); add(e.more); add(e.undoHelp); }
    MMWindowWelcome *w = m.welcome;
    for (NSString *x in @[w.title ?: @"", w.say ?: @"", w.loginTitle ?: @"", w.loginOnNote ?: @"", w.loginOffNote ?: @"", w.later ?: @"", w.start ?: @""]) add(x);
    for (MMWindowFact *f in w.facts) { add(f.label); add(f.value); }
    return s;
}

@end
