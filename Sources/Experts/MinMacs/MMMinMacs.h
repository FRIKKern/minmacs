// The MinMacs expert: apps, agents, RAM, CPU, energy and heat. Issue #21.
// Ported from MinMacs 1.2 on branch legacy: the app plan and quit in main.m, force quit, restore,
// browser tab trim in Browser.m, the rules in Rules.m with the fixes for #43, #44 and #45,
// and agent-aware sparing from Agents.m, now read from the Core registry and sessions.
// The expert reads MMFacts and MMSnapshot only. Quit, force quit and trim run through MMRunAction in Core Act.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"

#pragma mark Rules

/// What the rules say about one app, as MinMacs 1.2 named it.
typedef NS_ENUM(NSInteger, MMMinMacsVerdict) { MMMinMacsKeep, MMMinMacsClose, MMMinMacsUnsorted };
NSString *MMMinMacsVerdictName(MMMinMacsVerdict v);   // keep, close, unsorted
NSInteger MMMinMacsVerdictFrom(NSString *name);       // -1 when unknown

/// minmacs/rules.json in the support folder, in the shape MinMacs 1.2 wrote and the migration copies:
/// keep and close lists of bundle ids, an unsorted list, tabs.noise and tabs.work host lists, and ignoreServing.
/// A trailing * matches a prefix, *text* matches inside the id, and an exact id wins over any pattern (#43).
/// ignoreServing matches the same way, and !<bundle id> is an exception to a pattern (#44).
/// Defaults are merged on every load, never moving or removing an entry the person made (#45).
/// Reads and writes go through MMStateFile, so the app and the CLI take turns on the file.
@interface MMMinMacsRules : NSObject
+ (instancetype)shared;
@property (readonly, copy) NSString *path;
@property (readonly) NSArray<NSString *> *keep, *close, *unsorted, *noiseHosts, *workHosts, *ignoreServing;
- (MMMinMacsVerdict)verdictFor:(NSString *)bundleID;
/// Changes only this app's exact entries. A pattern such as com.adobe.* stays for every other app.
- (void)setVerdict:(MMMinMacsVerdict)v forBundleID:(NSString *)bundleID;
- (NSString *)tabVerdictForHost:(NSString *)host;     // noise, work or other. Work wins, and a host matches its subdomains
- (void)addWorkHost:(NSString *)host;
- (void)addNoiseHost:(NSString *)host;
- (BOOL)ignoresServing:(NSString *)bundleID;
- (void)setIgnoresServing:(BOOL)ignore forBundleID:(NSString *)bundleID;
/// Reads the file again and merges defaults it lacks. Writes only when something was added.
- (void)reload;
@end

#pragma mark Browsers

/// One browser tab, read from one browser process.
@interface MMMinMacsTab : NSObject
@property (copy) NSString *url, *title, *host;
@property (copy) NSString *verdict;                     // noise, work or other, from the rules
@property NSInteger windowID, tabID;                    // tabID is the tab's id in Chromium, its index in Safari
@end

/// Reads, closes and reopens tabs, always aimed at one process id, so a second browser instance is never touched.
/// The app uses Apple events through ScriptingBridge. Tests set a fake with MMMinMacsUseTabBridge.
@protocol MMMinMacsTabBridge <NSObject>
/// Tabs of normal windows. Private windows are skipped. nil with *error when the tabs cannot be read.
- (NSArray<MMMinMacsTab *> *)tabsOf:(pid_t)pid bundleID:(NSString *)bundleID error:(NSString **)error;
/// Closes each tab whose URL is still the one read, so a tab that moved on since is kept. Returns the tabs it closed.
- (NSArray<MMMinMacsTab *> *)close:(NSArray<MMMinMacsTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bundleID;
/// Opens the URLs again in the browser at appPath. nil on success, else the problem in words.
- (NSString *)open:(NSArray<NSString *> *)urls bundleID:(NSString *)bundleID appPath:(NSString *)appPath;
@end
void MMMinMacsUseTabBridge(id<MMMinMacsTabBridge> bridge);   // nil goes back to Apple events
id<MMMinMacsTabBridge> MMMinMacsTabBridgeNow(void);
BOOL MMMinMacsIsBrowser(NSString *bundleID);            // a browser MinMacs knows
BOOL MMMinMacsCanTrim(NSString *bundleID);              // one whose tabs it can read
#ifdef MM_TESTS
/// Treats a fixture app as a Chromium browser, so a test never needs a real browser's bundle id.
void MMMinMacsAddTestBrowser(NSString *bundleID);
#endif

#pragma mark Input

/// One running app with its helper processes rolled up, from the sample in MMFacts.
@interface MMMinMacsApp : NSObject
@property pid_t pid;
@property uint64_t startSec;
@property (copy) NSString *bundleID, *name, *bundlePath;
@property double cpuPercent, energyRank;
@property uint64_t memory;
@property NSInteger processCount;
@property (copy) NSArray<NSNumber *> *pids;
@property (copy) NSArray<NSNumber *> *loopbackPorts;    // loopback TCP listeners of its processes
@property (copy) NSString *debugging;                   // "remote debugging on port 9222", or nil
@property (copy) NSString *agentName;                   // the working agent that started it, or nil
@property (copy) NSString *agentPath;                   // that agent's folder, for the graph's owner
@end

/// One agent session, from the registry and sessions in MMFacts.
@interface MMMinMacsAgent : NSObject
@property (copy) NSString *name, *harnessID, *sessionID, *project, *why;
@property MMAgentState state;
@property MMProcKey key;
@property double cpuPercent;
@property uint64_t memory;
@end

/// What the expert reads from one MMFacts: apps, agents and the load.
@interface MMMinMacsInput : NSObject
@property (copy) NSArray<MMMinMacsApp *> *apps;
@property (copy) NSArray<MMMinMacsAgent *> *agents;
@property double totalCPU;                              // over every process, 100 is one core
@property NSInteger memoryPressure;                     // 1 normal, 2 warn, 4 critical
@property NSProcessInfoThermalState thermal;
@end

#pragma mark The expert

@interface MMMinMacsExpert : NSObject <MMExpert>
+ (instancetype)shared;
/// The apps, agents and load in facts. The app rolls them up from facts.sample and NSWorkspace's app list.
/// The render tool and tests set inputFrom to fixture input instead.
@property (copy) MMMinMacsInput *(^inputFrom)(MMFacts *facts);
- (MMMinMacsInput *)inputFrom:(MMFacts *)facts;
/// Seconds an app gets to quit on its own before Quit reports it still running. The pref minmacs.grace, 8 by default.
@property (readonly) NSTimeInterval grace;
/// The snapshot a verb reads: the graph's latest, or one built now from the graph's fact source when Core runs cold.
- (MMSnapshot *)snapshotNow;
/// Its part of `minmacs status`, as JSON and as one line.
- (NSDictionary *)statusJSON:(MMSnapshot *)s;
- (NSString *)statusLine:(MMSnapshot *)s;
/// Its part of `minmacs restore`: every MinMacs record that can be restored, or the one with rid.
/// Reopens trimmed tabs through the tab bridge, then restores the record through MMUndo. Blocks. Never on main.
/// Returns one result per record: rid, subject, ok and problem.
- (NSArray<NSDictionary *> *)restore:(NSString *)rid dryRun:(BOOL)dryRun;
/// YES when this app instance was asked to quit before, so Force Quit is a second request.
- (BOOL)quitAskedFor:(MMFinding *)f;
@end
