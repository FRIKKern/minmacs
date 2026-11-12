// Settings of the menu window, MMWindowFeed.h: one rule per expert that has modes, and the two switches.
//
// A mode is per expert, the pref <expert>.mode, and Core has three: Idle, Proactive and Eager. The window shows them
// as "Off", "Careful" and "Eager". Proactive is not "Ask": it acts on its own on clear cases, so a title that
// promised a question first would be false. Each explain line below says what that expert's -modeKeeps: does today
// for that mode. test/window.sh checks the lines against the experts' sources, so a changed rule fails there.
// No mode acts in the first day of watching, MMWatchedLongEnough, and the note says so while that holds.
#import "Shell/MMWindowFeed.h"
#import "UI/MMFormat.h"

NSArray<NSString *> *MMWindowRuleIDs(void) { return @[@"servers", @"apps", @"worktrees", @"caches"]; }

NSString *MMWindowRuleExpert(NSString *ruleID) {
    return @{@"servers": @"locohost", @"apps": @"minmacs", @"worktrees": @"workforest", @"caches": @"noonoo"}[ruleID ?: @""];
}

NSArray<NSString *> *MMWindowChoiceTitles(void) { return @[@"Off", @"Careful", @"Eager"]; }

NSString *const MMWindowRemovalRuleID = @"removal";

static NSString *RuleTitle(NSString *ruleID) {
    return @{@"servers": @"Stop idle servers", @"apps": @"Quit apps", @"worktrees": @"Remove finished worktrees",
             @"caches": @"Clean caches and leftovers"}[ruleID];
}

/// What each mode does today, for Idle, Proactive and Eager. Every claim is the expert's own rule:
/// servers: MMLHModeKeeps in MMLocoHost.m, with Proactive's wait of MMLHProactiveQuiet, 6 hours.
/// apps: MMMinMacsPolicy in MMMinMacsExpert.m. Proactive never quits an app.
/// worktrees: MMWFKeeps in MMWorkForest.m, with Proactive's wait of MMWFProactiveQuiet, 7 days.
/// caches: MMNNPolicyObject in MMNooNooExpert.m.
static NSArray<NSString *> *Explains(NSString *ruleID) {
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
    }[ruleID];
}

/// Whether a rule in this mode ever acts on its own. Proactive quits no app, so for apps only Eager does.
static BOOL RuleActs(NSString *ruleID, MMMode mode) {
    return mode == MMModeEager || (mode == MMModeProactive && ![ruleID isEqualToString:@"apps"]);
}

/// A rule shows only for an expert that runs in this binary and has a mode rule of its own.
static BOOL RuleShows(NSString *ruleID) {
    id<MMExpert> e = MMExpertNamed(MMWindowRuleExpert(ruleID));
    return e && [[e policy] respondsToSelector:@selector(modeKeeps:mode:review:)];
}

/// The fix kinds an expert's own press would run, for the note of a rule that is off.
static NSInteger Ready(MMPerformance *p, NSString *expert) {
    NSInteger n = 0;
    for (MMPerformanceFix *f in p.fixes) if (!f.wrapUp && !f.needsYou && [f.expert isEqualToString:expert]) n += (NSInteger)f.actions.count;
    return n;
}

static MMWindowRule *Rule(NSString *ruleID, MMPerformance *p) {
    NSString *expert = MMWindowRuleExpert(ruleID);
    MMMode mode = MMModeFor(expert);
    MMWindowRule *r = [MMWindowRule new];
    r.ruleID = ruleID; r.title = RuleTitle(ruleID);
    NSMutableArray *choices = [NSMutableArray new];
    NSArray<NSString *> *titles = MMWindowChoiceTitles(), *explains = Explains(ruleID);
    for (NSUInteger i = 0; i < titles.count; i++) {
        MMWindowChoice *c = [MMWindowChoice new];
        c.title = titles[i]; c.explain = explains[i];
        [choices addObject:c];
    }
    r.choices = choices;
    r.picked = (NSInteger)mode;
    BOOL acts = RuleActs(ruleID, mode);
    NSInteger ready = Ready(p, expert);
    NSTimeInterval left = MMWatchingLeft(expert);
    if (acts && left > 0) r.note = [NSString stringWithFormat:@"It only watches for %@ more, then it may act.", MMDuration(left)];
    else if (!acts && ready > 0) r.note = [NSString stringWithFormat:@"%ld ready. %@ for your press.", (long)ready, ready == 1 ? @"It waits" : @"They wait"];
    return r;
}

