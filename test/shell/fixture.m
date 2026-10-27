// The shell's fixture binary: the real CLI and shell from Sources, with two fixture experts in place of
// MinMacs and LocoHost, and facts built by hand. Built by test/shell.sh from every .m under Sources except main.m.
// Nothing is sampled or scanned: the experts read the fixture facts only, as AGENTS.md invariant 2 asks.
// Every path lives under $MINMACS_HOME/fx. The only process it touches is itself.
// Hidden verbs, for test/shell.sh only:
//   _serve      serves core.sock the way the app does, with no status items, until it is stopped
//   _review     saves a review that lets the idle fixture server go
//   _selftest   prints the router, legacy name and login item checks as name, want and got, split by tabs
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "CLI/MMRouter.h"
#import "Shell/MMShell.h"

static NSString *Home(void) { return [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"fx"]; }

#pragma mark - Fakes for Senses and Know, as in test/graph/graph.m

@interface FProc : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property uint64_t startSec;
@property (copy) NSString *name, *cwd;
@property double cpuPercent, energyRank; @property uint64_t footprint;
@end
@implementation FProc
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface FSample : NSObject
@property NSDate *at; @property uint64_t generation;
@property NSDictionary<NSNumber *, FProc *> *procs;
@end
@implementation FSample
- (FProc *)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return self.procs[@(pid)].cwd; }
- (NSArray *)childrenOf:(pid_t)pid {
    NSMutableArray *k = [NSMutableArray new];
    for (FProc *p in self.procs.allValues) if (p.ppid == pid) [k addObject:@(p.pid)];
    return k;
}
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *a = [NSMutableArray new];
    for (FProc *p = self.procs[@(self.procs[@(pid)].ppid)]; p && a.count < hops; p = p.pid == 1 ? nil : self.procs[@(p.ppid)]) [a addObject:@(p.pid)];
    return a;
}
@end

@interface FAgent : NSObject
@property (copy) NSString *harnessID, *sessionID, *cwd, *why;
@property MMProcKey key; @property MMAgentState state;
@end
@implementation FAgent @end

@interface FSession : NSObject
@property (copy) NSString *agent, *sessionID, *title, *cwd, *branch, *transcript, *liveStatus;
@property NSDate *started, *lastActive; @property pid_t pid; @property BOOL stillWorking;
@end
@implementation FSession @end

@interface FTree : NSObject
@property (copy) NSString *path, *repo, *branch; @property BOOL isMain, locked, missing;
@end
@implementation FTree @end

static FProc *P(pid_t pid, pid_t ppid, NSString *name, NSString *cwd) {
    FProc *p = [FProc new]; p.pid = pid; p.ppid = ppid; p.startSec = 1000 + pid; p.name = name; p.cwd = cwd;
    p.cpuPercent = 1; p.footprint = (uint64_t)pid << 20;
    return p;
}

/// The fixture Mac: one agent at work in the app checkout with its server on 3000, an idle server on 3001
/// in an old folder, and a Notes app.
@interface FSource : NSObject <MMFactSource>
@end
@implementation FSource
- (MMFacts *)factsFor:(uint64_t)generation {
    NSString *h = Home();
    NSString *app = [h stringByAppendingPathComponent:@"app"], *old = [h stringByAppendingPathComponent:@"old"];
    NSArray *ps = @[P(1, 0, @"launchd", @"/"), P(50, 1, @"Terminal", @"/"), P(100, 50, @"claude", app),
                    P(110, 100, @"node", [app stringByAppendingPathComponent:@"web"]), P(130, 50, @"node", old),
                    P(500, 1, @"Notes", @"/")];
    NSMutableDictionary *procs = [NSMutableDictionary new];
    for (FProc *p in ps) procs[@(p.pid)] = p;
    FSample *s = [FSample new]; s.at = NSDate.date; s.generation = generation; s.procs = procs;
    FAgent *a = [FAgent new]; a.harnessID = @"claude-code"; a.sessionID = @"s1"; a.cwd = app; a.key = ((FProc *)procs[@100]).key;
    a.state = MMAgentWorking; a.why = @"status file busy";
    FSession *ss = [FSession new]; ss.agent = @"claude-code"; ss.sessionID = @"s1"; ss.title = @"Checkout flow"; ss.cwd = app;
    ss.pid = 100; ss.started = [NSDate dateWithTimeIntervalSinceNow:-3600]; ss.lastActive = NSDate.date; ss.liveStatus = @"busy"; ss.stillWorking = YES;
    FTree *t = [FTree new]; t.path = app; t.repo = app; t.branch = @"main"; t.isMain = YES;
    return [MMFacts generation:generation sample:(MMSample *)s power:nil agents:[NSArray arrayWithObject:a] sessions:[NSArray arrayWithObject:ss]
                     worktrees:[NSArray arrayWithObject:t] clutter:@[] git:@{}];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self factsFor:0]; }
