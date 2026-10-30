// Wrap Up, issue #27: MinMacs's parts are the helpers a finished workstream left behind, and its localhost tabs.
// A helper is a process of the person's whose parent exited, so launchd adopted it, whose folder is inside the
// worktree, that listens on no port and is no shell and no agent. A headless browser or a file watcher left by a test
// run is one. Read from the shared sample in the snapshot. A server is LocoHost's part, and a process with a live
// parent, such as one in a terminal, is no leftover, so it keeps the worktree.
// A localhost tab is a tab on localhost, 127.0.0.1 or ::1 at a port one of the plan's server parts stops. Tabs are read
// through the tab bridge only: at once where the caller may wait, else in the background on
// no.guerrilla.minmacs.minmacs.tabs, and there only when the bridge says no prompt would show.
#import "Experts/MinMacs/MMMinMacs.h"
#import "UI/MMFormat.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static NSString *const kExpert = @"minmacs";
static const NSTimeInterval kGrace = 5;

static BOOL Within(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

static NSString *Quoted(NSArray<NSString *> *argv) {
    NSMutableArray *parts = [NSMutableArray new];
    for (NSString *a in argv) {
        BOOL plain = a.length && [a rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\n\"'\\$`*?&|;<>()#~{}[]!"]].location == NSNotFound;
        [parts addObject:plain ? a : [NSString stringWithFormat:@"'%@'", [a stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSValue *Box(MMProcKey k) { return [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]; }

/// YES for a shell, a terminal multiplexer or git: what a person works in, never a leftover.
static BOOL NeverAHelper(NSString *name) {
    static NSSet *names; static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"zsh", @"-zsh", @"bash", @"-bash", @"sh", @"fish", @"login", @"tmux", @"screen", @"git", @"ssh"]]; });
    return !name.length || [names containsObject:name];
}

/// Why pid is not a helper of folder in this sample, or nil when it is.
static NSString *NotAHelper(MMSample *s, MMProc *p, NSString *folder, NSSet<NSNumber *> *agentPids) {
    if (p.pid <= 1 || p.pid == getpid() || p.uid != getuid()) return @"not one of yours";
    if (p.ppid != 1) return @"its parent still runs";
    if (NeverAHelper(p.name)) return @"a shell or a tool you work in";
    if ([agentPids containsObject:@(p.pid)]) return @"an agent";
    if (!Within([s cwdOf:p.pid], folder)) return @"it runs outside the worktree";
    for (NSValue *v in [s socketsOf:p.pid]) { MMSocket k; [v getValue:&k size:sizeof k]; if (k.state == MMSocketListen) return @"a server"; }
    return nil;
}

static NSSet<NSNumber *> *AgentPids(MMFacts *facts) {
    NSMutableSet *out = [NSMutableSet new];
    for (MMAgent *a in facts.agents) { [out addObject:@(a.key.pid)]; for (MMAgent *h in a.hosted) [out addObject:@(h.key.pid)]; }
    return out;
}

#pragma mark - The policy

/// On fresh facts: the same process still runs, still in the worktree, and is still a leftover.
@interface MMMMHelperKeeps : NSObject <MMExpertPolicy>
@end
@implementation MMMMHelperKeeps
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    NSNumber *pid = f.facts[@"pid"], *start = f.facts[@"start"];
    MMProc *p = [facts.sample proc:pid.intValue];
    if (!p || p.startSec != start.unsignedLongLongValue) return @"cannot verify: it exited or its pid was reused";
    NSString *why = NotAHelper(facts.sample, p, f.facts[@"worktree"], AgentPids(facts));
    return why ? [@"no longer a leftover: " stringByAppendingString:why] : nil;
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

static id<MMExpertPolicy> HelperPolicy(void) {
    static MMMMHelperKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMMMHelperKeeps new]; });
    return p;
}

#pragma mark - The action

