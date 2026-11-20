// The migration of PLAN.md section 8, issue #37. See MMMigrate.h. The old files and prefs are read and never written.
// The shapes come from the old code: LocoHost's Rules.m, Ports.m SaveActivity, main.m KeepList and RememberClosed;
// MinMacs 1.2's Rules.m and its minmacs.closedBundleIDs and minmacs.closedTabs prefs in main.m; WorkForest's
// Rules.m, Review.m and Forest.m WFRemove; Insomnia's main.m prefs; Noo-Noo's internal/config, internal/store
// schema.sql and internal/cli/install_cmd.go.
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Act/MMAct.h"
#import "Core/Know/MMGit.h"
#import <objc/message.h>
#include <sqlite3.h>
#include <sys/sysctl.h>
#include <unistd.h>

NSString *const MMMigratedKey = @"core.migrated";
NSString *const MMNooNooAgentLabel = @"io.noo-noo.d";
// The old apps made their status item with no autosaveName, so AppKit saved its state under the first item's name.
static NSString *const kOldVisibleKey = @"NSStatusItem Visible Item-0";
static NSString *const kInsomniaDomain = @"no.guerrilla.insomnia";
static NSString *const kAlreadyOff = @"it is already off";
static NSString *const kLidModeOwns = @"MinMacs's own lid mode sets it now";

static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSArray *List(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] ? v : nil; }

static id ReadJSON(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
}

static BOOL IsOwnHome(NSString *home) {
    return [home.stringByStandardizingPath isEqualToString:NSHomeDirectory().stringByStandardizingPath];
}

/// An old prefs domain. The person's own home goes through CFPreferences, which only reads here.
/// Any other home is a copy, read from its plist file.
static NSDictionary *ReadDomain(NSString *home, NSString *domain, NSMutableArray *sources) {
    NSString *plist = [home stringByAppendingFormat:@"/Library/Preferences/%@.plist", domain];
    if (IsOwnHome(home)) {
        CFStringRef d = (__bridge CFStringRef)domain;
        NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        if (!keys.count) return @{};
        [sources addObject:domain];
        return CFBridgingRelease(CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) ?: @{};
    }
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:plist];
    if (p) [sources addObject:plist];
    return p ?: @{};
}

/// Old nested lists such as {"protect": {"names": [...]}} become 2.0's flat named lists, "protect.names".
static void Flatten(id node, NSString *prefix, NSMutableDictionary *out) {
    if ([node isKindOfClass:NSArray.class]) { out[prefix] = node; return; }
    if (![node isKindOfClass:NSDictionary.class]) return;
    for (NSString *k in node) {
        if ([k hasPrefix:@"_"] || [k isEqualToString:@"version"]) continue;   // comments and the old file version
        Flatten(node[k], prefix.length ? [NSString stringWithFormat:@"%@.%@", prefix, k] : k, out);
    }
}

static NSDictionary *Rules(NSString *path, NSMutableArray *sources) {
    id j = ReadJSON(path);
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    [sources addObject:path];
    NSMutableDictionary *out = [NSMutableDictionary new];
    Flatten(j, @"", out);
    return out;
}

/// Copies prefix keys the 2.0 prefs do not hold yet. rename maps an old key to a new one.
static void CopyPrefs(NSDictionary *old, NSString *prefix, NSDictionary *rename, NSSet *skip, NSMutableDictionary *out) {
    for (NSString *k in old) {
        NSString *to = rename[k] ?: ([k hasPrefix:prefix] ? k : nil);
        if (!to || [skip containsObject:k] || MMPref(to) != nil) continue;
        out[to] = old[k];
    }
}

static NSMutableDictionary *EmptyPlan(void) {
    return [@{@"prefs": [NSMutableDictionary new], @"files": [NSMutableDictionary new], @"merge": [NSMutableDictionary new],
              @"rows": [NSMutableArray new], @"sources": [NSMutableArray new]} mutableCopy];
}

/// Adds roots to the core rules file the repo index reads, PLAN.md section 8: WorkForest's and Noo-Noo's roots
/// become the one list.
static void AddRoots(NSMutableDictionary *plan, NSArray *roots) {
    NSMutableArray *have = [List(plan[@"files"][@"core/rules.json"][@"roots"]) mutableCopy] ?: [NSMutableArray new];
    for (id r in roots) if ([r isKindOfClass:NSString.class] && [r length] && ![have containsObject:r]) [have addObject:r];
    if (have.count) plan[@"files"][@"core/rules.json"] = @{@"roots": have};
}

#pragma mark - LocoHost and MinMacs 1.2

static NSDictionary *LocoHostPlan(NSString *home) {
    NSMutableDictionary *plan = EmptyPlan();
    NSMutableArray *sources = plan[@"sources"];
    NSString *dir = [home stringByAppendingPathComponent:@"Library/Application Support/LocoHost"];

    NSDictionary *prefs = ReadDomain(home, @"no.guerrilla.locohost", sources);
    CopyPrefs(prefs, @"locohost.", @{@"locohost.model": MMReviewModelKey, kOldVisibleKey: MMIconVisibleKey(@"locohost")}, nil, plan[@"prefs"]);

    NSDictionary *rules = Rules([dir stringByAppendingPathComponent:@"rules.json"], sources);
    if (rules) plan[@"files"][@"locohost/rules.json"] = rules;
    for (NSArray *pair in @[@[@"activity.json", @"locohost/activity.json"], @[@"keep.json", @"locohost/kept.json"]]) {
        NSString *p = [dir stringByAppendingPathComponent:pair[0]];
        id j = ReadJSON(p);
        if ([j isKindOfClass:NSDictionary.class]) { plan[@"files"][pair[1]] = j; [sources addObject:p]; }
    }

    // closed.json, newest first: what LocoHost stopped, with the command that starts it again.
    // Each record becomes an undo row in state done, so Recently Stopped and its restart keep working.
    // The body has the shape MMUndoRecord reads in Act: rid, state, kind, by, at and payload.restart.command.
    NSString *closedPath = [dir stringByAppendingPathComponent:@"closed.json"];
    id closed = ReadJSON(closedPath);
    if ([closed isKindOfClass:NSArray.class]) {
        [sources addObject:closedPath];
        // Oldest first, so the log's write order matches the order they were stopped.
        for (NSDictionary *c in [closed reverseObjectEnumerator]) {
            if (![c isKindOfClass:NSDictionary.class]) continue;
            NSString *subject = [[NSString stringWithFormat:@":%@ %@", c[@"port"] ?: @"", c[@"project"] ?: @""]
                                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *rid = [NSString stringWithFormat:@"legacy.locohost.%.0f.%@", [c[@"at"] doubleValue], c[@"port"] ?: @""];
            NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:c forKey:@"legacy"];
            if ([c[@"restart"] isKindOfClass:NSString.class] && [c[@"restart"] length]) payload[@"restart"] = @{@"command": c[@"restart"]};
            // LocoHost wrote "you" for a stop the person asked for, and the mode's name for the rest.
            NSString *by = [c[@"by"] isKindOfClass:NSString.class] ? [c[@"by"] lowercaseString] : @"";
            if (![@[@"proactive", @"eager", @"cli"] containsObject:by]) by = @"manual";
            NSDictionary *body = @{@"rid": rid, @"state": @"done", @"kind": @"stop", @"expert": @"locohost", @"subject": subject,
                                   @"findingID": [@"locohost:host:" stringByAppendingString:[c[@"port"] description] ?: @""],
                                   @"why": [c[@"why"] isKindOfClass:NSString.class] ? c[@"why"] : @"", @"by": by,
                                   @"at": @([c[@"at"] doubleValue]), @"payload": payload, @"from": @"LocoHost closed.json"};
            [plan[@"rows"] addObject:@{@"table": @"undo", @"rid": rid, @"expert": @"locohost",
                                       @"subject": subject, @"state": @"done", @"body": body}];
        }
    }
    // review.json is the last review. It goes into the review history as one row.
    NSString *reviewPath = [dir stringByAppendingPathComponent:@"review.json"];
    id review = ReadJSON(reviewPath);
    if ([review isKindOfClass:NSDictionary.class]) {
        [sources addObject:reviewPath];
        NSMutableDictionary *body = [review mutableCopy]; body[@"from"] = @"LocoHost review.json";
        [plan[@"rows"] addObject:@{@"table": @"review", @"rid": [NSString stringWithFormat:@"legacy.locohost.review.%.0f", [review[@"at"] doubleValue]],
                                   @"expert": @"locohost", @"subject": @"localhosts", @"state": @"done", @"body": body}];
    }
    return plan;
}

