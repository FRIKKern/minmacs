// Checks Core Store: the support folder, prefs, state files, rules, the SQLite log and the migration.
// Built by test/store.sh with Sources/Core/Store only. Everything it writes is inside $MINMACS_HOME.
// Usage:
//   check unit                 prints one line per check as name<TAB>want<TAB>got
//   check counter <n>          adds 1 to a shared state file n times, for the lock check
//   check logwrite <n> <tag>   appends n log rows, for the two-writer check
//   check plan <home>          prints MMLegacyPlan(home) as JSON
//   check import <home>        prints MMImportLegacy(home) as JSON
#import <Foundation/Foundation.h>
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"

static void Out(NSString *name, NSString *want, NSString *got) { printf("%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"nil").UTF8String); }
static NSString *N(NSInteger n) { return [NSString stringWithFormat:@"%ld", (long)n]; }
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

/// Dates cannot go into JSON, so the plan's prefs print as their descriptions where needed.
static id Printable(id v) {
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *o = [NSMutableDictionary new];
        for (id k in v) o[[k description]] = Printable(v[k]);
        return o;
    }
    if ([v isKindOfClass:NSArray.class]) {
        NSMutableArray *o = [NSMutableArray new];
        for (id x in v) [o addObject:Printable(x)];
        return o;
    }
    if ([v isKindOfClass:NSDate.class]) return @([v timeIntervalSince1970]);
    return v;
}

static void Unit(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];

    // P34
    Out(@"the support folder is MINMACS_HOME", home, MMSupportDir());
    NSString *ed = MMExpertDir(@"locohost");
    BOOL isDir = NO;
    Out(@"an expert folder is made on first use", @"yes", YN([NSFileManager.defaultManager fileExistsAtPath:ed isDirectory:&isDir] && isDir));
    Out(@"an expert folder sits in the support folder", [home stringByAppendingPathComponent:@"locohost"], ed);

    // P35
    Out(@"the prefs domain", @"no.guerrilla.minmacs", MMPrefsDomain);
    Out(@"prefs in tests go to a plist in MINMACS_HOME", [home stringByAppendingPathComponent:@"Preferences/no.guerrilla.minmacs.plist"], MMPrefsTarget());
    MMSetPref(@"test.string", @"eager");
    MMSetPref(@"test.int", @42);
    MMSetPref(@"test.double", @2.5);
    MMSetPref(@"test.bool", @NO);
    Out(@"a string pref reads back", @"eager", MMPrefString(@"test.string", @"x"));
    Out(@"an int pref reads back", @"42", N(MMPrefInt(@"test.int", 0)));
    Out(@"a double pref reads back", @"2.5", [NSString stringWithFormat:@"%.1f", MMPrefDouble(@"test.double", 0)]);
    Out(@"a NO bool pref is not the default", @"no", YN(MMPrefBool(@"test.bool", YES)));
    Out(@"a missing pref gives the default", @"proactive", MMPrefString(@"test.missing", @"proactive"));
    MMSetPref(@"test.string", nil);
    Out(@"nil removes a pref", @"nil", MMPref(@"test.string") ?: @"nil");
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:MMPrefsTarget()];
    Out(@"the prefs plist holds what was set", @"42", [plist[@"test.int"] description]);
    Out(@"the icon key follows autosaveName", @"NSStatusItem Visible minmacs.locohost", MMIconVisibleKey(@"LocoHost"));
    Out(@"an icon with no saved state is visible", @"yes", YN(MMIconVisible(@"workforest")));
    MMSetPref(MMIconVisibleKey(@"workforest"), @NO);
    Out(@"a hidden icon reads hidden", @"no", YN(MMIconVisible(@"workforest")));

    // P37
    MMStateFile *f = [MMStateFile fileNamed:@"activity" expert:@"locohost"];
    Out(@"a state file lives in its expert folder", [home stringByAppendingPathComponent:@"locohost/activity.json"], f.path);
    Out(@"a missing state file reads nil", @"nil", [f read] ?: @"nil");
    [f update:^id(id disk) { return @{@"hosts": @{@"a": @1}}; }];
    [f update:^id(id disk) { NSMutableDictionary *d = disk; d[@"hosts"][@"b"] = @2; return d; }];
    Out(@"update gets the disk and merges", @"a,b", [[[[f read][@"hosts"] allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]);
    [f update:^id(id disk) { return nil; }];
    Out(@"update returning nil leaves the file", @"2", N([[f read][@"hosts"] count]));
    [@"{broken" writeToFile:f.path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Out(@"a broken state file reads nil", @"nil", [f read] ?: @"nil");
    NSArray *left = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:ed error:nil]
                     filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (SELF ENDSWITH '.json' OR SELF ENDSWITH '.lock')"]];
    Out(@"an atomic write leaves no temp file", @"0", N(left.count));

    // P36
    NSDictionary *defs = @{@"keep": @[@"com.apple.Terminal", @"com.jetbrains.*", @"*noo-noo*"], @"ports": @[@5432]};
    MMRules *r = [MMRules rulesFor:@"rulestest" defaults:defs];
    Out(@"defaults are written on first use", @"3", N([r entries:@"keep"].count));
    Out(@"an exact entry matches", @"yes", YN([r list:@"keep" key:nil matches:@"com.apple.Terminal"]));
    Out(@"an exact entry matches nothing longer", @"no", YN([r list:@"keep" key:nil matches:@"com.apple.Terminal2"]));
    Out(@"a trailing star matches a prefix", @"yes", YN([r list:@"keep" key:nil matches:@"com.jetbrains.goland"]));
    Out(@"a prefix match keeps case", @"no", YN([r list:@"keep" key:nil matches:@"COM.JETBRAINS.goland"]));
    Out(@"stars on both sides match a substring in any case", @"yes", YN([r list:@"keep" key:nil matches:@"io.Noo-Noo.app"]));
    Out(@"a number entry matches its text", @"yes", YN([r list:@"ports" key:nil matches:@"5432"]));
    [r set:YES value:@"com.jetbrains.goland" inList:@"keep" key:nil];
    [r set:NO value:@"com.jetbrains.goland" inList:@"keep" key:nil];
    Out(@"removing one entry keeps the wildcard that matched it", @"yes", YN([[r entries:@"keep"] containsObject:@"com.jetbrains.*"]));
    [r set:NO value:@"com.apple.Terminal" inList:@"keep" key:nil];
    MMRules *again = [MMRules rulesFor:@"rulestest" defaults:defs];
    Out(@"a default the person removed stays removed", @"no", YN([again list:@"keep" key:nil matches:@"com.apple.Terminal"]));
    NSMutableDictionary *more = [defs mutableCopy];
    more[@"keep"] = [defs[@"keep"] arrayByAddingObject:@"dev.zed.Zed"];
    MMRules *upgraded = [MMRules rulesFor:@"rulestest" defaults:more];
    Out(@"a new default is added once", @"yes", YN([upgraded list:@"keep" key:nil matches:@"dev.zed.Zed"]));
    [upgraded set:NO value:@"dev.zed.Zed" inList:@"keep" key:nil];
    Out(@"and stays out once removed", @"no", YN([[MMRules rulesFor:@"rulestest" defaults:more] list:@"keep" key:nil matches:@"dev.zed.Zed"]));
    [r set:YES value:@{@"path": @"~/code/a", @"until": @1} inList:@"kept" key:@"path"];
    [r set:YES value:@{@"path": @"~/code/a", @"until": @2} inList:@"kept" key:@"path"];
    [r set:YES value:@{@"path": @"~/code/*", @"until": @3} inList:@"kept" key:@"path"];
    Out(@"a keyed entry replaces the one with the same key", @"2", N([r entries:@"kept"].count));
    Out(@"a keyed wildcard matches", @"yes", YN([r list:@"kept" key:@"path" matches:@"~/code/b"]));
    MMRules *other = [MMRules rulesFor:@"rulestest" defaults:defs];
    [other set:YES value:@"from.other" inList:@"keep" key:nil];
    Out(@"a write by another instance is seen", @"yes", YN([r list:@"keep" key:nil matches:@"from.other"]));

    // P38
    MMLog *log = MMLog.shared;
    Out(@"the log lives in the support folder", @"yes", YN([NSFileManager.defaultManager fileExistsAtPath:[home stringByAppendingPathComponent:@"minmacs.sqlite"]]));
    MMLogEntry *a = [log append:@"undo" rid:nil expert:@"locohost" subject:@":3000" state:@"pending" body:@{@"restart": @"pnpm dev"}];
    Out(@"append returns the row", @"pending", a.state);
    Out(@"a nil rid gets a new one", @"yes", YN(a.rid.length == 36));
    MMLogEntry *b = [log append:@"undo" rid:a.rid expert:@"locohost" subject:@":3000" state:@"done" body:@{@"restart": @"pnpm dev"}];
    [log append:@"undo" rid:a.rid expert:@"locohost" subject:@":3000" state:@"restored" body:nil];
    Out(@"a new state is a new row", @"yes", YN(b.row > a.row));
    NSArray *h = [log history:a.rid];
    Out(@"history is every row of a record, oldest first", @"pending,done,restored", [[h valueForKey:@"state"] componentsJoinedByString:@","]);
    Out(@"the body reads back", @"pnpm dev", [h[1] body][@"restart"]);
    MMLogEntry *c = [log append:@"undo" rid:nil expert:@"workforest" subject:@"promo" state:@"done" body:@{}];
    [log append:@"review" rid:nil expert:@"locohost" subject:@"localhosts" state:@"done" body:@{}];
    NSArray *l = [log latest:@"undo" expert:nil subject:nil since:nil limit:0];
    Out(@"latest gives the newest row of each rid", @"done,restored", [[l valueForKey:@"state"] componentsJoinedByString:@","]);
    Out(@"latest is newest first", c.rid, [l.firstObject rid]);
    Out(@"latest filters by expert", @"1", N([log latest:@"undo" expert:@"locohost" subject:nil since:nil limit:0].count));
    Out(@"latest filters by subject", @"promo", [[log latest:@"undo" expert:nil subject:@"promo" since:nil limit:0].firstObject subject]);
    Out(@"latest stays in its table", @"1", N([log latest:@"review" expert:nil subject:nil since:nil limit:0].count));
    Out(@"latest takes a limit", @"1", N([log latest:@"undo" expert:nil subject:nil since:nil limit:1].count));
    Out(@"latest takes a time", @"0", N([log latest:@"undo" expert:nil subject:nil since:[NSDate dateWithTimeIntervalSinceNow:60] limit:0].count));
    MMLog *second = [[MMLog alloc] initWithPath:[home stringByAppendingPathComponent:@"minmacs.sqlite"]];
    Out(@"a second handle on the file sees the rows", @"3", N([second history:a.rid].count));

    NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1800000000];
    [log addPoint:@"noonoo.disk.~/Library/Caches" value:10 at:t0 bucket:86400];
    [log addPoint:@"noonoo.disk.~/Library/Caches" value:12 at:[t0 dateByAddingTimeInterval:3600] bucket:86400];
    [log addPoint:@"noonoo.disk.~/Library/Caches" value:20 at:[t0 dateByAddingTimeInterval:86400] bucket:86400];
    [log addPoint:@"other" value:99 at:t0 bucket:86400];
    NSData *p = [log points:@"noonoo.disk.~/Library/Caches" since:nil];
    const MMTrendPoint *pt = p.bytes;
    NSUInteger n = p.length / sizeof(MMTrendPoint);
    Out(@"one point per bucket", @"2", N(n));
    Out(@"a newer value in a bucket replaces it", @"12,20", n == 2 ? [NSString stringWithFormat:@"%.0f,%.0f", pt[0].value, pt[1].value] : @"");
    Out(@"points take a time", @"1", N([log points:@"noonoo.disk.~/Library/Caches" since:[t0 dateByAddingTimeInterval:7200]].length / sizeof(MMTrendPoint)));
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *verb = argc > 1 ? @(argv[1]) : @"unit";
    if (![NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] length]) { fprintf(stderr, "MINMACS_HOME must be set\n"); return 2; }
    if ([verb isEqualToString:@"unit"]) { Unit(); return 0; }
    if ([verb isEqualToString:@"counter"] && argc > 2) {
        MMStateFile *f = [MMStateFile fileNamed:@"counter" expert:@"locktest"];
        for (int i = 0; i < atoi(argv[2]); i++)
            [f update:^id(id disk) { return @{@"n": @([disk[@"n"] integerValue] + 1)}; }];
        return 0;
    }
    if ([verb isEqualToString:@"logwrite"] && argc > 3) {
        for (int i = 0; i < atoi(argv[2]); i++)
            if (![MMLog.shared append:@"usage" rid:nil expert:@(argv[3]) subject:N(i) state:@"done" body:@{@"i": @(i)}]) return 1;
        return 0;
    }
    if ([verb isEqualToString:@"plan"] && argc > 2) { PrintJSON(Printable(MMLegacyPlan(@(argv[2])))); return 0; }
    if ([verb isEqualToString:@"import"] && argc > 2) { PrintJSON(Printable(MMImportLegacy(@(argv[2])))); return 0; }
    fprintf(stderr, "usage: check unit | counter <n> | logwrite <n> <tag> | plan <home> | import <home>\n");
    return 2;
}}
