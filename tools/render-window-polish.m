// The second look at the real menu window against 195-a, issue #62: more pictures and the checks that came with them.
// tools/render.m includes this file, so it is part of the render tool and uses its Check. It is not built on its own.

/// A row of every kind under the pointer, the pointer on Fix Everything, and a quiet day's story.
static NSArray<NSArray *> *WindowPolishShots(void) {
    return @[@[@"busy", @"agent", @"agent:4"], @[@"busy", @"asks", @"agent:0"], @[@"busy", @"app", @"app:7"], @[@"busy", @"cache", @"cache:0"],
             @[@"busy", @"fix", @""], @[@"calm", @"cache", @"cache:1"], @[@"young", @"server", @"server:6006"],
             // Settings with nobody asking, on a Mac with no lid, every rule Off: as the first live look met it.
             @[@"calm", @"settings", @""]];
}

@interface PolishHost : NSObject <MMWindowHost>
@property NSInteger stops, fixes;
@end
@implementation PolishHost
- (void)windowRunFixEverything { self.fixes++; }
- (void)windowStopRun { self.stops++; }
- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice {}
- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on {}
- (void)windowQuit {}
- (void)windowWelcomeStart:(BOOL)openAtLogin removal:(NSInteger)removal {}
@end

static MMWindowDockView *PolishDock(MMWindowView *v) {
    for (NSView *sub in WindowLists(v).firstObject.superview.subviews) if ([sub isKindOfClass:MMWindowDockView.class]) return (MMWindowDockView *)sub;
    return nil;
}

static MMWindowView *PolishView(NSString *fixture) {
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.model = MMWindowFixture(fixture);
    return v;
}

