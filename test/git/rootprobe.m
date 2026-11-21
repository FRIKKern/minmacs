// Issue #130: the files outside the repo MinMacs reads, built as the app is, with no MM_TESTS. Prints Files and Own of
// MMGitOutside.m for the environment given as KEY=VALUE arguments, so a check can see that MINMACS_TEST_GIT_ROOT
// changes nothing in a build without MM_TESTS. Built with every other file of Sources/Core.
#include "Core/Know/MMGitOutside.m"

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSMutableDictionary *env = [NSMutableDictionary new];
        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            NSRange r = [a rangeOfString:@"="];
            if (r.location != NSNotFound) env[[a substringToIndex:r.location]] = [a substringFromIndex:r.location + 1];
        }
        NSArray *files = Files(env);
        NSSet *own = Own(env);
        if (!files) { printf("files nil\n"); return 0; }
        for (NSString *f in files) printf("%s %s\n", [own containsObject:f] ? "own" : "theirs", f.UTF8String);
        for (NSString *f in [own.allObjects sortedArrayUsingSelector:@selector(compare:)])
            if (![files containsObject:f]) printf("own only %s\n", f.UTF8String);
    }
    return 0;
}
