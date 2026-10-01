#import <Foundation/Foundation.h>
#import "Agents.h"

/// Reads cmux (bundle id com.cmuxterm.app) for the one thing process signals cannot see:
/// an agent that is waiting on the human. It feeds MMAgents.overrides and overrideReasons.
///
/// Reads exactly two files and exactly these keys, with a key-filtered scanner that skips every
/// other value without copying it:
///   ~/.cmuxterm/claude-hook-sessions.json   pid, sessionId, surfaceId, workspaceId, updatedAt
///   ~/.cmuxterm/workstream.jsonl            kind, createdAt, workstreamId   (the last 2 MB only)
/// Prompts, tool inputs, payloads, context and titles are never read, stored or logged.
@interface MMCmuxReader : NSObject
extern NSString *const MMCmuxBundleID;        // com.cmuxterm.app
+ (BOOL)cmuxRunning;
/// Reads the files and adds overrides to the two dictionaries (blocked always, working only for an
/// event younger than 60 s). Writes nothing when cmux is not running, unless `directory` is given.
/// `directory` is the debug hook: read the two files from there instead of ~/.cmuxterm, cmux running or not.
- (void)addOverridesTo:(NSMutableDictionary<NSNumber *, NSString *> *)overrides
               reasons:(NSMutableDictionary<NSNumber *, NSString *> *)reasons
             directory:(NSString *)directory;
@end
