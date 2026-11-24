// core.sock and the instance lock, pattern P63. Ported from NN internal/ipc/server.go:82-160:
// an flock instance lock first, then the socket, then a same-uid check on every connection with getpeereid.
// One request and one reply per connection, each one JSON object on one line.
// The lock lives in <support folder>/core.lock and the socket in <support folder>/core.sock.
#import "Core/Runtime/MMCoreSocket.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import <os/log.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static const size_t kMaxRequest = 4 << 20;     // a line past 4 MB is refused; a reply can carry a verb's whole output
static const NSTimeInterval kReadLimit = 2;     // a peer that sends nothing for this long is closed

NSString *MMCoreSocketPath(void) { return [MMSupportDir() stringByAppendingPathComponent:@"core.sock"]; }
static NSString *LockPath(void) { return [MMSupportDir() stringByAppendingPathComponent:@"core.lock"]; }

static os_log_t SocketLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "socket"); });
    return log;
}

/// Fills addr for path. NO when the path does not fit in sun_path.
static BOOL Address(NSString *path, struct sockaddr_un *addr) {
    memset(addr, 0, sizeof *addr);
    addr->sun_family = AF_UNIX;
    const char *p = path.fileSystemRepresentation;
    if (!p || strlen(p) >= sizeof addr->sun_path) return NO;
    strlcpy(addr->sun_path, p, sizeof addr->sun_path);
    addr->sun_len = (uint8_t)SUN_LEN(addr);
    return YES;
}

/// Binds fd to path through a folder only this uid can enter, <support>/.s<pid>, made 0700 by mkdir with no change
/// of the umask: the socket is bound there, set to 0600, and renamed over path. NO with *why when any step fails, and
/// then nothing is left in that folder.
static BOOL BindPrivately(int fd, NSString *path, NSString **why) {
    NSString *dir = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@".s%d", (int)getpid()]];
    NSString *tmp = [dir stringByAppendingPathComponent:@"s"];
    struct sockaddr_un at, to;
    if (!Address(tmp, &at) || !Address(path, &to)) { *why = @"the support folder path is too long for core.sock"; return NO; }
    // A folder left by a crashed process with this pid: only its socket is ever in it.
    unlink(at.sun_path);
    rmdir(dir.fileSystemRepresentation);
    if (mkdir(dir.fileSystemRepresentation, 0700) != 0) { *why = [NSString stringWithFormat:@"core.sock folder: %s", strerror(errno)]; return NO; }
    BOOL ok = NO;
    struct stat st;
    // The folder must be the one just made: a folder of this uid's with no way in for anyone else.
    if (lstat(dir.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == getuid() && (st.st_mode & 077) == 0) {
        if (bind(fd, (struct sockaddr *)&at, at.sun_len) == 0 && chmod(at.sun_path, 0600) == 0 && rename(at.sun_path, to.sun_path) == 0) ok = YES;
        else *why = [NSString stringWithFormat:@"core.sock: %s", strerror(errno)];
    } else *why = @"core.sock folder is not the one MinMacs made";
    unlink(at.sun_path);
    rmdir(dir.fileSystemRepresentation);
    return ok;
}

/// Waits until fd is readable or writable, at most until deadline. NO on timeout or error.
static BOOL WaitFor(int fd, short events, NSDate *deadline) {
    for (;;) {
        double left = deadline.timeIntervalSinceNow;
        if (left <= 0) return NO;
        struct pollfd p = { .fd = fd, .events = events };
        int r = poll(&p, 1, (int)ceil(left * 1000));
        if (r > 0) return YES;
        if (r == 0) return NO;
        if (errno != EINTR) return NO;
    }
}

/// Reads one line, or everything until the peer closes. nil on timeout, error or a line past kMaxRequest.
static NSData *ReadLine(int fd, NSDate *deadline) {
    NSMutableData *d = [NSMutableData new];
    char buf[16384];
    for (;;) {
        if (!WaitFor(fd, POLLIN, deadline)) return nil;
        ssize_t n = read(fd, buf, sizeof buf);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n < 0) return nil;
        if (n == 0) return d.length ? d : nil;
        char *nl = memchr(buf, '\n', (size_t)n);
        [d appendBytes:buf length:nl ? (size_t)(nl - buf) : (size_t)n];
        if (nl) return d;
        if (d.length > kMaxRequest) return nil;
    }
}

