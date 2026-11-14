// The removal choice, MMRemoval.h: what still waits in a staging folder that MinMacs cannot settle by itself, and the
// person's two ways out, delete it now or put it back. Nothing here deletes or moves a file itself: the one delete is
// MMRemovalDeleteStagedItem and the one move is MMRemovalPutBackStagedItem, both in MMRemovalApply.m. Every field of a
// record is read through the checked reader of MMUndo.h.
#import "Core/Act/MMRemoval.h"
#import "Core/Act/MMUndo.h"
#include <fts.h>
#include <sys/stat.h>

@interface MMRemovalWaitingItem ()
@property (readwrite, copy) NSString *itemID, *name, *oldPath, *stagedAt, *detail, *wrapUpRid, *partRid;
@property (readwrite) int64_t bytes;
@property (readwrite) MMRemovalWaitWhy why;
@property (readwrite) BOOL canDelete, canPutBack;
@end

@implementation MMRemovalWaitingItem
- (NSString *)whyWords {
    switch (self.why) {
        case MMRemovalWaitDeleteFailed: return @"could not be deleted";
        case MMRemovalWaitOldPathTaken: return @"its old place is taken";
        case MMRemovalWaitPutBackFailed: return @"could not go back";
        case MMRemovalWaitDamaged: return @"its record is damaged";
    }
    return @"its record is damaged";
}
- (NSString *)whyWord { return @[@"delete-failed", @"old-path-taken", @"put-back-failed", @"damaged"][self.why]; }
- (NSDictionary *)json {
    id (^or)(id) = ^id(id v) { return v ?: NSNull.null; };
    return @{@"id": self.itemID, @"name": self.name ?: @"", @"oldPath": or(self.oldPath), @"stagedAt": self.stagedAt, @"bytes": @(self.bytes),
             @"why": self.whyWord, @"whyWords": self.whyWords, @"detail": or(self.detail), @"wrapUp": or(self.wrapUpRid), @"part": self.partRid,
             @"canDelete": @(self.canDelete), @"canPutBack": @(self.canPutBack)};
}
@end

/// What the item at path takes on its disk, every name inside counted, never following a link or leaving the volume.
static int64_t BytesIn(NSString *path) {
    char *argv[] = { (char *)path.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return 0;
    int64_t sum = 0;
    for (FTSENT *e; (e = fts_read(fts));)
        if (e->fts_info != FTS_DP && e->fts_statp) sum += (int64_t)e->fts_statp->st_blocks * 512;
    fts_close(fts);
    return sum;
}
static BOOL There(NSString *path) { struct stat st; return path.length && lstat(path.fileSystemRepresentation, &st) == 0; }
/// YES when to lies directly in folder, a staging folder MMRemovalStagingFolderOf accepted.
static BOOL In(NSString *folder, NSString *to) {
    NSString *t = MMRemovalRealPath(to);
    return folder && t && [t.stringByDeletingLastPathComponent isEqualToString:folder];
}

static MMRemovalWaitingItem *Item(MMUndoRecord *part, NSString *to, NSString *from) {
    MMRemovalWaitingItem *i = [MMRemovalWaitingItem new];
    NSString *staged = to.lastPathComponent;
    NSRange dot = [staged rangeOfString:@"."];
    i.itemID = [NSString stringWithFormat:@"%@:%@", part.rid, staged];
    i.name = from.lastPathComponent ?: (dot.location != NSNotFound ? [staged substringFromIndex:dot.location + 1] : staged);
    i.oldPath = from; i.stagedAt = to; i.partRid = part.rid; i.wrapUpRid = part.parentRid;
    i.bytes = BytesIn(to);
    return i;
}

NSArray<MMRemovalWaitingItem *> *MMRemovalWaiting(void) {
    NSMutableArray<MMUndoRecord *> *records = [[MMUndo.shared recent:nil limit:5000] mutableCopy];
    NSMutableDictionary<NSString *, MMUndoRecord *> *all = [NSMutableDictionary new];
    for (MMUndoRecord *r in records) all[r.rid] = r;
    // A damaged record older than the window is still named in core/damaged-records.json.
    for (NSString *rid in MMRemovalDamagedRecords()) {
        MMUndoRecord *r = all[rid] ? nil : [MMUndo.shared record:rid];
        if (r) { all[rid] = r; [records addObject:r]; }
    }
    NSMutableArray<MMRemovalWaitingItem *> *out = [NSMutableArray new];
    NSMutableSet<NSString *> *claimed = [NSMutableSet new];
    NSMutableArray<MMUndoRecord *> *unread = [NSMutableArray new];
    for (MMUndoRecord *r in records) {
        NSArray<NSDictionary *> *staged = MMRecordList(r.payload, @"staged");
        if (r.moveDamage) {
            // Its body or its lists cannot be read: MinMacs does not act on it. What it names is listed, and what else
            // waits in its folder is found there.
            NSString *folder = MMRemovalStagingFolderOf(r);
            for (NSDictionary *x in staged) {
                NSString *to = MMRecordString(x, @"to");
                if (!to) continue;
                [claimed addObject:to]; if (MMRemovalRealPath(to)) [claimed addObject:MMRemovalRealPath(to)];
                if (!There(to) || !In(folder, to)) continue;
                MMRemovalWaitingItem *i = Item(r, to, MMRecordString(x, @"from"));
                i.why = MMRemovalWaitDamaged; i.detail = r.moveDamage;
                [out addObject:i];
            }
            if (MMRecordString(r.payload, @"stagedIn")) [unread addObject:r];
            continue;
        }
        if (!r.parentRid.length || !staged.count) continue;
        MMUndoRecord *parent = all[r.parentRid] ?: [MMUndo.shared record:r.parentRid];
        BOOL damaged = r.damage || parent.damage, running = parent.state == MMUndoPending && parent != nil;
        BOOL began = MMRemovalDeletesBegan(parent, r), ended = r.state == MMUndoDone || r.state == MMUndoFailed;
        NSString *folder = MMRemovalStagingFolderOf(r);
        for (NSDictionary *x in staged) {
            NSString *to = MMRecordString(x, @"to"), *from = MMRecordString(x, @"from");
            if (!to) continue;
            [claimed addObject:to]; if (MMRemovalRealPath(to)) [claimed addObject:MMRemovalRealPath(to)];
            // A Wrap Up that still runs, or that recovery settles at the next start, is not listed. Nor is what does
            // not lie in this Wrap Up's own staging folder: a record names it, but MinMacs never put it there.
            if ((running && !damaged) || !There(to) || !In(folder, to)) continue;
            MMRemovalWaitingItem *i = Item(r, to, from);
            i.why = damaged ? MMRemovalWaitDamaged : began ? MMRemovalWaitDeleteFailed : There(from) ? MMRemovalWaitOldPathTaken : MMRemovalWaitPutBackFailed;
            i.detail = damaged ? (r.damage ?: parent.damage) : MMRecordString(x, @"why");
            i.canDelete = !damaged && !running && ended;
            i.canPutBack = !running && ended && from != nil;
            [out addObject:i];
        }
    }
    // What waits in the folder of a record that cannot be read and that no readable entry names.
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (MMUndoRecord *r in unread) {
        // Only a folder MinMacs made for a Wrap Up, its marker inside. A record that names a folder of the person's
        // own, such as Documents, lists nothing from it.
        NSString *folder = MMRemovalStagingFolderOf(r);
        if (!folder || [seen containsObject:folder]) continue;
        [seen addObject:folder];
        for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *to = [folder stringByAppendingPathComponent:name];
            if ([name isEqualToString:@".minmacs"] || [name isEqualToString:@".gitignore"] || [claimed containsObject:to]) continue;
            MMRemovalWaitingItem *i = Item(r, to, nil);
            i.why = MMRemovalWaitDamaged; i.detail = r.moveDamage;
            [out addObject:i];
        }
    }
    return out;
}

