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
    for (NSString *a in allowed ?: ([record.payload[@"asked"] isKindOfClass:NSArray.class] ? record.payload[@"asked"] : @[])) {
        NSString *x = [a isKindOfClass:NSString.class] ? MMRemovalRealPath(a) : nil;
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
        NSMutableArray *gone = [record.payload[@"deleted"] mutableCopy] ?: [NSMutableArray new];
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
// It holds a file .minmacs with the rid. Nothing waits in the person's Trash, and MinMacs deletes nothing there.

static NSString *const kMarker = @".minmacs";

static uint64_t FreeOn(NSString *path) {
    struct statfs s;
    return statfs(path.fileSystemRepresentation, &s) == 0 ? (uint64_t)s.f_bavail * s.f_bsize : 0;
}
static BOOL TestHome(void) { return NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length > 0; }

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
/// for this Wrap Up, and the very file that was staged, by device and inode. *real is its real path.
static NSString *StagedWhyNot(NSDictionary *x, MMUndoRecord *r, NSString **real) {
    NSString *to = x[@"to"], *folder = r.payload[@"stagedIn"];
    if (![to isKindOfClass:NSString.class] || ![folder isKindOfClass:NSString.class]) return @"the record does not say where it was staged";
    struct stat st;
    if (lstat(to.fileSystemRepresentation, &st) != 0) return @"it is gone";
    if ((long long)st.st_dev != [x[@"dev"] longLongValue] || (unsigned long long)st.st_ino != [x[@"ino"] unsignedLongLongValue]) return @"it is not the file that was staged";
    NSString *t = MMRemovalRealPath(to), *f = MMRemovalRealPath(folder);
    if (!t || !f) return @"it is gone";
    NSString *why = MMRemovalStagingWhyNot(t, f, r.parentRid, MMRemovalRealPath(MMSupportDir()));
    if (why) return why;
    if (!MarkerSays(f, r.parentRid)) return @"its folder was not made by MinMacs for this Wrap Up";
    return WhyNot(t, r, @[t], real);
}

/// Removes the staging folder once it holds nothing but its marker. Never one that still holds a staged item.
static void RemoveStagingFolder(NSString *folder, NSString *rid) {
    NSString *f = MMRemovalRealPath(folder);
    if (!f || MMRemovalStagingWhyNot([f stringByAppendingPathComponent:kMarker], f, rid, MMRemovalRealPath(MMSupportDir())) || !MarkerSays(f, rid)) return;
    NSArray *holds = [NSFileManager.defaultManager contentsOfDirectoryAtPath:f error:nil];
    if (holds.count == 1 && [holds.firstObject isEqualToString:kMarker]) Unlink(f, nil);
}

/// The staging folder for an item of this part, made now, on the item's own volume. nil with *why when there is none.
static NSString *StagingFolder(NSString *real, MMUndoRecord *record, NSString **why) {
    struct stat item, s;
    if (lstat(real.fileSystemRepresentation, &item) != 0) { *why = @"it is gone"; return nil; }
    NSString *rid = record.parentRid, *folder = nil;
    NSString *support = MMRemovalRealPath(MMSupportDir());
    // A check may ask for the folder beside the worktree, which a Mac with one volume would never use.
    BOOL beside = TestHome() && getenv("MINMACS_STAGE_BESIDE") != NULL;
    if (!beside && support && stat(support.fileSystemRepresentation, &s) == 0 && s.st_dev == item.st_dev)
        folder = [[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:rid];
    else {
        NSString *tree = [[MMUndo.shared record:rid].payload[@"path"] isKindOfClass:NSString.class] ? MMRemovalRealPath([MMUndo.shared record:rid].payload[@"path"]) : nil;
        NSString *holder = tree.stringByDeletingLastPathComponent;
        if (holder.length > 1 && stat(holder.fileSystemRepresentation, &s) == 0 && s.st_dev == item.st_dev)
            folder = [holder stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:rid]];
    }
    if (!folder) { *why = @"no folder of MinMacs's own is on its volume"; return nil; }
    NSString *marker = [folder stringByAppendingPathComponent:kMarker];
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
        (!MarkerSays(folder, rid) && ![rid writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil])) {
        *why = @"its staging folder could not be made"; return nil;
    }
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
        NSUInteger n = [record.payload[@"staged"] count];
        do { to = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.%@", (unsigned long)n++, real.lastPathComponent]]; } while (lstat(to.fileSystemRepresentation, &(struct stat){0}) == 0);
        // rename(2) never copies: across volumes it fails, and the item stays.
        if (rename(real.fileSystemRepresentation, to.fileSystemRepresentation) != 0) { why = [NSString stringWithFormat:@"it could not move to the staging folder: %s", strerror(errno)]; to = nil; }
    }
    @synchronized (MMUndo.shared) {
        if (to) {
            NSMutableArray *staged = [record.payload[@"staged"] mutableCopy] ?: [NSMutableArray new];
            [staged addObject:@{@"from": real, @"to": to, @"dev": @(st.st_dev), @"ino": @(st.st_ino)}];
            [MMUndo.shared note:record payload:@{@"staged": staged, @"stagedIn": folder}];
        } else {
            NSMutableArray *kept = [record.payload[@"unstaged"] mutableCopy] ?: [NSMutableArray new];
            [kept addObject:@{@"path": real, @"why": why ?: @"it could not be staged"}];
            [MMUndo.shared note:record payload:@{@"unstaged": kept}];
        }
    }
    if (!to && folder) RemoveStagingFolder(folder, record.parentRid);
    return YES;
}

