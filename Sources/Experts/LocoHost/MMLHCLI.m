// LocoHost's CLI verbs, registered through MMExpert. Ported from RunCLI in LocoHost's main.m.
// The 2.0 verbs are hosts, where, review and restore. The 1.x verbs keep their names, so `locohost list` and the rest
// work when the binary runs as locohost. A verb whose usage starts with "locohost " is one of those.
// Every verb takes --json and --dry-run. A verb that stops or starts something runs its action off the main thread,
// through MMRunAction or MMUndo, as Core requires. Every verb prints through its MMArgs, so its output reaches the
// terminal from the app too, and reads the snapshot MMArgs gives it: the app's, or the CLI's cold one from Sources/CLI.
// No verb samples on its own.
#import <AppKit/AppKit.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/LocoHost/MMLHScan.h"
#import "UI/MMFormat.h"
#import "CLI/MMArgs.h"

extern BOOL MMLHInCLI;
static NSString *const kExpert = @"locohost";

#pragma mark - Arguments

/// The words after the verb, flags and their values included, as the person typed them.
static NSArray<NSString *> *Words(MMArgs *a) {
    NSMutableArray *out = [NSMutableArray new];
    for (id x in a.all) if ([x isKindOfClass:NSString.class]) [out addObject:x];
    return out;
}

/// The parsed words of one verb run.
@interface MMLHArgs : NSObject
@property (copy) NSArray<NSString *> *words;
@property (copy) NSString *arg1, *arg2;
@property BOOL json, dry, yes, force;
- (BOOL)has:(NSString *)flag;
- (NSString *)opt:(NSString *)name;
@end
@implementation MMLHArgs
- (BOOL)has:(NSString *)flag { return [self.words containsObject:flag]; }
- (NSString *)opt:(NSString *)name {
    NSUInteger i = [self.words indexOfObject:name];
    return i != NSNotFound && i + 1 < self.words.count ? self.words[i + 1] : nil;
}
@end

static MMLHArgs *Parse(MMArgs *raw) {
    MMLHArgs *a = [MMLHArgs new];
    a.words = Words(raw);
    NSMutableArray *pos = [NSMutableArray new];
    NSSet *valued = [NSSet setWithArray:@[@"--port", @"--mode", @"--model", @"--timeout", @"--hours"]];
    for (NSUInteger i = 0; i < a.words.count; i++) {
        NSString *w = a.words[i];
        if ([valued containsObject:w]) { i++; continue; }
        if (![w hasPrefix:@"--"]) [pos addObject:w];
    }
    a.arg1 = pos.count > 0 ? pos[0] : nil; a.arg2 = pos.count > 1 ? pos[1] : nil;
    a.json = [a has:@"--json"]; a.dry = [a has:@"--dry-run"]; a.yes = [a has:@"--yes"]; a.force = [a has:@"--force"];
    return a;
}

#pragma mark - Output

/// The MMArgs of the verb that runs on this thread. A verb in the app runs on core.sock's queue, so the thread says which.
static NSString *const kArgsKey = @"no.guerrilla.minmacs.locohost.args";
static MMArgs *CurrentArgs(void) { return NSThread.currentThread.threadDictionary[kArgsKey]; }

/// One or more lines, through MMArgs when a verb runs. A final newline is dropped, since MMArgs adds one.
static void Emit(NSString *s, BOOL err) {
    if ([s hasSuffix:@"\n"]) s = [s substringToIndex:s.length - 1];
    MMArgs *a = CurrentArgs();
    if (a && err) [a error:@"%@", s];
    else if (a) [a print:@"%@", s];
    else fputs([s stringByAppendingString:@"\n"].UTF8String, err ? stderr : stdout);
}
static void Print(NSString *s) { Emit(s ?: @"", NO); }
static void Err(NSString *s) { Emit(s ?: @"", YES); }

/// printf's format, through MMArgs. %s takes UTF-8, as the table code passes it.
static void Outf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void Outf(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    char *buf = NULL;
    int n = vasprintf(&buf, fmt, ap);
    va_end(ap);
    if (n >= 0 && buf) Emit([NSString stringWithUTF8String:buf] ?: @"", NO);
    free(buf);
}

static void PrintJSON(id obj) {
    MMArgs *a = CurrentArgs();
    if (a) { [a printJSON:obj ?: @{}]; return; }
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj ?: @{} options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d ?: NSData.data encoding:NSUTF8StringEncoding].UTF8String);
}

static int Usage(NSString *usage) { Err([@"usage: " stringByAppendingString:usage]); return 2; }

static BOOL Confirm(NSString *q) {
    // A verb handed to the app has no terminal to ask on.
    if (CurrentArgs().inApp) { Err(@"add --yes, since MinMacs cannot ask from here"); return NO; }
    printf("%s [y/N] ", q.UTF8String); fflush(stdout);
    char buf[8] = {0};
    return fgets(buf, sizeof buf, stdin) && (buf[0] == 'y' || buf[0] == 'Y');
}

#pragma mark - Ports

