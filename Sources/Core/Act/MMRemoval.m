// Removal, MMRemoval.h: the old pref, the one decision and what a record says of it.
// The wall and the only place Act deletes a file are in MMRemovalApply.m.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <sys/stat.h>

NSString *const MMRemovalKey = @"core.removal";

MMRemovalChoice MMRemovalChoiceNow(void) { return MMRemovalTrash; }

NSString *MMRemovalChoiceName(MMRemovalChoice c) { return @"trash"; }

NSString *MMRemovalExplain(void) {
    return @"Everything MinMacs removes keeps a way back: a worktree through git, the rest in the Trash or a recovery folder. MinMacs never deletes anything at once and never empties the Trash.";
}

BOOL MMRemovalForgetOldChoice(void) {
    if (!MMPref(MMRemovalKey)) return NO;
    MMSetPref(MMRemovalKey, nil);
    return YES;
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
/// A decision that deletes is only the checks' seam, as an older MinMacs's Delete made it, so it says "delete".
- (NSDictionary *)json { return @{@"choice": self.deleteNow ? @"delete" : MMRemovalChoiceName(self.choice), @"wants": self.deleteNow ? @YES : @NO, @"deleted": @NO, @"why": self.why ?: @""}; }
@end

static NSString *Count(NSInteger n, NSString *one, NSString *many) { return [NSString stringWithFormat:@"%ld %@", (long)n, n == 1 ? one : many]; }

NSString *MMRemovalGitWhyNot(MMRemovalFacts *f) {
    if (!f || !f.gitKnown) return @"cannot verify its git facts";
    if (f.dirty < 0 || f.untracked < 0 || f.unpushed < 0 || f.stashes < 0) return @"cannot verify what git holds of it";
    if (f.dirty > 0) return [Count(f.dirty, @"change is", @"changes are") stringByAppendingString:@" not committed"];
    if (f.untracked > 0) return [Count(f.untracked, @"untracked file is", @"untracked files are") stringByAppendingString:@" not in git"];
    if (f.unpushed > 0) return [Count(f.unpushed, @"commit is", @"commits are") stringByAppendingString:@" on no remote"];
    if (f.stashes > 0) return [NSString stringWithFormat:@"it has %@", Count(f.stashes, @"stash", @"stashes")];
    if (!f.merged && f.upstreamUnknown) return @"its branch is not merged and its remote branch could not be read";
    if (!f.merged && !f.upstreamGone) return f.upstreamNone ? @"its branch is not merged and it tracks no remote branch"
                                                            : @"its branch is not merged and its remote branch still exists";
    return nil;
}

MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts, NSString *by) {
    MMRemovalDecision *d = [MMRemovalDecision new];
    d.choice = MMRemovalTrash; d.thing = thing; d.deleteNow = NO;
    switch (thing) {
        case MMRemovalWorktree: {
            // git worktree remove takes the folder. What git holds comes back through git, and the record says so.
            NSString *no = MMRemovalGitWhyNot(facts);
            d.why = !no ? (facts.merged ? @"git can give it back: its branch is merged and every commit is on a remote"
                                        : @"git can give it back: its remote branch is gone and every commit is on a remote")
                        : [@"a way back is kept, since " stringByAppendingString:no];
            break;
        }
        case MMRemovalIgnoredFiles: d.why = @"git does not hold the files it ignores, so they go to the recovery folder"; break;
        case MMRemovalToolCopy: d.why = @"a recovery copy is kept, so Restore copies back what the tool removed"; break;
        default: d.why = @"it goes to the Trash, so Restore moves it back"; break;
    }
    return d;
}

#ifdef MM_TESTS
MMRemovalDecision *MMRemovalTestDeleteDecision(MMRemovalThing thing) {
    MMRemovalDecision *d = [MMRemovalDecision new];
    d.choice = MMRemovalTrash; d.thing = thing; d.deleteNow = YES; d.why = @"a check deletes it, as an older MinMacs did";
    return d;
}
#endif

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
    // What a Wrap Up part wanted deleted waits in MinMacs's staging folder until the whole Wrap Up went through.
    // What could not be staged stayed where it is, so the part deleted nothing.
    BOOL staged = !key.length && [record.payload[@"staged"] isKindOfClass:NSArray.class] && [record.payload[@"staged"] count];
    BOOL unstaged = !key.length && [record.payload[@"unstaged"] isKindOfClass:NSArray.class] && [record.payload[@"unstaged"] count];
    if (unstaged) one[@"unstaged"] = @YES;
    if (staged) one[@"staged"] = @YES; else one[@"deleted"] = wants && !unstaged ? @YES : @NO;
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
