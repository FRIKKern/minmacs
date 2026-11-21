// Issue #120's review, B3: the CLI's fresh check. It links Sources but main.m and the shell, as the minmacs binary
// does, and prints JSON. Every path it gets lies in $MINMACS_HOME, and the index walks $MINMACS_ROOTS alone.
// Usage: outsidecli fresh <worktree> <config> <from> <to>
//   the cold source's facts, MMColdFacts, as a cold `minmacs tidy` plans on them; then config rewritten in place, from
//   replaced by to, which must be as long, with its size, inode and mtime to the nanosecond kept; then the source's
//   freshFactsFor: on a finding of the worktree, the check MMRunAction makes before it acts.
//        outsidecli race <worktree> <config> <from> <to>
//   round 2, B4: the cold plan's facts; then an update pass on core.git.N reads the worktree and is held before it
//   writes the index; config rewritten, from replaced by to; then freshFactsFor:, during which the held pass is let go
//   once the fresh read is done (at the sessions' refresh, which ColdFacts runs next) and writes its old answer.
//   Each read is given as upstream|upstreamGone|upstreamUnknown|smart, as gittool keeps gives it.
//   Built with MM_TESTS, for MMRepoIndexTestStep, which only orders the threads.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Core/Act/MMRemoval.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMSessions.h"
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

static dispatch_semaphore_t gRead, gRelease;
static _Atomic int gArmed, gHeld;
static IMP gRefresh;
static MMWorktree *gWorktree;

/// MMSessions's refresh, which ColdFacts runs right after the fresh read: the held pass is let go here, and its
/// write waited for, at most 10 s, so the index holds the pass's old answer when ColdFacts reads it.
static void Refresh(id self, SEL _cmd) {
    ((void (*)(id, SEL))gRefresh)(self, _cmd);
    if (gArmed != 1) return;
    gArmed = 2;
    dispatch_semaphore_signal(gRelease);
    for (int i = 0; i < 1000 && ![MMRepoIndex.shared factsFor:gWorktree wait:NO].upstreamGone; i++) usleep(10000);
}

static int Race(NSString *path, NSString *config, NSString *from, NSString *to) {
    id<MMFactSource> source = [NSClassFromString(@"MMColdFacts") new];
    if (!source) return 2;
    __block MMFacts *plan = nil, *fresh = nil;
    OffMain(^{ plan = [source factsFor:1]; });
    MMRepoIndex *ix = MMRepoIndex.shared;
    MMWorktree *w = [ix worktreeAt:path];
    if (!w) { fprintf(stderr, "no worktree\n"); return 2; }
    gRead = dispatch_semaphore_create(0); gRelease = dispatch_semaphore_create(0);
    NSString *key = w.path;
    MMRepoIndexTestStep = ^(NSString *step, NSString *p) {
        if (MMGitOnFreshRead() || ![p isEqualToString:key] || gHeld || ![step isEqualToString:@"write"]) return;
        gHeld = 1;
        dispatch_semaphore_signal(gRead);
        dispatch_semaphore_wait(gRelease, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
    };
    [ix invalidate:[NSSet setWithObject:w.path] subtrees:NO];   // a walk's pass, which reads the files before the change
    [ix updateFacts:nil];
    if (dispatch_semaphore_wait(gRead, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) { fprintf(stderr, "no pass\n"); return 2; }
    NSString *text = [NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:nil];
    if (![[text stringByReplacingOccurrencesOfString:from withString:to] writeToFile:config atomically:NO
                                                                             encoding:NSUTF8StringEncoding error:nil]) return 2;
    Method m = class_getInstanceMethod(MMSessions.class, @selector(refresh));
    gRefresh = method_setImplementation(m, (IMP)Refresh);
    MMFinding *finding = [MMFinding expert:@"workforest" kind:@"worktree" stableKey:path build:^(MMFindingBuilder *b) { b.path = path; }];
    gWorktree = w;
    gArmed = 1;
    OffMain(^{ fresh = [source freshFactsFor:finding]; });
    __block MMGitFacts *after = nil;
    OffMain(^{ after = [ix factsFor:w wait:NO]; });
    Print(@{@"plan": Say(plan, path), @"fresh": Say(fresh, path), @"released": gArmed == 2 ? @"yes" : @"no",
            @"index": after.upstreamGone ? @"gone" : after.upstreamUnknown ? @"unknown" : @"other"});
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();   // the worker child, as `minmacs _walk`
        if (argc == 6 && !strcmp(argv[1], "fresh")) return Fresh(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        if (argc == 6 && !strcmp(argv[1], "race")) return Race(@(argv[2]), @(argv[3]), @(argv[4]), @(argv[5]));
        fprintf(stderr, "usage: outsidecli fresh|race <worktree> <config> <from> <to>\n");
        return 2;
    }
}
