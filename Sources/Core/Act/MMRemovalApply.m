// The removal choice, MMRemoval.h: the wall and the only place Act deletes a file. What a Wrap Up stages, and how
// it is finished, put back and recovered after a crash, is below, since it deletes through the same one call.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>

#pragma mark - Real paths and places

NSString *MMRemovalRealPath(NSString *path) {
    if (![path hasPrefix:@"/"]) return nil;
    // The item itself is opened, a symlink as the link it is, and the kernel says where that is: every symlink above
    // it resolved, and each name in the case the disk holds, so HOME and home are one path on a disk that folds case.
    int fd = open(path.fileSystemRepresentation, O_EVTONLY | O_SYMLINK | O_CLOEXEC);
    if (fd < 0) return nil;
    char buf[PATH_MAX];
    NSString *real = fcntl(fd, F_GETPATH, buf) == 0 ? @(buf) : nil;
    close(fd);
    return real.length ? real : nil;
}

@implementation MMRemovalPlaces
+ (instancetype)placesFor:(NSString *)path {
    MMRemovalPlaces *p = [MMRemovalPlaces new];
    p.home = MMRemovalRealPath(NSHomeDirectory());
    p.support = MMRemovalRealPath(MMSupportDir());
    NSString *test = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    // A test home that cannot be read keeps every path out, since nothing lies inside "".
    if (test.length) p.testHome = MMRemovalRealPath(test) ?: @"";
    // The volume of the folder that holds the item, so a symlink is never followed to another volume.
    NSURL *holder = [NSURL fileURLWithPath:path.stringByDeletingLastPathComponent];
    NSURL *volume = nil; NSNumber *sensitive = nil;
    [holder getResourceValue:&volume forKey:NSURLVolumeURLKey error:nil];
    [holder getResourceValue:&sensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:nil];
    p.volume = volume.path;
    // Not knowing counts as folding case, the reading that refuses more.
    p.foldCase = !sensitive.boolValue;
    return p;
}
@end

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
    if (!r) return @"it is gone";
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
// It holds a file .minmacs with the rid, and a .gitignore that hides the folder from a repo it may sit in.
// Nothing waits in the person's Trash, and MinMacs deletes nothing there.
// An item is staged only when its staging folder would itself pass the wall. Otherwise it stays where it is.

static NSString *const kMarker = @".minmacs", *const kIgnore = @".gitignore", *const kIgnoreSays = @"*\n";

static uint64_t FreeOn(NSString *path) {
    struct statfs s;
    return statfs(path.fileSystemRepresentation, &s) == 0 ? (uint64_t)s.f_bavail * s.f_bsize : 0;
}
BOOL MMRemovalTestHome(void) { return NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length > 0; }

