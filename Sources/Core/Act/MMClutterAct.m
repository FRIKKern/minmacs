// Clutter actions: the Trash for cache, build and leak rows, the tool's own command for tool rows.
// Ported from NN's Apply and FreedByDelete, internal/leaks/module.go and internal/sizer, with the permanent delete
// replaced by the Trash, and the tool command preceded by an APFS clone that undo copies back from.
#import "Core/Act/MMClutterAct.h"
#import "Core/Act/MMUndo.h"
#import "Core/Store/MMStore.h"
#include <fts.h>
#include <sys/clonefile.h>
#include <sys/stat.h>

NSArray<NSDictionary *> *MMClutterAudit(NSArray<NSString *> *paths) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *p in paths) {
        struct stat st;
        BOOL exists = lstat(p.fileSystemRepresentation, &st) == 0;
        NSMutableDictionary *a = [@{@"path": p, @"exists": @(exists)} mutableCopy];
        if (exists) {
            MMSize s = [MMSizer quick:p];
            a[@"allocated"] = @(s.allocated); a[@"files"] = @(s.files); a[@"mtime"] = @(st.st_mtimespec.tv_sec);
        }
        [out addObject:a];
    }
    return out;
}

@interface MMClutterAction ()
@property (readwrite) MMClutterItem *item;
@property (strong) MMFinding *finding;
@property (strong) MMClutterCatalog *catalog;
@property (strong) MMClutterItem *fresh;
@end

@implementation MMClutterAction

+ (instancetype)actionFor:(MMFinding *)finding item:(MMClutterItem *)item catalog:(MMClutterCatalog *)catalog {
    if (!finding || !item) return nil;
    MMClutterAction *a = [MMClutterAction new];
    a.finding = finding; a.item = item; a.catalog = catalog ?: MMClutterCatalog.shared;
    return a;
}

- (BOOL)isTool { return self.item.kind.klass == MMClutterTool; }
- (NSString *)kind { return self.isTool ? @"clean" : @"trash"; }

- (NSString *)toolPath { return MMClutterToolPath(self.item.kind.cleanupArgs.firstObject); }

- (NSString *)recheck {
    MMClutterKind *k = self.item.kind;
    if (!k) return @"cannot verify which row it belongs to";
    if (k.reportOnly) return k.ownerSetting ?: @"its row only reports it";
    if (self.isTool && !self.toolPath) return [NSString stringWithFormat:@"%@ is not installed", k.cleanupArgs.firstObject ?: @"the tool"];
    MMClutterItem *now = [self.catalog inspect:self.item];
    if (!now) return @"it is gone";
    if (now.state != MMClutterFree) return now.why ?: @"it is in use";
    for (NSString *m in now.members) {
        NSString *w = [self.catalog whyNot:m kind:k];
        if (w) return w;
    }
    self.fresh = now;
    return nil;
}

- (NSString *)dryRun {
    MMClutterItem *i = self.fresh ?: self.item;
    NSString *what = i.members.count == 1 ? i.members.firstObject.stringByAbbreviatingWithTildeInPath
                                          : [NSString stringWithFormat:@"%lu folders of %@", (unsigned long)i.members.count, i.path.stringByAbbreviatingWithTildeInPath];
    if (self.isTool)
        return [NSString stringWithFormat:@"would copy %@ to the recovery folder, then run %@. Undo copies back what it removed.", what, i.kind.cleanup];
    return [NSString stringWithFormat:@"would move %@ to the Trash. Undo moves it back.", what];
}

- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMClutterItem *i = self.fresh ?: [self.catalog inspect:self.item];
    if (!i) { if (error) *error = @"it is gone"; return NO; }
    NSArray *paths = i.members;
    [MMUndo.shared note:record payload:@{@"kindID": i.kind.kindID, @"paths": paths, @"audit": @{@"before": MMClutterAudit(paths)}}];
    BOOL ok = self.isTool ? [self clean:i record:record error:error] : [self trash:i record:record error:error];
    MMUndoRecord *now = [MMUndo.shared record:record.rid];
    NSMutableDictionary *audit = [now.payload[@"audit"] mutableCopy] ?: [NSMutableDictionary new];
    audit[@"after"] = MMClutterAudit(paths);
    [MMUndo.shared note:record payload:@{@"audit": audit}];
    return ok;
}

