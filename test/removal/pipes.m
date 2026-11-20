// Included by moved.m. Issue #81: an open of a named pipe waits until a writer comes, so a removal whose item was a
// pipe never came back. A pipe or a socket is now never opened: its real path is the real path of its folder and
// its own name as that folder lists it, and it is staged, put back and deleted by that name, as any other item is.
// An item with a second name elsewhere, a hard link, goes by the name that was asked, and the other name stays.
//
//   Pipes ──▶ removaltest --pipe <case> <dir> ──▶ one line per check
//             a second process, ended by its own alarm after kPipeLimit seconds
//
// So a wait on a pipe fails the checks of one case and never holds the run, and what a case made is removed when it
// ends, however it ends. Every pipe and socket here is a fixture under <dir>, inside $MINMACS_HOME. Nothing writes
// to one, and nothing reads one. A device is not checked: making one needs root.
#import <fcntl.h>
#import <pthread.h>
#import <sys/socket.h>
#import <sys/un.h>

NSDictionary<NSString *, NSString *> *MMGitDirsOf(NSString *path);   // MMGitFacts.m: read from the checkout's .git

// Long, for a hosted runner that stalls. It costs time only on a run that fails anyway.
static const unsigned kPipeLimit = 10;

static NSString *KindAt(NSString *path) {
    struct stat st;
    if (!path.length || lstat(path.fileSystemRepresentation, &st) != 0) return @"gone";
    return S_ISFIFO(st.st_mode) ? @"pipe" : S_ISSOCK(st.st_mode) ? @"socket" : S_ISDIR(st.st_mode) ? @"folder" : @"file";
}
static void MakePipe(NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    (void)mkfifo(path.fileSystemRepresentation, 0600);
}
/// A socket nobody listens on. It is bound by its name from inside its folder, since a socket's path holds 103 bytes.
static void MakeSocket(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *was = fm.currentDirectoryPath;
    if (![fm changeCurrentDirectoryPath:path.stringByDeletingLastPathComponent]) return;
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    strlcpy(a.sun_path, path.lastPathComponent.fileSystemRepresentation, sizeof a.sun_path);
    if (s >= 0) { (void)bind(s, (struct sockaddr *)&a, sizeof a); close(s); }
    [fm changeCurrentDirectoryPath:was];
}
static void Said(NSString *line) { printf("%s\n", line.UTF8String); fflush(stdout); }
static NSString *RemovalSaysDeleted(MMUndoRecord *part) {
    return YN(MMRecordFlag(MMRecordDict([MMUndo.shared record:part.rid].payload, @"removal"), @"deleted"));
}

/// A part of a Wrap Up of tree stages item, which goes back, is staged again and is deleted. Three lines.
static void StagePutBackDelete(NSString *tree, NSString *item, NSString *inside) {
    MMUndoRecord *wrapUp = Unfinished([@"pipes: " stringByAppendingString:item.lastPathComponent], tree, nil);
    unsigned long long ino = InodeAt(item);
    MMUndoRecord *part = StageMany(wrapUp, @"pipes: staged, then put back", @[item], YES);
    NSString *to = StagedTo(part), *folder = MMRecordString(part.payload, @"stagedIn");
    Said([NSString stringWithFormat:@"%@ %@ %lu %lu", KindAt(item), KindAt(inside ? [to stringByAppendingPathComponent:inside] : to),
          (unsigned long)MMRecordList(part.payload, @"staged").count, (unsigned long)MMRecordList(part.payload, @"unstaged").count]);
    Said([NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalPutBack(@[part])), KindAt(inside ? [item stringByAppendingPathComponent:inside] : item),
          YN(InodeAt(item) == ino), YN(folder && Exists(folder))]);
    part = StageMany(wrapUp, @"pipes: staged, then deleted", @[item], YES);
    to = StagedTo(part); folder = MMRecordString(part.payload, @"stagedIn");
    [MMUndo.shared note:wrapUp payload:@{@"finishing": @YES}];
    (void)MMRemovalFinishStaged(@[part]);
    [MMUndo.shared finish:wrapUp ok:YES freed:0 error:nil];
    Said([NSString stringWithFormat:@"%@ %@ %@ %@", KindAt(item), KindAt(to), RemovalSaysDeleted(part), YN(folder && Exists(folder))]);
}