static BOOL Connects(const char *addr, int family, NSInteger port) {
    int fd = socket(family, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_storage ss = {0}; socklen_t len;
    if (family == AF_INET) {
        struct sockaddr_in *a = (struct sockaddr_in *)&ss; a->sin_family = AF_INET; a->sin_port = htons((uint16_t)port);
        inet_pton(AF_INET, addr, &a->sin_addr); len = sizeof *a;
    } else {
        struct sockaddr_in6 *a = (struct sockaddr_in6 *)&ss; a->sin6_family = AF_INET6; a->sin6_port = htons((uint16_t)port);
        inet_pton(AF_INET6, addr, &a->sin6_addr); len = sizeof *a;
    }
    BOOL ok = connect(fd, (struct sockaddr *)&ss, len) == 0;
    close(fd);
    return ok;
}

/// Anything answers a TCP connect on loopback.
static BOOL Listening(NSInteger port) { return Connects("127.0.0.1", AF_INET, port) || Connects("::1", AF_INET6, port); }

static BOOL PortFree(NSInteger port) {
    if (Listening(port)) return NO;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    BOOL ok = bind(fd, (struct sockaddr *)&a, sizeof a) == 0;
    close(fd);
    return ok;
}

static NSInteger HTTPStatus(NSInteger port) {
    __block NSInteger status = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 2;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    [[s dataTaskWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/", (long)port]]
      completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        if ([resp isKindOfClass:NSHTTPURLResponse.class]) status = ((NSHTTPURLResponse *)resp).statusCode;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    [s invalidateAndCancel];
    return status;
}

#pragma mark - The snapshot

/// The snapshot this verb reads, from MMArgs: the app's current one, or in the CLI one Sources/CLI builds cold.
/// settled waits for a second sample a second after the first, so CPU and new connections count, as 0.1 did.
/// LocoHost never samples here: the CLI's cold fact source in Sources/CLI does, through Senses.
static MMSnapshot *Snap(BOOL settled) {
    MMArgs *a = CurrentArgs();
    return settled ? a.settledSnapshot : a.snapshot;
}

static NSArray<MMFinding *> *Findings(MMSnapshot *s) { return [s findingsFor:kExpert]; }

static MMLHHost *Host(MMFinding *f) { return [MMLHHost fromJSON:f.facts]; }

/// The finding on this port, or of this pid.
static MMFinding *FindPort(MMSnapshot *s, NSString *arg) {
    NSInteger n = arg.integerValue;
    if (n <= 0) return nil;
    for (MMFinding *f in Findings(s)) if ([Host(f).ports containsObject:@(n)]) return f;
    for (MMFinding *f in Findings(s)) if (Host(f).pid == n) return f;
    return nil;
}

static NSArray<MMFinding *> *Scoped(NSArray<MMFinding *> *fs, MMLHArgs *a) {
    NSString *p = [a opt:@"--port"];
    if (!p) return fs;
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in fs) if ([Host(f).ports containsObject:@(p.integerValue)]) [out addObject:f];
    return out;
}

static NSInteger ModeOpt(MMLHArgs *a) {
    NSString *m = [a opt:@"--mode"];
    return m ? MMModeFrom(m) : MMModeFor(kExpert);
}

/// Runs block on LocoHost's act queue and waits. dispatch_sync would run it on the calling thread, which is main
/// in the CLI, and Core refuses to act on main.
static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(kExpert, @"act", QOS_CLASS_USER_INITIATED), ^{ block(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

/// Runs an action the way Core requires: off the main thread, through MMRunAction, waiting for it.
static MMUndoRecord *Run(id<MMAction> action, id<MMExpertPolicy> policy, MMReview *r, NSString *by, NSString *why, NSString **error) {
    __block MMUndoRecord *rec = nil;
    __block NSString *err = nil;
    OffMain(^{ rec = MMRunAction(action, policy, r, by, why, &err); });
    if (error) *error = err ?: rec.error;
    return rec;
}

static NSDictionary *VerdictJSON(MMVerdict *v, MMReview *r) {
    if (!v) return nil;
    NSString *model = nil;
    for (MMUsage *u in r.calls) if (u.model.length) model = u.model;
    return @{@"verdict": v.word ?: @"unsure", @"confidence": @(v.confidence), @"about": v.about ?: @"", @"reason": v.reason ?: @"",
             @"keepEvidence": v.keepEvidence ?: @"", @"judged": @(v.judged), @"decidedBy": v.decidedBy ?: @"",
             @"model": model ?: @"", @"at": @(r.at.timeIntervalSince1970)};
}

static NSDictionary *HostJSON(MMFinding *f, MMReview *r) {
    NSMutableDictionary *j = [f.facts mutableCopy];
    j[@"findingID"] = f.findingID;
    NSDictionary *v = VerdictJSON(MMLHVerdictFor(f, r), r);
    if (v) j[@"review"] = v;
    return j;
}

static NSString *Mark(MMFinding *f, MMReview *r) {
    MMLHHost *h = Host(f);
    if (h.state == MMLHActive) return @"●";
    if (MMLHVerdictFor(f, r).kind == MMVerdictGo && h.state == MMLHIdle) return @"◇";
    return h.state == MMLHRecent ? @"◐" : @"○";
}

static NSString *ModelOf(MMReview *r) {
    NSString *m = nil;
    for (MMUsage *u in r.calls) if (u.model.length) m = u.model;
    return m ?: @"";
}

#pragma mark - Verbs

static int Free(MMLHArgs *a) {
    for (NSInteger p = a.arg1 ? a.arg1.integerValue : 3000; p > 0 && p < 65536; p++)
        if (PortFree(p)) { if (a.json) PrintJSON(@{@"port": @(p)}); else Outf("%ld\n", (long)p); return 0; }
    return 1;
}

static int Ready(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost ready <port> [--http] [--timeout s]");
    NSInteger port = a.arg1.integerValue;
    double timeout = [a opt:@"--timeout"] ? [a opt:@"--timeout"].doubleValue : 60;
    BOOL http = [a has:@"--http"];
    NSDate *start = NSDate.date;
    while (-start.timeIntervalSinceNow < timeout) {
        if (Listening(port)) {
            NSInteger st = http ? HTTPStatus(port) : 0;
            if (!http || (st > 0 && st < 500)) {
                if (a.json) PrintJSON(@{@"port": @(port), @"ready": @YES, @"seconds": @(-start.timeIntervalSinceNow), @"http": @(st)});
                else Outf("ready :%ld after %.1fs%s\n", (long)port, -start.timeIntervalSinceNow, http ? [NSString stringWithFormat:@", HTTP %ld", (long)st].UTF8String : "");
                return 0;
            }
        }
        [NSThread sleepForTimeInterval:0.25];
    }
    Err([NSString stringWithFormat:@"not ready: nothing %@ on :%ld after %.0fs", http ? @"answered HTTP" : @"accepted a connection", (long)port, timeout]);
    return 1;
}

/// One table row from its columns, each [text, width] or [text, width, @YES] for right aligned. The last runs on.
/// An empty column of width n is a gap of n spaces.
/// Widths count characters, so a cut name or a state mark never pushes the next column over.
static NSString *Row(NSArray<NSArray *> *cols) {
    NSMutableString *line = [NSMutableString new];
    for (NSUInteger i = 0; i < cols.count; i++) {
        NSArray *c = cols[i];
        NSString *t = [c[0] isKindOfClass:NSString.class] ? c[0] : [c[0] description];
        NSUInteger w = [c[1] unsignedIntegerValue];
        if (i + 1 == cols.count && !w) [line appendString:t];
        else [line appendString:c.count > 2 ? MMColumnRight(t, w) : MMColumn(t, w)];
    }
    return [line stringByReplacingOccurrencesOfString:@"\\s+$" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, line.length)];
}

static void PrintHosts(NSArray<MMFinding *> *fs, MMReview *r) {
    Print(Row(@[@[@"", @3], @[@"port", @7], @[@"what", @18], @[@"project", @36], @[@"up", @8], @[@"cpu", @7, @YES], @[@"memory", @10, @YES],
                @[@"", @2], @[@"state", @26], @[@"started by", @0]]));
    for (MMFinding *f in fs) {
        MMLHHost *h = Host(f);
        NSString *proj = h.branch ? [NSString stringWithFormat:@"%@ · %@", h.project, h.branch] : h.project;
        Print(Row(@[@[Mark(f, r), @3], @[@(h.port), @7], @[h.framework ?: @"", @18], @[proj ?: @"", @36],
                    @[MMShortDuration(-h.started.timeIntervalSinceNow), @8], @[[NSString stringWithFormat:@"%.1f%%", h.cpuPercent], @7, @YES],
                    @[MMBytes(h.memory), @10, @YES], @[@"", @2], @[MMLHStateWords(h), @26], @[h.launcher ?: @"", @0]]));
        MMVerdict *v = MMLHVerdictFor(f, r);
        if (v) Outf("       %s %s, %.0f%%: %s\n", ModelOf(r).UTF8String, v.word.UTF8String, v.confidence * 100, (v.reason ?: @"").UTF8String);
    }
}

static int List(MMLHArgs *a) {
    MMSnapshot *s = Snap(YES);
    NSArray<MMFinding *> *fs = Findings(s);
    MMReview *r = [s reviewFor:kExpert];
    MMMode mode = (MMMode)MAX(0, ModeOpt(a));
    NSArray *ignored = MMLocoHost.shared.ignored;
    if (a.json) {
        NSMutableArray *hosts = [NSMutableArray new];
        for (MMFinding *f in fs) [hosts addObject:HostJSON(f, r)];
        NSMutableArray *plan = [NSMutableArray new];
        NSDictionary *pm = MMLHPlanMap(fs, s.facts, r, mode);
        for (MMFinding *f in fs) if (pm[f.findingID]) [plan addObject:@{@"findingID": f.findingID, @"port": @(Host(f).port), @"stop": pm[f.findingID][@"stop"], @"why": pm[f.findingID][@"why"]}];
        NSMutableArray *cands = [NSMutableArray new];
        for (MMFinding *f in MMLHCandidates(fs, r)) [cands addObject:f.findingID];
        PrintJSON(@{@"hosts": hosts, @"ignored": ignored, @"idleMinutes": @((long)(MMLHIdleSeconds() / 60)), @"mode": MMModeName(mode),
                    @"plan": plan, @"candidates": cands, @"watchingSince": @(MMLHScanner.shared.watchingSince.timeIntervalSince1970)});
        return 0;
    }
    if (!fs.count) { Print(@"no localhosts running"); return 0; }
    PrintHosts(fs, r);
    uint64_t mem = 0; double cpu = 0; NSInteger active = 0, idle = 0;
    for (MMFinding *f in fs) { MMLHHost *h = Host(f); mem += h.memory; cpu += h.cpuPercent; active += h.state == MMLHActive; idle += h.state == MMLHIdle; }
    Outf("\n%s: %ld in use now, %ld quiet over %ldm · %.0f%% CPU · %s · watching for %s\n", MMPlural(fs.count, @"localhost").UTF8String,
           (long)active, (long)idle, (long)(MMLHIdleSeconds() / 60), cpu, MMBytes(mem).UTF8String,
           MMDuration(-MMLHScanner.shared.watchingSince.timeIntervalSinceNow).UTF8String);
    if (r) Outf("last review: %s by %s%s\n", MMAgo(r.at).UTF8String, ModelOf(r).UTF8String, r.error ? [@", failed: " stringByAppendingString:r.error].UTF8String : "");
    if ([a has:@"--all"] && ignored.count) {
        Print(@"\nignored, macOS and apps, never touched:");
        for (NSDictionary *i in ignored)
            Outf("  %-24s pid %-7d %s\n", [i[@"name"] UTF8String], [i[@"pid"] intValue], [[i[@"ports"] valueForKey:@"stringValue"] componentsJoinedByString:@", "].UTF8String);
    }
    return 0;
}

static int Who(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost who <port> [--json]");
    MMSnapshot *s = Snap(YES);
    MMFinding *f = FindPort(s, a.arg1);
    MMReview *r = [s reviewFor:kExpert];
    if (!f) {
        for (NSDictionary *i in MMLocoHost.shared.ignored)
            if ([i[@"ports"] containsObject:@(a.arg1.integerValue)]) { Outf(":%s is held by %s, pid %d, which LocoHost ignores\n", a.arg1.UTF8String, [i[@"name"] UTF8String], [i[@"pid"] intValue]); return 0; }
        Outf(":%s is %s\n", a.arg1.UTF8String, Listening(a.arg1.integerValue) ? "taken by a process LocoHost cannot read, of another user or root" : "free");
        return 1;
    }
    MMLHHost *h = Host(f);
    MMLHFillWhere(h, s.facts.sample, YES);
    if (a.json) { NSMutableDictionary *j = [HostJSON(f, r) mutableCopy]; j[@"where"] = h.placeLabel ?: NSNull.null; PrintJSON(j); return 0; }
    Outf(":%ld  %s  pid %d, %s\n", (long)h.port, h.framework.UTF8String, h.pid, h.kind.UTF8String);
    Outf("  ports      %s on %s\n", [[h.ports valueForKey:@"stringValue"] componentsJoinedByString:@", "].UTF8String, (h.bind ?: @"").UTF8String);
    Outf("  folder     %s\n", (h.cwd.stringByAbbreviatingWithTildeInPath ?: @"unknown").UTF8String);
    if (h.repo) Outf("  repo       %s%s%s\n", h.repo.UTF8String, h.branch ? [@" on " stringByAppendingString:h.branch].UTF8String : "",
                       h.worktree ? [@", worktree " stringByAppendingString:h.worktree].UTF8String : "");
    Outf("  command    %s\n", h.command.UTF8String);
    Outf("  started by %s\n", (h.launcher ?: @"").UTF8String);
    Outf("  up         %s · CPU %.1f%% now · %s in %s\n", MMDuration(-h.started.timeIntervalSinceNow).UTF8String, h.cpuPercent,
           MMBytes(h.memory).UTF8String, MMPlural(h.processCount, @"process").UTF8String);
    Outf("  clients    %s%s\n", h.clients.count ? [h.clients componentsJoinedByString:@", "].UTF8String : h.connections ? MMPlural(h.connections, @"connection").UTF8String : "none now",
           h.newConnections ? [NSString stringWithFormat:@", %ld new", (long)h.newConnections].UTF8String : "");
    Outf("  state      %s\n", MMLHStateWords(h).UTF8String);
    MMVerdict *v = MMLHVerdictFor(f, r);
    if (v) Outf("  review     %s %s, %.0f%%, %s: %s\n", ModelOf(r).UTF8String, v.word.UTF8String, v.confidence * 100, MMAgo(r.at).UTF8String, (v.reason ?: @"").UTF8String);
    if (h.isDev) Outf("  agent      %s\n", MMLHSessionWords(h.session).UTF8String);
    Outf("  waste      %s\n", MMLHWasteWords(h).UTF8String);
    if (h.duplicates.count) Outf("  duplicate  same folder and branch as :%s\n", [[h.duplicates valueForKey:@"stringValue"] componentsJoinedByString:@", :"].UTF8String);
    if (h.placeLabel) Outf("  where      %s\n", h.placeLabel.UTF8String);
    if (h.isProtected) Outf("  protected  Close Idle never stops it\n");
    return 0;
}

static NSString *KindWord(MMPlaceKind k) {
    switch (k) {
        case MMPlaceCmux: return @"cmux";
        case MMPlaceTmux: return @"tmux";
        case MMPlaceTerminal: return @"terminal";
        case MMPlaceITerm: return @"iterm";
        case MMPlaceApp: return @"app";
        case MMPlaceUnknown: return @"unknown";
    }
    return @"unknown";
}

static NSDictionary *PlaceJSON(MMPlace *p) {
    if (!p) return nil;
    NSMutableDictionary *j = [@{@"kind": KindWord(p.kind)} mutableCopy];
    j[@"app"] = p.app; j[@"label"] = p.label; j[@"tab"] = p.tab; j[@"window"] = p.window; j[@"workspace"] = p.workspace;
    j[@"surface"] = p.surface; j[@"target"] = p.target; j[@"tty"] = p.tty;
    if (p.appPid) j[@"pid"] = @(p.appPid);
    return j;
}

static int Where(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"where <port> [--go] [--json]");
    MMSnapshot *s = Snap(NO);
    MMFinding *f = FindPort(s, a.arg1);
    if (!f) { Err([@"no localhost on " stringByAppendingString:a.arg1]); return 1; }
    MMLHHost *h = Host(f);
    MMProcKey k = { h.pid, h.startSec };
    MMPlace *p = MMWhereIs(k, s.facts.sample, YES);
    if (a.json) { PrintJSON(PlaceJSON(p) ?: @{}); return p ? 0 : 1; }
    if (!p) { Outf(":%ld: no terminal or app found\n", (long)h.port); return 1; }
    Outf(":%ld  %s\n", (long)h.port, p.label.UTF8String);
    if ([a has:@"--go"] && !a.dry) {
        NSString *e = nil;
        if (!MMGoTo(p, &e) && e) { Err(e); return 1; }
    }
    return 0;
}

static int Explain(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"hosts <port> [--json]");
    MMSnapshot *s = Snap(YES);
    MMFinding *f = FindPort(s, a.arg1);
    if (!f) { Err([@"no localhost on " stringByAppendingString:a.arg1]); return 1; }
    MMLHHost *h = Host(f);
    MMLHFillWhere(h, s.facts.sample, YES);
    MMReview *r = [s reviewFor:kExpert];
    MMVerdict *v = MMLHVerdictFor(f, r);
    if (a.json) {
        NSMutableDictionary *j = [HostJSON(f, r) mutableCopy];
        j[@"reviewFacts"] = [MMLocoHost.shared reviewFactsFor:f];
        j[@"where"] = h.placeLabel ?: NSNull.null;
        PrintJSON(j); return 0;
    }
    Outf(":%ld  %s  %s  pid %d, %s\n\n", (long)h.port, h.framework.UTF8String, h.project.UTF8String, h.pid, h.kind.UTF8String);
    NSDictionary *p = h.projectFacts;
    NSString *what = v.about.length ? v.about : p[@"description"] ?: p[@"readme"];
    Outf("  What      %s\n", (what ?: @"no project description found").UTF8String);
    Outf("  How       %s%s, started by %s\n", h.command.UTF8String, p[@"script"] ? [NSString stringWithFormat:@", script %@", p[@"script"]].UTF8String : "",
           (h.launcher.length ? h.launcher : @"unknown").UTF8String);
    if (h.isDev) Outf("  Why       %s\n", MMLHSessionWords(h.session).UTF8String);
    Outf("  Waste     %s\n", MMLHWasteWords(h).UTF8String);
    if (v) Outf("  Verdict   %s says %s, %.0f%%, %s: %s\n", ModelOf(r).UTF8String, v.word.UTF8String, v.confidence * 100, MMAgo(r.at).UTF8String, (v.reason ?: @"").UTF8String);
    else Outf("            no review yet: run `locohost review`\n");
    Outf("\nWhat LocoHost found\n");
    if (p[@"name"] || p[@"description"]) Outf("  project   %s%s\n", [p[@"name"] ?: h.project UTF8String], p[@"description"] ? [@": " stringByAppendingString:p[@"description"]].UTF8String : "");
    if (p[@"script"]) Outf("  script    %s\n", [p[@"script"] UTF8String]);
    if (p[@"app"]) Outf("  mix app   %s\n", [p[@"app"] UTF8String]);
    if (p[@"readme"]) Outf("  readme    %s\n", [p[@"readme"] UTF8String]);
    if ([p[@"configs"] count]) Outf("  configs   %s\n", [p[@"configs"] componentsJoinedByString:@", "].UTF8String);
    if (!p.count) Outf("  project   no package.json, README, mix.exs or pyproject.toml in its folders\n");
    Outf("  command   %s\n  started   %s, %s ago\n", h.command.UTF8String, (h.launcher ?: @"").UTF8String, MMDuration(-h.started.timeIntervalSinceNow).UTF8String);
    if (h.branch) Outf("  git       branch %s%s\n", h.branch.UTF8String, h.worktree ? [@", worktree " stringByAppendingString:h.worktree].UTF8String : "");
    Outf("  session   %s\n", MMLHSessionWords(h.session).UTF8String);
    if (h.placeLabel) Outf("  where     %s\n", h.placeLabel.UTF8String);
    if (h.duplicates.count) Outf("  duplicate same folder and branch as :%s\n", [[h.duplicates valueForKey:@"stringValue"] componentsJoinedByString:@", :"].UTF8String);
    Outf("  clients   %s\n  state     %s\n", h.clients.count ? [h.clients componentsJoinedByString:@", "].UTF8String : "none now", MMLHStateWords(h).UTF8String);
    return 0;
}

static int Hosts(MMLHArgs *a) { return a.arg1 ? Explain(a) : List(a); }

static int Waste(MMLHArgs *a) {
    MMSnapshot *s = Snap(YES);
    MMReview *r = [s reviewFor:kExpert];
    NSMutableArray<MMFinding *> *dev = [NSMutableArray new];
    for (MMFinding *f in Findings(s)) if (Host(f).isDev) [dev addObject:f];
    [dev sortUsingComparator:^NSComparisonResult(MMFinding *x, MMFinding *y) {
        MMLHHost *a1 = Host(x), *b1 = Host(y);
        double wa = a1.state == MMLHIdle ? -[(a1.lastActive ?: a1.firstSeen) timeIntervalSinceNow] * a1.memory : 0;
        double wb = b1.state == MMLHIdle ? -[(b1.lastActive ?: b1.firstSeen) timeIntervalSinceNow] * b1.memory : 0;
        return wa > wb ? NSOrderedAscending : wa < wb ? NSOrderedDescending : [@(a1.port) compare:@(b1.port)];
    }];
    double cpu = 0; uint64_t mem = 0; NSInteger idle = 0;
    for (MMFinding *f in dev) { MMLHHost *h = Host(f); if (h.state == MMLHIdle) { idle++; cpu += h.idleCPUSeconds; mem += h.memory; } }
    if (a.json) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMFinding *f in dev) {
            MMLHHost *h = Host(f);
            [o addObject:@{@"findingID": f.findingID, @"port": @(h.port), @"project": h.project, @"state": MMLHStateName(h.state),
                           @"waste": [MMLocoHost.shared reviewFactsFor:f][@"waste"] ?: @{}, @"duplicates": h.duplicates ?: @[]}];
        }
        PrintJSON(@{@"hosts": o, @"idle": @{@"count": @(idle), @"cpuSeconds": @(round(cpu)), @"memoryBytes": @(mem)}});
        return 0;
    }
    if (!dev.count) { Print(@"no dev servers running"); return 0; }
    Print(Row(@[@[@"", @3], @[@"port", @7], @[@"what", @16], @[@"project", @36], @[@"unused", @10], @[@"cpu", @9, @YES], @[@"memory", @10, @YES]]));
    for (MMFinding *f in dev) {
        MMLHHost *h = Host(f);
        Print(Row(@[@[Mark(f, r), @3], @[@(h.port), @7], @[h.framework ?: @"", @16], @[h.project ?: @"", @36],
                    @[h.state == MMLHActive ? @"now" : MMShortDuration(-(h.lastActive ?: h.firstSeen).timeIntervalSinceNow), @10],
                    @[MMDuration(h.idleCPUSeconds), @9, @YES], @[MMBytes(h.memory), @10, @YES],
                    @[@"", @1], @[h.duplicates.count ? [NSString stringWithFormat:@"duplicate of :%@", [[h.duplicates valueForKey:@"stringValue"] componentsJoinedByString:@", :"]] : @"", @0]]));
    }
    Outf("\n%s quiet over %ldm hold %s and burned %s CPU since they were last used\n", MMPlural(idle, @"server").UTF8String,
           (long)(MMLHIdleSeconds() / 60), MMBytes(mem).UTF8String, MMDuration(cpu).UTF8String);
    return 0;
}

