// The last hour in memory: fixed rings filled by each graph build and by SubagentStart events. MMHistory.h says
// which pass fills each ring. Nothing here touches the disk.
#import "Core/Graph/MMHistory.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Know/MMSessions.h"
#import "Core/Runtime/MMRuntime.h"
#import <mach/mach.h>
#import <os/lock.h>

const NSTimeInterval MMHistoryGoneKeep = 600;

NSString *MMHistoryKindName(MMHistoryKind kind) {
    switch (kind) {
        case MMHistoryMac: return @"mac";
        case MMHistoryDisk: return @"disk";
        case MMHistoryAgent: return @"agent";
        case MMHistoryServer: return @"server";
    }
    return @"unknown";
}

MMHostLoad MMReadHostLoad(void) {
    static mach_port_t host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ host = mach_host_self(); });   // one send right for the whole run
    MMHostLoad l = {0};
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t n = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &n) == KERN_SUCCESS) {
        l.busyTicks = (uint64_t)cpu.cpu_ticks[CPU_STATE_USER] + cpu.cpu_ticks[CPU_STATE_SYSTEM] + cpu.cpu_ticks[CPU_STATE_NICE];
        l.totalTicks = l.busyTicks + cpu.cpu_ticks[CPU_STATE_IDLE];
    }
    vm_statistics64_data_t vm;
    n = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &n) == KERN_SUCCESS) {
        uint64_t app = vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0;
        l.memoryUsed = (app + vm.wire_count + vm.compressor_page_count) * (uint64_t)vm_kernel_page_size;
    }
    return l;
}

#pragma mark - The fixed store

/// One minute as the store keeps it, 8 bytes. The low 16 bits of the minute tell a slot of this hour from an older
/// one. CPU is kept in tenths of a percent, 0xFFFF for none. passes takes 8 bits and whole megabytes the other 24,
/// so a value is capped at 16 TB.
typedef struct {
    uint16_t minute, cpuTenths;
    uint32_t passes : 8, megabytes : 24;
} MMHistoryCell;

/// One state change as the store keeps it, 8 bytes: seconds since 1970 and the state.
typedef struct { uint32_t at; uint8_t state; } MMHistoryMark;

/// One ring. Every field is a fixed size, so 200 of them never grow.
typedef struct {
    MMHistoryKind kind;                                 // 0 when the slot is free
    uint8_t lastState;
    uint16_t stateCount, stateNext;
    MMProcKey key;
    NSTimeInterval firstSeen, lastSeen, goneAt;
    char label[48], ident[96];
    MMHistoryCell cells[MMHistoryMinutes];
    MMHistoryMark states[MMHistoryMaxStates];
} MMHistorySlot;

typedef struct {
    NSTimeInterval at;
    char agent[24], session[40];
} MMHistorySubagent;

enum { kMacSlot = 0, kDiskSlot = 1, kFirstTree = 2, kNoCPU = 0xFFFF, kMaxMB = (1 << 24) - 1 };

static uint32_t MinuteOf(NSTimeInterval t) { return t > 0 ? (uint32_t)(t / 60) : 0; }

static void Copy(char *dst, size_t size, NSString *s) {
    if (!s.length) { dst[0] = 0; return; }
    // Cut at a whole character, so the copy is always valid UTF-8.
    NSUInteger used = 0;
    [s getBytes:dst maxLength:size - 1 usedLength:&used encoding:NSUTF8StringEncoding options:0
          range:NSMakeRange(0, s.length) remainingRange:NULL];
    dst[used] = 0;
}

static NSString *Str(const char *s) { return s[0] ? @(s) : nil; }

/// cpu below 0 is none, as for the disk.
static void AddValue(MMHistorySlot *s, NSTimeInterval t, double cpu, double mb) {
    uint32_t m = MinuteOf(t);
    MMHistoryCell *x = &s->cells[m % MMHistoryMinutes];
    if (x->minute != (uint16_t)m || !x->passes) *x = (MMHistoryCell){ .minute = (uint16_t)m, .cpuTenths = cpu < 0 ? kNoCPU : 0 };
    double n = x->passes;
    if (cpu >= 0) x->cpuTenths = (uint16_t)lround(MIN((x->cpuTenths * n + cpu * 10) / (n + 1), kNoCPU - 1));
    x->megabytes = (uint32_t)lround(MIN((x->megabytes * n + MAX(mb, 0)) / (n + 1), kMaxMB));
    if (x->passes < 255) x->passes++;
    if (!s->firstSeen) s->firstSeen = t;
    s->lastSeen = t;
}

