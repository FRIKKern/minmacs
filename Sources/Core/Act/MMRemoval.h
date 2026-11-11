// The removal choice, issue #62: what happens to a thing MinMacs removes is the person's choice.
//
//   pref core.removal      a merged worktree     .env, untracked config    a rebuilt cache or build    a leftover, logs
//   smart (the default)    git removes it        recovery folder, Trash    deleted at once             Trash
//   trash                  git removes it        recovery folder, Trash    Trash                       Trash
//   delete                 git removes it        deleted at once           deleted at once             deleted at once
//
// Every path that removes something asks MMRemovalDecide, and none decides by itself. The answer is made on the
// facts the caller read fresh at the moment of the act. It changes only where a removed thing goes. The fresh check,
// MustKeep and the record of MMRunAction run first in every choice, a git bundle is taken whenever commits are on no
// remote, git never runs with --force, and MinMacs never empties the Trash.
#import <Foundation/Foundation.h>
#import "Core/Know/MMClutter.h"
@class MMUndoRecord;

/// The three choices. Smart deletes only what git or its own tool can give back.
typedef NS_ENUM(NSInteger, MMRemovalChoice) { MMRemovalSmart = 0, MMRemovalTrash = 1, MMRemovalDelete = 2 };
extern NSString *const MMRemovalKey;                    // @"core.removal": smart, trash or delete. smart by default
/// The pref, read now. No value is Smart. A value that is none of the three is Trash, the choice that loses nothing.
MMRemovalChoice MMRemovalChoiceNow(void);
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

/// The one function. Reads the pref now.
///   trash    never deletes.
///   delete   always deletes.
///   smart    a worktree only when it is merged or its remote branch is gone, with no uncommitted change, no untracked
///            file, no commit on no remote and no stash. Ignored and config files never, since git does not hold them.
///            Clutter only when its row says rebuilt, it is a cache or build row, it is free now and its owner is not
///            gone. A tool's cleanup runs with no recovery copy only when its row says rebuilt.
MMRemovalDecision *MMRemovalDecide(MMRemovalThing thing, MMRemovalFacts *facts);
/// The same for a given choice, with no pref read, so a check can ask about each choice.
MMRemovalDecision *MMRemovalDecideWith(MMRemovalChoice choice, MMRemovalThing thing, MMRemovalFacts *facts);

/// Removes item as the decision says. Keep a way back: -[MMUndo trash:record:error:]. Delete now: the item is
/// unlinked, never followed through a symlink, and the record's payload lists it under "deleted" as {path}.
/// It refuses /, the home folder, the support folder and anything that holds them, and with MINMACS_HOME set anything
/// outside MINMACS_HOME, so no check can delete a real file. This is the only place Act deletes a file.
BOOL MMRemovalApply(NSURL *item, MMRemovalDecision *decision, MMUndoRecord *record, NSError **error);
/// Writes the decision into the record as payload "removal", before the caller acts on it. key names a second
/// decision of the same record, such as @"ignored" for a worktree's ignored files, kept inside "removal".
void MMRemovalNote(MMUndoRecord *record, MMRemovalDecision *decision, NSString *key);

/// "Deleted 3, moved 2 to the Trash and removed 1 that Restore brings back." from finished records, each counted
/// once by where its thing went. nil when none of them removed anything.
NSString *MMRemovalWhereWords(NSArray<MMUndoRecord *> *records);
