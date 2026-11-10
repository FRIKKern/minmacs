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
        @"caches": @[@"Moves nothing to the Trash on its own.",
                     @"After a review, moves the build output of finished projects and leftovers to the Trash.",
                     @"After a review, also moves caches to the Trash. A tool's own cleanup always waits for your press."],
    }[ruleID];
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
    // Proactive quits no app, so for apps only Eager ever acts on its own.
    BOOL acts = mode == MMModeEager || (mode == MMModeProactive && ![ruleID isEqualToString:@"apps"]);
    NSInteger ready = Ready(p, expert);
    NSTimeInterval left = MMWatchingLeft(expert);
    if (acts && left > 0) r.note = [NSString stringWithFormat:@"It only watches for %@ more, then it may act.", MMDuration(left)];
    else if (!acts && ready > 0) r.note = [NSString stringWithFormat:@"%ld ready. %@ for your press.", (long)ready, ready == 1 ? @"It waits" : @"They wait"];
    return r;
}

MMWindowSettings *MMWindowSettingsFrom(MMPerformance *p, MMWindowExtras *extras) {
    MMWindowSettings *st = [MMWindowSettings new];
    NSMutableArray *rules = [NSMutableArray new];
    // A rule shows only for an expert that runs in this binary and has a mode rule of its own.
    for (NSString *rid in MMWindowRuleIDs()) {
        id<MMExpert> e = MMExpertNamed(MMWindowRuleExpert(rid));
        if (e && [[e policy] respondsToSelector:@selector(modeKeeps:mode:review:)]) [rules addObject:Rule(rid, p)];
    }
    st.rules = rules;
    MMWindowSwitch *lid = [MMWindowSwitch new];
    lid.switchID = @"lid"; lid.title = @"Keep working with the lid closed"; lid.on = extras.lidOn; lid.note = extras.lidNote;
    MMWindowSwitch *login = [MMWindowSwitch new];
    login.switchID = @"login"; login.title = @"Open at login"; login.on = extras.loginOn; login.note = extras.loginNote;
    st.switches = @[lid, login];
    return st;
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
