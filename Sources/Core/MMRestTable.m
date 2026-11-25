// The table of the rest of the memory, MMRest.h: which category a process falls in and the plain name a person knows
// it by. Rows, not ifs. The first row that matches wins: a process's name first, then where it runs from, then its
// parent. Names come as the kernel keeps them, at most 15 or 16 characters, so a row may give the whole name and a
// cut one matches it: "com.apple.WebKi" is com.apple.WebKit.WebContent.
// The names are the processes of the development Mac, a 16 GB MacBook Air running many dev agents, and the ones
// Apple documents for each kind. A process the table does not know falls back by its path: /System, /usr/libexec,
// /usr/sbin, /sbin and /Library/Apple are macOS's own, an app bundle is Everything else named by its app.
#import "Core/MMRest.h"

NSString *const MMRestMacOS = @"macos", *const MMRestDesktop = @"desktop", *const MMRestSpotlight = @"spotlight",
    *const MMRestSiri = @"siri", *const MMRestMedia = @"media", *const MMRestCloud = @"cloud", *const MMRestApple = @"apple",
    *const MMRestBrowsers = @"browsers", *const MMRestDeveloper = @"developer", *const MMRestSecurity = @"security", *const MMRestElse = @"else";

@interface MMRestKind ()
@property (readwrite, copy) NSString *key, *title, *about;
@end
@implementation MMRestKind
@end

#pragma mark - The categories

static const struct { __unsafe_unretained NSString *key, *title, *about; } kKinds[] = {
    {@"macos", @"macOS", @"macOS's own processes: the kernel, the window server and the system's daemons."},
    {@"desktop", @"Desktop and widgets", @"What macOS draws around your apps: the Dock, Control Center, notifications, widgets and the extensions that open with them."},
    {@"spotlight", @"Spotlight", @"Spotlight and its indexers, which read new and changed files so search finds them."},
    {@"siri", @"Siri and suggestions", @"Siri, Apple Intelligence and the suggestions macOS learns on this Mac."},
    {@"media", @"Photos and media", @"Photos' analysis of your library, video decoding and the graphics compilers apps call on."},
    {@"cloud", @"iCloud and accounts", @"iCloud, your accounts, Messages, FaceTime, AirDrop and Home, which keep this Mac in sync."},
    {@"apple", @"Apple apps in the background", @"Apple apps' helpers that run while the app itself is closed."},
    {@"browsers", @"Browser helpers", @"A browser's pages and helpers that run outside the browser's own row."},
    {@"developer", @"Developer tools", @"Developer tools in the background: language servers, Node, watchers, git and virtual machines."},
    {@"security", @"Security", @"Security checks: XProtect, privacy and permissions, and the system extensions of security tools."},
    {@"else", @"Everything else", @"Processes of no kind above, each named by the app or the folder it runs from."},
};

NSArray<MMRestKind *> *MMRestKinds(void) {
    static NSArray<MMRestKind *> *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray new];
        for (size_t i = 0; i < sizeof kKinds / sizeof kKinds[0]; i++) {
            MMRestKind *k = [MMRestKind new];
            k.key = kKinds[i].key; k.title = kKinds[i].title; k.about = kKinds[i].about;
            [a addObject:k];
        }
        kinds = a;
    });
    return kinds;
}

MMRestKind *MMRestKindOf(NSString *key) {
    for (MMRestKind *k in MMRestKinds()) if ([k.key isEqualToString:key]) return k;
    return nil;
}

#pragma mark - By name

// How a row matches a name: the whole name, its start, its end, or a part of it anywhere.
typedef NS_ENUM(uint8_t, Match) { Is = 0, Starts, Ends, Has };
typedef struct { __unsafe_unretained NSString *name; Match match; __unsafe_unretained NSString *key, *human; } NameRow;

