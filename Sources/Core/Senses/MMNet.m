// The whole Mac's network: interface counters by sysctl and the route out from SystemConfiguration.
// MMSenses calls MMNetRead once per pass on its own queue. Nothing here runs a process or touches AppKit.
#import "Core/Senses/MMNet.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <os/lock.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <time.h>

// build.sh and every test link line name their frameworks. This one rides in the object file instead,
// so a test that compiles Sources/Core needs no change to link it.
__asm__(".linker_option \"-framework\", \"SystemConfiguration\"");

const double MMNetMaxBytesPerSecond = 100e9 / 8;

NSString *MMNetGroupName(MMNetGroup group) {
    switch (group) {
        case MMNetGroupTunnel: return @"tunnel";
        case MMNetGroupVirtual: return @"virtual";
        default: return @"physical";
    }
}

static BOOL HasPrefix(NSString *name, NSArray<NSString *> *prefixes) {
    for (NSString *p in prefixes) if ([name hasPrefix:p]) return YES;
    return NO;
}

MMNetGroup MMNetGroupOf(NSString *name) {
    if (HasPrefix(name, @[@"utun", @"ipsec", @"ppp", @"gif", @"stf", @"tun", @"tap", @"wg"])) return MMNetGroupTunnel;
    if (HasPrefix(name, @[@"bridge", @"vlan", @"bond"])) return MMNetGroupVirtual;
    return MMNetGroupPhysical;
}

NSString *MMNetKindName(MMNetKind kind) {
    switch (kind) {
        case MMNetKindWiFi: return @"wifi";
        case MMNetKindEthernet: return @"ethernet";
        case MMNetKindPhone: return @"phone";
        case MMNetKindTunnel: return @"tunnel";
        case MMNetKindOther: return @"other";
        default: return @"none";
    }
}

