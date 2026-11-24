// The second and third look at the real menu window against 195-a, issue #62: more pictures and the checks that came
// with them. tools/render.m includes this file after render-window-look.m and render-window-shown.m, and uses their
// Check, WindowLists, ShownWindow and Spin. It is not built on its own. render-window-words.m holds the checks of
// what is drawn: no ellipsis, nothing cut, and the feed's own vocabulary.

/// A row of every kind under the pointer, the pointer on Fix Everything, Settings on a first day, a day shaped as
/// the real feed makes it, and the day of extremes.
static NSArray<NSArray *> *WindowPolishShots(void) {
    return @[@[@"busy", @"agent", @"agent:4"], @[@"busy", @"asks", @"agent:0"], @[@"busy", @"app", @"app:7"], @[@"busy", @"cache", @"cache:0"],
             @[@"busy", @"fix", @""], @[@"calm", @"cache", @"cache:1"], @[@"young", @"server", @"server:6006"],
             // Settings with nobody asking, on a Mac with no lid, every rule still watching and no removal choice made.
             @[@"calm", @"settings", @""],
             @[@"real", @"main", @""], @[@"real", @"agent", @"agent:0"], @[@"real", @"server", @"server:56784"], @[@"real", @"fix", @""],
             @[@"extreme", @"main", @""], @[@"extreme", @"server", @"server:3000"], @[@"extreme", @"asks", @"agent:0"], @[@"extreme", @"tree", @"worktree:0"],
             @[@"extreme-running", @"main", @""], @[@"extreme-done", @"main", @""],
             // One worktree measured and the others not yet: the list, a row not measured, the measured one, and Fix Everything.
             @[@"measuring", @"main", @""], @[@"measuring", @"worktree", @"worktree:fix-auth-redirect"], @[@"measuring", @"measured", @"worktree:dogfood"],
             @[@"measuring", @"fix", @""]];
}

@interface PolishHost : NSObject <MMWindowHost>
@property NSInteger stops, fixes, rules, switches, lastPicked;
@property (copy) NSString *lastRule;
@end
@implementation PolishHost
- (void)windowRunFixEverything { self.fixes++; }
- (void)windowStopRun { self.stops++; }
- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice { self.rules++; self.lastRule = ruleID; self.lastPicked = choice; }
- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on { self.switches++; }
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

static MMWindowSettingsView *PolishSettings(MMWindowView *v) {
    for (NSView *sub in v.subviews) if ([sub isKindOfClass:MMWindowSettingsView.class]) return (MMWindowSettingsView *)sub;
    return nil;
}

#include "render-window-words.m"
#include "render-window-row.m"
#include "render-window-measuring.m"

