// MMWhereIs and MMGoTo. Ported from LocoHost's Where.m.
// The parent chain and the terminal device come from sysctl, which also reads processes owned by root,
// such as Terminal's login, where proc_pidinfo cannot. tmux is asked before cmux, because a tmux pane is more
// exact than the cmux tab that started tmux. Then Terminal and iTerm2 by tty, then the responsible app.
// AppKit is used for NSRunningApplication and NSWorkspace only, as Sources/Core/README.md allows. Nothing is drawn.
#import "Core/Know/MMWhere.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import "Core/Know/MMGit.h"
#import <AppKit/AppKit.h>
#import <libproc.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/sysctl.h>


static const NSTimeInterval kSnapshotAge = 15;  // cmux and tmux are asked at most this often
static const NSTimeInterval kCLILimit = 3;      // and each call gets at most this long

@interface MMPlace ()
@property (readwrite) MMPlaceKind kind;
@property (readwrite, copy) NSString *app, *label, *tab, *window, *workspace, *surface, *target, *tty;
@property (readwrite) pid_t appPid;
@property (strong) MMPlace *outer;              // the cmux tab whose client runs a tmux session, opened first
@end
@implementation MMPlace
@end

#pragma mark Processes

static NSDictionary<NSString *, NSString *> *Env(void) { return NSProcessInfo.processInfo.environment; }

/// Runs a CLI through MMRun. Returns its output, or nil when it failed or took too long.
static NSString *Run(NSString *path, NSArray<NSString *> *args) {
    if (!path) return nil;
    NSMutableDictionary *env = [NSMutableDictionary new];
    for (NSString *k in @[@"TMUX_TMPDIR", @"CMUX_SOCKET_PATH"]) if (Env()[k]) env[k] = Env()[k];
    NSData *out = nil;
    MMRunResult r = MMRun(path, args, nil, env, nil, kCLILimit, &out, NULL);
    return r.didRun && !r.timedOut && r.status == 0 ? [[NSString alloc] initWithData:out ?: NSData.data encoding:NSUTF8StringEncoding] : nil;
}

