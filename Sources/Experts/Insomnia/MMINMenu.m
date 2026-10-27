// Insomnia's data classes, menu and cards as specs. Pure: it reads an MMINState and nothing else,
// so tools/render.m draws it from fixture states with Sources/UI alone.
// Ported from -showMenu, -agentsLine and -pauseReason in Insomnia's main.m, rewritten to DESIGN.md:
// the submenus of switches become two actions, a lid row with its card, and More.
#import "Experts/Insomnia/MMInsomnia.h"
#import "UI/MMFormat.h"

NSString *const MMINLidFindingID = @"insomnia:lid:override";

@implementation MMINPrefs
+ (instancetype)defaults {
    MMINPrefs *p = [self new];
    p.manual = NO; p.agents = YES; p.lid = NO; p.screenOff = YES; p.thermalGuard = YES;
    p.minBattery = 20; p.graceMinutes = 120; p.offlineMinutes = 15; p.quietMinutes = 10;
    return p;
}
- (id)copyWithZone:(NSZone *)zone {
    MMINPrefs *p = [MMINPrefs new];
    p.manual = self.manual; p.agents = self.agents; p.lid = self.lid; p.screenOff = self.screenOff; p.thermalGuard = self.thermalGuard;
    p.minBattery = self.minBattery; p.graceMinutes = self.graceMinutes; p.offlineMinutes = self.offlineMinutes; p.quietMinutes = self.quietMinutes;
    return p;
}
@end

@implementation MMINClocks
- (id)copyWithZone:(NSZone *)zone {
    MMINClocks *c = [MMINClocks new];
    c.unpluggedAt = self.unpluggedAt; c.offlineAt = self.offlineAt; c.thermalHold = self.thermalHold;
    return c;
}
@end

@implementation MMINWorker
@end
@implementation MMINInput
@end
@implementation MMINHolder
@end
@implementation MMINState
@end
@implementation MMINView
@end

#pragma mark - Words

static NSString *const kThermalNames[] = { @"nominal", @"fair", @"serious", @"critical" };
static NSString *ThermalName(NSProcessInfoThermalState t) { return t <= 3 ? kThermalNames[t] : @"unknown"; }

/// "10 minutes", "2 hours", "never", for the guard numbers.
static NSString *Minutes(NSInteger m) {
    if (m <= 0) return @"never";
    if (m % 60 == 0) return MMPlural(m / 60, @"hour");
    return MMPlural(m, @"minute");
}

static NSInteger Working(MMINState *st) {
    NSInteger n = 0;
    for (MMINHolder *h in st.holders) n += h.working && ![h.kind isEqualToString:@"hold"];
    return n;
}

static NSInteger Agents(MMINState *st) {
    NSInteger n = 0;
    for (MMINHolder *h in st.holders) n += ![h.kind isEqualToString:@"hold"];
    return n;
}

static NSString *PowerWords(MMINState *st) {
    if (st.onAC) return st.batteryPercent >= 0 ? [NSString stringWithFormat:@"On charger, %d%%", st.batteryPercent] : @"On power";
    NSString *s = [NSString stringWithFormat:@"Battery %d%%", st.batteryPercent];
    if (st.clocks.unpluggedAt) s = [s stringByAppendingFormat:@", unplugged %@", MMDuration([st.at ?: NSDate.date timeIntervalSinceDate:st.clocks.unpluggedAt])];
    return s;
}

/// The lid override in a few words, for the lid row. brief leaves out the reason, for the header line.
static NSString *LidWords(MMINState *st, BOOL brief) {
    if (st.otherApp) return brief ? @"lid override left to Insomnia.app" : @"set by Insomnia.app";
    if (st.lidLive) return brief ? @"lid override live" : @"live";
    if (st.pauseReason) return brief ? @"lid override paused" : [@"paused, " stringByAppendingString:st.pauseReason];
    if (st.lidProblem) return brief ? @"lid override off" : [@"off, " stringByAppendingString:st.lidProblem];
    return brief ? @"lid override off" : @"off until something keeps the Mac awake";
}

NSString *MMINHeadline(MMINState *st) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:PowerWords(st)];
    if (st.prefs.lid && st.laptop) [parts addObject:LidWords(st, YES)];
    if (!st.prefs.agents) [parts addObject:@"agent mode off"];
    return [parts componentsJoinedByString:@" · "];
}

