// The removal choice, MMRemoval.h: the wall and the only place Act deletes a file. What a Wrap Up stages, and how
// it is finished, put back and recovered after a crash, is below, since it deletes through the same one call.
// The real path of an item and the wall's places are in MMRemovalPath.m.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <sys/mount.h>
#include <sys/stat.h>

#pragma mark - The wall

static BOOL Holds(NSString *folder, NSString *path) {
    if (!folder.length || !path.length) return NO;
    return [path isEqualToString:folder] || [path hasPrefix:[folder isEqualToString:@"/"] ? @"/" : [folder stringByAppendingString:@"/"]];
}
/// The count of names in a real path: 0 for /, 2 for /Users/me.
static NSInteger Depth(NSString *path) { return [path isEqualToString:@"/"] ? 0 : (NSInteger)[path componentsSeparatedByString:@"/"].count - 1; }

NSString *MMRemovalWallWhyNot(NSString *path, NSArray<NSString *> *asked, MMRemovalPlaces *places) {
    if (![path hasPrefix:@"/"]) return @"it has no full path";
    for (NSString *c in [path componentsSeparatedByString:@"/"]) if ([c isEqualToString:@".."] || [c isEqualToString:@"."]) return @"its path is not a real path";
    if (path.length > 1 && [path hasSuffix:@"/"]) return @"its path is not a real path";
    if (!places) return @"cannot verify where it lies";
    NSString *(^as)(NSString *) = ^NSString *(NSString *s) { return places.foldCase ? s.lowercaseString : s; };
    NSString *p = as(path), *home = as(places.home ?: @""), *support = as(places.support ?: @""), *volume = as(places.volume ?: @"");
    // 1. Only what the fresh finding named.
    BOOL named = NO;
    for (NSString *a in asked) if ([as(a) isEqualToString:p]) named = YES;
    if (!named) return @"no fresh finding names it";
    // 2. Never a volume's root, the home folder, MinMacs's own folder, or anything that holds one of them.
    if (!volume.length || !home.length) return @"cannot verify where it lies";
    if ([p isEqualToString:@"/"] || [p isEqualToString:volume]) return @"it is the root of a volume";
    if (Holds(p, home)) return @"it holds the home folder";
    if (support.length && Holds(p, support)) return @"it holds MinMacs's own folder";
    // 5. A check deletes only its own fixtures.
    if (places.testHome) {
        NSString *test = as(places.testHome);
        if (!test.length || !Holds(test, p) || [p isEqualToString:test]) return @"it is outside MINMACS_HOME, and a check deletes only its own fixtures";
    }
    // 3. Inside the home folder: at least 2 levels down.
    if (Holds(home, p)) return Depth(p) - Depth(home) >= 2 ? nil : @"it is a folder at the top of the home folder";
    // 4. Anywhere else: at least 3 levels below the root of its own volume.
    if (!Holds(volume, p)) return @"cannot verify which volume holds it";
    return Depth(p) - Depth(volume) >= 3 ? nil : @"it is too near the top of its volume";
}

#pragma mark - The one place that deletes

static NSError *Problem(NSString *words) {
    return [NSError errorWithDomain:@"no.guerrilla.minmacs.removal" code:1 userInfo:@{NSLocalizedDescriptionKey: words}];
}

/// Why the item at path may not be deleted for this record, or nil. *real is its real path. allowed stands in for
/// the record's "asked" list when a Wrap Up deletes what it staged itself.
static NSString *WhyNot(NSString *path, MMUndoRecord *record, NSArray<NSString *> *allowed, NSString **real) {
    if (![path hasPrefix:@"/"]) return @"it has no full path";
    NSString *r = MMRemovalRealPath(path);
    struct stat st;
    // It is there, and nothing says where: its folder cannot be listed, or lists no one name for it. So it stays.
    if (!r) return lstat(path.fileSystemRepresentation, &st) == 0 ? @"MinMacs never deletes it: cannot verify where it lies" : @"it is gone";
    *real = r;
    NSMutableArray *asked = [NSMutableArray new];
    for (NSString *a in allowed ?: MMRecordStrings(record.payload, @"asked") ?: @[]) {
        NSString *x = MMRemovalRealPath(a);
        if (x) [asked addObject:x];
    }
    NSString *wall = MMRemovalWallWhyNot(r, asked, [MMRemovalPlaces placesFor:r]);
    return wall ? [@"MinMacs never deletes it: " stringByAppendingString:wall] : nil;
}