int64_t MMRemovalFinishStaged(NSArray<MMUndoRecord *> *parts) {
    int64_t freed = 0;
    for (MMUndoRecord *given in parts) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        NSArray *staged = [r.payload[@"staged"] isKindOfClass:NSArray.class] ? r.payload[@"staged"] : nil;
        if (r.state != MMUndoDone || !staged.count) continue;
        NSMutableArray *left = [NSMutableArray new], *gone = [r.payload[@"deleted"] mutableCopy] ?: [NSMutableArray new];
        for (NSDictionary *x in staged) {
            NSString *real = nil;
            // Only the very file this Wrap Up staged, in the folder MinMacs made for it.
            if (StagedWhyNot(x, r, &real)) { [left addObject:x]; continue; }
            NSString *holder = real.stringByDeletingLastPathComponent;
            uint64_t before = FreeOn(holder);
            if (!Unlink(real, nil)) { [left addObject:x]; continue; }
            uint64_t after = FreeOn(holder);
            if (after > before) freed += (int64_t)(after - before);
            [gone addObject:@{@"path": x[@"from"] ?: @""}];
        }
        NSMutableDictionary *removal = [r.payload[@"removal"] isKindOfClass:NSDictionary.class] ? [r.payload[@"removal"] mutableCopy] : [NSMutableDictionary new];
        // Deleted only when every staged item went. What is left stays staged, and the part can still restore.
        if (!left.count) { removal[@"deleted"] = @YES; [removal removeObjectForKey:@"staged"]; }
        [MMUndo.shared note:r payload:@{@"staged": left, @"deleted": gone, @"removal": removal}];
        if ([r.payload[@"stagedIn"] isKindOfClass:NSString.class]) RemoveStagingFolder(r.payload[@"stagedIn"], r.parentRid);
    }
    return freed;
}

NSString *MMRemovalPutBack(NSArray<MMUndoRecord *> *parts) {
    NSMutableArray *problems = [NSMutableArray new];
    for (MMUndoRecord *given in parts.reverseObjectEnumerator) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        NSDictionary *p = r.payload;
        // Only a removal part that holds something: what it staged for a delete, and what it moved to the Trash to
        // keep. A part that failed midway had moved some of its files too, and those go back with the rest.
        BOOL holds = [p[@"removal"] isKindOfClass:NSDictionary.class] && ([p[@"trashed"] count] || [p[@"staged"] count]);
        if ((r.state != MMUndoDone && r.state != MMUndoFailed) || !holds) continue;
        // -[MMUndo restore:] renames each staged item back to its exact old path, and refuses when something sits there.
        NSString *problem = [MMUndo.shared restore:r.rid];
        if (problem) [problems addObject:[NSString stringWithFormat:@"%@: %@", r.subject ?: r.rid, problem]];
        else if ([p[@"stagedIn"] isKindOfClass:NSString.class]) RemoveStagingFolder(p[@"stagedIn"], r.parentRid);
    }
    return problems.count ? [problems componentsJoinedByString:@"; "] : nil;
}

#pragma mark - After a crash

static NSMutableSet<NSString *> *Running(void) {
    static NSMutableSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}
void MMRemovalWrapUpBegan(NSString *rid) { if (rid.length) @synchronized (Running()) { [Running() addObject:rid]; } }
void MMRemovalWrapUpEnded(NSString *rid) { if (rid.length) @synchronized (Running()) { [Running() removeObject:rid]; } }

NSInteger MMRemovalRecoverStaged(void) {
    // A Wrap Up that another process runs right now has a record that is not finished either. One this old is not running.
    NSTimeInterval old = 15 * 60;
    if (TestHome() && getenv("MINMACS_STAGE_RECOVER_AFTER")) old = atof(getenv("MINMACS_STAGE_RECOVER_AFTER"));
    NSMutableDictionary<NSString *, NSMutableArray<MMUndoRecord *> *> *byParent = [NSMutableDictionary new];
    for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:5000]) {
        if (!r.parentRid.length || ![r.payload[@"staged"] isKindOfClass:NSArray.class] || ![r.payload[@"staged"] count]) continue;
        [(byParent[r.parentRid] ?: (byParent[r.parentRid] = [NSMutableArray new])) addObject:r];
    }
    NSInteger recovered = 0;
    for (NSString *rid in byParent) {
        @synchronized (Running()) { if ([Running() containsObject:rid]) continue; }
        MMUndoRecord *parent = [MMUndo.shared record:rid];
        if (!parent || parent.state != MMUndoPending || -parent.at.timeIntervalSinceNow < old) continue;
        NSArray<MMUndoRecord *> *parts = byParent[rid];
        if ([parent.payload[@"finishing"] boolValue]) {
            // Every part had gone through and the deletes had begun: the worktree is gone, so they are finished.
            int64_t freed = MMRemovalFinishStaged(parts);
            [MMUndo.shared finish:parent ok:YES freed:freed error:nil];
        } else {
            // It never got that far: nothing is deleted. Each staged item goes back to its exact old path.
            for (MMUndoRecord *part in parts)
                if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"MinMacs stopped before this part ended"];
            NSString *notBack = MMRemovalPutBack(parts);
            [MMUndo.shared finish:parent ok:NO freed:0 error:[NSString stringWithFormat:@"MinMacs stopped before this Wrap Up ended. What it had staged was put back%@",
                                                             notBack ? [@", except: " stringByAppendingString:notBack] : @""]];
        }
        recovered++;
    }
    return recovered;
}
