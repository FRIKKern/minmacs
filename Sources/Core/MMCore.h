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
#import "Core/Know/MMTreeDisk.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Graph/MMHistory.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Review/MMReview.h"
#import "Core/Review/MMInvestigate.h"
#import "Core/Act/MMUndo.h"
#import "Core/Act/MMAct.h"
#import "Core/Act/MMWorktreeAct.h"
#import "Core/Act/MMClutterAct.h"
#import "Core/MMExpert.h"
#import "Core/MMSheet.h"
#import "Core/Store/MMDayLog.h"

NS_ASSUME_NONNULL_BEGIN
/// Starts Core in order: Store, Senses, Know, the graph with its fact source, the review broker and the core socket.
/// Call once on the main thread, after the experts are registered. Safe to call twice.
void MMCoreStart(void);
/// Stops the timers, streams and socket that MMCoreStart started.
void MMCoreStop(void);

/// P63. What the running app answers on core.sock. A request is a JSON object with a "verb" key, such as
/// {"verb": "ping"}, and the reply is a JSON object. A reply with an "error" key failed.
typedef NSDictionary *_Nullable (^MMCoreRequestHandler)(NSDictionary *request);
/// Adds the handler for one verb, or removes it when handler is nil. Core serves "ping" and "status" itself.
/// Handlers run on MMQueue(@"core", @"socket"), one request at a time. Sources/CLI adds the verbs that run in the app.
void MMCoreServe(NSString *verb, MMCoreRequestHandler _Nullable handler);
/// Routes one request to its verb's handler. The socket calls this; a test may call it directly.
NSDictionary *MMCoreHandleRequest(NSDictionary *request);
NS_ASSUME_NONNULL_END
