// Senses: the one 5-second pass over processes and sockets, the power facts, and the pushed signals.
// Patterns P6 to P14 and the test power source of P66, SYNTHESIS.md sections 1.2 and 1.9.
// Never in a tick: lsof, nettop, ps or pmset. One KERN_PROC_ALL sysctl covers every pid.
#import <Foundation/Foundation.h>
#import <sys/types.h>

@class NSRunningApplication;

/// P7. A process identity that survives pid reuse: the pid and its start time in seconds.
/// Starts from LH Ports.m:71-102 and KInfo in LH Where.m:28. Every action checks this key fresh before it signals.
typedef struct { pid_t pid; uint64_t startSec; } MMProcKey;
/// YES when a process with this pid and this start time still runs. A zombie counts as gone.
BOOL MMProcAlive(MMProcKey key);
/// "4123:1761578400", the form stored in undo records and keeps.
NSString *MMProcKeyString(MMProcKey key);

/// P7. The facts of one process in one sample.
/// CPU, footprint and energy come from RUSAGE_INFO_V6 and are read for our own uid only.
/// For other users' processes cpuPercent is -1 and footprint is 0.
@interface MMProc : NSObject
@property (readonly) pid_t pid, ppid;
@property (readonly) uid_t uid;
@property (readonly) uint64_t startSec;
@property (readonly) MMProcKey key;
@property (readonly, copy) NSString *name;             // p_comm, at most 16 characters
@property (readonly) double cpuPercent;                // since the last sample, 100 is one core
@property (readonly) double energyRank;                // 0 to 1 against this sample's busiest process, never joules
@property (readonly) uint64_t footprint;               // phys_footprint in bytes
@end

/// P10. One TCP socket of one of our own processes, LISTEN or ESTABLISHED, IPv4, IPv6 or v4-mapped.
/// Starts from ScanSockets in LH Ports.m:326, with PROC_PIDLISTFDS and PROC_PIDFDSOCKETINFO. IPv4 addresses sit in
/// the first 4 bytes.
typedef NS_ENUM(uint8_t, MMSocketState) { MMSocketListen = 1, MMSocketEstablished = 2 };
typedef struct {
    pid_t pid;
    uint8_t family;                                    // AF_INET or AF_INET6
    MMSocketState state;
    uint16_t localPort, remotePort;
    uint8_t localAddr[16], remoteAddr[16];
} MMSocket;

/// P6 and P8. One immutable pass over every process. A zombie, a process that exited and waits to be reaped,
/// is left out. Every array a sample hands out is immutable. A new sample replaces the old one every 5 seconds.
/// Starts from -[LHScanner sample] at LH Ports.m:439. The tree and roll-ups start from LH Ports.m:536,
/// which caps a tree at 500 pids and an ancestor walk at 20 hops.
/// Args and cwd are read lazily, once per sample, and memoized. Safe to read from any queue.
@interface MMSample : NSObject
@property (readonly) NSDate *at;
@property (readonly) uint64_t generation;               // counts up by one per pass
@property (readonly) NSDictionary<NSNumber *, MMProc *> *procs;   // by pid
- (MMProc *)proc:(pid_t)pid;
- (NSArray<NSString *> *)argsOf:(pid_t)pid;              // never nil, empty when it cannot be read
- (NSString *)cwdOf:(pid_t)pid;                          // nil when it cannot be read
- (NSArray<NSNumber *> *)childrenOf:(pid_t)pid;
- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max;          // pid first, then its descendants
- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops;    // parent first, launchd last
/// The sum of cpuPercent and footprint over treeOf:pid, computed once per sample.
- (double)treeCPU:(pid_t)pid;
- (uint64_t)treeFootprint:(pid_t)pid;
/// The socket table of this sample. The pointer lives as long as the sample.
- (const MMSocket *)sockets:(NSUInteger *)count;
- (NSArray<NSValue *> *)socketsOf:(pid_t)pid;            // MMSocket values in NSValue
@end