static void WindowPolishChecks(void) {
    const uint64_t MB = 1ull << 20, GB = 1ull << 30;
    // One rule for digits: a round size keeps its decimal beside the others, and a second one shows where it says more.
    NSString *sizes = [@[MMWindowBytes(1 * GB), MMWindowBytes(4 * GB), MMWindowBytes(6758 * MB), MMWindowBytes(1905 * MB), MMWindowBytes(1331 * MB), MMWindowBytes(14541 * MB),
                         MMWindowBytes(182 * GB), MMWindowBytes(905 * MB), MMWindowBytes(0), MMWindowBytes(10 * GB), MMWindowBytes(64 * GB), MMWindowWhole(64 * GB), MMWindowWhole(994 * GB)]
                       componentsJoinedByString:@" | "];
    Check([sizes isEqualToString:@"1.0 GB | 4.0 GB | 6.6 GB | 1.86 GB | 1.3 GB | 14.2 GB | 182 GB | 905 MB | 0 MB | 10.0 GB | 64.0 GB | 64 GB | 994 GB"],
          @"window sizes: one rule, so 1.0 GB stands beside 6.6 GB, with a second decimal only where it says more", sizes);
    Check(MMWindowCPU(0.04) == nil && MMWindowCPU(-1) == nil && [MMWindowCPU(0.3) isEqualToString:@"0.3"] && [MMWindowCPU(12.4) isEqualToString:@"12"],
          @"window sizes: CPU under 0.05 is not shown, and from 10 up it is whole", @"");

    // Nothing to fix: the dimmed button says it. No line claims it, on screen or to VoiceOver.
    NSMutableArray<NSString *> *claims = [NSMutableArray new];
    for (NSString *name in @[@"young", @"calm", @"empty", @"busy"])
        for (NSString *x in [MMWindowView shownStrings:MMWindowFixture(name)])
            for (NSString *no in @[@"Nothing to fix", @"nothing to fix", @"Nothing needs", @"is clean", @"is fine"]) if ([x containsString:no]) [claims addObject:x];
    MMWindowDockView *still = PolishDock(PolishView(@"young"));
    Check(claims.count == 0 && [still.fix.accessibilityLabel isEqualToString:@"Fix Everything, dimmed"] && !still.fix.enabled && still.stop.hidden,
          @"window dock: with nothing to fix the button is dimmed and no line says so", [NSString stringWithFormat:@"%@ %@", still.fix.accessibilityLabel, [claims componentsJoinedByString:@" | "]]);

    // No group ever ends on half a row, on any day, with the band or without.
    NSMutableArray<NSString *> *cut = [NSMutableArray new];
    for (NSString *name in @[@"quiet", @"busy", @"peak", @"young", @"calm", @"empty", @"long", @"running"]) {
        for (MMWindowListView *l in WindowLists(PolishView(name))) {
            CGFloat row = l.rowHeight, last = 0;
            if (row < 24 || row > 50) [cut addObject:[NSString stringWithFormat:@"%@ row %g", name, row]];
            NSArray<NSValue *> *frames = l.groupFrames;
            for (NSUInteger i = 0; i < frames.count; i++) {
                NSRect f = frames[i].rectValue;
                CGFloat box = f.size.height - 24;
                BOOL empty = l.groups[i].rows.count == 0;
                if (box < (empty ? 24 : row) || fmod(box, empty ? 24 : row) != 0 || f.origin.y < last || NSMaxY(f) > l.bounds.size.height) [cut addObject:[NSString stringWithFormat:@"%@ %@ %g", name, l.groups[i].key, box]];
                last = NSMaxY(f);
            }
        }
    }
    Check(cut.count == 0, @"window lists: every group is a whole number of rows high, inside its side, on every day", [cut componentsJoinedByString:@" | "]);

    // A side with room: taller rows with a second line, and its whole number at the foot. A full side has neither.
    NSArray<MMWindowListView *> *quiet = WindowLists(PolishView(@"quiet")), *busy = WindowLists(PolishView(@"busy")), *young = WindowLists(PolishView(@"young"));
    NSString *(^lines)(MMWindowListView *) = ^NSString *(MMWindowListView *l) {
        NSMutableArray *a = [NSMutableArray new];
        for (NSArray<NSString *> *x in l.sumLines) [a addObject:[x componentsJoinedByString:@": "]];
        return [a componentsJoinedByString:@" | "];
    };
    Check(quiet.count == 2 && quiet[1].rowHeight == 50 && quiet[1].showsSum && [lines(quiet[1]) isEqualToString:@"Free: 182 of 994 GB | By these holders: 28.4 GB | macOS and the rest: 784 GB"],
          @"window lists: a disk side with room has rows of two lines and closes with what the disk's whole number is", [NSString stringWithFormat:@"%g %@", quiet[1].rowHeight, lines(quiet[1])]);
    Check(busy[0].rowHeight == 24 && busy[1].rowHeight == 24 && !busy[0].showsSum && !busy[1].showsSum, @"window lists: a full side keeps one line a row and no closing lines", @"");
    Check(young[1].showsSum && [lines(young[1]) isEqualToString:@"Free: 612 of 994 GB | In use: 382 GB"] && !young[0].showsSum,
          @"window lists: a disk side with no rows still says its whole number, so the side is not bare", lines(young[1]));

    // A row's story opens with one line: asks, goes or stays. The facts under it do not say it twice.
    MMWindowModel *m = MMWindowFixture(@"busy");
    MMWindowRow *asks = [m row:@"agent:0"], *works = [m row:@"agent:4"], *goes = [m row:@"cache:0"], *stays = [m row:@"server:6006"];
    NSString *(^fate)(MMWindowRow *) = ^NSString *(MMWindowRow *r) { return [NSString stringWithFormat:@"%ld %@ %@", (long)r.fate.kind, r.fate.lead, r.fate.note]; };
    Check([fate(asks) isEqualToString:@"2 Asks you. It asked a question and has not moved since."] && [fate(works) isEqualToString:@"0 Working. Its session is active."] &&
          [fate(goes) isEqualToString:@"1 Goes with Fix Everything. 4 of its 7 projects are gone from this Mac."] && [fate(stays) isEqualToString:@"0 Stays. A browser tab and an agent use it."],
          @"window story: its first line says whether the row asks, works, goes or stays, and why", [@[fate(asks), fate(works), fate(goes), fate(stays)] componentsJoinedByString:@" | "]);
    BOOL twice = NO;
    for (MMWindowRow *r in @[asks, works, goes, stays]) for (MMWindowFact *f in r.storyFacts) if ([@[@"Why", @"Stays", @"State"] containsObject:f.label]) twice = YES;
    MMWindowRow *bare = [MMWindowRow new];
    bare.facts = @[[MMWindowFact label:@"Stays" value:@"in use"]];
    MMWindowRow *plain = [MMWindowRow new];
    plain.facts = @[[MMWindowFact label:@"Port" value:@"3000"]];
    Check(!twice && asks.storyFacts.count == asks.facts.count - 2 && stays.storyFacts.count == stays.facts.count - 1 && [fate(bare) isEqualToString:@"0 Stays. In use."] &&
          plain.fate == nil && plain.storyFacts.count == 1,
          @"window story: the facts under the line leave out what it said, a reason reads as a sentence, and a row with no reason has no line", fate(bare));

    // The pointed row reaches the dock, whose ring and numbers tell its share.
    MMWindowView *v = PolishView(@"busy");
    PolishHost *host = [PolishHost new];
    v.host = host;
    MMWindowDockView *dock = PolishDock(v);
    v.pointedRow = @"server:6006";
    BOOL pointed = [dock.pointed.key isEqualToString:@"server:6006"];
    v.pointedRow = nil;
    Check(pointed && dock.pointed == nil, @"window dock: the row under the pointer shows in the dock, and leaves it with the pointer", @"");

    // While a run plays, Stop sits under the button, and a press on it stops the run once. At rest it is not there.
    BOOL restHidden = dock.stop.hidden;
    [dock.stop performClick:nil];
    MMWindowView *r = PolishView(@"running");
    PolishHost *rhost = [PolishHost new];
    r.host = rhost;
    MMWindowDockView *rdock = PolishDock(r);
    NSRect at = rdock.stop.frame;
    [rdock.stop performClick:nil];
    Check(restHidden && host.stops == 0 && !rdock.stop.hidden && rhost.stops == 1 && rhost.fixes == 0 && NSMinY(at) > NSMaxY(rdock.fix.frame) && NSMaxY(at) <= rdock.bounds.size.height &&
          fabs(NSMidX(at) - NSMidX(rdock.fix.frame)) < 60 && [rdock.stop.accessibilityLabel isEqualToString:@"Stop after this step"],
          @"window dock: Stop shows under the button only while a run plays, and a press stops the run", [NSString stringWithFormat:@"%ld stops, %@", (long)rhost.stops, NSStringFromRect(at)]);
    [rdock.fix performClick:nil];
    Check(rhost.stops == 2 && rhost.fixes == 0, @"window dock: the large button stops the run too", @"");

    // Settings, from the live look: no title touches its explanation, no empty band stands over the title when nobody
    // asks, and the lid switch of a Mac with no lid is not available.
    MMWindowView *sv = PolishView(@"calm");
    PolishHost *shost = [PolishHost new];
    sv.host = shost;
    sv.showsSettings = YES;
    MMWindowSettingsView *panel = nil;
    for (NSView *sub in sv.subviews) if ([sub isKindOfClass:MMWindowSettingsView.class]) panel = (MMWindowSettingsView *)sub;
    CGFloat widest = 0, column = 1000;
    NSButton *lid = nil;
    for (NSView *sub in panel.subviews) {
        if (![sub isKindOfClass:NSButton.class] || ![sub respondsToSelector:NSSelectorFromString(@"explainX")]) continue;
        if ([[sub valueForKey:@"isSwitch"] boolValue]) { if (!lid) lid = (NSButton *)sub; continue; }
        widest = MAX(widest, MMWindowWidth(MMWindowText([sub valueForKey:@"label"], 13, NSFontWeightMedium, NSColor.whiteColor)));
        column = MIN(column, [[sub valueForKey:@"explainX"] doubleValue]);
    }
    Check(panel && widest > 30 && column >= 30 + widest + 8, @"window settings: every explanation starts past the widest title, with a gap",
          [NSString stringWithFormat:@"title %g, explanations at %g", widest, column]);
    MMWindowView *asked = PolishView(@"busy");
    asked.showsSettings = YES;
    CGFloat askedTop = 0;
    for (NSView *sub in asked.subviews) if ([sub isKindOfClass:MMWindowSettingsView.class]) askedTop = sub.frame.origin.y;
    Check(panel.frame.origin.y == 12 && askedTop == 40 && NSMaxY(panel.frame) == 702, @"window settings: with nobody asking, Settings starts at the top and no empty band stands over it",
          [NSString stringWithFormat:@"%g and %g", panel.frame.origin.y, askedTop]);
    [lid performClick:nil];
    Check(lid && !lid.enabled && [[lid valueForKey:@"inert"] boolValue] && [lid.accessibilityLabel hasSuffix:@"This Mac has no lid, so it changes nothing here."],
          @"window settings: on a Mac with no lid the lid switch is not available, takes no press and says why", lid.accessibilityLabel);

    // In a window that is ordered in, off screen: the glow around Fix Everything breathes only at rest with something
    // to fix, a new row gets its short light, and the turn to Settings ends with Settings in its place.
    BOOL motion = !MMWindowReduceMotion();
    MMWindowView *live = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    NSWindow *win = ShownWindow(live);
    live.model = MMWindowFixture(@"busy");
    [live opened];
    [live display];
    Spin(0.15);
    MMWindowDockView *ld = PolishDock(live);
    MMWindowListView *ll = WindowLists(live).firstObject;
    BOOL atRest = ld.breathes, firstFlash = ll.flashed > 0;
    [ld.fix setHover:YES];
    BOOL underPointer = ld.breathes;
    [ld.fix setHover:NO];
    BOOL again = ld.breathes;
    MMWindowModel *more = MMWindowFixture(@"busy");
    more.generation = 2;
    MMWindowRow *fresh = [MMWindowRow new];
    fresh.key = @"agent:new"; fresh.kind = MMWindowAgent; fresh.name = @"A new agent"; fresh.bytes = 3000 * MB;
    more.memoryGroups[1].rows = [@[fresh] arrayByAddingObjectsFromArray:more.memoryGroups[1].rows];
    live.model = more;
    NSInteger lit = ll.flashed;
    MMWindowModel *same = MMWindowFixture(@"busy");
    same.generation = 3;
    same.memoryGroups[1].rows = more.memoryGroups[1].rows;
    live.model = same;
    Check(atRest == motion && !underPointer && again == motion && !firstFlash && lit == 1 && ll.flashed == 0,
          @"window motion: the button's glow breathes at rest and not under the pointer, and only a row that is new gets the short light",
          [NSString stringWithFormat:@"rest %d, pointed %d, again %d, first %d, new %ld, same %ld", atRest, underPointer, again, firstFlash, (long)lit, (long)ll.flashed]);
    live.showsSettings = YES;
    NSView *pane = nil;
    for (NSView *sub in live.subviews) if ([sub isKindOfClass:MMWindowSettingsView.class]) pane = sub;
    BOOL held = !MMWindowTakesPresses(pane.subviews.firstObject) || !motion;
    Spin(0.55);
    Check(held && pane.frame.origin.y == 40 && pane.alphaValue == 1 && !pane.hidden && MMWindowTakesPresses(pane.subviews.firstObject) && !ld.breathes,
          @"window motion: the turn to Settings holds presses while Settings rises, and ends with it in its place and the menu's glow still",
          [NSString stringWithFormat:@"held %d, y %g, alpha %g, breathes %d", held, pane.frame.origin.y, pane.alphaValue, ld.breathes]);
    live.showsSettings = NO;
    Spin(0.55);
    MMWindowModel *none = MMWindowFixture(@"young");
    none.generation = 4;
    live.model = none;
    BOOL dimmedStill = !ld.breathes;
    [win orderOut:nil]; [live rest];
    Check(dimmedStill && !ld.breathes, @"window motion: a dimmed button does not breathe, and nothing does once the window closed", @"");
    [win close];
}