MMNetKind MMNetKindFrom(NSString *bsdName, NSString *scType, NSString *displayName) {
    if (!bsdName.length) return MMNetKindNone;
    if (MMNetGroupOf(bsdName) == MMNetGroupTunnel) return MMNetKindTunnel;
    if (!scType) return MMNetKindOther;
    if ([scType isEqualToString:(__bridge NSString *)kSCNetworkInterfaceTypeIEEE80211]) return MMNetKindWiFi;
    if ([scType isEqualToString:(__bridge NSString *)kSCNetworkInterfaceTypeBluetooth] ||
        [scType isEqualToString:(__bridge NSString *)kSCNetworkInterfaceTypeWWAN]) return MMNetKindPhone;
    if ([scType isEqualToString:(__bridge NSString *)kSCNetworkInterfaceTypeEthernet]) {
        // An iPhone or iPad shares its connection over USB as an Ethernet interface with its own name,
        // as an Android phone does over RNDIS.
        for (NSString *w in @[@"iPhone", @"iPad", @"RNDIS", @"Android"])
            if ([displayName rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) return MMNetKindPhone;
        return MMNetKindEthernet;
    }
    return MMNetKindOther;
}

#pragma mark - The values

@interface MMNetInterface ()
@property (readwrite, copy) NSString *name;
@property (readwrite) MMNetGroup group;
@property (readwrite) uint64_t bytesIn, bytesOut;
@property (readwrite) double inPerSecond, outPerSecond;
@property (readwrite) BOOL reset;
@property double baud;      // link speed in bits a second, 0 when unknown
@property unsigned bits;    // the counters' width, 32 or 64
@end
@implementation MMNetInterface
- (NSDictionary *)json {
    return @{@"name": _name, @"group": MMNetGroupName(_group), @"bytesIn": @(_bytesIn), @"bytesOut": @(_bytesOut),
             @"inPerSecond": _inPerSecond < 0 ? NSNull.null : @(llround(_inPerSecond)),
             @"outPerSecond": _outPerSecond < 0 ? NSNull.null : @(llround(_outPerSecond)), @"reset": @(_reset)};
}
@end

@interface MMNet ()
@property (readwrite) NSDate *at;
@property (readwrite) double clock;
@property (readwrite) NSArray<MMNetInterface *> *interfaces;
@property (readwrite) uint64_t bytesIn, bytesOut, tunnelBytesIn, tunnelBytesOut;
@property (readwrite) double inPerSecond, outPerSecond, tunnelInPerSecond, tunnelOutPerSecond, rateSeconds;
@property (readwrite, copy) NSString *primaryInterface;
@property (readwrite) MMNetKind kind;
@property (readwrite) BOOL online;
@property NSDictionary<NSString *, MMNetInterface *> *byName;
@end

static id Rate(double r) { return r < 0 ? NSNull.null : @(llround(r)); }

@implementation MMNet
- (NSDictionary *)json {
    NSMutableArray *ifs = [NSMutableArray arrayWithCapacity:_interfaces.count];
    for (MMNetInterface *i in _interfaces) [ifs addObject:[i json]];
    return @{@"online": @(_online), @"primaryInterface": _primaryInterface ?: NSNull.null, @"kind": MMNetKindName(_kind),
             @"bytesIn": @(_bytesIn), @"bytesOut": @(_bytesOut),
             @"inPerSecond": Rate(_inPerSecond), @"outPerSecond": Rate(_outPerSecond),
             @"rateSeconds": @(round(_rateSeconds * 1000) / 1000),
             @"tunnel": @{@"bytesIn": @(_tunnelBytesIn), @"bytesOut": @(_tunnelBytesOut),
                          @"inPerSecond": Rate(_tunnelInPerSecond), @"outPerSecond": Rate(_tunnelOutPerSecond)},
             @"interfaces": ifs};
}
@end

#pragma mark - The step

/// Bytes a second from one counter's two readings, never negative. A counter that went back is a wrap when it was
/// in the top quarter of its own width, 32 or 64 bits, and the step it gives is one the link could carry. Otherwise
/// the interface was reset, as when it went away and came back, and the step counts 0. The width matters: the
/// system reader's counters are 64 bits, so one that drops from 3.5 GB to 0 was reset, and a 32-bit rule would
/// read it as a wrap of 800 MB.
static double Step(uint64_t was, uint64_t now, unsigned bits, double dt, double maxPerSecond, BOOL *reset) {
    uint64_t top = bits == 32 ? UINT32_MAX : UINT64_MAX;
    uint64_t d;
    if (now >= was) d = now - was;
    else if (was <= top && was >= top - (top >> 2) && now <= top) d = (top - was) + now + 1;
    else { *reset = YES; return 0; }
    double r = (double)d / dt;
    if (r > maxPerSecond) { *reset = YES; return 0; }
    return r;
}

MMNet *MMNetNext(MMNet *prev, NSArray<NSDictionary *> *counters, NSDictionary *route, double clock) {
    MMNet *n = [MMNet new];
    n.at = NSDate.date;
    n.clock = clock;
    double dt = prev ? clock - prev.clock : 0;
    BOOL rated = prev && dt > 0;
    n.rateSeconds = rated ? dt : 0;
    double rin = 0, rout = 0, tin = 0, tout = 0;
    NSMutableArray<MMNetInterface *> *list = [NSMutableArray arrayWithCapacity:counters.count];
    NSMutableDictionary<NSString *, MMNetInterface *> *byName = [NSMutableDictionary dictionaryWithCapacity:counters.count];
    for (NSDictionary *c in counters) {
        NSString *name = c[@"name"];
        if (![name isKindOfClass:NSString.class] || !name.length || [c[@"loopback"] boolValue] || byName[name]) continue;
        MMNetInterface *i = [MMNetInterface new];
        i.name = name;
        i.group = MMNetGroupOf(name);
        i.bytesIn = [c[@"in"] unsignedLongLongValue];
        i.bytesOut = [c[@"out"] unsignedLongLongValue];
        i.baud = [c[@"baud"] doubleValue];
        i.bits = [c[@"bits"] unsignedIntValue] == 32 ? 32 : 64;
        i.inPerSecond = i.outPerSecond = -1;
        MMNetInterface *was = rated ? prev.byName[name] : nil;
        if (rated) {
            i.inPerSecond = i.outPerSecond = 0;
            if (was) {
                // A link that says its speed bounds its step at one and a half times that. The rest at 100 Gbit/s.
                double max = i.baud > 0 ? MIN(MMNetMaxBytesPerSecond, i.baud / 8 * 1.5) : MMNetMaxBytesPerSecond;
                BOOL reset = NO;
                double a = Step(was.bytesIn, i.bytesIn, i.bits, dt, max, &reset);
                double b = Step(was.bytesOut, i.bytesOut, i.bits, dt, max, &reset);
                // One counter reset means the interface was, so neither direction's step is trusted.
                if (reset) a = b = 0;
                i.inPerSecond = a; i.outPerSecond = b; i.reset = reset;
            }
        }
        if (i.group == MMNetGroupPhysical) {
            n.bytesIn += i.bytesIn; n.bytesOut += i.bytesOut;
            if (rated) { rin += i.inPerSecond; rout += i.outPerSecond; }
        } else if (i.group == MMNetGroupTunnel) {
            n.tunnelBytesIn += i.bytesIn; n.tunnelBytesOut += i.bytesOut;
            if (rated) { tin += i.inPerSecond; tout += i.outPerSecond; }
        }
        byName[name] = i;
        [list addObject:i];
    }
    [list sortUsingComparator:^NSComparisonResult(MMNetInterface *a, MMNetInterface *b) { return [a.name compare:b.name]; }];
    n.interfaces = [list copy];
    n.byName = [byName copy];
    n.inPerSecond = rated ? rin : -1; n.outPerSecond = rated ? rout : -1;
    n.tunnelInPerSecond = rated ? tin : -1; n.tunnelOutPerSecond = rated ? tout : -1;
    NSString *primary = route[@"interface"];
    if ([primary isKindOfClass:NSString.class] && primary.length) {
        n.primaryInterface = primary;
        n.kind = (MMNetKind)[route[@"kind"] unsignedCharValue];
        if (n.kind == MMNetKindNone) n.kind = MMNetKindOther;
        n.online = YES;
    }
    return n;
}

#pragma mark - The system reader

/// Every interface's counters, one IFMIB_IFDATA sysctl per interface index, about 3 us each.
/// IFMIB_IFCOUNT is at least the highest index, not the number of interfaces: 27 beside 23 names and a top index
/// of 26 on this Mac. The loop runs to it and skips a gap.
/// getifaddrs has 32-bit counters. NET_RT_IFLIST2 has 64-bit fields, but on macOS 27 it handed this process
/// en0's bytes cut to 32 bits and rounded to 1 KB: 83,474,432, where the interface MIB and netstat -ib said
/// 597,083,929,253.
static NSArray<NSDictionary *> *ReadCounters(void) {
    int count = 0; size_t len = sizeof count;
    int cmib[5] = { CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT };
    if (sysctl(cmib, 5, &count, &len, NULL, 0) != 0 || count <= 0) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int index = 1; index <= count && index < 4096; index++) {
        int mib[6] = { CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL };
        struct ifmibdata d; size_t dl = sizeof d;
        if (sysctl(mib, 6, &d, &dl, NULL, 0) != 0) continue;   // a gap in the index, or an interface just gone
        size_t nl = strnlen(d.ifmd_name, IFNAMSIZ);
        NSString *name = nl ? [[NSString alloc] initWithBytes:d.ifmd_name length:nl encoding:NSASCIIStringEncoding] : nil;
        if (!name) continue;
        [out addObject:@{@"name": name, @"in": @(d.ifmd_data.ifi_ibytes), @"out": @(d.ifmd_data.ifi_obytes),
                         @"baud": @(d.ifmd_data.ifi_baudrate), @"bits": @64, @"loopback": @((d.ifmd_flags & IFF_LOOPBACK) != 0)}];
    }
    return out;
}

