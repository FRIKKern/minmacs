// The removal choice, issue #62: what happens to a thing MinMacs removes is the person's choice.
//
//   pref core.removal      a merged worktree     .env, untracked config    a rebuilt cache or build    a leftover, logs
//   smart (the default)    git removes it        recovery folder, Trash    deleted at once             Trash
//   trash                  git removes it        recovery folder, Trash    Trash                       Trash
//   delete                 git removes it        deleted at once           deleted at once             deleted at once
//
// Until the person has chosen, which is while the pref has no value, an act MinMacs starts on its own keeps a way
// back as Trash does. Smart's deletes then apply only to the person's own presses.
// Every path that removes something asks MMRemovalDecide, and none decides by itself. The answer is made on the
// facts the caller read fresh at the moment of the act. It changes only where a removed thing goes. The fresh check,
// MustKeep and the record of MMRunAction run first in every choice, a git bundle is taken whenever commits are on no
// remote, git never runs with --force, and MinMacs never empties the Trash and never deletes from it.
#import <Foundation/Foundation.h>
#import "Core/Know/MMClutter.h"
@class MMUndoRecord, MMRemovalPlaces;

/// The three choices. Smart deletes only what git or its own tool can give back.
typedef NS_ENUM(NSInteger, MMRemovalChoice) { MMRemovalSmart = 0, MMRemovalTrash = 1, MMRemovalDelete = 2 };
extern NSString *const MMRemovalKey;                    // @"core.removal": smart, trash or delete. smart by default
/// The pref, read now. No value is Smart. A value that is none of the three is Trash, the choice that loses nothing.
MMRemovalChoice MMRemovalChoiceNow(void);
/// YES once the pref has a value: the person set it in the welcome, in Settings or with `minmacs removal`.
BOOL MMRemovalChosen(void);
/// What Settings and the CLI say while nothing is chosen, or nil once it is.
NSString *MMRemovalNotChosenNote(void);
void MMSetRemovalChoice(MMRemovalChoice choice);
NSString *MMRemovalChoiceName(MMRemovalChoice choice);  // smart, trash, delete
NSInteger MMRemovalChoiceFrom(NSString *name);          // -1 when unknown
/// The window's words: "Smart", "Trash", "Delete", and one plain sentence each.
NSString *MMRemovalChoiceTitle(MMRemovalChoice choice);
NSString *MMRemovalChoiceExplain(MMRemovalChoice choice);

/// What is about to be removed.
typedef NS_ENUM(NSInteger, MMRemovalThing) {
    MMRemovalWorktree,       // a linked worktree, which `git worktree remove` takes with no --force
    MMRemovalIgnoredFiles,   // the files in it that git ignores and no cache row names, such as .env
    MMRemovalConfigFiles,    // the untracked config files Wrap Up moves first, such as .env.local
    MMRemovalClutter,        // one item of a cache, build or leak row
    MMRemovalToolCopy,       // what a tool's own cleanup removes, which a recovery copy would keep
};

/// The fresh facts of the thing, read by the caller right before it acts. A fact nobody set counts against deleting.
@interface MMRemovalFacts : NSObject
// A worktree. A count is -1 while git could not tell.
@property BOOL gitKnown, merged, upstreamGone;
@property NSInteger dirty, untracked, unpushed, stashes;
// Clutter and a tool's cleanup.
@property MMClutterClass klass;
@property BOOL rebuilt, free, ownerGone;                // rebuilt: -[MMClutterKind rebuilt]. free: MMClutterFree now
/// Why the rebuild is not proven on the item read now, -[MMClutterItem unproven], or nil. Any reason keeps a way back.
@property (copy) NSString *unproven;
+ (instancetype)worktreeKnown:(BOOL)known merged:(BOOL)merged upstreamGone:(BOOL)gone dirty:(NSInteger)dirty
                    untracked:(NSInteger)untracked unpushed:(NSInteger)unpushed stashes:(NSInteger)stashes;
+ (instancetype)clutter:(MMClutterItem *)item;          // from the item -[MMClutterCatalog inspect:] just read
@end

/// The answer for one thing: delete now, or keep a way back, and why in plain words.
@interface MMRemovalDecision : NSObject
@property (readonly) MMRemovalChoice choice;
@property (readonly) MMRemovalThing thing;
@property (readonly) BOOL deleteNow;
@property (readonly, copy) NSString *why;
- (NSDictionary *)json;                                 // {choice, deleted, why}, as the record's payload keeps it
@end