static const NameRow kNames[] = {
    // macOS itself.
    {@"kernel_task", Is, @"macos", @"Kernel"},
    {@"launchd", Is, @"macos", nil},
    {@"WindowServer", Is, @"macos", @"Window server"},
    {@"logd", Is, @"macos", @"System log"},
    {@"runningboardd", Is, @"macos", nil},
    {@"cfprefsd", Is, @"macos", @"Settings store"},
    {@"distnoted", Is, @"macos", nil},
    {@"UserEventAgent", Is, @"macos", nil},
    {@"coreaudiod", Is, @"macos", @"Audio"},
    {@"bluetoothd", Is, @"macos", @"Bluetooth"},
    {@"airportd", Is, @"macos", @"Wi-Fi"},
    {@"locationd", Is, @"macos", @"Location"},
    {@"powerd", Is, @"macos", nil},
    {@"configd", Is, @"macos", nil},
    {@"fseventsd", Is, @"macos", @"File events"},
    {@"mDNSResponder", Is, @"macos", @"Bonjour and DNS"},
    {@"iconservicesagent", Is, @"macos", @"Icons"},
    {@"lsd", Is, @"macos", nil},
    {@"nsurlsessiond", Is, @"macos", @"Downloads"},
    {@"backupd", Is, @"macos", @"Time Machine"},
    {@"softwareupdated", Is, @"macos", @"Software Update"},
    {@"mobileassetd", Is, @"macos", nil},
    {@"spindump", Is, @"macos", nil},
    {@"ReportCrash", Is, @"macos", @"Crash reporter"},
    // The desktop: what macOS draws around the apps.
    {@"Dock", Is, @"desktop", nil},
    {@"DockHelper", Is, @"desktop", nil},
    {@"ControlCenter", Is, @"desktop", @"Control Center"},
    {@"NotificationCenter", Is, @"desktop", @"Notification Center"},
    {@"WindowManager", Is, @"desktop", @"Stage Manager"},
    {@"loginwindow", Is, @"desktop", @"Login window"},
    {@"SystemUIServer", Is, @"desktop", nil},
    {@"TextInputMenuAgent", Is, @"desktop", nil},
    {@"CoreServicesUIAgent", Is, @"desktop", nil},
    {@"chronod", Is, @"desktop", @"Widgets"},
    {@"WallpaperAgent", Is, @"desktop", @"Wallpaper"},
    {@"universalAccessd", Is, @"desktop", @"Accessibility"},
    // Spotlight.
    {@"Spotlight", Is, @"spotlight", nil},
    {@"mds", Is, @"spotlight", @"Spotlight server"},
    {@"mds_stores", Is, @"spotlight", @"Spotlight index"},
    {@"mdworker_shared", Is, @"spotlight", @"Spotlight indexer"},
    {@"mdworker", Is, @"spotlight", @"Spotlight indexer"},
    {@"mdsync", Is, @"spotlight", nil},
    {@"mdbulkimport", Is, @"spotlight", nil},
    {@"corespotlightd", Is, @"spotlight", @"Spotlight for apps"},
    {@"spotlightknowledged", Starts, @"spotlight", @"Spotlight knowledge"},
    // Siri, Apple Intelligence and suggestions.
    {@"assistantd", Is, @"siri", @"Siri"},
    {@"siri", Starts, @"siri", nil},
    {@"Siri", Starts, @"siri", nil},
    {@"suggestd", Is, @"siri", @"Suggestions"},
    {@"BiomeAgent", Is, @"siri", nil},
    {@"biomed", Is, @"siri", nil},
    {@"duetexpertd", Is, @"siri", nil},
    {@"routined", Is, @"siri", @"Significant locations"},
    {@"knowledge-agent", Is, @"siri", nil},
    {@"knowledgeconstructiond", Is, @"siri", nil},
    {@"intelligenceplatformd", Is, @"siri", @"Apple Intelligence"},
    {@"generativeexperiencesd", Is, @"siri", @"Apple Intelligence"},
    {@"modelmanagerd", Is, @"siri", @"Apple Intelligence models"},
    {@"textunderstandingd", Is, @"siri", nil},
    {@"proactived", Is, @"siri", nil},
    {@"coreduetd", Is, @"siri", nil},
    {@"triald", Is, @"siri", nil},
    {@"parsecd", Is, @"siri", nil},
    // Photos and media.
    {@"photoanalysisd", Is, @"media", @"Photos analysis"},
    {@"mediaanalysisd", Is, @"media", @"Media analysis"},
    {@"photolibraryd", Is, @"media", @"Photos library"},
    {@"VTDecoderXPCService", Is, @"media", @"Video decoder"},
    {@"VTEncoderXPCService", Is, @"media", @"Video encoder"},
    {@"MTLCompilerService", Is, @"media", @"Graphics compiler"},
    {@"mediaremoted", Is, @"media", nil},
    {@"AudioComponentRegistrar", Is, @"media", nil},
    // iCloud, accounts and messages.
    {@"cloudd", Is, @"cloud", @"iCloud"},
    {@"bird", Is, @"cloud", @"iCloud Drive"},
    {@"fileproviderd", Is, @"cloud", @"File providers"},
    {@"cloudphotod", Is, @"cloud", @"iCloud Photos"},
    {@"accountsd", Is, @"cloud", @"Accounts"},
    {@"identityservicesd", Is, @"cloud", @"Messages and FaceTime identity"},
    {@"imagent", Is, @"cloud", @"Messages"},
    {@"IMDPersistenceAgent", Is, @"cloud", @"Messages"},
    {@"callservicesd", Is, @"cloud", @"Calls"},
    {@"apsd", Is, @"cloud", @"Push notifications"},
    {@"sharingd", Is, @"cloud", @"AirDrop and Handoff"},
    {@"rapportd", Is, @"cloud", nil},
    {@"homed", Is, @"cloud", @"Home"},
    {@"akd", Is, @"cloud", @"Apple Account"},
    {@"CommCenter", Is, @"cloud", nil},
    {@"CloudKeychainProxy", Is, @"cloud", nil},
    {@"findmydeviced", Is, @"cloud", @"Find My"},
    {@"searchpartyd", Is, @"cloud", @"Find My"},
    {@"searchpartyuseragent", Is, @"cloud", @"Find My"},
    {@"itunescloudd", Is, @"cloud", nil},
    {@"remindd", Is, @"cloud", @"Reminders sync"},
    {@"calaccessd", Is, @"cloud", @"Calendar sync"},
    {@"contactsd", Is, @"cloud", @"Contacts"},
    {@"ScreenTimeAgent", Is, @"cloud", @"Screen Time"},
    {@"familycircled", Is, @"cloud", nil},
    // Browsers' helpers outside their browser's row.
    {@"com.apple.WebKit.WebContent", Is, @"browsers", @"Web page"},
    {@"com.apple.WebKit.Networking", Is, @"browsers", @"Web networking"},
    {@"com.apple.WebKit.GPU", Is, @"browsers", @"Web graphics"},
    {@"Google Chrome Helper", Starts, @"browsers", @"Chrome helper"},
    {@"Brave Browser Helper", Starts, @"browsers", @"Brave helper"},
    {@"Microsoft Edge Helper", Starts, @"browsers", @"Edge helper"},
    {@"Arc Helper", Starts, @"browsers", @"Arc helper"},
    {@"plugin-container", Is, @"browsers", @"Firefox content"},
    // Developer tools.
    {@"node", Is, @"developer", @"Node"},
    {@"bun", Is, @"developer", @"Bun"},
    {@"deno", Is, @"developer", @"Deno"},
    {@"clangd", Is, @"developer", @"C language server"},
    {@"sourcekit-lsp", Is, @"developer", @"Swift language server"},
    {@"SourceKitService", Is, @"developer", @"Swift language server"},
    {@"gopls", Is, @"developer", @"Go language server"},
    {@"rust-analyzer", Is, @"developer", @"Rust language server"},
    {@"watchman", Is, @"developer", @"Watchman"},
    {@"git", Is, @"developer", @"git"},
    {@"fsmonitor--daemon", Is, @"developer", @"git file watcher"},
    {@"docker", Starts, @"developer", @"Docker"},
    {@"com.docker.", Starts, @"developer", @"Docker"},
    {@"qemu-system-", Starts, @"developer", @"Virtual machine"},
    {@"vfkit", Is, @"developer", @"Virtual machine"},
    {@"limactl", Is, @"developer", @"Virtual machine"},
    {@"colima", Is, @"developer", @"Virtual machine"},
    {@"OrbStack Helper", Is, @"developer", @"OrbStack"},
    {@"XCBBuildService", Is, @"developer", @"Xcode build"},
    {@"CoreSimulatorService", Is, @"developer", @"Simulator"},
    {@"launchd_sim", Is, @"developer", @"Simulator"},
    {@"python3", Is, @"developer", @"Python"},
    {@"Python", Is, @"developer", @"Python"},
    {@"ruby", Is, @"developer", @"Ruby"},
    {@"java", Is, @"developer", @"Java"},
    {@"esbuild", Is, @"developer", nil},
    {@"tsserver", Is, @"developer", @"TypeScript server"},
    // Security.
    {@"XprotectService", Is, @"security", @"XProtect"},
    {@"XProtect", Starts, @"security", @"XProtect"},
    {@"syspolicyd", Is, @"security", @"Gatekeeper"},
    {@"tccd", Is, @"security", @"Privacy and permissions"},
    {@"trustd", Is, @"security", @"Certificates"},
    {@"securityd", Is, @"security", nil},
    {@"secd", Is, @"security", nil},
    {@"endpointsecurityd", Is, @"security", nil},
    {@"amfid", Is, @"security", nil},
    {@"sandboxd", Is, @"security", nil},
    {@"wdav", Starts, @"security", @"Microsoft Defender"},
    {@"falcond", Is, @"security", @"CrowdStrike"},
    {@"SentinelAgent", Is, @"security", @"SentinelOne"},
    // Last, a part of a name that says its kind: macOS names many small agents for what they serve.
    {@"Widget", Has, @"desktop", nil},
    {@"Spotlight", Has, @"spotlight", nil},
    {@"Intelligence", Has, @"siri", nil},
    {@"Prediction", Has, @"siri", nil},
    {@"speechrecognition", Has, @"siri", nil},
    {@"iCloud", Has, @"cloud", nil},
    {@"icloud", Starts, @"cloud", nil},
    {@"avconferenced", Is, @"cloud", @"FaceTime"},
    {@"Cloud", Has, @"cloud", nil},
    {@"Messages", Has, @"cloud", nil},
    {@"FaceTime", Has, @"cloud", nil},
    {@"home", Starts, @"cloud", nil},
    {@"Photo", Has, @"media", nil},
    {@"photo", Starts, @"media", nil},
};