static void AddState(MMHistorySlot *s, NSTimeInterval t, MMAgentState st) {
    s->states[s->stateNext] = (MMHistoryMark){ .at = (uint32_t)MAX(t, 0), .state = (uint8_t)st };
    s->stateNext = (uint16_t)((s->stateNext + 1) % MMHistoryMaxStates);
    if (s->stateCount < MMHistoryMaxStates) s->stateCount++;
    s->lastState = (uint8_t)st;
}

/// Bytes of one copy buffer: room for every ring and every subagent start.
static const size_t kBufferBytes = MMHistoryMaxRings * sizeof(MMHistorySlot) + MMHistoryMaxSubagents * sizeof(MMHistorySubagent);

@interface MMHistory ()
- (void)recycle:(void *)bytes;
@end

/// One copy's bytes: the live slots, then the subagent starts within the hour. When the last view that reads it
/// ends, the bytes go back to the store, which keeps two for the next copies. So a build every 5 seconds reuses the
/// same memory instead of leaving freed copies on the allocator's lists.
@interface MMHistoryBuffer : NSObject {
@public
    void *bytes;
    NSUInteger rings, subs;
}
@property (weak) MMHistory *owner;
@end
@implementation MMHistoryBuffer
- (const MMHistorySlot *)slots { return bytes; }
- (const MMHistorySubagent *)subagents { return (const MMHistorySubagent *)((const MMHistorySlot *)bytes + rings); }
- (void)dealloc {
    MMHistory *o = self.owner;
    if (o) [o recycle:bytes]; else free(bytes);
}
@end

#pragma mark - Tree samples

@implementation MMHistoryTreeSample
@end

#pragma mark - The read-only copy

@interface MMHistoryRing ()
@property MMHistoryBuffer *data;                        // the view's copy of the slots
@property NSUInteger index;
@property uint32_t viewMinute;
@property NSTimeInterval viewAt;
@end

@implementation MMHistoryRing

- (const MMHistorySlot *)slot { return self.data.slots + self.index; }
- (MMHistoryKind)kind { return self.slot->kind; }
- (MMProcKey)key { return self.slot->key; }
- (NSString *)label { return Str(self.slot->label); }
- (NSString *)ident { return Str(self.slot->ident); }
- (NSTimeInterval)firstSeen { return self.slot->firstSeen; }
- (NSTimeInterval)lastSeen { return self.slot->lastSeen; }
- (NSTimeInterval)goneAt { return self.slot->goneAt; }

- (MMHistoryMinute)minuteAt:(NSUInteger)i {
    uint32_t want = self.viewMinute - (uint32_t)(MMHistoryMinutes - 1) + (uint32_t)MIN(i, (NSUInteger)MMHistoryMinutes - 1);
    MMHistoryCell x = self.slot->cells[want % MMHistoryMinutes];
    if (x.minute != (uint16_t)want || !x.passes) return (MMHistoryMinute){ .minute = want, .passes = 0, .cpuPercent = -1, .megabytes = -1 };
    return (MMHistoryMinute){ .minute = want, .passes = x.passes, .cpuPercent = x.cpuTenths == kNoCPU ? -1 : x.cpuTenths / 10.0f,
                              .megabytes = (float)x.megabytes };
}

- (NSArray<NSValue *> *)stateChanges {
    const MMHistorySlot *s = self.slot;
    NSMutableArray *out = [NSMutableArray new];
    NSUInteger first = (s->stateNext + MMHistoryMaxStates - s->stateCount) % MMHistoryMaxStates;
    for (NSUInteger i = 0; i < s->stateCount; i++) {
        MMHistoryMark m = s->states[(first + i) % MMHistoryMaxStates];
        MMHistoryStateChange c = { .at = m.at, .state = (MMAgentState)m.state };
        if (c.at < self.viewAt - MMHistoryMinutes * 60) continue;
        [out addObject:[NSValue valueWithBytes:&c objCType:@encode(MMHistoryStateChange)]];
    }
    return out;
}

static id Num(double v) { return v < 0 ? NSNull.null : @(round(v * 10) / 10); }