static BOOL WriteAll(int fd, NSData *d, NSDate *deadline) {
    const uint8_t *p = d.bytes; size_t left = d.length;
    while (left > 0) {
        if (!WaitFor(fd, POLLOUT, deadline)) return NO;
        ssize_t n = write(fd, p, left);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return NO;
        p += n; left -= (size_t)n;
    }
    return YES;
}

static NSData *Line(NSDictionary *obj) {
    NSData *j = [NSJSONSerialization isValidJSONObject:obj]
        ? [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys error:nil] : nil;
    NSMutableData *d = [j ?: [@"{\"error\":\"the reply is not JSON\"}" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [d appendBytes:"\n" length:1];
    return d;
}

static void Answer(int c, NSDictionary *(^handler)(NSDictionary *), dispatch_queue_t socketQueue);

/// The instance lock this process holds while it serves, or -1. Touched under @synchronized (MMCoreSocket.class).
static int gLockFd = -1;

@implementation MMCoreSocket {
    int _listen;
    dispatch_source_t _accept;
    NSDictionary *(^_handler)(NSDictionary *);
    NSString *_path;
}

+ (instancetype)serve:(NSDictionary *(^)(NSDictionary *request))handler error:(NSString **)error {
    @synchronized (self) {
        if (gLockFd >= 0) { if (error) *error = @"this process already serves core.sock"; return nil; }
        // 1. The instance lock. A second MinMacs stops here, so it never removes the first one's socket.
        int lock = open(LockPath().fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (lock < 0) { if (error) *error = [NSString stringWithFormat:@"cannot open core.lock: %s", strerror(errno)]; return nil; }
        if (flock(lock, LOCK_EX | LOCK_NB) != 0) {
            close(lock);
            if (error) *error = @"another MinMacs holds the instance lock";
            return nil;
        }
        NSString *path = MMCoreSocketPath();
        struct sockaddr_un addr;
        if (!Address(path, &addr)) { close(lock); if (error) *error = @"the support folder path is too long for core.sock"; return nil; }
        // 2. The socket. A file left by a crash is replaced, which is safe because the lock is ours.
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) { close(lock); if (error) *error = [NSString stringWithFormat:@"socket: %s", strerror(errno)]; return nil; }
        fcntl(fd, F_SETFD, FD_CLOEXEC);
        // Bound in a folder of its own that only this uid can enter, set to 0600 there, then renamed into place, so
        // no other uid can connect before the chmod. Never through umask: the umask is the whole process's, and a
        // folder another thread made in that moment was made 0600, with no way in, which is how core/ once lost
        // its x bit and every move to the Trash was refused.
        NSString *why = nil;
        if (!BindPrivately(fd, path, &why) || listen(fd, 16) != 0) {
            if (!why) why = [NSString stringWithFormat:@"core.sock: %s", strerror(errno)];
            close(fd); unlink(addr.sun_path); close(lock);
            if (error) *error = why;
            return nil;
        }
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        gLockFd = lock;
        MMCoreSocket *s = [MMCoreSocket new];
        s->_listen = fd;
        s->_handler = [handler copy];
        s->_path = path;
        dispatch_queue_t q = MMQueue(@"core", @"socket", QOS_CLASS_UTILITY);
        s->_accept = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, q);
        __weak MMCoreSocket *weak = s;
        dispatch_source_set_event_handler(s->_accept, ^{ [weak acceptAll]; });
        dispatch_source_set_cancel_handler(s->_accept, ^{ close(fd); });
        dispatch_resume(s->_accept);
        return s;
    }
}

/// Runs on the socket queue: takes each waiting connection and hands it on at once.
/// Reading and writing happen off the socket queue, so a peer that connects and sends nothing never holds up
/// the next one. Only the handler runs on the socket queue, one request at a time.
- (void)acceptAll {
    dispatch_queue_t socketQueue = MMQueue(@"core", @"socket", QOS_CLASS_UTILITY);
    NSDictionary *(^handler)(NSDictionary *) = _handler;
    for (;;) {
        int c = accept(_listen, NULL, NULL);
        if (c < 0) return;   // EAGAIN: nothing more waits
        fcntl(c, F_SETFD, FD_CLOEXEC);
        fcntl(c, F_SETNOSIGPIPE, 1);
        fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool { Answer(c, handler, socketQueue); }
            close(c);
        });
    }
}