/// Unlinks the item at its real path. NSFileManager removes a symlink itself and never what it points at.
/// Every delete of a person's file in Act is this one call.
static BOOL Unlink(NSString *real, NSError **error) {
    NSError *e = nil;
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:real error:&e];
    if (!ok && error) *error = e ?: Problem(@"it could not be deleted");
    return ok;
}

static BOOL Stage(NSString *real, MMUndoRecord *record, NSError **error);

BOOL MMRemovalApply(NSString *path, MMRemovalDecision *d, MMUndoRecord *record, NSError **error) {
    if (!path.length || !d || !record) { if (error) *error = Problem(@"cannot verify what to remove"); return NO; }
    if (![path hasPrefix:@"/"]) { if (error) *error = Problem(@"it has no full path"); return NO; }
    if (!d.deleteNow) return [MMUndo.shared trash:[NSURL fileURLWithPath:path] record:record error:error] != nil;
    NSString *real = nil;
    NSString *why = WhyNot(path, record, nil, &real);
    if (why) { if (error) *error = Problem(why); return NO; }
    struct stat st;
    // A part of a Wrap Up: a later part may still refuse, so the item waits in a folder of MinMacs's own.
    if (record.parentRid.length) return Stage(real, record, error);
    NSError *e = nil;
    BOOL ok = Unlink(real, &e);
    BOOL left = lstat(real.fileSystemRepresentation, &st) == 0;
    @synchronized (MMUndo.shared) {
        NSMutableArray *gone = [MMRecordList(record.payload, @"deleted") mutableCopy] ?: [NSMutableArray new];
        // A delete that stopped partway took some files, and the record says so.
        if (ok && !left) [gone addObject:@{@"path": real}];
        else [gone addObject:@{@"path": real, @"partial": @YES, @"error": e.localizedDescription ?: @"it could not be deleted"}];
        [MMUndo.shared note:record payload:@{@"deleted": gone}];
    }
    if (!ok && error) *error = e ?: Problem(@"it could not be deleted");
    return ok;
}

#pragma mark - What a Wrap Up stages
//
//   a part wants a delete ──rename──▶ staging folder ──┬─ every part went through ──▶ deleted, folder removed
//   (MMRemovalApply)                  of MinMacs's own └─ a part refused, or MinMacs stopped ──rename──▶ back where it was
//
// The staging folder is on the item's own volume, so staging is one rename and never a copy:
//   <support>/staged/<wrap up rid>/                     for an item on the support folder's volume
//   <folder that holds the worktree>/.minmacs-staged-<wrap up rid>/     for an item on another volume
// It holds a file .minmacs with the rid, a .gitignore that hides the folder from a repo it may sit in, and its own
// list of items, .minmacs-items, written before an item moves in: MMRemovalStaging.m.
// Nothing waits in the person's Trash, and MinMacs deletes nothing there.
// An item is staged only when its staging folder would itself pass the wall. Otherwise it stays where it is.

static uint64_t FreeOn(NSString *path) {
    struct statfs s;
    return statfs(path.fileSystemRepresentation, &s) == 0 ? (uint64_t)s.f_bavail * s.f_bsize : 0;
}
BOOL MMRemovalTestHome(void) { return NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length > 0; }

/// YES when path is spelled as a real path is: full, with no "." or ".." name in it and no slash at its end.
static BOOL Spelled(NSString *path) {
    if (![path hasPrefix:@"/"] || (path.length > 1 && [path hasSuffix:@"/"])) return NO;
    for (NSString *c in [path componentsSeparatedByString:@"/"]) if ([c isEqualToString:@".."] || [c isEqualToString:@"."]) return NO;
    return YES;
}