/// P9. The app macOS holds responsible for pid, through responsibility_get_pid_responsible_for_pid.
/// Starts from Responsible in LH Ports.m:63. Returns pid itself when the answer is unknown.
pid_t MMResponsiblePid(pid_t pid);
/// P9. The running app that owns pid: itself, its responsible pid or the nearest ancestor that is an app.
/// Starts from AppOf in LH Where.m:62. nil when no app owns it.
NSRunningApplication *MMOwningApp(MMSample *s, pid_t pid);

/// P13 and P14. The power and pressure facts. Every field is read from IOKit, sysctl or NSProcessInfo in microseconds.
/// Starts from LH main.m:856 and IN main.m:259-291. The lid override comes from IOPMrootDomain SleepDisabled,
/// never from `pmset -g`, which IN main.m:681 runs on main at 80 ms a read.
@interface MMPower : NSObject
@property (readonly) NSDate *at;
@property (readonly) BOOL onAC, lidClosed, lowPowerMode;
@property (readonly) BOOL lidOverride;                  // IOPMrootDomain SleepDisabled, which Insomnia's lid mode sets
@property (readonly) int batteryPercent;                // -1 without a battery
@property (readonly) NSProcessInfoThermalState thermal;
@property (readonly) NSInteger memoryPressure;          // 1 normal, 2 warn, 4 critical, as DISPATCH_MEMORYPRESSURE_*
@property (readonly) uint64_t diskFree;                 // bytes free on the home volume
/// IOPMCopyAssertionsByProcess: the power assertions each pid holds, such as a caffeinate child of an agent.
@property (readonly) NSDictionary<NSNumber *, NSArray<NSDictionary *> *> *assertionsByPid;
@end

/// P11, P12 and P13. What Senses pushes. A block gets the bits that changed and one detail object:
/// the exited MMProcKey in an NSValue for MMSignalExit, the NSRunningApplication for MMSignalApp, nil otherwise.
typedef NS_OPTIONS(NSUInteger, MMSignal) {
    MMSignalMemory = 1 << 0,    // memory pressure changed
    MMSignalDisk = 1 << 1,      // free disk crossed a mark
    MMSignalThermal = 1 << 2,
    MMSignalPower = 1 << 3,     // power source or battery
    MMSignalLid = 1 << 4,       // lid closed, opened, or the override changed
    MMSignalExit = 1 << 5,      // a watched process exited, from kqueue NOTE_EXIT
    MMSignalApp = 1 << 6,       // an app launched or quit, from NSWorkspace
    MMSignalSleep = 1 << 7,     // the Mac slept or woke, from NSWorkspace
    MMSignalSample = 1 << 8,    // a new sample is ready
};

/// P6, P11 and P12. The one owner of every sample and signal. An expert never samples on its own.
/// The pass runs on MMQueue(@"core", @"senses") with an MMTimer every 5 seconds.
@interface MMSenses : NSObject
+ (instancetype)shared;
- (void)start;
/// Ends the timer, the pushed sources and the notification observers that start added. Main thread.
/// The last sample stays readable. start may be called again.
- (void)stop;
- (MMSample *)latest;                                   // never blocks; nil before the first pass ends
- (MMPower *)power;                                     // never blocks
/// Takes a sample now and waits for it. For the CLI when it runs Core cold, never on main in the app.
- (MMSample *)sampleNow;
/// P11. Registers kqueue NOTE_EXIT for each key. New code: costs 0.47 us a pid and nothing while idle.
/// An exit fires MMSignalExit. A key whose process already ended fires at once.
- (void)watchExits:(NSArray<NSValue *> *)keys;
/// Calls block on main for each change in mask. Returns a token; pass it to -stopObserving: to end.
- (id)observe:(MMSignal)mask block:(void (^)(MMSignal changed, id detail))block;
- (void)stopObserving:(id)token;
@end

#ifdef MM_TESTS
/// P66. A fake power source for tests, in place of Insomnia's insomnia.debug.* prefs.
/// Compiled only with -DMM_TESTS, so a release build has no way to fake power facts.
@protocol MMPowerSource <NSObject>
- (MMPower *)read;
@end
void MMUsePowerSource(id<MMPowerSource> source);       // nil goes back to IOKit
/// A power fact sheet built from a dictionary with the property names above as keys.
MMPower *MMPowerFrom(NSDictionary *facts);
#endif
