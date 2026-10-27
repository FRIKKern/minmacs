// Runs WorkForest's own Sessions() code, the session-log reader in every scan, and reports its peak
// footprint. Read-only: it maps and reads agent logs and writes nothing.
// build.sh extracts Sessions() and its helpers from ~/Documents/GitHub/workforest/Sources/Trees.m
// into sessions_wf.inc, once as is and once with a pool around each Mentions() call.
// Usage: sessions <none|item> <worktree>...    item wraps the whole call in one pool.
#import <Foundation/Foundation.h>
#include <mach/mach.h>

static const NSTimeInterval kMentionWindow = 14 * 86400;
static const NSUInteger kTailBytes = 16 << 20;

@interface WFTree : NSObject
@property (copy) NSString *path;
@end
@implementation WFTree
@end

static NSString *WFTilde(NSString *path) {
    NSString *home = NSHomeDirectory();
    return [path hasPrefix:home] ? [@"~" stringByAppendingString:[path substringFromIndex:home.length]] : path;
}
// WorkForest also redacts secrets here. The harness only keeps the clip, which allocates the same.
static NSString *WFClip(NSString *s, NSUInteger n) {
    if (![s isKindOfClass:NSString.class]) return nil;
    s = [[[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
          filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    if (!s.length) return nil;
    return s.length > n ? [[s substringToIndex:n - 1] stringByAppendingString:@"…"] : s;
}

#include "sessions_wf.inc"

static uint64_t peak(void) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n);
    return vi.ledger_phys_footprint_peak;
}
static uint64_t now(void) {
    task_vm_info_data_t vi; mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n);
    return vi.phys_footprint;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: sessions <none|item> <worktree>...\n"); return 2; }
    BOOL pool = !strcmp(argv[1], "item");
    NSMutableArray *trees = [NSMutableArray new];
    for (int i = 2; i < argc; i++) { WFTree *t = [WFTree new]; t.path = @(argv[i]); [trees addObject:t]; }
    __block NSUInteger found = 0;
    uint64_t before = peak();
    NSDate *start = NSDate.date;
    // As in WorkForest: the scan runs in one block on the global utility queue.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (pool) { @autoreleasepool { found = Sessions(trees).count; } }
        else found = Sessions(trees).count;
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    double took = -start.timeIntervalSinceNow;
    uint64_t end = now();
    [NSThread sleepForTimeInterval:3];
    printf("%-14s pool %-4s trees %lu with session %lu  time %.1f s  peak %.0f MB (before %.0f)  end %.0f MB  after 3 s %.0f MB\n",
           getprogname(), argv[1], (unsigned long)trees.count, (unsigned long)found, took, peak() / 1048576.0, before / 1048576.0,
           end / 1048576.0, now() / 1048576.0);
    return 0;
}
