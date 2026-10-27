// Insomnia's verbs. `awake` shows what keeps the Mac awake and why, and `insomnia` changes a switch or a guard.
// The commands follow Insomnia's URL scheme: on, off, toggle, agents-on and the rest, as words.
#import "Experts/Insomnia/MMInsomnia.h"
#import "CLI/MMArgs.h"
#import "UI/MMFormat.h"

static NSString *const kUsage =
    @"insomnia on|off|toggle | agents on|off | lid on|off | screen on|off | heat on|off"
     " | set battery|unplugged|offline|quiet <minutes or percent|never> | hold <pid> [reason] [--json] [--dry-run]";

/// The state the verb reads: the app's last pass, or the decision on the snapshot when no app runs.
static MMINState *StateFor(MMArgs *a) {
    MMInsomniaExpert *e = MMInsomniaExpert.shared;
    if (a.inApp && e.state) return e.state;
    MMSnapshot *s = a.snapshot;
    MMINInput *in = e.inputFrom ? e.inputFrom(s.facts) : MMINInputFrom(s.facts);
    MMINClocks *c = [MMINClocks new];
    id u = MMPref(@"insomnia.unpluggedAt"), o = MMPref(@"insomnia.offlineAt");
    if ([u isKindOfClass:NSNumber.class]) c.unpluggedAt = [NSDate dateWithTimeIntervalSince1970:[u doubleValue]];
    if ([o isKindOfClass:NSNumber.class]) c.offlineAt = [NSDate dateWithTimeIntervalSince1970:[o doubleValue]];
    c.thermalHold = MMPrefBool(@"insomnia.thermalHold", NO);
    NSDate *now = e.clock ? e.clock() : NSDate.date;
    MMINPrefs *prefs = [MMINPrefs current];
    return MMINDecide(in, s.facts.power, prefs, MMINAdvance(c, s.facts.power, prefs, now), nil, nil, s.awakeHolds, s, now);
}

static void PrintState(MMArgs *a, MMINState *st) {
    [a print:@"Insomnia: %@", MMINAccessibilityState(st)];
    for (MMINHolder *h in st.holders)
        [a print:@"  %@  %@  %@  pid %d", h.name, h.project.length ? h.project : @"-",
         [h.kind isEqualToString:@"hold"] ? @"until it exits" : h.working ? @"working" : [@"idle " stringByAppendingString:MMShortDuration(h.idleFor)], h.pid];
    [a print:@"%@", MMINHeadline(st)];
    if (st.prefs.lid && st.pauseReason) [a print:@"Lid override paused, %@", st.pauseReason];
    if (st.prefs.lid && st.lidProblem) [a print:@"Lid override problem: %@", st.lidProblem];
}

/// A guard number: minutes or a percent, or never for 0 where the guard allows it.
static NSNumber *Number(NSString *what, NSString *word) {
    if (!word.length) return nil;
    BOOL never = [word.lowercaseString isEqualToString:@"never"];
    NSInteger n = never ? 0 : word.integerValue;
    if (!never && (n <= 0 || ![[NSString stringWithFormat:@"%ld", (long)n] isEqualToString:word])) return nil;
    if ([what isEqualToString:@"battery"]) return !never && n >= 5 && n <= 95 ? @(n) : nil;
    if ([what isEqualToString:@"quiet"]) return !never && n <= 240 ? @(n) : nil;
    if ([what isEqualToString:@"unplugged"] || [what isEqualToString:@"offline"]) return n <= 24 * 60 ? @(n) : nil;
    return nil;
}

static int Change(MMArgs *a) {
    NSArray<NSString *> *w = a.words;
    NSString *cmd = w.firstObject.lowercaseString;
    NSString *what = nil; id value = nil;
    MMInsomniaExpert *e = MMInsomniaExpert.shared;
    if ([@[@"on", @"off"] containsObject:cmd ?: @""]) { what = @"manual"; value = @([cmd isEqualToString:@"on"]); }
    else if ([cmd isEqualToString:@"toggle"]) { what = @"manual"; value = @(![MMINPrefs current].manual); }
    else if ([@[@"agents", @"lid", @"screen", @"heat"] containsObject:cmd ?: @""] && w.count == 2 && [@[@"on", @"off"] containsObject:w[1]]) {
        what = cmd; value = @([w[1] isEqualToString:@"on"]);
    } else if ([cmd isEqualToString:@"set"] && w.count == 3) {
        what = w[1].lowercaseString; value = Number(what, w[2]);
        if (!value) { [a error:@"%@ takes %@", w[1], [what isEqualToString:@"battery"] ? @"a percent from 5 to 95" : @"minutes, or never"]; return MMExitUsage; }
    } else if ([cmd isEqualToString:@"hold"] && w.count >= 2) {
        pid_t pid = (pid_t)w[1].intValue;
        MMProc *p = pid > 1 ? [a.snapshot.facts.sample proc:pid] : nil;
        if (!p) { [a error:@"no process with pid %@", w[1]]; return MMExitFailed; }
        NSString *why = w.count > 2 ? [[w subarrayWithRange:NSMakeRange(2, w.count - 2)] componentsJoinedByString:@" "] : @"held by request";
        if (a.dryRun) { [a print:@"would keep the Mac awake until pid %d exits: %@", pid, why]; return MMExitOK; }
        [MMGraph.shared holdAwake:why pid:p.key];
        if (a.json) [a printJSON:@{@"held": MMProcKeyString(p.key), @"reason": why}];
        else [a print:@"Keeps the Mac awake until pid %d exits.", pid];
        return MMExitOK;
    }
    if (!what) return [a usageError];
    if (a.dryRun) {
        if (a.json) [a printJSON:@{@"setting": what, @"value": value, @"dryRun": @YES}];
        else [a print:@"would set %@ to %@", what, [value isKindOfClass:NSNumber.class] && [@[@"manual", @"agents", @"lid", @"screen", @"heat"] containsObject:what] ? ([value boolValue] ? @"on" : @"off") : value];
        return MMExitOK;
    }
    int need = [a needsApp];
    if (need) return need;
    NSString *problem = [e set:what value:value by:@"cli"];
    if (problem) { [a error:@"insomnia: %@", problem]; return MMExitFailed; }
    MMINState *st = e.state ?: StateFor(a);
    if (a.json) [a printJSON:MMINStateJSON(st)];
    else PrintState(a, st);
    return MMExitOK;
}

NSArray<MMVerbSpec *> *MMINVerbs(void) {
    MMVerbSpec *awake = [MMVerbSpec verb:@"awake" usage:@"awake [--json]" mutates:NO run:^int(MMArgs *a) {
        MMINState *st = StateFor(a);
        if (a.json) {
            NSMutableDictionary *j = [MMINStateJSON(st) mutableCopy];
            j[@"inApp"] = @(a.inApp);
            if (a.inApp) j[@"held"] = MMAwake.held;
            [a printJSON:j];
        } else PrintState(a, st);
        return MMExitOK;
    }];
    MMVerbSpec *change = [MMVerbSpec verb:@"insomnia" usage:kUsage mutates:YES run:^int(MMArgs *a) { return Change(a); }];
    return @[awake, change];
}