/// Stops one helper and what it started through Core's MMStop, its first request only, after MMStop checks pid and start time.
/// The record keeps its command line and folder, so restore starts it again.
@interface MMMMHelperStop : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end
@implementation MMMMHelperStop
- (NSString *)kind { return @"stop"; }
- (MMProcKey)root { MMProcKey k = { [self.finding.facts[@"pid"] intValue], [self.finding.facts[@"start"] unsignedLongLongValue] }; return k; }
- (NSString *)recheck { return MMProcAlive(self.root) ? nil : @"it has already exited"; }
- (NSString *)command { NSArray *a = self.finding.facts[@"args"]; return a.count ? Quoted(a) : nil; }
- (NSString *)dryRun {
    NSString *cmd = self.command;
    return [NSString stringWithFormat:@"would stop %@, pid %@, and wait %.0f seconds for it to end.%@", self.finding.facts[@"name"], self.finding.facts[@"pid"], kGrace,
            cmd ? [@" Restore starts it again with: " stringByAppendingString:cmd] : @" It has no command line to start it again."];
}
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    NSString *cmd = self.command;
    // PATH in the record makes restore run the command through /bin/sh, not a login shell.
    if (cmd) [MMUndo.shared note:record payload:@{@"restart": @{@"command": cmd, @"cwd": self.finding.facts[@"cwd"] ?: @"",
                                                                  @"env": @{@"PATH": @"/usr/bin:/bin:/usr/sbin:/sbin"}}}];
    // MMStop checks each pid and start time, signals each, then waits for all.
    (void)MMStop(self.finding.procs, MMStopTerm, kGrace);
    if (!MMProcAlive(self.root)) return YES;
    if (error) *error = @"it did not stop on the first request, so the worktree stays. Quit it yourself and try again";
    return NO;
}
@end


#pragma mark - Localhost tabs

static const NSTimeInterval kTabsFresh = 60;       // a background read is used this long
static const NSTimeInterval kPortWait = 15;        // restore waits this long for the servers to listen again

/// One read of one browser instance's tabs.
@interface MMMMTabRead : NSObject
@property (strong) NSDate *at;
@property (copy) NSArray<MMMinMacsTab *> *tabs;
@property (copy) NSString *error;
@end
@implementation MMMMTabRead
@end

static NSMutableDictionary<NSString *, MMMMTabRead *> *TabReads(void) {
    static NSMutableDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
    return d;
}
static NSMutableSet<NSString *> *TabReadsQueued(void) {
    static NSMutableSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}

static MMProcKey KeyOf(NSString *s) {
    NSArray *p = [s componentsSeparatedByString:@":"];
    MMProcKey k = { 0, 0 };
    if (p.count == 2) { k.pid = [p[0] intValue]; k.startSec = (uint64_t)[p[1] longLongValue]; }
    return k;
}

/// NO on main and on the graph queue, which must never wait on an Apple event.
static BOOL MayWaitHere(void) {
    if (NSThread.isMainThread) return NO;
    const char *label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    return !(label && !strcmp(label, "no.guerrilla.minmacs.core.graph"));
}

static MMMMTabRead *ReadTabs(pid_t pid, NSString *bid) {
    NSString *err = nil;
    NSArray *tabs = [MMMinMacsTabBridgeNow() tabsOf:pid bundleID:bid error:&err];
    MMMMTabRead *r = [MMMMTabRead new];
    r.at = NSDate.date; r.tabs = tabs ?: @[]; r.error = tabs ? nil : (err ?: @"its tabs cannot be read");
    return r;
}

static NSSet<NSString *> *URLsOf(MMMMTabRead *r) {
    NSMutableSet *out = [NSMutableSet new];
    for (MMMinMacsTab *t in r.tabs) if (t.url) [out addObject:t.url];
    return out;
}

static void KeepRead(NSString *key, MMMMTabRead *r) {
    @synchronized (TabReads()) {
        if (TabReads().count > 64) [TabReads() removeAllObjects];
        if (r) TabReads()[key] = r;
    }
}