static NSDictionary *MinMacs12Plan(NSString *home) {
    NSMutableDictionary *plan = EmptyPlan();
    NSMutableArray *sources = plan[@"sources"];
    // 1.2 used the same domain as 2.0. For the person's own home its keys are already in place, and CopyPrefs skips them.
    NSDictionary *prefs = ReadDomain(home, MMPrefsDomain, sources);
    NSSet *restore = [NSSet setWithArray:@[@"minmacs.closedBundleIDs", @"minmacs.closedTabs"]];
    CopyPrefs(prefs, @"minmacs.", @{kOldVisibleKey: MMIconVisibleKey(@"minmacs")}, restore, plan[@"prefs"]);

    // 1.2 kept its rules at the top of the support folder. 2.0 keeps them per expert, in minmacs/rules.json.
    NSDictionary *rules = Rules([home stringByAppendingPathComponent:@"Library/Application Support/MinMacs/rules.json"], sources);
    if (rules) plan[@"files"][@"minmacs/rules.json"] = rules;

    // What the last run quit, for Restore: the apps to relaunch and the tabs to reopen, one undo row per app.
    NSArray *ids = List(prefs[@"minmacs.closedBundleIDs"]) ?: @[];
    NSArray *tabs = List(prefs[@"minmacs.closedTabs"]) ?: @[];
    NSMutableArray *apps = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray *> *urls = [NSMutableDictionary new];
    for (id b in ids) if ([b isKindOfClass:NSString.class] && ![apps containsObject:b]) [apps addObject:b];
    for (NSDictionary *t in tabs) {
        if (![t isKindOfClass:NSDictionary.class] || !Str(t[@"bundleID"]) || !Str(t[@"url"])) continue;
        if (![apps containsObject:t[@"bundleID"]]) [apps addObject:t[@"bundleID"]];
        if (!urls[t[@"bundleID"]]) urls[t[@"bundleID"]] = [NSMutableArray new];
        [urls[t[@"bundleID"]] addObject:t[@"url"]];
    }
    // The body has the shape MMUndoRecord reads in Act. Act's restore opens payload.relaunch by its bundleID.
    for (NSString *b in apps) {
        NSString *rid = [@"legacy.minmacs." stringByAppendingString:b];
        [plan[@"rows"] addObject:@{@"table": @"undo", @"rid": rid, @"expert": @"minmacs", @"subject": b, @"state": @"done",
                                   @"body": @{@"rid": rid, @"state": @"done", @"kind": @"quit", @"expert": @"minmacs", @"subject": b,
                                              @"by": @"manual", @"why": @"", @"from": @"MinMacs 1.2 prefs",
                                              @"at": @(NSDate.date.timeIntervalSince1970),   // 1.2 kept no time
                                              @"payload": @{@"relaunch": @{@"bundleID": b, @"tabs": urls[b] ?: @[]}}}}];
    }
    return plan;
}

#pragma mark - WorkForest 0.1

/// WorkForest 0.1 wrote "you" or the mode's label as who removed it. 2.0 says manual or the mode's name.
static NSString *WorkForestBy(NSString *by) {
    NSString *b = by.lowercaseString;
    return [@[@"idle", @"proactive", @"eager"] containsObject:b ?: @""] ? b : @"manual";
}

