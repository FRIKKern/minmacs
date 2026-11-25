// An app row's insides as rows of the list, MMWindowTree.h.
#import "UI/Window/MMWindowTree.h"
#import "UI/Window/MMWindowViewParts.h"
#import "UI/Window/MMWindowListParts.h"

static const CGFloat kIndent = 14, kRowHigh = 24, kHeadHigh = 24;

static NSMutableSet<NSString *> *Open(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}
static NSString *gLastOpened;                           // main: the row opened last, whose insides show before others'
static NSMutableSet<NSString *> *gCut;                  // main: open rows whose insides the room left out: drawn closed

BOOL MMWindowTreeOpens(MMWindowRow *row) { return MMWindowRowInsides(row).count > 0 || MMWindowRowInsidesState(row) != nil; }
BOOL MMWindowTreeIsOpen(NSString *key) { return key && [Open() containsObject:key]; }
BOOL MMWindowTreeShowsOpen(NSString *key) { return MMWindowTreeIsOpen(key) && ![gCut containsObject:key]; }
NSInteger MMWindowTreeTopRows(MMWindowGroup *g) {
    NSInteger n = 0;
    for (MMWindowRow *r in g.rows) if (MMWindowRowDepth(r) == 0) n++;
    return n;
}
void MMWindowTreeSetOpen(NSString *key, BOOL open) {
    if (!key) return;
    if (open) { [Open() addObject:key]; gLastOpened = [key copy]; } else [Open() removeObject:key];
}
void MMWindowTreeCloseAll(void) { [Open() removeAllObjects]; gLastOpened = nil; }

#pragma mark The rows as shown

/// Appends row's insides when it is open, down to depth `most`. The row opened last shows its own insides whatever
/// `most` says, so a press always does what it says.
static void Under(MMWindowRow *row, NSInteger most, NSMutableArray<MMWindowRow *> *out) {
    if (!MMWindowTreeIsOpen(row.key)) return;
    NSArray<MMWindowRow *> *kids = MMWindowRowInsides(row);
    if (!kids.count) return;
    BOOL first = [row.key isEqualToString:gLastOpened];
    if (!first && MMWindowRowDepth(kids.firstObject) > most) { [gCut addObject:row.key]; return; }
    for (MMWindowRow *k in kids) { [out addObject:k]; Under(k, most, out); }
}

/// The deepest level open under row.
static NSInteger Deepest(MMWindowRow *row) {
    NSInteger d = MMWindowRowDepth(row);
    if (!MMWindowTreeIsOpen(row.key)) return d;
    for (MMWindowRow *k in MMWindowRowInsides(row)) d = MAX(d, Deepest(k));
    return d;
}

NSArray<MMWindowGroup *> *MMWindowTreeGroups(NSArray<MMWindowGroup *> *groups, CGFloat height) {
    BOOL any = NO;
    for (MMWindowGroup *g in groups) for (MMWindowRow *r in g.rows) if (MMWindowTreeIsOpen(r.key) && MMWindowRowInsides(r).count) any = YES;
    if (!any) return groups;
    // The rows the side holds with every group's header and one row for each of the other groups: what the tree may take.
    NSInteger n = (NSInteger)groups.count, room = MAX((NSInteger)floor((height - kHeadHigh * n) / kRowHigh) - n, 3);
    if (!gCut) gCut = [NSMutableSet new];
    [gCut removeAllObjects];
    NSMutableArray<MMWindowGroup *> *out = [NSMutableArray new];
    for (MMWindowGroup *g in groups) {
        NSMutableArray<MMWindowRow *> *rows = [NSMutableArray new];
        for (MMWindowRow *r in g.rows) {
            [rows addObject:r];
            if (!MMWindowTreeIsOpen(r.key)) continue;
            // The deepest levels close first, while the tree takes more rows than the side holds. Workspaces always show.
            NSMutableArray<MMWindowRow *> *tree = [NSMutableArray new];
            for (NSInteger most = Deepest(r); most >= 1; most--) {
                [tree removeAllObjects]; [gCut removeAllObjects];
                Under(r, most, tree);
                if ((NSInteger)tree.count <= room) break;
            }
            [rows addObjectsFromArray:tree];
        }
        MMWindowGroup *x = [MMWindowGroup new];
        x.key = g.key; x.title = g.title; x.side = g.side; x.rows = rows; x.emptyNote = g.emptyNote; x.byProject = g.byProject;
        [out addObject:x];
    }
    return out;
}

