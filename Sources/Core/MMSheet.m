// Stubs for the sheet model of MMSheet.h, so the contract links. The sheet wave fills in MMSheetFrom and the builder.
#import "Core/MMSheet.h"

MMSheetMode MMSheetModeFrom(NSInteger oldMode) { return oldMode <= 0 ? MMSheetModeOff : oldMode == 1 ? MMSheetModeAsk : MMSheetModeAuto; }
NSInteger MMOldModeFrom(MMSheetMode mode) { return mode == MMSheetModeOff ? 0 : mode == MMSheetModeAsk ? 1 : 2; }
NSString *MMSheetModeWord(MMSheetMode mode) { return mode == MMSheetModeOff ? @"Off" : mode == MMSheetModeAsk ? @"Ask" : @"Auto"; }

NSString *MMSheetTabName(MMSheetTab tab, BOOL advanced) {
    switch (tab) {
        case MMSheetTabWorkstreams: return @"Workstreams";
        case MMSheetTabPerformance: return advanced ? @"Apps" : @"Performance";
        case MMSheetTabSettings: return @"Settings";
        case MMSheetTabAgents: return @"Agents";
        case MMSheetTabServers: return @"Servers";
        case MMSheetTabWorktrees: return @"Worktrees";
        case MMSheetTabDisk: return @"Disk";
    }
    return @"";
}

@implementation MMLaneSpan
+ (instancetype)kind:(MMLaneKind)kind start:(NSDate *)start end:(NSDate *)end {
    MMLaneSpan *s = [self new]; s.kind = kind; s.start = start; s.end = end; return s;
}
@end
@implementation MMServerSpan @end
@implementation MMLaneMark @end
@implementation MMHold @end
@implementation MMLaneNext @end
@implementation MMLane @end
@implementation MMLeftover @end
@implementation MMSheetRule @end
@implementation MMPerfRow @end
@implementation MMPerfGroup @end
@implementation MMSheetPerformance @end
@implementation MMSheetRow @end
@implementation MMSheetGroup @end
@implementation MMSheetList @end
@implementation MMSheetSettings @end
@implementation MMSheet @end

@implementation MMSheetBuilder
- (instancetype)initWithSnapshot:(MMSnapshot *)snapshot { if ((self = [super init])) _snapshot = snapshot; return self; }
- (MMLane *)laneFor:(NSString *)workstreamKey { return nil; }
- (void)addHold:(MMHold *)hold toLane:(NSString *)laneID {}
- (void)addAction:(MMActionSpec *)action toLane:(NSString *)laneID {}
- (void)addLeftover:(MMLeftover *)leftover {}
- (void)addRule:(MMSheetRule *)rule {}
- (void)setPerformance:(MMSheetPerformance *)performance {}
- (void)setList:(MMSheetList *)list {}
- (void)setLid:(BOOL)on note:(NSString *)note {}
- (MMSheet *)build { return [MMSheet new]; }
@end

MMSheet *MMSheetFrom(MMSnapshot *snapshot, NSArray<id<MMExpert>> *experts) { return [[[MMSheetBuilder alloc] initWithSnapshot:snapshot] build]; }
