// Undo records, the Trash, git bundles, restore and tool commands. Patterns P52 and P53 of SYNTHESIS.md section 1.7.
// Principle 5: nothing is lost unless the person chose so. The record is written before the action, MinMacs never
// empties the Trash, and what cannot be verified is kept. Where a removed thing goes is MMRemoval.h's one decision.
#import <Foundation/Foundation.h>

/// P52. The states of one undo record. Each change is a new row in the log of P38.
typedef NS_ENUM(NSInteger, MMUndoState) { MMUndoPending, MMUndoDone, MMUndoFailed, MMUndoRestored };

/// P52. One action and how to take it back. Starts from the records of WFRemove and WFRestore, WF Forest.m:274,
/// and NN's record-first rule and Grave.
@interface MMUndoRecord : NSObject
@property (readonly, copy) NSString *rid;               // the log's record id
@property (readonly, copy) NSString *expert, *kind;     // kind: "stop", "remove", "trash", "tool", "quit"
@property (readonly, copy) NSString *findingID, *subject, *why, *by;   // by: "manual", "cli", "proactive", "eager", "guard"
/// The record of a Wrap Up that this record is one part of, PLAN.md section 6. nil for a single action.
@property (readonly, copy) NSString *parentRid;
@property (readonly) MMUndoState state;
@property (readonly) NSDate *at;
/// What restore needs: a restart command, cwd and env; a git bundle path and commit; trashed URLs and their old paths;
/// the tool command's dry-run output.
@property (readonly) NSDictionary *payload;
@property (readonly) int64_t freedBytes;                // from MMSizer freedOnVolume, the statfs delta
@property (readonly, copy) NSString *error;
/// NO for a failed stop or quit, which changed nothing, for a thing that was deleted at once with no way back kept,
/// and for every removal that went through under the Delete choice.
@property (readonly) BOOL canRestore;
/// YES when the payload's "removal" says the thing was deleted, MMRemoval.h. It says so only once the thing is gone:
/// a record that failed, or a Wrap Up part whose item still waits in the staging folder, says NO. A merged worktree deleted under
/// Smart can still be restored, since git holds it. Anything else deleted cannot.
@property (readonly) BOOL deletedNow;
/// Why this record cannot be read, or nil: a field MinMacs acts on has another shape than MinMacs writes, such as a
/// "staged" that is no list or a time that is no number. Such a record is never acted on: restore refuses it, and
/// recovery and the sweep of MMRemoval.h skip its Wrap Up and name it once in the log. A damaged "owner" is not
/// counted here: it reads as no owner.
@property (readonly, copy) NSString *damage;
@end

/// P52. The one undo engine for every expert.
@interface MMUndo : NSObject
+ (instancetype)shared;
/// Writes a pending record and returns it. Always called before the action starts.
/// parent is the rid of a Wrap Up record, or nil. A Wrap Up is one record with a part for each action in it.
- (MMUndoRecord *)begin:(NSString *)expert kind:(NSString *)kind finding:(NSString *)findingID subject:(NSString *)subject
                    why:(NSString *)why by:(NSString *)by parent:(NSString *)parent payload:(NSDictionary *)payload;
/// Adds to the payload of a pending record, such as the trashed URL once it is known.
- (void)note:(MMUndoRecord *)record payload:(NSDictionary *)more;
- (void)finish:(MMUndoRecord *)record ok:(BOOL)ok freed:(int64_t)bytes error:(NSString *)error;
/// Moves item to the Trash with NSFileManager trashItemAtURL and notes where it went. Never empties the Trash.
/// With MINMACS_HOME set it moves item into MMTrashFolder() instead, so a test never touches the person's Trash.
- (NSURL *)trash:(NSURL *)item record:(MMUndoRecord *)record error:(NSError **)error;
/// P52. `git bundle create` of every commit in the worktree that is on no remote, into <expert>/bundles/<rid>.bundle.
/// Returns the bundle path, or nil with *error. An action that needs a bundle does not run without one.
- (NSString *)bundle:(NSString *)worktree record:(MMUndoRecord *)record error:(NSString **)error;
/// The recovery folder. Copies each file, a path relative to root, into <expert>/recovery/<rid>/ and notes them.
/// For files an action would lose that the Trash does not hold, such as a worktree's ignored .env.local.
/// A file over 20 MB, or past 100 MB in all, is skipped and named in the payload. Returns the folder, or nil with *error.
- (NSString *)recover:(NSArray<NSString *> *)files from:(NSString *)root record:(MMUndoRecord *)record
                error:(NSString **)error;