static NSDictionary *WorkForestPlan(NSString *home) {
    NSMutableDictionary *plan = EmptyPlan();
    NSMutableArray *sources = plan[@"sources"];
    NSString *dir = [home stringByAppendingPathComponent:@"Library/Application Support/WorkForest"];

    // fetch, checkPRs and the CLI paths are gone in 2.0: MinMacs never fetches, and the review broker finds the CLIs.
    NSDictionary *prefs = ReadDomain(home, @"no.guerrilla.workforest", sources);
    NSSet *gone = [NSSet setWithArray:@[@"workforest.fetch", @"workforest.checkPRs", @"workforest.claudePath", @"workforest.codexPath"]];
    CopyPrefs(prefs, @"workforest.", @{@"workforest.model": MMReviewModelKey, kOldVisibleKey: MMIconVisibleKey(@"workforest")}, gone, plan[@"prefs"]);

    // rules.json: protect.paths is 2.0's protect list and ignore.paths its ignore list. The roots join the core rules.
    NSDictionary *flat = Rules([dir stringByAppendingPathComponent:@"rules.json"], sources);
    if (flat) {
        NSMutableDictionary *rules = [NSMutableDictionary new];
        NSDictionary *rename = @{@"protect.paths": @"protect", @"ignore.paths": @"ignore"};
        for (NSString *k in flat) {
            if ([k isEqualToString:@"roots"]) continue;
            rules[rename[k] ?: k] = flat[k];
        }
        plan[@"files"][@"workforest/rules.json"] = rules;
        AddRoots(plan, List(flat[@"roots"]));
    }

    NSString *reviewPath = [dir stringByAppendingPathComponent:@"review.json"];
    id review = ReadJSON(reviewPath);
    if ([review isKindOfClass:NSDictionary.class]) {
        [sources addObject:reviewPath];
        NSMutableDictionary *body = [review mutableCopy]; body[@"from"] = @"WorkForest review.json";
        [plan[@"rows"] addObject:@{@"table": @"review", @"rid": [NSString stringWithFormat:@"legacy.workforest.review.%.0f", [review[@"at"] doubleValue]],
                                   @"expert": @"workforest", @"subject": @"worktrees", @"state": @"done", @"body": body}];
    }

    // removed.json, newest first: each removal with its repo, head and the files WFRemove saved. Each becomes an undo
    // row that -[MMUndo restore:] takes back: the worktree is made again at its commit, and the saved files are copied
    // back from where 0.1 put them, which stay as they are. workforest/legacy-removed.json maps 0.1's id to the rid,
    // the same map the expert's own import keeps, so a record is imported once whichever ran first.
    NSString *removedPath = [dir stringByAppendingPathComponent:@"removed.json"];
    NSArray *removed = List(ReadJSON(removedPath));
    if (removed) {
        [sources addObject:removedPath];
        NSDictionary *seen = Dict([[MMStateFile fileNamed:@"legacy-removed" expert:@"workforest"] read]) ?: @{};
        NSMutableDictionary *map = [NSMutableDictionary new];
        for (NSDictionary *r in removed.reverseObjectEnumerator) {
            NSString *lid = Str(Dict(r)[@"id"]), *path = Str(r[@"path"]), *repo = Str(r[@"repo"]);
            if (!lid.length || !path.length || !repo.length || seen[lid] || map[lid]) continue;
            NSString *rid = [@"legacy.workforest." stringByAppendingString:lid];
            NSString *branch = Str(r[@"branch"]) ?: @"", *head = Str(r[@"head"]) ?: @"";
            NSMutableDictionary *payload = [NSMutableDictionary new];
            payload[@"legacyID"] = lid;
            payload[@"worktree"] = @{@"repo": repo, @"worktree": path, @"head": head, @"branch": branch};
            payload[@"removed"] = @{@"path": path, @"repo": repo, @"branch": branch, @"head": head, @"merged": Str(r[@"merged"]) ?: @"",
                                    @"diskBytes": r[@"diskBytes"] ?: @0, @"at": r[@"at"] ?: @0};
            payload[@"branchDeleted"] = r[@"branchDeleted"] ?: @NO;
            payload[@"legacy"] = r;
            NSArray *saved = List(r[@"saved"]) ?: @[];
            if (saved.count) payload[@"recovery"] = @{@"dir": [[[dir stringByAppendingPathComponent:@"removed"] stringByAppendingPathComponent:lid]
                                                                 stringByAppendingPathComponent:@"files"],
                                                       @"root": path, @"saved": saved, @"skipped": List(r[@"skipped"]) ?: @[]};
            NSString *subject = path.stringByAbbreviatingWithTildeInPath;
            NSDictionary *body = @{@"rid": rid, @"state": @"done", @"kind": @"remove", @"expert": @"workforest", @"subject": subject,
                                   @"findingID": [@"workforest:worktree:" stringByAppendingString:path],
                                   @"why": Str(r[@"why"]) ?: @"removed by WorkForest 0.1", @"by": WorkForestBy(Str(r[@"by"])),
                                   @"at": @([r[@"at"] doubleValue]), @"payload": payload, @"freedBytes": @0, @"from": @"WorkForest removed.json"};
            [plan[@"rows"] addObject:@{@"table": @"undo", @"rid": rid, @"expert": @"workforest", @"subject": subject,
                                       @"state": @"done", @"body": body}];
            map[lid] = rid;
        }
        if (map.count) plan[@"merge"][@"workforest/legacy-removed.json"] = map;
    }
    return plan;
}

#pragma mark - Insomnia

static NSDictionary *InsomniaPlan(NSString *home) {
    NSMutableDictionary *plan = EmptyPlan();
    NSDictionary *prefs = ReadDomain(home, kInsomniaDomain, plan[@"sources"]);
    // The settings carry over. The guard clocks, the update check and the debug prefs do not: a clock from the last
    // run would trip a guard at once, and 2.0 has no debug prefs.
    NSMutableSet *skip = [NSMutableSet setWithArray:@[@"insomnia.unpluggedAt", @"insomnia.offlineAt", @"insomnia.agents.workingAt",
                                                      @"insomnia.autoUpdateCheck", @"insomnia.availableVersion", @"insomnia.updateCheckedAt"]];
    // Built from two parts, so the release binary holds no debug pref name, as test/insomnia.sh checks.
    NSString *debug = [@"insomnia." stringByAppendingString:@"debug."];
    for (NSString *k in prefs) if ([k hasPrefix:debug]) [skip addObject:k];
    CopyPrefs(prefs, @"insomnia.", @{kOldVisibleKey: MMIconVisibleKey(@"insomnia")}, skip, plan[@"prefs"]);
    return plan;
}

#pragma mark - Noo-Noo 0.7

/// A small TOML reader for Noo-Noo's config.toml: tables, dotted keys, strings, numbers, booleans, arrays and
/// inline tables. A date stays a string. An array of tables is read past, since config.toml has none.
@interface MMTOMLReader : NSObject
- (instancetype)initWithString:(NSString *)s;
- (NSDictionary *)parse;
@end

@implementation MMTOMLReader {
    NSString *_s;
    NSUInteger _i;
}

- (instancetype)initWithString:(NSString *)s { if ((self = [super init])) { _s = s ?: @""; } return self; }
- (unichar)peek { return _i < _s.length ? [_s characterAtIndex:_i] : 0; }
- (void)skipSpace { while ([self peek] == ' ' || [self peek] == '\t') _i++; }
- (void)skipLine { while (_i < _s.length && [self peek] != '\n') _i++; }
/// Spaces, newlines and comments, as between array items.
- (void)skipBlank {
    for (;;) {
        unichar c = [self peek];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') _i++;
        else if (c == '#') [self skipLine];
        else return;
    }
}

- (NSString *)quoted:(unichar)q {
    _i++;
    BOOL multi = NO;
    if (_i + 1 < _s.length && [_s characterAtIndex:_i] == q && [_s characterAtIndex:_i + 1] == q) { multi = YES; _i += 2; if ([self peek] == '\n') _i++; }
    NSMutableString *out = [NSMutableString new];
    while (_i < _s.length) {
        unichar c = [_s characterAtIndex:_i];
        if (c == q) {
            if (!multi) { _i++; return out; }
            if (_i + 2 < _s.length && [_s characterAtIndex:_i + 1] == q && [_s characterAtIndex:_i + 2] == q) { _i += 3; return out; }
        }
        if (c == '\n' && !multi) return out;
        if (c == '\\' && q == '"' && _i + 1 < _s.length) {
            unichar e = [_s characterAtIndex:++_i];
            NSDictionary *esc = @{@"n": @"\n", @"t": @"\t", @"r": @"\r", @"\"": @"\"", @"\\": @"\\"};
            NSString *k = [NSString stringWithCharacters:&e length:1];
            [out appendString:esc[k] ?: k];
            _i++;
            continue;
        }
        [out appendFormat:@"%C", c];
        _i++;
    }
    return out;
}

