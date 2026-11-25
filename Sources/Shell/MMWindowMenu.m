// Each row's menu, MMWindowFeed.h: what a right-click on a row offers, like the Dock's menu for an app. Facts only:
// an item stands only where its row's facts say it works now, and nothing here acts. The shell runs a picked item
// through MMWindowActs.h, with "window" as who acted.
#import "Shell/MMWindowFeed.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }

static MMWindowMenuItem *Item(NSString *action, NSString *title, NSString *help) {
    MMWindowMenuItem *i = [MMWindowMenuItem action:action title:title];
    i.help = help;
    return i;
}

/// The first process a finding names, or 0.
pid_t MMWindowPidOf(MMFinding *f) {
    pid_t pid = (pid_t)[Num(f.facts[@"pid"]) intValue];
    if (pid > 0 || !f.procs.count) return pid;
    MMProcKey k = {0, 0};
    [f.procs.firstObject getValue:&k size:sizeof k];
    return k.pid;
}

BOOL MMWindowIsMinMacs(MMFinding *f) {
    pid_t pid = MMWindowPidOf(f);
    NSString *bid = Str(f.facts[@"bundleID"]), *own = NSBundle.mainBundle.bundleIdentifier;
    return pid == getpid() || [bid isEqualToString:@"no.guerrilla.minmacs"] || (own.length && [bid isEqualToString:own]);
}

/// YES while a timed keep holds f, from its facts or from the keeps file, which MMKeep reads once and keeps.
static BOOL Kept(MMFinding *f) {
    NSNumber *until = Num(f.facts[@"keptUntil"]);
    if (until.doubleValue > NSDate.date.timeIntervalSince1970) return YES;
    return f.stableKey.length && [MMKeep keptUntil:f.stableKey expert:f.expert] != nil;
}

/// YES when the expert offers this press on f now.
static BOOL Offers(MMFinding *f, NSString *what, MMStopStep step) {
    id<MMExpert> e = MMExpertNamed(f.expert);
    if (![e respondsToSelector:@selector(pressAction:finding:step:policy:)]) return NO;
    id<MMExpertPolicy> policy = nil;
    return [e pressAction:what finding:f step:step policy:&policy] != nil;
}

/// A separator above the item at `from`, when items stand above it and it is there.
static void Starts(NSMutableArray<MMWindowMenuItem *> *out, NSUInteger from) {
    if (from > 0 && out.count > from) out[from].startsGroup = YES;
}

static void Keep(NSMutableArray *out, MMFinding *f, BOOL hours) {
    if (!f.stableKey.length || Kept(f)) return;
    [out addObject:Item(@"keep", hours ? @"Keep for 4 Hours" : @"Keep for 7 Days",
                        hours ? @"No rule stops it for 4 hours, and Fix Everything leaves it too."
                              : @"No rule acts on it for 7 days, and Fix Everything leaves it too.")];
}

static void Reveal(NSMutableArray *out, NSString *path) {
    if (path.length) [out addObject:Item(@"reveal", @"Show in Finder", nil)];
}

/// An app: Show and Hide, then Quit with Force Quit under Option, then Show in Finder, Keep and Copy PID. A helper is
/// a process with no window: Stop, then the rest. MinMacs itself has no menu: it never quits from its own window.
static NSArray<MMWindowMenuItem *> *AppMenu(MMFinding *f, BOOL helper) {
    if (MMWindowIsMinMacs(f)) return nil;
    NSMutableArray *out = [NSMutableArray new];
    pid_t pid = MMWindowPidOf(f);
    if (!helper && pid > 0) { [out addObject:Item(@"show", @"Show", nil)]; [out addObject:Item(@"hide", @"Hide", nil)]; }
    NSUInteger second = out.count;
    // What a rule or a keep holds would be refused when it runs, so it is not offered.
    if (!Kept(f) && !f.keepReasons.count && Offers(f, helper ? @"stop" : @"quit", MMStopTerm)) {
        [out addObject:helper ? Item(@"stop", @"Stop", @"Undo starts it again.") : Item(@"quit", @"Quit", @"Undo opens it again.")];
        // Force Quit is the second request, so it is there once a Quit was asked for, as the card's.
        if (!helper && [Num(f.facts[@"quitAsked"]) boolValue] && Offers(f, @"quit", MMStopKill)) {
            MMWindowMenuItem *k = Item(@"force-quit", @"Force Quit", @"It did not quit. Force Quit closes it now, and unsaved changes are lost.");
            k.alternate = YES;
            [out addObject:k];
        }
    }
    NSUInteger third = out.count;
    Reveal(out, helper ? Str(f.facts[@"cwd"]) ?: f.path : Str(f.facts[@"bundlePath"]));
    Keep(out, f, NO);
    if (pid > 0) [out addObject:Item(@"copy-pid", @"Copy PID", nil)];
    Starts(out, second); Starts(out, third);
    return out;
}

