// Draws an expert's MMMenuSpec and MMCardSpec with the menu kit. Core describes a menu as data in MMExpert.h,
// and this turns that data into the kit's native items, so every expert's menu is built the same way.
// A row's name may carry its tag after a tab, such as "checkout-flow\t:3000". The tag is never cut.
// Main thread only, like the rest of the kit.
#import <Cocoa/Cocoa.h>
#import "Core/MMExpert.h"
#import "UI/MMCard.h"

/// The kit's card for a card spec: title, status, at most five facts, the note and the actions.
MMCard *MMCardForSpec(MMCardSpec *spec);

/// The kit's main menu for a menu spec: header, summary, actions, sections, More and the footer.
/// card gives the card of a row's finding, or nil for a row with no card. footerTarget gets hideIcon: and showSettings:.
NSMenu *MMMenuForSpec(MMMenuSpec *spec, MMCardSpec *(^card)(NSString *findingID), id footerTarget);

/// One menu item for an action spec. A spec with a disabledReason is dimmed in place with the reason as its tail.
NSMenuItem *MMItemForAction(MMActionSpec *spec);
