// Builds LocoHost's hosts from the facts Core gathered. It never samples: processes, sockets, args and cwd come
// from the MMSample in MMFacts, agents from the registry, sessions from Know, and places from Know's Where.
// Ported from -[LHScanner sample] in LocoHost's Ports.m, LHRules in Rules.m and the project part of Intel.m.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Experts/LocoHost/MMLHHost.h"

/// How long a host may read local project files and git's own files before it answers.
/// The app never waits on a file read, since macOS may hold a read in Documents until the person answers a prompt.
typedef NS_ENUM(NSInteger, MMLHRead) { MMLHReadCached = 0, MMLHReadNow = 1 };

/// The quiet threshold: LOCOHOST_IDLE_MINUTES for tests, else the locohost.idleMinutes pref, 30 minutes by default.
NSTimeInterval MMLHIdleSeconds(void);
/// Younger servers are never stopped by a mode: LOCOHOST_MIN_UPTIME_MINUTES, 30 minutes by default.
NSTimeInterval MMLHMinUptime(void);
/// Proactive waits this long: LOCOHOST_PROACTIVE_MINUTES, six hours by default.
NSTimeInterval MMLHProactiveQuiet(void);

/// locohost/rules.json: protect.names, protect.ports, protect.paths, ignore.names and ignore.devApps,
/// with MMRules wildcards. Defaults are additive, so an entry the person removed stays removed.
MMRules *MMLHRules(void);
BOOL MMLHProtects(MMLHHost *h);

@interface MMLHScanner : NSObject
+ (instancetype)shared;
/// Every listener in facts, as hosts sorted by port. Listeners of macOS and of apps that are not dev tools go to
/// *ignored as {pid, name, ports}. The same sample always gives the same hosts, so a rebuild on one sample
/// does not count a connection twice. Safe from any queue.
- (NSArray<MMLHHost *> *)hostsFrom:(MMFacts *)facts ignored:(NSArray<NSDictionary *> **)ignored read:(MMLHRead)read;
/// When LocoHost first saw any server on this Mac, from activity.json.
@property (readonly) NSDate *watchingSince;
@end

/// The git facts of a folder: repo, root, subdir, branch, worktree, touched as the last commit's time in seconds
/// since 1970 and merged in words. The checkout comes from
/// facts.worktrees, else from -[MMRepoIndex worktreeAt:], and the facts from -[MMFacts gitFor:], else
/// -[MMRepoIndex factsFor:wait:NO]. LocoHost reads no git file and runs no git. read NO never waits on the
/// .git read of a folder no walk covered.
NSDictionary *MMLHGitOf(NSString *folder, MMFacts *facts, MMLHRead read);
/// A path with macOS's /private prefix taken off /var and /tmp, so the kernel's folders and the repo index's
/// standardized paths compare with no disk read.
NSString *MMLHCanon(NSString *path);
/// "merged", "squash-merged", "merged through a pull request" or "not merged". nil for a main checkout or no facts.
NSString *MMLHMergeWords(MMGitFacts *g, BOOL isMain);

/// Where the host runs, from Know's Where. wait YES asks cmux and tmux now, for the CLI.
void MMLHFillWhere(MMLHHost *h, MMSample *s, BOOL wait);
