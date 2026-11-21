// MMGitFacts, pattern P26: what MMRepoIndex knows about one worktree's git state.
// Ported from ReadFacts, ReadStatus and SquashMerged in WorkForest's Trees.m:134-290, with two changes.
//  1. Branch, HEAD, the default branch, the upstream and the stash count come from git's own files, with no spawn:
//     HEAD, refs, packed-refs, config, refs/remotes/origin/HEAD and logs/refs/stash. Those also give the fingerprints.
//  2. The squash check no longer reads `git log -p -n 400` of the default branch on every scan, which spiked
//     WorkForest's CPU and memory (Trees.m:104-129, TESTS.md question 7). A patch id is kept per commit forever,
//     computed only for commits it has not seen, only for the default branch's commits since the merge base, and
//     only for branches not already merged by ancestry or tree. git's output streams through a pipe to patch-id.
// Every function here reads disk or runs git, so it runs on a Know queue, never on main.
#import "Core/Know/MMGit.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Runtime/MMRuntime.h"
#import <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

NSString *MMGitInput(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status);
NSString *MMGitPatchIds(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status);
NSArray *MMGitConfigItems(NSData *bytes, NSString *file);                                    // MMGitConfig.m
NSDictionary *MMGitConfigUpstream(NSString *common, NSString *gitDir, NSString *branch, id (^load)(NSString *path));
NSDictionary *MMGitOutsideUpstream(NSDictionary *up, NSString *branch, id (^load)(NSString *path));       // MMGitOutside.m

static const NSTimeInterval kGitShort = 15;        // rev-list, merge-base, show
static const NSTimeInterval kGitStatus = 30;       // status in a large checkout
static const NSTimeInterval kGitPatch = 120;       // patch ids for many commits, once per commit
static const NSUInteger kDefaultCommits = 1000;    // default-branch commits since the merge base that a squash may be among
static const NSUInteger kBranchCommits = 200;      // branch commits compared one by one for the patch kind

#pragma mark - The facts object

@interface MMGitFacts ()
@property (readwrite, copy) NSString *branch, *head, *defaultBranch, *upstream;
@property (readwrite) MMMergeKind merged;
@property (readwrite) NSInteger dirty, untracked, stashes, notInDefault, unpushed, ahead, behind;
@property (readwrite) BOOL onRemote, upstreamGone, upstreamUnknown;
@property (readwrite) NSDate *lastCommit;
@end

static NSArray<NSString *> *MergeWords(void) {
    return @[@"none", @"ancestor", @"tree", @"patch", @"squash", @"pr", @"merge-tree"];
}

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }
static NSInteger Int(id v, NSInteger dflt) { return [v isKindOfClass:NSNumber.class] ? [v integerValue] : dflt; }

@implementation MMGitFacts

