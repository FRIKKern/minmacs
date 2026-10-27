// MMRun, pattern P23. Ported from WFGitInput in WorkForest's Common.m.
// The rest of MMGit.h comes in phase 2. Where uses MMRun to ask cmux and tmux.
#import "Core/Know/MMGit.h"
#import <signal.h>

/// The environment a child starts from. env adds to this, never to the app's own environment.
static NSDictionary<NSString *, NSString *> *CleanEnvironment(void) {
    NSDictionary *ours = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *e = [@{ @"PATH": @"/usr/bin:/bin:/usr/sbin:/sbin", @"LC_ALL": @"C" } mutableCopy];
    for (NSString *k in @[@"HOME", @"USER", @"LOGNAME", @"TMPDIR"]) if (ours[k]) e[k] = ours[k];
    return e;
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
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe], *in = input ? [NSPipe pipe] : nil;
    t.standardOutput = out;
    t.standardError = err;
    t.standardInput = in ?: [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return r;
    r.didRun = YES;

    // Both pipes are read at once, so a child that fills one never blocks on it.
    __block NSData *o = nil, *x = nil;
    dispatch_group_t g = dispatch_group_create();
    dispatch_queue_t gq = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_group_async(g, gq, ^{ o = [out.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_async(g, gq, ^{ x = [err.fileHandleForReading readDataToEndOfFile]; });
    if (in) dispatch_async(gq, ^{
        @try { [in.fileHandleForWriting writeData:input]; } @catch (NSException *ex) {}
        [in.fileHandleForWriting closeFile];
    });
    if (dispatch_group_wait(g, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        r.timedOut = YES;
        pid_t pid = t.processIdentifier;
        [t terminate];
        // SIGKILL after one second, only for the child this call started and only while it still runs.
        for (int i = 0; i < 20 && t.running; i++) usleep(50000);
        if (t.running && pid > 1) kill(pid, SIGKILL);
        [t waitUntilExit];
        return r;   // the readers may still run, so their output is not used
    }
    [t waitUntilExit];
    r.status = t.terminationStatus;
    if (outData) *outData = o;
    if (errData) *errData = x;
    return r;
}
