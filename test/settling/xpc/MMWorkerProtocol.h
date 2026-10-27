// The protocol the probe's XPC service answers. It mirrors the one call Core's MMWorker needs:
// walk a folder and send back a count. Fixtures only: the host passes a folder it made.
#import <Foundation/Foundation.h>

@protocol MMProbeWorker
- (void)ping:(void (^)(int pid))reply;
- (void)countFilesIn:(NSString *)path reply:(void (^)(uint64_t files, uint64_t bytes, int pid))reply;
@end
