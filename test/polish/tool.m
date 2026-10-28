// The checks of test/polish.sh, the open items of the wave 4 reviews. test/polish.sh builds it with every .m under
// Sources but main.m. It counts what main does by defining realpath and stat in this binary, so every call from
// Sources lands here first and goes on to the system's own. Each command prints one JSON object.
//   tool main <worktree>   what main reads while WorkForest's menu and card build, with and without the prepared view,
//                          what each expert's watch reads on main, and where MinMacs's card actions write the rules
//   tool focus             MMLinkFocus: a click that opens no menu leaves no focus behind
//   tool spacing <worktree> <png folder>   the pitch of the fact rows and the link rows on the worktree's card
//   tool _walk             the worker child of P4, which the repo index starts from this same binary
// It refuses to run unless MINMACS_HOME is set and MINMACS_ROOTS sits inside it, so it reads no real worktree.
#import <Cocoa/Cocoa.h>
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"
#import "Shell/MMShell.h"
#import "UI/MMUI.h"
#import "UI/MMSpecMenu.h"
#import "UI/MMRender.h"
#import "Experts/LocoHost/MMLocoHost.h"
#import "Experts/WorkForest/MMWorkForest.h"
#import "Experts/NooNoo/MMNooNoo.h"
#import "Experts/MinMacs/MMMinMacs.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/stat.h>

#pragma mark - What main calls

static atomic_bool gCounting;
static atomic_int gMainRealpath, gMainStatsOfPrefs;
static NSString *gRealpathSuffix;   // only realpath calls on a path with this ending count

char *PolishRealpath(const char *path, char *resolved) __asm("_realpath$DARWIN_EXTSN");
char *PolishRealpath(const char *path, char *resolved) {
    static char *(*real)(const char *, char *);
    if (!real) real = (char *(*)(const char *, char *))dlsym(RTLD_NEXT, "realpath$DARWIN_EXTSN");
    if (atomic_load(&gCounting) && pthread_main_np() && path && gRealpathSuffix && [@(path) hasSuffix:gRealpathSuffix])
        atomic_fetch_add(&gMainRealpath, 1);
    return real(path, resolved);
}

int stat(const char *path, struct stat *buf) {
    static int (*real)(const char *, struct stat *);
    if (!real) real = (int (*)(const char *, struct stat *))dlsym(RTLD_NEXT, "stat");
    if (atomic_load(&gCounting) && pthread_main_np() && path && strstr(path, "no.guerrilla.minmacs.plist"))
        atomic_fetch_add(&gMainStatsOfPrefs, 1);
    return real(path, buf);
}

/// Count(YES) starts from zero, and Count(NO) stops and keeps the counts to read.
static void Count(BOOL on) {
    if (on) { atomic_store(&gMainRealpath, 0); atomic_store(&gMainStatsOfPrefs, 0); }
    atomic_store(&gCounting, on);
}

#pragma mark - A probe expert, which records where Wrap Up plans are made

@interface MMPolishProbe : NSObject <MMExpert>
@property (atomic) NSInteger plansOnMain, plansOff;
@end
@implementation MMPolishProbe
+ (instancetype)shared { static MMPolishProbe *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [MMPolishProbe new]; }); return p; }
- (NSString *)expertID { return @"polishprobe"; }
- (NSString *)name { return @"Probe"; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts { return @[]; }
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return [MMMenuSpec new]; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return @""; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return YES; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
- (NSArray<MMWrapUpPart *> *)wrapUpParts:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    if (NSThread.isMainThread) self.plansOnMain++; else self.plansOff++;
    return @[];
}
@end

#pragma mark - Helpers

static NSString *Env(NSString *k) { return NSProcessInfo.processInfo.environment[k]; }

