// The removal choice, MMRemoval.h: what a staging folder holds about itself, and what its own list says of an item
// no record names. Nothing here moves or deletes a person's file: MMRemovalApply.m does both, behind the one check
// MMRemovalStagedItemWhyNot. Every field of a record is read through the checked reader of MMUndo.h.
//
//   <staging folder>/
//     .minmacs          the rid of its Wrap Up, so a folder of that name MinMacs did not make is never taken for one
//     .gitignore        "*", so a repo that holds the folder never lists it
//     .minmacs-items    {<its name in the folder>: {from, part, ino, dev, vol}}, written before the item moves in, and
//                       again after, issue #79, when the file has another id at its new place
//     0.node_modules    an item
//
// The list is written before the rename, issue #75, so at every moment an item is either where it was, or in the
// folder and named in its list with its old path. A record in the log says where an item was, and a record can be
// written by anybody who can write the log. The folder's own list is what a put-back and a delete believe.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <sys/stat.h>

static NSString *const kMarker = @".minmacs", *const kIgnore = @".gitignore", *const kIgnoreSays = @"*\n";
static NSString *const kItems = @".minmacs-items";

BOOL MMRemovalStagingOwnName(NSString *name) {
    return [name isEqualToString:kMarker] || [name isEqualToString:kIgnore] || [name isEqualToString:kItems];
}

/// YES when path is a plain file of this user's, never a link or a folder.
static BOOL OwnFile(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid();
}

NSDictionary *MMRemovalStagingItems(NSString *folder) {
    NSString *path = [folder stringByAppendingPathComponent:kItems];
    if (!OwnFile(path)) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [j isKindOfClass:NSDictionary.class] ? j : nil;
}

/// Writes all as the folder's list. Something else under that name, or a list nobody can read, is never written over.
static BOOL WriteItems(NSString *folder, NSDictionary *all) {
    NSString *path = [folder stringByAppendingPathComponent:kItems];
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) == 0 && !MMRemovalStagingItems(folder)) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:all options:0 error:nil];
    return data && [data writeToFile:path atomically:YES];
}

BOOL MMRemovalStagingNoteItem(NSString *folder, NSString *to, NSString *from, NSString *rid, NSDictionary *identity) {
    NSMutableDictionary *all = [MMRemovalStagingItems(folder) mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *entry = [@{@"from": from, @"part": rid} mutableCopy];
    [entry addEntriesFromDictionary:identity ?: @{}];
    all[to.lastPathComponent] = entry;
    return WriteItems(folder, all);
}

BOOL MMRemovalStagingNoteIdentity(NSString *folder, NSString *name, NSDictionary *identity) {
    NSMutableDictionary *all = [MMRemovalStagingItems(folder) mutableCopy];
    NSMutableDictionary *entry = [MMRecordDict(all, name) mutableCopy];
    if (!entry || !MMRecordNumber(identity, @"ino")) return NO;
    // Where it was and which part staged it stay as they were written before the item moved.
    [entry removeObjectsForKeys:@[@"ino", @"dev", @"vol"]];
    [entry addEntriesFromDictionary:identity];
    all[name] = entry;
    return WriteItems(folder, all);
}

NSString *MMRemovalStagingListsAnother(NSString *stagedAt) {
    NSString *t = MMRemovalRealPath(stagedAt ?: @"");
    NSDictionary *e = t ? MMRecordDict(MMRemovalStagingItems(t.stringByDeletingLastPathComponent), t.lastPathComponent) : nil;
    BOOL unread = NO;
    // Only when the list says which file it means and the one there is not it. A UUID that cannot be read says neither.
    if (!e || MMFileIsEntryCheck(t, e, &unread) != 0 || unread) return nil;
    return MMRecordString(e, @"from");
}

void MMRemovalStagingForgetItem(NSString *folder, NSString *name) {
    NSMutableDictionary *all = [MMRemovalStagingItems(folder) mutableCopy];
    if (!all[name]) return;
    [all removeObjectForKey:name];
    (void)WriteItems(folder, all);
}

BOOL MMRemovalStagingMarkerSays(NSString *folder, NSString *rid) {
    NSString *m = [folder stringByAppendingPathComponent:kMarker];
    if (!OwnFile(m)) return NO;
    return [[NSString stringWithContentsOfFile:m encoding:NSUTF8StringEncoding error:nil] isEqualToString:rid];
}

BOOL MMRemovalStagingOwnFilesAreOurs(NSString *folder) {
    struct stat st;
    // No .gitignore, or the one MinMacs wrote: a plain file of ours that says exactly "*". A folder of that name, a
    // link, or a file that says anything else is not MinMacs's.
    NSString *g = [folder stringByAppendingPathComponent:kIgnore];
    if (lstat(g.fileSystemRepresentation, &st) != 0) { if (errno != ENOENT) return NO; }
    else if (!OwnFile(g) || ![[NSString stringWithContentsOfFile:g encoding:NSUTF8StringEncoding error:nil] isEqualToString:kIgnoreSays]) return NO;
    // Its own list of items the same way: a plain file of ours, or none.
    NSString *items = [folder stringByAppendingPathComponent:kItems];
    return lstat(items.fileSystemRepresentation, &st) == 0 ? OwnFile(items) : errno == ENOENT;
}

BOOL MMRemovalStagingMake(NSString *folder, NSString *rid) {
    NSString *marker = [folder stringByAppendingPathComponent:kMarker], *ignore = [folder stringByAppendingPathComponent:kIgnore];
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil] ||
        (!MMRemovalStagingMarkerSays(folder, rid) && ![rid writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil])) return NO;
    // A repo that holds this folder, as a main checkout holds .worktrees/, never lists it as untracked.
    struct stat st;
    if (lstat(ignore.fileSystemRepresentation, &st) != 0) [kIgnoreSays writeToFile:ignore atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return YES;
}

