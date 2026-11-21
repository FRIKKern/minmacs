// MMReadPlain, MMRuntime.h: a read of a file whose path comes from the disk that never waits, issue #96.
//
//   the path is                                   what happens
//   missing, a folder                             nil
//   a named pipe, with a writer or none           nil, never opened: stat says what it is
//   a socket, a device                            nil, never opened
//   a link to any of those                        nil, never opened: stat follows the link
//   a plain file, or a link to one                opened with O_NONBLOCK, asked again with fstat, then read
//   a plain file a pipe replaced after the stat   nil: the open of a pipe for reading with O_NONBLOCK returns at once,
//                                                 and fstat names it
//
// NSFileHandle and NSData's file reads open with no O_NONBLOCK, so a pipe under a session file's or a package.json's
// name held the queue that read it for ever, and with it every rebuild that waited on that queue.
#import "Core/Runtime/MMRuntime.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

NSData *MMReadPlain(NSString *path, NSUInteger max, MMPlainPart part) { return MMReadPlainWhy(path, max, part, NULL); }

/// Not a plain file: EISDIR for a folder, EFTYPE for anything else.
static int NotPlain(const struct stat *st) { return S_ISDIR(st->st_mode) ? EISDIR : EFTYPE; }

/// The one read. own: one of MinMacs's own files, issue #113, so a link at its name is never followed, ELOOP, and a
/// file of another user's is not read, EPERM. The open itself carries O_NOFOLLOW, so a link that takes the name after
/// the lstat is not followed either.
static NSData *ReadPlain(NSString *path, NSUInteger max, MMPlainPart part, BOOL own, int *why) {
    int none = 0;
    if (!why) why = &none;
    *why = ENOENT;
    if (!path.length) return nil;
    const char *p = path.fileSystemRepresentation;
    struct stat st;
    if (!p) { *why = EINVAL; return nil; }
    if ((own ? lstat(p, &st) : stat(p, &st)) != 0) { *why = errno; return nil; }
    if (own && S_ISLNK(st.st_mode)) { *why = ELOOP; return nil; }
    if (!S_ISREG(st.st_mode)) { *why = NotPlain(&st); return nil; }
    int fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (own ? O_NOFOLLOW : 0));
    if (fd < 0) { *why = errno; return nil; }
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0) { *why = EFTYPE; close(fd); return nil; }
    if (own && st.st_uid != getuid()) { *why = EPERM; close(fd); return nil; }
    unsigned long long size = (unsigned long long)st.st_size;
    if (part == MMPlainWhole && size > max) { *why = EFBIG; close(fd); return nil; }
    size_t want = (size_t)MIN(size, (unsigned long long)max);
    off_t from = part == MMPlainTail ? (off_t)(size - want) : 0;
    NSMutableData *d = [NSMutableData dataWithLength:want];
    size_t got = 0;
    while (got < want) {
        ssize_t n = pread(fd, (char *)d.mutableBytes + got, want - got, from + (off_t)got);
        if (n < 0) { if (errno == EINTR) continue; *why = errno ?: EIO; close(fd); return nil; }
        if (n == 0) break;   // it shrank since the fstat
        got += (size_t)n;
    }
    close(fd);
    d.length = got;
    *why = 0;
    return d;
}

NSData *MMReadPlainWhy(NSString *path, NSUInteger max, MMPlainPart part, int *why) { return ReadPlain(path, max, part, NO, why); }
NSData *MMReadOwnPlain(NSString *path, NSUInteger max, int *why) { return ReadPlain(path, max, MMPlainWhole, YES, why); }