static NSString *StateWord(MMAgentState st) {
    switch (st) {
        case MMAgentWorking: return @"working";
        case MMAgentWaiting: return @"waiting";
        case MMAgentIdle: return @"idle";
        default: return @"unknown";
    }
}

- (NSDictionary *)json {
    NSMutableArray *cpu = [NSMutableArray new], *mb = [NSMutableArray new], *passes = [NSMutableArray new];
    for (NSUInteger i = 0; i < MMHistoryMinutes; i++) {
        MMHistoryMinute m = [self minuteAt:i];
        [cpu addObject:Num(m.passes ? m.cpuPercent : -1)];
        [mb addObject:Num(m.passes ? m.megabytes : -1)];
        [passes addObject:@(m.passes)];
    }
    MMHistoryKind k = self.kind;
    NSMutableDictionary *j = [@{@"kind": MMHistoryKindName(k), @"passes": passes,
                                @"firstSeen": @(round(self.firstSeen)), @"lastSeen": @(round(self.lastSeen))} mutableCopy];
    if (k == MMHistoryDisk) j[@"freeMB"] = mb;
    else {
        j[@"cpuPercent"] = cpu;
        j[k == MMHistoryMac ? @"memoryUsedMB" : @"footprintMB"] = mb;
    }
    if (k == MMHistoryAgent || k == MMHistoryServer) {
        MMProcKey key = self.key;
        j[@"pid"] = @(key.pid); j[@"start"] = @(key.startSec); j[@"key"] = MMProcKeyString(key);
        j[@"label"] = self.label ?: NSNull.null;
        j[@"id"] = self.ident ?: NSNull.null;
        j[@"gone"] = self.goneAt > 0 ? @(round(self.goneAt)) : NSNull.null;
    }
    if (k == MMHistoryAgent) {
        NSMutableArray *st = [NSMutableArray new];
        for (NSValue *v in self.stateChanges) {
            MMHistoryStateChange c; [v getValue:&c size:sizeof c];
            [st addObject:@{@"at": @(round(c.at)), @"state": StateWord(c.state)}];
        }
        j[@"states"] = st;
    }
    return j;
}

@end

@interface MMHistoryView ()
@property (readwrite) NSTimeInterval at;
@property (readwrite) uint32_t minute;
@property (readwrite) NSUInteger rings, refused, dropped, fills, storeBytes, copyBytes;
@property MMHistoryBuffer *buffer;
@end

/// A view holds only its buffer until something reads its rings, so a build that nobody reads costs one memcpy.
@implementation MMHistoryView {
    BOOL _made;
    MMHistoryRing *_mac, *_disk;
    NSArray<MMHistoryRing *> *_trees;
    NSArray<NSDictionary *> *_subagentStarts;
}

- (void)make {
    @synchronized (self) {
        if (_made) return;
        _made = YES;
        MMHistoryBuffer *b = self.buffer;
        NSMutableArray<MMHistoryRing *> *agents = [NSMutableArray new], *servers = [NSMutableArray new];
        for (NSUInteger i = 0; i < b->rings; i++) {
            MMHistoryRing *r = [MMHistoryRing new];
            r.data = b; r.index = i; r.viewMinute = self.minute; r.viewAt = self.at;
            switch (b.slots[i].kind) {
                case MMHistoryMac: _mac = r; break;
                case MMHistoryDisk: _disk = r; break;
                case MMHistoryAgent: [agents addObject:r]; break;
                case MMHistoryServer: [servers addObject:r]; break;
            }
        }
        NSSortDescriptor *byFirst = [NSSortDescriptor sortDescriptorWithKey:@"firstSeen" ascending:YES];
        [agents sortUsingDescriptors:@[byFirst]];
        [servers sortUsingDescriptors:@[byFirst]];
        _trees = [agents arrayByAddingObjectsFromArray:servers];
        NSMutableArray<NSDictionary *> *subs = [NSMutableArray new];
        for (NSUInteger i = 0; i < b->subs; i++) {
            const MMHistorySubagent *x = &b.subagents[i];
            [subs addObject:@{@"at": @(x->at), @"agent": Str(x->agent) ?: @"", @"session": Str(x->session) ?: @""}];
        }
        [subs sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:YES]]];
        _subagentStarts = subs;
    }
}

