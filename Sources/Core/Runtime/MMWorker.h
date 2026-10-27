// The out-of-process worker for disk walks. Pattern P4 of SYNTHESIS.md section 1.1.
// Code inside the app cannot be stopped from outside, so a long walk runs in another process.
// Phase 0's settling test picks the kind at build time: an XPC service when it launches on macOS 14,
// otherwise a child of the same binary started as `minmacs _walk`.
#import <Foundation/Foundation.h>

/// P4. What the worker does. Every reply comes back on a queue the worker picks, never on main.
/// New code. Research track B built and timed an ad-hoc signed XPC service on this Mac: 13.9 ms cold, 0.03 ms a call.
/// Requests and replies are property lists, so the same calls cross XPC and a pipe to a child unchanged.
@protocol MMWorker <NSObject>
/// The quick tier of the Sizer, P16, for each root. Each value holds the keys allocated, freedIfDeleted, files and errors.
- (void)sizeTrees:(NSArray<NSString *> *)roots
            reply:(void (^)(NSDictionary<NSString *, NSDictionary *> *sizes, NSError *error))reply;
/// The exact tier of the Sizer: the bytes deleting all roots together frees, with clone extents counted once.
- (void)exactSize:(NSArray<NSString *> *)roots reply:(void (^)(uint64_t freed, NSError *error))reply;
/// Repo and worktree discovery under roots, P25. Each entry holds path, repo, branch and locked.
- (void)findWorktrees:(NSArray<NSString *> *)roots skip:(NSArray<NSString *> *)names
                reply:(void (^)(NSArray<NSDictionary *> *worktrees, NSError *error))reply;
@end

/// The one worker. It starts on first use and is restarted when it dies. A request in flight then fails with an error.
id<MMWorker> MMSharedWorker(void);

/// The body of `minmacs _walk`: reads requests from stdin, answers on stdout, and exits when stdin closes.
/// Unused when the worker is an XPC service.
int MMWorkerChildMain(void);
