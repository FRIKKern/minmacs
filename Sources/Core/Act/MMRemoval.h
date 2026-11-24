// Where a removed thing goes, issue #62 and the owner's decision D2: MinMacs never deletes anything at once.
// Everything it removes keeps a way back, and there is no choice to make.
//
//   a merged worktree          git worktree remove, with no --force. git gives its tracked files back, a git bundle
//                              keeps any commit on no remote, and its ignored files go to the recovery folder.
//   .env, untracked config     the Trash, before git worktree remove, and Restore moves them back.
//   a cache, build or leftover the Trash, and Restore moves it back.
//   a tool's own cleanup       an APFS recovery copy first, then the tool's command, and Restore copies back what the
//                              tool removed. The minmacs-recovery row sends the copy to the Trash after 7 days.
//
// The pref core.removal once held Smart, Trash or Delete. Nothing reads it to decide: MMRemovalChoiceNow is always
// the Trash, whatever it holds, and Core's start clears an old value, MMRemovalForgetOldChoice.
// Every path that removes something asks MMRemovalDecide, and none decides by itself. The fresh check, MustKeep and
// the record of MMRunAction run first, a git bundle is taken whenever commits are on no remote, git never runs with
// --force, and MinMacs never empties the Trash and never deletes from it.
#import <Foundation/Foundation.h>
#import "Core/Know/MMClutter.h"
@class MMUndoRecord, MMRemovalPlaces;

/// The one way a removed thing goes: it keeps a way back, as the old Trash choice did. A record keeps it as "trash".
typedef NS_ENUM(NSInteger, MMRemovalChoice) { MMRemovalTrash = 1 };
extern NSString *const MMRemovalKey;                    // @"core.removal": the old pref. Read by nothing that decides
/// Always MMRemovalTrash, whatever the pref holds, an old "smart" or "delete" too.
MMRemovalChoice MMRemovalChoiceNow(void);
NSString *MMRemovalChoiceName(MMRemovalChoice choice);  // "trash"
/// The one sentence the CLI says: "Everything MinMacs removes keeps a way back: ..."
NSString *MMRemovalExplain(void);
/// Clears an old value of core.removal, so no later build reads a Smart or Delete that nobody can see. YES when it
/// cleared one. Core's start calls it.
BOOL MMRemovalForgetOldChoice(void);

/// What is about to be removed.
typedef NS_ENUM(NSInteger, MMRemovalThing) {
    MMRemovalWorktree,       // a linked worktree, which `git worktree remove` takes with no --force
    MMRemovalIgnoredFiles,   // the files in it that git ignores and no cache row names, such as .env
    MMRemovalConfigFiles,    // the untracked config files Wrap Up moves first, such as .env.local
    MMRemovalClutter,        // one item of a cache, build or leak row
    MMRemovalToolCopy,       // what a tool's own cleanup removes, which a recovery copy keeps
};

/// The fresh facts of the thing, read by the caller right before it acts. They no longer change where it goes, which
/// is always a way back. A worktree's facts give the record's words, MMRemovalGitWhyNot.
@interface MMRemovalFacts : NSObject
// A worktree. A count is -1 while git could not tell.
@property BOOL gitKnown, merged, upstreamGone;
// Issue #118: the upstream could not be read, which keeps whatever else says, or the branch tracks none. Only the
// words follow upstreamNone: with neither set the remote branch it tracks is there.
@property BOOL upstreamUnknown, upstreamNone;
@property NSInteger dirty, untracked, unpushed, stashes;
// Clutter and a tool's cleanup.
@property MMClutterClass klass;
@property BOOL rebuilt, free, ownerGone;                // rebuilt: -[MMClutterKind rebuilt]. free: MMClutterFree now
/// Why the rebuild is not proven on the item read now, -[MMClutterItem unproven], or nil.
@property (copy) NSString *unproven;
+ (instancetype)worktreeKnown:(BOOL)known merged:(BOOL)merged upstreamGone:(BOOL)gone dirty:(NSInteger)dirty
                    untracked:(NSInteger)untracked unpushed:(NSInteger)unpushed stashes:(NSInteger)stashes;
