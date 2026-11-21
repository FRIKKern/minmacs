// MMGitOutside, issue #120: the config files git reads outside the repo, read with MMGitConfig.m's parser, for the one
// question whether they can change a branch's upstream. Their keys are never merged into the answer: when they can
// change it, the upstream is not known, which keeps.
//
//   the files, in git's order                     which are read here
//   system                                        none with GIT_CONFIG_NOSYSTEM. Else the file of every git the
//                                                 person may run: Apple's share/git-core/gitconfig of the Command
//                                                 Line Tools, of Xcode and of the developer folder xcode-select names,
//                                                 and $GIT_CONFIG_SYSTEM, or with none /etc/gitconfig, Homebrew's
//                                                 and MacPorts' etc/gitconfig
//   XDG and global                                $GIT_CONFIG_GLOBAL alone when it is set, as git reads it. Else
//                                                 $XDG_CONFIG_HOME/git/config, ~/.config/git/config and ~/.gitconfig,
//                                                 ~ from $HOME
//   what they include                             include.path, and includeIf.<any>.path whatever its condition,
//                                                 ten files deep as git
//
//   what they hold                                the upstream
//   branch.<b>.remote or merge for this branch    not known
//   remote.<r>.url for this branch's remote, or   not known
//   a fetch line of it that maps the merge
//   a line git refuses, a file there and not      not known: git refuses, or reads what is not read here
//   read, an include not followed or too deep,
//   extensions or core.repositoryformatversion
//   anything else                                 as the repo's own config says: the usual user, includeIf for an
//                                                 email, a pull-request fetch line, another branch's keys
//
// The environment: MinMacs's own git gets HOME, GIT_CONFIG_GLOBAL, GIT_CONFIG_SYSTEM and GIT_CONFIG_NOSYSTEM from
// MinMacs's environment, MMGitEnvironment, and so do these reads. Config given in the environment,
// GIT_CONFIG_COUNT or GIT_CONFIG_PARAMETERS, is never passed to MinMacs's git, and is read after the repo's config,
// so it wins; when MinMacs's own environment holds any, as a CLI run from a shell that set it does, every upstream is
// not known. A shell's environment the app cannot see is not guessed at.
// Every file comes through load, parsed once per stamp, and what they say is worked out again only when one moved.
// A walk looks at them at most once a second; the fresh read before an action always does.
#import <Foundation/Foundation.h>
#include <time.h>
#include <unistd.h>

BOOL MMGitConfigFlattenAll(id items, id (^load)(NSString *path), NSMutableArray *out);   // MMGitConfig.m
BOOL MMGitConfigMayMap(NSArray *fetch, NSString *src);                                  // MMGitConfig.m

/// git_env_bool: @YES, @NO, or nil for a value git refuses.
static NSNumber *EnvBool(NSString *v) {
    if (!v) return @NO;
    NSString *l = v.lowercaseString;
    if ([@[@"true", @"yes", @"on"] containsObject:l]) return @YES;
    if ([@[@"false", @"no", @"off", @""] containsObject:l]) return @NO;
    NSScanner *sc = [NSScanner scannerWithString:l];
    long long n = 0;
    return [sc scanLongLong:&n] && sc.isAtEnd ? @(n != 0) : nil;
}

/// The files outside the repo in git's order, or nil when what env says cannot be followed here.
static NSArray<NSString *> *Files(NSDictionary<NSString *, NSString *> *env) {
    NSString *count = env[@"GIT_CONFIG_COUNT"];
    if (env[@"GIT_CONFIG_PARAMETERS"].length || (count.length && [count stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@"0"]].length)) return nil;
    NSMutableArray *files = [NSMutableArray new];
    NSNumber *nosystem = EnvBool(env[@"GIT_CONFIG_NOSYSTEM"]);
    if (!nosystem) return nil;
    if (!nosystem.boolValue) {
        NSMutableArray *dev = [@[@"/Library/Developer/CommandLineTools", @"/Applications/Xcode.app/Contents/Developer"] mutableCopy];
        char link[PATH_MAX];
        ssize_t n = readlink("/var/db/xcode_select_link", link, sizeof link - 1);
        if (n > 0) { link[n] = 0; [dev addObject:@(link)]; }
        for (NSString *d in dev) [files addObject:[d stringByAppendingPathComponent:@"usr/share/git-core/gitconfig"]];
        NSString *system = env[@"GIT_CONFIG_SYSTEM"];
        if (system && !system.isAbsolutePath) return nil;
        [files addObjectsFromArray:system ? @[system] : @[@"/etc/gitconfig", @"/opt/homebrew/etc/gitconfig",
                                                         @"/usr/local/etc/gitconfig", @"/opt/local/etc/gitconfig"]];
    }
    NSString *global = env[@"GIT_CONFIG_GLOBAL"];
    if (global) {
        if (!global.isAbsolutePath) return nil;
        [files addObject:global];
    } else {
        NSString *home = env[@"HOME"].isAbsolutePath ? env[@"HOME"] : NSHomeDirectory(), *xdg = env[@"XDG_CONFIG_HOME"];
        if (xdg.length && !xdg.isAbsolutePath) return nil;
        if (xdg.length) [files addObject:[xdg stringByAppendingPathComponent:@"git/config"]];
        [files addObject:[home stringByAppendingPathComponent:@".config/git/config"]];
        [files addObject:[home stringByAppendingPathComponent:@".gitconfig"]];
    }
    return files;
}

