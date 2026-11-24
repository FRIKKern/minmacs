// The window's view model, issue #62. Plain values. MMWindowModel.h says what each holds.
#import "UI/Window/MMWindowModel.h"
#import <math.h>

NSArray<NSString *> *MMWindowSizeParts(uint64_t bytes, BOOL disk) {
    const double K = disk ? 1000.0 : 1024.0, M = K * K, G = M * K;
    if (bytes == 0) return @[@"0", @"MB"];
    // Under a megabyte rounds up to kilobytes, so something that holds bytes never reads as zero.
    if (bytes < M - K / 2) return @[[NSString stringWithFormat:@"%.0f", ceil(bytes / K)], @"KB"];
    if (bytes < G - M / 2) return @[[NSString stringWithFormat:@"%.0f", bytes / M], @"MB"];
    double x = bytes / G;
    if (x >= 999.5) return @[[NSString stringWithFormat:@"%.1f", x / K], @"TB"];
    if (x >= 99.95) return @[[NSString stringWithFormat:@"%.0f", x], @"GB"];
    if (x >= 9.995) return @[[NSString stringWithFormat:@"%.1f", x], @"GB"];
    BOOL two = fabs(x * 10 - round(x * 10)) > 0.3;
    return @[[NSString stringWithFormat:two ? @"%.2f" : @"%.1f", x], @"GB"];
}

NSString *MMWindowSizeText(uint64_t bytes, BOOL disk) { return [MMWindowSizeParts(bytes, disk) componentsJoinedByString:@" "]; }

NSString *MMWindowWholeText(uint64_t bytes, BOOL disk) {
    return [MMWindowSizeText(bytes, disk) stringByReplacingOccurrencesOfString:@".0 " withString:@" "];
}

NSString *MMWindowHourExplain(BOOL disk, uint64_t whole) {
    return disk ? [NSString stringWithFormat:@"Lower means less room left on the %@ disk", MMWindowWholeText(whole, YES)]
                : [NSString stringWithFormat:@"Higher means more of the %@ is in use", MMWindowWholeText(whole, NO)];
}

NSString *MMWindowHourTitle(BOOL disk) { return disk ? @"Disk free" : @"Memory in use"; }

@implementation MMWindowHour
- (instancetype)init { if ((self = [super init])) { _title = @""; _explain = @""; _values = @[]; _side = MMWindowMemory; } return self; }
@end

@implementation MMWindowFact
+ (instancetype)label:(NSString *)label value:(NSString *)value {
    MMWindowFact *f = [MMWindowFact new]; f.label = label; f.value = value; return f;
}
@end

#pragma mark The facts' words

NSString *MMWindowSpan(NSTimeInterval seconds) {
    long t = (long)MAX(0, seconds);
    if (t < 10) return nil;
    if (t < 60) return [NSString stringWithFormat:@"%ld s", t];
    if (t < 3600) return [NSString stringWithFormat:@"%ld min", t / 60];
    if (t < 86400) return t % 3600 >= 60 ? [NSString stringWithFormat:@"%ld h %ld min", t / 3600, t % 3600 / 60] : [NSString stringWithFormat:@"%ld h", t / 3600];
    // Past a week the hours say nothing: "13 d", not "13 d 4 h".
    return t % 86400 >= 3600 && t < 7 * 86400 ? [NSString stringWithFormat:@"%ld d %ld h", t / 86400, t % 86400 / 3600] : [NSString stringWithFormat:@"%ld d", t / 86400];
}

static MMWindowFact *Fact(NSString *label, NSString *value, NSString *phrase) {
    if (!value.length) return nil;
    MMWindowFact *f = [MMWindowFact label:label value:value];
    f.phrase = phrase;
    return f;
}

