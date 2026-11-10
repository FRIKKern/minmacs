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
- (NSDictionary *)json { return @{@"label": self.label ?: @"", @"value": self.value ?: @""}; }
@end

@implementation MMWindowRow (MMJSON)
- (NSDictionary *)json {
    return @{@"key": self.key, @"kind": MMWindowKindName(self.kind), @"iconHint": Or(self.iconHint), @"name": self.name,
             @"state": Or(self.state), @"cpuPercent": self.cpuPercent >= 0 ? @(round(self.cpuPercent * 10) / 10) : NSNull.null,
             @"bytes": @(self.bytes), @"tabs": @(self.tabs), @"needsYou": @(self.needsYou), @"inFix": @(self.inFix),
             @"hour": Or(self.hour), @"facts": All(self.facts)};
}
@end

@implementation MMWindowGroup (MMJSON)
- (NSDictionary *)json { return @{@"key": self.key, @"title": self.title, @"side": SideName(self.side), @"rows": All(self.rows)}; }
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
             @"needsYou": @(self.needsYou)};
}
@end

@implementation MMWindowRun (MMJSON)
- (NSDictionary *)json {
    return @{@"running": @(self.running), @"step": Or(self.step), @"done": @(self.done), @"total": @(self.total),
             @"memoryBack": @(self.memoryBack), @"diskBack": @(self.diskBack), @"memoryPlanned": @(self.memoryPlanned),
             @"diskPlanned": @(self.diskPlanned), @"endTitle": Or(self.endTitle), @"endNote": Or(self.endNote)};
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
        [switches addObject:@{@"switchID": s.switchID ?: @"", @"title": s.title ?: @"", @"on": @(s.on), @"note": Or(s.note)}];
    return @{@"rules": rules, @"switches": switches};
}
@end

@implementation MMWindowModel (MMJSON)
- (NSDictionary *)json {
    return @{@"generation": @(self.generation), @"asks": Or(self.asks),
             @"memoryHour": Or(self.memoryHour.json), @"diskHour": Or(self.diskHour.json),
             @"memory": All(self.memoryGroups), @"disk": All(self.diskGroups), @"ring": self.ring.json,
             @"fixes": All(self.fixes),
             @"fixEverything": @{@"fixes": @(self.fixCount), @"memoryBack": @(self.memoryBack), @"diskBack": @(self.diskBack)},
             @"run": Or(self.run.json), @"settings": self.settings.json};
}
@end
