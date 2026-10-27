// The menu, card and verb specs of MMExpert.h. Plain data, so the menu kit, the render tool and the CLI share them.
// Patterns P57, P58 and P61. Nothing here imports AppKit.
#import "Core/MMExpert.h"

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
