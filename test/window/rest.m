// The rest of the memory, "macOS and background". Included by window.m, after collapse.m.
// The table is read with the names and paths of the development Mac, a 16 GB MacBook Air running many dev agents, as
// `ps` and proc_pidpath gave them on 2026-11-25. A fake sample then holds processes of each kind, and the feed, the
// fold, the order, the ring, the JSON and the closed window are checked on it. No path is read: the checks give their
// own reader, since a fake pid may be a real process on this Mac.
#import "Core/MMRest.h"
#import "UI/Window/MMWindowInsides.h"

static NSString *Kind(NSString *name, NSString *path, NSString *parent, BOOL mine) {
    MMRestAnswer a = MMRestClassify(name, path, parent, mine);
    return a.human.length ? [NSString stringWithFormat:@"%@ %@", a.key, a.human] : a.key;
}

static void RestTable(void) {
    // name, path, parent, mine, what the table says
    NSArray<NSArray *> *rows = @[
        @[@"kernel_task", @"", @"", @NO, @"macos Kernel"],
        @[@"WindowServer", @"/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", @"launchd", @NO, @"macos Window server"],
        @[@"launchd", @"/sbin/launchd", @"", @NO, @"macos"],
        @[@"logd", @"/usr/libexec/logd", @"launchd", @NO, @"macos System log"],
        @[@"coreaudiod", @"/usr/sbin/coreaudiod", @"launchd", @NO, @"macos Audio"],
        @[@"mds_stores", @"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mds_stores", @"launchd", @NO, @"spotlight Spotlight index"],
        @[@"mds", @"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mds", @"launchd", @NO, @"spotlight Spotlight server"],
        @[@"mdworker_shared", @"/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared", @"launchd", @YES, @"spotlight Spotlight indexer"],
        @[@"Spotlight", @"/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight", @"launchd", @YES, @"spotlight"],
        @[@"corespotlightd", @"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/corespotlightd", @"launchd", @YES, @"spotlight Spotlight for apps"],
        @[@"NotificationCenter", @"/System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter", @"launchd", @YES, @"desktop Notification Center"],
        @[@"ControlCenter", @"/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", @"launchd", @YES, @"desktop Control Center"],
        @[@"Dock", @"/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", @"launchd", @YES, @"desktop"],
        @[@"StocksWidget", @"/System/Applications/Stocks.app/Contents/PlugIns/StocksWidget.appex/Contents/MacOS/StocksWidget", @"launchd", @YES, @"desktop"],
        @[@"CalendarWidgetExtension", @"/System/Applications/Calendar.app/Contents/PlugIns/CalendarWidgetExtension.appex/Contents/MacOS/CalendarWidgetExtension", @"launchd", @YES, @"desktop"],
        @[@"TextThumbnailExtension", @"/System/Library/ExtensionKit/Extensions/TextThumbnailExtension.appex/Contents/MacOS/TextThumbnailExtension", @"launchd", @YES, @"desktop"],
        @[@"assistantd", @"/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Support/assistantd", @"launchd", @YES, @"siri Siri"],
        @[@"siriinferenced", @"/System/Library/PrivateFrameworks/SiriInference.framework/Versions/A/siriinferenced", @"launchd", @YES, @"siri"],
        @[@"BiomeAgent", @"/System/Library/PrivateFrameworks/BiomeStreams.framework/Support/BiomeAgent", @"launchd", @YES, @"siri"],
        @[@"AppleIntelligenceReportingProcessingService", @"/System/Library/PrivateFrameworks/X.framework/AppleIntelligenceReportingProcessingService", @"launchd", @YES, @"siri"],
        @[@"photoanalysisd", @"/System/Library/PrivateFrameworks/PhotoAnalysis.framework/Versions/A/Support/photoanalysisd", @"launchd", @YES, @"media Photos analysis"],
        @[@"VTDecoderXPCService", @"/System/Library/Frameworks/VideoToolbox.framework/Versions/A/XPCServices/VTDecoderXPCService.xpc/Contents/MacOS/VTDecoderXPCService", @"launchd", @YES, @"media Video decoder"],
        @[@"MTLCompilerService", @"/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService", @"launchd", @YES, @"media Graphics compiler"],
        @[@"accountsd", @"/System/Library/Frameworks/Accounts.framework/Versions/A/Support/accountsd", @"launchd", @YES, @"cloud Accounts"],
        @[@"identityservicesd", @"/System/Library/PrivateFrameworks/IDS.framework/identityservicesd.app/Contents/MacOS/identityservicesd", @"launchd", @YES, @"cloud Messages and FaceTime identity"],
        @[@"icloudwebd", @"/System/Library/PrivateFrameworks/X.framework/icloudwebd", @"launchd", @YES, @"cloud"],
        @[@"iCloudNotificationAgent", @"/System/Library/PrivateFrameworks/X.framework/iCloudNotificationAgent", @"launchd", @YES, @"cloud"],
        @[@"com.apple.WebKit.WebContent", @"/System/Volumes/Preboot/Cryptexes/Incoming/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", @"launchd", @YES, @"browsers Web page"],
        @[@"Google Chrome Helper (Renderer)", @"/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/158.0.8127.89/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", @"Google Chrome", @YES, @"browsers Chrome helper"],
        @[@"clangd", @"/Library/Developer/CommandLineTools/usr/bin/clangd", @"2.1.331", @YES, @"developer C language server"],
        @[@"node", @"/opt/homebrew/Cellar/node/25.1.0/bin/node", @"zsh", @YES, @"developer Node"],
        @[@"watchman", @"/opt/homebrew/bin/watchman", @"launchd", @YES, @"developer Watchman"],
        @[@"XprotectService", @"/System/Library/PrivateFrameworks/XprotectFramework.framework/Versions/A/XPCServices/XprotectService.xpc/Contents/MacOS/XprotectService", @"launchd", @NO, @"security XProtect"],
        @[@"tccd", @"/System/Library/PrivateFrameworks/TCC.framework/Support/tccd", @"launchd", @YES, @"security Privacy and permissions"],
        @[@"wdavdaemon_enterprise", @"/Library/Application Support/Microsoft/Defender/wdavdaemon_enterprise.app/Contents/MacOS/wdavdaemon_enterprise", @"launchd", @NO, @"security Microsoft Defender"],
        @[@"JournalWidgets", @"/System/Applications/Journal.app/Contents/PlugIns/JournalWidgets.appex/Contents/MacOS/JournalWidgets", @"launchd", @YES, @"desktop"],
        @[@"NotesHelper", @"/System/Applications/Notes.app/Contents/XPCServices/NotesHelper.xpc/Contents/MacOS/NotesHelper", @"launchd", @YES, @"apple"],
        // A name the kernel cut at 15 characters still finds its row.
        @[@"com.apple.WebKi", @"", @"launchd", @YES, @"browsers Web page"],
        @[@"Google Chrome H", @"", @"Google Chrome", @YES, @"browsers Chrome helper"],
        // Unknown processes fall back by their path, then their parent, never into a heap of their own.
        @[@"ptpcamerad", @"/System/Library/Image Capture/Support/ptpcamerad", @"launchd", @YES, @"macos"],
        @[@"ndoagent", @"/usr/libexec/ndoagent", @"launchd", @YES, @"macos"],
        @[@"ZoomHelper", @"/Applications/zoom.us.app/Contents/Frameworks/ZoomHelper.app/Contents/MacOS/ZoomHelper", @"launchd", @YES, @"else"],
        @[@"esbuild-x", @"/Users/x/.bun/install/cache/esbuild-x", @"launchd", @YES, @"developer"],
        @[@"my-tool", @"/Users/x/Code/my-tool/bin/my-tool", @"node", @YES, @"developer"],
        @[@"daemon-x", @"", @"launchd", @NO, @"macos"],
        @[@"daemon-x", @"", @"launchd", @YES, @"else"],
    ];
    NSMutableArray *wrong = [NSMutableArray new];
    for (NSArray *r in rows) {
        NSString *got = Kind(r[0], [r[1] length] ? r[1] : nil, [r[2] length] ? r[2] : nil, [r[3] boolValue]);
        if (![got isEqualToString:r[4]]) [wrong addObject:[NSString stringWithFormat:@"%@: %@, wanted %@", r[0], got, r[4]]];
    }
    T(@"rest: the table puts each real process of the development Mac in its category, with its plain name", @"", [wrong componentsJoinedByString:@"; "]);
    T(@"rest: a name the table knows needs no path, and one it does not asks for it", @"no yes",
      [NSString stringWithFormat:@"%@ %@", YN(MMRestByName(@"mds_stores").needsPath), YN(MMRestByName(@"ZoomHelper").needsPath)]);
    T(@"rest: an unknown process is named by the app or folder it runs from", @"zoom.us bin",
      [NSString stringWithFormat:@"%@ %@", MMRestOwnerByPath(@"/Applications/zoom.us.app/Contents/Frameworks/ZoomHelper.app/Contents/MacOS/ZoomHelper"), MMRestOwnerByPath(@"/Users/x/Code/my-tool/bin/my-tool")]);
    NSMutableArray *keys = [NSMutableArray new];
    for (MMRestKind *k in MMRestKinds()) [keys addObject:k.key];
    T(@"rest: eleven categories, Everything else last, each with a plain sentence", @"11 else yes", [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)keys.count, keys.lastObject,
      YN([[MMRestKinds() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"about.length < 20 OR about CONTAINS '...' OR about CONTAINS '('"]] count] == 0)]);
}

