// MMGitConfigValues: what git makes of a config value, for MMGitConfig.m's parser. A bool and an int as config.c and
// parse.c read them, and issue #120's question for a file outside the repo: may a line here make every git command
// refuse the config? The keys every command reads are git_default_config's in git 2.39's config.c, which
// for-each-ref, status and the rest call: core.*, user.*, author.*, committer.*, i18n.*, branch.<key>, push.*,
// mailmap.*, advice.*, sparse.*, color.ui, color.pager, color.advice, pager.color and pack.compression and
// packSizeLimit, and attr.* of later gits. A key there is taken only as listed below, in values git 2.39 takes and
// later gits keep; any other key or value there, and a key with no value anywhere but a bool, may be refused.
// That reads more as refused than git does, which costs a cleanup and never a removal.
#import <Foundation/Foundation.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <strings.h>

/// git_config_int: git_parse_signed with int's range. strtoimax in any base it takes, then k, m or g in any case,
/// and nil past int range once that is applied, or for anything else.
NSNumber *MMGitConfigInt(NSString *v) {
    const char *s = v.UTF8String;
    if (!s || !*s) return nil;
    char *end;
    errno = 0;
    intmax_t n = strtoimax(s, &end, 0);
    if (errno == ERANGE || end == s) return nil;
    intmax_t f = !*end ? 1 : !strcasecmp(end, "k") ? 1 << 10 : !strcasecmp(end, "m") ? 1 << 20 : !strcasecmp(end, "g") ? 1 << 30 : 0;
    if (!f || (n < 0 && -INT_MAX / f > n) || (n > 0 && INT_MAX / f < n)) return nil;
    return @((long long)(n * f));
}

/// git_config_bool: no value is true, then true, yes, on, false, no, off and "" in any case, then git_config_int.
/// nil for what git refuses.
NSNumber *MMGitConfigBool(NSString *v) {
    if (!v) return @YES;
    NSString *l = v.lowercaseString;
    if ([@[@"true", @"yes", @"on"] containsObject:l]) return @YES;
    if ([@[@"false", @"no", @"off", @""] containsObject:l]) return @NO;
    NSNumber *n = MMGitConfigInt(v);
    return n ? @(n.longLongValue != 0) : nil;
}

/// What a key every command reads takes: b a bool; s any value; p a path, which ~user or %(prefix) can make git die
/// on; w: one of the words, as written; b: one of the words in any case, or a bool; bw: one of the words as written,
/// or a bool; i:lo:hi an int from lo to hi, or one of the words after them in any case.
static NSDictionary<NSString *, NSString *> *Kinds(void) {
    static NSDictionary *kinds; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *k = [NSMutableDictionary new];
        for (NSString *b in @[@"core.filemode", @"core.ignorecase", @"core.precomposeunicode", @"core.symlinks", @"core.bare",
                              @"core.quotepath", @"core.trustctime", @"core.preloadindex", @"core.protecthfs",
                              @"core.protectntfs", @"core.sparsecheckout", @"core.sparsecheckoutcone",
                              @"core.warnambiguousrefs", @"core.commitgraph", @"core.multipackindex", @"core.usereplacerefs",
                              @"user.useconfigonly", @"push.autosetupremote", @"push.followtags", @"color.pager",
                              @"pager.color", @"sparse.expectfilesoutsideofpatterns"]) k[b] = @"b";
        for (NSString *s in @[@"core.editor", @"core.pager", @"core.sshcommand", @"core.askpass", @"core.whitespace",
                              @"core.fsmonitor", @"core.eol", @"user.name", @"user.email", @"user.signingkey",
                              @"author.name", @"author.email", @"committer.name", @"committer.email",
                              @"i18n.commitencoding", @"i18n.logoutputencoding", @"mailmap.blob", @"attr.tree"]) k[s] = @"s";
        for (NSString *p in @[@"core.excludesfile", @"core.attributesfile", @"core.hookspath", @"mailmap.file"]) k[p] = @"p";
        [k addEntriesFromDictionary:@{
            @"core.autocrlf": @"b:input", @"core.safecrlf": @"b:warn", @"core.logallrefupdates": @"b:always",
            @"color.ui": @"b:never,always,auto", @"color.advice": @"b:never,always,auto", @"push.gpgsign": @"b:if-asked",
            @"push.default": @"w:nothing,matching,simple,upstream,tracking,current",
            @"branch.autosetupmerge": @"bw:always,inherit,simple", @"branch.autosetuprebase": @"w:never,local,remote,always",
            @"core.abbrev": @"i:4:40:auto", @"core.compression": @"i:-1:9", @"core.loosecompression": @"i:-1:9",
            @"pack.compression": @"i:-1:9"}];
        kinds = k;
    });
    return kinds;
}