/// The tabs of one browser instance. wait YES reads now. wait NO returns the last read, and queues a read when that
/// is missing or older than a minute and the bridge says it can read with no prompt. A read that changed what is
/// open asks the graph for a rebuild, so the plan shows it.
static MMMMTabRead *TabsOf(MMProcKey k, NSString *bid, BOOL wait) {
    NSString *key = [NSString stringWithFormat:@"%@|%@", bid, MMProcKeyString(k)];
    if (wait) { MMMMTabRead *r = ReadTabs(k.pid, bid); KeepRead(key, r); return r; }
    MMMMTabRead *have;
    @synchronized (TabReads()) { have = TabReads()[key]; }
    if (have && -have.at.timeIntervalSinceNow < kTabsFresh) return have;
    @synchronized (TabReadsQueued()) {
        if ([TabReadsQueued() containsObject:key]) return have;
        [TabReadsQueued() addObject:key];
    }
    dispatch_async(MMQueue(@"minmacs", @"tabs", QOS_CLASS_UTILITY), ^{
        id<MMMinMacsTabBridge> b = MMMinMacsTabBridgeNow();
        BOOL may = [b respondsToSelector:@selector(mayReadWithoutAsking:bundleID:)] && [b mayReadWithoutAsking:k.pid bundleID:bid];
        MMMMTabRead *r;
        if (may) r = ReadTabs(k.pid, bid);
        else { r = [MMMMTabRead new]; r.at = NSDate.date; r.tabs = @[]; r.error = @"MinMacs may not read its tabs without asking"; }
        KeepRead(key, r);
        @synchronized (TabReadsQueued()) { [TabReadsQueued() removeObject:key]; }
        if (may && ![URLsOf(r) isEqualToSet:URLsOf(have)]) [MMGraph.shared rebuild:@"minmacs localhost tabs"];
    });
    return have;
}

/// The tabs on localhost, 127.0.0.1 or ::1 at one of ports, outside private windows.
static NSArray<MMMinMacsTab *> *LocalTabs(NSArray<MMMinMacsTab *> *tabs, NSSet<NSNumber *> *ports) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMMinMacsTab *t in tabs) {
        if (t.privateWindow || !t.url.length) continue;
        if (!MMMinMacsIsLocalHost([NSURL URLWithString:t.url].host)) continue;
        if ([ports containsObject:@(MMMinMacsPortOf(t.url))]) [out addObject:t];
    }
    return out;
}

/// Why the rules or an agent keep this browser's tabs, or nil. verdict is the rules' word for it.
static NSString *BrowserKept(NSString *name, NSString *verdict, NSString *agent) {
    if ([verdict isEqualToString:@"keep"]) return [name stringByAppendingString:@" is on your keep list, so its tabs stay"];
    if (![verdict isEqualToString:@"close"]) return [name stringByAppendingString:@" is on no list in your rules, so MinMacs never touches it"];
    if (agent.length) return [NSString stringWithFormat:@"%@ started %@ and is working", agent, name];
    return nil;
}

static NSString *TabsTitle(NSUInteger n, NSString *name) {
    return [NSString stringWithFormat:@"Close %lu localhost tab%@ in %@", (unsigned long)n, n == 1 ? @"" : @"s", name];
}

static NSString *PortWords(NSArray<NSNumber *> *ports) {
    NSMutableArray *w = [NSMutableArray new];
    for (NSNumber *p in ports) [w addObject:[@":" stringByAppendingString:p.stringValue]];
    if (w.count <= 1) return w.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@", [[w subarrayWithRange:NSMakeRange(0, w.count - 1)] componentsJoinedByString:@", "], w.lastObject];
}

#pragma mark - The tabs policy

@interface MMMinMacsExpert (MMWrapUpLookup)
- (MMFinding *)finding:(NSString *)findingID in:(MMFacts *)facts;
@end

