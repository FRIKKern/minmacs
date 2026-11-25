// The insides of an app row, for the window's model: cmux's workspaces, panes and tabs, with the agent, the folder or
// worktree, the servers, CPU and memory of each, UI/Window/MMWindowInsides.h. What cmux says comes from MMAppInsides's
// memory; everything else from the snapshot, as each row's story does. Nothing here asks cmux or runs a process.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Core/Know/MMAppInsides.h"
#import "UI/Window/MMWindowInsides.h"

NS_ASSUME_NONNULL_BEGIN

/// The bundle id of an app row whose insides MinMacs reads, or nil.
NSString *_Nullable MMWindowInsidesApp(MMWindowRow *row);
/// Gives each such app row of m its insides from answer a, which may be nil before the first ask: the rows under it,
/// its story's section, and the state `--json` prints. With the app unreachable or older, its process tree as the
/// snapshot's sample knows it, and one line that says why.
void MMWindowInsidesAttach(MMWindowModel *m, MMSnapshot *s, MMInsidesAnswer *_Nullable a);

/// For `minmacs window`: cmux read once now, off main and within MMAppInsides's limit, when m has a cmux row. nil
/// without one: then nothing is asked.
MMInsidesAnswer *_Nullable MMWindowInsidesReadOnce(MMWindowModel *m);


NS_ASSUME_NONNULL_END
