// The host side of the probe. It lives in Contents/MacOS of an ad-hoc signed bundle, so its main
// bundle is the .app and NSXPCConnection finds the service in Contents/XPCServices.
// It has no window and no status item. It prints the cold start time, the time per call and the
// service's pid, then exits. Usage: Contents/MacOS/host <fixture folder>
#import "MMWorkerProtocol.h"
#include <mach/mach_time.h>

static double ms(uint64_t a, uint64_t b) {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    return (double)(b - a) * tb.numer / tb.denom / 1e6;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = argc > 1 ? @(argv[1]) : NSTemporaryDirectory();
        printf("main bundle %s\n", NSBundle.mainBundle.bundlePath.UTF8String);
        NSXPCConnection *c = [[NSXPCConnection alloc] initWithServiceName:@"no.guerrilla.minmacs.probe.worker"];
        c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MMProbeWorker)];
        __block NSString *failure = nil;
        c.interruptionHandler = ^{ failure = @"interrupted"; };
        c.invalidationHandler = ^{ if (!failure) failure = @"invalidated"; };
        [c resume];
        id<MMProbeWorker> w = [c synchronousRemoteObjectProxyWithErrorHandler:^(NSError *e) { failure = e.description; }];
        uint64_t t0 = mach_absolute_time();
        __block int pid = 0;
        [w ping:^(int p) { pid = p; }];
        uint64_t t1 = mach_absolute_time();
        if (!pid) { printf("FAIL no reply: %s\n", failure.UTF8String ?: "unknown"); return 1; }
        printf("cold start and first reply: %.1f ms, service pid %d\n", ms(t0, t1), pid);
        uint64_t t2 = mach_absolute_time();
        for (int i = 0; i < 100; i++) [w ping:^(int p) { (void)p; }];
        uint64_t t3 = mach_absolute_time();
        printf("100 warm calls: %.3f ms per call\n", ms(t2, t3) / 100);
        __block uint64_t files = 0, bytes = 0; __block int wpid = 0;
        [w countFilesIn:dir reply:^(uint64_t f, uint64_t b, int p) { files = f; bytes = b; wpid = p; }];
        printf("walk of %s in the service: %llu files, %llu bytes, pid %d\n", dir.UTF8String, files, bytes, wpid);
        [c invalidate];
        printf("PASS\n");
    }
    return 0;
}
