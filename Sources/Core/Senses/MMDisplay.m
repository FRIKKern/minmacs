// The displays on demand. See MMDisplay.h.
#import <CoreGraphics/CoreGraphics.h>
#import <os/lock.h>
#import "Core/Senses/MMDisplay.h"

@interface MMDisplay ()
@property (readwrite) uint32_t displayID, vendor, model;
@property (readwrite) BOOL builtin, asleep, active, main, mirrored;
@property (readwrite) NSInteger width, height;
@end

@implementation MMDisplay
- (NSDictionary *)json {
    return @{@"id": @(self.displayID), @"builtin": @(self.builtin), @"asleep": @(self.asleep), @"active": @(self.active),
             @"main": @(self.main), @"mirrored": @(self.mirrored), @"vendor": @(self.vendor), @"model": @(self.model),
             @"width": @(self.width), @"height": @(self.height)};
}
@end

#ifdef MM_TESTS
static NSArray<NSDictionary *> *gFake;
static os_unfair_lock gFakeLock = OS_UNFAIR_LOCK_INIT;
void MMUseDisplays(NSArray<NSDictionary *> *displays) {
    os_unfair_lock_lock(&gFakeLock);
    gFake = [displays copy];
    os_unfair_lock_unlock(&gFakeLock);
}
#endif

NSArray<MMDisplay *> *MMDisplaysNow(void) {
#ifdef MM_TESTS
    os_unfair_lock_lock(&gFakeLock);
    NSArray *fake = gFake;
    os_unfair_lock_unlock(&gFakeLock);
    if (fake) {
        NSMutableArray *out = [NSMutableArray new];
        for (NSDictionary *d in fake) {
            MMDisplay *x = [MMDisplay new];
            for (NSString *k in d) [x setValue:d[k] forKey:k];
            [out addObject:x];
        }
        return out;
    }
#endif
    CGDirectDisplayID ids[32];
    uint32_t n = 0;
    if (CGGetOnlineDisplayList(32, ids, &n) != kCGErrorSuccess) return nil;
    NSMutableArray<MMDisplay *> *out = [NSMutableArray new];
    for (uint32_t i = 0; i < n; i++) {
        CGDirectDisplayID d = ids[i];
        MMDisplay *x = [MMDisplay new];
        x.displayID = d;
        x.builtin = CGDisplayIsBuiltin(d) != 0;
        x.asleep = CGDisplayIsAsleep(d) != 0;
        x.active = CGDisplayIsActive(d) != 0;
        x.main = CGDisplayIsMain(d) != 0;
        x.mirrored = CGDisplayMirrorsDisplay(d) != kCGNullDirectDisplay;
        x.vendor = CGDisplayVendorNumber(d);
        x.model = CGDisplayModelNumber(d);
        x.width = (NSInteger)CGDisplayPixelsWide(d);
        x.height = (NSInteger)CGDisplayPixelsHigh(d);
        [out addObject:x];
    }
    [out sortUsingComparator:^NSComparisonResult(MMDisplay *a, MMDisplay *b) {
        return a.builtin == b.builtin ? (a.displayID < b.displayID ? NSOrderedAscending : NSOrderedDescending) : (a.builtin ? NSOrderedAscending : NSOrderedDescending);
    }];
    return out;
}

MMDisplayState MMDisplayStateFrom(NSArray<MMDisplay *> *displays, BOOL lidClosed, BOOL lidLive, BOOL screenOff) {
    MMDisplayState st = {0};
    if (!displays) return st;
    st.known = YES;
    for (MMDisplay *d in displays) {
        if (d.asleep) { st.anyAsleep = YES; continue; }
        if (d.builtin) {
            // Shut, the panel is dark, unless the lid override keeps the Mac running and the screen is left on.
            if (!lidClosed || (lidLive && !screenOff)) st.builtinLit = YES;
        } else st.externalAwake = YES;
    }
    st.canCapture = st.builtinLit || st.externalAwake;
    return st;
}

NSString *MMDisplayActiveWord(MMDisplayState st) {
    if (!st.known) return @"unknown";
    if (st.externalAwake) return @"external";
    if (st.builtinLit) return @"builtin";
    if (st.anyAsleep) return @"asleep";
    return @"none";
}
