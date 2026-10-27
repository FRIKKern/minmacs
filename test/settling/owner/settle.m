// MMSettle.app: the settling tests that need the owner at the screen. One ad-hoc signed bundle,
// one mode per question. Every mode writes what it sees to a log, so the result is in text.
// Run a mode with: open -n MMSettle.app --args <mode>       (see README.md for each one)
// The log goes to /tmp/mm-settle/<mode>.log, or MM_SETTLE_LOG if set.
//
// Modes:
//   notify          asks for notification permission, posts one notification with an Undo action
//   login-status    prints SMAppService status for the app and its agent; changes nothing
//   login-on        registers the app as a login item with SMAppService.mainAppService
//   login-off       unregisters it again
//   agent-on        registers the bundled LaunchAgent with agentServiceWithPlistName:
//   agent-off       unregisters it again
//   agent-run       what the LaunchAgent runs: writes one line and exits
//   icons           five status items, as MinMacs 2.0 will have; logs each one's visibility every second
//   crosslink       two status items; opens the second one's menu at row 3, from the first
//   fsevents        watches ~/Documents with FSEvents for 60 seconds and logs the event count
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <UserNotifications/UserNotifications.h>
#import <CoreServices/CoreServices.h>

static FILE *logf_;
static NSString *mode;

static void Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSISO8601DateFormatter stringFromDate:NSDate.date timeZone:NSTimeZone.localTimeZone formatOptions:NSISO8601DateFormatWithInternetDateTime], s];
    fputs(line.UTF8String, logf_); fflush(logf_);
    fputs(line.UTF8String, stderr);
}

static NSString *StatusName(SMAppServiceStatus s) {
    switch (s) {
        case SMAppServiceStatusNotRegistered: return @"notRegistered";
        case SMAppServiceStatusEnabled: return @"enabled";
        case SMAppServiceStatusRequiresApproval: return @"requiresApproval";
        case SMAppServiceStatusNotFound: return @"notFound";
    }
    return [NSString stringWithFormat:@"%ld", (long)s];
}

static NSString *const kAgent = @"no.guerrilla.minmacs.settle.agent.plist";

@interface MMSettleProbe : NSObject <NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate>
@property NSMutableArray<NSStatusItem *> *items;
@property NSMenu *target;
@end

@implementation MMSettleProbe

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    Log(@"mode %@, pid %d, bundle %@, macOS %@", mode, getpid(), NSBundle.mainBundle.bundlePath,
        NSProcessInfo.processInfo.operatingSystemVersionString);
    SEL s = NSSelectorFromString([[mode stringByReplacingOccurrencesOfString:@"-" withString:@"_"] stringByAppendingString:@"Mode"]);
    if (![self respondsToSelector:s]) { Log(@"unknown mode"); [NSApp terminate:nil]; return; }
    ((void (*)(id, SEL))[self methodForSelector:s])(self, s);
}

- (void)quitAfter:(NSTimeInterval)t {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Log(@"done"); [NSApp terminate:nil]; });
}

#pragma mark - Notifications

