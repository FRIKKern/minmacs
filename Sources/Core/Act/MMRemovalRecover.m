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
    // This very process: it may still work on the Wrap Up, so it is alive, whatever the record's age.
    if (pid == getpid()) return 1;
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

/// A record made recovery or the sweep raise: it is named with the others that cannot be read, once, and left.
static void Raised(MMUndoRecord *r, NSException *e) {
    if (!r.rid.length || [MMRemovalDamagedRecords() containsObject:r.rid]) return;
    os_log(os_log_create("no.guerrilla.minmacs", "removal"), "the record %{public}@ stopped a put-back and is left as it is: %{public}@", r.rid, e.reason ?: e.name ?: @"");
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

/// YES while what part r staged still waits: it lists staged items and was not put back. A restore keeps the list
/// and marks the record restored.
static BOOL StillHolds(MMUndoRecord *r) { return r.state != MMUndoRestored && MMRecordList(r.payload, @"staged").count > 0; }

/// The first damage among records, for the words of a Wrap Up that is failed.
static NSString *DamageOf(NSArray<MMUndoRecord *> *records) {
    for (MMUndoRecord *r in records) if (r.damage) return r.damage;
    return @"a part cannot be read";
}

static NSString *Items(NSUInteger n) { return [NSString stringWithFormat:@"%lu item%@", (unsigned long)n, n == 1 ? @"" : @"s"]; }

/// The error of a damaged Wrap Up that recovery fails, built only from what the records say: how many items went
/// back now, the parts that were restored before wasBack, and what had been deleted, from the parts' "deleted" lists
/// and the Wrap Up's "finishing". When a list or the flag cannot be read, it says so. A part that removed its thing
/// and can still bring it back, as a merged worktree that git recreates, is counted as that, never as deleted.
static NSString *DamagedWords(MMUndoRecord *parent, NSArray<MMUndoRecord *> *parts, NSSet<NSString *> *wasBack) {
    NSUInteger back = 0, gone = 0, kept = 0;
    // Only a true or false that MinMacs wrote says whether the deletes had begun. A number, even 0, says nothing.
    BOOL unknown = !parent.payload.count || (MMRecordHas(parent.payload, @"finishing") && !MMRecordIsFlag(parent.payload, @"finishing"));
    for (MMUndoRecord *given in parts) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid] ?: given;
        NSArray *deleted = MMRecordList(r.payload, @"deleted");
        if (MMRecordHas(r.payload, @"deleted") && !deleted) unknown = YES;
        NSUInteger n = MAX(deleted.count, r.deletedNow ? 1u : 0u);
        // Restore can still bring it back, or already did: that is no loss. A record that cannot be read restores nothing.
        if (n && (r.state == MMUndoRestored || (r.canRestore && !r.damage))) kept += r.state == MMUndoRestored ? 0 : n;
        else gone += n;
        if (r.state == MMUndoRestored && ![wasBack containsObject:r.rid]) back += MMRecordList(r.payload, @"staged").count + MMRecordList(r.payload, @"trashed").count;
    }
    NSString *moved = back ? [NSString stringWithFormat:@"%@ it had moved out of the worktree went back", Items(back)] : @"Nothing it had moved needed to go back";
    NSString *deleted = unknown ? @"Whether anything was deleted cannot be read from the record"
                      : gone ? [NSString stringWithFormat:@"%@ had already been deleted and cannot be brought back", Items(gone)]
                      : MMRecordFlag(parent.payload, @"finishing") ? @"Its deletes had begun, so an item may have been deleted before it stopped, and that cannot be brought back"
                      : kept ? @"Nothing was deleted that cannot be brought back" : @"Nothing was deleted";
    if (kept) deleted = [deleted stringByAppendingFormat:@". %@ it had removed can still come back with Restore", Items(kept)];
    return [NSString stringWithFormat:@"MinMacs stopped before this Wrap Up ended, and its record could not be read in full: %@. %@. %@",
            parent.damage ?: DamageOf(parts), moved, deleted];
}

