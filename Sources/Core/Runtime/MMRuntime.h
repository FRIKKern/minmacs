// The runtime every knower runs on: labeled queues, dispatch timers, jobs with deadlines and crash breadcrumbs.
// Patterns P1, P2, P3 and P5 of docs/2.0/research/SYNTHESIS.md section 1.1. P4 is in MMWorker.h.
// AppKit runs on main only. Every other piece of Core work runs on a queue made here.
#import <Foundation/Foundation.h>

/// P1. The labeled serial queue of one knower, named no.guerrilla.minmacs.<expert>.<job>.
/// Each block runs in its own autorelease pool, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM.
/// New code. Today WorkForest scans on global queues with no pool, WF Trees.m:296-330.
/// The same expert and job always return the same queue, so a caller may ask again instead of keeping it.
/// Core's own knowers pass "core" as the expert, such as MMQueue(@"core", @"senses", QOS_CLASS_UTILITY).
dispatch_queue_t MMQueue(NSString *expert, NSString *job, dispatch_qos_class_t qos);

/// P2. A repeating dispatch timer on q. It keeps firing while a menu is open.
/// New code. LocoHost ticks from an NSTimer on main, LH main.m:862.
/// The timer is resumed when it is returned. dispatch_source_cancel stops it.
dispatch_source_t MMTimer(dispatch_queue_t q, NSTimeInterval every, NSTimeInterval leeway, dispatch_block_t tick);

/// P3. One named turn of work with a time budget.
/// Starts from LH Where.m:20-22, which ends a slow cmux or tmux call, and WF Trees.m:406, which gives git a limit.
/// A subprocess the job watches gets -terminate once the job is past its deadline.
/// An in-process job cannot be stopped from outside. When it overruns, the overrun is logged and its next turn is skipped.
/// The breadcrumb of P5 is set for the length of the work block.
@interface MMJob : NSObject
/// Runs work on q, unless the last turn of this name overran. Never blocks the caller.
+ (void)run:(NSString *)name expert:(NSString *)expert on:(dispatch_queue_t)q
     budget:(NSTimeInterval)budget work:(void (^)(MMJob *job))work;
@property (readonly, copy) NSString *name, *expert;
@property (readonly) NSDate *started;
@property (readonly) NSTimeInterval budget;
@property (readonly) BOOL pastDeadline;           // a long loop checks this and returns early
/// Ends task with -terminate when the deadline passes. The job stops watching once the task exits.
- (void)watchTask:(NSTask *)task;
@end

/// P5. Crash breadcrumbs. Enter writes the expert and job to Store/running before the work starts, and Leave clears it.
/// New code. A crash leaves the file behind, and the next launch reads it once to name what ran last.
/// MMJob calls both, so other code rarely needs them.
void MMBreadcrumbEnter(NSString *expert, NSString *job);
void MMBreadcrumbLeave(NSString *expert, NSString *job);
/// "workforest.scan" when the last run crashed inside that job, nil after a clean exit. Read once at launch.
NSString *MMBreadcrumbLeftOver(void);

/// Which bytes of a plain file MMReadPlain gives.
typedef NS_ENUM(NSInteger, MMPlainPart) {
    MMPlainHead,    // the first max bytes, or all of a shorter file
    MMPlainTail,    // the last max bytes, or all of a shorter file
    MMPlainWhole,   // the whole file, or nil when it is longer than max
};

/// Issue #96. The bytes of the plain file at path, read with no wait, for every file whose path comes from the disk:
/// an agent's session file, a project's package.json, git's files, another tool's config. An open of a named pipe
/// waits until a writer comes, and an open of a device can wait or act on it, so only a plain file is ever opened.
/// nil, at once and with nothing opened, when path is missing, a folder, a named pipe with or without a writer, a
/// socket, a device, or a link to any of those. A link to a plain file reads as that file. The open carries
/// O_NONBLOCK and the opened file is asked again with fstat, so a pipe that takes the name in between gives nil too.
/// A file is read as long as it was when opened: one that shrinks gives what it still holds. A read error gives nil.
/// MMPlainFile.m.
NSData *MMReadPlain(NSString *path, NSUInteger max, MMPlainPart part);
/// MMReadPlain that says why it gave nil, issue #116, so "missing" is told from "there and not read" with no second
/// look. *why is 0 with bytes, else the errno of the stat, open or read that failed: ENOENT or ENOTDIR when nothing is
/// there, EISDIR for a folder, EFTYPE for a named pipe, a socket or a device, EFBIG for a whole file past max.
NSData *MMReadPlainWhy(NSString *path, NSUInteger max, MMPlainPart part, int *why);
/// MMReadPlainWhy of a whole file of MinMacs's own, such as its list of what it sent to the Trash, issue #113: a link
/// at that name is never followed, *why ELOOP, not even one that takes the name between the check and the open, and
/// a file of another user's is not read, *why EPERM.
NSData *MMReadOwnPlain(NSString *path, NSUInteger max, int *why);