/// The facts from one cache value: {files, status, history}, as MMRepoIndex keeps them.
+ (instancetype)fromValue:(NSDictionary *)v {
    if (![v isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *f = [v[@"files"] isKindOfClass:NSDictionary.class] ? v[@"files"] : nil;
    if (!f) return nil;
    NSDictionary *s = [v[@"status"] isKindOfClass:NSDictionary.class] ? v[@"status"] : @{};
    NSDictionary *h = [v[@"history"] isKindOfClass:NSDictionary.class] ? v[@"history"] : @{};
    MMGitFacts *g = [MMGitFacts new];
    g.branch = Str(f[@"branch"]); g.head = Str(f[@"head"]); g.defaultBranch = Str(f[@"def"]); g.upstream = Str(f[@"up"]);
    g.upstreamGone = [f[@"gone"] boolValue]; g.upstreamUnknown = [f[@"upUnread"] boolValue];
    g.stashes = Int(f[@"stashes"], -1);   // issue #116: not known keeps
    g.dirty = Int(s[@"dirty"], -1); g.untracked = Int(s[@"untracked"], -1);   // not known yet counts as dirty
    g.notInDefault = Int(h[@"notInDefault"], -1); g.unpushed = Int(h[@"unpushed"], -1);
    g.ahead = Int(h[@"ahead"], 0); g.behind = Int(h[@"behind"], 0);
    g.onRemote = [h[@"onRemote"] boolValue];
    NSUInteger m = [MergeWords() indexOfObject:Str(h[@"merged"]) ?: @"none"];
    g.merged = m == NSNotFound ? MMMergedNone : (MMMergeKind)m;
    if ([h[@"lastCommit"] isKindOfClass:NSNumber.class]) g.lastCommit = [NSDate dateWithTimeIntervalSince1970:[h[@"lastCommit"] doubleValue]];
    return g;
}

- (NSDictionary *)json {
    NSUInteger m = (NSUInteger)self.merged;
    return @{@"branch": self.branch ?: NSNull.null, @"head": self.head ?: NSNull.null,
             @"defaultBranch": self.defaultBranch ?: NSNull.null, @"upstream": self.upstream ?: NSNull.null,
             @"upstreamGone": @(self.upstreamGone), @"upstreamUnknown": @(self.upstreamUnknown), @"merged": m < MergeWords().count ? MergeWords()[m] : @"none",
             @"dirty": @(self.dirty), @"untracked": @(self.untracked), @"stashes": @(self.stashes),
             @"notInDefault": @(self.notInDefault), @"unpushed": @(self.unpushed), @"ahead": @(self.ahead),
             @"behind": @(self.behind), @"onRemote": @(self.onRemote),
             @"lastCommit": self.lastCommit ? @(self.lastCommit.timeIntervalSince1970) : NSNull.null};
}

- (NSString *)description { return [NSString stringWithFormat:@"<MMGitFacts %@>", self.json]; }

@end

#pragma mark - git's own files

/// The most of git's own files that is read: far past any packed-refs or config git writes. A bigger one is not read.
static const NSUInteger kGitFileMax = 256u * 1024 * 1024;

// Issue #116: git's files are bytes, and a fact read from one that cannot be read is not known, never none.
//
//   the file is                                 what it gives
//   missing, or a link to nothing               none: no stash, no such ref, no config section
//   there and read                              its lines, split on the byte \n, a \r before it dropped. A byte that
//                                               starts no UTF-8 sequence, and a NUL, reads as U+FFFD, so the line
//                                               still counts and a name in it still shows
//   there and not read: a pipe, past the cap,   kUnread: the stash count is -1, HEAD and the commits on it are not
//   no permission, a read error                 known, no default branch, and the remote branch is not gone
//   a ref name with U+FFFD or a NUL             shown, and never made a path or a git argument: Resolve gives kUnread
//
// Counts and which refs exist come from the lines alone. A name is decoded only to be shown or compared.

/// What a file that is there and cannot be read gives, and the sha of a ref that cannot be known. Compared by pointer.
static NSString *const kUnread = @"(not read)";

/// YES when why, the errno of the stat or read that found no file, says nothing is there: the one case a file git did
/// not write is none. A link to nothing is none too, as git's own fopen finds it. dirToo, for a loose ref: a folder
/// there is no ref, as git reads it, since it holds refs below that name.
static BOOL Missing(int why, BOOL dirToo) { return why == ENOENT || why == ENOTDIR || (dirToo && why == EISDIR); }

/// The length of the UTF-8 sequence at s, or 0 when none starts there: the strict rules Foundation decodes by, with
/// no overlong form, no surrogate and nothing past U+10FFFF. A NUL counts as none.
static NSUInteger UTF8Run(const unsigned char *s, NSUInteger n) {
    unsigned char c = s[0], lo = 0x80, hi = 0xBF;
    NSUInteger len;
    if (c < 0x80) return c ? 1 : 0;
    if (c >= 0xC2 && c <= 0xDF) len = 2;
    else if (c >= 0xE0 && c <= 0xEF) { len = 3; if (c == 0xE0) lo = 0xA0; if (c == 0xED) hi = 0x9F; }
    else if (c >= 0xF0 && c <= 0xF4) { len = 4; if (c == 0xF0) lo = 0x90; if (c == 0xF4) hi = 0x8F; }
    else return 0;
    if (n < len || s[1] < lo || s[1] > hi) return 0;
    for (NSUInteger i = 2; i < len; i++) if (s[i] < 0x80 || s[i] > 0xBF) return 0;
    return len;
}

/// n bytes as text, never nil. *lossy, when given, turns YES when a byte is not UTF-8 or is a NUL: each such byte
/// reads as U+FFFD, and the rest as it is.
static NSString *Text(const unsigned char *b, NSUInteger n, BOOL *lossy) {
    if (!n) return @"";
    if (!memchr(b, 0, n)) {
        NSString *s = [[NSString alloc] initWithBytes:b length:n encoding:NSUTF8StringEncoding];
        if (s) return s;
    }
    if (lossy) *lossy = YES;
    static const unsigned char fffd[] = {0xEF, 0xBF, 0xBD};
    NSMutableData *d = [NSMutableData dataWithCapacity:n + 16];
    for (NSUInteger i = 0; i < n;) {
        NSUInteger k = UTF8Run(b + i, n - i);
        if (k) { [d appendBytes:b + i length:k]; i += k; } else { [d appendBytes:fffd length:3]; i++; }
    }
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s) return s;
    d.length = 0;   // were Foundation stricter than UTF8Run: ASCII alone, and U+FFFD for every other byte
    for (NSUInteger i = 0; i < n; i++) { if (b[i] && b[i] < 0x80) [d appendBytes:b + i length:1]; else [d appendBytes:fffd length:3]; }
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

NSString *MMGitText(const unsigned char *b, NSUInteger n, BOOL *lossy) { return Text(b, n, lossy); }

/// A file's lines, split on the byte \n, each with a \r before the \n dropped, as git's config reader drops it.
static NSArray<NSString *> *FileLines(NSData *data) {
    const unsigned char *b = data.bytes;
    NSUInteger n = data.length;
    NSMutableArray *out = [NSMutableArray new];
    if (!n) return out;
    // The usual file, all UTF-8 with no NUL, decodes once as before.
    NSString *whole = memchr(b, 0, n) ? nil : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (whole) {
        for (NSString *l in [whole componentsSeparatedByString:@"\n"]) [out addObject:[l hasSuffix:@"\r"] ? [l substringToIndex:l.length - 1] : l];
        return out;
    }
    for (NSUInteger i = 0; i < n;) {
        const unsigned char *nl = memchr(b + i, '\n', n - i);
        NSUInteger end = nl ? (NSUInteger)(nl - b) : n, len = end - i;
        if (len && b[i + len - 1] == '\r') len--;
        [out addObject:Text(b + i, len, NULL)];
        i = end + 1;
    }
    return out;
}

/// NO for a name with U+FFFD or a NUL: it stands for bytes it does not hold, so it never builds a path or a git argument.
static BOOL NameUsable(NSString *s) {
    static NSCharacterSet *bad; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *c = [NSMutableCharacterSet new];
        [c addCharactersInRange:NSMakeRange(0, 1)]; [c addCharactersInRange:NSMakeRange(0xFFFD, 1)];
        bad = c;
    });
    return [s rangeOfCharacterFromSet:bad].location == NSNotFound;
}