- (NSString *)key {
    [self skipSpace];
    unichar c = [self peek];
    if (c == '"' || c == '\'') return [self quoted:c];
    NSUInteger start = _i;
    while (_i < _s.length) {
        c = [self peek];
        if ([NSCharacterSet.alphanumericCharacterSet characterIsMember:c] || c == '_' || c == '-') _i++;
        else break;
    }
    return [_s substringWithRange:NSMakeRange(start, _i - start)];
}

/// A dotted key such as heuristics.leaks, up to the stop character.
- (NSArray<NSString *> *)keyPath {
    NSMutableArray *parts = [NSMutableArray new];
    for (;;) {
        NSString *k = [self key];
        if (!k.length) return parts;
        [parts addObject:k];
        [self skipSpace];
        if ([self peek] != '.') return parts;
        _i++;
    }
}

- (id)value {
    [self skipSpace];
    unichar c = [self peek];
    if (c == '"' || c == '\'') return [self quoted:c];
    if (c == '[') {
        _i++;
        NSMutableArray *a = [NSMutableArray new];
        for (;;) {
            [self skipBlank];
            if ([self peek] == ']') { _i++; return a; }
            if (_i >= _s.length) return a;
            NSUInteger before = _i;
            id v = [self value];
            if (v) [a addObject:v];
            [self skipBlank];
            if ([self peek] == ',') _i++;
            else if (_i == before) _i++;   // a character that starts no value is read past
        }
    }
    if (c == '{') {
        _i++;
        NSMutableDictionary *t = [NSMutableDictionary new];
        for (;;) {
            [self skipBlank];
            if ([self peek] == '}') { _i++; return t; }
            if (_i >= _s.length) return t;
            NSArray *path = [self keyPath];
            [self skipSpace];
            if (!path.count || [self peek] != '=') { _i++; continue; }
            _i++;
            [self set:[self value] path:path in:t];
            [self skipBlank];
            if ([self peek] == ',') _i++;
        }
    }
    NSUInteger start = _i;
    while (_i < _s.length) {
        c = [self peek];
        if (c == ',' || c == ']' || c == '}' || c == '#' || c == '\n' || c == '\r') break;
        _i++;
    }
    NSString *tok = [[_s substringWithRange:NSMakeRange(start, _i - start)]
                     stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([tok isEqualToString:@"true"]) return @YES;
    if ([tok isEqualToString:@"false"]) return @NO;
    NSString *num = [tok stringByReplacingOccurrencesOfString:@"_" withString:@""];
    NSScanner *sc = [NSScanner scannerWithString:num];
    long long n; double d;
    if ([sc scanLongLong:&n] && sc.isAtEnd) return @(n);
    sc = [NSScanner scannerWithString:num];
    if ([sc scanDouble:&d] && sc.isAtEnd) return @(d);
    return tok.length ? tok : nil;   // a date or a time stays as written
}

- (void)set:(id)value path:(NSArray<NSString *> *)path in:(NSMutableDictionary *)root {
    if (!value || !path.count) return;
    NSMutableDictionary *t = root;
    for (NSUInteger k = 0; k + 1 < path.count; k++) {
        NSMutableDictionary *next = [t[path[k]] isKindOfClass:NSMutableDictionary.class] ? t[path[k]] : nil;
        if (!next) { next = [NSMutableDictionary new]; t[path[k]] = next; }
        t = next;
    }
    t[path.lastObject] = value;
}

- (NSDictionary *)parse {
    NSMutableDictionary *root = [NSMutableDictionary new];
    NSMutableDictionary *current = root;
    while (_i < _s.length) {
        [self skipBlank];
        if (_i >= _s.length) break;
        if ([self peek] == '[') {
            _i++;
            BOOL arrayTable = [self peek] == '[';
            if (arrayTable) _i++;
            NSArray *path = [self keyPath];
            [self skipLine];
            if (arrayTable || !path.count) { current = [NSMutableDictionary new]; continue; }   // read past, kept nowhere
            current = root;
            for (NSString *k in path) {
                NSMutableDictionary *next = [current[k] isKindOfClass:NSMutableDictionary.class] ? current[k] : nil;
                if (!next) { next = [NSMutableDictionary new]; current[k] = next; }
                current = next;
            }
            continue;
        }
        NSArray *path = [self keyPath];
        [self skipSpace];
        if (!path.count || [self peek] != '=') { [self skipLine]; continue; }
        _i++;
        [self set:[self value] path:path in:current];
        [self skipSpace];
        if ([self peek] == '#') [self skipLine];
    }
    return root;
}

@end

/// Rows of one query on Noo-Noo's store.db, opened read-only and immutable, so SQLite writes no journal, WAL or
/// shm file next to it. Each row is a dictionary of column name to value.
static NSArray<NSDictionary *> *StoreRows(NSString *path, NSString *sql) {
    NSString *uri = [[NSURL fileURLWithPath:path].absoluteString stringByAppendingString:@"?immutable=1"];
    sqlite3 *db = NULL;
    NSMutableArray *out = [NSMutableArray new];
    if (sqlite3_open_v2(uri.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) != SQLITE_OK) { sqlite3_close(db); return nil; }
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK) {
        while (sqlite3_step(st) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary new];
            for (int c = 0; c < sqlite3_column_count(st); c++) {
                NSString *name = @(sqlite3_column_name(st, c));
                switch (sqlite3_column_type(st, c)) {
                    case SQLITE_INTEGER: row[name] = @(sqlite3_column_int64(st, c)); break;
                    case SQLITE_FLOAT: row[name] = @(sqlite3_column_double(st, c)); break;
                    case SQLITE_TEXT: row[name] = @((const char *)sqlite3_column_text(st, c)) ?: @""; break;
                    default: break;
                }
            }
            [out addObject:row];
        }
    } else out = nil;
    sqlite3_finalize(st);
    sqlite3_close(db);
    return out;
}

