// The one URL router, pattern P62. minmacs:// is the app's scheme, and the old apps' schemes stay as aliases,
// so links and Shortcuts from LocoHost and MinMacs 1.x keep working. The router owns login and quit:
//   <scheme>://quit, login-on, login-off and settings, for every scheme
//   minmacs://<expert>/<command>   the same as <legacy scheme of expert>://<command>
//   locohost://<command>           LocoHost's -openURL:, with a CLI fallback when it has none
//   minmacs://<command>            MinMacs 1.x: run, run-now, restore and review
// Foundation only. The app shell carries the route out on the main thread.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MMRouteKind) {
    MMRouteNone = 0,      // a scheme or command the router does not know
    MMRouteQuit,
    MMRouteLoginOn,
    MMRouteLoginOff,
    MMRouteSettings,      // the Settings window on its overview pane
    MMRouteExpert,        // hand url to the expert's -openURL:, then run words when it says NO
};

@interface MMRoute : NSObject
@property (readonly) MMRouteKind kind;
@property (readonly, copy) NSString *expert;            // the expert id, for MMRouteExpert
/// The URL in the expert's own legacy scheme, such as locohost://review for minmacs://locohost/review.
@property (readonly) NSURL *url;
/// The CLI words that do the same, such as review locohost --now, or nil. The shell runs them in the app.
@property (readonly, copy) NSArray<NSString *> *words;
@end

/// The schemes the app answers, minmacs first. Info.plist lists the same.
NSArray<NSString *> *MMURLSchemes(void);
/// Where a URL goes. legacyNames maps a scheme such as "locohost" to its expert id. nil uses MMLegacyNames.
MMRoute *MMRouteURL(NSURL *url, NSDictionary<NSString *, NSString *> *legacyNames);
