// The migration from the five old apps, PLAN.md section 8 and issue #37.
// The import reads the old prefs domains and state files and never writes them. The follow-up runs once after it,
// off main: it turns off a lid override the old Insomnia left on, then asks once about Noo-Noo's LaunchAgent and
// once about the old apps. Every read goes through home, so a test points it at a copy inside MINMACS_HOME.
#import <Foundation/Foundation.h>

/// What the five old apps leave in home, read and never changed, so 2.0 can import it.
/// home is the home folder to read from, nil for the person's own. Tests pass a copy inside MINMACS_HOME.
/// For the person's own home a prefs domain is read through CFPreferences, which only reads here. For any other
/// home it is read from <home>/Library/Preferences/<domain>.plist. The sources, by name:
///   locohost     no.guerrilla.locohost, Application Support/LocoHost: rules, activity, keep, closed and review
///   minmacs-1.2  no.guerrilla.minmacs, Application Support/MinMacs/rules.json, the closed apps and tabs
///   workforest   no.guerrilla.workforest, Application Support/WorkForest: rules, review and removed.json
///   insomnia     no.guerrilla.insomnia
///   noonoo       io.noo-noo.app for its icon, .config/noo-noo/config.toml and Application Support/noo-noo/store.db
/// The plan is a dictionary:
///   prefs   key to value, in 2.0 keys, only keys 2.0 does not hold yet
///   files   published path under the support folder to the JSON it gets
///   rows    log rows as dictionaries with table, rid, expert, subject, state and body
///   sources the files and domains it read
///   names   the sources that had something to read
NSDictionary *MMLegacyPlan(NSString *home);
/// Applies MMLegacyPlan once per source and records that in the core.migrated pref. A file that already exists
/// in 2.0 is left as it is. Returns the plan it applied, with nothing in it on a second run. A source already
/// marked is not read again. The rows go to the log through MMLogWhenOpen, off main in the app, and Noo-Noo's
/// store.db is read there too, so its rows are not in the plan it returns.
NSDictionary *MMImportLegacy(NSString *home);

/// The pref that records what the migration did and when: one date per source, and "insomnia.lid",
/// "noonoo.agent" and "apps" for the follow-up.
extern NSString *const MMMigratedKey;                   // @"core.migrated"

/// NO when env has MINMACS_HOME or MM_TESTS set, where a test never reads the person's old apps.
/// The app calls the follow-up only when this says YES.
BOOL MMMigrateWanted(NSDictionary<NSString *, NSString *> *env);

/// The label of Noo-Noo's LaunchAgent, and where it lives under home: Library/LaunchAgents/io.noo-noo.d.plist.
extern NSString *const MMNooNooAgentLabel;              // @"io.noo-noo.d"
NSString *MMNooNooAgentPath(NSString *home);
/// +[SMAppService statusForLegacyURL:] for that plist: 0 not registered, 1 enabled, 2 requires approval, 3 not found,
/// and -1 when ServiceManagement is not loaded in this process. Never on main.
NSInteger MMNooNooAgentStatus(NSString *home);

/// One old app on disk. Only <home>/Applications is looked in, and for the person's own home /Applications too,
/// each by its name and checked by the bundle id in its Info.plist. MinMacs 1.x is left out: 2.0 replaces it.
@interface MMLegacyApp : NSObject
@property (readonly, copy) NSString *name, *bundleID, *path, *expert;   // "LocoHost", "no.guerrilla.locohost", ...
@end
/// The old apps found in home. Never on main.
NSArray<MMLegacyApp *> *MMLegacyApps(NSString *home);

/// The confirm the follow-up shows. YES when the person chose the first button. The app shows an alert on main;
/// a test answers with a fake.
typedef BOOL (^MMMigrateAsk)(NSString *title, NSString *body, NSString *yesButton, NSString *noButton);

/// The follow-up, once per part, each part recorded in MMMigratedKey when it is done:
///   insomnia.lid  When the old Insomnia had lid mode on and the override is still live, it is turned off once,
///                 through MMRunAction with an undo record of kind "lid". The sudoers rule stays as it is.
///                 While Insomnia.app runs it owns the override, so the part waits for a later launch. While the
///                 2.0 pref insomnia.lid is on, the Insomnia expert owns it, and the part is done without a write.
///   noonoo.agent  When Noo-Noo's LaunchAgent plist exists, ask once. On yes `launchctl bootout` stops it and the plist
///                 goes to the Trash, through MMRunAction with an undo record that puts it back.
///   apps          When old apps are found, ask once. On yes each one is quit when it runs and moved to the Trash,
///                 each through MMRunAction with its own undo record.
/// launchctl runs as /bin/launchctl, and with MINMACS_HOME set only through the fake MINMACS_LAUNCHCTL_CMD, which gets
/// the whole command line. The Trash is MMTrashFolder() in a test. Blocks. Never on main.
/// Returns what it did: {"insomnia.lid": ..., "noonoo.agent": ..., "apps": [...], "asked": [titles]}.
NSDictionary *MMMigrateFollowUp(NSString *home, MMMigrateAsk ask);

#ifdef MM_TESTS
/// Stands in for +[SMAppService statusForLegacyURL:] in tests. nil goes back to the real call.
void MMUseNooNooAgentStatus(NSInteger (^)(NSURL *plist));
@class MMApp;
/// Stands in for MMRunningApps in the follow-up's checks, so a test never sees the person's own running apps.
void MMUseLegacyRunningApps(NSArray<MMApp *> *(^)(void));
#endif