/// Noo-Noo's DATETIME text, such as "2026-05-02 03:00:00+00:00", as seconds since 1970. 0 when unreadable.
static double StoreTime(id v) {
    if ([v isKindOfClass:NSNumber.class]) return [v doubleValue];
    NSString *s = Str(v);
    if (!s.length) return 0;
    for (NSString *fmt in @[@"yyyy-MM-dd HH:mm:ss.SSSSSSSSSZZZZZ", @"yyyy-MM-dd HH:mm:ssZZZZZ", @"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                            @"yyyy-MM-dd HH:mm:ss"]) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        f.dateFormat = fmt;
        NSDate *d = [f dateFromString:s];
        if (d) return d.timeIntervalSince1970;
    }
    return 0;
}

/// store.db's rows as log rows, history in table "legacy". Its cleans removed files for good, so there is nothing to
/// restore, and never undo rows, so Undo Last Clean never picks one.
static NSArray<NSDictionary *> *NooNooStoreRows(NSString *storePath) {
    NSArray *actions = StoreRows(storePath, @"SELECT id, ts, module, op, target, size_bytes, evidence_json, outcome FROM actions ORDER BY id DESC LIMIT 500");
    NSArray *autos = StoreRows(storePath, @"SELECT id, started_at_unix, ended_at_unix, trigger, outcome, skip_reason, target_path, module, "
                                           "target_size_bytes, freed_bytes, idle_days_at_decision, error_msg FROM auto_clean_events ORDER BY id DESC LIMIT 500");
    if (!actions && !autos) return nil;
    NSMutableArray *rows = [NSMutableArray new];
    for (NSDictionary *a in actions.reverseObjectEnumerator) {
        NSString *rid = [NSString stringWithFormat:@"legacy.noonoo.action.%@", a[@"id"]];
        NSMutableDictionary *body = [a mutableCopy];
        body[@"at"] = @(StoreTime(a[@"ts"])); body[@"from"] = @"Noo-Noo store.db actions";
        [rows addObject:@{@"table": @"legacy", @"rid": rid, @"expert": @"noonoo", @"subject": Str(a[@"target"]) ?: @"",
                          @"state": Str(a[@"outcome"]) ?: @"", @"body": body}];
    }
    for (NSDictionary *a in autos.reverseObjectEnumerator) {
        NSString *rid = [NSString stringWithFormat:@"legacy.noonoo.autoclean.%@", a[@"id"]];
        NSMutableDictionary *body = [a mutableCopy];
        body[@"at"] = a[@"started_at_unix"] ?: @0; body[@"from"] = @"Noo-Noo store.db auto_clean_events";
        [rows addObject:@{@"table": @"legacy", @"rid": rid, @"expert": @"noonoo", @"subject": Str(a[@"target_path"]) ?: @"",
                          @"state": Str(a[@"outcome"]) ?: @"", @"body": body}];
    }
    return rows;
}

/// readStore NO leaves store.db's rows out and names the file in plan["store"], so the import reads it off main.
static NSDictionary *NooNooPlan(NSString *home, BOOL readStore) {
    NSMutableDictionary *plan = EmptyPlan();
    NSMutableArray *sources = plan[@"sources"];
    // Noo-Noo's app kept only its status item's state in its own domain.
    NSDictionary *prefs = ReadDomain(home, @"io.noo-noo.app", sources);
    CopyPrefs(prefs, @"noonoo.", @{kOldVisibleKey: MMIconVisibleKey(@"noonoo")}, nil, plan[@"prefs"]);

    NSString *storePath = [home stringByAppendingPathComponent:@"Library/Application Support/noo-noo/store.db"];
    NSString *cfgPath = [home stringByAppendingPathComponent:@".config/noo-noo/config.toml"];
    NSString *toml = [NSString stringWithContentsOfFile:cfgPath encoding:NSUTF8StringEncoding error:nil];
    if (toml) {
        [sources addObject:cfgPath];
        NSDictionary *cfg = [[MMTOMLReader alloc] initWithString:toml].parse;
        // The whole file is kept, so nothing the person set is lost, and the parts 2.0 has a place for move there.
        plan[@"files"][@"noonoo/legacy-config.json"] = cfg;
        NSDictionary *auto_ = Dict(cfg[@"auto_clean"]);
        // Noo-Noo cleaned on its own only with auto_clean on and the risk acknowledged. Off, it only reported.
        if (auto_[@"enabled"] && !MMPref(@"noonoo.mode")) {
            BOOL on = [auto_[@"enabled"] boolValue] && Str(auto_[@"risk_acknowledged_at"]).length;
            plan[@"prefs"][@"noonoo.mode"] = on ? @"proactive" : @"idle";
        }
        NSMutableArray *roots = [NSMutableArray new];
        [roots addObjectsFromArray:List(Dict(cfg[@"scan"])[@"roots"]) ?: @[]];
        [roots addObjectsFromArray:List(Dict(cfg[@"worktrees"])[@"roots"]) ?: @[]];
        AddRoots(plan, roots);
        NSString *own = Str(Dict(cfg[@"daemon"])[@"store_path"]);
        // A store path in the file counts only inside this home, so a copy never reads the person's own store.
        if (own.length) {
            NSString *p = [own stringByReplacingOccurrencesOfString:@"~" withString:home options:NSAnchoredSearch range:NSMakeRange(0, own.length)];
            if ([p.stringByStandardizingPath hasPrefix:[home.stringByStandardizingPath stringByAppendingString:@"/"]]) storePath = p;
        }
    }

    // store.db: what Noo-Noo did, as history rows. In the import it is read with the other rows, off main.
    if ([NSFileManager.defaultManager fileExistsAtPath:storePath]) {
        if (!readStore) { plan[@"store"] = storePath; [sources addObject:storePath]; }
        else {
            NSArray *rows = NooNooStoreRows(storePath);
            if (rows) { [sources addObject:storePath]; [plan[@"rows"] addObjectsFromArray:rows]; }
        }
    }
    return plan;
}

#pragma mark - The plan and the import

static NSArray<NSString *> *SourceNames(void) { return @[@"insomnia", @"locohost", @"minmacs-1.2", @"noonoo", @"workforest"]; }

static NSDictionary *PlanFor(NSString *name, NSString *home, BOOL readStore) {
    if ([name isEqualToString:@"locohost"]) return LocoHostPlan(home);
    if ([name isEqualToString:@"minmacs-1.2"]) return MinMacs12Plan(home);
    if ([name isEqualToString:@"workforest"]) return WorkForestPlan(home);
    if ([name isEqualToString:@"insomnia"]) return InsomniaPlan(home);
    if ([name isEqualToString:@"noonoo"]) return NooNooPlan(home, readStore);
    return EmptyPlan();
}

/// One file's JSON from two sources: named lists are joined, anything else the first source keeps.
static id MergeJSON(id a, id b) {
    if (![a isKindOfClass:NSDictionary.class] || ![b isKindOfClass:NSDictionary.class]) return a ?: b;
    NSMutableDictionary *out = [a mutableCopy];
    for (NSString *k in b) {
        if (!out[k]) { out[k] = b[k]; continue; }
        if (List(out[k]) && List(b[k])) {
            NSMutableArray *l = [out[k] mutableCopy];
            for (id v in b[k]) if (![l containsObject:v]) [l addObject:v];
            out[k] = l;
        }
    }
    return out;
}

static NSDictionary *Merge(NSDictionary *plans, NSArray *names) {
    NSMutableDictionary *all = EmptyPlan();
    all[@"names"] = [NSMutableArray new];
    for (NSString *n in names) {
        NSDictionary *p = plans[n];
        if ([p[@"sources"] count]) [all[@"names"] addObject:n];
        [all[@"prefs"] addEntriesFromDictionary:p[@"prefs"]];
        for (NSString *path in p[@"files"]) all[@"files"][path] = MergeJSON(all[@"files"][path], p[@"files"][path]);
        for (NSString *path in p[@"merge"]) all[@"merge"][path] = MergeJSON(all[@"merge"][path], p[@"merge"][path]);
        [all[@"rows"] addObjectsFromArray:p[@"rows"]];
        [all[@"sources"] addObjectsFromArray:p[@"sources"]];
    }
    return all;
}

static NSObject *MarkLock(void) { static NSObject *o; static dispatch_once_t once; dispatch_once(&once, ^{ o = [NSObject new]; }); return o; }
static NSDictionary *Marks(void) { return Dict(MMPref(MMMigratedKey)) ?: @{}; }
/// Records parts as done, merged with what is in the pref now, so the import and the follow-up never undo each other.
static void Mark(NSArray<NSString *> *parts) {
    if (!parts.count) return;
    @synchronized (MarkLock()) {
        NSMutableDictionary *m = [Marks() mutableCopy];
        for (NSString *p in parts) m[p] = NSDate.date;
        MMSetPref(MMMigratedKey, m);
    }
}

NSDictionary *MMLegacyPlan(NSString *home) {
    home = home.length ? home : NSHomeDirectory();
    NSMutableDictionary *plans = [NSMutableDictionary new];
    for (NSString *n in SourceNames()) plans[n] = PlanFor(n, home, YES);
    return Merge(plans, SourceNames());
}

NSDictionary *MMImportLegacy(NSString *home) {
    home = home.length ? home : NSHomeDirectory();
    NSDictionary *done = Marks();
    NSMutableDictionary *plans = [NSMutableDictionary new];
    NSMutableArray *todo = [NSMutableArray new];
    // A source marked before is not read again. A source with nothing to read is not marked, so it is looked at
    // again when it appears.
    for (NSString *n in SourceNames()) {
        if (done[n]) continue;
        plans[n] = PlanFor(n, home, NO);
        if ([plans[n][@"sources"] count]) [todo addObject:n];
    }
    NSDictionary *plan = Merge(plans, todo);

    [plan[@"prefs"] enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) { MMSetPref(k, v); }];
    [plan[@"files"] enumerateKeysAndObjectsUsingBlock:^(NSString *path, id json, BOOL *stop) {
        MMStateFile *f = [MMStateFile fileNamed:path.lastPathComponent.stringByDeletingPathExtension expert:path.stringByDeletingLastPathComponent];
        [f update:^id(id disk) { return disk ? nil : json; }];   // a file 2.0 already wrote stays as it is
    }];
    // A map such as legacy-removed.json gains the keys it lacks. Written now, before the rows, so the WorkForest
    // expert's own import, which runs later at launch, skips what this one brings.
    [plan[@"merge"] enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *add, BOOL *stop) {
        MMStateFile *f = [MMStateFile fileNamed:path.lastPathComponent.stringByDeletingPathExtension expert:path.stringByDeletingLastPathComponent];
        [f update:^id(id disk) {
            NSMutableDictionary *m = [Dict(disk) mutableCopy] ?: [NSMutableDictionary new];
            BOOL changed = NO;
            for (NSString *k in add) if (!m[k]) { m[k] = add[k]; changed = YES; }
            return changed ? m : nil;
        }];
    }];
    // The rows go to the log off main in the app, and the marker is set after them, so a launch that ends first
    // imports again. A row imported before is skipped by its rid.
    // store.db is read there too, since the app calls the import on main.
    NSArray *rows = plan[@"rows"];
    NSArray *names = [todo copy];
    NSString *store = [todo containsObject:@"noonoo"] ? plans[@"noonoo"][@"store"] : nil;
    MMLogWhenOpen(^(MMLog *log) {
        NSArray *all = store ? [rows arrayByAddingObjectsFromArray:NooNooStoreRows(store) ?: @[]] : rows;
        for (NSDictionary *r in all) {
            if ([log history:r[@"rid"]].count) continue;   // imported before, under another marker
            [log append:r[@"table"] rid:r[@"rid"] expert:r[@"expert"] subject:r[@"subject"] state:r[@"state"] body:r[@"body"]];
        }
        Mark(names);
    });
    return plan;
}

