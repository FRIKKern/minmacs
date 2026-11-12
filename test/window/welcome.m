// The welcome of the first launch, issue #62. Included by window.m, after removal.m. It uses window.m's world and
// controller.m's Spin and SnapshotAt. The login item is a fake that only writes down what it was asked, so no check
// here can touch the real one.

@interface WLogin : NSObject <MMWindowLogin>
@property BOOL enabled;
@property (strong) NSMutableArray<NSNumber *> *asked;   // each -setLogin:, in order
@end
@implementation WLogin
- (instancetype)init { if ((self = [super init])) _asked = [NSMutableArray new]; return self; }
- (BOOL)loginEnabled { return self.enabled; }
- (void)setLogin:(BOOL)on { [self.asked addObject:@(on)]; self.enabled = on; }
@end

static NSString *Asked(WLogin *l) { return l.asked.count ? [l.asked componentsJoinedByString:@","] : @"none"; }

/// A person new to MinMacs: nothing welcomed, nothing chosen, every rule where it starts, no day watched.
static void NewPerson(void) {
    MMSetPref(MMWindowWelcomedKey, nil);
    MMSetPref(MMRemovalKey, nil);
    MMSetPref(MMWindowLoginNotAskedKey, nil);
    MMSetPref(@"insomnia.agents", nil);
    for (NSString *rid in MMWindowRuleIDs()) MMSetPref([MMWindowRuleExpert(rid) stringByAppendingString:@".mode"], nil);
    [NSFileManager.defaultManager removeItemAtPath:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"] error:nil];
}

static void Welcome(void) {
    World();
    NewPerson();
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); };

    // The words.
    MMWindowWelcome *w = MMWindowWelcomeNow(NO);
    T(@"welcome: a person who never pressed Start gets one, with the switch on and Smart picked", @"yes yes 0 Start",
      [NSString stringWithFormat:@"%@ %@ %ld %@", YN(w != nil), YN(w.loginOn), (long)w.removalPicked, w.start]);
    T(@"welcome: it says what MinMacs is in two sentences", @"MinMacs watches what your agents, servers and apps hold. Press Fix Everything and it gives memory and disk back.", w.say);
    MMWindowSettings *st = MMWindowSettingsFrom(nil, [MMWindowExtras readWithLogin:YES]);
    MMWindowSettings *off = MMWindowSettingsFrom(nil, [MMWindowExtras readWithLogin:NO]);
    MMWindowRule *card = st.rules.lastObject;
    NSString *(^words)(NSString *, NSArray<MMWindowChoice *> *) = ^NSString *(NSString *title, NSArray<MMWindowChoice *> *choices) {
        NSMutableArray *out = [NSMutableArray arrayWithObject:title ?: @"(nil)"];
        for (MMWindowChoice *c in choices) [out addObject:[NSString stringWithFormat:@"%@: %@", c.title, c.explain]];
        return [out componentsJoinedByString:@" | "];
    };
    T(@"welcome: the removal choice says what its Settings card says, word for word", words(card.title, card.choices), words(w.removalTitle, w.removal));
    T(@"welcome: its three choices are Core's, in Core's order", @"Smart: Deletes what git or its tool can give back. The rest goes to the Trash. | "
      @"Trash: Everything goes to the Trash. The disk comes back when you empty it. | Delete: Deletes everything it removes at once. Nothing can be brought back.",
      [words(@"", w.removal) substringFromIndex:3]);
    T(@"welcome: Open at login says what each state means, as the Settings switch does", @"Open at login: MinMacs starts when you sign in. / MinMacs starts only when you open it.",
      [NSString stringWithFormat:@"%@: %@ / %@", w.loginTitle, w.loginOnNote, w.loginOffNote]);
    T(@"welcome: the Settings switch has the same two sentences", [NSString stringWithFormat:@"%@: %@ / %@", w.loginTitle, w.loginOnNote, w.loginOffNote],
      [NSString stringWithFormat:@"%@: %@ / %@", st.switches.lastObject.title, st.switches.lastObject.note, off.switches.lastObject.note]);
    NSString *(^facts)(MMWindowWelcome *) = ^NSString *(MMWindowWelcome *x) {
        NSMutableArray *out = [NSMutableArray new];
        for (MMWindowFact *f in x.facts) [out addObject:[NSString stringWithFormat:@"%@: %@", f.label, f.value]];
        return [out componentsJoinedByString:@" | "];
    };
    T(@"welcome: three facts for a new person", @"It waits a day: For its first day MinMacs stops, quits and removes nothing on its own. | "
      @"You set every rule: Each rule can be Off, Careful or Eager. Each starts on Careful. | "
      @"It starts quietly: No permission is asked at launch. The Mac stays awake while agents work.", facts(w));
    // Each fact is read from the code that makes it true, so it changes when that does.
    T(@"welcome: the first fact holds: no mode acts yet, and every rule is on Careful", @"no proactive,proactive,proactive,proactive", [NSString stringWithFormat:@"%@ %@",
      YN(MMWatchedLongEnough(@"locohost")), [@[MMModeName(MMModeFor(@"locohost")), MMModeName(MMModeFor(@"minmacs")), MMModeName(MMModeFor(@"workforest")), MMModeName(MMModeFor(@"noonoo"))] componentsJoinedByString:@","]]);
    T(@"welcome: Careful is the window's word for Proactive", @"Careful", MMWindowChoiceTitles()[MMModeProactive]);
    [[NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970 - 200000] writeToFile:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"]
                                                                                    atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *(^first)(void) = ^NSString *{ return [[facts(MMWindowWelcomeNow(NO)) componentsSeparatedByString:@" | You set every rule"] firstObject]; };
    T(@"welcome: after a day of watching it names what the rules as they stand may do: on Careful, no app is quit and no cache cleaned",
      @"It has watched a day: MinMacs may now stop servers, remove worktrees and clean up leftovers on its own.", first());
    MMSetMode(@"noonoo", MMModeEager); MMSetMode(@"minmacs", MMModeEager); MMSetMode(@"workforest", MMModeIdle);
    T(@"welcome: with rules moved it follows them, and no longer says where rules start",
      @"It has watched a day: MinMacs may now stop servers, quit apps and clean up caches on its own. | You set every rule: Each rule can be Off, Careful or Eager. Settings shows where each stands.",
      [[facts(MMWindowWelcomeNow(NO)) componentsSeparatedByString:@" | It starts quietly"] firstObject]);
    MMSetMode(@"locohost", MMModeIdle); MMSetMode(@"noonoo", MMModeIdle); MMSetMode(@"minmacs", MMModeProactive);
    T(@"welcome: with nothing left that acts, apps on Careful among them, it says so", @"It has watched a day: As the rules stand, MinMacs stops, quits and removes nothing on its own.", first());
    // Awake while agents work is read from its pref, so the welcome does not say it once that is off.
    MMSetPref(@"insomnia.agents", @NO);
    T(@"welcome: with awake while agents work turned off, the third fact does not say the Mac stays awake", @"It starts quietly: No permission is asked at launch.",
      [NSString stringWithFormat:@"%@: %@", MMWindowWelcomeNow(NO).facts.lastObject.label, MMWindowWelcomeNow(NO).facts.lastObject.value]);
    MMSetPref(@"insomnia.agents", nil);
    // Open at login: a person who used MinMacs before sees the switch where their login item stands.
    T(@"welcome: a person who used MinMacs before sees the switch where the login item stands now", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(MMWindowWelcomeNow(NO).loginOn), YN(MMWindowWelcomeNow(YES).loginOn)]);
    MMSetPref(MMWindowLoginNotAskedKey, @YES);
    T(@"welcome: after a first launch that left the login item for the welcome to ask about, off is nobody's answer yet and the switch is on", @"yes", YN(MMWindowWelcomeNow(NO).loginOn));
    MMSetPref(MMWindowLoginNotAskedKey, nil);
    MMSetRemovalChoice(MMRemovalTrash);
    T(@"welcome: a choice made before the first open, as with minmacs removal, is the one picked", @"1", @(MMWindowWelcomeNow(NO).removalPicked));
    NewPerson();
    NSMutableArray<NSString *> *shown = [NSMutableArray arrayWithObjects:w.title, w.say, w.loginTitle, w.loginOnNote, w.loginOffNote, w.removalTitle, w.later, w.start, nil];
    for (MMWindowChoice *c in w.removal) [shown addObjectsFromArray:@[c.title, c.explain]];
    for (MMWindowFact *f in w.facts) [shown addObjectsFromArray:@[f.label, f.value]];
    NSRegularExpression *marks = [NSRegularExpression regularExpressionWithPattern:@"[!…()]|\\.\\.\\.|hide icon|nothing needs you" options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *marked = [NSMutableArray new];
    for (NSString *s in shown) if ([marks firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) [marked addObject:s];
    T(@"welcome: no shown string names an old app, claims a result, says for good, or holds an exclamation mark or an ellipsis", @"none",
      Bad(shown).length || marked.count ? [NSString stringWithFormat:@"%@ %@", Bad(shown), [marked componentsJoinedByString:@" | "]] : @"none");

    // Opened before the first snapshot: the welcome is there at once, alone, and nothing is asked of the login item.
    WLogin *login = [WLogin new];
    MMWindowController *c = [MMWindowController new];
    c.shell = login;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    BOOL cold = MMGraph.shared.current == nil;
    [c setOpen:YES];
    T(@"welcome: opened before the first snapshot, one model holds the welcome alone", @"yes 1 yes 0 0", [NSString stringWithFormat:@"%@ %lu %@ %llu %lu", YN(cold),
      (unsigned long)models.count, YN(models.lastObject.welcome != nil), (unsigned long long)models.lastObject.generation, (unsigned long)models.lastObject.memoryGroups.count]);
    [c take:SnapshotAt(1)];
    BOOL got = Spin(20, ^BOOL { return models.lastObject.generation == 1; });
    T(@"welcome: the first snapshot's model still holds it, with the lists behind", @"yes yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN(got),
      YN(models.lastObject.welcome != nil), YN(models.lastObject.memoryGroups.count > 0)]);
    [c setOpen:NO]; [c setOpen:YES];
    [c take:SnapshotAt(2)];
    Spin(20, ^BOOL { return models.lastObject.generation == 2; });
    T(@"welcome: closed and opened again without Start, it shows again", @"yes", YN(models.lastObject.welcome != nil));
    T(@"welcome: until Start nothing is written and the login item is not touched", @"none no no", [NSString stringWithFormat:@"%@ %@ %@", Asked(login),
      YN(MMRemovalChosen()), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);

    // Start with the switch off and Trash picked.
    [c windowWelcomeStart:NO removal:MMRemovalTrash];
    T(@"welcome: Start with the switch off asks for no login item, writes the removal choice and marks the welcome done", @"none no trash yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Asked(login), YN(login.enabled), MMPref(MMRemovalKey), YN(MMRemovalChosen()), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    settle();
    got = Spin(20, ^BOOL { return models.lastObject.welcome == nil; });
    T(@"welcome: the next model holds no welcome, and Settings shows both answers", @"yes 1 no", [NSString stringWithFormat:@"%@ %ld %@", YN(got),
      (long)models.lastObject.settings.rules.lastObject.picked, YN(models.lastObject.settings.switches.lastObject.on)]);
    T(@"welcome: once chosen, the Settings card no longer says not chosen yet", @"(null)", [NSString stringWithFormat:@"%@", models.lastObject.settings.rules.lastObject.note]);
    [c windowWelcomeStart:YES removal:MMRemovalDelete];
    T(@"welcome: a second Start changes nothing", @"none trash", [NSString stringWithFormat:@"%@ %@", Asked(login), MMPref(MMRemovalKey)]);
    T(@"welcome: it never comes back", @"yes", YN(MMWindowWelcomeNow(NO) == nil));
    [c setOpen:NO];
    NSUInteger had = models.count;
    [c setOpen:YES];
    // Start had the graph build again, so this snapshot's generation is above any it made.
    [c take:SnapshotAt(1000)];
    got = Spin(20, ^BOOL { return models.count > had && models.lastObject.generation == 1000; });
    T(@"welcome: closed and opened again after Start, no model holds one", @"yes no", [NSString stringWithFormat:@"%@ %@", YN(got), YN(models.lastObject.welcome != nil)]);
    // Open at login stays changeable in Settings, through the same seam.
    [c windowSetSwitch:@"login" on:YES];
    settle();
    Spin(20, ^BOOL { return models.lastObject.settings.switches.lastObject.on; });
    T(@"welcome: the Settings switch adds the login item later, and the model shows it on with its sentence", @"1 yes MinMacs starts when you sign in.",
      [NSString stringWithFormat:@"%@ %@ %@", Asked(login), YN(models.lastObject.settings.switches.lastObject.on), models.lastObject.settings.switches.lastObject.note]);
    [c windowSetSwitch:@"login" on:NO];
    T(@"welcome: and takes it away again", @"1,0 no", [NSString stringWithFormat:@"%@ %@", Asked(login), YN(login.enabled)]);
    [c setOpen:NO];

    // Start with the switch on, as it stands when the person touches nothing.
    NewPerson();
    WLogin *second = [WLogin new];
    MMWindowController *d = [MMWindowController new];
    d.shell = second;
    d.onModel = ^(MMWindowModel *m) {};
    [d setOpen:YES];
    T(@"welcome: opening a window asks nothing of the login item", @"none", Asked(second));
    [d windowWelcomeStart:YES removal:MMRemovalSmart];
    T(@"welcome: Start with the switch on adds the login item once and writes Smart as the person's choice", @"1 yes smart yes", [NSString stringWithFormat:@"%@ %@ %@ %@",
      Asked(second), YN(second.enabled), MMPref(MMRemovalKey), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    [d setOpen:NO];

    // A number that is no choice writes no choice, and the welcome is still done.
    NewPerson();
    MMWindowController *e = [MMWindowController new];
    [e windowWelcomeStart:YES removal:7];
    T(@"welcome: a number that is no removal choice writes none, and with no shell nothing is added", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalChosen()), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    settle();
    // A person who used MinMacs before, with the login item off: a day watched, and no mark from a first launch.
    NewPerson();
    [[NSString stringWithFormat:@"%.0f\n", NSDate.date.timeIntervalSince1970 - 200000] writeToFile:[MMSupportDir() stringByAppendingPathComponent:@"watching-since"]
                                                                                    atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // That person presses Start without touching anything: the login item, off, is not added back.
    {
        WLogin *was = [WLogin new];
        MMWindowController *k = [MMWindowController new];
        k.shell = was;
        NSMutableArray<MMWindowModel *> *got = [NSMutableArray new];
        k.onModel = ^(MMWindowModel *m) { [got addObject:m]; };
        [k setOpen:YES];
        [k take:SnapshotAt(2000)];
        Spin(20, ^BOOL { return got.lastObject.generation > 0; });
        MMWindowModel *m = got.lastObject;
        T(@"welcome: for them the welcome's switch and the Settings switch agree, both off", @"no no", [NSString stringWithFormat:@"%@ %@", YN(m.welcome.loginOn), YN(m.settings.switches.lastObject.on)]);
        [k windowWelcomeStart:m.welcome.loginOn removal:m.welcome.removalPicked];
        T(@"welcome: their untouched Start asks nothing of the login item, and it stays off", @"none no yes", [NSString stringWithFormat:@"%@ %@ %@", Asked(was), YN(was.enabled), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
        dispatch_sync(window, ^{});
        [k setOpen:NO];
        // The same person with the login item on, who turns the switch off: Start takes it away.
        MMSetPref(MMWindowWelcomedKey, nil); MMSetPref(MMRemovalKey, nil);
        was.enabled = YES;
        MMWindowController *k2 = [MMWindowController new];
        k2.shell = was;
        [k2 setOpen:YES];
        Spin(20, ^BOOL { return k2.model != nil; });
        T(@"welcome: with the login item on, their switch starts on", @"yes", YN(k2.model.welcome.loginOn));
        [k2 windowWelcomeStart:YES removal:MMRemovalSmart];
        T(@"welcome: and an untouched Start asks nothing again", @"none yes", [NSString stringWithFormat:@"%@ %@", Asked(was), YN(was.enabled)]);
        MMSetPref(MMWindowWelcomedKey, nil);
        [k2 windowWelcomeStart:NO removal:MMRemovalSmart];
        T(@"welcome: turned off in the welcome, Start takes the login item away", @"0 no", [NSString stringWithFormat:@"%@ %@", Asked(was), YN(was.enabled)]);
        dispatch_sync(window, ^{});
        [k2 setOpen:NO];
    }
    NewPerson();
    MMSetPref(MMWindowWelcomedKey, @YES);
}