NSString *MMINAccessibilityState(MMINState *st) {
    if (!st) return @"starting";
    if (st.prefs.manual) return @"awake, Keep Mac Awake is on";
    NSInteger n = Agents(st);
    if (st.holding && n) return [NSString stringWithFormat:@"awake for %@", MMPlural(n, @"agent")];
    if (st.holding) return @"awake for a script";
    return @"Mac may sleep";
}

#pragma mark - Menu

static MMActionSpec *Act(MMINView *v, NSString *title, NSString *what, NSString *key) {
    void (^act)(NSString *, NSString *) = v.act;
    return [MMActionSpec title:title tail:nil run:^(BOOL option) { if (act) act(what, key); }];
}

/// "for 6 more minutes", "for 1 more minute".
static NSString *MoreMinutes(NSTimeInterval seconds) {
    NSInteger n = MAX(1, (NSInteger)ceil(seconds / 60));
    return [NSString stringWithFormat:@"for %ld more %@", (long)n, n == 1 ? @"minute" : @"minutes"];
}

static void Header(MMINState *st, MMMenuSpec *m) {
    NSInteger agents = Agents(st), working = Working(st);
    m.headerLine = MMINHeadline(st);
    if (st.prefs.manual) { m.headerBig = @"Awake"; m.headerUnit = @"until you let it sleep"; return; }
    if (!st.holding) { m.headerBig = @"Sleeps"; m.headerUnit = @"when idle"; return; }
    if (working) { m.headerBig = @"Awake"; m.headerUnit = [@"for " stringByAppendingString:MMPlural(agents, @"agent")]; return; }
    if (agents && st.releaseIn > 0) {
        m.headerBig = @"Awake";
        m.headerUnit = MoreMinutes(st.releaseIn);
        return;
    }
    m.headerBig = @"Awake"; m.headerUnit = @"for a script";
}

static NSString *Summary(MMINState *st) {
    NSMutableArray *s = [NSMutableArray new];
    NSInteger working = Working(st);
    MMINHolder *first = st.holders.firstObject;
    if (st.lowBattery && !st.prefs.manual) {
        [s addObject:@"The battery is low, so agent holds ended and the Mac may sleep."];
        [s addObject:@"They come back when the charger does."];
    } else if (st.prefs.manual) {
        [s addObject:@"Keep Mac Awake is on, so the Mac stays awake whatever the agents do."];
        if (working) [s addObject:[NSString stringWithFormat:@"%@ working now %@ no hold of %@ own.", MMCapitalized(MMPlural(working, @"agent")),
                                   working == 1 ? @"needs" : @"need", working == 1 ? @"its" : @"their"]];
    } else if (working == 1) {
        [s addObject:[NSString stringWithFormat:@"%@ works%@, so the Mac stays awake.", first.name,
                      first.project.length ? [@" in " stringByAppendingString:first.project] : @""]];
        [s addObject:[NSString stringWithFormat:@"It may sleep %@ after the last agent stops.", Minutes(st.prefs.quietMinutes)]];
    } else if (working > 1) {
        [s addObject:[NSString stringWithFormat:@"%ld agents work, so the Mac stays awake.", (long)working]];
        [s addObject:[NSString stringWithFormat:@"It may sleep %@ after the last one stops.", Minutes(st.prefs.quietMinutes)]];
    } else if (st.holding && Agents(st)) {
        [s addObject:@"No agent works now."];
        [s addObject:@"The Mac may sleep once the quiet period ends, unless one starts again."];
    } else if (st.holding) {
        [s addObject:@"A script asked MinMacs to keep the Mac awake until its process exits."];
    } else if (st.prefs.agents) {
        [s addObject:st.watched ? @"No agent works now, so the Mac sleeps as usual." : @"No agent runs now, so the Mac sleeps as usual."];
        [s addObject:@"Insomnia keeps it awake while an agent works."];
    } else {
        [s addObject:@"Awake While Agents Work is off, so the Mac sleeps as usual."];
    }
    return [s componentsJoinedByString:@" "];
}

static MMRowSpec *HolderRow(MMINHolder *h) {
    MMRowSpec *r = [MMRowSpec new];
    r.name = h.name;
    NSString *state = [h.kind isEqualToString:@"hold"] ? @"until it exits"
                    : h.working ? @"working" : [@"idle " stringByAppendingString:MMShortDuration(h.idleFor)];
    r.facts = @[h.project.length ? h.project : (h.why ?: @""), state];
    r.mark = h.working ? MMRowMarkWorking : MMRowMarkRecent;
    r.findingID = [h.kind isEqualToString:@"hold"] ? nil : h.findingID;
    return r;
}

