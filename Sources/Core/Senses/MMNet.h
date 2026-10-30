// Senses: the whole Mac's network, read in the Senses pass, off main. Pattern P13, beside MMPower.
// Bytes come from the interface counters, one IFMIB_IFDATA sysctl per interface with 64-bit if_data64 per pass.
// NET_RT_IFLIST2 cut the counts to 32 bits and rounded them to 1 KB on macOS 27, and getifaddrs has 32 bits.
// The route out comes from SystemConfiguration: PrimaryInterface in State:/Network/Global/IPv4, or IPv6 when
// IPv4 has none, and the kind of that interface from SCNetworkInterface.
// There is no per-app traffic. The designs ask for the whole Mac only. nettop never runs, as invariant 4 says.
#import <Foundation/Foundation.h>

/// Which total an interface counts toward. Loopback is left out of every reading.
/// A tunnel, such as utun, ipsec or ppp, carries traffic that also crosses a physical interface, so a VPN
/// would count it twice. A bridge, vlan or bond adds up its members, so it would count them twice too.
typedef NS_ENUM(uint8_t, MMNetGroup) {
    MMNetGroupPhysical = 0,     // en, awdl, llw, ap and the rest: the whole Mac's traffic
    MMNetGroupTunnel = 1,       // utun, ipsec, ppp, gif, stf, tun, tap, wg: counted apart
    MMNetGroupVirtual = 2,      // bridge, vlan, bond: listed, in no total
};
/// "physical", "tunnel" or "virtual".
NSString *MMNetGroupName(MMNetGroup group);
/// The group a BSD interface name belongs to, from its prefix.
MMNetGroup MMNetGroupOf(NSString *name);

/// The kind of the interface the primary route uses.
typedef NS_ENUM(uint8_t, MMNetKind) {
    MMNetKindNone = 0,          // no primary route: offline
    MMNetKindWiFi = 1,          // SCNetworkInterface type IEEE80211
    MMNetKindEthernet = 2,      // type Ethernet, and not a phone
    MMNetKindPhone = 3,         // a phone over USB, an iPhone or iPad Ethernet, Bluetooth PAN or WWAN
    MMNetKindTunnel = 4,        // a VPN that takes the whole route, such as utun
    MMNetKindOther = 5,         // a bridge, FireWire or an interface SystemConfiguration does not list
};
/// "none", "wifi", "ethernet", "phone", "tunnel" or "other".
NSString *MMNetKindName(MMNetKind kind);
/// The kind from an SCNetworkInterface type and its display name. With a nil type, from the BSD name alone.
MMNetKind MMNetKindFrom(NSString *bsdName, NSString *scType, NSString *displayName);

/// The most bytes a second an interface may move before a step counts as a reset: 100 Gbit/s.
extern const double MMNetMaxBytesPerSecond;

/// One interface in one reading.
@interface MMNetInterface : NSObject
@property (readonly, copy) NSString *name;              // BSD name, such as en0
@property (readonly) MMNetGroup group;
@property (readonly) uint64_t bytesIn, bytesOut;        // the counters as read: since boot, or since it came up
/// Bytes a second since the reading before. 0 when the interface is new, came back, or its counter went
/// back or jumped past MMNetMaxBytesPerSecond. -1 when there is no reading before.
@property (readonly) double inPerSecond, outPerSecond;
/// YES when this reading counted a reset: a counter went back, a 32-bit wrap or a step too large to be real.
@property (readonly) BOOL reset;
@end

/// The whole Mac's network in one Senses pass. Immutable. MMPower.net holds the latest.
@interface MMNet : NSObject
@property (readonly) NSDate *at;
/// Seconds on CLOCK_MONOTONIC_RAW, sleep included, when the counters were read. Rates divide by its steps.
@property (readonly) double clock;
@property (readonly) NSArray<MMNetInterface *> *interfaces;     // loopback left out, sorted by name
/// The sums over the physical interfaces, and apart over the tunnels. An interface that went away leaves the sum.
@property (readonly) uint64_t bytesIn, bytesOut, tunnelBytesIn, tunnelBytesOut;
/// Bytes a second over the same groups, from the interfaces read in both readings. Never negative.
/// -1 on the first reading, when there is nothing to divide by.
@property (readonly) double inPerSecond, outPerSecond, tunnelInPerSecond, tunnelOutPerSecond;
/// The seconds the rates cover. 0 on the first reading.
@property (readonly) double rateSeconds;
/// The BSD name of the interface the primary route uses, or nil when there is none.
@property (readonly, copy) NSString *primaryInterface;
@property (readonly) MMNetKind kind;
/// YES when a primary route exists. MMPower.online reads the routing table and can see a default route
/// a moment before SystemConfiguration names a primary service, so the two may differ for one pass.
@property (readonly) BOOL online;
/// The JSON form that `minmacs net --json` and `status --json` print.
- (NSDictionary *)json;
@end

/// The next reading from the one before, pure, so tests can step it.
/// counters: one dictionary per interface with "name", "in" and "out", and "loopback" YES to leave it out.
/// route: "interface" and "kind", an MMNetKind as a number, or empty for no primary route.
/// clock: seconds on a clock that only goes forward. prev may be nil.
MMNet *MMNetNext(MMNet *prev, NSArray<NSDictionary *> *counters, NSDictionary *route, double clock);

/// Reads the counters and the route now and steps from prev. Senses calls it once per pass, on its own queue.
/// The route's interface kind is read once per new interface name, at most once a minute for a name
/// SystemConfiguration does not list. Never on main.
MMNet *MMNetRead(MMNet *prev);

#ifdef MM_TESTS
/// A fake reader for tests, so wrap, a gone interface and offline are checked without the real network.
/// Compiled only with -DMM_TESTS, as MMPowerSource is.
@protocol MMNetSource <NSObject>
- (NSArray<NSDictionary *> *)counters;      // as MMNetNext takes them
- (NSDictionary *)route;                    // as MMNetNext takes it
- (double)clock;                            // seconds, as MMNetNext takes it
@end
void MMUseNetSource(id<MMNetSource> source); // nil goes back to the system
#endif