/// A row's name matches the kernel's name of a process, which is cut at 15 or 16 characters.
static BOOL NameMatches(const NameRow *r, NSString *name) {
    switch (r->match) {
        case Is: return [name isEqualToString:r->name] || (name.length >= 15 && name.length < r->name.length && [r->name hasPrefix:name]);
        case Starts: return [name hasPrefix:r->name] || (name.length >= 15 && [r->name hasPrefix:name]);
        case Ends: return name.length > r->name.length && [name hasSuffix:r->name];
        case Has: return [name rangeOfString:r->name].location != NSNotFound;
    }
    return NO;
}

MMRestAnswer MMRestByName(NSString *name) {
    for (size_t i = 0; i < sizeof kNames / sizeof kNames[0]; i++)
        if (NameMatches(&kNames[i], name ?: @"")) return (MMRestAnswer){kNames[i].key, kNames[i].human, NO};
    return (MMRestAnswer){MMRestElse, nil, YES};
}

#pragma mark - By path

typedef struct { __unsafe_unretained NSString *part; Match match; __unsafe_unretained NSString *key; } PathRow;

// Starts means the path starts so, Is means it holds the part anywhere, Ends that it ends so.
static const PathRow kPaths[] = {
    // Security tools first: their paths sit under /Library and /Applications too.
    {@"/Library/SystemExtensions/", Starts, @"security"},
    {@"/Library/Application Support/Microsoft/Defender", Starts, @"security"},
    {@"/Applications/Microsoft Defender.app/", Starts, @"security"},
    {@"/Library/CS/", Starts, @"security"},
    {@"/Library/Sentinel/", Starts, @"security"},
    {@"/XprotectFramework.framework/", Is, @"security"},
    // Browsers' helper bundles, wherever they stand.
    {@"/Google Chrome Framework.framework/", Is, @"browsers"},
    {@"/WebKit.framework/", Is, @"browsers"},
    {@"/Brave Browser Framework.framework/", Is, @"browsers"},
    {@"/Microsoft Edge Framework.framework/", Is, @"browsers"},
    {@"/Firefox.app/", Is, @"browsers"},
    // Developer tools by where they install.
    {@"/Library/Developer/", Starts, @"developer"},
    {@"/Applications/Xcode", Starts, @"developer"},
    {@"/opt/homebrew/", Starts, @"developer"},
    {@"/usr/local/", Starts, @"developer"},
    {@"/.local/", Is, @"developer"},
    {@"/.nvm/", Is, @"developer"},
    {@"/.bun/", Is, @"developer"},
    {@"/.cargo/", Is, @"developer"},
    {@"/.volta/", Is, @"developer"},
    {@"/.pyenv/", Is, @"developer"},
    {@"/Applications/Docker.app/", Starts, @"developer"},
    {@"/Applications/OrbStack.app/", Starts, @"developer"},
    // macOS's own kinds by their frameworks.
    {@"/Metadata.framework/", Is, @"spotlight"},
    {@"/Spotlight.app/", Is, @"spotlight"},
    {@"/SiriInference.framework/", Is, @"siri"},
    {@"/AssistantServices.framework/", Is, @"siri"},
    {@"/Siri", Is, @"siri"},
    {@"/BiomeStreams.framework/", Is, @"siri"},
    {@"/CoreSuggestions.framework/", Is, @"siri"},
    {@"/IntelligencePlatform", Is, @"siri"},
    {@"/PhotoAnalysis.framework/", Is, @"media"},
    {@"/MediaAnalysis.framework/", Is, @"media"},
    {@"/PhotoLibraryServices.framework/", Is, @"media"},
    {@"/VideoToolbox.framework/", Is, @"media"},
    {@"/Metal.framework/", Is, @"media"},
    {@"/CloudDocs", Is, @"cloud"},
    {@"/CloudKit", Is, @"cloud"},
    {@"/IMCore.framework/", Is, @"cloud"},
    {@"/IMDPersistence.framework/", Is, @"cloud"},
    {@"/IDS.framework/", Is, @"cloud"},
    {@"/Accounts.framework/", Is, @"cloud"},
    {@"/HomeKitDaemon.framework/", Is, @"cloud"},
    {@"/FileProvider.framework/", Is, @"cloud"},
    {@"/TelephonyUtilities.framework/", Is, @"cloud"},
    {@"/TCC.framework/", Is, @"security"},
    // Widgets and the extensions macOS opens with its own panels.
    {@"Widget.appex/", Is, @"desktop"},
    {@"/System/Library/ExtensionKit/", Starts, @"desktop"},
    {@"/System/Library/CoreServices/Dock.app/", Starts, @"desktop"},
    {@"/System/Library/CoreServices/ControlCenter.app/", Starts, @"desktop"},
    {@"/System/Library/CoreServices/NotificationCenter.app/", Starts, @"desktop"},
    // Apple's apps, while the app itself is not a row.
    {@"/System/Applications/", Starts, @"apple"},
    {@"/System/Volumes/Preboot/Cryptexes/App/System/Applications/", Starts, @"apple"},
    {@"/System/Cryptexes/App/System/Applications/", Starts, @"apple"},
    {@"/System/iOSSupport/System/Library/CoreServices/", Starts, @"apple"},
    // The rest of macOS.
    {@"/System/", Starts, @"macos"},
    {@"/usr/libexec/", Starts, @"macos"},
    {@"/usr/sbin/", Starts, @"macos"},
    {@"/usr/bin/", Starts, @"macos"},
    {@"/sbin/", Starts, @"macos"},
    {@"/bin/", Starts, @"macos"},
    {@"/Library/Apple/", Starts, @"macos"},
};

