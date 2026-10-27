// The one list of experts, in menu bar order. The app registers each expert once at launch, before MMCoreStart.
// The graph asks each for findings and the broker holds its rules. The CLI and the status items read this list.
#import "Core/MMExpert.h"

static NSMutableArray<id<MMExpert>> *Experts(void) {
    static NSMutableArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ list = [NSMutableArray new]; });
    return list;
}

void MMRegisterExpert(id<MMExpert> expert) {
    if (!expert.expertID.length) return;
    NSMutableArray *list = Experts();
    @synchronized (list) {
        for (id<MMExpert> e in list) if ([e.expertID isEqualToString:expert.expertID]) return;   // once per expert
        [list addObject:expert];
    }
    [MMGraph.shared addExpert:expert];
    NSArray *rules = [expert rules];
    if (rules.count) [MMReviewBroker.shared registerRules:rules expert:expert.expertID];
}

NSArray<id<MMExpert>> *MMExperts(void) {
    NSMutableArray *list = Experts();
    @synchronized (list) { return [list copy]; }
}

id<MMExpert> MMExpertNamed(NSString *expertID) {
    for (id<MMExpert> e in MMExperts()) if ([e.expertID isEqualToString:expertID]) return e;
    return nil;
}
