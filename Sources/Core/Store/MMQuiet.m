// Quiet holds. See MMQuiet.h.
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import "Core/Store/MMQuiet.h"
#import "Core/Act/MMAct.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"

NSString *const MMLogQuietTable = @"quiet";
static NSString *const kExpert = @"core";

static dispatch_queue_t QuietQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = MMQueue(@"core", @"quiet", QOS_CLASS_UTILITY); });
    return q;
}

static NSString *Dir(void) { return MMExpertDir(@"quiet"); }
static NSString *HoldsPath(void) { return [Dir() stringByAppendingPathComponent:@"holds.json"]; }

/// The process with this pid now, by its start time from the kernel. pid 0 when there is none or it is a zombie.
static MMProcKey KeyOf(pid_t pid) {
    MMProcKey k = { 0, 0 };
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (pid <= 0 || sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len != sizeof kp || kp.kp_proc.p_stat == SZOMB) return k;
    k.pid = pid; k.startSec = (uint64_t)kp.kp_proc.p_starttime.tv_sec;
    return k;
}
static MMProcKey SelfKey(void) {
    static MMProcKey k; static dispatch_once_t once;
    dispatch_once(&once, ^{ k = KeyOf(getpid()); });
    return k;
}
static MMProcKey KeyFrom(id s) {
    MMProcKey k = { 0, 0 };
    NSArray *parts = [s isKindOfClass:NSString.class] ? [s componentsSeparatedByString:@":"] : nil;
    if (parts.count == 2) { k.pid = (pid_t)[parts[0] intValue]; k.startSec = (uint64_t)[parts[1] longLongValue]; }
    return k;
}
static BOOL SameKey(MMProcKey a, MMProcKey b) { return a.pid == b.pid && a.startSec == b.startSec; }

#pragma mark - The file

/// The file's lock across processes, around each read, change and write of holds.json.
static int LockFile(void) {
    int fd = open([Dir() stringByAppendingPathComponent:@".lock"].fileSystemRepresentation, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (fd >= 0) flock(fd, LOCK_EX);
    return fd;
}
static void UnlockFile(int fd) { if (fd >= 0) { flock(fd, LOCK_UN); close(fd); } }

static NSObject *CacheLock(void) { static NSObject *o; static dispatch_once_t once; dispatch_once(&once, ^{ o = [NSObject new]; }); return o; }
static NSString *gStamp;
static NSDictionary *gParsed;

/// holds.json as key string to entry, parsed again only when the file changed. A file of another shape reads as none.
static NSDictionary<NSString *, NSDictionary *> *ReadHolds(void) {
    NSString *path = HoldsPath();
    struct stat st;
    NSString *stamp = stat(path.fileSystemRepresentation, &st) == 0
        ? [NSString stringWithFormat:@"%llu:%ld.%ld:%lld", (unsigned long long)st.st_ino, (long)st.st_mtimespec.tv_sec,
                                     st.st_mtimespec.tv_nsec, (long long)st.st_size] : @"-";
    @synchronized (CacheLock()) { if ([stamp isEqualToString:gStamp]) return gParsed; }
    NSData *d = [stamp isEqualToString:@"-"] ? nil : [NSData dataWithContentsOfFile:path];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    if ([j isKindOfClass:NSDictionary.class]) {
        id holds = j[@"holds"];
        if ([holds isKindOfClass:NSDictionary.class])
            for (id k in holds) if ([k isKindOfClass:NSString.class] && [holds[k] isKindOfClass:NSDictionary.class] && KeyFrom(k).pid > 1) out[k] = holds[k];
    }
    @synchronized (CacheLock()) { gStamp = stamp; gParsed = [out copy]; }
    return out;
}
static void WriteHolds(NSDictionary *holds) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"holds": holds ?: @{}} options:NSJSONWritingSortedKeys error:nil];
    [d writeToFile:HoldsPath() atomically:YES];
}

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

