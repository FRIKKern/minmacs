#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MMVerdict) { MMKeep, MMClose, MMUnsorted };

/// The rules file: keep / close lists of bundle ids (a trailing * matches a prefix),
/// noise / work lists of hosts for browser trimming, and apps whose local listeners
/// do not mean "serving an agent". JSON the user can read and edit.
/// Defaults are written on first run; new defaults merge in on upgrade, additively.
@interface MMRules : NSObject
+ (instancetype)shared;
@property (readonly) NSURL *fileURL;
@property (readonly) NSArray<NSString *> *keep, *close, *noiseHosts, *workHosts, *ignoreServing;
- (MMVerdict)verdictFor:(NSString *)bundleID;
- (void)setVerdict:(MMVerdict)v forBundleID:(NSString *)bundleID;
- (NSString *)tabVerdictForHost:(NSString *)host;       // noise | work | other
- (void)addWorkHost:(NSString *)host;
- (void)addNoiseHost:(NSString *)host;
- (BOOL)ignoresServing:(NSString *)bundleID;
- (void)setIgnoresServing:(BOOL)ignore forBundleID:(NSString *)bundleID;
- (void)reload;
@end
