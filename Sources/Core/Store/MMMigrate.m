// The migration of PLAN.md section 8, for MinMacs 1.2 and LocoHost. Their files and prefs are read and never written.
// The shapes come from the old code: LocoHost's Rules.m, Ports.m SaveActivity, main.m KeepList and RememberClosed,
// and MinMacs 1.2's Rules.m and its minmacs.closedBundleIDs and minmacs.closedTabs prefs in main.m.
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"

static NSString *const kMigratedKey = @"core.migrated";
// The old apps made their status item with no autosaveName, so AppKit saved its state under the first item's name.
static NSString *const kOldVisibleKey = @"NSStatusItem Visible Item-0";

static id ReadJSON(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
}

/// An old prefs domain. The person's own home goes through CFPreferences, which only reads here.
/// Any other home is a copy, read from its plist file.
static NSDictionary *ReadDomain(NSString *home, NSString *domain, NSMutableArray *sources) {
    NSString *plist = [home stringByAppendingFormat:@"/Library/Preferences/%@.plist", domain];
    if ([home.stringByStandardizingPath isEqualToString:NSHomeDirectory().stringByStandardizingPath]) {
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
    return [@{@"prefs": [NSMutableDictionary new], @"files": [NSMutableDictionary new],
              @"rows": [NSMutableArray new], @"sources": [NSMutableArray new]} mutableCopy];
}

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
    NSArray *ids = [prefs[@"minmacs.closedBundleIDs"] isKindOfClass:NSArray.class] ? prefs[@"minmacs.closedBundleIDs"] : @[];
    NSArray *tabs = [prefs[@"minmacs.closedTabs"] isKindOfClass:NSArray.class] ? prefs[@"minmacs.closedTabs"] : @[];
    NSMutableArray *apps = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray *> *urls = [NSMutableDictionary new];
    for (id b in ids) if ([b isKindOfClass:NSString.class] && ![apps containsObject:b]) [apps addObject:b];
    for (NSDictionary *t in tabs) {
        if (![t isKindOfClass:NSDictionary.class] || ![t[@"bundleID"] isKindOfClass:NSString.class] || ![t[@"url"] isKindOfClass:NSString.class]) continue;
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

static NSDictionary *Plans(NSString *home) {
    home = home.length ? home : NSHomeDirectory();
    return @{@"locohost": LocoHostPlan(home), @"minmacs-1.2": MinMacs12Plan(home)};
}

static NSDictionary *Merge(NSDictionary *plans, NSArray *names) {
    NSMutableDictionary *all = EmptyPlan();
    for (NSString *n in names) {
        NSDictionary *p = plans[n];
        [all[@"prefs"] addEntriesFromDictionary:p[@"prefs"]];
        [all[@"files"] addEntriesFromDictionary:p[@"files"]];
        [all[@"rows"] addObjectsFromArray:p[@"rows"]];
        [all[@"sources"] addObjectsFromArray:p[@"sources"]];
    }
    return all;
}

NSDictionary *MMLegacyPlan(NSString *home) {
    NSDictionary *plans = Plans(home);
    return Merge(plans, [plans.allKeys sortedArrayUsingSelector:@selector(compare:)]);
}

NSDictionary *MMImportLegacy(NSString *home) {
    NSDictionary *plans = Plans(home);
    NSDictionary *done = [MMPref(kMigratedKey) isKindOfClass:NSDictionary.class] ? MMPref(kMigratedKey) : @{};
    NSMutableArray *todo = [NSMutableArray new];
    // A source with nothing to read is not marked, so it is looked at again when it appears.
    for (NSString *n in [plans.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (!done[n] && [plans[n][@"sources"] count]) [todo addObject:n];
    NSDictionary *plan = Merge(plans, todo);

    [plan[@"prefs"] enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) { MMSetPref(k, v); }];
    [plan[@"files"] enumerateKeysAndObjectsUsingBlock:^(NSString *path, id json, BOOL *stop) {
        MMStateFile *f = [MMStateFile fileNamed:path.lastPathComponent.stringByDeletingPathExtension expert:path.stringByDeletingLastPathComponent];
        [f update:^id(id disk) { return disk ? nil : json; }];   // a file 2.0 already wrote stays as it is
    }];
    MMLog *log = MMLog.shared;
    for (NSDictionary *r in plan[@"rows"]) {
        if ([log history:r[@"rid"]].count) continue;   // imported before, under another marker
        [log append:r[@"table"] rid:r[@"rid"] expert:r[@"expert"] subject:r[@"subject"] state:r[@"state"] body:r[@"body"]];
    }
    if (todo.count) {
        NSMutableDictionary *mark = [done mutableCopy];
        for (NSString *n in todo) mark[n] = NSDate.date;
        MMSetPref(kMigratedKey, mark);
    }
    return plan;
}
