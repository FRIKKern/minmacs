// The out-of-process worker for disk walks. Pattern P4.
// The settling test proved the XPC service on macOS 27 only, so this is the other kind PLAN.md names:
// a child of the same binary, started as `minmacs _walk`, as track H recommends first.
// Requests and replies are one JSON object per line. The child exits when its stdin closes,
// and the client closes it after kIdle seconds with nothing in flight, so the child's memory goes back to the OS.
#import "Core/Runtime/MMWorker.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Know/MMSizer.h"
#include <libproc.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

static const NSTimeInterval kIdle = 30;

/// kIdle, or MM_WORKER_IDLE in a test build, so a test can reach the moment the child closes.
static NSTimeInterval IdleSeconds(void) {
#ifdef MM_TESTS
    double t = [NSProcessInfo.processInfo.environment[@"MM_WORKER_IDLE"] doubleValue];
    if (t > 0) return t;
#endif
    return kIdle;
}
static const NSInteger kWalkDepth = 4;
static NSString *const kErrorDomain = @"no.guerrilla.minmacs.worker";

static NSError *WorkerError(NSInteger code, NSString *why) {
    return [NSError errorWithDomain:kErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: why}];
}

#pragma mark - The client

@interface MMChildWorker : NSObject <MMWorker>
@end

@implementation MMChildWorker {
    dispatch_queue_t _q;                // every field below is touched on _q only
    NSTask *_task;
    int _in, _out;
    dispatch_source_t _reader;
    NSMutableData *_buffer;
    NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *_pending;
    int64_t _nextId;
    uint64_t _idleGeneration;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = MMQueue(@"core", @"worker", QOS_CLASS_UTILITY);
        _pending = [NSMutableDictionary new];
        _in = _out = -1;
    }
    return self;
}

static NSString *SelfPath(void) {
    char buf[PROC_PIDPATHINFO_MAXSIZE];
    return proc_pidpath(getpid(), buf, sizeof buf) > 0 ? @(buf) : NSProcessInfo.processInfo.arguments.firstObject;
}

- (BOOL)ensureChild {
    if (_task.isRunning && _in >= 0) return YES;
    // The old child is dead or closing, but its exit may not have reached _q yet. Drop it now, so its
    // reader cannot touch the new child's state and its requests in flight fail instead of waiting forever.
    if (_task) [self childEnded:_task];
    NSPipe *toChild = [NSPipe pipe], *fromChild = [NSPipe pipe];
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:SelfPath()];
    t.arguments = @[@"_walk"];
    t.standardInput = toChild;
    t.standardOutput = fromChild;
    t.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak MMChildWorker *weak = self;
    t.terminationHandler = ^(NSTask *done) {
        MMChildWorker *me = weak;
        if (me) dispatch_async(me->_q, ^{ [me childEnded:done]; });
    };
    if (![t launchAndReturnError:nil]) return NO;
    _task = t;
    _in = dup(toChild.fileHandleForWriting.fileDescriptor);
    _out = dup(fromChild.fileHandleForReading.fileDescriptor);
    [toChild.fileHandleForWriting closeFile];
    [fromChild.fileHandleForReading closeFile];
    fcntl(_in, F_SETNOSIGPIPE, 1);       // a dead child must never send SIGPIPE to the app
    fcntl(_out, F_SETFL, fcntl(_out, F_GETFL) | O_NONBLOCK);
    _buffer = [NSMutableData new];
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_out, 0, _q);
    int fd = _out;
    dispatch_source_t reader = _reader;
    dispatch_source_set_event_handler(_reader, ^{
        MMChildWorker *me = weak;
        // A reader of a child that was dropped only drains and closes its own pipe.
        if (me && me->_reader == reader) [me readFrom:fd]; else dispatch_source_cancel(reader);
    });
    dispatch_source_set_cancel_handler(_reader, ^{ close(fd); });
    dispatch_resume(_reader);
    return YES;
}

