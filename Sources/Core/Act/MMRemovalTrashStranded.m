// The removal choice, MMRemoval.h: an item MinMacs sent to the Trash, or was sending there, that no record names,
// issue #113. -[MMUndo trash:record:error:] writes MinMacs's own list of what a record sent to the Trash,
// MMRemovalTrashList.m, before the move, moves, writes the list again with the Trash path, and only then the record's
// entry. A stop in between leaves an entry only that list names:
//
//   it stopped                    the list holds          so MinMacs knows                 it looks for the file
//   before the move               from, its id at from    only that it was sending it      at from, then in the Trash
//   after the move                from, its id at from    the same: the list cannot tell   at from, then in the Trash
//   after the list's second write from, to, its id there  that it had sent it to the Trash at from, at to, then the Trash
//
// Each look ends one of three ways: the very file is there, by inode and volume UUID, never by a name alone; MinMacs
// looked and it is not; or MinMacs could not look, as when the Trash refuses a look without Full Disk Access. Only
// the second says "not there". The words say each of these as it is. An item found where a record names it, this
// one's or any other's, at that Trash path with that id, is that record's and left out here. A record whose Undo ran
// names nothing any more: the same file sent to the same Trash name again is no longer its.
// Read only: nothing here moves, deletes or writes a file or a record. --waiting lists what is found in the Trash, and
// recovery's words say all of it, so the person puts it back from the Trash. Recovery never moves it, since the list
// would then be the only witness for a move out of the Trash, and anyone who can write the support folder can write it.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#include <sys/stat.h>
#include <unistd.h>

static const int kThere = 1, kNotThere = 0, kUnlooked = -1;
static NSString *const kRefused = @"the Trash could not be read, so MinMacs cannot say whether it is there. macOS may refuse a look in the Trash without Full Disk Access";

/// The paths a fresh finding asked of r, spelled as -[MMUndo trash:record:error:] spells the item it moves.
static NSSet<NSString *> *Asked(MMUndoRecord *r) {
    NSMutableSet<NSString *> *out = [NSMutableSet new];
    for (NSString *a in MMRecordStrings(r.payload, @"asked") ?: @[]) if ([a hasPrefix:@"/"]) [out addObject:[NSURL fileURLWithPath:a].path];
    return out;
}

/// The id of the file an entry names, as text: its inode and its volume's UUID, or its device when it has no UUID.
static NSString *IdKey(NSDictionary *e) {
    NSNumber *ino = MMRecordNumber(e, @"ino"), *dev = MMRecordNumber(e, @"dev");
    NSString *vol = MMRecordString(e, @"vol");
    if (!ino || (!vol && !dev)) return nil;
    return vol ? [NSString stringWithFormat:@"%@ %@", ino, vol] : [NSString stringWithFormat:@"%@ dev %@", ino, dev];
}

/// A Trash path and an id together, as MMRemovalTrashNamed holds them.
static NSString *Named(NSString *to, NSString *key) { return [NSString stringWithFormat:@"%@ at %@", key, to]; }

NSSet<NSString *> *MMRemovalTrashNamed(NSArray<MMUndoRecord *> *records) {
    NSMutableSet<NSString *> *out = [NSMutableSet new];
    for (MMUndoRecord *r in records) {
        if (r.state == MMUndoRestored) continue;
        for (NSDictionary *x in MMRecordList(r.payload, @"trashed")) {
            NSString *to = MMRecordString(x, @"to"), *key = IdKey(x);
            if (to.length && key) [out addObject:Named(to, key)];
        }
    }
    return out;
}

/// Whether the very file e names is at path: kThere, kNotThere once MinMacs looked and it is not, or kUnlooked when
/// the look was refused or the id cannot be told.
static int At(NSString *path, NSDictionary *e) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return errno == ENOENT || errno == ENOTDIR ? kNotThere : kUnlooked;
    BOOL unread = NO;
    int same = MMFileIsEntryCheck(path, e, &unread);
    return same == 1 ? kThere : same < 0 || unread ? kUnlooked : kNotThere;
}