/// What the files say: @{unknown} when they cannot be followed, else {branches, remotes: {name: {url, fetch}}}. seen
/// gets the items of each file read, in order, an empty one as NSNull: when they are the very objects of lastSeen,
/// which the memo hands back until a stamp moves, the answer is last.
static NSDictionary *Summary(NSArray<NSString *> *files, id (^load)(NSString *path), NSMutableArray *seen,
                             NSArray *lastSeen, NSDictionary *last) {
    NSDictionary *unknown = @{@"unknown": @YES};
    if (!files) return unknown;
    id (^read)(NSString *) = ^id(NSString *p) {
        id items = [p isEqualToString:@"/dev/null"] ? @[] : load(p);   // git reads it as empty
        [seen addObject:[items isKindOfClass:NSArray.class] && ![items count] ? NSNull.null : items ?: NSNull.null];
        return items;
    };
    NSMutableArray<NSDictionary *> *segs = [NSMutableArray new];
    for (NSString *f in files) if (!MMGitConfigFlattenAll(read(f), read, segs)) return unknown;
    BOOL same = last && seen.count == lastSeen.count;
    for (NSUInteger i = 0; same && i < seen.count; i++) same = seen[i] == lastSeen[i];
    if (same) return last;
    NSMutableSet *branches = [NSMutableSet new];
    NSMutableDictionary *remotes = [NSMutableDictionary new];
    for (NSDictionary *seg in segs) {
        if (seg[@"bad"] || seg[@"wt"] || seg[@"version"]) return unknown;
        [branches addObjectsFromArray:[seg[@"b"] allKeys] ?: @[]];
        [seg[@"r"] enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *r, BOOL *stop) {
            NSMutableDictionary *m = remotes[name] ?: (remotes[name] = [NSMutableDictionary new]);
            if (r[@"url"]) m[@"url"] = @YES;
            if (r[@"fetch"]) m[@"fetch"] = [m[@"fetch"] ?: @[] arrayByAddingObjectsFromArray:r[@"fetch"]];
        }];
    }
    return @{@"branches": branches, @"remotes": remotes};
}

/// up, MMGitConfigUpstream's answer from the repo's own config for branch, or not known when a file outside the repo
/// can change it. load gives a config file's items as MMGitConfigUpstream's load does.
NSDictionary *MMGitOutsideUpstream(NSDictionary *up, NSString *branch, id (^load)(NSString *path)) {
    if (!up || up[@"unknown"]) return up;
    static NSArray *files; static dispatch_once_t once;
    dispatch_once(&once, ^{ files = Files(NSProcessInfo.processInfo.environment); });
    // A walk asks once per checkout, so the answer is kept for a second, which a pass of 1,500 checkouts fits in: no
    // file is looked at again for each. The fresh read before an action, on core.git.fresh, always looks again, and
    // Parsed then reads each file whatever its stamp. When it looks, the items load hands back stay the same objects
    // until a file's stamp moves, so what they say is worked out again only then.
    static NSArray *lastSeen; static NSDictionary *last, *kept; static uint64_t keptAt; static NSObject *lock;
    static dispatch_once_t made;
    dispatch_once(&made, ^{ lock = [NSObject new]; });
    BOOL fresh = !strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), "no.guerrilla.minmacs.core.git.fresh");
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    NSArray *wasSeen; NSDictionary *was, *s = nil;
    @synchronized (lock) { wasSeen = lastSeen; was = last; if (!fresh && kept && now - keptAt < NSEC_PER_SEC) s = kept; }
    if (!s) {
        NSMutableArray *seen = [NSMutableArray new];
        s = Summary(files, load, seen, wasSeen, was);
        @synchronized (lock) {
            kept = s; keptAt = now;
            if (!s[@"unknown"]) { last = s; lastSeen = seen; }
        }
    }
    NSDictionary *unknown = @{@"unknown": @YES};
    if (s[@"unknown"] || [s[@"branches"] containsObject:branch]) return unknown;
    NSString *remote = up[@"remote"];
    NSDictionary *r = remote ? s[@"remotes"][remote] : nil;
    if (r[@"url"] || (r && [remote isEqualToString:@"."])) return unknown;
    if (r[@"fetch"] && (!up[@"merge"] || MMGitConfigMayMap(r[@"fetch"], up[@"merge"]))) return unknown;
    return up;
}
