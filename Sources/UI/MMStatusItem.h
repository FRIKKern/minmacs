// Status item helpers, to DESIGN.md "The menu bar". Each expert gets one square template symbol,
// a saved position under minmacs.<expert>, and an accessibility label that names the expert and its state.
#import <Cocoa/Cocoa.h>

/// The point size of every expert's icon.
extern const CGFloat MMStatusSymbolSize;

/// "minmacs.locohost", "minmacs.noonoo": the expert's name in lower case, letters and digits only.
NSString *MMStatusAutosaveName(NSString *expert);
/// "LocoHost, 2 idle servers", or the expert's name alone when the state is empty. Never a symbol name.
NSString *MMStatusLabel(NSString *expert, NSString *state);
/// The expert's symbol as a template image at the one point size, described by `label`. nil for an unknown symbol.
NSImage *MMStatusImage(NSString *symbol, NSString *label);
/// A number that asks the person to act, at most three characters of digits and "+".
/// nil when there is none, when it is longer, or when it holds words.
NSString *MMStatusBadge(NSString *badge);

/// A new status item for an expert: square, removal allowed, its position saved under MMStatusAutosaveName.
/// Call on the main thread.
NSStatusItem *MMMakeStatusItem(NSString *expert, NSString *symbol);
/// The same under another saved name, such as the One Icon item's. The name is set before anything else, so the item
/// never loads the visible state saved under the expert's own name.
NSStatusItem *MMMakeStatusItemSaved(NSString *expert, NSString *symbol, NSString *autosaveName);
/// Sets the icon, the badge beside it and the accessibility label. The item stays square without a badge.
void MMUpdateStatusItem(NSStatusItem *item, NSString *expert, NSString *symbol, NSString *state, NSString *badge);
