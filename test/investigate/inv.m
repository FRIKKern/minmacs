// The Investigate tool for test/investigate.sh, issue #35. It links every .m under Sources but main.m.
// It registers one fixture expert whose only finding is a server in $INV_APP, sets fixture facts with no sample,
// so nothing on the Mac is read, and runs a verb the way the app or the cold CLI does.
//   inv unit <fixture folder>     the scope checks, one line each: name, want, got
//   inv card                      the card note and action of LocoHost and WorkForest from a run in memory
//   inv start <subject>           the app's path: a run on its own queue, then the card's state, as checks
//   inv app <verb> [args]         a verb as the app runs it, handed over core.sock
//   inv <verb> [args]             a verb as the cold CLI runs it, _investigate-tools included
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "UI/MMInvestigateUI.h"
#import "Experts/LocoHost/MMLHHost.h"
#import "Experts/WorkForest/MMWFTree.h"

static void Out(NSString *name, NSString *want, NSString *got) {
    printf("%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"(nil)").UTF8String);
}
static NSString *B(BOOL b) { return b ? @"yes" : @"no"; }

static NSString *AppFolder(void) { return NSProcessInfo.processInfo.environment[@"INV_APP"] ?: @"/nonexistent"; }

@interface INVExpert : NSObject <MMExpert>
@end
@implementation INVExpert
- (NSString *)expertID { return @"invtest"; }
- (NSString *)name { return @"InvTest"; }
- (NSString *)symbol { return @"magnifyingglass"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    return @[[MMFinding expert:@"invtest" kind:@"server" stableKey:@"fixture-app#dev" build:^(MMFindingBuilder *b) {
        b.title = @"Fixture server for the fixture app";
        b.path = [AppFolder() stringByAppendingPathComponent:@"src/server.js"];   // a file: its folder is used
        b.ownerPath = AppFolder();
    }]];
}
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return [MMMenuSpec new]; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return @"one fixture"; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return NO; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
@end

@interface INVSource : NSObject <MMFactSource>
@end
@implementation INVSource
- (MMFacts *)factsFor:(uint64_t)generation {
    return [MMFacts generation:generation sample:nil power:nil agents:@[] sessions:@[] worktrees:@[] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:1]; }
@end

static MMSnapshot *Snapshot(void) {
    return [MMSnapshot snapshotFrom:[[INVSource new] factsFor:1] experts:MMExperts() reviews:nil holds:nil];
}

static int Unit(NSString *fx) {
    NSString *in = [fx stringByAppendingPathComponent:@"in"], *outside = [fx stringByAppendingPathComponent:@"outside"];
    NSArray *folders = MMInvestigateFolders(@[in]);
    NSString *why = nil;
    Out(@"scope: the folder is resolved to its real path", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)folders.count]);
    Out(@"scope: a file inside is allowed", @"yes", B(MMInvestigateScoped(folders, [in stringByAppendingPathComponent:@"README.md"], nil) != nil));
    Out(@"scope: a relative path starts at the folder", @"yes", B(MMInvestigateScoped(folders, @"src/server.js", nil) != nil));
    Out(@"scope: the folder itself is allowed", @"yes", B(MMInvestigateScoped(folders, nil, nil) != nil));
    Out(@"scope: a file outside is refused", @"no", B(MMInvestigateScoped(folders, [outside stringByAppendingPathComponent:@"secret.txt"], &why) != nil));
    Out(@"scope: and says why", @"yes", B([why containsString:@"outside the folders"]));
    Out(@"scope: .. out of the folder is refused", @"no", B(MMInvestigateScoped(folders, @"src/../../outside/secret.txt", nil) != nil));
    Out(@"scope: .. that stays inside is allowed", @"yes", B(MMInvestigateScoped(folders, @"src/../README.md", nil) != nil));
    Out(@"scope: a symlink inside that points out is refused", @"no", B(MMInvestigateScoped(folders, @"link-out.txt", nil) != nil));
    Out(@"scope: a symlinked folder that points out is refused", @"no", B(MMInvestigateScoped(folders, @"dir-out/secret.txt", nil) != nil));
    Out(@"scope: a symlink inside that points inside is allowed", @"yes", B(MMInvestigateScoped(folders, @"link-in.md", nil) != nil));
    Out(@"scope: a sibling folder with the same prefix is refused", @"no", B(MMInvestigateScoped(folders, [fx stringByAppendingPathComponent:@"in-other/x.txt"], nil) != nil));
    Out(@"scope: a path that does not exist is refused", @"no", B(MMInvestigateScoped(folders, @"nope.txt", nil) != nil));
    Out(@"scope: with no folder nothing is allowed", @"no", B(MMInvestigateScoped(@[], [in stringByAppendingPathComponent:@"README.md"], nil) != nil));
    // A link to the folder resolves to the same real folder, so the check holds either way.
    NSArray *viaLink = MMInvestigateFolders(@[[fx stringByAppendingPathComponent:@"in-link"]]);
    Out(@"folders: a link to the folder resolves to it", @"yes", B([viaLink.firstObject isEqualToString:folders.firstObject]));
    Out(@"folders: the root is never a folder", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)MMInvestigateFolders(@[@"/"]).count]);
    Out(@"folders: the home folder is never a folder", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)MMInvestigateFolders(@[NSHomeDirectory()]).count]);
    Out(@"folders: a folder above home is never a folder", @"0",
        [NSString stringWithFormat:@"%lu", (unsigned long)MMInvestigateFolders(@[NSHomeDirectory().stringByDeletingLastPathComponent]).count]);
    NSArray *nested = MMInvestigateFolders(@[[in stringByAppendingPathComponent:@"src"], in, [in stringByAppendingPathComponent:@"README.md"]]);
    Out(@"folders: a folder inside another and a file count once", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)nested.count]);

    MMSnapshot *s = Snapshot();
    MMFinding *f = [s findingsFor:@"invtest"].firstObject;
    MMInvestigateSubject *x = [MMInvestigateSubject finding:f snapshot:s];
    Out(@"subject: a finding gives its folder and its owner's", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)x.folders.count]);
    Out(@"subject: the folder is the app, not its src folder", AppFolder().lastPathComponent, [x.folders.firstObject lastPathComponent]);
    Out(@"subject: by its id", @"invtest:server:fixture-app#dev", [MMInvestigateSubject named:f.findingID snapshot:s cwd:nil].subjectID);
    MMInvestigateSubject *byPath = [MMInvestigateSubject named:[AppFolder() stringByAppendingPathComponent:@"src/server.js"] snapshot:s cwd:nil];
    Out(@"subject: a path names the finding at it", @"invtest:server:fixture-app#dev", byPath.subjectID);
    Out(@"subject: a bare folder is a folder subject", @"yes", B([[MMInvestigateSubject named:in snapshot:s cwd:nil].subjectID hasPrefix:@"folder:"]));
    Out(@"subject: nothing at a missing path", @"nil", [MMInvestigateSubject named:@"/nonexistent/x" snapshot:s cwd:nil] ? @"subject" : @"nil");

    MMInvestigateEstimate *e = [MMInvestigateEstimate new];
    e.model = @"haiku"; e.tokens = 35000;
    Out(@"estimate: the sentence before the first run", @"About 35,000 tokens on Haiku, an estimate before the first run.", e.sentence);
    e.tokens = 360; e.basedOn = 3;
    Out(@"estimate: the sentence after three runs", @"About 360 tokens on Haiku, the median of the last 3 runs.", e.sentence);
    return 0;
}

