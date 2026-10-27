// The app's end of core.sock, and the instance lock. Pattern P63 of SYNTHESIS.md section 1.9.
// The CLI asks the running app first. When no app answers, it runs Core cold, and verbs that change things refuse.
// The CLI side of P63 lives in Sources/CLI. This header holds what the app and the CLI share.
#import <Foundation/Foundation.h>

/// <support folder>/core.sock.
NSString *MMCoreSocketPath(void);

/// P63. A Unix socket server for requests from the CLI. One request and one reply per connection, as JSON.
/// Starts from NN internal/ipc/server.go:82-160: an flock instance lock, then the socket, then a same-uid check
/// on every connection with getpeereid. A peer with another uid is closed without a reply.
/// The socket file is mode 0600, so only the person's own uid can connect at all.
@interface MMCoreSocket : NSObject
/// Takes the instance lock and serves. nil with *error when another MinMacs holds the lock.
/// handler runs on MMQueue(@"core", @"socket"), one request at a time, and returns the reply.
/// Each connection is read and answered off that queue, so a peer that sends nothing holds up no other.
+ (instancetype)serve:(NSDictionary *(^)(NSDictionary *request))handler error:(NSString **)error;
/// The client side: sends one request and waits for the reply. nil when no app answers within timeout.
/// The CLI passes 0.2 seconds.
+ (NSDictionary *)ask:(NSDictionary *)request timeout:(NSTimeInterval)timeout;
- (void)stop;
@end

/// YES while another process holds the instance lock, so a second app launch can quit at once.
BOOL MMAnotherInstanceRuns(void);