/// item is a second name, in the worktree tree, of other, which lies in another folder and is made by make. Asked by
/// that second name, only that name goes: deleted at once, then as a part of a Wrap Up. Two lines.
static void SecondName(NSString *tree, NSString *other, NSString *item, void (^make)(NSString *path)) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:tree withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *real = [MMRemovalRealPath(tree) stringByAppendingPathComponent:item.lastPathComponent];
    // The second name is made anew before each step, so a build that takes the wrong name fails each line by itself.
    void (^again)(void) = ^{
        if (!Exists(other)) make(other);
        [fm removeItemAtPath:item error:nil];
        (void)link(other.fileSystemRepresentation, item.fileSystemRepresentation);
    };
    again();
    MMUndoRecord *r = Begin(@"trash", @"pipes: a second name, deleted at once");
    MMRemovalAsk(r, @[item]);
    BOOL ok = MMRemovalApply(item, MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil), r, nil);
    NSArray<NSDictionary *> *deleted = MMRecordList(r.payload, @"deleted");
    Said([NSString stringWithFormat:@"%@ %@ %@ %@", YN(ok), KindAt(item), KindAt(other), YN(deleted.count == 1 && [MMRecordString(deleted.firstObject, @"path") isEqualToString:real])]);
    (void)Done(r);
    again();
    MMUndoRecord *wrapUp = Unfinished(@"pipes: a second name", tree, nil);
    MMUndoRecord *part = StageMany(wrapUp, @"pipes: a second name, part", @[item], YES);
    NSDictionary *x = MMRecordList(part.payload, @"staged").firstObject;
    NSString *staged = [NSString stringWithFormat:@"%@ %@ %@", KindAt(item), KindAt(other), YN([MMRecordString(x, @"from") isEqualToString:real])];
    [MMUndo.shared note:wrapUp payload:@{@"finishing": @YES}];
    (void)MMRemovalFinishStaged(@[part]);
    [MMUndo.shared finish:wrapUp ok:YES freed:0 error:nil];
    Said([NSString stringWithFormat:@"%@ %@ %@", staged, KindAt(other), KindAt(MMRecordString(x, @"to"))]);
}

static char gAskPath[PATH_MAX];
static volatile BOOL gAskStop;
/// Asks for the file at gAskPath over and over, as another process that uses a file's other name would.
static void *AskOther(void *unused) {
    struct stat st;
    while (!gAskStop) {
        (void)lstat(gAskPath, &st);
        int fd = open(gAskPath, O_EVTONLY | O_CLOEXEC);
        if (fd >= 0) close(fd);
    }
    return NULL;
}