/// Runs one review of the scoped findings through the broker and saves it. Returns it, or nil with exit status 2
/// for a bad mode.
static MMReview *RunReview(MMSnapshot *s, MMLHArgs *a, NSArray<MMFinding *> *scope) {
    NSInteger mode = ModeOpt(a);
    MMReviewRequest *q = MMLHReviewRequest(scope, s.facts, @"manual", (MMMode)MAX(0, mode), [a opt:@"--model"]);
    if (!q) {
        MMReview *r = [MMReview new];
        r.expert = kExpert; r.at = NSDate.date; r.verdicts = @{}; r.calls = @[]; r.actions = @[]; r.summary = @"Nothing to review.";
        return r;
    }
    if (!a.json) Err([NSString stringWithFormat:@"reviewing %@ with %@…", MMPlural(scope.count, @"localhost"), q.model]);
    __block MMReview *r = nil;
    OffMain(^{ r = [MMReviewBroker.shared run:q]; });   // the model calls block, so they stay off main
    [MMGraph.shared saveReview:r forExpert:kExpert];
    return r;
}

static int Review(MMLHArgs *a) {
    if (ModeOpt(a) < 0) return Usage(@"review [--mode idle|proactive|eager] [--model name] [--port p] [--json]");
    MMSnapshot *s = Snap(YES);
    NSArray<MMFinding *> *scope = Scoped(Findings(s), a);
    if (a.dry) {
        MMReviewRequest *q = MMLHReviewRequest(scope, s.facts, @"manual", (MMMode)ModeOpt(a), [a opt:@"--model"]);
        NSMutableArray *sent = [NSMutableArray new];
        for (MMFinding *f in scope) [sent addObject:@{@"id": f.findingID, @"facts": q.factsFor(f)}];
        if (a.json) PrintJSON(@{@"model": q.model ?: @"", @"judge": @(q.judge), @"findings": sent});
        else Outf("would review %s with %s%s\n", MMPlural(scope.count, @"localhost").UTF8String, (q.model ?: @"auto").UTF8String, q.judge ? ", then the judge" : "");
        return 0;
    }
    MMReview *r = RunReview(s, a, scope);
    if (r.error.length) { Err([@"review failed: " stringByAppendingString:r.error]); if (a.json) PrintJSON(@{@"error": r.error, @"note": r.note ?: NSNull.null}); return 1; }
    if (r.note.length && !a.json) Err([NSString stringWithFormat:@"%@, so %@ answered", r.note, ModelOf(r)]);
    if (r.judgeError.length && !a.json) Err([@"the Eager judge failed: " stringByAppendingString:r.judgeError]);
    // The review's own findings carry the fingerprints it judged, so Close Idle reads them as they were.
    NSArray *cands = MMLHCandidates(scope, r);
    if (a.json) {
        NSMutableArray *hosts = [NSMutableArray new];
        for (MMFinding *f in scope) [hosts addObject:HostJSON(f, r)];
        NSMutableArray *usage = [NSMutableArray new];
        for (MMUsage *u in r.calls) [usage addObject:u.json];
        PrintJSON(@{@"hosts": hosts, @"model": ModelOf(r), @"note": r.note ?: NSNull.null, @"summary": r.summary ?: @"",
                    @"judgeError": r.judgeError ?: NSNull.null, @"calls": usage, @"candidates": [cands valueForKey:@"findingID"]});
        return 0;
    }
    for (MMFinding *f in scope) {
        MMLHHost *h = Host(f);
        MMVerdict *v = MMLHVerdictFor(f, r);
        Print(Row(@[@[Mark(f, r), @3], @[[NSString stringWithFormat:@":%ld", (long)h.port], @7], @[v.word ?: @"-", @9],
                    @[[NSString stringWithFormat:@"%.0f%%", v.confidence * 100], @6, @YES], @[(v.about.length ? v.about : h.framework) ?: @"", @0]]));
        Outf("         %s\n", (v.reason ?: @"no verdict").UTF8String);
    }
    NSInteger uncached = 0;
    for (MMUsage *u in r.calls) uncached += u.uncached;
    Outf("\n%s · %s · %ld confirmed idle now\n", ModelOf(r).length ? ModelOf(r).UTF8String : "no model call", MMPlural(uncached, @"uncached token").UTF8String, (long)cands.count);
    if (r.summary.length) Outf("\n%s\n", r.summary.UTF8String);
    return 0;
}