/// The one function. Reads the pref now. by is who asked, as MMRunAction takes it: "manual" or "cli" for a press,
/// "proactive", "eager" or "guard" for an act MinMacs starts on its own. nil counts as a press, for words shown
/// before anybody acts.
///   not chosen yet   an act MinMacs starts on its own never deletes. A press follows Smart.
///   trash    never deletes.
///   delete   always deletes.
///   smart    a worktree only when it is merged or its remote branch is gone, with no uncommitted change, no untracked
///            file, no commit on no remote and no stash. Ignored and config files never, since git does not hold them.
///            Clutter only when its row says rebuilt, the fresh check proves it, it is a cache or build row, it is free
///            now and its owner is not gone. A tool's cleanup runs with no recovery copy only when its row says rebuilt.
MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts, NSString *by);
/// The same for a given choice the person made, asked by a press, with no pref read.
MMRemovalDecision *MMRemovalDecideWith(MMRemovalChoice choice, MMRemovalThing thing, MMRemovalFacts *facts);
/// The same with everything given: the choice, whether the person chose it, and who asks.
MMRemovalDecision *MMRemovalDecideAs(MMRemovalChoice choice, BOOL chosen, NSString *by, MMRemovalThing thing, MMRemovalFacts *facts);

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

/// Removes the item at path as the decision says. Keep a way back: -[MMUndo trash:record:error:]. Delete now: the
/// item is unlinked, never followed through a symlink, and the record's payload lists it under "deleted" as {path}.
/// Before it deletes it asks MMRemovalWallWhyNot on the item's real path. This is the only place Act deletes a file.
///
/// A part of a Wrap Up, a record with a parent, never deletes here, since a later part, such as git worktree
/// remove, may still refuse. Its item is renamed into a staging folder of MinMacs's own on the item's own volume and
/// listed under "staged": <support>/staged/<wrap up rid>/, or for another volume a hidden folder
/// .minmacs-staged-<wrap up rid> beside the worktree. It is one rename and never a copy. When no such rename can be,
/// or the staging folder would lie where the wall lets nothing be deleted, the item stays where it is and is listed
/// under "unstaged". Nothing waits in the person's Trash.
BOOL MMRemovalApply(NSString *path, MMRemovalDecision *decision, MMUndoRecord *record, NSError **error);
/// Every part went through: deletes what these parts staged, each checked to be the same file, in the staging folder
/// MinMacs made for this Wrap Up, then removes the empty folder and marks each part deleted. An item that cannot be
/// deleted stays staged, and its part can still restore. Returns the bytes the volume got back.
int64_t MMRemovalFinishStaged(NSArray<MMUndoRecord *> *parts);
/// A later part of the Wrap Up refused, so the worktree stays: renames each staged item back to its exact old path,
/// newest first, and moves back what these removal parts sent to the Trash to keep. Each item on its own: one that
/// cannot go back, since something sits at its old path now, stays where it waits and is reported, and the others
/// still go. A second call moves the rest. A part whose every item is back is marked restored, and the empty
/// staging folder is removed.
/// A stop or a quit is not taken back here. Returns nil, or what could not go back.
NSString *MMRemovalPutBack(NSArray<MMUndoRecord *> *parts);
/// After a crash: a Wrap Up whose record never finished and whose process is gone is settled at once. Nothing is
/// deleted: what its removal parts had moved, to the staging folder or to the Trash, goes back to its old path, and
/// the record and every part still pending are failed, so none stays pending. Only one that had every part through
/// and had begun its deletes, payload "finishing", is finished. The record's "owner", MMRemovalOwner, says whose it
/// is: a Wrap Up whose process lives is never touched, whatever its age. A record with no owner is settled once it is
/// 15 minutes old. MMCoreStart and MMRunWrapUp call it, off main. Returns how many Wrap Ups it settled.
NSInteger MMRemovalRecoverStaged(void);
/// {pid, start}: this process, for the Wrap Up record it begins.
NSDictionary *MMRemovalOwner(void);
/// What was left staged though its Wrap Up ended, such as after a put-back that stopped halfway: each item the
/// record still names goes back to its old path. A folder under <support>/staged that no record names is left alone
/// and returned in *orphans the first time it is seen, for the log. Nothing is deleted but an empty staging folder.
/// MMCoreStart calls it after MMRemovalRecoverStaged. Returns how many parts it put back.
NSInteger MMRemovalSweepStaged(NSArray<NSString *> **orphans);
/// The staging folder as a rule on strings: item may be deleted as staged for the Wrap Up rid only when folder is
/// <support>/staged/<rid> or is named .minmacs-staged-<rid>, and item lies directly in it. A folder that only looks
/// like one, for another rid or one level off, is refused. The marker inside is checked on the disk besides.
NSString *MMRemovalStagingWhyNot(NSString *item, NSString *folder, NSString *rid, NSString *support);
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
/// A symlink is named, never followed. nil when it is gone or was not given as a full path.
NSString *MMRemovalRealPath(NSString *path);

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
