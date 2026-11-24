// Near-identical rows as one, DESIGN rule 16, MMWindowModel.h. A Mac's temp folder can hold 169 families of empty
// folders that one registry row found, each a row that reads like the one above it. The window shows them as one row
// that says what they are and how many, and its story names the biggest. Plain values: no Core and no AppKit.
#import "UI/Window/MMWindowModel.h"

const NSInteger MMWindowCollapseLeast = 3;

@implementation MMWindowKin
- (instancetype)init { if ((self = [super init])) { _key = @""; _title = @""; _one = @"item"; _many = @"items"; } return self; }
@end

static BOOL Holds(NSString *outer, NSString *inner) {
    if (!outer.length || !inner.length || ![inner hasPrefix:outer]) return NO;
    return inner.length == outer.length || [inner characterAtIndex:outer.length] == '/' || [outer hasSuffix:@"/"];
}

/// Marks each member that lies inside another member by path, kin.within: what it holds is already in the size of
/// the one it lies in. The owner's Mac had Claude Code's scratch of 317 sessions and, inside one live session's folder,
/// 71 entries of its scratchpad, each a member of the same registry row, since a live session's old entries may go
/// on their own. Kept apart for that, 388 rows stood in Caches one by one. A member with no path holds no other.
static void MarkWithin(NSArray<MMWindowRow *> *members) {
    for (MMWindowRow *m in members) m.kin.within = NO;
    for (NSUInteger i = 0; i < members.count; i++) {
        NSString *a = members[i].kin.path;
        if (!a.length) continue;
        for (NSUInteger j = 0; j < members.count; j++) {
            NSString *b = members[j].kin.path;
            if (i == j || !b.length || !Holds(b, a)) continue;
            // Two members at one path are one place: the first stands for both.
            if ([a isEqualToString:b] && j > i) continue;
            members[i].kin.within = YES;
            break;
        }
    }
}

NSArray<MMWindowRow *> *MMWindowCollapsed(NSArray<MMWindowRow *> *rows) {
    NSMutableDictionary<NSString *, NSMutableArray<MMWindowRow *> *> *by = [NSMutableDictionary new];
    for (MMWindowRow *r in rows) {
        NSString *k = r.kin.key;
        if (!k.length || r.members) continue;
        if (!by[k]) by[k] = [NSMutableArray new];
        [by[k] addObject:r];
    }
    NSMutableDictionary<NSString *, MMWindowRow *> *one = [NSMutableDictionary new];
    for (NSString *k in by) if ((NSInteger)by[k].count >= MMWindowCollapseLeast) one[k] = MMWindowCollapsedRow(by[k]);
    if (!one.count) return rows;
    NSMutableArray<MMWindowRow *> *out = [NSMutableArray arrayWithCapacity:rows.count];
    NSMutableSet<NSString *> *placed = [NSMutableSet new];
    for (MMWindowRow *r in rows) {
        MMWindowRow *x = r.kin.key.length && !r.members ? one[r.kin.key] : nil;
        if (!x) { [out addObject:r]; continue; }
        if ([placed containsObject:r.kin.key]) continue;
        [placed addObject:r.kin.key];
        [out addObject:x];
    }
    return out;
}

/// The value of the fact of this label when every member has it alike, else nil.
static MMWindowFact *Shared(NSArray<MMWindowRow *> *members, NSString *label) {
    NSString *value = nil;
    for (MMWindowRow *m in members) {
        MMWindowFact *f = nil;
        for (MMWindowFact *x in m.facts) if ([x.label isEqualToString:label]) { f = x; break; }
        if (!f.value.length || (value && ![value isEqualToString:f.value])) return nil;
        value = f.value;
    }
    // The second line is the totals alone, so a shared fact is for the story only.
    return value ? [MMWindowFact label:label value:value] : nil;
}

MMWindowRow *MMWindowCollapsedRow(NSArray<MMWindowRow *> *given) {
    NSArray<MMWindowRow *> *members = [given sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
    MMWindowRow *first = members.firstObject;
    MMWindowKin *kin = first.kin;
    MMWindowRow *row = [MMWindowRow new];
    row.key = [@"kin:" stringByAppendingString:kin.key ?: @""];
    row.kind = first.kind; row.iconHint = first.iconHint; row.name = kin.title.length ? kin.title : first.name;
    MarkWithin(members);
    row.members = members;
    row.kin = kin;
    uint64_t bytes = 0;
    double cpu = -1;
    NSInteger inner = 0, go = 0, inUse = 0, kept = 0, other = 0, unmeasured = 0;
    BOOL quiet = YES, sameState = YES;
    NSMutableArray<NSString *> *why = [NSMutableArray new];
    // What lies inside another member is in that one's size and count already: it is counted with it, never again.
    NSInteger outer = 0;
    for (MMWindowRow *m in members) {
        if (m.inFix) row.inFix = YES;
        if (m.needsYou) row.needsYou = YES;
        if (m.kin.within) continue;
        outer++;
        if (m.unmeasured) unmeasured++; else bytes += m.bytes;
        if (m.cpuPercent >= 0) cpu = MAX(cpu, 0) + m.cpuPercent;
        if (!m.quiet) quiet = NO;
        if (!(m.state == first.state || [m.state isEqualToString:first.state])) sameState = NO;
        inner += MAX(m.kin.inner, 0);
        if (m.kin.canGo) go++;
        else {
            if ([m.state isEqualToString:@"in use"]) inUse++; else if ([m.state isEqualToString:@"kept"]) kept++; else other++;
            if (m.kin.why.length) [why addObject:m.kin.why];
        }
    }
    row.bytes = bytes; row.unmeasured = unmeasured == outer; row.cpuPercent = cpu; row.quiet = quiet;
    // One word for all: theirs when they share it. A member in use stops none of the others, so "in use" says that
    // some of it is, and the story says how many.
    BOOL anyInUse = NO, anyKept = NO;
    for (MMWindowRow *m in members) { if ([m.state isEqualToString:@"in use"]) anyInUse = YES; if ([m.state isEqualToString:@"kept"]) anyKept = YES; }
    row.state = sameState ? first.state : anyInUse ? @"in use" : anyKept ? @"kept" : nil;

    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    void (^add)(MMWindowFact *) = ^(MMWindowFact *f) { if (f) [facts addObject:f]; };
    add(MMWindowFactHolds(outer, kin.one, kin.many, inner, kin.innerOne, kin.innerMany));
    add(Shared(members, @"Kind"));
    add(Shared(members, @"Left by"));
    add(Shared(members, @"Folder"));
    add(MMWindowFactSplit(MMWindowCollapsedSplit(go, inUse, kept, other, kin.one, kin.many)));
    add(MMWindowFactWhyStay(why, go == 0));
    row.facts = facts;
    return row;
}
