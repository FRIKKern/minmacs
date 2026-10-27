// Writable views of the Graph and Review types, for the Act test doubles in doubles.m.
#import "Core/Act/MMAct.h"

@interface MMProposal ()
@property (readwrite, copy) NSString *verb, *title;
@property (readwrite) MMReversibility reversibility;
@property (readwrite) BOOL needsForce;
@end

@interface MMFinding ()
@property (readwrite, copy) NSString *findingID, *expert, *kind, *stableKey, *instanceKey, *title, *path, *fingerprint;
@property (readwrite) NSArray<NSString *> *keepReasons;
@property (readwrite) MMProposal *proposal;
@property (readwrite) NSArray<NSValue *> *procs;
@property (readwrite) NSDictionary *facts;
@end

@interface MMFacts ()
@property NSDictionary *values;   // what the test's graph read fresh from the fixture, by name
@end

@interface MMGraph ()
@property (copy) MMFacts *(^gather)(MMFinding *f);
@end
