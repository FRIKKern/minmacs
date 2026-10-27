// The LocoHost CLI for test/locohost.sh while the verb registry in Sources/CLI does not run expert verbs yet.
// It links Sources/Core, Sources/UI and Sources/Experts/LocoHost, and runs each verb through LocoHost's MMVerbSpec,
// with an MMArgs that holds the raw words. Once the minmacs binary answers `locohost free`, the section uses it instead.
#import <Foundation/Foundation.h>
#import "Experts/LocoHost/MMLocoHost.h"

@interface MMArgs : NSObject
@property (copy) NSArray<NSString *> *argv;
@end
@implementation MMArgs
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MMRegisterExpert(MMLocoHost.shared);
        if (argc < 2) { fprintf(stderr, "usage: locohost <verb> [args]\n"); return 2; }
        NSString *verb = @(argv[1]);
        for (MMVerbSpec *v in MMLocoHost.shared.verbs) {
            if (![v.verb isEqualToString:verb]) continue;
            MMArgs *a = [MMArgs new];
            NSMutableArray *words = [NSMutableArray new];
            for (int i = 2; i < argc; i++) [words addObject:@(argv[i])];
            a.argv = words;
            int r = v.run(a);
            fflush(stdout);
            return r;
        }
        if ([verb isEqualToString:@"verbs"]) {
            for (MMVerbSpec *v in MMLocoHost.shared.verbs) printf("%s\t%d\t%s\n", v.verb.UTF8String, v.mutates, v.usage.UTF8String);
            printf("legacyName\t%s\n", MMLocoHost.shared.legacyName.UTF8String);
            printf("registered\t%s\n", MMExpertNamed(@"locohost") == MMLocoHost.shared ? "yes" : "no");
            return 0;
        }
        fprintf(stderr, "locohost: unknown verb '%s'\n", argv[1]);
        return 2;
    }
}