static BOOL PathMatches(const PathRow *r, NSString *path) {
    switch (r->match) {
        case Starts: return [path hasPrefix:r->part];
        case Is: return [path rangeOfString:r->part].location != NSNotFound;
        case Ends: return [path hasSuffix:r->part];
        case Has: return [path rangeOfString:r->part].location != NSNotFound;
    }
    return NO;
}

/// The developer tools that run as an interpreter or a shell's child: their parent says what they are.
static const struct { __unsafe_unretained NSString *parent, *key; } kParents[] = {
    {@"node", @"developer"}, {@"bun", @"developer"}, {@"watchman", @"developer"}, {@"git", @"developer"},
    {@"zsh", @"developer"}, {@"bash", @"developer"}, {@"fish", @"developer"}, {@"make", @"developer"},
    {@"Docker", @"developer"}, {@"com.docker.backend", @"developer"},
};

MMRestAnswer MMRestClassify(NSString *name, NSString *path, NSString *parentName, BOOL mine) {
    MMRestAnswer a = MMRestByName(name);
    if (!a.needsPath) return a;
    a.needsPath = NO;
    if (path.length) {
        for (size_t i = 0; i < sizeof kPaths / sizeof kPaths[0]; i++)
            if (PathMatches(&kPaths[i], path)) { a.key = kPaths[i].key; return a; }
    }
    for (size_t i = 0; i < sizeof kParents / sizeof kParents[0]; i++)
        if ([parentName isEqualToString:kParents[i].parent]) { a.key = kParents[i].key; return a; }
    // A process another user runs with no path that says otherwise is macOS's own: no person's app runs as root.
    a.key = !mine && !path.length ? MMRestMacOS : MMRestElse;
    return a;
}

NSString *MMRestOwnerByPath(NSString *path) {
    if (!path.length) return nil;
    // The outermost app bundle names it: /Applications/Zoom.us.app/Contents/Frameworks/... is Zoom.us's.
    for (NSString *part in path.pathComponents)
        if ([part hasSuffix:@".app"] && part.length > 4) return [part substringToIndex:part.length - 4];
    NSString *folder = path.stringByDeletingLastPathComponent.lastPathComponent;
    return folder.length && ![folder isEqualToString:@"/"] ? folder : nil;
}