- (void)readFrom:(int)fd {
    char buf[65536];
    ssize_t got;
    while ((got = read(fd, buf, sizeof buf)) > 0) [_buffer appendBytes:buf length:(NSUInteger)got];
    if (got == 0 && _reader) { dispatch_source_cancel(_reader); _reader = nil; }
    for (;;) {
        NSRange nl = [_buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, _buffer.length)];
        if (nl.location == NSNotFound) break;
        NSData *line = [_buffer subdataWithRange:NSMakeRange(0, nl.location)];
        [_buffer replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
        NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
        if (![reply isKindOfClass:NSDictionary.class]) continue;
        NSNumber *rid = reply[@"id"];
        void (^done)(id, NSError *) = rid ? _pending[rid] : nil;
        if (!done) continue;
        [_pending removeObjectForKey:rid];
        NSString *err = reply[@"error"];
        done(reply[@"result"], [err isKindOfClass:NSString.class] ? WorkerError(2, err) : nil);
    }
    [self scheduleIdle];
}

- (void)childEnded:(NSTask *)t {
    if (t != _task) return;
    if (_reader) [self readFrom:_out];   // a reply written just before the exit is still in the pipe
    _task = nil;
    if (_in >= 0) { close(_in); _in = -1; }
    if (_reader) { dispatch_source_cancel(_reader); _reader = nil; }
    NSArray<void (^)(id, NSError *)> *failed = _pending.allValues;
    [_pending removeAllObjects];
    for (void (^done)(id, NSError *) in failed) done(nil, WorkerError(1, @"the worker exited before it replied"));
}

/// Closes the child's stdin after kIdle seconds with nothing in flight. The child then exits.
- (void)scheduleIdle {
    if (_pending.count) return;
    uint64_t gen = ++_idleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(IdleSeconds() * NSEC_PER_SEC)), _q, ^{
        if (gen != self->_idleGeneration || self->_pending.count || self->_in < 0) return;
        close(self->_in); self->_in = -1;
    });
}

- (void)call:(NSString *)method args:(NSDictionary *)args done:(void (^)(id result, NSError *error))done {
    dispatch_async(_q, ^{
        self->_idleGeneration++;
        if (![self ensureChild]) { done(nil, WorkerError(3, @"the worker did not start")); return; }
        NSNumber *rid = @(++self->_nextId);
        NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"id": rid, @"method": method, @"args": args} options:0 error:nil];
        NSMutableData *line = [body mutableCopy];
        [line appendBytes:"\n" length:1];
        self->_pending[rid] = done;
        const char *p = line.bytes; size_t left = line.length;
        while (left > 0) {
            ssize_t w = write(self->_in, p, left);
            if (w < 0 && errno == EINTR) continue;
            if (w <= 0) {
                [self->_pending removeObjectForKey:rid];
                done(nil, WorkerError(1, @"the worker exited before it replied"));
                return;
            }
            p += w; left -= (size_t)w;
        }
    });
}

- (void)sizeTrees:(NSArray<NSString *> *)roots
            reply:(void (^)(NSDictionary<NSString *, NSDictionary *> *sizes, NSError *error))reply {
    [self call:@"sizeTrees" args:@{@"roots": roots ?: @[]} done:^(id r, NSError *e) {
        reply([r isKindOfClass:NSDictionary.class] ? r : nil, e);
    }];
}

- (void)exactSize:(NSArray<NSString *> *)roots reply:(void (^)(uint64_t freed, NSError *error))reply {
    [self call:@"exactSize" args:@{@"roots": roots ?: @[]} done:^(id r, NSError *e) {
        reply([r isKindOfClass:NSDictionary.class] ? [r[@"freed"] unsignedLongLongValue] : 0, e);
    }];
}

- (void)findWorktrees:(NSArray<NSString *> *)roots skip:(NSArray<NSString *> *)names
                reply:(void (^)(NSArray<NSDictionary *> *worktrees, NSError *error))reply {
    [self call:@"findWorktrees" args:@{@"roots": roots ?: @[], @"skip": names ?: @[]} done:^(id r, NSError *e) {
        reply([r isKindOfClass:NSArray.class] ? r : nil, e);
    }];
}

