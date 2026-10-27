// Worktree removal, part of P52. See MMWorktreeAct.h. Ported from WFRemove and SaveIgnored in WorkForest's Forest.m.
#import "Core/Act/MMWorktreeAct.h"
#import "Core/Know/MMGit.h"

/// git with the caller's environment, as the undo engine runs it, plus no optional locks, no prompts and the C locale.
static int Git(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, NSString **output) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    t.arguments = [@[@"-C", dir, @"--no-pager"] arrayByAddingObjectsFromArray:args];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"GIT_OPTIONAL_LOCKS"] = @"0"; env[@"GIT_TERMINAL_PROMPT"] = @"0"; env[@"LC_ALL"] = @"C";
    t.environment = env;
    NSData *o = nil, *x = nil;
    MMRunResult r = MMRunTask(t, nil, timeout, &o, &x);
    if (output) {
        NSMutableData *all = [o ?: NSData.data mutableCopy];
        if (!o.length) [all appendData:x ?: NSData.data];
        *output = [[[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding] ?: @""
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (!r.didRun || r.timedOut) return -1;
    return r.status;
}

NSArray<NSString *> *MMWorktreeIgnoredFiles(NSString *worktree, NSArray<NSString *> *cacheNames) {
    if (!worktree.length) return nil;
    NSString *out = nil;
    int st = Git(worktree, @[@"ls-files", @"--others", @"--ignored", @"--exclude-standard", @"--directory", @"--no-empty-directory"], 30, &out);
    if (st != 0) return nil;
    NSSet *caches = [NSSet setWithArray:cacheNames ?: @[]];
    NSMutableArray *files = [NSMutableArray new];
    for (NSString *raw in [out componentsSeparatedByString:@"\n"]) {
        NSString *rel = [raw hasSuffix:@"/"] ? [raw substringToIndex:raw.length - 1] : raw;
        if (!rel.length) continue;
        BOOL cache = NO;
        for (NSString *c in rel.pathComponents) if ([caches containsObject:c] || [c isEqualToString:@".DS_Store"]) { cache = YES; break; }
        if (!cache) [files addObject:rel];
    }
    return files;
}

BOOL MMWorktreeRemove(NSString *repo, NSString *worktree, NSString *branch, BOOL deleteBranch,
                      BOOL *branchDeleted, NSString **error) {
    if (branchDeleted) *branchDeleted = NO;
    if (!repo.length || !worktree.length || [repo isEqualToString:worktree]) {
        if (error) *error = @"a main checkout is never removed";
        return NO;
    }
    NSString *out = nil;
    if (Git(repo, @[@"worktree", @"remove", worktree], 120, &out) != 0) {
        if (error) *error = [NSString stringWithFormat:@"git worktree remove refused, and the worktree is unchanged: %@",
                             out.length > 300 ? [out substringToIndex:300] : out ?: @""];
        return NO;
    }
    if (deleteBranch && branch.length) {
        BOOL gone = Git(repo, @[@"branch", @"-d", branch], 30, nil) == 0;
        if (branchDeleted) *branchDeleted = gone;
    }
    return YES;
}

BOOL MMWorktreePrune(NSString *repo, NSString **output) {
    if (!repo.length) return NO;
    return Git(repo, @[@"worktree", @"prune", @"--verbose"], 30, output) == 0;
}