/// One row of the quiet table for a hold that ended.
static void LogEnd(NSString *ks, NSDictionary *entry, NSString *how, NSString *by) {
    MMProcKey k = KeyFrom(ks);
    NSDictionary *row = @{@"holdRid": Str(entry[@"rid"]) ?: @"", @"pid": @(k.pid), @"process": ks, @"reason": Str(entry[@"reason"]) ?: @"",
                          @"since": [entry[@"since"] isKindOfClass:NSNumber.class] ? entry[@"since"] : NSNull.null,
                          @"until": [how isEqualToString:@"gone"] ? NSNull.null : @(NSDate.date.timeIntervalSince1970),
                          @"how": how, @"by": by ?: @"unknown"};
    MMLogWhenOpen(^(MMLog *log) { [log append:MMLogQuietTable rid:nil expert:kExpert subject:ks state:@"ended" body:row]; });
}

#pragma mark - Holders

@interface MMQuietHolder ()
@property (readwrite) MMProcKey key, keeper;
@property (readwrite, copy) NSString *reason, *by, *rid;
@property (readwrite) NSDate *since;
@property (readwrite) BOOL awake;
@end
@implementation MMQuietHolder
- (NSDictionary *)json {
    return @{@"pid": @(self.key.pid), @"reason": self.reason ?: @"", @"since": @(round(self.since.timeIntervalSince1970)),
             @"by": self.by ?: @"", @"rid": self.rid ?: @"", @"awake": @(self.awake)};
}
@end

NSArray<MMQuietHolder *> *MMQuietHolders(void) {
    NSDictionary *holds = ReadHolds();
    NSMutableArray<MMQuietHolder *> *out = [NSMutableArray new];
    for (NSString *ks in holds) {
        MMProcKey k = KeyFrom(ks);
        if (!MMProcAlive(k)) continue;
        NSDictionary *e = holds[ks];
        MMQuietHolder *h = [MMQuietHolder new];
        h.key = k; h.reason = Str(e[@"reason"]) ?: @""; h.by = Str(e[@"by"]); h.rid = Str(e[@"rid"]);
        h.since = [NSDate dateWithTimeIntervalSince1970:[e[@"since"] doubleValue]];
        h.keeper = KeyFrom(e[@"keeper"]);
        h.awake = h.keeper.pid > 0 && MMProcAlive(h.keeper);
        [out addObject:h];
    }
    [out sortUsingComparator:^NSComparisonResult(MMQuietHolder *a, MMQuietHolder *b) { return [a.since compare:b.since]; }];
    return out;
}

NSString *MMQuietWhy(void) {
    NSArray<MMQuietHolder *> *hs = MMQuietHolders();
    if (!hs.count) return nil;
    MMQuietHolder *h = hs.firstObject;
    NSString *more = hs.count > 1 ? [NSString stringWithFormat:@", and %lu more", (unsigned long)hs.count - 1] : @"";
    return [NSString stringWithFormat:@"a quiet hold is active for %@ (pid %d)%@", h.reason.length ? h.reason : @"a task", h.key.pid, more];
}

#pragma mark - What this process keeps

/// One hold this process keeps: the two assertions and the exit watch on the held pid.
@interface MMQuietKeep : NSObject
@property MMProcKey key;
@property (copy) NSString *reason;
@property IOPMAssertionID system, display;
@property dispatch_source_t exit;
@end
@implementation MMQuietKeep
@end

static NSMutableDictionary<NSString *, MMQuietKeep *> *Kept(void) {
    static NSMutableDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
    return d;
}
static NSObject *KeptLock(void) { static NSObject *o; static dispatch_once_t once; dispatch_once(&once, ^{ o = [NSObject new]; }); return o; }

static void Drop(NSString *ks) {
    MMQuietKeep *k;
    @synchronized (KeptLock()) { k = Kept()[ks]; [Kept() removeObjectForKey:ks]; }
    if (!k) return;
    if (k.exit) dispatch_source_cancel(k.exit);
    if (k.system) IOPMAssertionRelease(k.system);
    if (k.display) IOPMAssertionRelease(k.display);
}

NSDictionary<NSString *, NSString *> *MMQuietKept(void) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    @synchronized (KeptLock()) { for (NSString *ks in Kept()) out[ks] = Kept()[ks].reason ?: @""; }
    return out;
}

