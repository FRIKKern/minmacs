// Test tool: drives Sources/Rules.m against the rules file named by MINMACS_RULES_FILE.
//   rulecheck verdict <bundle-id>                 prints keep, close or unsorted
//   rulecheck set keep|close|unsorted <bundle-id>
//   rulecheck serving <bundle-id>                 prints yes when its listeners are ignored, else no
//   rulecheck set-serving yes|no <bundle-id>
//   rulecheck list <key>                          prints one entry per line: keep, close, unsorted, noise, work, ignoreServing
// Built by test.sh: clang -fobjc-arc -ISources tools/rulecheck.m Sources/Rules.m -framework Foundation
#import "Rules.h"

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (!getenv("MINMACS_RULES_FILE")) { fprintf(stderr, "rulecheck: set MINMACS_RULES_FILE to a fixture rules file\n"); return 2; }
        if (argc < 3) return 2;
        MMRules *r = MMRules.shared;
        NSString *cmd = @(argv[1]), *a = @(argv[2]), *b = argc > 3 ? @(argv[3]) : nil;
        if ([cmd isEqualToString:@"verdict"]) {
            MMVerdict v = [r verdictFor:a];
            printf("%s\n", v == MMKeep ? "keep" : v == MMClose ? "close" : "unsorted");
        } else if ([cmd isEqualToString:@"set"] && b) {
            NSDictionary *v = @{@"keep": @(MMKeep), @"close": @(MMClose), @"unsorted": @(MMUnsorted)};
            if (!v[a]) return 2;
            [r setVerdict:[v[a] integerValue] forBundleID:b];
        } else if ([cmd isEqualToString:@"serving"]) {
            printf("%s\n", [r ignoresServing:a] ? "yes" : "no");
        } else if ([cmd isEqualToString:@"set-serving"] && b) {
            [r setIgnoresServing:[a isEqualToString:@"yes"] forBundleID:b];
        } else if ([cmd isEqualToString:@"list"]) {
            NSDictionary *l = @{@"keep": r.keep, @"close": r.close, @"unsorted": r.unsorted, @"noise": r.noiseHosts,
                                @"work": r.workHosts, @"ignoreServing": r.ignoreServing};
            if (!l[a]) return 2;
            for (NSString *e in l[a]) printf("%s\n", e.UTF8String);
        } else return 2;
    }
    return 0;
}
