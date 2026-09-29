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
    @"com.anthropic.claudefordesktop", @"com.anthropic.*", @"com.openai.chat", @"com.openai.codex", @"com.raycast.macos",
    @"com.superduper.superwhisper",
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
    @"no.guerrilla.insomnia", @"no.guerrilla.minmacs", @"io.noo-noo.app", @"*noo-noo*",
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
    @"com.skype.skype", @"com.loom.desktop", @"com.facebook.archon", @"tv.parsec.www",
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

// Hosts whose tabs do nothing for the work. Closed when a browser is trimmed.
static NSString *const kDefaultNoise[] = {
    @"youtube.com", @"youtu.be", @"netflix.com", @"twitch.tv", @"kick.com", @"vimeo.com", @"disneyplus.com", @"max.com",
    @"hbomax.com", @"primevideo.com", @"tv.apple.com", @"open.spotify.com", @"soundcloud.com", @"suno.com",
    @"tiktok.com", @"instagram.com", @"facebook.com", @"x.com", @"twitter.com", @"reddit.com", @"pinterest.com", @"9gag.com",
    @"threads.net", @"bsky.app", @"tumblr.com",
    @"cnn.com", @"bbc.com", @"bbc.co.uk", @"nytimes.com", @"theguardian.com", @"vg.no", @"dagbladet.no", @"nrk.no", @"aftenposten.no",
    @"amazon.com", @"ebay.com", @"aliexpress.com", @"temu.com", @"komplett.no", @"finn.no", @"elkjop.no",
};
// Hosts that are the work. Never closed, whatever else matches.
static NSString *const kDefaultWork[] = {
    @"localhost", @"127.0.0.1", @"0.0.0.0", @"github.com", @"gitlab.com", @"bitbucket.org", @"githubusercontent.com",
    @"claude.ai", @"claude.com", @"anthropic.com", @"openai.com", @"chatgpt.com",
    @"vercel.com", @"vercel.app", @"netlify.app", @"netlify.com", @"cloudflare.com", @"hetzner.com", @"fly.io", @"render.com",
    @"aws.amazon.com", @"console.aws.amazon.com", @"cloud.google.com", @"azure.com",
    @"google.com", @"stackoverflow.com", @"developer.apple.com", @"developer.mozilla.org", @"npmjs.com", @"hex.pm", @"hexdocs.pm",
    @"pkg.go.dev", @"crates.io", @"pypi.org", @"docs.rs", @"figma.com", @"linear.app", @"notion.so", @"sentry.io", @"slack.com",
};
// Apps that listen on loopback for their own reasons (presence, device discovery), not for an agent.
static NSString *const kDefaultIgnoreServing[] = {
    @"com.hnc.Discord", @"com.spotify.client", @"com.tinyspeck.slackmacgap", @"us.zoom.xos", @"com.microsoft.teams2",
    @"com.valvesoftware.steam", @"com.apple.Music",
};
static const NSInteger kRulesVersion = 2;

@implementation MMRules {
    NSArray<NSString *> *_keep, *_close, *_noise, *_work, *_ignore;
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
- (NSArray<NSString *> *)noiseHosts { return _noise; }
- (NSArray<NSString *> *)workHosts { return _work; }
- (NSArray<NSString *> *)ignoreServing { return _ignore; }

#define ARR(c) [NSArray arrayWithObjects:c count:sizeof(c) / sizeof(*c)]
static NSArray *Strings(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }

static BOOL Match(NSString *pattern, NSString *bid) {
    if ([pattern hasPrefix:@"*"] && [pattern hasSuffix:@"*"] && pattern.length > 2)
        return [bid.lowercaseString containsString:[pattern substringWithRange:NSMakeRange(1, pattern.length - 2)].lowercaseString];
    if ([pattern hasSuffix:@"*"]) return [bid hasPrefix:[pattern substringToIndex:pattern.length - 1]];
    return [bid isEqualToString:pattern];
}
static BOOL HostMatch(NSString *rule, NSString *host) {
    return [host isEqualToString:rule] || [host hasSuffix:[@"." stringByAppendingString:rule]];
}

- (void)reload {
    NSData *d = [NSData dataWithContentsOfURL:self.fileURL];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class] || !Strings(j[@"keep"]) || !Strings(j[@"close"])) {
        _keep = ARR(kDefaultKeep); _close = ARR(kDefaultClose);
        _noise = ARR(kDefaultNoise); _work = ARR(kDefaultWork); _ignore = ARR(kDefaultIgnoreServing);
        [self save];
        return;
    }
    _keep = j[@"keep"]; _close = j[@"close"];
    NSDictionary *tabs = [j[@"tabs"] isKindOfClass:NSDictionary.class] ? j[@"tabs"] : @{};
    _noise = Strings(tabs[@"noise"]) ?: @[]; _work = Strings(tabs[@"work"]) ?: @[];
    _ignore = Strings(j[@"ignoreServing"]) ?: @[];
    if ([j[@"version"] integerValue] < kRulesVersion) [self mergeDefaults];
}

