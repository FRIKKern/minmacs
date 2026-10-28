// The one Settings window of PLAN.md section 7 and DESIGN.md, opened by "Settings…" with Command-Comma
// and by opening MinMacs again. It replaces the nested Settings submenus of LocoHost and MinMacs 1.2.
// Overview first, as DESIGN.md rule 3 of the menu bar asks, then Experts, then one pane for each expert that has
// prefs of its own, then General. An expert's pane draws the MMPrefSpec values of Core/MMExpert.h.
// The view holds no state of its own. The app fills it from Core Store and gets each change back through a block,
// so tools/render.sh can draw it from fixtures with Sources/UI and the plain specs of Core/MMSpecs.m. Main thread only.
#import <Cocoa/Cocoa.h>

@class MMPrefSpec;

typedef NS_ENUM(NSInteger, MMSettingsPane) { MMSettingsOverview = 0, MMSettingsExperts, MMSettingsGeneral };

/// What Settings shows for one expert.
@interface MMSettingsExpert : NSObject
@property (copy) NSString *expert;                      // the id, such as "locohost"
@property (copy) NSString *name, *symbol;               // "LocoHost", "server.rack"
@property (copy) NSString *headline;                    // the menu's header line, such as "7 localhosts · 2 quiet"
@property (copy) NSString *summary;                     // one sentence from the menu's summary, or nil
@property BOOL iconVisible;                             // the NSStatusItem Visible state of minmacs.<expert>
@property (copy) NSString *mode;                        // idle, proactive or eager. nil when the expert has no mode
@property (copy) NSArray<MMPrefSpec *> *prefs;          // its own prefs. Empty or nil: it has no pane of its own
+ (instancetype)expert:(NSString *)expert name:(NSString *)name symbol:(NSString *)symbol;
@end

/// The model choices, in the order the menu shows them. The first is the default.
NSArray<NSString *> *MMSettingsModels(void);            // auto, haiku, sonnet, opus, luna
NSString *MMSettingsModelTitle(NSString *model);        // "Auto: Haiku, Then Luna", "Haiku", ...
NSArray<NSString *> *MMSettingsModes(void);             // idle, proactive, eager
NSString *MMSettingsPaneTitle(MMSettingsPane pane);     // "Overview", "Experts", "General"

@interface MMSettings : NSObject
@property (copy) NSArray<MMSettingsExpert *> *experts;
@property (copy) NSString *model;
@property BOOL oneIcon, openAtLogin;

/// Each change the person makes. A nil block leaves that control dimmed.
@property (copy) void (^onIcon)(NSString *expert, BOOL visible);
@property (copy) void (^onMode)(NSString *expert, NSString *mode);
@property (copy) void (^onModel)(NSString *model);
@property (copy) void (^onOneIcon)(BOOL on);
@property (copy) void (^onOpenAtLogin)(BOOL on);
@property (copy) void (^onOpenMenu)(NSString *expert, NSView *from);
/// A change in an expert's own pane: the spec's key and the new value, YES or NO for a switch.
@property (copy) void (^onPref)(NSString *expert, NSString *key, NSNumber *value);

/// One pane, laid out at the window's width. The render tool draws these.
- (NSView *)viewFor:(MMSettingsPane)pane;
/// An expert's own pane, or nil when it has no prefs.
- (NSView *)viewForExpert:(NSString *)expert;
/// The toolbar's panes in order: Overview, Experts, each expert with prefs by name, General.
- (NSArray<NSString *> *)paneTitles;
/// Opens the window on a pane, or brings it forward. Call -reload after a change from outside.
- (void)show:(MMSettingsPane)pane;
- (void)reload;
/// Opens the window on an expert's own pane, or on Experts when it has none.
- (void)showExpert:(NSString *)expert;
@property (readonly) NSWindow *window;
@property (readonly) MMSettingsPane pane;
@property (readonly, copy) NSString *expertPane;       // the expert whose pane shows, nil on the other panes
@end

/// The window's content width in points.
extern const CGFloat MMSettingsWidth;