static os_unfair_lock gKindLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *gKinds;        // BSD name to MMNetKind, as SC listed it
static NSMutableDictionary<NSString *, NSNumber *> *gKindMissAt;   // BSD name to when SC did not list it
static SCDynamicStoreRef gStore;

static double Monotonic(void) { return (double)clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9; }

/// The kind of one interface. SCNetworkInterfaceCopyAll costs about 9 ms, so it runs only for a name not seen,
/// and at most once a minute for a name it does not list.
static MMNetKind KindOf(NSString *bsd) {
    if (MMNetGroupOf(bsd) == MMNetGroupTunnel) return MMNetKindTunnel;
    os_unfair_lock_lock(&gKindLock);
    NSNumber *k = gKinds[bsd];
    double missAt = [gKindMissAt[bsd] doubleValue];
    os_unfair_lock_unlock(&gKindLock);
    if (k) return (MMNetKind)k.unsignedCharValue;
    if (missAt > 0 && Monotonic() - missAt < 60) return MMNetKindOther;
    NSMutableDictionary *kinds = [NSMutableDictionary new];
    CFArrayRef all = SCNetworkInterfaceCopyAll();
    for (CFIndex i = 0; all && i < CFArrayGetCount(all); i++) {
        SCNetworkInterfaceRef r = (SCNetworkInterfaceRef)CFArrayGetValueAtIndex(all, i);
        NSString *name = (__bridge NSString *)SCNetworkInterfaceGetBSDName(r);
        if (!name.length) continue;
        kinds[name] = @(MMNetKindFrom(name, (__bridge NSString *)SCNetworkInterfaceGetInterfaceType(r),
                                      (__bridge NSString *)SCNetworkInterfaceGetLocalizedDisplayName(r)));
    }
    if (all) CFRelease(all);
    os_unfair_lock_lock(&gKindLock);
    gKinds = kinds;
    if (!gKindMissAt) gKindMissAt = [NSMutableDictionary new];
    if (!kinds[bsd]) gKindMissAt[bsd] = @(Monotonic());
    os_unfair_lock_unlock(&gKindLock);
    return kinds[bsd] ? (MMNetKind)[kinds[bsd] unsignedCharValue] : MMNetKindOther;
}