/// Upgrade path: add defaults the file has never seen. Never removes or moves a user's entry.
- (void)mergeDefaults {
    NSMutableArray *k = [_keep mutableCopy], *c = [_close mutableCopy];
    for (NSString *p in ARR(kDefaultKeep))  if ([self verdictFor:p] == MMUnsorted && ![k containsObject:p]) [k addObject:p];
    _keep = k;
    for (NSString *p in ARR(kDefaultClose)) if ([self verdictFor:p] == MMUnsorted && ![c containsObject:p]) [c addObject:p];
    _close = c;
    NSMutableArray *n = [_noise mutableCopy], *w = [_work mutableCopy], *i = [_ignore mutableCopy];
    for (NSString *h in ARR(kDefaultWork))  if (![w containsObject:h] && ![n containsObject:h]) [w addObject:h];
    for (NSString *h in ARR(kDefaultNoise)) if (![n containsObject:h] && ![w containsObject:h]) [n addObject:h];
    for (NSString *b in ARR(kDefaultIgnoreServing)) if (![i containsObject:b]) [i addObject:b];
    _noise = n; _work = w; _ignore = i;
    [self save];
}

- (void)save {
    NSDictionary *j = @{
        @"_comment": @"MinMacs rules. keep: never closed. close: quit on MinMacs (browsers are trimmed instead). A trailing * matches a prefix. "
                      "tabs.noise hosts are closed when a browser is trimmed; tabs.work hosts are never closed; a host matches its subdomains. "
                      "ignoreServing: apps whose local listeners do not mean an agent is using them. Anything not listed is left alone.",
        @"version": @(kRulesVersion),
        @"keep": _keep, @"close": _close,
        @"tabs": @{ @"noise": _noise, @"work": _work },
        @"ignoreServing": _ignore };
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [d writeToURL:self.fileURL atomically:YES];
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

- (NSString *)tabVerdictForHost:(NSString *)host {
    if (!host.length) return @"other";
    for (NSString *r in _work)  if (HostMatch(r, host)) return @"work";    // work wins over noise
    for (NSString *r in _noise) if (HostMatch(r, host)) return @"noise";
    return @"other";
}

- (void)moveHost:(NSString *)host toWork:(BOOL)toWork {
    NSMutableArray *n = [_noise mutableCopy], *w = [_work mutableCopy];
    [n removeObject:host]; [w removeObject:host];
    // A parent rule would still match; drop parents from the opposite list too.
    NSMutableArray *other = toWork ? n : w;
    [other filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *r, NSDictionary *_) { return !HostMatch(r, host); }]];
    [(toWork ? w : n) addObject:host];
    _noise = n; _work = w;
    [self save];
}
- (void)addWorkHost:(NSString *)host  { [self moveHost:host toWork:YES]; }
- (void)addNoiseHost:(NSString *)host { [self moveHost:host toWork:NO]; }

- (BOOL)ignoresServing:(NSString *)bundleID { return [_ignore containsObject:bundleID]; }
- (void)setIgnoresServing:(BOOL)ignore forBundleID:(NSString *)bundleID {
    NSMutableArray *i = [_ignore mutableCopy];
    [i removeObject:bundleID];
    if (ignore) [i addObject:bundleID];
    _ignore = i;
    [self save];
}

@end
