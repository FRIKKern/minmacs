// The MMExpert protocol every expert implements, and the menu, card and verb specs it hands to UI and CLI.
// An expert is a lens on the graph. It never samples, scans or asks the model on its own.
// Core stays free of AppKit: an expert describes its menu as data, and the menu kit in Sources/UI draws it.
// Patterns P56 to P62 live in Sources/UI and Sources/CLI. This header holds the part of each that an expert sees:
// the status item of P56, the menu kit of P57, the card of P58, the verbs of P61 and the URL router of P62.
// The render tool of P59 draws menuFor: and cardFor: from fixture snapshots, and the formatters of P60
// for bytes, durations, plurals and tail cuts live in Sources/UI beside the kit.
#import <Foundation/Foundation.h>
#import "Core/Graph/MMGraph.h"
#import "Core/Review/MMReview.h"
#import "Core/Act/MMAct.h"

@class MMArgs;   // P61, defined in Sources/CLI

/// The state mark of a row or a card's status. Each mark draws a different shape, so state never rests on color alone.
/// The members follow MMMark in Sources/UI/MMMenuKit.h in the same order with the same values, so the kit casts it.
/// Core cannot import that header, because it imports Cocoa. The kit also picks each mark's color.
typedef NS_ENUM(NSInteger, MMRowMark) {
    MMRowMarkNone = 0,
    MMRowMarkWorking,      // in use now
    MMRowMarkRecent,       // used a short while ago
    MMRowMarkQuiet,        // quiet, nothing decided
    MMRowMarkGoes,         // goes at the next review or at a set time
    MMRowMarkBlocked,      // waits on the person
    MMRowMarkUnknown,      // not known yet
};

/// P57. One action in a menu or card. Leave out an action that never applies here.
/// An action that cannot run right now stays, with disabledReason as its gray tail.
@interface MMActionSpec : NSObject
@property (copy) NSString *title;                       // title case, ends in an ellipsis when it asks for more input
@property (copy) NSString *tail;                        // gray: a time, a size, or nil
@property (copy) NSString *disabledReason;              // nil when it can run
@property (copy) NSString *optionTitle;                 // the Option alternate, such as "Force Stop"; never the only way
@property (copy) void (^run)(BOOL option);              // main thread
+ (instancetype)title:(NSString *)title tail:(NSString *)tail run:(void (^)(BOOL option))run;
@end

/// P57. One row: a name and at most three facts, ordered owner, size, state.
@interface MMRowSpec : NSObject
@property (copy) NSString *name;
@property (copy) NSArray<NSString *> *facts;
@property MMRowMark mark;
@property (copy) NSString *findingID;                   // the card of P58 opens for this finding
@end

/// P57. One section: a title with no count, and its rows. The kit puts rows past six under More.
@interface MMSectionSpec : NSObject
@property (copy) NSString *title;
@property (copy) NSArray<MMRowSpec *> *rows;
@end

/// P56 and P57. One expert's main menu, as DESIGN.md sets it out.
/// The kit adds the footer: Hide Icon, Settings... and Quit MinMacs.
@interface MMMenuSpec : NSObject
@property (copy) NSString *headerBig, *headerUnit, *headerLine;   // "3", "servers", "1.2 GB, 2 idle"
@property (copy) NSString *summary;                     // at most three lines, cut at a whole sentence
@property (copy) NSArray<MMActionSpec *> *actions;      // at most two
@property (copy) NSArray<MMSectionSpec *> *sections;    // at most four
@property (copy) NSArray<MMActionSpec *> *more;         // under the More item, such as Recently Stopped
@end

/// P58. One fact on a card. A fact that belongs to another expert links to that expert's card.
@interface MMCardFact : NSObject
@property (copy) NSString *label, *value;
@property (copy) NSString *linkExpert, *linkFindingID;
+ (instancetype)label:(NSString *)label value:(NSString *)value;
@end

/// P58. A hover card. Starts from -cardFor: in WF main.m:633.
@interface MMCardSpec : NSObject
@property (copy) NSString *title;                       // one or two lines
@property (copy) NSString *statusWord, *statusText;     // "Stays", "Goes at 18:00", then why, in at most two lines
@property MMRowMark mark;                               // the mark beside the status word; the kit colors the word from it
@property (copy) NSArray<MMCardFact *> *facts;          // at most five; empty values are left out
@property (copy) NSString *noteBy;                      // who wrote the note, such as "Haiku says stale"
@property (copy) NSString *note;                        // the model's note, at most two lines, only when it adds something
@property (copy) NSArray<MMActionSpec *> *actions;      // at most four, the rest under More
@end

/// P61. One CLI verb. Every verb takes --json and --dry-run. A verb that changes things runs in the app,
/// through the core socket of P63. Starts from NN Register, cli.go:25.
@interface MMVerbSpec : NSObject
@property (copy) NSString *verb, *usage;                // "hosts", "hosts [port] [--json]"
@property BOOL mutates;
@property (copy) int (^run)(MMArgs *args);              // returns the exit status
+ (instancetype)verb:(NSString *)verb usage:(NSString *)usage mutates:(BOOL)mutates run:(int (^)(MMArgs *args))run;
@end