/// The other side: run as `removaltest --pipe <case> <dir>`. An alarm ends it when a call waits on a pipe.
static int PipeChild(NSString *which, NSString *dir) {
    alarm(kPipeLimit);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tree = [[dir stringByAppendingPathComponent:which] stringByAppendingPathComponent:@"Wt"];
    NSString *pipe = [tree stringByAppendingPathComponent:@".env.Local"];
    if ([which isEqualToString:@"pipe"]) {
        MakePipe(pipe);
        // Asked through a link above it, and in another spelling where the disk does not tell upper from lower case.
        NSString *link = [tree.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"link"];
        [fm createSymbolicLinkAtPath:link withDestinationPath:tree error:nil];
        NSString *real = [MMRemovalRealPath(tree) stringByAppendingPathComponent:pipe.lastPathComponent];
        NSString *other = [link stringByAppendingPathComponent:pipe.lastPathComponent.uppercaseString];
        Said([NSString stringWithFormat:@"%@ %@", YN([MMRemovalRealPath([link stringByAppendingPathComponent:pipe.lastPathComponent]) isEqualToString:real]),
              YN(!Exists(other) || [MMRemovalRealPath(other) isEqualToString:real])]);
        StagePutBackDelete(tree, pipe, nil);
        // No Wrap Up: under Delete it is deleted at once, and the record lists it.
        MakePipe(pipe);
        MMUndoRecord *r = Begin(@"trash", @"pipes: deleted at once");
        MMRemovalAsk(r, @[pipe]);
        NSError *e = nil;
        BOOL ok = MMRemovalApply(pipe, MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil), r, &e);
        Said([NSString stringWithFormat:@"%@ %@ %lu %@", YN(ok), KindAt(pipe), (unsigned long)MMRecordList(r.payload, @"deleted").count, e.localizedDescription ?: @"no error"]);
        (void)Done(r);
    } else if ([which isEqualToString:@"socket"]) {
        NSString *sock = [tree stringByAppendingPathComponent:@"agent.sock"];
        MakeSocket(sock);
        StagePutBackDelete(tree, sock, nil);
    } else if ([which isEqualToString:@"holds"]) {
        // The common case: a folder with a pipe somewhere inside.
        NSString *mods = [tree stringByAppendingPathComponent:@"node_modules"];
        Write([mods stringByAppendingPathComponent:@"a.js"], @"A=1");
        MakePipe([mods stringByAppendingPathComponent:@"deep/agent.pipe"]);
        StagePutBackDelete(tree, mods, @"deep/agent.pipe");
        // A worktree's ignored files are saved before git takes it. The copy saves the file, skips the pipe and says so.
        Write([tree stringByAppendingPathComponent:@".env"], @"KEEP=1");
        MakePipe([tree stringByAppendingPathComponent:@".env.pipe"]);
        MMUndoRecord *r = Begin(@"trash", @"pipes: ignored files saved");
        NSString *saved = [MMUndo.shared recover:@[@".env", @".env.pipe"] from:tree record:r error:nil];
        NSDictionary *copy = MMRecordDict(r.payload, @"recovery");
        Said([NSString stringWithFormat:@"%@ %@ %@ %@", Read([saved stringByAppendingPathComponent:@".env"]), [MMRecordStrings(copy, @"saved") componentsJoinedByString:@","],
              [MMRecordStrings(copy, @"skipped") componentsJoinedByString:@","], KindAt([saved stringByAppendingPathComponent:@".env.pipe"])]);
        (void)Done(r);
    } else if ([which isEqualToString:@"names"]) {
        // A second name of a pipe or a socket that lies elsewhere, as an agent's control pipe would.
        NSString *agent = [tree.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"else/agent"];
        SecondName(tree, [agent stringByAppendingPathComponent:@"control.pipe"], [tree stringByAppendingPathComponent:@".env.pipe"], ^(NSString *path) { MakePipe(path); });
        SecondName(tree, [agent stringByAppendingPathComponent:@"S.agent"], [tree stringByAppendingPathComponent:@".env.sock"], ^(NSString *path) { MakeSocket(path); });
        // A plain file with a second name, while its other name is asked for all the time: an open file can then
        // be named by either, so its real path must come from the folder that was asked.
        NSString *first = [agent stringByAppendingPathComponent:@"first.txt"], *second = [tree stringByAppendingPathComponent:@".env"];
        Write(first, @"KEEP=1");
        (void)link(first.fileSystemRepresentation, second.fileSystemRepresentation);
        NSString *real = [MMRemovalRealPath(tree) stringByAppendingPathComponent:@".env"];
        strlcpy(gAskPath, first.fileSystemRepresentation, sizeof gAskPath);
        pthread_t asker;
        BOOL asking = pthread_create(&asker, NULL, AskOther, NULL) == 0;
        NSUInteger wrong = 0;
        for (int i = 0; i < 2000; i++) if (![MMRemovalRealPath(second) isEqualToString:real]) wrong++;
        MMUndoRecord *r = Begin(@"trash", @"pipes: a file's second name, deleted at once");
        MMRemovalAsk(r, @[second]);
        BOOL ok = MMRemovalApply(second, MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil), r, nil);
        gAskStop = YES;
        if (asking) pthread_join(asker, NULL);
        Said([NSString stringWithFormat:@"%lu %@ %@ %@", (unsigned long)wrong, YN(ok), KindAt(second), Read(first)]);
        (void)Done(r);
        // A pipe in a folder that cannot be listed: nothing says which name is its own, so it stays.
        NSString *locked = [tree stringByAppendingPathComponent:@"locked"], *in = [locked stringByAppendingPathComponent:@"agent.pipe"];
        MakePipe(in);
        chmod(locked.fileSystemRepresentation, 0300);
        r = Begin(@"trash", @"pipes: in a folder that cannot be listed");
        MMRemovalAsk(r, @[in]);
        NSError *e = nil;
        ok = MMRemovalApply(in, MMRemovalDecideWith(MMRemovalDelete, MMRemovalClutter, nil), r, &e);
        Said([NSString stringWithFormat:@"%@ %@ %@", YN(ok), KindAt(in), e.localizedDescription ?: @"no error"]);
        (void)Done(r);
        chmod(locked.fileSystemRepresentation, 0700);
    } else if ([which isEqualToString:@"kept"]) {
        // Under the Trash choice it goes to the Trash by its name and comes back from there.
        MakePipe(pipe);
        unsigned long long ino = InodeAt(pipe);
        MMRemovalDecision *keep = MMRemovalDecideWith(MMRemovalTrash, MMRemovalConfigFiles, nil);
        MMUndoRecord *wrapUp = Unfinished(@"pipes: to the Trash", tree, nil);
        MMUndoRecord *part = Part(wrapUp.rid, @"pipes: to the Trash, part");
        MMRemovalNote(part, keep, nil); MMRemovalAsk(part, @[pipe]);
        BOOL ok = MMRemovalApply(pipe, keep, part, nil);
        MMRemovalDone(part, nil);
        part = Done(part);
        NSString *to = MMRecordString(MMRecordList(part.payload, @"trashed").firstObject, @"to");
        Said([NSString stringWithFormat:@"%@ %@ %@ %@", YN(ok), KindAt(pipe), KindAt(to), YN([to hasPrefix:MMTrashFolder() ?: @"(none)"])]);
        Said([NSString stringWithFormat:@"%@ %@ %@", Or(MMRemovalPutBack(@[part])), KindAt(pipe), YN(InodeAt(pipe) == ino)]);
        // It waits in the staging folder with its old path taken: it is listed, and the person deletes it.
        part = StageMany(wrapUp, @"pipes: waits", @[pipe], YES);
        to = StagedTo(part);
        [MMUndo.shared finish:wrapUp ok:NO freed:0 error:@"test"];
        Write(pipe, @"NEWER=1");
        MMRemovalWaitingItem *item = WaitingOfPart(part.rid);
        Said([NSString stringWithFormat:@"%@ %@ %@ %@", WhyName(item), KindAt(item.stagedAt), YN(item.canPutBack), YN(item.canDelete)]);
        Said([NSString stringWithFormat:@"%@ %@ %@ %@", Or(item ? MMRemovalDeleteWaiting(item.itemID, NULL) : @"not listed"), KindAt(to), Read(pipe), WhyName(WaitingOfPart(part.rid))]);
    } else if ([which isEqualToString:@"git"]) {
        // A checkout whose .git is a pipe: the walk that reads .git files must come back, with no checkout read.
        NSString *git = [tree stringByAppendingPathComponent:@".git"];
        MakePipe(git);
        // A writer waits on that pipe, a process of this check's own that writes nothing. An open of the pipe for
        // reading, even one that does not wait, would let its open come back. So the pipe must not be opened at all.
        char name[PATH_MAX];
        strlcpy(name, git.fileSystemRepresentation, sizeof name);
        pid_t writer = fork();
        if (writer == 0) { alarm(kPipeLimit + 5); close(STDOUT_FILENO); _exit(open(name, O_WRONLY) >= 0 ? 7 : 8); }
        usleep(100000);   // it reaches its open
        Said(MMGitDirsOf(tree) ? @"read" : @"no checkout");
        int st = 0;
        BOOL ended = writer <= 0;
        for (int k = 0; k < 40 && !ended; k++) { ended = waitpid(writer, &st, WNOHANG) == writer; if (!ended) usleep(5000); }
        // Only the process this check started, which has not been waited for yet, so the pid is still its own.
        if (writer > 0 && !ended) { kill(writer, SIGKILL); waitpid(writer, &st, 0); }
        Said(writer <= 0 ? @"no writer could be started" : ended ? @"its open came back" : @"still waits");
    } else return 2;
    return 0;
}