/// Runs block off main and turns the main run loop until it ends, as the graph queue runs beside main in the app.
static void OffMain(dispatch_block_t block) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ block(); dispatch_semaphore_signal(done); });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW))
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static void Turn(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static void PrintJSON(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:MMJSONSafe(j) options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

static NSString *RealPath(NSString *p) { char b[PATH_MAX]; return realpath(p.fileSystemRepresentation, b) ? @(b) : p; }

static MMFinding *TreeFinding(MMSnapshot *s, NSString *path) {
    NSString *real = RealPath(path);
    for (MMFinding *f in [s findingsFor:@"workforest"]) if ([f.path isEqualToString:path] || [f.path isEqualToString:real]) return f;
    return nil;
}

static NSArray<NSString *> *Titles(MMCardSpec *c) {
    NSMutableArray *t = [NSMutableArray new];
    for (MMActionSpec *a in c.actions) [t addObject:a.title ?: @""];
    return t;
}

static NSArray<NSString *> *FactLabels(MMCardSpec *c) {
    NSMutableArray *t = [NSMutableArray new];
    for (MMCardFact *f in c.facts) [t addObject:f.label ?: @""];
    return t;
}

/// The snapshot the cold CLI builds, made off main, with a review for each expert whose watch acts on a new one.
static MMSnapshot *Snapshot(BOOL withReviews) {
    __block MMSnapshot *s = nil;
    OffMain(^{
        MMSnapshot *cold = MMCLISnapshot(NO);
        if (!withReviews) { s = cold; return; }
        NSMutableDictionary *reviews = [NSMutableDictionary new];
        for (NSString *e in @[@"locohost", @"workforest", @"noonoo"]) {
            MMReview *r = [MMReview new];
            r.expert = e; r.at = NSDate.date; r.verdicts = @{}; r.calls = @[]; r.actions = @[];
            reviews[e] = r;
        }
        s = [MMSnapshot snapshotFrom:cold.facts experts:MMExperts() reviews:reviews holds:nil];
    });
    return s;
}

#pragma mark - main

static int MainChecks(NSString *tree) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    MMWorkForestExpert *wf = MMWorkForestExpert.shared;
    gRealpathSuffix = @"/srv";

    // 1. A snapshot with nothing prepared, as a test makes: main builds WorkForest's view without the parts that
    // read disk. Before the fix it made a Wrap Up plan for each merged worktree and resolved each server's folder.
    MMSnapshot *bare = Snapshot(NO);
    MMFinding *f = TreeFinding(bare, tree);
    out[@"found"] = @(f != nil);
    if (!f) { PrintJSON(out); return 1; }
    MMPolishProbe.shared.plansOnMain = 0;
    Count(YES);
    MMMenuSpec *menu = [wf menuFor:bare];
    MMCardSpec *card = [wf cardFor:f snapshot:bare];
    (void)[wf badgeFor:bare]; (void)[wf accessibilityStateFor:bare];
    Count(NO);
    MMFinding *server = nil;
    for (MMFinding *x in [bare findingsFor:@"locohost"]) if ([x.path hasPrefix:RealPath(tree)] || [x.path hasPrefix:tree]) server = x;
    out[@"serverPath"] = server.path ?: @"";
    out[@"bare"] = @{@"plansOnMain": @(MMPolishProbe.shared.plansOnMain), @"serverRealpathsOnMain": @(atomic_load(&gMainRealpath)),
                     @"actions": Titles(card), @"facts": FactLabels(card), @"sections": @(menu.sections.count)};

    // 2. The same snapshot prepared off main, as the graph queue does: main reads the view, which holds Wrap Up and
    // the server link, and makes no plan and resolves no folder itself.
    MMSnapshot *s = Snapshot(NO);
    f = TreeFinding(s, tree);
    MMWFTree *t = MMWFTreeOf(f);
    OffMain(^{ (void)MMWrapUpConfigOnly(t.path, t.head, t.untracked, YES); });
    MMPolishProbe.shared.plansOnMain = 0; MMPolishProbe.shared.plansOff = 0;
    OffMain(^{ [s prepareFor:MMExperts()]; });
    NSInteger off = MMPolishProbe.shared.plansOff;
    Count(YES);
    card = [wf cardFor:f snapshot:s];
    (void)[wf menuFor:s];
    Count(NO);
    out[@"prepared"] = @{@"plansOnMain": @(MMPolishProbe.shared.plansOnMain), @"plansOff": @(off),
                         @"serverRealpathsOnMain": @(atomic_load(&gMainRealpath)), @"actions": Titles(card), @"facts": FactLabels(card)};

    // 3. Each expert's watch, on main, once per snapshot: it reads the mode and the review interval from what the
    // graph queue prepared, never the prefs file. Every mode is Idle and every interval 0, so nothing wakes or acts.
    MMSnapshot *w = Snapshot(YES);
    OffMain(^{ [w prepareFor:MMExperts()]; });
    NSMutableDictionary *watch = [NSMutableDictionary new];
    for (id<MMExpert> e in @[MMLocoHost.shared, MMWorkForestExpert.shared, MMNooNooExpert.shared]) {
        SEL sel = NSSelectorFromString(@"watch:");
        if (![(id)e respondsToSelector:sel]) { watch[e.expertID] = @"no watch"; continue; }
        Count(YES);
        ((void (*)(id, SEL, id))[(id)e methodForSelector:sel])(e, sel, w);
        Count(NO);
        watch[e.expertID] = @(atomic_load(&gMainStatsOfPrefs));
    }
    out[@"watchPrefReadsOnMain"] = watch;

    // 4. MinMacs's card actions that sort an app write the rules file on MinMacs's act queue, never on main.
    // The act queue is held while each action runs, so a write on main shows as a changed file at once.
    NSString *rulesPath = MMMinMacsRules.shared.path;
    NSString *(^stamp)(void) = ^NSString *{
        struct stat st;
        if (lstat(rulesPath.fileSystemRepresentation, &st) != 0) return @"none";
        return [NSString stringWithFormat:@"%llu:%ld.%ld:%lld", (unsigned long long)st.st_ino, (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec, (long long)st.st_size];
    };
    MMFinding *app = nil;
    for (MMFinding *x in [w findingsFor:@"minmacs"]) if ([x.kind isEqualToString:@"app"] && x.facts[@"bundleID"]) { app = x; break; }
    if (!app) for (MMFinding *x in [w findingsFor:@"minmacs"]) if ([x.kind isEqualToString:@"app"]) { app = x; break; }
    NSMutableArray *sorts = [NSMutableArray new];
    for (NSString *title in @[@"Always Keep", @"Quit on MinMacs", @"Leave Unsorted", @"Always Keep", @"Leave Unsorted"]) {
        if (!app) break;
        MMSnapshot *now = Snapshot(NO);
        MMFinding *a = nil;
        for (MMFinding *x in [now findingsFor:@"minmacs"]) if ([x.findingID isEqualToString:app.findingID]) a = x;
        MMCardSpec *c = a ? [MMMinMacsExpert.shared cardFor:a snapshot:now] : nil;
        MMActionSpec *act = nil;
        for (MMActionSpec *x in c.actions) if ([x.title isEqualToString:title]) act = x;
        if (!act) continue;
        dispatch_queue_t q = MMQueue(@"minmacs", @"act", QOS_CLASS_USER_INITIATED);
        dispatch_semaphore_t hold = dispatch_semaphore_create(0), held = dispatch_semaphore_create(0);
        dispatch_async(q, ^{ dispatch_semaphore_signal(held); dispatch_semaphore_wait(hold, DISPATCH_TIME_FOREVER); });
        dispatch_semaphore_wait(held, DISPATCH_TIME_FOREVER);
        NSString *before = stamp();
        act.run(NO);
        NSString *onMain = stamp();
        dispatch_semaphore_signal(hold);
        dispatch_sync(q, ^{});
        NSString *after = stamp();
        [sorts addObject:@{@"title": title, @"wroteOnMain": @(![before isEqualToString:onMain]), @"wroteOffMain": @(![onMain isEqualToString:after])}];
    }
    out[@"app"] = app.title ?: @"";
    out[@"sorts"] = sorts;
    PrintJSON(out);
    return 0;
}

#pragma mark - focus

static int FocusChecks(void) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    MMLinkFocus *f = [MMLinkFocus new];
    // A click that opens no menu, as when the item is hidden behind the notch.
    [f set:@"locohost" finding:@"locohost:server:1" click:^{}];
    out[@"rightAfterNoMenu"] = f.expert ?: @"";
    Turn(MMLinkFocusWait + 0.3);
    out[@"afterNoMenu"] = f.expert ?: @"";
    // A click whose menu opens and builds: the focus holds until the menu closes.
    __weak MMLinkFocus *weak = f;
    [f set:@"workforest" finding:@"workforest:worktree:/x" click:^{ [weak opened]; }];
    Turn(MMLinkFocusWait + 0.3);
    out[@"whileOpen"] = f.expert ?: @"";
    [f closed];
    out[@"afterClose"] = f.expert ?: @"";
    // A menu that opens a turn later, before the wait is over, keeps its focus too.
    [f set:@"noonoo" finding:@"noonoo:x" click:^{ dispatch_async(dispatch_get_main_queue(), ^{ [weak opened]; }); }];
    Turn(MMLinkFocusWait + 0.3);
    out[@"openedLater"] = f.expert ?: @"";
    PrintJSON(out);
    return 0;
}

#pragma mark - spacing

/// The top of each line of text whose ink starts at the value column, in points from the top of the PNG.
/// Fact values and link values both start there, and nothing else on the card does.
static NSArray<NSNumber *> *ValueLineTops(NSString *png, CGFloat valueX) {
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:png]];
    if (!rep) return @[];
    NSInteger W = rep.pixelsWide, H = rep.pixelsHigh;
    CGFloat scale = W / MMMenuWidth;
    NSColor *bg = [rep colorAtX:W - 3 y:H / 2];
    BOOL (^ink)(NSInteger, NSInteger) = ^BOOL(NSInteger x, NSInteger y) {
        NSColor *c = [rep colorAtX:x y:y];
        CGFloat d = fabs(c.redComponent - bg.redComponent) + fabs(c.greenComponent - bg.greenComponent) + fabs(c.blueComponent - bg.blueComponent);
        return d > 0.6;
    };
    NSInteger x0 = (NSInteger)round((valueX - 2) * scale), x1 = (NSInteger)round((valueX + 6) * scale), xEnd = W - (NSInteger)(20 * scale);
    NSMutableArray *tops = [NSMutableArray new];
    NSInteger y = 0;
    while (y < H) {
        BOOL any = NO;
        for (NSInteger x = x0; x < xEnd && !any; x++) any = ink(x, y);
        if (!any) { y++; continue; }
        NSInteger top = y, left = W;
        while (y < H) {
            BOOL row = NO;
            for (NSInteger x = (NSInteger)(4 * scale); x < xEnd; x++) if (ink(x, y)) { row = YES; if (x < left) left = x; }
            if (!row) break;
            y++;
        }
        // The separator above the actions starts left of the card's margin. The rows end there.
        if (left < (NSInteger)(13 * scale) && tops.count) break;
        // Only lines with ink where values start, and none at the card's margin, where the title and the status start.
        // Labels start right of the margin, and a link row's label as well.
        if (left >= (NSInteger)(20 * scale) && y - top > 3) {
            BOOL valueStarts = NO;
            for (NSInteger yy = top; yy < y && !valueStarts; yy++) for (NSInteger x = x0; x <= x1; x++) if (ink(x, yy)) { valueStarts = YES; break; }
            if (valueStarts) [tops addObject:@(top / scale)];
        }
    }
    return tops;
}