/// A server: Open in Browser and Copy URL, then Stop with Force Stop under Option and Keep for 4 Hours, then its agent
/// and its folder.
static NSArray<MMWindowMenuItem *> *ServerMenu(MMFinding *f, NSString *agent) {
    NSMutableArray *out = [NSMutableArray new];
    if (Str(f.facts[@"url"])) { [out addObject:Item(@"open-url", @"Open in Browser", nil)]; [out addObject:Item(@"copy-url", @"Copy URL", nil)]; }
    NSUInteger second = out.count;
    BOOL protect = [Num(f.facts[@"protected"]) boolValue];
    if (!protect && !Kept(f) && Offers(f, @"stop", MMStopTerm)) {
        [out addObject:Item(@"stop", @"Stop", @"Undo starts it again.")];
        MMWindowMenuItem *k = Item(@"force-stop", @"Force Stop", @"SIGKILL ends it at once, and what it held in memory is lost. Undo starts it again.");
        k.alternate = YES;
        [out addObject:k];
    }
    if (!protect) Keep(out, f, YES);
    NSUInteger third = out.count;
    if (agent) {
        MMWindowMenuItem *a = Item(@"show-row", @"Show Agent", nil);
        a.link = agent;
        [out addObject:a];
    }
    Reveal(out, Str(f.facts[@"cwd"]) ?: f.path);
    Starts(out, second); Starts(out, third);
    return out;
}

/// An agent: Go to where it runs, its worktree's row and its folder, then Copy Session ID.
static NSArray<MMWindowMenuItem *> *AgentMenu(MMFinding *f, MMWindowRow *row, NSString *worktree) {
    NSMutableArray *out = [NSMutableArray new];
    if (row.goTo.length) [out addObject:Item(@"go-to", [@"Go to " stringByAppendingString:row.goTo], nil)];
    if (worktree) {
        MMWindowMenuItem *w = Item(@"show-row", @"Show Worktree", nil);
        w.link = worktree;
        [out addObject:w];
    }
    NSString *project = Str(f.facts[@"project"]);
    Reveal(out, [project isEqualToString:NSHomeDirectory()] ? nil : project);
    NSUInteger second = out.count;
    NSString *stable = f.stableKey ?: @"";
    NSRange colon = [stable rangeOfString:@":"];
    if (colon.location != NSNotFound && colon.location + 1 < stable.length) [out addObject:Item(@"copy-session", @"Copy Session ID", nil)];
    Starts(out, second);
    return out;
}

