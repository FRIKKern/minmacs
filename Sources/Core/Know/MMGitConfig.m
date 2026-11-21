// MMGitConfig, issue #118: git's config files read as git's own reader reads them, for the one fact Know takes from
// them, the upstream of a branch. The parser follows git's config.c, git_parse_source, get_value, parse_value and
// get_base_var, and the upstream follows remote.c, handle_config, set_merge and remote_find_tracking.
//
//   what the file holds                           what the upstream is
//   a line git refuses: an unknown escape, an     not known: git refuses every command on that repo
//   open quote, a header with a space inside,
//   a key with no = and more after it
//   a value with no = where git needs one          not known: git refuses to read the remotes
//   (branch.x.merge, remote, remote.r.fetch)
//   an [includeIf] path                            not known: its condition is not read here
//   an include.path                                followed, relative to its file, ten deep at most as git
//   extensions.worktreeConfig                      config.worktree of the checkout's git dir is read after config
//   a fetch line that is negative, or not          not known
//   src:dst with one * on each side or none
//   remote . with a merge not under refs/          not known: git looks the short name up
//   no remote or no merge                          none
//   remote and merge                               the ref the remote's fetch lines map the FIRST merge to, as
//                                                  git's @{upstream}; the LAST remote; none when no line maps it
//
// What is not read: the global and system config, which only the person's own git setup writes to.
// Every function here reads no file: MMGitFacts.m hands each file over, parsed once per stamp.
#import <Foundation/Foundation.h>
#include <sys/stat.h>

