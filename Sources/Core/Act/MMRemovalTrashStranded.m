// The removal choice, MMRemoval.h: an item MinMacs sent to the Trash that its record does not name, issue #113.
// -[MMUndo trash:record:error:] writes MinMacs's own list of what a record sent to the Trash, MMRemovalTrashList.m,
// before the move, moves, writes the list again with the Trash path, and only then the record's entry. A stop in
// between leaves the item in the Trash, named only by that list:
//
//   it stopped                    the list holds              the item is                 named here
//   before the move               from, its id at from        at from                     not at all: it never left
//   after the move                from, its id at from        in the Trash, under a name  at that name, found by its id
//   after the list's second write from, to, its id there      at to                       at to, the very file by its id
//   any of these, then it moved   either                      at neither place            as not known where it is
//
// The id is the inode and the volume's UUID, MMFileIsEntry, never a name alone. Read only: nothing here moves,
// deletes or writes a file or a record. --waiting lists what it finds and recovery's words say it, so the person
// puts it back from the Trash. Recovery never moves it, since the list would then be the only witness for a move out
// of the Trash, and anyone who can write the support folder can write the list.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#include <sys/stat.h>
#include <unistd.h>

/// The paths a fresh finding asked of r, spelled as -[MMUndo trash:record:error:] spells the item it moves.
static NSSet<NSString *> *Asked(MMUndoRecord *r) {
    NSMutableSet<NSString *> *out = [NSMutableSet new];
    for (NSString *a in MMRecordStrings(r.payload, @"asked") ?: @[]) if ([a hasPrefix:@"/"]) [out addObject:[NSURL fileURLWithPath:a].path];
    return out;
}

/// YES when path lies directly in a Trash, by its real path: in a check, only in the test home's own, MMPathLiesInTrash.
static BOOL LiesInTrash(NSString *path) {
    NSString *real = MMRemovalRealPath(path), *test = MMTrashFolder();
    return real && MMPathLiesInTrash(real, MMRemovalRealPath(NSHomeDirectory()), getuid(), test ? (MMRemovalRealPath(test) ?: @"") : nil);
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

/// Where the very file entry e names lies directly in a Trash now, or nil. Its "to" first, then each name directly in
/// the Trash folders of its old path, by inode and volume UUID. *several is YES when more than one name there has its
/// id, as two names of one hard-linked file have: then none is named, since MinMacs cannot tell which it moved.
static NSString *FoundInTrash(NSDictionary *e, BOOL *several) {
    *several = NO;
    NSString *to = MMRecordString(e, @"to");
    if (to.length && MMFileIsEntry(to, e) == 1 && LiesInTrash(to)) return to;
    // With no volume UUID an inode alone says nothing across a whole folder.
    NSNumber *ino = MMRecordNumber(e, @"ino");
    if (!ino || !MMRecordString(e, @"vol")) return nil;
    NSMutableArray<NSString *> *found = [NSMutableArray new];
    for (NSString *trash in TrashesFor(MMRecordString(e, @"from"))) {
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:trash error:nil]) {
            NSString *p = [trash stringByAppendingPathComponent:name];
            struct stat st;
            if (lstat(p.fileSystemRepresentation, &st) != 0 || (unsigned long long)st.st_ino != ino.unsignedLongLongValue) continue;
            if (MMFileIsEntry(p, e) == 1 && LiesInTrash(p) && ![found containsObject:p]) [found addObject:p];
        }
    }
    *several = found.count > 1;
    return found.count == 1 ? found.firstObject : nil;
}

NSArray<NSDictionary *> *MMRemovalTrashStranded(MMUndoRecord *r, BOOL *unread) {
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
    NSMutableSet<NSString *> *named = [NSMutableSet new];
    for (NSDictionary *x in MMRecordList(r.payload, @"trashed")) if (MMRecordString(x, @"from")) [named addObject:MMRecordString(x, @"from")];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    for (NSDictionary *e in items) {
        NSString *from = MMRecordString(e, @"from");
        // Its record names it, or the very file is at its old path: the move never ran, or it is back.
        if ([named containsObject:from] || MMFileIsEntry(from, e) == 1) continue;
        BOOL several = NO;
        NSString *at = FoundInTrash(e, &several);
        NSMutableDictionary *x = [@{@"from": from, @"stranded": @YES} mutableCopy];
        for (NSString *k in @[@"ino", @"dev"]) if (MMRecordNumber(e, k)) x[k] = MMRecordNumber(e, k);
        if (MMRecordString(e, @"vol")) x[@"vol"] = MMRecordString(e, @"vol");
        if (at) x[@"to"] = at;
        else if (several) x[@"several"] = @YES;
        [out addObject:x];
    }
    return out;
}

static NSString *Count(NSUInteger n) { return [NSString stringWithFormat:@"%lu item%@", (unsigned long)n, n == 1 ? @"" : @"s"]; }

NSString *MMRemovalTrashStrandedWords(NSArray<MMUndoRecord *> *parts) {
    NSMutableArray<NSString *> *there = [NSMutableArray new], *several = [NSMutableArray new], *unknown = [NSMutableArray new];
    BOOL unread = NO;
    for (MMUndoRecord *given in parts) {
        BOOL bad = NO;
        for (NSDictionary *x in MMRemovalTrashStranded([MMUndo.shared record:given.rid] ?: given, &bad)) {
            NSString *from = x[@"from"], *to = x[@"to"];
            if (to) [there addObject:[NSString stringWithFormat:@"%@, from %@", to, from]];
            else if (MMRecordFlag(x, @"several")) [several addObject:from];
            else [unknown addObject:from];
        }
        unread = unread || bad;
    }
    NSMutableArray<NSString *> *said = [NSMutableArray new];
    NSUInteger n = there.count;
    if (n) [said addObject:[NSString stringWithFormat:@"%@ it had sent to the Trash, which no record names, %@ still there: %@",
                            Count(n), n == 1 ? @"is" : @"are", [there componentsJoinedByString:@"; "]]];
    n = several.count;
    if (n) [said addObject:[NSString stringWithFormat:@"%@ it had sent to the Trash, which no record names, %@ more than one name in the Trash, so MinMacs names none: from %@",
                            Count(n), n == 1 ? @"has" : @"have", [several componentsJoinedByString:@", "]]];
    n = unknown.count;
    if (n) [said addObject:[NSString stringWithFormat:@"%@ it had sent to the Trash, which no record names, %@ not where MinMacs left %@, and it is not known where %@: from %@",
                            Count(n), n == 1 ? @"is" : @"are", n == 1 ? @"it" : @"them", n == 1 ? @"it is" : @"they are", [unknown componentsJoinedByString:@", "]]];
    if (unread) [said addObject:@"MinMacs's own list of what it sent to the Trash cannot be read, or names a path its record never asked about, so MinMacs cannot say whether something it sent there is still in the Trash"];
    return said.count ? [said componentsJoinedByString:@"; "] : nil;
}

#ifdef MM_TESTS
void MMRemovalTestStopTrash(const char *point) {
    const char *at = getenv("MINMACS_TEST_STOP_TRASH");
    if (at && point && !strcmp(at, point) && MMRemovalTestHome()) _exit(0);
}
#endif