static TProc *RestProc(pid_t pid, NSString *name, uint64_t bytes, BOOL mine, double cpu) {
    TProc *p = [TProc new]; p.pid = pid; p.ppid = 1; p.startSec = 7; p.footprint = mine ? bytes : 0; p.uid = mine ? getuid() : 0; p.name = name; p.cpuPercent = cpu;
    gProcs[@(pid)] = p;
    return p;
}

/// A sample of every kind: twelve Spotlight indexers, a Spotlight, macOS's own daemons of root, a browser's pages, and
/// two processes no table row knows, one with a path that says developer.
static void RestWorld(void) {
    World();
    MMRestForget();
    NSDictionary *paths = @{@88001: @"/opt/homebrew/bin/mystery-tool", @88002: @"/Applications/Zoom.app/Contents/MacOS/zoomhelperx"};
    MMRestUsePathReader(^NSString *(pid_t pid) { return paths[@(pid)]; });
    for (int i = 0; i < 12; i++) RestProc(80000 + i, @"mdworker_shared", (uint64_t)(20 + i) * MB, YES, 0.5);
    RestProc(80100, @"Spotlight", 200 * MB, YES, 0.2);
    RestProc(80101, @"mds_stores", 0, NO, 0);
    RestProc(80200, @"WindowServer", 0, NO, 0);
    RestProc(80201, @"logd", 0, NO, 0);
    RestProc(80202, @"cfprefsd", 9 * MB, YES, 0);
    for (int i = 0; i < 4; i++) RestProc(80300 + i, @"com.apple.WebKi", (uint64_t)(150 - 10 * i) * MB, YES, 2);
    RestProc(80400, @"NotificationCenter", 130 * MB, YES, 0.1);
    RestProc(88001, @"mystery-tool", 40 * MB, YES, 1);
    RestProc(88002, @"zoomhelperx", 30 * MB, YES, 0);
}