/// On fresh facts: the browser is still on the close list and no working agent started it. A browser that quit
/// has nothing to close, so it does not keep the worktree.
@interface MMMMTabsKeeps : NSObject <MMExpertPolicy>
@end
@implementation MMMMTabsKeeps
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    NSString *bid = f.facts[@"bundleID"], *name = f.facts[@"name"] ?: bid;
    if (!bid.length) return @"cannot verify: the part names no browser";
    NSString *agent = nil;
    MMFinding *now = [MMMinMacsExpert.shared finding:[@"minmacs:app:" stringByAppendingString:bid] in:facts];
    if (now && [now.instanceKey isEqualToString:f.instanceKey]) agent = now.facts[@"agent"];
    return BrowserKept(name, MMMinMacsVerdictName([MMMinMacsRules.shared verdictFor:bid]), agent);
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

static id<MMExpertPolicy> TabsPolicy(void) {
    static MMMMTabsKeeps *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [MMMMTabsKeeps new]; });
    return p;
}

#pragma mark - The tabs action

/// Closes the localhost tabs the plan read, in one browser instance, through the tab bridge. A tab whose URL changed
/// since is kept, both since the plan's read and since the read right before closing. The browser keeps running.
/// The record keeps the tabs that closed and how to open them again.
@interface MMMMTabsClose : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end
@implementation MMMMTabsClose
- (NSString *)kind { return @"tabs"; }
- (MMProcKey)key { return KeyOf(self.finding.instanceKey); }
/// Nothing here holds the worktree back: a browser that quit or tabs that closed leave nothing to do.
- (NSString *)recheck { return nil; }
- (NSString *)dryRun {
    NSArray *urls = self.finding.facts[@"urls"];
    return [NSString stringWithFormat:@"would close %@ in %@ on %@, and keep %@ running. Restore opens them again there.",
            MMPlural((NSInteger)urls.count, @"localhost tab"), self.finding.facts[@"name"], PortWords(self.finding.facts[@"ports"]), self.finding.facts[@"name"]];
}
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMFinding *f = self.finding;
    NSString *bid = f.facts[@"bundleID"];
    MMProcKey k = self.key;
    NSArray<NSString *> *planned = f.facts[@"urls"] ?: @[];
    if (!MMProcAlive(k)) { [MMUndo.shared note:record payload:@{@"tabs": @[], @"note": @"the browser quit, so no tab was closed"}]; return YES; }
    NSString *err = nil;
    NSArray<MMMinMacsTab *> *tabs = [MMMinMacsTabBridgeNow() tabsOf:k.pid bundleID:bid error:&err];
    // What cannot be read is kept: the tabs stay open, and the rest of the Wrap Up goes on.
    if (!tabs) { [MMUndo.shared note:record payload:@{@"tabs": @[], @"note": [@"no tab was closed: " stringByAppendingString:err ?: @"its tabs cannot be read"]}]; return YES; }
    NSCountedSet *left = [[NSCountedSet alloc] initWithArray:planned];
    NSMutableArray<MMMinMacsTab *> *targets = [NSMutableArray new];
    for (MMMinMacsTab *t in LocalTabs(tabs, [NSSet setWithArray:f.facts[@"ports"] ?: @[]])) {
        if (![left countForObject:t.url]) continue;   // opened or moved there since the plan read the tabs
        [left removeObject:t.url];
        [targets addObject:t];
    }
    NSArray<MMMinMacsTab *> *closed = targets.count ? [MMMinMacsTabBridgeNow() close:targets pid:k.pid bundleID:bid] : @[];
    NSMutableArray *rows = [NSMutableArray new], *urls = [NSMutableArray new];
    for (MMMinMacsTab *t in closed) {
        [rows addObject:@{@"url": t.url ?: @"", @"host": t.host ?: @"", @"title": t.title ?: @""}];
        if (t.url) [urls addObject:t.url];
    }
    NSMutableDictionary *more = [@{@"tabs": rows, @"kept": @(planned.count - closed.count), @"browser": bid ?: @"", @"pid": f.instanceKey ?: @""} mutableCopy];
    if (urls.count) {
        more[@"reopen"] = @{@"bundleID": bid ?: @"", @"appPath": f.facts[@"bundlePath"] ?: @"", @"urls": urls, @"ports": f.facts[@"ports"] ?: @[]};
        more[@"restoreLast"] = @YES;
    }
    [MMUndo.shared note:record payload:more];
    return YES;
}
@end

