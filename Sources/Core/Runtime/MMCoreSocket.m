// core.sock and the instance lock, pattern P63. Ported from NN internal/ipc/server.go:82-160:
// an flock instance lock, then the socket, then a same-uid check with getpeereid on every connection.
// One request and one reply per connection, each one JSON object. The client writes its request and shuts
// its write side, so the server reads to EOF. The server writes the reply and closes.
// A second +serve: in the same process adds its handler to the one server. The newest handler that returns
// a reply answers, so the CLI's handler and Core's own can share the socket.
#import "Core/Runtime/MMCoreSocket.h"
#import "Core/Runtime/MMRuntime.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSString *MMRuntimeSupportDir(void);

NSString *MMCoreSocketPath(void) { return [MMRuntimeSupportDir() stringByAppendingPathComponent:@"core.sock"]; }
static NSString *LockPath(void) { return [MMRuntimeSupportDir() stringByAppendingPathComponent:@"core.lock"]; }

static const size_t kMaxMessage = 4 << 20;             // a reply carries a verb's whole output, so allow a few MB
static int gLockFD = -1;                                // held for the life of the process once taken

/// Takes the instance lock for this process. NO when another process holds it.
static BOOL TakeLock(void) {
    @synchronized (NSFileManager.class) {
        if (gLockFD >= 0) return YES;
        int fd = open(LockPath().fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (fd < 0) return NO;
        if (flock(fd, LOCK_EX | LOCK_NB) != 0) { close(fd); return NO; }
        NSString *pid = [NSString stringWithFormat:@"%d\n", getpid()];
        ftruncate(fd, 0);
        write(fd, pid.UTF8String, strlen(pid.UTF8String));
        gLockFD = fd;
        return YES;
    }
}

BOOL MMAnotherInstanceRuns(void) {
    @synchronized (NSFileManager.class) {
        if (gLockFD >= 0) return NO;
        int fd = open(LockPath().fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (fd < 0) return NO;
        BOOL held = flock(fd, LOCK_EX | LOCK_NB) != 0 && errno == EWOULDBLOCK;
        close(fd);   // closing drops a lock this probe took
        return held;
    }
}

static BOOL FillAddress(struct sockaddr_un *a, NSString *path) {
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    const char *p = path.fileSystemRepresentation;
    if (strlen(p) >= sizeof a->sun_path) return NO;
    strlcpy(a->sun_path, p, sizeof a->sun_path);
    return YES;
}

/// Waits until fd is ready for events, up to the deadline. NO on a timeout or an error.
static BOOL WaitFor(int fd, short events, NSDate *deadline) {
    for (;;) {
        int ms = (int)MAX(0, deadline.timeIntervalSinceNow * 1000);
        struct pollfd p = { fd, events, 0 };
        int r = poll(&p, 1, ms);
        if (r > 0) return YES;
        if (r == 0) return NO;
        if (errno != EINTR) return NO;
    }
}

static BOOL WriteAll(int fd, NSData *d, NSDate *deadline) {
    const uint8_t *b = d.bytes; size_t left = d.length;
    while (left) {
        if (!WaitFor(fd, POLLOUT, deadline)) return NO;
        ssize_t n = write(fd, b, left);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) return NO;
        b += n; left -= (size_t)n;
    }
    return YES;
}

/// Reads to EOF. nil on a timeout, an error, or a message over the limit.
static NSData *ReadAll(int fd, NSDate *deadline) {
    NSMutableData *d = [NSMutableData new];
    uint8_t buf[16384];
    for (;;) {
        if (!WaitFor(fd, POLLIN, deadline)) return nil;
        ssize_t n = read(fd, buf, sizeof buf);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n < 0) return nil;
        if (n == 0) return d;
        [d appendBytes:buf length:(NSUInteger)n];
        if (d.length > kMaxMessage) return nil;
    }
}

static NSDictionary *Parse(NSData *d) {
    if (!d.length) return nil;
    id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [j isKindOfClass:NSDictionary.class] ? j : nil;
}