static NSString *Trimmed(NSString *s) { return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

/// "port 3000", "ports 3000, 3001".
static NSString *Ports(NSArray *ports) {
    NSMutableArray<NSString *> *a = [NSMutableArray new];
    for (id p in ports) if ([[p description] integerValue] > 0) [a addObject:[p description]];
    return a.count ? [NSString stringWithFormat:@"%@ %@", a.count == 1 ? @"port" : @"ports", [a componentsJoinedByString:@", "]] : nil;
}

MMWindowFact *MMWindowFactPort(NSInteger port) { return port > 0 ? Fact(@"Port", [NSString stringWithFormat:@":%ld", (long)port], nil) : nil; }

MMWindowFact *MMWindowFactProject(NSString *project) {
    NSString *p = Trimmed(project);
    // The disk's top and the home folder are no project: "in /" and "in ~" say nothing.
    if ([p isEqualToString:@"/"] || [p isEqualToString:@"~"]) return nil;
    NSString *last = p.lastPathComponent;
    return Fact(@"Project", p, last.length ? [@"in " stringByAppendingString:last] : nil);
}

MMWindowFact *MMWindowFactOwner(NSString *project) { NSString *p = Trimmed(project); return Fact(@"Project", p, [@"for " stringByAppendingString:p]); }
MMWindowFact *MMWindowFactRunsIn(NSString *where) { NSString *w = Trimmed(where); return Fact(@"Runs in", w, [@"runs in " stringByAppendingString:w]); }

MMWindowFact *MMWindowFactStartedBy(NSString *who) {
    // Core writes who started a server as a chain with the starter first, "pnpm dev · cmux", and ends it with "parent
    // exited" when the starter is gone, or "launchd" when launchd took the server over. The dot is the second line's
    // own separator between facts, so the chain is said in words: "pnpm dev in cmux".
    NSMutableArray<NSString *> *chain = [NSMutableArray new];
    for (NSString *part in [Trimmed(who) componentsSeparatedByString:@"·"]) if (Trimmed(part).length) [chain addObject:Trimmed(part)];
    BOOL quit = [chain.lastObject isEqualToString:@"parent exited"];
    if (quit) [chain removeLastObject];
    if (chain.count > 1 && [chain.lastObject isEqualToString:@"launchd"]) [chain removeLastObject];
    if (!chain.count) return quit ? Fact(@"Started by", @"a program that has quit", @"its starter has quit") : nil;
    NSString *w = [chain componentsJoinedByString:@" in "];
    if (!quit) return Fact(@"Started by", w, [@"started by " stringByAppendingString:w]);
    // "parent exited" says the server's own parent process ended. The names before it still run: the last is the app
    // the server runs in, so it is never said to have quit.
    if (chain.count == 1) return Fact(@"Started by", [NSString stringWithFormat:@"a program in %@ that has quit", w], [NSString stringWithFormat:@"started in %@, its starter has quit", w]);
    w = [w stringByAppendingString:@", its starter has quit"];
    return Fact(@"Started by", w, [@"started by " stringByAppendingString:w]);
}

MMWindowFact *MMWindowFactIdle(NSTimeInterval seconds) {
    NSString *span = MMWindowSpan(seconds);
    return span ? Fact(@"Idle", span, [@"idle for " stringByAppendingString:span]) : Fact(@"Idle", @"since just now", @"idle since just now");
}

MMWindowFact *MMWindowFactLastUsed(NSTimeInterval ago) {
    NSString *span = MMWindowSpan(ago), *when = span ? [span stringByAppendingString:@" ago"] : @"just now";
    return Fact(@"Last used", when, [@"used " stringByAppendingString:when]);
}

MMWindowFact *MMWindowFactUp(NSTimeInterval seconds) {
    NSString *span = MMWindowSpan(seconds);
    return span ? Fact(@"Running", span, [@"up " stringByAppendingString:span]) : Fact(@"Running", @"since just now", @"started just now");
}

MMWindowFact *MMWindowFactKept(NSTimeInterval left) {
    NSString *span = MMWindowSpan(left);
    return span ? Fact(@"Kept", [span stringByAppendingString:@" more"], [NSString stringWithFormat:@"kept for %@ more", span]) : nil;
}

MMWindowFact *MMWindowFactAgent(NSString *harness) { NSString *h = Trimmed(harness); return Fact(@"Agent", h, h); }
MMWindowFact *MMWindowFactSession(NSString *title) { NSString *t = Trimmed(title); return Fact(@"Session", t, t); }
MMWindowFact *MMWindowFactState(NSString *state) { return Fact(@"State", Trimmed(state), nil); }
MMWindowFact *MMWindowFactUsedBy(NSString *agent) { NSString *a = Trimmed(agent); return Fact(@"Used by", a, [@"used by " stringByAppendingString:a]); }
MMWindowFact *MMWindowFactServes(NSArray *ports) { NSString *p = Ports(ports); return Fact(@"Serves", p, [@"serves " stringByAppendingString:p ?: @""]); }
MMWindowFact *MMWindowFactStays(NSString *reason) { return Fact(@"Stays", Trimmed(reason), nil); }
MMWindowFact *MMWindowFactLeftBy(NSString *worktree) { NSString *w = Trimmed(worktree); return Fact(@"Left by", w, [@"left by " stringByAppendingString:w]); }
MMWindowFact *MMWindowFactFolder(NSString *folder) { return Fact(@"Folder", Trimmed(folder), nil); }

MMWindowFact *MMWindowFactOpenTabs(NSInteger tabs) {
    if (tabs <= 0) return nil;
    NSString *n = [NSString stringWithFormat:@"%ld %@", (long)tabs, tabs == 1 ? @"tab" : @"tabs"];
    return Fact(@"Open", n, [n stringByAppendingString:@" open"]);
}

MMWindowFact *MMWindowFactOnPorts(NSArray *ports) { NSString *p = Ports(ports); return Fact(@"On", p, [@"on " stringByAppendingString:p ?: @""]); }
MMWindowFact *MMWindowFactBranch(NSString *branch) { return Fact(@"Branch", Trimmed(branch), nil); }

MMWindowFact *MMWindowFactFiles(NSInteger changed, NSInteger added) {
    NSMutableArray<NSString *> *v = [NSMutableArray new], *said = [NSMutableArray new];
    if (changed > 0) { [v addObject:[NSString stringWithFormat:@"%ld changed", (long)changed]]; [said addObject:[NSString stringWithFormat:@"%ld %@ changed", (long)changed, changed == 1 ? @"file" : @"files"]]; }
    if (added > 0) { [v addObject:[NSString stringWithFormat:@"%ld new", (long)added]]; [said addObject:changed > 0 ? [NSString stringWithFormat:@"%ld new", (long)added] : [NSString stringWithFormat:@"%ld new %@", (long)added, added == 1 ? @"file" : @"files"]]; }
    return Fact(@"Files", [v componentsJoinedByString:@", "], [said componentsJoinedByString:@", "]);
}

MMWindowFact *MMWindowFactNotPushed(NSInteger commits) {
    if (commits <= 0) return nil;
    NSString *n = [NSString stringWithFormat:@"%ld %@", (long)commits, commits == 1 ? @"commit" : @"commits"];
    return Fact(@"Not pushed", n, [n stringByAppendingString:@" not pushed"]);
}

MMWindowFact *MMWindowFactUntouched(NSTimeInterval seconds) {
    NSString *span = MMWindowSpan(seconds);
    return span ? Fact(@"Untouched", span, [@"untouched for " stringByAppendingString:span]) : Fact(@"Changed", @"just now", @"changed just now");
}

MMWindowFact *MMWindowFactKind(NSString *kind) { NSString *k = Trimmed(kind); return Fact(@"Kind", k, k); }

NSString *MMWindowEmptyNote(NSString *groupKey, MMWindowLooked looked) {
    if ([groupKey isEqualToString:@"worktrees"])
        return looked == MMWindowLookedNowhere ? @"No folders to look in" : looked == MMWindowLookedNotYet ? @"Looking for worktrees" : @"No worktrees found";
    if ([groupKey isEqualToString:@"caches"])
        return looked == MMWindowLookedNowhere ? @"Not looked at" : looked == MMWindowLookedNotYet ? @"Looking for caches" : @"No caches or leftovers found";
    // Servers, agents and apps are read from the processes of every pass, so their look has always ended.
    return @{@"servers": @"No servers found", @"agents": @"No agents found", @"apps": @"No apps found"}[groupKey];
}

NSString *const MMWindowMeasuring = @"measuring";
NSString *const MMWindowNotMeasured = @"Not measured yet";

NSComparisonResult MMWindowRowOrder(MMWindowRow *a, MMWindowRow *b) {
    if (a.unmeasured != b.unmeasured) return a.unmeasured ? NSOrderedDescending : NSOrderedAscending;
    if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
    if (a.tabs != b.tabs) return a.tabs > b.tabs ? NSOrderedAscending : NSOrderedDescending;
    return [a.key compare:b.key];
}

@implementation MMWindowRow
- (instancetype)init { if ((self = [super init])) { _key = @""; _name = @""; _cpuPercent = -1; _facts = @[]; } return self; }
- (NSString *)shownName {
    return self.kind == MMWindowTabs ? MMWindowTabsName(self.tabs, self.name) : self.name;
}
- (BOOL)showsSize { return !self.unmeasured && (self.kind != MMWindowTabs || self.bytes > 0); }
- (NSString *)sizeWord { return self.unmeasured ? MMWindowMeasuring : nil; }

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
/// The sentence is the fact labelled Stays, which the experts write in plain words for a person. An agent's Why is
/// a raw fact of its processes, such as "child caffeinate": it stays in the fact list and is never the sentence.
- (MMWindowFate *)fateFrom:(MMWindowFact *__autoreleasing *)source saysState:(BOOL *)saysState {
    MMWindowFact *stays = [self factLabelled:@"Stays"], *state = [self factLabelled:@"State"], *from = nil;
    MMWindowFate *f = [MMWindowFate new];
    BOOL says = NO;
    if (self.needsYou) { f.kind = MMWindowFateAsks; f.lead = @"Asks you."; says = YES; }
    else if (self.inFix) { f.kind = MMWindowFateGoes; f.lead = @"Goes with Fix Everything."; }
    else if (stays) { f.lead = @"Stays."; from = stays; }
    else if (self.kind == MMWindowAgent && state.value.length) { f.lead = Sentence(state.value); says = YES; }
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
- (NSInteger)unmeasured { NSInteger n = 0; for (MMWindowRow *r in self.rows) if (r.unmeasured) n++; return n; }
@end

@implementation MMWindowSlice
@end

@implementation MMWindowRing
- (instancetype)init { if ((self = [super init])) { _memory = @[]; _disk = @[]; } return self; }
@end

@implementation MMWindowFix
@end

@implementation MMWindowRun
static double Share(uint64_t back, uint64_t planned) { return planned ? MIN(1.0, (double)back / (double)planned) : 0; }
- (double)memoryShare { return Share(self.memoryBack, self.memoryPlanned); }
/// A planned disk that is no total has no share to show, however much came back.
- (double)diskShare { return self.diskPlannedPartial ? 0 : Share(self.diskBack, self.diskPlanned); }
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

#pragma mark The words of Settings

NSArray<NSString *> *MMWindowRuleIDs(void) { return @[@"servers", @"apps", @"worktrees", @"caches"]; }

NSArray<NSString *> *MMWindowChoiceTitles(void) { return @[@"Off", @"Careful", @"Eager"]; }

NSString *MMWindowRuleTitle(NSString *ruleID) {
    return @{@"servers": @"Stop idle servers", @"apps": @"Quit apps", @"worktrees": @"Remove finished worktrees",
             @"caches": @"Clean caches and leftovers"}[ruleID ?: @""];
}

NSArray<NSString *> *MMWindowRuleExplains(NSString *ruleID) {
    return @{
        @"servers": @[@"Stops no server on its own.",
                      @"After a review, stops an idle dev server that was quiet for 6 hours and has no agent above it.",
                      @"After a review, stops each idle dev server the review finds no use for."],
        @"apps": @[@"Quits no app on its own.",
                   @"Quits no app on its own either. An app closes only on your press.",
                   @"Quits the apps on your close list, only while memory pressure or heat is high."],
        @"worktrees": @[@"Removes no worktree on its own.",
                        @"After a review, removes a worktree that is merged, or whose remote branch is gone, and quiet for 7 days.",
                        @"After a review, removes each worktree the review finds no use for."],
        @"caches": @[@"Cleans up nothing on its own.",
                     @"After a review, cleans up the build output of finished projects and leftovers.",
                     @"After a review, also cleans up caches. A tool's own cleanup always waits for your press."],
    }[ruleID ?: @""];
}

MMWindowRule *MMWindowChoiceCard(NSString *ruleID, NSString *title, NSInteger picked, NSArray<NSArray<NSString *> *> *choices, NSString *note) {
    MMWindowRule *r = [MMWindowRule new];
    r.ruleID = ruleID; r.title = title ?: @""; r.picked = picked; r.note = note;
    NSMutableArray *list = [NSMutableArray new];
    for (NSArray<NSString *> *c in choices) { MMWindowChoice *x = [MMWindowChoice new]; x.title = c[0]; x.explain = c[1]; [list addObject:x]; }
    r.choices = list;
    return r;
}

MMWindowRule *MMWindowRuleCard(NSString *ruleID, NSInteger picked, NSString *note) {
    NSArray<NSString *> *titles = MMWindowChoiceTitles(), *explains = MMWindowRuleExplains(ruleID);
    NSMutableArray *choices = [NSMutableArray new];
    for (NSUInteger i = 0; i < titles.count && i < explains.count; i++) [choices addObject:@[titles[i], explains[i]]];
    return MMWindowChoiceCard(ruleID, MMWindowRuleTitle(ruleID), picked, choices, note);
}

NSString *MMWindowStartsNote(NSTimeInterval left) {
    if (left <= 0) return nil;
    // A badge, so short: whole hours past an hour, "Starts in 23 h", and minutes under it.
    long t = (long)left;
    if (t >= 3600 && t <= 86400) return [NSString stringWithFormat:@"Starts in %ld h", MAX(1L, (t + 1800) / 3600)];
    NSString *span = MMWindowSpan(left);
    return span ? [@"Starts in " stringByAppendingString:span] : @"Starts soon";
}

NSString *const MMWindowStartsHelp = @"For its first day MinMacs only watches. Then the rules that are on may act.";
NSString *const MMWindowTrashLine = @"Removed things go to the Trash.";

NSString *const MMWindowNoLidNote = @"This Mac has no lid.";

NSString *const MMWindowAwakeCard = @"Keep this Mac awake", *const MMWindowMacCard = @"This Mac",
                *const MMWindowCleanupCard = @"Clean up on its own";

static MMWindowSwitch *Switch(NSString *switchID, NSString *title, NSString *card, BOOL on, NSString *note, NSString *help) {
    MMWindowSwitch *s = [MMWindowSwitch new];
    s.switchID = switchID; s.title = title; s.card = card; s.on = on; s.note = note; s.help = help;
    return s;
}

NSString *MMWindowAwakeHelp(void) { return @"Keeps the Mac from sleeping, as caffeinate does, until you turn it off."; }

NSString *MMWindowAgentsHelp(NSInteger quietMinutes) {
    return [NSString stringWithFormat:@"Keeps the Mac awake while an agent works, and %ld min after.", (long)MAX(quietMinutes, 0)];
}

NSString *MMWindowAgentsNote(BOOL on, NSInteger holding) {
    return on && holding > 0 ? [NSString stringWithFormat:@"Awake now for %@", MMWindowCount(holding, @"agent", @"agents")] : nil;
}

MMWindowSwitch *MMWindowAwakeSwitch(BOOL on, NSString *note) {
    return Switch(@"awake", @"Keep awake now", MMWindowAwakeCard, on, note, MMWindowAwakeHelp());
}

MMWindowSwitch *MMWindowAgentsSwitch(BOOL on, NSString *note) {
    return Switch(@"agents", @"While agents work", MMWindowAwakeCard, on, note, MMWindowAgentsHelp(10));
}

MMWindowSwitch *MMWindowLidSwitch(BOOL on, BOOL inert, NSString *note) {
    MMWindowSwitch *s = Switch(@"lid", @"Lid closed", MMWindowAwakeCard, on, note,
                               @"Keeps the Mac working with the lid shut, while something keeps it awake.");
    s.inert = inert;
    return s;
}

NSString *MMWindowRuleSwitchTitle(NSString *ruleID) {
    return @{@"servers": @"Idle dev servers", @"apps": @"Apps when memory is low",
             @"worktrees": @"Finished worktrees", @"caches": @"Build output and leftovers"}[ruleID ?: @""];
}

/// Careful quits no app, so for apps only Eager is on.
BOOL MMWindowRuleIsOn(NSString *ruleID, NSInteger picked) { return [ruleID isEqualToString:@"apps"] ? picked == 2 : picked > 0; }

NSInteger MMWindowRuleOnChoice(NSString *ruleID) { return [ruleID isEqualToString:@"apps"] ? 2 : 1; }

NSString *MMWindowRuleSwitchNote(NSString *ruleID, NSInteger picked) {
    // The same rules as MMWindowRuleExplains, said short: Careful's and Eager's, by the mode it is in or would turn on to.
    NSInteger mode = MMWindowRuleIsOn(ruleID, picked) ? picked : MMWindowRuleOnChoice(ruleID);
    NSDictionary *careful = @{@"servers": @"After a review, stops a dev server quiet for 6 hours that no agent uses.",
                              @"worktrees": @"After a review, removes a worktree that is merged or whose remote is gone, and quiet for 7 days.",
                              @"caches": @"After a review, cleans up the build output of finished projects, and leftovers."};
    NSDictionary *eager = @{@"servers": @"After a review, stops each idle dev server the review finds no use for.",
                            @"apps": @"Quits only apps on your close list, and only while memory pressure or heat is high.",
                            @"worktrees": @"After a review, removes each worktree the review finds no use for.",
                            @"caches": @"After a review, cleans up caches too. A tool's own cleanup waits for your press."};
    return (mode == 2 ? eager : careful)[ruleID ?: @""];
}

MMWindowSwitch *MMWindowLoginSwitch(BOOL on, NSString *note) {
    // No state line: the switch says it. The welcome's sentence for this state is its tooltip.
    return Switch(@"login", @"Open at login", MMWindowMacCard, on, note, MMWindowLoginNote(on));
}

NSString *const MMWindowLookingNote = @"MinMacs is taking its first look. It takes a few seconds.";

NSString *MMWindowLoginNote(BOOL on) { return on ? @"MinMacs starts when you sign in." : @"MinMacs starts only when you open it."; }

@implementation MMWindowWelcome
+ (instancetype)welcomeWithFacts:(NSArray<MMWindowFact *> *)facts {
    MMWindowWelcome *w = [MMWindowWelcome new];
    w.title = @"Welcome to MinMacs";
    w.say = @"MinMacs watches what your agents, servers and apps hold. Press Fix Everything and it gives memory and disk back.";
    w.loginTitle = @"Open at login"; w.loginOn = YES;
    w.loginOnNote = MMWindowLoginNote(YES); w.loginOffNote = MMWindowLoginNote(NO);
    w.later = @"It can be changed later in Settings.";
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
- (BOOL)diskBackPartial { for (MMWindowFix *f in self.fixes) if (!f.needsYou && f.diskPartial) return YES; return NO; }
- (NSInteger)fixCount { NSInteger n = 0; for (MMWindowFix *f in self.fixes) if (!f.needsYou) n++; return n; }
@end
