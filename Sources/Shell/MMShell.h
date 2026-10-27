// The app shell, pattern P56: one binary, one app, one status item per registered expert.
// main.m registers the experts, then calls MMMain. With a verb in argv it runs the CLI and exits.
// Without one it runs the menu bar app: MMCoreStart, core.sock, the status items, Settings, the URL router
// and the login item on first launch.
#import <Cocoa/Cocoa.h>

/// The class names of the five experts, in menu bar order. main.m registers each one that is linked in, so an
/// expert lands by adding its class under Sources/Experts and nothing else. Each class implements MMExpert.
NSArray<NSString *> *MMBuiltInExpertClasses(void);
/// Registers every class in MMBuiltInExpertClasses that exists in this binary. Returns how many it registered.
NSUInteger MMRegisterBuiltInExperts(void);

/// The menu bar app or the CLI, from argv. Call after the experts are registered.
int MMMain(int argc, const char *argv[]);

/// Decision 18: register the login item on first launch, but only in the real app. NO under tests, which always
/// set MINMACS_HOME, and NO for a binary that does not run from an .app bundle.
BOOL MMMayRegisterLoginItem(NSDictionary<NSString *, NSString *> *env, NSString *bundlePath);

/// DESIGN.md "First launch": an expert whose field is empty starts with its icon hidden, and shows it once,
/// when the field appears. seen says the field appeared before. Returns the visible state to set, or nil to leave
/// the person's own choice alone.
NSNumber *MMIconVisibleFor(BOOL fieldEmpty, BOOL seen, BOOL firstLaunch);

/// The line the menu shows for a day after first launch, decision 18.
extern NSString *const MMLoginNotice;

/// The app delegate. One per process, made by MMMain.
@interface MMShell : NSObject <NSApplicationDelegate>
@end