@end

id<MMWorker> MMSharedWorker(void) {
    static MMChildWorker *w; static dispatch_once_t once;
    dispatch_once(&once, ^{ w = [MMChildWorker new]; });
    return w;
}

#pragma mark - The child: sizes

// The Sizer lives in Know. The child calls it through the runtime, so Runtime builds and links without Know,
// and the child stays a thin host for walks. +[MMSizer quick:] and +exact: must walk in this process.
static Class Sizer(SEL sel, NSString **error) {
    Class c = NSClassFromString(@"MMSizer");
    if (![c respondsToSelector:sel]) { *error = @"MMSizer is not built into this binary"; return Nil; }
    return c;
}

static id SizeTrees(NSDictionary *args, NSString **error) {
    SEL sel = NSSelectorFromString(@"quick:");
    Class c = Sizer(sel, error);
    if (!c) return nil;
    MMSize (*quick)(id, SEL, NSString *) = (MMSize (*)(id, SEL, NSString *))[c methodForSelector:sel];
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *root in args[@"roots"]) {
        if (![root isKindOfClass:NSString.class]) continue;
        @autoreleasepool {
            MMSize s = quick(c, sel, root);
            out[root] = @{@"allocated": @(s.allocated), @"freedIfDeleted": @(s.freedIfDeleted),
                          @"files": @(s.files), @"errors": @(s.errors)};
        }
    }
    return out;
}

static id ExactSize(NSDictionary *args, NSString **error) {
    SEL sel = NSSelectorFromString(@"exact:");
    Class c = Sizer(sel, error);
    if (!c) return nil;
    uint64_t (*exact)(id, SEL, NSArray *) = (uint64_t (*)(id, SEL, NSArray *))[c methodForSelector:sel];
    NSArray *roots = [args[@"roots"] isKindOfClass:NSArray.class] ? args[@"roots"] : @[];
    return @{@"freed": @(exact(c, sel, roots))};
}

#pragma mark - The child: worktrees

/// Folders under the roots that hold a .git: a folder for a main checkout, a file for a linked worktree.
/// From Walk in WorkForest Trees.m:57. Hidden folders, skipped names and the inside of repos are not searched.
static void Walk(NSString *dir, NSInteger depth, BOOL root, NSSet *skip, NSMutableSet *mains, NSMutableSet *linked) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@".git"] isDirectory:&isDir]) {
        [(isDir ? mains : linked) addObject:dir];
        if (!root) return;   // a scan root that is itself a repo is still searched
    }
    if (depth <= 0) return;
    for (NSString *n in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if ([n hasPrefix:@"."] || [skip containsObject:n]) continue;
        NSString *p = [dir stringByAppendingPathComponent:n];
        if (![[fm attributesOfItemAtPath:p error:nil].fileType isEqualToString:NSFileTypeDirectory]) continue;   // no symlinks
        @autoreleasepool { Walk(p, depth - 1, NO, skip, mains, linked); }
    }
}