/// A small file's text, trimmed, or nil: HEAD, a ref, a .git file, commondir. Text that is not UTF-8, or holds a NUL,
/// would build a path, so it reads as nil, issue #116, except a symbolic ref, "ref: <name>": its name is shown, so it
/// reads with U+FFFD for each such byte, and Resolve never makes a path of it. *unread, when given, turns YES when the
/// file is there and gives no text, and a ref's folder is no file, as Missing says. Issue #54: open and read, since
/// Foundation's file read cost most of a warm walk of 300 worktrees, which reads about 15 such files each. Issues #81
/// and #96: through MMReadPlain, so only a plain file is opened, and a named pipe under one of those names, as a .git
/// in a folder that is scanned can be, is not read.
static NSString *Line(NSString *path, BOOL *unread, BOOL ref) {
    int why = 0;
    NSData *d = MMReadPlainWhy(path, kGitFileMax, MMPlainWhole, &why);
    BOOL lossy = NO;
    NSString *s = d ? Text(d.bytes, d.length, &lossy) : nil;
    if (lossy && !(d.length >= 5 && !memcmp(d.bytes, "ref: ", 5))) s = nil;
    if (unread) *unread = d ? !s : !Missing(why, ref);
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *MMReadLine(NSString *path) { return Line(path, NULL, NO); }

static NSString *ReadLine(NSString *path) { return Line(path, NULL, NO); }

/// mtime, size and inode, or "-" when the file is missing. A rewrite of the file always moves it. *why, when given, is
/// the errno of a stat that failed.
static NSString *StampWhy(NSString *path, int *why) {
    struct stat st;
    const char *p = path.fileSystemRepresentation;
    if (!p || stat(p, &st) != 0) { if (why) *why = p ? errno : EINVAL; return @"-"; }
    return [NSString stringWithFormat:@"%ld.%09ld:%lld:%llu", (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec,
            (long long)st.st_size, (unsigned long long)st.st_ino];
}

static NSString *Stamp(NSString *path) { return StampWhy(path, NULL); }

static BOOL IsSha(NSString *s) {
    if (s.length != 40 && s.length != 64) return NO;
    return [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location == NSNotFound;
}

/// A file git rewrites whole, parsed from its bytes once per stamp and kept per path. A missing file parses as no
/// bytes. Issues #96 and #116: one that is there and cannot be read, a named pipe among them, gives kUnread and never
/// waits, and is read again next time. Issue #120: a file rewritten in place can keep its size, inode and mtime, so the
/// fresh read before an action, factsFor:wait:YES on core.git.fresh, never takes the memo's answer: it reads the file.
static id Parsed(NSString *path, id (^parse)(NSData *bytes)) {
    static NSMutableDictionary<NSString *, NSArray *> *memo; static dispatch_once_t once;
    dispatch_once(&once, ^{ memo = [NSMutableDictionary new]; });
    int why = 0;
    NSString *stamp = StampWhy(path, &why);
    if ([stamp isEqualToString:@"-"]) return Missing(why, NO) ? parse(NSData.data) ?: NSNull.null : kUnread;
    const char *queue = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    if (!(queue && !strcmp(queue, "no.guerrilla.minmacs.core.git.fresh"))) @synchronized (memo) {
        NSArray *hit = memo[path];
        if ([hit[0] isEqualToString:stamp]) return hit[1];
    }
    NSData *bytes = MMReadPlainWhy(path, kGitFileMax, MMPlainWhole, &why);
    if (!bytes) return Missing(why, NO) ? parse(NSData.data) ?: NSNull.null : kUnread;
    id value = parse(bytes) ?: NSNull.null;
    @synchronized (memo) {
        if (memo.count > 512) [memo removeAllObjects];
        memo[path] = @[stamp, value];
    }
    return value;
}

/// packed-refs as ref name to sha, or kUnread. A name that is not UTF-8 is kept with U+FFFD, and no lookup asks for it.
static id PackedRefs(NSString *common) {
    return Parsed([common stringByAppendingPathComponent:@"packed-refs"], ^id(NSData *bytes) {
        NSMutableDictionary *refs = [NSMutableDictionary new];
        for (NSString *line in FileLines(bytes)) {
            if (line.length < 42 || [line hasPrefix:@"#"] || [line hasPrefix:@"^"]) continue;
            NSRange sp = [line rangeOfString:@" "];
            if (sp.location == NSNotFound) continue;
            refs[[line substringFromIndex:NSMaxRange(sp)]] = [line substringToIndex:sp.location];
        }
        return refs;
    });
}

/// The sha a ref names, from the loose file or packed-refs, following a symbolic ref twice at most. nil when no such
/// ref is there. kUnread when it cannot be known, issue #116: a name NameUsable refuses, a loose file or a packed-refs
/// that is there and not read, a loose file or a packed line that names no sha, or a loop.
static NSString *Resolve(NSString *common, NSString *ref, int depth) {
    if (!ref.length || depth > 3 || [ref containsString:@".."] || !NameUsable(ref)) return kUnread;
    BOOL unread = NO;
    NSString *line = Line([common stringByAppendingPathComponent:ref], &unread, YES);
    if (unread) return kUnread;
    if ([line hasPrefix:@"ref: "]) return Resolve(common, [line substringFromIndex:5], depth + 1);
    if (line) return IsSha(line) ? line : kUnread;
    id packed = PackedRefs(common);
    if (![packed isKindOfClass:NSDictionary.class]) return kUnread;
    NSString *sha = Str(packed[ref]);
    return !sha || IsSha(sha) ? sha : kUnread;
}

/// A config file's items, MMGitConfigItems, parsed once per stamp. NSNull for a file git refuses, kUnread for one
/// that is there and not read, no items for a missing one.
static id ConfigItems(NSString *path) {
    return Parsed(path, ^id(NSData *bytes) { return MMGitConfigItems(bytes, path); });
}

/// The stash entries made on branch, from logs/refs/stash: "WIP on <branch>:" or "On <branch>:". -1 when the log is
/// there and cannot be read, issue #116. A line that is not UTF-8 still counts, its subject read with U+FFFD, so a
/// branch whose name is not UTF-8 matches its own entries, and at worst those of a name that reads the same: more,
/// never fewer.
static NSInteger StashesOn(NSString *common, NSString *branch) {
    if (!branch.length) return 0;
    id lines = Parsed([common stringByAppendingPathComponent:@"logs/refs/stash"], ^id(NSData *bytes) {
        NSMutableArray *subjects = [NSMutableArray new];
        for (NSString *line in FileLines(bytes)) {
            NSRange tab = [line rangeOfString:@"\t"];
            if (tab.location != NSNotFound) [subjects addObject:[line substringFromIndex:NSMaxRange(tab)]];
        }
        return subjects;
    });
    if (![lines isKindOfClass:NSArray.class]) return -1;
    NSString *wip = [NSString stringWithFormat:@"WIP on %@:", branch], *on = [NSString stringWithFormat:@"On %@:", branch];
    NSInteger n = 0;
    for (NSString *s in lines) if ([s hasPrefix:wip] || [s hasPrefix:on]) n++;
    return n;
}

/// The git dir and the common dir of the checkout at path, read from its .git, or nil.
NSDictionary<NSString *, NSString *> *MMGitDirsOf(NSString *path) {
    NSString *dotgit = [path stringByAppendingPathComponent:@".git"];
    struct stat st;   // stat, not NSFileManager, issue #54: once per worktree on every walk
    if (stat(dotgit.fileSystemRepresentation, &st) != 0) return nil;
    if (S_ISDIR(st.st_mode)) return @{@"gitDir": dotgit, @"common": dotgit};
    NSString *line = ReadLine(dotgit);
    if (![line hasPrefix:@"gitdir: "]) return nil;
    NSString *gitDir = [line substringFromIndex:8];
    if (!gitDir.isAbsolutePath) gitDir = [path stringByAppendingPathComponent:gitDir];
    gitDir = gitDir.stringByStandardizingPath;
    BOOL unread = NO;
    NSString *common = Line([gitDir stringByAppendingPathComponent:@"commondir"], &unread, NO);
    if (unread) return nil;   // issue #116: a commondir there and not read is not a submodule's
    if (!common.length) return @{@"gitDir": gitDir, @"common": gitDir};   // a submodule keeps its own refs
    if (!common.isAbsolutePath) common = [gitDir stringByAppendingPathComponent:common];
    return @{@"gitDir": gitDir, @"common": common.stringByStandardizingPath};
}

/// Everything git's files tell with no spawn, plus the stamps the fingerprints are made of. Issue #116: what cannot be
/// known is said so, never left out as none. headUnread: HEAD, or the sha its branch names, cannot be known, so the
/// history layer counts nothing as 0. upUnread: the upstream cannot be known, so it is not gone. stashes -1.
NSDictionary *MMGitReadFiles(NSString *gitDir, NSString *common) {
    NSMutableDictionary *f = [NSMutableDictionary new];
    BOOL headUnread = NO;
    NSString *line = Line([gitDir stringByAppendingPathComponent:@"HEAD"], &headUnread, NO);
    if ([line hasPrefix:@"ref: "]) {
        NSString *ref = [line substringFromIndex:5];
        if ([ref hasPrefix:@"refs/heads/"]) f[@"branch"] = [ref substringFromIndex:11];   // shown, U+FFFD and all
        NSString *sha = Resolve(common, ref, 0);
        if (sha == kUnread) headUnread = YES;
        else if (sha) f[@"head"] = sha;   // nil: a branch with no commit yet
    } else if (IsSha(line)) f[@"head"] = line;
    else if (line) headUnread = YES;      // a HEAD git does not write
    if (headUnread) f[@"headUnread"] = @YES;
    f[@"index"] = Stamp([gitDir stringByAppendingPathComponent:@"index"]);

    // The default branch: origin/HEAD when the clone set it, else the usual names. One that cannot be known ends the
    // search, so no other name stands in for it.
    BOOL originUnread = NO;
    NSString *originHead = Line([common stringByAppendingPathComponent:@"refs/remotes/origin/HEAD"], &originUnread, YES);
    NSMutableArray *candidates = [NSMutableArray new];
    if ([originHead hasPrefix:@"ref: refs/"]) [candidates addObject:[originHead substringFromIndex:5]];
    if (!originUnread) [candidates addObjectsFromArray:@[@"refs/remotes/origin/main", @"refs/remotes/origin/master", @"refs/heads/main", @"refs/heads/master"]];
    for (NSString *ref in candidates) {
        NSString *tip = Resolve(common, ref, 0);
        if (tip == kUnread) break;
        if (!tip) continue;
        f[@"defRef"] = ref; f[@"defTip"] = tip;
        f[@"def"] = [ref hasPrefix:@"refs/remotes/"] ? [ref substringFromIndex:13] : [ref substringFromIndex:11];
        break;
    }

    // The upstream, as git's own config reader and @{upstream} give it, issue #118: MMGitConfig.m. A branch whose name
    // NameUsable refuses could read the section of another name that reads the same, so its upstream is not known.
    BOOL named = f[@"branch"] && NameUsable(f[@"branch"]);
    if ((f[@"branch"] && !named) || (headUnread && !f[@"branch"])) f[@"upUnread"] = @YES;
    id (^load)(NSString *) = ^id(NSString *p) { return ConfigItems(p); };
    NSDictionary *up = named ? MMGitOutsideUpstream(MMGitConfigUpstream(common, gitDir, f[@"branch"], load), f[@"branch"], load) : nil;
    if (up[@"unknown"]) f[@"upUnread"] = @YES;
    else if (up[@"ref"]) {
        NSString *ref = up[@"ref"];
        f[@"up"] = up[@"up"]; f[@"upRef"] = ref;
        NSString *tip = Resolve(common, ref, 0);
        if (tip == kUnread) f[@"upUnread"] = @YES;
        else if (tip) f[@"upTip"] = tip;
        else f[@"gone"] = @YES;
    }
    f[@"fetched"] = Stamp([common stringByAppendingPathComponent:@"FETCH_HEAD"]);
    f[@"packed"] = Stamp([common stringByAppendingPathComponent:@"packed-refs"]);
    f[@"stashes"] = @(headUnread && !f[@"branch"] ? -1 : StashesOn(common, f[@"branch"]));
    return f;
}

/// The status layer's fingerprint: HEAD and the index file. A change to a tracked file moves neither, so
/// MMRepoIndex drops this layer whenever FSEvents reports a change inside the worktree.
NSString *MMGitStatusFingerprint(NSDictionary *files) {
    return [NSString stringWithFormat:@"%@|%@", files[@"head"] ?: @"-", files[@"index"] ?: @"-"];
}

/// The history layer's fingerprint: everything the counts and the merge kind depend on.
NSString *MMGitHistoryFingerprint(NSDictionary *files, BOOL isMain) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%d", files[@"head"] ?: (files[@"headUnread"] ? @"?" : @"-"), files[@"defRef"] ?: @"-",
            files[@"defTip"] ?: @"-", files[@"upRef"] ?: @"-", files[@"upTip"] ?: @"-", files[@"fetched"] ?: @"-",
            files[@"packed"] ?: @"-", isMain];
}

#pragma mark - What git computes

static void Count(NSMutableDictionary *counts, NSString *key, NSInteger n) {
    if (!counts || !n) return;
    @synchronized (counts) { counts[key] = @([counts[key] integerValue] + n); }
}

static NSString *Git(NSString *dir, NSArray *args, NSTimeInterval timeout, int *st, NSMutableDictionary *counts) {
    Count(counts, @"gitRuns", 1);
    return MMGitInput(dir, args, nil, timeout, st);
}

/// Uncommitted and untracked counts from `git status`. -1 for both when git could not tell.
NSDictionary *MMGitStatusOf(NSString *dir, NSMutableDictionary *counts) {
    int st = -1;
    NSString *out = Git(dir, @[@"status", @"--porcelain=v1", @"--untracked-files=normal", @"--ignore-submodules=dirty"], kGitStatus, &st, counts);
    if (st != 0 || !out) return @{@"dirty": @(-1), @"untracked": @(-1)};
    NSInteger dirty = 0, untracked = 0;
    for (NSString *l in [out componentsSeparatedByString:@"\n"]) {
        if (l.length < 3) continue;
        if ([l hasPrefix:@"??"]) untracked++; else dirty++;
    }
    return @{@"dirty": @(dirty), @"untracked": @(untracked)};
}

static NSArray<NSString *> *Lines(NSString *s) {
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *l in [s componentsSeparatedByString:@"\n"]) if (l.length) [out addObject:l];
    return out;
}

