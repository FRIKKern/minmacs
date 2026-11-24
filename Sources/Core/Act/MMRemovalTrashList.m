// Issue #74: MinMacs's own list of what it sent to the Trash. A record in the log says where an item went, and a record
// can be written by anybody who can write the log, so a "trashed" entry is a claim. The file it names may be one the
// person trashed themselves, and its inode and volume can be read by anyone who can read the Trash. This list is the
// second witness, as a staging folder's .minmacs-items is for a staged item:
//
//   <support>/core/trashed/<rid>.json    {"items": [{from, to, ino, dev, vol}]}, one file for each record rid
//
// An entry is written before the item moves, with from and the identity it has there, and again after the move, with
// to and the identity it has in the Trash. A stop between the two leaves an entry with no to, which names nothing in
// the Trash. Once the item is back at from, its entry goes, so a record written again never takes the same file out
// of the Trash a second time. Nothing here moves or deletes a file: -[MMUndo trash:record:error:] moves an item there
// and -[MMUndo untrash:of:] back. This file only ever writes the list. A stop between the move and the record's note
// leaves an item only this list names, issue #113: MMRemovalTrashStranded.m reads it for that, and writes nothing.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Act/MMNotice.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#include <sys/stat.h>
#include <unistd.h>

/// The list's file for rid, or nil when rid is no name MinMacs gives a record: letters and digits only, so a record
/// can never name a file outside the list's folder.
static NSString *ListPath(NSString *rid) {
    if (!rid.length || rid.length > 64) return nil;
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"].invertedSet;
    if ([rid rangeOfCharacterFromSet:bad].location != NSNotFound) return nil;
    return [[MMExpertDir(@"core") stringByAppendingPathComponent:@"trashed"] stringByAppendingPathComponent:[rid stringByAppendingPathExtension:@"json"]];
}

/// YES when the lists' folder is a folder of this user's, or not there yet. A link there would send every list
/// wherever it points, issue #113, so then no list is read or written.
static BOOL FolderIsOurs(NSString *dir) {
    struct stat st;
    if (lstat(dir.fileSystemRepresentation, &st) != 0) return errno == ENOENT;
    return S_ISDIR(st.st_mode) && st.st_uid == getuid();
}

/// What the list at path holds: its entries, an empty list when there is no file, or nil when something is there that
/// is not a list MinMacs wrote: a link, a folder, a file of another user's, or text that is no list. One read that
/// never follows a link and never opens a pipe, MMReadOwnPlain, so nothing can take the name between a check and it.
static NSMutableArray<NSDictionary *> *Read(NSString *path) {
    if (!FolderIsOurs(path.stringByDeletingLastPathComponent)) return nil;
    int why = 0;
    NSData *data = MMReadOwnPlain(path, 4 << 20, &why);
    if (!data) return why == ENOENT ? [NSMutableArray new] : nil;
    id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![j isKindOfClass:NSDictionary.class] || ![((NSDictionary *)j)[@"items"] isKindOfClass:NSArray.class]) return nil;
    return [MMRecordList(j, @"items") mutableCopy];
}

static BOOL Write(NSString *path, NSArray<NSDictionary *> *items) {
    NSString *dir = path.stringByDeletingLastPathComponent;
    if (!FolderIsOurs(dir) || ![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
        !FolderIsOurs(dir)) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"items": items} options:NSJSONWritingWithoutEscapingSlashes error:nil];
    return data && [data writeToFile:path atomically:YES];
}

NSString *const MMRemovalTrashListUnwritten = @"MinMacs could not write its own list of what it sends to the Trash, so the item stays where it is";

NSString *MMRemovalTrashListCannot(void) {
    NSString *dir = [MMExpertDir(@"core") stringByAppendingPathComponent:@"trashed"];
    if (!FolderIsOurs(dir) || ![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
        !FolderIsOurs(dir)) return MMRemovalTrashListUnwritten;
    // A list is written as a new file in that folder renamed over the old one, which needs its write and search
    // bits, and a volume that takes writes. This file never makes or deletes a file to find that out.
    return access(dir.fileSystemRepresentation, W_OK | X_OK) == 0 ? nil : MMRemovalTrashListUnwritten;
}

void MMNoticeTrashUnwritten(NSString *expert, NSArray<NSString *> *paths, NSString *run) {
    NSUInteger n = paths.count;
    if (!n) return;
    BOOL groups = YES;
    for (NSString *p in paths) if ([p.lastPathComponent rangeOfString:@"*"].location == NSNotFound) { groups = NO; break; }
    NSString *noun = groups ? (n == 1 ? @"Group" : @"Groups") : (n == 1 ? @"Leftover" : @"Leftovers");
    NSString *title = [NSString stringWithFormat:@"Could Not Move %lu %@ to the Trash", (unsigned long)n, noun];
    NSString *text = [NSString stringWithFormat:@"MinMacs could not write its own list of what it sends to the Trash, so %@. %@ tried none of %@.",
                      n == 1 ? @"it stays where it is" : @"they stay where they are", run.length ? run : @"The run", n == 1 ? @"it" : @"them"];
    MMNotice(expert, title, text);
}

/// One lock for the lists of every record in this process. Each record has its own file, so two processes write the
/// same list only when both act on one record.
static NSObject *Lock(void) {
    static NSObject *o; static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [NSObject new]; });
    return o;
}

