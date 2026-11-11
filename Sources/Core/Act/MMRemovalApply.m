// The removal choice, MMRemoval.h: the wall, the only place Act deletes a file, and what a Wrap Up stages.
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

BOOL MMRemovalApply(NSString *path, MMRemovalDecision *d, MMUndoRecord *record, NSError **error) {
    if (!path.length || !d || !record) { if (error) *error = Problem(@"cannot verify what to remove"); return NO; }
    if (![path hasPrefix:@"/"]) { if (error) *error = Problem(@"it has no full path"); return NO; }
    if (!d.deleteNow) return [MMUndo.shared trash:[NSURL fileURLWithPath:path] record:record error:error] != nil;
    NSString *real = nil;
    NSString *why = WhyNot(path, record, nil, &real);
    if (why) { if (error) *error = Problem(why); return NO; }
    struct stat st;
    if (record.parentRid.length) {
        // A part of a Wrap Up: a later part may still refuse, so the item waits in the Trash. See MMRemovalFinishStaged.
        if (lstat(real.fileSystemRepresentation, &st) != 0) { if (error) *error = Problem(@"it is gone"); return NO; }
        NSURL *to = [MMUndo.shared trash:[NSURL fileURLWithPath:real] record:record error:error];
        if (!to) return NO;
        @synchronized (MMUndo.shared) {
            NSMutableArray *staged = [record.payload[@"staged"] mutableCopy] ?: [NSMutableArray new];
            [staged addObject:@{@"from": real, @"to": to.path, @"dev": @(st.st_dev), @"ino": @(st.st_ino)}];
            [MMUndo.shared note:record payload:@{@"staged": staged}];
        }
        return YES;
    }
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

#pragma mark - What a Wrap Up staged

static uint64_t FreeOn(NSString *path) {
    struct statfs s;
    return statfs(path.fileSystemRepresentation, &s) == 0 ? (uint64_t)s.f_bavail * s.f_bsize : 0;
}

int64_t MMRemovalFinishStaged(NSArray<MMUndoRecord *> *parts) {
    int64_t freed = 0;
    for (MMUndoRecord *given in parts) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        NSArray *staged = [r.payload[@"staged"] isKindOfClass:NSArray.class] ? r.payload[@"staged"] : nil;
        if (r.state != MMUndoDone || !staged.count) continue;
        NSMutableArray *left = [NSMutableArray new], *gone = [r.payload[@"deleted"] mutableCopy] ?: [NSMutableArray new];
        NSMutableArray *trashed = [r.payload[@"trashed"] mutableCopy] ?: [NSMutableArray new];
        for (NSDictionary *x in staged) {
            NSString *to = x[@"to"], *real = nil;
            struct stat st;
            // Only the very file this run put in the Trash: the same device and inode at the place the record names.
            BOOL same = [to isKindOfClass:NSString.class] && lstat(to.fileSystemRepresentation, &st) == 0 &&
                        (long long)st.st_dev == [x[@"dev"] longLongValue] && (unsigned long long)st.st_ino == [x[@"ino"] unsignedLongLongValue];
            NSString *holder = to.stringByDeletingLastPathComponent;
            uint64_t before = same ? FreeOn(holder) : 0;
            if (!same || WhyNot(to, r, @[to], &real) || !Unlink(real, nil)) { [left addObject:x]; continue; }
            uint64_t after = FreeOn(holder);
            if (after > before) freed += (int64_t)(after - before);
            [gone addObject:@{@"path": x[@"from"] ?: @""}];
            for (NSDictionary *t in [trashed copy]) if ([t[@"to"] isEqual:to]) [trashed removeObject:t];
        }
        NSMutableDictionary *removal = [r.payload[@"removal"] isKindOfClass:NSDictionary.class] ? [r.payload[@"removal"] mutableCopy] : [NSMutableDictionary new];
        // Deleted only when every staged item went. What is left stays in the Trash, and the part can still restore.
        if (!left.count) { removal[@"deleted"] = @YES; [removal removeObjectForKey:@"staged"]; }
        [MMUndo.shared note:r payload:@{@"staged": left, @"deleted": gone, @"trashed": trashed, @"removal": removal}];
    }
    return freed;
}

NSString *MMRemovalPutBack(NSArray<MMUndoRecord *> *parts) {
    NSMutableArray *problems = [NSMutableArray new];
    for (MMUndoRecord *given in parts.reverseObjectEnumerator) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        // Only a removal part that holds something in the Trash: what it staged for a delete, and what it moved there
        // to keep. A part that failed midway had moved some of its files too, and those go back with the rest.
        BOOL holds = [r.payload[@"removal"] isKindOfClass:NSDictionary.class] && [r.payload[@"trashed"] isKindOfClass:NSArray.class] && [r.payload[@"trashed"] count];
        if ((r.state != MMUndoDone && r.state != MMUndoFailed) || !holds) continue;
        NSString *p = [MMUndo.shared restore:r.rid];
        if (p) [problems addObject:[NSString stringWithFormat:@"%@: %@", r.subject ?: r.rid, p]];
    }
    return problems.count ? [problems componentsJoinedByString:@"; "] : nil;
}