/// Smart, Trash and Delete with Core's one sentence each. The Settings card and the welcome show the same three.
static NSArray<MMWindowChoice *> *RemovalChoices(void) {
    NSMutableArray *choices = [NSMutableArray new];
    for (NSInteger i = MMRemovalSmart; i <= MMRemovalDelete; i++) {
        MMWindowChoice *c = [MMWindowChoice new];
        c.title = MMRemovalChoiceTitle((MMRemovalChoice)i); c.explain = MMRemovalChoiceExplain((MMRemovalChoice)i);
        [choices addObject:c];
    }
    return choices;
}

/// "When MinMacs removes things": the removal choice of Core/Act/MMRemoval.h, with Core's own words for each choice.
/// It is no expert's mode, so it shows whatever experts run, after their rules.
static MMWindowRule *RemovalRule(void) {
    MMWindowRule *r = [MMWindowRule new];
    r.ruleID = MMWindowRemovalRuleID; r.title = MMWindowRemovalTitle;
    r.choices = RemovalChoices();
    r.picked = (NSInteger)MMRemovalChoiceNow();
    // Smart is shown as picked while nothing is, and the note says what holds until the person picks.
    r.note = MMRemovalNotChosenNote();
    return r;
}

MMWindowSettings *MMWindowSettingsFrom(MMPerformance *p, MMWindowExtras *extras) {
    MMWindowSettings *st = [MMWindowSettings new];
    NSMutableArray *rules = [NSMutableArray new];
    for (NSString *rid in MMWindowRuleIDs()) if (RuleShows(rid)) [rules addObject:Rule(rid, p)];
    [rules addObject:RemovalRule()];
    st.rules = rules;
    MMWindowSwitch *lid = [MMWindowSwitch new];
    lid.switchID = @"lid"; lid.title = @"Keep working with the lid closed"; lid.on = extras.lidOn; lid.note = extras.lidNote;
    MMWindowSwitch *login = [MMWindowSwitch new];
    login.switchID = @"login"; login.title = @"Open at login"; login.on = extras.loginOn;
    // The same sentence the welcome shows for this state of the switch.
    login.note = extras.loginNote ?: MMWindowLoginNote(extras.loginOn);
    st.switches = @[lid, login];
    return st;
}

#pragma mark - The welcome

NSString *const MMWindowWelcomedKey = @"core.welcomed";

NSString *const MMWindowLoginNotAskedKey = @"core.loginNotAsked";

/// "servers and worktrees", "servers, worktrees and leftovers".
static NSString *Listed(NSArray<NSString *> *words) {
    if (words.count < 2) return words.firstObject ?: @"";
    NSArray *head = [words subarrayWithRange:NSMakeRange(0, words.count - 1)];
    return [NSString stringWithFormat:@"%@ and %@", [head componentsJoinedByString:@", "], words.lastObject];
}

