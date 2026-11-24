// `minmacs device` and `minmacs quiet`, D9 parts 2 and 3: what this Mac can take on now, for a remote orchestrator
// such as BarkBot that picks a Mac for a task, and peace for a task that asks for it.
// device reads only what Core already holds: the last Senses pass and the graph's snapshot in the app, or one sample
// when no app runs. A few one-off reads on the verb itself, each microseconds to a few ms: sysctl for the hardware,
// the displays from CoreGraphics, the display-sleep setting from IOKit, host_statistics for memory, vm.swapusage and
// one proc_pid_rusage of MinMacs. It runs no process, never pmset, ps or lsof, and adds nothing to any tick.
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/sysctl.h>
#import <stdlib.h>
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#import "UI/MMFormat.h"

// From MMSelfCLI.m.
NSDictionary *MMSelfSinceLaunch(pid_t pid);
// IOKit exports it and pmset reads the same: the active power settings, by power source. No header declares it.
extern CFDictionaryRef IOPMCopyActivePMPreferences(void);

static id Or(id v) { return v ?: NSNull.null; }

static NSString *SysString(const char *name) {
    char buf[256]; size_t len = sizeof buf;
    return sysctlbyname(name, buf, &len, NULL, 0) == 0 && len > 0 ? [NSString stringWithUTF8String:buf] : nil;
}
static NSNumber *SysInt(const char *name) {
    int64_t v = 0; size_t len = sizeof v;
    if (sysctlbyname(name, &v, &len, NULL, 0) != 0) return nil;
    if (len == sizeof(int32_t)) return @((int32_t)v);
    return @(v);
}

static NSString *ThermalWord(NSProcessInfoThermalState t) {
    switch (t) {
        case NSProcessInfoThermalStateNominal: return @"nominal";
        case NSProcessInfoThermalStateFair: return @"fair";
        case NSProcessInfoThermalStateSerious: return @"serious";
        case NSProcessInfoThermalStateCritical: return @"critical";
    }
    return @"unknown";
}
/// A number with two decimals that JSON prints as written, 2.32 and not 2.3199999999999998.
static NSNumber *Two(double v) { return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.2f", v]]; }
static NSString *PressureWord(NSInteger p) { return p >= 4 ? @"critical" : p >= 2 ? @"warn" : @"normal"; }

#pragma mark - The parts

static NSDictionary *Identity(void) {
    NSString *computer = CFBridgingRelease(SCDynamicStoreCopyComputerName(NULL, NULL));
    NSString *local = CFBridgingRelease(SCDynamicStoreCopyLocalHostName(NULL));
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return @{@"computerName": Or(computer), @"localHostName": Or(local), @"model": Or(SysString("hw.model")),
             @"chip": Or(SysString("machdep.cpu.brand_string")),
             @"cores": @{@"physical": Or(SysInt("hw.physicalcpu")), @"logical": Or(SysInt("hw.logicalcpu")),
                         @"performance": Or(SysInt("hw.perflevel0.physicalcpu")), @"efficiency": Or(SysInt("hw.perflevel1.physicalcpu"))},
             @"memoryBytes": Or(SysInt("hw.memsize")),
             @"macOS": @{@"version": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion],
                         @"build": Or(SysString("kern.osversion"))},
             @"minmacs": @{@"version": @MM_VERSION, @"build": Or(info[@"CFBundleVersion"])}};
}

