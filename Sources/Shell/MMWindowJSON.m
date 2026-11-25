// The window's model as JSON, MMWindowJSON.h.
#import "Shell/MMWindowJSON.h"

static id Or(id v) { return v ?: NSNull.null; }
static NSString *SideName(MMWindowSide s) { return s == MMWindowDisk ? @"disk" : @"memory"; }
static NSArray *All(NSArray *objects) {
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:objects.count];
    for (id o in objects) [a addObject:[o json]];
    return a;
}

NSString *MMWindowKindName(MMWindowKind kind) {
    switch (kind) {
        case MMWindowServer: return @"server";
        case MMWindowAgent: return @"agent";
        case MMWindowApp: return @"app";
        case MMWindowHelper: return @"helper";
        case MMWindowTabs: return @"tabs";
        case MMWindowWorktree: return @"worktree";
        case MMWindowCache: return @"cache";
    }
    return @"app";
}

@implementation MMWindowHour (MMJSON)
- (NSDictionary *)json { return @{@"title": self.title, @"explain": self.explain, @"side": SideName(self.side), @"values": self.values}; }
@end

@implementation MMWindowFact (MMJSON)
- (NSDictionary *)json {
    if (!self.link.length) return @{@"label": self.label ?: @"", @"value": self.value ?: @""};
    return @{@"label": self.label ?: @"", @"value": self.value ?: @"", @"link": self.link};
}
@end

@implementation MMWindowPull (MMJSON)
- (NSDictionary *)json {
    NSString *known = self.known == MMWindowPullLooking ? @"looking" : self.known == MMWindowPullNone ? @"none" : @"found";
    return @{@"known": known, @"line": self.line, @"number": self.number > 0 ? @(self.number) : NSNull.null, @"state": Or(self.state),
             @"draft": @(self.draft), @"review": Or(self.review), @"title": Or(self.title), @"url": Or(self.url), @"milestone": Or(self.milestone),
             @"checks": @{@"passing": @(self.checksPassing), @"failing": @(self.checksFailing), @"pending": @(self.checksPending)}};
}
@end

@implementation MMWindowRow (MMJSON)
- (NSDictionary *)json {
    NSDictionary *j = @{@"key": self.key, @"kind": MMWindowKindName(self.kind), @"iconHint": Or(self.iconHint), @"name": self.name,
             @"state": Or(self.state), @"cpuPercent": self.cpuPercent >= 0 ? @(round(self.cpuPercent * 10) / 10) : NSNull.null,
             // A size not measured yet is null, never 0.
             @"bytes": self.unmeasured ? NSNull.null : @(self.bytes), @"measured": self.unmeasured ? @NO : @YES, @"tabs": @(self.tabs), @"needsYou": @(self.needsYou), @"inFix": @(self.inFix), @"quiet": @(self.quiet),
             @"hour": Or(self.hour), @"facts": All(self.facts), @"project": Or(self.project), @"workedAt": self.workedAt > 0 ? @(self.workedAt) : NSNull.null};
    if (self.pull) {
        NSMutableDictionary *x = [j mutableCopy];
        x[@"pullRequest"] = self.pull.json;
        j = x;
    }
    if (self.goTo.length) { NSMutableDictionary *g = [j mutableCopy]; g[@"goTo"] = self.goTo; j = g; }
    // Its right-click menu, as the window offers it: what each item does, its title, and an Option alternate.
    if (self.menu.count) {
        NSMutableArray *items = [NSMutableArray new];
        for (MMWindowMenuItem *i in self.menu) {
            NSMutableDictionary *it = [@{@"action": i.action, @"title": i.title, @"alternate": @(i.alternate)} mutableCopy];
            if (i.link) it[@"link"] = i.link;
            [items addObject:it];
        }
        NSMutableDictionary *g = [j mutableCopy]; g[@"menu"] = items; j = g;
    }
    if (!self.members) return j;
    // A row that stands for several, DESIGN rule 16, says so and holds each member whole, as the rows it stands for.
    NSMutableDictionary *x = [j mutableCopy];
    // inside: the members that lie inside another member, whose size is in that one's and is not counted again.
    NSInteger inside = 0;
    for (MMWindowRow *m in self.members) if (m.kin.within) inside++;
    x[@"collapsed"] = @{@"count": @(self.members.count), @"inside": @(inside), @"kin": self.kin.key ?: @"", @"members": All(self.members)};
    return x;
}
@end

