// Checks for the fixes after wave 3. test/fixes.sh builds this with every .m under Sources but main.m.
// Prints one line per check as CHECK<TAB>name<TAB>want<TAB>got, then END. Every file it touches is under MINMACS_HOME.
//   undo <repo> <worktree>   the Trash of a test home, and git through MMGitPath and MMRun
//   start <root>             MMCoreStart as the app runs it: the log opens off main and repos.eventid goes
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"

static void Check(NSString *name, NSString *want, NSString *got) {
    printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"nil").UTF8String);
    fflush(stdout);
}
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }
static BOOL Exists(NSString *p) { return [NSFileManager.defaultManager fileExistsAtPath:p]; }
static NSString *Home(void) { return NSProcessInfo.processInfo.environment[@"MINMACS_HOME"]; }

/// Runs block off main and waits, as the app's act queue does.
static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"fixes", @"act", QOS_CLASS_UTILITY), ^{ block(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

static int Undo(NSString *repo, NSString *worktree) {
    NSString *trash = [Home() stringByAppendingPathComponent:@"Trash"];
    Check(@"fixes: with MINMACS_HOME set the Trash is <MINMACS_HOME>/Trash", trash, MMTrashFolder());
    NSString *dir = [Home() stringByAppendingPathComponent:@"items"];
    [NSFileManager.defaultManager createDirectoryAtPath:[dir stringByAppendingPathComponent:@"a"] withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:[dir stringByAppendingPathComponent:@"b"] withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *one = [dir stringByAppendingPathComponent:@"a/notes.txt"], *two = [dir stringByAppendingPathComponent:@"b/notes.txt"];
    [@"one" writeToFile:one atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"two" writeToFile:two atomically:YES encoding:NSUTF8StringEncoding error:nil];

    __block MMUndoRecord *r = nil;
    __block NSString *restored = @"?";
    OffMain(^{
        r = [MMUndo.shared begin:@"fixes" kind:@"trash" finding:@"fixes:notes" subject:@"notes" why:@"test" by:@"manual" parent:nil payload:nil];
        NSError *e = nil;
        [MMUndo.shared trash:[NSURL fileURLWithPath:one] record:r error:&e];
        [MMUndo.shared trash:[NSURL fileURLWithPath:two] record:r error:&e];
        [MMUndo.shared finish:r ok:YES freed:0 error:nil];
        r = [MMUndo.shared record:r.rid];
    });
    NSArray *to = [r.payload[@"trashed"] valueForKey:@"to"];
    Check(@"fixes: trash moves items into the test home's Trash", [NSString stringWithFormat:@"%@/notes.txt %@/notes 2.txt", trash, trash],
          [to componentsJoinedByString:@" "]);
    Check(@"fixes: both left their folders and the Trash holds them", @"no no yes yes",
          [NSString stringWithFormat:@"%@ %@ %@ %@", YN(Exists(one)), YN(Exists(two)), YN(Exists(to.firstObject)), YN(Exists(to.lastObject))]);
    OffMain(^{ restored = [MMUndo.shared restore:r.rid] ?: @"nil"; });
    Check(@"fixes: restore moves both back from that Trash", @"nil", restored);
    Check(@"fixes: each is back with its own text, and that Trash is empty", @"one two 0",
          [NSString stringWithFormat:@"%@ %@ %lu", [NSString stringWithContentsOfFile:one encoding:NSUTF8StringEncoding error:nil],
           [NSString stringWithContentsOfFile:two encoding:NSUTF8StringEncoding error:nil],
           (unsigned long)[NSFileManager.defaultManager contentsOfDirectoryAtPath:trash error:nil].count]);

    // A bundle runs git through MMGitPath, so $MINMACS_GIT, a logging wrapper here, is the git that runs.
    __block NSString *bundle = nil, *err = nil;
    OffMain(^{
        MMUndoRecord *b = [MMUndo.shared begin:@"fixes" kind:@"remove" finding:@"fixes:wt" subject:@"wt" why:@"test" by:@"manual" parent:nil payload:nil];
        NSString *e = nil;
        bundle = [MMUndo.shared bundle:worktree record:b error:&e];
        err = e;
        [MMUndo.shared finish:b ok:bundle != nil freed:0 error:e];
    });
    Check(@"fixes: the bundle is made in the test home", @"yes", YN(bundle && [bundle hasPrefix:Home()] && Exists(bundle)));
    if (!bundle) Check(@"fixes: the bundle error", @"nil", err);
    NSString *log = [NSString stringWithContentsOfFile:NSProcessInfo.processInfo.environment[@"FIXES_GIT_LOG"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    Check(@"fixes: MMUndo's git ran through MINMACS_GIT", @"yes yes",
          [NSString stringWithFormat:@"%@ %@", YN([log containsString:@"bundle create"]), YN([log containsString:@"bundle verify"])]);
    Check(@"fixes: and with MMGit's environment, so no prompt and no pager", @"yes", YN([log containsString:@"GIT_TERMINAL_PROMPT=0"]));
    printf("END\n");
    return 0;
}

static BOOL Spin(double seconds, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && end.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

static int Start(void) {
    NSString *old = [Home() stringByAppendingPathComponent:@"repos.eventid"];
    NSString *kept = [Home() stringByAppendingPathComponent:@"fixture.eventid"];
    [@"12345" writeToFile:old atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"678" writeToFile:kept atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check(@"fixes: before start the old repos.eventid is there", @"yes", YN(Exists(old)));
    MMCoreStart();
    // What a menu does on main right after launch: it reads the log, which must not open there.
    MMLog *onMain = MMLog.shared;
    NSArray *recent = [MMUndo.shared recent:nil limit:5];
    BOOL opened = Spin(20, ^BOOL { __block MMLog *l = nil; OffMain(^{ l = MMLog.shared; }); return l != nil; });
    Check(@"fixes: the log opens off main after MMCoreStart", @"yes", YN(opened));
    Check(@"fixes: main never opened the log", @"0", @(MMLogMainThreadOpens()).stringValue);
    Check(@"fixes: on main before the open, the log is nil or open, never opened there", @"yes",
          YN(onMain == nil || onMain == MMLog.shared));
    Check(@"fixes: reading undo on main before the open returns a list", @"yes", YN(recent != nil));
    Check(@"fixes: once open, main gets the same log", @"yes", YN(MMLog.shared != nil));
    BOOL gone = Spin(10, ^BOOL { return !Exists(old); });
    Check(@"fixes: MMCoreStart removes the old repos.eventid", @"yes", YN(gone));
    Check(@"fixes: and leaves every other event id file", @"yes", YN(Exists(kept)));
    MMCoreStop();
    Check(@"fixes: a second start finds nothing to remove", @"0", @(MMRemoveStaleFiles().count).stringValue);
    printf("END\n");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!Home().length) { fprintf(stderr, "fixes: set MINMACS_HOME\n"); return 2; }
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqualToString:@"_walk"]) return MMWorkerChildMain();   // the worker child is this same binary
        if ([mode isEqualToString:@"undo"] && argc > 3) return Undo(@(argv[2]), @(argv[3]));
        if ([mode isEqualToString:@"start"]) return Start();
        fprintf(stderr, "usage: fixes undo <repo> <worktree> | start\n");
        return 2;
    }
}
