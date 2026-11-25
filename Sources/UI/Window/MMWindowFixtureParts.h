// What the render's made-up days are built from, MMWindowFixture*.m. Only those files import this.
#import "UI/Window/MMWindowUI.h"

NS_ASSUME_NONNULL_BEGIN

/// Memory counts in 1024s and disk in thousands, as the window shows them.
static const uint64_t MMFixMB = 1ull << 20, MMFixGB = 1ull << 30, MMFixDiskMB = 1000000ull, MMFixDiskGB = 1000000000ull;

/// An hour that ends at `now`: flat, a step, a climb or a hump, by `shape`, with the same small noise on every run.
NSArray *MMWindowFixtureHour(double now, NSString *key, NSInteger shape);
MMWindowRow *MMWindowFixtureRow(MMWindowKind kind, NSString *key, NSString *name, NSString *_Nullable hint, NSString *_Nullable state, uint64_t bytes, double cpu);
/// Rows as the feed shapes them, Shell/MMWindowRows.m: its state words, its fact labels in its order, its values'
/// form. The render's checks hold every word to that list.
NSArray<MMWindowRow *> *MMWindowFixtureServers(NSInteger count);
NSArray<MMWindowRow *> *MMWindowFixtureAgents(NSInteger count, NSInteger asking);
NSArray<MMWindowRow *> *MMWindowFixtureApps(NSInteger count);
/// The day "agents": the fourth agent with every fact of an agent's story and the third with almost none.
void MMWindowFixtureAgentStories(NSArray<MMWindowRow *> *agents);
/// The worktrees of five made-up projects, or with `projects` 1 all of one repo, as a Mac with one project has them.
NSArray<MMWindowRow *> *MMWindowFixtureWorktrees(NSInteger count, NSInteger projects);
NSArray<MMWindowRow *> *MMWindowFixtureCaches(NSInteger count);
/// The leftovers of the day named "caches": 169 temp-folder families of one registry row, three in use, and Claude
/// Code's scratch of four sessions, one running. Each row with its kin, as the feed gives it, before MMWindowCollapsed.
NSArray<MMWindowRow *> *MMWindowFixtureLeftovers(void);
/// A group with the feed's words for when it is empty, its rows biggest first.
MMWindowGroup *MMWindowFixtureGroup(NSString *key, NSString *title, MMWindowSide side, NSArray<MMWindowRow *> *rows);
/// The ring of a model: its groups as slices, and the rest.
void MMWindowFixtureRing(MMWindowModel *m, uint64_t memoryUsed, uint64_t memoryTotal, uint64_t diskFree, uint64_t diskTotal);
/// A made-up log, MMWindowFixtureLog.m: "empty", "new", "busy" with 300 entries, "undo" with the Undo presses and
/// two runs, or "day".
MMWindowLog *MMWindowFixtureLog(NSString *kind);
/// The 7 days of "week", "week-young" and "week-gap", MMWindowFixtureWeek.m, on a model with its ring set: full, the
/// last 2 days only, and with gaps. The strip shows them.
void MMWindowFixtureWeek(MMWindowModel *m, NSString *name);
/// An answer of Ask MinMacs, MMWindowFixtureAsk.m: "ask-why", "ask-keep", "ask-undo", "ask-undone", "ask-plan" or,
/// for any other name, the answer to a question no rule knows.
MMWindowAnswer *MMWindowFixtureAnswer(NSString *name);
/// What MinMacs itself costs on the made-up days, in the shape of MMSelfCost.h's report, MMWindowFixtureMore.m:
/// "self" within every budget, "self-cpu" over its CPU budget, "self-memory" over its memory budget and
/// "self-wakeups" over its wakeup budget.
NSDictionary *MMWindowFixtureSelfReport(NSString *name);
/// "real" and "extreme", MMWindowFixtureMore.m. nil for any other name.
MMWindowModel *_Nullable MMWindowFixtureMore(NSString *name);

NS_ASSUME_NONNULL_END
