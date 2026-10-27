// Agent sessions and agent events. Patterns P19 to P22 and P64 of SYNTHESIS.md sections 1.3 and 1.9.
// No hooks are installed in 2.0, decision 11. Status files, cmux events and Codex's SQLite cover Claude Code and Codex.
#import <Foundation/Foundation.h>

/// P19. One agent session, from any agent.
@interface MMSession : NSObject
@property (readonly, copy) NSString *agent;             // registry harnessID: claude-code, codex, pi, cursor
@property (readonly, copy) NSString *sessionID, *title, *cwd, *branch, *transcript;
@property (readonly) NSDate *started, *lastActive;
@property (readonly) pid_t pid;                         // 0 when no process runs it now
/// P20. Claude Code's live status from ~/.claude/sessions/<pid>.json: "busy", "idle" or "shell", nil when there is
/// no file. The file is undocumented, and what "shell" means is a guess. A settling test checks both.
@property (readonly, copy) NSString *liveStatus;
/// Claude Code's Stop with background tasks or session crons counts as still working. StopFailure counts as idle.
@property (readonly) BOOL stillWorking;
@end

/// P19, P20 and P21. One index of every session for every folder, built in one pass and refreshed by FSEvents.
/// Starts from Sessions in WF Trees.m:545.
/// P20 reads ~/.claude/sessions and ~/.claude/projects, both under $CLAUDE_CONFIG_DIR when it is set.
/// P21 reads Codex's state_5.sqlite and thread_history_1.sqlite under $CODEX_HOME, opened with mode=ro.
/// Never immutable=1, which research used for one look: Codex writes these files while MinMacs reads them.
/// It never walks the rollout folders and never writes Codex's notify setting.
@interface MMSessions : NSObject
+ (instancetype)shared;
- (void)refresh;                                        // the graph queue calls this; reads never block
- (NSArray<MMSession *> *)all;
- (MMSession *)latestIn:(NSString *)folder;             // the newest session whose cwd is folder or inside it
- (MMSession *)openAt:(NSDate *)t inFolders:(NSArray<NSString *> *)folders;
- (MMSession *)forPid:(pid_t)pid;
- (MMSession *)withID:(NSString *)sessionID;
@end

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
- (void)start;                                          // no-op when cmux is not installed
/// block runs on MMQueue(@"core", @"events"). Returns a token for -stopObserving:.
- (id)observe:(void (^)(MMAgentEvent *event))block;
- (void)stopObserving:(id)token;
@end

/// P64. The body of `minmacs hook <agent>`: reads the hook payload on stdin, appends at most 512 bytes to the spool
/// and sends one datagram to the app. It always returns 0, so a hook never blocks the agent.
/// New code. No verb calls it in 2.0, because no hooks ship. It is here so opt-in hooks can come later.
int MMHookIngest(NSString *agent, NSFileHandle *input);