#pragma mark - Restore

/// YES once something listens on 127.0.0.1 or ::1 at port.
static BOOL Listening(uint16_t port) {
    for (int family = 0; family < 2; family++) {
        int fd = socket(family ? AF_INET6 : AF_INET, SOCK_STREAM, 0);
        if (fd < 0) continue;
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        struct sockaddr_storage ss; memset(&ss, 0, sizeof ss);
        socklen_t len;
        if (family) {
            struct sockaddr_in6 *a = (struct sockaddr_in6 *)&ss;
            a->sin6_family = AF_INET6; a->sin6_port = htons(port); a->sin6_addr = in6addr_loopback; len = sizeof *a;
        } else {
            struct sockaddr_in *a = (struct sockaddr_in *)&ss;
            a->sin_family = AF_INET; a->sin_port = htons(port); a->sin_addr.s_addr = htonl(INADDR_LOOPBACK); len = sizeof *a;
        }
        BOOL ok = connect(fd, (struct sockaddr *)&ss, len) == 0;
        if (!ok && errno == EINPROGRESS) {
            struct pollfd p = { fd, POLLOUT, 0 };
            int err = 0; socklen_t el = sizeof err;
            ok = poll(&p, 1, 200) == 1 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el) == 0 && err == 0;
        }
        close(fd);
        if (ok) return YES;
    }
    return NO;
}

void MMMinMacsRegisterTabRestore(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MMUndoRestoreKey(@"reopen", ^NSString *(id value) {
            NSDictionary *r = [value isKindOfClass:NSDictionary.class] ? value : nil;
            NSMutableArray<NSString *> *urls = [NSMutableArray new];
            for (id u in [r[@"urls"] isKindOfClass:NSArray.class] ? r[@"urls"] : @[]) if ([u isKindOfClass:NSString.class]) [urls addObject:u];
            if (!urls.count) return nil;
            NSString *bid = [r[@"bundleID"] isKindOfClass:NSString.class] ? r[@"bundleID"] : nil;
            NSString *path = [r[@"appPath"] isKindOfClass:NSString.class] && [r[@"appPath"] length] ? r[@"appPath"] : nil;
            if (!bid.length && !path) return @"the record does not say which browser the tabs came from";
            // The server parts came back first. Each gets up to 15 seconds in all to listen again.
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kPortWait];
            for (id p in [r[@"ports"] isKindOfClass:NSArray.class] ? r[@"ports"] : @[]) {
                if (![p isKindOfClass:NSNumber.class]) continue;
                while (!Listening((uint16_t)[p unsignedIntValue]) && until.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.2];
            }
            return [MMMinMacsTabBridgeNow() open:urls bundleID:bid appPath:path];
        });
    });
}

#pragma mark - The parts

@implementation MMMinMacsExpert (MMWrapUp)