- (MMHistoryRing *)mac { [self make]; return _mac; }
- (MMHistoryRing *)disk { [self make]; return _disk; }
- (NSArray<MMHistoryRing *> *)trees { [self make]; return _trees; }
- (NSArray<NSDictionary *> *)subagentStarts { [self make]; return _subagentStarts; }

- (MMHistoryRing *)treeFor:(MMProcKey)key {
    for (MMHistoryRing *r in self.trees) if (r.key.pid == key.pid && r.key.startSec == key.startSec) return r;
    return nil;
}

- (NSDictionary *)json {
    NSMutableArray *agents = [NSMutableArray new], *servers = [NSMutableArray new];
    for (MMHistoryRing *r in self.trees) [(r.kind == MMHistoryAgent ? agents : servers) addObject:r.json];
    NSMutableArray *subs = [NSMutableArray new];
    for (NSDictionary *d in self.subagentStarts)
        [subs addObject:@{@"at": @(round([d[@"at"] doubleValue])), @"agent": d[@"agent"] ?: NSNull.null, @"session": d[@"session"] ?: NSNull.null}];
    return @{@"at": @(round(self.at)), @"minute": @(self.minute), @"minutes": @(MMHistoryMinutes),
             @"from": @((double)(self.minute - (MMHistoryMinutes - 1)) * 60),
             @"rings": @(self.rings), @"maxRings": @(MMHistoryMaxRings), @"refused": @(self.refused), @"dropped": @(self.dropped),
             @"fills": @(self.fills), @"storeBytes": @(self.storeBytes), @"copyBytes": @(self.copyBytes),
             @"goneKeepSeconds": @(MMHistoryGoneKeep),
             @"mac": self.mac.json ?: NSNull.null, @"disk": self.disk.json ?: NSNull.null,
             @"agents": agents, @"servers": servers, @"subagentStarts": subs};
}

@end

#pragma mark - The store

@implementation MMHistory {
    os_unfair_lock _lock;
    MMHistorySlot *_slots;                              // MMHistoryMaxRings, allocated once
    MMHistorySubagent *_subs;                           // MMHistoryMaxSubagents, allocated once
    void *_spare[2];                                    // copy buffers no view reads any more
    NSUInteger _subCount, _subNext;
    NSUInteger _refused, _dropped, _fills;
    MMHostLoad _lastLoad;
    MMHistoryView *_latest;
    id _eventsToken;
}

+ (instancetype)shared {
    static MMHistory *h; static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [MMHistory new]; });
    return h;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _lock = OS_UNFAIR_LOCK_INIT;
    // calloc hands out zero pages, so a slot never used costs no memory until a ring lands in it.
    _slots = calloc(MMHistoryMaxRings, sizeof(MMHistorySlot));
    _subs = calloc(MMHistoryMaxSubagents, sizeof(MMHistorySubagent));
    return self;
}

- (void)dealloc { free(_slots); free(_subs); free(_spare[0]); free(_spare[1]); }

- (void)recycle:(void *)bytes {
    os_unfair_lock_lock(&_lock);
    if (!_spare[0]) { _spare[0] = bytes; bytes = NULL; }
    else if (!_spare[1]) { _spare[1] = bytes; bytes = NULL; }
    os_unfair_lock_unlock(&_lock);
    free(bytes);
}

static NSUInteger StoreBytes(void) { return MMHistoryMaxRings * sizeof(MMHistorySlot) + MMHistoryMaxSubagents * sizeof(MMHistorySubagent); }

- (void)noteMacCPU:(double)cpuPercent memoryUsed:(uint64_t)used diskFree:(uint64_t)free at:(NSTimeInterval)t {
    os_unfair_lock_lock(&_lock);
    if (cpuPercent >= 0) {
        _slots[kMacSlot].kind = MMHistoryMac;
        AddValue(&_slots[kMacSlot], t, MIN(cpuPercent, 100), used / 1048576.0);
    }
    if (free > 0) {
        _slots[kDiskSlot].kind = MMHistoryDisk;
        AddValue(&_slots[kDiskSlot], t, -1, free / 1048576.0);
    }
    os_unfair_lock_unlock(&_lock);
}

