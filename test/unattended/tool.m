// D3, no person needed: the test tool of test/unattended.sh. Built with all of Core, the kit, the CLI, the five
// experts and the window's log and controller under -DMM_TESTS, and run inside the section's MINMACS_HOME.
//   tool notice     MMNotice: its row, its one notification, and its sentence in the window's log
//   tool paths      each former alert path, driven with nobody there: it writes its notice and shows no confirm
//   tool welcome    the welcome on a Mac that runs unattended: skipped, its defaults applied and logged
//   tool lid        lid mode turned on with no sudoers rule: refused at once while unattended, with its notice, and
//                   macOS's prompt only for a person. The commands go to $MINMACS_INSOMNIA_CMD, test/insomnia/fakecmd.sh
// Each prints one line per check, CHECK<TAB>name<TAB>want<TAB>got, and END last.
// Nothing here acts on anything outside the test home: the actions are fakes that fail their own check, the record
// ids name nothing, the lid override meets MMLidOverride's refusal in a test home, and the login item is a fake.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "UI/MMConfirm.h"
#import "Shell/MMWindowLog.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMWindowController.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/Insomnia/MMInsomnia.h"
#import "Experts/MinMacs/MMMinMacs.h"

static void T(NSString *name, NSString *want, NSString *got) { printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"(nil)").UTF8String); fflush(stdout); }
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }

/// Spins main until done says YES or seconds pass, so work that hops through main can finish.
static BOOL Spin(double seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done()) {
        if (until.timeIntervalSinceNow < 0) return NO;
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return YES;
}

static NSArray<MMLogEntry *> *Notices(void) { return [MMLog.shared rows:@[MMLogNoticeTable] before:0 limit:100]; }
static NSString *NoticeTitled(NSString *expert, NSString *title) {
    for (MMLogEntry *e in Notices())
        if ([e.expert isEqualToString:expert] && [e.body[@"title"] isEqual:title]) return [NSString stringWithFormat:@"%@|%@", e.body[@"title"], e.body[@"text"]];
    return nil;
}
static BOOL WaitNotice(NSString *expert, NSString *title) { return Spin(10, ^BOOL { return NoticeTitled(expert, title) != nil; }); }

@interface UNotifier : NSObject <MMNotifier>
@property (strong) NSMutableArray<NSString *> *posts;
@end
@implementation UNotifier
- (instancetype)init { if ((self = [super init])) _posts = [NSMutableArray new]; return self; }
- (void)post:(NSString *)title body:(NSString *)body undoRid:(NSString *)undoRid passive:(BOOL)passive expert:(NSString *)expert {
    @synchronized (self) { [self.posts addObject:[NSString stringWithFormat:@"%@|%@|%@", expert, title, undoRid ? @"undo" : @"none"]]; }
}
@end

/// An action whose own check always refuses, so MMRunAction never starts it and nothing is touched.
@interface UAction : NSObject <MMAction>
@property (strong) MMFinding *finding;
@end
@implementation UAction
- (NSString *)kind { return @"quit"; }
- (NSString *)recheck { return @"the fixture is gone"; }
- (NSString *)dryRun { return @"nothing"; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error { if (error) *error = @"it never runs"; return NO; }
@end

@interface ULogin : NSObject <MMWindowLogin>
@property BOOL enabled;
@property NSUInteger asked;
@end
@implementation ULogin
- (BOOL)loginEnabled { return self.enabled; }
- (void)setLogin:(BOOL)on { self.asked++; self.enabled = on; }
@end

@interface MMMinMacsExpert (UTest)
- (void)menuRun:(NSArray<id<MMAction>> *)actions;
@end
@interface MMWorkForestExpert (UTest)
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s;
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s present:(BOOL)present;
@end
@interface MMLocoHost (UTest)
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s;
- (void)act:(NSString *)what key:(NSString *)key option:(BOOL)option snapshot:(MMSnapshot *)s present:(BOOL)present;
@end
@interface MMInsomniaExpert (UTest)
- (void)act:(NSString *)what key:(NSString *)key;
- (NSString *)set:(NSString *)what value:(id)value by:(NSString *)by;
@end

static NSString *FakeLog(void) {
    NSString *p = [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"insomnia-fake/log"];
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

/// -set:value:by: off main, as the CLI and the act queue run it, and how long it took.
static NSString *SetOffMain(NSString *what, id value, NSTimeInterval *took) {
    __block NSString *problem = nil;
    NSDate *t0 = NSDate.date;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        problem = [MMInsomniaExpert.shared set:what value:value by:@"cli"];
        dispatch_semaphore_signal(done);
    });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW)) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (took) *took = -t0.timeIntervalSinceNow;
    return problem;
}