/// "a\tb" from rev-list --left-right --count, as two numbers. NO when git failed.
static BOOL LeftRight(NSString *dir, NSString *range, NSInteger *left, NSInteger *right, NSMutableDictionary *counts) {
    int st = -1;
    NSString *out = Git(dir, @[@"rev-list", @"--left-right", @"--count", range, @"--"], kGitShort, &st, counts);
    NSArray *p = [out componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (st != 0 || p.count < 2) return NO;
    *left = [p.firstObject integerValue]; *right = [p.lastObject integerValue];
    return YES;
}

/// The patch id of every commit in shas, from the cache or computed now for the ones it has not seen.
/// A commit with an empty diff is stored as "", so it is not asked for again.
static NSDictionary<NSString *, NSString *> *PatchIds(NSString *dir, NSArray<NSString *> *shas, MMFactCache *cache,
                                                      NSMutableDictionary *counts) {
    NSMutableDictionary *ids = [NSMutableDictionary new];
    NSMutableArray *missing = [NSMutableArray new];
    for (NSString *c in shas) {
        NSString *v = [cache peek:c];
        if ([v isKindOfClass:NSString.class]) ids[c] = v; else [missing addObject:c];
    }
    if (!missing.count) return ids;
    Count(counts, @"gitRuns", 2);
    int st = -1;
    NSData *input = [[[missing componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *out = MMGitPatchIds(dir, @[@"diff-tree", @"--stdin", @"-p", @"--root", @"--no-color", @"--no-ext-diff", @"--no-renames"],
                                  input, kGitPatch, &st);
    if (st != 0 || !out) return ids;   // nothing stored, so the next check asks again
    for (NSString *line in Lines(out)) {
        NSArray *p = [line componentsSeparatedByString:@" "];
        if (p.count == 2) ids[p[1]] = p[0];
    }
    for (NSString *c in missing) {
        if (!ids[c]) ids[c] = @"";
        [cache setValue:ids[c] for:c fingerprint:@""];
    }
    Count(counts, @"patchIdsComputed", (NSInteger)missing.count);
    return ids;
}

/// Patch or squash: every branch commit, or the branch's whole change as one patch, equals a default-branch
/// commit made since the merge base. Only those commits can hold a merge of the branch.
static MMMergeKind PatchOrSquash(NSString *dir, NSString *def, NSString *head, MMFactCache *cache, NSMutableDictionary *counts) {
    Count(counts, @"squashChecks", 1);
    int st = -1;
    NSString *base = Git(dir, @[@"merge-base", def, head], kGitShort, &st, counts);
    if (st != 0 || !IsSha(base)) return MMMergedNone;
    NSArray *onDefault = Lines(Git(dir, @[@"rev-list", @"--no-merges", [NSString stringWithFormat:@"--max-count=%lu", (unsigned long)kDefaultCommits],
                                          [NSString stringWithFormat:@"%@..%@", base, def], @"--"], kGitShort, &st, counts));
    if (st != 0 || !onDefault.count) return MMMergedNone;   // the default branch did not move since the fork
    NSArray *onBranch = Lines(Git(dir, @[@"rev-list", @"--no-merges", [NSString stringWithFormat:@"--max-count=%lu", (unsigned long)kBranchCommits + 1],
                                         [NSString stringWithFormat:@"%@..%@", base, head], @"--"], kGitShort, &st, counts));
    if (st != 0) return MMMergedNone;
    BOOL perCommit = onBranch.count > 0 && onBranch.count <= kBranchCommits;
    NSDictionary *ids = PatchIds(dir, perCommit ? [onDefault arrayByAddingObjectsFromArray:onBranch] : onDefault, cache, counts);
    NSMutableSet *defaultIds = [NSMutableSet new];
    for (NSString *c in onDefault) if ([ids[c] length]) [defaultIds addObject:ids[c]];
    if (!defaultIds.count) return MMMergedNone;
    if (perCommit) {
        BOOL all = YES;
        for (NSString *c in onBranch) if (![ids[c] length] || ![defaultIds containsObject:ids[c]]) { all = NO; break; }
        if (all) return MMMergedPatch;
    }
    // The whole change from the merge base, keyed by both ends, which never change for a pair of commits.
    NSString *key = [NSString stringWithFormat:@"%@..%@", base, head];
    NSString *whole = [cache peek:key];
    if (![whole isKindOfClass:NSString.class]) {
        Count(counts, @"gitRuns", 2);
        NSString *out = MMGitPatchIds(dir, @[@"diff", @"--no-color", @"--no-ext-diff", @"--no-renames", base, head, @"--"], nil, kGitPatch, &st);
        if (st != 0 || !out) return MMMergedNone;
        whole = [out componentsSeparatedByString:@" "].firstObject ?: @"";
        whole = [whole stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [cache setValue:whole for:key fingerprint:@""];
        Count(counts, @"patchIdsComputed", 1);
    }
    return whole.length && [defaultIds containsObject:whole] ? MMMergedSquash : MMMergedNone;
}

/// The history layer: last commit time, counts against the default branch, the upstream and the remotes,
/// and how the branch reached the default branch. The main checkout is never called merged.
NSDictionary *MMGitHistoryOf(NSString *dir, NSDictionary *files, BOOL isMain, MMFactCache *patchIds, NSMutableDictionary *counts) {
    NSString *head = files[@"head"];
    // No commit yet, or issue #116, a HEAD that cannot be known: its commits are not counted, and so not 0.
    if (!head) return [files[@"headUnread"] boolValue] ? @{@"merged": @"none", @"notInDefault": @(-1), @"unpushed": @(-1)}
                                                       : @{@"merged": @"none", @"notInDefault": @0, @"unpushed": @0};
    NSMutableDictionary *h = [NSMutableDictionary new];
    int st = -1;
    NSString *ct = Git(dir, @[@"show", @"-s", @"--format=%ct", head, @"--"], kGitShort, &st, counts);
    if (st == 0 && ct.longLongValue > 0) h[@"lastCommit"] = @(ct.longLongValue);
    NSInteger left = 0, right = 0;
    NSString *def = files[@"defTip"];
    if (def) h[@"notInDefault"] = LeftRight(dir, [NSString stringWithFormat:@"%@...%@", def, head], &left, &right, counts) ? @(right) : @(-1);
    if (files[@"upTip"] && LeftRight(dir, [NSString stringWithFormat:@"%@...%@", files[@"upTip"], head], &left, &right, counts)) {
        h[@"behind"] = @(left); h[@"ahead"] = @(right);
    }
    NSString *n = Git(dir, @[@"rev-list", @"--count", head, @"--not", @"--remotes"], kGitShort, &st, counts);
    h[@"unpushed"] = st == 0 ? @(n.integerValue) : @(-1);
    h[@"onRemote"] = @(st == 0 && n.integerValue == 0);

    MMMergeKind kind = MMMergedNone;
    NSInteger notIn = Int(h[@"notInDefault"], -1);
    if (!isMain && def && notIn == 0) kind = MMMergedAncestor;
    else if (!isMain && def && notIn > 0) {
        Git(dir, @[@"diff", @"--quiet", @"--no-ext-diff", def, head, @"--"], kGitShort, &st, counts);
        if (st == 0) kind = MMMergedTree;
        else kind = PatchOrSquash(dir, def, head, patchIds, counts);
    }
    h[@"merged"] = MergeWords()[kind];
    return h;
}
