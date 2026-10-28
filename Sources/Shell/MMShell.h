// The app shell, pattern P56: one binary, one app, one status item per registered expert.
// main.m registers the experts, then calls MMMain. With a verb in argv it runs the CLI and exits.
// Without one it runs the menu bar app: MMCoreStart, core.sock, the status items, Settings, the URL router
// and the login item on first launch. Once after the import, the migration's follow-up of MMMigrate.h.
#import <Cocoa/Cocoa.h>

@protocol MMExpert;
@class MMSnapshot;

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

/// DESIGN.md menu bar rule 4: the One Icon menu holds one section per visible expert. An expert with an empty
/// field, or one the person hid in Settings, stays out. MinMacs's own section follows the one icon itself.
BOOL MMOneIconShows(NSString *expertID, BOOL fieldEmpty, BOOL iconVisible);

/// The One Icon item's saved position and Visible state, DESIGN.md menu bar rule 2. It is its own, so hiding the
/// one icon never hides MinMacs's own item, minmacs.minmacs, when the person goes back to five icons.
extern NSString *const MMOneIconAutosaveName;

/// The line the menu shows for a day after first launch, decision 18.
extern NSString *const MMLoginNotice;

/// The menu an expert's own icon opens, built as the app builds it when the menu opens: menuFor: on the snapshot,
/// which reads what the graph queue prepared, then the kit, with each row's card built on hover. Main thread.
/// footerTarget gets hideIcon: and showSettings:.
NSMenu *MMShellMenu(id<MMExpert> expert, MMSnapshot *s, NSString *notice, id footerTarget);
/// The One Icon menu: a section for each expert MMOneIconShows lets in, cards built on hover. Main thread.
NSMenu *MMShellOneIconMenu(MMSnapshot *s, NSString *notice, id footerTarget);

#pragma mark Startup, issue #55

/// Marks the start of MMMain. MMMain calls it first. The bench calls it where MMMain would run.
void MMStartupBegin(void);
/// Times in ms since MMStartupBegin, main thread: "items" when every status item that starts visible is made,
/// "snapshot" at the first snapshot on main, "summaries" once every expert has its first summary line, and
/// "summary.<expert>" for each. "made" and "deferred" list the experts whose items were made at launch and those
/// left for later. An expert whose icon was hidden at the last run, such as one whose field is empty on this Mac,
/// gets its status item, menu and per-snapshot updates only once its field appears or Settings shows it.
NSDictionary *MMStartupTimes(void);
/// The app's launch without the status bar and without NSApp's run loop, for the bench: Core, core.sock, then each
/// item as the app makes it, with the icon image and label made but no NSStatusItem. Returns the shell, which the
/// caller keeps. Main thread. The caller turns the run loop.
id MMShellStartHeadless(void);
/// Stops what MMShellStartHeadless started.
void MMShellStopHeadless(id shell);
/// The menu a cross-link opens, from the snapshot. With five icons it is the linked expert's own menu, with the
/// linked finding's card as the first row below the header, TESTS.md question 5. In One Icon mode it is the one menu,
/// with the linked expert's part first and the card first in it. nil when no such expert is registered.
/// Every link row of every card opens through this, so no expert wires its own jump. Main thread.
NSMenu *MMLinkMenu(NSString *expertID, NSString *findingID, MMSnapshot *s, BOOL oneIcon, id footerTarget);

/// The app delegate. One per process, made by MMMain.
@interface MMShell : NSObject <NSApplicationDelegate>
@end