/// 3. The same-uid check, then one request and one reply. The handler runs on socketQueue.
static void Answer(int c, NSDictionary *(^handler)(NSDictionary *), dispatch_queue_t socketQueue) {
    uid_t uid = (uid_t)-1; gid_t gid;
    if (getpeereid(c, &uid, &gid) != 0 || uid != getuid()) {
        os_log(SocketLog(), "closed a core.sock peer with uid %d", (int)uid);
        return;   // closed without a reply
    }
    NSData *line = ReadLine(c, [NSDate dateWithTimeIntervalSinceNow:kReadLimit]);
    id req = line ? [NSJSONSerialization JSONObjectWithData:line options:0 error:nil] : nil;
    __block NSDictionary *reply;
    if (![req isKindOfClass:NSDictionary.class]) reply = @{@"error": @"the request is not a JSON object"};
    else {
        void (^run)(void) = ^{
            @try { reply = handler ? handler(req) : nil; }
            @catch (NSException *e) { reply = @{@"error": e.reason ?: e.name}; }
        };
        // ping skips the line, so a long verb in the app never makes the CLI think no app runs.
        if ([req[@"verb"] isEqual:@"ping"]) run(); else dispatch_sync(socketQueue, run);
        if (![reply isKindOfClass:NSDictionary.class]) reply = @{@"error": @"no reply"};
    }
    WriteAll(c, Line(reply), [NSDate dateWithTimeIntervalSinceNow:kReadLimit]);
}

- (void)stop {
    @synchronized (MMCoreSocket.class) {
        if (!_accept) return;
        dispatch_source_cancel(_accept);
        _accept = nil;
        struct sockaddr_un addr;
        if (Address(_path, &addr)) unlink(addr.sun_path);
        if (gLockFd >= 0) { flock(gLockFd, LOCK_UN); close(gLockFd); gLockFd = -1; }
    }
}

- (void)dealloc { [self stop]; }

+ (NSDictionary *)ask:(NSDictionary *)request timeout:(NSTimeInterval)timeout {
    if (![NSJSONSerialization isValidJSONObject:request ?: @{}]) return nil;
    struct sockaddr_un addr;
    if (!Address(MMCoreSocketPath(), &addr)) return nil;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(fd, F_SETNOSIGPIPE, 1);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0.01)];
    NSDictionary *reply = nil;
    int r = connect(fd, (struct sockaddr *)&addr, addr.sun_len);
    BOOL connected = r == 0 || (errno == EINPROGRESS && WaitFor(fd, POLLOUT, deadline));
    if (connected) {
        int soerr = 0; socklen_t len = sizeof soerr;
        if (r != 0) getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &len);
        if (soerr == 0 && WriteAll(fd, Line(request ?: @{}), deadline)) {
            NSData *line = ReadLine(fd, deadline);
            id j = line ? [NSJSONSerialization JSONObjectWithData:line options:0 error:nil] : nil;
            if ([j isKindOfClass:NSDictionary.class]) reply = j;
        }
    }
    close(fd);
    return reply;
}

@end

BOOL MMAnotherInstanceRuns(void) {
    @synchronized (MMCoreSocket.class) {
        if (gLockFd >= 0) return NO;   // this process holds it
        int fd = open(LockPath().fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (fd < 0) return NO;
        BOOL held = flock(fd, LOCK_EX | LOCK_NB) != 0 && errno == EWOULDBLOCK;
        if (!held) flock(fd, LOCK_UN);
        close(fd);
        return held;
    }
}