- (void)notifyMode {
    UNUserNotificationCenter *c = UNUserNotificationCenter.currentNotificationCenter;
    c.delegate = self;
    UNNotificationAction *undo = [UNNotificationAction actionWithIdentifier:@"undo" title:@"Undo" options:0];
    [c setNotificationCategories:[NSSet setWithObject:[UNNotificationCategory categoryWithIdentifier:@"acted" actions:@[undo] intentIdentifiers:@[] options:0]]];
    [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) {
        Log(@"before asking: authorizationStatus %ld (0 notDetermined, 1 denied, 2 authorized, 3 provisional)", (long)s.authorizationStatus);
        [c requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *e) {
            Log(@"requestAuthorization granted %d error %@", granted, e);
            [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s2) {
                Log(@"after asking: authorizationStatus %ld alertSetting %ld", (long)s2.authorizationStatus, (long)s2.alertSetting);
                UNMutableNotificationContent *m = [UNMutableNotificationContent new];
                m.title = @"Stopped 2 Servers"; m.body = @"MinMacs settling test. Click Undo to log the action.";
                m.categoryIdentifier = @"acted"; m.interruptionLevel = UNNotificationInterruptionLevelPassive;
                [c addNotificationRequest:[UNNotificationRequest requestWithIdentifier:@"settle" content:m trigger:nil]
                    withCompletionHandler:^(NSError *e2) { Log(@"addNotificationRequest error %@", e2); }];
            }];
        }];
    }];
    [self quitAfter:90];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)c willPresentNotification:(UNNotification *)n withCompletionHandler:(void (^)(UNNotificationPresentationOptions))h {
    Log(@"willPresent %@", n.request.identifier);
    h(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)c didReceiveNotificationResponse:(UNNotificationResponse *)r withCompletionHandler:(void (^)(void))h {
    Log(@"response action %@", r.actionIdentifier);
    h();
}

#pragma mark - Login item and agent

- (void)login_statusMode {
    Log(@"mainAppService %@", StatusName(SMAppService.mainAppService.status));
    Log(@"agent %@", StatusName([SMAppService agentServiceWithPlistName:kAgent].status));
    [NSApp terminate:nil];
}
- (void)change:(SMAppService *)s on:(BOOL)on label:(NSString *)label {
    NSError *e = nil;
    BOOL ok = on ? [s registerAndReturnError:&e] : [s unregisterAndReturnError:&e];
    Log(@"%@ %@: ok %d error %@ status now %@", label, on ? @"register" : @"unregister", ok, e, StatusName(s.status));
    [NSApp terminate:nil];
}
- (void)login_onMode { [self change:SMAppService.mainAppService on:YES label:@"mainAppService"]; }
- (void)login_offMode { [self change:SMAppService.mainAppService on:NO label:@"mainAppService"]; }
- (void)agent_onMode { [self change:[SMAppService agentServiceWithPlistName:kAgent] on:YES label:@"agent"]; }
- (void)agent_offMode { [self change:[SMAppService agentServiceWithPlistName:kAgent] on:NO label:@"agent"]; }
- (void)agent_runMode { Log(@"the LaunchAgent ran"); [NSApp terminate:nil]; }

#pragma mark - Five icons

- (NSStatusItem *)item:(NSString *)name symbol:(NSString *)symbol {
    NSStatusItem *i = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    i.autosaveName = [@"minmacs.settle." stringByAppendingString:name];
    i.behavior = NSStatusItemBehaviorRemovalAllowed;
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:name];
    img.template = YES;
    i.button.image = img;
    NSMenu *m = [NSMenu new];
    for (int r = 1; r <= 5; r++) [m addItemWithTitle:[NSString stringWithFormat:@"%@ row %d", name, r] action:nil keyEquivalent:@""];
    [m addItem:NSMenuItem.separatorItem];
    [m addItemWithTitle:@"Quit Probe" action:@selector(terminate:) keyEquivalent:@""];
    m.delegate = self;
    i.menu = m;
    [self.items addObject:i];
    return i;
}

- (void)iconsMode {
    self.items = [NSMutableArray new];
    NSArray *names = @[@"minmacs", @"locohost", @"workforest", @"noonoo", @"insomnia"];
    NSArray *syms = @[@"gauge.with.dots.needle.33percent", @"network", @"tree", @"trash", @"moon.zzz"];
    for (NSUInteger k = 0; k < names.count; k++) [self item:names[k] symbol:syms[k]];
    // isVisible says what the app asked for. The button's window says whether the system shows it:
    // a window that is not on screen, or has no frame, is an icon the system hid.
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t __unused) {
        NSMutableArray *parts = [NSMutableArray new];
        for (NSStatusItem *i in self.items) {
            NSWindow *w = i.button.window;
            [parts addObject:[NSString stringWithFormat:@"%@ visible=%d onscreen=%d occluded=%d x=%.0f",
                              [i.autosaveName substringFromIndex:15], i.isVisible, w.isVisible,
                              !(w.occlusionState & NSWindowOcclusionStateVisible), w.frame.origin.x]];
        }
        Log(@"%@", [parts componentsJoinedByString:@" | "]);
    }];
    [self quitAfter:300];
}