NSString *MMRemovalStagedItemWhyNot(MMUndoRecord *r, NSString *stagedAt) {
    // Only a part of a Wrap Up stages, and only a Wrap Up that has a record says where its worktree was.
    if (!r.parentRid.length) return @"its record names no Wrap Up";
    MMUndoRecord *parent = [MMUndo.shared record:r.parentRid];
    if (!parent) return @"its Wrap Up has no record";
    if (!stagedAt.length || !Spelled(stagedAt)) return @"its path is not a real path";
    NSString *t = MMRemovalRealPath(stagedAt), *in = MMRecordString(r.payload, @"stagedIn");
    if (!t) return @"it is gone from the staging folder";
    // A record whose "stagedIn" cannot be read: the folder that holds the item now is asked the same questions.
    NSString *f = in ? MMRemovalRealPath(in) : t.stringByDeletingLastPathComponent;
    if (!f) return @"the record does not say where it was staged";
    NSString *support = MMRemovalRealPath(MMSupportDir());
    NSString *why = MMRemovalStagingWhyNot(t, f, r.parentRid, support);
    if (why) return why;
    if (!support.length || ![f isEqualToString:[[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:r.parentRid]]) {
        // The hidden folder is only ever made beside the Wrap Up's worktree, StagingFolder. One of that name anywhere
        // else was not made by MinMacs. The worktree may be gone by now, so the folder that held it is asked.
        NSString *tree = MMRecordString(parent.payload, @"path");
        NSString *holder = tree.length > 1 && Spelled(tree) ? MMRemovalRealPath([tree.stringByDeletingLastPathComponent stringByAppendingString:@"/."]) : nil;
        if (!holder || ![holder isEqualToString:f.stringByDeletingLastPathComponent]) return @"its folder is not beside the worktree of this Wrap Up";
    }
    if (!MMRemovalStagingMarkerSays(f, r.parentRid)) return @"its folder was not made by MinMacs for this Wrap Up";
    // The folder's own marker, .gitignore and list are no items, whoever names them.
    if (MMRemovalStagingOwnName(t.lastPathComponent)) return @"it is the staging folder's own file, not an item";
    // The folder's own list must say that this part staged this very file. A record alone never does.
    NSDictionary *bound = MMRecordDict(MMRemovalStagingItems(f), t.lastPathComponent);
    if (!bound) return @"its staging folder does not say that MinMacs staged it";
    if (![MMRecordString(bound, @"part") isEqualToString:r.rid]) return @"another part of the Wrap Up staged it";
    BOOL unread = NO;
    if (MMFileIsEntryCheck(t, bound, &unread) != 1)
        return unread ? @"its volume's UUID cannot be read now, so MinMacs cannot tell it is the file that was staged" : @"it is not the file that was staged";
    return nil;
}

NSString *MMRemovalStagedEntryWhyNot(MMUndoRecord *r, NSDictionary *x) {
    NSString *to = MMRecordString(x, @"to"), *from = MMRecordString(x, @"from");
    // An entry that does not say where its item was is named by -[MMUndo moveBack:from:], which moves nothing for it.
    if (!to.length || !from.length) return nil;
    if (!Spelled(from)) return @"its old path is not a real path";
    struct stat st;
    // Nothing waits there, so nothing would move: moveBack says whether it is back already or gone.
    if (lstat(to.fileSystemRepresentation, &st) != 0) return nil;
    NSString *why = MMRemovalStagedItemWhyNot(r, to);
    if (why) return why;
    // It goes back only to the old path the folder's own list holds for it, not to one a record names.
    NSString *t = MMRemovalRealPath(to);
    NSString *was = MMRecordString(MMRecordDict(MMRemovalStagingItems(t.stringByDeletingLastPathComponent), t.lastPathComponent), @"from");
    if (!was || ![was isEqualToString:from]) return @"the record names another old path than the one it was staged from";
    return nil;
}

/// Why the staged entry x of record r may not be deleted, or nil: the very file that was staged, MMFileIsEntry, in
/// the staging folder MinMacs made for this Wrap Up, MMRemovalStagedItemWhyNot. An entry that does not say which
/// file it is is never deleted. *real is its real path.
static NSString *StagedWhyNot(NSDictionary *x, MMUndoRecord *r, NSString **real) {
    NSString *to = MMRecordString(x, @"to"), *folder = MMRecordString(r.payload, @"stagedIn");
    if (!to || !folder) return @"the record does not say where it was staged";
    struct stat st;
    if (lstat(to.fileSystemRepresentation, &st) != 0) return @"it is gone";
    BOOL unread = NO;
    int same = MMFileIsEntryCheck(to, x, &unread);
    if (same < 0) return @"the record does not say which file was staged";
    if (same == 0) return unread ? @"its volume's UUID cannot be read now, so MinMacs cannot tell it is the file that was staged" : @"it is not the file that was staged";
    NSString *why = MMRemovalStagedItemWhyNot(r, to);
    if (why) return why;
    NSString *t = MMRemovalRealPath(to);
    if (!t) return @"it is gone";
    return WhyNot(t, r, @[t], real);
}

/// Removes the staging folder once it holds nothing but what MinMacs wrote there itself: its marker and its
/// .gitignore, each a plain file with MinMacs's own words, and its list of items, a plain file of ours. Never one that still holds a staged item, and never one
/// where something else took one of those two names.
void MMRemovalDropEmptyStagingFolder(NSString *folder, NSString *rid) {
    NSString *f = MMRemovalRealPath(folder);
    if (!f || MMRemovalStagingWhyNot([f stringByAppendingPathComponent:@".minmacs"], f, rid, MMRemovalRealPath(MMSupportDir())) || !MMRemovalStagingMarkerSays(f, rid)) return;
    if (!MMRemovalStagingOwnFilesAreOurs(f)) return;
    NSMutableSet *holds = [NSMutableSet new];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:f error:nil] ?: @[@"?"]) if (!MMRemovalStagingOwnName(name)) [holds addObject:name];
    if (holds.count == 0) Unlink(f, nil);
}

