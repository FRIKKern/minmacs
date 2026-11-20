// Included by moved.m. Issue #81: an open of a named pipe waits until a writer comes, so a removal whose item was a
// pipe never came back. A pipe or a socket is now never opened: its folder entry gives its real path, and it is
// staged, put back and deleted by its name, as any other item is.
//
//   Pipes ──▶ removaltest --pipe <case> <dir> ──▶ one line per check
//             a second process, ended by its own alarm after kPipeLimit seconds
//
// So a wait on a pipe fails the checks of one case and never holds the run. Every pipe and socket here is a fixture
// under <dir>, inside $MINMACS_HOME. Nothing writes to one, and nothing reads one. A device is not checked: making
// one needs root.
#import <sys/socket.h>
#import <sys/un.h>

NSDictionary<NSString *, NSString *> *MMGitDirsOf(NSString *path);   // MMGitFacts.m: read from the checkout's .git

static const unsigned kPipeLimit = 3;

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
        [fm removeItemAtPath:[tree stringByAppendingPathComponent:@".env.pipe"] error:nil];
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
        MakePipe([tree stringByAppendingPathComponent:@".git"]);
        Said(MMGitDirsOf(tree) ? @"read" : @"no checkout");
        // No pipe stays behind for the sections that scan after this one.
        [fm removeItemAtPath:[tree stringByAppendingPathComponent:@".git"] error:nil];
    } else return 2;
    return 0;
}

/// Runs one case in a second process and hands each of its lines to a check. A case that was ended by its alarm,
/// or said less than was asked, fails every check it did not reach.
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
}

static void Pipes(void) {
    PipeCase(@"pipe", @[
        @[@"pipe: its real path comes from its folder entry, through a link above it and in the case the disk holds", @"yes yes"],
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
    PipeCase(@"kept", @[
        @[@"pipe, Trash: under the Trash choice it goes to the Trash by its name", @"yes gone pipe yes"],
        @[@"pipe, Trash: a put-back brings the same pipe back from the Trash", @"nil pipe yes"],
        @[@"pipe, waits: one that waits with its old path taken is listed, with both ways out", @"old-path-taken pipe yes yes"],
        @[@"pipe, waits: the person deletes it, and the file at its old path stays", @"nil gone NEWER=1 not listed"]]);
    PipeCase(@"git", @[
        @[@"pipe: a folder whose .git is a pipe is read as no checkout, and the read comes back", @"no checkout"]]);
}
