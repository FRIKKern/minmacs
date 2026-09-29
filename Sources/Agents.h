#import <Foundation/Foundation.h>
#import "Scanner.h"

/// One agent session found running, and whether it is working.
@interface MMAgent : NSObject
@property (copy) NSString *harness, *harnessID, *surface, *state, *why, *sessionID, *project;
@property pid_t pid;
@property double cpu;                     // whole process tree
@property uint64_t memory;                // whole process tree
@property NSInteger children;
@property NSInteger transcriptAge;        // seconds since the session's transcript was written, -1 unknown
@property (strong) NSArray<NSNumber *> *treePids;
@property (readonly) BOOL working;
- (NSDictionary *)json;
@end

/// Finds agent sessions from registry rows (data, not code) and OS signals.
/// tools/agents_probe.py is the reference; this must agree with it.
@interface MMAgents : NSObject
+ (NSArray<NSString *> *)defaultRowDirectories;       // bundled rows, then the user's own
- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs;
@property (readonly) NSInteger rowCount;
/// A session counts as working for this long after its last working signal (default 30 s).
/// Covers an agent waiting on a slow model reply, and signals that flicker between steps. 0 for one-shot use.
@property NSTimeInterval holdSeconds;
- (NSArray<MMAgent *> *)detect:(MMScanner *)scanner;
/// The working agent that owns this pid (it is in that agent's process tree), or nil.
- (MMAgent *)workingAgentOwning:(pid_t)pid in:(NSArray<MMAgent *> *)agents;
@end
