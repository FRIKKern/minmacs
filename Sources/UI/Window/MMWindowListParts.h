// What a side's list keeps, for the files it is written in: MMWindowList.m lays it out and draws it, and
// MMWindowListInput.m takes the pointer, the scrolling and VoiceOver. Only they import this.
#import "UI/Window/MMWindowParts.h"

@interface MMWindowListView () {
    NSArray<MMWindowGroup *> *_groups;
    NSMutableDictionary<NSString *, NSNumber *> *_offsets;   // how far each group is scrolled, by its key
    NSMutableArray<NSValue *> *_frames;                       // each group's frame, header included
    NSMutableArray<NSArray<NSNumber *> *> *_tops;             // each group's rows: where each starts, and where the last ends
    NSString *_scrolling;                                     // the group whose scroller shows
    NSMutableDictionary<NSString *, NSString *> *_anchors;    // the first row shown of each scrolled group, by the group's key
    NSTrackingArea *_tracking;
    CGFloat _rowHeight;                                       // 24, or more on a side with room to spare
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
/// Where a row is drawn, scrolled by `off`.
- (NSRect)rowRect:(NSInteger)r in:(NSInteger)i box:(NSRect)box offset:(CGFloat)off;
@end

@interface MMWindowListView (Input)
/// The scroll came to rest: each group settles on a whole row. MMWindowListInput.m.
- (void)hideScroller;
@end
