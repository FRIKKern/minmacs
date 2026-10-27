// The support folder, the prefs domain, rules files and state files. Patterns P34 to P37 of SYNTHESIS.md section 1.5.
// P38, the SQLite log, is in MMLog.h.
#import <Foundation/Foundation.h>

/// P34. ~/Library/Application Support/MinMacs, or $MINMACS_HOME when it is set. Made on first use.
/// Starts from LHSupportDir in LH Ports.m:32. Tests set MINMACS_HOME, so they never touch the person's files.
NSString *MMSupportDir(void);
/// P34. <support folder>/<expert>, such as .../MinMacs/locohost. Made on first use.
NSString *MMExpertDir(NSString *expert);

/// P35. The one prefs domain. The old apps' domains are read once by the migration in PLAN.md section 8.
extern NSString *const MMPrefsDomain;                   // @"no.guerrilla.minmacs"

/// P35. Prefs on MMPrefsDomain through CFPreferences, so the app and the CLI see the same values.
/// Starts from the LH, WF and MM helpers, such as WFPref in WF Forest.h. Keys carry the expert, such as "locohost.mode".
id MMPref(NSString *key);
void MMSetPref(NSString *key, id value);                // nil removes the key
BOOL MMPrefBool(NSString *key, BOOL dflt);
NSInteger MMPrefInt(NSString *key, NSInteger dflt);
double MMPrefDouble(NSString *key, double dflt);
NSString *MMPrefString(NSString *key, NSString *dflt);

/// P36. One expert's rules file, <expert>/rules.json: named lists of entries the person or an expert set.
/// Starts from WFRules, with MinMacs 1.2's wildcards and without its setVerdict: removal bug.
/// Defaults are additive: a default entry the person removed stays removed, and a new default is added once.
/// Reads and writes are synchronized, and each write merges with the file on disk.
@interface MMRules : NSObject
+ (instancetype)rulesFor:(NSString *)expert defaults:(NSDictionary<NSString *, NSArray *> *)defaults;
/// YES when an entry of list matches value. An entry matches exactly, as a prefix with a trailing *,
/// or as a substring with * on both sides. key picks a field when entries are dictionaries, nil otherwise.
- (BOOL)list:(NSString *)list key:(NSString *)key matches:(NSString *)value;
/// Adds or removes this exact entry, and only this one.
- (void)set:(BOOL)on value:(id)value inList:(NSString *)list key:(NSString *)key;
- (NSArray *)entries:(NSString *)list;
@end

/// P37. One JSON state file, <expert>/<name>.json, shared by the app and the CLI.
/// Starts from SaveActivity in LH Ports.m:376: flock, read, change, write to a temp file and rename.
@interface MMStateFile : NSObject
+ (instancetype)fileNamed:(NSString *)name expert:(NSString *)expert;
@property (readonly, copy) NSString *path;
- (id)read;                                             // nil when the file is missing or broken
/// change gets what is on disk now, under the lock, and returns what to write. nil leaves the file as it is.
- (void)update:(id (^)(id disk))change;
@end
