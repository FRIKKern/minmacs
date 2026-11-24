// What a side's list keeps, for the files it is written in: MMWindowList.m lays it out and draws it,
// MMWindowListProjects.m lays out a group with projects, and MMWindowListInput.m takes the pointer, the scrolling and
// VoiceOver. Only they import this.
#import "UI/Window/MMWindowParts.h"

// In a group with projects: a project's sub-header, and the line under it that says how many of its rows wait.
static const CGFloat MMListSub = 22, MMListMore = 20;

@interface MMWindowListView () {
    NSArray<MMWindowGroup *> *_groups;
    NSMutableDictionary<NSString *, NSNumber *> *_offsets;   // how far each group is scrolled, by its key
    NSMutableArray<NSValue *> *_frames;                       // each group's frame, header included
    NSMutableArray<NSArray<NSNumber *> *> *_tops;             // each group's rows as drawn: where each starts, and where the last ends
    // A group with projects draws its rows in an order of its own, each project's most active first, with the project's
    // sub-header above its first row and, where its rows wait below, a line under its last. A row's place in _tops
    // counts both, so a group still ends on a whole row. For any other group the order is the rows' own and both are 0.
    NSMutableArray<NSArray<NSNumber *> *> *_order;            // each group's rows as drawn: the index of each in the group's rows
    NSMutableArray<NSArray<NSNumber *> *> *_leads;            // the height of the sub-header above each drawn row, or 0
    NSMutableArray<NSArray *> *_trails;                       // the line under each drawn row, "3 more in barkbot", or NSNull
    NSMutableArray<NSArray<NSNumber *> *> *_steps;            // the heights each group's box may take, each on a whole row
    NSString *_scrolling;                                     // the group whose scroller shows
    NSMutableDictionary<NSString *, NSString *> *_anchors;    // the first row shown of each scrolled group, by the group's key
    NSTrackingArea *_tracking;
    CGFloat _rowHeight;                                       // 24: a row is one line, also on a side with room to spare
    CGFloat _sumTop;                                          // where the side's closing lines start, or below 0 for none
    NSSet<NSString *> *_known;                                // the rows of the model before this one, to tell a new row
    NSInteger _flashed;

}
/// Lays the groups out again: each group's height, its rows' tops and where each scrolled group rests.
- (void)place;
/// The group under a point, or -1.
- (NSInteger)groupAt:(NSPoint)p;
/// Where a group's rows show, under its header.
- (NSRect)boxOf:(NSInteger)i;
/// How far a group can scroll in a box of this height.
- (CGFloat)maxOffset:(NSInteger)i box:(CGFloat)boxHeight;
/// The drawn row under a point, or nil.
- (MMWindowRow *)rowAt:(NSPoint)p;
/// Where a row is drawn, scrolled by `off`. `r` counts the rows as drawn.
- (NSRect)rowRect:(NSInteger)r in:(NSInteger)i box:(NSRect)box offset:(CGFloat)off;
/// The rows of a group that show now. While the group moves under the fingers, rows cut by the box's edges show too.
- (NSRange)shown:(NSInteger)i moving:(BOOL)moving;
@end

/// A group's rows by project: for each project, in the group's order, the indexes of its rows. MMWindowListProjects.m.
NSArray<NSArray<NSNumber *> *> *MMWindowListProjectsOf(MMWindowGroup *g);

@interface MMWindowListView (Projects)
/// The row drawn `r`th in a group.
- (MMWindowRow *)drawn:(NSInteger)r in:(NSInteger)i;
/// A row's name as this list shows it: under a project's sub-header, the name in its project.
- (NSString *)nameOf:(MMWindowRow *)row in:(MMWindowGroup *)g;
/// How high a row of a group is: `row` points, and a line more for each line more its name wraps to.
- (CGFloat)heightOf:(MMWindowRow *)r in:(MMWindowGroup *)g hasHour:(BOOL)hasHour row:(CGFloat)row;
/// The ways a group with projects can show, smallest first, with the height of each in `heights`.
- (NSArray<NSData *> *)plansOf:(MMWindowGroup *)g projects:(NSArray<NSArray<NSNumber *> *> *)projects heights:(NSArray<NSNumber *> *)rowH out:(NSMutableArray<NSNumber *> *)heights;
/// Lays group `i` out as drawn, by `plan`, or in its rows' own order with no plan.
- (void)arrange:(NSInteger)i plan:(NSData *)plan projects:(NSArray<NSArray<NSNumber *> *> *)projects heights:(NSArray<NSNumber *> *)rowH;
/// Where a row is drawn in its group, counted as drawn, or -1.
- (NSInteger)drawnIndexOf:(NSString *)key in:(NSInteger)i;
/// A project's sub-header, its top at `top`.
- (void)drawProjectOf:(MMWindowRow *)row in:(MMWindowGroup *)g top:(CGFloat)top;
@end

@interface MMWindowListView (Input)
/// The scroll came to rest: each group settles on a whole row. MMWindowListInput.m.
- (void)hideScroller;
@end