static BOOL KInfo(pid_t p, struct kinfo_proc *k) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, p};
    size_t len = sizeof *k;
    return p > 0 && sysctl(mib, 4, k, &len, NULL, 0) == 0 && len == sizeof *k && k->kp_proc.p_pid == p;
}
static pid_t ParentOf(pid_t p) { struct kinfo_proc k; return KInfo(p, &k) ? k.kp_eproc.e_ppid : 0; }
static NSString *TTYOf(pid_t p) {
    struct kinfo_proc k;
    if (!KInfo(p, &k) || k.kp_eproc.e_tdev == NODEV || k.kp_eproc.e_tdev == 0) return nil;
    char *n = devname(k.kp_eproc.e_tdev, S_IFCHR);
    return n && strcmp(n, "??") ? @(n) : nil;
}
static NSString *ExecPath(pid_t p) {
    char buf[PROC_PIDPATHINFO_MAXSIZE];
    return proc_pidpath(p, buf, sizeof buf) > 0 ? @(buf) : nil;
}
/// P9. The app macOS holds responsible for a process. It is set when the process starts and survives its parent.
static pid_t Responsible(pid_t p) {
    static pid_t (*f)(pid_t); static dispatch_once_t once;
    dispatch_once(&once, ^{ f = dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid"); });
    return f ? f(p) : 0;
}

/// The process and every parent up to launchd.
static NSArray<NSNumber *> *Chain(pid_t pid) {
    NSMutableOrderedSet *c = [NSMutableOrderedSet new];
    for (pid_t p = pid; p > 1 && c.count < 64; p = ParentOf(p)) [c addObject:@(p)];
    return c.array;
}

/// The running app a process belongs to: the first parent that is a regular app, else the responsible app.
static NSRunningApplication *AppOf(NSArray<NSNumber *> *chain, pid_t pid) {
    NSMutableArray *pids = [chain mutableCopy];
    pid_t r = Responsible(pid);
    if (r > 1) [pids addObject:@(r)];
    for (NSNumber *p in pids) {
        NSRunningApplication *a = [NSRunningApplication runningApplicationWithProcessIdentifier:p.intValue];
        if (a.bundleIdentifier && a.activationPolicy == NSApplicationActivationPolicyRegular && a.processIdentifier != getpid()) return a;
        NSString *exec = ExecPath(p.intValue);
        NSRange app = [exec rangeOfString:@".app/Contents/"];
        if (app.location == NSNotFound) continue;
        NSString *bundle = [exec substringToIndex:app.location + 4];
        for (NSRunningApplication *ra in NSWorkspace.sharedWorkspace.runningApplications)
            if ([ra.bundleURL.path isEqualToString:bundle] && ra.activationPolicy == NSApplicationActivationPolicyRegular) return ra;
    }
    return nil;
}

/// cmux puts a status glyph in front of agent tabs. "◐ repo check" reads "repo check".
static NSString *Clean(NSString *title) {
    NSCharacterSet *keep = NSCharacterSet.alphanumericCharacterSet;
    NSUInteger i = 0;
    while (i < title.length && ![keep characterIsMember:[title characterAtIndex:i]] && [title characterAtIndex:i] != '~' && [title characterAtIndex:i] != '/') i++;
    return [[title substringFromIndex:i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}
static NSString *LastWord(NSString *s) { return [s componentsSeparatedByString:@" "].lastObject; }

#pragma mark cmux

/// The cmux CLI. MINMACS_CMUX names another one, which tests use for a fake.
static NSString *CmuxPath(void) {
    if (Env()[@"MINMACS_CMUX"].length) return Env()[@"MINMACS_CMUX"];
    NSURL *u = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.cmuxterm.app"];
    NSString *p = [u.path stringByAppendingPathComponent:@"Contents/Resources/bin/cmux"];
    return p && [NSFileManager.defaultManager isExecutableFileAtPath:p] ? p : nil;
}
static NSRunningApplication *CmuxApp(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.cmuxterm.app"].firstObject;
}

/// cmux's own process list: every process under its windows, workspaces, panes and tabs. One call covers every pid.
static NSDictionary *CmuxSnapshot(void) {
    static NSDictionary *snap; static NSDate *at;
    @synchronized (NSRunningApplication.class) {
        if (snap && -at.timeIntervalSinceNow < kSnapshotAge) return snap;
        NSMutableDictionary *procs = [NSMutableDictionary new], *objs = [NSMutableDictionary new];
        BOOL running = Env()[@"MINMACS_CMUX"].length || CmuxApp();
        NSString *out = running ? Run(CmuxPath(), @[@"top", @"--all", @"--processes", @"--format", @"tsv", @"--id-format", @"both"]) : nil;
        for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
            NSArray *c = [line componentsSeparatedByString:@"\t"];
            if (c.count < 6) continue;
            NSString *type = c[3], *idf = c[4], *parent = c[5], *title = c.count > 6 ? c[6] : @"";
            if ([type isEqualToString:@"process"]) procs[@([idf intValue])] = parent;
            else if (![type isEqualToString:@"webview"]) objs[idf] = @[type, parent, title];
        }
        snap = @{@"procs": procs, @"objs": objs}; at = NSDate.date;
        return snap;
    }
}

static MMPlace *InCmux(NSArray<NSNumber *> *chain) {
    NSDictionary *snap = CmuxSnapshot(), *procs = snap[@"procs"], *objs = snap[@"objs"];
    if (![procs count]) return nil;
    for (NSNumber *pid in chain) {
        NSString *parent = procs[pid];
        for (int i = 0; parent.length && [parent rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound && i < 64; i++)
            parent = procs[@(parent.intValue)];   // a parent that is itself a process
        if (!parent) continue;
        NSMutableDictionary *found = [NSMutableDictionary new];
        int hops = 0;
        for (NSString *key = parent; objs[key] && hops < 64; key = objs[key][1], hops++) found[objs[key][0]] = @[key, objs[key][2]];
        NSArray *surface = found[@"surface"], *workspace = found[@"workspace"], *window = found[@"window"];
        if (!surface || !workspace) continue;
        // The workspace title follows whichever tab is selected, so only the tab is named.
        NSString *tab = Clean(surface[1]);
        MMPlace *w = [MMPlace new];
        w.kind = MMPlaceCmux; w.app = @"cmux";
        w.label = tab.length ? [@"cmux, " stringByAppendingString:tab] : @"cmux";
        w.tab = tab ?: @"";
        w.workspace = LastWord(workspace[0]); w.surface = LastWord(surface[0]); w.window = window ? LastWord(window[0]) : @"";
        w.appPid = Env()[@"MINMACS_CMUX"].length ? 0 : CmuxApp().processIdentifier;   // a fake cmux has no app to bring forward
        return w;
    }
    return nil;
}

#pragma mark tmux

/// The tmux CLI. MINMACS_TMUX names another one, which tests use for a fake.
static NSString *TmuxPath(void) {
    if (Env()[@"MINMACS_TMUX"].length) return Env()[@"MINMACS_TMUX"];
    for (NSString *p in @[@"/opt/homebrew/bin/tmux", @"/usr/local/bin/tmux", @"/usr/bin/tmux"])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) return p;
    return nil;
}

/// Every tmux pane's shell by pid, and which process runs each session's client.
static NSDictionary *TmuxSnapshot(void) {
    static NSDictionary *snap; static NSDate *at;
    @synchronized (NSFileManager.class) {
        if (snap && -at.timeIntervalSinceNow < kSnapshotAge) return snap;
        NSMutableDictionary *panes = [NSMutableDictionary new], *clients = [NSMutableDictionary new];
        NSString *tmux = TmuxPath();
        NSString *out = Run(tmux, @[@"list-panes", @"-a", @"-F", @"#{pane_pid}\t#{pane_id}\t#{session_name}\t#{window_index}\t#{window_name}\t#{pane_index}"]);
        for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
            NSArray *c = [line componentsSeparatedByString:@"\t"];
            if (c.count == 6) panes[@([c[0] intValue])] = c;
        }
        if (panes.count)
            for (NSString *line in [Run(tmux, @[@"list-clients", @"-F", @"#{client_pid}\t#{client_session}"]) componentsSeparatedByString:@"\n"]) {
                NSArray *c = [line componentsSeparatedByString:@"\t"];
                if (c.count == 2) clients[c[1]] = @([c[0] intValue]);
            }
        snap = @{@"panes": panes, @"clients": clients}; at = NSDate.date;
        return snap;
    }
}

/// A tmux pane whose shell is above pid. When the session's client runs in a cmux tab, that tab is kept as outer,
/// so going there opens the tab first and then the pane.
static MMPlace *InTmux(NSArray<NSNumber *> *chain) {
    NSDictionary *snap = TmuxSnapshot(), *panes = snap[@"panes"];
    for (NSNumber *pid in chain) {
        NSArray *p = panes[pid];
        if (!p) continue;
        pid_t client = [snap[@"clients"][p[2]] intValue];
        NSArray *clientChain = client > 1 ? Chain(client) : @[];
        MMPlace *outer = clientChain.count ? InCmux(clientChain) : nil;
        NSRunningApplication *app = clientChain.count ? AppOf(clientChain, client) : nil;
        NSString *in = outer ? [NSString stringWithFormat:@", in %@", outer.label]
                     : app ? [NSString stringWithFormat:@", in %@", app.localizedName] : @", no client attached";
        MMPlace *w = [MMPlace new];
        w.kind = MMPlaceTmux; w.app = app.localizedName ?: @"tmux";
        w.label = [NSString stringWithFormat:@"tmux, %@, %@%@", p[2], p[4], in];
        w.tab = p[4]; w.target = p[1]; w.appPid = app.processIdentifier;
        w.outer = outer;
        return w;
    }
    return nil;
}

#pragma mark Lookup

static MMPlace *Compute(pid_t pid) {
    NSArray *chain = Chain(pid);
    if (!chain.count) return nil;
    MMPlace *w = InTmux(chain) ?: InCmux(chain);
    if (w) return w;
    NSRunningApplication *app = AppOf(chain, pid);
    if (!app) return nil;
    NSString *tty = nil;
    for (NSNumber *p in chain) if ((tty = TTYOf(p.intValue))) break;
    NSString *bundle = app.bundleIdentifier;
    MMPlaceKind kind = [bundle isEqualToString:@"com.apple.Terminal"] ? MMPlaceTerminal
                     : [bundle isEqualToString:@"com.googlecode.iterm2"] ? MMPlaceITerm : MMPlaceApp;
    // The app is not above pid when the shell that started it has closed. Its tab is gone then.
    BOOL orphan = [chain indexOfObject:@(app.processIdentifier)] == NSNotFound;
    w = [MMPlace new];
    w.kind = orphan ? MMPlaceApp : kind;
    w.app = app.localizedName ?: @"";
    w.appPid = app.processIdentifier;
    if (kind != MMPlaceApp && tty && !orphan) { w.label = [NSString stringWithFormat:@"%@, tab on %@", w.app, tty]; w.tty = tty; }
    else if (orphan) w.label = [NSString stringWithFormat:@"%@, the tab that started it has closed", w.app];
    else w.label = w.app;
    return w;
}

static NSMutableDictionary<NSString *, MMPlace *> *Answers(void) {
    static NSMutableDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
    return d;
}

static NSString *KeyString(MMProcKey k) { return [NSString stringWithFormat:@"%d:%llu", k.pid, k.startSec]; }

/// YES when the pid still runs with this start time, read from sysctl. A start time of 0 matches any.
static BOOL StillThere(MMProcKey k) {
    struct kinfo_proc p;
    return KInfo(k.pid, &p) && (!k.startSec || (uint64_t)p.kp_proc.p_starttime.tv_sec == k.startSec);
}

static const NSUInteger kMaxAnswers = 256;   // more answers than this means the pruning missed some; drop them all

/// Drops answers whose process is gone: from the sample when there is one, else read fresh from sysctl.
/// A key names the pid and its start time, so a reused pid never keeps the old process's place.
/// Call with answers locked.
static void Prune(NSMutableDictionary<NSString *, MMPlace *> *answers, MMSample *s) {
    for (NSString *x in answers.allKeys) {
        NSArray *parts = [x componentsSeparatedByString:@":"];
        MMProcKey k = { (pid_t)[parts.firstObject intValue], (uint64_t)[parts.lastObject longLongValue] };
        MMProc *p = s ? [s proc:k.pid] : nil;
        BOOL alive = s ? (p && (!k.startSec || p.startSec == k.startSec)) : StillThere(k);
        if (!alive) [answers removeObjectForKey:x];
    }
    if (answers.count > kMaxAnswers) [answers removeAllObjects];
}

MMPlace *MMWhereIs(MMProcKey key, MMSample *s, BOOL wait) {
    if (key.pid <= 1) return nil;
    NSString *k = KeyString(key);
    NSMutableDictionary *answers = Answers();
    if (wait) {
        MMPlace *w = StillThere(key) ? Compute(key.pid) : nil;
        @synchronized (answers) {
            if (w) answers[k] = w; else [answers removeObjectForKey:k];
            Prune(answers, s);
        }
        return w;
    }
    MMPlace *old;
    @synchronized (answers) { old = answers[k]; }
    dispatch_async(MMQueue(@"core", @"where", QOS_CLASS_UTILITY), ^{
        MMPlace *w = StillThere(key) ? Compute(key.pid) : nil;
        @synchronized (answers) {
            if (w) answers[k] = w; else [answers removeObjectForKey:k];
            Prune(answers, s);
        }
    });
    return old;
}

/// YES while an answer for key is cached. For the Know checks, which declare it themselves.
BOOL MMWhereCached(MMProcKey key);
BOOL MMWhereCached(MMProcKey key) {
    NSMutableDictionary *answers = Answers();
    @synchronized (answers) { return answers[KeyString(key)] != nil; }
}

#pragma mark Going there

static NSString *TabScript(MMPlaceKind kind, NSString *tty) {
    NSString *dev = [@"/dev/" stringByAppendingString:tty];
    if (kind == MMPlaceTerminal)
        return [NSString stringWithFormat:@"tell application id \"com.apple.Terminal\"\n"
                "repeat with w in windows\nrepeat with t in tabs of w\n"
                "if tty of t is \"%@\" then\nset selected of t to true\nset index of w to 1\nactivate\nreturn \"ok\"\nend if\n"
                "end repeat\nend repeat\nactivate\nreturn \"missing\"\nend tell", dev];
    return [NSString stringWithFormat:@"tell application id \"com.googlecode.iterm2\"\n"
            "repeat with w in windows\nrepeat with t in tabs of w\nrepeat with s in sessions of t\n"
            "if tty of s is \"%@\" then\nselect w\ntell t to select\ntell s to select\nactivate\nreturn \"ok\"\nend if\n"
            "end repeat\nend repeat\nend repeat\nactivate\nreturn \"missing\"\nend tell", dev];
}

static BOOL Activate(MMPlace *w, NSString **error) {
    NSRunningApplication *a = w.appPid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:w.appPid] : nil;
    if (!a) { if (error) *error = [NSString stringWithFormat:@"%@ is no longer running", w.app.length ? w.app : @"the app"]; return NO; }
    [a activateWithOptions:NSApplicationActivateAllWindows];
    return YES;
}

BOOL MMGoTo(MMPlace *w, NSString **error) {
    if (!w) { if (error) *error = @"nowhere to go"; return NO; }
    if (w.kind == MMPlaceCmux) {
        NSString *cmux = CmuxPath();
        NSArray *win = w.window.length ? @[@"--window", w.window] : @[];
        if (win.count) Run(cmux, [@[@"focus-window"] arrayByAddingObjectsFromArray:win]);
        Run(cmux, [@[@"select-workspace", @"--workspace", w.workspace ?: @""] arrayByAddingObjectsFromArray:win]);
        BOOL ok = Run(cmux, [@[@"focus-panel", @"--panel", w.surface ?: @"", @"--workspace", w.workspace ?: @""] arrayByAddingObjectsFromArray:win]) != nil;
        Activate(w, nil);
        if (!ok && error) *error = @"cmux did not find the tab. It may have closed";
        return ok;
    }
    if (w.kind == MMPlaceTmux) {
        if (w.outer) MMGoTo(w.outer, nil);
        NSString *tmux = TmuxPath();
        Run(tmux, @[@"switch-client", @"-t", w.target ?: @""]);
        Run(tmux, @[@"select-window", @"-t", w.target ?: @""]);
        BOOL ok = Run(tmux, @[@"select-pane", @"-t", w.target ?: @""]) != nil;
        if (w.appPid > 0) Activate(w, nil);
        if (!ok && error) *error = @"tmux did not find the pane. It may have closed";
        return ok;
    }
    if ((w.kind == MMPlaceTerminal || w.kind == MMPlaceITerm) && w.tty.length) {
        // osascript, not NSAppleScript, so this runs on any queue. The first time, macOS asks the person for permission
        // and the script waits on the answer, so it gets far longer than a cmux or tmux call.
        NSData *out = nil, *errOut = nil;
        MMRunResult r = MMRun(@"/usr/bin/osascript", @[@"-e", TabScript(w.kind, w.tty)], nil, nil, nil, 60, &out, &errOut);
        NSString *said = [[[NSString alloc] initWithData:out ?: NSData.data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (r.didRun && r.status == 0 && [said isEqualToString:@"ok"]) return YES;
        Activate(w, nil);
        NSString *why = [[[NSString alloc] initWithData:errOut ?: NSData.data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (error) *error = r.status != 0 || !r.didRun ? [NSString stringWithFormat:@"%@ did not allow MinMacs to select the tab: %@", w.app, why.length ? why : @"no permission"]
                                                       : @"the tab has closed";
        return NO;
    }
    return Activate(w, error);
}