#pragma mark Drawing

NSRect MMWindowTreeContent(MMWindowRow *row, NSRect r) {
    CGFloat in = kIndent * MMWindowRowDepth(row);
    return NSMakeRect(r.origin.x + in, r.origin.y, MAX(r.size.width - in, 60), r.size.height);
}

NSRect MMWindowTreeDisclosure(MMWindowRow *row, NSRect r) {
    if (!MMWindowTreeOpens(row)) return NSZeroRect;
    NSInteger depth = MMWindowRowDepth(row);
    // At the top the disclosure stands in the row's own margin, left of its icon; deeper, in the indent.
    CGFloat x = depth == 0 ? r.origin.x + 0.5 : r.origin.x + kIndent * depth - 9;
    return NSMakeRect(x, NSMidY(r) - 4.5, 8, 9);
}

void MMWindowTreeDrawRow(MMWindowRow *row, NSString *shown, NSRect r, MMWindowSide side, BOOL hasHour, NSInteger look, BOOL tall) {
    NSRect content = MMWindowTreeContent(row, r);
    BOOL deep = MMWindowRowDepth(row) > 0;
    // The look spans the whole width, so a row deep in the tree is as easy to see pointed or picked as any other.
    if (deep && look == MMWindowRowActive) {
        [MMWindowColor(MMWindowInkHot) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
    } else if (deep && look == MMWindowRowHover) {
        [MMWindowColor(MMWindowInkHover) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6] fill];
        if (MMWindowContrast()) {
            NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:5.5 yRadius:5.5];
            edge.lineWidth = 1;
            [[NSColor colorWithWhite:1 alpha:0.42] setStroke];
            [edge stroke];
        }
    }
    // A hover's wash is drawn once: the text of a pointed row stays as at rest.
    MMWindowDrawRowAs(row, shown, deep ? content : r, side, hasHour, deep && look == MMWindowRowHover ? MMWindowRowRest : (MMWindowRowLook)look, tall);
    NSRect d = MMWindowTreeDisclosure(row, r);
    if (NSIsEmptyRect(d)) return;
    BOOL open = MMWindowTreeShowsOpen(row.key);
    NSColor *ink = look == MMWindowRowActive ? NSColor.whiteColor : MMWindowColor(MMWindowContrast() ? MMWindowInkText : MMWindowInkText2);
    NSBezierPath *p = [NSBezierPath bezierPath];
    p.lineWidth = 1.6; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat cx = NSMidX(d), cy = NSMidY(d);
    if (open) { [p moveToPoint:NSMakePoint(cx - 3.2, cy - 1.6)]; [p lineToPoint:NSMakePoint(cx, cy + 1.8)]; [p lineToPoint:NSMakePoint(cx + 3.2, cy - 1.6)]; }
    else { [p moveToPoint:NSMakePoint(cx - 1.4, cy - 3.4)]; [p lineToPoint:NSMakePoint(cx + 2, cy)]; [p lineToPoint:NSMakePoint(cx - 1.4, cy + 3.4)]; }
    [ink setStroke];
    [p stroke];
}

void MMWindowTreeAccessibility(NSAccessibilityElement *el, MMWindowRow *row) {
    NSInteger depth = MMWindowRowDepth(row);
    BOOL opens = MMWindowTreeOpens(row);
    if (!opens && depth == 0) return;
    // An outline's row: its level, and whether it opens and is open, as VoiceOver reads a Finder list.
    el.accessibilityRole = NSAccessibilityRowRole;
    el.accessibilitySubrole = NSAccessibilityOutlineRowSubrole;
    el.accessibilityDisclosureLevel = depth;
    el.accessibilityDisclosed = opens && MMWindowTreeShowsOpen(row.key);
    if (opens) el.accessibilityHelp = MMWindowTreeIsOpen(row.key) ? @"Open. The left arrow closes it." : @"Closed. The right arrow opens it.";
}

