// Identical failures fold into one entry of the log, MMWindowLogParts.h. A run whose every move to the Trash failed
// the same way once gave the window 169 entries, one per group, each with the same words why. Now it gives one, which
// counts them and names them in its more. Every word is in the window's words, DESIGN.md "Words".
#import "Shell/MMWindowLogParts.h"
#import "Core/MMCore.h"

@interface MMWindowLogFold : NSObject
@property (copy) NSString *key, *kind, *error;
@property MMWindowLogEntry *entry;
@property NSMutableArray<NSString *> *subjects;
@property NSDate *newest, *oldest;
@end
@implementation MMWindowLogFold
@end

static NSString *Clock(NSDate *d) {
    static NSDateFormatter *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat = @"HH:mm"; });
    @synchronized (f) { f.timeZone = NSTimeZone.localTimeZone; return [f stringFromDate:d]; }
}

/// A sentence from words that may end on a period of their own.
static NSString *Sentence(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length) s = [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]];
    return [s hasSuffix:@"."] ? s : [s stringByAppendingString:@"."];
}

/// What n failed records of one kind set out to do: "move 169 groups to the Trash". A family's subject has a * in
/// its name, "MMWorker-* folders", and is a group.
static NSString *FoldedTodo(NSString *kind, NSInteger n, BOOL groups) {
    NSString *k = kind ?: @"";
    if ([k isEqualToString:@"trash"]) return [NSString stringWithFormat:@"move %@ to the Trash", MMWindowCount(n, groups ? @"group" : @"item", groups ? @"groups" : @"items")];
    if ([k isEqualToString:@"stop"]) return [@"stop " stringByAppendingString:MMWindowCount(n, @"process", @"processes")];
    if ([k isEqualToString:@"quit"]) return [@"quit " stringByAppendingString:MMWindowCount(n, @"app", @"apps")];
    if ([k isEqualToString:@"remove"]) return [@"remove " stringByAppendingString:MMWindowCount(n, @"worktree", @"worktrees")];
    if ([k isEqualToString:@"clean"] || [k isEqualToString:@"tool"]) return [@"run " stringByAppendingString:MMWindowCount(n, @"cleanup", @"cleanups")];
    if ([k isEqualToString:@"wrapup"]) return [@"wrap up " stringByAppendingString:MMWindowCount(n, @"workstream", @"workstreams")];
    return [@"act on " stringByAppendingString:MMWindowCount(n, @"thing", @"things")];
}

/// Words why one thing failed, said of several: "so the item stays where it is" becomes "so they stay where they are".
static NSString *PluralWhy(NSString *why) {
    for (NSString *one in @[@"the item stays where it is", @"it stays where it is"])
        why = [why stringByReplacingOccurrencesOfString:one withString:@"they stay where they are"];
    return why;
}

/// The fold's entry once a record more is in it: one sentence for all, the times from the oldest to the newest, and
/// in more the things it names. The key is the oldest row's, which stays while newer failures join.
static void Refold(MMWindowLogFold *f, MMLogEntry *row) {
    NSInteger n = (NSInteger)f.subjects.count;
    BOOL groups = YES;
    for (NSString *s in f.subjects) if ([s rangeOfString:@"*"].location == NSNotFound) { groups = NO; break; }
    NSString *err = f.error.length ? [@" " stringByAppendingString:Sentence(PluralWhy(f.error))] : @"";
    MMWindowLogEntry *e = f.entry;
    e.sentence = [NSString stringWithFormat:@"Could not %@.%@", FoldedTodo(f.kind, n, groups), err];
    e.key = [NSString stringWithFormat:@"failed:%lld", row.row];
    NSString *from = Clock(f.oldest), *to = Clock(f.newest);
    e.time = [from isEqualToString:to] ? to : [NSString stringWithFormat:@"%@ to %@", from, to];
    NSArray<NSString *> *named = [f.subjects subarrayWithRange:NSMakeRange(0, MIN(f.subjects.count, (NSUInteger)12))];
    NSString *list = n > 12 ? [NSString stringWithFormat:@"%@ and %ld more", [named componentsJoinedByString:@", "], (long)(n - 12)]
                            : [[[named subarrayWithRange:NSMakeRange(0, named.count - 1)] componentsJoinedByString:@", "] stringByAppendingFormat:@" and %@", named.lastObject];
    e.more = [list stringByAppendingString:@"."];
}

BOOL MMWindowLogFoldFailed(MMWindowLogFold **fold, MMWindowLogEntry *e, MMLogEntry *row, NSString *day, MMWindowLogEntry *last) {
    MMUndoRecord *r = [MMUndoRecord fromBody:row.body hasParts:NO];
    NSString *key = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", r.kind ?: @"", r.error ?: @"", e.who ?: @"", day ?: @""];
    NSString *subject = r.subject.length ? r.subject : @"something";
    MMWindowLogFold *f = *fold;
    if (f && last && f.entry == last && [f.key isEqualToString:key]) {
        [f.subjects addObject:subject];
        f.oldest = row.at;
        Refold(f, row);
        return YES;
    }
    f = [MMWindowLogFold new];
    f.key = key; f.kind = r.kind; f.error = r.error; f.entry = e;
    f.subjects = [NSMutableArray arrayWithObject:subject];
    f.newest = f.oldest = row.at;
    *fold = f;
    return NO;
}
