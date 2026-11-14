// What MMWindowView keeps, for the files it is written in: MMWindowView.m, and MMWindowRun.m for the run's motion.
// Only they import this.
#import "UI/Window/MMWindowParts.h"

@interface MMWindowView () {
    MMWindowFlipped *_main;
    MMWindowListView *_left, *_right;
    MMWindowMiddleView *_middle;
    MMWindowDockView *_dock;
    NSBox *_rule;
    MMWindowSettingsView *_settings;
    MMWindowButton *_gear, *_power;
    NSString *_hovered;                 // the row under the pointer
    NSTimer *_timer;                    // runs only while something moves and the window shows
    NSDate *_stepped, *_endSeen;        // the last step, and when this view first saw the run ended
    NSString *_stepWords;               // the step the button shows, and when it came
    NSDate *_stepCame;
    BOOL _letGo;                        // the end was shown long enough
    double _memoryShare, _diskShare, _memoryShown, _diskShown;
    MMWindowWelcomeView *_welcome;      // made the first time a model holds a welcome
    BOOL _started;                      // Start was pressed here: a model built before that brings no welcome back
    BOOL _looking;                      // no model came for a moment, so the window says it is taking its first look
    BOOL _quiet;                        // from Start until the menu has arrived and a moment more: only Quit takes a press
    NSInteger _startRun;                // counts Starts and closes, so a fade that outlived its window changes nothing
    NSInteger _flips;                   // fades between the menu and Settings under way
}
@end

@interface MMWindowView (Run)
/// Takes the run's numbers as the place the lines and the gains move toward. MMWindowRun.m.
- (void)followRun:(BOOL)hadRun;
/// The timer runs only while the window shows and something moves or the end still shows.
- (void)wake;
- (void)runTick:(NSDate *)now;
@end