/// A worktree: Open in Finder, Open in Terminal, its pull request and Copy Branch Name, then Keep, Wrap Up and Remove.
/// Wrap Up stands only where Fix Everything's plan has it ready, and Remove only where the expert proposes it.
static NSArray<MMWindowMenuItem *> *WorktreeMenu(MMFinding *f, MMWindowRow *row, MMPerformance *p) {
    NSMutableArray *out = [NSMutableArray new];
    NSDictionary *x = f.facts;
    NSString *path = f.path ?: Str(x[@"path"]);
    if ([Num(x[@"missing"]) boolValue] || !path.length) return out;
    [out addObject:Item(@"open-folder", @"Open in Finder", nil)];
    [out addObject:Item(@"terminal", @"Open in Terminal", nil)];
    if (row.pull.opens) [out addObject:Item(@"open-pr", @"Open Pull Request", nil)];
    if (Str(x[@"branch"])) [out addObject:Item(@"copy-branch", @"Copy Branch Name", nil)];
    NSUInteger second = out.count;
    if (![Num(x[@"main"]) boolValue] && ![Num(x[@"protected"]) boolValue]) {
        Keep(out, f, NO);
        BOOL wrap = NO;
        for (MMPerformanceFix *fix in p.fixes) {
            MMWrapUpSubject *sub = fix.wrapUp.subject;
            if (sub && !fix.wrapUp.whyNot && ([sub.path isEqualToString:path] || [sub.worktree.path isEqualToString:path] || [sub.worktree.realPath isEqualToString:path])) wrap = YES;
        }
        if (wrap && !Kept(f))
            [out addObject:Item(@"wrap-up", @"Wrap Up", @"Stops what runs in it, moves its caches to the Trash and removes it, as one step Undo takes back.")];
        if (!Kept(f) && Offers(f, @"remove", MMStopTerm))
            [out addObject:Item(@"remove", @"Remove", @"git removes it and can bring it back. Its ignored files are saved first, and Undo restores it.")];
    }
    Starts(out, second);
    return out;
}

/// A cache: Show in Finder, then Move to Trash where it is free to go, and Keep.
static NSArray<MMWindowMenuItem *> *CacheMenu(MMFinding *f) {
    NSMutableArray *out = [NSMutableArray new];
    Reveal(out, f.path ?: Str(f.facts[@"path"]));
    NSUInteger second = out.count;
    BOOL free = [Str(f.facts[@"state"]) isEqualToString:@"free"] && !f.keepReasons.count && !Kept(f);
    if (free && Offers(f, @"trash", MMStopTerm)) [out addObject:Item(@"trash", @"Move to Trash", @"Undo moves it back.")];
    Keep(out, f, NO);
    Starts(out, second);
    return out;
}

void MMWindowMenusOn(MMWindowModel *m, MMSnapshot *s, MMPerformance *p) {
    NSArray<MMWindowGroup *> *groups = [m.memoryGroups ?: @[] arrayByAddingObjectsFromArray:m.diskGroups ?: @[]];
    // An agent's story links its worktree and its servers, so each server knows its agent from there.
    NSMutableDictionary<NSString *, NSString *> *agentOf = [NSMutableDictionary new], *treeOf = [NSMutableDictionary new];
    for (MMWindowGroup *g in groups) for (MMWindowRow *r in g.rows) {
        if (r.kind != MMWindowAgent) continue;
        for (MMWindowFact *fact in r.facts) {
            MMWindowRow *to = fact.link.length ? [m row:fact.link] : nil;
            if (!to.key.length) continue;
            if (to.kind == MMWindowServer && !agentOf[to.key]) agentOf[to.key] = r.key;
            if (to.kind == MMWindowWorktree && !treeOf[r.key]) treeOf[r.key] = to.key;
        }
    }
    for (MMWindowGroup *g in groups) for (MMWindowRow *r in g.rows) {
        // A row that stands for several has no one thing to act on, and a tabs row closes only with its Wrap Up.
        if (r.members || r.kind == MMWindowTabs) continue;
        MMPerformanceRow *pr = [p row:r.key];
        MMFinding *f = pr.finding ?: [s finding:pr.findingID ?: r.key];
        if (!f) continue;
        NSArray *items = nil;
        switch (r.kind) {
            case MMWindowApp: items = AppMenu(f, NO); break;
            case MMWindowHelper: items = AppMenu(f, YES); break;
            case MMWindowServer: items = ServerMenu(f, agentOf[r.key]); break;
            case MMWindowAgent: items = AgentMenu(f, r, treeOf[r.key]); break;
            case MMWindowWorktree: items = WorktreeMenu(f, r, p); break;
            case MMWindowCache: items = CacheMenu(f); break;
            case MMWindowTabs: case MMWindowSystem: break;   // the rest of the memory has no menu: macOS's processes are not MinMacs's to act on
        }
        r.menu = items.count ? items : nil;
    }
}
