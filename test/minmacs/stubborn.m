// Test fixture app, from tools/stubborn.m on branch legacy. It refuses a normal Quit, and can listen on a loopback port.
//   open -g -n Stubborn.app --args --listen 47999
// Built into a bundle whose id ends in .polite, it quits when asked. test/minmacs.sh builds each copy
// inside $MINMACS_HOME with a name and bundle id unique to the run.
#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
@interface Stubborn : NSObject <NSApplicationDelegate>
@end
@implementation Stubborn
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)s {
    return [NSBundle.mainBundle.bundleIdentifier hasSuffix:@".polite"] ? NSTerminateNow : NSTerminateCancel;
}
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
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        Stubborn *d = [Stubborn new];
        app.delegate = d;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
