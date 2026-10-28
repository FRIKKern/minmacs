// The migration's test tool, issue #37. Built by test/migrate.sh with Core, the kit and the CLI under -DMM_TESTS.
// Every path it reads or writes is inside $MINMACS_HOME. The old home it reads is a copy the test made there.
// Usage:
//   tool plan <home>                       prints MMLegacyPlan(home) as JSON
//   tool import <home>                     prints MMImportLegacy(home) as JSON
//   tool followup <home> <yes|no> [log]    runs MMMigrateFollowUp with a fake confirm that answers yes or no, prints
//                                          its report, and appends each confirm's title and body to log
//   tool record <rid>                      prints the undo record as JSON with canRestore
//   tool restore <rid>                     -[MMUndo restore:], prints ok or the problem
//   tool readable <path>                   yes when this process may read the file, for the sandbox check
//   tool wanted                            prints MMMigrateWanted for a few environments
//   tool route <url>                       prints the expert a URL goes to
// The follow-up's power facts come from a fake power source that reads $MINMACS_HOME/migrate-fake/lid, which
// test/migrate/fakecmd.sh writes in place of pmset. Noo-Noo's agent status is MIGRATE_AGENT_STATUS, and the running
// apps are the bundle ids in MIGRATE_RUNNING, so the person's own running apps never count.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "Core/Store/MMMigrate.h"
#import "CLI/MMRouter.h"

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String : "null");
}

/// Dates cannot go into JSON, so they print as seconds since 1970.
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

static NSString *FakeDir(void) {
    return [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"migrate-fake"];
}

/// The lid override as the fake pmset left it.
@interface MGPower : NSObject <MMPowerSource>
@end
@implementation MGPower
- (MMPower *)read {
    NSString *lid = [NSString stringWithContentsOfFile:[FakeDir() stringByAppendingPathComponent:@"lid"] encoding:NSUTF8StringEncoding error:nil];
    BOOL on = [[lid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqualToString:@"1"];
    return MMPowerFrom(@{@"lidOverride": @(on), @"onAC": @YES, @"batteryPercent": @80});
}
@end

/// A running app the test names by bundle id, from MIGRATE_RUNNING. The person's own running apps never count.
@interface MGApp : MMApp
@property (copy) NSString *bid;
@end
@implementation MGApp
- (NSString *)bundleID { return self.bid; }
- (NSString *)bundlePath { return nil; }
@end

/// Fresh facts for MMRunAction: the fake power facts, read again on each call, and no sample.
@interface MGSource : NSObject <MMFactSource>
@end
@implementation MGSource
- (MMFacts *)factsFor:(uint64_t)generation { return nil; }
- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    return [MMFacts generation:0 sample:nil power:[[MGPower new] read] agents:@[] sessions:@[] worktrees:@[] clutter:@[] git:@{}];
}
@end

static id OffMain(id (^work)(void)) {
    __block id out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ out = work(); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return out;
}

static NSString *StateName(MMUndoState s) {
    switch (s) { case MMUndoPending: return @"pending"; case MMUndoDone: return @"done"; case MMUndoFailed: return @"failed"; case MMUndoRestored: return @"restored"; }
    return @"?";
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "MINMACS_HOME must be set\n"); return 2; }
        NSString *verb = argc > 1 ? @(argv[1]) : @"";
        NSString *arg = argc > 2 ? @(argv[2]) : @"";
        if ([verb isEqualToString:@"plan"]) { PrintJSON(Printable(MMLegacyPlan(arg))); return 0; }
        if ([verb isEqualToString:@"import"]) { PrintJSON(Printable(MMImportLegacy(arg))); return 0; }
        if ([verb isEqualToString:@"followup"] && argc > 3) {
            BOOL yes = !strcmp(argv[3], "yes");
            NSString *log = argc > 4 ? @(argv[4]) : nil;
            MMUsePowerSource([MGPower new]);
            MMGraph.shared.source = [MGSource new];
            NSString *status = NSProcessInfo.processInfo.environment[@"MIGRATE_AGENT_STATUS"];
            MMUseNooNooAgentStatus(^NSInteger(NSURL *plist) { return status.length ? status.integerValue : 3; });
            NSMutableArray *running = [NSMutableArray new];
            for (NSString *b in [NSProcessInfo.processInfo.environment[@"MIGRATE_RUNNING"] componentsSeparatedByString:@","]) {
                if (!b.length) continue;
                MGApp *a = [MGApp new]; a.bid = b; [running addObject:a];
            }
            MMUseLegacyRunningApps(^NSArray<MMApp *> *{ return running; });
            NSDictionary *r = OffMain(^id{
                return MMMigrateFollowUp(arg, ^BOOL(NSString *title, NSString *body, NSString *y, NSString *n) {
                    if (log) {
                        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:log];
                        if (!h) { [NSData.data writeToFile:log atomically:YES]; h = [NSFileHandle fileHandleForWritingAtPath:log]; }
                        [h seekToEndOfFile];
                        [h writeData:[[NSString stringWithFormat:@"%@\t%@\t%@\t%@\n", title, body, y, n] dataUsingEncoding:NSUTF8StringEncoding]];
                        [h closeFile];
                    }
                    return yes;
                });
            });
            PrintJSON(Printable(r));
            return 0;
        }
        if ([verb isEqualToString:@"record"]) {
            MMUndoRecord *r = [MMUndo.shared record:arg];
            if (!r) { PrintJSON(@{}); return 0; }
            PrintJSON(Printable(@{@"kind": r.kind ?: @"", @"expert": r.expert ?: @"", @"state": StateName(r.state), @"by": r.by ?: @"",
                                  @"canRestore": @(r.canRestore), @"payload": r.payload ?: @{}, @"subject": r.subject ?: @""}));
            return 0;
        }
        if ([verb isEqualToString:@"restore"]) {
            NSString *p = OffMain(^id{ return [MMUndo.shared restore:arg]; });
            printf("%s\n", p ? p.UTF8String : "ok");
            return 0;
        }
        if ([verb isEqualToString:@"readable"]) {
            printf("%s\n", [NSData dataWithContentsOfFile:arg] ? "yes" : "no");
            return 0;
        }
        if ([verb isEqualToString:@"wanted"]) {
            printf("%s %s %s\n", MMMigrateWanted(@{}) ? "yes" : "no", MMMigrateWanted(@{@"MINMACS_HOME": @"/x"}) ? "yes" : "no",
                   MMMigrateWanted(@{@"MM_TESTS": @"1"}) ? "yes" : "no");
            return 0;
        }
        if ([verb isEqualToString:@"route"]) {
            MMRoute *r = MMRouteURL([NSURL URLWithString:arg], nil);
            printf("%s %s\n", r.kind == MMRouteExpert ? "expert" : "other", r.expert.UTF8String ?: "-");
            return 0;
        }
        fprintf(stderr, "unknown verb\n");
        return 2;
    }
}