- (NSArray<MMWrapUpPart *> *)wrapUpParts:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    MMSample *sample = s.facts.sample;
    if (!sample) return @[];
    NSSet *agents = AgentPids(s.facts);
    NSMutableArray *parts = [NSMutableArray new];
    NSArray *pids = [sample.procs.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *n in pids) {
        MMProc *p = sample.procs[n];
        if (NotAHelper(sample, p, subject.path, agents) && NotAHelper(sample, p, subject.worktree.path, agents)) continue;
        NSMutableArray *keys = [NSMutableArray new];
        for (NSNumber *t in [sample treeOf:p.pid limit:200]) { MMProc *q = [sample proc:t.intValue]; if (q && q.uid == getuid()) [keys addObject:Box(q.key)]; }
        NSString *cwd = [sample cwdOf:p.pid];
        NSDictionary *facts = @{@"pid": @(p.pid), @"start": @(p.startSec), @"name": p.name ?: @"?", @"cwd": cwd ?: @"",
                                @"args": [sample argsOf:p.pid] ?: @[], @"worktree": subject.path ?: @""};
        MMFinding *f = [MMFinding expert:kExpert kind:@"helper" stableKey:[NSString stringWithFormat:@"%@#%@", subject.path, p.name ?: @"?"]
                                   build:^(MMFindingBuilder *b) {
            b.instanceKey = MMProcKeyString(p.key);
            b.title = p.name ?: @"helper";
            b.path = cwd;
            b.cost = (MMCost){ .ramBytes = [sample treeFootprint:p.pid], .cpuPercent = [sample treeCPU:p.pid] };
            b.procs = keys;
            b.facts = facts;
            b.proposal = [MMProposal verb:@"stop" title:@"Stop Helper" reversibility:MMReversibleRestart];
        }];
        MMMMHelperStop *a = [MMMMHelperStop new];
        a.finding = f;
        MMWrapUpPart *part = [MMWrapUpPart step:MMWrapUpHelpers expert:kExpert title:[NSString stringWithFormat:@"Stop %@, left behind", p.name ?: @"helper"]
                                         action:a policy:HelperPolicy()];
        if (part) [parts addObject:part];
    }
    return parts;
}


- (NSArray<MMWrapUpPart *> *)wrapUpPartsAfter:(NSArray<MMWrapUpPart *> *)earlier subject:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    NSArray<NSNumber *> *ports = subject.serverPorts;
    if (!ports.count) return @[];
    NSSet *portSet = [NSSet setWithArray:ports];
    BOOL wait = MayWaitHere();
    NSMutableArray *parts = [NSMutableArray new];
    for (MMFinding *app in [s findingsFor:kExpert]) {
        if (![app.kind isEqualToString:@"app"] || ![app.facts[@"browser"] boolValue]) continue;
        NSString *bid = app.facts[@"bundleID"], *name = app.facts[@"name"] ?: app.title ?: bid;
        if (!MMMinMacsCanTrim(bid) || BrowserKept(name, app.facts[@"verdict"], app.facts[@"agent"])) continue;
        MMProcKey k = KeyOf(app.instanceKey);
        if (k.pid <= 0) continue;
        NSArray<MMMinMacsTab *> *local = LocalTabs(TabsOf(k, bid, wait).tabs, portSet);
        if (!local.count) continue;
        NSMutableArray *urls = [NSMutableArray new];
        NSMutableOrderedSet *on = [NSMutableOrderedSet new];
        for (MMMinMacsTab *t in local) { [urls addObject:t.url]; [on addObject:@(MMMinMacsPortOf(t.url))]; }
        NSMutableDictionary *facts = [@{@"bundleID": bid, @"name": name, @"pid": @(k.pid), @"start": @(k.startSec),
                                        @"urls": urls, @"ports": on.array, @"worktree": subject.path ?: @""} mutableCopy];
        if ([app.facts[@"bundlePath"] length]) facts[@"bundlePath"] = app.facts[@"bundlePath"];
        MMFinding *f = [MMFinding expert:kExpert kind:@"tabs" stableKey:[NSString stringWithFormat:@"%@#%@", subject.path, bid]
                                   build:^(MMFindingBuilder *b) {
            b.instanceKey = app.instanceKey;
            b.title = name;
            b.facts = facts;
            b.proposal = [MMProposal verb:@"close-tabs" title:@"Close Tabs" reversibility:MMReversibleNotNeeded];
        }];
        MMMMTabsClose *a = [MMMMTabsClose new];
        a.finding = f;
        MMWrapUpPart *part = [MMWrapUpPart step:MMWrapUpTabs expert:kExpert title:TabsTitle(urls.count, name) action:a policy:TabsPolicy()];
        if (part) [parts addObject:part];
    }
    return parts;
}

@end