/// Removes each pipe and socket that lies directly in folder.
static void DropPipesIn(NSString *folder) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in folder ? [fm contentsOfDirectoryAtPath:folder error:nil] : @[]) {
        NSString *p = [folder stringByAppendingPathComponent:name], *kind = KindAt(p);
        if ([kind isEqualToString:@"pipe"] || [kind isEqualToString:@"socket"]) [fm removeItemAtPath:p error:nil];
    }
}

/// Runs one case in a second process and hands each of its lines to a check. A case that was ended by its alarm,
/// or said less than was asked, fails every check it did not reach. What the case made is removed then, so no pipe
/// stays for the sections that scan the test home after this one.
static void PipeCase(NSString *which, NSArray<NSArray<NSString *> *> *checks) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:gSelf];
    t.arguments = @[@"--pipe", which, Path(@"pipes")];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    NSArray<NSString *> *lines = @[];
    NSString *ended = @"the check could not start";
    if ([t launchAndReturnError:nil]) {
        NSData *d = [p.fileHandleForReading readDataToEndOfFile];
        [t waitUntilExit];
        NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        lines = s.length ? [s componentsSeparatedByString:@"\n"] : @[];
        BOOL alarmed = t.terminationReason == NSTaskTerminationReasonUncaughtSignal && t.terminationStatus == SIGALRM;
        ended = alarmed ? [NSString stringWithFormat:@"it did not come back in %u s", kPipeLimit] : [NSString stringWithFormat:@"it ended with %d and said no more", t.terminationStatus];
    }
    for (NSUInteger i = 0; i < checks.count; i++) T(checks[i][0], checks[i][1], i < lines.count ? lines[i] : ended);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *made = [Path(@"pipes") stringByAppendingPathComponent:which];
    chmod([made stringByAppendingPathComponent:@"Wt/locked"].fileSystemRepresentation, 0700);
    [fm removeItemAtPath:made error:nil];
    if (lines.count >= checks.count) return;
    // The case stopped partway, so a pipe of its own may wait in the test home's Trash or in a staging folder. Only
    // this file makes a pipe or a socket there.
    DropPipesIn(MMTrashFolder());
    for (NSString *rid in [fm contentsOfDirectoryAtPath:StagedRoot() error:nil]) DropPipesIn([StagedRoot() stringByAppendingPathComponent:rid]);
}