NSString *MMRemovalStagingWhyNot(NSString *item, NSString *folder, NSString *rid, NSString *support) {
    if (!rid.length || !folder.length || !item.length) return @"cannot verify whose staging folder it is";
    BOOL own = support.length && [folder isEqualToString:[[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:rid]];
    BOOL beside = [folder.lastPathComponent isEqualToString:[@".minmacs-staged-" stringByAppendingString:rid]];
    if (!own && !beside) return @"its folder is not the staging folder of this Wrap Up";
    if (![item.stringByDeletingLastPathComponent isEqualToString:folder]) return @"it does not lie directly in the staging folder";
    return nil;
}

/// The real path of folder when it is a staging folder of the Wrap Up rid with MinMacs's marker in it, else nil.
static NSString *Ours(NSString *folder, NSString *rid) {
    NSString *f = folder.length ? MMRemovalRealPath(folder) : nil;
    if (!f || MMRemovalStagingWhyNot([f stringByAppendingPathComponent:kMarker], f, rid, MMRemovalRealPath(MMSupportDir())) || !MMRemovalStagingMarkerSays(f, rid)) return nil;
    return f;
}

NSString *MMRemovalStagingFolderOf(MMUndoRecord *r) {
    NSString *f = MMRemovalRealPath(MMRecordString(r.payload, @"stagedIn") ?: @"");
    if (!f) return nil;
    // A record whose parent cannot be read: the folder's own name says which Wrap Up made it, and its marker must agree.
    NSString *rid = r.parentRid, *name = f.lastPathComponent, *beside = @".minmacs-staged-";
    if (!rid.length) rid = [name hasPrefix:beside] ? [name substringFromIndex:beside.length] : name;
    return Ours(f, rid);
}

#pragma mark - An item no record names, issue #75

/// The folders where part r's items may wait: its "stagedIn" when the record has one, else the two MinMacs would have
/// made for its Wrap Up, <support>/staged/<rid> and .minmacs-staged-<rid> beside its worktree.
static NSArray<NSString *> *FoldersOf(MMUndoRecord *r, MMUndoRecord *parent) {
    if (MMRecordHas(r.payload, @"stagedIn")) { NSString *f = MMRemovalStagingFolderOf(r); return f ? @[f] : @[]; }
    NSString *rid = r.parentRid, *support = MMRemovalRealPath(MMSupportDir());
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    NSString *own = support ? Ours([[support stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:rid], rid) : nil;
    if (own) [out addObject:own];
    NSString *tree = MMRecordString((parent ?: [MMUndo.shared record:rid]).payload, @"path");
    NSString *beside = tree.length > 1 ? Ours([tree.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:rid]], rid) : nil;
    if (beside && ![out containsObject:beside]) [out addObject:beside];
    return out;
}

NSArray<NSDictionary *> *MMRemovalStranded(MMUndoRecord *r, MMUndoRecord *parent) {
    // Only a part of a Wrap Up that was asked to remove something stages, and only one whose lists read is read here.
    if (!r.parentRid.length || r.moveDamage || !MMRecordHas(r.payload, @"asked")) return @[];
    NSMutableSet<NSString *> *named = [NSMutableSet new];
    for (NSDictionary *x in MMRecordList(r.payload, @"staged")) {
        NSString *to = MMRecordString(x, @"to");
        if (!to) continue;
        [named addObject:to];
        if (MMRemovalRealPath(to)) [named addObject:MMRemovalRealPath(to)];
    }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    for (NSString *f in FoldersOf(r, parent)) {
        NSDictionary *items = MMRemovalStagingItems(f);
        for (NSString *name in [items.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *e = MMRecordDict(items, name);
            NSString *from = MMRecordString(e, @"from"), *to = [f stringByAppendingPathComponent:name];
            struct stat st;
            // Only what this part staged, by the list's own word, that is a name directly in the folder and is there.
            if (![MMRecordString(e, @"part") isEqualToString:r.rid] || !from.length || !name.length || [name containsString:@"/"] ||
                [name isEqualToString:@"."] || [name isEqualToString:@".."] || MMRemovalStagingOwnName(name) || [named containsObject:to] ||
                lstat(to.fileSystemRepresentation, &st) != 0) continue;
            NSMutableDictionary *x = [@{@"from": from, @"to": to, @"stranded": @YES,
                                        @"why": @"its record did not name it, so its staging folder's own list says where it was"} mutableCopy];
            for (NSString *k in @[@"ino", @"dev"]) if (MMRecordNumber(e, k)) x[k] = MMRecordNumber(e, k);
            if (MMRecordString(e, @"vol")) x[@"vol"] = MMRecordString(e, @"vol");
            [out addObject:x];
        }
    }
    return out;
}

NSUInteger MMRemovalAdoptStranded(MMUndoRecord *given, MMUndoRecord *parent) {
    if (!MMRemovalStranded(given, parent).count) return 0;
    @synchronized (MMUndo.shared) {
        MMUndoRecord *r = [MMUndo.shared record:given.rid];
        MMUndoRecord *p = [MMUndo.shared record:r.parentRid];
        // Never while the process that runs its Wrap Up lives: it may be about to write that very entry itself. Never
        // into a record that cannot be read, or one restored already, and never for a Wrap Up that has no record.
        if (!r || r.moveDamage || r.state == MMUndoRestored || !p) return 0;
        if (p.state == MMUndoPending && MMRemovalOwnerAlive(p) == 1) return 0;
        NSMutableArray<NSDictionary *> *add = [NSMutableArray new];
        NSString *in = MMRemovalRealPath(MMRecordString(r.payload, @"stagedIn") ?: @"");
        for (NSDictionary *x in MMRemovalStranded(r, p)) {
            NSString *to = x[@"to"], *folder = to.stringByDeletingLastPathComponent;
            if (in && ![folder isEqualToString:in]) continue;
            // The one check every staged item passes before MinMacs moves or deletes it: the folder MinMacs made for
            // this Wrap Up, whose own list says this part staged this very file, by inode and volume UUID.
            if (MMRemovalStagedItemWhyNot(r, to)) continue;
            in = in ?: folder;
            [add addObject:x];
        }
        if (!add.count) return 0;
        NSMutableArray *staged = [MMRecordList(r.payload, @"staged") mutableCopy] ?: [NSMutableArray new];
        [staged addObjectsFromArray:add];
        NSMutableDictionary *more = [@{@"staged": staged} mutableCopy];
        if (!MMRecordHas(r.payload, @"stagedIn")) more[@"stagedIn"] = in;
        [MMUndo.shared note:r payload:more];
        return add.count;
    }
}
