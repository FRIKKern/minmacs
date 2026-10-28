// The Investigate card words and alerts, issue #35. MMInvestigateUI.h says what each does.
#import <Cocoa/Cocoa.h>
#import "UI/MMInvestigateUI.h"
#import "UI/MMFormat.h"
#import "UI/MMMenuKit.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

static NSDate *At(NSDictionary *run) {
    return [run[@"at"] isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[run[@"at"] doubleValue]] : nil;
}

NSString *MMInvestigateTail(NSDictionary *run) {
    return [run isKindOfClass:NSDictionary.class] && Str(run[@"answer"]).length && ![run[@"running"] boolValue] ? MMAgo(At(run)) : nil;
}

NSString *MMInvestigateDisabledReason(NSDictionary *run) {
    return [run isKindOfClass:NSDictionary.class] && [run[@"running"] boolValue] ? @"running now" : nil;
}

BOOL MMInvestigateNote(NSDictionary *run, NSString **noteBy, NSString **note) {
    if (![run isKindOfClass:NSDictionary.class]) return NO;
    NSString *model = MMCapitalized(Str(run[@"model"]).length ? run[@"model"] : @"haiku");
    if ([run[@"running"] boolValue]) { *noteBy = [model stringByAppendingString:@" is investigating"]; *note = @"The answer shows here."; return YES; }
    NSString *answer = Str(run[@"answer"]);
    if (!answer.length) { *noteBy = @"Investigate failed"; *note = MMSentence(Str(run[@"error"]) ?: @"the model did not answer"); return YES; }
    // The note holds two lines, so it keeps the whole sentences that fit, as MMCard draws it. The full answer
    // is in the Investigate alert and in `minmacs investigate`. The width and size are MMCard's card text.
    *noteBy = [model stringByAppendingString:@" investigated"];
    NSString *by = [*noteBy stringByAppendingString:@": "];
    NSString *fit = MMFitSentences([by stringByAppendingString:MMSentence(answer)], [NSFont systemFontOfSize:11.5], MMMenuWidth - 32, MMMaxCardNoteLines);
    *note = [fit hasPrefix:by] ? [fit substringFromIndex:by.length] : MMSentence(answer);
    return YES;
}

NSString *MMInvestigateConfirm(NSString *title, NSString *text, NSString *placeholder) {
    NSAlert *a = [NSAlert new];
    a.messageText = title ?: @"Investigate?";
    a.informativeText = text ?: @"";
    NSTextField *q = [NSTextField textFieldWithString:@""];
    q.placeholderString = placeholder;
    q.frame = NSMakeRect(0, 0, 340, 24);
    a.accessoryView = q;
    [a addButtonWithTitle:@"Investigate"]; [a addButtonWithTitle:@"Cancel"];
    a.window.initialFirstResponder = q;
    [NSApp activateIgnoringOtherApps:YES];
    if ([a runModal] != NSAlertFirstButtonReturn) return nil;
    return [q.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

void MMInvestigateFailed(NSString *error) {
    NSAlert *a = [NSAlert new];
    a.messageText = @"Investigate Failed";
    a.informativeText = MMSentence(error ?: @"the model did not answer");
    [NSApp activateIgnoringOtherApps:YES];
    [a runModal];
}