/// Whatever lies in the two folders MinMacs would have made for the Wrap Up r, but for the folders' own files.
static NSArray<NSString *> *InFolders(MMUndoRecord *r) {
    NSMutableArray<NSString *> *folders = [NSMutableArray new], *at = [NSMutableArray new];
    NSString *support = MMRemovalRealPath(MMSupportDir()), *tree = MMRecordString(r.payload, @"path");
    if (support) [folders addObject:[[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:r.rid]];
    if (tree.length > 1) [folders addObject:[tree.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:r.rid]]];
    for (NSString *given in folders) {
        NSString *folder = MMRemovalRealPath(given);
        for (NSString *name in folder ? [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] : @[])
            if (!MMRemovalStagingOwnName(name)) [at addObject:[folder stringByAppendingPathComponent:name]];
    }
    return at;
}

/// What lies in the staging folders of the Wrap Up r that no "staged" list of its parts names now, sorted.
static NSArray<NSString *> *Unnamed(MMUndoRecord *r, NSArray<MMUndoRecord *> *parts) {
    NSMutableSet<NSString *> *named = [NSMutableSet new];
    for (MMUndoRecord *given in parts) {
        for (NSDictionary *x in MMRecordList(([MMUndo.shared record:given.rid] ?: given).payload, @"staged")) {
            NSString *to = MMRecordString(x, @"to");
            if (to) [named addObject:MMRemovalRealPath(to) ?: to];
        }
    }
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSString *path in InFolders(r)) if (![named containsObject:path]) [out addObject:path];
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

/// Only for a record with no owner: one this old, in seconds, does not run any more.
static NSTimeInterval OldAfter(void) {
    if (MMRemovalTestHome() && getenv("MINMACS_STAGE_RECOVER_AFTER")) return atof(getenv("MINMACS_STAGE_RECOVER_AFTER"));
    return 15 * 60;
}