+ (instancetype)clutter:(MMClutterItem *)item;          // from the item -[MMClutterCatalog inspect:] just read
@end

/// Why git alone could not give this worktree back, or nil when it could: merged or its remote branch gone, with no
/// uncommitted change, no untracked file, no commit on no remote and no stash. A fact nobody set counts against it.
/// It decides nothing, since every worktree keeps a way back. It is the record's word, and the git checks read it.
NSString *MMRemovalGitWhyNot(MMRemovalFacts *facts);

/// The answer for one thing: always keep a way back, and why in plain words.
@interface MMRemovalDecision : NSObject
@property (readonly) MMRemovalChoice choice;
@property (readonly) MMRemovalThing thing;
/// Always NO from MMRemovalDecide. Only a check's own seam, MMRemovalTestDeleteDecision, sets it, to leave behind
/// what an older MinMacs staged.
@property (readonly) BOOL deleteNow;
@property (readonly, copy) NSString *why;
- (NSDictionary *)json;                                 // {choice, wants, deleted, why}, as the record's payload keeps it
@end

/// The one function. Whatever the pref holds and whoever asks, by as MMRunAction takes it, the answer keeps a way
/// back: deleteNow is NO. Every removal path still asks it, so the record says where the thing went and why.
MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts, NSString *by);
#ifdef MM_TESTS
/// A check's own seam, compiled only with MM_TESTS: a decision that deletes, as Smart and Delete made them before
/// D2, so a check can leave what an older MinMacs staged and see the recovery, the sweep and the waiting list settle it.
MMRemovalDecision *MMRemovalTestDeleteDecision(MMRemovalThing thing);
#endif

#pragma mark The record

/// Writes the decision into the record as payload "removal", before the caller acts on it: {choice, wants, why,
/// deleted NO}. "wants" is the answer. "deleted" turns YES only in MMRemovalDone, once the thing is gone, so a record
/// that failed never says deleted. key names a second decision of the same record, such as @"ignored" for a
/// worktree's ignored files, kept inside "removal".
void MMRemovalNote(MMUndoRecord *record, MMRemovalDecision *decision, NSString *key);
/// Lists the paths the fresh finding names, as payload "asked", before the first one goes. MMRemovalApply refuses
/// any path that is not on the list.
void MMRemovalAsk(MMUndoRecord *record, NSArray<NSString *> *paths);
/// The act went through: "deleted" becomes what "wants" said. A part of a Wrap Up whose deletes wait in the staging
/// folder says "staged" in its place, until MMRemovalFinishStaged, and one whose item could not be staged says
/// "unstaged" and never deleted.
void MMRemovalDone(MMUndoRecord *record, NSString *key);

#pragma mark The one place that deletes

/// Removes the item at path as the decision says. Keep a way back, which is every answer MMRemovalDecide gives:
/// -[MMUndo trash:record:error:]. The delete below stays behind the wall for a decision that deletes, which only a
/// check's seam makes now: the item is unlinked, never followed through a symlink, and the record's payload lists it
/// under "deleted" as {path}. Before it deletes it asks MMRemovalWallWhyNot on the item's real path. This is the
/// only place Act deletes a file.
///
/// The staging, the finish, the recovery and the waiting list below settle what a Wrap Up of an older MinMacs, under
/// Smart or Delete, left staged. A part of a Wrap Up, a record with a parent, never deletes here, since a later part, such as git worktree
/// remove, may still refuse. Its item is renamed into a staging folder of MinMacs's own on the item's own volume and
/// listed under "staged": <support>/staged/<wrap up rid>/, or for another volume a hidden folder
/// .minmacs-staged-<wrap up rid> beside the worktree. It is one rename and never a copy. When no such rename can be,
/// or the staging folder would lie where the wall lets nothing be deleted, the item stays where it is and is listed
/// under "unstaged". Nothing waits in the person's Trash.
BOOL MMRemovalApply(NSString *path, MMRemovalDecision *decision, MMUndoRecord *record, NSError **error);
/// The same for the members of one temp-folder family, siblings in one folder: to the Trash as one folder named name,
/// -[MMUndo trashMembers:asFolder:record:refused:error:], so a family of 45,000 is one item in the Trash and one record.
/// Only a decision that keeps a way back moves anything, and nothing is deleted here. A path with a "." or ".." name
/// is refused, as by MMRemovalApply. refused gets "name: why" for each member left where it is. Returns how many went.
NSInteger MMRemovalApplyHeld(NSArray<NSString *> *paths, NSString *name, MMRemovalDecision *decision, MMUndoRecord *record,
                             NSMutableArray<NSString *> *refused, NSError **error);
