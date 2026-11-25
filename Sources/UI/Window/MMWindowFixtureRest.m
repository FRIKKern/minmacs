// The rest of the memory on the render's made-up days, as the feed makes it, Shell/MMWindowRestFeed.m. The numbers of
// "rest" are those the development Mac held, a 16 GB MacBook Air running many dev agents, measured on 2026-11-25:
// macOS 2.1 GB in 499 processes, 280 of them another user's, Desktop and widgets 939 MB, iCloud 452 MB, Photos and
// media 430 MB, Siri 395 MB, Spotlight 325 MB. The names are the ones that Mac ran. Nothing else here is measured.
#import "UI/Window/MMWindowFixtureParts.h"

static const uint64_t MB = MMFixMB, GB = MMFixGB;

/// name, raw name or nil, megabytes, CPU in tenths or -1, launched by or nil, how many alike
typedef struct { __unsafe_unretained NSString *name, *raw; double mb; int cpu; __unsafe_unretained NSString *by; int many; } Proc;

static MMWindowRow *ProcRow(NSString *category, Proc p, int i, int n) {
    MMWindowRow *r = MMWindowFixtureRow(MMWindowSystem, [NSString stringWithFormat:@"insides:rest:%@|%d", category, 900 + i * 17 + n], p.name, category, nil,
                                        (uint64_t)(p.mb * MB), p.cpu < 0 ? 0 : p.cpu / 10.0);
    r.quiet = r.cpuPercent < 0.5;
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    if (p.raw) [facts addObject:MMWindowFactRawName(p.raw)];
    [facts addObject:MMWindowFactPid(900 + i * 17 + n)];
    MMWindowFact *by = MMWindowFactLaunchedBy(p.by);
    if (by) [facts addObject:by];
    [facts addObject:MMWindowFactParent(@"launchd", 1)];
    [facts addObject:MMWindowFactUp(3600 * (2 + i))];
    [facts addObject:MMWindowFactPath([NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/Support/%@", p.raw ?: p.name, p.raw ?: p.name])];
    r.facts = facts;
    return r;
}

/// One category as the feed makes it: its processes biggest first, the other user's ones after them with no size,
/// and macOS's memory in no process as a line of its own.
static MMWindowRow *Category(NSString *key, NSString *title, NSString *about, const Proc *procs, size_t count, int others, double unheldMB, NSString *tail) {
    MMWindowRow *row = MMWindowFixtureRow(MMWindowSystem, [@"rest:" stringByAppendingString:key], title, key, nil, 0, 0);
    row.about = about;
    NSMutableArray<MMWindowRow *> *members = [NSMutableArray new];
    double cpu = 0;
    uint64_t bytes = 0;
    for (size_t i = 0; i < count; i++) for (int n = 0; n < MAX(procs[i].many, 1); n++) {
        Proc p = procs[i];
        // Alike processes differ a little, as they do.
        p.mb = p.mb * (1 - 0.06 * n);
        MMWindowRow *m = ProcRow(key, p, (int)i, n);
        [members addObject:m]; bytes += m.bytes; cpu += m.cpuPercent;
    }
    int t = 0;
    for (NSString *item in [tail componentsSeparatedByString:@","]) {
        NSArray<NSString *> *nm = [item componentsSeparatedByString:@":"];
        if (nm.count != 2) continue;
        Proc p = {nm[0], nil, nm[1].doubleValue, 0, nil, 1};
        MMWindowRow *m = ProcRow(key, p, (int)count + t++, 0);
        [members addObject:m]; bytes += m.bytes;
    }
    if (unheldMB > 0) {
        MMWindowRow *u = MMWindowFixtureRow(MMWindowSystem, [NSString stringWithFormat:@"insides:rest:%@|unheld", key], @"Kernel and system memory", key, nil, (uint64_t)(unheldMB * MB), -1);
        u.quiet = YES; u.facts = @[MMWindowFactUnheld(u.bytes)];
        [members addObject:u]; bytes += u.bytes;
    }
    for (int n = 0; n < others; n++) {
        MMWindowRow *o = MMWindowFixtureRow(MMWindowSystem, [NSString stringWithFormat:@"insides:rest:%@|%d", key, 100 + n], @"root daemon", key, nil, 0, -1);
        o.unmeasured = YES; o.facts = @[MMWindowFactPid(100 + n), MMWindowFactOtherUser()];
        [members addObject:o];
    }
    [members sortUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
    row.members = members; row.bytes = bytes; row.cpuPercent = cpu; row.quiet = cpu < 0.5;
    NSInteger n = MMWindowRestProcessCount(row);
    NSString *growth = nil;
    row.state = growth ?: MMWindowRestCountWord(n);
    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    if (growth) [facts addObject:MMWindowFactGrowth(growth)];
    [facts addObject:MMWindowFactRestCount(n, others)];
    row.facts = facts;
    MMWindowRestOpens(row);
    return row;
}

#define N(a) (sizeof(a) / sizeof((a)[0]))

static const Proc kMacOS[] = {
    {@"Icons", @"iconservicesagent", 25, 0, nil, 1}, {@"AppleSpell", nil, 21, 0, nil, 1}, {@"universalAccessAuthWarn", nil, 19, 0, nil, 1},
    {@"AccessibilityUIServer", nil, 18, 0, nil, 1}, {@"UserNotificationCenter", nil, 17, 0, nil, 1}, {@"fontworker", nil, 16, 0, nil, 1},
    {@"passd", nil, 16, 0, nil, 1}, {@"appstoreagent", nil, 16, 0, nil, 1}, {@"amsengagementd", nil, 14, 0, nil, 1},
    {@"CursorUIViewService", nil, 14, 0, nil, 1}, {@"donotdisturbd", nil, 14, 0, nil, 1}, {@"peopled", nil, 13, 0, nil, 1},
    {@"transparencyd", nil, 13, 0, nil, 1}, {@"syncdefaultsd", nil, 13, 0, nil, 1}, {@"amsaccountsd", nil, 13, 0, nil, 1},
    {@"fontd", nil, 13, 0, nil, 1}, {@"com.apple.geod", nil, 12, 0, nil, 1}, {@"networkserviceproxy", nil, 12, 0, nil, 1},
    {@"usernoted", nil, 12, 2, nil, 1}, {@"nsattributedstringagent", nil, 12, 0, nil, 1}, {@"gamed", nil, 12, 0, nil, 1},
    {@"axassetsd", nil, 11, 0, nil, 1}, {@"corespeechd", nil, 11, 0, nil, 1}, {@"PowerChime", nil, 11, 0, nil, 1},
    {@"dataaccessd", nil, 11, 0, nil, 1}, {@"AccessibilityVisualsAgent", nil, 11, 0, nil, 1}, {@"UIKitSystem", nil, 11, 0, nil, 1},
    {@"studentd", nil, 11, 0, nil, 1}, {@"replayd", nil, 11, 0, nil, 1}, {@"heard", nil, 10, 0, nil, 1}, {@"tipsd", nil, 10, 0, nil, 1},
    {@"Downloads", @"nsurlsessiond", 10, 0, nil, 1}, {@"linkd", nil, 10, 0, nil, 1}, {@"Audio", @"coreaudiod", 12, 4, nil, 1},
    {@"Settings store", @"cfprefsd", 9, 1, nil, 1},
};
/// The other 213 processes of macOS on the measured Mac, by name and megabytes, smaller than those above.
static NSString *const kMacOSTail =
    @"AuthenticationServicesAgent:10,StatusKitAgent:10,shazamd:9,nbagent:9,intelligencecontextd:9,"
    @"SafariBookmarksSyncAgent:9,LocalAuthenticationRemoteService:9,universalaccessd:9,financed:9,"
    @"usernotificationsd:9,KonaSynthesizer:9,WiFiAgent:9,TextInputSwitcher:9,postersyncd:9,talagentd:9,"
    @"SoftwareUpdateNotificationManager:9,assistant_cdmd:9,intelligenceflowd:9,"
    @"com.apple.quicklook.ThumbnailsAgent:9,replicatord:9,newsd:8,MacinTalkAUSP:8,"
    @"com.apple.photos.ImageConversionService:8,UserEventAgent:8,AppSSOAgent:8,textcomposerd:8,audioaccessoryd:8,"
    @"FeatureAccessAgent:8,AMPLibraryAgent:8,UniversalControl:8,Crash reporter:8,avatarsd:8,translationd:8,"
    @"findmylocateagent:8,lsd:8,ShortcutsViewService:8,CoreLocationAgent:8,com.apple.siri.embeddedspeech:7,"
    @"promotedcontentd:7,adprivacyd:7,managedappdistributionagent:7,contactsdonationagent:7,mapssyncd:7,"
    @"naturallanguaged:7,communicationtrustd:7,UsageTrackingAgent:7,ContextStoreAgent:7,WardaSynthesizer:7,"
    @"appleaccountd:7,ContinuityCaptureAgent:7,AirPlayUIAgent:7,secinitd:7,ScreenTimeWidgetIntentsExtension:7,"
    @"SelectPerson_iOS:7,amsondevicestoraged:7,GamePolicyAgent:7,voicebankingd:6,BackgroundTaskManagementAgent:6,"
    @"ndoagent:6,milod:6,mediaanalysisd-access:6,liveactivitiesd:6,coreautha:6,followupd:6,PasswordBreachAgent:6,"
    @"CategoriesService:6,pkd:6,FPCKService:6,swtransparencyd:6,appplaceholdersyncd:6,"
    @"Keychain Circle Notification:6,coreauthd:6,mlhostd:6,SafariLaunchAgent:6,ModelCatalogAgent:6,"
    @"diagnostics_agent:6,com.apple.Safari.History:6,privatecloudcomputed:6,ContextService:5,frauddefensed:5,"
    @"bluetoothuserd:5,com.apple.sbd:5,TrialArchivingService:5,TrustedPeersHelper:5,distnoted:5,stickersd:5,"
    @"com.apple.Safari.SafeBrowsing.Service:5,IMTranscoderAgent:5,keyboardservicesd:5,ciphermld:5,"
    @"Managed Background Assets Helper Service:5,deleted:5,WallpaperControlsExtension:5,intelligentroutingd:5,"
    @"recentsd:5,cdpd:5,progressd:5,MauiAUSP:5,useractivityd:5,HubbleBlastDoorService:5,filevaultd:5,"
    @"inputanalyticsd:5,swcd:5,RemoteManagementAgent:5,jetpackassetd:5,dmd:5,imklaunchagent:5,mobiletimerd:5,"
    @"businessservicesd:5,AssetCacheLocatorService:5,MobileTimerIntents:5,PodcastContentService:5,webprivacyd:4,"
    @"sociallayerd:4,ContainerMetadataExtractor:4,seserviced:4,geoanalyticsd:4,ViewBridgeAuxiliary:4,"
    @"askpermissiond:4,sharedfilelistd:4,analyticsagent:4,appleaccounttransparencyd:4,SafariNotificationAgent:4,"
    @"ctkd:4,Settings store:4,pboard:4,dprivacyd:4,com.apple.StreamingUnzipService:4,devicecheckd:4,"
    @"AMPArtworkAgent:4,ASConfigurationSubscriber:4,EscrowSecurityAlert:4,neagent:4,SafariConfigurationSubscriber:4,"
    @"ScopedBookmarkAgent:4,AMPDeviceDiscoveryAgent:4,AccountSubscriber:4,extensionkitservice:4,"
    @"extensionkitservice:4,IDSBlastDoorService:4,MTLAssetUpgraderD:4,proactiveeventtrackerd:4,contentlinkingd:3,"
    @"extensionkitservice:3,com.apple.BKAgentService:3,ManagedSettingsAgent:3,ScreenSharingSubscriber:3,"
    @"containermanagerd:3,ManagedSettingsSubscriber:3,MENotificationAgent:3,assessmentagent:3,mobilerepaird:3,"
    @"SidecarRelay:3,SetStoreUpdateService:3,fskit_agent:3,icdd:3,SetStoreUpdateService:3,feedbackd:3,"
    @"extensionkitservice:3,SetStoreUpdateService:3,commerce:3,ctkahp:3,lockoutagent:3,ManagedAppsSubscriber:3,"
    @"findmydevice-user-agent:3,betaenrollmentagent:3,SetStoreUpdateService:3,CMFSyncAgent:3,pbs:3,"
    @"IntentsExtension:3,localizationswitcherd:3,SecuritySubscriber:3,InteractiveLegacyProfilesSubscriber:3,"
    @"backgroundassets.user:3,intelligencetasksd:3,maild:3,PasscodeSettingsSubscriber:3,ManagementTestSubscriber:3,"
    @"com.apple.audio.SandboxHelper:3,intents_helper:3,LegacyProfilesSubscriber:3,keychainsharingmessagingd:3,"
    @"BTLEServerAgent:3,com.apple.audio.SandboxHelper:3,CredentialProviderExtensionHelper:3,"
    @"com.apple.hiservices-xpcservice:2,APFSUserAgent:2,mlruntimed:2,colorsync.useragent:2,"
    @"com.apple.accessibility.mediaaccessibilityd:2,geodMachServiceBridge:2,ptpcamerad:2,installerauthagent:2,"
    @"mediaremoteagent:2,PlugInLibraryService:2,PlugInLibraryService:2,PlugInLibraryService:2,"
    @"PlugInLibraryService:2,com.apple.tonelibraryd:2,PlugInLibraryService:2,PlugInLibraryService:2,"
    @"PlugInLibraryService:2,PlugInLibraryService:2,spindump_agent:2,PlugInLibraryService:2,PlugInLibraryService:2,"
    @"PlugInLibraryService:2,PlugInLibraryService:2,PlugInLibraryService:2,PlugInLibraryService:2,"
    @"com.apple.ColorSyncXPCAgent:2,com.apple.ColorSyncXPCAgent:2,DiskUnmountWatcher:2";
static const Proc kDesktop[] = {
    {@"Notification Center", @"NotificationCenter", 132, 2, nil, 1}, {@"Control Center", @"ControlCenter", 65, 3, nil, 1},
    {@"TextThumbnailExtension", nil, 61, 0, nil, 1}, {@"NotificationsSettings", nil, 54, 0, @"System Settings", 1},
    {@"Login window", @"loginwindow", 46, 0, nil, 1}, {@"DisplaysExt", nil, 44, 0, @"System Settings", 1},
    {@"Dock", nil, 40, 1, nil, 1}, {@"Widgets", @"chronod", 31, 0, nil, 1}, {@"StocksWidget", nil, 25, 0, nil, 1},
    {@"WeatherWidget", nil, 21, 0, nil, 1}, {@"Stage Manager", @"WindowManager", 22, 0, nil, 1},
};
static const Proc kCloud[] = {
    {@"Accounts", @"accountsd", 31, 0, nil, 1}, {@"Messages", @"IMDPersistenceAgent", 27, 0, nil, 1},
    {@"Messages and FaceTime identity", @"identityservicesd", 25, 0, nil, 1}, {@"File providers", @"fileproviderd", 24, 0, nil, 1},
    {@"Home", @"homed", 23, 0, nil, 1}, {@"Calls", @"callservicesd", 22, 0, nil, 1}, {@"AirDrop and Handoff", @"sharingd", 21, 0, nil, 1},
    {@"Messages", @"imagent", 19, 0, nil, 1}, {@"iCloud", @"cloudd", 18, 1, nil, 1}, {@"iCloud Drive", @"bird", 14, 0, nil, 1},
};
static const Proc kMedia[] = {
    {@"Media analysis", @"mediaanalysisd", 77, 6, nil, 1}, {@"Video decoder", @"VTDecoderXPCService", 67, 0, @"Safari", 1},
    {@"Photos analysis", @"photoanalysisd", 50, 0, nil, 1}, {@"Photos library", @"photolibraryd", 41, 0, nil, 1},
    {@"Graphics compiler", @"MTLCompilerService", 30, 0, nil, 4},
};
static const Proc kSiri[] = {
    {@"Siri", @"assistantd", 29, 0, nil, 1}, {@"siriinferenced", nil, 26, 0, nil, 1}, {@"sirittsd", nil, 25, 0, nil, 1},
    {@"SiriNCService", nil, 24, 0, nil, 1}, {@"Suggestions", @"suggestd", 22, 0, nil, 1}, {@"BiomeAgent", nil, 22, 0, nil, 1},
    {@"Significant locations", @"routined", 20, 0, nil, 1}, {@"textunderstandingd", nil, 19, 0, nil, 1}, {@"duetexpertd", nil, 19, 0, nil, 1},
};
static const Proc kSpotlight[] = {
    {@"Spotlight", nil, 201, 1, nil, 1}, {@"Spotlight for apps", @"corespotlightd", 31, 0, nil, 1},
    {@"Spotlight knowledge", @"spotlightknowledged", 20, 0, nil, 1}, {@"Spotlight indexer", @"mdworker_shared", 6, 3, nil, 12},
};
static const Proc kBrowsers[] = {
    {@"Web page", @"com.apple.WebKit.WebContent", 160, 4, @"Safari", 3}, {@"Web networking", @"com.apple.WebKit.Networking", 31, 0, @"Safari", 1},
    {@"Chrome helper", @"Google Chrome Helper (Renderer)", 64, 2, @"Google Chrome", 2},
};
static const Proc kDeveloper[] = {
    {@"C language server", @"clangd", 132, 0, nil, 1}, {@"Node", @"node", 96, 12, nil, 3}, {@"Watchman", @"watchman", 38, 1, nil, 1},
    {@"git file watcher", @"fsmonitor--daemon", 14, 0, nil, 2},
};
static const Proc kApple[] = {
    {@"HomeEnergyWidgetsExtension", nil, 18, 0, nil, 1}, {@"CalendarWidgetExtension", nil, 16, 0, nil, 1}, {@"JournalWidgets", nil, 14, 0, nil, 1},
    {@"FindMyWidgetItems", nil, 13, 0, nil, 1}, {@"NotesWidgetExtension", nil, 12, 0, nil, 1},
};
static const Proc kSecurity[] = {
    {@"secd", nil, 12, 0, nil, 1}, {@"Certificates", @"trustd", 8, 0, nil, 1}, {@"Privacy and permissions", @"tccd", 8, 0, nil, 1},
};
static const Proc kElse[] = { {@"cmux-cua", nil, 7, 0, nil, 1} };

/// A calm hour of a category, or one that climbs from `from` to its size over the last 40 minutes.
static NSArray *Hour(uint64_t now, double from, NSString *key) {
    NSArray *flat = MMWindowFixtureHour(now, key, 0);
    if (from <= 0) return flat;
    NSMutableArray *v = [flat mutableCopy];
    for (NSInteger i = 0; i < 60; i++) {
        double t = MAX(0, (i - 20) / 39.0);
        v[i] = @((uint64_t)(from + (now - from) * t * t));
    }
    return v;
}

MMWindowGroup *MMWindowFixtureRest(NSString *day) {
    BOOL calm = [day isEqualToString:@"calm"], growing = [day isEqualToString:@"growing"];
    NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
    // The sentences are the table's, Core/MMRestTable.m, which the fixtures cannot link: test/window holds them alike.
    [rows addObject:Category(@"macos", @"macOS", @"macOS's own processes: the kernel, the window server and the system's daemons.",
                             kMacOS, N(kMacOS), calm ? 240 : 280, calm ? 420 : 506, calm ? nil : kMacOSTail)];
    [rows addObject:Category(@"desktop", @"Desktop and widgets", @"What macOS draws around your apps: the Dock, Control Center, notifications, widgets and the extensions that open with them.",
                             kDesktop, calm ? 6 : N(kDesktop), 0, 0, nil)];
    [rows addObject:Category(@"cloud", @"iCloud and accounts", @"iCloud, your accounts, Messages, FaceTime, AirDrop and Home, which keep this Mac in sync.", kCloud, N(kCloud), 2, 0, nil)];
    [rows addObject:Category(@"media", @"Photos and media", @"Photos' analysis of your library, video decoding and the graphics compilers apps call on.", kMedia, calm ? 3 : N(kMedia), 0, 0, nil)];
    [rows addObject:Category(@"siri", @"Siri and suggestions", @"Siri, Apple Intelligence and the suggestions macOS learns on this Mac.", kSiri, N(kSiri), 0, 0, nil)];
    MMWindowRow *spot = Category(@"spotlight", @"Spotlight", @"Spotlight and its indexers, which read new and changed files so search finds them.", kSpotlight, N(kSpotlight), 3, 0, nil);
    if (growing) {
        // A big checkout was cloned: twelve indexers read it, and Spotlight grew by 1.4 GB in the hour.
        for (MMWindowRow *m in spot.members) if ([m.name isEqualToString:@"Spotlight indexer"]) { m.bytes += 118 * MB; m.cpuPercent = 9; m.quiet = NO; }
        uint64_t b = 0; double c = 0;
        for (MMWindowRow *m in spot.members) { b += m.bytes; c += MAX(m.cpuPercent, 0); }
        spot.bytes = b; spot.cpuPercent = c; spot.quiet = NO;
        spot.hour = Hour(b, (double)b - 1.4 * GB, @"rest:spotlight");
        NSString *grew = MMWindowRestGrowth(spot.hour);
        spot.state = MMWindowRestGrowthWord(grew);
        spot.facts = @[MMWindowFactGrowth(grew), MMWindowFactRestCount(MMWindowRestProcessCount(spot), 3)];
        MMWindowRestOpens(spot);
    }
    [rows addObject:spot];
    if (!calm) {
        [rows addObject:Category(@"browsers", @"Browser helpers", @"A browser's pages and helpers that run outside the browser's own row.", kBrowsers, N(kBrowsers), 0, 0, nil)];
        [rows addObject:Category(@"developer", @"Developer tools", @"Developer tools in the background: language servers, Node, watchers, git and virtual machines.", kDeveloper, N(kDeveloper), 0, 0, nil)];
        [rows addObject:Category(@"apple", @"Apple apps in the background", @"Apple apps' helpers that run while the app itself is closed.", kApple, N(kApple), 0, 0, nil)];
        [rows addObject:Category(@"security", @"Security", @"Security checks: XProtect, privacy and permissions, and the system extensions of security tools.", kSecurity, N(kSecurity), 14, 0, nil)];
    }
    [rows addObject:Category(@"else", @"Everything else", @"Processes of no kind above, each named by the app or the folder it runs from.", kElse, N(kElse), 0, 0, nil)];
    // Busiest first, Everything else last, as the feed orders them.
    MMWindowRow *last = rows.lastObject;
    [rows removeLastObject];
    [rows sortUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
    [rows addObject:last];
    MMWindowGroup *g = [MMWindowGroup new];
    g.key = MMWindowRestGroup; g.title = MMWindowRestTitle; g.side = MMWindowMemory; g.rows = rows;
    return g;
}

/// The 16 GB MacBook Air of the measurement, with many agents: "rest", "rest-calm" and "rest-growing".
MMWindowModel *MMWindowFixtureRestDay(NSString *name) {
    BOOL calm = [name isEqualToString:@"rest-calm"];
    MMWindowModel *m = [MMWindowModel new];
    m.generation = 1;
    NSArray<MMWindowRow *> *servers = MMWindowFixtureServers(calm ? 2 : 5), *agents = MMWindowFixtureAgents(calm ? 2 : 12, calm ? 0 : 1), *apps = MMWindowFixtureApps(calm ? 5 : 9);
    // The agents of a 16 GB Mac are smaller than the busy day's of 64: as the measurement had them.
    for (MMWindowRow *r in agents) r.bytes = r.bytes / 3;
    for (MMWindowRow *r in apps) r.bytes = r.bytes / 2;
    for (MMWindowRow *r in [servers arrayByAddingObjectsFromArray:[agents arrayByAddingObjectsFromArray:apps]]) { r.inFix = NO; if ([r.state isEqualToString:@"will close"]) r.state = nil; }
    MMWindowGroup *rest = MMWindowFixtureRest(calm ? @"calm" : [name isEqualToString:@"rest-growing"] ? @"growing" : @"real");
    m.memoryGroups = @[MMWindowFixtureGroup(@"servers", @"Servers", MMWindowMemory, servers), MMWindowFixtureGroup(@"agents", @"Agents", MMWindowMemory, agents),
                       MMWindowFixtureGroup(@"apps", @"Apps and helpers", MMWindowMemory, apps), rest];
    m.diskGroups = @[MMWindowFixtureGroup(@"worktrees", @"Worktrees", MMWindowDisk, MMWindowFixtureWorktrees(calm ? 3 : 10, calm ? 1 : 3)),
                     MMWindowFixtureGroup(@"caches", @"Caches", MMWindowDisk, MMWindowFixtureCaches(calm ? 2 : 5))];
    for (MMWindowGroup *g in m.diskGroups) for (MMWindowRow *r in g.rows) r.inFix = NO;
    // Memory in use is what the groups and the rest hold, as the feed's ring adds them up: the rest is its last slice.
    // The made-up rows of the busy day are for 64 GB, so the groups are brought down to what 16 GB holds with the rest.
    uint64_t held = 0, restBytes = 0;
    for (MMWindowRow *r in rest.rows) restBytes += r.bytes;
    for (MMWindowGroup *g in m.memoryGroups) if (g != rest) for (MMWindowRow *r in g.rows) held += r.bytes;
    double room = (calm ? 11.6 : 15.1) * GB - restBytes;
    if (held > room) for (MMWindowGroup *g in m.memoryGroups) if (g != rest) for (MMWindowRow *r in g.rows) {
        double f = room / held;
        r.bytes = (uint64_t)(r.bytes * f);
        NSMutableArray *hour = [NSMutableArray new];
        for (id v in r.hour) [hour addObject:[v isKindOfClass:NSNumber.class] ? @((uint64_t)([v doubleValue] * f)) : v];
        if (r.hour) r.hour = hour;
    }
    held = 0;
    for (MMWindowGroup *g in m.memoryGroups) for (MMWindowRow *r in g.rows) held += r.bytes;
    MMWindowFixtureRing(m, held, 16 * GB, 182 * MMFixDiskGB, 494 * MMFixDiskGB);
    MMWindowHour *mem = [MMWindowHour new], *disk = [MMWindowHour new];
    mem.side = MMWindowMemory; mem.title = MMWindowHourTitle(NO); mem.explain = MMWindowHourExplain(NO, 16 * GB);
    mem.values = MMWindowFixtureHour((double)m.ring.memoryUsed, @"rest-mac", 2);
    disk.side = MMWindowDisk; disk.title = MMWindowHourTitle(YES); disk.explain = MMWindowHourExplain(YES, 494 * MMFixDiskGB);
    disk.values = MMWindowFixtureHour(182.0 * MMFixDiskGB, @"rest-disk", 0);
    m.memoryHour = mem; m.diskHour = disk;
    return m;
}