/// Each path is checked against the walls once more, right before it moves.
- (BOOL)trash:(MMClutterItem *)i record:(MMUndoRecord *)record error:(NSString **)error {
    NSMutableArray *refused = [NSMutableArray new];
    NSInteger moved = 0;
    for (NSString *m in i.members) {
        NSString *w = [self.catalog whyNot:m kind:i.kind];
        if (w) { [refused addObject:[NSString stringWithFormat:@"%@: %@", m.lastPathComponent, w]]; continue; }
        NSError *e = nil;
        if ([MMUndo.shared trash:[NSURL fileURLWithPath:m] record:record error:&e]) moved++;
        else [refused addObject:[NSString stringWithFormat:@"%@: %@", m.lastPathComponent, e.localizedDescription ?: @"it could not go to the Trash"]];
    }
    if (refused.count) [MMUndo.shared note:record payload:@{@"refused": refused}];
    if (moved == 0) { if (error) *error = refused.firstObject ?: @"nothing went to the Trash"; return NO; }
    return YES;
}

/// The paths under copy whose twin is gone now: what the tool removed, relative to /, as the recovery copy holds them
/// under dir. A gone folder is named once.
static NSArray<NSString *> *Vanished(NSString *dir, NSString *copy) {
    NSMutableArray *out = [NSMutableArray new];
    char *argv[] = { (char *)copy.fileSystemRepresentation, NULL };
    FTS *fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_NOSTAT, NULL);
    if (!fts) return out;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (e->fts_info == FTS_DP || e->fts_level == 0) continue;
        NSString *p = @(e->fts_path);
        if (![p hasPrefix:[dir stringByAppendingString:@"/"]]) continue;
        NSString *rel = [p substringFromIndex:dir.length + 1];
        struct stat st;
        if (lstat([@"/" stringByAppendingString:rel].fileSystemRepresentation, &st) != 0) {
            [out addObject:rel];
            fts_set(fts, e, FTS_SKIP);
        }
    }
    fts_close(fts);
    return out;
}

- (BOOL)clean:(MMClutterItem *)i record:(MMUndoRecord *)record error:(NSString **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [[MMExpertDir(@"noonoo") stringByAppendingPathComponent:@"recovery"] stringByAppendingPathComponent:record.rid];
    for (NSString *m in i.members) {
        NSString *to = [dir stringByAppendingString:m];
        [fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        // An APFS clone shares every block, so the copy costs almost nothing until the tool removes the original.
        if (clonefile(m.fileSystemRepresentation, to.fileSystemRepresentation, CLONE_NOFOLLOW) != 0) {
            if (error) *error = [NSString stringWithFormat:@"no recovery copy of %@ could be made: %s. MinMacs leaves it.", m.lastPathComponent, strerror(errno)];
            return NO;
        }
    }
    NSArray *argv = i.kind.cleanupArgs, *dry = i.kind.dryRunArgs;
    NSArray *dryArgs = dry.count && [dry.firstObject isEqualToString:argv.firstObject] ? [dry subarrayWithRange:NSMakeRange(1, dry.count - 1)] : nil;
    MMToolCommand *cmd = [MMToolCommand tool:i.kind.kindID path:self.toolPath args:[argv subarrayWithRange:NSMakeRange(1, argv.count - 1)]
                                  dryRunArgs:dryArgs env:nil];
    NSString *out = nil, *err = nil;
    BOOL ok = [cmd runWithRecord:record output:&out error:&err];
    // Whatever the exit status, what is gone now can be copied back.
    NSMutableArray *saved = [NSMutableArray new];
    for (NSString *m in i.members) {
        NSString *copy = [dir stringByAppendingString:m];
        struct stat st;
        if (lstat(m.fileSystemRepresentation, &st) != 0) [saved addObject:[m substringFromIndex:1]];
        else [saved addObjectsFromArray:Vanished(dir, copy)];
    }
    // A copy of a path the tool left in place shares its blocks with the original until one of them changes.
    // Restore copies only the saved paths, from dir to root, and never over a file that exists.
    [MMUndo.shared note:record payload:@{@"recovery": @{@"dir": dir, @"root": @"/", @"saved": saved, @"skipped": @[]}}];
    if (!ok && error) *error = err ?: @"the tool failed";
    return ok;
}

@end