NSInteger MMRemovalRecoverStaged(void) {
    NSTimeInterval old = OldAfter();
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
    for (MMUndoRecord *parent in pending) @try {
        NSArray<MMUndoRecord *> *parts = byParent[parent.rid] ?: @[];
        BOOL damaged = Damaged(parent, parts);
        // A Wrap Up whose process lives is never touched, whatever its age: that process still works on it. One whose
        // process is gone is settled at once, so a quick restart after a crash puts things back.
        int alive = MMRemovalOwnerAlive(parent);
        if (alive == 1 || (alive < 0 && -parent.at.timeIntervalSinceNow < old)) continue;
        // A Wrap Up whose state cannot be read may have ended, and git may have taken its worktree. Nothing of it is
        // moved back or failed: it stays pending, named, and MMRemovalWaiting lists what it staged.
        if (parent.stateUnread) continue;
        if (damaged) {
            // Nothing is deleted for a record that cannot be read. What a part moved aside goes back when that part's
            // body and lists read. A part whose do not is never written, and its Wrap Up stays pending.
            NSMutableArray<MMUndoRecord *> *readable = [NSMutableArray new];
            for (MMUndoRecord *part in parts) {
                if (part.moveDamage) continue;
                if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"MinMacs stopped before this part ended"];
                [readable addObject:part];
            }
            // What a part staged and its record never named, issue #75, is named now, so it goes back with the rest.
            for (MMUndoRecord *part in readable) (void)MMRemovalAdoptStranded(part, parent);
            NSMutableSet<NSString *> *wasBack = [NSMutableSet new];
            for (MMUndoRecord *part in readable) if ([MMUndo.shared record:part.rid].state == MMUndoRestored) [wasBack addObject:part.rid];
            NSString *notBack = readable.count ? MMRemovalPutBack(readable) : nil;
            // Once every part's items are back and nothing of it waits, the Wrap Up is failed, with words that say so.
            // While something still waits it stays pending, and `minmacs removal --waiting` shows where.
            BOOL waits = notBack != nil || readable.count < parts.count;
            for (MMUndoRecord *part in readable) if (StillHolds([MMUndo.shared record:part.rid])) waits = YES;
            if (waits) continue;
            [MMUndo.shared finish:parent ok:NO freed:0 error:DamagedWords(parent, parts, wasBack)];
            recovered++;
            continue;
        }
        // Only a true yes that MinMacs wrote counts as "the deletes had begun".
        if (MMRecordFlag(parent.payload, @"finishing")) {
            // Every part had gone through and the deletes had begun: the worktree is gone, so they are finished.
            for (MMUndoRecord *part in parts) (void)MMRemovalAdoptStranded(part, parent);
            int64_t freed = MMRemovalFinishStaged(parts);
            [MMUndo.shared finish:parent ok:YES freed:freed error:nil];
        } else {
            // It never got that far: nothing is deleted. A part that was still running is failed, so no record stays
            // pending. Then what the removal parts moved, to the staging folder or to the Trash, goes back.
            for (MMUndoRecord *part in parts)
                if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"MinMacs stopped before this part ended"];
            // It stopped between a rename into the staging folder and the record, issue #75: the folder's own list
            // names the item, and now its record does too, so it goes back with the rest.
            for (MMUndoRecord *part in parts) (void)MMRemovalAdoptStranded(part, parent);
            NSString *notBack = MMRemovalPutBack(parts);
            // The words say put back only of what went back. What still lies in its staging folder and no record
            // names is said too, with where it waits.
            NSMutableArray<NSString *> *except = [NSMutableArray new];
            if (notBack) [except addObject:notBack];
            NSArray<NSString *> *unnamed = Unnamed(parent, parts);
            if (unnamed.count) [except addObject:[NSString stringWithFormat:@"%@ that no record names still wait%@ in MinMacs's staging folder: %@",
                                                  Items(unnamed.count), unnamed.count == 1 ? @"s" : @"", [unnamed componentsJoinedByString:@", "]]];
            [MMUndo.shared finish:parent ok:NO freed:0 error:[NSString stringWithFormat:@"MinMacs stopped before this Wrap Up ended. What it had moved out of the worktree was put back%@",
                                                             except.count ? [@", except: " stringByAppendingString:[except componentsJoinedByString:@"; "]] : @""]];
        }
        recovered++;
    } @catch (NSException *e) {
        // A record that makes MinMacs raise is left as it is and named, and the others are still settled.
        Raised(parent, e);
    }
    return recovered;
}

#pragma mark - What was left staged

BOOL MMRemovalDeletesBegan(MMUndoRecord *parent, MMUndoRecord *part) {
    // Only a Wrap Up that is done and says so with a true yes, and only when neither record is damaged. Once the
    // person asked for an Undo, even one that could not finish, they want it back: its leftovers are never deleted.
    return parent && !parent.damage && !part.damage && parent.state == MMUndoDone && MMRecordFlag(parent.payload, @"finishing") &&
           !MMRecordFlag(parent.payload, @"undoAsked") && !MMRecordFlag(part.payload, @"undoAsked");
}

