// An app row's insides in the window's model: the rows under an app that knows its insides, cmux's workspaces, panes,
// tabs and what runs in each, Core/Know/MMAppInsides.h. Plain values like the rest of the model, kept on the row as
// associated objects, so this whole file is a header: every part that links the model links this, with no build list
// to change.
//
//   cmux                         the app row, in Apps and helpers: depth 0, its insides under it
//     Sign In                    a workspace, as cmux names it: depth 1
//       Tune the ranking         a tab, as cmux names it: depth 2, or under its pane where a pane holds several
//         Tune the ranking       the agent in it: the Agents row itself, the same key, so hover and active stay one
//       3 idle shells            the tabs where only a shell waits, one row that opens
//
// A row the app's insides hold has a key that starts with "insides:", except an agent or a server, which keeps the
// key of its own row: the list draws it in both places, and both are one row.
#import <objc/runtime.h>
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The rows under this row, busiest first. nil for a row with no insides.
static inline NSArray<MMWindowRow *> *_Nullable MMWindowRowInsides(MMWindowRow *r) { return objc_getAssociatedObject(r, @selector(mmInsides)); }
static inline void MMWindowRowSetInsides(MMWindowRow *r, NSArray<MMWindowRow *> *_Nullable rows) { objc_setAssociatedObject(r, @selector(mmInsides), rows, OBJC_ASSOCIATION_COPY_NONATOMIC); }
/// How deep in the tree: 0 for a row of its own group, 1 for a workspace, and so on.
static inline NSInteger MMWindowRowDepth(MMWindowRow *r) { return [objc_getAssociatedObject(r, @selector(mmDepth)) integerValue]; }
static inline void MMWindowRowSetDepth(MMWindowRow *r, NSInteger depth) { objc_setAssociatedObject(r, @selector(mmDepth), @(depth), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
/// The key of the row it is under, nil at depth 0.
static inline NSString *_Nullable MMWindowRowParent(MMWindowRow *r) { return objc_getAssociatedObject(r, @selector(mmParent)); }
static inline void MMWindowRowSetParent(MMWindowRow *r, NSString *_Nullable key) { objc_setAssociatedObject(r, @selector(mmParent), key, OBJC_ASSOCIATION_COPY_NONATOMIC); }
/// What `--json` says of the node, for BarkBot: kind, title, pid, cwd, worktree, servers, agent, goTo, the app's handles.
static inline NSDictionary *_Nullable MMWindowRowInsidesInfo(MMWindowRow *r) { return objc_getAssociatedObject(r, @selector(mmInsidesInfo)); }
static inline void MMWindowRowSetInsidesInfo(MMWindowRow *r, NSDictionary *_Nullable info) { objc_setAssociatedObject(r, @selector(mmInsidesInfo), info, OBJC_ASSOCIATION_COPY_NONATOMIC); }
/// The app row's own state of its insides: {app, known, looking, why}, known found, unreachable, older or nothing.
static inline NSDictionary *_Nullable MMWindowRowInsidesState(MMWindowRow *r) { return objc_getAssociatedObject(r, @selector(mmInsidesState)); }
static inline void MMWindowRowSetInsidesState(MMWindowRow *r, NSDictionary *_Nullable state) { objc_setAssociatedObject(r, @selector(mmInsidesState), state, OBJC_ASSOCIATION_COPY_NONATOMIC); }

/// "Looking at cmux": the one quiet line while the app is asked.
static inline NSString *MMWindowInsidesLooking(NSString *app) { return [@"Looking at " stringByAppendingString:app.length ? app : @"the app"]; }
/// "3 idle shells", "1 idle shell".
static inline NSString *MMWindowIdleShells(NSInteger n) { return MMWindowCount(n, @"idle shell", @"idle shells"); }

/// A row of an app's insides.
static inline MMWindowRow *MMWindowInsidesRow(NSString *key, MMWindowKind kind, NSString *name, NSString *_Nullable state, double cpu, uint64_t bytes, NSInteger depth, NSString *_Nullable parent) {
    MMWindowRow *r = [MMWindowRow new];
    r.key = key; r.kind = kind; r.name = name.length ? name : @"untitled"; r.state = state; r.cpuPercent = cpu; r.bytes = bytes; r.facts = @[];
    r.quiet = cpu >= 0 && cpu < 0.5;
    MMWindowRowSetDepth(r, depth); MMWindowRowSetParent(r, parent);
    return r;
}

/// A copy of an agent's or a server's own row to stand in the tree: the same key, name, state and story.
static inline MMWindowRow *MMWindowInsidesSame(MMWindowRow *own, NSInteger depth, NSString *parent) {
    MMWindowRow *r = [MMWindowRow new];
    r.key = own.key; r.kind = own.kind; r.iconHint = own.iconHint; r.name = own.name; r.state = own.state; r.cpuPercent = own.cpuPercent;
    r.bytes = own.bytes; r.unmeasured = own.unmeasured; r.needsYou = own.needsYou; r.inFix = own.inFix; r.quiet = own.quiet; r.hour = own.hour;
    r.facts = own.facts; r.goTo = own.goTo; r.pull = own.pull;
    r.menu = own.menu;   // its own right-click menu: the same row, the same items
    MMWindowRowSetDepth(r, depth); MMWindowRowSetParent(r, parent);
    MMWindowRowSetInsidesInfo(r, @{@"kind": own.kind == MMWindowAgent ? @"agent" : @"server", @"same": own.key});
    return r;
}

/// A row an app's insides hold, by key, at any depth. nil when none.
static inline MMWindowRow *_Nullable MMWindowInsidesIn(NSArray<MMWindowRow *> *_Nullable rows, NSString *key) {
    for (MMWindowRow *r in rows) {
        if ([r.key isEqualToString:key]) return r;
        MMWindowRow *in = MMWindowInsidesIn(MMWindowRowInsides(r), key);
        if (in) return in;
    }
    return nil;
}
static inline MMWindowRow *_Nullable MMWindowInsidesFind(MMWindowModel *m, NSString *key) {
    if (![key hasPrefix:@"insides:"]) return nil;
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups ?: @[], m.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows) { MMWindowRow *in = MMWindowInsidesIn(MMWindowRowInsides(r), key); if (in) return in; }
    return nil;
}

/// What `--json` gives for each row of the insides: the node's facts, its row's key, name, state and numbers, and
/// what is under it.
static inline NSArray *MMWindowInsidesNodesJSON(NSArray<MMWindowRow *> *_Nullable rows) {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWindowRow *r in rows) {
        NSMutableDictionary *j = [MMWindowRowInsidesInfo(r) ?: @{} mutableCopy];
        j[@"key"] = r.key; j[@"name"] = r.name; j[@"state"] = r.state ?: NSNull.null;
        j[@"cpuPercent"] = r.cpuPercent >= 0 ? @(round(r.cpuPercent * 10) / 10) : NSNull.null; j[@"bytes"] = @(r.bytes);
        j[@"children"] = MMWindowInsidesNodesJSON(MMWindowRowInsides(r));
        [out addObject:j];
    }
    return out;
}
/// The app row's `insides`: {app, known, looking, why, workspaces}. nil for a row with no insides to tell.
static inline NSDictionary *_Nullable MMWindowInsidesJSON(MMWindowRow *r) {
    NSDictionary *state = MMWindowRowInsidesState(r);
    if (!state) return nil;
    NSMutableDictionary *j = [state mutableCopy];
    j[@"workspaces"] = MMWindowInsidesNodesJSON(MMWindowRowInsides(r));
    return j;
}

/// A host that hears when an app row's insides open and close, so it asks the app only while they show.
@protocol MMWindowInsidesHost <NSObject>
- (void)windowInsides:(NSString *)rowKey open:(BOOL)open;
@end

NS_ASSUME_NONNULL_END
