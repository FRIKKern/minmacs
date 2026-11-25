// A row's menu in the window, like the Dock's menu for an app: what each kind offers, and what a pick runs. Included by
// window.m after the others, and run by test/window.sh as `row-menu` and `row-menu-controller`. It uses window.m's
// world and fake experts, controller.m's Spin and SnapshotAt and welcome.m's fake login item. Every action is a fake
// that acts only on the fixture folder: a stop or a quit writes its key to a list, and a move to the Trash goes to
// the home's own Trash. The desk is a fake too, so no app is shown, no folder opened and nothing copied.

static NSMutableArray<NSString *> *gPressed;    // "findingID what step by" of each press the window ran

/// A press as the expert's own menu runs it: the fixture's action, which also says who asked and which request.
@interface WPress : WAction
@property (copy) NSString *what;
@property MMStopStep step;
@end
@implementation WPress
- (NSString *)kind { return [self.what isEqualToString:@"trash"] ? @"trash" : self.what; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    @synchronized (gPressed) {
        [gPressed addObject:[NSString stringWithFormat:@"%@ %@ %@ %@", self.finding.findingID, self.what, self.step == MMStopKill ? @"kill" : @"term", record.by]];
    }
    return [super perform:record error:error];
}
@end

@implementation WExpert (RowMenu)
/// As the real experts: a server and a helper stop, an app quits, a worktree with a proposal is removed, and a cache
/// that goes to the Trash moves there. A helper, a removal and a move have no second request.
- (id<MMAction>)pressAction:(NSString *)what finding:(MMFinding *)f step:(MMStopStep)step policy:(id<MMExpertPolicy> *)policy {
    BOOL fits = ([what isEqualToString:@"stop"] && ([f.kind isEqualToString:@"server"] || ([f.kind isEqualToString:@"helper"] && step == MMStopTerm))) ||
                ([what isEqualToString:@"quit"] && [f.kind isEqualToString:@"app"]) ||
                ([what isEqualToString:@"remove"] && [f.kind isEqualToString:@"worktree"] && f.proposal && step == MMStopTerm) ||
                ([what isEqualToString:@"trash"] && [f.kind isEqualToString:@"clutter"] && f.proposal.reversibility == MMReversibleTrash && step == MMStopTerm);
    if (!fits) return nil;
    WPress *a = [WPress new];
    a.finding = f; a.what = what; a.step = step;
    if (policy) *policy = [self policy];
    return a;
}
@end

/// The desk's calls, in order, as "call value".
@interface WDesk : NSObject <MMWindowDesk>
@property NSMutableArray<NSString *> *calls;
@end
@implementation WDesk
- (instancetype)init { if ((self = [super init])) _calls = [NSMutableArray new]; return self; }
- (void)note:(NSString *)call value:(NSString *)v { @synchronized (self.calls) { [self.calls addObject:[NSString stringWithFormat:@"%@ %@", call, v]]; } }
- (void)showApp:(pid_t)pid { [self note:@"show" value:[NSString stringWithFormat:@"%d", pid]]; }
- (void)hideApp:(pid_t)pid { [self note:@"hide" value:[NSString stringWithFormat:@"%d", pid]]; }
- (void)reveal:(NSString *)path { [self note:@"reveal" value:path.lastPathComponent]; }
- (void)openFolder:(NSString *)path { [self note:@"folder" value:path.lastPathComponent]; }
- (void)openInTerminal:(NSString *)path { [self note:@"terminal" value:path.lastPathComponent]; }
- (void)openURL:(NSString *)url { [self note:@"url" value:url]; }
- (void)copyText:(NSString *)text { [self note:@"copy" value:text]; }
@end

/// The finding with more facts: findings are values, so it is made again.
static MMFinding *With(MMFinding *f, NSDictionary *more) {
    NSMutableDictionary *x = [f.facts mutableCopy];
    [x addEntriesFromDictionary:more];
    return [MMFinding expert:f.expert kind:f.kind stableKey:f.stableKey build:^(MMFindingBuilder *b) {
        b.title = f.title; b.path = f.path; b.instanceKey = f.instanceKey; b.procs = f.procs; b.cost = f.cost; b.proposal = f.proposal; b.facts = x;
    }];
}

