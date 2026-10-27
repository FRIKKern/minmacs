// Insomnia on the shared core: keeps the Mac awake while an agent works, and lets it sleep when nothing does.
// Issue #31. Ported from Insomnia's one main.m. The expert reads agents and sessions from the snapshot, power, lid,
// heat and network from MMPower, and holds the Mac awake through MMAwake in Core Act, one hold per working agent's pid.
// The lid override runs through MMLidOverride and MMRunAction. The expert never samples, scans or runs a process.
// Sources/Experts/Insomnia/README.md says what was ported and what is left open.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"

#pragma mark Prefs

/// Every Insomnia pref, read once per pass. Keys and defaults follow Insomnia, under the insomnia. prefix of the one
/// prefs domain. Decision 4 changes two defaults: Keep Mac Awake starts off and Awake While Agents Work starts on.
@interface MMINPrefs : NSObject <NSCopying>
@property BOOL manual;                  // insomnia.awake, NO. "Keep Mac Awake": the person's own switch
@property BOOL agents;                  // insomnia.agents, YES. "Awake While Agents Work"
@property BOOL lid;                     // insomnia.lid, NO. "Keep Awake With Lid Closed"
@property BOOL screenOff;               // insomnia.lid.screenOff, YES. Sleep the display when the lid closes
@property BOOL thermalGuard;            // insomnia.lid.thermalGuard, YES. The bag guard
@property NSInteger minBattery;         // insomnia.lid.minBattery, 20 percent
@property NSInteger graceMinutes;       // insomnia.lid.graceMinutes, 120. 0 is never
@property NSInteger offlineMinutes;     // insomnia.lid.offlineMinutes, 15. 0 is never
@property NSInteger quietMinutes;       // insomnia.agents.quietMinutes, 10
+ (instancetype)defaults;
@end
/// Reading the prefs needs Core Store, so it sits apart from the data the render tool draws.
@interface MMINPrefs (MMINStore)
+ (instancetype)current;                // reads the prefs. Never on main in the app
@end

#pragma mark Guards

/// The guard clocks and the bag guard's hold. Insomnia kept the two clocks in its prefs, so they survive a relaunch.
@interface MMINClocks : NSObject <NSCopying>
@property (copy) NSDate *unpluggedAt;   // insomnia.unpluggedAt, nil on the charger
@property (copy) NSDate *offlineAt;     // insomnia.offlineAt, nil while online
@property BOOL thermalHold;             // insomnia.thermalHold: hot with the lid closed on battery, until lid open or AC
@end

/// The clocks after one reading. From the top of -syncLid, IN main.m:648-659. Pure.
/// The charger clears the unplugged clock, a route clears the offline clock, and the thermal hold is set at serious
/// or worse with the lid closed on battery, and cleared only by the charger, an open lid or the guard turned off.
MMINClocks *MMINAdvance(MMINClocks *old, MMPower *p, MMINPrefs *prefs, NSDate *now);
/// Why the battery guards pause the lid override right now, or nil. From -pauseReason, IN main.m:631. Pure.
/// Only on battery, in this order: battery at or below the threshold, unplugged past the grace, the thermal hold,
/// offline past its limit.
NSString *MMINPauseReason(MMPower *p, MMINPrefs *prefs, MMINClocks *c, NSDate *now);
/// YES on battery at or below the battery guard. Agent holds end then. Keep Mac Awake stays, since manual wins.
BOOL MMINLowBattery(MMPower *p, MMINPrefs *prefs);

#pragma mark Input

/// One process that may hold the Mac awake: an agent, a session the registry did not match, or a hold a script asked
/// for through -[MMGraph holdAwake:pid:].
@interface MMINWorker : NSObject
@property MMProcKey key;
@property (copy) NSString *kind;        // agent, session or hold
@property (copy) NSString *name;        // "Claude Code", or the process name for a hold
@property (copy) NSString *harness, *sessionID, *cwd, *why;
@property BOOL working;                 // working now. Waiting on the person is not working
@property (copy) NSString *stableKey;   // harness and session or folder, never a pid
@end

/// What the expert reads from one MMFacts.
@interface MMINInput : NSObject
@property (copy) NSArray<MMINWorker *> *workers;
/// YES while the standalone Insomnia app runs. It owns the lid override then, so this expert never writes it.
@property BOOL otherApp;
@end

/// The workers in facts: agents from the registry, then sessions whose live status says a turn runs and whose pid no
/// agent has. Waiting on the person and "shell" are not working. Pure.
MMINInput *MMINInputFrom(MMFacts *facts);

#pragma mark State

