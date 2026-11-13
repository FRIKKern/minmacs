// Every string the window can show for a model, for the render tool's word check: no old app name, no claimed result.
#import "UI/Window/MMWindowParts.h"

@implementation MMWindowView (Words)

+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)m {
    NSMutableArray<NSString *> *s = [NSMutableArray arrayWithArray:@[
        @"Fix Everything", @"Stop", @"memory in use", @"disk free", @"memory back", @"disk back", @"so far",
        @"the last hour", @"an hour ago", @"now", @"The line fills in as the hour passes.", @"min ago", @"memory back today", @"disk back today", @"more above", @"about the same", @"more below", @"Its last hour", @"by memory", @"by disk", @"This disk", @"Memory", @"the whole number", @"Free", @"In use",
        @"By these holders", @"macOS and the rest", @"Asks you.", @"Goes with Fix Everything.", @"Stays.", @"After the fix", @"After all", @"memory, now", @"biggest", @"minutes",
        @"Settings", @"Each change applies at once.", @"Done", @"This Mac", @"Quit MinMacs", MMWindowLookingNote]];
    void (^add)(NSString *) = ^(NSString *x) { if (x.length) [s addObject:x]; };
    add(m.asks);
    for (MMWindowHour *h in @[m.memoryHour ?: [MMWindowHour new], m.diskHour ?: [MMWindowHour new]]) { add(h.title); add(h.explain); }
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) {
        add(g.title); add(g.emptyNote);
        for (MMWindowRow *r in g.rows) { add(r.name); add(r.state); for (MMWindowFact *f in r.facts) { add(f.label); add(f.value); } }
    }
    for (MMWindowFix *f in m.fixes) add(f.title);
    add(m.run.step); add(m.run.endTitle); add(m.run.endNote);
    for (MMWindowRule *r in m.settings.rules) { add(r.title); add(r.note); for (MMWindowChoice *c in r.choices) { add(c.title); add(c.explain); } }
    for (MMWindowSwitch *w in m.settings.switches) { add(w.title); add(w.note); }
    MMWindowWelcome *w = m.welcome;
    for (NSString *x in @[w.title ?: @"", w.say ?: @"", w.loginTitle ?: @"", w.loginOnNote ?: @"", w.loginOffNote ?: @"", w.removalTitle ?: @"", w.later ?: @"", w.start ?: @""]) add(x);
    for (MMWindowChoice *c in w.removal) { add(c.title); add(c.explain); }
    for (MMWindowFact *f in w.facts) { add(f.label); add(f.value); }
    return s;
}

@end