/// Lock held. The slot of a tree with this kind and key, or a new one. -1 when 200 rings are live.
- (NSInteger)slotFor:(MMHistoryKind)kind key:(MMProcKey)key {
    NSInteger free = -1, oldestGone = -1;
    for (NSInteger i = kFirstTree; i < MMHistoryMaxRings; i++) {
        MMHistorySlot *s = &_slots[i];
        if (!s->kind) { if (free < 0) free = i; continue; }
        if (s->kind == kind && s->key.pid == key.pid && s->key.startSec == key.startSec) return i;
        if (s->goneAt > 0 && (oldestGone < 0 || s->goneAt < _slots[oldestGone].goneAt)) oldestGone = i;
    }
    NSInteger i = free >= 0 ? free : oldestGone;
    if (i < 0) return -1;
    if (free < 0) _dropped++;                           // a gone ring makes room before its ten minutes are up
    memset(&_slots[i], 0, sizeof(MMHistorySlot));
    _slots[i].kind = kind; _slots[i].key = key;
    return i;
}

- (void)noteTrees:(NSArray<MMHistoryTreeSample *> *)trees at:(NSTimeInterval)t {
    os_unfair_lock_lock(&_lock);
    BOOL seen[MMHistoryMaxRings] = {NO};
    for (MMHistoryTreeSample *x in trees) {
        if (x.kind != MMHistoryAgent && x.kind != MMHistoryServer) continue;
        NSInteger i = [self slotFor:x.kind key:x.key];
        if (i < 0) { _refused++; continue; }
        if (seen[i]) continue;                          // the same tree twice in one pass counts once
        seen[i] = YES;
        MMHistorySlot *s = &_slots[i];
        BOOL fresh = !s->firstSeen;
        s->goneAt = 0;
        Copy(s->label, sizeof s->label, x.label);
        Copy(s->ident, sizeof s->ident, x.ident);
        AddValue(s, t, MAX(x.cpuPercent, 0), x.footprint / 1048576.0);
        if (x.kind == MMHistoryAgent && (fresh || (uint8_t)x.state != s->lastState)) AddState(s, t, x.state);
    }
    for (NSInteger i = kFirstTree; i < MMHistoryMaxRings; i++) {
        MMHistorySlot *s = &_slots[i];
        if (!s->kind || seen[i]) continue;
        if (!s->goneAt) s->goneAt = t;
        else if (t - s->goneAt >= MMHistoryGoneKeep) { memset(s, 0, sizeof *s); _dropped++; }
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)noteSubagentStart:(NSString *)agent session:(NSString *)sessionID at:(NSTimeInterval)t {
    os_unfair_lock_lock(&_lock);
    MMHistorySubagent x = { .at = t };
    Copy(x.agent, sizeof x.agent, agent);
    Copy(x.session, sizeof x.session, sessionID);
    BOOL again = NO;                                    // a reconnect may hand the same event over twice
    for (NSUInteger i = 0; i < _subCount && !again; i++) {
        MMHistorySubagent *y = &_subs[i];
        again = y->at == x.at && !strcmp(y->session, x.session) && !strcmp(y->agent, x.agent);
    }
    if (!again) {
        _subs[_subNext] = x;
        _subNext = (_subNext + 1) % MMHistoryMaxSubagents;
        if (_subCount < MMHistoryMaxSubagents) _subCount++;
    }
    os_unfair_lock_unlock(&_lock);
}

- (MMHistoryView *)viewAt:(NSTimeInterval)t {
    MMHistoryView *v = [MMHistoryView new];
    v.at = t; v.minute = MinuteOf(t);
    v.storeBytes = StoreBytes();
    MMHistoryBuffer *b = [MMHistoryBuffer new];
    os_unfair_lock_lock(&_lock);
    void *bytes = _spare[0] ?: _spare[1];
    if (bytes == _spare[0]) _spare[0] = NULL; else _spare[1] = NULL;
    os_unfair_lock_unlock(&_lock);
    // A fresh buffer is touched only as far as a copy writes, so a store with few rings dirties few pages.
    if (!bytes) bytes = malloc(kBufferBytes);
    b->bytes = bytes;
    os_unfair_lock_lock(&_lock);
    MMHistorySlot *out = bytes;
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < MMHistoryMaxRings; i++) if (_slots[i].kind) out[n++] = _slots[i];
    MMHistorySubagent *subs = (MMHistorySubagent *)(out + n);
    NSUInteger k = 0, first = (_subNext + MMHistoryMaxSubagents - _subCount) % MMHistoryMaxSubagents;
    for (NSUInteger i = 0; i < _subCount; i++) {
        MMHistorySubagent *x = &_subs[(first + i) % MMHistoryMaxSubagents];
        if (x->at < t - MMHistoryMinutes * 60 || x->at > t) continue;
        subs[k++] = *x;
    }
    v.refused = _refused; v.dropped = _dropped; v.fills = _fills;
    os_unfair_lock_unlock(&_lock);
    b->rings = n; b->subs = k;
    b.owner = self;
    v.buffer = b;
    v.rings = n;
    v.copyBytes = n * sizeof(MMHistorySlot) + k * sizeof(MMHistorySubagent);
    return v;
}

