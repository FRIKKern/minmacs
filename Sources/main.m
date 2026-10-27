// MinMacs 2.0, phase 0. One binary: the menu bar app, or the CLI when a verb is given.
// The app shows one status item with a menu that names the phase and quits.
// Each expert gets its own status item in phase 1, with autosaveName minmacs.<expert>.
#import <Cocoa/Cocoa.h>
#import "CLI/MMCLI.h"

@interface MMAppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *item;
@end

@implementation MMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.item.autosaveName = @"minmacs.minmacs";
    self.item.behavior = NSStatusItemBehaviorRemovalAllowed;

    // A square template symbol and no text, as DESIGN.md asks.
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"gauge.with.dots.needle.33percent"
                              accessibilityDescription:@"MinMacs"];
    icon.template = YES;
    self.item.button.image = icon;
    self.item.button.accessibilityLabel = @"MinMacs";

    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:[NSString stringWithFormat:@"MinMacs 2.0 (%@)", MMPhase] action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit MinMacs" action:@selector(terminate:) keyEquivalent:@"q"];
    self.item.menu = menu;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (MMWantsCLI(argc, argv)) return MMRunCLI(argc, argv);
        NSApplication *app = NSApplication.sharedApplication;
        MMAppDelegate *delegate = [MMAppDelegate new];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        [app run];
    }
    return 0;
}
