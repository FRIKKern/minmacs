// MMGitConfig, issue #118: git's config files read as git's own reader reads them, for the one fact Know takes from
// them, the upstream of a branch. The parser follows git's config.c, git_parse_source, get_value, parse_value and
// get_base_var, and the upstream follows remote.c, handle_config, set_merge and remote_find_tracking.
//
//   what the file holds                           what the upstream is
//   a line git refuses: an unknown escape, an     not known: git refuses every command on that repo
//   open quote, a header with a space inside,
//   a key with no = and more after it
//   a value with no = where git needs one          not known: git refuses to read the remotes
//   (branch.x.merge, remote, remote.r.fetch,
//   url.x.insteadOf), a fetch or push line git
//   refuses, or a bool it refuses, past int
//   range too, in any remote
//   a remote, merge, fetch or include value with   not known: two such values that differ read the same here, and
//   bytes that are not UTF-8, or a tab inside      gits before 2.45 read a tab inside as a space
//   an [includeIf] path                            not known: its condition is not read here
//   an include.path                                followed, relative to its file, ten deep at most as git
//   extensions.worktreeConfig                      config.worktree of the checkout's git dir is read after config,
//                                                  when config itself holds core.repositoryformatversion 0 or 1;
//                                                  with none, or -1, git drops the extension; past 1, not known
//   a fetch line that is negative, or not          not known
//   src:dst with one * on each side or none
//   remote . with a merge not under refs/          not known: git looks the short name up
//   no remote or no merge                          none
//   remote and merge                               the ref the remote's fetch lines map the FIRST merge to, as
//                                                  git's @{upstream}; the LAST remote; none when no line maps it
//
// The files outside the repo, the system, XDG and global ones, are read in MMGitOutside.m, issue #120.
// Every function here reads no file: MMGitFacts.m hands each file over, parsed once per stamp.
#import <Foundation/Foundation.h>
#include <sys/stat.h>

NSString *MMGitText(const unsigned char *b, NSUInteger n, BOOL *lossy);   // MMGitFacts.m
NSDictionary *MMGitOutsideUpstream(NSDictionary *up, NSString *branch, id (^load)(NSString *path));   // MMGitOutside.m: #120
NSNumber *MMGitConfigBool(NSString *v);                                                             // MMGitConfigValues.m
NSNumber *MMGitConfigInt(NSString *v);
BOOL MMGitConfigEveryOK(NSString *section, NSString *sub, NSString *key, NSString *value, BOOL lossy);
BOOL MMGitConfigLaterOK(NSString *section, NSString *sub, NSString *key, NSString *value, BOOL lossy);

/// What git refuses, as a value of the items or of the upstream. Compared by pointer.
static NSString *const kBad = @"(git refuses it)";

#pragma mark - The parser, as config.c

typedef struct { const unsigned char *b; NSUInteger n, i; BOOL eof; } MMGitConfigSrc;

/// get_next_char: \r\n reads as \n, and the end reads as \n with eof set.
static int Next(MMGitConfigSrc *s) {
    if (s->i >= s->n) { s->eof = YES; return '\n'; }
    int c = s->b[s->i++];
    if (c == '\r' && s->i < s->n && s->b[s->i] == '\n') { s->i++; c = '\n'; }
    return c;
}

