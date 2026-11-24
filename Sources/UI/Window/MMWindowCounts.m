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

NSString *MMWindowFixCountTitle(NSString *kind, NSInteger n) {
    if ([kind isEqualToString:@"stop"]) return [@"Stop " stringByAppendingString:MMWindowCount(n, @"idle server", @"idle servers")];
    if ([kind isEqualToString:@"quit"]) return [@"Quit " stringByAppendingString:MMWindowCount(n, @"app", @"apps")];
    if ([kind isEqualToString:@"remove"]) return [@"Remove " stringByAppendingString:MMWindowCount(n, @"merged worktree", @"merged worktrees")];
    // Everything MinMacs removes keeps a way back, Core/Act/MMRemoval.h, so a leftover goes to the Trash.
    if ([kind isEqualToString:@"trash"]) return [NSString stringWithFormat:@"Move %@ to the Trash", MMWindowCount(n, @"leftover", @"leftovers")];
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

NSString *MMWindowProjectMoreLine(NSInteger hidden, NSString *project) {
    return project.length ? [NSString stringWithFormat:@"%ld more in %@", (long)hidden, project] : [NSString stringWithFormat:@"%ld more", (long)hidden];
}

NSString *MMWindowProjectsMoreLine(NSInteger hidden, NSInteger projects) {
    return [NSString stringWithFormat:@"%ld more in %@", (long)hidden, MMWindowCount(projects, @"project", @"projects")];
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

NSString *MMWindowSumText(NSString *size, NSInteger count, NSInteger unmeasured) {
    if (unmeasured <= 0) return size;
    return unmeasured >= count ? MMWindowMeasuring : [size stringByAppendingString:@" so far"];
}

NSString *MMWindowBackText(NSString *size, BOOL nothing, BOOL partial) {
    if (!partial) return size;
    return nothing ? @"not measured yet" : [size stringByAppendingString:@" or more"];
}

NSString *MMWindowPlaceLine(NSInteger place, NSInteger count, NSInteger unmeasured, BOOL rowMeasured, NSString *title) {
    NSInteger known = count - unmeasured;
    if (!rowMeasured) return [NSString stringWithFormat:@"%ld %@", (long)count, title];
    if (known == 1 && unmeasured > 0) return [NSString stringWithFormat:@"The only one measured so far of %ld %@", (long)count, title];
    NSString *rank;
    if (place <= 1) rank = @"The biggest";
    else if (place == known) rank = @"The smallest";
    else {
        NSString *end = place % 100 >= 11 && place % 100 <= 13 ? @"th" : place % 10 == 1 ? @"st" : place % 10 == 2 ? @"nd" : place % 10 == 3 ? @"rd" : @"th";
        rank = [NSString stringWithFormat:@"%ld%@ biggest", (long)place, end];
    }
    return [NSString stringWithFormat:@"%@ of %ld %@%@", rank, (long)known, title, unmeasured > 0 ? @" measured so far" : @""];
}

NSString *MMWindowCollapsedSplit(NSInteger go, NSInteger inUse, NSInteger kept, NSInteger other, NSString *one, NSString *many) {
    // The unit stands once, at the first count, as a person says it: "168 groups can go, 1 in use".
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    __block BOOL unit = NO;
    NSString *(^count)(NSInteger, NSString *) = ^NSString *(NSInteger n, NSString *what) {
        NSString *c = unit ? [NSString stringWithFormat:@"%ld", (long)n] : MMWindowCount(n, one, many);
        // The verb takes its number from the count: "1 group stays", "2 groups stay".
        if ([what isEqualToString:@"stay"] && n == 1) what = @"stays";
        unit = YES;
        return [NSString stringWithFormat:@"%@ %@", c, what];
    };
    if (go > 0) [parts addObject:count(go, @"can go")];
    if (inUse > 0) [parts addObject:count(inUse, @"in use")];
    if (kept > 0) [parts addObject:count(kept, @"kept")];
    if (other > 0) [parts addObject:count(other, @"stay")];
    return [parts componentsJoinedByString:@", "];
}

NSString *MMWindowMembersLine(NSInteger shown, NSInteger count, NSString *one, NSString *many) {
    if (shown >= count) return [@"Its " stringByAppendingString:MMWindowCount(count, one, many)];
    return [NSString stringWithFormat:@"The %ld biggest of its %@", (long)shown, MMWindowCount(count, one, many)];
}