static int SpacingChecks(NSString *tree, NSString *folder) {
    MMSnapshot *s = Snapshot(NO);
    MMFinding *f = TreeFinding(s, tree);
    if (!f) { PrintJSON(@{@"found": @NO}); return 1; }
    OffMain(^{ [s prepareFor:MMExperts()]; });
    MMCardSpec *spec = [MMWorkForestExpert.shared cardFor:f snapshot:s];
    NSMutableDictionary *out = [NSMutableDictionary new];
    NSInteger links = 0;
    for (MMCardFact *x in spec.facts) if (x.linkExpert.length) links++;
    out[@"links"] = @(links);
    out[@"facts"] = @(spec.facts.count);
    NSDictionary *aps = MMRenderAppearances();
    NSMutableDictionary *pitches = [NSMutableDictionary new];
    for (NSString *mode in aps) {
        NSString *path = [folder stringByAppendingFormat:@"/polish-card-%@.png", mode];
        (void)MMRenderMenu([MMCardFromSpec(spec) menu], path, aps[mode]);
        NSArray<NSNumber *> *tops = ValueLineTops(path, 16 + MMLabelColumn + 10);
        // One line for each fact and each link row, so the lines past them, the actions, are not counted.
        tops = [tops subarrayWithRange:NSMakeRange(0, MIN(tops.count, spec.facts.count))];
        NSMutableArray *p = [NSMutableArray new];
        for (NSUInteger i = 1; i < tops.count; i++) [p addObject:@(round((tops[i].doubleValue - tops[i - 1].doubleValue) * 2) / 2)];
        pitches[mode] = p;
    }
    out[@"pitches"] = pitches;
    // A native menu item's height, from a menu of one item and one of two, as AppKit lays them out.
    NSMenu *one = [NSMenu new], *two = [NSMenu new];
    for (NSMenu *m in @[one, two, two]) [m addItemWithTitle:@"Row" action:NULL keyEquivalent:@""];
    out[@"itemPitch"] = @(two.size.height - one.size.height);
    PrintJSON(out);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "_walk")) return MMWorkerChildMain();
        NSString *home = Env(@"MINMACS_HOME"), *roots = Env(@"MINMACS_ROOTS");
        if (!home.length || !roots.length || ![roots.stringByStandardizingPath hasPrefix:[home.stringByStandardizingPath stringByAppendingString:@"/"]]) {
            fprintf(stderr, "tool: MINMACS_ROOTS must sit inside MINMACS_HOME\n");
            return 9;
        }
        if (argc < 2) { fprintf(stderr, "usage: tool main <worktree> | focus | spacing <worktree> <folder>\n"); return 2; }
        [NSApplication sharedApplication];
        if (!strcmp(argv[1], "focus")) return FocusChecks();
        MMRegisterExpert(MMLocoHost.shared);
        MMRegisterExpert(MMMinMacsExpert.shared);
        MMRegisterExpert(MMNooNooExpert.shared);
        MMRegisterExpert(MMWorkForestExpert.shared);
        MMRegisterExpert(MMPolishProbe.shared);
        if (!strcmp(argv[1], "main") && argc > 2) return MainChecks(@(argv[2]));
        if (!strcmp(argv[1], "spacing") && argc > 3) return SpacingChecks(@(argv[2]), @(argv[3]));
        fprintf(stderr, "tool: unknown command %s\n", argv[1]);
        return 2;
    }
}