MMMenuSpec *MMINMenu(MMINView *v) {
    MMINState *st = v.state;
    MMMenuSpec *m = [MMMenuSpec new];
    Header(st, m);
    m.summary = Summary(st);

    NSMutableArray *actions = [NSMutableArray new];
    [actions addObject:Act(v, st.prefs.manual ? @"Let Mac Sleep" : @"Keep Mac Awake", @"manual", nil)];
    if (st.laptop) {
        MMActionSpec *lid = Act(v, st.prefs.lid ? @"Let Mac Sleep When Lid Closes" : @"Keep Awake With Lid Closed…", @"lid", nil);
        if (st.otherApp) lid.disabledReason = @"Insomnia.app sets it";
        [actions addObject:lid];
    }
    m.actions = actions;

    NSMutableArray *sections = [NSMutableArray new];
    if (st.holders.count) {
        MMSectionSpec *sec = [MMSectionSpec new];
        sec.title = st.prefs.manual || st.lowBattery ? @"Agents" : @"Keeping awake";
        NSMutableArray *rows = [NSMutableArray new];
        for (MMINHolder *h in st.holders) [rows addObject:HolderRow(h)];
        sec.rows = rows;
        [sections addObject:sec];
    }
    if (st.prefs.lid && st.laptop) {
        MMSectionSpec *sec = [MMSectionSpec new];
        sec.title = @"Lid closed";
        MMRowSpec *r = [MMRowSpec new];
        r.name = @"Lid override";
        r.facts = @[LidWords(st, NO)];
        r.mark = st.lidLive ? MMRowMarkWorking : st.lidProblem && !st.otherApp ? MMRowMarkBlocked : MMRowMarkQuiet;
        r.findingID = MMINLidFindingID;
        sec.rows = @[r];
        [sections addObject:sec];
    }
    m.sections = sections;

    NSMutableArray *more = [NSMutableArray new];
    [more addObject:Act(v, st.prefs.agents ? @"Turn Off Awake While Agents Work" : @"Turn On Awake While Agents Work", @"agents", nil)];
    if (st.prefs.lid && st.laptop) {
        [more addObject:Act(v, st.prefs.screenOff ? @"Leave Screen On With Lid Closed" : @"Sleep Screen With Lid Closed", @"screen", nil)];
        [more addObject:Act(v, st.prefs.thermalGuard ? @"Ignore Heat With Lid Closed" : @"Pause When Hot With Lid Closed", @"heat", nil)];
    }
    m.more = more;
    return m;
}

#pragma mark - Cards

static MMCardSpec *LidCard(MMINView *v) {
    MMINState *st = v.state;
    MMINPrefs *p = st.prefs;
    MMCardSpec *c = [MMCardSpec new];
    c.title = @"Lid override";
    NSMutableArray *g = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%ld%%", (long)p.minBattery]];
    if (p.graceMinutes > 0) [g addObject:[MMShortDuration(p.graceMinutes * 60) stringByAppendingString:@" unplugged"]];
    if (p.offlineMinutes > 0) [g addObject:[MMShortDuration(p.offlineMinutes * 60) stringByAppendingString:@" offline"]];
    if (p.thermalGuard) [g addObject:@"heat"];
    NSString *guards = [g componentsJoinedByString:@" · "];
    if (st.otherApp) {
        c.statusWord = @"Left alone."; c.mark = MMRowMarkQuiet;
        c.statusText = @"Insomnia.app still runs and sets the override itself. Quit it and MinMacs takes over.";
    } else if (st.lidLive) {
        c.statusWord = @"Live."; c.mark = MMRowMarkWorking;
        c.statusText = @"The Mac stays awake with the lid closed. On battery the guards below pause it.";
    } else if (st.pauseReason) {
        c.statusWord = @"Paused."; c.mark = MMRowMarkQuiet;
        NSString *back = [st.pauseReason hasPrefix:@"offline"] ? @"the network or the charger returns"
                       : [st.pauseReason hasPrefix:@"hot"] ? @"the lid opens or the charger returns" : @"the charger returns";
        c.statusText = [NSString stringWithFormat:@"%@. The Mac sleeps when the lid closes, until %@.", MMCapitalized(st.pauseReason), back];
    } else if (st.lidProblem) {
        c.statusWord = @"Off."; c.mark = MMRowMarkBlocked;
        c.statusText = [NSString stringWithFormat:@"The override could not be set: %@.", st.lidProblem];
    } else {
        c.statusWord = @"Waits."; c.mark = MMRowMarkQuiet;
        c.statusText = @"It goes live while something keeps the Mac awake, and clears when nothing does.";
    }
    NSString *net = st.online ? @"online" : st.clocks.offlineAt ? [@"offline " stringByAppendingString:MMDuration(-[st.clocks.offlineAt timeIntervalSinceDate:st.at ?: NSDate.date])] : @"offline";
    c.facts = @[[MMCardFact label:@"Power" value:PowerWords(st)],
                [MMCardFact label:@"Lid" value:st.lidClosed ? @"closed" : @"open"],
                [MMCardFact label:@"Heat" value:st.clocks.thermalHold ? [ThermalName(st.thermal) stringByAppendingString:@", held until the lid opens"] : ThermalName(st.thermal)],
                [MMCardFact label:@"Network" value:net],
                [MMCardFact label:@"Guards" value:guards]];
    c.actions = @[Act(v, @"Let Mac Sleep When Lid Closes", @"lid", nil),
                  Act(v, p.screenOff ? @"Leave Screen On With Lid Closed" : @"Sleep Screen With Lid Closed", @"screen", nil),
                  Act(v, p.thermalGuard ? @"Ignore Heat With Lid Closed" : @"Pause When Hot With Lid Closed", @"heat", nil)];
    if (st.otherApp) for (MMActionSpec *a in c.actions) a.disabledReason = @"Insomnia.app sets it";
    return c;
}

