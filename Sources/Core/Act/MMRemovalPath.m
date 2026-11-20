// The removal choice, MMRemoval.h: the real path of an item, and the places the wall asks about. Nothing here moves
// or deletes a file.
//
//   the item is                    its real path comes from              held open across the rename
//   a file, a folder, a link       an open of it, then F_GETPATH         yes
//   a pipe, a socket, a device     its folder entry, getattrlist         no: it is never opened
//
// Issue #81: an open of a named pipe waits until a writer comes, so a removal whose item was a pipe never came
// back. An open of a device can wait too, or act on the device, and a socket cannot be opened at all. None of the
// three is ever opened here. Its folder entry gives the same path, and a rename, an lstat and an unlink need no open.
// Every other open carries O_NONBLOCK, so a pipe that takes an item's place between the lstat and the open cannot
// hold MinMacs either.
#import "Core/Act/MMRemoval.h"
#import "Core/Store/MMStore.h"
#include <fcntl.h>
#include <sys/attr.h>
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

/// The real path of the item at path as its folder entry gives it, with no open of the item: the path F_GETPATH
/// gives for an open file, every symlink above it resolved and each name in the case the disk holds.
static NSString *EntryPath(NSString *path) {
    struct attrlist want = {.bitmapcount = ATTR_BIT_MAP_COUNT, .commonattr = ATTR_CMN_FULLPATH};
    struct { uint32_t length; attrreference_t ref; char text[PATH_MAX]; } __attribute__((aligned(4), packed)) got;
    if (getattrlist(path.fileSystemRepresentation, &want, &got, sizeof got, FSOPT_NOFOLLOW) != 0) return nil;
    // The text lies at an offset from the reference, with its length. Both must lie inside what was asked for.
    int32_t at = got.ref.attr_dataoffset;
    uint32_t length = got.ref.attr_length;
    if (at < (int32_t)sizeof got.ref || (size_t)at + length > sizeof got.ref + sizeof got.text) return nil;
    const char *text = (const char *)&got.ref + at;
    // A full path that ends inside its length. Anything else is no answer.
    if (length < 2 || text[0] != '/' || strnlen(text, length) == length) return nil;
    return @(text);
}

NSString *MMRemovalRealPath(NSString *path) {
    if (![path hasPrefix:@"/"]) return nil;
    // The item itself is opened, a symlink as the link it is, and the kernel says where that is: every symlink above
    // it resolved, and each name in the case the disk holds, so HOME and home are one path on a disk that folds case.
    BOOL never = NO;
    int fd = MMRemovalOpenItem(path, &never);
    if (fd < 0) return never ? EntryPath(path) : nil;
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