static int Auto(MMLHArgs *a, BOOL summaryOnly) {
    NSInteger modeN = ModeOpt(a);
    if (modeN < 0) return Usage(@"locohost auto [--mode idle|proactive|eager] [--port p] [--dry-run] [--review] [--force] [--json]");
    MMMode mode = (MMMode)modeN;
    BOOL dry = summaryOnly || a.dry;
    MMSnapshot *s = Snap(YES);
    NSArray<MMFinding *> *scope = Scoped(Findings(s), a);
    MMReview *r = [s reviewFor:kExpert];
    if ([a has:@"--review"] && !summaryOnly) {
        r = RunReview(s, a, scope);
        if (r.error.length) { Err([@"review failed: " stringByAppendingString:r.error]); return 1; }
    }
    NSMutableArray<MMFinding *> *dev = [NSMutableArray new];
    for (MMFinding *f in scope) if (Host(f).isDev) [dev addObject:f];
    NSArray<MMPlanEntry *> *plan = MMPlan(dev, s.facts, r, mode, MMLHModePolicy());
    NSMutableArray *actions = [NSMutableArray new];
    if (!dry) for (MMPlanEntry *e in plan) {
        if (!e.act) continue;
        NSString *err = nil;
        MMUndoRecord *rec = Run(MMLHStopAction(e.finding, a.force ? MMStopKill : MMStopTerm), MMLHModePolicy(), r, MMModeName(mode), e.why, &err);
        [actions addObject:@{@"findingID": e.finding.findingID, @"port": @(Host(e.finding).port), @"project": Host(e.finding).project,
                             @"stopped": @(rec.state == MMUndoDone), @"rid": rec.rid ?: NSNull.null, @"why": e.why ?: @"", @"error": err ?: NSNull.null}];
    }
    if (a.json) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMPlanEntry *e in plan)
            [o addObject:@{@"findingID": e.finding.findingID, @"port": @(Host(e.finding).port), @"project": Host(e.finding).project,
                           @"stop": @(e.act), @"why": e.why ?: @""}];
        PrintJSON(@{@"mode": MMModeName(mode), @"summary": r.summary ?: NSNull.null, @"plan": o, @"actions": actions,
                    @"reviewAt": r ? @(r.at.timeIntervalSince1970) : NSNull.null, @"trigger": r.trigger ?: NSNull.null});
        return 0;
    }
    if (summaryOnly) {
        if (r.summary.length) Outf("%s\n\n", r.summary.UTF8String); else Print(@"no summary yet: run `locohost review`\n");
        if (r) Outf("review %s by %s%s\n", MMAgo(r.at).UTF8String, ModelOf(r).UTF8String, r.trigger ? [@", woken by " stringByAppendingString:r.trigger].UTF8String : "");
    }
    Outf("%s mode%s:\n", MMLHModeLabel(MMModeName(mode)).UTF8String, dry && !summaryOnly ? ", dry run" : "");
    for (MMPlanEntry *e in plan) {
        MMLHHost *h = Host(e.finding);
        Print(Row(@[@[@"", @2], @[e.act ? @"stop" : @"keep", @6], @[[NSString stringWithFormat:@":%ld", (long)h.port], @7], @[h.framework ?: @"", @17],
                    @[h.project ?: @"", @33], @[e.why ?: @"", @0]]));
    }
    if (!plan.count) Print(@"  no dev servers running");
    for (NSDictionary *x in actions)
        Outf("%s :%s %s\n", [x[@"stopped"] boolValue] ? "stopped" : "still running", [x[@"port"] description].UTF8String, [x[@"project"] UTF8String]);
    return 0;
}

