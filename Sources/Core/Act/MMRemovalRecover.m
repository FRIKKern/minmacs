// The removal choice, MMRemoval.h: what happens after MinMacs stopped in the middle of a Wrap Up, and what an ended
// Wrap Up left staged. Nothing here deletes a file itself: it calls MMRemovalFinishStaged and MMRemovalPutBack of
// MMRemovalApply.m. Every field of a record is read through the checked reader of MMUndo.h, and a record that
// cannot be read is skipped, named once in the log, and never acted on.
#import <os/log.h>
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#import "Core/Senses/MMSenses.h"
#include <signal.h>
#include <sys/stat.h>
#include <sys/sysctl.h>

#pragma mark - Whose Wrap Up it is

/// When the process pid began, in seconds since 1970 with its fraction, or 0 when that cannot be read.
static double StartOf(pid_t pid) {
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (pid <= 0 || sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || !len) return 0;
    return (double)kp.kp_proc.p_starttime.tv_sec + (double)kp.kp_proc.p_starttime.tv_usec / 1e6;
}

NSDictionary *MMRemovalOwner(void) {
    return @{@"pid": @(getpid()), @"start": @((uint64_t)StartOf(getpid()))};
}

int MMRemovalOwnerAlive(MMUndoRecord *parent) {
    NSDictionary *o = MMRecordDict(parent.payload, @"owner");
    NSNumber *pidN = MMRecordNumber(o, @"pid");
    if (!pidN || (o[@"start"] && !MMRecordNumber(o, @"start"))) return -1;
    pid_t pid = pidN.intValue;
    if (pid <= 0) return -1;
    uint64_t start = MMRecordNumber(o, @"start").unsignedLongLongValue;
    if (start) return MMProcAlive((MMProcKey){ pid, start }) ? 1 : 0;
    // The start time could not be read when the Wrap Up began, so only the pid can be asked.
    if (kill(pid, 0) != 0) {
        // Gone. Or a process of another user, which is no MinMacs of this person: then the record's age decides.
        return errno == EPERM ? -1 : 0;
    }
    // A process that began after the record was written may have taken the pid since. Or it is the owner, and the
    // clock moved back between its start and the record, or the gap is within the clock's own error. A live pid is
    // never read as gone on that alone: the record's age decides, as for a record with no owner.
    double began = StartOf(pid);
    if (began > 0 && began > parent.at.timeIntervalSince1970) return -1;
    return 1;
}

#pragma mark - Records that cannot be read

static NSString *const kDamagedFile = @"damaged-records";

NSArray<NSString *> *MMRemovalDamagedRecords(void) {
    id seen = [[MMStateFile fileNamed:kDamagedFile expert:@"core"] read];
    return MMRecordStrings(@{@"seen": seen ?: @[]}, @"seen") ?: @[];
}

/// Names a record that cannot be read, once: the first time in the log, and from then on only in the state file.
static void NameDamaged(MMUndoRecord *r) {
    if (!r.rid.length || [MMRemovalDamagedRecords() containsObject:r.rid]) return;
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "removal"); });
    os_log(log, "the record %{public}@ cannot be read and is left as it is: %{public}@", r.rid, r.damage ?: @"");
    [[MMStateFile fileNamed:kDamagedFile expert:@"core"] update:^id(id disk) {
        NSMutableArray *all = [MMRecordStrings(@{@"seen": disk ?: @[]}, @"seen") mutableCopy] ?: [NSMutableArray new];
        if (![all containsObject:r.rid]) [all addObject:r.rid];
        return all;
    }];
}

/// YES when the Wrap Up or one of its parts cannot be read. Each such record is named.
static BOOL Damaged(MMUndoRecord *parent, NSArray<MMUndoRecord *> *parts) {
    BOOL any = NO;
    for (MMUndoRecord *r in [@[parent] arrayByAddingObjectsFromArray:parts ?: @[]]) if (r.damage) { NameDamaged(r); any = YES; }
    return any;
}

#pragma mark - After a crash

NSInteger MMRemovalRecoverStaged(void) {
    // Only for a record with no owner: one this old does not run any more.
    NSTimeInterval old = 15 * 60;
    if (MMRemovalTestHome() && getenv("MINMACS_STAGE_RECOVER_AFTER")) old = atof(getenv("MINMACS_STAGE_RECOVER_AFTER"));
    NSMutableArray<MMUndoRecord *> *candidates = [NSMutableArray new], *pending = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<MMUndoRecord *> *> *byParent = [NSMutableDictionary new];
    for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:5000]) {
        if (r.parentRid.length) [(byParent[r.parentRid] ?: (byParent[r.parentRid] = [NSMutableArray new])) addObject:r];
        else if (r.state == MMUndoPending) [candidates addObject:r];
    }
    // A Wrap Up, or a pending record with parts whose kind cannot be read, which may be one.
    for (MMUndoRecord *r in candidates)
        if ([r.kind isEqualToString:@"wrapup"] || (!r.kind && r.damage && byParent[r.rid].count)) [pending addObject:r];
    NSInteger recovered = 0;
    for (MMUndoRecord *parent in pending) {
        NSArray<MMUndoRecord *> *parts = byParent[parent.rid] ?: @[];
        BOOL damaged = Damaged(parent, parts);
        // A Wrap Up whose process lives is never touched, whatever its age: that process still works on it. One whose
        // process is gone is settled at once, so a quick restart after a crash puts things back.
        int alive = MMRemovalOwnerAlive(parent);
        if (alive == 1 || (alive < 0 && -parent.at.timeIntervalSinceNow < old)) continue;
        if (damaged) {
            // A record that cannot be read is never finished, and nothing is deleted for it. Its Wrap Up stays pending
            // until a person looks. What a part moved aside still goes back when that part's body and lists read.
            NSMutableArray<MMUndoRecord *> *readable = [NSMutableArray new];
            for (MMUndoRecord *part in parts) {
                if (part.moveDamage) continue;
                if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"MinMacs stopped before this part ended"];
                [readable addObject:part];
            }
            if (readable.count) (void)MMRemovalPutBack(readable);
            continue;
        }
        // Only a true yes that MinMacs wrote counts as "the deletes had begun".
        if (MMRecordFlag(parent.payload, @"finishing")) {
            // Every part had gone through and the deletes had begun: the worktree is gone, so they are finished.
            int64_t freed = MMRemovalFinishStaged(parts);
            [MMUndo.shared finish:parent ok:YES freed:freed error:nil];
        } else {
            // It never got that far: nothing is deleted. A part that was still running is failed, so no record stays
            // pending. Then what the removal parts moved, to the staging folder or to the Trash, goes back.
            for (MMUndoRecord *part in parts)
                if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"MinMacs stopped before this part ended"];
            NSString *notBack = MMRemovalPutBack(parts);
            [MMUndo.shared finish:parent ok:NO freed:0 error:[NSString stringWithFormat:@"MinMacs stopped before this Wrap Up ended. What it had moved out of the worktree was put back%@",
                                                             notBack ? [@", except: " stringByAppendingString:notBack] : @""]];
        }
        recovered++;
    }
    return recovered;
}