#pragma mark The window's part

@interface MMWindowView (TreeShown)
- (void)showPointed;
@end

@implementation MMWindowView (Tree)

- (void)treeShow {
    [_left setGroups:MMWindowTreeGroups(self.model.memoryGroups ?: @[], _left.bounds.size.height) ring:self.model.ring];
    [_right setGroups:MMWindowTreeGroups(self.model.diskGroups ?: @[], _right.bounds.size.height) ring:self.model.ring];
    // The host asks the app only while its row is open: it hears every app row that is, each model, and drops a repeat.
    id<MMWindowHost> host = self.host;
    if (![host respondsToSelector:@selector(windowInsides:open:)]) return;
    for (NSArray<MMWindowGroup *> *side in @[self.model.memoryGroups ?: @[], self.model.diskGroups ?: @[]])
        for (MMWindowGroup *g in side) for (MMWindowRow *r in g.rows)
            if (MMWindowRowInsidesState(r)) [(id<MMWindowInsidesHost>)host windowInsides:r.key open:MMWindowTreeIsOpen(r.key)];
}

- (void)treeToggle:(NSString *)key {
    MMWindowRow *row = [self.model row:key];
    if (!row || !MMWindowTreeOpens(row)) return;
    MMWindowTreeSetOpen(key, !MMWindowTreeIsOpen(key));
    [self treeShow];
    [_left reveal:key]; [_right reveal:key];
    [self showPointed];
}

/// The row as the list draws it: an agent or a server in the tree shares its key with its own row.
- (MMWindowRow *)treeRow:(NSString *)key {
    return [self.model row:key];
}

- (BOOL)treePress:(NSString *)key {
    MMWindowRow *row = key ? [self treeRow:key] : nil;
    if (!row || !MMWindowTreeOpens(row)) return NO;
    BOOL option = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    BOOL onDisclosure = NO;
    for (MMWindowListView *list in @[_left, _right]) {
        NSRect f = [list frameOfRow:key];
        if (NSIsEmptyRect(f) || !self.window) continue;
        NSPoint p = [list convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
        NSRect d = MMWindowTreeDisclosure(row, f);
        // The disclosure and the icon beside it take the press, so a small mark is easy to hit.
        if (NSPointInRect(p, NSMakeRect(NSMinX(d) - 4, NSMinY(f), 30, NSHeight(f)))) onDisclosure = YES;
    }
    if (!option && !onDisclosure) return NO;
    [self treeToggle:key];
    return YES;
}

- (BOOL)treeArrow:(unsigned short)code {
    if (code != 123 && code != 124) return NO;
    MMWindowRow *row = _active ? [self treeRow:_active] : nil;
    if (!row) return NO;
    BOOL opens = MMWindowTreeOpens(row), open = MMWindowTreeIsOpen(row.key);
    if (code == 124 && opens && !open) { [self treeToggle:row.key]; return YES; }
    if (code == 123 && opens && open) { [self treeToggle:row.key]; return YES; }
    NSString *parent = MMWindowRowParent(row);
    if (code == 123 && parent && [self.model row:parent]) {
        [_left reveal:parent]; [_right reveal:parent];
        _hovered = nil;
        self.activeRow = parent;
        return YES;
    }
    return NO;
}

- (void)treeReveal:(NSString *)key {
    if (![key hasPrefix:@"insides:"]) return;
    BOOL changed = NO;
    for (NSString *up = MMWindowRowParent([self.model row:key] ?: [MMWindowRow new]); up; up = MMWindowRowParent([self.model row:up] ?: [MMWindowRow new]))
        if (!MMWindowTreeIsOpen(up)) { MMWindowTreeSetOpen(up, YES); changed = YES; }
    if (changed) [self treeShow];
}

@end
