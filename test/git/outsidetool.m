// Issue #120's tool. It links all of Sources/Core and prints JSON. Every path it gets lies in $MINMACS_HOME.
// Usage: outsidetool stale <worktree> <config> <from> <to>
//   the worktree's facts read fresh, factsFor:wait:YES as a removal reads them; then config rewritten in place, from
//   replaced by to, which must be as long, with its size, inode and mtime to the nanosecond kept; then read fresh again.
//   Each read is given as upstream|upstreamGone|upstreamUnknown|smart, as gittool keeps gives it.
#import <Foundation/Foundation.h>
#import "Core/Act/MMRemoval.h"
#import "Core/Know/MMGit.h"
#include <fcntl.h>
#include <sys/stat.h>

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

/// factsFor:wait:YES, off main as it must be, with Smart's answer on them.
static NSString *Fresh(MMWorktree *w) {
    __block MMGitFacts *g = nil;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ g = [MMRepoIndex.shared factsFor:w wait:YES]; dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
    if (!g) return @"no facts";
    MMRemovalFacts *f = [MMRemovalFacts worktreeKnown:YES merged:!w.isMain && g.merged != MMMergedNone upstreamGone:g.upstreamGone
                                                 dirty:g.dirty untracked:g.untracked unpushed:g.unpushed stashes:g.stashes];
    f.upstreamUnknown = g.upstreamUnknown; f.upstreamNone = !g.upstream.length && !g.upstreamGone && !g.upstreamUnknown;
    MMRemovalDecision *d = MMRemovalDecideWith(MMRemovalSmart, MMRemovalWorktree, f);
    return [NSString stringWithFormat:@"%@|%@|%@|%@", g.upstream.length ? g.upstream : @"None", g.upstreamGone ? @"True" : @"False",
            g.upstreamUnknown ? @"True" : @"False", d.deleteNow ? @"delete now" : [@"keep: " stringByAppendingString:d.why ?: @""]];
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

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 6 && !strcmp(argv[1], "stale")) return Stale(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        fprintf(stderr, "usage: outsidetool stale <worktree> <config> <from> <to>\n");
        return 2;
    }
}
