// More checks for test/window/window.m, which includes this file: a worktree's pull request through gh, MMPulls.
// gh here is always test/window/gh, a fake copied into this run's fixture folder and put on the PATH. It answers from
// files beside it and writes one line a call, so nothing reaches the real gh or the network. MMPulls itself only takes
// a gh inside the test home while MINMACS_HOME is set.
#import "Core/Know/MMPulls.h"

static NSString *gGh;                                   // the fake's folder

static void GhFile(NSString *name, NSString *text) {
    NSString *p = [gGh stringByAppendingPathComponent:name];
    if (text) [text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else [NSFileManager.defaultManager removeItemAtPath:p error:nil];
}

static NSArray<NSString *> *GhCalls(void) {
    NSString *s = [NSString stringWithContentsOfFile:[gGh stringByAppendingPathComponent:@"calls"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    return [[s componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}

/// The fake on the PATH, or not, and logged in, or not. MMPulls looks for gh again after forget.
static void GhWorld(BOOL onPath, BOOL loggedIn) {
    [MMPulls.shared forget];
    setenv("PATH", (onPath ? [gGh stringByAppendingString:@":/usr/bin:/bin"] : @"/usr/bin:/bin").UTF8String, 1);
    NSString *config = [gGh stringByAppendingPathComponent:@"config"];
    [NSFileManager.defaultManager createDirectoryAtPath:config withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *hosts = [config stringByAppendingPathComponent:@"hosts.yml"];
    if (loggedIn) [@"github.com:\n    user: sam\n" writeToFile:hosts atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else [NSFileManager.defaultManager removeItemAtPath:hosts error:nil];
    setenv("GH_CONFIG_DIR", config.UTF8String, 1);
    unsetenv("GH_TOKEN"); unsetenv("GITHUB_TOKEN"); unsetenv("GH_ENTERPRISE_TOKEN"); unsetenv("GITHUB_ENTERPRISE_TOKEN");
    GhFile(@"mode", @"answer");
}

/// want: runs off main, as the controller's queue calls it.
static BOOL Want(NSString *folder, NSString *repo, NSString *branch, NSString *head) {
    // dispatch_sync would run the block on main, the caller's thread, which want: refuses.
    __block BOOL look = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"windowtest", @"pulls", QOS_CLASS_USER_INITIATED), ^{ look = [MMPulls.shared want:folder repo:repo branch:branch head:head]; dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return look;
}

/// Waits until gh's run for the newest ask is over: the prs queue is serial.
static void PullsSettle(void) { dispatch_sync(MMQueue(@"workforest", @"prs", QOS_CLASS_UTILITY), ^{}); }

static NSString *Line(NSString *json) {
    MMWindowPull *p = MMWindowPullFrom(MMPullParse([json dataUsingEncoding:NSUTF8StringEncoding]));
    return p ? p.line : @"nothing";
}

static NSString *ISO(NSTimeInterval ago) {
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    return [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-ago]];
}

static NSString *const kOpen = @"[{\"number\":142,\"title\":\"Tune the ranking\",\"state\":\"OPEN\",\"isDraft\":false,"
    @"\"url\":\"https://github.com/acme/atlas/pull/142\",\"reviewDecision\":\"REVIEW_REQUIRED\","
    @"\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"},"
    @"{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\"},{\"__typename\":\"StatusContext\",\"state\":\"SUCCESS\"}],"
    @"\"mergedAt\":\"0001-01-01T00:00:00Z\",\"updatedAt\":\"2026-11-20T10:00:00Z\"}]";

/// gh's answers, each state as the story says it.
static void PullsParse(void) {
    MMPullAnswer *a = MMPullParse([kOpen dataUsingEncoding:NSUTF8StringEncoding]);
    T(@"pulls: an open pull request with passing checks, as gh gives it", @"found 142 open no 3 0 0 review requested https://github.com/acme/atlas/pull/142 no",
      [NSString stringWithFormat:@"%@ %ld %@ %@ %ld %ld %ld %@ %@ %@", a.known == MMPullFound ? @"found" : @"other", (long)a.pull.number, a.pull.stateWord, YN(a.pull.draft),
       (long)a.pull.checksPassing, (long)a.pull.checksFailing, (long)a.pull.checksPending, a.pull.review, a.pull.url, YN(a.pull.mergedAt != nil)]);
    T(@"pulls: its line", @"PR #142 · open · checks passing · review requested", Line(kOpen));
    T(@"pulls: two checks failing, one passing", @"PR #7 · open · 2 checks failing",
      Line(@"[{\"number\":7,\"title\":\"x\",\"state\":\"OPEN\",\"url\":\"https://github.com/a/b/pull/7\",\"statusCheckRollup\":["
           @"{\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"},{\"__typename\":\"StatusContext\",\"state\":\"ERROR\"},{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}]"));
    T(@"pulls: one check failing", @"PR #7 · open · 1 check failing · changes requested",
      Line(@"[{\"number\":7,\"state\":\"OPEN\",\"reviewDecision\":\"CHANGES_REQUESTED\",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"TIMED_OUT\"}]}]"));
    T(@"pulls: checks still running, with none failing", @"PR #8 · open · checks running",
      Line(@"[{\"number\":8,\"state\":\"OPEN\",\"statusCheckRollup\":[{\"status\":\"IN_PROGRESS\",\"conclusion\":\"\"},{\"__typename\":\"StatusContext\",\"state\":\"PENDING\"},"
           @"{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}]"));
    T(@"pulls: a draft, approved", @"PR #9 · draft · checks passing · approved",
      Line(@"[{\"number\":9,\"state\":\"OPEN\",\"isDraft\":true,\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"NEUTRAL\"}]}]"));
    T(@"pulls: no checks and no review say nothing of them", @"PR #10 · open",
      Line(@"[{\"number\":10,\"state\":\"OPEN\",\"reviewDecision\":\"\",\"statusCheckRollup\":[]}]"));
    T(@"pulls: merged, with when", @"PR #98 · merged 2 d ago",
      Line([NSString stringWithFormat:@"[{\"number\":98,\"state\":\"MERGED\",\"mergedAt\":\"%@\",\"statusCheckRollup\":[{\"conclusion\":\"FAILURE\",\"status\":\"COMPLETED\"}]}]", ISO(2 * 86400 + 60)]));
    T(@"pulls: closed", @"PR #5 · closed", Line(@"[{\"number\":5,\"state\":\"CLOSED\",\"reviewDecision\":\"REVIEW_REQUIRED\"}]"));
    T(@"pulls: no pull request for the branch", @"No pull request for this branch", Line(@"[]"));
    T(@"pulls: what is not gh's array shows nothing", @"nothing nothing nothing nothing",
      [NSString stringWithFormat:@"%@ %@ %@ %@", Line(@"{\"number\":1}"), Line(@"not json"), Line(@""), Line(@"[{\"title\":\"no number\"}]")]);
    MMWindowPull *p = MMWindowPullFrom(MMPullParse([@"[{\"number\":3,\"state\":\"OPEN\",\"url\":\"file:///etc/passwd\"}]" dataUsingEncoding:NSUTF8StringEncoding]));
    MMWindowPull *open = MMWindowPullFrom(MMPullParse([kOpen dataUsingEncoding:NSUTF8StringEncoding]));
    T(@"pulls: only a web address gets the press", @"no yes Tune the ranking", [NSString stringWithFormat:@"%@ %@ %@", YN(p.opens), YN(open.opens), open.title]);
    NSString *all = [@[Line(kOpen), Line(@"[]"), [MMWindowPull new].line, MMWindowOpenPull] componentsJoinedByString:@" "];
    MMWindowPull *look = [MMWindowPull new]; look.known = MMWindowPullLooking;
    T(@"pulls: the words hold no ellipsis", @"no Looking for a pull request", [NSString stringWithFormat:@"%@ %@", YN([all containsString:@"…"] || [all containsString:@"..."]), look.line]);
    T(@"pulls: gh is asked for the newest pull request of the branch, in every state, with only the fields the story needs",
      @"pr list --head fix-auth --state all --limit 1 --json number,title,state,isDraft,url,reviewDecision,statusCheckRollup,mergedAt,updatedAt",
      [MMPullArguments(@"fix-auth") componentsJoinedByString:@" "]);
}

/// The knower: gh missing or not logged in, the cache, a moved head, a time-out, a failure and the pref.
static void PullsKnower(void) {
    NSString *folder = Dir(@"trees/feature"), *repo = Dir(@"repo");
    GhFile(@"calls", nil);
    GhFile(@"answer.json", kOpen);
    MMPulls.shared.timeout = 1.5;

    // No gh on the PATH: nothing is asked and nothing shows.
    GhWorld(NO, YES);
    BOOL look = Want(folder, repo, @"feature", @"aaa");
    PullsSettle();
    T(@"pulls: with no gh, nothing is asked and nothing shows", @"no 0 nothing", [NSString stringWithFormat:@"%@ %lu %@", YN(look), (unsigned long)GhCalls().count,
      [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"].json[@"known"]]);
    // gh there, nobody logged in: no spawn either.
    GhWorld(YES, NO);
    look = Want(folder, repo, @"feature", @"aaa");
    PullsSettle();
    T(@"pulls: with gh not logged in, nothing is asked and nothing shows", @"no 0 nothing", [NSString stringWithFormat:@"%@ %lu %@", YN(look), (unsigned long)GhCalls().count,
      [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"].json[@"known"]]);
    // gh says to log in, as when its token was revoked: nothing shows, and gh is left alone for a while.
    GhWorld(YES, YES);
    GhFile(@"mode", @"auth");
    look = Want(folder, repo, @"feature", @"aaa");
    PullsSettle();
    BOOL again = Want(folder, repo, @"other", @"ccc");
    PullsSettle();
    T(@"pulls: gh that asks for a login shows nothing, and is not asked again soon", @"yes 1 nothing no 1",
      [NSString stringWithFormat:@"%@ %lu %@ %@ %lu", YN(look), (unsigned long)GhCalls().count, [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"].json[@"known"],
       YN(again), (unsigned long)GhCalls().count]);

    // The pref off: nothing is asked, and what is kept does not show.
    GhWorld(YES, YES);
    GhFile(@"calls", nil);
    MMSetPref(MMPullsPrefKey, @NO);
    look = Want(folder, repo, @"feature", @"aaa");
    PullsSettle();
    T(@"pulls: with the pref off, nothing is asked", @"no 0 nothing", [NSString stringWithFormat:@"%@ %lu %@", YN(look), (unsigned long)GhCalls().count,
      [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"].json[@"known"]]);
    MMSetPref(MMPullsPrefKey, nil);

    // Two looks at one branch make one call, and the answer is kept.
    look = Want(folder, repo, @"feature", @"aaa");
    MMPullKnown first = [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"].known;
    PullsSettle();
    MMPullAnswer *a = [MMPulls.shared knownFor:repo branch:@"feature" head:@"aaa"];
    BOOL second = Want(folder, repo, @"feature", @"aaa");
    PullsSettle();
    NSString *call = GhCalls().firstObject ?: @"";
    T(@"pulls: the first look says it is looking, then shows the answer", @"yes yes found 142", [NSString stringWithFormat:@"%@ %@ %@ %ld", YN(look),
      YN(first == MMPullLooking || first == MMPullFound), a.json[@"known"], (long)a.pull.number]);
    T(@"pulls: two looks at one branch make one gh call", @"no 1", [NSString stringWithFormat:@"%@ %lu", YN(second), (unsigned long)GhCalls().count]);
    T(@"pulls: gh runs in the worktree's folder with the branch", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN([call hasPrefix:[folder stringByAppendingString:@" "]]), YN([call hasSuffix:[MMPullArguments(@"feature") componentsJoinedByString:@" "]])]);
    // The head moved: gh is asked again, and the answer from before stands meanwhile, so the story does not flicker.
    GhFile(@"answer.json", [kOpen stringByReplacingOccurrencesOfString:@"\"COMPLETED\",\"conclusion\":\"SUCCESS\"" withString:@"\"COMPLETED\",\"conclusion\":\"FAILURE\""]);
    look = Want(folder, repo, @"feature", @"bbb");
    MMPullKnown during = [MMPulls.shared knownFor:repo branch:@"feature" head:@"bbb"].known;
    PullsSettle();
    MMWindowPull *now = MMWindowPullFrom([MMPulls.shared knownFor:repo branch:@"feature" head:@"bbb"]);
    T(@"pulls: a moved head asks gh again, and the old answer shows until the new one comes", @"no found 2 PR #142 · open · 1 check failing · review requested",
      [NSString stringWithFormat:@"%@ %@ %lu %@", YN(look), during == MMPullFound ? @"found" : @"other", (unsigned long)GhCalls().count, now.line]);
    // The answer is kept on disk, so `trees explain --json` knows it.
    NSData *kept = [NSData dataWithContentsOfFile:[MMExpertDir(@"workforest") stringByAppendingPathComponent:@"pulls.json"]];
    T(@"pulls: the answer is kept in the support folder", @"yes", YN([[[NSString alloc] initWithData:kept encoding:NSUTF8StringEncoding] containsString:@"\"number\":142"]));

    // A gh that does not answer in time: the look ends with nothing, and nothing hangs.
    GhWorld(YES, YES);
    GhFile(@"calls", nil);
    GhFile(@"mode", @"sleep");
    NSDate *t0 = NSDate.date;
    look = Want(folder, repo, @"slow", @"ddd");
    NSTimeInterval asked = -t0.timeIntervalSinceNow;
    MMPullKnown looking = [MMPulls.shared knownFor:repo branch:@"slow" head:@"ddd"].known;
    PullsSettle();
    NSTimeInterval took = -t0.timeIntervalSinceNow;
    MMPullAnswer *late = [MMPulls.shared knownFor:repo branch:@"slow" head:@"ddd"];
    BOOL retry = Want(folder, repo, @"slow", @"ddd");
    PullsSettle();
    T(@"pulls: a gh past its time: the ask does not wait, it shows Looking, then nothing", @"yes yes yes nothing", [NSString stringWithFormat:@"%@ %@ %@ %@",
      YN(look && asked < 0.5), YN(looking == MMPullLooking), YN(took < 5), late.json[@"known"]]);
    T(@"pulls: after a time-out the repo is backed off, so gh is not asked again at once", @"no 1 1", [NSString stringWithFormat:@"%@ %lu %@", YN(retry),
      (unsigned long)GhCalls().count, MMPulls.shared.stats[@"timeouts"] ?: @0]);
    // A failure, such as a repo that is not on GitHub: nothing shows.
    GhWorld(YES, YES);
    GhFile(@"mode", @"fail");
    Want(folder, repo, @"elsewhere", @"eee");
    PullsSettle();
    T(@"pulls: a failure shows nothing", @"nothing", [MMPulls.shared knownFor:repo branch:@"elsewhere" head:@"eee"].json[@"known"]);
    // Only the newest look runs: looks that came while gh ran and were replaced are dropped.
    GhWorld(YES, YES);
    GhFile(@"calls", nil);
    GhFile(@"answer.json", @"[]");
    dispatch_semaphore_t hold = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"workforest", @"prs", QOS_CLASS_UTILITY), ^{ dispatch_semaphore_wait(hold, DISPATCH_TIME_FOREVER); });
    for (NSString *b in @[@"one", @"two", @"three"]) Want(folder, repo, b, @"fff");
    dispatch_semaphore_signal(hold);
    PullsSettle(); PullsSettle(); PullsSettle();
    T(@"pulls: one gh at a time, and only for the newest look", @"1 none", [NSString stringWithFormat:@"%lu %@", (unsigned long)GhCalls().count,
      [MMPulls.shared knownFor:repo branch:@"three" head:@"fff"].json[@"known"]]);
    // Never on main: main reads no disk for gh.
    T(@"pulls: want refuses main", @"no", YN([MMPulls.shared want:folder repo:repo branch:@"main-thread" head:@"x"]));
}

/// The controller asks only for a story that shows, while the window is open, and never for a snapshot.
static void PullsController(void) {
    World();
    MMSetPref(MMWindowWelcomedKey, @YES);
    GhWorld(YES, YES);
    GhFile(@"calls", nil);
    GhFile(@"answer.json", kOpen);
    MMPulls.shared.timeout = 3;
    NSString *w1 = Dir(@"trees/fix-auth-redirect"), *w3 = Dir(@"repo");
    NSTimeInterval now = floor(NSDate.date.timeIntervalSince1970);
    NSDictionary *(^tree)(NSString *, BOOL) = ^(NSString *path, BOOL main) {
        return @{@"path": path, @"repo": w3, @"branch": main ? @"main" : path.lastPathComponent, @"main": @(main), @"head": @"1234567890abcdef",
                 @"gitKnown": @YES, @"defaultBranch": @"main", @"dirty": @0, @"untracked": @0, @"unpushed": @0, @"notInDefault": @3, @"behindDefault": @1,
                 @"subject": @"Fix the auth redirect", @"lastCommitAt": @(now - 7200), @"upstream": @"origin/x", @"maker": @"claude-code",
                 @"lastWorkAt": @(now - 3600)};
    };
    gFindings[@"workforest"] = @[Finding(@"workforest", @"worktree", w1, @"repo/fix-auth-redirect", w1, 0, 0, 2500 * MB, nil, tree(w1, NO)),
                                 Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 10 * GB, nil, tree(w3, YES))];
    NSString *key = [@"workforest:worktree:" stringByAppendingString:w1], *mainKey = [@"workforest:worktree:" stringByAppendingString:w3];
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); };
    MMWindowController *c = [MMWindowController new];
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };

    // Closed: a story asks nothing.
    [c windowShowsStory:key];
    settle(); PullsSettle();
    T(@"pulls: with the window closed, a story asks gh nothing", @"0", @(GhCalls().count));
    // Open: snapshot after snapshot builds models and asks nothing, as no tick does.
    [c setOpen:YES];
    for (uint64_t g = 2; g <= 6; g++) { [c take:SnapshotAt(g)]; Spin(20, ^BOOL { return models.lastObject.generation == g; }); }
    settle(); PullsSettle();
    MMWindowRow *row = [models.lastObject row:key];
    T(@"pulls: five snapshots build five models and ask gh nothing", @"5 0 no", [NSString stringWithFormat:@"%lu %lu %@", (unsigned long)models.count,
      (unsigned long)GhCalls().count, YN(row.pull != nil)]);
    // Its git, in plain words, from WorkForest's facts.
    NSMutableArray *facts = [NSMutableArray new];
    for (MMWindowFact *f in row.facts) [facts addObject:[NSString stringWithFormat:@"%@: %@", f.label, f.value]];
    NSString *told = [facts componentsJoinedByString:@" | "];
    T(@"pulls: the worktree's story says its last commit, where it stands against main and who made it",
      @"yes yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN([told containsString:@"Last commit: Fix the auth redirect · 1234567 · 2 h ago"]),
                        YN([told containsString:@"Against: 3 ahead, 1 behind main"]), YN([told containsString:@"Made by: Claude Code"])]);
    // The main checkout's story asks nothing.
    [c windowShowsStory:mainKey];
    settle(); PullsSettle();
    T(@"pulls: the main checkout's story asks gh nothing", @"0", @(GhCalls().count));
    // A linked worktree's story asks once, and the model that follows holds the answer.
    [c windowShowsStory:key];
    BOOL got = Spin(20, ^BOOL { return [models.lastObject row:key].pull.known == MMWindowPullFound; });
    MMWindowPull *p = [models.lastObject row:key].pull;
    T(@"pulls: a worktree's story asks gh once, and the next model holds its pull request", @"yes 1 PR #142 · open · checks passing · review requested yes",
      [NSString stringWithFormat:@"%@ %lu %@ %@", YN(got), (unsigned long)GhCalls().count, p.line, YN(p.opens)]);
    // A second look at it, and new snapshots, keep the answer and ask nothing.
    [c windowShowsStory:key];
    [c take:SnapshotAt(7)];
    Spin(20, ^BOOL { return models.lastObject.generation == 7; });
    settle(); PullsSettle();
    T(@"pulls: a second look and a new snapshot ask gh nothing more", @"1 yes", [NSString stringWithFormat:@"%lu %@", (unsigned long)GhCalls().count,
      YN([models.lastObject row:key].pull.known == MMWindowPullFound)]);
    // The pref off, from Settings: the story shows no pull request, and nothing is asked.
    [c windowSetSwitch:@"prs" on:NO];
    settle();
    Spin(5, ^BOOL { return [models.lastObject row:key].pull == nil; });
    [MMPulls.shared forget];
    [c windowShowsStory:mainKey]; [c windowShowsStory:key];
    settle(); PullsSettle();
    MMWindowSwitch *sw = nil;
    for (MMWindowSwitch *s in models.lastObject.settings.switches) if ([s.switchID isEqualToString:@"prs"]) sw = s;
    T(@"pulls: Settings turns it off: no pull request shows and gh is not asked", @"no 1 off This Mac", [NSString stringWithFormat:@"%@ %lu %@ %@",
      YN([models.lastObject row:key].pull != nil), (unsigned long)GhCalls().count, sw.on ? @"on" : @"off", sw.card]);
    [c windowSetSwitch:@"prs" on:YES];
    settle();
    // Closed again: nothing.
    [c setOpen:NO];
    [MMPulls.shared forget];
    GhWorld(YES, YES);
    [c windowShowsStory:key];
    settle(); PullsSettle();
    T(@"pulls: after the window closed, a story asks gh nothing", @"1", @(GhCalls().count));
}

static void Pulls(void) {
    gGh = [gDir stringByAppendingPathComponent:@"ghbin"];
    [NSFileManager.defaultManager createDirectoryAtPath:gGh withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *fake = [gGh stringByAppendingPathComponent:@"gh"];
    [NSFileManager.defaultManager removeItemAtPath:fake error:nil];
    BOOL copied = [NSFileManager.defaultManager copyItemAtPath:@"test/window/gh" toPath:fake error:nil];
    T(@"pulls: the fake gh is in the test home", @"yes", YN(copied && [NSFileManager.defaultManager isExecutableFileAtPath:fake]));
    if (!copied) return;
    PullsParse();
    PullsKnower();
    PullsController();
}