static NSData *Encode(NSDictionary *j) {
    if (![NSJSONSerialization isValidJSONObject:j]) return nil;
    return [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
}

@interface MMCoreSocket ()
@property (strong) dispatch_source_t source;
@property (strong) NSMutableArray *handlers;
@property int fd;
@end

static MMCoreSocket *gServer;

@implementation MMCoreSocket

+ (instancetype)serve:(NSDictionary *(^)(NSDictionary *request))handler error:(NSString **)error {
    @synchronized (self) {
        if (gServer) {
            if (handler) [gServer.handlers insertObject:[handler copy] atIndex:0];
            return gServer;
        }
        if (!TakeLock()) { if (error) *error = @"another MinMacs holds the instance lock"; return nil; }
        NSString *path = MMCoreSocketPath();
        struct sockaddr_un a;
        if (!FillAddress(&a, path)) { if (error) *error = [@"the socket path is too long: " stringByAppendingString:path]; return nil; }
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) { if (error) *error = @(strerror(errno)); return nil; }
        fcntl(fd, F_SETFD, FD_CLOEXEC);
        // The lock is ours, so a socket file left here is stale.
        unlink(a.sun_path);
        mode_t old = umask(0077);
        int b = bind(fd, (struct sockaddr *)&a, sizeof a);
        umask(old);
        if (b != 0 || chmod(a.sun_path, 0600) != 0 || listen(fd, 16) != 0) {
            if (error) *error = [NSString stringWithFormat:@"core.sock: %s", strerror(errno)];
            close(fd); return nil;
        }
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        MMCoreSocket *s = [MMCoreSocket new];
        s.fd = fd;
        s.handlers = [NSMutableArray new];
        if (handler) [s.handlers addObject:[handler copy]];
        dispatch_queue_t q = MMQueue(@"core", @"socket", QOS_CLASS_UTILITY);
        s.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, q);
        __weak MMCoreSocket *weak = s;
        dispatch_source_set_event_handler(s.source, ^{ @autoreleasepool { [weak acceptAll]; } });
        dispatch_source_set_cancel_handler(s.source, ^{ close(fd); });
        dispatch_resume(s.source);
        gServer = s;
        return s;
    }
}

- (void)acceptAll {
    for (;;) {
        int c = accept(self.fd, NULL, NULL);
        if (c < 0) return;
        fcntl(c, F_SETFD, FD_CLOEXEC);
        int nosig = 1;
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof nosig);
        [self answer:c];
        close(c);
    }
}

- (void)answer:(int)c {
    uid_t uid; gid_t gid;
    // Another user's process is closed with no reply. The socket's mode 0600 already keeps it out.
    if (getpeereid(c, &uid, &gid) != 0 || uid != geteuid()) return;
    fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK);
    NSDictionary *req = Parse(ReadAll(c, [NSDate dateWithTimeIntervalSinceNow:5]));
    if (!req) return;
    NSDictionary *reply = nil;
    NSArray *handlers;
    @synchronized (MMCoreSocket.class) { handlers = [self.handlers copy]; }
    for (NSDictionary *(^h)(NSDictionary *) in handlers) if ((reply = h(req))) break;
    if (!reply) reply = @{@"error": @"no handler for this request"};
    NSData *d = Encode(reply) ?: Encode(@{@"error": @"the reply is not JSON"});
    WriteAll(c, d, [NSDate dateWithTimeIntervalSinceNow:5]);
}

+ (NSDictionary *)ask:(NSDictionary *)request timeout:(NSTimeInterval)timeout {
    struct sockaddr_un a;
    if (!FillAddress(&a, MMCoreSocketPath())) return nil;
    struct stat st;
    if (stat(a.sun_path, &st) != 0 || !S_ISSOCK(st.st_mode)) return nil;
    NSData *body = Encode(request);
    if (!body) return nil;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    int nosig = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, sizeof nosig);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSDictionary *reply = nil;
    int r = connect(fd, (struct sockaddr *)&a, sizeof a);
    BOOL up = r == 0;
    if (!up && (errno == EINPROGRESS || errno == EAGAIN) && WaitFor(fd, POLLOUT, deadline)) {
        int err = 0; socklen_t len = sizeof err;
        up = getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0;
    }
    if (up && WriteAll(fd, body, deadline)) {
        shutdown(fd, SHUT_WR);
        reply = Parse(ReadAll(fd, deadline));
    }
    close(fd);
    return reply;
}

- (void)stop {
    @synchronized (MMCoreSocket.class) {
        if (gServer != self) return;
        dispatch_source_cancel(self.source);
        unlink(MMCoreSocketPath().fileSystemRepresentation);
        gServer = nil;
    }
}

@end
