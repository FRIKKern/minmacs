// The main-thread watchdog, issue #55. Main never waits on disk, a process or the log, and a menu or card opens
// within one frame. The watchdog checks that: every pass of the main run loop that takes longer than the threshold
// is a stall, logged with main's stack as it was when the threshold passed.
//
// How it works. A run loop observer on main marks the start and end of each pass. The watchdog's own thread sleeps
// until a pass starts. While the pass runs it reads main's run state every millisecond. At start plus threshold, if
// the same pass still runs, it suspends main for a moment, reads its registers and walks its frame pointers, resumes
// it, and waits for the pass to end. Nothing is allocated while main is suspended. The symbols are looked up after
// main runs again.
//
// A pass can be long with nothing held on main: on a Mac with every core busy, main is ready to run and gets no CPU.
// A stall says how much of the pass that was, as readyMs, issue #84. No call gives that time for one thread, so it
// is the smaller of what the kernel counts for the whole process and what the reads of main's run state saw, and
// never the CPU main used. Main blocked, such as asleep or on a lock, is not ready, so that time stays in the stall.
// When the watchdog thread gets no CPU either, the time since its last read counts as ready, up to the process's
// number.
//
// It is on in a debug build, DEBUG=1 ./build.sh, which defines MM_DEBUG, and wherever MINMACS_WATCHDOG=1 is set.
// Each stall goes to the unified log through NSLog, to <support folder>/stalls.log as one JSON line, and to
// MMWatchdogStalls for a test. When main is idle the watchdog thread sleeps, so it adds no wakeups at rest.
#import <Foundation/Foundation.h>

/// The threshold of issue #55: a pass over 50 ms is a stall.
extern const double MMWatchdogDefaultMs;

/// Starts the watchdog on main's run loop. Call on the main thread. A second call changes only the threshold.
void MMWatchdogStart(double thresholdMs);
/// Stops it. Stalls already recorded stay until MMWatchdogReset.
void MMWatchdogStop(void);
BOOL MMWatchdogRunning(void);
/// YES in a debug build or with MINMACS_WATCHDOG=1, so MMMain starts it.
BOOL MMWatchdogWanted(NSDictionary<NSString *, NSString *> *env);

/// The stalls so far, oldest first, as {ms, cpuMs, readyMs, state, at, stack, what}. ms is the pass's wall time,
/// cpuMs the CPU main used in it, and readyMs the part of it main was ready to run and had no CPU, so ms less readyMs
/// is how long main held the pass. state is "waits" when main was blocked at the threshold, such as on disk or a
/// lock, and "runs" when it was on the CPU or ready for it. stack is main's frames at the threshold, innermost first, as
/// "image symbol + offset". what is the innermost frame in MinMacs's own code, or the innermost frame.
NSArray<NSDictionary *> *MMWatchdogStalls(void);
void MMWatchdogReset(void);
/// Passes the watchdog saw start, so a test can tell the observer runs.
NSUInteger MMWatchdogPasses(void);
