#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MMVerdict) { MMKeep, MMClose, MMUnsorted };

/// Keep / close lists of bundle ids (a trailing * matches a prefix).
/// Stored as JSON the user can read and edit. Defaults are written on first run.
@interface MMRules : NSObject
+ (instancetype)shared;
@property (readonly) NSURL *fileURL;
@property (readonly) NSArray<NSString *> *keep, *close;
- (MMVerdict)verdictFor:(NSString *)bundleID;
- (void)setVerdict:(MMVerdict)v forBundleID:(NSString *)bundleID;
- (void)reload;
@end