- (MMHistoryView *)latest {
    os_unfair_lock_lock(&_lock);
    MMHistoryView *v = _latest;
    os_unfair_lock_unlock(&_lock);
    return v ?: [self viewAt:NSDate.date.timeIntervalSince1970];
}

- (MMHistoryView *)fillFrom:(MMSnapshot *)snap {
    NSTimeInterval t = NSDate.date.timeIntervalSince1970;
    MMHostLoad load = MMReadHostLoad();
    double cpu = -1;
    os_unfair_lock_lock(&_lock);
    if (_lastLoad.totalTicks && load.totalTicks > _lastLoad.totalTicks && load.busyTicks >= _lastLoad.busyTicks)
        cpu = 100.0 * (double)(load.busyTicks - _lastLoad.busyTicks) / (double)(load.totalTicks - _lastLoad.totalTicks);
    if (load.totalTicks) _lastLoad = load;
    _fills++;
    os_unfair_lock_unlock(&_lock);
    // Like MMGraph.m, a fill sends messages and checks for them, so a test may hand the graph facts of its own.
    MMPower *power = snap.facts.power;
    uint64_t diskFree = [power respondsToSelector:@selector(diskFree)] ? power.diskFree : 0;
    [self noteMacCPU:load.memoryUsed ? cpu : -1 memoryUsed:load.memoryUsed diskFree:diskFree at:t];

    NSMutableArray<MMHistoryTreeSample *> *trees = [NSMutableArray new];
    for (MMAgent *a in snap.facts.agents) {
        if (![a respondsToSelector:@selector(key)] || ![a respondsToSelector:@selector(state)]) continue;
        MMHistoryTreeSample *x = [MMHistoryTreeSample new];
        x.kind = MMHistoryAgent; x.key = a.key; x.state = a.state;
        x.cpuPercent = [a respondsToSelector:@selector(treeCPU)] ? a.treeCPU : 0;
        x.footprint = [a respondsToSelector:@selector(treeFootprint)] ? a.treeFootprint : 0;
        x.label = [a respondsToSelector:@selector(harnessID)] ? a.harnessID : nil;
        x.ident = [a respondsToSelector:@selector(sessionID)] ? a.sessionID : nil;
        [trees addObject:x];
    }
    for (MMFinding *f in [snap findingsFor:@"locohost"]) {
        if (![f.kind isEqualToString:@"server"] || !f.procs.count) continue;
        MMHistoryTreeSample *x = [MMHistoryTreeSample new];
        MMProcKey k; [f.procs.firstObject getValue:&k size:sizeof k];
        MMCost c = f.cost;
        x.kind = MMHistoryServer; x.key = k; x.cpuPercent = c.cpuPercent; x.footprint = c.ramBytes;
        x.label = f.title; x.ident = f.findingID;
        [trees addObject:x];
    }
    [self noteTrees:trees at:t];
    MMHistoryView *v = [self viewAt:t];
    os_unfair_lock_lock(&_lock);
    _latest = v;
    os_unfair_lock_unlock(&_lock);
    return v;
}

- (void)start {
    @synchronized (self) {
        if (_eventsToken) return;
        __weak MMHistory *weak = self;
        _eventsToken = [MMAgentEvents.shared observe:^(MMAgentEvent *e) {
            if (![e.event isEqualToString:@"SubagentStart"]) return;
            [weak noteSubagentStart:e.agent session:e.sessionID at:(e.at ?: NSDate.date).timeIntervalSince1970];
        }];
    }
}

- (void)stop {
    @synchronized (self) {
        if (_eventsToken) [MMAgentEvents.shared stopObserving:_eventsToken];
        _eventsToken = nil;
    }
}

@end