NSString *MMRemovalStagingWhyNot(NSString *item, NSString *folder, NSString *rid, NSString *support) {
    if (!rid.length || !folder.length || !item.length) return @"cannot verify whose staging folder it is";
    BOOL own = support.length && [folder isEqualToString:[[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:rid]];
    BOOL beside = [folder.lastPathComponent isEqualToString:[@".minmacs-staged-" stringByAppendingString:rid]];
    if (!own && !beside) return @"its folder is not the staging folder of this Wrap Up";
    if (![item.stringByDeletingLastPathComponent isEqualToString:folder]) return @"it does not lie directly in the staging folder";
    return nil;
}

/// YES when folder holds the marker MinMacs wrote for this rid: a plain file of ours that says the rid.
static BOOL MarkerSays(NSString *folder, NSString *rid) {
    NSString *m = [folder stringByAppendingPathComponent:kMarker];
    struct stat st;
    if (lstat(m.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != getuid()) return NO;
    return [[NSString stringWithContentsOfFile:m encoding:NSUTF8StringEncoding error:nil] isEqualToString:rid];
}

/// Why the staged entry x of record r may not be deleted, or nil: the record's own staging folder, made by MinMacs
/// for this Wrap Up, and the very file that was staged, MMFileIsEntry. An entry that does not say which file it is
/// is never deleted. *real is its real path.
static NSString *StagedWhyNot(NSDictionary *x, MMUndoRecord *r, NSString **real) {
    NSString *to = MMRecordString(x, @"to"), *folder = MMRecordString(r.payload, @"stagedIn");
    if (!to || !folder) return @"the record does not say where it was staged";
    struct stat st;
    if (lstat(to.fileSystemRepresentation, &st) != 0) return @"it is gone";
    BOOL unread = NO;
    int same = MMFileIsEntryCheck(to, x, &unread);
    if (same < 0) return @"the record does not say which file was staged";
    if (same == 0) return unread ? @"its volume's UUID cannot be read now, so MinMacs cannot tell it is the file that was staged" : @"it is not the file that was staged";
    NSString *t = MMRemovalRealPath(to), *f = MMRemovalRealPath(folder);
    if (!t || !f) return @"it is gone";
    NSString *why = MMRemovalStagingWhyNot(t, f, r.parentRid, MMRemovalRealPath(MMSupportDir()));
    if (why) return why;
    if (!MarkerSays(f, r.parentRid)) return @"its folder was not made by MinMacs for this Wrap Up";
    return WhyNot(t, r, @[t], real);
}

/// YES when folder holds no .gitignore, or the one MinMacs wrote: a plain file of ours that says exactly "*".
/// A folder of that name, a link, or a file that says anything else is not MinMacs's.
static BOOL IgnoreIsOurs(NSString *folder) {
    NSString *g = [folder stringByAppendingPathComponent:kIgnore];
    struct stat st;
    if (lstat(g.fileSystemRepresentation, &st) != 0) return errno == ENOENT;
    if (!S_ISREG(st.st_mode) || st.st_uid != getuid()) return NO;
    return [[NSString stringWithContentsOfFile:g encoding:NSUTF8StringEncoding error:nil] isEqualToString:kIgnoreSays];
}

/// Removes the staging folder once it holds nothing but what MinMacs wrote there itself: its marker and its
/// .gitignore, each a plain file with MinMacs's own words. Never one that still holds a staged item, and never one
/// where something else took one of those two names.
void MMRemovalDropEmptyStagingFolder(NSString *folder, NSString *rid) {
    NSString *f = MMRemovalRealPath(folder);
    if (!f || MMRemovalStagingWhyNot([f stringByAppendingPathComponent:kMarker], f, rid, MMRemovalRealPath(MMSupportDir())) || !MarkerSays(f, rid)) return;
    if (!IgnoreIsOurs(f)) return;
    NSMutableSet *holds = [NSMutableSet setWithArray:[NSFileManager.defaultManager contentsOfDirectoryAtPath:f error:nil] ?: @[@"?"]];
    [holds minusSet:[NSSet setWithArray:@[kMarker, kIgnore]]];
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
    NSString *marker = [folder stringByAppendingPathComponent:kMarker], *ignore = [folder stringByAppendingPathComponent:kIgnore];
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
        (!MarkerSays(folder, rid) && ![rid writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil])) {
        *why = @"its staging folder could not be made"; return nil;
    }
    // A repo that holds this folder, as a main checkout holds .worktrees/, never lists it as untracked.
    if (lstat(ignore.fileSystemRepresentation, &s) != 0) [kIgnoreSays writeToFile:ignore atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return folder;
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
        // rename(2) never copies: across volumes it fails, and the item stays.
        if (rename(real.fileSystemRepresentation, to.fileSystemRepresentation) != 0) { why = [NSString stringWithFormat:@"it could not move to the staging folder: %s", strerror(errno)]; to = nil; }
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

NSString *MMRemovalDeleteStagedItem(MMUndoRecord *part, NSString *stagedAt, int64_t *freed) {
    MMUndoRecord *r = [MMUndo.shared record:part.rid];
    if (!r || !stagedAt.length) return @"the record does not list it";
    // Never on behalf of a record that cannot be read, its own or its Wrap Up's.
    if (r.damage || [MMUndo.shared record:r.parentRid].damage) return @"its record is damaged, so MinMacs does not delete it";
    if (r.state != MMUndoDone && r.state != MMUndoFailed) return @"its part has not ended";
    NSString *why = nil;
    int64_t got = FinishPart(r, stagedAt, &why);
    if (freed) *freed = got;
    return why;
}

NSString *MMRemovalPutBackStagedItem(MMUndoRecord *part, NSString *stagedAt, NSString *path) {
    MMUndoRecord *r = [MMUndo.shared record:part.rid];
    if (!r || !stagedAt.length || !path.length) return @"the record does not list it";
    // The record is written again below, so its body and its lists must read.
    if (r.moveDamage) return @"its record is damaged, so MinMacs does not move it";
    NSDictionary *x = nil;
    NSMutableArray *left = [NSMutableArray new];
    for (NSDictionary *e in MMRecordList(r.payload, @"staged")) {
        if (!x && [MMRecordString(e, @"to") isEqualToString:stagedAt]) x = e; else [left addObject:e];
    }
    if (!x) return @"the record does not list it";
    // It must wait in the staging folder MinMacs made for this Wrap Up, so a record never moves a file from elsewhere.
    NSString *t = MMRemovalRealPath(stagedAt), *f = MMRemovalRealPath(MMRecordString(r.payload, @"stagedIn") ?: @"");
    if (!t) return @"it is gone from the staging folder";
    NSString *no = f ? MMRemovalStagingWhyNot(t, f, r.parentRid, MMRemovalRealPath(MMSupportDir())) : @"the record does not say where it was staged";
    if (!no && !MarkerSays(f, r.parentRid)) no = @"its folder was not made by MinMacs for this Wrap Up";
    if (no) return no;
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
        BOOL holds = MMRecordDict(p, @"removal") && (MMRecordList(p, @"trashed").count || MMRecordList(p, @"staged").count);
        if ((r.state != MMUndoDone && r.state != MMUndoFailed) || !holds) continue;
        // -[MMUndo restore:] renames each staged item back to its exact old path, and refuses when something sits there.
        // A record with a damaged field has only what it moved aside moved back, and only when its lists read.
        NSString *problem = r.damage ? [MMUndo.shared moveBackOnly:r.rid] : [MMUndo.shared restore:r.rid];
        if (problem) [problems addObject:[NSString stringWithFormat:@"%@: %@", r.subject ?: r.rid, problem]];
        else if (MMRecordString(p, @"stagedIn")) MMRemovalDropEmptyStagingFolder(MMRecordString(p, @"stagedIn"), r.parentRid);
    }
    return problems.count ? [problems componentsJoinedByString:@"; "] : nil;
}