/// YES when the identity a and b give is the same: the inode, and the volume's UUID, or no UUID in both. The device
/// number is never compared, MMFileIdentity.
static BOOL SameFile(NSDictionary *a, NSDictionary *b) {
    NSNumber *i = MMRecordNumber(a, @"ino"), *j = MMRecordNumber(b, @"ino");
    NSString *v = MMRecordString(a, @"vol"), *w = MMRecordString(b, @"vol");
    return i && j && [i isEqualToNumber:j] && (v || w ? [v isEqualToString:w] : YES);
}

NSDictionary *MMRemovalTrashListNote(NSString *rid, NSString *from, NSString *to, NSDictionary *identity) {
    NSString *path = ListPath(rid);
    if (!path || !from.length || !MMRecordNumber(identity, @"ino")) return nil;
    @synchronized (Lock()) {
        NSMutableArray<NSDictionary *> *items = Read(path);
        if (!items) return nil;   // something MinMacs did not write holds that name: never written over
        NSMutableDictionary *entry = nil;
        NSUInteger at = NSNotFound;
        if (to.length) {
            // After the move: the entry written before it, for this old path, which names no place in the Trash yet.
            for (NSUInteger i = items.count; i-- > 0;)
                if ([MMRecordString(items[i], @"from") isEqualToString:from] && !MMRecordHas(items[i], @"to")) { at = i; break; }
            if (at == NSNotFound) return nil;
            entry = [items[at] mutableCopy];
            // A volume UUID the entry had stays when the read in the Trash gives none, so it never comes to match by
            // inode alone, as for .minmacs-items.
            NSString *vol = MMRecordString(entry, @"vol");
            [entry removeObjectsForKeys:@[@"ino", @"dev", @"vol"]];
            [entry addEntriesFromDictionary:identity];
            if (vol && !MMRecordString(identity, @"vol")) entry[@"vol"] = vol;
            entry[@"to"] = to;
            items[at] = entry;
        } else {
            entry = [@{@"from": from} mutableCopy];
            [entry addEntriesFromDictionary:identity];
            [items addObject:entry];
        }
        MM_TEST_STOP_TRASH("list-write");   // a check holds here and turns the folder into a link, issue #113
        if (!Write(path, items)) return nil;
        NSMutableDictionary *said = [NSMutableDictionary new];
        for (NSString *k in @[@"ino", @"dev", @"vol"]) if (entry[k]) said[k] = entry[k];
        return said;
    }
}

void MMRemovalTrashListDrop(NSString *rid, NSString *from, NSString *to) {
    NSString *path = ListPath(rid);
    if (!path || !from.length) return;
    @synchronized (Lock()) {
        NSMutableArray<NSDictionary *> *items = Read(path);
        NSUInteger before = items.count;
        NSIndexSet *gone = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *stop) {
            NSString *t = MMRecordString(e, @"to");
            return [MMRecordString(e, @"from") isEqualToString:from] && (to.length ? [t isEqualToString:to] : !MMRecordHas(e, @"to"));
        }];
        [items removeObjectsAtIndexes:gone];
        if (items && items.count != before) (void)Write(path, items);
    }
}

/// YES when path is spelled as a real path is: full, with no "." or ".." name in it and no slash at its end.
static BOOL Spelled(NSString *path) {
    if (![path hasPrefix:@"/"] || (path.length > 1 && [path hasSuffix:@"/"])) return NO;
    for (NSString *c in [path componentsSeparatedByString:@"/"]) if ([c isEqualToString:@".."] || [c isEqualToString:@"."]) return NO;
    return YES;
}

NSArray<NSDictionary *> *MMRemovalTrashListItems(NSString *rid, BOOL *unread) {
    if (unread) *unread = NO;
    NSString *path = ListPath(rid);
    if (!path) return nil;
    NSArray<NSDictionary *> *items = nil;
    @synchronized (Lock()) { items = Read(path); }
    // An entry MinMacs never writes: an old path that is no real path, no inode, or a Trash path that is no real
    // path. Then nothing in the list is believed.
    for (NSDictionary *e in items)
        if (!Spelled(MMRecordString(e, @"from")) || !MMRecordNumber(e, @"ino") || (MMRecordHas(e, @"to") && !Spelled(MMRecordString(e, @"to")))) { items = nil; break; }
    if (!items && unread) *unread = YES;
    return items;
}

NSString *MMRemovalTrashListWhyNot(NSString *rid, NSDictionary *entry) {
    NSString *from = MMRecordString(entry, @"from"), *to = MMRecordString(entry, @"to"), *path = ListPath(rid);
    // Issue #113: never to an old path with a "." or ".." name in it, whatever the record and the list say.
    if (from.length && !Spelled(from)) return @"its old path is not a real path";
    NSArray<NSDictionary *> *items = nil;
    if (path) @synchronized (Lock()) { items = Read(path); }
    for (NSDictionary *e in items)
        if (from.length && to.length && [MMRecordString(e, @"from") isEqualToString:from] && [MMRecordString(e, @"to") isEqualToString:to] && SameFile(e, entry)) return nil;
    return @"MinMacs's own list of what it sent to the Trash does not name it, so MinMacs does not move it";
}
