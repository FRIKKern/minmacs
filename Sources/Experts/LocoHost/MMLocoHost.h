// LocoHost on the shared core: every localhost on the Mac, where it runs, who uses it and what it costs.
// Issue #22. The expert reads servers and sockets from the Core snapshot, sessions from Know and places from
// Know's Where, and reviews through the Core broker. It never samples, scans or asks the model on its own.
// Sources/Experts/LocoHost/README.md says what was ported and what is left open.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import "Experts/LocoHost/MMLHHost.h"

@interface MMLocoHost : NSObject <MMExpert>
/// The one LocoHost. It registers itself with MMRegisterExpert when the binary loads.
+ (instancetype)shared;
/// The hosts behind a snapshot's findings, sorted by port. Built from each finding's facts, so it never samples.
- (NSArray<MMLHHost *> *)hostsIn:(MMSnapshot *)s;
/// The menu's view of a snapshot: the review, the plan under the mode, Close Idle and Recently Stopped.
- (MMLHView *)viewFor:(MMSnapshot *)s;
/// Listeners of macOS and apps in the last build, as {pid, name, ports}. Never findings.
@property (readonly, copy) NSArray<NSDictionary *> *ignored;
@end

/// The keep checks a mode runs on fresh facts, and the lighter one for an action the person asked for:
/// that it is still the same server.
id<MMExpertPolicy> MMLHModePolicy(void);
id<MMExpertPolicy> MMLHManualPolicy(void);
/// Stops a server: its tree and the package manager runner above it. MMStopKill is the second request.
id<MMAction> MMLHStopAction(MMFinding *f, MMStopStep step);
/// What Close Idle stops: dev servers, not protected, quiet, called idle by a review without an error,
/// and not used since that review. Ported from Candidates in LocoHost's main.m.
NSArray<MMFinding *> *MMLHCandidates(NSArray<MMFinding *> *findings, MMReview *r);
/// The review request for these findings in this mode. The CLI passes a model, the app nil for the Settings choice.
MMReviewRequest *MMLHReviewRequest(NSArray<MMFinding *> *findings, MMFacts *facts, NSString *trigger, MMMode mode, NSString *model);
/// The newest LocoHost review in the log, or nil.
MMReview *MMLHLastReview(void);
/// The plan of mode m as {findingID: {stop, why}}.
NSDictionary<NSString *, NSDictionary *> *MMLHPlanMap(NSArray<MMFinding *> *findings, MMFacts *facts, MMReview *r, MMMode m);
/// The verbs, in MMLHCLI.m.
NSArray<MMVerbSpec *> *MMLHVerbs(void);