/// A held process exited: its entry leaves the file with a row, and this process lets go of its assertions.
static void Exited(NSString *ks) {
    int fd = LockFile();
    NSMutableDictionary *holds = [ReadHolds() mutableCopy];
    NSDictionary *e = holds[ks];
    if (e) { [holds removeObjectForKey:ks]; WriteHolds(holds); }
    UnlockFile(fd);
    if (e) LogEnd(ks, e, @"exited", @"exit");
    Drop(ks);
}

/// Someone changed holds.json: a hold this process keeps that the file no longer gives it ends here too.
static void Reconcile(void) {
    NSDictionary *holds = ReadHolds();
    for (NSString *ks in MMQuietKept().allKeys) {
        NSDictionary *e = holds[ks];
        if (!e || !SameKey(KeyFrom(e[@"keeper"]), SelfKey())) Drop(ks);
    }
}

/// The kqueue watch on the quiet folder, started with the first hold this process keeps. A write there is a rename
/// of holds.json into place, so a release from another process reaches the keeper without a poll.
static void Watch(void) {
    static dispatch_source_t watch; static dispatch_once_t once;
    dispatch_once(&once, ^{
        int fd = open(Dir().fileSystemRepresentation, O_EVTONLY | O_CLOEXEC);
        if (fd < 0) return;
        watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
                                       DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, QuietQueue());
        dispatch_source_set_event_handler(watch, ^{ Reconcile(); });
        dispatch_source_set_cancel_handler(watch, ^{ close(fd); });
        dispatch_resume(watch);
    });
}

/// This process takes the assertions and the exit watch for key.
static void Keep(MMProcKey key, NSString *reason) {
    NSString *ks = MMProcKeyString(key);
    @synchronized (KeptLock()) {
        MMQuietKeep *old = Kept()[ks];
        if (old) return;
        MMQuietKeep *k = [MMQuietKeep new];
        k.key = key; k.reason = reason;
        NSString *name = [@"MinMacs keeps the Mac and the display awake for quiet: " stringByAppendingString:reason.length ? reason : @"a task"];
        IOPMAssertionID a = 0, b = 0;
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionLevelOn, (__bridge CFStringRef)name, &a);
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, (__bridge CFStringRef)name, &b);
        k.system = a; k.display = b;
        k.exit = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)key.pid, DISPATCH_PROC_EXIT, QuietQueue());
        dispatch_source_set_event_handler(k.exit, ^{ Exited(ks); });
        dispatch_resume(k.exit);
        Kept()[ks] = k;
    }
    Watch();
    // The process may have ended between the check and the watch. Then the watch never fires.
    if (!MMProcAlive(key)) dispatch_async(QuietQueue(), ^{ Exited(ks); });
}

/// Entries whose process ended while no MinMacs kept them: out of the file, each with a row of kind "gone".
/// Call with the file locked. Returns the holds left.
static NSMutableDictionary *Prune(NSMutableDictionary *holds, BOOL *changed) {
    for (NSString *ks in holds.allKeys) {
        if (MMProcAlive(KeyFrom(ks))) continue;
        MMProcKey keeper = KeyFrom(holds[ks][@"keeper"]);
        if (keeper.pid > 0 && MMProcAlive(keeper) && !SameKey(keeper, SelfKey())) continue;   // its keeper's exit watch ends it
        LogEnd(ks, holds[ks], SameKey(keeper, SelfKey()) ? @"exited" : @"gone", @"exit");
        [holds removeObjectForKey:ks];
        *changed = YES;
    }
    return holds;
}

#pragma mark - The action

/// The hold as an action, so it is checked fresh and has its record first, as Insomnia's hold has.
@interface MMQuietHoldAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property MMProcKey key;
@property (copy) NSString *reason, *by;
@end
@implementation MMQuietHoldAction
- (NSString *)kind { return @"quiet"; }
- (NSString *)recheck {
    if (self.key.pid <= 1) return @"pid 1 is never held";
    if (self.key.pid == getpid()) return @"MinMacs never holds itself";
    return nil;
}
- (NSString *)dryRun { return [NSString stringWithFormat:@"keeps quiet until pid %d exits: %@", self.key.pid, self.reason]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    NSString *ks = MMProcKeyString(self.key);
    [MMUndo.shared note:record payload:@{@"pid": @(self.key.pid), @"process": ks, @"reason": self.reason ?: @""}];
    int fd = LockFile();
    BOOL changed = NO;
    NSMutableDictionary *holds = Prune([ReadHolds() mutableCopy], &changed);
    holds[ks] = @{@"pid": @(self.key.pid), @"start": @(self.key.startSec), @"reason": self.reason ?: @"", @"by": self.by ?: @"",
                  @"since": @(round(NSDate.date.timeIntervalSince1970)), @"rid": record.rid ?: @"", @"keeper": MMProcKeyString(SelfKey())};
    WriteHolds(holds);
    UnlockFile(fd);
    Keep(self.key, self.reason);
    return YES;
}
@end

