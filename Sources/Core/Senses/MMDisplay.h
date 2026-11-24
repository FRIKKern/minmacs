// The displays, for `minmacs device`: which are online, built in or not, and asleep. One read on demand, never on a
// tick: CGGetOnlineDisplayList and a few CGDisplay calls, microseconds. Nothing polls it.
#import <Foundation/Foundation.h>

/// One display as CoreGraphics lists it now.
@interface MMDisplay : NSObject
@property (readonly) uint32_t displayID;
@property (readonly) BOOL builtin, asleep, active, main;
@property (readonly) BOOL mirrored;                      // it shows another display's picture
@property (readonly) uint32_t vendor, model;             // CGDisplayVendorNumber and CGDisplayModelNumber
@property (readonly) NSInteger width, height;            // pixels of its current mode, 0 when asleep or unknown
- (NSDictionary *)json;
@end

/// The online displays now, built in first. nil when CoreGraphics could not be asked, such as with no window server.
NSArray<MMDisplay *> *MMDisplaysNow(void);

/// What the displays mean for a task that draws on or captures the screen, from the displays and the lid.
/// The built-in panel counts only while the lid is open, or while Insomnia's lid override is live and its screenOff is
/// off: then the panel stays lit with the lid shut until display sleep turns it off. Pure.
typedef struct {
    BOOL known;               // the displays could be read
    BOOL builtinLit;          // the built-in panel is there, awake, and lit
    BOOL externalAwake;       // a display that is not built in is awake
    BOOL anyAsleep;           // some display is there but asleep
    BOOL canCapture;          // builtinLit or externalAwake
} MMDisplayState;
MMDisplayState MMDisplayStateFrom(NSArray<MMDisplay *> *displays, BOOL lidClosed, BOOL lidLive, BOOL screenOff);
/// "external", "builtin", "asleep" or "none", and "unknown" when the displays could not be read.
NSString *MMDisplayActiveWord(MMDisplayState st);

#ifdef MM_TESTS
/// The displays MMDisplaysNow gives in place of CoreGraphics, each a dictionary with the property names above as keys.
/// nil goes back to CoreGraphics. An empty array is a Mac with no display. Compiled only with -DMM_TESTS.
void MMUseDisplays(NSArray<NSDictionary *> *displays);
#endif