BOOL MMMigrateWanted(NSDictionary<NSString *, NSString *> *env) {
    return !env[@"MINMACS_HOME"].length && !env[@"MM_TESTS"].length;
}

#pragma mark - What the follow-up finds

NSString *MMNooNooAgentPath(NSString *home) {
    home = home.length ? home : NSHomeDirectory();
    return [home stringByAppendingFormat:@"/Library/LaunchAgents/%@.plist", MMNooNooAgentLabel];
}

#ifdef MM_TESTS
static NSInteger (^gAgentStatus)(NSURL *);
void MMUseNooNooAgentStatus(NSInteger (^status)(NSURL *plist)) { gAgentStatus = [status copy]; }
#endif

NSInteger MMNooNooAgentStatus(NSString *home) {
    NSURL *url = [NSURL fileURLWithPath:MMNooNooAgentPath(home)];
#ifdef MM_TESTS
    if (gAgentStatus) return gAgentStatus(url);
#endif
    if (NSThread.isMainThread) return -1;
    // Looked up by name, so a binary without ServiceManagement, such as a test tool, still links.
    Class c = NSClassFromString(@"SMAppService");
    SEL sel = NSSelectorFromString(@"statusForLegacyURL:");
    if (![c respondsToSelector:sel]) return -1;
    NSInteger (*status)(id, SEL, NSURL *) = (NSInteger (*)(id, SEL, NSURL *))objc_msgSend;
    return status(c, sel, url);
}

@interface MMLegacyApp ()
@property (readwrite, copy) NSString *name, *bundleID, *path, *expert;
@end
@implementation MMLegacyApp
@end

/// The four old apps 2.0 replaces, by name, bundle id and expert. MinMacs 1.x has 2.0's own bundle id.
static NSArray<NSArray<NSString *> *> *OldApps(void) {
    return @[@[@"LocoHost", @"no.guerrilla.locohost", @"locohost"], @[@"WorkForest", @"no.guerrilla.workforest", @"workforest"],
             @[@"Insomnia", kInsomniaDomain, @"insomnia"], @[@"Noo-Noo", @"io.noo-noo.app", @"noonoo"]];
}

static NSString *BundleIDAt(NSString *app) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    return Str(info[@"CFBundleIdentifier"]);
}