/// Every part went through: deletes what these parts staged, each checked to be the same file, in the staging folder
/// MinMacs made for this Wrap Up, then removes the empty folder and marks each part deleted. An item that cannot be
/// deleted stays staged with "why" in its entry, and its part can still restore. Returns the bytes the volume got back.
int64_t MMRemovalFinishStaged(NSArray<MMUndoRecord *> *parts);
/// A later part of the Wrap Up refused, so the worktree stays: renames each staged item back to its exact old path,
/// newest first, and moves back what these removal parts sent to the Trash to keep. Each item on its own: one that
/// cannot go back, since something sits at its old path now, stays where it waits and is reported, and the others
/// still go. A second call moves the rest. A part whose every item is back is marked restored, and the empty
/// staging folder is removed.
/// Nobody asked for this put-back, so it only moves files, -[MMUndo moveBackOnly:]: a record's restart command,
/// relaunch, restorer, bundle and recovery copy are never run from here, whatever the record holds.
/// A stop or a quit is not taken back here. Returns nil, or what could not go back.
NSString *MMRemovalPutBack(NSArray<MMUndoRecord *> *parts);
/// After a crash: a Wrap Up whose record never finished and whose process is gone is settled at once. Nothing is
/// deleted: what its removal parts had moved, to the staging folder or to the Trash, goes back to its old path, and
/// the record and every part still pending are failed, so none stays pending. Only one that had every part through
/// and had begun its deletes, payload "finishing", is finished. The record's "owner", MMRemovalOwner, says whose it
/// is, MMRemovalOwnerAlive: a Wrap Up whose process lives is never touched, whatever its age. A record with no
/// owner is settled once it is 15 minutes old.
/// A Wrap Up with a record that cannot be read is named, and nothing is deleted for it. What its parts moved aside
/// goes back, for each part whose body and "staged" and "trashed" lists read, -[MMUndoRecord moveDamage]. Once all
/// of it is back and nothing waits, the Wrap Up is failed, its error saying its record could not be read in full.
/// While a part cannot be read or something still waits, it stays pending, and MMRemovalWaiting lists what waits.
/// The error says how many items went back and what had been deleted, only as far as the records show it. A Wrap Up
/// whose state cannot be read, -[MMUndoRecord stateUnread], may have ended: nothing of it is moved back or failed.
/// MMCoreStart and MMRunWrapUp call it, off main. Returns how many Wrap Ups it settled, failed or finished.
NSInteger MMRemovalRecoverStaged(void);
/// {pid, start}: this process, for the Wrap Up record it begins. start is 0 when it could not be read.
NSDictionary *MMRemovalOwner(void);
/// Whose Wrap Up it is, from the record's "owner":
///    1  its process lives, so the record is left alone, whatever its age
///    0  its process is gone, or the pid is another process now, so it is settled at once
///   -1  the record names no owner or a damaged one, or the pid is a process of another user: its age decides
/// This very process's pid is alive, 1, when the record has no start time. With no start time and another pid, only
/// the pid can be asked. A pid that lives keeps the record when its process
/// began before the record was written. One that began after it may have taken the pid since, or the clock may have
/// moved back: that is never read as gone, -1, so the record's age decides.
int MMRemovalOwnerAlive(MMUndoRecord *parent);
/// The rids of the records recovery and the sweep found that cannot be read, -[MMUndoRecord damage]. Each was named
/// in the log once, and its Wrap Up is left as it is: nothing of it is moved, and nothing deleted.
NSArray<NSString *> *MMRemovalDamagedRecords(void);
/// For MMRemovalRecover.m: removes the staging folder of rid once it holds nothing but MinMacs's own marker and
/// .gitignore, and YES when MINMACS_HOME is set.
void MMRemovalDropEmptyStagingFolder(NSString *folder, NSString *rid);
BOOL MMRemovalTestHome(void);
/// What was left staged though its Wrap Up ended. When the Wrap Up is done and its record says the deletes had
/// begun, payload "finishing", the worktree is gone: the delete of what is left is tried once more, as
/// MMRemovalFinishStaged deletes, behind the same wall and the same check that it is the very file that was staged,
/// and the part notes "sweepTried" so it is not tried at every start. What still cannot be deleted waits, and
/// MMRemovalWaiting lists it. In every other case, a Wrap Up that failed or was restored, each item goes back to its
/// old path, and only from the staging folder MinMacs made for that Wrap Up, MMRemovalStagedItemWhyNot: an entry
/// that names a file anywhere else is left where it is. A part whose Wrap Up has no record takes no act: nothing of
/// it is moved or deleted, and MMRemovalWaiting lists it. A record that cannot be read never has anything deleted: a part whose lists read goes
/// back, -[MMUndoRecord moveDamage], and one whose lists do not is left. A folder under <support>/staged that no
/// record names is left alone and returned in *orphans the first time it is seen, for the log.
/// MMCoreStart calls it after MMRemovalRecoverStaged. Returns how many parts it settled: put back or deleted.
NSInteger MMRemovalSweepStaged(NSArray<NSString *> **orphans);
/// YES when what part staged may be deleted now as its Wrap Up's deletes: the Wrap Up is done, its record says the
/// deletes had begun with a true yes, "finishing", neither record is damaged, and no Undo was asked of either,
/// "undoAsked", which -[MMUndo restore:] notes even when it cannot finish. Otherwise it is put back.
BOOL MMRemovalDeletesBegan(MMUndoRecord *parent, MMUndoRecord *part);

