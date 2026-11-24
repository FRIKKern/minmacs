// A branch's pull request through the person's gh, MMPulls.h.
#import "Core/Know/MMPulls.h"
#import "Core/Know/MMGit.h"
#import "Core/Store/MMStore.h"
#import "Core/Runtime/MMRuntime.h"

NSString *const MMPullsPrefKey = @"workforest.pullRequests";
NSNotificationName const MMPullsDidChangeNotification = @"MMPullsDidChange";

static const NSTimeInterval kFirstBackOff = 60, kMostBackOff = 30 * 60;   // a repo whose ask failed, doubling
static const NSTimeInterval kNoGh = 10 * 60;            // gh missing or not logged in: looked for again after this
static const NSTimeInterval kGhLookedFor = 60;          // where gh is, and whether it is logged in, kept this long
static const NSUInteger kKept = 200;                    // answers kept in the file, the newest

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }

static NSDate *ISODate(id v) {
    NSString *s = Str(v);
    // gh writes a time that never happened as the year 1 for a pull request that is not merged.
    if (!s || [s hasPrefix:@"0001-"]) return nil;
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSISO8601DateFormatter new]; });
    @synchronized (f) { return [f dateFromString:s]; }
}

#pragma mark - One pull request

@implementation MMPull

- (NSDictionary *)json {
    return @{@"number": @(self.number), @"title": self.title ?: @"", @"url": self.url ?: @"", @"state": self.stateWord ?: @"",
             @"draft": @(self.draft), @"review": self.review ?: NSNull.null,
             @"checks": @{@"passing": @(self.checksPassing), @"failing": @(self.checksFailing), @"pending": @(self.checksPending)},
             @"mergedAt": self.mergedAt ? @(self.mergedAt.timeIntervalSince1970) : NSNull.null,
             @"updatedAt": self.updatedAt ? @(self.updatedAt.timeIntervalSince1970) : NSNull.null};
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:NSDictionary.class] || [Num(j[@"number"]) integerValue] <= 0) return nil;
    MMPull *p = [MMPull new];
    p.number = [j[@"number"] integerValue]; p.title = Str(j[@"title"]) ?: @""; p.url = Str(j[@"url"]) ?: @"";
    p.stateWord = Str(j[@"state"]) ?: @"open"; p.draft = [Num(j[@"draft"]) boolValue]; p.review = Str(j[@"review"]);
    NSDictionary *c = [j[@"checks"] isKindOfClass:NSDictionary.class] ? j[@"checks"] : @{};
    p.checksPassing = [Num(c[@"passing"]) integerValue]; p.checksFailing = [Num(c[@"failing"]) integerValue]; p.checksPending = [Num(c[@"pending"]) integerValue];
    if ([Num(j[@"mergedAt"]) doubleValue] > 0) p.mergedAt = [NSDate dateWithTimeIntervalSince1970:[j[@"mergedAt"] doubleValue]];
    if ([Num(j[@"updatedAt"]) doubleValue] > 0) p.updatedAt = [NSDate dateWithTimeIntervalSince1970:[j[@"updatedAt"] doubleValue]];
    return p;
}

@end

@implementation MMPullAnswer
- (NSDictionary *)json {
    NSString *known = @[@"nothing", @"looking", @"none", @"found"][(NSUInteger)MAX(0, MIN(self.known, MMPullFound))];
    return @{@"known": known, @"pull": self.pull.json ?: NSNull.null,
             @"checkedAt": self.checkedAt ? @(self.checkedAt.timeIntervalSince1970) : NSNull.null};
}
@end

#pragma mark - gh's answer

/// One entry of statusCheckRollup: a check run, with a status and a conclusion, or a commit status, with a state.
/// 1 passing, -1 failing, 0 still running.
static NSInteger CheckOutcome(NSDictionary *c) {
    NSString *conclusion = Str(c[@"conclusion"]).uppercaseString, *status = Str(c[@"status"]).uppercaseString, *state = Str(c[@"state"]).uppercaseString;
    if (state && !status) {
        if ([state isEqualToString:@"SUCCESS"]) return 1;
        if ([state isEqualToString:@"FAILURE"] || [state isEqualToString:@"ERROR"]) return -1;
        return 0;   // PENDING, EXPECTED
    }
    if (status && ![status isEqualToString:@"COMPLETED"]) return 0;
    if (!conclusion) return 0;
    if ([@[@"SUCCESS", @"NEUTRAL", @"SKIPPED"] containsObject:conclusion]) return 1;
    if ([conclusion isEqualToString:@"STALE"]) return 0;
    return -1;   // FAILURE, CANCELLED, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE
}