NSString *MMRemovalStagingFolderWhyNot(NSString *folder, MMRemovalPlaces *places) {
    // What would be deleted later is a file directly in the folder, so that path is what the wall is asked about now.
    NSString *item = [folder stringByAppendingPathComponent:@"0.item"];
    return MMRemovalWallWhyNot(item, @[item], places);
}

/// The staging folder for an item of this part, made now, on the item's own volume. nil with *why when there is none.
static NSString *StagingFolder(NSString *real, MMUndoRecord *record, NSString **why) {
    struct stat item, s;
    if (lstat(real.fileSystemRepresentation, &item) != 0) { *why = @"it is gone"; return nil; }
    NSString *rid = record.parentRid, *folder = nil;
    NSString *support = MMRemovalRealPath(MMSupportDir());
    // A check may ask for the folder beside the worktree, which a Mac with one volume would never use.
    BOOL beside = MMRemovalTestHome() && getenv("MINMACS_STAGE_BESIDE") != NULL;
    if (!beside && support && stat(support.fileSystemRepresentation, &s) == 0 && s.st_dev == item.st_dev)
        folder = [[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:rid];
    else {
        NSString *path = MMRecordString([MMUndo.shared record:rid].payload, @"path");
        NSString *tree = path ? MMRemovalRealPath(path) : nil;
        NSString *holder = tree.stringByDeletingLastPathComponent;
        if (holder.length > 1 && stat(holder.fileSystemRepresentation, &s) == 0 && s.st_dev == item.st_dev)
            folder = [holder stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:rid]];
    }
    if (!folder) { *why = @"no folder of MinMacs's own is on its volume"; return nil; }
    // The wall is asked now, before anything moves. A staging folder where MinMacs could never delete, such as one
    // beside a worktree at the top of a volume, would strand the item, so the item is not staged at all.
    NSString *wall = MMRemovalStagingFolderWhyNot(folder, [MMRemovalPlaces placesFor:real]);
    if (wall) { *why = [@"its staging folder would lie where MinMacs never deletes: " stringByAppendingString:wall]; return nil; }
    if (!MMRemovalStagingMake(folder, rid)) { *why = @"its staging folder could not be made"; return nil; }
    return folder;
}

/// The identity of the item at to when it is the very file held open since before the rename, else nil: the open
/// file says which id it has now, and the item at to must have that one.
static NSDictionary *HeldAt(int held, NSString *to) {
    struct stat h;
    NSDictionary *now = held >= 0 && fstat(held, &h) == 0 ? MMFileIdentity(to) : nil;
    if (!now || [now[@"ino"] unsignedLongLongValue] != (unsigned long long)h.st_ino || [now[@"dev"] longLongValue] != (long long)h.st_dev) return nil;
    return now;
}