static MMWindowGroup *RestOf(MMWindowModel *m) {
    for (MMWindowGroup *g in m.memoryGroups) if ([g.key isEqualToString:MMWindowRestGroup]) return g;
    return nil;
}

static void Rest(void) {
    RestTable();
    RestWorld();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowExtras *x = [MMWindowExtras readWithLogin:NO];
    MMWindowModel *m = MMWindowModelFrom(s, p, x);
    MMWindowGroup *rest = RestOf(m);
    NSArray *names = [rest.rows valueForKey:@"name"];
    T(@"rest: the window's left side ends with macOS and background", @"4 macOS and background", [NSString stringWithFormat:@"%lu %@", (unsigned long)m.memoryGroups.count, m.memoryGroups.lastObject.title]);
    T(@"rest: what no row holds is categorized, busiest first, Everything else last",
      @"macOS,Browser helpers,Spotlight,Desktop and widgets,Developer tools,Everything else", [names componentsJoinedByString:@","]);
    // The fixture rows the world already had, unclaimed, have no path and are their user's: Everything else.
    MMWindowRow *spot = [m row:@"rest:spotlight"], *mac = [m row:@"rest:macos"], *other = [m row:@"rest:else"];
    uint64_t indexers = 0;
    for (int i = 0; i < 12; i++) indexers += (uint64_t)(20 + i) * MB;
    T(@"rest: a category sums its processes' memory and CPU, and counts the ones another user runs",
      [NSString stringWithFormat:@"%llu 6.2 14 processes", indexers + 200 * MB], [NSString stringWithFormat:@"%llu %.1f %@", spot.bytes, spot.cpuPercent, spot.state]);
    MMWindowRestList *lines = MMWindowRestListOf(spot, 12);
    T(@"rest: twelve alike processes fold into one line under their plain name, the other user's apart",
      @"12 Spotlight indexers Spotlight 1", [NSString stringWithFormat:@"%@ %ld", [[lines.lines valueForKey:@"name"] componentsJoinedByString:@" "], (long)lines.unmeasured]);
    MMWindowRestList *two = MMWindowRestListOf([m row:@"rest:browsers"], 2);
    T(@"rest: four pages of one name fold, and a list with too little room says what is left", @"4 Web pages | 0 0",
      [NSString stringWithFormat:@"%@ | %ld %llu", [[two.lines valueForKey:@"name"] componentsJoinedByString:@","], (long)two.more, two.moreBytes]);
    MMWindowRestList *cut = MMWindowRestListOf(mac, 1);
    T(@"rest: macOS's memory in no process is a line of its own, and the rest say how many and how much", @"yes and 1 smaller, 9 MB",
      [NSString stringWithFormat:@"%@ %@", YN([cut.lines.firstObject.name isEqualToString:@"Kernel and system memory"] || cut.lines.count == 1), MMWindowRestMoreLine(cut.more, cut.moreBytes)]);
    T(@"rest: macOS counts its root daemons, which cannot be measured", @"3 2", [NSString stringWithFormat:@"%ld %ld", (long)MMWindowRestProcessCount(mac), (long)MMWindowRestListOf(mac, 12).unmeasured]);
    uint64_t sum = 0;
    for (MMWindowRow *r in rest.rows) sum += r.bytes;
    uint64_t otherPart = [p.memory.parts[MMPerformanceOther] unsignedLongLongValue];
    uint64_t unheld = 0;
    for (MMWindowRow *r in mac.members) if ([r.key hasSuffix:@"|unheld"]) unheld = r.bytes;
    T(@"rest: the categories add up to the ring's rest, macOS holding what no process does", @"yes",
      YN(sum == MAX(otherPart, sum - unheld)));
    T(@"rest: the ring's other slice is the rest's now", @"yes no", [NSString stringWithFormat:@"%@ %@",
      YN([[m.ring.memory valueForKey:@"group"] containsObject:MMWindowRestGroup]), YN([[m.ring.memory valueForKey:@"group"] containsObject:@"other"])]);
    BOOL unknownNamed = NO;
    for (MMWindowRow *r in other.members) if ([r.name isEqualToString:@"zoomhelperx"]) unknownNamed = YES;
    T(@"rest: an unknown app's helper goes to Everything else under its own name, a tool from Homebrew to developer tools", @"yes yes",
      [NSString stringWithFormat:@"%@ %@", YN(unknownNamed), YN([[[m row:@"rest:developer"].members valueForKey:@"name"] containsObject:@"mystery-tool"])]);

    // Its story's details are read only while it shows.
    BOOL path = NO;
    for (MMWindowRow *r in spot.members) for (MMWindowFact *f in r.facts) if ([f.label isEqualToString:@"Parent"] || [f.label isEqualToString:@"Path"]) path = YES;
    x.restStory = @"rest:developer";
    MMWindowModel *told = MMWindowModelFrom(s, p, x);
    BOOL devPath = NO, spotPath = NO;
    for (MMWindowRow *r in [told row:@"rest:developer"].members) for (MMWindowFact *f in r.facts) if ([f.label isEqualToString:@"Path"] && [f.value hasPrefix:@"/opt/homebrew"]) devPath = YES;
    for (MMWindowRow *r in [told row:@"rest:spotlight"].members) for (MMWindowFact *f in r.facts) if ([f.label isEqualToString:@"Path"]) spotPath = YES;
    T(@"rest: a process's path and parent are read only for the category whose story shows", @"no yes no", [NSString stringWithFormat:@"%@ %@ %@", YN(path), YN(devPath), YN(spotPath)]);

    // A process row of a category's tree tells its category's story, so its details are read the same way.
    (void)MMWindowRestStoryNow(nil);
    T(@"rest: a process row's story is its category's, and the same story again asks for nothing", @"yes no no",
      [NSString stringWithFormat:@"%@ %@ %@", YN(MMWindowRestStoryNow(@"insides:rest:developer|88001")), YN(MMWindowRestStoryNow(@"rest:developer")), YN(MMWindowRestStoryNow(@"server:3000"))]);
    (void)MMWindowRestStoryNow(nil);
    T(@"rest: a category opens in the list's tree into its lines", @"yes 2", [NSString stringWithFormat:@"%@ %lu",
      YN(MMWindowRowInsides(spot).count > 0), (unsigned long)MMWindowRowInsides(spot).count]);

    // Kept by pid and start time: a second model classifies nothing again, and a pid used again is looked up again.
    MMRestCounts a = MMRestCountsNow();
    (void)MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:NO]);
    MMRestCounts b = MMRestCountsNow();
    ((TProc *)gProcs[@88001]).startSec = 99;
    (void)MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:NO]);
    MMRestCounts c = MMRestCountsNow();
    T(@"rest: each process is classified once in its life, and a pid used again once more", @"0 1",
      [NSString stringWithFormat:@"%lu %lu", (unsigned long)(b.classified - a.classified), (unsigned long)(c.classified - b.classified)]);
    T(@"rest: a path is read only for a process its name does not place", @"yes", YN(a.pathsRead < a.classified));

    // The ring: eight slices at most, nothing lost.
    NSMutableArray<MMWindowRow *> *many = [NSMutableArray new];
    for (NSInteger i = 0; i < 11; i++) { MMWindowRow *r = [MMWindowRow new]; r.key = i == 10 ? MMWindowRestElseKey : [NSString stringWithFormat:@"rest:k%ld", (long)i]; r.bytes = (uint64_t)(100 - i) * MB; [many addObject:r]; }
    NSArray<MMWindowSlice *> *arcs = MMWindowRestArcs(many);
    uint64_t arcSum = 0;
    for (MMWindowSlice *sl in arcs) arcSum += sl.bytes;
    T(@"rest: the ring has at most 8 slices, the smallest merged into Everything else", @"8 rest:else yes 3",
      [NSString stringWithFormat:@"%lu %@ %@ %lu", (unsigned long)arcs.count, arcs.lastObject.group, YN(arcSum == 1045 * MB), (unsigned long)MMWindowRestArcs([many subarrayWithRange:NSMakeRange(8, 3)]).count]);

    // Quiet unless really unusual: a grown category says so, a calm one keeps its count.
    NSMutableArray *flat = [NSMutableArray new], *climb = [NSMutableArray new], *small = [NSMutableArray new];
    for (NSInteger i = 0; i < 60; i++) { [flat addObject:@(800 * MB)]; [climb addObject:@((uint64_t)(800 * MB + i * 25 * MB))]; [small addObject:@((uint64_t)(100 * MB + i * 5 * MB))]; }
    T(@"rest: only a category that grew by 512 MB and a third says so", @"- | up 1.44 GB this hour | -",
      [NSString stringWithFormat:@"%@ | %@ | %@", MMWindowRestGrowth(flat) ?: @"-", MMWindowRestGrowth(climb) ?: @"-", MMWindowRestGrowth(small) ?: @"-"]);

    // --json: the categories with their processes.
    NSDictionary *j = [MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:NO]) json];
    NSArray *cats = j[@"categories"];
    NSDictionary *spotJ = nil;
    for (NSDictionary *c2 in cats) if ([c2[@"key"] isEqualToString:@"spotlight"]) spotJ = c2;
    NSDictionary *root = nil;
    for (NSDictionary *pj in spotJ[@"processes"]) if ([pj[@"name"] isEqualToString:@"mds_stores"]) root = pj;
    T(@"rest: --json gives the categories with every process, an unmeasured one with a null size", @"6 14 Spotlight index null 0",
      [NSString stringWithFormat:@"%lu %@ %@ %@ %@", (unsigned long)cats.count, spotJ[@"count"], root[@"shownName"], root[@"bytes"] == NSNull.null ? @"null" : root[@"bytes"], root[@"measured"]]);
    NSData *data = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
    T(@"rest: the JSON is valid", @"yes", YN(data.length > 0));
    MMRestUsePathReader(^NSString *(pid_t pid) { return nil; });
}

