// The removal choice, MMRemoval.h: the pref, the one decision and what a record says of it.
// The wall and the only place Act deletes a file are in MMRemovalApply.m.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <sys/stat.h>

NSString *const MMRemovalKey = @"core.removal";

static NSArray<NSString *> *Names(void) { return @[@"smart", @"trash", @"delete"]; }

NSString *MMRemovalChoiceName(MMRemovalChoice c) { return c >= 0 && c < (NSInteger)Names().count ? Names()[(NSUInteger)c] : @"trash"; }

NSInteger MMRemovalChoiceFrom(NSString *name) {
    NSUInteger i = [name isKindOfClass:NSString.class] ? [Names() indexOfObject:name.lowercaseString] : NSNotFound;
    return i == NSNotFound ? -1 : (NSInteger)i;
}

MMRemovalChoice MMRemovalChoiceNow(void) {
    id v = MMPref(MMRemovalKey);
    if (!v) return MMRemovalSmart;
    // A value nobody can read must not delete anything, so it counts as the Trash.
    NSInteger c = MMRemovalChoiceFrom(v);
    return c < 0 ? MMRemovalTrash : (MMRemovalChoice)c;
}

void MMSetRemovalChoice(MMRemovalChoice c) { MMSetPref(MMRemovalKey, MMRemovalChoiceName(c)); }

BOOL MMRemovalChosen(void) { return MMPref(MMRemovalKey) != nil; }

NSString *MMRemovalNotChosenNote(void) {
    return MMRemovalChosen() ? nil : @"Not chosen yet. Until you pick one, what MinMacs removes on its own goes to the Trash.";
}

NSString *MMRemovalChoiceTitle(MMRemovalChoice c) { return @[@"Smart", @"Trash", @"Delete"][(NSUInteger)MAX(0, MIN(2, c))]; }

NSString *MMRemovalChoiceExplain(MMRemovalChoice c) {
    return @[@"Deletes what git or its tool can give back. The rest goes to the Trash.",
             @"Everything goes to the Trash. The disk comes back when you empty it.",
             @"Deletes everything it removes at once. Nothing can be brought back."][(NSUInteger)MAX(0, MIN(2, c))];
}

#pragma mark - Facts

@implementation MMRemovalFacts

- (instancetype)init {
    // Nothing is known yet: every count is unknown, and no flag says it may go.
    if ((self = [super init])) { _dirty = _untracked = _unpushed = _stashes = -1; _klass = MMClutterLeak; }
    return self;
}

+ (instancetype)worktreeKnown:(BOOL)known merged:(BOOL)merged upstreamGone:(BOOL)gone dirty:(NSInteger)dirty
                    untracked:(NSInteger)untracked unpushed:(NSInteger)unpushed stashes:(NSInteger)stashes {
    MMRemovalFacts *f = [MMRemovalFacts new];
    f.gitKnown = known; f.merged = merged; f.upstreamGone = gone;
    f.dirty = dirty; f.untracked = untracked; f.unpushed = unpushed; f.stashes = stashes;
    return f;
}

+ (instancetype)clutter:(MMClutterItem *)item {
    MMRemovalFacts *f = [MMRemovalFacts new];
    if (!item.kind) return f;
    f.klass = item.kind.klass; f.rebuilt = item.kind.rebuilt;
    f.free = item.state == MMClutterFree; f.ownerGone = item.ownerGone; f.unproven = item.unproven;
    return f;
}

@end

#pragma mark - The decision

@interface MMRemovalDecision ()
@property (readwrite) MMRemovalChoice choice;
@property (readwrite) MMRemovalThing thing;
@property (readwrite) BOOL deleteNow;
@property (readwrite, copy) NSString *why;
@end

@implementation MMRemovalDecision
/// "deleted" starts NO. MMRemovalDone turns it into "wants" once the thing is gone.
- (NSDictionary *)json { return @{@"choice": MMRemovalChoiceName(self.choice), @"wants": self.deleteNow ? @YES : @NO, @"deleted": @NO, @"why": self.why ?: @""}; }
@end

