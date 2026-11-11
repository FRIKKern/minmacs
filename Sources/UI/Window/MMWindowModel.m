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
