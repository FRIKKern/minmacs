// The WorkForest CLI for test/workforest.sh. It links every .m under Sources except main.m, registers WorkForest,
// and runs each verb the way the app runs a verb handed over core.sock, so a verb that changes things runs too.
// The facts are the cold CLI's own, from Sources/CLI: Core's repo index walks $MINMACS_ROOTS in the worker and
// reads the git facts of the fixture repos itself. Processes come from Senses and sessions from Know.
// Nothing here runs git or hands facts over by hand.
// The name it runs under picks the program, so a symlink named workforest gets WorkForest 0.1's syntax.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Experts/WorkForest/MMWorkForest.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child is this same binary
        MMRegisterExpert(MMWorkForestExpert.shared);
        if (argc > 1 && !strcmp(argv[1], "_verbs")) {
            for (MMVerbSpec *v in MMWorkForestExpert.shared.verbs) printf("%s\t%d\n", v.verb.UTF8String, v.mutates);
            printf("legacyName\t%s\n", MMWorkForestExpert.shared.legacyName.UTF8String);
            printf("registered\t%s\n", MMExpertNamed(@"workforest") == MMWorkForestExpert.shared ? "yes" : "no");
            NSArray *w = MMLegacyWords(@"workforest", @[@"remove", @"/x", @"--yes"]);
            printf("shim\t%s\n", [w componentsJoinedByString:@" "].UTF8String);
            return 0;
        }
        NSMutableArray *words = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [words addObject:@(argv[i])];
        if (!words.count) [words addObject:@"list"];
        NSDictionary *req = @{@"cli": words, @"program": MMProgramName(argv[0]), @"cwd": NSFileManager.defaultManager.currentDirectoryPath};
        __block NSDictionary *reply;
        // As in the app: the verb runs off main, where MMRunAction may gather fresh facts.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ reply = MMCLIReply(req); dispatch_semaphore_signal(done); });
        while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW)) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        fputs([reply[@"out"] description].UTF8String ?: "", stdout);
        fputs([reply[@"err"] description].UTF8String ?: "", stderr);
        fflush(stdout);
        return [reply[@"status"] intValue];
    }
}
