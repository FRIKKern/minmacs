// The investigate verb and the hidden tool server it starts through claude, issue #35.
// `minmacs investigate <finding|workstream|path> [question]` shows what a run will cost and asks for --yes.
// `minmacs _investigate-tools --folder <path>...` is the MCP server of Review/MMInvestigate.h. claude starts it.
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#include <stdio.h>
#include <stdlib.h>

static NSString *Tilde(NSString *s) {
    NSString *home = NSHomeDirectory();
    return home.length > 1 && [s hasPrefix:[home stringByAppendingString:@"/"]] ? [@"~" stringByAppendingString:[s substringFromIndex:home.length]] : s;
}

static NSArray *TildeAll(NSArray<NSString *> *paths) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in paths) [out addObject:Tilde(p)];
    return out;
}

static NSString *Ago(NSDate *d) {
    if (!d) return @"";
    NSTimeInterval s = MAX(0, -d.timeIntervalSinceNow);
    if (s < 90) return @"just now";
    if (s < 5400) return [NSString stringWithFormat:@"%.0f minutes ago", s / 60];
    if (s < 129600) return [NSString stringWithFormat:@"%.0f hours ago", s / 3600];
    return [NSString stringWithFormat:@"%.0f days ago", s / 86400];
}

static NSDictionary *RunJSON(MMInvestigation *r) {
    if (!r) return nil;
    NSMutableDictionary *j = [r.json mutableCopy];
    j[@"folders"] = TildeAll(r.folders);
    return j;
}

static void PrintRun(MMArgs *a, MMInvestigation *r, BOOL last) {
    if (r.running) { [a print:@"An investigation started %@ still runs.", Ago(r.at)]; return; }
    if (r.answer) [a print:@"%@%@", last ? [NSString stringWithFormat:@"Last answer, %@:\n", Ago(r.at)] : @"", r.answer];
    else [a print:@"%@ %@", last ? [NSString stringWithFormat:@"The last run, %@, failed:", Ago(r.at)] : @"It failed:", r.error ?: @"no answer"];
    if (!last && r.usage)
        [a print:@"Used %ld uncached tokens on %@, with %ld tool calls, %ld refused.", (long)r.usage.uncached, r.model ?: MMInvestigateModel,
                 (long)r.toolCalls, (long)r.refused];
}

int MMInvestigateVerb(MMArgs *a) {
    NSString *name = [a word:0];
    if (!name.length) return [a usageError];
    NSArray *rest = a.words.count > 1 ? [a.words subarrayWithRange:NSMakeRange(1, a.words.count - 1)] : @[];
    NSString *question = rest.count ? [rest componentsJoinedByString:@" "] : nil;
    MMInvestigateSubject *subject = [MMInvestigateSubject named:name snapshot:a.snapshot cwd:a.cwd];
    if (!subject) { [a error:@"nothing named %@ has a folder to look in", name]; return MMExitFailed; }
    MMInvestigations *store = MMInvestigations.shared;
    [store load];
    MMInvestigateEstimate *estimate = store.estimate;
    MMInvestigation *last = [store latestFor:subject.subjectID];
    NSString *q = question ?: subject.question;
    BOOL go = [a has:@"--yes"] && !a.dryRun;
    if (!go) {
        if (a.json) {
            [a printJSON:@{@"subject": subject.subjectID, @"title": subject.title ?: @"", @"folders": TildeAll(subject.folders),
                           @"question": q, @"estimate": estimate.json, @"last": RunJSON(last) ?: NSNull.null, @"ran": @NO}];
            return 0;
        }
        [a print:@"Investigate %@", subject.title ?: subject.subjectID];
        [a print:@"  Folders   %@", [TildeAll(subject.folders) componentsJoinedByString:@", "]];
        [a print:@"  Question  %@", q];
        [a print:@"  Cost      %@", estimate.sentence];
        if (last) PrintRun(a, last, YES);
        [a print:@"Run it with --yes to confirm the cost."];
        return 0;
    }
    if (last.running) { [a error:@"an investigation of this already runs"]; return MMExitFailed; }
    if (a.inApp) {
        // The socket answers one verb at a time, so a run in the app goes on its own queue and the card shows it.
        [store start:subject question:question done:nil];
        if (a.json) { [a printJSON:@{@"subject": subject.subjectID, @"started": @YES, @"estimate": estimate.json}]; return 0; }
        [a print:@"Started. The answer shows on its card, and here with %@ investigate %@.", a.program ?: @"minmacs", name];
        return 0;
    }
    // Cold, the CLI waits for the run, but the run itself stays off main, as MMInvestigations asks.
    __block NSString *e = nil;
    __block MMInvestigation *r = nil;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *why = nil;
        r = [store run:subject question:question error:&why];
        e = why;
        dispatch_semaphore_signal(finished);
    });
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    if (a.json) { [a printJSON:RunJSON(r) ?: @{@"error": e ?: @"it did not run"}]; return r.answer ? 0 : MMExitFailed; }
    if (!r) { [a error:@"%@", e ?: @"it did not run"]; return MMExitFailed; }
    PrintRun(a, r, NO);
    return r.answer ? 0 : MMExitFailed;
}

int MMInvestigateToolsVerb(MMArgs *a) {
    NSMutableArray *candidates = [NSMutableArray new];
    NSString *audit = nil;
    NSArray *all = a.all;
    for (NSUInteger i = 0; i + 1 < all.count; i++) {
        if ([all[i] isEqualToString:@"--folder"]) [candidates addObject:all[++i]];
        else if ([all[i] isEqualToString:@"--audit"]) audit = all[++i];
    }
    NSArray *folders = MMInvestigateFolders(candidates);
    if (!folders.count) { [a error:@"no folder to serve"]; return MMExitUsage; }
    __block char *buf = NULL; __block size_t cap = 0;
    int status = MMInvestigateServeTools(folders, audit, ^NSString *{
        ssize_t n = getline(&buf, &cap, stdin);
        if (n < 0) return nil;
        return [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] ?: @"";
    }, ^(NSString *line) {
        [a print:@"%@", line];
        fflush(stdout);
    });
    free(buf);
    return status;
}