/// The world of window.m with the facts the menus read: a server's address and folder, an app's bundle and a Quit
/// asked for already, and MinMacs itself among the apps.
static void RowMenuWorld(void) {
    World();
    gPressed = [NSMutableArray new];
    NSMutableArray *servers = [NSMutableArray new];
    for (MMFinding *f in gFindings[@"locohost"])
        [servers addObject:[f.stableKey isEqualToString:@"db"] ? f : With(f, @{@"url": [NSString stringWithFormat:@"http://localhost:%@/", f.facts[@"port"]], @"cwd": f.path})];
    gFindings[@"locohost"] = servers;
    NSMutableArray *mm = [NSMutableArray new];
    for (MMFinding *f in gFindings[@"minmacs"])
        [mm addObject:[f.stableKey isEqualToString:@"com.example.chat"] ? With(f, @{@"bundlePath": @"/Applications/Chat.app", @"quitAsked": @YES, @"pid": @71020}) : f];
    Proc(getpid(), 40 * MB);
    [mm addObject:Finding(@"minmacs", @"app", @"no.guerrilla.minmacs", @"MinMacs", nil, getpid(), 40 * MB, 0, nil,
                          @{@"bundleID": @"no.guerrilla.minmacs", @"name": @"MinMacs", @"group": @"unsorted", @"pid": @(getpid())})];
    gFindings[@"minmacs"] = mm;
    // The main checkout says so, as WorkForest's facts do.
    NSMutableArray *trees = [NSMutableArray new];
    for (MMFinding *f in gFindings[@"workforest"]) [trees addObject:[f.path isEqualToString:Dir(@"repo")] ? With(f, @{@"main": @YES}) : f];
    gFindings[@"workforest"] = trees;
}

/// A menu as one line: items by " | ", a separator as " / ", an Option alternate in brackets after its item.
static NSString *MenuSaid(MMWindowRow *r) {
    if (!r) return @"(no row)";
    if (!r.menu.count) return @"(none)";
    NSMutableString *out = [NSMutableString new];
    for (MMWindowMenuItem *i in r.menu) {
        if (i.alternate) { [out appendFormat:@" [%@]", i.title]; continue; }
        if (out.length) [out appendString:i.startsGroup ? @" / " : @" | "];
        [out appendString:i.title];
        if (i.link) [out appendFormat:@" -> %@", i.link];
    }
    return out;
}

static void RowMenu(void) {
    RowMenuWorld();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    NSString *helper = nil, *agent = @"minmacs:agent:claude-code:s-71010";
    for (MMWindowRow *r in Rows(m)) if (r.kind == MMWindowHelper) helper = r.key;
    for (MMWindowRow *r in Rows(m)) Info([NSString stringWithFormat:@"%@: %@", r.key, MenuSaid(r)]);
    T(@"row menu: an app has Show and Hide, Quit with Force Quit under Option once a Quit was asked, then Show in Finder, Keep and Copy PID",
      @"Show | Hide / Quit [Force Quit] / Show in Finder | Keep for 7 Days | Copy PID", MenuSaid([m row:@"minmacs:app:com.example.chat"]));
    T(@"row menu: an app nobody asked to quit has no Force Quit, and nothing to show in the Finder without its bundle",
      @"Show | Hide / Quit / Keep for 7 Days | Copy PID", MenuSaid([m row:@"minmacs:app:com.example.editor"]));
    T(@"row menu: MinMacs itself has no menu: no Quit, no Hide", @"(none)", MenuSaid([m row:@"minmacs:app:no.guerrilla.minmacs"]));
    T(@"row menu: a helper stops, with no Show, Hide or Force Quit", @"Stop / Show in Finder | Keep for 7 Days | Copy PID", MenuSaid(helper ? [m row:helper] : nil));
    T(@"row menu: a server opens and copies its address, stops with Force Stop under Option, keeps for 4 hours and shows its folder",
      @"Open in Browser | Copy URL / Stop [Force Stop] | Keep for 4 Hours / Show in Finder", MenuSaid([m row:@"locohost:server:w1#dev"]));
    T(@"row menu: a server in an agent's tree shows that agent", [NSString stringWithFormat:@"Open in Browser | Copy URL / Stop [Force Stop] | Keep for 4 Hours / Show Agent -> %@ | Show in Finder", agent],
      MenuSaid([m row:@"locohost:server:app#dev"]));
    T(@"row menu: a protected server has no Stop and no Keep", @"Show in Finder", MenuSaid([m row:@"locohost:server:db"]));
    T(@"row menu: an agent shows its folder and copies its session id", @"Show in Finder / Copy Session ID", MenuSaid([m row:agent]));
    T(@"row menu: a finished worktree opens, copies its branch, keeps, wraps up and is removed",
      @"Open in Finder | Open in Terminal | Copy Branch Name / Keep for 7 Days | Wrap Up | Remove", MenuSaid([m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"trees/fix-auth-redirect")]]));
    T(@"row menu: the main checkout is neither kept nor removed", @"Open in Finder | Open in Terminal | Copy Branch Name", MenuSaid([m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"repo")]]));
    T(@"row menu: a cache that is free moves to the Trash", @"Show in Finder / Move to Trash | Keep for 7 Days", MenuSaid([m row:@"noonoo:clutter:derived-data"]));
    T(@"row menu: a cache in use does not, and a tool's own cleanup is not offered", @"Show in Finder / Keep for 7 Days | Show in Finder / Keep for 7 Days",
      [NSString stringWithFormat:@"%@ | %@", MenuSaid([m row:@"noonoo:clutter:sims"]), MenuSaid([m row:@"noonoo:clutter:pnpm-store"])]);

    // Words: title case, no ellipsis, no parentheses, no old name, and an alternate always under the item it stands for.
    NSRegularExpression *bad = [NSRegularExpression regularExpressionWithPattern:@"\\.\\.\\.|…|\\(|locohost|workforest|noo-?noo|insomnia|for good|permanently"
                                                                         options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *wrong = [NSMutableArray new];
    for (MMWindowRow *r in Rows(m)) for (NSUInteger i = 0; i < r.menu.count; i++) {
        MMWindowMenuItem *it = r.menu[i];
        NSString *t = [it.title stringByAppendingFormat:@" %@", it.help ?: @""];
        if ([bad firstMatchInString:t options:0 range:NSMakeRange(0, t.length)]) [wrong addObject:t];
        if (it.alternate && (i == 0 || r.menu[i - 1].alternate)) [wrong addObject:[@"alone: " stringByAppendingString:it.title]];
        if ([it.title characterAtIndex:0] != [it.title.uppercaseString characterAtIndex:0]) [wrong addObject:it.title];
    }
    T(@"row menu: every title and tooltip keeps the words rules, and every alternate stands under its item", @"", [wrong componentsJoinedByString:@" | "]);

    // A keep that holds already takes its Keep away, and keeps Stop from being offered, as the press would be refused.
    dispatch_sync(MMQueue(@"windowtest", @"keep", QOS_CLASS_USER_INITIATED), ^{
        [MMKeep keep:@"w1#dev" expert:@"locohost" until:[NSDate dateWithTimeIntervalSinceNow:3600] by:@"cli" name:@"dev"];
    });
    MMWindowModel *kept = MMWindowModelFrom(s, p, nil);
    T(@"row menu: a kept server offers no Stop and no second Keep", @"Open in Browser | Copy URL / Show in Finder", MenuSaid([kept row:@"locohost:server:w1#dev"]));
    dispatch_sync(MMQueue(@"windowtest", @"keep", QOS_CLASS_USER_INITIATED), ^{
        [MMKeep keep:@"w1#dev" expert:@"locohost" until:nil by:@"cli" name:@"dev"];
    });

    // The JSON says the same, so an agent reads what the window offers.
    NSDictionary *j = [m json];
    NSString *menu = nil;
    for (NSDictionary *g in j[@"memory"]) for (NSDictionary *r in g[@"rows"]) if ([r[@"key"] isEqual:@"minmacs:app:com.example.chat"])
        menu = [[r[@"menu"] valueForKey:@"action"] componentsJoinedByString:@","];
    T(@"row menu: --json gives each row its menu", @"show,hide,quit,force-quit,reveal,keep,copy-pid", menu);
}