#pragma mark - Cross-links

- (void)crosslinkMode {
    self.items = [NSMutableArray new];
    [self item:@"a" symbol:@"a.square"];
    NSStatusItem *b = [self item:@"b" symbol:@"b.square"];
    self.target = b.menu;
    // Way 1: pop the menu up under B's button with row 3 placed at the button. No item is highlighted
    // by AppKit, so the log shows whether the menu opened and where.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Log(@"way 1: popUpMenuPositioningItem row 3 from B's button");
        [self closeLater];
        NSMenuItem *row = self.target.itemArray[2];
        [self.target popUpMenuPositioningItem:row atLocation:NSMakePoint(0, 0) inView:b.button];
        Log(@"way 1 closed");
        // Way 2: click B's button in code, then post two Down Arrow key events into this app's own
        // queue while the menu tracks. No Accessibility right is needed for events the app posts to itself.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            Log(@"way 2: performClick on B, then three Down Arrow events");
            [self closeLater];
            [self performSelector:@selector(arrows) withObject:nil afterDelay:0.4 inModes:@[NSEventTrackingRunLoopMode, NSDefaultRunLoopMode]];
            [b.button performClick:nil];
            Log(@"way 2 closed");
            [self quitAfter:2];
        });
    });
}

- (void)arrows {
    for (int k = 0; k < 3; k++) {
        unichar down = NSDownArrowFunctionKey;
        NSString *c = [NSString stringWithCharacters:&down length:1];
        NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagFunction | NSEventModifierFlagNumericPad
                                      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:0 context:nil characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:125];
        [NSApp postEvent:e atStart:NO];
    }
}

- (void)closeLater {
    NSMenu *m = self.target;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [m cancelTracking]; });
    [self performSelector:@selector(cancel:) withObject:m afterDelay:3 inModes:@[NSEventTrackingRunLoopMode]];
}
- (void)cancel:(NSMenu *)m { [m cancelTracking]; }

- (void)menuWillOpen:(NSMenu *)m { Log(@"menuWillOpen %@", m.itemArray.firstObject.title); }
- (void)menuDidClose:(NSMenu *)m { Log(@"menuDidClose %@", m.itemArray.firstObject.title); }
- (void)menu:(NSMenu *)m willHighlightItem:(NSMenuItem *)i { Log(@"willHighlightItem %@", i.title ?: @"none"); }

#pragma mark - FSEvents

static void FSCallback(ConstFSEventStreamRef s __unused, void *info __unused, size_t n, void *paths,
                       const FSEventStreamEventFlags flags[] __unused, const FSEventStreamEventId ids[] __unused) {
    static size_t total;
    total += n;
    Log(@"%zu events, %zu so far, first %s", n, total, n ? ((char **)paths)[0] : "");
}

- (void)fseventsMode {
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    FSEventStreamRef s = FSEventStreamCreate(NULL, FSCallback, NULL, (__bridge CFArrayRef)@[docs], kFSEventStreamEventIdSinceNow, 1.0,
                                             kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
    FSEventStreamSetDispatchQueue(s, dispatch_get_main_queue());
    Log(@"FSEventStreamStart %d on %@. Touch a file in ~/Documents now if nothing changes there by itself.", FSEventStreamStart(s), docs);
    [self quitAfter:60];
}

@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        mode = argc > 1 ? @(argv[1]) : @"login-status";
        NSString *dir = NSProcessInfo.processInfo.environment[@"MM_SETTLE_LOG"] ?: @"/tmp/mm-settle";
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        logf_ = fopen([dir stringByAppendingPathComponent:[mode stringByAppendingString:@".log"]].fileSystemRepresentation, "a");
        if (!logf_) logf_ = stderr;
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        static MMSettleProbe *p; p = [MMSettleProbe new];
        app.delegate = p;
        [app run];
    }
    return 0;
}
