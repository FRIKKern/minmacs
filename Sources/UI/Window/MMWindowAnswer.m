// Ask MinMacs as the window shows it, MMWindowModel.h: plain values, no AppKit. Shell/MMAsk.m makes them.
#import "UI/Window/MMWindowModel.h"

NSString *const MMWindowAskTitle = @"Ask MinMacs";
NSString *const MMWindowAskBack = @"Back to the log";
NSString *const MMWindowAskCannot = @"I can't answer that without the model yet.";
NSString *const MMWindowAskAsking = @"Asking Claude";

@implementation MMWindowAnswerEntry
@end

@implementation MMWindowSuggest
@end

@implementation MMWindowAnswer

- (instancetype)init {
    if ((self = [super init])) { _question = @""; _kind = @"unknown"; _answer = @""; _entries = @[]; _examples = @[]; _answeredBy = @"rules"; }
    return self;
}

- (MMWindowAnswer *)withNote:(NSString *)note {
    MMWindowAnswer *a = [MMWindowAnswer new];
    a.serial = self.serial; a.question = self.question; a.kind = self.kind; a.answer = self.answer;
    a.entries = self.entries; a.examples = self.examples; a.row = self.row; a.answeredBy = self.answeredBy;
    a.byline = self.byline; a.tokens = self.tokens; a.model = self.model; a.asking = self.asking;
    if (self.suggest) {
        MMWindowSuggest *s = [MMWindowSuggest new];
        s.action = self.suggest.action; s.title = self.suggest.title; s.target = self.suggest.target;
        s.command = self.suggest.command; s.help = self.suggest.help; s.note = note;
        a.suggest = s;
    }
    return a;
}

@end