/// Each fact is true of the code named beside it, and is left out or said another way when it would not be.
MMWindowWelcome *MMWindowWelcomeNow(BOOL loginNow) {
    if (MMPrefBool(MMWindowWelcomedKey, NO)) return nil;
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    // MMPlan and MMRunAction in Core/Act/MMAct.m: no mode acts before MMWatchedLongEnough, a day after the first launch.
    // The day is one for every expert. Before the first launch nothing is written, and the whole day is left.
    NSTimeInterval left = MMWatchingLeft(@"minmacs");
    BOOL careful = YES;
    NSMutableArray<NSString *> *may = [NSMutableArray new];
    for (NSString *rid in MMWindowRuleIDs()) {
        if (!RuleShows(rid)) continue;
        MMMode mode = MMModeFor(MMWindowRuleExpert(rid));
        if (mode != MMModeProactive) careful = NO;
        // What each rule does on its own in the mode it is in, Explains above: Careful cleans up no cache.
        if (RuleActs(rid, mode)) [may addObject:@{@"servers": @"stop servers", @"apps": @"quit apps", @"worktrees": @"remove worktrees",
                                                  @"caches": mode == MMModeEager ? @"clean up caches" : @"clean up leftovers"}[rid]];
    }
    if (left > 0) [facts addObject:[MMWindowFact label:@"It waits a day" value:@"For its first day MinMacs stops, quits and removes nothing on its own."]];
    else if (may.count) [facts addObject:[MMWindowFact label:@"It has watched a day" value:[NSString stringWithFormat:@"MinMacs may now %@ on its own.", Listed(may)]]];
    else [facts addObject:[MMWindowFact label:@"It has watched a day" value:@"As the rules stand, MinMacs stops, quits and removes nothing on its own."]];
    // MMModeFor: a mode with no value is Proactive, which the window calls Careful. Rules brought over from the old
    // apps may stand elsewhere, and then the welcome does not say where they start.
    [facts addObject:[MMWindowFact label:@"You set every rule" value:careful ? @"Each rule can be Off, Careful or Eager. Each starts on Careful."
                                                                           : @"Each rule can be Off, Careful or Eager. Settings shows where each stands."]];
    // AGENTS.md invariant 6: no permission is asked for at launch; the notifier asks at its first notice. PLAN.md
    // decision 4: awake while an agent works starts on, the pref insomnia.agents of MMINPrefs in Experts/Insomnia.
    // With that pref off, or no keep-awake expert in this binary, the welcome does not say it.
    BOOL awake = MMExpertNamed(@"insomnia") != nil && MMPrefBool(@"insomnia.agents", YES);
    [facts addObject:[MMWindowFact label:@"It starts quietly" value:awake ? @"No permission is asked at launch. The Mac stays awake while agents work."
                                                                          : @"No permission is asked at launch."]];
    MMWindowWelcome *w = [MMWindowWelcome welcomeWithRemoval:RemovalChoices() picked:(NSInteger)MMRemovalChoiceNow() facts:facts];
    // New to MinMacs: never launched, or a first launch that left the login item for this welcome to ask about.
    // Anyone else launched it before, so the login item as it is now is their answer, whatever was watched.
    BOOL fresh = !MMPrefBool(@"core.launched", NO) || MMPrefBool(MMWindowLoginNotAskedKey, NO);
    w.loginOn = fresh || loginNow;
    return w;
}

void MMWindowWelcomeDone(NSInteger removal) {
    if (removal >= MMRemovalSmart && removal <= MMRemovalDelete) MMSetRemovalChoice((MMRemovalChoice)removal);
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMSetPref(MMWindowLoginNotAskedKey, nil);
}

#pragma mark - The switches

@implementation MMWindowExtras

/// The keep-awake expert is read through its published state by key, so the shell names no expert class and links
/// without Sources/Experts, as test/shell.sh builds it. The keys are MMINState's in MMInsomnia.h.
+ (instancetype)readWithLogin:(BOOL)loginOn {
    MMWindowExtras *x = [MMWindowExtras new];
    x.loginOn = loginOn;
    id<MMExpert> e = MMExpertNamed(@"insomnia");
    id st = nil;
    @try { st = [(id)e respondsToSelector:NSSelectorFromString(@"state")] ? [(id)e valueForKey:@"state"] : nil; }
    @catch (NSException *ex) { st = nil; }
    if (!st) {
        // Before the first pass, and in a cold CLI, the pref is all there is.
        x.lidOn = MMPrefBool(@"insomnia.lid", NO);
        return x;
    }
    @try {
        x.lidOn = [[st valueForKeyPath:@"prefs.lid"] boolValue];
        NSString *paused = [st valueForKey:@"pauseReason"], *problem = [st valueForKey:@"lidProblem"];
        BOOL live = [[st valueForKey:@"lidLive"] boolValue], other = [[st valueForKey:@"otherApp"] boolValue];
        BOOL laptop = [[st valueForKey:@"laptop"] boolValue];
        if (!laptop) x.lidNote = @"This Mac has no lid, so it changes nothing here.";
        else if (!x.lidOn) x.lidNote = nil;
        else if (other) x.lidNote = @"Another app sets it now.";
        else if (live) x.lidNote = @"On now. The Mac keeps running with the lid shut.";
        else if (paused.length) x.lidNote = [NSString stringWithFormat:@"Paused, %@.", paused];
        else if (problem.length) x.lidNote = [NSString stringWithFormat:@"Off, %@.", problem];
        else x.lidNote = @"Off until something keeps the Mac awake.";
    } @catch (NSException *ex) { x.lidNote = nil; }
    return x;
}

@end
