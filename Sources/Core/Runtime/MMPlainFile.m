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

NSData *MMReadPlain(NSString *path, NSUInteger max, MMPlainPart part) {
    if (!path.length) return nil;
    const char *p = path.fileSystemRepresentation;
    struct stat st;
    if (!p || stat(p, &st) != 0 || !S_ISREG(st.st_mode)) return nil;
    int fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return nil;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0) { close(fd); return nil; }
    unsigned long long size = (unsigned long long)st.st_size;
    if (part == MMPlainWhole && size > max) { close(fd); return nil; }
    size_t want = (size_t)MIN(size, (unsigned long long)max);
    off_t from = part == MMPlainTail ? (off_t)(size - want) : 0;
    NSMutableData *d = [NSMutableData dataWithLength:want];
    size_t got = 0;
    while (got < want) {
        ssize_t n = pread(fd, (char *)d.mutableBytes + got, want - got, from + (off_t)got);
        if (n < 0) { if (errno == EINTR) continue; close(fd); return nil; }
        if (n == 0) break;   // it shrank since the fstat
        got += (size_t)n;
    }
    close(fd);
    d.length = got;
    return d;
}
