// The command line side of the one binary. `minmacs <verb>` runs a verb and exits.
// Phase 0 has one verb. Experts add theirs to the table in MMCLI.m.
#import <Foundation/Foundation.h>

// The version shown by `minmacs version` and in the menu. build.sh passes it from Info.plist.
#ifndef MM_VERSION
#define MM_VERSION "0.0.0"
#endif
extern NSString *const MMPhase;

// YES when argv names a verb, so main runs the CLI instead of the app.
// Finder and launchd may pass flags such as -psn_0_123, which are not verbs.
BOOL MMWantsCLI(int argc, const char *argv[]);

// Runs the verb in argv[1] and returns the exit status. 2 means an unknown verb.
int MMRunCLI(int argc, const char *argv[]);
