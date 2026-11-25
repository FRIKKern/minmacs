// Ask MinMacs in the menu window's middle, slice 4 of the center, tier 0: the field empty and being typed in, an
// answer with entries, one with its action button, one whose button was pressed, the plan and the honest fallback.
// tools/render.m includes this file after render-window-pulls.m and uses its Check, PolishHost, PolishView,
// WordViews and LogDraw. It is not built on its own.

/// fixture, state, the row the pointer rests on.
static NSArray<NSArray *> *WindowAskShots(void) {
    return @[@[@"ask-empty", @"main", @""], @[@"ask-typing", @"typing", @""], @[@"ask-why", @"main", @""], @[@"ask-keep", @"main", @""],
             @[@"ask-undo", @"main", @""], @[@"ask-undone", @"main", @""], @[@"ask-plan", @"main", @""], @[@"ask-fallback", @"main", @""],
             @[@"ask-asking", @"main", @""], @[@"ask-claude", @"main", @""], @[@"ask-unreachable", @"main", @""]];
}

static MMWindowMiddleView *AskMiddle(MMWindowView *v) { return WordViews(v, MMWindowMiddleView.class).firstObject; }

static void AskShotState(MMWindowView *v, NSString *state) {
    if ([state isEqualToString:@"typing"]) AskMiddle(v).askBar.field.stringValue = @"why did you stop 43";
}

/// A host that counts what the answer's presses ask for. Nothing it is told acts.
@interface AskHost : PolishHost
@property NSInteger asks, backs, keeps, askStops;
@property (copy) NSString *lastAsk, *lastKeep, *lastRow;
@end
@implementation AskHost
- (void)windowAsk:(NSString *)question row:(NSString *)rowKey { self.asks++; self.lastAsk = question; self.lastRow = rowKey; }
- (void)windowAskBack { self.backs++; }
- (void)windowKeep:(NSString *)rowKey { self.keeps++; self.lastKeep = rowKey; }
- (void)windowAskStop { self.askStops++; }
@end

/// The views of the middle in the order Tab reaches them, from the first that can take the keyboard.
static NSArray<NSView *> *AskKeyOrder(NSView *from, NSInteger most) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSView *k = from; k && out.count < (NSUInteger)most; k = k.nextValidKeyView) { if ([out containsObject:k]) break; [out addObject:k]; }
    return out;
}