#pragma mark What still waits

/// Why an item still waits in a staging folder, or in the Trash with no record to name it.
typedef NS_ENUM(NSInteger, MMRemovalWaitWhy) {
    MMRemovalWaitDeleteFailed,  // its Wrap Up is done, and the delete failed, also when tried once more
    MMRemovalWaitOldPathTaken,  // its Wrap Up failed, and something sits at its old path now
    MMRemovalWaitPutBackFailed, // its Wrap Up failed, its old path is free, and the move back failed
    MMRemovalWaitDamaged,       // its record, or its Wrap Up's, cannot be read, so MinMacs does not act on it alone
    MMRemovalWaitNoWrapUp,      // its Wrap Up has no record, so nobody can tell MinMacs staged it: listed, never acted on
    MMRemovalWaitInTrash,       // in the Trash, and its record does not name it, issue #113: listed, never acted on
};
/// One item in a staging folder that MinMacs cannot settle by itself.
@interface MMRemovalWaitingItem : NSObject
@property (readonly, copy) NSString *itemID;            // "<part rid>:<its name in the staging folder>", for the CLI,
                                                        // or "<rid>:trash:<its name in the Trash>"
@property (readonly, copy) NSString *name;              // its own name, such as node_modules
@property (readonly, copy) NSString *oldPath;           // where it was, or nil when the record does not say
/// Set when the staging folder's list holds this name for a file with another id than the one that waits there now:
/// the old path the list holds. oldPath is nil then, since MinMacs cannot tell that this is that file.
@property (readonly, copy) NSString *listedOldPath;
/// "was at <old path>.", or what the list holds instead, as one line for the CLI.
@property (readonly, copy) NSString *wasWords;
@property (readonly, copy) NSString *stagedAt;          // where it waits now: in the staging folder, or in the Trash
@property (readonly) int64_t bytes;                     // what it takes on the disk
@property (readonly) MMRemovalWaitWhy why;
@property (readonly, copy) NSString *detail;            // the last failure or the damage, in words, or nil
@property (readonly, copy) NSString *wrapUpRid, *partRid;
@property (readonly) BOOL canDelete, canPutBack;        // what MMRemovalDeleteWaiting and MMRemovalPutBackWaiting allow
/// "could not be deleted", "its old place is taken", "could not go back", "its record is damaged",
/// "its Wrap Up has no record", "is in the Trash where no record MinMacs can undo names it"
@property (readonly, copy) NSString *whyWords;
- (NSDictionary *)json;
@end
/// What sits in a staging folder and cannot be settled, from the records and core/damaged-records.json. A Wrap Up
/// that still runs, or that recovery will settle at the next start, is not listed. An item of a record whose staged
/// list cannot be read is found in its staging folder, with no old path. Only what lies directly in a folder that
/// MMRemovalStagingFolderOf accepts is listed, so a record never lists a file of the person's own. Last, read only,
/// what a record sent to the Trash and does not name, MMRemovalWaitInTrash: each item MMRemovalTrashStranded finds
/// directly in a Trash by its id, unless the act that sent it there may still name it. MinMacs neither deletes nor
/// moves one of those.
NSArray<MMRemovalWaitingItem *> *MMRemovalWaiting(void);
/// The person deletes one listed item now. Only an item MinMacs staged itself, whose record and Wrap Up read, whose
/// Wrap Up has a record and ended, and only through MMRemovalFinishStaged's own wall and identity check. nil when it is deleted, else
/// why not. *freed gets the bytes the volume got back.
NSString *MMRemovalDeleteWaiting(NSString *itemID, int64_t *freed);
/// The person puts one listed item back: to path, or to its old path when path is nil. Never over something there,
/// and only the very file that was staged, from the staging folder MinMacs made for its Wrap Up, which must have a
/// record. A path of the person's own must be a full path in a folder that exists.
/// nil when it is there, else why not.
NSString *MMRemovalPutBackWaiting(NSString *itemID, NSString *path);
/// The listed item with that id, or nil. Then why MMRemovalDeleteWaiting or MMRemovalPutBackWaiting would refuse it
/// now, or nil when it would act: what a dry run says.
MMRemovalWaitingItem *MMRemovalWaitingFind(NSString *itemID);
NSString *MMRemovalDeleteWaitingWhyNot(MMRemovalWaitingItem *item);
NSString *MMRemovalPutBackWaitingWhyNot(MMRemovalWaitingItem *item, NSString *path);
/// For MMRemovalWaiting.m: the one staged item of part at stagedAt, deleted as MMRemovalFinishStaged deletes, or
/// moved to path, as put-back moves, after the same check of its staging folder. Each notes the record.
NSString *MMRemovalDeleteStagedItem(MMUndoRecord *part, NSString *stagedAt, int64_t *freed);
NSString *MMRemovalPutBackStagedItem(MMUndoRecord *part, NSString *stagedAt, NSString *path);
/// The one check of where a staged item waits, asked before MinMacs deletes it or moves it back, issue #70. nil when
/// MinMacs may act on what part staged at stagedAt, else why not. All of these must hold:
///   1. part names a Wrap Up, and that Wrap Up has a record
///   2. stagedAt is spelled as a real path, with no ".." in it, and something is there
///   3. it lies directly in part's "stagedIn", by real paths, so a link is never taken for the folder it points at.
///      When "stagedIn" cannot be read, the folder that holds the item now is the one asked 4 and 5
///   4. that folder is <support>/staged/<rid>, or is named .minmacs-staged-<rid> and lies beside the worktree that
///      the Wrap Up's record names, where alone MinMacs makes one
///   5. the folder holds the marker MinMacs wrote, and it says that rid
///   6. it is not one of the folder's own files, MMRemovalStagingOwnName
///   7. the folder's own list, .minmacs-items, written when the item was staged, says that this part staged this
///      very file, by its inode and volume UUID
/// So a record that names a file somewhere else, whatever inode it gives, never has that file moved or deleted.
NSString *MMRemovalStagedItemWhyNot(MMUndoRecord *part, NSString *stagedAt);
/// For -[MMUndo restore:] and -[MMUndo moveBackOnly:]: the same for one entry of part's "staged" list before it is
/// moved back, and its old path must be spelled as a real path and be the one the folder's own list holds for the
/// item, so a record never sends a staged item to an old path of its own making. nil when nothing waits at the
/// entry's "to", since nothing moves then.
NSString *MMRemovalStagedEntryWhyNot(MMUndoRecord *part, NSDictionary *entry);
/// YES for the names MinMacs keeps in a staging folder for itself: .minmacs, .gitignore and .minmacs-items. None is
/// ever an item.
BOOL MMRemovalStagingOwnName(NSString *name);
/// An item its part's record never names, issue #75: MinMacs stopped between the rename into the staging folder and
/// the write of the record, or that write was lost. The folder's own list named it before it moved. Each such item
/// that part r staged by the list's word and that is there, as a "staged" entry {from, to, ino, dev, vol, stranded,
/// why}, read only. Only from the staging folder r's "stagedIn" names, or with none, the two MinMacs makes for r's
/// Wrap Up. parent is r's Wrap Up when the caller has it, else nil. Empty for a record whose lists cannot be read.
NSArray<NSDictionary *> *MMRemovalStranded(MMUndoRecord *r, MMUndoRecord *parent);
/// Writes into r's "staged" list each item of MMRemovalStranded that passes MMRemovalStagedItemWhyNot, the one check,
/// so put-back, the delete, the sweep and the waiting list then treat it as any staged item. Never while the process
/// that runs r's Wrap Up lives, never for a Wrap Up that has no record, never into a record whose lists cannot be read
/// or that was restored. Returns how many it wrote in.
NSUInteger MMRemovalAdoptStranded(MMUndoRecord *r, MMUndoRecord *parent);
/// An item record r sent to the Trash, or was sending there, that no record names, since MinMacs stopped between the
/// list's first write and the record's note, issue #113, MMRemovalTrashStranded.m. Each entry of MinMacs's own list
/// of what r sent there, MMRemovalTrashListItems, whose old path r asked about, whose very file is not at that old
/// path, whose old path and id r itself does not name, and that is not where named names it, as {from, ino, dev, vol, stranded},
/// with "sending"
/// when the list never got a Trash path, so the move may not have run. Then where it is: "to" when that very file
/// lies directly in a Trash by its inode and volume UUID, never by a name alone; "several" when more than one name
/// there has its id; "unlooked", in words, when a look was refused or its id cannot be matched; and none of these
/// when MinMacs looked everywhere and did not find it. Read only: nothing is moved, deleted or written. Empty for a
/// record that is no removal or whose lists cannot be read. *unread is YES when r's list is there and is not
/// believed: not a list MinMacs wrote, or one that names an old path r never asked about. named nil is r's own.
NSArray<NSDictionary *> *MMRemovalTrashStranded(MMUndoRecord *r, NSSet<NSString *> *named, BOOL *unread);
/// What the records' "trashed" lists name, each Trash path with its id, for MMRemovalTrashStranded, and what the Trash
/// list of a record that still acts, MMRemovalStillActs, names: it may have moved a file and not yet named it. A
/// restored record names nothing: its Undo ran.
NSSet<NSString *> *MMRemovalTrashNamed(NSArray<MMUndoRecord *> *records);
/// YES while the act that sent something of r to the Trash may still be about to name it in r: r's Wrap Up, parent,
/// still runs, or r is a pending record of its own from the last 15 minutes. MMRemovalWaiting.m.
BOOL MMRemovalStillActs(MMUndoRecord *r, MMUndoRecord *parent);
/// What recovery says of the parts' items MMRemovalTrashStranded finds, or nil when there are none, one clause each:
/// that MinMacs had sent it to the Trash, or was sending it there when it stopped, and then that it is in the Trash at
/// its path where no record MinMacs can undo names it, has more than one name there, could not be looked for and why, or is at neither place. A list that is
/// not believed is said too. It never says put back.
NSString *MMRemovalTrashStrandedWords(NSArray<MMUndoRecord *> *parts);
#ifdef MM_TESTS
/// Compiled only with -DMM_TESTS. Ends this process at once, as a crash would, when MINMACS_TEST_STOP_TRASH says point
/// and MINMACS_HOME is set: "before-move", "after-move" or "after-list" in -[MMUndo trash:record:error:], or
/// "list-write" between the Trash list's read and its write. When MINMACS_TEST_HOLD_TRASH says point it prints "held"
/// once and waits until its input ends, so a check sees a record that still acts.
void MMRemovalTestStopTrash(const char *point);
#define MM_TEST_STOP_TRASH(point) MMRemovalTestStopTrash(point)
#else
#define MM_TEST_STOP_TRASH(point) ((void)0)
#endif