/// YES when every git command reads this key, by git_default_config.
static BOOL Every(NSString *section, NSString *sub, NSString *key) {
    if ([@[@"core", @"user", @"author", @"committer", @"i18n", @"push", @"mailmap", @"advice", @"sparse", @"attr"] containsObject:section]) return YES;
    if (sub) return [section isEqualToString:@"color"] && [sub isEqualToString:@"advice"];   // color.advice.<slot>
    if ([section isEqualToString:@"branch"]) return YES;
    if ([section isEqualToString:@"color"]) return [@[@"ui", @"pager", @"advice"] containsObject:key];
    if ([section isEqualToString:@"pack"]) return [@[@"compression", @"packsizelimit"] containsObject:key];
    return [section isEqualToString:@"pager"] && [key isEqualToString:@"color"];
}

/// Issue #120: NO when this line of a file outside the repo may make git refuse the config for every command. value
/// is nil for a key with no =, lossy YES for a value not read as git reads it. An includeIf on hasconfig: is refused
/// when the file it names holds a remote's url, which is not looked at, so it is NO too.
BOOL MMGitConfigEveryOK(NSString *section, NSString *sub, NSString *key, NSString *value, BOOL lossy) {
    if ([section isEqualToString:@"includeif"]) return ![sub.lowercaseString hasPrefix:@"hasconfig:"];
    BOOL remoteBool = [section isEqualToString:@"remote"] && sub &&
                      [@[@"mirror", @"skipdefaultupdate", @"skipfetchall", @"prune", @"prunetags"] containsObject:key];
    if (!Every(section, sub, key)) return value || remoteBool;   // no value: a bool, or what git may refuse
    NSString *kind = sub ? nil : Kinds()[[NSString stringWithFormat:@"%@.%@", section, key]];
    if (!kind && [section isEqualToString:@"advice"] && !sub) kind = @"b";   // advice.<x>: a bool, or one git ignores
    if (!kind || lossy) return NO;
    NSArray<NSString *> *parts = [kind componentsSeparatedByString:@":"];
    NSArray<NSString *> *words = [parts.lastObject componentsSeparatedByString:@","];
    if ([kind isEqualToString:@"s"]) return value != nil;
    if ([kind isEqualToString:@"p"]) return value && ![value hasPrefix:@"%("] && (![value hasPrefix:@"~"] || [value hasPrefix:@"~/"]);
    if ([kind isEqualToString:@"b"]) return MMGitConfigBool(value) != nil;
    if ([parts[0] isEqualToString:@"b"]) return [words containsObject:value.lowercaseString] || MMGitConfigBool(value);
    if ([parts[0] isEqualToString:@"w"]) return value && [words containsObject:value];
    if ([parts[0] isEqualToString:@"bw"]) return [words containsObject:value ?: @""] || MMGitConfigBool(value);
    NSNumber *n = MMGitConfigInt(value);   // i:lo:hi[:words]
    if (parts.count > 3 && [[parts[3] componentsSeparatedByString:@","] containsObject:value.lowercaseString]) return YES;
    return n && n.longLongValue >= parts[1].longLongValue && n.longLongValue <= parts[2].longLongValue;
}
