// The hover card at the top of a row's submenu, to DESIGN.md rule 5 (A11, P58).
// It started as WorkForest's -cardFor:, with LocoHost's facts, and one label column for every expert.
#import <Cocoa/Cocoa.h>
#import "MMMenuKit.h"

@interface MMCard : NSObject
/// One or two lines, in sentence case.
@property (copy) NSString *title;
/// The word the status starts with, such as "Stays." or "Goes at 18:00.".
@property (copy) NSString *statusWord;
/// Why the item stays or when it goes, and what happens next. Cut at a whole sentence to two lines.
@property (copy) NSString *statusText;
/// The state mark beside the status word.
@property MMMark mark;
/// The color of the status word. nil takes the mark's color: green in use, yellow used recently,
/// orange when it goes, red when it waits on the person, gray otherwise.
@property (strong) NSColor *statusColor;
/// Who wrote the note, such as "Haiku says stale". Shown before the note.
@property (copy) NSString *noteBy;
/// The model's note. Shown in at most two lines, and only when it adds to the status.
@property (copy) NSString *note;

/// A fact as label and value. An empty value is left out, and at most five facts show.
- (void)fact:(NSString *)label value:(NSString *)value;
/// A fact that belongs to another expert, such as "Worktree   speed-3-base, merged". It counts as one of the five.
/// The value shows in link color, and `links` names where it points.
- (void)link:(NSString *)label value:(NSString *)value expert:(NSString *)expert key:(NSString *)key;
/// Each link as @{label, expert, key}, for the expert that wires the jump.
@property (readonly) NSArray<NSDictionary *> *links;
/// An action under the card. The first four show, and the rest go under More.
/// An Option alternate follows its action and does not count.
- (void)action:(NSMenuItem *)item;
/// An item that always goes under More.
- (void)more:(NSMenuItem *)item;

/// Does the note add to the status? NO when it is empty or the status already says it.
- (BOOL)noteAddsSomething;
/// The card as a menu item with a view.
- (NSMenuItem *)cardItem;
/// The card, a separator, at most four actions and More.
- (NSMenu *)menu;
/// Where the card breaks DESIGN.md, for the render check. Empty when it follows it.
- (NSArray<NSString *> *)layoutProblems;
@end