static MMCardSpec *HolderCard(MMINView *v, MMINHolder *h) {
    MMINState *st = v.state;
    MMCardSpec *c = [MMCardSpec new];
    c.title = h.project.length ? [NSString stringWithFormat:@"%@ in %@", h.name, h.project] : h.name;
    NSString *ends = [NSString stringWithFormat:@"The hold ends %@ after it stops, or when it exits.", MMShortDuration(st.prefs.quietMinutes * 60)];
    if (st.prefs.manual) {
        c.statusWord = @"Manual wins."; c.mark = MMRowMarkQuiet;
        c.statusText = @"Keep Mac Awake is on, so this agent needs no hold of its own.";
    } else if (st.lowBattery) {
        c.statusWord = @"Let go."; c.mark = MMRowMarkQuiet;
        c.statusText = [NSString stringWithFormat:@"The battery is at %d%%, so its hold ended. It comes back when the charger does.", st.batteryPercent];
    } else if (h.working) {
        c.statusWord = @"Awake."; c.mark = MMRowMarkWorking;
        c.statusText = [NSString stringWithFormat:@"%@ works. %@", h.name, ends];
    } else {
        NSTimeInterval left = MAX(60, st.prefs.quietMinutes * 60 - h.idleFor);
        c.statusWord = [NSString stringWithFormat:@"Awake %@.", MoreMinutes(left)];
        c.mark = MMRowMarkRecent;
        c.statusText = [NSString stringWithFormat:@"It stopped %@ ago. The hold ends %@ after it stops, or when it exits.",
                        MMShortDuration(h.idleFor), MMShortDuration(st.prefs.quietMinutes * 60)];
    }
    NSMutableArray *facts = [NSMutableArray new];
    if (h.linkFindingID) {
        MMCardFact *f = [MMCardFact label:@"Agent" value:h.linkValue ?: h.name];
        f.linkExpert = h.linkExpert; f.linkFindingID = h.linkFindingID;
        [facts addObject:f];
    }
    [facts addObject:[MMCardFact label:@"Process" value:[NSString stringWithFormat:@"pid %d", h.pid]]];
    if (h.why.length) [facts addObject:[MMCardFact label:@"Signal" value:h.why]];
    [facts addObject:[MMCardFact label:@"Holds" value:h.held ? @"idle and system sleep" : st.prefs.manual ? @"nothing, Keep Mac Awake does" : @"nothing now"]];
    c.facts = facts;
    MMActionSpec *skip = Act(v, @"Let Mac Sleep Anyway", @"skip", h.findingID);
    if (!h.held) skip.disabledReason = @"no hold of its own";
    c.actions = @[skip];
    return c;
}

MMCardSpec *MMINCard(MMINView *v, NSString *findingID) {
    if ([findingID isEqualToString:MMINLidFindingID]) return LidCard(v);
    for (MMINHolder *h in v.state.holders) if ([h.findingID isEqualToString:findingID]) return HolderCard(v, h);
    return nil;
}