NSArray<MMLegacyApp *> *MMLegacyApps(NSString *home) {
    home = home.length ? home : NSHomeDirectory();
    NSMutableArray *dirs = [NSMutableArray arrayWithObject:[home stringByAppendingPathComponent:@"Applications"]];
    if (IsOwnHome(home)) [dirs addObject:@"/Applications"];
    NSString *me = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSMutableArray *out = [NSMutableArray new];
    for (NSArray *a in OldApps()) {
        for (NSString *dir in dirs) {
            NSString *path = [dir stringByAppendingPathComponent:[a[0] stringByAppendingPathExtension:@"app"]];
            NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
            if (![attrs.fileType isEqualToString:NSFileTypeDirectory]) continue;   // a symlink or a file is left alone
            if (![BundleIDAt(path) isEqualToString:a[1]] || [path.stringByStandardizingPath isEqualToString:me]) continue;
            MMLegacyApp *x = [MMLegacyApp new];
            x.name = a[0]; x.bundleID = a[1]; x.expert = a[2]; x.path = path;
            [out addObject:x];
        }
    }
    return out;
}

#ifdef MM_TESTS
static NSArray<MMApp *> *(^gRunning)(void);
void MMUseLegacyRunningApps(NSArray<MMApp *> *(^running)(void)) { gRunning = [running copy]; }
#endif

static MMApp *RunningAt(NSString *path, NSString *bundleID) {
    NSArray<MMApp *> *apps = MMRunningApps();
#ifdef MM_TESTS
    if (gRunning) apps = gRunning();
#endif
    for (MMApp *a in apps) {
        if (path && [a.bundlePath.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) return a;
        if (!path && [a.bundleID isEqualToString:bundleID]) return a;
    }
    return nil;
}

#pragma mark - The follow-up's actions

/// Turns the lid override off, once, after the old Insomnia. The finding wants it off.
@interface MMMigrateLidOff : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end
@implementation MMMigrateLidOff
- (NSString *)kind { return @"lid"; }
- (NSString *)recheck { return [MMLidOverride unavailableReason]; }
- (NSString *)dryRun { return @"sudo -n /usr/bin/pmset -a disablesleep 0"; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    [MMUndo.shared note:record payload:@{@"lid": @NO, @"command": [self dryRun], @"from": @"Insomnia.app"}];
    return [MMLidOverride set:NO error:error];
}
@end

/// launchctl, or with MINMACS_HOME set only the fake MINMACS_LAUNCHCTL_CMD with the whole command line.
static BOOL Launchctl(NSArray<NSString *> *args, NSString **error) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSString *home = env[@"MINMACS_HOME"], *fake = home.length ? env[@"MINMACS_LAUNCHCTL_CMD"] : nil;
    if (home.length && !fake.length) { if (error) *error = @"a test home never runs launchctl"; return NO; }
    NSString *path = fake.length ? fake : @"/bin/launchctl";
    NSArray *argv = fake.length ? [@[@"/bin/launchctl"] arrayByAddingObjectsFromArray:args] : args;
    NSData *err = nil;
    MMRunResult r = MMRun(path, argv, nil, fake.length ? @{@"MINMACS_HOME": home} : nil, nil, 10, NULL, &err);
    if (r.didRun && !r.timedOut && r.status == 0) return YES;
    if (error) {
        NSString *said = [[[NSString alloc] initWithData:err ?: NSData.data encoding:NSUTF8StringEncoding]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        *error = !r.didRun ? @"launchctl did not start" : r.timedOut ? @"launchctl did not answer in time"
               : said.length ? said : [NSString stringWithFormat:@"launchctl exited with status %d", r.status];
    }
    return NO;
}

/// Stops Noo-Noo's LaunchAgent and moves its plist to the Trash. Undo moves the plist back; it loads at the next login.
@interface MMMigrateAgentAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end
@implementation MMMigrateAgentAction
- (NSString *)kind { return @"trash"; }
- (NSString *)recheck {
    NSString *path = self.finding.path;
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attrs.fileType isEqualToString:NSFileTypeRegular]) return @"the agent's file is gone";
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![Str(plist[@"Label"]) isEqualToString:MMNooNooAgentLabel]) return @"the file is not Noo-Noo's agent";
    return nil;
}
- (NSString *)dryRun {
    return [NSString stringWithFormat:@"launchctl bootout gui/%u %@, then the file goes to the Trash", getuid(), self.finding.path];
}
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    NSString *why = nil;
    // Noo-Noo's own uninstall stops the agent the same way and goes on when it was not loaded.
    BOOL stopped = Launchctl(@[@"bootout", [NSString stringWithFormat:@"gui/%u", getuid()], self.finding.path], &why);
    [MMUndo.shared note:record payload:@{@"label": MMNooNooAgentLabel, @"bootout": stopped ? @"stopped" : (why ?: @"failed")}];
    NSError *e = nil;
    if ([MMUndo.shared trash:[NSURL fileURLWithPath:self.finding.path] record:record error:&e]) return YES;
    if (error) *error = e.localizedDescription ?: @"the file did not go to the Trash";
    return NO;
}
@end

static MMProcKey KeyOf(pid_t pid) {
    MMProcKey k = { pid, 0 };
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len == sizeof kp) k.startSec = (uint64_t)kp.kp_proc.p_starttime.tv_sec;
    return k;
}

/// Quits an old app when it runs, then moves it to the Trash. Undo moves it back.
@interface MMMigrateAppAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@property (copy) NSString *bundleID;
@end
@implementation MMMigrateAppAction
- (NSString *)kind { return @"trash"; }
- (NSString *)recheck {
    NSString *path = self.finding.path;
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attrs.fileType isEqualToString:NSFileTypeDirectory]) return @"the app is gone";
    if (![BundleIDAt(path) isEqualToString:self.bundleID]) return @"the app there is another one now";
    return nil;
}
- (NSString *)dryRun { return [NSString stringWithFormat:@"quits %@ when it runs, then moves it to the Trash", self.finding.path.lastPathComponent]; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMApp *running = RunningAt(self.finding.path, nil);
    if (running) {
        NSArray *left = MMQuitApps(@[[NSValue valueWithBytes:(MMProcKey[]){KeyOf(running.pid)} objCType:@encode(MMProcKey)]], MMStopTerm, 10);
        [MMUndo.shared note:record payload:@{@"quit": left.count ? @"still runs" : @"quit"}];
        if (left.count) { if (error) *error = @"it did not quit"; return NO; }
    }
    NSError *e = nil;
    if ([MMUndo.shared trash:[NSURL fileURLWithPath:self.finding.path] record:record error:&e]) return YES;
    if (error) *error = e.localizedDescription ?: @"it did not go to the Trash";
    return NO;
}
@end