MMPullAnswer *MMPullParse(NSData *json) {
    if (!json.length) return nil;
    id a = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![a isKindOfClass:NSArray.class]) return nil;
    MMPullAnswer *answer = [MMPullAnswer new];
    answer.known = MMPullNone;
    NSDictionary *j = [a count] && [[a firstObject] isKindOfClass:NSDictionary.class] ? [a firstObject] : nil;
    if (!j) return [a count] ? nil : answer;
    if ([Num(j[@"number"]) integerValue] <= 0) return nil;
    MMPull *p = [MMPull new];
    p.number = [j[@"number"] integerValue];
    p.title = Str(j[@"title"]) ?: @"";
    NSString *url = Str(j[@"url"]);
    // Only a web address of the pull request opens from the window.
    p.url = [url hasPrefix:@"https://"] ? url : @"";
    NSString *state = Str(j[@"state"]).uppercaseString;
    p.stateWord = [state isEqualToString:@"MERGED"] ? @"merged" : [state isEqualToString:@"CLOSED"] ? @"closed" : @"open";
    p.draft = [Num(j[@"isDraft"]) boolValue];
    NSString *review = Str(j[@"reviewDecision"]).uppercaseString;
    p.review = [review isEqualToString:@"APPROVED"] ? @"approved" : [review isEqualToString:@"CHANGES_REQUESTED"] ? @"changes requested"
             : [review isEqualToString:@"REVIEW_REQUIRED"] ? @"review requested" : nil;
    NSArray *checks = [j[@"statusCheckRollup"] isKindOfClass:NSArray.class] ? j[@"statusCheckRollup"] : @[];
    for (id c in checks) {
        if (![c isKindOfClass:NSDictionary.class]) continue;
        NSInteger o = CheckOutcome(c);
        if (o > 0) p.checksPassing++; else if (o < 0) p.checksFailing++; else p.checksPending++;
    }
    p.mergedAt = ISODate(j[@"mergedAt"]);
    p.updatedAt = ISODate(j[@"updatedAt"]);
    answer.pull = p;
    answer.known = MMPullFound;
    return answer;
}

NSArray<NSString *> *MMPullArguments(NSString *branch) {
    return @[@"pr", @"list", @"--head", branch ?: @"", @"--state", @"all", @"--limit", @"1",
             @"--json", @"number,title,state,isDraft,url,reviewDecision,statusCheckRollup,mergedAt,updatedAt"];
}

#pragma mark - The knower

/// One kept answer: what gh said for a branch, at which head and when.
@interface MMPullEntry : NSObject
@property (strong) MMPull *pull;                         // nil: no pull request
@property (copy) NSString *head;
@property (strong) NSDate *at;
@end
@implementation MMPullEntry
@end

@implementation MMPulls {
    // All under @synchronized (self). gh itself runs on the queue, outside the lock.
    NSMutableDictionary<NSString *, MMPullEntry *> *_answers;   // by repo and branch
    BOOL _loaded;                                               // the kept file was read
    NSMutableDictionary<NSString *, NSDate *> *_looking;        // a look's start, by key
    NSDictionary *_wanted;                                      // the newest ask: folder, repo, branch, head, key
    NSString *_running;                                         // the key gh runs for now
    NSMutableDictionary<NSString *, NSDate *> *_failUntil;      // by repo
    NSMutableDictionary<NSString *, NSNumber *> *_backOff;      // by repo, the next wait
    NSDate *_noGhUntil;
    NSString *_gh;                                              // where gh is, or nil
    NSDate *_ghAt;                                              // when that was looked for
    NSMutableDictionary<NSString *, NSNumber *> *_stats;
}