NSInteger MMRemovalSweepStaged(NSArray<NSString *> **orphans) {
    // 1. A part that still lists staged items though its Wrap Up ended: a put-back that stopped halfway, or a delete
    // that could not finish.
    NSMutableDictionary<NSString *, MMUndoRecord *> *all = [NSMutableDictionary new];
    NSMutableArray<MMUndoRecord *> *left = [NSMutableArray new];
    NSMutableSet<NSString *> *named = [NSMutableSet new];
    NSArray<MMUndoRecord *> *recent = [MMUndo.shared recent:nil limit:5000];
    for (MMUndoRecord *r in recent) all[r.rid] = r;
    for (MMUndoRecord *given in recent) {
        MMUndoRecord *r = given;
        // Every record that cannot be read is named once, also one whose parent or kind cannot be read.
        if (r.damage) NameDamaged(r);
        NSString *folder = MMRecordString(r.payload, @"stagedIn");
        // A part whose body or lists cannot be read is not acted on, and its folder is no orphan.
        if (r.moveDamage) { if (folder) [named addObject:folder]; continue; }
        if (!r.parentRid.length) continue;
        BOOL ended = r.state == MMUndoDone || r.state == MMUndoFailed;
        // An item its record never named though its Wrap Up ended, issue #75: the folder's own list names it, and
        // the record does from now on, so it is settled as any staged item.
        MMUndoRecord *parent = all[r.parentRid];
        if (ended && parent && parent.state != MMUndoPending && MMRemovalAdoptStranded(r, parent)) r = [MMUndo.shared record:r.rid] ?: r;
        if (MMRecordList(r.payload, @"staged").count && ended) [left addObject:r];
    }
    NSInteger settled = 0;
    for (MMUndoRecord *part in left) @try {
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
        // Counted only once nothing of it waits any more.
        if (!MMRemovalPutBack(@[part]) && !StillHolds([MMUndo.shared record:part.rid])) settled++;
        else if (folder) [named addObject:folder];
    } @catch (NSException *e) {
        Raised(part, e);
        NSString *folder = MMRecordString(part.payload, @"stagedIn");
        if (folder) [named addObject:folder];
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

#pragma mark - A Wrap Up whose state cannot be read
//
// Recovery leaves such a Wrap Up pending: it may have ended, and git may have taken its worktree, so nothing of it is
// moved back. The person moves what it staged by hand, MMRemovalWaiting says from where. After that only they can
// say it is over: MMRemovalCloseUnread fails the record. It moves no file and deletes none.

/// The parts of the Wrap Up rid, as the log holds them now.
static NSArray<MMUndoRecord *> *PartsOf(NSString *rid) {
    NSMutableArray<MMUndoRecord *> *parts = [NSMutableArray new];
    for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:0]) if ([r.parentRid isEqualToString:rid]) [parts addObject:r];
    return parts;
}

/// YES when r is a Wrap Up whose state cannot be read: no part itself, and a Wrap Up by its kind, or, when its kind
/// cannot be read either, by having parts.
static BOOL UnreadWrapUp(MMUndoRecord *r, NSArray<MMUndoRecord *> *parts) {
    return r && !r.parentRid.length && r.stateUnread && ([r.kind isEqualToString:@"wrapup"] || (!r.kind && parts.count));
}