/// What the controller does with a pick: each item through the action paths by "window", or the desk.
static void RowMenuController(void) {
    RowMenuWorld();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMLogOpenOffMain();
    __block BOOL open = NO;
    MMLogWhenOpen(^(MMLog *l) { open = l != nil; });
    Spin(20, ^BOOL { return open; });
    MMWindowController *c = [MMWindowController new];
    WDesk *desk = [WDesk new];
    WLogin *login = [WLogin new];
    c.shell = login; c.desk = desk;
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    [c setOpen:YES];
    [c take:SnapshotAt(1)];
    Spin(20, ^BOOL { return models.count > 0; });
    NSString *(^pressed)(void) = ^NSString * { @synchronized (gPressed) { return [gPressed componentsJoinedByString:@" | "]; } };
    BOOL (^pick)(NSString *, NSString *, NSUInteger) = ^BOOL(NSString *key, NSString *action, NSUInteger want) {
        [c windowRow:key item:action];
        return Spin(20, ^BOOL { @synchronized (gPressed) { @synchronized (desk.calls) { return gPressed.count + desk.calls.count >= want; } } });
    };
    NSString *tree = [@"workforest:worktree:" stringByAppendingString:Dir(@"trees/fix-auth-redirect")];
    BOOL all = pick(@"minmacs:app:com.example.chat", @"quit", 1) && pick(@"minmacs:app:com.example.chat", @"force-quit", 2) &&
               pick(@"locohost:server:w1#dev", @"stop", 3) && pick(@"locohost:server:app#dev", @"force-stop", 4) &&
               pick(@"noonoo:clutter:derived-data", @"trash", 5);
    T(@"row menu: Quit, Force Quit, Stop, Force Stop and Move to Trash each run their own press, the second request for the alternates, by window",
      @"yes minmacs:app:com.example.chat quit term window | minmacs:app:com.example.chat quit kill window | locohost:server:w1#dev stop term window | "
      @"locohost:server:app#dev stop kill window | noonoo:clutter:derived-data trash term window",
      [NSString stringWithFormat:@"%@ %@", YN(all), pressed()]);

    // The desk's items read the finding's own value and keep no record.
    NSUInteger ran = gPressed.count;
    for (NSArray *x in @[@[@"minmacs:app:com.example.chat", @"show"], @[@"minmacs:app:com.example.chat", @"hide"], @[@"minmacs:app:com.example.chat", @"copy-pid"],
                         @[@"minmacs:app:com.example.chat", @"reveal"], @[@"locohost:server:w1#dev", @"open-url"], @[@"locohost:server:w1#dev", @"copy-url"],
                         @[@"minmacs:agent:claude-code:s-71010", @"copy-session"], @[tree, @"open-folder"], @[tree, @"terminal"], @[tree, @"copy-branch"]])
        pick(x[0], x[1], ran + desk.calls.count + 1);
    T(@"row menu: Show, Hide, Copy PID, Show in Finder, Open in Browser, Copy URL, Copy Session ID, Open in Finder, Open in Terminal and Copy Branch Name go to the desk",
      @"show 71020 | hide 71020 | copy 71020 | reveal Chat.app | url http://localhost:3000/ | copy http://localhost:3000/ | copy s-71010 | folder fix-auth-redirect | "
      @"terminal fix-auth-redirect | copy fix-auth-redirect", [desk.calls componentsJoinedByString:@" | "]);

    // MinMacs itself: nothing quits, hides or shows it, whatever asks.
    NSUInteger calls = desk.calls.count;
    [c windowRow:@"minmacs:app:no.guerrilla.minmacs" item:@"quit"];
    [c windowRow:@"minmacs:app:no.guerrilla.minmacs" item:@"hide"];
    Spin(1.5, ^BOOL { return NO; });
    T(@"row menu: a pick on MinMacs itself runs nothing", @"5 0", [NSString stringWithFormat:@"%lu %lu", (unsigned long)gPressed.count, (unsigned long)(desk.calls.count - calls)]);

    // Keep: MMKeep by window, and its row in the log's keep table.
    [c windowRow:@"minmacs:app:com.example.editor" item:@"keep"];
    BOOL keptNow = Spin(20, ^BOOL { __block NSDate *d = nil; dispatch_sync(MMQueue(@"windowtest", @"keep", QOS_CLASS_USER_INITIATED), ^{ d = [MMKeep keptUntil:@"com.example.editor" expert:@"minmacs"]; }); return d != nil; });
    __block NSString *keepBy = nil;
    Spin(20, ^BOOL {
        dispatch_sync(MMQueue(@"windowtest", @"keep", QOS_CLASS_USER_INITIATED), ^{
            for (MMLogEntry *e in [MMLog.shared rows:@[MMLogKeepTable] before:0 limit:20]) if ([e.body[@"key"] isEqual:@"com.example.editor"]) { keepBy = e.body[@"by"]; break; }
        });
        return keepBy != nil;
    });
    T(@"row menu: Keep keeps the app for 7 days, by window, with its row in the log", @"yes window", [NSString stringWithFormat:@"%@ %@", YN(keptNow), keepBy]);

    // The log shows the move at once, by you in the window, with its Undo.
    BOOL shown = Spin(20, ^BOOL {
        for (MMWindowLogEntry *e in models.lastObject.log.entries) if ([e.sentence containsString:@"DerivedData"] && e.canUndo) return YES;
        return NO;
    });
    MMWindowLogEntry *moved = nil, *quit = nil;
    for (MMWindowLogEntry *e in models.lastObject.log.entries) {
        if (!moved && [e.sentence containsString:@"DerivedData"]) moved = e;
        if (!quit && [e.sentence containsString:@"Chat"]) quit = e;
    }
    T(@"row menu: the move to the Trash shows in the log at once, by you in the window, with Undo", @"yes by you in the window yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN(shown), moved.who, YN(moved.canUndo && moved.undoRid.length)]);
    Info([NSString stringWithFormat:@"%@ / %@ / %@", moved.sentence, quit.sentence, quit.who]);

    // Wrap Up: the one plan Fix Everything runs, as one record by window.
    NSUInteger before = gPressed.count, parts = gRan.count;
    [c windowRow:tree item:@"wrap-up"];
    BOOL wrapped = Spin(30, ^BOOL {
        for (MMWindowLogEntry *e in models.lastObject.log.entries) if ([e.sentence hasPrefix:@"Wrapped up fix-auth-redirect"] && [e.who isEqualToString:@"by you in the window"]) return YES;
        return NO;
    });
    T(@"row menu: Wrap Up runs the worktree's plan by window, told in the log", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(wrapped), YN(gRan.count > parts && gPressed.count == before)]);
    [c setOpen:NO];
}
