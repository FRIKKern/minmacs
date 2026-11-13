// The window's view model, issue #62. Plain values. MMWindowModel.h says what each holds.
#import "UI/Window/MMWindowModel.h"

@implementation MMWindowHour
- (instancetype)init { if ((self = [super init])) { _title = @""; _explain = @""; _values = @[]; _side = MMWindowMemory; } return self; }
@end

@implementation MMWindowFact
+ (instancetype)label:(NSString *)label value:(NSString *)value {
    MMWindowFact *f = [MMWindowFact new]; f.label = label; f.value = value; return f;
}
@end

@implementation MMWindowRow
- (instancetype)init { if ((self = [super init])) { _key = @""; _name = @""; _cpuPercent = -1; _facts = @[]; } return self; }
- (NSString *)shownName {
    if (self.kind != MMWindowTabs || self.tabs <= 0 || [self.name hasPrefix:@(self.tabs).stringValue]) return self.name;
    return [NSString stringWithFormat:@"%ld %@", (long)self.tabs, self.name];
}
- (BOOL)showsSize { return self.kind != MMWindowTabs || self.bytes > 0; }

- (MMWindowFact *)factLabelled:(NSString *)label {
    for (MMWindowFact *f in self.facts) if ([f.label isEqualToString:label]) return f;
    return nil;
}

/// A fact's words as a sentence of their own: a capital first, and a period when no mark ends it.
static NSString *Sentence(NSString *words) {
    NSString *w = [words stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!w.length) return nil;
    w = [[w substringToIndex:1].localizedUppercaseString stringByAppendingString:[w substringFromIndex:1]];
    return [NSCharacterSet.alphanumericCharacterSet characterIsMember:[w characterAtIndex:w.length - 1]] ? [w stringByAppendingString:@"."] : w;
}

/// The line's lead and kind, the fact its sentence comes from, and whether it says the row's State already.
- (MMWindowFate *)fateFrom:(MMWindowFact *__autoreleasing *)source saysState:(BOOL *)saysState {
    MMWindowFact *why = [self factLabelled:@"Why"], *stays = [self factLabelled:@"Stays"], *state = [self factLabelled:@"State"], *from = nil;
    MMWindowFate *f = [MMWindowFate new];
    BOOL says = NO;
    if (self.needsYou) { f.kind = MMWindowFateAsks; f.lead = @"Asks you."; from = why ?: stays; says = YES; }
    else if (self.inFix) { f.kind = MMWindowFateGoes; f.lead = @"Goes with Fix Everything."; from = why; }
    else if (stays) { f.lead = @"Stays."; from = stays; }
    else if (self.kind == MMWindowAgent && state.value.length) { f.lead = Sentence(state.value); from = why; says = YES; }
    else if (why) from = why;
    else return nil;
    f.note = Sentence(from.value);
    if (source) *source = from;
    if (saysState) *saysState = says;
    return f;
}

- (MMWindowFate *)fate { return [self fateFrom:NULL saysState:NULL]; }

- (NSArray<MMWindowFact *> *)storyFacts {
    MMWindowFact *from = nil;
    BOOL says = NO;
    if (![self fateFrom:&from saysState:&says]) return self.facts;
    NSMutableArray<MMWindowFact *> *out = [NSMutableArray new];
    for (MMWindowFact *f in self.facts) if (f != from && !(says && [f.label isEqualToString:@"State"])) [out addObject:f];
    return out;
}
@end

@implementation MMWindowFate
- (instancetype)init { if ((self = [super init])) { _lead = @""; } return self; }
@end

@implementation MMWindowGroup
- (instancetype)init { if ((self = [super init])) { _key = @""; _title = @""; _side = MMWindowMemory; _rows = @[]; } return self; }
@end

@implementation MMWindowSlice
@end

@implementation MMWindowRing
- (instancetype)init { if ((self = [super init])) { _memory = @[]; _disk = @[]; } return self; }
@end

@implementation MMWindowFix
@end

@implementation MMWindowRun
@end

@implementation MMWindowChoice
@end

@implementation MMWindowRule
- (instancetype)init { if ((self = [super init])) { _ruleID = @""; _title = @""; _choices = @[]; } return self; }
@end

@implementation MMWindowSwitch
@end

@implementation MMWindowSettings
- (instancetype)init { if ((self = [super init])) { _rules = @[]; _switches = @[]; } return self; }
@end

NSString *const MMWindowRemovalTitle = @"When MinMacs removes things";
NSString *const MMWindowLookingNote = @"MinMacs is taking its first look. It takes a few seconds.";

NSString *MMWindowLoginNote(BOOL on) { return on ? @"MinMacs starts when you sign in." : @"MinMacs starts only when you open it."; }

@implementation MMWindowWelcome
+ (instancetype)welcomeWithRemoval:(NSArray<MMWindowChoice *> *)removal picked:(NSInteger)picked facts:(NSArray<MMWindowFact *> *)facts {
    MMWindowWelcome *w = [MMWindowWelcome new];
    w.title = @"Welcome to MinMacs";
    w.say = @"MinMacs watches what your agents, servers and apps hold. Press Fix Everything and it gives memory and disk back.";
    w.loginTitle = @"Open at login"; w.loginOn = YES;
    w.loginOnNote = MMWindowLoginNote(YES); w.loginOffNote = MMWindowLoginNote(NO);
    w.removalTitle = MMWindowRemovalTitle;
    w.removal = removal ?: @[]; w.removalPicked = picked;
    w.later = @"Both can be changed later in Settings.";
    w.facts = facts ?: @[];
    w.start = @"Start";
    return w;
}
@end

@implementation MMWindowModel
- (instancetype)init {
    if ((self = [super init])) {
        _memoryGroups = @[]; _diskGroups = @[]; _fixes = @[];
        _ring = [MMWindowRing new]; _settings = [MMWindowSettings new];
    }
    return self;
}

- (MMWindowRow *)row:(NSString *)key {
    for (NSArray<MMWindowGroup *> *side in @[self.memoryGroups, self.diskGroups])
        for (MMWindowGroup *g in side)
            for (MMWindowRow *r in g.rows) if ([r.key isEqualToString:key]) return r;
    return nil;
}

- (uint64_t)memoryBack { uint64_t n = 0; for (MMWindowFix *f in self.fixes) if (!f.needsYou) n += f.memoryBack; return n; }
- (uint64_t)diskBack { uint64_t n = 0; for (MMWindowFix *f in self.fixes) if (!f.needsYou) n += f.diskBack; return n; }
- (NSInteger)fixCount { NSInteger n = 0; for (MMWindowFix *f in self.fixes) if (!f.needsYou) n++; return n; }
@end