static int Mode(MMLHArgs *a) {
    if (a.arg1) {
        NSInteger m = MMModeFrom(a.arg1);
        if (m < 0) return Usage(@"locohost mode [idle|proactive|eager]");
        if (!a.dry) MMSetMode(kExpert, (MMMode)m);
    }
    if (a.json) PrintJSON(@{@"mode": MMModeName(MMModeFor(kExpert))}); else Print(MMModeName(MMModeFor(kExpert)));
    return 0;
}

/// Stops each finding: SIGTERM, or SIGKILL with --force as the second request. Exit 0 all stopped, 3 some still run.
static int Stop(NSArray<MMFinding *> *targets, MMLHArgs *a, NSString *why) {
    NSInteger left = 0;
    NSMutableArray *out = [NSMutableArray new];
    for (MMFinding *f in targets) {
        MMLHHost *h = Host(f);
        if (a.dry) { [out addObject:@{@"port": @(h.port), @"dryRun": [MMLHStopAction(f, a.force ? MMStopKill : MMStopTerm) dryRun]}]; continue; }
        NSString *err = nil;
        MMUndoRecord *rec = Run(MMLHStopAction(f, a.force ? MMStopKill : MMStopTerm), MMLHManualPolicy(), nil, @"cli", why, &err);
        BOOL ok = rec.state == MMUndoDone;
        if (!ok) left++;
        [out addObject:@{@"port": @(h.port), @"stopped": @(ok), @"rid": rec.rid ?: NSNull.null, @"error": ok ? NSNull.null : err ?: @"it did not start"}];
        if (!a.json) {
            if (ok) Outf("stopped :%ld %s\n", (long)h.port, h.framework.UTF8String);
            else Outf("still running: :%ld %s, pid %d. %s\n", (long)h.port, h.framework.UTF8String, h.pid, MMSentence(err ?: @"it did not stop").UTF8String);
        }
    }
    if (a.json) PrintJSON(@{@"results": out});
    else if (a.dry) for (NSDictionary *x in out) Print(x[@"dryRun"]);
    else Outf("stopped %lu of %lu\n", (unsigned long)(targets.count - left), (unsigned long)targets.count);
    return left ? 3 : 0;
}

