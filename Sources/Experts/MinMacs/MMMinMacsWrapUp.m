// Wrap Up, issue #27: MinMacs's part is the helpers a finished workstream left behind. A helper is a process of the
// person's whose parent exited, so launchd adopted it, whose folder is inside the worktree, that listens on no port
// and is no shell and no agent. A headless browser or a file watcher left by a test run is one.
// Read from the shared sample in the snapshot. A server is LocoHost's part, and a process with a live parent, such as
// one in a terminal, is no leftover, so it keeps the worktree.
#import "Experts/MinMacs/MMMinMacs.h"

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

@end