/// One pref of an expert's own pane in the Settings window: a switch, or a choice among numbers.
/// The pane draws it, and the change comes back to the expert through -setPref:value:.
@interface MMPrefSpec : NSObject
@property (copy) NSString *key;                         // the expert's word for it, such as "battery"
@property (copy) NSString *title;                       // the label beside the control, such as "Low battery"
@property (copy) NSString *switchTitle;                 // a switch's own title, such as "Pause When Hot"; nil for a choice
@property (copy) NSString *note;                        // one or two sentences under the control, or nil
@property (copy) NSArray<NSNumber *> *values;           // the choices, in order; nil for a switch
@property (copy) NSArray<NSString *> *valueTitles;      // what each choice shows, such as "20%" or "Never"
@property (strong) NSNumber *value;                     // the value now; a switch holds YES or NO
@property (copy) NSString *section;                     // the group title above it; a new title starts a group
+ (instancetype)toggle:(NSString *)key title:(NSString *)title switchTitle:(NSString *)switchTitle on:(BOOL)on;
+ (instancetype)choice:(NSString *)key title:(NSString *)title values:(NSArray<NSNumber *> *)values
                titles:(NSArray<NSString *> *)titles value:(NSNumber *)value;
@end

/// The protocol each of the five experts implements. One object per expert, made once at launch.
/// New code. It replaces each standalone app's main.m: LH, WF, MM 1.2, NN and IN.
@protocol MMExpert <NSObject>
/// "locohost": the prefs prefix, the queue label, the Store folder, the log's expert field,
/// and autosaveName minmacs.<expertID> for the status item of P56.
@property (readonly, copy) NSString *expertID;
@property (readonly, copy) NSString *name;              // "LocoHost"
@property (readonly, copy) NSString *symbol;            // a square template SF Symbol, "server.rack"
/// P41. The expert's own words for keep, go and unsure, decision 9.
@property (readonly) MMVerdictWords *words;

/// Findings. Runs on the graph queue on every rebuild. Reads facts only.
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts;
/// P49. The keep checks Act asks before every plan and every action.
- (id<MMExpertPolicy>)policy;
/// Actions. The action that carries out f's proposal, or nil when there is none.
/// step is MMStopKill for the Option alternate or a second request.
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step;

/// Review facts. What the review sends about f, redacted. docs/REVIEW.md lists each field.
- (NSDictionary *)reviewFactsFor:(MMFinding *)f;
/// P47. The rules that decide before the model. May be empty.
- (NSArray<id<MMRule>> *)rules;
/// The review request for a wake, built from the snapshot. nil when there is nothing to review.
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s;

/// Menu sections. P56 and P57. Main thread. The menu kit draws what this returns.
- (MMMenuSpec *)menuFor:(MMSnapshot *)s;
/// P58. The hover card of one finding. Main thread.
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s;
/// A number beside the icon, at most three characters, and only when it asks the person to act. nil otherwise.
- (NSString *)badgeFor:(MMSnapshot *)s;
/// The status item's accessibility state, such as "2 idle servers". UI adds the name.
- (NSString *)accessibilityStateFor:(MMSnapshot *)s;
/// YES when this Mac has nothing in the expert's field, so its icon starts hidden.
- (BOOL)fieldEmptyIn:(MMSnapshot *)s;

/// CLI verbs. P61.
- (NSArray<MMVerbSpec *> *)verbs;

@optional
/// P61 and P62. The standalone app's name, such as "locohost". It works as argv[0] for the binary
/// and as a URL scheme, so old scripts and links keep working. The URL router of P62 lives in Sources/CLI.
@property (readonly, copy) NSString *legacyName;
/// P62. Handles a URL of the legacy scheme. The router owns login and quit, so an expert never sees those.
- (BOOL)openURL:(NSURL *)url;
/// Its own prefs, for its pane in the Settings window. An expert without them, or with none, has no pane.
/// Main thread. It reads what the expert already holds, never disk.
- (NSArray<MMPrefSpec *> *)prefSpecs;
/// One change from that pane, on main. The expert makes it off main, through MMRunAction like any other change.
- (void)setPref:(NSString *)key value:(NSNumber *)value;
/// Issue #52. A digest of what findingsFrom: reads from facts, cheaper to make than the findings. When it matches the
/// last build's and only a new sample asked for this build, the graph reuses the last findings, for at most
/// 30 seconds. An action, an exit or a change in Know always builds anew.
- (uint64_t)inputDigestFrom:(MMFacts *)facts;
@end

/// Registers an expert with the graph, the broker and the CLI. Called once per expert at launch.
void MMRegisterExpert(id<MMExpert> expert);
/// The registered experts, in menu bar order.
NSArray<id<MMExpert>> *MMExperts(void);
id<MMExpert> MMExpertNamed(NSString *expertID);