static NSUInteger NoticesTitled(NSString *title) {
    NSUInteger n = 0;
    for (MMLogEntry *e in Notices()) n += [e.body[@"title"] isEqual:title];
    return n;
}

static void Lid(void) {
    UNotifier *n = [UNotifier new];
    MMUseNotifier(n);
    MMSetPref(MMUnattendedKey, @YES);
    NSTimeInterval took = 0;
    NSString *problem = SetOffMain(@"lid", @YES, &took);
    T(@"lid: unattended with no rule, lid on is refused at once, in under 5 seconds", @"yes", YN(took < 5));
    T(@"lid: and says what the one-time setup is", @"yes", YN([problem hasPrefix:@"Lid mode needs a one-time setup: run minmacs insomnia lid on with a person present, or install /etc/sudoers.d/insomnia."]));
    T(@"lid: macOS's administrator prompt never ran", @"no", YN([FakeLog() containsString:@"osascript"]));
    T(@"lid: the refusal is one notice", @"1", [NSString stringWithFormat:@"%lu", (unsigned long)NoticesTitled(@"Lid Mode Needs a One-Time Setup")]);
    T(@"lid: and lid mode stays off", @"no", YN(MMPrefBool(@"insomnia.lid", NO)));
    // From the menu with nobody there: the same one notice, and no second one about Keep Awake.
    [MMInsomniaExpert.shared act:@"lid" key:nil];
    Spin(10, ^BOOL { return NoticesTitled(@"Lid Mode Needs a One-Time Setup") == 2; });
    T(@"lid: from the menu, unattended, one notice of the setup and none of a failure", @"2 0",
      [NSString stringWithFormat:@"%lu %lu", (unsigned long)NoticesTitled(@"Lid Mode Needs a One-Time Setup"), (unsigned long)NoticesTitled(@"Could Not Change Keep Awake")]);
    T(@"lid: no confirm was asked", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)MMAskPersonCalls()]);
    // A person is here: the turn goes to macOS's prompt, which the fake answers by writing the rule.
    MMSetPref(MMUnattendedKey, nil);
    problem = SetOffMain(@"lid", @YES, &took);
    T(@"lid: with a person here, lid on asks macOS for the rule", @"yes", YN([FakeLog() containsString:@"osascript"]));
    T(@"lid: and the setup notice is not written again", @"2", [NSString stringWithFormat:@"%lu", (unsigned long)NoticesTitled(@"Lid Mode Needs a One-Time Setup")]);
    MMUseNotifier(nil);
}

static void Notice(void) {
    UNotifier *n = [UNotifier new];
    MMUseNotifier(n);
    MMSetPref(@"act.lastNotify", nil);
    MMNotice(@"workforest", @"Could Not Restore", @"The record is gone.");
    MMNotice(@"locohost", @"Could Not Stop :3000", @"It did not stop.");
    NSArray<MMLogEntry *> *rows = Notices();
    T(@"notice: each one is a row of the notice table", @"2", [NSString stringWithFormat:@"%lu", (unsigned long)rows.count]);
    MMLogEntry *first = rows.lastObject;
    T(@"notice: the row holds expert, title and text", @"workforest|Could Not Restore|The record is gone.",
      [NSString stringWithFormat:@"%@|%@|%@", first.body[@"expert"], first.body[@"title"], first.body[@"text"]]);
    T(@"notice: at most one ordinary notification, with no Undo, inside the gap", @"workforest|Could Not Restore|none", [n.posts componentsJoinedByString:@","]);
    MMWindowLog *log = MMWindowLogFrom(rows, NSDate.date, 10, 0, 0);
    T(@"notice: the window's log says it in one plain sentence", @"Could not restore. The record is gone.|notice",
      [NSString stringWithFormat:@"%@|%@", log.entries.lastObject.sentence, log.entries.lastObject.kind]);
    T(@"notice: the log's tables include notice", @"yes", YN([MMWindowLogTables() containsObject:@"notice"]));
    MMUseNotifier(nil);
}

