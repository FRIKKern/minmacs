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
    MMSetPref(MMWindowNewPersonKey, @YES);
    MMSetPref(MMRemovalKey, nil);
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
    MMSetMode(@"noonoo", MMModeEager);
    T(@"welcome: after a day of watching, and with a rule moved, it no longer says it waits or where rules start",
      @"It has watched a day: A rule that is not Off may now stop, quit or remove things on its own. | You set every rule: Each rule can be Off, Careful or Eager. Settings shows where each stands.",
      [[facts(MMWindowWelcomeNow(NO)) componentsSeparatedByString:@" | It starts quietly"] firstObject]);
    MMSetRemovalChoice(MMRemovalTrash);
    T(@"welcome: a choice made before the first open, as with minmacs removal, is the one picked", @"1", @(MMWindowWelcomeNow(NO).removalPicked));
    // A person who had MinMacs before the welcome: launched, never welcomed, no mark of a first launch with the window.
    MMSetPref(MMWindowNewPersonKey, nil);
    T(@"welcome: for a person who had MinMacs before, the switch starts on what the login item is now, and their removal choice is picked", @"yes no 1",
      [NSString stringWithFormat:@"%@ %@ %ld", YN(MMWindowWelcomeNow(YES).loginOn), YN(MMWindowWelcomeNow(NO).loginOn), (long)MMWindowWelcomeNow(NO).removalPicked]);
    MMSetPref(MMRemovalKey, nil);
    T(@"welcome: with no removal choice of theirs, Smart is picked for them too", @"0", @(MMWindowWelcomeNow(NO).removalPicked));
    T(@"welcome: a new person's switch starts on whatever the login item is", @"yes yes yes no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(MMWindowWelcomeLoginStartsOn(YES, NO)), YN(MMWindowWelcomeLoginStartsOn(YES, YES)), YN(MMWindowWelcomeLoginStartsOn(NO, YES)), YN(MMWindowWelcomeLoginStartsOn(NO, NO))]);
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
    T(@"welcome: Start with the switch off asks for no login item, writes the removal choice and marks the welcome done", @"0 no trash yes yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", Asked(login), YN(login.enabled), MMPref(MMRemovalKey), YN(MMRemovalChosen()), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    settle();
    got = Spin(20, ^BOOL { return models.lastObject.welcome == nil; });
    T(@"welcome: the next model holds no welcome, and Settings shows both answers", @"yes 1 no", [NSString stringWithFormat:@"%@ %ld %@", YN(got),
      (long)models.lastObject.settings.rules.lastObject.picked, YN(models.lastObject.settings.switches.lastObject.on)]);
    T(@"welcome: once chosen, the Settings card no longer says not chosen yet", @"(null)", [NSString stringWithFormat:@"%@", models.lastObject.settings.rules.lastObject.note]);
    [c windowWelcomeStart:YES removal:MMRemovalDelete];
    T(@"welcome: a second Start changes nothing", @"0 trash", [NSString stringWithFormat:@"%@ %@", Asked(login), MMPref(MMRemovalKey)]);
    T(@"welcome: it never comes back", @"yes", YN(MMWindowWelcomeNow(YES) == nil));
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
    T(@"welcome: the Settings switch adds the login item later, and the model shows it on with its sentence", @"0,1 yes MinMacs starts when you sign in.",
      [NSString stringWithFormat:@"%@ %@ %@", Asked(login), YN(models.lastObject.settings.switches.lastObject.on), models.lastObject.settings.switches.lastObject.note]);
    [c windowSetSwitch:@"login" on:NO];
    T(@"welcome: and takes it away again", @"0,1,0 no", [NSString stringWithFormat:@"%@ %@", Asked(login), YN(login.enabled)]);
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

    // A person who had MinMacs before, through the controller: the model's switch follows their login item, and Start
    // with the switch left alone changes nothing about it.
    NewPerson();
    MMSetPref(MMWindowNewPersonKey, nil);
    for (NSNumber *had in @[@NO, @YES]) {
        MMSetPref(MMWindowWelcomedKey, nil);
        WLogin *old = [WLogin new];
        old.enabled = had.boolValue;
        MMWindowController *u = [MMWindowController new];
        u.shell = old;
        NSMutableArray<MMWindowModel *> *seen = [NSMutableArray new];
        u.onModel = ^(MMWindowModel *m) { [seen addObject:m]; };
        [u setOpen:YES];
        Spin(20, ^BOOL { return seen.lastObject.welcome != nil; });
        BOOL starts = seen.lastObject.welcome.loginOn;
        [u windowWelcomeStart:starts removal:seen.lastObject.welcome.removalPicked];
        T(had.boolValue ? @"welcome: a person from before with a login item sees the switch on, and Start keeps the item"
                        : @"welcome: a person from before with no login item sees the switch off, and Start adds none",
          had.boolValue ? @"yes yes yes" : @"no no yes", [NSString stringWithFormat:@"%@ %@ %@", YN(starts), YN(old.enabled), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
        settle();
        [u setOpen:NO];
    }

    // A number that is no choice writes no choice, and the welcome is still done.
    NewPerson();
    MMWindowController *e = [MMWindowController new];
    [e windowWelcomeStart:YES removal:7];
    T(@"welcome: a number that is no removal choice writes none, and with no shell nothing is added", @"no yes", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalChosen()), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    settle();
    NewPerson();
    MMSetPref(MMWindowWelcomedKey, @YES);
}
