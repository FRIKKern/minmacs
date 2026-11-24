// A mode pass of the servers rule, for test/log.sh: LocoHost's own pass after a review, run in a fixture home on one
// server it planned to stop. The server is no process at all, pid 0 and a port nobody listens on, so the fresh check
// before the stop keeps it and nothing is ever signaled. The pass writes its run row to this home's log, and the
// check reads it back through `minmacs log --json`. It links Sources but main.m and Shell, as test/locohost does.
// Usage: MINMACS_HOME=<fixture home> pass
#import <Foundation/Foundation.h>
#import "Experts/LocoHost/MMLocoHost.h"

@interface MMLocoHost (LogPass)
- (void)autoStop:(NSArray<NSArray *> *)todo review:(MMReview *)r mode:(MMMode)mode;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *home = getenv("MINMACS_HOME");
        if (!home || !strstr(home, "minmacs-test")) { fprintf(stderr, "pass: runs only in a test home\n"); return 2; }
        MMSetPref(@"locohost.mode", @"proactive");
        MMFinding *f = [MMFinding expert:@"locohost" kind:@"server" stableKey:@"logpass#dev" build:^(MMFindingBuilder *b) {
            b.title = @":1 Vite logpass"; b.instanceKey = @"logpass#dev";
            b.facts = @{@"ports": @[@1], @"pid": @0, @"framework": @"Vite", @"name": @"logpass"};
            b.proposal = [MMProposal verb:@"stop" title:@"Stop" reversibility:MMReversibleRestart];
        }];
        // On a queue of its own, as on the expert's act queue: no action runs on the main thread.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_queue_create("no.guerrilla.minmacs.test.logpass", DISPATCH_QUEUE_SERIAL), ^{
            [MMLocoHost.shared autoStop:@[@[f, @"idle for 6 h"]] review:nil mode:MMModeProactive];
            dispatch_semaphore_signal(done);
        });
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { fprintf(stderr, "pass: did not end\n"); return 1; }
        printf("END\n");
    }
    return 0;
}
