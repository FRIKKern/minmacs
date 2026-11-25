// The rest of the memory in the window's model, MMWindowModel.h: a category's story lines with near-identical
// processes folded, its quiet words, and its slices of the ring. Plain values: no Core and no AppKit.
#import "UI/Window/MMWindowModel.h"
#import "UI/Window/MMWindowInsides.h"

NSString *const MMWindowRestGroup = @"rest", *const MMWindowRestTitle = @"macOS and background", *const MMWindowRestElseKey = @"rest:else";
const NSInteger MMWindowRestMostLines = 12;
const NSInteger MMWindowRestRingMost = 8;

#pragma mark - The facts of the rest

static MMWindowFact *Fact(NSString *label, NSString *value, NSString *phrase) {
    if (!value.length) return nil;
    MMWindowFact *f = [MMWindowFact label:label value:value];
    f.phrase = phrase;
    return f;
}

MMWindowFact *MMWindowFactRestCount(NSInteger n, NSInteger unmeasured) {
    if (n <= 0) return nil;
    NSString *value = unmeasured > 0 ? [NSString stringWithFormat:@"%ld, %ld that macOS runs as another user", (long)n, (long)unmeasured] : @(n).stringValue;
    return Fact(@"Processes", value, MMWindowRestCountWord(n));
}
MMWindowFact *MMWindowFactUnheld(uint64_t bytes) {
    if (!bytes) return nil;
    return Fact(@"In no process", [MMWindowSizeText(bytes, NO) stringByAppendingString:@", the kernel's own, wired and compressed memory, and what other users' processes hold"], nil);
}
MMWindowFact *MMWindowFactGrowth(NSString *growth) { return Fact(@"Lately", growth, growth); }
MMWindowFact *MMWindowFactRawName(NSString *raw) { return Fact(@"Process", raw, nil); }
MMWindowFact *MMWindowFactPid(int pid) { return pid > 0 ? Fact(@"Pid", @(pid).stringValue, nil) : nil; }
MMWindowFact *MMWindowFactPath(NSString *path) { return Fact(@"Path", path, nil); }
MMWindowFact *MMWindowFactParent(NSString *name, int pid) {
    if (!name.length) return nil;
    return Fact(@"Parent", pid > 0 ? [NSString stringWithFormat:@"%@, pid %d", name, pid] : name, nil);
}
MMWindowFact *MMWindowFactLaunchedBy(NSString *app) { return Fact(@"Launched by", app, app.length ? [@"for " stringByAppendingString:app] : nil); }
MMWindowFact *MMWindowFactOtherUser(void) { return Fact(@"Memory", @"not measured: macOS runs it as another user", nil); }

/// The words of a process's details, one per line, for its tooltip and for VoiceOver: "Pid 412", "Parent launchd, pid 1".
NSString *MMWindowRestDetailsText(MMWindowRow *proc) {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (MMWindowFact *f in proc.facts) [lines addObject:[NSString stringWithFormat:@"%@: %@", f.label, f.value]];
    return [lines componentsJoinedByString:@"\n"];
}

@implementation MMWindowRestList
- (instancetype)init { if ((self = [super init])) { _lines = @[]; } return self; }
@end

/// "Spotlight indexers" for a plain name of a person's words, the raw name as it is: "mdworker_shared".
static NSString *Many(NSString *name, BOOL plain) {
    if (!plain || !name.length || [name hasSuffix:@"s"]) return name;
    return [name stringByAppendingString:@"s"];
}

/// A process row is measured unless it is marked so: another user's process has no size to show.
static BOOL Measured(MMWindowRow *m) { return !m.unmeasured; }

