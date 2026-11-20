// The removal choice, MMRemoval.h: the real path of an item, and the places the wall asks about. Nothing here moves
// or deletes a file.
//
//   the item is                          its real path comes from                         held open across the rename
//   a folder, a file or link             an open of it, then F_GETPATH                    yes
//     with one name
//   a file or link with a second name    its folder's real path, and its own name         yes
//                                        as that folder lists it
//   a pipe, a socket, a device           the same                                         no: it is never opened
//
// Issue #81: an open of a named pipe waits until a writer comes, so a removal whose item was a pipe never came
// back. An open of a device can wait too, or act on the device, and a socket cannot be opened at all. None of the
// three is ever opened here: a rename, an lstat and an unlink need no open. Every other open carries O_NONBLOCK, so
// a pipe that takes an item's place between the lstat and the open cannot hold MinMacs either.
//
// What the kernel says of the item itself is not asked when the item may have a second name, a hard link. It keeps
// one path per file, and for a file with two names that can be the other name, in another folder: always for a pipe
// or a socket, and for an open plain file whenever somebody asked for the other name last. MinMacs would then delete
// a name no finding named. So such an item is named by the folder that was asked: EntryPath.
#import "Core/Act/MMRemoval.h"
#import "Core/Store/MMStore.h"
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>

/// YES for what is never opened: a named pipe, a socket, a device, and whatever else is no file, folder or link.
static BOOL NeverOpened(mode_t mode) { return !S_ISREG(mode) && !S_ISDIR(mode) && !S_ISLNK(mode); }

int MMRemovalOpenItem(NSString *path, BOOL *never) {
    if (never) *never = NO;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return -1;
    if (NeverOpened(st.st_mode)) { if (never) *never = YES; return -1; }
    int fd = open(path.fileSystemRepresentation, O_EVTONLY | O_SYMLINK | O_NONBLOCK | O_CLOEXEC);
    // What was opened is asked once more: another thing may have taken the item's place since the lstat.
    if (fd >= 0 && (fstat(fd, &st) != 0 || NeverOpened(st.st_mode))) {
        close(fd);
        if (never) *never = YES;
        return -1;
    }
    return fd;
}

/// The real path of the item at path as the folder that holds it says, with no open of the item: that folder's
/// real path, and the item's own name as the folder lists it. So the answer is always the entry that was asked,
/// whatever other names the item has. nil when the folder cannot be listed, or lists no one name for the item: the
/// item then stays, since nothing says where it lies.
static NSString *EntryPath(NSString *path) {
    NSString *holder = path.stringByDeletingLastPathComponent, *asked = path.lastPathComponent;
    // The folder is a folder, so its own real path comes from an open of it. "/." so a link to it is followed, as
    // every link above an item is.
    NSString *folder = asked.length ? MMRemovalRealPath([holder stringByAppendingString:@"/."]) : nil;
    int dir = folder ? open(holder.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NONBLOCK | O_CLOEXEC) : -1;
    if (dir < 0) return nil;
    char buf[PATH_MAX];
    struct stat st, now;
    // The folder that is listed must be the one whose real path was taken, and the item must lie in it.
    BOOL same = fcntl(dir, F_GETPATH, buf) == 0 && [folder isEqualToString:@(buf)];
    DIR *list = same && fstatat(dir, asked.fileSystemRepresentation, &st, AT_SYMLINK_NOFOLLOW) == 0 && !S_ISDIR(st.st_mode) ? fdopendir(dir) : NULL;
    if (!list) { close(dir); return nil; }
    // Every name this folder lists for that very file. Its names in other folders are not among them.
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (struct dirent *e; (e = readdir(list));) {
        NSString *name = e->d_ino == st.st_ino ? @(e->d_name) : nil;
        if (name) [names addObject:name];
    }
    // The asked name as the disk holds it: letter for letter, else the same letters spelled another way, else in
    // another case, as a disk that folds case allows. Two names that fit at one step say nothing.
    NSString *own = nil;
    for (NSNumber *how in @[@(NSLiteralSearch), @0, @(NSCaseInsensitiveSearch)]) {
        NSUInteger fit = 0;
        for (NSString *name in names) if ([name compare:asked options:how.unsignedIntegerValue] == NSOrderedSame) { own = name; fit++; }
        if (fit > 1) own = nil;
        if (fit) break;
    }
    BOOL there = own && fstatat(dir, own.fileSystemRepresentation, &now, AT_SYMLINK_NOFOLLOW) == 0 && now.st_ino == st.st_ino;
    closedir(list);   // closes dir as well
    if (!there) return nil;
    NSString *real = [folder isEqualToString:@"/"] ? [@"/" stringByAppendingString:own] : [NSString stringWithFormat:@"%@/%@", folder, own];
    return [real lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < PATH_MAX ? real : nil;
}

NSString *MMRemovalRealPath(NSString *path) {
    if (![path hasPrefix:@"/"]) return nil;
    // The item itself is opened, a symlink as the link it is, and the kernel says where that is: every symlink above
    // it resolved, and each name in the case the disk holds, so HOME and home are one path on a disk that folds case.
    BOOL never = NO;
    int fd = MMRemovalOpenItem(path, &never);
    if (fd < 0) return never ? EntryPath(path) : nil;
    char buf[PATH_MAX];
    struct stat st;
    NSString *real = fcntl(fd, F_GETPATH, buf) == 0 ? @(buf) : nil;
    // A folder has one name. A file or a link with more than one may be named here by another of them.
    BOOL names = fstat(fd, &st) != 0 || (!S_ISDIR(st.st_mode) && st.st_nlink != 1);
    close(fd);
    if (names) return EntryPath(path);
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
