#import <Foundation/Foundation.h>

/// One browser tab, as read from a specific browser process.
@interface MMTab : NSObject
@property (copy) NSString *url, *title, *host;
@property (copy) NSString *verdict;     // noise | work | other
@property NSInteger windowID, tabID;    // tabID is the tab's id (Chromium) or its index (Safari)
@end

/// Reads and closes tabs through Apple events aimed at ONE process id, so a second
/// instance of the same browser (Playwright, remote debugging) is never touched.
@interface MMBrowser : NSObject
+ (BOOL)isBrowser:(NSString *)bundleID;          // a browser MinMacs knows at all
+ (BOOL)canTrim:(NSString *)bundleID;            // one whose tabs it can read
/// All tabs in normal (non-private) windows, classified. nil plus *error when it cannot read them.
+ (NSArray<MMTab *> *)tabsOfPid:(pid_t)pid bundleID:(NSString *)bundleID error:(NSString **)error;
/// Closes the given tabs. Returns how many were closed.
+ (NSInteger)closeTabs:(NSArray<MMTab *> *)tabs pid:(pid_t)pid bundleID:(NSString *)bundleID;
@end
