#import <Foundation/Foundation.h>
#import "Scanner.h"

/// One agent session found running, and whether it is working.
@interface MMAgent : NSObject
@property (copy) NSString *harness, *harnessID, *surface, *state, *why, *sessionID, *project;   // state: working | idle | blocked | unknown
@property pid_t pid;
@property double cpu;                     // whole process tree
@property uint64_t memory;                // whole process tree
@property NSInteger children;
@property NSInteger transcriptAge;        // seconds since the session's transcript was written, -1 unknown
@property (strong) NSArray<NSNumber *> *treePids;
@property (strong) NSArray<NSDictionary *> *hosted;   // agents of other rows folded into this host: harness, id, pid, state
@property (readonly) BOOL working;
- (NSDictionary *)json;
@end

/// Finds agent sessions from registry rows (data, not code) and OS signals.
/// tools/agents_probe.py is the reference; this must agree with it.
/// Optional row fields it reads beyond the schema's basics: presence (a name-only match needs one of
/// these paths to exist), no_outside_signal (no signal fired reads unknown, not idle), a surface's
/// hosts_agents (agents of other rows below it are folded into it), and a child_process signal's
/// args_contain (see registry/schema.json).
@interface MMAgents : NSObject
+ (NSArray<NSString *> *)defaultRowDirectories;       // bundled rows, then the user's own
- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs;
@property (readonly) NSInteger rowCount;
/// A session counts as working for this long after its last working signal (default 30 s).
/// Covers an agent waiting on a slow model reply, and signals that flicker between steps. 0 for one-shot use.
@property NSTimeInterval holdSeconds;
- (NSArray<MMAgent *> *)detect:(MMScanner *)scanner;
/// States a host or hook reader knows better than process signals do, keyed by pid.
/// Values: working | idle | blocked | unknown. Applied after signal evaluation: blocked and
/// unknown replace the computed state; working and idle only replace a computed idle.
@property (strong) NSDictionary<NSNumber *, NSString *> *overrides;
/// Why each override holds, keyed by pid (shown in the menu as the reason).
@property (strong) NSDictionary<NSNumber *, NSString *> *overrideReasons;
/// The working agent that owns this pid (it is in that agent's process tree), or nil.
- (MMAgent *)workingAgentOwning:(pid_t)pid in:(NSArray<MMAgent *> *)agents;
@end