static NSArray *Titles(MMCardSpec *c) { return [c.actions valueForKey:@"title"]; }

static int Card(void) {
    NSDictionary *done = @{@"subject": @"x", @"model": @"haiku", @"answer": @"It serves the fixture app from src/server.js.",
                           @"at": @(NSDate.date.timeIntervalSince1970 - 2 * 3600)};
    NSDictionary *running = @{@"subject": @"x", @"model": @"haiku", @"running": @YES, @"at": @(NSDate.date.timeIntervalSince1970)};

    MMWFTree *t = [MMWFTree new];
    t.repo = @"/Users/dev/code/app"; t.path = @"/Users/dev/code/app.worktrees/feature"; t.findingID = @"workforest:worktree:feature";
    t.branch = @"feat/x";
    MMWFView *wv = [MMWFView new]; wv.trees = @[t]; wv.mode = @"proactive";
    MMCardSpec *wc = MMWFCard(t, wv);
    Out(@"workforest: the card offers Investigate", @"yes", B([Titles(wc) containsObject:@"Investigate…"]));
    Out(@"workforest: with no run the card has no note", @"nil", wc.note ?: @"nil");
    wv.investigations = @{t.findingID: done};
    wc = MMWFCard(t, wv);
    Out(@"workforest: the answer is the card's note", @"Haiku investigated: It serves the fixture app from src/server.js.",
        [NSString stringWithFormat:@"%@: %@", wc.noteBy, wc.note]);
    MMActionSpec *ia = nil;
    for (MMActionSpec *a in wc.actions) if ([a.title isEqualToString:@"Investigate…"]) ia = a;
    Out(@"workforest: the action's tail is the answer's age", @"2h ago", ia.tail);
    wv.investigations = @{t.findingID: running};
    wc = MMWFCard(t, wv);
    for (MMActionSpec *a in wc.actions) if ([a.title isEqualToString:@"Investigate…"]) ia = a;
    Out(@"workforest: while it runs the action is dimmed", @"running now", ia.disabledReason);
    Out(@"workforest: and the note says so", @"Haiku is investigating", wc.noteBy);
    __block NSString *acted = nil;
    wv.act = ^(NSString *what, NSString *key, BOOL option) { acted = [NSString stringWithFormat:@"%@ %@", what, key]; };
    wv.investigations = nil;
    wc = MMWFCard(t, wv);
    for (MMActionSpec *a in wc.actions) if ([a.title isEqualToString:@"Investigate…"]) a.run(NO);
    Out(@"workforest: the action goes to the expert's investigate", @"investigate workforest:worktree:feature", acted);

    MMLHHost *h = [MMLHHost new];
    h.findingID = @"locohost:server:~/code/app#dev"; h.ports = @[@3000]; h.cwd = @"/Users/dev/code/app"; h.kind = @"dev";
    h.launcher = @"pnpm dev"; h.started = [NSDate dateWithTimeIntervalSinceNow:-3600];
    MMLHView *lv = [MMLHView new]; lv.hosts = @[h]; lv.mode = @"proactive";
    lv.investigations = @{h.findingID: @{@"subject": @"x", @"error": @"claude CLI not found"}};
    MMCardSpec *lc = MMLHCard(h, lv);
    Out(@"locohost: the card offers Investigate", @"yes", B([Titles(lc) containsObject:@"Investigate…"]));
    Out(@"locohost: a failed run says so on the card", @"Investigate failed: Claude CLI not found.", [NSString stringWithFormat:@"%@: %@", lc.noteBy, lc.note]);
    MMLHHost *svc = [MMLHHost new];
    svc.findingID = @"locohost:service:pg"; svc.ports = @[@5432]; svc.kind = @"service"; svc.cwd = @"/"; svc.launcher = @"Homebrew";
    Out(@"locohost: a listener with no folder has no Investigate", @"no", B([Titles(MMLHCard(svc, lv)) containsObject:@"Investigate…"]));
    return 0;
}