/// The display-sleep setting of the power source in use, in minutes, 0 for never. nil when it cannot be read.
static NSNumber *DisplaySleepMinutes(BOOL onAC) {
    NSDictionary *all = CFBridgingRelease(IOPMCopyActivePMPreferences());
    if (![all isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *mine = all[onAC ? @"AC Power" : @"Battery Power"] ?: all[@"AC Power"];
    id n = [mine isKindOfClass:NSDictionary.class] ? mine[@"Display Sleep Timer"] : nil;
    return [n isKindOfClass:NSNumber.class] ? n : nil;
}

/// The listening TCP ports of a process tree, ascending.
static NSArray<NSNumber *> *ListenPorts(MMSample *s, pid_t pid) {
    NSMutableSet<NSNumber *> *ports = [NSMutableSet new];
    for (NSNumber *p in [s treeOf:pid limit:500])
        for (NSValue *v in [s socketsOf:p.intValue]) {
            MMSocket k; [v getValue:&k size:sizeof k];
            if (k.state == MMSocketListen && k.localPort) [ports addObject:@(k.localPort)];
        }
    return [ports.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *AgentStateWord(MMAgentState st) {
    switch (st) {
        case MMAgentWorking: return @"working";
        case MMAgentWaiting: return @"waiting";
        case MMAgentIdle: return @"idle";
        default: return @"unknown";
    }
}

/// What holds the Mac awake now. In the app, MMAwake's pairs as Insomnia's last pass took them; with no app, nothing
/// of MinMacs's holds it, and Keep Mac Awake says only what the app would do. Other processes' assertions come from
/// the last Senses pass.
static NSDictionary *Awake(BOOL inApp, MMSnapshot *snap, MMPower *p, MMSample *s, NSArray<MMQuietHolder *> *quiet) {
    NSMutableArray *agents = [NSMutableArray new], *holds = [NSMutableArray new];
    BOOL manualHeld = NO;
    if (inApp) {
        NSDictionary *held = MMAwake.held, *asked = snap.awakeHolds ?: @{};
        for (NSString *k in [held.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            pid_t pid = (pid_t)[[k componentsSeparatedByString:@":"].firstObject intValue];
            if (pid == getpid()) { manualHeld = YES; continue; }
            NSDictionary *x = @{@"pid": @(pid), @"reason": held[k] ?: @""};
            if (asked[k]) [holds addObject:x]; else [agents addObject:x];
        }
    }
    NSMutableArray *quietOut = [NSMutableArray new];
    for (MMQuietHolder *h in quiet) [quietOut addObject:@{@"pid": @(h.key.pid), @"reason": h.reason ?: @"", @"awake": @(h.awake)}];
    // Every other process that asks the Mac or its display to stay up, as IOKit lists it.
    static NSSet *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kinds = [NSSet setWithArray:@[@"PreventUserIdleSystemSleep", @"PreventSystemSleep", @"PreventUserIdleDisplaySleep",
                                                          @"NoIdleSleepAssertion", @"NoDisplaySleepAssertion"]]; });
    NSMutableArray *others = [NSMutableArray new];
    for (NSNumber *pid in [p.assertionsByPid.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (pid.intValue == getpid()) continue;
        for (NSDictionary *x in p.assertionsByPid[pid]) {
            if (![x isKindOfClass:NSDictionary.class] || ![kinds containsObject:x[@"AssertType"] ?: @""]) continue;
            if (others.count >= 20) break;
            NSString *name = [s proc:pid.intValue].name ?: ([x[@"Process Name"] isKindOfClass:NSString.class] ? x[@"Process Name"] : nil);
            [others addObject:@{@"pid": pid, @"process": Or(name), @"type": x[@"AssertType"],
                                @"name": [x[@"AssertName"] isKindOfClass:NSString.class] ? x[@"AssertName"] : @""}];
        }
    }
    BOOL quietAwake = NO;
    for (MMQuietHolder *h in quiet) quietAwake = quietAwake || h.awake;
    BOOL manual = MMPrefBool(@"insomnia.awake", NO);
    return @{@"held": @((BOOL)(manualHeld || agents.count || holds.count || quietAwake)),
             @"manual": @(manual), @"manualHeld": @(manualHeld), @"agentsMode": @(MMPrefBool(@"insomnia.agents", YES)),
             @"agents": agents, @"holds": holds, @"quiet": quietOut, @"others": others,
             @"displaySleepMinutes": Or(DisplaySleepMinutes(p ? p.onAC : YES))};
}

static NSDictionary *Load(MMSnapshot *snap, MMPower *p) {
    MMHostLoad l = MMReadHostLoad();
    double avg[3] = {0, 0, 0};
    int n = getloadavg(avg, 3);
    // The whole Mac's CPU, the mean of this minute's graph builds, or the minute before. Only the app has it.
    id cpu = NSNull.null;
    MMHistoryRing *mac = snap.history.mac;
    for (NSUInteger i = 59; mac && i >= 58; i--) {
        MMHistoryMinute m = [mac minuteAt:i];
        if (m.passes > 0 && m.cpuPercent >= 0) { cpu = Two(m.cpuPercent); break; }
    }
    return @{@"memoryPressure": PressureWord(p ? p.memoryPressure : 1), @"memoryUsedBytes": @(l.memoryUsed),
             @"memoryTotalBytes": Or(SysInt("hw.memsize")), @"swapUsedBytes": @(MMClutterSwapUsed()),
             @"cpuPercent": cpu, @"loadAverage": n == 3 ? @[Two(avg[0]), Two(avg[1]), Two(avg[2])] : NSNull.null,
             @"diskFreeBytes": @(p.diskFree), @"diskTotalBytes": @(p.diskTotal)};
}

static NSDictionary *Agents(NSArray<MMAgent *> *all, MMSample *s) {
    NSMutableArray *list = [NSMutableArray new], *names = [NSMutableArray new];
    NSInteger working = 0;
    for (MMAgent *a in all) {
        BOOL w = a.state == MMAgentWorking;
        if (w) { working++; if (a.row.name.length && ![names containsObject:a.row.name]) [names addObject:a.row.name]; }
        [list addObject:@{@"pid": @(a.key.pid), @"name": a.row.name ?: a.harnessID ?: @"", @"harness": a.harnessID ?: @"",
                          @"state": AgentStateWord(a.state), @"working": @(w), @"ports": ListenPorts(s, a.key.pid)}];
    }
    return @{@"working": @(working), @"total": @(all.count), @"workingNames": names, @"list": list};
}

/// The whole report. Pure but for the one-off reads named at the top of the file.
static NSDictionary *DeviceReport(BOOL inApp) {
    MMSnapshot *snap = inApp ? MMGraph.shared.latest : nil;
    MMSample *s = snap.facts.sample;
    NSArray<MMAgent *> *agents = snap.facts.agents;
    if (!s) {
        // No graph to read, as in a CLI with no app: one sample, and the registry's agents in it.
        s = [MMSenses.shared sampleNow];
        agents = [MMRegistry.shared agentsIn:s power:MMSenses.shared.power] ?: @[];
    }
    MMPower *p = MMSenses.shared.power ?: snap.facts.power;
    BOOL lidMode = MMPrefBool(@"insomnia.lid", NO), screenOff = MMPrefBool(@"insomnia.lid.screenOff", YES);
    NSArray<MMDisplay *> *displays = MMDisplaysNow();
    MMDisplayState ds = MMDisplayStateFrom(displays, p.lidClosed, p.lidOverride, screenOff);
    NSMutableArray *dj = [NSMutableArray new];
    for (MMDisplay *d in displays) [dj addObject:d.json];
    NSArray<MMQuietHolder *> *quiet = MMQuietHolders();
    NSMutableArray *qj = [NSMutableArray new];
    for (MMQuietHolder *h in quiet) [qj addObject:h.json];
    // MinMacs's own cost: this process in the app, or the app's pid from its answer on core.sock.
    pid_t app = inApp ? getpid() : (pid_t)[[MMCoreSocket ask:@{@"verb": @"ping"} timeout:0.3][@"pid"] intValue];
    NSDictionary *cost = app > 0 ? MMSelfSinceLaunch(app) : nil;
    return @{
        @"schema": @1, @"at": @(round(NSDate.date.timeIntervalSince1970)), @"inApp": @(inApp),
        @"identity": Identity(),
        @"power": @{@"onAC": @((BOOL)(p ? p.onAC : YES)), @"batteryPercent": p && p.batteryPercent >= 0 ? @(p.batteryPercent) : NSNull.null,
                    @"lowPowerMode": @(p.lowPowerMode), @"thermal": ThermalWord(p ? p.thermal : NSProcessInfoThermalStateNominal),
                    @"online": @(p.online)},
        @"lid": @{@"closed": @(p.lidClosed), @"insomniaLidMode": @(lidMode), @"insomniaLidLive": @(p.lidOverride),
                  @"screenOff": @(screenOff), @"keepsScreenLit": @((BOOL)(lidMode && !screenOff))},
        @"display": @{@"active": MMDisplayActiveWord(ds), @"canCaptureScreen": @(ds.canCapture), @"known": @(ds.known),
                      @"builtinLit": @(ds.builtinLit), @"externalAwake": @(ds.externalAwake), @"displays": dj},
        @"awake": Awake(inApp, snap, p, s, quiet),
        @"load": Load(snap, p),
        @"agents": Agents(agents, s),
        @"quiet": @{@"active": @((BOOL)(quiet.count > 0)), @"holders": qj},
        @"minmacs": Or(cost),
    };
}

static int Device(MMArgs *a) {
    if (a.words.count) return [a usageError];
    NSDictionary *j = DeviceReport(a.inApp);
    if (a.json) { [a printJSON:j]; return MMExitOK; }
    NSDictionary *idn = j[@"identity"], *pw = j[@"power"], *lid = j[@"lid"], *disp = j[@"display"], *load = j[@"load"], *ag = j[@"agents"], *q = j[@"quiet"];
    [a print:@"%@, %@ %@, macOS %@, MinMacs %@ (%@)", idn[@"computerName"] != NSNull.null ? idn[@"computerName"] : @"This Mac", idn[@"model"], idn[@"chip"],
             idn[@"macOS"][@"version"], idn[@"minmacs"][@"version"], idn[@"minmacs"][@"build"]];
    [a print:@"Power:   %@%@, thermal %@%@", [pw[@"onAC"] boolValue] ? @"on AC" : @"on battery",
             pw[@"batteryPercent"] != NSNull.null ? [NSString stringWithFormat:@", battery %@%%", pw[@"batteryPercent"]] : @"", pw[@"thermal"],
             [pw[@"lowPowerMode"] boolValue] ? @", Low Power Mode" : @""];
    [a print:@"Lid:     %@%@", [lid[@"closed"] boolValue] ? @"closed" : @"open",
             [lid[@"insomniaLidMode"] boolValue] ? ([lid[@"insomniaLidLive"] boolValue] ? @", kept running by lid mode" : @", lid mode on, not live") : @""];
    [a print:@"Display: %@, %@", disp[@"active"], [disp[@"canCaptureScreen"] boolValue] ? @"a screen task can run" : @"no screen to capture"];
    [a print:@"Awake:   %@", [j[@"awake"][@"held"] boolValue] ? @"held awake by MinMacs" : @"MinMacs holds nothing"];
    [a print:@"Load:    memory %@, %@ used, %@ swap, %@ free on disk", load[@"memoryPressure"], MMBytes([load[@"memoryUsedBytes"] unsignedLongLongValue]),
             MMBytes([load[@"swapUsedBytes"] unsignedLongLongValue]), MMBytes([load[@"diskFreeBytes"] unsignedLongLongValue])];
    [a print:@"Agents:  %@ working of %@%@", ag[@"working"], ag[@"total"],
             [ag[@"workingNames"] count] ? [@": " stringByAppendingString:[ag[@"workingNames"] componentsJoinedByString:@", "]] : @""];
    [a print:@"Quiet:   %@", [q[@"active"] boolValue] ? MMQuietWhy() ?: @"active" : @"no hold"];
    return MMExitOK;
}

#pragma mark - quiet

static void PrintHolders(MMArgs *a) {
    NSArray<MMQuietHolder *> *hs = MMQuietHolders();
    if (a.json) {
        NSMutableArray *j = [NSMutableArray new];
        for (MMQuietHolder *h in hs) [j addObject:h.json];
        [a printJSON:@{@"active": @((BOOL)(hs.count > 0)), @"holders": j, @"kept": a.inApp ? MMQuietKept() : NSNull.null}];
        return;
    }
    if (!hs.count) { [a print:@"No quiet hold. Every expert acts as its mode says."]; return; }
    for (MMQuietHolder *h in hs)
        [a print:@"Quiet for %@, pid %d, since %@%@", h.reason, h.key.pid, MMAgo(h.since),
                 h.awake ? @", the Mac and display held awake" : @", nothing holds the Mac awake: MinMacs is not running"];
}

static int Quiet(MMArgs *a) {
    NSString *cmd = [a word:0];
    if (!cmd) { PrintHolders(a); return MMExitOK; }
    if (!([cmd isEqualToString:@"hold"] || [cmd isEqualToString:@"release"]) || a.words.count != 2) return [a usageError];
    NSString *w = [a word:1];
    pid_t pid = (pid_t)w.intValue;
    if (pid <= 0 || ![[NSString stringWithFormat:@"%d", pid] isEqualToString:w]) { [a error:@"%@ takes a pid", cmd]; return [a usageError]; }
    if ([cmd isEqualToString:@"release"]) {
        if (a.dryRun) { [a print:@"would end the quiet holds of pid %d", pid]; return MMExitOK; }
        NSUInteger n = MMQuietRelease(pid, @"cli");
        if (a.json) [a printJSON:@{@"released": @(n), @"pid": @(pid)}];
        else [a print:n ? @"Quiet for pid %d ended." : @"No quiet hold for pid %d.", pid];
        return n ? MMExitOK : MMExitFailed;
    }
    NSString *reason = [a option:@"--reason"];
    if ([a has:@"--reason"] && !reason.length) { [a error:@"--reason takes a text"]; return [a usageError]; }
    if (pid == 1 || pid == getpid()) { [a error:@"quiet: pid %d is never held", pid]; return MMExitFailed; }
    if (a.dryRun) { [a print:@"would keep quiet, and the Mac and display awake, until pid %d exits: %@", pid, reason ?: @"a task"]; return MMExitOK; }
    // The assertions live in the process that takes them, so the hold runs in the app.
    int need = [a needsApp];
    if (need) return need;
    NSString *rid = nil, *problem = MMQuietHold(pid, reason, @"cli", &rid);
    if (problem) { [a error:@"quiet: %@", problem]; return MMExitFailed; }
    if (a.json) [a printJSON:@{@"held": @(pid), @"reason": reason ?: @"a task", @"rid": Or(rid)}];
    else [a print:@"Quiet until pid %d exits: no expert acts on its own, and the Mac and display stay awake.", pid];
    return MMExitOK;
}

NSArray<MMVerbSpec *> *MMDeviceVerbs(void);
NSArray<MMVerbSpec *> *MMDeviceVerbs(void) {
    MMVerbSpec *device = [MMVerbSpec verb:@"device"
                                    usage:@"device [--json]   what this Mac can take on now, for a remote orchestrator: identity, power, lid and display, what keeps it awake, load, agents, quiet holds and MinMacs's own cost"
                                  mutates:NO run:^int(MMArgs *a) { return Device(a); }];
    device.reads = MMVerbReadsNoWorktrees;
    MMVerbSpec *quiet = [MMVerbSpec verb:@"quiet"
                                   usage:@"quiet [--json] | quiet hold <pid> [--reason <text>] | quiet release <pid> [--dry-run]   peace for a task such as a screen recording: while that process runs no expert acts on its own, and the Mac and display stay awake"
                                 mutates:NO run:^int(MMArgs *a) { return Quiet(a); }];
    quiet.reads = MMVerbReadsNoWorktrees;
    quiet.mutatingForms = @[@"hold", @"release"];
    return @[device, quiet];
}
