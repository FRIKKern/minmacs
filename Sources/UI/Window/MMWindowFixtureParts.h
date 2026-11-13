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
NSArray<MMWindowRow *> *MMWindowFixtureWorktrees(NSInteger count);
NSArray<MMWindowRow *> *MMWindowFixtureCaches(NSInteger count);
/// A group with the feed's words for when it is empty, its rows biggest first.
MMWindowGroup *MMWindowFixtureGroup(NSString *key, NSString *title, MMWindowSide side, NSArray<MMWindowRow *> *rows);
/// The ring of a model: its groups as slices, and the rest.
void MMWindowFixtureRing(MMWindowModel *m, uint64_t memoryUsed, uint64_t memoryTotal, uint64_t diskFree, uint64_t diskTotal);
/// "real" and "extreme", MMWindowFixtureMore.m. nil for any other name.
MMWindowModel *_Nullable MMWindowFixtureMore(NSString *name);

NS_ASSUME_NONNULL_END