static int Idle(MMLHArgs *a, BOOL close) {
    MMSnapshot *s = Snap(YES);
    MMReview *r = [s reviewFor:kExpert];
    if (close && [a has:@"--review"]) {
        r = RunReview(s, a, Scoped(Findings(s), a));
        if (r.error.length) { Err([@"review failed: " stringByAppendingString:r.error]); return 1; }
    }
    NSArray<MMFinding *> *c = Scoped(MMLHCandidates(Findings(s), r), a);
    if (!close && a.json) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMFinding *f in c) [o addObject:HostJSON(f, r)];
        PrintJSON(@{@"candidates": o, @"reviewAt": r ? @(r.at.timeIntervalSince1970) : NSNull.null});
        return 0;
    }
    if (!r && !a.json) Print(@"no review yet: run `locohost review` or wait for the scheduled one");
    uint64_t mem = 0;
    for (MMFinding *f in c) {
        MMLHHost *h = Host(f);
        mem += h.memory;
        if (!a.json) Print(Row(@[@[@"", @2], @[[NSString stringWithFormat:@":%ld", (long)h.port], @8], @[h.framework ?: @"", @17], @[h.project ?: @"", @33],
                                 @[[@"up " stringByAppendingString:MMShortDuration(-h.started.timeIntervalSinceNow)], @12], @[MMBytes(h.memory), @10, @YES],
                                 @[@"", @1], @[MMLHVerdictFor(f, r).reason ?: @"", @0]]));
    }
    if (!c.count) { if (a.json) PrintJSON(@{@"results": @[]}); else Print(@"nothing confirmed idle"); return 0; }
    if (!close) { Outf("%s confirmed idle · %s\n", MMPlural(c.count, @"server").UTF8String, MMBytes(mem).UTF8String); return 0; }
    if (!a.yes && !a.dry && !Confirm([NSString stringWithFormat:@"Stop %@, %@?%@", MMPlural(c.count, @"server"), MMBytes(mem),
                                      a.force ? @" Servers that ignored SIGTERM before get SIGKILL." : @""])) { Print(@"aborted"); return 1; }
    return Stop(c, a, @"Close Idle");
}