/// The keep checks of the follow-up. The person said yes to the agent and the apps, so only the lid has work keeps.
@interface MMMigratePolicy : NSObject <MMExpertPolicy>
@end
@implementation MMMigratePolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    if (![f.kind isEqualToString:@"lid"]) return nil;
    if (RunningAt(nil, kInsomniaDomain)) return @"Insomnia.app runs and sets it";
    if (!facts.power) return @"cannot verify the power facts";
    if (!facts.power.lidOverride) return kAlreadyOff;
    // The Insomnia expert writes the override while its lid mode is on, and clears it when nothing wants it. It may
    // want it on now, with the lid shut and an agent at work, so the follow-up leaves it to the expert.
    return MMPrefBool(@"insomnia.lid", NO) ? kLidModeOwns : nil;
}
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

static MMFinding *Subject(NSString *expert, NSString *kind, NSString *key, NSString *title, NSString *path, MMReversibility rev) {
    return [MMFinding expert:expert kind:kind stableKey:key build:^(MMFindingBuilder *b) {
        b.title = title; b.path = path;
        b.proposal = [MMProposal verb:kind title:title reversibility:rev];
    }];
}

static NSString *Names(NSArray<NSString *> *names) {
    if (names.count <= 1) return names.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@", [[names subarrayWithRange:NSMakeRange(0, names.count - 1)] componentsJoinedByString:@", "], names.lastObject];
}

static NSDictionary *LidPart(NSString *home) {
    NSDictionary *prefs = ReadDomain(home, kInsomniaDomain, nil);
    // Only an override the old Insomnia's lid mode set is turned off. One another tool set stays.
    if (![prefs[@"insomnia.lid"] boolValue]) { Mark(@[@"insomnia.lid"]); return @{@"state": @"lid mode was off"}; }
    MMMigrateLidOff *a = [MMMigrateLidOff new];
    a.finding = Subject(@"insomnia", @"lid", @"migrate", @"Lid override off", nil, MMReversibleNotNeeded);
    NSString *err = nil;
    MMUndoRecord *r = MMRunAction(a, [MMMigratePolicy new], nil, @"guard", @"MinMacs takes over from Insomnia.app", &err);
    if (r.state == MMUndoDone) { Mark(@[@"insomnia.lid"]); return @{@"state": @"off", @"rid": r.rid}; }
    if ([err hasSuffix:kAlreadyOff]) { Mark(@[@"insomnia.lid"]); return @{@"state": @"already off"}; }
    if ([err hasSuffix:kLidModeOwns]) { Mark(@[@"insomnia.lid"]); return @{@"state": @"lid mode owns it"}; }
    // Insomnia.app runs, or the write failed: the next launch tries again.
    return @{@"state": @"waits", @"why": err ?: r.error ?: @"the write failed"};
}

NSDictionary *MMMigrateFollowUp(NSString *home, MMMigrateAsk ask) {
    if (NSThread.isMainThread) return @{@"error": @"the follow-up never runs on the main thread"};
    home = home.length ? home : NSHomeDirectory();
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSMutableArray *asked = [NSMutableArray new];
    out[@"asked"] = asked;
    MMMigrateAsk confirm = ^BOOL(NSString *title, NSString *body, NSString *yes, NSString *no) {
        [asked addObject:title];
        return ask ? ask(title, body, yes, no) : NO;
    };

    if (!Marks()[@"insomnia.lid"]) out[@"insomnia.lid"] = LidPart(home);

    if (!Marks()[@"noonoo.agent"]) {
        NSString *path = MMNooNooAgentPath(home);
        NSInteger status = MMNooNooAgentStatus(home);
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
            Mark(@[@"noonoo.agent"]);
            out[@"noonoo.agent"] = @{@"state": @"none", @"status": @(status)};
        } else {
            BOOL yes = confirm(@"Remove Noo-Noo's Background Agent?",
                               @"Noo-Noo's agent still starts at login. MinMacs does its work now. "
                               "MinMacs stops the agent and moves its file to the Trash. You can put it back with minmacs restore.",
                               @"Remove Agent", @"Keep It");
            NSMutableDictionary *r = [@{@"status": @(status), @"state": yes ? @"removed" : @"kept"} mutableCopy];
            if (yes) {
                MMMigrateAgentAction *a = [MMMigrateAgentAction new];
                a.finding = Subject(@"core", @"agent", MMNooNooAgentLabel, @"Noo-Noo's agent", path, MMReversibleTrash);
                NSString *err = nil;
                MMUndoRecord *rec = MMRunAction(a, [MMMigratePolicy new], nil, @"manual", @"replaced by MinMacs", &err);
                if (rec.state == MMUndoDone) r[@"rid"] = rec.rid;
                else { r[@"state"] = @"failed"; r[@"why"] = err ?: rec.error ?: @"it failed"; }
            }
            Mark(@[@"noonoo.agent"]);
            out[@"noonoo.agent"] = r;
        }
    }

    if (!Marks()[@"apps"]) {
        NSArray<MMLegacyApp *> *apps = MMLegacyApps(home);
        NSMutableArray *results = [NSMutableArray new];
        if (apps.count) {
            NSMutableArray *names = [NSMutableArray new];
            for (MMLegacyApp *a in apps) if (![names containsObject:a.name]) [names addObject:a.name];
            NSString *body = [NSString stringWithFormat:@"MinMacs now does the work of %@, and their settings, rules and undo history "
                              "carried over. MinMacs quits the ones that run and moves them to the Trash. "
                              "You can put them back from the Trash or with minmacs restore.", Names(names)];
            BOOL yes = confirm(names.count == 1 ? [NSString stringWithFormat:@"Move %@ to the Trash?", names[0]] : @"Move the Old Apps to the Trash?",
                               body, @"Move to Trash", @"Keep Them");
            for (MMLegacyApp *a in apps) {
                NSMutableDictionary *r = [@{@"name": a.name, @"path": a.path, @"state": yes ? @"trashed" : @"kept"} mutableCopy];
                if (yes) {
                    MMMigrateAppAction *act = [MMMigrateAppAction new];
                    act.bundleID = a.bundleID;
                    act.finding = Subject(@"core", @"app", a.path, a.name, a.path, MMReversibleTrash);
                    NSString *err = nil;
                    MMUndoRecord *rec = MMRunAction(act, [MMMigratePolicy new], nil, @"manual", @"replaced by MinMacs", &err);
                    if (rec.state == MMUndoDone) r[@"rid"] = rec.rid;
                    else { r[@"state"] = @"failed"; r[@"why"] = err ?: rec.error ?: @"it failed"; }
                }
                [results addObject:r];
            }
        }
        Mark(@[@"apps"]);
        out[@"apps"] = results;
        // Insomnia.app may have held the override until it quit just now.
        BOOL quit = NO;
        for (NSDictionary *r in results) if ([r[@"state"] isEqual:@"trashed"] && [r[@"name"] isEqual:@"Insomnia"]) quit = YES;
        if (quit && !Marks()[@"insomnia.lid"]) out[@"insomnia.lid"] = LidPart(home);
    }
    return out;
}