/// One rename into the staging folder. When that cannot be, the item stays where it is, listed as "unstaged": it is
/// never copied and never deleted here, and the part goes on. git then takes it with the worktree or refuses.
static BOOL Stage(NSString *real, MMUndoRecord *record, NSError **error) {
    struct stat st;
    if (lstat(real.fileSystemRepresentation, &st) != 0) { if (error) *error = Problem(@"it is gone"); return NO; }
    NSString *why = nil;
    NSString *folder = StagingFolder(real, record, &why);
    NSString *to = nil;
    if (folder) {
        NSUInteger n = MMRecordList(record.payload, @"staged").count;
        do { to = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.%@", (unsigned long)n++, real.lastPathComponent]]; } while (lstat(to.fileSystemRepresentation, &(struct stat){0}) == 0);
        // The folder's own list says where it was and which part staged it, and says so before the item moves, issue
        // #75: a stop at any moment leaves the item where it was, or in the folder and named there. An item the list
        // cannot name could never be put back or deleted by MinMacs, so it does not move. The item is held open across
        // the rename, a link as the link it is, so the file at the new place can be told to be this very one. A named
        // pipe, a socket or a device is never opened, issue #81, so held is -1 for one: it moves by its name alone, and
        // its entry keeps the id read before the rename.
        int held = MMRemovalOpenItem(real, NULL);
        NSDictionary *before = MMFileIdentity(real) ?: @{@"ino": @(st.st_ino), @"dev": @(st.st_dev)};
#ifdef MM_TESTS
        // A check has the list hold another id before the rename, as a volume that gives a moved file a new id would.
        if (getenv("MINMACS_TEST_ID_MOVES_ON_RENAME") && MMRemovalTestHome()) {
            NSMutableDictionary *other = [before mutableCopy];
            other[@"ino"] = @(st.st_ino + 1);
            before = other;
        }
#endif
        if (!MMRemovalStagingNoteItem(folder, to, real, record.rid, before)) {
            why = @"its staging folder's list could not be written"; to = nil;
        }
        // rename(2) never copies: across volumes it fails, and the item stays. Its line in the list goes again.
        else if (rename(real.fileSystemRepresentation, to.fileSystemRepresentation) != 0) {
            why = [NSString stringWithFormat:@"it could not move to the staging folder: %s", strerror(errno)];
            MMRemovalStagingForgetItem(folder, to.lastPathComponent);
            to = nil;
        } else {
#ifdef MM_TESTS
            // A check stops MinMacs here, as a crash would, between the rename and the record.
            if (getenv("MINMACS_TEST_STOP_AFTER_RENAME") && MMRemovalTestHome()) _exit(0);
            // Or puts a fixture of its own in the item's place, as another process could right after the rename.
            const char *swap = MMRemovalTestHome() ? getenv("MINMACS_TEST_SWAP_AFTER_RENAME") : NULL;
            if (swap) (void)rename(swap, to.fileSystemRepresentation);
#endif
            // Issue #79: a volume may give the file another id where it lies now, as msdosfs does for an empty file.
            // Put-back and the delete believe only the list, so the list gets the id read at the new place. Only for
            // the very file held open since before the rename, HeldAt, so the list never comes to name a file MinMacs
            // did not stage. A stop before this write, or a write that fails, leaves the id from the old place: the
            // item is then kept and listed, and MinMacs neither moves nor deletes it.
            NSDictionary *after = HeldAt(held, to);
            // Only when the inode or the device is another. A volume UUID that read before and does not read now is
            // no reason to write, and the entry never loses the one it had.
            if (after && (![after[@"ino"] isEqual:before[@"ino"]] || ![after[@"dev"] isEqual:before[@"dev"]])) (void)MMRemovalStagingNoteIdentity(folder, to.lastPathComponent, after);
        }
        if (held >= 0) close(held);
    }
    @synchronized (MMUndo.shared) {
        if (to) {
            NSMutableArray *staged = [MMRecordList(record.payload, @"staged") mutableCopy] ?: [NSMutableArray new];
            // The very file that now waits there: its inode and its volume's UUID, MMFileIdentity.
            NSMutableDictionary *entry = [@{@"from": real, @"to": to} mutableCopy];
            [entry addEntriesFromDictionary:MMFileIdentity(to) ?: @{@"ino": @(st.st_ino), @"dev": @(st.st_dev)}];
            [staged addObject:entry];
            [MMUndo.shared note:record payload:@{@"staged": staged, @"stagedIn": folder}];
        } else {
            NSMutableArray *kept = [MMRecordList(record.payload, @"unstaged") mutableCopy] ?: [NSMutableArray new];
            [kept addObject:@{@"path": real, @"why": why ?: @"it could not be staged"}];
            [MMUndo.shared note:record payload:@{@"unstaged": kept}];
        }
    }
    if (!to && folder) MMRemovalDropEmptyStagingFolder(folder, record.parentRid);
    return YES;
}

/// Deletes what part r staged, or with only the one item staged at that path, each checked by StagedWhyNot first.
/// What cannot go stays staged, its entry noting why. *why gets the last reason. Returns the bytes freed.
static int64_t FinishPart(MMUndoRecord *r, NSString *only, NSString **why) {
    int64_t freed = 0;
    BOOL found = NO;
    NSMutableArray *left = [NSMutableArray new], *gone = [MMRecordList(r.payload, @"deleted") mutableCopy] ?: [NSMutableArray new];
    for (NSDictionary *x in MMRecordList(r.payload, @"staged")) {
        if (only && ![MMRecordString(x, @"to") isEqualToString:only]) { [left addObject:x]; continue; }
        found = YES;
        // Only the very file this Wrap Up staged, in the folder MinMacs made for it.
        NSString *real = nil, *no = StagedWhyNot(x, r, &real);
        NSString *holder = real.stringByDeletingLastPathComponent;
        uint64_t before = no ? 0 : FreeOn(holder);
        NSError *e = nil;
        if (!no && !Unlink(real, &e)) no = e.localizedDescription ?: @"it could not be deleted";
        if (no) {
            // A delete that stopped partway leaves the rest of the item staged, and the entry says why.
            NSMutableDictionary *y = [x mutableCopy];
            y[@"why"] = no;
            [left addObject:y];
            if (why) *why = no;
            continue;
        }
        uint64_t after = FreeOn(holder);
        if (after > before) freed += (int64_t)(after - before);
        [gone addObject:@{@"path": MMRecordString(x, @"from") ?: @""}];
    }
    if (only && !found) { if (why) *why = @"the record does not list it"; return 0; }
    NSMutableDictionary *removal = [MMRecordDict(r.payload, @"removal") mutableCopy] ?: [NSMutableDictionary new];
    // Deleted only when every staged item went. What is left stays staged, and the part can still restore.
    if (!left.count) { removal[@"deleted"] = @YES; [removal removeObjectForKey:@"staged"]; }
    [MMUndo.shared note:r payload:@{@"staged": left, @"deleted": gone, @"removal": removal}];
    if (MMRecordString(r.payload, @"stagedIn")) MMRemovalDropEmptyStagingFolder(MMRecordString(r.payload, @"stagedIn"), r.parentRid);
    return freed;
}

int64_t MMRemovalFinishStaged(NSArray<MMUndoRecord *> *parts) {
    int64_t freed = 0;
    for (MMUndoRecord *given in parts) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        // A record that cannot be read is never acted on: an entry that does not say where its item came from, a
        // list that is no list. -[MMUndoRecord damage] says which.
        if (r.state != MMUndoDone || !MMRecordList(r.payload, @"staged").count || r.damage) continue;
        // Nor is the part of a Wrap Up whose own record cannot be read: nobody can tell that its deletes had begun.
        if ([MMUndo.shared record:r.parentRid].damage) continue;
        freed += FinishPart(r, nil, NULL);
    }
    return freed;
}