@implementation MMWindowGroup (MMJSON)
- (NSDictionary *)json { return @{@"key": self.key, @"title": self.title, @"side": SideName(self.side), @"rows": All(self.rows),
                                 @"emptyNote": Or(self.emptyNote), @"byProject": @(self.byProject)}; }
@end

@implementation MMWindowRing (MMJSON)
- (NSDictionary *)json {
    NSArray *(^slices)(NSArray<MMWindowSlice *> *) = ^(NSArray<MMWindowSlice *> *in) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMWindowSlice *s in in) [a addObject:@{@"group": s.group ?: @"", @"bytes": @(s.bytes)}];
        return a;
    };
    return @{@"memory": @{@"used": @(self.memoryUsed), @"total": @(self.memoryTotal), @"slices": slices(self.memory)},
             @"disk": @{@"free": @(self.diskFree), @"total": @(self.diskTotal), @"slices": slices(self.disk)}};
}
@end

@implementation MMWindowFix (MMJSON)
- (NSDictionary *)json {
    return @{@"key": self.key ?: @"", @"title": self.title ?: @"", @"memoryBack": @(self.memoryBack), @"diskBack": @(self.diskBack),
             @"diskBackPartial": @(self.diskPartial), @"needsYou": @(self.needsYou)};
}
@end

@implementation MMWindowRun (MMJSON)
- (NSDictionary *)json {
    return @{@"running": @(self.running), @"step": Or(self.step), @"done": @(self.done), @"total": @(self.total),
             @"memoryBack": @(self.memoryBack), @"diskBack": @(self.diskBack), @"memoryPlanned": @(self.memoryPlanned),
             @"diskPlanned": @(self.diskPlanned), @"diskPlannedPartial": @(self.diskPlannedPartial),
             @"endTitle": Or(self.endTitle), @"endNote": Or(self.endNote)};
}
@end

@implementation MMWindowSettings (MMJSON)
- (NSDictionary *)json {
    NSMutableArray *rules = [NSMutableArray new], *switches = [NSMutableArray new];
    for (MMWindowRule *r in self.rules) {
        NSMutableArray *choices = [NSMutableArray new];
        for (MMWindowChoice *c in r.choices) [choices addObject:@{@"title": c.title ?: @"", @"explain": c.explain ?: @""}];
        [rules addObject:@{@"ruleID": r.ruleID, @"title": r.title, @"choices": choices, @"picked": @(r.picked), @"note": Or(r.note)}];
    }
    for (MMWindowSwitch *s in self.switches)
        [switches addObject:@{@"switchID": s.switchID ?: @"", @"title": s.title ?: @"", @"on": @(s.on), @"inert": @(s.inert), @"note": Or(s.note),
                                @"help": Or(s.help)}];
    return @{@"rules": rules, @"switches": switches, @"startsIn": Or(self.startsIn)};
}
@end

@implementation MMWindowModel (MMJSON)
- (NSDictionary *)json {
    return @{@"generation": @(self.generation), @"asks": Or(self.asks),
             @"memoryHour": Or(self.memoryHour.json), @"diskHour": Or(self.diskHour.json),
             @"memory": All(self.memoryGroups), @"disk": All(self.diskGroups), @"ring": self.ring.json,
             @"fixes": All(self.fixes),
             @"fixEverything": @{@"fixes": @(self.fixCount), @"memoryBack": @(self.memoryBack), @"diskBack": @(self.diskBack),
                                  @"diskBackPartial": @(self.diskBackPartial)},
             @"backToday": @{@"memoryBack": @(self.memoryBackToday), @"diskBack": @(self.diskBackToday),
                              @"diskBackPartial": @(self.diskBackTodayPartial)},
             @"run": Or(self.run.json), @"settings": self.settings.json};
}
@end
