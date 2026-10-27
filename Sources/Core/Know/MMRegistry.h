// The agent registry and the working signal. Patterns P17 and P18 of SYNTHESIS.md section 1.3.
// The registry is the only agent recognizer. LocoHost's 18 agent names become lookups here.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"

/// P18. What an agent is doing right now.
typedef NS_ENUM(NSInteger, MMAgentState) { MMAgentUnknown, MMAgentWorking, MMAgentWaiting, MMAgentIdle };

/// P18. Where a state came from, in order of trust. The highest signal that fires decides.
/// New ranking. MM Agents.m:253-279 has no status file signal.
/// The row signals from Child to TreeCPU are Agents.m's, and the most trusted one that fired is named.
typedef NS_ENUM(NSInteger, MMAgentSignal) {
    MMAgentSignalNone,
    MMAgentSignalStatusFile,   // ~/.claude/sessions/<pid>.json, P20
    MMAgentSignalEvent,        // cmux events or Codex SQLite, P21 and P22
    MMAgentSignalCaffeinate,   // a caffeinate child holding an assertion, from MMPower
    MMAgentSignalChild,        // another child_process signal, or a tool shell for tool_children
    MMAgentSignalAssertion,    // a power assertion held in the tree, from MMPower
    MMAgentSignalTranscript,   // the session's transcript was written within the row's window
    MMAgentSignalTreeCPU,      // tree CPU over the row's threshold
    MMAgentSignalHosted,       // an agent this host runs is working
};

/// P17. One row of registry/agents/*.json. Rows are data: tools/validate_row.py checks each one,
/// and build.sh ships every row that passes. registry/schema.json describes the fields.
@interface MMAgentRow : NSObject
@property (readonly, copy) NSString *harnessID, *name;  // "claude-code", "Claude Code"
@property (readonly) NSDictionary *json;                // the whole row, for fields this class does not name
@end

/// P17 and P18. One agent session found running.
@interface MMAgent : NSObject
@property (readonly) MMAgentRow *row;
@property (readonly, copy) NSString *harnessID, *sessionID, *cwd;
@property (readonly, copy) NSString *surface;           // the matched surface's kind: tui, gui, ide or daemon
@property (readonly) MMProcKey key;
@property (readonly) MMAgentState state;
@property (readonly) MMAgentSignal signal;              // the signal that decided state
@property (readonly, copy) NSString *why;               // "status file busy", "caffeinate child", for cards and --json
@property (readonly) double treeCPU;
@property (readonly) uint64_t treeFootprint;
/// Agents of other rows that run below a hosts_agents surface. They are folded into this one and not listed apart.
@property (readonly) NSArray<MMAgent *> *hosted;
@end

/// P17. The loaded rows, and the detector that ranks the signals of P18.
/// Starts from MMAgents in MM Agents.m:38 on branch legacy, with its 63 rows.
/// tools/agents_probe.py is the reference detector, and this must agree with it on every fixture.
@interface MMRegistry : NSObject
+ (instancetype)shared;                                 // bundled rows, then the user's rows in Store/registry/agents
+ (NSArray<NSString *> *)defaultRowDirectories;         // what shared loads, in that order
/// Rows from each folder in turn. A later row with the same id replaces an earlier one. For tests and --rows.
- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs;
@property (readonly) NSArray<MMAgentRow *> *rows;
/// Every agent in the sample. Runs on the graph queue. A state holds for holdSeconds after its last working signal.
- (NSArray<MMAgent *> *)agentsIn:(MMSample *)s power:(MMPower *)p;
/// The agent whose process tree holds pid, or nil.
- (MMAgent *)agentAbove:(pid_t)pid in:(NSArray<MMAgent *> *)agents sample:(MMSample *)s;
/// The row whose name or args match p, or nil. LocoHost asks this to tell an agent's helper from a dev server.
- (MMAgentRow *)rowMatching:(MMProc *)p sample:(MMSample *)s;
@property NSTimeInterval holdSeconds;                   // 30 by default, as in 1.2
@end