/// The one keep check: the pid must still be the same process by its start time, read from the kernel now.
@interface MMQuietPolicy : NSObject <MMExpertPolicy>
@end
@implementation MMQuietPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    MMProcKey k = KeyFrom(f.facts[@"process"]);
    if (k.pid <= 1) return @"cannot verify the process";
    return MMProcAlive(k) ? nil : @"that process has exited, or its pid is another process now";
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

NSString *MMQuietHold(pid_t pid, NSString *reason, NSString *by, NSString **rid) {
    if (rid) *rid = nil;
    if (NSThread.isMainThread) return @"it never runs on the main thread";
    if (pid <= 1) return @"pid 1 is never held";
    if (pid == getpid()) return @"MinMacs never holds itself";
    MMProcKey key = KeyOf(pid);
    if (key.pid <= 0) return [NSString stringWithFormat:@"no process with pid %d", pid];
    NSString *ks = MMProcKeyString(key);
    NSDictionary *have = ReadHolds()[ks];
    if (have && MMQuietKept()[ks]) { if (rid) *rid = Str(have[@"rid"]); return nil; }
    reason = reason.length ? reason : @"a task";
    MMQuietHoldAction *a = [MMQuietHoldAction new];
    a.key = key; a.reason = reason; a.by = by;
    NSString *title = [NSString stringWithFormat:@"Quiet for %@ (pid %d)", reason, pid];
    a.finding = [MMFinding expert:kExpert kind:@"quiet" stableKey:ks build:^(MMFindingBuilder *b) {
        b.title = title; b.facts = @{@"pid": @(pid), @"process": ks};
        b.proposal = [MMProposal verb:@"quiet" title:title reversibility:MMReversibleNotNeeded];
    }];
    NSString *err = nil;
    MMUndoRecord *r = MMRunAction(a, [MMQuietPolicy new], nil, by, reason, &err);
    if (!r || r.state != MMUndoDone) return err ?: r.error ?: @"it did not hold";
    if (rid) *rid = r.rid;
    return nil;
}

NSUInteger MMQuietRelease(pid_t pid, NSString *by) {
    int fd = LockFile();
    BOOL changed = NO;
    NSMutableDictionary *holds = Prune([ReadHolds() mutableCopy], &changed);
    NSMutableArray *ended = [NSMutableArray new];
    for (NSString *ks in holds.allKeys) if (KeyFrom(ks).pid == pid) { [ended addObject:@[ks, holds[ks]]]; [holds removeObjectForKey:ks]; }
    if (ended.count || changed) WriteHolds(holds);
    UnlockFile(fd);
    for (NSArray *x in ended) { LogEnd(x[0], x[1], @"released", by); Drop(x[0]); }
    return ended.count;
}

void MMQuietResume(void) {
    int fd = LockFile();
    BOOL changed = NO;
    NSMutableDictionary *holds = Prune([ReadHolds() mutableCopy], &changed);
    NSMutableArray *take = [NSMutableArray new];
    for (NSString *ks in holds.allKeys) {
        MMProcKey keeper = KeyFrom(holds[ks][@"keeper"]);
        if (keeper.pid > 0 && MMProcAlive(keeper) && !SameKey(keeper, SelfKey())) continue;   // another MinMacs keeps it
        NSMutableDictionary *e = [holds[ks] mutableCopy];
        e[@"keeper"] = MMProcKeyString(SelfKey());
        holds[ks] = e;
        changed = YES;
        [take addObject:@[ks, Str(e[@"reason"]) ?: @""]];
    }
    if (changed) WriteHolds(holds);
    UnlockFile(fd);
    for (NSArray *x in take) Keep(KeyFrom(x[0]), x[1]);
}
