// The rest of the memory, by kind: what no server, agent, app or helper row holds, as a few calm categories, issue
// "memory rest". The ring's other slice was one gray arc and the list said nothing of it. Here each process that no
// group claimed gets one category from a table, MMRestTable.m, by its name, then by where it runs from, then by its
// parent: macOS, Spotlight, Siri, iCloud, a browser's helpers, developer tools and the rest.
//
// What it costs, D11: nothing while the window is closed. It reads the sample MinMacs already took, never samples,
// and is asked only by the window's feed and by `minmacs window`. A process's category is kept by pid and start time,
// so a process is looked up once in its life. Its path is read once, and only when its name does not say it. What a
// story shows of one process, its parent, who launched it and since when, is read only while that story shows.
//
// macOS runs many of its own processes as other users, root among them. Their memory cannot be read without root,
// and no tick runs ps, invariant 4, so they are counted and named but not measured. The macOS category holds them and
// what no process holds: the kernel, wired and compressed memory. Its size is what the rest leaves when the other
// categories took theirs, so the categories always add up to the ring's other slice.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"

@class MMPerformance;

NS_ASSUME_NONNULL_BEGIN

/// The category keys, in the table's order. Everything else is last wherever it stands.
extern NSString *const MMRestMacOS, *const MMRestDesktop, *const MMRestSpotlight, *const MMRestSiri, *const MMRestMedia,
    *const MMRestCloud, *const MMRestApple, *const MMRestBrowsers, *const MMRestDeveloper, *const MMRestSecurity, *const MMRestElse;

/// One category as the table holds it: its key, its plain name and one plain sentence of what it is.
@interface MMRestKind : NSObject
@property (readonly, copy) NSString *key, *title, *about;
@end

/// Every category, in the table's order, Everything else last.
NSArray<MMRestKind *> *MMRestKinds(void);
/// The category of this key, or nil.
MMRestKind *_Nullable MMRestKindOf(NSString *key);

/// What the table says of one process: its category and the plain name a person knows it by, such as "Spotlight
/// index" for mds_stores, or nil where its own name is the plain one.
typedef struct { __unsafe_unretained NSString *key; __unsafe_unretained NSString *_Nullable human; BOOL needsPath; } MMRestAnswer;

/// The table, from a process's name alone: its p_comm, at most 16 characters. needsPath is YES when the name does not
/// decide, and the path must be asked. Pure, so a test reads the table with real names.
MMRestAnswer MMRestByName(NSString *name);
/// The table with the path too, and the parent's name for one the path does not decide. `mine` is NO for a process
/// another user runs, which is macOS's own when nothing else says. Pure.
MMRestAnswer MMRestClassify(NSString *name, NSString *_Nullable path, NSString *_Nullable parentName, BOOL mine);
/// What a process that fits no other kind is named by: its app's folder, "Zoom", for one inside an app bundle, else
/// its parent's name, else its folder. nil when nothing says.
NSString *_Nullable MMRestOwnerByPath(NSString *_Nullable path);

/// One process of the rest.
@interface MMRestProc : NSObject
@property (readonly) pid_t pid, ppid;
@property (readonly) uint64_t startSec;
@property (readonly) uid_t uid;
@property (readonly, copy) NSString *name;              // p_comm, the raw name
@property (readonly, copy, nullable) NSString *human;   // the table's plain name, else nil
@property (readonly) uint64_t bytes;                    // phys_footprint; 0 when not measured
@property (readonly) BOOL measured;                     // NO for a process of another user: its memory cannot be read
@property (readonly) double cpuPercent;                 // below 0 when not known
/// The plain name to show: human, else the raw name.
@property (readonly) NSString *shownName;
@end

/// One category with its processes, biggest first, the measured ones before the rest.
@interface MMRestCategory : NSObject
@property (readonly) MMRestKind *kind;
/// Its size: the measured processes' footprints. macOS's adds what the rest leaves, `unheld`.
@property (readonly) uint64_t bytes;
/// What no measured process holds: macOS's own, kernel, wired and compressed, and its other users' processes. 0 elsewhere.
@property (readonly) uint64_t unheld;
@property (readonly) double cpuPercent;                 // the measured processes' sum, of one core
@property (readonly) NSArray<MMRestProc *> *procs;
@property (readonly) NSInteger unmeasured;              // processes in it whose memory cannot be read
@end

/// The pids that a server, agent, helper or app row already holds, as the ring claims them: each server, agent and
/// helper finding's process trees, and every process that rolls up into an app row, by its responsible app or its
/// nearest app ancestor. The rest is every other pid.
NSSet<NSNumber *> *MMRestClaimed(MMPerformance *p, MMSample *sample);

/// Reads one process's path. nil reads it with proc_pidpath. A check passes a block of its own.
typedef NSString *_Nullable (^MMRestPathReader)(pid_t pid);

/// The categories of the processes no row claims, with their sizes. `rest` is the ring's other part: what memory in
/// use holds that no group does. Busiest first, Everything else last, and only categories that hold something.
/// Each process is looked up in the kept table by pid and start time, and only a new one is classified.
NSArray<MMRestCategory *> *MMRestBuild(MMSample *sample, NSSet<NSNumber *> *claimed, uint64_t rest, MMRestPathReader _Nullable path);

/// How many processes the kept table knows, and how many paths it ever read, for the bench and the checks.
typedef struct { NSUInteger kept, classified, pathsRead; } MMRestCounts;
MMRestCounts MMRestCountsNow(void);
/// Forgets the kept table. For the checks.
void MMRestForget(void);

/// The details of one process for its story, read now: its path, its parent's name and pid, the app macOS holds
/// responsible for it when that is not itself, and its start. Asked only while a category's story shows.
/// Keys: path, parent, parentPid, launchedBy, startSec. A missing fact is left out.
NSDictionary *MMRestDetails(MMSample *sample, pid_t pid, MMRestPathReader _Nullable path);

#ifdef MM_TESTS
/// The reader a nil reader means, for the checks, whose fake pids may be real processes on the Mac. nil goes back to
/// proc_pidpath.
void MMRestUsePathReader(MMRestPathReader _Nullable reader);
#endif

NS_ASSUME_NONNULL_END