#pragma mark - What was left staged

BOOL MMRemovalDeletesBegan(MMUndoRecord *parent, MMUndoRecord *part) {
    // Only a Wrap Up that is done and says so with a true yes, and only when neither record is damaged.
    return parent && !parent.damage && !part.damage && parent.state == MMUndoDone && MMRecordFlag(parent.payload, @"finishing");
}

NSInteger MMRemovalSweepStaged(NSArray<NSString *> **orphans) {
    // 1. A part that still lists staged items though its Wrap Up ended: a put-back that stopped halfway, or a delete
    // that could not finish.
    NSMutableDictionary<NSString *, MMUndoRecord *> *all = [NSMutableDictionary new];
    NSMutableArray<MMUndoRecord *> *left = [NSMutableArray new];
    NSMutableSet<NSString *> *named = [NSMutableSet new];
    for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:5000]) {
        all[r.rid] = r;
        // Every record that cannot be read is named once, also one whose parent or kind cannot be read.
        if (r.damage) NameDamaged(r);
        NSString *folder = MMRecordString(r.payload, @"stagedIn");
        // A part whose body or lists cannot be read is not acted on, and its folder is no orphan.
        if (r.moveDamage) { if (folder) [named addObject:folder]; continue; }
        if (!r.parentRid.length) continue;
        if (MMRecordList(r.payload, @"staged").count && (r.state == MMUndoDone || r.state == MMUndoFailed)) [left addObject:r];
    }
    NSInteger settled = 0;
    for (MMUndoRecord *part in left) {
        MMUndoRecord *parent = all[part.parentRid];
        NSString *folder = MMRecordString(part.payload, @"stagedIn");
        // A Wrap Up that still runs, or that recovery has yet to settle, is not this sweep's.
        if (parent && parent.state == MMUndoPending) { if (folder) [named addObject:folder]; continue; }
        if (MMRemovalDeletesBegan(parent, part)) {
            // The Wrap Up went through and git took the worktree: putting the item back would make the worktree's
            // folder again for it. Its delete is tried once more, behind the same wall, and then it waits and is listed.
            if (MMRecordFlag(part.payload, @"sweepTried")) { if (folder) [named addObject:folder]; continue; }
            [MMUndo.shared note:part payload:@{@"sweepTried": @YES}];
            (void)MMRemovalFinishStaged(@[part]);
            if (!MMRecordList([MMUndo.shared record:part.rid].payload, @"staged").count) settled++;
            else if (folder) [named addObject:folder];
            continue;
        }
        // It failed, was restored, cannot be found or cannot be read: the record names each item's old path, so each
        // goes back there. Nothing is deleted.
        if (parent.damage) NameDamaged(parent);
        if (!MMRemovalPutBack(@[part])) settled++;
        else if (folder) [named addObject:folder];
    }
    // 2. A folder under <support>/staged that no record names: left alone, and named once.
    NSString *root = [MMRemovalRealPath(MMSupportDir()) stringByAppendingPathComponent:@"staged"];
    MMStateFile *seen = [MMStateFile fileNamed:@"staged-orphans" expert:@"core"];
    NSArray *before = MMRecordStrings(@{@"seen": [seen read] ?: @[]}, @"seen") ?: @[];
    NSMutableArray<NSString *> *fresh = [NSMutableArray new], *now = [NSMutableArray new];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *folder = [root stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(folder.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode) || [named containsObject:folder]) continue;
        MMUndoRecord *parent = all[name];
        if (parent && (parent.state == MMUndoPending || parent.damage)) continue;
        // Empty but for what MinMacs wrote: nothing waits in it, so it goes. Otherwise nobody knows whose files these are.
        MMRemovalDropEmptyStagingFolder(folder, name);
        if (lstat(folder.fileSystemRepresentation, &st) != 0) continue;
        [now addObject:folder];
        if (![before containsObject:folder]) [fresh addObject:folder];
    }
    if (![now isEqualToArray:before]) [seen update:^id(id disk) { return now; }];
    if (orphans) *orphans = fresh;
    return settled;
}
