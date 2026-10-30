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

#pragma mark - A row's own cleanup command, for good

/// Designs 74 and 75: a tool row's own cleanup command, such as `pnpm store prune`, run for good. No recovery copy is
/// made, so it cannot be undone, and its record says so. MMRunAction runs it, with the record kind "tool", which
/// -[MMUndo restore:] refuses.
/// Only a person asks for it: by must be "manual" or "cli", and recheck refuses anything else. No expert hands it to a
/// mode, a plan, Tidy or Wrap Up, since -[MMExpert actionFor:step:] never returns it.
/// recheck, right before it runs: the row still names the command and is not report only, the tool's binary is still
/// the executable file MMClutterToolPath named when the action was made, no app the row's quitFirst names is running,
/// the item is still there and free, and every path passes the walls.
/// perform, through MMRunTask with a time limit each: the dry-run form first when the row has one, and nothing more
/// when it fails; then the command. The payload keeps the command line, each run's output tail, exit status and
/// whether it ran past its limit, the size of the item's paths before and after, read again with MMSizer, and
/// "undo": why it cannot be undone.
@interface MMClutterCommandAction : NSObject <MMAction>
+ (instancetype)actionFor:(MMFinding *)finding item:(MMClutterItem *)item catalog:(MMClutterCatalog *)catalog by:(NSString *)by;
@property (readonly) MMClutterItem *item;
@property (readonly, copy) NSString *by;
/// The binary MMClutterToolPath named when the action was made, or nil when none is installed.
@property (readonly, copy) NSString *toolPath;
/// The time limit of the command, 300 seconds, and of its dry run, 120 seconds.
@property NSTimeInterval timeout, dryRunTimeout;
/// The button's title, from MMClutterCommandTitle.
@property (readonly, copy) NSString *title;
/// -dryRun runs the row's dry-run form when it has one, keeps the result here and in MMClutterLastDryRun, and says
/// what it would free from its output. Without a dry-run form it runs nothing and says what the last scan measured.
/// {kindID, command, at, exit, timedOut, output, wouldFree}. wouldFree is -1 when the output names no size.
@property (readonly) NSDictionary *lastDryRun;
@end

/// "Run pnpm store prune, Cannot Be Undone". nil for a row with no command.
NSString *MMClutterCommandTitle(MMClutterKind *kind);
/// What a cleanup tool's output says it frees or would free, in bytes, or -1 when it names no size.
/// Reads the last size on a line that says free, reclaim, remove, delete, total or would, such as Docker's
/// "Total reclaimed space: 1.2GB" or Homebrew's "would free approximately 340MB". kB, MB, GB and TB count in
/// thousands, KiB, MiB, GiB and TiB in 1024s.
int64_t MMClutterFreedFromOutput(NSString *output);
/// The last dry run of a row's command, as -[MMClutterCommandAction lastDryRun] gave it, kept in
/// <noonoo>/commands.json. nil before the first. It reads the file again only when the file changed, so it stats the
/// file each call: call it off main, as findingsFrom: runs on the graph queue.
NSDictionary *MMClutterLastDryRun(NSString *kindID);
/// The bundle ids among the row's quitFirst that run now, from MMRunningApps. Empty when none runs.
NSArray<NSString *> *MMClutterRunningQuitFirst(MMClutterKind *kind);
/// Where MMClutterRunningQuitFirst reads the running apps' bundle ids. Tests pass a fixture list. nil goes back to
/// MMRunningApps.
typedef NSArray<NSString *> *(^MMClutterAppsProvider)(void);
void MMClutterUseRunningApps(MMClutterAppsProvider provider);
