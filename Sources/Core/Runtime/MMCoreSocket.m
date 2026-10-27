// core.sock and the instance lock, pattern P63. A stub in issue #14.
// The server, the client and the flock instance lock come with the CLI work, ported from
// NN internal/ipc/server.go:82-160. Until then the CLI finds no app and runs Core cold,
// which is what MMRunCLI does today. MMCoreSocketPath is real, so both sides already agree on the path.
#import "Core/Runtime/MMCoreSocket.h"

NSString *MMRuntimeSupportDir(void);

NSString *MMCoreSocketPath(void) { return [MMRuntimeSupportDir() stringByAppendingPathComponent:@"core.sock"]; }

@implementation MMCoreSocket

+ (instancetype)serve:(NSDictionary *(^)(NSDictionary *request))handler error:(NSString **)error {
    if (error) *error = @"core.sock is not built yet. Issue #14 left it a stub";
    return nil;
}

+ (NSDictionary *)ask:(NSDictionary *)request timeout:(NSTimeInterval)timeout { return nil; }

- (void)stop {}

@end

BOOL MMAnotherInstanceRuns(void) { return NO; }
