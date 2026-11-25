// The window controller's part of an app row's insides, Shell/MMWindowInsides.h.
#import "Shell/MMWindowController.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMWindowInsides.h"

NS_ASSUME_NONNULL_BEGIN

/// The controller's part, on its queue: it asks the app only while the window is open and the app row's insides
/// show, as its story or opened in the list, at most once in MMAppInsides's `every`, D11.
@interface MMWindowController (Insides) <MMWindowInsidesHost>
/// The window closed: nothing is asked and nothing is kept. Open, the first ask starts to listen for answers.
- (void)insidesOpen:(BOOL)open;
/// A story shows: the app row's or one of its insides' asks the app. YES for a row of the insides, whose story needs
/// nothing more of the controller.
- (BOOL)insidesStory:(nullable NSString *)key;
/// A press on Go to in a tab's story, off main. NO for a row that is not one of the insides.
- (BOOL)insidesGoTo:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
