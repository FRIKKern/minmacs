// The one confirm, MMConfirm.h. The only NSAlert in MinMacs: it guards a press a person made, while that person is
// plainly there, and is never shown for anything else.
#import <stdatomic.h>
#import "UI/MMConfirm.h"

#ifdef MM_TESTS
static atomic_uint gCalls;
NSUInteger MMAskPersonCalls(void) { return atomic_load(&gCalls); }
#endif

BOOL MMAskPerson(NSString *title, NSString *text, NSString *yes, NSView *accessory) {
#ifdef MM_TESTS
    atomic_fetch_add(&gCalls, 1);
#endif
    if (!NSThread.isMainThread || !NSApp) return NO;
    NSAlert *a = [NSAlert new];
    a.messageText = title ?: @"";
    a.informativeText = text ?: @"";
    [a addButtonWithTitle:yes ?: @"OK"]; [a addButtonWithTitle:@"Cancel"];
    if (accessory) { a.accessoryView = accessory; a.window.initialFirstResponder = accessory; }
    [NSApp activateIgnoringOtherApps:YES];
    return [a runModal] == NSAlertFirstButtonReturn;
}