/// With the window closed nothing of the rest runs: no snapshot builds a model, so no process is classified.
static void RestClosed(void) {
    RestWorld();
    MMSetPref(MMWindowWelcomedKey, @YES);
    MMWindowController *c = [MMWindowController new];
    __block NSInteger models = 0;
    c.onModel = ^(MMWindowModel *m) { models++; };
    MMRestCounts before = MMRestCountsNow();
    for (NSInteger g = 1; g <= 5; g++) [c take:SnapshotAt((uint64_t)g)];
    dispatch_sync(MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED), ^{});
    Spin(0.3, ^BOOL { return models > 0; });
    MMRestCounts after = MMRestCountsNow();
    NSDictionary *hours = MMWindowRestHours(NSDate.date.timeIntervalSince1970);
    T(@"rest: with the window closed, five snapshots classify nothing, read no path and keep no hour", @"0 0 0 0",
      [NSString stringWithFormat:@"%ld %lu %lu %lu", (long)models, (unsigned long)(after.classified - before.classified), (unsigned long)(after.pathsRead - before.pathsRead), (unsigned long)hours.count]);
    [c setOpen:YES];
    [c take:SnapshotAt(6)];
    Spin(20, ^BOOL { return models > 0; });
    dispatch_sync(MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED), ^{});
    MMRestCounts open = MMRestCountsNow();
    T(@"rest: open, the window classifies the rest and keeps its minute", @"yes yes",
      [NSString stringWithFormat:@"%@ %@", YN(open.classified > after.classified), YN(MMWindowRestHours(NSDate.date.timeIntervalSince1970).count > 0)]);
    [c setOpen:NO];
    MMRestUsePathReader(^NSString *(pid_t pid) { return nil; });
}