@end

#pragma mark - The fixture experts

static NSInteger PortOf(FProc *p) { return p.pid == 110 ? 3000 : 3001; }

@interface FPolicy : NSObject <MMExpertPolicy>
@end
@implementation FPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts { return [f.facts[@"inUse"] boolValue] ? @"an agent works here" : nil; }
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

/// Stops a fixture server by writing a file. Its undo record restarts it by writing another.
@interface FStop : NSObject <MMAction>
@property MMFinding *finding;
@end
@implementation FStop
- (NSString *)kind { return @"stop"; }
- (NSString *)recheck { return nil; }
- (NSString *)dryRun { return [NSString stringWithFormat:@"would stop :%@", self.finding.facts[@"port"]]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    NSString *port = [self.finding.facts[@"port"] description];
    NSString *marker = [Home() stringByAppendingPathComponent:[@"stopped-" stringByAppendingString:port]];
    [MMUndo.shared note:record payload:@{@"restart": @{@"command": [NSString stringWithFormat:@"echo restarted > '%@/restarted-%@'", Home(), port],
                                                       @"env": @{@"PATH": @"/usr/bin:/bin"}, @"cwd": Home()}}];
    return [@"stopped\n" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
@end

static int SelfTest(MMArgs *a);

@interface FExpert : NSObject <MMExpert>
@property (copy) NSString *expertID, *name, *symbol;
@end

@implementation FExpert
- (MMVerdictWords *)words {
    return [self.expertID isEqual:@"locohost"] ? [MMVerdictWords keep:@"in_use" go:@"idle" unsure:@"unsure"]
                                               : [MMVerdictWords keep:@"keep" go:@"quit" unsure:@"unsure"];
}
- (NSString *)legacyName { return [self.expertID isEqual:@"locohost"] ? @"locohost" : nil; }

- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSMutableArray *out = [NSMutableArray new];
    FSample *s = (FSample *)facts.sample;
    for (NSNumber *n in [s.procs.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        FProc *p = s.procs[n];
        BOOL server = [p.name isEqual:@"node"], app = [p.name isEqual:@"Notes"];
        if (!([self.expertID isEqual:@"locohost"] ? server : app)) continue;
        NSString *kind = server ? @"server" : @"app";
        NSString *stable = server ? [p.cwd stringByAppendingString:@"#dev"] : @"com.apple.Notes";
        [out addObject:[MMFinding expert:self.expertID kind:kind stableKey:stable build:^(MMFindingBuilder *b) {
            b.instanceKey = [NSString stringWithFormat:@"%d:%llu", p.pid, p.startSec];
            b.title = server ? [NSString stringWithFormat:@"Vite :%ld", (long)PortOf(p)] : @"Notes";
            b.path = server ? p.cwd : nil;
            b.fingerprint = stable;
            b.cost = (MMCost){ .ramBytes = p.footprint, .cpuPercent = p.cpuPercent };
            MMProcKey k = p.key;
            b.procs = @[[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
            if (server) {
                b.facts = @{@"port": @(PortOf(p)), @"inUse": @(p.pid == 110)};
                b.proposal = [MMProposal verb:@"stop" title:@"Stop" reversibility:MMReversibleRestart];
            } else b.facts = @{@"bundleID": @"com.apple.Notes"};
        }]];
    }
    return out;
}
- (id<MMExpertPolicy>)policy { return [FPolicy new]; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step {
    if (!f.proposal) return nil;
    FStop *a = [FStop new]; a.finding = f; return a;
}
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return f.facts; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }

- (MMMenuSpec *)menuFor:(MMSnapshot *)s {
    NSArray *fs = [s findingsFor:self.expertID];
    MMMenuSpec *m = [MMMenuSpec new];
    m.headerBig = [NSString stringWithFormat:@"%lu", (unsigned long)fs.count];
    m.headerUnit = [self.expertID isEqual:@"locohost"] ? @"servers" : @"apps";
    m.headerLine = [self.expertID isEqual:@"locohost"] ? @"1 in use · 1 quiet" : @"Notes is open";
    MMSectionSpec *sec = [MMSectionSpec new];
    sec.title = @"Running";
    NSMutableArray *rows = [NSMutableArray new];
    for (MMFinding *f in fs) {
        MMRowSpec *r = [MMRowSpec new]; r.name = f.title; r.facts = @[f.expert, @"quiet"]; r.mark = MMRowMarkQuiet; r.findingID = f.findingID;
        [rows addObject:r];
    }
    sec.rows = rows;
    m.sections = @[sec];
    return m;
}
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s {
    MMCardSpec *c = [MMCardSpec new];
    c.title = f.title; c.statusWord = @"Stays."; c.statusText = @"A fixture."; c.mark = MMRowMarkQuiet;
    c.facts = @[[MMCardFact label:@"Kind" value:f.kind]];
    return c;
}
- (NSString *)badgeFor:(MMSnapshot *)s { return [self.expertID isEqual:@"locohost"] ? @"1" : nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return [self.expertID isEqual:@"locohost"] ? @"1 idle server" : @"1 app"; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return [s findingsFor:self.expertID].count == 0; }

static NSDictionary *Row(MMFinding *f) {
    return @{@"id": f.findingID, @"title": f.title, @"facts": f.facts ?: @{}};
}

- (NSArray<MMVerbSpec *> *)verbs {
    if ([self.expertID isEqual:@"minmacs"]) return @[
        [MMVerbSpec verb:@"apps" usage:@"apps [--json]   the apps open now" mutates:NO run:^int(MMArgs *a) {
            NSMutableArray *rows = [NSMutableArray new];
            for (MMFinding *f in [a.snapshot findingsFor:@"minmacs"]) [rows addObject:Row(f)];
            if (a.json) [a printJSON:@{@"apps": rows, @"inApp": @(a.inApp)}]; else for (NSDictionary *r in rows) [a print:@"%@", r[@"title"]];
            return 0;
        }],
    ];
    return @[
        [MMVerbSpec verb:@"hosts" usage:@"hosts [port] [--json]   every localhost, or one port" mutates:NO run:^int(MMArgs *a) {
            NSString *port = [a word:0];
            NSMutableArray *rows = [NSMutableArray new];
            for (MMFinding *f in [a.snapshot findingsFor:@"locohost"])
                if (!port || [[f.facts[@"port"] description] isEqualToString:port]) [rows addObject:Row(f)];
            if (port && !rows.count) { [a error:@"nothing listens on :%@", port]; return MMExitFailed; }
            if (a.json) [a printJSON:@{@"hosts": rows, @"inApp": @(a.inApp), @"program": a.program}];
            else for (NSDictionary *r in rows) [a print:@"%@", r[@"title"]];
            return 0;
        }],
        [MMVerbSpec verb:@"close" usage:@"close <port>   stop one server" mutates:YES run:^int(MMArgs *a) {
            [a print:@"closed %@", [a word:0]];
            return 0;
        }],
        [MMVerbSpec verb:@"_serve" usage:@"_serve" mutates:NO run:^int(MMArgs *a) {
            NSString *err = nil;
            MMCoreSocket *s = [MMCoreSocket serve:^NSDictionary *(NSDictionary *req) { return MMCLIReply(req); } error:&err];
            if (!s) { [a error:@"%@", err]; return MMExitFailed; }
            [a print:@"serving %@", MMCoreSocketPath()];
            fflush(stdout);
            dispatch_main();
        }],
        [MMVerbSpec verb:@"_review" usage:@"_review" mutates:NO run:^int(MMArgs *a) {
            MMSnapshot *s = a.snapshot;
            NSMutableDictionary *v = [NSMutableDictionary new];
            for (MMFinding *f in [s findingsFor:@"locohost"]) {
                MMVerdict *x = [MMVerdict new];
                BOOL idle = ![f.facts[@"inUse"] boolValue];
                x.kind = idle ? MMVerdictGo : MMVerdictKeep; x.word = idle ? @"idle" : @"in_use"; x.confidence = 0.95;
                x.findingID = f.findingID; x.fingerprint = f.fingerprint; x.reason = idle ? @"quiet for 3 hours" : @"an agent uses it";
                x.decidedBy = @"model";
                v[f.findingID] = x;
            }
            MMReview *r = [MMReview new];
            r.expert = @"locohost"; r.trigger = @"manual"; r.at = NSDate.date; r.mode = MMModeProactive; r.verdicts = v;
            r.summary = @"One server is quiet.";
            [r save];
            [a print:@"saved"];
            return 0;
        }],
        [MMVerbSpec verb:@"_selftest" usage:@"_selftest" mutates:NO run:^int(MMArgs *a) { return SelfTest(a); }],
    ];
}

static void C(MMArgs *a, NSString *name, id want, id got) { [a print:@"%@\t%@\t%@", name, want ?: @"nil", got ?: @"nil"]; }

static NSString *RouteWords(NSString *url) {
    MMRoute *r = MMRouteURL([NSURL URLWithString:url], nil);
    NSArray *kinds = @[@"none", @"quit", @"login-on", @"login-off", @"settings", @"expert"];
    NSString *k = kinds[r.kind];
    if (r.kind == MMRouteExpert) k = [NSString stringWithFormat:@"%@ %@ %@", k, r.expert, r.url.absoluteString];
    if (r.words) k = [k stringByAppendingFormat:@" [%@]", [r.words componentsJoinedByString:@" "]];
    return k;
}

static int SelfTest(MMArgs *a) {
    C(a, @"router: locohost://quit quits", @"quit", RouteWords(@"locohost://quit"));
    C(a, @"router: minmacs://quit quits", @"quit", RouteWords(@"minmacs://quit"));
    C(a, @"router: locohost://login-on is the router's", @"login-on", RouteWords(@"locohost://login-on"));
    C(a, @"router: minmacs://login-off is the router's", @"login-off", RouteWords(@"minmacs://login-off"));
    C(a, @"router: minmacs:// opens Settings", @"settings", RouteWords(@"minmacs://"));
    C(a, @"router: locohost://review goes to LocoHost", @"expert locohost locohost://review [review locohost --now]", RouteWords(@"locohost://review"));
    C(a, @"router: minmacs://locohost/review is the same", @"expert locohost locohost://review [review locohost --now]", RouteWords(@"minmacs://locohost/review"));
    C(a, @"router: minmacs://locohost/quit still quits", @"quit", RouteWords(@"minmacs://locohost/quit"));
    C(a, @"router: minmacs://restore is MinMacs 1.x restore", @"expert minmacs minmacs://restore [restore --expert minmacs]", RouteWords(@"minmacs://restore"));
    C(a, @"router: minmacs://run-now runs tidy", @"expert minmacs minmacs://run-now [tidy minmacs]", RouteWords(@"minmacs://run-now"));
    C(a, @"router: minmacs://run asks first, so no CLI fallback", @"expert minmacs minmacs://run", RouteWords(@"minmacs://run"));
    C(a, @"router: another scheme is not ours", @"none", RouteWords(@"https://quit"));
    C(a, @"router: Info.plist schemes", @"minmacs,locohost", [MMURLSchemes() componentsJoinedByString:@","]);

    C(a, @"program: a locohost symlink is locohost", @"locohost", MMProgramName("/x/bin/locohost"));
    C(a, @"program: the bundle binary is minmacs", @"minmacs", MMProgramName("/x/MinMacs.app/Contents/MacOS/MinMacs"));
    C(a, @"program: an unknown name is minmacs", @"minmacs", MMProgramName("/x/bin/mmshell-copy"));
    C(a, @"legacy: locohost list is hosts", @"hosts --json", [MMLegacyWords(@"locohost", @[@"list", @"--json"]) componentsJoinedByString:@" "]);
    C(a, @"legacy: locohost where 3000 is where --port 3000", @"where --port 3000 --json",
      [MMLegacyWords(@"locohost", @[@"where", @"3000", @"--json"]) componentsJoinedByString:@" "]);
    C(a, @"legacy: minmacs plan is tidy minmacs --dry-run", @"tidy minmacs --dry-run --json",
      [MMLegacyWords(@"minmacs", @[@"plan", @"--json"]) componentsJoinedByString:@" "]);
    C(a, @"legacy: no alias for a 2.0 verb", @"nil", MMLegacyWords(@"minmacs", @[@"status"]) ? @"alias" : @"nil");

    C(a, @"login item: never under MINMACS_HOME", @"NO", MMMayRegisterLoginItem(@{@"MINMACS_HOME": @"/tmp/x"}, @"/Applications/MinMacs.app") ? @"YES" : @"NO");
    C(a, @"login item: never outside an .app bundle", @"NO", MMMayRegisterLoginItem(@{}, @"/x/bin") ? @"YES" : @"NO");
    C(a, @"login item: the real app registers", @"YES", MMMayRegisterLoginItem(@{}, @"/Applications/MinMacs.app") ? @"YES" : @"NO");
    C(a, @"login item: this test process may not", @"NO",
      MMMayRegisterLoginItem(NSProcessInfo.processInfo.environment, NSBundle.mainBundle.bundlePath) ? @"YES" : @"NO");
    C(a, @"icon: an empty field starts hidden", @"0", [MMIconVisibleFor(YES, NO, YES) description]);
    C(a, @"icon: it shows once the field appears", @"1", [MMIconVisibleFor(NO, NO, NO) description]);
    C(a, @"icon: after that the person decides", @"nil", MMIconVisibleFor(YES, YES, NO) ? @"set" : @"nil");
    C(a, @"icon: an empty field later leaves the icon alone", @"nil", MMIconVisibleFor(YES, NO, NO) ? @"set" : @"nil");
    C(a, @"one icon: a hidden expert has no section", @"NO", MMOneIconShows(@"locohost", NO, NO) ? @"YES" : @"NO");
    C(a, @"one icon: an empty field has no section", @"NO", MMOneIconShows(@"locohost", YES, YES) ? @"YES" : @"NO");
    C(a, @"one icon: a visible expert has a section", @"YES", MMOneIconShows(@"locohost", NO, YES) ? @"YES" : @"NO");
    C(a, @"one icon: MinMacs keeps its section", @"YES", MMOneIconShows(@"minmacs", NO, NO) ? @"YES" : @"NO");
    C(a, @"experts: built-in classes in menu bar order", @"MMMinMacsExpert MMLocoHostExpert MMWorkForestExpert MMNooNooExpert MMInsomniaExpert",
      [MMBuiltInExpertClasses() componentsJoinedByString:@" "]);
    C(a, @"experts: registered once, in order", @"minmacs locohost", [[MMExperts() valueForKey:@"expertID"] componentsJoinedByString:@" "]);
    MMRegisterExpert(MMExperts().lastObject);
    C(a, @"experts: a second registration is ignored", @"2", [@(MMExperts().count) description]);
    C(a, @"experts: MMExpertNamed finds one", @"LocoHost", MMExpertNamed(@"locohost").name);
    C(a, @"socket: the path is in the support folder", @"core.sock", MMCoreSocketPath().lastPathComponent);
    return 0;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSFileManager.defaultManager createDirectoryAtPath:Home() withIntermediateDirectories:YES attributes:nil error:nil];
        FSource *src = [FSource new];
        MMSetCLIFactSource(src);
        MMGraph.shared.source = src;
        NSArray *experts = @[@[@"minmacs", @"MinMacs", @"gauge.with.dots.needle.33percent"], @[@"locohost", @"LocoHost", @"server.rack"]];
        for (NSArray *e in experts) {
            FExpert *x = [FExpert new]; x.expertID = e[0]; x.name = e[1]; x.symbol = e[2];
            MMRegisterExpert(x);
        }
        return MMMain(argc, argv);
    }
}
