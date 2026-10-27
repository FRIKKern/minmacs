// The LocoHost CLI for test/locohost.sh. It links Sources/Core, Sources/UI, Sources/CLI and Sources/Experts/LocoHost,
// registers LocoHost alone and runs each verb through the real verb registry, as the app runs a verb handed over
// core.sock: MMArgs collects the output, and a verb that changes things may run, since this process stands in for
// the app. No app runs, so the snapshot is the CLI's cold one from Sources/CLI.
// `verbs` lists LocoHost's MMVerbSpecs. `_menureads` and `_gotime <port>` are checks of the menu on the main thread.
#import <Foundation/Foundation.h>
#import "Experts/LocoHost/MMLocoHost.h"
#import "CLI/MMCLI.h"

/// The undo log and the keeps read on the main thread while LocoHost draws its menu, its cards, badge and label.
static int MenuReads(void) {
    MMSnapshot *s = MMCLISettledSnapshot(NO);
    NSUInteger logBefore = MMLogMainThreadQueries(), keepsBefore = MMKeepMainThreadReads();
    MMMenuSpec *m = [MMLocoHost.shared menuFor:s];
    for (MMFinding *f in [s findingsFor:@"locohost"]) (void)[MMLocoHost.shared cardFor:f snapshot:s];
    (void)[MMLocoHost.shared badgeFor:s]; (void)[MMLocoHost.shared accessibilityStateFor:s];
    printf("%lu %lu %lu\n", (unsigned long)(MMLogMainThreadQueries() - logBefore), (unsigned long)(MMKeepMainThreadReads() - keepsBefore),
           (unsigned long)m.sections.count);
    return 0;
}

/// How long the menu's Go To blocks the main thread, in tenths of a second, for the server on this port.
static int GoTime(NSString *port) {
    MMSnapshot *s = MMCLISettledSnapshot(NO);
    MMFinding *f = nil;
    for (MMFinding *x in [s findingsFor:@"locohost"]) if ([x.facts[@"ports"] containsObject:@(port.integerValue)]) f = x;
    if (!f) { fprintf(stderr, "no localhost on %s\n", port.UTF8String); return 1; }
    MMLHHost *h = [MMLHHost fromJSON:f.facts];
    MMProcKey k = { h.pid, h.startSec };
    if (!MMWhereIs(k, s.facts.sample, YES)) { fprintf(stderr, "no place for :%s\n", port.UTF8String); return 1; }   // as Know has it in the app
    MMLHView *v = [MMLocoHost.shared viewFor:s];
    NSDate *t = NSDate.date;
    v.act(@"go", f.findingID, NO);
    printf("%ld\n", (long)round(-t.timeIntervalSinceNow * 10));
    fflush(stdout);
    // Let the go finish off main, so the fake tmux it runs ends before this process does.
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:8]];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MMRegisterExpert(MMLocoHost.shared);
        if (argc < 2) { fprintf(stderr, "usage: locohost <verb> [args]\n"); return 2; }
        NSString *verb = @(argv[1]);
        if ([verb isEqualToString:@"verbs"]) {
            for (MMVerbSpec *v in MMLocoHost.shared.verbs) printf("%s\t%d\t%s\n", v.verb.UTF8String, v.mutates, v.usage.UTF8String);
            printf("legacyName\t%s\n", MMLocoHost.shared.legacyName.UTF8String);
            printf("registered\t%s\n", MMExpertNamed(@"locohost") == MMLocoHost.shared ? "yes" : "no");
            return 0;
        }
        if ([verb isEqualToString:@"_menureads"]) return MenuReads();
        if ([verb isEqualToString:@"_gotime"] && argc > 2) return GoTime(@(argv[2]));
        NSMutableArray *words = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [words addObject:@(argv[i])];
        NSDictionary *r = MMCLIReply(@{@"cli": words, @"program": @"locohost", @"cwd": NSFileManager.defaultManager.currentDirectoryPath});
        fputs([r[@"out"] UTF8String] ?: "", stdout);
        fputs([r[@"err"] UTF8String] ?: "", stderr);
        fflush(stdout);
        return [r[@"status"] intValue];
    }
}