/// The primary interface from configd: one SCDynamicStoreCopyMultiple for the IPv4 and IPv6 global keys,
/// about 40 us. The store session is made once.
static NSDictionary *ReadRoute(void) {
    os_unfair_lock_lock(&gKindLock);
    if (!gStore) gStore = SCDynamicStoreCreate(NULL, CFSTR("no.guerrilla.minmacs.core.senses"), NULL, NULL);
    SCDynamicStoreRef store = gStore;
    os_unfair_lock_unlock(&gKindLock);
    if (!store) return @{};
    NSArray *keys = @[@"State:/Network/Global/IPv4", @"State:/Network/Global/IPv6"];
    NSDictionary *d = CFBridgingRelease(SCDynamicStoreCopyMultiple(store, (__bridge CFArrayRef)keys, NULL));
    NSString *name = nil;
    for (NSString *key in keys) {
        NSDictionary *v = d[key];
        if (![v isKindOfClass:NSDictionary.class]) continue;
        id p = v[(__bridge NSString *)kSCDynamicStorePropNetPrimaryInterface];
        if ([p isKindOfClass:NSString.class] && [p length]) { name = p; break; }
    }
    if (!name) return @{};
    return @{@"interface": name, @"kind": @(KindOf(name))};
}

#ifdef MM_TESTS
static id<MMNetSource> gNetSource;
static os_unfair_lock gNetSourceLock = OS_UNFAIR_LOCK_INIT;
void MMUseNetSource(id<MMNetSource> source) {
    os_unfair_lock_lock(&gNetSourceLock);
    gNetSource = source;
    os_unfair_lock_unlock(&gNetSourceLock);
}
#endif

MMNet *MMNetRead(MMNet *prev) {
#ifdef MM_TESTS
    os_unfair_lock_lock(&gNetSourceLock);
    id<MMNetSource> src = gNetSource;
    os_unfair_lock_unlock(&gNetSourceLock);
    if (src) return MMNetNext(prev, [src counters], [src route], [src clock]);
#endif
    NSArray *counters = ReadCounters();
    double clock = Monotonic();
    return MMNetNext(prev, counters, ReadRoute(), clock);
}
