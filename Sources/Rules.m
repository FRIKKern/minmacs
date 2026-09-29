#import "Rules.h"

// Developer and agent essentials. Never closed, never even offered.
static NSString *const kDefaultKeep[] = {
    // terminals and multiplexers
    @"com.apple.Terminal", @"com.googlecode.iterm2", @"dev.warp.Warp-Stable", @"com.mitchellh.ghostty",
    @"net.kovidgoyal.kitty", @"org.alacritty", @"com.github.wez.wezterm", @"com.cmuxterm.app", @"com.cmux.*",
    // editors and IDEs
    @"com.microsoft.VSCode", @"com.microsoft.VSCodeInsiders", @"com.todesktop.230313mzl4w4u92" /* Cursor */,
    @"dev.zed.Zed", @"com.apple.dt.Xcode", @"com.jetbrains.*", @"com.sublimetext.*", @"com.exafunction.windsurf",
    @"com.neovide.neovide", @"org.vim.MacVim",
    // AI and agent hosts
    @"com.anthropic.claudefordesktop", @"com.anthropic.*", @"com.openai.chat", @"com.raycast.macos",
    // containers, databases, dev services
    @"com.docker.docker", @"com.electron.dockerdesktop", @"dev.orbstack.OrbStack", @"com.postgresapp.Postgres2",
    @"com.tinyapp.TablePlus", @"com.sequel-ace.sequel-ace", @"com.getpostman.Postman", @"com.konghq.insomnia",
    @"org.mongodb.compass", @"com.redis.RedisInsight",
    // source control and utilities that agents rely on
    @"com.github.GitHubClient", @"com.fournova.Tower3", @"com.sourcetreeapp.*", @"com.tailscale.ipn.macos",
    @"com.1password.*", @"com.agilebits.onepassword*", @"com.bitwarden.desktop", @"org.pqrs.Karabiner*",
    @"com.runningwithcrayons.Alfred", @"com.knollsoft.Rectangle", @"org.hammerspoon.Hammerspoon", @"com.apple.finder", @"com.apple.systempreferences",
    @"com.apple.ActivityMonitor", @"com.apple.Console",
    // the family
    @"no.guerrilla.insomnia", @"no.guerrilla.minmacs", @"com.frikkern.noo-noo", @"no.guerrilla.noo-noo", @"*noo-noo*",
    @"com.apple.Passwords", @"com.apple.keychainaccess",
};
// Known performance hogs that do nothing for an agent. Closed on MinMacs. All reopen fine.
static NSString *const kDefaultClose[] = {
    // browsers (all restore their tabs on relaunch)
    @"com.google.Chrome", @"com.google.Chrome.canary", @"org.chromium.Chromium", @"com.brave.Browser",
    @"company.thebrowser.Browser" /* Arc */, @"com.apple.Safari", @"org.mozilla.firefox", @"com.microsoft.edgemac",
    @"com.vivaldi.Vivaldi", @"com.operasoftware.Opera",
    // media
    @"com.apple.Music", @"com.spotify.client", @"com.apple.TV", @"com.apple.podcasts", @"com.apple.Photos",
    @"com.apple.QuickTimePlayerX", @"org.videolan.vlc", @"com.colliderli.iina", @"com.apple.iBooksX", @"com.apple.news",
    // communication
    @"com.apple.MobileSMS", @"com.apple.FaceTime", @"com.apple.mail", @"us.zoom.xos", @"com.microsoft.teams2",
    @"com.hnc.Discord", @"ru.keepcoder.Telegram", @"net.whatsapp.WhatsApp", @"com.tinyspeck.slackmacgap",
    @"com.skype.skype", @"com.loom.desktop",
    // creative and heavy
    @"com.adobe.*", @"com.apple.FinalCut", @"com.apple.logic10", @"com.apple.garageband10", @"org.blenderfoundation.blender",
    @"com.figma.Desktop", @"com.bohemiancoding.sketch3", @"com.pixelmatorteam.pixelmator.x", @"com.affinity.*",
    @"com.canva.CanvaDesktop", @"notion.id", @"com.apple.Keynote", @"com.apple.Numbers", @"com.apple.Pages",
    @"com.microsoft.Word", @"com.microsoft.Excel", @"com.microsoft.Powerpoint", @"com.microsoft.Outlook",
    // games and stores
    @"com.valvesoftware.steam", @"com.epicgames.EpicGamesLauncher", @"com.apple.AppStore",
    // misc leisure
    @"com.apple.Maps", @"com.apple.stocks", @"com.apple.weather", @"com.apple.Preview", @"com.apple.Dictionary",
};

@implementation MMRules {
    NSArray<NSString *> *_keep, *_close;
}

+ (instancetype)shared { static MMRules *r; static dispatch_once_t o; dispatch_once(&o, ^{ r = [MMRules new]; [r reload]; }); return r; }

- (NSURL *)fileURL {
    NSURL *dir = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                  URLByAppendingPathComponent:@"MinMacs"];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:@"rules.json"];
}

- (NSArray<NSString *> *)keep { return _keep; }
- (NSArray<NSString *> *)close { return _close; }

static NSArray *Arr(NSString *const *c, size_t n) { return [NSArray arrayWithObjects:c count:n]; }

- (void)reload {
    NSData *d = [NSData dataWithContentsOfURL:self.fileURL];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class] || ![j[@"keep"] isKindOfClass:NSArray.class] || ![j[@"close"] isKindOfClass:NSArray.class]) {
        _keep = Arr(kDefaultKeep, sizeof(kDefaultKeep) / sizeof(*kDefaultKeep));
        _close = Arr(kDefaultClose, sizeof(kDefaultClose) / sizeof(*kDefaultClose));
        [self save];
        return;
    }
    _keep = j[@"keep"]; _close = j[@"close"];
}

- (void)save {
    NSDictionary *j = @{
        @"_comment": @"MinMacs rules. 'keep' apps are never closed. 'close' apps are quit on MinMacs. A trailing * matches a prefix. Anything else is listed as unsorted and never touched.",
        @"keep": _keep, @"close": _close };
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [d writeToURL:self.fileURL atomically:YES];
}

static BOOL Match(NSString *pattern, NSString *bid) {
    if ([pattern hasPrefix:@"*"] && [pattern hasSuffix:@"*"] && pattern.length > 2)
        return [bid.lowercaseString containsString:[pattern substringWithRange:NSMakeRange(1, pattern.length - 2)].lowercaseString];
    if ([pattern hasSuffix:@"*"]) return [bid hasPrefix:[pattern substringToIndex:pattern.length - 1]];
    return [bid isEqualToString:pattern];
}

- (MMVerdict)verdictFor:(NSString *)bundleID {
    for (NSString *p in _keep)  if (Match(p, bundleID)) return MMKeep;
    for (NSString *p in _close) if (Match(p, bundleID)) return MMClose;
    return MMUnsorted;
}

- (void)setVerdict:(MMVerdict)v forBundleID:(NSString *)bid {
    NSMutableArray *k = [_keep mutableCopy], *c = [_close mutableCopy];
    // Remove exact and pattern matches so the explicit choice wins.
    [k filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *_) { return !Match(p, bid); }]];
    [c filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *_) { return !Match(p, bid); }]];
    if (v == MMKeep) [k addObject:bid];
    if (v == MMClose) [c addObject:bid];
    _keep = k; _close = c;
    [self save];
}

@end
