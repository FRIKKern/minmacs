// What an item of a row's menu does, MMWindowActs.h.
#import "Shell/MMWindowActs.h"
#import "Shell/MMWindowFeed.h"

NSString *const MMWindowBy = @"window";

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

/// The words of a failure, as the menus say it: the action's own reason, and a keep's without its prefix.
static NSString *Why(NSString *err) {
    NSString *w = err.length ? err : @"it did not run";
    if ([w hasPrefix:@"kept: "]) w = [@"it is kept: " stringByAppendingString:[w substringFromIndex:6]];
    w = [w stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[w substringToIndex:1].uppercaseString];
    return [w hasSuffix:@"."] ? w : [w stringByAppendingString:@"."];
}

/// The folder or file a "reveal" shows, by the finding's kind.
static NSString *RevealPath(MMFinding *f) {
    NSDictionary *x = f.facts;
    if ([f.kind isEqualToString:@"app"]) return Str(x[@"bundlePath"]);
    if ([f.kind isEqualToString:@"helper"] || [f.kind isEqualToString:@"server"]) return Str(x[@"cwd"]) ?: f.path;
    if ([f.kind isEqualToString:@"agent"]) return Str(x[@"project"]);
    return f.path ?: Str(x[@"path"]);
}

/// What the desk is asked for, or nil when the item is not the desk's. It names the finding's own value, read now.
static NSString *DeskValue(NSString *action, MMFinding *f) {
    NSDictionary *x = f.facts;
    if ([action isEqualToString:@"reveal"]) return RevealPath(f);
    if ([action isEqualToString:@"open-folder"] || [action isEqualToString:@"terminal"]) return f.path ?: Str(x[@"path"]);
    if ([action isEqualToString:@"open-url"] || [action isEqualToString:@"copy-url"]) return Str(x[@"url"]);
    if ([action isEqualToString:@"open-pr"]) return MMWindowPullOf(x).url;
    if ([action isEqualToString:@"copy-branch"]) return Str(x[@"branch"]);
    if ([action isEqualToString:@"copy-pid"] || [action isEqualToString:@"show"] || [action isEqualToString:@"hide"]) {
        pid_t pid = MMWindowPidOf(f);
        return pid > 0 ? [NSString stringWithFormat:@"%d", pid] : nil;
    }
    if ([action isEqualToString:@"copy-session"]) {
        NSString *stable = f.stableKey ?: @"";
        NSRange colon = [stable rangeOfString:@":"];
        return colon.location == NSNotFound ? nil : Str([stable substringFromIndex:colon.location + 1]);
    }
    return nil;
}

static void Desk(id<MMWindowDesk> desk, NSString *action, NSString *v) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([action isEqualToString:@"show"]) [desk showApp:(pid_t)v.intValue];
        else if ([action isEqualToString:@"hide"]) [desk hideApp:(pid_t)v.intValue];
        else if ([action isEqualToString:@"reveal"]) [desk reveal:v];
        else if ([action isEqualToString:@"open-folder"]) [desk openFolder:v];
        else if ([action isEqualToString:@"terminal"]) [desk openInTerminal:v];
        else if ([action isEqualToString:@"open-url"] || [action isEqualToString:@"open-pr"]) [desk openURL:v];
        else [desk copyText:v];
    });
}

/// The press an item stands for, as the expert's own menu runs it: what, and the step.
static NSString *PressOf(NSString *action, MMStopStep *step) {
    *step = [action hasPrefix:@"force-"] ? MMStopKill : MMStopTerm;
    NSString *what = [action hasPrefix:@"force-"] ? [action substringFromIndex:6] : action;
    return [@[@"quit", @"stop", @"remove", @"trash"] containsObject:what] ? what : nil;
}

static MMUndoRecord *Act(NSString *action, NSString *key, MMSnapshot *s, MMPerformance *p, id<MMWindowDesk> desk, NSString *__strong *problem) {
    MMPerformanceRow *row = [p row:key];
    MMFinding *f = row.finding ?: [s finding:row.findingID ?: key];
    void (^refuse)(NSString *) = ^(NSString *why) { *problem = why; };
    if (!f) { refuse(@"it is gone"); return nil; }
    // MinMacs never quits, hides or stops itself from its own window, whatever asks.
    if (MMWindowIsMinMacs(f)) { refuse(@"it is MinMacs itself"); return nil; }
    NSString *name = MMWindowNameOf(f);

    NSString *v = DeskValue(action, f);
    if (v) {
        if (!desk) { refuse(@"there is nothing to show it with"); return nil; }
        Desk(desk, action, v);
        return nil;
    }

    if ([action isEqualToString:@"keep"]) {
        if (!f.stableKey.length) { refuse(@"it has nothing to keep it by"); return nil; }
        NSTimeInterval span = [f.expert isEqualToString:@"locohost"] ? 4 * 3600 : 7 * 86400;
        [MMKeep keep:f.stableKey expert:f.expert until:[NSDate dateWithTimeIntervalSinceNow:span] by:MMWindowBy name:name];
        [MMGraph.shared rebuild:@"window keep"];
        return nil;
    }

    NSString *err = nil;
    MMUndoRecord *rec = nil;
    NSString *verb = nil;
    if ([action isEqualToString:@"wrap-up"]) {
        verb = @"Wrap Up";
        // The plan is made again from the snapshot shown, and every part is checked fresh before it runs.
        MMWrapUpPlan *plan = MMWrapUpPlanFor(f.path ?: Str(f.facts[@"path"]) ?: @"", s);
        if (plan.whyNot) err = plan.whyNot;
        else rec = MMRunWrapUp(plan, MMWindowBy, &err);
    } else {
        MMStopStep step = MMStopTerm;
        NSString *what = PressOf(action, &step);
        if (!what) { refuse(@"the window has no such item"); return nil; }
        verb = @{@"quit": step == MMStopKill ? @"Force Quit" : @"Quit", @"stop": step == MMStopKill ? @"Force Stop" : @"Stop",
                 @"remove": @"Remove", @"trash": @"Move"}[what];
        id<MMExpert> e = MMExpertNamed(f.expert);
        id<MMExpertPolicy> policy = nil;
        id<MMAction> a = [e respondsToSelector:@selector(pressAction:finding:step:policy:)] ? [e pressAction:what finding:f step:step policy:&policy] : nil;
        if (!a) err = @"MinMacs has no such action for it";
        else rec = MMRunAction(a, policy ?: e.policy, nil, MMWindowBy, @"pressed in the window", &err);
    }
    if (!rec || rec.state != MMUndoDone) {
        NSString *why = err ?: rec.error;
        refuse(why ?: @"it did not run");
        // D3: a failure is a notice in the log, with at most one notification. Nothing waits for a person.
        NSString *title = [action isEqualToString:@"trash"] ? [NSString stringWithFormat:@"Could Not Move %@ to the Trash", name]
                                                            : [NSString stringWithFormat:@"Could Not %@ %@", verb, name];
        MMNotice(f.expert ?: @"core", title, Why(why));
    }
    if ([action isEqualToString:@"remove"] || [action isEqualToString:@"wrap-up"]) [MMRepoIndex.shared refresh:nil];
    [MMGraph.shared rebuild:@"window menu"];
    return rec;
}

MMUndoRecord *MMWindowRowAct(NSString *action, NSString *key, MMSnapshot *s, MMPerformance *p, id<MMWindowDesk> desk, NSString **problem) {
    NSString *why = nil;
    MMUndoRecord *r = Act(action, key, s, p, desk, &why);
    if (problem) *problem = why;
    return r;
}
