// Issue #120's review, B3: the CLI's fresh check. It links Sources but main.m and the shell, as the minmacs binary
// does, and prints JSON. Every path it gets lies in $MINMACS_HOME, and the index walks $MINMACS_ROOTS alone.
// Usage: outsidecli fresh <worktree> <config> <from> <to>
//   the cold source's facts, MMColdFacts, as a cold `minmacs tidy` plans on them; then config rewritten in place, from
//   replaced by to, which must be as long, with its size, inode and mtime to the nanosecond kept; then the source's
//   freshFactsFor: on a finding of the worktree, the check MMRunAction makes before it acts.
//   Each read is given as upstream|upstreamGone|upstreamUnknown|smart, as gittool keeps gives it.
#import <Foundation/Foundation.h>
#import "Core/Act/MMRemoval.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Know/MMGit.h"
#import "Core/Runtime/MMWorker.h"
#include <fcntl.h>
#include <sys/stat.h>

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

static NSString *Say(MMFacts *facts, NSString *path) {
    MMWorktree *w = nil;
    for (MMWorktree *x in facts.worktrees) if ([x.path.stringByStandardizingPath isEqualToString:path.stringByStandardizingPath]) w = x;
    MMGitFacts *g = w ? [facts gitFor:w] : nil;
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

/// block off main, as a cold verb's action runs, waited for.
static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ block(); dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
}

static int Fresh(NSString *path, NSString *config, NSString *from, NSString *to) {
    id<MMFactSource> source = [NSClassFromString(@"MMColdFacts") new];
    if (!source || from.length != to.length) { fprintf(stderr, "no cold source, or from and to differ in length\n"); return 2; }
    __block MMFacts *plan = nil, *fresh = nil;
    OffMain(^{ plan = [source factsFor:1]; });
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
    MMFinding *finding = [MMFinding expert:@"workforest" kind:@"worktree" stableKey:path build:^(MMFindingBuilder *b) { b.path = path; }];
    OffMain(^{ fresh = [source freshFactsFor:finding]; });
    Print(@{@"plan": Say(plan, path), @"fresh": Say(fresh, path), @"sameStamp": same ? @"yes" : @"no"});
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child, as `minmacs _walk`
        if (argc == 6 && !strcmp(argv[1], "fresh")) return Fresh(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        fprintf(stderr, "usage: outsidecli fresh <worktree> <config> <from> <to>\n");
        return 2;
    }
}