#pragma mark For MMRemovalApply.m: the staging folder's own files, MMRemovalStaging.m

/// The folder's own list, .minmacs-items, or nil when it has none that MinMacs wrote: a plain file of this user's.
NSDictionary *MMRemovalStagingItems(NSString *folder);
/// Writes into the folder's list that the item to be at to was at from, staged by the part rid, with its identity.
/// NO, and nothing written over, when something else holds that name or the list cannot be read.
BOOL MMRemovalStagingNoteItem(NSString *folder, NSString *to, NSString *from, NSString *rid, NSDictionary *identity);
/// After the rename, issue #79: writes the identity the item has at its new place into the entry the list holds
/// under name. Its "from" and "part" stay. NO when the list has no such entry or cannot be written.
BOOL MMRemovalStagingNoteIdentity(NSString *folder, NSString *name, NSDictionary *identity);
/// For the waiting list: the old path the folder's list holds under the name of the file at stagedAt, when the list
/// means another file than the one that is there now, by inode and volume UUID. Then that old path is not this
/// file's own. nil when the file is the one the list names, or the list does not say.
NSString *MMRemovalStagingListsAnother(NSString *stagedAt);
/// Takes name out of the folder's list again, when the rename it was written for did not happen.
void MMRemovalStagingForgetItem(NSString *folder, NSString *name);
/// YES when folder holds the marker MinMacs wrote for this rid: a plain file of ours that says the rid.
BOOL MMRemovalStagingMarkerSays(NSString *folder, NSString *rid);
/// YES when the folder's .gitignore and list are each a plain file of ours with MinMacs's own words, or not there.
BOOL MMRemovalStagingOwnFilesAreOurs(NSString *folder);
/// Makes the folder, 0700, with its marker for rid and its .gitignore. NO when it cannot be made.
BOOL MMRemovalStagingMake(NSString *folder, NSString *rid);
/// A Wrap Up whose state cannot be read, -[MMUndoRecord stateUnread], is left pending by recovery, since it may have
/// ended. Once the person has moved what it staged by hand, only they can say it is over. Each such Wrap Up, for the
/// CLI: {rid, subject, waiting: how many of its items still wait where MinMacs staged them, problem: why it cannot be
/// closed now, or null}.
NSArray<NSDictionary *> *MMRemovalUnreadWrapUps(void);
/// The person closes one: its record is failed, its error saying its state could not be read and that it was closed
/// by hand. No file is moved and none deleted. Only a Wrap Up whose state cannot be read, whose process is gone, and
/// of which nothing waits in a staging folder any more. A pending part that reads is failed with it, and a part's
/// "staged" list, of which nothing is there any more, moves to "stagedBeforeClose", so the sweep puts nothing of it
/// back. What its parts sent to the Trash stays in the Trash. nil when it is closed, else why not.
NSString *MMRemovalCloseUnread(NSString *rid);
NSString *MMRemovalCloseUnreadWhyNot(NSString *rid);    // what a dry run says
/// The staging folder as a rule on strings: item may be deleted as staged for the Wrap Up rid only when folder is
/// <support>/staged/<rid> or is named .minmacs-staged-<rid>, and item lies directly in it. A folder that only looks
/// like one, for another rid or one level off, is refused. The marker inside is checked on the disk besides.
NSString *MMRemovalStagingWhyNot(NSString *item, NSString *folder, NSString *rid, NSString *support);
/// The real path of record r's staging folder, "stagedIn", or nil when it is none: its name must be the staging
/// folder of r's Wrap Up and its marker must say that Wrap Up's rid. When r's parent cannot be read, the folder's
/// own name gives the rid, and the marker must agree.
NSString *MMRemovalStagingFolderOf(MMUndoRecord *r);
/// Why nothing may be staged in folder, or nil: a file directly in it must itself pass MMRemovalWallWhyNot, or it
/// could never be deleted from there. So a worktree at the top of a volume, whose staging folder would sit 2 levels
/// below the volume's root, has its items left where they are.
NSString *MMRemovalStagingFolderWhyNot(NSString *folder, MMRemovalPlaces *places);

