// The day of prototype 54-a as an MMSheet, for the render tool, the bench and the view checks.
// Every name is a fixture. Times are set from now, so a render at any hour shows the same picture.
#import "Core/MMSheet.h"

NS_ASSUME_NONNULL_BEGIN

/// now is the "16:42" of the prototype. The day starts at 9:00 on now's date.
MMSheet *MMSheetFixture(NSDate *now);
/// The same day with nothing in it: no agents, no leftovers. The views draw their empty states from it.
MMSheet *MMSheetFixtureEmpty(NSDate *now);

NS_ASSUME_NONNULL_END