/// Why a person's act on what part r staged must wait, or nil: its Wrap Up has not ended, so that Wrap Up may still
/// act on the same files, or recovery settles it at the next start.
static NSString *StillRuns(MMUndoRecord *r) {
    MMUndoRecord *parent = r.parentRid.length ? [MMUndo.shared record:r.parentRid] : nil;
    if (parent && parent.state == MMUndoPending) return MMRemovalOwnerAlive(parent) == 1 ? @"its Wrap Up still runs" : @"its Wrap Up has not ended";
    return nil;
}

NSString *MMRemovalDeleteStagedItem(MMUndoRecord *part, NSString *stagedAt, int64_t *freed) {
    MMUndoRecord *r = [MMUndo.shared record:part.rid];
    if (!r || !stagedAt.length) return @"the record does not list it";
    NSString *runs = StillRuns(r);
    if (runs) return runs;
    // Never on behalf of a record that cannot be read, its own or its Wrap Up's, or of a Wrap Up that has no record.
    if (r.damage || [MMUndo.shared record:r.parentRid].damage) return @"its record is damaged, so MinMacs does not delete it";
    if (!r.parentRid.length || ![MMUndo.shared record:r.parentRid]) return @"its Wrap Up has no record, so MinMacs does not delete it";
    if (r.state != MMUndoDone && r.state != MMUndoFailed) return @"its part has not ended";
    // One its record never named, issue #75: the folder's own list names it, and the same one check takes it in.
    if (MMRemovalAdoptStranded(r, nil)) r = [MMUndo.shared record:r.rid];
    NSString *why = nil;
    int64_t got = FinishPart(r, stagedAt, &why);
    if (freed) *freed = got;
    return why;
}

