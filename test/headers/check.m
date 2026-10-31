// Compile check for the Core headers, issue #11. test/headers/check.sh compiles this file and never links it.
// It imports every header under Sources/Core one by one, then uses the main types once,
// so a header that does not parse, warns, or declares a type it cannot use fails the check.
// check.sh also fails when a header under Sources/Core is missing from this list.
#import "Core/Runtime/MMRuntime.h"
#import "Core/Runtime/MMWorker.h"
#import "Core/Runtime/MMCoreSocket.h"
#import "Core/Senses/MMSenses.h"
#import "Core/Senses/MMFolders.h"
#import "Core/Senses/MMNet.h"
#import "Core/Know/MMRegistry.h"
#import "Core/Know/MMSessions.h"
#import "Core/Know/MMWhere.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Know/MMSizer.h"
#import "Core/Know/MMClutter.h"
#import "Core/Know/MMTreeDisk.h"
#import "Core/Graph/MMGraph.h"
#import "Core/Graph/MMHistory.h"
#import "Core/Store/MMStore.h"
#import "Core/Store/MMLog.h"
#import "Core/Store/MMGains.h"
#import "Core/Store/MMMigrate.h"
#import "Core/Review/MMReview.h"
#import "Core/Review/MMInvestigate.h"
#import "Core/Act/MMUndo.h"
#import "Core/Act/MMAct.h"
#import "Core/Act/MMWorktreeAct.h"
#import "Core/Act/MMClutterAct.h"
#import "Core/MMExpert.h"
#import "Core/MMCore.h"
#import "Core/MMSheet.h"
#import "Core/MMPerformance.h"
#import "Core/Store/MMDayLog.h"

// Calls one thing from each part, as an expert or the app would. Never called; it only has to compile.
__attribute__((unused)) static void MMCheckUse(id<MMExpert> e, MMSnapshot *s, MMFinding *f) {
    dispatch_queue_t q = MMQueue(e.expertID, @"check", QOS_CLASS_UTILITY);
    [MMJob run:@"check" expert:e.expertID on:q budget:1 work:^(MMJob *job) { (void)job.pastDeadline; }];
    MMProcKey k = { .pid = 1, .startSec = 0 };
    (void)MMProcAlive(k);
    MMSize size = [MMSizer quick:@"/tmp"];
    (void)size.freedIfDeleted;
    MMFactCache<NSString *> *cache = [[MMFactCache alloc] initWithName:@"check" maxAge:60 persist:NO];
    NSString *v = [cache valueFor:@"k" fingerprint:@"fp" orCompute:^NSString *{ return @"v"; } wait:NO];
    (void)v;
    MMCost cost = f.cost;
    (void)cost.diskFreed;
    MMReview *r = [s reviewFor:e.expertID];
    MMVerdictKind kind = [e.words kindFor:[r verdictFor:f].word];
    (void)kind;
    NSArray<MMPlanEntry *> *plan = MMPlan(s.findings, s.facts, r, MMModeFor(e.expertID), [e policy]);
    (void)plan;
    id<MMAction> a = [e actionFor:f step:MMStopTerm];
    NSString *err = nil;
    (void)MMRunAction(a, [e policy], nil, @"manual", @"check", &err);
    MMFacts *fresh = [MMGraph.shared freshFactsFor:f];
    (void)MMMustKeep(f, fresh, r, [e policy]);
    MMMenuSpec *menu = [e menuFor:s];
    (void)menu.sections.count;
    (void)[MMLog.shared latest:@"undo" expert:nil subject:nil since:nil limit:10];
    (void)MMPrefBool(@"check.on", NO);
    MMNotify(e.expertID, @"Checked", @"Nothing happened.", nil);
    MMPerformance *perf = [MMPerformance from:s history:s.history lookBack:[MMPerformanceLookBack fromSummary:@{}]];
    (void)perf.memory.parts[MMPerformanceOther];
    (void)perf.fixes.firstObject.memoryBack;
    (void)MMPerformanceFold(MMPerformanceServers);
#ifdef MM_TESTS
    MMUsePowerSource(nil);
#endif
}
