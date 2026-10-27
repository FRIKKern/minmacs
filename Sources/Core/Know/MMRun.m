// MMRun and MMRunTask, pattern P23. Ported from WFGitInput in WorkForest's Common.m.
// The rest of MMGit.h comes in phase 2. Where uses MMRun to ask cmux and tmux, and the review broker runs
// claude and codex through MMRunTask.
//
// One thread does all the pipe work with poll: it feeds stdin and drains stdout and stderr, so a child that
// fills one pipe never blocks on it, and nothing reads on another thread after the call returns.
// Past the time limit the child gets SIGTERM, then SIGKILL one second later. Half a second after that the
// pipes are closed even when a grandchild still holds them open.
// The child's exit comes from a kqueue NOTE_EXIT in the same poll, which does not reap it, so NSTask still does.
// Waiting for NSTask's running flag instead cost a 50 ms poll step or more on every run.
#import "Core/Know/MMGit.h"
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <sys/event.h>
#import <signal.h>
#import <unistd.h>

static const NSTimeInterval kKillAfter = 1;      // SIGKILL this long after SIGTERM
static const NSTimeInterval kDrainAfter = 0.5;   // pipes are closed this long after SIGKILL

/// The environment a child starts from. env adds to this, never to the app's own environment.
static NSDictionary<NSString *, NSString *> *CleanEnvironment(void) {
    NSDictionary *ours = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *e = [@{ @"PATH": @"/usr/bin:/bin:/usr/sbin:/sbin", @"LC_ALL": @"C" } mutableCopy];
    for (NSString *k in @[@"HOME", @"USER", @"LOGNAME", @"TMPDIR"]) if (ours[k]) e[k] = ours[k];
    return e;
}

static void NonBlocking(int fd) { fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); }

/// Reads what fd holds now into d. NO once the writer closed it or it failed.
static BOOL Drain(int fd, NSMutableData *d) {
    char buf[65536];
    for (;;) {
        ssize_t n = read(fd, buf, sizeof buf);
        if (n > 0) { [d appendBytes:buf length:(NSUInteger)n]; continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && errno == EAGAIN) return YES;
        return NO;
    }
}

