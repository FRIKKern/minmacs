// Removing clutter. Patterns P51 to P53 applied to the clutter catalog of P28, for Noo-Noo's rows.
// Principle 5 and decision 1: build output, caches and leftovers go to the Trash. A tool row runs the tool's own
// command, after a recovery copy of what it may remove. Nothing is deleted for good, and every action can be undone.
#import <Foundation/Foundation.h>
#import "Core/Act/MMAct.h"
#import "Core/Know/MMClutter.h"

/// P51 to P53. One clutter item, checked fresh right before it acts. MMRunAction runs it.
/// New code, from NN's Apply in internal/leaks/module.go: staleness is proven again at apply time, every path
/// passes -[MMClutterCatalog whyNot:kind:], and the freed bytes are the statfs delta MMRunAction records.
///   kind "trash"  cache, build and leak rows. Each path goes to the Trash through MMUndo, and restore moves it back.
///   kind "clean"  tool rows. An APFS clone of each path goes to <noonoo>/recovery/<rid>, the dry run and the command
///                 run through MMToolCommand, and what the tool removed is listed as the record's recovery files,
///                 so restore copies them back. The minmacs-recovery row sends the copy to the Trash after 7 days.
/// The payload also holds "audit": the paths, their sizes and newest change before and after the action.
@interface MMClutterAction : NSObject <MMAction>
+ (instancetype)actionFor:(MMFinding *)finding item:(MMClutterItem *)item catalog:(MMClutterCatalog *)catalog;
@property (readonly) MMClutterItem *item;
@end

/// The audit of each path: whether it exists, its allocated size, its file count and its newest change.
NSArray<NSDictionary *> *MMClutterAudit(NSArray<NSString *> *paths);