+ (instancetype)shared {
    static MMPulls *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMPulls new]; });
    return p;
}

+ (BOOL)enabled { return MMPrefBool(MMPullsPrefKey, YES); }

- (instancetype)init {
    if ((self = [super init])) {
        _timeout = 5; _fresh = 5 * 60;
        _answers = [NSMutableDictionary new]; _looking = [NSMutableDictionary new];
        _failUntil = [NSMutableDictionary new]; _backOff = [NSMutableDictionary new]; _stats = [NSMutableDictionary new];
    }
    return self;
}

static dispatch_queue_t Queue(void) { return MMQueue(@"workforest", @"prs", QOS_CLASS_UTILITY); }
static NSString *Key(NSString *repo, NSString *branch) { return [NSString stringWithFormat:@"%@\n%@", repo ?: @"", branch ?: @""]; }

- (void)count:(NSString *)what { @synchronized (self) { _stats[what] = @([_stats[what] integerValue] + 1); } }
- (NSDictionary *)stats { @synchronized (self) { return [_stats copy]; } }

#pragma mark Where gh is

/// The path with every link resolved, as the kernel names it, or nil.
static NSString *Real(NSString *path) {
    char buf[PATH_MAX];
    return path.length && realpath(path.fileSystemRepresentation, buf) ? @(buf) : nil;
}

/// gh on the PATH, then where Homebrew and the installer put it. In a test home only the PATH counts, and only a gh
/// inside the test home: a check reaches a fake, never the real gh.
static NSString *FindGh(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *home = Str(env[@"MINMACS_HOME"]);
    NSMutableArray<NSString *> *dirs = [[Str(env[@"PATH"]) ?: @"" componentsSeparatedByString:@":"] mutableCopy];
    if (!home) [dirs addObjectsFromArray:@[@"/opt/homebrew/bin", @"/usr/local/bin", [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"]]];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *d in dirs) {
        if (!d.length) continue;
        NSString *p = [d stringByAppendingPathComponent:@"gh"];
        if (![fm isExecutableFileAtPath:p]) continue;
        if (home) {
            NSString *real = Real(p), *root = Real(home);
            if (!real || !root || ![real hasPrefix:[root stringByAppendingString:@"/"]]) continue;
        }
        return p;
    }
    return nil;
}

/// gh keeps who is logged in under hosts.yml in its config folder, and a token in the environment counts too.
/// A stat, so a person who never logged in costs no spawn.
static BOOL LoggedIn(void) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    for (NSString *k in @[@"GH_TOKEN", @"GITHUB_TOKEN", @"GH_ENTERPRISE_TOKEN", @"GITHUB_ENTERPRISE_TOKEN"]) if (Str(env[k])) return YES;
    NSString *dir = Str(env[@"GH_CONFIG_DIR"]);
    if (!dir) dir = Str(env[@"XDG_CONFIG_HOME"]) ? [env[@"XDG_CONFIG_HOME"] stringByAppendingPathComponent:@"gh"] : [NSHomeDirectory() stringByAppendingPathComponent:@".config/gh"];
    return [NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:@"hosts.yml"]];
}

/// What gh gets on top of MMRun's clean environment: git for the repo's remote, gh's own config and login, a proxy
/// when there is one, and no prompt, pager, color or update check.
static NSDictionary *GhEnvironment(NSString *gh) {
    NSDictionary *ours = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *e = [MMGitEnvironment() mutableCopy] ?: [NSMutableDictionary new];
    NSMutableArray *path = [NSMutableArray arrayWithObject:gh.stringByDeletingLastPathComponent];
    NSString *git = MMGitPath().stringByDeletingLastPathComponent;
    if (git.length && ![path containsObject:git]) [path addObject:git];
    [path addObjectsFromArray:@[@"/usr/bin", @"/bin"]];
    e[@"PATH"] = [path componentsJoinedByString:@":"];
    for (NSString *k in @[@"GH_CONFIG_DIR", @"XDG_CONFIG_HOME", @"GH_TOKEN", @"GITHUB_TOKEN", @"GH_ENTERPRISE_TOKEN", @"GITHUB_ENTERPRISE_TOKEN",
                          @"GH_HOST", @"HTTPS_PROXY", @"https_proxy", @"HTTP_PROXY", @"http_proxy", @"NO_PROXY", @"no_proxy", @"ALL_PROXY",
                          @"all_proxy", @"SSL_CERT_FILE", @"SSL_CERT_DIR"])
        if (Str(ours[k])) e[k] = ours[k];
    [e addEntriesFromDictionary:@{@"GH_PROMPT_DISABLED": @"1", @"GH_NO_UPDATE_NOTIFIER": @"1", @"GH_NO_EXTENSION_UPDATE_NOTIFIER": @"1",
                                  @"GH_PAGER": @"cat", @"NO_COLOR": @"1", @"GH_SPINNER_DISABLED": @"1"}];
    return e;
}