static NSString *Count(NSInteger n, NSString *one, NSString *many) { return [NSString stringWithFormat:@"%ld %@", (long)n, n == 1 ? one : many]; }

/// Why Smart keeps a way back for this worktree, or nil when git can give all of it back.
static NSString *WorktreeKeeps(MMRemovalFacts *f) {
    if (!f || !f.gitKnown) return @"cannot verify its git facts";
    if (f.dirty < 0 || f.untracked < 0 || f.unpushed < 0 || f.stashes < 0) return @"cannot verify what git holds of it";
    if (f.dirty > 0) return [Count(f.dirty, @"change is", @"changes are") stringByAppendingString:@" not committed"];
    if (f.untracked > 0) return [Count(f.untracked, @"untracked file is", @"untracked files are") stringByAppendingString:@" not in git"];
    if (f.unpushed > 0) return [Count(f.unpushed, @"commit is", @"commits are") stringByAppendingString:@" on no remote"];
    if (f.stashes > 0) return [NSString stringWithFormat:@"it has %@", Count(f.stashes, @"stash", @"stashes")];
    if (!f.merged && !f.upstreamGone) return @"its branch is not merged and its remote branch still exists";
    return nil;
}

/// Why Smart keeps a way back for this clutter, or nil when its tool rebuilds it.
static NSString *ClutterKeeps(MMRemovalFacts *f) {
    if (!f) return @"cannot verify what it is";
    if (f.klass == MMClutterLeak) return @"it is a leftover, and nothing rebuilds a leftover";
    if (f.klass != MMClutterCache && f.klass != MMClutterBuild) return @"its row is neither a cache nor build output";
    if (!f.rebuilt) return @"its row does not say that a tool rebuilds it";
    if (f.unproven.length) return f.unproven;
    if (!f.free) return @"cannot verify that nothing uses it";
    if (f.ownerGone) return @"its project is gone, so nothing can rebuild it";
    return nil;
}

/// YES for an act MinMacs starts on its own: a mode or an expert's own rule. A press, the CLI and words shown before
/// anybody acts are the person's.
static BOOL OnItsOwn(NSString *by) { return by.length && ![by isEqualToString:@"manual"] && ![by isEqualToString:@"cli"]; }

MMRemovalDecision *MMRemovalDecideWith(MMRemovalChoice choice, MMRemovalThing thing, MMRemovalFacts *facts) {
    return MMRemovalDecideAs(choice, YES, nil, thing, facts);
}

MMRemovalDecision *MMRemovalDecideAs(MMRemovalChoice choice, BOOL chosen, NSString *by, MMRemovalThing thing, MMRemovalFacts *facts) {
    MMRemovalDecision *d = [MMRemovalDecision new];
    d.choice = choice; d.thing = thing;
    // Nobody was asked yet, so what MinMacs does unasked loses nothing, whatever the default would allow.
    if (!chosen && OnItsOwn(by)) { d.deleteNow = NO; d.why = @"you have not chosen what happens to removed things yet, so a way back is kept"; return d; }
    if (choice == MMRemovalDelete) { d.deleteNow = YES; d.why = @"you chose Delete, so it is deleted at once"; return d; }
    if (choice != MMRemovalSmart) { d.deleteNow = NO; d.why = @"you chose the Trash, so a way back is kept"; return d; }
    NSString *keeps = nil;
    switch (thing) {
        case MMRemovalWorktree:
            keeps = WorktreeKeeps(facts);
            if (!keeps) d.why = facts.merged ? @"its branch is merged and every commit is on a remote, so git can give it back"
                                             : @"its remote branch is gone and every commit is on a remote, so git can give it back";
            break;
        case MMRemovalIgnoredFiles: keeps = @"git does not hold the files it ignores"; break;
        case MMRemovalConfigFiles: keeps = @"git does not hold untracked files"; break;
        case MMRemovalClutter:
            keeps = ClutterKeeps(facts);
            if (!keeps) d.why = @"its tool rebuilds it";
            break;
        case MMRemovalToolCopy:
            if (!facts || facts.klass != MMClutterTool) keeps = @"cannot verify that a tool owns it";
            else if (!facts.rebuilt) keeps = @"its row does not say that the tool fetches it again";
            else d.why = @"its tool fetches it again";
            break;
        default: keeps = @"cannot verify what it is"; break;
    }
    d.deleteNow = keeps == nil;
    if (keeps) d.why = keeps;
    return d;
}

MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts, NSString *by) {
    return MMRemovalDecideAs(MMRemovalChoiceNow(), MMRemovalChosen(), by, thing, facts);
}

#pragma mark - The record

void MMRemovalNote(MMUndoRecord *record, MMRemovalDecision *d, NSString *key) {
    if (!record || !d) return;
    NSMutableDictionary *r = [record.payload[@"removal"] isKindOfClass:NSDictionary.class] ? [record.payload[@"removal"] mutableCopy] : [NSMutableDictionary new];
    if (key.length) r[key] = d.json; else [r addEntriesFromDictionary:d.json];
    if (!r[@"choice"]) r[@"choice"] = MMRemovalChoiceName(d.choice);
    [MMUndo.shared note:record payload:@{@"removal": r}];
}

void MMRemovalAsk(MMUndoRecord *record, NSArray<NSString *> *paths) {
    if (!record || !paths.count) return;
    NSMutableArray *asked = [record.payload[@"asked"] isKindOfClass:NSArray.class] ? [record.payload[@"asked"] mutableCopy] : [NSMutableArray new];
    for (NSString *p in paths) if (![asked containsObject:p]) [asked addObject:p];
    [MMUndo.shared note:record payload:@{@"asked": asked}];
}

void MMRemovalDone(MMUndoRecord *record, NSString *key) {
    NSDictionary *was = record.payload[@"removal"];
    if (![was isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *r = [was mutableCopy];
    NSMutableDictionary *one = key.length ? ([r[key] isKindOfClass:NSDictionary.class] ? [r[key] mutableCopy] : nil) : r;
    if (!one) return;
    BOOL wants = [one[@"wants"] isKindOfClass:NSNumber.class] && [one[@"wants"] boolValue];
    // What a Wrap Up part wanted deleted waits in the Trash until the whole Wrap Up went through.
    BOOL staged = !key.length && [record.payload[@"staged"] isKindOfClass:NSArray.class] && [record.payload[@"staged"] count];
    if (staged) one[@"staged"] = @YES; else one[@"deleted"] = wants ? @YES : @NO;
    if (key.length) r[key] = one;
    [MMUndo.shared note:record payload:@{@"removal": r}];
}

#pragma mark - Where things went

NSString *MMRemovalWhereWords(NSArray<MMUndoRecord *> *records) {
    NSInteger deleted = 0, trashed = 0, kept = 0;
    for (MMUndoRecord *r in records) {
        if (r.state != MMUndoDone && r.state != MMUndoRestored) continue;
        BOOL removes = [r.kind isEqualToString:@"remove"] || [r.kind isEqualToString:@"trash"] || [r.kind isEqualToString:@"clean"];
        if (!removes) continue;
        NSDictionary *p = r.payload;
        if ([p[@"trashed"] isKindOfClass:NSArray.class] && [p[@"trashed"] count]) trashed++;
        else if (r.deletedNow) deleted++;
        else kept++;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    if (deleted) [parts addObject:[NSString stringWithFormat:@"deleted %ld", (long)deleted]];
    if (trashed) [parts addObject:[NSString stringWithFormat:@"moved %ld to the Trash", (long)trashed]];
    if (kept) [parts addObject:[NSString stringWithFormat:@"removed %ld that Restore brings back", (long)kept]];
    if (!parts.count) return nil;
    NSString *list = parts.count < 3 ? [parts componentsJoinedByString:@", "]
        : [NSString stringWithFormat:@"%@, %@ and %@", parts[0], parts[1], parts[2]];
    return [NSString stringWithFormat:@"%@%@.", [list substringToIndex:1].uppercaseString, [list substringFromIndex:1]];
}
