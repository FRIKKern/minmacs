// Issue #120's tool. It links all of Sources/Core and prints JSON. Every path it gets lies in $MINMACS_HOME.
// Usage: outsidetool stale <worktree> <config> <from> <to>
//   the worktree's facts read fresh, factsFor:wait:YES as a removal reads them; then config rewritten in place, from
//   replaced by to, which must be as long, with its size, inode and mtime to the nanosecond kept; then read fresh again.
//        outsidetool window <worktree> <config> <from> <to>
//   a walk's read, as an update pass makes it; config rewritten, from replaced by to; a walk's read at once, a fresh
//   read, and a walk's read 1.2 seconds later.
//   Each read is given as upstream|upstreamGone|upstreamUnknown|smart, as gittool keeps gives it.
#import <Foundation/Foundation.h>
#import "Core/Act/MMRemoval.h"
#import "Core/Know/MMGit.h"
#import "Core/Runtime/MMWorker.h"
#include <fcntl.h>
#include <sys/stat.h>

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

/// The facts with Smart's answer on them.
static NSString *Say(MMWorktree *w, MMGitFacts *g) {
    if (!g) return @"no facts";
    MMRemovalFacts *f = [MMRemovalFacts worktreeKnown:YES merged:!w.isMain && g.merged != MMMergedNone upstreamGone:g.upstreamGone
                                                 dirty:g.dirty untracked:g.untracked unpushed:g.unpushed stashes:g.stashes];
    f.upstreamUnknown = g.upstreamUnknown; f.upstreamNone = !g.upstream.length && !g.upstreamGone && !g.upstreamUnknown;
    MMRemovalDecision *d = MMRemovalDecideWith(MMRemovalSmart, MMRemovalWorktree, f);
    return [NSString stringWithFormat:@"%@|%@|%@|%@", g.upstream.length ? g.upstream : @"None", g.upstreamGone ? @"True" : @"False",
            g.upstreamUnknown ? @"True" : @"False", d.deleteNow ? @"delete now" : [@"keep: " stringByAppendingString:d.why ?: @""]];
}

/// factsFor:wait:YES, off main as it must be.
static NSString *Fresh(MMWorktree *w) {
    __block MMGitFacts *g = nil;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ g = [MMRepoIndex.shared factsFor:w wait:YES]; dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
    return Say(w, g);
}

/// A walk's read: the worktree marked, one update pass waited for, and the facts it left, on core.git.N.
static NSString *Walk(MMWorktree *w) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    [MMRepoIndex.shared invalidate:[NSSet setWithObject:w.path] subtrees:NO];
    [MMRepoIndex.shared updateFacts:^(NSUInteger ran) { dispatch_semaphore_signal(s); }];
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    return Say(w, [MMRepoIndex.shared factsFor:w wait:NO]);
}

static NSString *StampOf(struct stat st) {
    return [NSString stringWithFormat:@"%ld.%09ld:%lld:%llu", (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec,
            (long long)st.st_size, (unsigned long long)st.st_ino];
}

static int Stale(NSString *path, NSString *config, NSString *from, NSString *to) {
    MMWorktree *w = [MMRepoIndex.shared worktreeAt:path];
    if (!w || from.length != to.length) { fprintf(stderr, "no worktree, or from and to differ in length\n"); return 2; }
    NSString *before = Fresh(w);
    struct stat st0, st1;
    if (stat(config.fileSystemRepresentation, &st0) != 0) return 2;
    NSString *text = [NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:nil];
    NSData *bytes = [[text stringByReplacingOccurrencesOfString:from withString:to] dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open(config.fileSystemRepresentation, O_WRONLY | O_TRUNC);
    if (fd < 0 || write(fd, bytes.bytes, bytes.length) != (ssize_t)bytes.length) return 2;
    struct timespec times[2] = {st0.st_atimespec, st0.st_mtimespec};
    futimens(fd, times);
    close(fd);
    stat(config.fileSystemRepresentation, &st1);
    BOOL same = [StampOf(st0) isEqualToString:StampOf(st1)] && ![text containsString:to];
    Print(@{@"before": before, @"after": Fresh(w), @"sameStamp": same ? @"yes" : @"no"});
    return 0;
}

/// For a walk's read the index walks its roots, $MINMACS_ROOTS, first.
static int Window(NSString *path, NSString *config, NSString *from, NSString *to) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    NSInteger done = [ix.stats[@"walksDone"] integerValue];
    [ix refresh:nil];
    for (int i = 0; i < 3000 && [ix.stats[@"walksDone"] integerValue] <= done; i++) usleep(10000);
    MMWorktree *w = [ix worktreeAt:path];
    if (!w) { fprintf(stderr, "no worktree\n"); return 2; }
    NSString *before = Walk(w);
    NSString *text = [NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:nil];
    if (![[text stringByReplacingOccurrencesOfString:from withString:to] writeToFile:config atomically:NO
                                                                             encoding:NSUTF8StringEncoding error:nil]) return 2;
    NSString *now = Walk(w), *fresh = Fresh(w);
    usleep(1200000);
    Print(@{@"before": before, @"walkNow": now, @"fresh": fresh, @"later": Walk(w)});
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child, as `minmacs _walk`
        if (argc == 6 && !strcmp(argv[1], "stale")) return Stale(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        if (argc == 6 && !strcmp(argv[1], "window")) return Window(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        fprintf(stderr, "usage: outsidetool stale|window <worktree> <config> <from> <to>\n");
        return 2;
    }
}
