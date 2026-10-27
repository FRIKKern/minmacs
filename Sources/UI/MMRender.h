// Draws a finished menu to PNG and checks it against DESIGN.md, for the render tool and for each expert's tests (P59).
// The render tool in tools/render.m uses these with fixture subjects. Nothing here opens a menu or makes a status item.
// Main thread only, like the rest of the kit.
#import <Cocoa/Cocoa.h>

/// The four appearances the render check covers, by the name each PNG carries:
/// light, dark, contrast-light and contrast-dark. An appearance this Mac cannot load is left out.
/// +appearanceNamed: gives plain Aqua for the Increase Contrast names, so those load from the system's
/// own appearance bundle, the files System Settings uses when Increase Contrast is on.
NSDictionary<NSString *, NSAppearance *> *MMRenderAppearances(void);

/// Lays out the menu's items top to bottom as a menu draws them and writes a PNG of the kit's width at
/// two pixels per point. Custom views keep their own size. Separators, section titles and plain items are
/// drawn by hand, so plain items are close to macOS and not exact. Option alternates are hidden, as with no key held.
/// Returns the titles of items whose text does not fit, so an empty array means nothing is cut off.
/// Returns nil when the PNG could not be written.
NSArray<NSString *> *MMRenderMenu(NSMenu *menu, NSString *path, NSAppearance *appearance);

/// Writes any view to a PNG on the window background of this appearance. For views that are not a menu,
/// such as a strip of status icons. Returns NO when the PNG could not be written.
BOOL MMRenderView(NSView *view, NSString *path, NSAppearance *appearance);

/// Where a main menu breaks DESIGN.md, empty when it follows it. It checks that no item carries a symbol,
/// that no line holds parentheses, at most two actions, at most four sections of at most six rows,
/// the footer of Hide Icon, Settings… and Quit MinMacs, and that no line says the same thing twice.
NSArray<NSString *> *MMMenuProblems(NSMenu *menu);
