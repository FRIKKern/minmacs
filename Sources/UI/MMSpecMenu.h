// Draws an expert's menu and card specs from Core/MMExpert.h with the kit, to DESIGN.md (P56 to P58).
// The one spec converter: the app shell, the render tool and every expert's tests use these, so what the render
// checks is what the menu bar shows. A row's name may carry its tag after a tab, such as "checkout-flow\t:3000".
// It sends messages to the specs and never names their classes, so it links with Sources/UI alone.
// Main thread only, like the rest of the kit.
#import <Cocoa/Cocoa.h>
#import "MMMenuKit.h"
#import "MMCard.h"

@class MMMenuSpec, MMCardSpec, MMActionSpec;

/// The card spec for a row's finding, or nil when the row has no card.
typedef MMCardSpec *(^MMCardProvider)(NSString *findingID);
/// YES when a row's finding has a card, said without building it, so the menu can give the row its submenu arrow.
typedef BOOL (^MMCardCheck)(NSString *findingID);

/// An action spec as a menu item: dimmed with its reason when it cannot run, else one that calls its block.
NSMenuItem *MMItemFromAction(MMActionSpec *action);
/// The spec's Option alternate, or nil when it has none. It follows its action's item.
NSMenuItem *MMAlternateFromAction(MMActionSpec *action);

/// A card spec as a kit card.
MMCard *MMCardFromSpec(MMCardSpec *spec);

/// An expert's main menu: the header, the summary, an optional notice line, at most two actions, the sections
/// with a card under each row that has one, the More item and the footer. footerTarget gets hideIcon: and showSettings:.
NSMenu *MMMenuFromSpec(MMMenuSpec *spec, MMCardProvider cards, NSString *notice, id footerTarget);
/// The same menu, item for item, with each card built only when its row's submenu opens, on hover or from the
/// keyboard. has says which rows get a card, and cards runs on main when the submenu opens. Issue #53: the menu opens
/// without building a card, so its time no longer grows with the rows. The app's menus use this one.
NSMenu *MMMenuFromSpecOnHover(MMMenuSpec *spec, MMCardCheck has, MMCardProvider cards, NSString *notice, id footerTarget);
/// Builds every card this menu and its submenus still wait for, as hovering each row would. For the render tool,
/// the render checks and the tests, so they see the cards the person sees. MMRenderMenu and MMMenuProblems call it.
void MMLoadCards(NSMenu *menu);
/// YES when this submenu is a card that waits for its first hover.
BOOL MMCardWaits(NSMenu *submenu);
/// How many cards a hover has built in this process, for the checks that a menu opens with none built.
NSUInteger MMCardsBuiltOnHover(void);

/// One expert as the One Icon menu shows it, DESIGN.md menu bar rule 4.
@interface MMOneIconPart : NSObject
@property (copy) NSString *name;
@property (strong) MMMenuSpec *spec;
@property (copy) MMCardProvider cards;
/// Set by the app: the cards are then built on hover, as in MMMenuFromSpecOnHover. nil builds them with the menu.
@property (copy) MMCardCheck has;
@end

/// The rows each expert shows in the One Icon menu, so five experts still fit one screen.
extern const NSUInteger MMOneIconRows;
/// The One Icon menu: one flat section per visible expert, with its header line and top rows, then the footer.
/// Experts never nest as submenus, so a card is one level deep, as in each expert's own menu.
/// Past four experts, DESIGN.md rule 3, the rest go under More with their header lines and rows but no cards.
NSMenu *MMOneIconMenu(NSArray<MMOneIconPart *> *parts, NSString *notice, id footerTarget);
/// An expert's header as one line, "3.5 GB in servers · 7 localhosts · 2 quiet".
NSString *MMHeaderLine(MMMenuSpec *spec);
