// Every phrase the window shows with a count in it, worded here and nowhere else, so one of a thing reads "1 fix",
// "1 localhost tab", "1 agent asks you", and never "1 fixes". The feed, the runner and the views call these, and
// tools/render-window-words.m reads each at 0, 1 and 2. Each noun has its two forms written out: none is guessed.
#import "UI/Window/MMWindowModel.h"

NSString *MMWindowCount(NSInteger n, NSString *one, NSString *many) { return [NSString stringWithFormat:@"%ld %@", (long)n, n == 1 ? one : many]; }

NSString *MMWindowFixes(NSInteger n) { return MMWindowCount(n, @"fix", @"fixes"); }

NSString *MMWindowAsksLine(NSInteger agents) {
    if (agents <= 0) return nil;
    return agents == 1 ? @"1 agent asks you" : [NSString stringWithFormat:@"%ld agents ask you", (long)agents];
}

NSString *MMWindowEndTitle(NSInteger done, NSInteger total) {
    if (done == total) return [MMWindowFixes(done) stringByAppendingString:@" done"];
    return [NSString stringWithFormat:@"%ld of %@ done", (long)done, MMWindowFixes(total)];
}

NSString *MMWindowSkippedNote(NSInteger asks, NSInteger needYou, NSInteger kept, NSInteger blocked, NSInteger notReached, NSInteger notRun) {
    NSMutableArray<NSString *> *skipped = [NSMutableArray new];
    if (asks > 0) [skipped addObject:asks == 1 ? @"1 agent that asks you" : [NSString stringWithFormat:@"%ld agents that ask you", (long)asks]];
    if (needYou > 0) [skipped addObject:needYou == 1 ? @"1 fix that needs your own press" : [NSString stringWithFormat:@"%ld fixes that need your own press", (long)needYou]];
    if (kept > 0) [skipped addObject:[NSString stringWithFormat:@"%ld kept since %@ changed or %@ in use", (long)kept, kept == 1 ? @"it" : @"they", kept == 1 ? @"is" : @"are"]];
    if (blocked > 0) [skipped addObject:[NSString stringWithFormat:@"%ld blocked", (long)blocked]];
    if (notReached > 0) [skipped addObject:[MMWindowCount(notReached, @"thing", @"things") stringByAppendingString:@" in the fix you stopped partway"]];
    if (notRun > 0) [skipped addObject:[MMWindowFixes(notRun) stringByAppendingString:@" you stopped"]];
    if (!skipped.count) return nil;
    NSString *list = skipped.count == 1 ? skipped[0]
        : [NSString stringWithFormat:@"%@ and %@", [[skipped subarrayWithRange:NSMakeRange(0, skipped.count - 1)] componentsJoinedByString:@", "], skipped.lastObject];
    return [NSString stringWithFormat:@"Skipped %@.", list];
}

NSString *MMWindowFixCountTitle(NSString *kind, NSInteger n, NSInteger removal) {
    if ([kind isEqualToString:@"stop"]) return [@"Stop " stringByAppendingString:MMWindowCount(n, @"idle server", @"idle servers")];
    if ([kind isEqualToString:@"quit"]) return [@"Quit " stringByAppendingString:MMWindowCount(n, @"app", @"apps")];
    if ([kind isEqualToString:@"remove"]) return [@"Remove " stringByAppendingString:MMWindowCount(n, @"merged worktree", @"merged worktrees")];
    // What the press does follows the removal choice. Under Smart some are deleted and the rest go to the Trash.
    if ([kind isEqualToString:@"trash"]) {
        NSString *what = MMWindowCount(n, @"leftover", @"leftovers");
        return removal == 1 ? [NSString stringWithFormat:@"Move %@ to the Trash", what] : removal == 2 ? [@"Delete " stringByAppendingString:what] : [@"Clean up " stringByAppendingString:what];
    }
    if ([kind isEqualToString:@"clean"]) return [@"Run " stringByAppendingString:MMWindowCount(n, @"tool cleanup", @"tool cleanups")];
    return nil;
}

NSString *MMWindowAfterTitle(NSInteger fixes) {
    if (fixes <= 0) return nil;
    return fixes == 1 ? @"After the fix" : [NSString stringWithFormat:@"After all %@", MMWindowFixes(fixes)];
}

NSString *MMWindowMoreLine(NSInteger below, NSInteger above) {
    if (below > 0) return [NSString stringWithFormat:@"%ld more below", (long)below];
    return above > 0 ? [NSString stringWithFormat:@"%ld more above", (long)above] : nil;
}

NSString *MMWindowTabsName(NSInteger tabs, NSString *browser) {
    if (tabs <= 0) return browser ?: @"";
    NSString *count = MMWindowCount(tabs, @"localhost tab", @"localhost tabs");
    return browser.length ? [NSString stringWithFormat:@"%@ in %@", count, browser] : count;
}

NSString *MMWindowReadyNote(NSInteger ready) {
    if (ready <= 0) return nil;
    return [NSString stringWithFormat:@"%ld ready. %@ for your press.", (long)ready, ready == 1 ? @"It waits" : @"They wait"];
}
