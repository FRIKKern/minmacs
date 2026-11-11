// The removal choice, MMRemoval.h: the pref, the one decision, and the only place Act deletes a file.
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
    f.free = item.state == MMClutterFree; f.ownerGone = item.ownerGone;
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
- (NSDictionary *)json { return @{@"choice": MMRemovalChoiceName(self.choice), @"deleted": @(self.deleteNow), @"why": self.why ?: @""}; }
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
    if (!f.free) return @"cannot verify that nothing uses it";
    if (f.ownerGone) return @"its project is gone, so nothing can rebuild it";
    return nil;
}

MMRemovalDecision *MMRemovalDecideWith(MMRemovalChoice choice, MMRemovalThing thing, MMRemovalFacts *facts) {
    MMRemovalDecision *d = [MMRemovalDecision new];
    d.choice = choice; d.thing = thing;
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

MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts) {
    return MMRemovalDecideWith(MMRemovalChoiceNow(), thing, facts);
}

#pragma mark - Acting on it

void MMRemovalNote(MMUndoRecord *record, MMRemovalDecision *d, NSString *key) {
    if (!record || !d) return;
    NSMutableDictionary *r = [record.payload[@"removal"] isKindOfClass:NSDictionary.class] ? [record.payload[@"removal"] mutableCopy] : [NSMutableDictionary new];
    if (key.length) r[key] = d.json; else [r addEntriesFromDictionary:d.json];
    if (!r[@"choice"]) r[@"choice"] = MMRemovalChoiceName(d.choice);
    [MMUndo.shared note:record payload:@{@"removal": r}];
}

/// path with every symlink above it resolved, and its own last name kept, so a link is named and never followed.
static NSString *RealParent(NSString *path) {
    NSString *std = path.stringByStandardizingPath;
    if (std.length <= 1) return std;
    char buf[PATH_MAX];
    if (!realpath(std.stringByDeletingLastPathComponent.fileSystemRepresentation, buf)) return nil;
    return [@(buf) stringByAppendingPathComponent:std.lastPathComponent];
}
static NSString *Real(NSString *path) {
    char buf[PATH_MAX];
    return path.length && realpath(path.fileSystemRepresentation, buf) ? @(buf) : nil;
}
static BOOL Holds(NSString *folder, NSString *path) {
    return folder.length && path.length && ([path isEqualToString:folder] || [path hasPrefix:[folder isEqualToString:@"/"] ? @"/" : [folder stringByAppendingString:@"/"]]);
}

/// Why this path is never deleted, whatever asked, or nil.
static NSString *DeleteWall(NSString *path) {
    if (![path hasPrefix:@"/"]) return @"it has no full path";
    NSString *p = RealParent(path);
    if (!p.length) return @"its folder cannot be read";
    if (p.pathComponents.count < 3) return @"it is too near the top of the disk";
    NSString *home = Real(NSHomeDirectory()), *support = Real(MMSupportDir());
    if (Holds(p, home)) return @"it holds the home folder";
    if (Holds(p, support)) return @"it holds MinMacs's own folder";
    NSString *test = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (test.length) {
        NSString *root = Real(test);
        if (!root || !Holds(root, p) || [p isEqualToString:root]) return @"it is outside MINMACS_HOME, and a check deletes only its own fixtures";
    }
    return nil;
}

static NSError *Problem(NSString *words) {
    return [NSError errorWithDomain:@"no.guerrilla.minmacs.removal" code:1 userInfo:@{NSLocalizedDescriptionKey: words}];
}

BOOL MMRemovalApply(NSURL *item, MMRemovalDecision *d, MMUndoRecord *record, NSError **error) {
    if (!item.path.length || !d || !record) { if (error) *error = Problem(@"cannot verify what to remove"); return NO; }
    if (!d.deleteNow) return [MMUndo.shared trash:item record:record error:error] != nil;
    NSString *path = item.path;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) { if (error) *error = Problem(@"it is gone"); return NO; }
    NSString *wall = DeleteWall(path);
    if (wall) { if (error) *error = Problem([@"MinMacs never deletes it: " stringByAppendingString:wall]); return NO; }
    NSError *e = nil;
    // NSFileManager removes a symlink itself and never what it points at.
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:path error:&e];
    BOOL left = lstat(path.fileSystemRepresentation, &st) == 0;
    @synchronized (MMUndo.shared) {
        NSMutableArray *gone = [record.payload[@"deleted"] mutableCopy] ?: [NSMutableArray new];
        // A delete that stopped partway took some files, and the record says so.
        if (ok && !left) [gone addObject:@{@"path": path}];
        else [gone addObject:@{@"path": path, @"partial": @YES, @"error": e.localizedDescription ?: @"it could not be deleted"}];
        [MMUndo.shared note:record payload:@{@"deleted": gone}];
    }
    if (!ok && error) *error = e ?: Problem(@"it could not be deleted");
    return ok;
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