/// Undoes a done record: restarts, moves back from the Trash, recreates a worktree from its bundle,
/// and copies back what the recovery folder holds.
/// A Wrap Up record restores each of its parts, newest first. A tool command's record cannot be restored.
/// Returns nil on success, else the problem in words.
- (NSString *)restore:(NSString *)rid;
- (NSArray<MMUndoRecord *> *)recent:(NSString *)expert limit:(NSUInteger)limit;   // newest first, expert nil means all
- (MMUndoRecord *)record:(NSString *)rid;
@end

#pragma mark The one checked reader

/// Every field Act reads from a record goes through these. A record comes from disk, so any field may have another
/// shape than MinMacs wrote. A value of the wrong type reads as absent, nil or NO, and never raises.
/// from is a payload, a body or an entry of a list. Anything that is no dictionary has no fields.
NSString *MMRecordString(id from, NSString *key);
NSNumber *MMRecordNumber(id from, NSString *key);                  // a number, never a boolean
BOOL MMRecordFlag(id from, NSString *key);                         // YES only for a boolean that is true
NSDictionary *MMRecordDict(id from, NSString *key);
NSArray<NSDictionary *> *MMRecordList(id from, NSString *key);     // a list, with only its dictionaries
NSArray<NSString *> *MMRecordStrings(id from, NSString *key);      // a list, with only its strings

/// The very file at path, for a "staged" or "trashed" entry: {ino, vol, dev}. vol is the UUID of the volume that
/// holds it, which stays the same across a replug or a restart. The device number does not, so it is kept only to
/// say the entry knew its file. A symlink is named, never followed. nil when nothing is there.
NSDictionary *MMFileIdentity(NSString *path);
/// Whether the file at path is the one the entry names: 1 yes, 0 another file or nothing, -1 the entry does not say.
/// The inode must match. With "vol" the volume's UUID must match too. An entry with "dev" and no "vol", as one
/// build wrote them, is matched by its inode alone at that path. An entry with neither does not say.
int MMFileIsEntry(NSString *path, NSDictionary *entry);

/// A payload key whose restore an expert does, such as MinMacs's "reopen", which opens closed tabs again through its
/// tab bridge. -[MMUndo restore:] of a done record that holds key calls the block with the value, after its own steps,
/// and a record that holds only such a key can be restored. The block runs on the restoring queue, never on main, and
/// returns nil or the problem in words. A part whose payload has "restoreLast" set comes back after the other parts
/// of its Wrap Up, so tabs reopen once their servers run again.
void MMUndoRestoreKey(NSString *key, NSString *(^)(id value));

/// The Trash of a test run: <MINMACS_HOME>/Trash when MINMACS_HOME is set, else nil for the real Trash.
/// -[MMUndo trash:record:error:] moves items there, and restore moves them back from there.
NSString *MMTrashFolder(void);

/// P53. A tool's own cleanup command, run first in its dry-run form.
/// New code. uv says direct edits to its cache are never safe, and Go's module cache is read-only on this Mac.
/// Decision 1 lists the commands: `xcrun simctl`, `brew cleanup`, `pnpm store prune`, `docker system prune`.
@interface MMToolCommand : NSObject
@property (readonly, copy) NSString *tool, *path;       // the row id and the resolved binary
@property (readonly) NSArray<NSString *> *args, *dryRunArgs;
@property (readonly) NSDictionary<NSString *, NSString *> *env;
@property (readonly) NSTimeInterval timeout;
+ (instancetype)tool:(NSString *)tool path:(NSString *)path args:(NSArray<NSString *> *)args
          dryRunArgs:(NSArray<NSString *> *)dryRunArgs env:(NSDictionary<NSString *, NSString *> *)env;
/// dryRunArgs nil means the tool has no dry-run form, such as `docker system prune`.
/// Runs the dry-run form and returns its output, or nil with *error. With no dry-run form it returns nil and
/// leaves *error nil.
- (NSString *)dryRun:(NSString **)error;
/// Runs the dry run, keeps its output in record's payload, then runs the command. NO when either part failed.
/// With no dry-run form the payload keeps the full command line in place of the dry-run output.
- (BOOL)runWithRecord:(MMUndoRecord *)record output:(NSString **)output error:(NSString **)error;
@end