MMRunResult MMRunTask(NSTask *t, NSData *input, NSTimeInterval timeout, NSData **outData, NSData **errData) {
    MMRunResult r = { .status = -1, .timedOut = NO, .didRun = NO };
    if (outData) *outData = nil;
    if (errData) *errData = nil;
    if (!t) return r;
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe], *in = input ? [NSPipe pipe] : nil;
    t.standardOutput = out;
    t.standardError = err;
    t.standardInput = in ?: [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return r;
    r.didRun = YES;
    pid_t pid = t.processIdentifier;

    // Our copies of the child's ends close now, so EOF arrives when the child and its children close theirs.
    [out.fileHandleForWriting closeFile];
    [err.fileHandleForWriting closeFile];
    if (in) [in.fileHandleForReading closeFile];
    int ofd = out.fileHandleForReading.fileDescriptor, efd = err.fileHandleForReading.fileDescriptor;
    int wfd = in ? in.fileHandleForWriting.fileDescriptor : -1;
    NonBlocking(ofd); NonBlocking(efd);
    if (wfd >= 0) {
        NonBlocking(wfd);
        fcntl(wfd, F_SETNOSIGPIPE, 1);   // a child that exits without reading its input gives EPIPE, not a signal
    }
    // A kqueue fd can be polled. It turns readable when the child exits.
    int kq = kqueue();
    BOOL exited = NO;
    if (kq >= 0) {
        struct kevent ke;
        EV_SET(&ke, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
        if (kevent(kq, &ke, 1, NULL, 0, NULL) < 0) { exited = errno == ESRCH; close(kq); kq = -1; }
    }
    BOOL outOpen = YES, errOpen = YES, inOpen = wfd >= 0;
    if (inOpen && !input.length) { [in.fileHandleForWriting closeFile]; inOpen = NO; }
    NSUInteger written = 0;
    NSMutableData *o = [NSMutableData new], *x = [NSMutableData new];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0)], *killAt = nil, *stopAt = nil;

    for (;;) {
        BOOL running = !exited && t.running;
        if (!outOpen && !errOpen && !inOpen && !running) break;
        NSDate *now = NSDate.date;
        if (!r.timedOut && [now compare:deadline] != NSOrderedAscending) {
            r.timedOut = YES;
            if (running) [t terminate];
            killAt = [now dateByAddingTimeInterval:kKillAfter];
        }
        if (killAt && [now compare:killAt] != NSOrderedAscending) {
            killAt = nil;
            // Only the child this call started, and only while it still runs.
            if (t.running && pid > 1) kill(pid, SIGKILL);
            stopAt = [now dateByAddingTimeInterval:kDrainAfter];
        }
        if (stopAt && [now compare:stopAt] != NSOrderedAscending) break;   // a grandchild may hold the pipes
        if (r.timedOut && !killAt && !stopAt && !running) stopAt = [now dateByAddingTimeInterval:kDrainAfter];

        struct pollfd p[4]; nfds_t n = 0;
        if (kq >= 0 && !exited) p[n++] = (struct pollfd){ .fd = kq, .events = POLLIN };
        if (outOpen) p[n++] = (struct pollfd){ .fd = ofd, .events = POLLIN };
        if (errOpen) p[n++] = (struct pollfd){ .fd = efd, .events = POLLIN };
        if (inOpen) p[n++] = (struct pollfd){ .fd = wfd, .events = POLLOUT };
        NSDate *next = stopAt ?: killAt ?: deadline;
        double wait = MIN(MAX(next.timeIntervalSinceNow, 0), 0.05);   // a short step also notices the exit
        int got = poll(n ? p : NULL, n, (int)ceil(wait * 1000));
        if (got < 0 && errno != EINTR) break;
        if (got <= 0) continue;
        for (nfds_t i = 0; i < n; i++) {
            if (!p[i].revents) continue;
            if (p[i].fd == kq) {
                struct kevent got1; struct timespec zero = {0, 0};
                if (kevent(kq, NULL, 0, &got1, 1, &zero) > 0) exited = YES;
            } else if (p[i].fd == ofd) outOpen = Drain(ofd, o);
            else if (p[i].fd == efd) errOpen = Drain(efd, x);
            else if (p[i].fd == wfd) {
                ssize_t w = write(wfd, (const uint8_t *)input.bytes + written, input.length - written);
                if (w > 0) written += (NSUInteger)w;
                if ((w < 0 && errno != EAGAIN && errno != EINTR) || written >= input.length || (p[i].revents & (POLLERR | POLLHUP))) {
                    [in.fileHandleForWriting closeFile];
                    inOpen = NO;
                }
            }
        }
    }
    if (kq >= 0) close(kq);
    [out.fileHandleForReading closeFile];
    [err.fileHandleForReading closeFile];
    if (inOpen) [in.fileHandleForWriting closeFile];
    if (r.timedOut) {
        if (t.running && pid > 1) kill(pid, SIGKILL);
        [t waitUntilExit];
        return r;   // the output of a child that ran past its limit is not used
    }
    [t waitUntilExit];
    r.status = t.terminationStatus;
    if (outData) *outData = o;
    if (errData) *errData = x;
    return r;
}

MMRunResult MMRun(NSString *path, NSArray<NSString *> *args, NSData *input, NSDictionary<NSString *, NSString *> *env,
                  NSString *cwd, NSTimeInterval timeout, NSData **outData, NSData **errData) {
    MMRunResult r = { .status = -1, .timedOut = NO, .didRun = NO };
    if (outData) *outData = nil;
    if (errData) *errData = nil;
    if (!path.length || ![NSFileManager.defaultManager isExecutableFileAtPath:path]) return r;
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args ?: @[];
    NSMutableDictionary *e = [CleanEnvironment() mutableCopy];
    [e addEntriesFromDictionary:env ?: @{}];
    t.environment = e;
    if (cwd.length) t.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    return MMRunTask(t, input, timeout, outData, errData);
}