// git's own ctype: ASCII only, and space is \t, \n, \r and ' '.
static BOOL Space(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
static BOOL Alpha(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static BOOL KeyChar(int c) { return Alpha(c) || (c >= '0' && c <= '9') || c == '-'; }
static int Lower(int c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
static void Add(NSMutableData *d, int c) { unsigned char b = (unsigned char)c; [d appendBytes:&b length:1]; }

/// parse_value: quotes, the escapes \t \b \n \\ \" and a backslash before the line's end, a comment outside quotes,
/// and whitespace at the end trimmed. nil for what git refuses: another escape, or a quote still open at the end.
/// *blank turns YES when a tab or a lone \r outside quotes stays inside the value: git up to 2.44 reads it as a space,
/// and git 2.45 on keeps it as it is ("config: really keep value-internal whitespace verbatim"), so its meaning
/// depends on the git that reads it.
static NSMutableData *Value(MMGitConfigSrc *s, BOOL *blank) {
    BOOL quote = NO, comment = NO;
    NSUInteger trim = 0, odd = NSNotFound;
    NSMutableData *v = [NSMutableData new];
    for (;;) {
        int c = Next(s);
        if (c == '\n') {
            if (quote) return nil;
            if (trim) v.length = trim;
            *blank = odd < v.length;
            return v;
        }
        if (comment) continue;
        if (Space(c) && !quote) {
            if (!trim) trim = v.length;
            if (v.length && c != ' ' && odd == NSNotFound) odd = v.length;
            if (v.length) Add(v, c);
            continue;
        }
        if (!quote && (c == ';' || c == '#')) { comment = YES; continue; }
        trim = 0;
        if (c == '\\') {
            c = Next(s);
            switch (c) {
                case '\n': continue;
                case 't': c = '\t'; break;
                case 'b': c = '\b'; break;
                case 'n': c = '\n'; break;
                case '\\': case '"': break;
                default: return nil;
            }
            Add(v, c);
            continue;
        }
        if (c == '"') { quote = !quote; continue; }
        Add(v, c);
    }
}

/// get_extended_base_var: [section "subsection"], with \ before any byte standing for that byte.
static BOOL Extended(MMGitConfigSrc *s, NSMutableData *name, int c) {
    do {
        if (c == '\n') return NO;
        c = Next(s);
    } while (Space(c));
    if (c != '"') return NO;
    Add(name, '.');
    for (;;) {
        c = Next(s);
        if (c == '\n') return NO;
        if (c == '"') break;
        if (c == '\\') { c = Next(s); if (c == '\n') return NO; }
        Add(name, c);
    }
    return Next(s) == ']';
}

/// get_base_var: the section's name, lowercased, dots and all, as the old [branch.x] form writes it.
static BOOL Header(MMGitConfigSrc *s, NSMutableData *name) {
    for (;;) {
        int c = Next(s);
        if (s->eof) return NO;
        if (c == ']') return YES;
        if (Space(c)) return Extended(s, name, c);
        if (!KeyChar(c) && c != '.') return NO;
        Add(name, Lower(c));
    }
}

#pragma mark - What a key means for the upstream

static NSMutableDictionary *Segment(NSMutableArray *items) {
    NSMutableDictionary *seg = [items.lastObject isKindOfClass:NSMutableDictionary.class] ? items.lastObject : nil;
    if (!seg) { seg = [NSMutableDictionary new]; [items addObject:seg]; }
    return seg;
}

static NSMutableDictionary *Sub(NSMutableDictionary *seg, NSString *kind, NSString *name) {
    NSMutableDictionary *all = seg[kind] ?: (seg[kind] = [NSMutableDictionary new]);
    return all[name] ?: (all[name] = [NSMutableDictionary new]);
}

/// The include path as handle_path_include makes it: ~/ from $HOME, a relative path from the folder of the file that
/// holds it. kBad for what is not followed here: ~user, %(prefix) or an empty path.
static NSString *IncludePath(NSString *v, NSString *file) {
    if (!v.length || [v hasPrefix:@"%("]) return kBad;
    if ([v hasPrefix:@"~"]) {
        const char *home = getenv("HOME");
        if (!(v.length == 1 || [v hasPrefix:@"~/"]) || !home || !*home) return kBad;
        v = [@(home) stringByAppendingString:[v substringFromIndex:1]];
    }
    return v.isAbsolutePath ? v : [file.stringByDeletingLastPathComponent stringByAppendingPathComponent:v];
}

/// check_refname_format with REFNAME_ALLOW_ONELEVEL, and REFNAME_REFSPEC_PATTERN when pattern: one * at most.
static BOOL RefnameOK(NSString *r, BOOL pattern) {
    if (!r.length || [r isEqualToString:@"@"] || [r hasSuffix:@"."] || [r containsString:@".."] || [r containsString:@"@{"]) return NO;
    static NSCharacterSet *bad; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *c = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(0, 0x21)];
        [c addCharactersInString:@"\x7f~^:?[\\"];
        bad = c;
    });
    if ([r rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;
    if ([r componentsSeparatedByString:@"*"].count > (pattern ? 2 : 1)) return NO;
    for (NSString *part in [r componentsSeparatedByString:@"/"])
        if (!part.length || [part hasPrefix:@"."] || [part hasSuffix:@".lock"]) return NO;
    return YES;
}

/// parse_refspec: YES for a fetch or push line git takes. A line it refuses makes git refuse to read any remote.
/// A negative push line, and a hex name of either hash's length, count as refused here.
static BOOL RefspecOK(NSString *spec, BOOL fetch) {
    BOOL negative = NO;
    if ([spec hasPrefix:@"+"]) spec = [spec substringFromIndex:1];   // + or ^, not both: "+^x" has ^ in its name
    else if ([spec hasPrefix:@"^"]) { negative = YES; spec = [spec substringFromIndex:1]; }
    if (!fetch && negative) return NO;
    if (!fetch && [spec isEqualToString:@":"]) return YES;   // push the matching branches
    NSRange colon = [spec rangeOfString:@":" options:NSBackwardsSearch];
    NSString *lhs = colon.location == NSNotFound ? spec : [spec substringToIndex:colon.location];
    NSString *rhs = colon.location == NSNotFound ? nil : [spec substringFromIndex:NSMaxRange(colon)];
    if (negative && rhs) return NO;
    BOOL glob = rhs.length && [rhs containsString:@"*"];
    if (lhs.length && [lhs containsString:@"*"]) {
        if ((rhs && !glob) || (!rhs && !negative && fetch)) return NO;
        glob = YES;
    } else if (rhs && glob) return NO;
    if ([lhs isEqualToString:@"@"]) lhs = @"HEAD";
    BOOL hex = (lhs.length == 40 || lhs.length == 64) &&
               [lhs rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet].location == NSNotFound;
    if (negative) return lhs.length && !hex && RefnameOK(lhs, glob);
    if (fetch) {
        if (lhs.length && !hex && !RefnameOK(lhs, glob)) return NO;
        return !rhs.length || RefnameOK(rhs, glob);
    }
    if (lhs.length && glob && !RefnameOK(lhs, glob)) return NO;
    return rhs ? rhs.length && RefnameOK(rhs, glob) : RefnameOK(lhs, glob);
}

/// One key and its value, nil for a key with no =. Each is cut at a NUL, as git reads them as C strings. Only what
/// the upstream depends on is kept: branch.<x>.remote and merge, remote.<x>.url and fetch, include.path, an
/// includeIf path, extensions.worktreeConfig and core.repositoryformatversion, and every value git refuses to read
/// the remotes over. blank: Value's *blank.
static void Emit(NSData *var, NSData *val, BOOL blank, NSMutableArray *items, NSString *file) {
    const unsigned char *k = var.bytes;
    NSUInteger n = var.length;
    const unsigned char *nul = n ? memchr(k, 0, n) : NULL;
    if (nul) n = (NSUInteger)(nul - k);
    const unsigned char *first = n ? memchr(k, '.', n) : NULL;
    if (!first) return;
    const unsigned char *last = first;
    for (const unsigned char *p = first; p < k + n; p++) if (*p == '.') last = p;
    NSString *section = MMGitText(k, (NSUInteger)(first - k), NULL);
    NSString *key = MMGitText(last + 1, (NSUInteger)(k + n - last - 1), NULL);
    BOOL subLossy = NO, valLossy = NO;
    NSString *sub = last > first ? MMGitText(first + 1, (NSUInteger)(last - first - 1), &subLossy) : nil;
    NSString *value = nil;
    if (val) {
        NSUInteger vn = val.length;
        const unsigned char *vnul = vn ? memchr(val.bytes, 0, vn) : NULL;
        value = MMGitText(val.bytes, vnul ? (NSUInteger)(vnul - (const unsigned char *)val.bytes) : vn, &valLossy);
    }
    // Issue #118: a value with bytes that are not UTF-8 reads as U+FFFD, so two such values that differ can read the
    // same; and a tab inside one means what the git that reads it makes of it. Where the upstream is made of it, kBad.
    NSString *kept = value && (valLossy || blank) ? kBad : value;
    // Issue #120: a line that may make every git command refuse the file, which counts in a file outside the repo
    // that MinMacs's own git does not read, MMGitOutside.m.
    if (!MMGitConfigEveryOK(section, sub, key, value, kept == kBad)) Segment(items)[@"every"] = @YES;
    // Issue #126: one only a later git refuses counts in every file outside the repo: the person's git may be one.
    if (!MMGitConfigLaterOK(section, sub, key, value, kept == kBad)) Segment(items)[@"later"] = @YES;
    if ([section isEqualToString:@"branch"] && sub) {
        BOOL needs = [@[@"remote", @"pushremote", @"merge"] containsObject:key];
        if (!sub.length || (needs && !value)) { Segment(items)[@"bad"] = @YES; return; }
        if (subLossy) return;   // a branch name that reads as another
        if ([key isEqualToString:@"remote"]) Sub(Segment(items), @"b", sub)[@"remote"] = kept;
        else if ([key isEqualToString:@"merge"]) {
            NSMutableDictionary *b = Sub(Segment(items), @"b", sub);
            if (!b[@"merge"]) b[@"merge"] = kept;   // the first one is the upstream
        }
    } else if ([section isEqualToString:@"remote"] && sub && ![sub hasPrefix:@"/"]) {
        NSArray *strings = @[@"url", @"pushurl", @"push", @"fetch", @"receivepack", @"uploadpack", @"tagopt", @"proxy",
                             @"proxyauthmethod", @"vcs", @"serveroption", @"followremotehead"];   // the last two: newer gits
        NSArray *bools = @[@"mirror", @"skipdefaultupdate", @"skipfetchall", @"prune", @"prunetags"];
        BOOL refused = ([strings containsObject:key] && !value) || ([bools containsObject:key] && !MMGitConfigBool(value)) ||
                       (value && [key isEqualToString:@"fetch"] && !RefspecOK(value, YES)) ||
                       (value && [key isEqualToString:@"push"] && !RefspecOK(value, NO));
        if (refused) { Segment(items)[@"bad"] = @YES; return; }
        if (subLossy) return;   // a name no usable value names: a lossy value is kBad above
        if ([key isEqualToString:@"url"]) Sub(Segment(items), @"r", sub)[@"url"] = @YES;
        else if ([key isEqualToString:@"fetch"]) {
            NSMutableDictionary *r = Sub(Segment(items), @"r", sub);
            r[@"fetch"] = [r[@"fetch"] ?: @[] arrayByAddingObject:kept];
        }
    } else if ([section isEqualToString:@"remote"] && !sub && [key isEqualToString:@"pushdefault"] && !value) {
        Segment(items)[@"bad"] = @YES;
    } else if ([section isEqualToString:@"url"] && sub && ([key isEqualToString:@"insteadof"] || [key isEqualToString:@"pushinsteadof"]) && !value) {
        Segment(items)[@"bad"] = @YES;   // remote.c refuses it, and so every read of a remote
    } else if ([section isEqualToString:@"include"] && !sub && [key isEqualToString:@"path"]) {
        if (!value) { Segment(items)[@"bad"] = @YES; return; }
        [items addObject:kept == kBad ? kBad : IncludePath(value, file)];   // a string: what comes next is read after that file
    } else if ([section isEqualToString:@"includeif"] && sub && [key isEqualToString:@"path"]) {
        NSMutableDictionary *seg = Segment(items);   // its path too, for a file outside the repo, issue #120
        seg[@"if"] = @YES;
        seg[@"ifs"] = [seg[@"ifs"] ?: @[] arrayByAddingObject:!value || kept == kBad ? kBad : IncludePath(value, file)];
    } else if ([section isEqualToString:@"extensions"] && !sub && [key isEqualToString:@"worktreeconfig"]) {
        Segment(items)[@"wt"] = MMGitConfigBool(value) ?: kBad;
    } else if ([section isEqualToString:@"core"] && !sub && [key isEqualToString:@"repositoryformatversion"]) {
        Segment(items)[@"version"] = MMGitConfigInt(value) ?: kBad;
    }
}

/// One config file's bytes, as items in file order: a dictionary of what a run of lines says, and the path of each
/// include between them, or kBad for one not followed. nil when git refuses the file. file is its path, which a
/// relative include is read from.
NSArray *MMGitConfigItems(NSData *bytes, NSString *file) {
    MMGitConfigSrc s = {bytes.bytes, bytes.length, 0, NO};
    static const unsigned char bom[] = {0xEF, 0xBB, 0xBF};
    NSUInteger inBom = 0;
    BOOL bomDone = NO, comment = NO;
    NSMutableArray *items = [NSMutableArray new];
    NSMutableData *var = [NSMutableData new];
    NSUInteger base = 0;
    for (;;) {
        int c = Next(&s);
        if (!bomDone) {
            if (c == bom[inBom]) { if (++inBom == 3) bomDone = YES; continue; }
            if (inBom) return nil;   // git refuses part of a BOM
            bomDone = YES;
        }
        if (c == '\n') {
            if (s.eof) return items;
            comment = NO;
            continue;
        }
        if (comment || Space(c)) continue;
        if (c == '#' || c == ';') { comment = YES; continue; }
        if (c == '[') {
            var.length = 0;
            if (!Header(&s, var) || !var.length) return nil;
            Add(var, '.');
            base = var.length;
            continue;
        }
        if (!Alpha(c)) return nil;
        var.length = base;
        Add(var, Lower(c));
        // get_value: the rest of the key, blanks, then the end of the line, or = and the value.
        for (;;) {
            c = Next(&s);
            if (s.eof || !KeyChar(c)) break;
            Add(var, Lower(c));
        }
        while (c == ' ' || c == '\t') c = Next(&s);
        NSData *value = nil;
        BOOL blank = NO;
        if (c != '\n') {
            if (c != '=') return nil;
            if (!(value = Value(&s, &blank))) return nil;
        }
        Emit(var, value, blank, items, file);
    }
}

#pragma mark - The upstream, as remote.c

/// The items of path and of every file it includes, as one run of dictionaries in the order git reads them. NO when
/// the upstream cannot be known: a file there and not read, one git refuses, an include not followed or too deep.
/// ifs: an includeIf's file is read too, whatever its condition, issue #120.
static BOOL Flatten(id items, id (^load)(NSString *path), NSUInteger depth, BOOL ifs, NSMutableArray *out) {
    if (![items isKindOfClass:NSArray.class]) return NO;
    for (id it in items) {
        if ([it isKindOfClass:NSDictionary.class]) [out addObject:it];
        for (id p in [it isKindOfClass:NSDictionary.class] ? (ifs ? it[@"ifs"] : nil) : @[it]) {
            if (p == kBad || depth >= 10) return NO;   // git's MAX_INCLUDE_DEPTH
            if (!Flatten(load(p), load, depth + 1, ifs, out)) return NO;
        }
    }
    return YES;
}

BOOL MMGitConfigFlattenAll(id items, id (^load)(NSString *path), NSMutableArray *out) { return Flatten(items, load, 0, YES, out); }

/// YES for a ref name git would read: under refs/, shared by every worktree, and none of what check-ref-format refuses.
static BOOL RefOK(NSString *ref) {
    return [ref hasPrefix:@"refs/"] && ![ref hasPrefix:@"refs/worktree/"] && ![ref hasPrefix:@"refs/bisect/"] &&
           ![ref hasPrefix:@"refs/rewritten/"] && RefnameOK(ref, NO);
}

/// remote_find_tracking: the first fetch line that maps src, with its one * or none. kBad for a line not read here.
static NSString *Track(NSArray<NSString *> *fetch, NSString *src) {
    // A negative line, ^ref, anywhere: git 2.39 maps the merge past it, and later gits may not.
    for (NSString *line in fetch) if (line == kBad || [line hasPrefix:@"^"] || [line hasPrefix:@"+^"]) return kBad;
    for (NSString *line in fetch) {
        NSString *spec = [line hasPrefix:@"+"] ? [line substringFromIndex:1] : line;
        NSArray *p = [spec componentsSeparatedByString:@":"];
        if ([spec hasPrefix:@"^"] || p.count != 2) return kBad;
        NSString *from = p[0], *to = p[1];
        NSUInteger stars = [from componentsSeparatedByString:@"*"].count - 1;
        if (!from.length || !to.length || stars > 1 || stars != [to componentsSeparatedByString:@"*"].count - 1) return kBad;
        if (!stars) { if ([from isEqualToString:src]) return to; continue; }
        NSRange star = [from rangeOfString:@"*"];
        NSString *pre = [from substringToIndex:star.location], *post = [from substringFromIndex:NSMaxRange(star)];
        // hasPrefix: and hasSuffix: answer NO for "", so an empty end is no test.
        if (src.length < pre.length + post.length || (pre.length && ![src hasPrefix:pre]) || (post.length && ![src hasSuffix:post])) continue;
        NSString *mid = [src substringWithRange:NSMakeRange(pre.length, src.length - pre.length - post.length)];
        return [to stringByReplacingOccurrencesOfString:@"*" withString:mid];
    }
    return nil;
}

/// The name git shows for a ref, as %(upstream:short) gives it for the usual ones.
static NSString *Short(NSString *ref) {
    for (NSString *p in @[@"refs/heads/", @"refs/remotes/", @"refs/tags/", @"refs/"])
        if ([ref hasPrefix:p]) return [ref substringFromIndex:p.length];
    return ref;
}

/// The upstream of branch in the repo whose common dir is common, for the checkout whose git dir is gitDir: @{} for
/// none, @{unknown: YES} when it cannot be known, else {ref, up}: the ref its remote branch is read from and the name
/// git shows. load gives a config file's items, @[] for a missing file, anything else for one not read.
static NSDictionary *Upstream(id top, NSString *common, NSString *gitDir, NSString *branch, id (^load)(NSString *path), BOOL *alone);

NSDictionary *MMGitConfigUpstream(NSString *common, NSString *gitDir, NSString *branch, id (^load)(NSString *path)) {
    // The answer for a config that stands alone, with no include, no config.worktree and no .git/remotes looked at,
    // depends on its items alone, which load hands back as the same object until the file's stamp moves. So a warm walk
    // looks it up, per branch, kept as long as those items are.
    static NSMapTable<id, NSMutableDictionary *> *memo; static dispatch_once_t once;
    dispatch_once(&once, ^{ memo = [NSMapTable weakToStrongObjectsMapTable]; });
    id top = load([common stringByAppendingPathComponent:@"config"]);
    if ([top isKindOfClass:NSArray.class]) {
        @synchronized (memo) { NSDictionary *hit = [memo objectForKey:top][branch]; if (hit) return MMGitOutsideUpstream(hit, branch, load); }
    }
    BOOL alone = NO;
    NSDictionary *up = Upstream(top, common, gitDir, branch, load, &alone);
    if (alone) @synchronized (memo) {
        NSMutableDictionary *m = [memo objectForKey:top];
        if (!m) [memo setObject:(m = [NSMutableDictionary new]) forKey:top];
        m[branch] = up;
    }
    return MMGitOutsideUpstream(up, branch, load);
}

/// MMGitConfigUpstream on config's items, top. *alone turns YES when the answer depends on them alone.
static NSDictionary *Upstream(id top, NSString *common, NSString *gitDir, NSString *branch, id (^load)(NSString *path), BOOL *alone) {
    NSDictionary *unknown = @{@"unknown": @YES};
    NSMutableArray<NSDictionary *> *segs = [NSMutableArray new];
    if (!Flatten(top, load, 0, NO, segs)) return unknown;
    // extensions are read from config itself, includes left out, as read_repository_format reads them.
    id wt = nil, version = nil;
    for (id it in top) if ([it isKindOfClass:NSDictionary.class] && it[@"wt"]) wt = it[@"wt"];
    for (id it in top) if ([it isKindOfClass:NSDictionary.class] && it[@"version"]) version = it[@"version"];
    // With no core.repositoryformatversion, or -1, git drops every extension and never reads config.worktree. One it
    // cannot read, or past 1, and git refuses the repo.
    if (version == kBad || (version && ([version longLongValue] < -1 || [version longLongValue] > 1))) return unknown;
    if (!version || [version longLongValue] == -1) wt = nil;
    if (wt == kBad) return unknown;
    if ([wt boolValue] && !Flatten(load([gitDir stringByAppendingPathComponent:@"config.worktree"]), load, 0, NO, segs)) return unknown;
    *alone = ![wt boolValue];   // no config.worktree, and below, no include among config's items
    for (id it in top) if (![it isKindOfClass:NSDictionary.class]) *alone = NO;
    NSString *remote = nil, *merge = nil;
    NSMutableArray *fetch = [NSMutableArray new];
    BOOL url = NO, dotRemote = NO;
    for (NSDictionary *seg in segs) {
        if (seg[@"bad"] || seg[@"if"]) return unknown;
        NSDictionary *b = seg[@"b"][branch];
        if (b[@"remote"]) remote = b[@"remote"];
        if (!merge && b[@"merge"]) merge = b[@"merge"];
    }
    if (remote == kBad || merge == kBad) return unknown;
    if (!remote || !merge) return remote ? @{@"remote": remote} : @{};   // the remote, for MMGitOutside.m
    if (!remote.length) return unknown;
    for (NSDictionary *seg in segs) {
        NSDictionary *r = seg[@"r"][remote];
        if (r[@"url"]) url = YES;
        if (r[@"fetch"]) [fetch addObjectsFromArray:r[@"fetch"]];
        if (seg[@"r"][@"."]) dotRemote = YES;
    }
    NSString *ref = nil;
    if ([remote isEqualToString:@"."]) {
        if (dotRemote || ![merge hasPrefix:@"refs/"]) return unknown;
        ref = merge;
    } else {
        // A remote with no url in config is read from .git/remotes or .git/branches too, which is not read here.
        if (!url && ![remote containsString:@"/"] && ![remote isEqualToString:@".."]) {
            *alone = NO;   // those files are looked at each time
            struct stat st;
            for (NSString *dir in @[@"remotes", @"branches"])
                if (lstat([[common stringByAppendingPathComponent:dir] stringByAppendingPathComponent:remote].fileSystemRepresentation, &st) == 0) return unknown;
        }
        ref = Track(fetch, merge);
        if (ref == kBad) return unknown;
        if (!ref) return @{@"remote": remote, @"merge": merge};
    }
    if (!RefOK(ref)) return unknown;
    return @{@"ref": ref, @"up": Short(ref), @"remote": remote, @"merge": merge};
}

/// Issue #120: NO only when each line of fetch maps src to ref, or not at all. Read before the repo's own lines, and
/// in any order or part, as the files of another git, they leave git's answer as it is.
BOOL MMGitConfigMayMap(NSArray *fetch, NSString *src, NSString *ref) {
    for (NSString *line in fetch) {
        NSString *to = Track(@[line], src);
        if (to && (to == kBad || ![to isEqualToString:ref])) return YES;
    }
    return NO;
}