NSString *MMGitText(const unsigned char *b, NSUInteger n, BOOL *lossy);   // MMGitFacts.m

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
static NSMutableData *Value(MMGitConfigSrc *s) {
    BOOL quote = NO, comment = NO;
    NSUInteger trim = 0;
    NSMutableData *v = [NSMutableData new];
    for (;;) {
        int c = Next(s);
        if (c == '\n') {
            if (quote) return nil;
            if (trim) v.length = trim;
            return v;
        }
        if (comment) continue;
        if (Space(c) && !quote) {
            if (!trim) trim = v.length;
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

/// git_config_bool: no value is true, then true, yes, on, false, no, off and "" in any case, then a number with an
/// optional k, m or g. nil for what git refuses.
static NSNumber *Bool(NSString *v) {
    if (!v) return @YES;
    NSString *l = v.lowercaseString;
    if ([@[@"true", @"yes", @"on"] containsObject:l]) return @YES;
    if ([@[@"false", @"no", @"off", @""] containsObject:l]) return @NO;
    NSScanner *sc = [NSScanner scannerWithString:l];
    long long n = 0;
    if (![sc scanLongLong:&n]) return nil;
    NSString *rest = [l substringFromIndex:sc.scanLocation];
    if (rest.length && ![@[@"k", @"m", @"g"] containsObject:rest]) return nil;
    return @(n != 0);
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

/// One key and its value, nil for a key with no =. Each is cut at a NUL, as git reads them as C strings. Only what
/// the upstream depends on is kept: branch.<x>.remote and merge, remote.<x>.url and fetch, include.path, an
/// includeIf path and extensions.worktreeConfig, and every value git refuses to read the remotes over.
static void Emit(NSData *var, NSData *val, NSMutableArray *items, NSString *file) {
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
    NSString *sub = last > first ? MMGitText(first + 1, (NSUInteger)(last - first - 1), NULL) : nil;
    NSString *value = nil;
    if (val) {
        NSUInteger vn = val.length;
        const unsigned char *vnul = vn ? memchr(val.bytes, 0, vn) : NULL;
        value = MMGitText(val.bytes, vnul ? (NSUInteger)(vnul - (const unsigned char *)val.bytes) : vn, NULL);
    }
    if ([section isEqualToString:@"branch"] && sub) {
        BOOL needs = [@[@"remote", @"pushremote", @"merge"] containsObject:key];
        if (!sub.length || (needs && !value)) { Segment(items)[@"bad"] = @YES; return; }
        if ([key isEqualToString:@"remote"]) Sub(Segment(items), @"b", sub)[@"remote"] = value;
        else if ([key isEqualToString:@"merge"]) {
            NSMutableDictionary *b = Sub(Segment(items), @"b", sub);
            if (!b[@"merge"]) b[@"merge"] = value;   // the first one is the upstream
        }
    } else if ([section isEqualToString:@"remote"] && sub && ![sub hasPrefix:@"/"]) {
        NSArray *strings = @[@"url", @"pushurl", @"push", @"fetch", @"receivepack", @"uploadpack", @"tagopt", @"proxy", @"proxyauthmethod", @"vcs"];
        NSArray *bools = @[@"mirror", @"skipdefaultupdate", @"skipfetchall", @"prune", @"prunetags"];
        if (([strings containsObject:key] && !value) || ([bools containsObject:key] && !Bool(value))) { Segment(items)[@"bad"] = @YES; return; }
        if ([key isEqualToString:@"url"]) Sub(Segment(items), @"r", sub)[@"url"] = @YES;
        else if ([key isEqualToString:@"fetch"]) {
            NSMutableDictionary *r = Sub(Segment(items), @"r", sub);
            r[@"fetch"] = [r[@"fetch"] ?: @[] arrayByAddingObject:value];
        }
    } else if ([section isEqualToString:@"remote"] && !sub && [key isEqualToString:@"pushdefault"] && !value) {
        Segment(items)[@"bad"] = @YES;
    } else if ([section isEqualToString:@"include"] && !sub && [key isEqualToString:@"path"]) {
        if (!value) { Segment(items)[@"bad"] = @YES; return; }
        [items addObject:IncludePath(value, file)];   // a string: what comes next is read after that file
    } else if ([section isEqualToString:@"includeif"] && sub && [key isEqualToString:@"path"]) {
        Segment(items)[@"if"] = @YES;
    } else if ([section isEqualToString:@"extensions"] && !sub && [key isEqualToString:@"worktreeconfig"]) {
        Segment(items)[@"wt"] = Bool(value) ?: kBad;
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
        if (c != '\n') {
            if (c != '=') return nil;
            if (!(value = Value(&s))) return nil;
        }
        Emit(var, value, items, file);
    }
}

#pragma mark - The upstream, as remote.c

/// The items of path and of every file it includes, as one run of dictionaries in the order git reads them. NO when
/// the upstream cannot be known: a file there and not read, one git refuses, an include not followed or too deep.
static BOOL Flatten(id items, id (^load)(NSString *path), NSUInteger depth, NSMutableArray *out) {
    if (![items isKindOfClass:NSArray.class]) return NO;
    for (id it in items) {
        if ([it isKindOfClass:NSDictionary.class]) { [out addObject:it]; continue; }
        if (it == kBad || depth >= 10) return NO;   // git's MAX_INCLUDE_DEPTH
        if (!Flatten(load(it), load, depth + 1, out)) return NO;
    }
    return YES;
}

/// YES for a ref name git would read: under refs/, shared by every worktree, and none of what check-ref-format refuses.
static BOOL RefOK(NSString *ref) {
    if (![ref hasPrefix:@"refs/"] || [ref hasPrefix:@"refs/worktree/"] || [ref hasPrefix:@"refs/bisect/"] ||
        [ref hasPrefix:@"refs/rewritten/"]) return NO;
    static NSCharacterSet *bad; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *c = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(0, 0x21)];
        [c addCharactersInString:@"\x7f~^:?*[\\"];
        bad = c;
    });
    if ([ref rangeOfCharacterFromSet:bad].location != NSNotFound || [ref containsString:@".."] || [ref containsString:@"@{"]) return NO;
    for (NSString *part in [ref componentsSeparatedByString:@"/"])
        if (!part.length || [part hasPrefix:@"."] || [part hasSuffix:@".lock"]) return NO;
    return ![ref hasSuffix:@"."];
}

/// remote_find_tracking: the first fetch line that maps src, with its one * or none. kBad for a line not read here.
static NSString *Track(NSArray<NSString *> *fetch, NSString *src) {
    // A negative line, ^ref, anywhere: git 2.39 maps the merge past it, and later gits may not.
    for (NSString *line in fetch) if ([line hasPrefix:@"^"] || [line hasPrefix:@"+^"]) return kBad;
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
        @synchronized (memo) { NSDictionary *hit = [memo objectForKey:top][branch]; if (hit) return hit; }
    }
    BOOL alone = NO;
    NSDictionary *up = Upstream(top, common, gitDir, branch, load, &alone);
    if (alone) @synchronized (memo) {
        NSMutableDictionary *m = [memo objectForKey:top];
        if (!m) [memo setObject:(m = [NSMutableDictionary new]) forKey:top];
        m[branch] = up;
    }
    return up;
}

/// MMGitConfigUpstream on config's items, top. *alone turns YES when the answer depends on them alone.
static NSDictionary *Upstream(id top, NSString *common, NSString *gitDir, NSString *branch, id (^load)(NSString *path), BOOL *alone) {
    NSDictionary *unknown = @{@"unknown": @YES};
    NSMutableArray<NSDictionary *> *segs = [NSMutableArray new];
    if (!Flatten(top, load, 0, segs)) return unknown;
    // extensions are read from config itself, includes left out, as read_repository_format reads them.
    id wt = nil;
    for (id it in top) if ([it isKindOfClass:NSDictionary.class] && it[@"wt"]) wt = it[@"wt"];
    if (wt == kBad) return unknown;
    if ([wt boolValue] && !Flatten(load([gitDir stringByAppendingPathComponent:@"config.worktree"]), load, 0, segs)) return unknown;
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
    if (!remote || !merge) return @{};
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
        if (!ref) return @{};
    }
    if (!RefOK(ref)) return unknown;
    return @{@"ref": ref, @"up": Short(ref)};
}