static int Close(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost close <port|pid> [--yes] [--force]");
    MMSnapshot *s = Snap(NO);
    MMFinding *f = FindPort(s, a.arg1);
    if (!f) { Err([@"no localhost on " stringByAppendingString:a.arg1]); return 1; }
    MMLHHost *h = Host(f);
    if (!a.yes && !a.dry && !Confirm([NSString stringWithFormat:@"Stop :%ld %@ in %@, pid %d?", (long)h.port, h.framework, h.project, h.pid])) { Print(@"aborted"); return 1; }
    return Stop(@[f], a, @"stopped from the CLI");
}

static int Open(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost open <port>");
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%ld", (long)a.arg1.integerValue]];
    if (a.dry) { Print([@"would open " stringByAppendingString:u.absoluteString]); return 0; }
    return [NSWorkspace.sharedWorkspace openURL:u] ? 0 : 1;
}

/// Every stop LocoHost recorded, newest first, with the command that starts it again.
static NSArray<MMUndoRecord *> *Stops(void) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMUndoRecord *r in [MMUndo.shared recent:kExpert limit:50])
        if ([r.kind isEqualToString:@"stop"] && r.state != MMUndoPending && [r.payload[@"restart"] isKindOfClass:NSDictionary.class]) [out addObject:r];
    return out;
}

static NSString *StateWord(MMUndoState s) {
    return s == MMUndoDone ? @"done" : s == MMUndoFailed ? @"failed" : s == MMUndoRestored ? @"restored" : @"pending";
}

static NSDictionary *StopJSON(MMUndoRecord *r) {
    NSDictionary *rs = r.payload[@"restart"];
    NSString *cmd = rs[@"command"] ?: @"";
    NSString *cwd = rs[@"cwd"];
    return @{@"rid": r.rid ?: @"", @"at": @(r.at.timeIntervalSince1970), @"port": rs[@"port"] ?: @0, @"framework": rs[@"framework"] ?: @"",
             @"project": rs[@"project"] ?: @"", @"restart": cwd.length ? [NSString stringWithFormat:@"cd %@ && %@", MMLHQuote(cwd), cmd] : cmd,
             @"by": r.by ?: @"manual", @"why": r.why ?: @"", @"state": StateWord(r.state), @"canRestore": @(r.canRestore && r.state == MMUndoDone)};
}

static int Stopped(MMLHArgs *a) {
    NSArray<MMUndoRecord *> *all = Stops();
    if (a.json) { NSMutableArray *o = [NSMutableArray new]; for (MMUndoRecord *r in all) [o addObject:StopJSON(r)]; PrintJSON(o); return 0; }
    for (MMUndoRecord *r in all) {
        NSDictionary *j = StopJSON(r);
        Outf(":%-6s %-16s %s by %s%s\n        %s\n", [j[@"port"] description].UTF8String, [j[@"framework"] UTF8String], MMAgo(r.at).UTF8String,
               [j[@"by"] UTF8String], r.why.length ? [@": " stringByAppendingString:r.why].UTF8String : "", [j[@"restart"] UTF8String]);
    }
    if (!all.count) Print(@"LocoHost has stopped nothing yet");
    return 0;
}

/// Starts the newest stopped server on this port again, through Core's undo record.
static int RestartPort(NSInteger port, MMLHArgs *a) {
    for (MMUndoRecord *r in Stops()) {
        if ([r.payload[@"restart"][@"port"] integerValue] != port || r.state != MMUndoDone) continue;
        if (Listening(port)) { Err([NSString stringWithFormat:@":%ld is already taken", (long)port]); return 1; }
        if (a.dry) { Print([@"would run " stringByAppendingString:StopJSON(r)[@"restart"]]); return 0; }
        __block NSString *problem = nil;
        OffMain(^{ problem = [MMUndo.shared restore:r.rid]; });
        if (problem) { Err([@"could not restart: " stringByAppendingString:problem]); return 1; }
        if (a.json) PrintJSON(@{@"rid": r.rid, @"port": @(port), @"restart": StopJSON(r)[@"restart"]});
        else Outf("restarting :%ld: %s\n", (long)port, [StopJSON(r)[@"restart"] UTF8String]);
        return 0;
    }
    Err([NSString stringWithFormat:@"LocoHost has not stopped anything on :%ld", (long)port]);
    return 1;
}

static int Restart(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost restart <port>");
    return RestartPort(a.arg1.integerValue, a);
}

