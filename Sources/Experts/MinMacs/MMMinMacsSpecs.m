// Makers for the menu, card and verb specs of Core/MMExpert.h.
// The spec classes are implemented outside Core, by the code that draws menus and runs verbs, in parallel with this expert.
// So each maker takes the real class when it is linked, and else a value object here with the same properties.
// The kit and the verb registry read specs by property, so either one works, and nothing here links the real classes.
#import "Experts/MinMacs/MMMinMacsSpecs.h"

@interface MMMinMacsActionValue : NSObject
@property (copy) NSString *title, *tail, *disabledReason, *optionTitle;
@property (copy) void (^run)(BOOL option);
@end
@implementation MMMinMacsActionValue
@end

@interface MMMinMacsRowValue : NSObject
@property (copy) NSString *name;
@property (copy) NSArray<NSString *> *facts;
@property MMRowMark mark;
@property (copy) NSString *findingID;
@end
@implementation MMMinMacsRowValue
@end

@interface MMMinMacsSectionValue : NSObject
@property (copy) NSString *title;
@property (copy) NSArray *rows;
@end
@implementation MMMinMacsSectionValue
@end

@interface MMMinMacsMenuValue : NSObject
@property (copy) NSString *headerBig, *headerUnit, *headerLine, *summary;
@property (copy) NSArray *actions, *sections, *more;
@end
@implementation MMMinMacsMenuValue
@end

@interface MMMinMacsFactValue : NSObject
@property (copy) NSString *label, *value, *linkExpert, *linkFindingID;
@end
@implementation MMMinMacsFactValue
@end

@interface MMMinMacsCardValue : NSObject
@property (copy) NSString *title, *statusWord, *statusText, *noteBy, *note;
@property MMRowMark mark;
@property (copy) NSArray *facts, *actions;
@end
@implementation MMMinMacsCardValue
@end

@interface MMMinMacsVerbValue : NSObject
@property (copy) NSString *verb, *usage;
@property BOOL mutates;
@property (copy) int (^run)(MMArgs *args);
@end
@implementation MMMinMacsVerbValue
@end

static id Make(NSString *real, Class fallback) {
    Class c = NSClassFromString(real);
    return [c ?: fallback new];
}

MMActionSpec *MMMinMacsAction(NSString *title, NSString *tail, NSString *disabledReason, void (^run)(BOOL option)) {
    MMActionSpec *a = Make(@"MMActionSpec", MMMinMacsActionValue.class);
    a.title = title; a.tail = tail; a.disabledReason = disabledReason; a.run = run;
    return a;
}

MMRowSpec *MMMinMacsRow(NSString *name, NSArray<NSString *> *facts, MMRowMark mark, NSString *findingID) {
    MMRowSpec *r = Make(@"MMRowSpec", MMMinMacsRowValue.class);
    NSMutableArray *f = [NSMutableArray new];
    for (NSString *s in facts) if (s.length && f.count < 3) [f addObject:s];
    r.name = name; r.facts = f; r.mark = mark; r.findingID = findingID;
    return r;
}

MMSectionSpec *MMMinMacsSection(NSString *title, NSArray<MMRowSpec *> *rows) {
    MMSectionSpec *s = Make(@"MMSectionSpec", MMMinMacsSectionValue.class);
    s.title = title; s.rows = rows;
    return s;
}

MMMenuSpec *MMMinMacsMenu(void) { return Make(@"MMMenuSpec", MMMinMacsMenuValue.class); }

MMCardFact *MMMinMacsFact(NSString *label, NSString *value) {
    MMCardFact *f = Make(@"MMCardFact", MMMinMacsFactValue.class);
    f.label = label; f.value = value;
    return f;
}

MMCardSpec *MMMinMacsCard(void) { return Make(@"MMCardSpec", MMMinMacsCardValue.class); }

MMVerbSpec *MMMinMacsVerb(NSString *verb, NSString *usage, BOOL mutates, int (^run)(MMArgs *args)) {
    MMVerbSpec *v = Make(@"MMVerbSpec", MMMinMacsVerbValue.class);
    v.verb = verb; v.usage = usage; v.mutates = mutates; v.run = run;
    return v;
}

/// The words after the verb. MMArgs is declared in Sources/CLI, which lands in parallel, so its words are read
/// by the first array accessor it answers, and else from the process's own arguments after the verb.
NSArray<NSString *> *MMMinMacsWords(MMArgs *args, NSString *verb) {
    id a = args;
    for (NSString *name in @[@"words", @"arguments", @"argv", @"all"]) {
        SEL sel = NSSelectorFromString(name);
        if (![a respondsToSelector:sel]) continue;
        id v = ((id (*)(id, SEL))[a methodForSelector:sel])(a, sel);
        if ([v isKindOfClass:NSArray.class]) {
            NSMutableArray *out = [v mutableCopy];
            if (out.count && [out.firstObject isEqual:verb]) [out removeObjectAtIndex:0];
            return out;
        }
    }
    NSArray *all = NSProcessInfo.processInfo.arguments;
    NSUInteger i = [all indexOfObject:verb];
    return i == NSNotFound ? @[] : [all subarrayWithRange:NSMakeRange(i + 1, all.count - i - 1)];
}
