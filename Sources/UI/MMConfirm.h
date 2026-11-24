// The one confirm in the app, D3. MinMacs never waits for a person, so this is shown only for a press a person
// plainly made in the window or a menu: the caller asks MMPersonPresses in Core/Act/MMNotice.h at the press, and
// never calls this for anything started on its own, from a URL, from the CLI or while the Mac runs unattended.
// A failure is never an alert: it goes to MMNotice. test/unattended.sh fails when NSAlert or runModal appears in any
// other file. AppKit, main thread. Plain values only, so the render tool links it alone.
#import <Cocoa/Cocoa.h>

/// A confirm with yes and Cancel, and an optional view under the text, such as a field for a question.
/// YES when the person chose yes.
BOOL MMAskPerson(NSString *title, NSString *text, NSString *yes, NSView *accessory);

#ifdef MM_TESTS
/// How many times MMAskPerson was called in this process, shown or not. test/unattended.sh holds it to zero for
/// every path that starts with nobody there.
NSUInteger MMAskPersonCalls(void);
#endif