static void WindowAskChecks(void) {
    // Every string of every answer, in both looks: no ellipsis, none past its box, none leaves its view.
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    __block NSMutableArray<NSString *> *seen = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        [seen addObject:text];
        NSString *fault = nil;
        if ([text containsString:@"…"] || [text containsString:@"..."]) fault = @"ellipsis";
        else if (!NSIsEmptyRect(allowed) && (NSWidth(used) > NSWidth(allowed) + 1 || NSMaxY(used) > NSMaxY(allowed) + 1)) fault = @"past its box";
        else if (!NSIsEmptyRect(bounds) && (NSMinX(used) < NSMinX(bounds) - 1 || NSMaxX(used) > NSMaxX(bounds) + 1 || NSMinY(used) < NSMinY(bounds) - 1 || NSMaxY(used) > NSMaxY(bounds) + 1)) fault = @"past its view";
        if (fault && faults.count < 10) [faults addObject:[NSString stringWithFormat:@"%@: %@", fault, text]];
    });
    NSArray<NSString *> *names = @[@"ask-why", @"ask-keep", @"ask-undo", @"ask-undone", @"ask-plan", @"ask-fallback", @"ask-asking", @"ask-claude", @"ask-unreachable"];
    NSInteger drawn = 0;
    for (NSNumber *contrast in @[@NO, @YES]) {
        MMWindowForceContrast(contrast.boolValue);
        for (NSString *name in names) { LogDraw(PolishView(name)); drawn++; }
    }
    MMWindowForceContrast(NO);
    Check(faults.count == 0 && drawn == 18, @"window ask: in every answer, in both looks, no drawn string holds an ellipsis, none is past its box and none leaves its view",
          [faults componentsJoinedByString:@" | "]);
    NSArray<NSString *> *banned = @[@"LocoHost", @"WorkForest", @"Noo-Noo", @"NooNoo", @"Insomnia", @"for good", @"forever", @"permanently", @"is clean", @"all clean", @"(", @")", @"!"];
    NSMutableArray *bad = [NSMutableArray new];
    for (NSString *name in names) for (NSString *s in [MMWindowView shownStrings:MMWindowFixture(name)])
        for (NSString *b in banned) if ([s rangeOfString:b options:NSCaseInsensitiveSearch].location != NSNotFound) [bad addObject:s];
    Check(bad.count == 0, @"window ask: no answer holds a banned phrase, an old app name, an aside or an exclamation mark", [bad componentsJoinedByString:@" | "]);

    // The field empty: it stands at the foot of the middle, over the dock, with its placeholder, and the log shows.
    MMWindowView *empty = PolishView(@"ask-empty");
    MMWindowMiddleView *mid = AskMiddle(empty);
    NSRect bar = mid.askBar.frame;
    Check(!mid.askBar.hidden && [mid.askBar.field.placeholderAttributedString.string isEqualToString:@"Ask MinMacs"] && NSMaxY(bar) == mid.bounds.size.height
          && NSMaxY(mid.logView.frame) <= NSMinY(bar) && !mid.logView.hidden && mid.answerView.hidden && [mid.askBar.field.accessibilityLabel isEqualToString:@"Ask MinMacs"],
          @"window ask: the field Ask MinMacs stands at the foot of the middle, under the log, which shows while no answer does", NSStringFromRect(bar));
    // A pointed row's story stands over the middle but the field, which stays where it is.
    empty.pointedRow = @"server:6006";
    Check(!mid.askBar.hidden && mid.logView.hidden && NSEqualRects(mid.askBar.frame, bar), @"window ask: a row's story replaces the log, and the field stays", @"");
    empty.pointedRow = nil;

    // An answer with entries: in the log's place, with Back to the log, each entry a press to its row or its log entry.
    AskHost *host = [AskHost new];
    MMWindowView *why = PolishView(@"ask-why");
    why.host = host;
    MMWindowMiddleView *wm = AskMiddle(why);
    MMWindowAnswerView *av = wm.answerView;
    LogDraw(why);
    NSInteger entryPresses = 0;
    for (MMWindowButton *b in av.presses) if (b.kind == MMWindowButtonClear) entryPresses++;
    Check(!av.hidden && wm.logView.hidden && av.backButton && [av.backButton.title isEqualToString:@"Back to the log"] && entryPresses == 2 && av.drawnLines.count == 3
          && [av.drawnLines.firstObject hasPrefix:@"The log holds 2 actions"] && !av.suggestButton,
          @"window ask: an answer stands in the log's place with Back to the log, and each of its entries is a press", [av.drawnLines componentsJoinedByString:@" | "]);
    MMWindowButton *toRow = nil, *toLog = nil;
    for (MMWindowButton *b in av.presses) if (b.kind == MMWindowButtonClear) { if (!toRow) toRow = b; else toLog = b; }
    [toRow performClick:nil];
    Check([why.activeRow isEqualToString:@"server:4321"] && av.hidden, @"window ask: a press on an entry that names a row makes it the active row, and its story shows", why.activeRow ?: @"none");
    [why escape];
    Check(!why.activeRow && !av.hidden, @"window ask: Escape lets go of the row first, and the answer is back", @"");
    toLog = nil;
    for (MMWindowButton *b in av.presses) if (b.kind == MMWindowButtonClear && b.tag == 1) toLog = b;
    [toLog performClick:nil];
    Check(av.hidden && !wm.logView.hidden && host.backs == 1, @"window ask: a press on an entry of the log puts the answer away and shows the log", @(host.backs).stringValue);
    MMWindowView *why2 = PolishView(@"ask-why");
    why2.host = host;
    [why2 escape];
    Check(AskMiddle(why2).answerView.hidden && host.backs == 2, @"window ask: Escape over an answer puts it away, before it would close the window", @(host.backs).stringValue);
    MMWindowView *why3 = PolishView(@"ask-why");
    why3.host = host;
    [AskMiddle(why3).answerView.backButton performClick:nil];
    Check(AskMiddle(why3).answerView.hidden && !AskMiddle(why3).logView.hidden && host.backs == 3, @"window ask: Back to the log shows the log again", @"");

    // The action button: the one that exists already, and nothing acts until it is pressed.
    for (NSArray *t in @[@[@"ask-keep", @"Keep for 7 days", @"worktree:fix-auth-redirect"], @[@"ask-undo", @"Undo", @"rid-0"]]) {
        AskHost *h = [AskHost new];
        MMWindowView *v = PolishView(t[0]);
        v.host = h;
        MMWindowAnswerView *a = AskMiddle(v).answerView;
        LogDraw(v);
        MMWindowButton *s = a.suggestButton;
        BOOL before = h.keeps == 0 && h.undos == 0;
        [s performClick:nil];
        BOOL pressed = [t[0] isEqualToString:@"ask-keep"] ? (h.keeps == 1 && [h.lastKeep isEqualToString:t[2]] && h.undos == 0) : (h.undos == 1 && [h.lastUndo isEqualToString:t[2]] && h.keeps == 0);
        Check(s && [s.title isEqualToString:t[1]] && s.toolTip.length && before && pressed && NSContainsRect(a.bounds, s.frame),
              [NSString stringWithFormat:@"window ask: %@ shows the button %@, nothing acts before it is pressed, and its press goes to the host once", t[0], t[1]],
              [NSString stringWithFormat:@"%@ %ld keeps %ld undos", s.title, (long)h.keeps, (long)h.undos]);
    }
    MMWindowView *undone = PolishView(@"ask-undone");
    MMWindowAnswerView *ua = AskMiddle(undone).answerView;
    [seen removeAllObjects];
    LogDraw(undone);
    Check(!ua.suggestButton && [seen containsObject:@"Taking it back."], @"window ask: once pressed, the button gives way to a line that says what happens", @"");

    // The fallback: the honest sentence, and three questions it can answer, each a press that asks it.
    AskHost *fh = [AskHost new];
    MMWindowView *fb = PolishView(@"ask-fallback");
    fb.host = fh;
    MMWindowAnswerView *fa = AskMiddle(fb).answerView;
    [seen removeAllObjects];
    LogDraw(fb);
    NSMutableArray<MMWindowButton *> *examples = [NSMutableArray new];
    for (MMWindowButton *b in fa.presses) if ([b.accessibilityLabel hasPrefix:@"Ask: "]) [examples addObject:b];
    [examples.firstObject performClick:nil];
    Check([seen containsObject:@"I can't answer that without the model yet."] && examples.count == 3 && fh.asks == 1 && [fh.lastAsk isEqualToString:@"Why did you stop :4321 Astro?"],
          @"window ask: the fallback says it cannot answer without the model, and offers three questions, each a press that asks it", [NSString stringWithFormat:@"%lu examples, %@", (unsigned long)examples.count, fh.lastAsk]);

    // Tier 1: Asking Claude with Stop, whose press goes to the host and acts on nothing; Claude's answer with its quiet
    // line and the rules' own Keep; and Claude out of reach, said so, with the rules' examples.
    AskHost *sh = [AskHost new];
    MMWindowView *asking = PolishView(@"ask-asking");
    asking.host = sh;
    MMWindowAnswerView *sa = AskMiddle(asking).answerView;
    [seen removeAllObjects];
    LogDraw(asking);
    MMWindowButton *stopButton = sa.suggestButton;
    [stopButton performClick:nil];
    Check([seen containsObject:@"Asking Claude"] && [stopButton.title isEqualToString:@"Stop"] && sh.askStops == 1 && sh.keeps == 0 && sh.undos == 0 && sh.asks == 0,
          @"window ask: while Claude is asked the answer says Asking Claude, with Stop, whose press goes to the host once and acts on nothing",
          [NSString stringWithFormat:@"%@ %ld stops", stopButton.title, (long)sh.askStops]);
    AskHost *ch = [AskHost new];
    MMWindowView *claude = PolishView(@"ask-claude");
    claude.host = ch;
    MMWindowAnswerView *ca = AskMiddle(claude).answerView;
    [seen removeAllObjects];
    LogDraw(claude);
    BOOL beforePress = ch.keeps == 0;
    [ca.suggestButton performClick:nil];
    Check([seen containsObject:@"Answered by Claude · 1,240 tokens"] && [ca.suggestButton.title isEqualToString:@"Keep for 4 hours"] && beforePress && ch.keeps == 1
          && [ch.lastKeep isEqualToString:@"server:6006"] && NSContainsRect(ca.bounds, ca.suggestButton.frame),
          @"window ask: Claude's answer stands in the middle with Answered by Claude and its tokens, and its suggestion is the rules' Keep, which acts only on its press",
          [NSString stringWithFormat:@"%@ %ld keeps", ca.suggestButton.title, (long)ch.keeps]);
    MMWindowView *gone = PolishView(@"ask-unreachable");
    MMWindowAnswerView *ga = AskMiddle(gone).answerView;
    [seen removeAllObjects];
    LogDraw(gone);
    NSInteger gex = 0;
    for (MMWindowButton *b in ga.presses) if ([b.accessibilityLabel hasPrefix:@"Ask: "]) gex++;
    BOOL saidWhy = NO;
    for (NSString *x in seen) if ([x hasPrefix:@"Claude isn't reachable: "]) saidWhy = YES;
    Check(saidWhy && gex == 3 && !ga.suggestButton, @"window ask: Claude out of reach says so and why, with the rules' three questions, and no button", @(gex).stringValue);

    // The field: Return asks with the row whose story shows, Escape clears it first and then does the window's Escape.
    AskHost *kh = [AskHost new];
    MMWindowView *typed = PolishView(@"ask-empty");
    typed.host = kh;
    MMWindowAskBar *ab = AskMiddle(typed).askBar;
    id<NSTextFieldDelegate> d = ab.field.delegate;
    ab.field.stringValue = @"  what is :6006  ";
    typed.activeRow = @"server:6006";
    [d control:ab.field textView:[NSTextView new] doCommandBySelector:@selector(insertNewline:)];
    BOOL asked = kh.asks == 1 && [kh.lastAsk isEqualToString:@"what is :6006"] && [kh.lastRow isEqualToString:@"server:6006"] && ab.field.stringValue.length == 0;
    [d control:ab.field textView:[NSTextView new] doCommandBySelector:@selector(insertNewline:)];
    ab.field.stringValue = @"keep";
    [d control:ab.field textView:[NSTextView new] doCommandBySelector:@selector(cancelOperation:)];
    BOOL cleared = ab.field.stringValue.length == 0 && [typed.activeRow isEqualToString:@"server:6006"];
    [d control:ab.field textView:[NSTextView new] doCommandBySelector:@selector(cancelOperation:)];
    Check(asked && kh.asks == 1 && cleared && typed.activeRow == nil, @"window ask: Return asks once with the row whose story shows; an empty field asks nothing; Escape clears the field, then lets go of the row",
          [NSString stringWithFormat:@"%ld asks, %@, row %@", (long)kh.asks, kh.lastAsk, typed.activeRow]);

    // A new answer that names a row makes it the active one, so its story shows; the same answer again does not.
    MMWindowModel *m = MMWindowFixture(@"ask-empty");
    MMWindowAnswer *about = [MMWindowAnswer new];
    about.serial = 7; about.kind = @"about"; about.question = @"what is :6006"; about.answer = @":6006 Storybook, in servers."; about.row = @"server:6006";
    m.answer = about;
    MMWindowView *ab2 = PolishView(@"ask-empty");
    ab2.model = m;
    BOOL made = [ab2.activeRow isEqualToString:@"server:6006"];
    ab2.activeRow = nil;
    ab2.model = m;
    Check(made && ab2.activeRow == nil && !AskMiddle(ab2).answerView.hidden, @"window ask: what is :6006 makes that row active once, and the answer shows once it is let go", @"");

    // An answer is no row's story: a new one lets go of the active row and shows, a row the pointer rests on peeks
    // over it, and when the pointer leaves the answer is back, not the row.
    MMWindowView *act = PolishView(@"ask-empty");
    act.activeRow = @"server:6006";
    act.model = MMWindowFixture(@"ask-why");
    BOOL shows = act.activeRow == nil && !AskMiddle(act).answerView.hidden;
    act.pointedRow = @"server:3001";
    BOOL peeks = AskMiddle(act).answerView.hidden;
    act.pointedRow = nil;
    Check(shows && peeks && !AskMiddle(act).answerView.hidden && act.activeRow == nil,
          @"window ask: a new answer lets go of the active row and shows, a pointed row peeks over it, and the answer comes back after", @"");

    // The keyboard: Tab reaches the field after the answer's presses and before the dock's Fix Everything.
    MMWindowView *kv = PolishView(@"ask-keep");
    NSWindow *win = [[NSWindow alloc] initWithContentRect:kv.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    win.releasedWhenClosed = NO;
    win.contentView = kv;
    [win recalculateKeyViewLoop];
    MMWindowAnswerView *ka = AskMiddle(kv).answerView;
    NSTextField *field = AskMiddle(kv).askBar.field;
    NSArray<NSView *> *order = AskKeyOrder(ka.backButton, 60);
    NSUInteger back = [order indexOfObject:ka.backButton], keep = [order indexOfObject:ka.suggestButton], at = [order indexOfObject:field];
    NSUInteger fix = NSNotFound;
    for (NSUInteger i = 0; i < order.count; i++) if ([order[i] isKindOfClass:MMWindowButton.class] && [[(MMWindowButton *)order[i] title] hasPrefix:@"Fix Everything"]) { fix = i; break; }
    if (fix == NSNotFound) for (NSUInteger i = 0; i < order.count; i++) if ([order[i] isDescendantOf:PolishDock(kv)]) { fix = i; break; }
    Check(field.canBecomeKeyView && back == 0 && keep != NSNotFound && keep > back && at != NSNotFound && at > keep && fix != NSNotFound && fix > at,
          @"window ask: Tab goes from Back to the log to the answer's button and its entries, then to the field, then to the dock",
          [NSString stringWithFormat:@"back %lu keep %lu field %lu dock %lu of %lu", (unsigned long)back, (unsigned long)keep, (unsigned long)at, (unsigned long)fix, (unsigned long)order.count]);
    [win close];
    MMWindowWatchDraws(nil);
}
