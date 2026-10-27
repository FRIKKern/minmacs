// The command line side of the one binary, patterns P61 and P63. `minmacs <verb>` runs a verb and exits.
// One verb registry. Core's own verbs live in MMCoreVerbs.m, and each registered expert adds the verbs its
// -verbs returns. The CLI asks a running app first, over core.sock. When no app answers it runs Core cold,
// and a verb that changes things refuses with MMExitNeedsApp unless it is given --dry-run.
// Old names keep working: a symlink named locohost runs LocoHost's verbs with LocoHost 1.x syntax,
// and MinMacs 1.x verbs such as plan and agents map to their 2.0 verbs.
#import <Foundation/Foundation.h>
#import "CLI/MMArgs.h"

@class MMSnapshot, MMVerbSpec;
@protocol MMExpert, MMFactSource;

// The version shown by `minmacs version` and in the menu. build.sh passes it from Info.plist.
#ifndef MM_VERSION
#define MM_VERSION "0.0.0"
#endif
extern NSString *const MMPhase;

/// YES when argv names a verb, so main runs the CLI instead of the app.
/// Finder and launchd may pass flags such as -psn_0_123, which are not verbs.
BOOL MMWantsCLI(int argc, const char *argv[]);

/// Runs the verb in argv[1] and returns the exit status. 2 means an unknown verb.
int MMRunCLI(int argc, const char *argv[]);

/// The program a path names: "locohost" for a symlink named locohost, "minmacs" for anything else.
/// A legacy name is one a registered expert gives as legacyName, or one of the five standalone app names.
NSString *MMProgramName(const char *argv0);

/// The legacy names of the five standalone apps, mapped to the expert id each became.
NSDictionary<NSString *, NSString *> *MMLegacyNames(void);

/// The words a legacy program's command means in 2.0, such as locohost "list" as "hosts".
/// nil when the program has no alias for it, so the words run as they are.
NSArray<NSString *> *MMLegacyWords(NSString *program, NSArray<NSString *> *words);

/// The verb that words[0] runs for program, from Core's verbs and every registered expert's.
/// The expert a legacy program names is asked first, then Core, then the experts in menu bar order.
MMVerbSpec *MMFindVerb(NSString *program, NSString *verb);
/// Every verb: Core's first, then each expert's, in menu bar order. Hidden verbs start with an underscore.
NSArray<MMVerbSpec *> *MMAllVerbs(void);
/// Core's own verbs, from MMCoreVerbs.m.
NSArray<MMVerbSpec *> *MMCoreVerbs(void);

/// The app's side of core.sock, for a request of {"cli": [words], "program", "cwd"}, or {"ping": 1}.
/// Runs the verb with its output collected and replies {"status", "out", "err"}. nil for any other request,
/// so another handler on the socket can answer it. Runs on the socket queue.
NSDictionary *MMCLIReply(NSDictionary *request);

/// The snapshot a verb reads. In the app, the graph's latest. In the CLI, one built cold from the graph's
/// fact source when one is set, else from a one-time sample of Senses and Know.
MMSnapshot *MMCLISnapshot(BOOL inApp);
/// The same, after a second sample. Cold, it hands the first sample to every expert's findings, waits a second and
/// builds from a second one, so CPU and new connections count. In the app, the graph's latest.
MMSnapshot *MMCLISettledSnapshot(BOOL inApp);
/// The fact source the CLI reads when it runs cold and the graph has none. Tests set fixture facts here.
/// A cold CLI with no source of its own uses MMColdFacts, one sample of Senses and Know, and gives it to the graph
/// as well, so an action's fresh check reads the same source. No expert samples for the CLI.
void MMSetCLIFactSource(id<MMFactSource> source);

/// Runs block on the main thread and waits. Runs it at once when already on main.
/// Menu and card specs are main thread only, and a verb in the app runs on the socket queue.
void MMOnMain(dispatch_block_t block);

/// A JSON-safe copy: dates become seconds since 1970, and values JSON cannot hold become strings.
id MMJSONSafe(id value);