NSString *MMRemovalPutBackStagedItem(MMUndoRecord *part, NSString *stagedAt, NSString *path) {
    MMUndoRecord *r = [MMUndo.shared record:part.rid];
    if (!r || !stagedAt.length || !path.length) return @"the record does not list it";
    NSString *runs = StillRuns(r);
    if (runs) return runs;
    if (r.state != MMUndoDone && r.state != MMUndoFailed) return @"its part has not ended";
    // The record is written again below, so its body and its lists must read.
    if (r.moveDamage) return @"its record is damaged, so MinMacs does not move it";
    if (MMRemovalAdoptStranded(r, nil)) r = [MMUndo.shared record:r.rid];
    NSDictionary *x = nil;
    NSMutableArray *left = [NSMutableArray new];
    for (NSDictionary *e in MMRecordList(r.payload, @"staged")) {
        if (!x && [MMRecordString(e, @"to") isEqualToString:stagedAt]) x = e; else [left addObject:e];
    }
    if (!x) return @"the record does not list it";
    // It must wait in the staging folder MinMacs made for this Wrap Up, so a record never moves a file from elsewhere.
    NSString *no = MMRemovalStagedItemWhyNot(r, stagedAt);
    if (no) return no;
    if (!Spelled(path)) return @"its path is not a real path";
    // The very file that was staged goes, and never over something at path: -[MMUndo moveBack:from:].
    NSMutableDictionary *y = [x mutableCopy];
    y[@"from"] = path;
    NSString *problem = [MMUndo.shared moveBack:@[y] from:@"MinMacs's staging folder"];
    if (problem) return problem;
    NSMutableArray *moved = [MMRecordList(r.payload, @"movedBack") mutableCopy] ?: [NSMutableArray new];
    [moved addObject:@{@"from": MMRecordString(x, @"from") ?: @"", @"to": path}];
    [MMUndo.shared note:r payload:@{@"staged": left, @"movedBack": moved}];
    MMRemovalDropEmptyStagingFolder(MMRecordString(r.payload, @"stagedIn"), r.parentRid);
    return nil;
}

NSString *MMRemovalPutBack(NSArray<MMUndoRecord *> *parts) {
    NSMutableArray *problems = [NSMutableArray new];
    for (MMUndoRecord *given in parts.reverseObjectEnumerator) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        NSDictionary *p = r.payload;
        // Only a removal part that holds something: what it staged for a delete, and what it moved to the Trash to
        // keep. A part that failed midway had moved some of its files too, and those go back with the rest.
        // Only its lists need to read: a part whose removal field is damaged still has its items moved back. Only a
        // removal part stages, and a part that says it is one, readable or not, has its Trash items moved back too.
        // No Wrap Up part trashes without a "removal" today: MMRemovalApply and MMClutterAct note it first. The key
        // stays as a rule, so a part that sent something to the Trash for another reason, as a migration does, never
        // has it pulled back here. No test reaches it.
        BOOL holds = MMRecordList(p, @"staged").count || (MMRecordHas(p, @"removal") && MMRecordList(p, @"trashed").count);
        if ((r.state != MMUndoDone && r.state != MMUndoFailed) || !holds) continue;
        // Nobody asked for this put-back: a Wrap Up, recovery or the sweep runs it. So only what the part moved aside
        // is moved back, -[MMUndo moveBackOnly:], each staged item to its exact old path and never over something
        // there. A record's restart command, relaunch, restorer, bundle and recovery copy are never run from here,
        // whatever the record holds: those are for the person's own Undo, -[MMUndo restore:].
        NSString *problem = [MMUndo.shared moveBackOnly:r.rid];
        if (problem) [problems addObject:[NSString stringWithFormat:@"%@: %@", r.subject ?: r.rid, problem]];
        else if (MMRecordString(p, @"stagedIn")) MMRemovalDropEmptyStagingFolder(MMRecordString(p, @"stagedIn"), r.parentRid);
    }
    return problems.count ? [problems componentsJoinedByString:@"; "] : nil;
}
