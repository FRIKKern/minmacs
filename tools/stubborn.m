// Test fixture: an app that refuses a normal Quit, and can listen on a loopback port.
//   open -g -n build/Stubborn.app --args --listen 47999
#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
@interface Stubborn : NSObject <NSApplicationDelegate> @end
@implementation Stubborn
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)s { return NSTerminateCancel; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSArray *a = NSProcessInfo.processInfo.arguments;
    NSUInteger i = [a indexOfObject:@"--listen"];
    if (i == NSNotFound || i + 1 >= a.count) return;
    int fd = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = { .sin_len = sizeof sa, .sin_family = AF_INET, .sin_port = htons([a[i + 1] intValue]) };
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    if (bind(fd, (struct sockaddr *)&sa, sizeof sa) == 0) listen(fd, 4);
}
@end
int main(void) { @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication; Stubborn *d = [Stubborn new]; app.delegate = d;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app run]; } return 0; }
