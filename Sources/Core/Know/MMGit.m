// MMGit and MMGitPath, pattern P24. Ported from WFGit and WFGitPath in WorkForest's Common.m:71-105,
// on top of MMRun, so a git that hangs is stopped at its time limit and its pipes are drained on one thread.
#import "Core/Know/MMGit.h"

NSString *MMGitPath(void) {
    NSString *forced = NSProcessInfo.processInfo.environment[@"MINMACS_GIT"];
    if (forced.length) return [NSFileManager.defaultManager isExecutableFileAtPath:forced] ? forced : nil;
    static NSString *found; static dispatch_once_t once;
    dispatch_once(&once, ^{
        // /usr/bin/git without the command line tools asks the person to install them, so it is never used.
        for (NSString *p in @[@"/Library/Developer/CommandLineTools/usr/bin/git", @"/opt/homebrew/bin/git", @"/usr/local/bin/git",
                              @"/Applications/Xcode.app/Contents/Developer/usr/bin/git"])
            if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) { found = p; break; }
    });
    return found;
}

/// What every git child gets on top of MMRun's clean environment.
static NSDictionary<NSString *, NSString *> *GitEnvironment(void) {
    static NSDictionary *env; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *e = [@{ @"GIT_OPTIONAL_LOCKS": @"0", @"GIT_TERMINAL_PROMPT": @"0", @"GIT_PAGER": @"cat",
                                     @"LC_ALL": @"C", @"GIT_ASKPASS": @"/usr/bin/false", @"SSH_ASKPASS": @"/usr/bin/false" } mutableCopy];
        NSDictionary *ours = NSProcessInfo.processInfo.environment;
        for (NSString *k in @[@"GIT_CONFIG_GLOBAL", @"GIT_CONFIG_NOSYSTEM"]) if (ours[k]) e[k] = ours[k];
        env = e;
    });
    return env;
}

/// Runs git with input on stdin. The CLI and the checks may call it from any thread but main.
NSString *MMGitInput(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status) {
    if (status) *status = -1;
    if (NSThread.isMainThread) return nil;   // main never waits on a process
    NSString *git = MMGitPath();
    if (!git || !dir.length) return nil;
    NSData *out = nil;
    MMRunResult r = MMRun(git, [@[@"-C", dir, @"--no-pager"] arrayByAddingObjectsFromArray:args ?: @[]], input,
                          GitEnvironment(), nil, timeout, &out, NULL);
    if (!r.didRun || r.timedOut) return nil;
    if (status) *status = r.status;
    NSString *s = [[NSString alloc] initWithData:out ?: [NSData data] encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding];
    while ([s hasSuffix:@"\n"]) s = [s substringToIndex:s.length - 1];
    return s;
}

NSString *MMGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status) {
    return MMGitInput(dir, args, nil, timeout, status);
}

/// git one | git patch-id --stable, piped through /bin/sh so a long diff streams and is never held in memory.
/// That pipe took WorkForest's peak from 1,192 MB to 3 MB in TESTS.md question 7. Returns patch-id's output.
NSString *MMGitPatchIds(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status) {
    if (status) *status = -1;
    if (NSThread.isMainThread) return nil;
    NSString *git = MMGitPath();
    if (!git || !dir.length) return nil;
    // $0 is git and $1 the folder. The rest are the first git's arguments, passed through untouched.
    NSString *script = @"g=\"$0\"; d=\"$1\"; shift; \"$g\" -C \"$d\" --no-pager \"$@\" | \"$g\" -C \"$d\" patch-id --stable";
    NSData *out = nil;
    MMRunResult r = MMRun(@"/bin/sh", [@[@"-c", script, git, dir] arrayByAddingObjectsFromArray:args ?: @[]], input,
                          GitEnvironment(), nil, timeout, &out, NULL);
    if (!r.didRun || r.timedOut) return nil;
    if (status) *status = r.status;
    return [[NSString alloc] initWithData:out ?: [NSData data] encoding:NSUTF8StringEncoding];
}
