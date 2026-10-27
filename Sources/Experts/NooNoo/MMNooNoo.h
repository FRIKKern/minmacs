// Noo-Noo on the shared core: developer clutter, its owner, its size and how fast it grows. Issues #28, #29 and #30.
// The expert reads MMFacts.clutter, which Know's clutter catalog fills from registry/clutter/*.json on its own
// schedule, plus the worktrees, git facts and sessions in the same facts. It never samples, scans or asks the model.
// Removal runs through MMRunAction and MMClutterAction: the Trash, or the tool's own command after a recovery copy.
// Sources/Experts/NooNoo/README.md says what was ported and what is left open.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Experts/NooNoo/MMNNMenu.h"

@interface MMNooNooExpert : NSObject <MMExpert>
/// The one Noo-Noo. main.m registers it through MMRegisterBuiltInExperts.
+ (instancetype)shared;
/// The catalog the expert's actions check against. The shared one, or a test's own.
@property (strong) MMClutterCatalog *catalog;
/// The menu's view of a snapshot. Pure apart from the undo list, which findingsFrom: read on the graph queue.
- (MMNNView *)viewFor:(MMSnapshot *)s;
/// The item behind one of this expert's findings, in these facts, or nil when it is gone.
- (MMClutterItem *)itemFor:(MMFinding *)f facts:(MMFacts *)facts;
/// The snapshot a verb reads: the graph's latest, or one built now from the graph's fact source, or cold.
- (MMSnapshot *)snapshotNow;
/// One action the person asked for, by menu or CLI, through MMRunAction off main. Returns the record or nil with *error.
- (MMUndoRecord *)clean:(MMFinding *)f by:(NSString *)by error:(NSString **)error;
@end

/// The keep checks of every action: the item on fresh facts must still be free, and no agent may work in its project.
id<MMExpertPolicy> MMNNPolicy(void);