MMWindowRestList *MMWindowRestListOf(MMWindowRow *category, NSInteger most) {
    MMWindowRestList *out = [MMWindowRestList new];
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<MMWindowRow *> *> *by = [NSMutableDictionary new];
    for (MMWindowRow *m in category.members) {
        if (!Measured(m)) { out.unmeasured++; continue; }
        NSString *k = m.shownName;
        if (!by[k]) { by[k] = [NSMutableArray new]; [order addObject:k]; }
        [by[k] addObject:m];
    }
    NSMutableArray<MMWindowRow *> *lines = [NSMutableArray new];
    for (NSString *k in order) {
        NSArray<MMWindowRow *> *same = by[k];
        // Two still read as two things; a third makes a list that repeats itself, DESIGN rule 16. A fold's own list,
        // which has no sentence of its own, lists each of its processes.
        if ((NSInteger)same.count < MMWindowCollapseLeast || !category.about.length) { [lines addObjectsFromArray:same]; continue; }
        MMWindowRow *one = [MMWindowRow new];
        MMWindowRow *first = same.firstObject;
        one.key = [NSString stringWithFormat:@"insides:%@|%@", category.key, k];
        one.kind = MMWindowSystem; one.iconHint = category.iconHint;
        // A plain name says its raw one in its first fact, Process; a raw name stays as it is.
        BOOL plain = [first.facts.firstObject.label isEqualToString:@"Process"];
        one.name = [NSString stringWithFormat:@"%lu %@", (unsigned long)same.count, Many(k, plain)];
        double cpu = -1;
        uint64_t bytes = 0;
        for (MMWindowRow *m in same) { bytes += m.bytes; if (m.cpuPercent >= 0) cpu = MAX(cpu, 0) + m.cpuPercent; }
        one.bytes = bytes; one.cpuPercent = cpu; one.members = same; one.quiet = cpu < 0.5;
        [lines addObject:one];
    }
    [lines sortUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
    NSInteger keep = MAX(0, MIN(most, (NSInteger)lines.count));
    out.lines = [lines subarrayWithRange:NSMakeRange(0, (NSUInteger)keep)];
    for (NSUInteger i = (NSUInteger)keep; i < lines.count; i++) {
        out.more += lines[i].members ? (NSInteger)lines[i].members.count : 1;
        out.moreBytes += lines[i].bytes;
    }
    return out;
}

NSString *MMWindowRestMoreLine(NSInteger more, uint64_t bytes) {
    if (more <= 0) return nil;
    return [NSString stringWithFormat:@"and %ld smaller, %@", (long)more, MMWindowSizeText(bytes, NO)];
}

NSString *MMWindowRestUnmeasuredLine(NSInteger n, BOOL more) {
    if (n <= 0) return nil;
    return [NSString stringWithFormat:@"%@%ld that macOS runs as another user, not measured", more ? @"and " : @"", (long)n];
}

NSString *MMWindowRestCountWord(NSInteger n) { return MMWindowCount(n, @"process", @"processes"); }

NSString *MMWindowRestGrowthWord(NSString *growth) {
    if (!growth.length) return nil;
    NSRange cut = [growth rangeOfString:@" this hour"];
    if (cut.location == NSNotFound) cut = [growth rangeOfString:@" in "];
    return cut.location == NSNotFound ? growth : [growth substringToIndex:cut.location];
}

NSString *MMWindowRestGrowth(NSArray *hour) {
    NSInteger first = -1, last = -1;
    for (NSInteger i = 0; i < (NSInteger)hour.count; i++) {
        if (![hour[(NSUInteger)i] isKindOfClass:NSNumber.class]) continue;
        if (first < 0) first = i;
        last = i;
    }
    // Ten minutes at least, so a moment's swing says nothing.
    if (first < 0 || last - first < 10) return nil;
    double a = [hour[(NSUInteger)first] doubleValue], b = [hour[(NSUInteger)last] doubleValue];
    if (b - a < 512.0 * 1048576 || b < a * 4 / 3) return nil;
    NSString *size = MMWindowSizeText((uint64_t)(b - a), NO);
    NSInteger span = last - first;
    return span >= 50 ? [NSString stringWithFormat:@"up %@ this hour", size] : [NSString stringWithFormat:@"up %@ in %ld min", size, (long)span];
}

NSArray<MMWindowSlice *> *MMWindowRestArcs(NSArray<MMWindowRow *> *rows) {
    NSMutableArray<MMWindowSlice *> *out = [NSMutableArray new];
    MMWindowSlice *last = nil;
    NSInteger room = MMWindowRestRingMost;
    BOOL hasElse = NO;
    for (MMWindowRow *r in rows) if ([r.key isEqualToString:MMWindowRestElseKey]) hasElse = YES;
    for (MMWindowRow *r in rows) {
        BOOL isElse = [r.key isEqualToString:MMWindowRestElseKey];
        // The last slice is Everything else's, which takes every category that has no room of its own.
        if (!isElse && (NSInteger)out.count < room - 1) {
            MMWindowSlice *s = [MMWindowSlice new];
            s.group = r.key; s.bytes = r.bytes;
            [out addObject:s];
            continue;
        }
        if (!last) { last = [MMWindowSlice new]; last.group = hasElse ? MMWindowRestElseKey : r.key; }
        last.bytes += r.bytes;
    }
    if (last) [out addObject:last];
    return out;
}

NSInteger MMWindowRestProcessCount(MMWindowRow *row) {
    NSInteger n = 0;
    for (MMWindowRow *m in row.members) if (![m.key hasSuffix:@"|unheld"]) n++;
    return n;
}

NSString *MMWindowRestSpoken(MMWindowRow *row) {
    NSInteger n = MMWindowRestProcessCount(row);
    return [NSString stringWithFormat:@"%@, %@, %@", row.name, MMWindowSizeText(row.bytes, NO), MMWindowRestCountWord(n)];
}

void MMWindowRestOpens(MMWindowRow *category) {
    MMWindowRestList *list = MMWindowRestListOf(category, MMWindowRestMostLines);
    NSMutableArray<MMWindowRow *> *kids = [NSMutableArray new];
    for (MMWindowRow *line in list.lines) {
        MMWindowRowSetDepth(line, 1); MMWindowRowSetParent(line, category.key);
        // A fold opens into the processes it stands for.
        if (line.members.count) {
            for (MMWindowRow *m in line.members) { MMWindowRowSetDepth(m, 2); MMWindowRowSetParent(m, line.key); }
            MMWindowRowSetInsides(line, line.members);
        }
        [kids addObject:line];
    }
    // What is left after the lines, as one quiet row: "40 smaller processes", with their size.
    if (list.more > 0) {
        MMWindowRow *more = [MMWindowRow new];
        more.key = [NSString stringWithFormat:@"insides:%@|smaller", category.key]; more.kind = MMWindowSystem; more.iconHint = category.iconHint;
        more.name = MMWindowCount(list.more, @"smaller process", @"smaller processes"); more.bytes = list.moreBytes; more.quiet = YES;
        MMWindowRowSetDepth(more, 1); MMWindowRowSetParent(more, category.key);
        [kids addObject:more];
    }
    if (kids.count) MMWindowRowSetInsides(category, kids);
}
