#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/// One process, as sampled.
@interface MMProc : NSObject
@property pid_t pid, ppid;
@property (copy) NSString *name;
@property double cpuNs;          // cumulative user+system CPU, nanoseconds
@property uint64_t footprint;    // physical footprint, bytes
@property double cpuPercent;     // since the previous sample
@end

/// A GUI app with its helper processes rolled up.
@interface MMApp : NSObject
@property (strong) NSRunningApplication *app;
@property (copy) NSString *bundleID, *name;
@property double cpuPercent;
@property uint64_t memory;
@property NSInteger processCount;
@property (strong) NSMutableArray<NSNumber *> *pids;   // every process attributed to this app
@end

/// Samples every process, computes CPU% between samples, and attributes
/// helper processes to their owning GUI app by walking the parent chain.
@interface MMScanner : NSObject
- (void)sample;
@property (readonly) NSArray<MMApp *> *apps;            // sorted by cpu desc
@property (readonly) NSArray<MMProc *> *unattributed;   // non-app processes, sorted by cpu desc
@property (readonly) double totalCPU;                   // sum over all processes, percent of one core
@end

NSString *MMFormatBytes(uint64_t bytes);

/// TCP ports these processes listen on, bound to loopback only (127.0.0.1 / ::1).
/// A loopback listener is a local tool bridge; a wildcard listener is LAN discovery and is ignored.
NSArray<NSNumber *> *MMLoopbackListeners(NSArray<NSNumber *> *pids);

/// Command line arguments of a process, or nil.
NSArray<NSString *> *MMProcessArgs(pid_t pid);
