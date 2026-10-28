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
#import <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

NSString *MMGitInput(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status);
NSString *MMGitPatchIds(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status);

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
@property (readwrite) BOOL onRemote, upstreamGone;
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
    g.upstreamGone = [f[@"gone"] boolValue];
    g.stashes = Int(f[@"stashes"], 0);
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
             @"upstreamGone": @(self.upstreamGone), @"merged": m < MergeWords().count ? MergeWords()[m] : @"none",
             @"dirty": @(self.dirty), @"untracked": @(self.untracked), @"stashes": @(self.stashes),
             @"notInDefault": @(self.notInDefault), @"unpushed": @(self.unpushed), @"ahead": @(self.ahead),
             @"behind": @(self.behind), @"onRemote": @(self.onRemote),
             @"lastCommit": self.lastCommit ? @(self.lastCommit.timeIntervalSince1970) : NSNull.null};
}

- (NSString *)description { return [NSString stringWithFormat:@"<MMGitFacts %@>", self.json]; }

@end

#pragma mark - git's own files

/// A small file's text, trimmed, or nil when it cannot be read or is not UTF-8: HEAD, a ref, a .git file, commondir.
/// Issue #54: open and read, since Foundation's file read cost most of a warm walk of 300 worktrees, which reads
/// about 15 such files each. A file over 4 KB is read by Foundation, as before.
NSString *MMReadLine(NSString *path) {
    if (!path.length) return nil;
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return nil;
    char buf[4096];
    ssize_t got = 0, n = 0;
    while (got < (ssize_t)sizeof buf && (n = read(fd, buf + got, sizeof buf - (size_t)got)) != 0) {
        if (n < 0) { if (errno == EINTR) continue; break; }
        got += n;
    }
    BOOL more = got == (ssize_t)sizeof buf;
    close(fd);
    if (n < 0) return nil;
    NSString *s = more ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
                       : [[NSString alloc] initWithBytes:buf length:(NSUInteger)got encoding:NSUTF8StringEncoding];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ReadLine(NSString *path) { return MMReadLine(path); }

/// mtime, size and inode, or "-" when the file is missing. A rewrite of the file always moves it.
static NSString *Stamp(NSString *path) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return @"-";
    return [NSString stringWithFormat:@"%ld.%09ld:%lld:%llu", (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec,
            (long long)st.st_size, (unsigned long long)st.st_ino];
}

static BOOL IsSha(NSString *s) {
    if (s.length != 40 && s.length != 64) return NO;
    return [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location == NSNotFound;
}

/// A file git rewrites whole, parsed once per stamp and kept per path.
static id Parsed(NSString *path, id (^parse)(NSString *text)) {
    static NSMutableDictionary<NSString *, NSArray *> *memo; static dispatch_once_t once;
    dispatch_once(&once, ^{ memo = [NSMutableDictionary new]; });
    NSString *stamp = Stamp(path);
    @synchronized (memo) {
        NSArray *hit = memo[path];
        if ([hit[0] isEqualToString:stamp]) return hit[1];
    }
    NSString *text = [stamp isEqualToString:@"-"] ? @"" :
        ([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"");
    id value = parse(text) ?: NSNull.null;
    @synchronized (memo) {
        if (memo.count > 512) [memo removeAllObjects];
        memo[path] = @[stamp, value];
    }
    return value;
}

/// packed-refs as ref name to sha.
static NSDictionary<NSString *, NSString *> *PackedRefs(NSString *common) {
    return Parsed([common stringByAppendingPathComponent:@"packed-refs"], ^id(NSString *text) {
        NSMutableDictionary *refs = [NSMutableDictionary new];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (line.length < 42 || [line hasPrefix:@"#"] || [line hasPrefix:@"^"]) continue;
            NSRange sp = [line rangeOfString:@" "];
            if (sp.location == NSNotFound) continue;
            refs[[line substringFromIndex:NSMaxRange(sp)]] = [line substringToIndex:sp.location];
        }
        return refs;
    });
}

/// The sha a ref names, from the loose file or packed-refs, following a symbolic ref twice at most. nil when none.
static NSString *Resolve(NSString *common, NSString *ref, int depth) {
    if (!ref.length || depth > 3 || [ref containsString:@".."]) return nil;
    NSString *line = ReadLine([common stringByAppendingPathComponent:ref]);
    if ([line hasPrefix:@"ref: "]) return Resolve(common, [line substringFromIndex:5], depth + 1);
    if (IsSha(line)) return line;
    NSDictionary *packed = PackedRefs(common);
    return [packed isKindOfClass:NSDictionary.class] ? Str(packed[ref]) : nil;
}

/// The [branch "x"] sections of config as {x: {remote, merge}}. Includes are not followed.
static NSDictionary<NSString *, NSDictionary *> *BranchConfig(NSString *common) {
    return Parsed([common stringByAppendingPathComponent:@"config"], ^id(NSString *text) {
        NSMutableDictionary *out = [NSMutableDictionary new];
        NSString *branch = nil;
        NSRegularExpression *head = [NSRegularExpression regularExpressionWithPattern:@"^\\[\\s*([A-Za-z0-9.-]+)(?:\\s+\"((?:[^\"\\\\]|\\\\.)*)\")?\\s*\\]"
                                                                              options:0 error:nil];
        for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
            NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@";"]) continue;
            if ([line hasPrefix:@"["]) {
                NSTextCheckingResult *m = [head firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
                branch = nil;
                if (m && [[line substringWithRange:[m rangeAtIndex:1]].lowercaseString isEqualToString:@"branch"] &&
                    [m rangeAtIndex:2].location != NSNotFound)
                    branch = [[line substringWithRange:[m rangeAtIndex:2]] stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
                continue;
            }
            if (!branch) continue;
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *key = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
            NSString *val = [[line substringFromIndex:NSMaxRange(eq)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (val.length >= 2 && [val hasPrefix:@"\""] && [val hasSuffix:@"\""]) val = [val substringWithRange:NSMakeRange(1, val.length - 2)];
            if (![key isEqualToString:@"remote"] && ![key isEqualToString:@"merge"]) continue;
            NSMutableDictionary *b = out[branch] ?: [NSMutableDictionary new];
            b[key] = val;
            out[branch] = b;
        }
        return out;
    });
}

/// The stash entries made on branch, from logs/refs/stash: "WIP on <branch>:" or "On <branch>:".
static NSInteger StashesOn(NSString *common, NSString *branch) {
    if (!branch.length) return 0;
    NSArray *lines = Parsed([common stringByAppendingPathComponent:@"logs/refs/stash"], ^id(NSString *text) {
        NSMutableArray *subjects = [NSMutableArray new];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSRange tab = [line rangeOfString:@"\t"];
            if (tab.location != NSNotFound) [subjects addObject:[line substringFromIndex:NSMaxRange(tab)]];
        }
        return subjects;
    });
    if (![lines isKindOfClass:NSArray.class]) return 0;
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
    NSString *common = ReadLine([gitDir stringByAppendingPathComponent:@"commondir"]);
    if (!common.length) return @{@"gitDir": gitDir, @"common": gitDir};   // a submodule keeps its own refs
    if (!common.isAbsolutePath) common = [gitDir stringByAppendingPathComponent:common];
    return @{@"gitDir": gitDir, @"common": common.stringByStandardizingPath};
}

/// Everything git's files tell with no spawn, plus the stamps the fingerprints are made of.
NSDictionary *MMGitReadFiles(NSString *gitDir, NSString *common) {
    NSMutableDictionary *f = [NSMutableDictionary new];
    NSString *line = ReadLine([gitDir stringByAppendingPathComponent:@"HEAD"]);
    if ([line hasPrefix:@"ref: "]) {
        NSString *ref = [line substringFromIndex:5];
        if ([ref hasPrefix:@"refs/heads/"]) f[@"branch"] = [ref substringFromIndex:11];
        NSString *sha = Resolve(common, ref, 0);
        if (sha) f[@"head"] = sha;
    } else if (IsSha(line)) f[@"head"] = line;
    f[@"index"] = Stamp([gitDir stringByAppendingPathComponent:@"index"]);

    // The default branch: origin/HEAD when the clone set it, else the usual names.
    NSString *originHead = ReadLine([common stringByAppendingPathComponent:@"refs/remotes/origin/HEAD"]);
    NSMutableArray *candidates = [NSMutableArray new];
    if ([originHead hasPrefix:@"ref: refs/"]) [candidates addObject:[originHead substringFromIndex:5]];
    [candidates addObjectsFromArray:@[@"refs/remotes/origin/main", @"refs/remotes/origin/master", @"refs/heads/main", @"refs/heads/master"]];
    for (NSString *ref in candidates) {
        NSString *tip = Resolve(common, ref, 0);
        if (!tip) continue;
        f[@"defRef"] = ref; f[@"defTip"] = tip;
        f[@"def"] = [ref hasPrefix:@"refs/remotes/"] ? [ref substringFromIndex:13] : [ref substringFromIndex:11];
        break;
    }

    // The upstream, from [branch "x"] remote and merge.
    NSDictionary *cfg = f[@"branch"] ? BranchConfig(common) : nil;
    NSDictionary *b = [cfg isKindOfClass:NSDictionary.class] ? cfg[f[@"branch"]] : nil;
    NSString *remote = Str(b[@"remote"]), *merge = Str(b[@"merge"]);
    if (remote && [merge hasPrefix:@"refs/heads/"]) {
        NSString *name = [merge substringFromIndex:11];
        NSString *ref = [remote isEqualToString:@"."] ? merge : [NSString stringWithFormat:@"refs/remotes/%@/%@", remote, name];
        f[@"up"] = [remote isEqualToString:@"."] ? name : [NSString stringWithFormat:@"%@/%@", remote, name];
        f[@"upRef"] = ref;
        NSString *tip = Resolve(common, ref, 0);
        if (tip) f[@"upTip"] = tip; else f[@"gone"] = @YES;
    }
    f[@"fetched"] = Stamp([common stringByAppendingPathComponent:@"FETCH_HEAD"]);
    f[@"packed"] = Stamp([common stringByAppendingPathComponent:@"packed-refs"]);
    f[@"stashes"] = @(StashesOn(common, f[@"branch"]));
    return f;
}

/// The status layer's fingerprint: HEAD and the index file. A change to a tracked file moves neither, so
/// MMRepoIndex drops this layer whenever FSEvents reports a change inside the worktree.
NSString *MMGitStatusFingerprint(NSDictionary *files) {
    return [NSString stringWithFormat:@"%@|%@", files[@"head"] ?: @"-", files[@"index"] ?: @"-"];
}

/// The history layer's fingerprint: everything the counts and the merge kind depend on.
NSString *MMGitHistoryFingerprint(NSDictionary *files, BOOL isMain) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%d", files[@"head"] ?: @"-", files[@"defRef"] ?: @"-",
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
    if (!head) return @{@"merged": @"none", @"notInDefault": @0, @"unpushed": @0};   // no commit yet
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
