// The MinMacs rules file. Ported from Rules.m on branch legacy, with the fixes for #43, #44 and #45.
// The file keeps 1.2's shape, so the migration's copy of an old rules file works unchanged.
// It lives in minmacs/rules.json and goes through MMStateFile, which locks it and writes by rename.
#import "Experts/MinMacs/MMMinMacs.h"
#import <sys/stat.h>

// Developer and agent essentials. Never quit, never even offered.
static NSString *const kDefaultKeep[] = {
    // terminals and multiplexers
    @"com.apple.Terminal", @"com.googlecode.iterm2", @"dev.warp.Warp-Stable", @"com.mitchellh.ghostty",
    @"net.kovidgoyal.kitty", @"org.alacritty", @"com.github.wez.wezterm", @"com.cmuxterm.app", @"com.cmux.*",
    // editors and IDEs
    @"com.microsoft.VSCode", @"com.microsoft.VSCodeInsiders", @"com.todesktop.230313mzl4w4u92",
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
    @"com.runningwithcrayons.Alfred", @"com.knollsoft.Rectangle", @"org.hammerspoon.Hammerspoon", @"com.apple.finder",
    @"com.apple.systempreferences", @"com.apple.ActivityMonitor", @"com.apple.Console",
    // the family
    @"no.guerrilla.insomnia", @"no.guerrilla.minmacs", @"io.noo-noo.app", @"*noo-noo*",
    @"com.apple.Passwords", @"com.apple.keychainaccess",
};
// Known performance hogs that do nothing for an agent. All reopen fine.
static NSString *const kDefaultClose[] = {
    // browsers, which restore their tabs on relaunch. They are trimmed unless minmacs.quitBrowsers is on.
    @"com.google.Chrome", @"com.google.Chrome.canary", @"org.chromium.Chromium", @"com.brave.Browser",
    @"company.thebrowser.Browser", @"com.apple.Safari", @"org.mozilla.firefox", @"com.microsoft.edgemac",
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
// Apps that listen on loopback for their own reasons, such as presence or device discovery, not for an agent.
static NSString *const kDefaultIgnoreServing[] = {
    @"com.hnc.Discord", @"com.spotify.client", @"com.tinyspeck.slackmacgap", @"us.zoom.xos", @"com.microsoft.teams2",
    @"com.valvesoftware.steam", @"com.apple.Music",
};
static const NSInteger kRulesVersion = 3;
#define ARR(c) [NSArray arrayWithObjects:c count:sizeof(c) / sizeof(*c)]

NSString *MMMinMacsVerdictName(MMMinMacsVerdict v) {
    switch (v) {
        case MMMinMacsKeep: return @"keep";
        case MMMinMacsClose: return @"close";
        case MMMinMacsUnsorted: return @"unsorted";
    }
    return @"unsorted";
}

NSInteger MMMinMacsVerdictFrom(NSString *name) {
    NSUInteger i = [@[@"keep", @"close", @"unsorted"] indexOfObject:name.lowercaseString ?: @""];
    return i == NSNotFound ? -1 : (NSInteger)i;
}

static NSArray *Strings(id v) {
    if (![v isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *out = [NSMutableArray new];
    for (id s in v) if ([s isKindOfClass:NSString.class]) [out addObject:s];
    return out;
}

/// 1.2's Match: *x* is a substring in any case, x* a prefix, anything else exact.
static BOOL Match(NSString *pattern, NSString *bid) {
    if (!pattern.length || !bid.length) return NO;
    if ([pattern hasPrefix:@"*"] && [pattern hasSuffix:@"*"] && pattern.length > 2)
        return [bid.lowercaseString containsString:[pattern substringWithRange:NSMakeRange(1, pattern.length - 2)].lowercaseString];
    if ([pattern hasSuffix:@"*"]) return [bid hasPrefix:[pattern substringToIndex:pattern.length - 1]];
    return [bid isEqualToString:pattern];
}
static BOOL HostMatch(NSString *rule, NSString *host) {
    return [host isEqualToString:rule] || [host hasSuffix:[@"." stringByAppendingString:rule]];
}
static BOOL IsDefaultApp(NSString *bid) { return [ARR(kDefaultKeep) containsObject:bid] || [ARR(kDefaultClose) containsObject:bid]; }

/// The lists of one load. Plain values, so a verdict never reads a half-written file.
@interface MMMinMacsLists : NSObject
@property (copy) NSArray<NSString *> *keep, *close, *unsorted, *noise, *work, *ignore;
@end
@implementation MMMinMacsLists
@end

/// An exact entry is an exception to every pattern. Then keep patterns, then close patterns.
static MMMinMacsVerdict VerdictIn(MMMinMacsLists *l, NSString *bid) {
    if ([l.keep containsObject:bid]) return MMMinMacsKeep;
    if ([l.close containsObject:bid]) return MMMinMacsClose;
    if ([l.unsorted containsObject:bid]) return MMMinMacsUnsorted;
    for (NSString *p in l.keep) if (Match(p, bid)) return MMMinMacsKeep;
    for (NSString *p in l.close) if (Match(p, bid)) return MMMinMacsClose;
    return MMMinMacsUnsorted;
}

static BOOL IgnoresIn(MMMinMacsLists *l, NSString *bid) {
    if ([l.ignore containsObject:[@"!" stringByAppendingString:bid]]) return NO;
    for (NSString *p in l.ignore) if (![p hasPrefix:@"!"] && Match(p, bid)) return YES;
    return NO;
}

static MMMinMacsLists *ListsFrom(id disk) {
    NSDictionary *j = [disk isKindOfClass:NSDictionary.class] ? disk : nil;
    if (!j || !Strings(j[@"keep"]) || !Strings(j[@"close"])) return nil;
    MMMinMacsLists *l = [MMMinMacsLists new];
    NSDictionary *tabs = [j[@"tabs"] isKindOfClass:NSDictionary.class] ? j[@"tabs"] : @{};
    l.keep = Strings(j[@"keep"]); l.close = Strings(j[@"close"]); l.unsorted = Strings(j[@"unsorted"]) ?: @[];
    l.noise = Strings(tabs[@"noise"]) ?: @[]; l.work = Strings(tabs[@"work"]) ?: @[];
    l.ignore = Strings(j[@"ignoreServing"]) ?: @[];
    return l;
}

static MMMinMacsLists *DefaultLists(void) {
    MMMinMacsLists *l = [MMMinMacsLists new];
    l.keep = ARR(kDefaultKeep); l.close = ARR(kDefaultClose); l.unsorted = @[];
    l.noise = ARR(kDefaultNoise); l.work = ARR(kDefaultWork); l.ignore = ARR(kDefaultIgnoreServing);
    return l;
}

/// #45. Adds each default the file does not mention, on every load, whatever the file's version.
/// Never removes or moves an entry. A default app the lists already decide, or that is on the unsorted list, is skipped.
/// So is an ignoreServing default with a !<bundle id> exception, and a host on either host list.
static BOOL MergeDefaults(MMMinMacsLists *l) {
    NSUInteger before = l.keep.count + l.close.count + l.noise.count + l.work.count + l.ignore.count;
    NSMutableArray *k = [l.keep mutableCopy], *c = [l.close mutableCopy];
    MMMinMacsLists *now = [MMMinMacsLists new];
    now.keep = k; now.close = c; now.unsorted = l.unsorted;
    for (NSString *p in ARR(kDefaultKeep)) {
        now.keep = k; now.close = c;
        if (VerdictIn(now, p) == MMMinMacsUnsorted && ![l.unsorted containsObject:p]) [k addObject:p];
    }
    for (NSString *p in ARR(kDefaultClose)) {
        now.keep = k; now.close = c;
        if (VerdictIn(now, p) == MMMinMacsUnsorted && ![l.unsorted containsObject:p]) [c addObject:p];
    }
    NSMutableArray *n = [l.noise mutableCopy], *w = [l.work mutableCopy], *i = [l.ignore mutableCopy];
    for (NSString *h in ARR(kDefaultWork)) if (![w containsObject:h] && ![n containsObject:h]) [w addObject:h];
    for (NSString *h in ARR(kDefaultNoise)) if (![n containsObject:h] && ![w containsObject:h]) [n addObject:h];
    for (NSString *b in ARR(kDefaultIgnoreServing))
        if (![i containsObject:b] && ![i containsObject:[@"!" stringByAppendingString:b]]) [i addObject:b];
    l.keep = k; l.close = c; l.noise = n; l.work = w; l.ignore = i;
    return l.keep.count + l.close.count + l.noise.count + l.work.count + l.ignore.count != before;
}

static NSDictionary *FileFrom(MMMinMacsLists *l, id disk) {
    NSMutableDictionary *j = [disk isKindOfClass:NSDictionary.class] ? [disk mutableCopy] : [NSMutableDictionary new];
    j[@"_comment"] = @"MinMacs rules. keep: never quit. close: quit by MinMacs; browsers are trimmed instead. "
                      "A trailing * matches a prefix and *text* matches inside the id. "
                      "An exact bundle id wins over any pattern, so com.adobe.Photoshop in keep is an exception to com.adobe.* in close. "
                      "unsorted: exact bundle ids that no pattern applies to; they are listed and never touched. "
                      "New defaults are added on every load. To stop a default from coming back, put it on the unsorted list. "
                      "tabs.noise hosts are closed when a browser is trimmed; tabs.work hosts are never closed; a host matches its subdomains. "
                      "ignoreServing: apps whose local listeners do not mean an agent uses them, matched like keep and close; "
                      "!<bundle id> is an exception to a pattern.";
    j[@"version"] = @(kRulesVersion);
    j[@"keep"] = l.keep; j[@"close"] = l.close; j[@"unsorted"] = l.unsorted;
    j[@"tabs"] = @{@"noise": l.noise, @"work": l.work};
    j[@"ignoreServing"] = l.ignore;
    return j;
}

@implementation MMMinMacsRules {
    MMStateFile *_file;
    MMMinMacsLists *_lists;
    struct timespec _mtime;
    off_t _size;
}

+ (instancetype)shared {
    static MMMinMacsRules *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ r = [MMMinMacsRules new]; r->_file = [MMStateFile fileNamed:@"rules" expert:@"minmacs"]; [r reload]; });
    return r;
}

- (NSString *)path { return _file.path; }

/// Loads under the file's lock. A missing or broken file gets the defaults. Writes only when something changed.
- (void)reload {
    __block MMMinMacsLists *loaded = nil;
    [_file update:^id(id disk) {
        MMMinMacsLists *l = ListsFrom(disk);
        if (!l) { loaded = DefaultLists(); return FileFrom(loaded, nil); }
        BOOL added = MergeDefaults(l);
        loaded = l;
        return added || [disk[@"version"] integerValue] != kRulesVersion ? FileFrom(l, disk) : nil;
    }];
    @synchronized (self) { _lists = loaded; [self stamp]; }
}

- (void)stamp {
    struct stat st;
    if (stat(_file.path.fileSystemRepresentation, &st) == 0) { _mtime = st.st_mtimespec; _size = st.st_size; }
}

/// The lists, read again when the file changed on disk, as when the CLI or the person edits it.
- (MMMinMacsLists *)lists {
    struct stat st;
    BOOL changed = stat(_file.path.fileSystemRepresentation, &st) != 0 || st.st_size != _size ||
                   st.st_mtimespec.tv_sec != _mtime.tv_sec || st.st_mtimespec.tv_nsec != _mtime.tv_nsec;
    if (changed) [self reload];
    @synchronized (self) { return _lists; }
}

/// One change under the file's lock, on what is on disk now.
- (void)change:(void (^)(MMMinMacsLists *l))block {
    __block MMMinMacsLists *after = nil;
    [_file update:^id(id disk) {
        MMMinMacsLists *l = ListsFrom(disk) ?: DefaultLists();
        MergeDefaults(l);
        block(l);
        after = l;
        return FileFrom(l, disk);
    }];
    @synchronized (self) { _lists = after; [self stamp]; }
}

- (NSArray<NSString *> *)keep { return self.lists.keep; }
- (NSArray<NSString *> *)close { return self.lists.close; }
- (NSArray<NSString *> *)unsorted { return self.lists.unsorted; }
- (NSArray<NSString *> *)noiseHosts { return self.lists.noise; }
- (NSArray<NSString *> *)workHosts { return self.lists.work; }
- (NSArray<NSString *> *)ignoreServing { return self.lists.ignore; }

- (MMMinMacsVerdict)verdictFor:(NSString *)bundleID { return bundleID.length ? VerdictIn(self.lists, bundleID) : MMMinMacsUnsorted; }

/// #43. A choice for one app changes only that app's exact entries. 1.2.0 removed every entry that matched,
/// so Keep on com.adobe.Photoshop dropped com.adobe.* from the close list for every Adobe app.
- (void)setVerdict:(MMMinMacsVerdict)v forBundleID:(NSString *)bid {
    if (!bid.length) return;
    [self change:^(MMMinMacsLists *l) {
        NSMutableArray *k = [l.keep mutableCopy], *c = [l.close mutableCopy], *u = [l.unsorted mutableCopy];
        [k removeObject:bid]; [c removeObject:bid]; [u removeObject:bid];
        if (v == MMMinMacsKeep) [k addObject:bid];
        if (v == MMMinMacsClose) [c addObject:bid];
        l.keep = k; l.close = c; l.unsorted = u;
        // Unsorted needs an entry when a pattern would still decide this app, or when it is a default
        // that the next load would add back.
        if (v == MMMinMacsUnsorted && (VerdictIn(l, bid) != MMMinMacsUnsorted || IsDefaultApp(bid))) { [u addObject:bid]; l.unsorted = u; }
    }];
}

- (NSString *)tabVerdictForHost:(NSString *)host {
    if (!host.length) return @"other";
    MMMinMacsLists *l = self.lists;
    for (NSString *r in l.work) if (HostMatch(r, host)) return @"work";
    for (NSString *r in l.noise) if (HostMatch(r, host)) return @"noise";
    return @"other";
}

- (void)moveHost:(NSString *)host toWork:(BOOL)toWork {
    if (!host.length) return;
    [self change:^(MMMinMacsLists *l) {
        NSMutableArray *n = [l.noise mutableCopy], *w = [l.work mutableCopy];
        [n removeObject:host]; [w removeObject:host];
        // A parent rule on the other list would still match, so it goes too.
        NSMutableArray *other = toWork ? n : w;
        [other filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *r, NSDictionary *b) { return !HostMatch(r, host); }]];
        [(toWork ? w : n) addObject:host];
        l.noise = n; l.work = w;
    }];
}
- (void)addWorkHost:(NSString *)host { [self moveHost:host toWork:YES]; }
- (void)addNoiseHost:(NSString *)host { [self moveHost:host toWork:NO]; }

/// #44. Matches like keep and close. 1.2.0 compared exactly, so com.adobe.* matched nothing here.
- (BOOL)ignoresServing:(NSString *)bundleID { return bundleID.length && IgnoresIn(self.lists, bundleID); }

/// #44 and #45. Changes only this app's own entries. Turning it off under a pattern, or for a default,
/// adds !<bundle id>, so the pattern stays for the others and the default does not come back.
- (void)setIgnoresServing:(BOOL)ignore forBundleID:(NSString *)bid {
    if (!bid.length) return;
    [self change:^(MMMinMacsLists *l) {
        NSString *except = [@"!" stringByAppendingString:bid];
        NSMutableArray *i = [l.ignore mutableCopy];
        [i removeObject:bid]; [i removeObject:except];
        l.ignore = i;
        if (ignore && !IgnoresIn(l, bid)) [i addObject:bid];
        if (!ignore && (IgnoresIn(l, bid) || [ARR(kDefaultIgnoreServing) containsObject:bid])) [i addObject:except];
        l.ignore = i;
    }];
}

@end
