// The part of WorkForest's scan that the spike sample pointed at: DefaultPatchIds(), Trees.m:104-129.
// It reads `git log -p -n 400 <default>` into one string, appends a newline, encodes it again and
// pipes it into `git patch-id`. This harness does the same per repo, six repos at a time on the
// global utility queue, and reports the peak footprint. Read-only: git only reads, with
// GIT_OPTIONAL_LOCKS=0, and nothing is written to disk.
// Usage: patchids <none|item|stream> <repo>:<default branch>...
//   none    as WorkForest does it: no pool of its own
//   item    an @autoreleasepool around each repo's work
//   stream  git log's output goes straight into git patch-id through a pipe; only ids are read
#import <Foundation/Foundation.h>
#include <mach/mach.h>

static uint64_t footprint(BOOL peak) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n);
    return peak ? vi.ledger_phys_footprint_peak : vi.phys_footprint;
}

static NSTask *GitTask(NSString *dir, NSArray *args) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    t.arguments = [@[@"-C", dir, @"--no-pager"] arrayByAddingObjectsFromArray:args];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"GIT_OPTIONAL_LOCKS"] = @"0"; env[@"LC_ALL"] = @"C";
    t.environment = env;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    return t;
}

// WorkForest's WFGitInput, Common.m:78-104, without the timeout.
static NSString *GitInput(NSString *dir, NSArray *args, NSData *input) {
    NSTask *t = GitTask(dir, args);
    NSPipe *out = [NSPipe pipe], *in = input ? [NSPipe pipe] : nil;
    t.standardOutput = out; t.standardInput = in ?: [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    __block NSData *d = nil;
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_async(g, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ d = [out.fileHandleForReading readDataToEndOfFile]; });
    if (in) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try { [in.fileHandleForWriting writeData:input]; } @catch (NSException *e) {}
        [in.fileHandleForWriting closeFile];
    });
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    [t waitUntilExit];
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray *LogArgs(NSString *def) {
    return @[@"log", @"-p", @"--no-merges", @"--no-color", @"--no-ext-diff", @"-n", @"400", @"--format=commit %H", def];
}

static NSUInteger IdsInMemory(NSString *repo, NSString *def) {
    NSString *log = GitInput(repo, LogArgs(def), nil);
    NSString *out = GitInput(repo, @[@"patch-id", @"--stable"], [[log stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]);
    return [out componentsSeparatedByString:@"\n"].count;
}

// The fix to measure: the log never enters this process.
static NSUInteger IdsStreamed(NSString *repo, NSString *def) {
    NSTask *log = GitTask(repo, LogArgs(def)), *pid = GitTask(repo, @[@"patch-id", @"--stable"]);
    NSPipe *mid = [NSPipe pipe], *out = [NSPipe pipe];
    log.standardOutput = mid; pid.standardInput = mid; pid.standardOutput = out;
    if (![log launchAndReturnError:nil] || ![pid launchAndReturnError:nil]) return 0;
    NSData *d = [out.fileHandleForReading readDataToEndOfFile];
    [log waitUntilExit]; [pid waitUntilExit];
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"].count;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: patchids <none|item|stream> <repo>:<default>...\n"); return 2; }
    int mode = !strcmp(argv[1], "item") ? 1 : !strcmp(argv[1], "stream") ? 2 : 0;
    dispatch_semaphore_t gate = dispatch_semaphore_create(6);
    dispatch_group_t g = dispatch_group_create();
    __block NSUInteger ids = 0;
    NSDate *start = NSDate.date;
    for (int i = 2; i < argc; i++) {
        NSArray *p = [@(argv[i]) componentsSeparatedByString:@":"];
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        dispatch_group_async(g, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSUInteger n = 0;
            if (mode == 2) n = IdsStreamed(p[0], p[1]);
            else if (mode == 1) { @autoreleasepool { n = IdsInMemory(p[0], p[1]); } }
            else n = IdsInMemory(p[0], p[1]);
            @synchronized (g) { ids += n; }
            dispatch_semaphore_signal(gate);
        });
    }
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    double took = -start.timeIntervalSinceNow;
    uint64_t end = footprint(NO);
    [NSThread sleepForTimeInterval:3];
    printf("mode %-6s repos %d ids %lu  time %.1f s  peak %.0f MB  end %.0f MB  after 3 s %.0f MB\n", argv[1], argc - 2,
           (unsigned long)ids, took, footprint(YES) / 1048576.0, end / 1048576.0, footprint(NO) / 1048576.0);
    return 0;
}