static void Paths(void) {
    UNotifier *n = [UNotifier new];
    MMUseNotifier(n);
    T(@"paths: with no click or key press, no person is plainly there", @"no", YN(MMPersonPresses()));
    // WorkForest: an Undo of a record that is not there, and Investigate of a subject with no folder.
    MMWorkForestExpert *wf = MMWorkForestExpert.shared;
    [wf act:@"restore" key:@"no-such-record" option:NO snapshot:nil];
    T(@"paths: WorkForest's failed restore is a notice", @"yes", YN(WaitNotice(@"workforest", @"Could Not Restore")));
    [wf act:@"investigate" key:@"no-such-subject" option:NO snapshot:nil present:NO];
    T(@"paths: WorkForest's failed Investigate is a notice", @"yes", YN(WaitNotice(@"workforest", @"Investigate Failed")));
    T(@"paths: a workforest://clean-up link with nothing to clean asks nothing", @"yes", YN([wf openURL:[NSURL URLWithString:@"workforest://clean-up"]]));
    // LocoHost: a restart of a record that is not there.
    [MMLocoHost.shared act:@"restart" key:@"no-such-record" option:NO snapshot:nil];
    T(@"paths: LocoHost's failed restart is a notice", @"yes", YN(WaitNotice(@"locohost", @"Could Not Restart")));
    [MMLocoHost.shared act:@"investigate" key:@"no-such-subject" option:NO snapshot:nil present:NO];
    T(@"paths: LocoHost's failed Investigate is a notice", @"yes", YN(WaitNotice(@"locohost", @"Investigate Failed")));
    // Keep awake: lid mode turned on from the menu with nobody there has no confirm. In a test home the sudoers
    // rule cannot be written, so the change fails, and says so as a notice.
    [MMInsomniaExpert.shared act:@"lid" key:nil];
    T(@"paths: the lid turned on with nobody there has no confirm, and its failure is a notice", @"yes", YN(WaitNotice(@"insomnia", @"Could Not Change Keep Awake")));
    T(@"paths: and the lid stays off", @"no", YN(MMPrefBool(@"insomnia.lid", NO)));
    // Apps and agents: an action from the menu that fails its own check.
    UAction *a = [UAction new];
    a.finding = [MMFinding expert:@"minmacs" kind:@"app" stableKey:@"unattended-fixture" build:^(MMFindingBuilder *b) { b.title = @"Fixture"; }];
    [MMMinMacsExpert.shared menuRun:@[a]];
    T(@"paths: a menu action of apps and agents that failed is a notice", @"yes", YN(WaitNotice(@"minmacs", @"MinMacs Could Not Do It")));
    T(@"paths: the notice says what failed", @"yes", YN([NoticeTitled(@"minmacs", @"MinMacs Could Not Do It") containsString:@"Fixture: "]));
    T(@"paths: no confirm was asked on any path", @"0", [NSString stringWithFormat:@"%lu", (unsigned long)MMAskPersonCalls()]);
    @synchronized (n) {
        T(@"paths: one notification at most, for all of these", @"yes", YN(n.posts.count <= 1));
    }
    MMUseNotifier(nil);
}