static NSString *ReadLine(NSString *path) {
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

/// "main" from "ref: refs/heads/main". nil when HEAD is detached.
static NSString *BranchIn(NSString *gitDir) {
    NSString *head = ReadLine([gitDir stringByAppendingPathComponent:@"HEAD"]);
    return [head hasPrefix:@"ref: refs/heads/"] ? [head substringFromIndex:16] : nil;
}

static NSDictionary *Entry(NSString *path, NSString *repo, NSString *gitDir, BOOL locked) {
    NSMutableDictionary *e = [@{@"path": path, @"repo": repo, @"locked": @(locked)} mutableCopy];
    NSString *b = BranchIn(gitDir);
    if (b) e[@"branch"] = b;
    return e;
}

/// A linked worktree read from its .git file, with no git spawn: gitdir, then commondir.
static NSDictionary *Linked(NSString *dir) {
    NSString *line = ReadLine([dir stringByAppendingPathComponent:@".git"]);
    if (![line hasPrefix:@"gitdir: "]) return nil;
    NSString *gitDir = [line substringFromIndex:8];
    if (!gitDir.isAbsolutePath) gitDir = [dir stringByAppendingPathComponent:gitDir];
    gitDir = gitDir.stringByStandardizingPath;
    NSString *common = ReadLine([gitDir stringByAppendingPathComponent:@"commondir"]);
    if (!common.length) return nil;
    if (!common.isAbsolutePath) common = [gitDir stringByAppendingPathComponent:common];
    common = common.stringByStandardizingPath;
    NSString *repo = [common.lastPathComponent isEqualToString:@".git"] ? common.stringByDeletingLastPathComponent : common;
    BOOL locked = [NSFileManager.defaultManager fileExistsAtPath:[gitDir stringByAppendingPathComponent:@"locked"]];
    return Entry(dir, repo, gitDir, locked);
}

static id FindWorktrees(NSDictionary *args, NSString **error) {
    NSSet *skip = [NSSet setWithArray:[args[@"skip"] isKindOfClass:NSArray.class] ? args[@"skip"] : @[]];
    NSMutableSet *mains = [NSMutableSet new], *linked = [NSMutableSet new];
    for (NSString *root in args[@"roots"])
        if ([root isKindOfClass:NSString.class]) Walk(root.stringByStandardizingPath, kWalkDepth, YES, skip, mains, linked);
    // A main checkout names its linked worktrees in .git/worktrees/*/gitdir, also those outside the roots.
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *repo in mains) {
        NSString *wts = [repo stringByAppendingPathComponent:@".git/worktrees"];
        for (NSString *n in [fm contentsOfDirectoryAtPath:wts error:nil]) {
            NSString *gitFile = ReadLine([[wts stringByAppendingPathComponent:n] stringByAppendingPathComponent:@"gitdir"]);
            NSString *dir = gitFile.stringByStandardizingPath.stringByDeletingLastPathComponent;
            if (dir.length && [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@".git"]]) [linked addObject:dir];
        }
    }
    NSMutableArray *out = [NSMutableArray new];
    for (NSString *repo in [mains.allObjects sortedArrayUsingSelector:@selector(compare:)])
        [out addObject:Entry(repo, repo, [repo stringByAppendingPathComponent:@".git"], NO)];
    for (NSString *dir in [linked.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *e = Linked(dir);
        if (e) [out addObject:e];
    }
    return out;
}

#pragma mark - The child: the loop

int MMWorkerChildMain(void) {
    signal(SIGPIPE, SIG_IGN);
    char *line = NULL; size_t cap = 0; ssize_t len;
    while ((len = getline(&line, &cap, stdin)) > 0) {
        @autoreleasepool {
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:line length:(NSUInteger)len]
                                                                options:0 error:nil];
            if (![req isKindOfClass:NSDictionary.class] || !req[@"id"]) continue;
            NSString *method = req[@"method"], *error = nil;
            NSDictionary *args = [req[@"args"] isKindOfClass:NSDictionary.class] ? req[@"args"] : @{};
            id result = nil;
            if ([method isEqual:@"sizeTrees"]) result = SizeTrees(args, &error);
            else if ([method isEqual:@"exactSize"]) result = ExactSize(args, &error);
            else if ([method isEqual:@"findWorktrees"]) result = FindWorktrees(args, &error);
            else error = [NSString stringWithFormat:@"unknown method %@", method];
            NSMutableDictionary *reply = [@{@"id": req[@"id"]} mutableCopy];
            if (result) reply[@"result"] = result;
            if (error || !result) reply[@"error"] = error ?: @"no result";
            NSData *out = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
            if (!out) out = [NSJSONSerialization dataWithJSONObject:@{@"id": req[@"id"], @"error": @"reply not JSON"} options:0 error:nil];
            fwrite(out.bytes, 1, out.length, stdout);
            fputc('\n', stdout);
            fflush(stdout);
        }
    }
    free(line);
    return 0;
}