MMRemovalWaitingItem *MMRemovalWaitingFind(NSString *itemID) {
    if (!itemID.length) return nil;
    for (MMRemovalWaitingItem *i in MMRemovalWaiting()) if ([i.itemID isEqualToString:itemID]) return i;
    return nil;
}

/// "its Wrap Up still runs" when the process that runs item's Wrap Up lives, else nil.
static NSString *Runs(MMRemovalWaitingItem *i) {
    MMUndoRecord *parent = i.wrapUpRid.length ? [MMUndo.shared record:i.wrapUpRid] : nil;
    return parent && parent.state == MMUndoPending && MMRemovalOwnerAlive(parent) == 1 ? @"its Wrap Up still runs" : nil;
}

NSString *MMRemovalDeleteWaitingWhyNot(MMRemovalWaitingItem *i) {
    if (!i) return @"nothing waits under that id";
    if (i.canDelete) return nil;
    NSString *runs = Runs(i);
    if (runs) return runs;
    if (i.why != MMRemovalWaitDamaged) return @"its Wrap Up has not ended";
    return i.oldPath ? [NSString stringWithFormat:@"its record is damaged, so MinMacs does not delete it. Put it back, or move it by hand from %@", i.stagedAt]
                     : [NSString stringWithFormat:@"its record is damaged and does not say what it is, so MinMacs does not delete it. Move it by hand from %@", i.stagedAt];
}

NSString *MMRemovalPutBackWaitingWhyNot(MMRemovalWaitingItem *i, NSString *path) {
    if (!i) return @"nothing waits under that id";
    if (!i.canPutBack) {
        NSString *runs = Runs(i);
        if (runs) return runs;
        if (i.why == MMRemovalWaitDamaged) return [NSString stringWithFormat:@"its record is damaged, so MinMacs does not move it. Move it by hand from %@", i.stagedAt];
        return i.oldPath ? @"its Wrap Up has not ended" : @"the record does not say where it was";
    }
    NSString *to = path.length ? path : i.oldPath;
    if (![to hasPrefix:@"/"]) return @"give a full path";
    for (NSString *c in [to componentsSeparatedByString:@"/"]) if ([c isEqualToString:@".."] || [c isEqualToString:@"."]) return @"its path is not a real path";
    if (to.length > 1 && [to hasSuffix:@"/"]) return @"its path is not a real path";
    if (path.length) {
        // A place of the person's own: the folder must be there already. MinMacs makes no folders for it.
        BOOL dir = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:to.stringByDeletingLastPathComponent isDirectory:&dir] || !dir)
            return [NSString stringWithFormat:@"the folder %@ does not exist", to.stringByDeletingLastPathComponent];
    }
    if (There(to)) return [NSString stringWithFormat:@"something already exists at %@", to];
    return nil;
}

NSString *MMRemovalDeleteWaiting(NSString *itemID, int64_t *freed) {
    if (freed) *freed = 0;
    MMRemovalWaitingItem *i = MMRemovalWaitingFind(itemID);
    NSString *no = MMRemovalDeleteWaitingWhyNot(i);
    return no ?: MMRemovalDeleteStagedItem([MMUndo.shared record:i.partRid], i.stagedAt, freed);
}

NSString *MMRemovalPutBackWaiting(NSString *itemID, NSString *path) {
    MMRemovalWaitingItem *i = MMRemovalWaitingFind(itemID);
    NSString *no = MMRemovalPutBackWaitingWhyNot(i, path);
    return no ?: MMRemovalPutBackStagedItem([MMUndo.shared record:i.partRid], i.stagedAt, path.length ? path : i.oldPath);
}