static void Welcome(void) {
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    ULogin *login = [ULogin new];
    MMSetPref(MMWindowWelcomedKey, nil);
    MMSetPref(MMUnattendedKey, nil);
    T(@"welcome: attended, the welcome shows and is not skipped", @"yes no 0",
      [NSString stringWithFormat:@"%@ %@ %lu", YN(MMWindowWelcomeNow(NO) != nil), YN([MMWindowController skipWelcomeUnattended:login]), (unsigned long)login.asked]);
    MMSetPref(MMUnattendedKey, @YES);
    T(@"welcome: unattended, no welcome is offered", @"yes", YN(MMWindowWelcomeNow(NO) == nil));
    BOOL skipped = [MMWindowController skipWelcomeUnattended:login];
    dispatch_sync(window, ^{});
    T(@"welcome: unattended, it is skipped, the login item turned on, and the welcome marked done", @"yes 1 yes yes",
      [NSString stringWithFormat:@"%@ %lu %@ %@", YN(skipped), (unsigned long)login.asked, YN(login.enabled), YN(MMPrefBool(MMWindowWelcomedKey, NO))]);
    NSMutableArray *rows = [NSMutableArray new];
    for (MMLogEntry *e in [MMLog.shared rows:@[MMLogSettingTable] before:0 limit:10])
        [rows addObject:[NSString stringWithFormat:@"%@=%@ by %@", e.body[@"key"], e.body[@"new"], e.body[@"by"]]];
    T(@"welcome: the skip is logged as setting rows by unattended", @"core.login=1 by unattended,core.welcomed=1 by unattended",
      [rows componentsJoinedByString:@","]);
    MMWindowLog *log = MMWindowLogFrom([MMLog.shared rows:@[MMLogSettingTable] before:0 limit:10], NSDate.date, 10, 0, 0);
    T(@"welcome: the log says the welcome was skipped, and by whom", @"The welcome was skipped, since this Mac runs unattended. Its defaults apply.|on its own, unattended",
      [NSString stringWithFormat:@"%@|%@", log.entries.lastObject.sentence, log.entries.lastObject.who]);
    T(@"welcome: a second time does nothing", @"no 1", [NSString stringWithFormat:@"%@ %lu", YN([MMWindowController skipWelcomeUnattended:login]), (unsigned long)login.asked]);
    // A login item that is on already is left as it is, and only the welcome's row is written.
    MMSetPref(MMWindowWelcomedKey, nil);
    ULogin *on = [ULogin new]; on.enabled = YES;
    [MMWindowController skipWelcomeUnattended:on];
    dispatch_sync(window, ^{});
    T(@"welcome: a login item already on is not asked for again", @"0 yes", [NSString stringWithFormat:@"%lu %@", (unsigned long)on.asked, YN(on.enabled)]);
    // MINMACS_UNATTENDED=0 says a person is here, whatever the pref holds.
    setenv("MINMACS_UNATTENDED", "0", 1);
    MMSetPref(MMWindowWelcomedKey, nil);
    T(@"welcome: MINMACS_UNATTENDED=0 decides over the pref, and the welcome shows", @"no yes",
      [NSString stringWithFormat:@"%@ %@", YN(MMUnattended()), YN(MMWindowWelcomeNow(NO) != nil)]);
    setenv("MINMACS_UNATTENDED", "1", 1);
    MMSetPref(MMUnattendedKey, nil);
    T(@"welcome: MINMACS_UNATTENDED=1 with no pref is unattended", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(MMUnattended()), YN(MMWindowWelcomeNow(NO) == nil)]);
    unsetenv("MINMACS_UNATTENDED");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
        if (!home.length || argc < 2) { fprintf(stderr, "usage: MINMACS_HOME=<test home> tool notice|paths|welcome|lid\n"); return 2; }
        unsetenv("MINMACS_UNATTENDED");
        NSString *mode = @(argv[1]);
        if ([mode isEqualToString:@"notice"]) Notice();
        else if ([mode isEqualToString:@"paths"]) Paths();
        else if ([mode isEqualToString:@"welcome"]) Welcome();
        else if ([mode isEqualToString:@"lid"]) Lid();
        else { fprintf(stderr, "unknown mode %s\n", argv[1]); return 2; }
        printf("END\n");
    }
    return 0;
}