/// Where items of the Wrap Up r still wait where MinMacs staged them, each path: what MMRemovalWaiting lists for it,
/// what its parts' lists name and is still there, and whatever else lies in the two folders MinMacs would have made
/// for it, also a file no record names.
static NSArray<NSString *> *StillStaged(MMUndoRecord *r, NSArray<MMUndoRecord *> *parts) {
    NSMutableSet<NSString *> *at = [NSMutableSet new];
    struct stat st;
    for (MMRemovalWaitingItem *i in MMRemovalWaiting()) if ([i.wrapUpRid isEqualToString:r.rid]) [at addObject:MMRemovalRealPath(i.stagedAt) ?: i.stagedAt];
    for (MMUndoRecord *part in parts) {
        if (part.state == MMUndoRestored) continue;
        for (NSDictionary *x in MMRecordList(part.payload, @"staged")) {
            NSString *to = MMRecordString(x, @"to");
            if (to.length && lstat(to.fileSystemRepresentation, &st) == 0) [at addObject:MMRemovalRealPath(to) ?: to];
        }
    }
    [at addObjectsFromArray:InFolders(r)];
    return [at.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *CloseWhyNot(MMUndoRecord *r, NSArray<MMUndoRecord *> *parts) {
    if (!r) return @"no record has that id";
    if (r.parentRid.length || !([r.kind isEqualToString:@"wrapup"] || (!r.kind && parts.count))) return @"it is not a Wrap Up";
    // One whose state reads is settled by MinMacs itself, at its next start, or has ended.
    if (!r.stateUnread) return r.state == MMUndoPending ? @"its state can be read, so MinMacs settles it by itself the next time it starts" : @"it has ended already";
    int alive = MMRemovalOwnerAlive(r);
    if (alive == 1) return @"its Wrap Up still runs";
    if (alive < 0 && -r.at.timeIntervalSinceNow < OldAfter()) return @"its Wrap Up may still run. Try again in 15 minutes";
    // Each path is named here, since --waiting lists only what a record names.
    NSArray<NSString *> *at = StillStaged(r, parts);
    NSUInteger n = at.count;
    if (n) return [NSString stringWithFormat:@"%@ of it still wait%@ in MinMacs's staging folder: %@. Move %@ by hand first",
                   Items(n), n == 1 ? @"s" : @"", [at componentsJoinedByString:@", "], n == 1 ? @"it" : @"each"];
    return nil;
}

NSString *MMRemovalCloseUnreadWhyNot(NSString *rid) {
    if (!rid.length) return @"no record has that id";
    return CloseWhyNot([MMUndo.shared record:rid], PartsOf(rid));
}

NSString *MMRemovalCloseUnread(NSString *rid) {
    if (!rid.length) return @"no record has that id";
    MMUndoRecord *r = [MMUndo.shared record:rid];
    NSArray<MMUndoRecord *> *parts = PartsOf(rid);
    NSString *no = CloseWhyNot(r, parts);
    if (no) return no;
    for (MMUndoRecord *part in parts) {
        // A part whose body or lists cannot be read is never written.
        if (part.moveDamage) continue;
        if (part.state == MMUndoPending) [MMUndo.shared finish:part ok:NO freed:0 error:@"Its Wrap Up was closed by hand before this part ended"];
        // Nothing its list names waits any more, StillStaged. The list is set aside under another name, so the sweep
        // never takes this part for one with something left to put back into a worktree that may be gone.
        NSArray *staged = MMRecordList(part.payload, @"staged");
        if (staged.count && part.state != MMUndoRestored) [MMUndo.shared note:[MMUndo.shared record:part.rid] payload:@{@"staged": @[], @"stagedBeforeClose": staged}];
    }
    [MMUndo.shared finish:r ok:NO freed:r.freedBytes error:@"Its state could not be read, so MinMacs did not settle it: it moved nothing back and deleted nothing for it. It was closed by hand with minmacs removal --waiting --close"];
    return nil;
}

NSArray<NSDictionary *> *MMRemovalUnreadWrapUps(void) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    NSMutableDictionary<NSString *, MMUndoRecord *> *seen = [NSMutableDictionary new];
    for (MMUndoRecord *r in [MMUndo.shared recent:nil limit:5000]) if (r.stateUnread && !r.parentRid.length) seen[r.rid] = r;
    // One older than that window is still named in core/damaged-records.json.
    for (NSString *rid in MMRemovalDamagedRecords()) {
        MMUndoRecord *r = seen[rid] ? nil : [MMUndo.shared record:rid];
        if (r.stateUnread && !r.parentRid.length) seen[rid] = r;
    }
    for (NSString *rid in [seen.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        MMUndoRecord *r = seen[rid];
        NSArray<MMUndoRecord *> *parts = PartsOf(rid);
        if (!UnreadWrapUp(r, parts)) continue;
        [out addObject:@{@"rid": rid, @"subject": r.subject ?: NSNull.null, @"waiting": @(StillStaged(r, parts).count), @"problem": CloseWhyNot(r, parts) ?: NSNull.null}];
    }
    return out;
}