/// Whether the file at path lies directly in a Trash, by its real path: in a check, only in the test home's own.
static int InATrash(NSString *path) {
    NSString *real = MMRemovalRealPath(path), *test = MMTrashFolder();
    if (!real) return kUnlooked;
    return MMPathLiesInTrash(real, MMRemovalRealPath(NSHomeDirectory()), getuid(), test ? (MMRemovalRealPath(test) ?: @"") : nil) ? kThere : kNotThere;
}

/// The Trash folders an item that was at from can lie in now: in a check the test home's own alone, else the
/// person's Trash, and the Trash of from's volume when from lies under /Volumes.
static NSArray<NSString *> *TrashesFor(NSString *from) {
    NSString *test = MMTrashFolder();
    if (test) return @[test];
    NSMutableArray<NSString *> *out = [@[[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"]] mutableCopy];
    NSArray<NSString *> *names = [from componentsSeparatedByString:@"/"];   // "", Volumes, <volume>, ...
    if (names.count > 3 && [names[1] isEqualToString:@"Volumes"] && names[2].length)
        [out addObject:[NSString stringWithFormat:@"/Volumes/%@/.Trashes/%u", names[2], (unsigned)getuid()]];
    return out;
}

/// Where the very file e names lies in a Trash. Its "to" first, then each name directly in the Trash folders of its
/// old path. Sets x's "to" when exactly one name has its id, "several" when more than one has, as two names of one
/// hard-linked file do, and "unlooked" with why when a look was refused or its id cannot be matched in a folder.
static void LookInTrash(NSDictionary *e, NSMutableDictionary *x) {
    NSString *to = MMRecordString(e, @"to");
    NSString *refused = nil;
    if (to.length) {
        int at = At(to, e);
        if (at == kThere) at = InATrash(to);
        if (at == kThere) { x[@"to"] = to; return; }
        if (at == kUnlooked) refused = kRefused;
    }
    // With no volume UUID an inode alone says nothing across a whole folder.
    NSNumber *ino = MMRecordNumber(e, @"ino");
    if (!MMRecordString(e, @"vol")) {
        x[@"unlooked"] = refused ?: @"its volume gives no id MinMacs can match in the Trash, so MinMacs cannot say whether it is there";
        return;
    }
    NSMutableArray<NSString *> *found = [NSMutableArray new];
    for (NSString *trash in TrashesFor(MMRecordString(e, @"from"))) {
        struct stat st;
        if (lstat(trash.fileSystemRepresentation, &st) != 0) {
            // A volume with no Trash of this user's has nothing in it. Any other answer is a refused look.
            if (errno != ENOENT) refused = refused ?: kRefused;
            continue;
        }
        NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:trash error:nil];
        if (!names) { refused = refused ?: kRefused; continue; }
        for (NSString *name in names) {
            NSString *p = [trash stringByAppendingPathComponent:name];
            // A folder that lists its names and refuses a look at each, as one with no search right does.
            if (lstat(p.fileSystemRepresentation, &st) != 0) { if (errno != ENOENT) refused = refused ?: kRefused; continue; }
            if ((unsigned long long)st.st_ino != ino.unsignedLongLongValue) continue;
            // By its real path: a Trash folder that is a link to elsewhere is no Trash.
            if (At(p, e) == kThere && InATrash(p) == kThere && ![found containsObject:p]) [found addObject:p];
        }
    }
    if (found.count == 1) x[@"to"] = found.firstObject;
    else if (found.count > 1) x[@"several"] = @YES;
    else if (refused) x[@"unlooked"] = refused;
}

NSArray<NSDictionary *> *MMRemovalTrashStranded(MMUndoRecord *r, NSSet<NSString *> *named, BOOL *unread) {
    if (unread) *unread = NO;
    // Only a removal, which lists what a fresh finding asked for first, and only one whose lists read.
    if (!r.rid.length || r.moveDamage || !MMRecordHas(r.payload, @"removal")) return @[];
    NSSet<NSString *> *asked = Asked(r);
    if (!asked.count) return @[];
    BOOL bad = NO;
    NSArray<NSDictionary *> *items = MMRemovalTrashListItems(r.rid, &bad);
    if (!items.count) { if (unread) *unread = bad; return @[]; }
    // A list that names an old path this record never asked about was not written for it: nothing in it is believed.
    for (NSDictionary *e in items) if (![asked containsObject:MMRecordString(e, @"from")]) { if (unread) *unread = YES; return @[]; }
    NSSet<NSString *> *names = named ?: MMRemovalTrashNamed(@[r]);
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    for (NSDictionary *e in items) {
        NSString *from = MMRecordString(e, @"from"), *key = IdKey(e);
        NSMutableDictionary *x = [@{@"from": from, @"stranded": @YES} mutableCopy];
        // Only once the list names a Trash path did the move happen. Before that, MinMacs was only sending it.
        if (!MMRecordHas(e, @"to")) x[@"sending"] = @YES;
        int home = At(from, e);
        // The very file at its old path: the move never ran, or it is back.
        if (home == kThere) continue;
        LookInTrash(e, x);
        // A record names that very file where it lies: issue #113's second review, as when the person put it back
        // and a later record sent it to the Trash again.
        if (x[@"to"] && key && [names containsObject:Named(x[@"to"], key)]) continue;
        if (home == kUnlooked && !x[@"to"] && !x[@"several"] && !x[@"unlooked"])
            x[@"unlooked"] = @"its old path could not be read, so MinMacs cannot say where it is";
        for (NSString *k in @[@"ino", @"dev"]) if (MMRecordNumber(e, k)) x[k] = MMRecordNumber(e, k);
        if (MMRecordString(e, @"vol")) x[@"vol"] = MMRecordString(e, @"vol");
        [out addObject:x];
    }
    return out;
}

NSString *MMRemovalTrashStrandedWords(NSArray<MMUndoRecord *> *parts) {
    NSSet<NSString *> *named = MMRemovalTrashNamed([MMUndo.shared recent:nil limit:5000]);
    NSMutableArray<NSString *> *said = [NSMutableArray new];
    BOOL unread = NO;
    for (MMUndoRecord *given in parts) {
        BOOL bad = NO;
        for (NSDictionary *x in MMRemovalTrashStranded([MMUndo.shared record:given.rid] ?: given, named, &bad)) {
            NSString *from = x[@"from"], *to = x[@"to"];
            NSString *what = MMRecordFlag(x, @"sending") ? [NSString stringWithFormat:@"MinMacs was sending %@ to the Trash when it stopped, and no record names it", from]
                                                        : [NSString stringWithFormat:@"MinMacs had sent %@ to the Trash, and no record names it", from];
            NSString *where = to ? [NSString stringWithFormat:@"it is in the Trash at %@", to]
                            : MMRecordFlag(x, @"several") ? @"more than one name in the Trash has its id, so MinMacs names none"
                            : MMRecordString(x, @"unlooked") ?: @"MinMacs finds it neither at its old path nor in the Trash";
            [said addObject:[NSString stringWithFormat:@"%@: %@", what, where]];
        }
        unread = unread || bad;
    }
    if (unread) [said addObject:@"MinMacs's own list of what it sent to the Trash cannot be read, or names a path its record never asked about, so MinMacs cannot say whether something it sent there is still in the Trash"];
    return said.count ? [said componentsJoinedByString:@"; "] : nil;
}

#ifdef MM_TESTS
void MMRemovalTestStopTrash(const char *point) {
    const char *at = getenv("MINMACS_TEST_STOP_TRASH");
    if (at && point && !strcmp(at, point) && MMRemovalTestHome()) _exit(0);
}
#endif