/// Where a path may be deleted. Every place is a real path: symlinks resolved, in the case the disk holds.
@interface MMRemovalPlaces : NSObject
@property (copy) NSString *home, *support;              // the home folder and MinMacs's own folder
@property (copy) NSString *volume;                      // the root of the volume that holds the path, "/" for the boot volume
@property (copy) NSString *testHome;                    // MINMACS_HOME when set, else nil
@property BOOL foldCase;                                // YES when that volume does not tell upper from lower case
/// The places of the path as the disk says now. path is already real.
+ (instancetype)placesFor:(NSString *)path;
@end

/// The real path of the item itself: every symlink above it resolved and its own name in the case the disk holds.
/// A symlink is named, never followed. nil when it is gone or was not given as a full path. A named pipe, a socket
/// or a device is never opened for it, issue #81. Such an item, and a file or link that has a second name, a hard
/// link, is named by the folder that was asked: that folder's real path and the item's own name as the folder lists
/// it, so never by another of its names. nil too when that folder cannot be listed. MMRemovalPath.m.
NSString *MMRemovalRealPath(NSString *path);
/// For MMRemovalApply.m: the item at path held open for its path and its id alone, a symlink as the link it is, or
/// -1. Nothing is read through it, and the open never waits. A named pipe, a socket or a device is not opened, and
/// *never, when given, says so with YES.
int MMRemovalOpenItem(NSString *path, BOOL *never);

/// The wall, as one rule on strings, so a check can ask it about / or the home folder and delete nothing.
/// A path may be deleted only when all of these hold:
///   1. it is a full path, and one of asked: the paths the fresh finding named, each real
///   2. it is not a volume root, and holds neither the home folder nor MinMacs's own folder
///   3. inside the home folder it lies at least 2 levels down, so never ~/Documents or ~/Library itself
///   4. outside the home folder it lies at least 3 levels below its volume's root, so never /Applications/X.app
///   5. with MINMACS_HOME set it lies inside MINMACS_HOME
/// Returns nil when it may, else the first clause it breaks, in words.
NSString *MMRemovalWallWhyNot(NSString *path, NSArray<NSString *> *asked, MMRemovalPlaces *places);

/// "Deleted 3, moved 2 to the Trash and removed 1 that Restore brings back." from finished records, each counted
/// once by where its thing went. nil when none of them removed anything.
NSString *MMRemovalWhereWords(NSArray<MMUndoRecord *> *records);
