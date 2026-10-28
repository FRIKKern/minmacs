// Agent sessions and agent events. Patterns P19 to P22 and P64 of SYNTHESIS.md sections 1.3 and 1.9.
// No hooks are installed in 2.0, decision 11. Status files, cmux events and Codex's SQLite cover Claude Code and Codex.
#import <Foundation/Foundation.h>

/// P19. One agent session, from any agent.
@interface MMSession : NSObject
@property (readonly, copy) NSString *agent;             // registry harnessID: claude-code, codex, pi, cursor
@property (readonly, copy) NSString *sessionID, *title, *cwd, *branch, *transcript;
@property (readonly) NSDate *started, *lastActive;
@property (readonly) pid_t pid;                         // 0 when no process runs it now
/// P20. Claude Code's live status from ~/.claude/sessions/<pid>.json: "busy", "waiting", "idle" or "shell", nil when
/// there is no file or its pid no longer runs with the start time the file names. TESTS.md question 9: "shell" is no
/// turn while a background shell runs, so it counts as idle. The file is undocumented.
/// P21. For Codex, the status of the thread's newest turn, such as "inProgress" or "completed".
@property (readonly, copy) NSString *liveStatus;
/// YES while liveStatus says a turn runs: busy, waiting or inProgress. "shell" is not working.
@property (readonly) BOOL stillWorking;
@end

/// P19, P20 and P21. One index of every session for every folder, built in one pass and refreshed by FSEvents.
/// Starts from Sessions in WF Trees.m:545.
/// P20 reads ~/.claude/sessions and ~/.claude/projects, both under $CLAUDE_CONFIG_DIR when it is set.
/// P21 reads Codex's state_5.sqlite and thread_history_1.sqlite under $CODEX_HOME, read-only. TESTS.md question 10:
/// mode=ro when the -shm file exists, which means Codex has the file open, and immutable=1 when it does not,
/// because a read-only connection cannot create the -shm file and nothing writes then.
/// It never walks the rollout folders and never writes Codex's notify setting.
/// pi sessions come from $PI_CODING_AGENT_SESSION_DIR, $PI_CODING_AGENT_DIR/sessions or ~/.pi/agent/sessions.
@interface MMSessions : NSObject
+ (instancetype)shared;
/// The graph queue calls this; reads never block. Issue #52: once startWatching ran, it reads the folders again only
/// when FSEvents saw a change under them, when a live status file's process ended, or after a minute.
/// Before startWatching, as in the CLI and the tools, every call reads them.
- (void)refresh;
/// Reads every folder and database now, for fresh facts.
- (void)refreshAll;
/// One FSEvents stream over Claude Code's, Codex's and pi's folders. A change posts MMSessionsDidChangeNotification.
/// A missing folder is watched from the nearest folder above it, but never from the home folder or above.
/// Such a folder costs a stat on each refresh, and the watch starts again once it exists.
- (void)startWatching;
- (void)stopWatching;
/// How many refresh calls read the folders, and how many found nothing new and returned at once.
@property (readonly) NSUInteger readCount, skipCount;
- (NSArray<MMSession *> *)all;
- (MMSession *)latestIn:(NSString *)folder;             // the newest session whose cwd is folder or inside it
- (MMSession *)openAt:(NSDate *)t inFolders:(NSArray<NSString *> *)folders;
- (MMSession *)forPid:(pid_t)pid;
- (MMSession *)withID:(NSString *)sessionID;
@end

/// Posted on the sessions watch queue after FSEvents saw a change in a session folder. Core asks for a rebuild.
extern NSNotificationName const MMSessionsDidChangeNotification;

/// P22. One agent event, kept small: the event name, session id, cwd, parent pid and time. Nothing else is kept.
@interface MMAgentEvent : NSObject
@property (readonly, copy) NSString *agent, *event, *sessionID, *cwd;   // event: "Stop", "UserPromptSubmit", ...
@property (readonly) pid_t ppid;
@property (readonly) NSDate *at;
@end

/// P22. The one reader of agent events: `cmux events --category agent --cursor-file ... --reconnect`,
/// with its cursor in Store/cmux.cursor, plus the spool in Store/events/*.jsonl.
/// New code. It replaces the 2 MB tail of workstream.jsonl that MM Hosts.m:142-238 reads.
@interface MMAgentEvents : NSObject
+ (instancetype)shared;
/// A no-op when cmux is not installed, when cmux is not in automation mode, or when the flag is off.
/// Phase 1 keeps the reader behind the pref core.cmuxEvents or MINMACS_CMUX_EVENTS=1. MINMACS_CMUX names the CLI.
- (void)start;
- (void)stop;                                           // ends the cmux child this object started
@property (readonly, copy) NSString *unavailableReason; // why start did nothing, for a dimmed reason; nil while it reads
/// block runs on MMQueue(@"core", @"events"). Returns a token for -stopObserving:.
- (id)observe:(void (^)(MMAgentEvent *event))block;
- (void)stopObserving:(id)token;
@end

/// P64. The body of `minmacs hook <agent>`: reads the hook payload on stdin, appends at most 512 bytes to the spool
/// and sends one datagram to the app. It always returns 0, so a hook never blocks the agent.
/// New code. No verb calls it in 2.0, because no hooks ship. It is here so opt-in hooks can come later.
int MMHookIngest(NSString *agent, NSFileHandle *input);