/// The app's path: start on the investigate queue, the card's state while it runs, and the saved run after.
static int Start(NSString *name) {
    MMSnapshot *s = Snapshot();
    MMInvestigateSubject *x = [MMInvestigateSubject named:name snapshot:s cwd:nil];
    if (!x) { Out(@"start: the subject resolves", @"yes", @"no"); return 1; }
    __block BOOL finished = NO;
    __block MMInvestigation *got = nil;
    [MMInvestigations.shared start:x question:@"What does it serve?" done:^(MMInvestigation *run, NSString *error) { got = run; finished = YES; }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while (!finished && [until timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    NSUInteger before = MMLogMainThreadQueries();
    MMInvestigation *now = [MMInvestigations.shared latestFor:x.subjectID];
    Out(@"start: while it runs, memory says it runs", @"yes", B(now.running));
    MMInvestigation *again = [MMInvestigations.shared run:x question:nil error:nil];
    Out(@"start: a second run of the same subject is refused", @"nil", again ? @"run" : @"nil");
    // A second start while one runs is refused at once, so a second click never queues a paid run behind the first.
    __block BOOL secondDone = NO; __block NSString *secondError = nil; __block MMInvestigation *secondRun = nil;
    [MMInvestigations.shared start:x question:nil done:^(MMInvestigation *run, NSString *error) { secondRun = run; secondError = error; secondDone = YES; }];
    until = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while (!secondDone && [until timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    Out(@"start: a second start of the same subject is refused at once", @"an investigation of this already runs",
        secondDone && !secondRun ? secondError : @"(it queued)");
    // The card's alert resolves its subject and estimate while another run goes, without waiting for it.
    __block BOOL prepared = NO; __block MMInvestigateSubject *other = nil;
    [MMInvestigations.shared prepare:[AppFolder() stringByAppendingPathComponent:@"src"] snapshot:s
                                done:^(MMInvestigateSubject *subject, MMInvestigateEstimate *estimate) { other = subject; prepared = YES; }];
    until = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while (!prepared && [until timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    Out(@"start: another card's alert does not wait for the run", @"yes", B(prepared && !finished && other.folders.count == 1));
    until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!finished && [until timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Out(@"start: done runs on main with the answer", @"yes", B(finished && got.answer.length > 0));
    MMInvestigation *after = [MMInvestigations.shared latestFor:x.subjectID];
    Out(@"start: memory holds the answer after", @"yes", B(!after.running && after.answer.length > 0));
    Out(@"start: reading it on main ran no log query", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)(MMLogMainThreadQueries() - before)]);
    return 0;
}

static int Verb(NSArray<NSString *> *words, BOOL inApp) {
    if (!inApp) {
        // The cold CLI, on main, as minmacs runs a verb when no app answers.
        NSMutableArray *argv = [NSMutableArray arrayWithObject:@"minmacs"];
        [argv addObjectsFromArray:words];
        const char **c = calloc(argv.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < argv.count; i++) c[i] = [argv[i] UTF8String];
        setenv("MINMACS_COLD", "1", 1);
        int r = MMRunCLI((int)argv.count, c);
        free(c);
        fflush(stdout);
        return r;
    }
    NSDictionary *req = @{@"cli": words, @"program": @"minmacs", @"cwd": NSFileManager.defaultManager.currentDirectoryPath};
    __block NSDictionary *reply;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ reply = MMCLIReply(req); dispatch_semaphore_signal(done); });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW)) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    fputs([reply[@"out"] description].UTF8String ?: "", stdout);
    fputs([reply[@"err"] description].UTF8String ?: "", stderr);
    fflush(stdout);
    // An app run goes on its own queue. Wait for it, as the app would keep running.
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while ([until timeIntervalSinceNow] > 0) {
        BOOL busy = NO;
        MMInvestigateSubject *x = words.count > 1 ? [MMInvestigateSubject named:words[1] snapshot:Snapshot() cwd:nil] : nil;
        if (x) busy = [MMInvestigations.shared latestFor:x.subjectID].running;
        if (!busy) break;
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return [reply[@"status"] intValue];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MMRegisterExpert([INVExpert new]);
        INVSource *src = [INVSource new];
        MMSetCLIFactSource(src);
        if (argc < 2) { fprintf(stderr, "usage: inv unit | card | start | app <verb> | <verb>\n"); return 2; }
        NSString *cmd = @(argv[1]);
        if ([cmd isEqualToString:@"unit"] && argc > 2) return Unit(@(argv[2]));
        if ([cmd isEqualToString:@"card"]) return Card();
        if ([cmd isEqualToString:@"start"] && argc > 2) { MMGraph.shared.source = src; return Start(@(argv[2])); }
        NSMutableArray *words = [NSMutableArray new];
        BOOL inApp = [cmd isEqualToString:@"app"];
        for (int i = inApp ? 2 : 1; i < argc; i++) [words addObject:@(argv[i])];
        if (inApp) MMGraph.shared.source = src;
        return Verb(words, inApp);
    }
}
