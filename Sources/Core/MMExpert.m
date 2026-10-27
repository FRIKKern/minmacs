// The specs of MMExpert.h and the expert registry.
// The registry hands each expert to the graph and the review broker. It looks both up at run time,
// so the render tool and the expert's own checks can link the specs without the rest of Core.
#import "Core/MMExpert.h"

#pragma mark - Specs

@implementation MMActionSpec
+ (instancetype)title:(NSString *)title tail:(NSString *)tail run:(void (^)(BOOL option))run {
    MMActionSpec *a = [self new];
    a.title = title; a.tail = tail; a.run = run;
    return a;
}
@end

@implementation MMRowSpec
@end

@implementation MMSectionSpec
@end

@implementation MMMenuSpec
@end

@implementation MMCardFact
+ (instancetype)label:(NSString *)label value:(NSString *)value {
    MMCardFact *f = [self new];
    f.label = label; f.value = value;
    return f;
}
@end

@implementation MMCardSpec
@end

@implementation MMVerbSpec
+ (instancetype)verb:(NSString *)verb usage:(NSString *)usage mutates:(BOOL)mutates run:(int (^)(MMArgs *args))run {
    MMVerbSpec *v = [self new];
    v.verb = verb; v.usage = usage; v.mutates = mutates; v.run = run;
    return v;
}
@end

#pragma mark - Registry

static NSMutableArray<id<MMExpert>> *Registered(void) {
    static NSMutableArray *all; static dispatch_once_t once;
    dispatch_once(&once, ^{ all = [NSMutableArray new]; });
    return all;
}

/// Registers once per expertID. A second call with the same id is a no-op, so an expert that registers itself
/// and an app that registers it again do not add it twice.
void MMRegisterExpert(id<MMExpert> expert) {
    if (!expert.expertID.length) return;
    @synchronized (Registered()) {
        for (id<MMExpert> e in Registered()) if ([e.expertID isEqualToString:expert.expertID]) return;
        [Registered() addObject:expert];
    }
    Class graph = NSClassFromString(@"MMGraph");
    if (graph) [(MMGraph *)[graph shared] addExpert:expert];
    Class broker = NSClassFromString(@"MMReviewBroker");
    if (broker) {
        MMReviewBroker *b = [broker shared];
        [b registerRules:[expert rules] ?: @[] expert:expert.expertID];
        __weak id<MMExpert> weak = expert;
        [b setRequestMaker:^MMReviewRequest *(NSString *trigger, MMSnapshot *s) { return [weak reviewRequest:trigger snapshot:s]; }
                    expert:expert.expertID];
    }
}

NSArray<id<MMExpert>> *MMExperts(void) {
    @synchronized (Registered()) { return [Registered() copy]; }
}

id<MMExpert> MMExpertNamed(NSString *expertID) {
    for (id<MMExpert> e in MMExperts()) if ([e.expertID isEqualToString:expertID]) return e;
    return nil;
}