static void Pipes(void) {
    PipeCase(@"pipe", @[
        @[@"pipe: its real path is its folder's real path and its own name, through a link above it and in the case the disk holds", @"yes yes"],
        @[@"pipe: a named pipe as an item is staged by its name, and is still a pipe where it waits", @"gone pipe 1 0"],
        @[@"pipe: a put-back brings the same pipe back to its old path, and its folder goes", @"nil pipe yes no"],
        @[@"pipe: after the last part it is deleted, the record says so, and its folder goes", @"gone gone yes no"],
        @[@"pipe: with no Wrap Up, Delete deletes it at once and lists it", @"yes gone 1 no error"]]);
    PipeCase(@"socket", @[
        @[@"socket: a socket as an item is staged by its name, and is still a socket where it waits", @"gone socket 1 0"],
        @[@"socket: a put-back brings the same socket back to its old path, and its folder goes", @"nil socket yes no"],
        @[@"socket: after the last part it is deleted, the record says so, and its folder goes", @"gone gone yes no"]]);
    PipeCase(@"holds", @[
        @[@"holds a pipe: a folder with a pipe inside is staged whole, the pipe with it", @"gone pipe 1 0"],
        @[@"holds a pipe: a put-back brings the folder back, the pipe inside it", @"nil pipe yes no"],
        @[@"holds a pipe: after the last part the folder is deleted, the pipe with it", @"gone gone yes no"],
        @[@"holds a pipe: the copy of a worktree's ignored files saves the file, skips the pipe and says so", @"KEEP=1 .env .env.pipe gone"]]);
    PipeCase(@"names", @[
        @[@"second name: a pipe that has another name elsewhere is deleted by the name that was asked, and the other name stays", @"yes gone pipe yes"],
        @[@"second name: as a part of a Wrap Up that pipe is staged from the asked name and deleted, and the other name stays", @"gone pipe yes pipe gone"],
        @[@"second name: a socket that has another name elsewhere is deleted by the name that was asked, and the other name stays", @"yes gone socket yes"],
        @[@"second name: as a part of a Wrap Up that socket is staged from the asked name and deleted, and the other name stays", @"gone socket yes socket gone"],
        @[@"second name: a plain file's real path is never its other name while that name is asked for, and only the asked name goes", @"0 yes gone KEEP=1"],
        @[@"second name: a pipe in a folder that cannot be listed is left, and the reason is plain", @"no pipe MinMacs never deletes it: cannot verify where it lies"]]);
    PipeCase(@"kept", @[
        @[@"pipe, Trash: under the Trash choice it goes to the Trash by its name", @"yes gone pipe yes"],
        @[@"pipe, Trash: a put-back brings the same pipe back from the Trash", @"nil pipe yes"],
        @[@"pipe, waits: one that waits with its old path taken is listed, with both ways out", @"old-path-taken pipe yes yes"],
        @[@"pipe, waits: the person deletes it, and the file at its old path stays", @"nil gone NEWER=1 not listed"]]);
    PipeCase(@"git", @[
        @[@"pipe: a folder whose .git is a pipe is read as no checkout, and the read comes back", @"no checkout"],
        @[@"pipe: a writer that waits on that .git pipe is not let through, since the pipe is never opened", @"still waits"]]);
}
