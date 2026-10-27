// The XPC service side of the probe. launchd starts it on the first message and ends it when idle.
#import "MMWorkerProtocol.h"
#include <sys/stat.h>
#include <fts.h>

@interface MMProbeService : NSObject <MMProbeWorker, NSXPCListenerDelegate>
@end

@implementation MMProbeService
- (void)ping:(void (^)(int))reply { reply(getpid()); }

- (void)countFilesIn:(NSString *)path reply:(void (^)(uint64_t, uint64_t, int))reply {
    char *paths[] = {(char *)path.fileSystemRepresentation, NULL};
    FTS *f = fts_open(paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, NULL);
    uint64_t n = 0, b = 0;
    FTSENT *e;
    while (f && (e = fts_read(f))) if (e->fts_info == FTS_F) { n++; b += (uint64_t)e->fts_statp->st_blocks * 512; }
    if (f) fts_close(f);
    reply(n, b, getpid());
}

- (BOOL)listener:(NSXPCListener *)l shouldAcceptNewConnection:(NSXPCConnection *)c {
    c.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MMProbeWorker)];
    c.exportedObject = self;
    [c resume];
    return YES;
}
@end

int main(void) {
    static MMProbeService *s;
    s = [MMProbeService new];
    NSXPCListener *l = NSXPCListener.serviceListener;
    l.delegate = s;
    [l resume];   // never returns
    return 0;
}
