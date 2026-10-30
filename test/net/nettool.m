// The network facts of Sources/Core/Senses/MMNet.h on fake readings. Built by test/net.sh with -DMM_TESTS.
// No command here reads the real network: steps calls MMNetNext with made-up counters, and senses runs the
// Senses pass with a fake MMNetSource in place of the sysctl and SystemConfiguration.
#import "Core/MMCore.h"

static id J(double r) { return r < 0 ? NSNull.null : @(llround(r)); }
static NSDictionary *C(NSString *name, uint64_t in, uint64_t out) { return @{@"name": name, @"in": @(in), @"out": @(out)}; }
static NSDictionary *Wifi(void) { return @{@"interface": @"en0", @"kind": @(MMNetKindWiFi)}; }

static NSDictionary *Ifs(MMNet *n) {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (MMNetInterface *i in n.interfaces)
        d[i.name] = @{@"in": J(i.inPerSecond), @"out": J(i.outPerSecond), @"reset": @(i.reset), @"group": MMNetGroupName(i.group)};
    return d;
}

static NSDictionary *Steps(void) {
    NSMutableDictionary *o = [NSMutableDictionary new];
    // The first reading: loopback is left out, a tunnel is counted apart, a bridge is in no total, and there is no rate.
    NSArray *first = @[C(@"en0", 1000, 2000), @{@"name": @"lo0", @"in": @(500), @"out": @(500), @"loopback": @YES},
                       C(@"utun3", 300, 400), C(@"bridge0", 7000, 7000), C(@"en5", 100, 100)];
    MMNet *a = MMNetNext(nil, first, Wifi(), 100);
    o[@"first"] = @{@"names": [[a.interfaces valueForKey:@"name"] componentsJoinedByString:@","], @"in": @(a.bytesIn), @"out": @(a.bytesOut),
                    @"tunnelIn": @(a.tunnelBytesIn), @"rateIn": J(a.inPerSecond), @"rateSeconds": @(a.rateSeconds),
                    @"ifRate": J([a.interfaces.firstObject inPerSecond]), @"online": @(a.online), @"kind": MMNetKindName(a.kind),
                    @"primary": a.primaryInterface ?: NSNull.null};
    // Five seconds on: en0 moved 5000 in and 10000 out, the tunnel 4000 in that en0 also carried.
    MMNet *b = MMNetNext(a, @[C(@"en0", 6000, 12000), C(@"utun3", 4300, 400), C(@"bridge0", 9000, 9000), C(@"en5", 100, 100)], Wifi(), 105);
    o[@"step"] = @{@"in": J(b.inPerSecond), @"out": J(b.outPerSecond), @"tunnelIn": J(b.tunnelInPerSecond), @"seconds": @(b.rateSeconds),
                   @"ifs": Ifs(b)};
    // A 32-bit counter wraps: 4294967000 to 1000 over 5 seconds is 1296 bytes.
    MMNet *w0 = MMNetNext(nil, @[@{@"name": @"en0", @"in": @4294967000ull, @"out": @10, @"bits": @32}], Wifi(), 0);
    MMNet *w1 = MMNetNext(w0, @[@{@"name": @"en0", @"in": @1000, @"out": @10, @"bits": @32}], Wifi(), 5);
    o[@"wrap"] = @{@"in": J(w1.inPerSecond), @"reset": @([w1.interfaces.firstObject reset])};
    // The same drop on a 64-bit counter, the system reader's width, is a reset. Read as a 32-bit wrap it would be
    // 794,967,396 bytes in 5 seconds, 1.27 Gbit/s, under the 1.5 Gbit/s bound of a 1 Gbit/s link.
    MMNet *x0 = MMNetNext(nil, @[@{@"name": @"en0", @"in": @3500000000ull, @"out": @10, @"baud": @1e9}], Wifi(), 0);
    MMNet *x1 = MMNetNext(x0, @[@{@"name": @"en0", @"in": @100, @"out": @10, @"baud": @1e9}], Wifi(), 5);
    o[@"wide"] = @{@"in": J(x1.inPerSecond), @"reset": @([x1.interfaces.firstObject reset])};
    // A 64-bit counter wraps at 64 bits: UINT64_MAX - 999 to 1000 over 5 seconds is 2000 bytes.
    MMNet *y0 = MMNetNext(nil, @[C(@"en0", UINT64_MAX - 999, 10)], Wifi(), 0);
    MMNet *y1 = MMNetNext(y0, @[C(@"en0", 1000, 10)], Wifi(), 5);
    o[@"wrap64"] = @{@"in": J(y1.inPerSecond), @"reset": @([y1.interfaces.firstObject reset])};
    // A 64-bit counter that goes back means the interface was reset, so the step is 0, never negative or huge.
    MMNet *r0 = MMNetNext(nil, @[C(@"en0", 10000000000ull, 5000000000ull)], Wifi(), 0);
    MMNet *r1 = MMNetNext(r0, @[C(@"en0", 100, 5000000100ull)], Wifi(), 5);
    o[@"back"] = @{@"in": J(r1.inPerSecond), @"out": J(r1.outPerSecond), @"reset": @([r1.interfaces.firstObject reset])};
    // A counter low in 32 bits that goes back is a reset too, not a wrap, at either width.
    MMNet *l0 = MMNetNext(nil, @[C(@"en0", 1000000000ull, 0)], Wifi(), 0);
    MMNet *l1 = MMNetNext(l0, @[C(@"en0", 100, 0)], Wifi(), 5);
    o[@"lowBack"] = @{@"in": J(l1.inPerSecond), @"reset": @([l1.interfaces.firstObject reset])};
    // A step past 100 Gbit/s is not real.
    MMNet *h0 = MMNetNext(nil, @[C(@"en0", 0, 0)], Wifi(), 0);
    MMNet *h1 = MMNetNext(h0, @[C(@"en0", 1000000000000000ull, 0)], Wifi(), 5);
    o[@"huge"] = @{@"in": J(h1.inPerSecond), @"reset": @([h1.interfaces.firstObject reset])};
    // A link that says it runs at 1 Gbit/s cannot move 1 GB in one second.
    MMNet *b0 = MMNetNext(nil, @[@{@"name": @"en0", @"in": @0, @"out": @0, @"baud": @1e9}], Wifi(), 0);
    MMNet *b1 = MMNetNext(b0, @[@{@"name": @"en0", @"in": @1000000000, @"out": @0, @"baud": @1e9}], Wifi(), 1);
    MMNet *b2 = MMNetNext(b0, @[@{@"name": @"en0", @"in": @100000000, @"out": @0, @"baud": @1e9}], Wifi(), 1);
    o[@"baud"] = @{@"over": J(b1.inPerSecond), @"under": J(b2.inPerSecond)};
    // en5 goes away: it leaves the list and the sums. Then it comes back with fresh counters and counts 0 at first.
    MMNet *g1 = MMNetNext(b, @[C(@"en0", 11000, 12000), C(@"utun3", 4300, 400)], Wifi(), 110);
    MMNet *g2 = MMNetNext(g1, @[C(@"en0", 16000, 12000), C(@"utun3", 4300, 400), C(@"en5", 20, 30)], Wifi(), 115);
    MMNet *g3 = MMNetNext(g2, @[C(@"en0", 16000, 12000), C(@"utun3", 4300, 400), C(@"en5", 520, 30)], Wifi(), 120);
    o[@"gone"] = @{@"names": [[g1.interfaces valueForKey:@"name"] componentsJoinedByString:@","], @"in": @(g1.bytesIn), @"rateIn": J(g1.inPerSecond)};
    o[@"back5"] = @{@"en5": Ifs(g2)[@"en5"][@"in"], @"rateIn": J(g2.inPerSecond), @"next": J(g3.inPerSecond)};
    // Offline: no primary route.
    MMNet *off = MMNetNext(g3, @[C(@"en0", 16000, 12000)], @{}, 125);
    o[@"offline"] = @{@"online": @(off.online), @"kind": MMNetKindName(off.kind), @"primary": off.primaryInterface ?: NSNull.null,
                      @"json": [off json][@"primaryInterface"] == NSNull.null ? @"null" : @"set"};
    // The same clock twice gives no rate.
    MMNet *same = MMNetNext(g3, @[C(@"en0", 16000, 12000)], Wifi(), 120);
    o[@"sameClock"] = @{@"in": J(same.inPerSecond), @"seconds": @(same.rateSeconds)};
    // The kind of the route's interface.
    o[@"kinds"] = @{@"wifi": MMNetKindName(MMNetKindFrom(@"en0", @"IEEE80211", @"Wi-Fi")),
                    @"ethernet": MMNetKindName(MMNetKindFrom(@"en8", @"Ethernet", @"USB 10/100/1000 LAN")),
                    @"iphone": MMNetKindName(MMNetKindFrom(@"en7", @"Ethernet", @"iPhone USB")),
                    @"bluetooth": MMNetKindName(MMNetKindFrom(@"en9", @"Bluetooth", @"Bluetooth PAN")),
                    @"utun": MMNetKindName(MMNetKindFrom(@"utun4", nil, nil)),
                    @"bridge": MMNetKindName(MMNetKindFrom(@"bridge0", @"Bridge", @"Thunderbolt Bridge")),
                    @"unlisted": MMNetKindName(MMNetKindFrom(@"en12", nil, nil)),
                    @"none": MMNetKindName(MMNetKindFrom(nil, nil, nil))};
    NSDictionary *j = [b json];
    o[@"json"] = @{@"keys": [[[j allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","],
                   @"firstRate": [a json][@"inPerSecond"] == NSNull.null ? @"null" : @"set"};
    return o;
}

@interface TNet : NSObject <MMNetSource>
@property NSArray *list;
@property NSDictionary *where;
@property double now;
@end
@implementation TNet
- (NSArray<NSDictionary *> *)counters { return self.list; }
- (NSDictionary *)route { return self.where; }
- (double)clock { return self.now; }
@end

/// The Senses pass with the fake reader: two passes give a rate, the power sheet holds it, and the pass times it.
static NSDictionary *Senses(void) {
    TNet *t = [TNet new];
    t.list = @[C(@"en0", 1000, 1000), C(@"utun9", 0, 0)];
    t.where = @{@"interface": @"en7", @"kind": @(MMNetKindPhone)};
    t.now = 50;
    MMUseNetSource(t);
    MMSensesCounts c0 = MMSenses.shared.counts;
    (void)[MMSenses.shared sampleNow];
    MMNet *first = MMSenses.shared.power.net;
    t.list = @[C(@"en0", 3000, 1500), C(@"utun9", 1000, 0)];
    t.now = 52;
    (void)[MMSenses.shared sampleNow];
    MMPower *p = MMSenses.shared.power;
    t.list = @[];
    t.where = @{};
    t.now = 54;
    (void)[MMSenses.shared sampleNow];
    MMPower *q = MMSenses.shared.power;
    MMSensesCounts c1 = MMSenses.shared.counts;
    MMUseNetSource(nil);
    return @{@"firstRate": J(first.inPerSecond), @"in": J(p.net.inPerSecond), @"out": J(p.net.outPerSecond),
             @"tunnelIn": J(p.net.tunnelInPerSecond), @"kind": MMNetKindName(p.net.kind), @"primary": p.net.primaryInterface ?: NSNull.null,
             @"online": @(p.net.online), @"emptyOnline": @(q.net.online), @"emptyIn": J(q.net.inPerSecond), @"emptyCount": @(q.net.interfaces.count),
             @"diskTotal": @((BOOL)(p.diskTotal > 0 && p.diskTotal >= p.diskFree)), @"netNs": @((BOOL)(c1.netNs > c0.netNs)),
             @"partsSum": @((BOOL)(c1.tableNs + c1.procsNs + c1.socketsNs + c1.carryNs + c1.powerNs + c1.netNs <= c1.cpuNs + 1000))};
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSDictionary *out = nil;
        if (argc == 2 && !strcmp(argv[1], "steps")) out = Steps();
        else if (argc == 2 && !strcmp(argv[1], "senses")) out = Senses();
        else { fprintf(stderr, "usage: nettool steps|senses\n"); return 2; }
        NSData *d = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
        fwrite(d.bytes, 1, d.length, stdout);
        printf("\n");
        return 0;
    }
}
