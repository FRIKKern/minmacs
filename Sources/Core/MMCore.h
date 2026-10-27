// MinMacs Core: every Core header in one import. Sources/Core/README.md maps each pattern P1 to P66 to its header.
// P65, the one build, test and release script set, is build.sh, test.sh and .github/workflows/ci.yml.
// P66, test isolation, is MINMACS_HOME in MMSupportDir, the env homes in test.sh, and MMPowerSource under MM_TESTS.
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#import "Core/Runtime/MMCoreSocket.h"
#import "Core/Senses/MMSenses.h"
#import "Core/Senses/MMFolders.h"
#import "Core/Know/MMRegistry.h"
#import "Core/Know/MMSessions.h"
#import "Core/Know/MMWhere.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Know/MMSizer.h"
#import "Core/Know/MMClutter.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Review/MMReview.h"
#import "Core/Act/MMUndo.h"
#import "Core/Act/MMAct.h"
#import "Core/MMExpert.h"

NS_ASSUME_NONNULL_BEGIN
/// Starts Core in order: Store, Senses, Know, the graph with its fact source, the review broker and the core socket.
/// Call once on the main thread, after the experts are registered. Safe to call twice.
void MMCoreStart(void);
/// Stops the timers, streams and socket that MMCoreStart started.
void MMCoreStop(void);
NS_ASSUME_NONNULL_END
