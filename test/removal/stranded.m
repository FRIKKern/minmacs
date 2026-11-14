// Included by staged.m. The second review of #64: nothing may be left stranded in the staging folder.
// A symlink that points nowhere while it waits, a put-back that stopped halfway, a crash followed by a quick
// restart, a crash with things in the Trash, a staging folder the wall would never let be emptied, and what an ended
// Wrap Up left behind. Every file is a fixture under <dir>, inside $MINMACS_HOME.
#import <sys/wait.h>

static NSString *LinkOf(NSString *path) { return [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:path error:nil] ?: @"(no link)"; }

/// A part of parent that stages each path under Delete. Returns the finished record, or the pending one.
static MMUndoRecord *StageMany(MMUndoRecord *parent, NSString *subject, NSArray<NSString *> *paths, BOOL finish) {
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *part = Part(parent.rid, subject);
    MMRemovalNote(part, del, nil);
    MMRemovalAsk(part, paths);
    for (NSString *p in paths) MMRemovalApply(p, del, part, nil);
    if (!finish) return part;
    MMRemovalDone(part, nil);
    return Done(part);
}
/// A Wrap Up record that never finished, owned as given: nil for no owner.
static MMUndoRecord *Unfinished(NSString *subject, NSString *tree, NSDictionary *owner) {
    MMUndoRecord *parent = Begin(@"wrapup", subject);
    NSMutableDictionary *p = [@{@"path": tree} mutableCopy];
    if (owner) p[@"owner"] = owner;
    [MMUndo.shared note:parent payload:p];
    return parent;
}
/// The pid of a process this test started and that has ended, so nobody owns it now.
static NSDictionary *GoneOwner(void) {
    pid_t pid = fork();
    if (pid == 0) _exit(0);
    int st; waitpid(pid, &st, 0);
    return @{@"pid": @(pid), @"start": @1};
}
static NSString *StateWord(MMUndoRecord *r) { return @[@"pending", @"done", @"failed", @"restored"][[MMUndo.shared record:r.rid].state]; }
static NSString *GitStatus(NSString *repo) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    t.arguments = @[@"-C", repo, @"status", @"--porcelain", @"--untracked-files=all"];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p; t.standardError = p;
    if (![t launchAndReturnError:nil]) return @"git would not start";
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void Stranded(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = Path(@"stranded"), *tree = [base stringByAppendingPathComponent:@"wt"];
    NSString *plain = [tree stringByAppendingPathComponent:@".env"], *link = [tree stringByAppendingPathComponent:@".env.local"];
    Write([base stringByAppendingPathComponent:@"main/.env.local"], @"SHARED=1");
    Write(plain, @"PLAIN=1");
    [fm createSymbolicLinkAtPath:link withDestinationPath:@"../main/.env.local" error:nil];

    // 1. A relative symlink points nowhere while it waits in the staging folder. It is still there.
    MMUndoRecord *parent = Unfinished(@"links", tree, nil);
    MMUndoRecord *part = StageMany(parent, @"config with a link", @[plain, link], YES);
    NSString *folder = part.payload[@"stagedIn"];
    T(@"put back: both are staged, the link as a link", @"2 no no", [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)[part.payload[@"staged"] count], YN(Exists(plain)), YN(Exists(link))]);
    T(@"put back: a relative symlink goes back as the same link, and the plain file beside it goes back too", @"nil ../main/.env.local SHARED=1 PLAIN=1 no restored",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", Or(MMRemovalPutBack(@[part])), LinkOf(link), Read(link), Read(plain), YN(Exists(folder)), StateWord(part)]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    // The same through crash recovery, for a Wrap Up whose process is gone.
    parent = Unfinished(@"links after a crash", tree, GoneOwner());
    part = StageMany(parent, @"config with a link, crashed", @[plain, link], YES);
    folder = part.payload[@"stagedIn"];
    NSInteger n = MMRemovalRecoverStaged();
    T(@"crash: a relative symlink goes back as the same link, and the plain file beside it goes back too", @"1 ../main/.env.local SHARED=1 PLAIN=1 no failed",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@", (long)n, LinkOf(link), Read(link), Read(plain), YN(Exists(folder)), StateWord(parent)]);
    // A link whose target does not exist at all is still an item, and goes back as it was.
    NSString *dangling = [tree stringByAppendingPathComponent:@".dangling"];
    [fm createSymbolicLinkAtPath:dangling withDestinationPath:@"nowhere/at/all" error:nil];
    parent = Unfinished(@"dangling", tree, nil);
    part = StageMany(parent, @"a dangling link", @[dangling], YES);
    T(@"put back: a link that points nowhere at all goes back as the same link", @"nil nowhere/at/all", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalPutBack(@[part])), LinkOf(dangling)]);
    [fm removeItemAtPath:dangling error:nil];
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // 2. A put-back that stopped halfway: one old folder cannot be written to. The other item still goes back, and a
    // second put-back moves the rest.
    NSString *rw = [base stringByAppendingPathComponent:@"half/rw/.env"], *ro = [base stringByAppendingPathComponent:@"half/ro/.env"];
    Write(rw, @"RW=1"); Write(ro, @"RO=1");
    parent = Unfinished(@"halfway", [base stringByAppendingPathComponent:@"half"], nil);
    part = StageMany(parent, @"two files", @[rw, ro], YES);
    folder = part.payload[@"stagedIn"];
    chmod(ro.stringByDeletingLastPathComponent.fileSystemRepresentation, 0500);
    NSString *first = MMRemovalPutBack(@[part]);
    T(@"put back: one item that cannot go back does not hold the other, and it is reported", @"yes RW=1 no done yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
      YN([first containsString:@".env could not leave MinMacs's staging folder"]), Read(rw), YN(Exists(ro)), StateWord(part), YN(Exists(folder))]);
    chmod(ro.stringByDeletingLastPathComponent.fileSystemRepresentation, 0700);
    T(@"put back: after a put-back that stopped halfway, a second one moves the rest", @"nil RW=1 RO=1 restored no", [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
      Or(MMRemovalPutBack(@[[MMUndo.shared record:part.rid]])), Read(rw), Read(ro), StateWord(part), YN(Exists(folder))]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
    // Gone from staging, and another file at the old path: that is not "already back", and nothing is written over.
    parent = Unfinished(@"swapped old path", tree, nil);
    part = StageMany(parent, @"one file", @[plain], YES);
    NSString *to = [part.payload[@"staged"] firstObject][@"to"];
    [fm removeItemAtPath:to error:nil];
    Write(plain, @"SOMEONE ELSE");
    T(@"put back: another file at the old path is not taken for the staged one", @"yes SOMEONE ELSE done", [NSString stringWithFormat:@"%@ %@ %@",
      YN([MMRemovalPutBack(@[part]) containsString:@"something else sits at"]), Read(plain), StateWord(part)]);
    Write(plain, @"PLAIN=1");
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // 3. Whose Wrap Up it is decides, not its age. Gone: settled at once. Alive: never touched.
    parent = Unfinished(@"owner gone", tree, GoneOwner());
    part = StageMany(parent, @"config, owner gone", @[plain], YES);
    n = MMRemovalRecoverStaged();
    T(@"crash: a record whose process is gone is settled at once", @"1 PLAIN=1 failed restored", [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, Read(plain), StateWord(parent), StateWord(part)]);
    parent = Unfinished(@"owner alive", tree, MMRemovalOwner());
    part = StageMany(parent, @"config, owner alive", @[plain], YES);
    setenv("MINMACS_STAGE_RECOVER_AFTER", "0", 1);
    n = MMRemovalRecoverStaged();
    T(@"crash: a record whose process is alive is left alone, even when old", @"0 no pending done", [NSString stringWithFormat:@"%ld %@ %@ %@", (long)n, YN(Exists(plain)), StateWord(parent), StateWord(part)]);
    unsetenv("MINMACS_STAGE_RECOVER_AFTER");
    // The same pid with another start time is another process: the owner is gone.
    NSMutableDictionary *reused = [MMRemovalOwner() mutableCopy];
    reused[@"start"] = @([reused[@"start"] unsignedLongLongValue] - 1000);
    [MMUndo.shared note:parent payload:@{@"owner": reused}];
    n = MMRemovalRecoverStaged();
    T(@"crash: a pid that is another process now does not count as the owner", @"1 PLAIN=1 failed", [NSString stringWithFormat:@"%ld %@ %@", (long)n, Read(plain), StateWord(parent)]);
    T(@"owner: this process is named by pid and start time, and is alive", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN([MMRemovalOwner()[@"pid"] intValue] == getpid()),
      YN([MMRemovalOwner()[@"start"] unsignedLongLongValue] > 0)]);

    // 4. A crash with things in the Trash: they are moved back out, never deleted, never over something, and no
    // record stays pending.
    MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalConfigFiles, nil);
    parent = Unfinished(@"trash crash", tree, GoneOwner());
    MMUndoRecord *trashed = Part(parent.rid, @"config to the Trash");
    MMRemovalNote(trashed, keep, nil); MMRemovalAsk(trashed, @[plain]);
    MMRemovalApply(plain, keep, trashed, nil);
    MMRemovalDone(trashed, nil);
    trashed = Done(trashed);
    MMUndoRecord *staged = StageMany(parent, @"caches staged", @[link], YES);
    MMUndoRecord *running = Part(parent.rid, @"a part that was still running");
    NSString *inTrash = [trashed.payload[@"trashed"] firstObject][@"to"];
    T(@"crash: before recovery one waits in the Trash, one in the staging folder, and three records are unfinished or done", @"yes no no pending",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN(Exists(inTrash)), YN(Exists(plain)), YN(Exists(link)), StateWord(running)]);
    n = MMRemovalRecoverStaged();
    T(@"crash: what a part sent to the Trash goes back too, and the record is no longer pending", @"1 PLAIN=1 no ../main/.env.local failed restored restored failed",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@ %@ %@ %@", (long)n, Read(plain), YN(Exists(inTrash)), LinkOf(link), StateWord(parent), StateWord(trashed), StateWord(staged), StateWord(running)]);
    T(@"crash: the Wrap Up's record says so", @"MinMacs stopped before this Wrap Up ended. What it had moved out of the worktree was put back", [MMUndo.shared record:parent.rid].error);
    // Something sits at the old path by then: the Trash keeps its item, and the record says what did not go back.
    parent = Unfinished(@"trash crash, old path taken", tree, GoneOwner());
    trashed = Part(parent.rid, @"config to the Trash again");
    MMRemovalNote(trashed, keep, nil); MMRemovalAsk(trashed, @[plain]);
    MMRemovalApply(plain, keep, trashed, nil);
    MMRemovalDone(trashed, nil);
    trashed = Done(trashed);
    inTrash = [trashed.payload[@"trashed"] firstObject][@"to"];
    Write(plain, @"NEWER=1");
    n = MMRemovalRecoverStaged();
    T(@"crash: with something at the old path the Trash keeps its item, nothing is written over, and the record is failed, not pending", @"1 NEWER=1 PLAIN=1 failed yes",
      [NSString stringWithFormat:@"%ld %@ %@ %@ %@", (long)n, Read(plain), Read(inTrash), StateWord(parent), YN([[MMUndo.shared record:parent.rid].error containsString:@", except: "])]);
    [fm removeItemAtPath:plain error:nil];
    T(@"crash: its restore then brings it back from the Trash", @"nil PLAIN=1", [NSString stringWithFormat:@"%@ %@", Or([MMUndo.shared restore:trashed.rid]), Read(plain)]);

    // 5. A staging folder the wall would never let be emptied: the item is not staged.
    MMRemovalPlaces *disk = Places(@"/Users/me", @"/Volumes/D", nil, NO);
    T(@"staging: an item whose staging folder would sit too near the top of its volume is not staged", @"it is too near the top of its volume|may stage|may stage", [@[
      MMRemovalStagingFolderWhyNot(@"/Volumes/D/.minmacs-staged-abc123", disk) ?: @"may stage",
      MMRemovalStagingFolderWhyNot(@"/Volumes/D/code/.minmacs-staged-abc123", disk) ?: @"may stage",
      MMRemovalStagingFolderWhyNot(@"/Users/me/Library/Application Support/MinMacs/staged/abc123", Places(@"/Users/me", @"/", nil, NO)) ?: @"may stage"] componentsJoinedByString:@"|"]);
    T(@"staging: nor one whose staging folder would sit at the top of the home folder", @"it is a folder at the top of the home folder", MMRemovalStagingFolderWhyNot(@"/Users/me", Places(@"/Users/me", @"/", nil, NO)) ?: @"may stage");
    // On the disk: a worktree whose holder is MINMACS_HOME's own parent would stage outside the test home, which the
    // wall refuses. The item stays where it is, no folder is made there, and the part does not say deleted.
    setenv("MINMACS_STAGE_BESIDE", "1", 1);
    NSString *outside = MMRemovalRealPath(MMSupportDir()).stringByDeletingLastPathComponent;
    parent = Unfinished(@"folder outside the wall", MMRemovalRealPath(MMSupportDir()), nil);
    part = StageMany(parent, @"config beside a top-level tree", @[plain], YES);
    T(@"staging: with a staging folder the wall refuses, the item stays where it is and no folder is made", @"PLAIN=1 0 1 0 no yes", [NSString stringWithFormat:@"%@ %lu %lu %@ %@ %@", Read(plain),
      (unsigned long)[part.payload[@"staged"] count], (unsigned long)[part.payload[@"unstaged"] count], part.payload[@"removal"][@"deleted"],
      YN(Exists([outside stringByAppendingPathComponent:[@".minmacs-staged-" stringByAppendingString:parent.rid]])),
      YN([[part.payload[@"unstaged"] firstObject][@"why"] hasPrefix:@"its staging folder would lie where MinMacs never deletes: "])]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // 6b. Beside a worktree inside another repo, as a main checkout holds .worktrees/: git does not list the folder.
    NSString *repo = [base stringByAppendingPathComponent:@"repo"], *inner = [repo stringByAppendingPathComponent:@".worktrees/feat"], *env = [inner stringByAppendingPathComponent:@".env.local"];
    Write(env, @"IN=1");
    NSTask *init = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/git"] arguments:@[@"init", @"-q", repo] error:nil terminationHandler:nil];
    [init waitUntilExit];
    NSString *before = GitStatus(repo);
    parent = Unfinished(@"inside a repo", inner, nil);
    part = StageMany(parent, @"config in a nested worktree", @[env], YES);
    folder = part.payload[@"stagedIn"];
    T(@"beside: in a repo that holds the worktree, git lists the file before and nothing of the staging folder while it waits", @"?? .worktrees/feat/.env.local|yes|",
      [NSString stringWithFormat:@"%@|%@|%@", before, YN([folder hasPrefix:[repo stringByAppendingString:@"/.worktrees/.minmacs-staged-"]] && Exists([part.payload[@"staged"] firstObject][@"to"])), GitStatus(repo)]);
    T(@"beside: put back removes the folder with its marker and its .gitignore", @"nil IN=1 no", [NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[part])), Read(env), YN(Exists(folder))]);
    unsetenv("MINMACS_STAGE_BESIDE");
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];

    // 6a. What an ended Wrap Up left staged: the record still names it, so it goes back. Nothing is deleted.
    parent = Unfinished(@"ended with leftovers", tree, nil);
    part = StageMany(parent, @"config left staged", @[plain], YES);
    folder = part.payload[@"stagedIn"];
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
    NSString *orphan = [[MMRemovalRealPath(MMSupportDir()) stringByAppendingPathComponent:@"staged"] stringByAppendingPathComponent:@"nobodys"];
    Write([orphan stringByAppendingPathComponent:@"0.notes.txt"], @"whose?");
    Write([orphan stringByAppendingPathComponent:@".minmacs"], @"nobodys");
    NSArray<NSString *> *orphans = nil;
    NSInteger back = MMRemovalSweepStaged(&orphans);
    T(@"sweep: what an ended Wrap Up left staged goes back to its old path, and its folder goes", @"yes PLAIN=1 no restored", [NSString stringWithFormat:@"%@ %@ %@ %@", YN(back >= 1), Read(plain), YN(Exists(folder)), StateWord(part)]);
    T(@"sweep: a staging folder no record names is left as it is, and named", @"whose? yes", [NSString stringWithFormat:@"%@ %@", Read([orphan stringByAppendingPathComponent:@"0.notes.txt"]), YN([orphans containsObject:orphan])]);
    orphans = nil;
    (void)MMRemovalSweepStaged(&orphans);
    T(@"sweep: it is named once, and still left as it is", @"no whose?", [NSString stringWithFormat:@"%@ %@", YN([orphans containsObject:orphan]), Read([orphan stringByAppendingPathComponent:@"0.notes.txt"])]);
    // A Wrap Up that still runs is not the sweep's.
    parent = Unfinished(@"still running", tree, MMRemovalOwner());
    part = StageMany(parent, @"config of a running one", @[plain], YES);
    (void)MMRemovalSweepStaged(NULL);
    T(@"sweep: what a Wrap Up that still runs has staged is not touched", @"no done", [NSString stringWithFormat:@"%@ %@", YN(Exists(plain)), StateWord(part)]);
    (void)MMRemovalPutBack(@[part]);
    [MMUndo.shared finish:parent ok:NO freed:0 error:@"test"];
}

// An owner that cannot be read, a damaged record, and a file that only sits where the item waited.
#import "owner.m"