/// Under the lock. gh's place, looked for again at most once a minute.
- (NSString *)gh {
    NSDate *now = NSDate.date;
    if (!_ghAt || -_ghAt.timeIntervalSinceNow > kGhLookedFor) { _gh = FindGh(); _ghAt = now; }
    return _gh;
}

#pragma mark The kept answers

static NSString *KeptFile(void) { return [MMExpertDir(@"workforest") stringByAppendingPathComponent:@"pulls.json"]; }

/// Under the lock. The answers an earlier run kept, read once, so the CLI knows them too.
- (void)load {
    if (_loaded) return;
    _loaded = YES;
    NSData *d = [NSData dataWithContentsOfFile:KeptFile()];
    NSDictionary *all = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![all isKindOfClass:NSDictionary.class]) return;
    for (NSString *key in all) {
        NSDictionary *v = all[key];
        if (![v isKindOfClass:NSDictionary.class] || [Num(v[@"at"]) doubleValue] <= 0 || _answers[key]) continue;
        MMPullEntry *e = [MMPullEntry new];
        e.pull = [MMPull fromJSON:v[@"pull"]]; e.head = Str(v[@"head"]);
        e.at = [NSDate dateWithTimeIntervalSince1970:[v[@"at"] doubleValue]];
        _answers[key] = e;
    }
}

