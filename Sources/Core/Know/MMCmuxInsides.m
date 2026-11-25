// cmux's insides, MMAppInsides.h: one `cmux --json top --all --processes`, which returns every window, workspace,
// pane and tab with the processes under each and what they use. Read only: nothing is sent to a tab, nothing opens
// or closes. The answer's shape, from cmux 0.65:
//
//   {windows: [{ref, workspaces: [{id, ref, title, selected, resources, tags: [{key, value, pid}],
//                                  panes: [{ref, focused, resources, surfaces: [{ref, title, type, tty, url, selected,
//                                           foreground_pgids, resources, processes: [{pid, name, resources, children}]}]}]}]}]}
//
// resources is {cpu_percent, memory_bytes, process_count}. An answer with no windows array is an older cmux.
#import "Core/Know/MMAppInsides.h"
#import "Core/Know/MMGit.h"
#import <AppKit/AppKit.h>

NSString *const MMAppInsidesCmux = @"com.cmuxterm.app";

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSNumber *Num(id v) { return [v isKindOfClass:NSNumber.class] ? v : nil; }
static NSArray *Arr(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : @{}; }

/// cmux puts a status glyph in front of an agent's tab: "◐ repo check" reads "repo check", as MMWhere names it.
static NSString *Clean(NSString *title) {
    if (!title) return @"";
    NSCharacterSet *keep = NSCharacterSet.alphanumericCharacterSet;
    NSUInteger i = 0;
    while (i < title.length && ![keep characterIsMember:[title characterAtIndex:i]] && [title characterAtIndex:i] != '~' && [title characterAtIndex:i] != '/') i++;
    NSString *t = [[title substringFromIndex:i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // One line, and never more than a row can hold whole.
    t = [[t componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    return t.length > 120 ? [t substringToIndex:120] : t;
}

/// Only an address on this Mac is kept from a browser tab: it is where a server of the person's own runs.
static NSString *LocalURL(NSString *url) {
    NSURL *u = url ? [NSURL URLWithString:url] : nil;
    NSString *host = u.host.lowercaseString;
    return [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"] || [host hasSuffix:@".localhost"] ? url : nil;
}

static void Use(MMInsidesNode *n, NSDictionary *resources) {
    n.cpuPercent = MAX([Num(resources[@"cpu_percent"]) doubleValue], 0);
    n.bytes = (uint64_t)MAX([Num(resources[@"memory_bytes"]) longLongValue], 0);
}

static MMInsidesNode *Node(NSString *kind, NSString *ref, NSString *title) {
    MMInsidesNode *n = [MMInsidesNode new];
    n.kind = kind; n.ref = ref ?: @""; n.title = title ?: @""; n.children = @[]; n.pids = @[];
    return n;
}

/// A process and every one under it, at most 400 in all, and its pid and theirs into pids.
static MMInsidesNode *Process(NSDictionary *p, NSMutableArray<NSNumber *> *pids, NSInteger depth) {
    pid_t pid = (pid_t)[Num(p[@"pid"]) intValue];
    if (pid <= 0 || pids.count >= 400) return nil;
    [pids addObject:@(pid)];
    MMInsidesNode *n = Node(@"process", @(pid).stringValue, Str(p[@"name"]) ?: @"");
    n.pid = pid;
    Use(n, Dict(p[@"resources"]));
    NSMutableArray *kids = [NSMutableArray new];
    if (depth < 32) for (id c in Arr(p[@"children"])) { MMInsidesNode *k = [c isKindOfClass:NSDictionary.class] ? Process(c, pids, depth + 1) : nil; if (k) [kids addObject:k]; }
    n.children = kids;
    return n;
}

@implementation MMCmuxInsides

- (NSString *)bundleID { return MMAppInsidesCmux; }
- (NSString *)appName { return @"cmux"; }

+ (NSArray<NSString *> *)arguments { return @[@"--json", @"top", @"--all", @"--processes"]; }

+ (MMInsidesAnswer *)parse:(NSData *)json {
    MMInsidesAnswer *a = [MMInsidesAnswer new];
    a.app = @"cmux";
    id top = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![top isKindOfClass:NSDictionary.class] || ![top[@"windows"] isKindOfClass:NSArray.class]) {
        a.known = MMInsidesOlder;
        a.why = @"This cmux answers in a shape MinMacs does not read. It may be an older version.";
        return a;
    }
    MMInsidesNode *root = Node(@"app", @"cmux", @"cmux");
    Use(root, Dict(top[@"totals"]));
    NSMutableArray *windows = [NSMutableArray new];
    for (id w in Arr(top[@"windows"])) {
        if (![w isKindOfClass:NSDictionary.class]) continue;
        MMInsidesNode *win = Node(@"window", Str(w[@"ref"]), @"");
        Use(win, Dict(w[@"resources"]));
        NSMutableArray *spaces = [NSMutableArray new];
        for (id ws in Arr(w[@"workspaces"])) {
            if (![ws isKindOfClass:NSDictionary.class]) continue;
            MMInsidesNode *space = Node(@"workspace", Str(ws[@"ref"]), Clean(Str(ws[@"title"])));
            space.uid = Str(ws[@"id"]); space.selected = [Num(ws[@"selected"]) boolValue];
            Use(space, Dict(ws[@"resources"]));
            // cmux's own word for an agent, by the pid it watches: "Working", "Waiting".
            NSMutableDictionary<NSNumber *, NSString *> *status = [NSMutableDictionary new];
            for (id t in Arr(ws[@"tags"])) {
                NSDictionary *tag = Dict(t);
                pid_t pid = (pid_t)[Num(tag[@"pid"]) intValue];
                if (pid > 0 && Str(tag[@"value"])) status[@(pid)] = Clean(tag[@"value"]);
            }
            NSMutableArray *panes = [NSMutableArray new], *spacePids = [NSMutableArray new];
            for (id p in Arr(ws[@"panes"])) {
                if (![p isKindOfClass:NSDictionary.class]) continue;
                MMInsidesNode *pane = Node(@"pane", Str(p[@"ref"]), @"");
                pane.selected = [Num(p[@"focused"]) boolValue];
                Use(pane, Dict(p[@"resources"]));
                NSMutableArray *tabs = [NSMutableArray new], *panePids = [NSMutableArray new];
                for (id s in Arr(p[@"surfaces"])) {
                    if (![s isKindOfClass:NSDictionary.class]) continue;
                    MMInsidesNode *tab = Node(@"tab", Str(s[@"ref"]), Clean(Str(s[@"title"])));
                    tab.tty = Str(s[@"tty"]); tab.type = Str(s[@"type"]); tab.url = LocalURL(Str(s[@"url"]));
                    tab.selected = [Num(s[@"selected_in_pane"]) boolValue] || [Num(s[@"selected"]) boolValue];
                    Use(tab, Dict(s[@"resources"]));
                    NSMutableArray<NSNumber *> *pids = [NSMutableArray new];
                    NSMutableArray *procs = [NSMutableArray new];
                    for (id pr in Arr(s[@"processes"])) { MMInsidesNode *n = [pr isKindOfClass:NSDictionary.class] ? Process(pr, pids, 0) : nil; if (n) [procs addObject:n]; }
                    tab.children = procs; tab.pids = pids;
                    // The foreground process: what the person sees running in the tab.
                    for (id g in Arr(s[@"foreground_pgids"])) if ([Num(g) intValue] > 0 && [pids containsObject:@([g intValue])]) { tab.pid = [g intValue]; break; }
                    for (NSNumber *pid in pids) if (status[pid]) { tab.status = status[pid]; break; }
                    [tabs addObject:tab]; [panePids addObjectsFromArray:pids];
                }
                pane.children = tabs; pane.pids = panePids;
                [panes addObject:pane]; [spacePids addObjectsFromArray:panePids];
            }
            space.children = panes; space.pids = spacePids;
            [spaces addObject:space];
        }
        win.children = spaces;
        [windows addObject:win];
    }
    root.children = windows;
    a.root = root; a.known = MMInsidesFound;
    return a;
}

/// The cmux CLI: MINMACS_CMUX names another one, which tests use for a fake, as MMWhere does.
static NSString *CmuxPath(void) {
    NSString *fake = Str(NSProcessInfo.processInfo.environment[@"MINMACS_CMUX"]);
    if (fake) return fake;
    NSURL *u = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:MMAppInsidesCmux];
    NSString *p = [u.path stringByAppendingPathComponent:@"Contents/Resources/bin/cmux"];
    return p && [NSFileManager.defaultManager isExecutableFileAtPath:p] ? p : nil;
}

- (MMInsidesAnswer *)readWithin:(NSTimeInterval)limit {
    MMInsidesAnswer *a = [MMInsidesAnswer new];
    a.app = @"cmux"; a.known = MMInsidesUnreachable;
    NSString *cmux = CmuxPath();
    if (!cmux || ![NSFileManager.defaultManager isExecutableFileAtPath:cmux]) { a.why = @"cmux's command line is not there, so MinMacs cannot look inside it."; return a; }
    NSMutableDictionary *env = [NSMutableDictionary new];
    for (NSString *k in @[@"CMUX_SOCKET_PATH", @"CMUX_SOCKET_PASSWORD"]) if (Str(NSProcessInfo.processInfo.environment[k])) env[k] = NSProcessInfo.processInfo.environment[k];
    NSData *out = nil, *err = nil;
    MMRunResult r = MMRun(cmux, MMCmuxInsides.arguments, nil, env, nil, limit, &out, &err);
    if (!r.didRun) { a.why = @"cmux's command line did not start, so MinMacs cannot look inside it."; return a; }
    if (r.timedOut) { a.why = [NSString stringWithFormat:@"cmux did not answer within %.0f s.", MAX(limit, 1)]; return a; }
    if (r.status != 0) {
        NSString *said = [[[NSString alloc] initWithData:err ?: NSData.data encoding:NSUTF8StringEncoding] lowercaseString] ?: @"";
        // An older cmux knows no --json or no --processes: it says so and exits. Anything else is its socket.
        BOOL older = [said containsString:@"unknown"] || [said containsString:@"unrecognized"] || [said containsString:@"usage"] || [said containsString:@"invalid option"];
        a.known = older ? MMInsidesOlder : MMInsidesUnreachable;
        a.why = older ? @"This cmux is older than what MinMacs reads. Its own process tree shows instead."
                      : @"cmux did not answer on its socket, so MinMacs cannot look inside it.";
        return a;
    }
    MMInsidesAnswer *parsed = [MMCmuxInsides parse:out];
    if (parsed.known == MMInsidesOlder) parsed.why = @"This cmux is older than what MinMacs reads. Its own process tree shows instead.";
    parsed.at = NSDate.date;
    return parsed;
}

@end
