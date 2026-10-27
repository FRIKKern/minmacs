// Test doubles for the Graph and Review types Act reads. Graph and Review land in parallel with Act,
// so the Act test binary links these in their place. They hold values and do nothing else,
// except MMGraph, whose freshFactsFor: reads the fixture again through the block the test sets.
#import "doubles.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-protocol-property-synthesis"

@implementation MMProposal
+ (instancetype)verb:(NSString *)verb title:(NSString *)title reversibility:(MMReversibility)r {
    MMProposal *p = [MMProposal new];
    p.verb = verb; p.title = title; p.reversibility = r;
    return p;
}
@end

@implementation MMFinding
- (BOOL)kept { return self.keepReasons.count > 0; }
@end

@implementation MMFacts
@end

@implementation MMVerdict
@end

@implementation MMReview
@end

@implementation MMGraph
+ (instancetype)shared {
    static MMGraph *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [MMGraph new]; });
    return g;
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return self.gather ? self.gather(finding) : nil; }
@end