static void WindowPolishChecks(void) {
    const uint64_t MB = 1ull << 20, GB = 1ull << 30, DMB = 1000000ull, DGB = 1000000000ull;
    // One rule for digits: a round size keeps its decimal beside the others, and a second one shows where it says more.
    NSString *sizes = [@[MMWindowBytes(1 * GB, NO), MMWindowBytes(4 * GB, NO), MMWindowBytes(6758 * MB, NO), MMWindowBytes(1905 * MB, NO), MMWindowBytes(1331 * MB, NO),
                         MMWindowBytes(14541 * MB, NO), MMWindowBytes(182 * GB, NO), MMWindowBytes(905 * MB, NO), MMWindowBytes(0, NO), MMWindowBytes(10 * GB, NO),
                         MMWindowBytes(64 * GB, NO), MMWindowWhole(64 * GB, NO)] componentsJoinedByString:@" | "];
    Check([sizes isEqualToString:@"1.0 GB | 4.0 GB | 6.6 GB | 1.86 GB | 1.3 GB | 14.2 GB | 182 GB | 905 MB | 0 MB | 10.0 GB | 64.0 GB | 64 GB"],
          @"window sizes: one rule, so 1.0 GB stands beside 6.6 GB, with a second decimal only where it says more", sizes);
    // The edges of the units, and a disk in thousands as the Finder counts: this Mac's 245 GB disk is 245, not 228.
    NSString *edges = [@[MMWindowBytes(999 * MB, NO), MMWindowBytes(1023 * MB, NO), MMWindowBytes((uint64_t)(9.96 * GB), NO), MMWindowBytes((uint64_t)(99.9 * GB), NO),
                         MMWindowBytes((uint64_t)(999.4 * GB), NO), MMWindowBytes((uint64_t)(1023.6 * GB), NO), MMWindowBytes(1024 * GB, NO), MMWindowBytes(300, NO),
                         MMWindowWhole(245107195904ull, YES), MMWindowBytes(38651658240ull, YES), MMWindowBytes(999 * DMB, YES), MMWindowBytes(1000 * DMB, YES),
                         MMWindowBytes(4000 * DGB, YES), MMWindowWhole(994 * DGB, YES)] componentsJoinedByString:@" | "];
    Check([edges isEqualToString:@"999 MB | 1023 MB | 9.96 GB | 99.9 GB | 999 GB | 1.0 TB | 1.0 TB | 1 KB | 245 GB | 38.7 GB | 999 MB | 1.0 GB | 4.0 TB | 994 GB"],
          @"window sizes: the units' edges hold, 1023.6 GB reads 1.0 TB, and a disk counts in thousands as the Finder does", edges);
    Check(MMWindowCPU(0.04) == nil && MMWindowCPU(-1) == nil && [MMWindowCPU(0.3) isEqualToString:@"0.3"] && [MMWindowCPU(12.4) isEqualToString:@"12"],
          @"window sizes: CPU under 0.05 is not shown, and from 10 up it is whole", @"");
    // One disk, one size: the graph's line and "This disk" name the same whole.
    MMWindowModel *busyModel = MMWindowFixture(@"busy");
    MMWindowListView *diskSide = WindowLists(PolishView(@"busy")).lastObject;
    diskSide.frame = NSMakeRect(0, 0, 320, 2000);
    Check([busyModel.diskHour.explain containsString:@"the 994 GB disk"] && [diskSide.sumLines.firstObject.lastObject hasSuffix:@"of 994 GB"],
          @"window sizes: the disk has one size, in the graph's line and in This disk", [NSString stringWithFormat:@"%@ / %@", busyModel.diskHour.explain, diskSide.sumLines.firstObject.lastObject]);

    // Nothing to fix: the button rests, calm, takes no press and says only what a press does: no fixes to run. No
    // line claims the Mac is clean, on screen or to VoiceOver, and no gain is made up.
    NSMutableArray<NSString *> *claims = [NSMutableArray new];
    for (NSString *name in @[@"young", @"calm", @"empty", @"busy"])
        for (NSString *x in [MMWindowView shownStrings:MMWindowFixture(name)])
            for (NSString *no in @[@"Nothing to fix", @"nothing to fix", @"Nothing needs", @"is clean", @"is fine"]) if ([x containsString:no]) [claims addObject:x];
    MMWindowDockView *still = PolishDock(PolishView(@"young"));
    Check(claims.count == 0 && [still.fix.accessibilityLabel isEqualToString:@"Fix Everything, no fixes to run"] && [still.buttonWords isEqualToString:@"No fixes to run"] &&
          !still.fix.enabled && still.stop.hidden && still.gainLines.count == 0,
          @"window dock: with nothing to fix the button rests calm, takes no press and says only that no fix waits to run", [NSString stringWithFormat:@"%@ / %@ %@", still.fix.accessibilityLabel, still.buttonWords, [claims componentsJoinedByString:@" | "]]);

    // No group ever ends on half a row, on any day, with the band or without, also where a name wraps and its row is taller.
    NSMutableArray<NSString *> *cut = [NSMutableArray new];
    for (NSString *name in WordFixtures()) {
        for (MMWindowListView *l in WindowLists(PolishView(name))) {
            CGFloat row = l.rowHeight, last = 0;
            if (row < 24 || row > 50) [cut addObject:[NSString stringWithFormat:@"%@ row %g", name, row]];
            NSArray<NSValue *> *frames = l.groupFrames;
            for (NSUInteger i = 0; i < frames.count; i++) {
                NSRect f = frames[i].rectValue;
                CGFloat box = f.size.height - 24;
                BOOL empty = l.groups[i].rows.count == 0, whole = empty ? box == 24 : [l.rowTops[i] containsObject:@(box)] && box > 0;
                if (!whole || f.origin.y < last || NSMaxY(f) > l.bounds.size.height) [cut addObject:[NSString stringWithFormat:@"%@ %@ %g", name, l.groups[i].key, box]];
                last = NSMaxY(f);
            }
        }
    }
    Check(cut.count == 0, @"window lists: every group ends on a whole row, inside its side, on every day", [cut componentsJoinedByString:@" | "]);

    // A side with room stays compact: one line a row, and what it holds in all right under its rows. A full side has no
    // closing lines.
    // What the rows hold is never summed: one row can hold another.
    NSArray<MMWindowListView *> *quiet = WindowLists(PolishView(@"quiet")), *busy = WindowLists(PolishView(@"busy")), *young = WindowLists(PolishView(@"young")),
                                *real = WindowLists(PolishView(@"real"));
    NSString *(^lines)(MMWindowListView *) = ^NSString *(MMWindowListView *l) {
        NSMutableArray *a = [NSMutableArray new];
        for (NSArray<NSString *> *x in l.sumLines) [a addObject:[x componentsJoinedByString:@": "]];
        return [a componentsJoinedByString:@" | "];
    };
    Check(quiet.count == 2 && quiet[1].rowHeight == 24 && quiet[1].showsSum && [lines(quiet[1]) isEqualToString:@"Free: 182 of 994 GB | In use: 812 GB"],
          @"window lists: a disk side with room keeps one line a row and closes with what the disk holds in all", [NSString stringWithFormat:@"%g %@", quiet[1].rowHeight, lines(quiet[1])]);
    Check(busy[0].rowHeight == 24 && busy[1].rowHeight == 24 && !busy[0].showsSum && !busy[1].showsSum, @"window lists: a full side keeps one line a row and no closing lines", @"");
    Check(young[1].showsSum && [lines(young[1]) isEqualToString:@"Free: 612 of 994 GB | In use: 382 GB"] && !young[0].showsSum,
          @"window lists: a disk side with no rows still says what the disk holds, so the side is not bare", lines(young[1]));
    uint64_t rowsHold = 0, inUse = MMWindowFixture(@"real").ring.memoryUsed;
    for (MMWindowGroup *g in MMWindowFixture(@"real").memoryGroups) for (MMWindowRow *r in g.rows) rowsHold += r.bytes;
    real[0].frame = NSMakeRect(0, 0, 320, 2400);
    Check(rowsHold > inUse && [lines(real[0]) isEqualToString:@"In use: 13.0 of 16 GB"] && [lines(real[1]) isEqualToString:@"Free: 38.7 of 245 GB | In use: 206 GB"],
          @"window lists: rows that hold one another are never summed: the memory side says only what is in use, the disk side what is free and in use",
          [NSString stringWithFormat:@"%@ / %@", lines(real[0]), lines(real[1])]);

    // A row's story opens with one line: asks, works, goes or stays. Its sentence is the fact written for a person,
    // never an agent's raw Why, and the facts under it do not say it twice.
    MMWindowModel *m = MMWindowFixture(@"busy");
    MMWindowRow *asks = [m row:@"agent:0"], *works = [m row:@"agent:4"], *goes = [m row:@"cache:0"], *stays = [m row:@"server:4000"], *plainServer = [m row:@"server:6006"];
    NSString *(^fate)(MMWindowRow *) = ^NSString *(MMWindowRow *r) { return [NSString stringWithFormat:@"%ld %@ %@", (long)r.fate.kind, r.fate.lead, r.fate.note]; };
    Check([fate(asks) isEqualToString:@"2 Asks you. (null)"] && [fate(works) isEqualToString:@"0 Working. (null)"] &&
          [fate(goes) isEqualToString:@"1 Goes with Fix Everything. (null)"] && [fate(stays) isEqualToString:@"0 Stays. You asked to keep it."] && plainServer.fate == nil,
          @"window story: its first line says whether the row asks, works, goes or stays, with the reason only where one was written for a person",
          [@[fate(asks), fate(works), fate(goes), fate(stays)] componentsJoinedByString:@" | "]);
    BOOL raw = NO, twice = NO;
    for (NSString *name in WordFixtures()) {
        MMWindowModel *x = MMWindowFixture(name);
        for (NSArray<MMWindowGroup *> *side in @[x.memoryGroups, x.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) {
            for (MMWindowFact *f in r.facts) if ([f.label isEqualToString:@"Why"]) raw = YES;
            for (MMWindowFact *f in r.storyFacts) if ([f.label isEqualToString:@"Stays"] && r.fate.note.length) twice = YES;
        }
    }
    MMWindowRow *bare = [MMWindowRow new];
    bare.facts = @[[MMWindowFact label:@"Stays" value:@"in use"]];
    MMWindowRow *plain = [MMWindowRow new];
    plain.facts = @[[MMWindowFact label:@"Port" value:@"3000"]];
    Check(!raw && !twice && asks.storyFacts.count == asks.facts.count - 1 && stays.storyFacts.count == stays.facts.count - 1 &&
          [fate(bare) isEqualToString:@"0 Stays. In use."] && plain.fate == nil && plain.storyFacts.count == 1,
          @"window story: no made-up row carries an agent's raw Why, the line's sentence is never one, and a row with no reason has no line", fate(bare));

    // The pointed row reaches the dock, whose ring and numbers tell its share.
    MMWindowView *v = PolishView(@"busy");
    PolishHost *host = [PolishHost new];
    v.host = host;
    MMWindowDockView *dock = PolishDock(v);
    NSString *atRest = [dock.macLines componentsJoinedByString:@" | "];
    v.pointedRow = @"server:6006";
    BOOL pointed = [dock.pointed.key isEqualToString:@"server:6006"];
    NSString *onRow = [dock.macLines componentsJoinedByString:@" | "];
    v.pointedRow = nil;
    Check(pointed && dock.pointed == nil && [atRest isEqualToString:@"42.4 / 64 GB | memory in use | 182 GB disk free"] &&
          [onRow isEqualToString:@":6006 Storybook | 520 MB | of 42.4 GB memory in use | CPU 0.3 %"],
          @"window dock: the row under the pointer shows in the dock with its own numbers, and leaves it with the pointer", [NSString stringWithFormat:@"%@ / %@", atRest, onRow]);

    // The Mac after Fix Everything: what is in use now less what the fixes that need nobody give back, what is free
    // now plus what they free, each side on its own. A fix that waits for its own press counts on neither side, and
    // the ring leaves out exactly the rows a press acts on.
    MMWindowModel *after = MMWindowFixture(@"busy");
    MMWindowFix *own = [MMWindowFix new], *press = [MMWindowFix new];
    own.key = @"clean:own"; own.title = @"Clean npm cache"; own.diskBack = 14 * DGB; own.memoryBack = 3 * GB; own.needsYou = YES;
    press.key = @"stop:idle"; press.title = @"Stop 1 idle server"; press.memoryBack = 800 * MB; press.diskBack = 2 * DGB;
    after.fixes = @[own, press];
    MMWindowView *av = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    av.model = after;
    av.pointsAtFix = YES;
    NSString *then = [PolishDock(av).macLines componentsJoinedByString:@" | "];
    NSMutableSet<NSString *> *all = [NSMutableSet setWithArray:MMWindowRingRows(after, NO)], *left = [NSMutableSet setWithArray:MMWindowRingRows(after, YES)], *marked = [NSMutableSet new];
    for (NSArray<MMWindowGroup *> *side in @[after.memoryGroups, after.diskGroups]) for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) if (r.inFix) [marked addObject:r.key];
    NSMutableSet<NSString *> *gone = [all mutableCopy];
    [gone minusSet:left];
    press.memoryBack = 0;
    NSString *noMemory = [PolishDock(av).macLines componentsJoinedByString:@" | "];
    press.memoryBack = 800 * MB;
    after.fixes = @[own, press, press];
    av.model = ({ after.generation = 2; after; });
    av.pointsAtFix = YES;
    NSString *two = PolishDock(av).macLines.firstObject;
    Check([noMemory isEqualToString:@"After the fix | 42.4 GB | memory in use, as now | 184 GB disk free"] && [two isEqualToString:@"After all 2 fixes"],
          @"window dock: a fix that gives no memory back does not say one number twice, and several are \"all 2 fixes\"", [NSString stringWithFormat:@"%@ / %@", noMemory, two]);
    Check([then isEqualToString:@"After the fix | 41.6 GB | memory, now 42.4 GB | 184 GB disk free"] && all.count == 72 && marked.count > 0 && [gone isEqualToSet:marked],
          @"window dock: the Mac after Fix Everything counts only the fixes that need nobody, each side on its own, and the ring drops exactly the rows a press acts on",
          [NSString stringWithFormat:@"%@, %lu of %lu rows gone, %lu marked", then, (unsigned long)gone.count, (unsigned long)all.count, (unsigned long)marked.count]);

    // While a run plays, Stop sits right of the button beside "Fix 3 of 5", inside the slim dock, and a press on it
    // stops the run once. At rest it is not there.
    BOOL restHidden = dock.stop.hidden;
    [dock.stop performClick:nil];
    MMWindowView *r = PolishView(@"running");
    PolishHost *rhost = [PolishHost new];
    r.host = rhost;
    MMWindowDockView *rdock = PolishDock(r);
    NSRect at = rdock.stop.frame;
    [rdock.stop performClick:nil];
    Check(restHidden && host.stops == 0 && !rdock.stop.hidden && rhost.stops == 1 && rhost.fixes == 0 && NSMinX(at) > NSMaxX(rdock.fix.frame) && NSMinY(at) >= 0 && NSMaxY(at) <= rdock.bounds.size.height &&
          NSMinX(at) - NSMaxX(rdock.fix.frame) < 140 && NSMaxX(at) <= rdock.bounds.size.width && [rdock.stop.accessibilityLabel isEqualToString:@"Stop after this step"],
          @"window dock: Stop shows beside the run's count, right of the button, only while a run plays, and a press stops the run", [NSString stringWithFormat:@"%ld stops, %@", (long)rhost.stops, NSStringFromRect(at)]);
    [rdock.fix performClick:nil];
    Check(rhost.stops == 2 && rhost.fixes == 0, @"window dock: the large button stops the run too", @"");
    // The slim dock: one band of 64 points at the window's foot, the gear and the power icon level with its middle,
    // right of it. The running button is filled as far as fixes landed, 2 of 5, and the gains count "so far".
    MMWindowButton *rgear = nil;
    for (MMWindowButton *b in WindowButtons(r)) if (b.kind == MMWindowButtonGear) rgear = b;
    NSRect dockIn = [rdock convertRect:rdock.bounds toView:r];
    MMWindowDockView *ended = PolishDock(PolishView(@"done"));
    Check(rdock.bounds.size.height == 64 && NSMaxY(dockIn) == MMWindowSize.height && fabs(NSMidY(rgear.frame) - NSMidY(dockIn)) < 0.5 && NSMinX(rgear.frame) >= NSMaxX(dockIn) &&
          fabs(rdock.progress - 0.4) < 0.001 && [rdock.gainWord isEqualToString:@"so far"] && [rdock.buttonWords isEqualToString:@"Stopping :4321 Astro"] &&
          [dock.buttonWords isEqualToString:@"Fix Everything"] && dock.gainWord == nil && [ended.buttonWords isEqualToString:@"5 fixes done"] && ended.gainLines.count == 2,
          @"window dock: one slim band at the foot with the gear beside it, the running button filled as far as fixes landed, and the end on the button's face",
          [NSString stringWithFormat:@"%@, gear %@, %g filled, %@ / %@ / %@", NSStringFromRect(dockIn), NSStringFromRect(rgear.frame), rdock.progress, rdock.buttonWords, dock.buttonWords, ended.buttonWords]);
    // VoiceOver hears how far the run is, in the button's label and as it moves on.
    NSString *heard = rdock.announced;
    MMWindowModel *next = MMWindowFixture(@"running");
    next.generation = 2; next.run.done = 3; next.run.step = @"Quitting Music";
    r.model = next;
    Check([heard isEqualToString:@"Fix 3 of 5"] && [rdock.announced isEqualToString:@"Fix 4 of 5"] && [rdock.fix.accessibilityLabel isEqualToString:@"Stop, Fix 4 of 5, Quitting Music"],
          @"window dock: VoiceOver hears the run's count when it changes, and the button's label holds it", [NSString stringWithFormat:@"%@ then %@, %@", heard, rdock.announced, rdock.fix.accessibilityLabel]);
    // A step with a name far too long for the button shows its action alone, never a cut name: the count stands
    // under the button already. A short one is whole.
    MMWindowDockView *xdock = PolishDock(PolishView(@"extreme-running"));
    Check([rdock.stepWords isEqualToString:@"Quitting Music"] && [xdock.stepWords isEqualToString:@"Wrapping up"] && [xdock.fix.accessibilityLabel containsString:MMWindowFixture(@"extreme-running").run.step],
          @"window dock: a step too long for two lines in the button shows its action alone, and VoiceOver still hears the whole step", xdock.stepWords);
    // The end note is whole sentences, and where removed things went is kept first. The longest the runner can make
    // shortens its Skipped list from the end, to whole phrases and "and more", before any other sentence goes. With
    // a skip list longer still, the Skipped sentence goes and the others stay.
    MMWindowView *ev = PolishView(@"extreme-done");
    NSString *drawn = PolishDock(ev).endNote, *where = @"Deleted 3, moved 2 to the Trash and kept 1 in a recovery folder.", *saved = @"Files git ignores were saved in a recovery folder.";
    MMWindowModel *longer = MMWindowFixture(@"extreme-done");
    longer.generation = 2;
    longer.run.endNote = [@"Skipped 12 agents that ask you working on the longest branch names anyone has given to a branch in any of the repositories on this Mac, "
                          @"each of them waiting on a question about a permission that only you can answer, 3 fixes that need your own press because their tools clean their own caches and nothing else may, "
                          @"14 kept since they changed or are in use. " stringByAppendingString:[@[where, saved] componentsJoinedByString:@" "]];
    ev.model = longer;
    NSString *longest = PolishDock(ev).endNote;
    Check([drawn hasPrefix:@"Skipped 12 agents that ask you, "] && [drawn containsString:@" and more. "] && [drawn hasSuffix:[@[where, saved] componentsJoinedByString:@" "]] &&
          [longest isEqualToString:[@[where, saved] componentsJoinedByString:@" "]] &&
          [PolishDock(PolishView(@"done")).endNote isEqualToString:MMWindowFixture(@"done").run.endNote],
          @"window dock: a long end note keeps whole sentences only and where removed things went first, its Skipped list shortened before that, and one that fits is whole",
          [NSString stringWithFormat:@"%@ / %@", drawn, longest]);

    // Settings: three cards that read at a glance. Keep this Mac awake stands first with its three switches, Clean up
    // on its own beside it with one switch a rule, and This Mac under the first. Every row is one line high with a
    // second line only for a state, no removal choice is drawn, and the watching note stands once, in a badge.
    MMWindowView *sv = PolishView(@"calm");
    PolishHost *shost = [PolishHost new];
    sv.host = shost;
    sv.showsSettings = YES;
    MMWindowSettingsView *panel = PolishSettings(sv);
    NSMutableDictionary<NSString *, NSButton *> *switches = [NSMutableDictionary new];
    NSInteger others = 0, tall = 0, noted = 0, helped = 0;
    for (NSView *sub in panel.subviews) {
        if (![sub isKindOfClass:NSButton.class] || ![sub respondsToSelector:NSSelectorFromString(@"mark")]) continue;
        if (![[sub valueForKey:@"isSwitch"] boolValue]) { others++; continue; }
        switches[[sub valueForKey:@"ownerID"]] = (NSButton *)sub;
        NSString *note = [sub valueForKey:@"note"];
        if (note.length) noted++;
        if (sub.frame.size.height < 36 || sub.frame.size.height > (note.length ? 56 : 44)) tall++;
        if (((NSButton *)sub).toolTip.length > 20 && [((NSButton *)sub).toolTip isEqualToString:sub.accessibilityHelp]) helped++;
    }
    NSButton *lid = switches[@"lid"], *login = switches[@"login"];
    NSButton *awake = switches[@"awake"], *agents = switches[@"agents"], *servers = switches[@"rule:servers"], *caches = switches[@"rule:caches"];
    Check(awake && agents && lid && login && servers && caches && switches.count == 8 && others == 0 &&
          NSMinX(awake.frame) == NSMinX(agents.frame) && NSMinX(agents.frame) == NSMinX(lid.frame) && NSMaxY(awake.frame) <= NSMinY(agents.frame) && NSMaxY(agents.frame) <= NSMinY(lid.frame) &&
          NSMinY(awake.frame) == NSMinY(servers.frame) && NSMinX(awake.frame) < NSMinX(servers.frame) && NSMinX(servers.frame) == NSMinX(caches.frame) &&
          NSMinX(login.frame) == NSMinX(awake.frame) && NSMinY(login.frame) > NSMaxY(lid.frame) + 40,
          @"window settings: Keep this Mac awake stands first with Keep awake now, While agents work and the lid, each rule is one switch beside it, This Mac stands under the first, and no removal choice is drawn",
          [NSString stringWithFormat:@"%@, %ld others", [switches.allKeys componentsJoinedByString:@","], (long)others]);
    Check(tall == 0 && noted == 1 && helped == 8 && [[lid valueForKey:@"note"] isEqualToString:MMWindowNoLidNote],
          @"window settings: every row is one line high, a second line only says a state, here that the Mac has no lid, and what each switch does is its tooltip and VoiceOver's help",
          [NSString stringWithFormat:@"%ld too tall, %ld with a second line, %ld with help", (long)tall, (long)noted, (long)helped]);
    NSArray *cards = [panel valueForKey:@"cards"];
    NSMutableSet *tints = [NSMutableSet new], *marks = [NSMutableSet new];
    NSInteger badges = 0;
    CGFloat lowest = 0;
    for (id c in cards) {
        [tints addObject:[[c valueForKey:@"tint"] description]]; [marks addObject:[c valueForKey:@"mark"]];
        if ([[c valueForKey:@"badge"] length]) badges++;
        lowest = MAX(lowest, NSMaxY([[c valueForKey:@"frame"] rectValue]));
    }
    Check(cards.count == 3 && tints.count == 3 && marks.count == 3 && lowest < panel.bounds.size.height - 60 &&
          [[cards[0] valueForKey:@"title"] isEqualToString:MMWindowAwakeCard] && [[cards[1] valueForKey:@"title"] isEqualToString:MMWindowCleanupCard] &&
          [[cards[2] valueForKey:@"footer"] isEqualToString:MMWindowTrashLine],
          @"window settings: three cards, each with its own color and mark, as tall as their rows, and This Mac says removed things go to the Trash",
          [NSString stringWithFormat:@"%lu cards, %lu colors, %lu marks, foot at %g", (unsigned long)cards.count, (unsigned long)tints.count, (unsigned long)marks.count, lowest]);
    Check(badges == 1 && [[cards[1] valueForKey:@"badge"] isEqualToString:@"Starts in 23 h"] && [servers.toolTip hasSuffix:@" Starts in 23 h."],
          @"window settings: the watching note stands once, as a badge on the cleanup card's head, and not on each rule", [NSString stringWithFormat:@"%ld badges", (long)badges]);
    MMWindowView *busySettings = PolishView(@"busy");
    busySettings.showsSettings = YES;
    NSInteger busyBadges = 0, busyNoted = 0;
    for (id c in [PolishSettings(busySettings) valueForKey:@"cards"]) if ([[c valueForKey:@"badge"] length]) busyBadges++;
    for (NSView *sub in PolishSettings(busySettings).subviews) if ([sub respondsToSelector:NSSelectorFromString(@"mark")] && [[sub valueForKey:@"note"] length]) busyNoted++;
    Check(busyBadges == 0 && busyNoted == 3, @"window settings: once the rules may act there is no badge, and the busy day's state lines are the agents held, the lid and the app that waits",
          [NSString stringWithFormat:@"%ld badges, %ld state lines", (long)busyBadges, (long)busyNoted]);
    MMWindowView *asked = PolishView(@"busy");
    asked.showsSettings = YES;
    Check(panel.frame.origin.y == 12 && PolishSettings(asked).frame.origin.y == 40 && NSMaxY(panel.frame) == 688, @"window settings: with nobody asking, Settings starts at the top and no empty band stands over it",
          [NSString stringWithFormat:@"%g and %g", panel.frame.origin.y, PolishSettings(asked).frame.origin.y]);
    [lid performClick:nil];
    Check(lid && !lid.enabled && [[lid valueForKey:@"inert"] boolValue] && shost.switches == 0 && [lid.accessibilityLabel hasSuffix:MMWindowNoLidNote],
          @"window settings: on a Mac with no lid the lid switch is not available, takes no press and says why", [NSString stringWithFormat:@"%ld calls, %@", (long)shost.switches, lid.accessibilityLabel]);
    [login performClick:nil];
    Check(shost.switches == 1, @"window settings: the login switch does take its press", @"");
    [awake performClick:nil];
    [servers performClick:nil];
    Check(shost.switches == 2 && shost.rules == 1 && [shost.lastRule isEqualToString:@"servers"] && shost.lastPicked == 0,
          @"window settings: Keep awake now takes its press, and a rule's switch turns the rule off", [NSString stringWithFormat:@"%ld switches, %@ %ld", (long)shost.switches, shost.lastRule, (long)shost.lastPicked]);
    NSButton *apps = nil;
    for (NSView *sub in PolishSettings(sv).subviews) if ([sub respondsToSelector:NSSelectorFromString(@"mark")] && [[sub valueForKey:@"ownerID"] isEqualToString:@"rule:apps"]) apps = (NSButton *)sub;
    [apps performClick:nil];
    Check(shost.rules == 2 && [shost.lastRule isEqualToString:@"apps"] && shost.lastPicked == MMWindowRuleOnChoice(@"apps"),
          @"window settings: a rule's switch that is off turns the rule to the mode that acts on its own", [NSString stringWithFormat:@"%@ %ld", shost.lastRule, (long)shost.lastPicked]);

    // In a window that is ordered in, off screen: the glow around Fix Everything breathes only at rest with something
    // to fix, a new row gets its short light, and the turn to Settings ends with Settings in its place.
    BOOL motion = !MMWindowReduceMotion();
    MMWindowView *live = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    NSWindow *win = ShownWindow(live);
    live.model = MMWindowFixture(@"busy");
    [live opened];
    [live display];
    MMWindowDockView *ld = PolishDock(live);
    SpinUntil(^BOOL { return ld.breathes == motion; });          // the breath starts right after the first drawing
    MMWindowListView *ll = WindowLists(live).firstObject;
    BOOL breathes = ld.breathes, firstFlash = ll.flashed > 0;
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
    Check(breathes == motion && !underPointer && again == motion && !firstFlash && lit == 1 && ll.flashed == 0,
          @"window motion: the button's glow breathes at rest and not under the pointer, and only a row that is new gets the short light",
          [NSString stringWithFormat:@"rest %d, pointed %d, again %d, first %d, new %ld, same %ld", breathes, underPointer, again, firstFlash, (long)lit, (long)ll.flashed]);
    // A model with no rows, as after Start before the first numbers, then the first full one: nothing is new then.
    MMWindowModel *none = MMWindowFixture(@"empty"), *full = MMWindowFixture(@"busy");
    none.generation = 4; full.generation = 5;
    live.model = none;
    live.model = full;
    NSInteger afterNone = ll.flashed + WindowLists(live).lastObject.flashed;
    // And a list that is hidden under Settings lights nothing.
    live.showsSettings = YES;
    NSView *pane = PolishSettings(live);
    BOOL held = !MMWindowTakesPresses(pane.subviews.firstObject) || !motion;
    SpinUntil(^BOOL { return pane.frame.origin.y == 40 && pane.alphaValue == 1 && MMWindowTakesPresses(pane.subviews.firstObject); });
    MMWindowModel *hidden = MMWindowFixture(@"busy");
    hidden.generation = 6;
    hidden.memoryGroups[1].rows = [@[fresh] arrayByAddingObjectsFromArray:hidden.memoryGroups[1].rows];
    live.model = hidden;
    Check(afterNone == 0 && ll.flashed == 0, @"window motion: after a model with no rows the first full one lights nothing, and a list hidden under Settings lights nothing",
          [NSString stringWithFormat:@"%ld after none, %ld hidden", (long)afterNone, (long)ll.flashed]);
    Check(held && pane.frame.origin.y == 40 && pane.alphaValue == 1 && !pane.hidden && MMWindowTakesPresses(pane.subviews.firstObject) && !ld.breathes,
          @"window motion: the turn to Settings holds presses while Settings rises, and ends with it in its place and the menu's glow still",
          [NSString stringWithFormat:@"held %d, y %g, alpha %g, breathes %d", held, pane.frame.origin.y, pane.alphaValue, ld.breathes]);
    live.showsSettings = NO;
    SpinUntil(^BOOL { return MMWindowTakesPresses(ld.fix) && ld.breathes == motion; });
    BOOL back = ld.breathes;
    // Closed while still on screen: the breath does not come back with the next drawing.
    [live rest];
    [live display];
    // Something that must not start: there is nothing to wait for, so the main loop runs a moment for it to show if it would.
    Spin(0.1);
    BOOL afterRest = ld.breathes;
    [live opened];
    [live display];
    SpinUntil(^BOOL { return ld.breathes == motion; });
    BOOL reopened = ld.breathes;
    MMWindowModel *dim = MMWindowFixture(@"young");
    dim.generation = 7;
    live.model = dim;
    BOOL dimmedStill = !ld.breathes;
    [win orderOut:nil]; [live rest];
    Check(back == motion && !afterRest && reopened == motion && dimmedStill && !ld.breathes,
          @"window motion: nothing breathes once the window closed, even while it is still on screen, and a dimmed button does not breathe",
          [NSString stringWithFormat:@"back %d, after rest %d, reopened %d", back, afterRest, reopened]);
    [win close];

    // A scrolled group keeps the row it showed first when a model changes what is above it, a model that comes while
    // the fingers move leaves the offset alone, and at rest a group has no blank strip at its foot.
    MMWindowListView *sl = WindowLists(PolishView(@"extreme")).firstObject;
    MMWindowGroup *sg = sl.groups.firstObject;
    [sl reveal:sg.rows[40].key];
    CGFloat restOff = sl.offsets[sg.key].doubleValue;
    NSArray<NSNumber *> *restTops = sl.rowTops.firstObject;
    NSUInteger firstShown = [restTops indexOfObject:@(restOff)];
    NSString *firstKey = firstShown != NSNotFound ? sg.rows[firstShown].key : nil;
    MMWindowModel *grown = MMWindowFixture(@"extreme");
    grown.memoryGroups[0].rows[5].name = @":3005 Vite with a name that is now long enough to wrap onto a second line of its row";
    [sl setGroups:grown.memoryGroups ring:grown.ring];
    CGFloat grownOff = sl.offsets[sg.key].doubleValue;
    NSUInteger grownFirst = [sl.rowTops.firstObject indexOfObject:@(grownOff)];
    Check(firstKey && grownOff > restOff && grownFirst != NSNotFound && [sl.groups.firstObject.rows[grownFirst].key isEqualToString:firstKey],
          @"window lists: a scrolled group keeps the row it showed first when a row above it grows", [NSString stringWithFormat:@"%g then %g", restOff, grownOff]);
    NSRect sbox = sl.groupFrames.firstObject.rectValue;
    // A wheel event placed over the first group: where the CG point (0, 0) lands is read first, then the event is
    // moved to the group's middle, so it scrolls that group wherever the real pointer is.
    CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, -7);
    CGEventSetLocation(cg, CGPointZero);
    NSPoint zero = [NSEvent eventWithCGEvent:cg].locationInWindow, want = [sl convertPoint:NSMakePoint(NSMidX(sbox), NSMidY(sbox)) toView:nil];
    CGEventSetLocation(cg, CGPointMake(want.x - zero.x, zero.y - want.y));
    NSEvent *wheel = [NSEvent eventWithCGEvent:cg];
    CFRelease(cg);
    BOOL over = NSPointInRect([sl convertPoint:wheel.locationInWindow fromView:nil], sbox);
    [sl scrollWheel:wheel];
    CGFloat moving = sl.offsets[sg.key].doubleValue;
    [sl setGroups:MMWindowFixture(@"extreme").memoryGroups ring:grown.ring];
    CGFloat stillMoving = sl.offsets[sg.key].doubleValue;
    Check(over && moving == grownOff + 7 && stillMoving == moving, @"window lists: a model that comes while a group is being scrolled leaves its offset where the fingers have it",
          [NSString stringWithFormat:@"over the group %d, %g at rest, %g moving, %g after the model", over, grownOff, moving, stillMoving]);
    [sl rest];
    [sl setGroups:grown.memoryGroups ring:grown.ring];
    [sl reveal:grown.memoryGroups[0].rows[60].key];
    NSRect foot = [sl frameOfRow:@""], lastShown = NSZeroRect;
    for (MMWindowRow *row in grown.memoryGroups[0].rows) { NSRect at = [sl frameOfRow:row.key]; if (!NSIsEmptyRect(at)) lastShown = at; }
    (void)foot;
    Check(!NSIsEmptyRect(lastShown) && fabs(NSMaxY(lastShown) - NSMaxY(sbox)) < 1, @"window lists: at rest a scrolled group has no blank strip at its foot: its last row ends where the group does",
          [NSString stringWithFormat:@"last row ends at %g, the group at %g", NSMaxY(lastShown), NSMaxY(sbox)]);

    WindowWordChecks();
    WindowRowChecks();
    WindowMeasuringChecks();
}