/// On the queue, after an answer. The newest kKept answers, written whole.
- (void)save {
    NSMutableDictionary *out = [NSMutableDictionary new];
    @synchronized (self) {
        NSArray *keys = [_answers keysSortedByValueUsingComparator:^NSComparisonResult(MMPullEntry *a, MMPullEntry *b) { return [b.at compare:a.at]; }];
        for (NSString *k in [keys subarrayWithRange:NSMakeRange(0, MIN(keys.count, kKept))]) {
            MMPullEntry *e = _answers[k];
            out[k] = @{@"pull": e.pull.json ?: NSNull.null, @"head": e.head ?: NSNull.null, @"at": @(e.at.timeIntervalSince1970)};
        }
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
    [d writeToFile:KeptFile() atomically:YES];
}

#pragma mark Asking

- (MMPullAnswer *)knownFor:(NSString *)repo branch:(NSString *)branch head:(NSString *)head {
    MMPullAnswer *a = [MMPullAnswer new];
    if (!repo.length || !branch.length || ![MMPulls enabled]) return a;
    NSString *key = Key(repo, branch);
    @synchronized (self) {
        [self load];
        MMPullEntry *e = _answers[key];
        BOOL asking = [_running isEqualToString:key] || [_wanted[@"key"] isEqualToString:key];
        // An answer at the head asked for, or one at an older head while gh is asked again for this one.
        if (e && (!head.length || [e.head isEqualToString:head] || asking)) {
            a.known = e.pull ? MMPullFound : MMPullNone;
            a.pull = e.pull; a.checkedAt = e.at; a.head = e.head;
            return a;
        }
        NSDate *since = _looking[key];
        if (since && -since.timeIntervalSinceNow < self.timeout + 1) a.known = MMPullLooking;
    }
    return a;
}

- (BOOL)want:(NSString *)folder repo:(NSString *)repo branch:(NSString *)branch head:(NSString *)head {
    if (NSThread.isMainThread || !folder.length || !repo.length || !branch.length || ![MMPulls enabled]) return NO;
    NSString *key = Key(repo, branch);
    BOOL look = NO;
    @synchronized (self) {
        [self load];
        MMPullEntry *e = _answers[key];
        if (e && [e.head isEqualToString:head ?: @""] && -e.at.timeIntervalSinceNow < self.fresh) { _stats[@"fresh"] = @([_stats[@"fresh"] integerValue] + 1); return NO; }
        if ([_running isEqualToString:key]) return NO;
        if (_noGhUntil && _noGhUntil.timeIntervalSinceNow > 0) return NO;
        if (_failUntil[repo].timeIntervalSinceNow > 0) { _stats[@"backedOff"] = @([_stats[@"backedOff"] integerValue] + 1); return NO; }
        if (!self.gh || !LoggedIn()) { _noGhUntil = [NSDate dateWithTimeIntervalSinceNow:kNoGh]; _stats[@"noGh"] = @([_stats[@"noGh"] integerValue] + 1); return NO; }
        _wanted = @{@"folder": folder, @"repo": repo, @"branch": branch, @"head": head ?: @"", @"key": key};
        // A branch with no answer yet says it is looking. One with an older answer keeps showing it meanwhile.
        if (!e) { _looking[key] = NSDate.date; look = YES; }
    }
    dispatch_async(Queue(), ^{ [self runWanted]; });
    return look;
}

/// On the queue: gh for the newest ask, if one still waits. Asks that came meanwhile and were replaced are dropped.
- (void)runWanted {
    NSDictionary *w;
    NSString *gh;
    @synchronized (self) {
        w = _wanted;
        _wanted = nil;
        if (!w) return;
        _running = w[@"key"];
        gh = self.gh;
    }
    NSString *repo = w[@"repo"], *key = w[@"key"];
    NSData *out = nil, *err = nil;
    MMRunResult r = { .status = -1, .timedOut = NO, .didRun = NO };
    if (gh) {
        [self count:@"calls"];
        r = MMRun(gh, MMPullArguments(w[@"branch"]), nil, GhEnvironment(gh), w[@"folder"], self.timeout, &out, &err);
    }
    MMPullAnswer *answer = r.status == 0 && !r.timedOut ? MMPullParse(out) : nil;
    NSString *said = err.length ? [[NSString alloc] initWithData:err encoding:NSUTF8StringEncoding] ?: @"" : @"";
    BOOL notLoggedIn = r.status == 4 || [said containsString:@"gh auth login"];
    @synchronized (self) {
        _running = nil;
        [_looking removeObjectForKey:key];
        if (answer) {
            MMPullEntry *e = [MMPullEntry new];
            e.pull = answer.pull; e.head = w[@"head"]; e.at = NSDate.date;
            _answers[key] = e;
            [_failUntil removeObjectForKey:repo]; [_backOff removeObjectForKey:repo];
            _stats[@"answers"] = @([_stats[@"answers"] integerValue] + 1);
        } else if (!gh || notLoggedIn) {
            _noGhUntil = [NSDate dateWithTimeIntervalSinceNow:kNoGh];
            _stats[@"notLoggedIn"] = @([_stats[@"notLoggedIn"] integerValue] + 1);
        } else {
            NSTimeInterval wait = [_backOff[repo] doubleValue] ?: kFirstBackOff;
            _failUntil[repo] = [NSDate dateWithTimeIntervalSinceNow:wait];
            _backOff[repo] = @(MIN(wait * 2, kMostBackOff));
            _stats[r.timedOut ? @"timeouts" : @"failures"] = @([_stats[r.timedOut ? @"timeouts" : @"failures"] integerValue] + 1);
        }
    }
    if (answer) [self save];
    [NSNotificationCenter.defaultCenter postNotificationName:MMPullsDidChangeNotification object:self];
}

#ifdef MM_TESTS
- (void)forget {
    @synchronized (self) {
        [_answers removeAllObjects]; [_looking removeAllObjects]; [_failUntil removeAllObjects]; [_backOff removeAllObjects];
        [_stats removeAllObjects];
        _wanted = nil; _noGhUntil = nil; _gh = nil; _ghAt = nil; _loaded = YES;
    }
}
#endif

@end