/// LocoHost's part of restore: with no argument, the stops that can be undone; with a port or a record id, undo it.
static int Restore(MMLHArgs *a) {
    if (!a.arg1) {
        NSMutableArray *o = [NSMutableArray new];
        for (MMUndoRecord *r in Stops()) if (r.state == MMUndoDone) [o addObject:StopJSON(r)];
        if (a.json) PrintJSON(o);
        else { for (NSDictionary *j in o) Outf("%s  :%s %s, %s\n", [j[@"rid"] UTF8String], [j[@"port"] description].UTF8String, [j[@"framework"] UTF8String], MMAgo([NSDate dateWithTimeIntervalSince1970:[j[@"at"] doubleValue]]).UTF8String);
               if (!o.count) Print(@"nothing to restore"); }
        return 0;
    }
    if (a.arg1.integerValue > 0 && a.arg1.integerValue < 65536 && [a.arg1 rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound)
        return RestartPort(a.arg1.integerValue, a);
    MMUndoRecord *r = [MMUndo.shared record:a.arg1];
    if (!r || ![r.expert isEqualToString:kExpert]) { Err([@"no LocoHost record " stringByAppendingString:a.arg1]); return 1; }
    NSInteger port = [r.payload[@"restart"][@"port"] integerValue];
    if (port && Listening(port)) { Err([NSString stringWithFormat:@":%ld is already taken", (long)port]); return 1; }
    if (a.dry) { Print([@"would run " stringByAppendingString:StopJSON(r)[@"restart"]]); return 0; }
    __block NSString *problem = nil;
    OffMain(^{ problem = [MMUndo.shared restore:r.rid]; });
    if (problem) { Err([@"could not restore: " stringByAppendingString:problem]); return 1; }
    if (a.json) PrintJSON(@{@"rid": r.rid, @"restored": @YES}); else Outf("restored %s\n", r.rid.UTF8String);
    return 0;
}

static int Keep(MMLHArgs *a) {
    if (!a.arg1) return Usage(@"locohost keep <port> [hours]");
    MMSnapshot *s = Snap(NO);
    MMFinding *f = FindPort(s, a.arg1);
    if (!f) { Err([@"no localhost on " stringByAppendingString:a.arg1]); return 1; }
    MMLHHost *h = Host(f);
    double hours = a.arg2 ? a.arg2.doubleValue : [a opt:@"--hours"] ? [a opt:@"--hours"].doubleValue : 4;
    if (!a.dry) [MMKeep keep:f.stableKey expert:kExpert until:hours > 0 ? [NSDate dateWithTimeIntervalSinceNow:hours * 3600] : nil];
    if (a.json) { PrintJSON(@{@"findingID": f.findingID, @"hours": @(hours)}); return 0; }
    if (hours > 0) Outf("no mode stops :%ld %s for %s\n", (long)h.port, h.framework.UTF8String, MMDuration(hours * 3600).UTF8String);
    else Outf(":%ld %s is up to the mode again\n", (long)h.port, h.framework.UTF8String);
    return 0;
}

static int Rules(MMLHArgs *a) {
    (void)MMLHRules();
    NSString *path = [MMExpertDir(kExpert) stringByAppendingPathComponent:@"rules.json"];
    if (a.json) PrintJSON(@{@"path": path}); else Print(path);
    return 0;
}

#pragma mark - Registry

NSArray<MMVerbSpec *> *MMLHVerbs(void) {
    static NSArray *verbs; static dispatch_once_t once;
    dispatch_once(&once, ^{
        typedef int (^Body)(MMLHArgs *a);
        NSMutableArray *v = [NSMutableArray new];
        void (^add)(NSString *, NSString *, BOOL, Body) = ^(NSString *verb, NSString *usage, BOOL mutates, Body body) {
            [v addObject:[MMVerbSpec verb:verb usage:usage mutates:mutates run:^int(MMArgs *args) { @autoreleasepool {
                // Outside a running app LocoHost reads project files and asks Where now, as a CLI waits for its answer.
                MMLHInCLI = !args.inApp || !MMGraph.shared.latest;
                NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
                id before = td[kArgsKey];
                td[kArgsKey] = args;
                int status = body(Parse(args));
                if (before) td[kArgsKey] = before; else [td removeObjectForKey:kArgsKey];
                return status;
            } }]];
        };
        // 2.0 verbs.
        add(@"hosts", @"hosts [port] [--json]: every localhost, or what one port is, how it runs and why", NO, ^int(MMLHArgs *a) { return Hosts(a); });
        add(@"where", @"where <port> [--go] [--json]: the cmux tab, tmux pane, terminal tab or app a server runs in", NO, ^int(MMLHArgs *a) { return Where(a); });
        add(@"review", @"review [--mode name] [--model name] [--port p] [--json]: ask the model which localhosts are in use", NO, ^int(MMLHArgs *a) { return Review(a); });
        add(@"restore", @"restore [record id|port] [--json]: list the servers LocoHost stopped, or start one again", YES, ^int(MMLHArgs *a) { return Restore(a); });
        // 1.x verbs, for the locohost name.
        add(@"list", @"locohost list [--all] [--json]: every localhost, its cost, state and who started it", NO, ^int(MMLHArgs *a) { return List(a); });
        add(@"who", @"locohost who <port> [--json]: the process on a port, its folder, branch, command and clients", NO, ^int(MMLHArgs *a) { return Who(a); });
        add(@"explain", @"locohost explain <port> [--json]: what it is, how it runs, why it is there and what it wastes", NO, ^int(MMLHArgs *a) { return Explain(a); });
        add(@"ready", @"locohost ready <port> [--http] [--timeout s]: wait until the port answers; exit 0 ready, 1 timed out", NO, ^int(MMLHArgs *a) { return Ready(a); });
        add(@"free", @"locohost free [port]: the first free port at or above port, 3000 by default", NO, ^int(MMLHArgs *a) { return Free(a); });
        add(@"waste", @"locohost waste [--json]: what each dev server burned since it was last used", NO, ^int(MMLHArgs *a) { return Waste(a); });
        add(@"summary", @"locohost summary [--mode name] [--json]: the review's words and what the mode would do", NO, ^int(MMLHArgs *a) { return Auto(a, YES); });
        add(@"auto", @"locohost auto [--mode name] [--port p] [--dry-run] [--review] [--force] [--json]: one round of the mode", YES, ^int(MMLHArgs *a) { return Auto(a, NO); });
        add(@"mode", @"locohost mode [idle|proactive|eager]: show or set the mode", YES, ^int(MMLHArgs *a) { return Mode(a); });
        add(@"idle", @"locohost idle [--port p] [--json]: what Close Idle would stop right now", NO, ^int(MMLHArgs *a) { return Idle(a, NO); });
        add(@"close-idle", @"locohost close-idle [--yes] [--force] [--port p] [--review]: stop every confirmed idle server", YES, ^int(MMLHArgs *a) { return Idle(a, YES); });
        add(@"close", @"locohost close <port|pid> [--yes] [--force]: stop one server, SIGTERM, then SIGKILL on a second request", YES, ^int(MMLHArgs *a) { return Close(a); });
        add(@"open", @"locohost open <port>: open it in the browser", NO, ^int(MMLHArgs *a) { return Open(a); });
        add(@"stopped", @"locohost stopped [--json]: what LocoHost stopped, with the command to start each again", NO, ^int(MMLHArgs *a) { return Stopped(a); });
        add(@"restart", @"locohost restart <port>: start the server LocoHost last stopped on that port again", YES, ^int(MMLHArgs *a) { return Restart(a); });
        add(@"keep", @"locohost keep <port> [hours]: no mode stops it for this many hours, 4 by default, 0 clears", YES, ^int(MMLHArgs *a) { return Keep(a); });
        add(@"rules", @"locohost rules: print the rules file path", NO, ^int(MMLHArgs *a) { return Rules(a); });
        verbs = [v copy];
    });
    return verbs;
}