/// One holder in the state, for rows, cards and --json.
@interface MMINHolder : NSObject
@property (copy) NSString *findingID, *kind, *name, *project, *why, *keyString;
@property pid_t pid;
@property BOOL working;
@property NSTimeInterval idleFor;       // seconds since it last worked, 0 while it works
@property BOOL held;                    // YES when it has its own assertion pair. NO when Keep Mac Awake holds for it
@property (copy) NSString *linkExpert, *linkFindingID, *linkValue;   // the MinMacs card of the agent, when there is one
@end

/// What one pass decided and did. Immutable once published. The menu, the cards and the verbs read it.
@interface MMINState : NSObject
@property (copy) MMINPrefs *prefs;
@property (copy) MMINClocks *clocks;
@property (strong) NSDate *at;
/// The power facts the pass read, copied, so the menu needs no Senses object.
@property BOOL onAC, lidClosed, online;
@property int batteryPercent;                     // -1 without a battery
@property NSProcessInfoThermalState thermal;
@property (copy) NSArray<MMINHolder *> *holders;  // the agents and holds that keep the Mac awake, working first
@property NSInteger watched;                      // agents and sessions seen in the snapshot
@property BOOL holding;                           // any assertion is held, manual or for a holder
@property BOOL lowBattery;                        // agent holds ended on low battery
@property BOOL lidLive;                           // the override is set, as IOKit or the last write says
@property BOOL lidWanted;
@property (copy) NSString *pauseReason;           // the guard that pauses it, nil when none does
@property (copy) NSString *lidProblem;            // why the override cannot be written, nil when it can
@property BOOL otherApp;
@property BOOL laptop;                            // a battery exists, so lid mode applies
@property NSTimeInterval releaseIn;               // seconds until the last quiet hold ends, 0 when none waits
@property NSInteger asserted;                     // MMAwake holds right now
@end

/// The decision of one pass, with no side effects. The engine applies it; the CLI shows it when no app runs.
/// last maps a worker's key string to when it last worked. skipped holds the keys the person let sleep.
MMINState *MMINDecide(MMINInput *input, MMPower *power, MMINPrefs *prefs, MMINClocks *clocks,
                      NSDictionary<NSString *, NSDate *> *last, NSSet<NSString *> *skipped,
                      NSDictionary<NSString *, NSString *> *explicitHolds, MMSnapshot *s, NSDate *now);
/// The state as JSON, for `minmacs awake --json`.
NSDictionary *MMINStateJSON(MMINState *st);

#pragma mark Menu

/// The menu's view: the state and a block that carries out an action on the expert's queue.
/// what: manual, lid, agents, screen, heat, skip. key: a holder's findingID for skip.
@interface MMINView : NSObject
@property (strong) MMINState *state;
@property (copy) void (^act)(NSString *what, NSString *key);
@end
MMMenuSpec *MMINMenu(MMINView *v);
MMCardSpec *MMINCard(MMINView *v, NSString *findingID);   // a holder's card or the lid card, insomnia:lid
NSString *MMINAccessibilityState(MMINState *st);
NSString *MMINHeadline(MMINState *st);
extern NSString *const MMINLidFindingID;

#pragma mark The expert

@interface MMInsomniaExpert : NSObject <MMExpert>
/// The one Insomnia. main.m registers it through MMRegisterBuiltInExperts.
+ (instancetype)shared;
/// The input in facts. The render tool and tests set fixture input here, as MinMacs does with inputFrom.
@property (copy) MMINInput *(^inputFrom)(MMFacts *facts);
/// The clock. Tests move it to walk the guard clocks and the quiet period.
@property (copy) NSDate *(^clock)(void);
/// The last state a pass published, nil before the first. Any queue.
@property (readonly, strong) MMINState *state;
/// One pass on the expert's queue: decide from s and the latest power, hold and release, write the lid override
/// through MMRunAction when it must change, and publish the state. Waits for the pass. Never on main.
- (MMINState *)reconcile:(MMSnapshot *)s;
/// Changes one pref, as the menu and the CLI do, then passes once. what: manual, agents, lid, screen, heat,
/// battery, unplugged, offline, quiet. Runs through MMRunAction with by, so it has an undo record. Never on main.
/// Returns nil, or why it did not change.
- (NSString *)set:(NSString *)what value:(id)value by:(NSString *)by;
/// The pids the menu let sleep, until each exits.
- (void)skip:(NSString *)keyString;
/// Starts watching the graph, Senses and the minute clock. The app calls it once, through the first build.
- (void)start;
@end

/// The verbs, in MMINCLI.m.
NSArray<MMVerbSpec *> *MMINVerbs(void);
