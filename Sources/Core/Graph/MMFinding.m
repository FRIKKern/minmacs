// The value types of the graph: owners, evidence, proposals, findings and facts. Issue #16.
// Every type here is immutable once made. A collection handed in is copied, so a caller that keeps
// a mutable array and changes it later never changes a finding, a fact sheet or a snapshot.
// This file sends messages to Senses and Know objects and never names their classes,
// so it links before those modules land, and tests can pass objects built by hand.
#import "Core/Graph/MMGraph.h"

#pragma mark - Owner

@implementation MMOwner {
    MMOwnerKind _kind;
    NSString *_key, *_name, *_path;
    MMOwner *_parent;
}

+ (instancetype)kind:(MMOwnerKind)kind key:(NSString *)key name:(NSString *)name path:(NSString *)path parent:(MMOwner *)parent {
    MMOwner *o = [self new];
    o->_kind = kind;
    o->_key = [key copy] ?: @"";
    o->_name = [name copy] ?: o->_key;
    o->_path = [path copy];
    o->_parent = parent;
    return o;
}

- (MMOwnerKind)kind { return _kind; }
- (NSString *)key { return _key; }
- (NSString *)name { return _name; }
- (NSString *)path { return _path; }
- (MMOwner *)parent { return _parent; }

static NSString *KindWord(MMOwnerKind k) {
    switch (k) {
        case MMOwnerWorkstream: return @"workstream";
        case MMOwnerSession: return @"session";
        case MMOwnerWorktree: return @"worktree";
        case MMOwnerProject: return @"project";
        case MMOwnerApp: return @"app";
    }
    return @"owner";
}

- (NSString *)ownerID { return [NSString stringWithFormat:@"%@:%@", KindWord(_kind), _key]; }

- (BOOL)isWithin:(MMOwner *)other {
    if (!other) return NO;
    for (MMOwner *o = self; o; o = o->_parent) if ([o isEqual:other]) return YES;
    return NO;
}

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:MMOwner.class]) return NO;
    MMOwner *o = object;
    return o->_kind == _kind && [o->_key isEqualToString:_key];
}

- (NSUInteger)hash { return _key.hash ^ (NSUInteger)_kind; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.ownerID; }

@end

#pragma mark - Evidence and proposals

@implementation MMEvidence {
    NSString *_label, *_value, *_linkExpert, *_linkFindingID;
    id _raw;
}

+ (instancetype)label:(NSString *)label value:(NSString *)value raw:(id)raw {
    return [self label:label value:value raw:raw linkExpert:nil findingID:nil];
}

+ (instancetype)label:(NSString *)label value:(NSString *)value raw:(id)raw linkExpert:(NSString *)expert findingID:(NSString *)findingID {
    MMEvidence *e = [self new];
    e->_label = [label copy] ?: @"";
    e->_value = [value copy] ?: @"";
    e->_raw = [raw respondsToSelector:@selector(copyWithZone:)] ? [raw copy] : raw;
    e->_linkExpert = [expert copy];
    e->_linkFindingID = [findingID copy];
    return e;
}

- (NSString *)label { return _label; }
- (NSString *)value { return _value; }
- (id)raw { return _raw; }
- (NSString *)linkExpert { return _linkExpert; }
- (NSString *)linkFindingID { return _linkFindingID; }

@end

@implementation MMProposal {
    NSString *_verb, *_title;
    MMReversibility _reversibility;
    BOOL _needsForce;
}

+ (instancetype)verb:(NSString *)verb title:(NSString *)title reversibility:(MMReversibility)r {
    return [self verb:verb title:title reversibility:r needsForce:NO];
}

+ (instancetype)verb:(NSString *)verb title:(NSString *)title reversibility:(MMReversibility)r needsForce:(BOOL)force {
    MMProposal *p = [self new];
    p->_verb = [verb copy] ?: @"";
    p->_title = [title copy] ?: @"";
    p->_reversibility = r;
    p->_needsForce = force;
    return p;
}

- (NSString *)verb { return _verb; }
- (NSString *)title { return _title; }
- (MMReversibility)reversibility { return _reversibility; }
- (BOOL)needsForce { return _needsForce; }

@end

#pragma mark - Findings

@implementation MMFindingBuilder
- (instancetype)init {
    if ((self = [super init])) _cost = (MMCost){ .cpuPercent = -1 };
    return self;
}
@end

@implementation MMFinding {
    NSString *_findingID, *_expert, *_kind, *_stableKey, *_instanceKey, *_title, *_path, *_ownerPath, *_fingerprint;
    MMOwner *_owner;
    MMCost _cost;
    NSArray<MMEvidence *> *_evidence;
    NSArray<NSString *> *_keepReasons;
    MMProposal *_proposal;
    NSArray<NSValue *> *_procs;
    NSDictionary *_facts;
}

/// A deep, immutable copy of a property list, so nested mutable values cannot change later.
static id Frozen(id v) {
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[v count]];
        [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k, id o, BOOL *stop) { d[[k copy]] = Frozen(o); }];
        return [d copy];
    }
    if ([v isKindOfClass:NSArray.class]) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:[v count]];
        for (id o in v) [a addObject:Frozen(o)];
        return [a copy];
    }
    return [v respondsToSelector:@selector(copyWithZone:)] ? [v copy] : v;
}

/// The default fingerprint: the stable key and the facts, with keys sorted, so equal facts give equal strings.
static NSString *DefaultFingerprint(NSString *stableKey, NSDictionary *facts) {
    NSMutableString *s = [stableKey mutableCopy];
    for (id k in [facts.allKeys sortedArrayUsingSelector:@selector(compare:)]) [s appendFormat:@"|%@=%@", k, facts[k]];
    return s;
}

+ (instancetype)expert:(NSString *)expert kind:(NSString *)kind stableKey:(NSString *)stableKey
                 build:(void (^)(MMFindingBuilder *b))build {
    MMFindingBuilder *b = [MMFindingBuilder new];
    if (build) build(b);
    MMFinding *f = [self new];
    f->_expert = [expert copy] ?: @"";
    f->_kind = [kind copy] ?: @"";
    f->_stableKey = [stableKey copy] ?: @"";
    f->_findingID = [NSString stringWithFormat:@"%@:%@:%@", f->_expert, f->_kind, f->_stableKey];
    f->_instanceKey = [b.instanceKey copy];
    f->_title = [b.title copy] ?: f->_stableKey;
    f->_path = [b.path copy];
    f->_ownerPath = [b.ownerPath copy];
    f->_owner = b.owner;
    f->_cost = b.cost;
    f->_evidence = [b.evidence copy] ?: @[];
    f->_keepReasons = Frozen(b.keepReasons) ?: @[];
    f->_proposal = b.proposal;
    f->_procs = [b.procs copy] ?: @[];
    f->_facts = Frozen(b.facts) ?: @{};
    f->_fingerprint = [b.fingerprint copy] ?: DefaultFingerprint(f->_stableKey, f->_facts);
    return f;
}

- (instancetype)withOwner:(MMOwner *)owner {
    if (owner == _owner) return self;
    MMFinding *f = [MMFinding new];
    f->_findingID = _findingID; f->_expert = _expert; f->_kind = _kind; f->_stableKey = _stableKey;
    f->_instanceKey = _instanceKey; f->_title = _title; f->_path = _path; f->_ownerPath = _ownerPath;
    f->_fingerprint = _fingerprint; f->_cost = _cost; f->_evidence = _evidence; f->_keepReasons = _keepReasons;
    f->_proposal = _proposal; f->_procs = _procs; f->_facts = _facts;
    f->_owner = owner;
    return f;
}

- (NSString *)findingID { return _findingID; }
- (NSString *)expert { return _expert; }
- (NSString *)kind { return _kind; }
- (NSString *)stableKey { return _stableKey; }
- (NSString *)instanceKey { return _instanceKey; }
- (NSString *)title { return _title; }
- (MMOwner *)owner { return _owner; }
- (MMCost)cost { return _cost; }
- (NSArray<MMEvidence *> *)evidence { return _evidence; }
- (NSArray<NSString *> *)keepReasons { return _keepReasons; }
- (MMProposal *)proposal { return _proposal; }
- (NSArray<NSValue *> *)procs { return _procs; }
- (NSString *)path { return _path; }
- (NSString *)ownerPath { return _ownerPath; }
- (NSString *)fingerprint { return _fingerprint; }
- (NSDictionary *)facts { return _facts; }
- (BOOL)kept { return _keepReasons.count > 0; }
- (NSString *)description { return [NSString stringWithFormat:@"%@ owner %@", _findingID, _owner.ownerID]; }

@end

#pragma mark - Facts

@implementation MMFacts {
    uint64_t _generation;
    MMSample *_sample;
    MMPower *_power;
    NSArray *_agents, *_sessions, *_worktrees, *_clutter;
    NSDictionary<NSString *, MMGitFacts *> *_git;
}

+ (instancetype)generation:(uint64_t)generation sample:(MMSample *)sample power:(MMPower *)power
                    agents:(NSArray<MMAgent *> *)agents sessions:(NSArray<MMSession *> *)sessions
                 worktrees:(NSArray<MMWorktree *> *)worktrees clutter:(NSArray<MMClutterItem *> *)clutter
                       git:(NSDictionary<NSString *, MMGitFacts *> *)git {
    MMFacts *f = [self new];
    f->_generation = generation;
    f->_sample = sample;
    f->_power = power;
    f->_agents = [agents copy] ?: @[];
    f->_sessions = [sessions copy] ?: @[];
    f->_worktrees = [worktrees copy] ?: @[];
    f->_clutter = [clutter copy] ?: @[];
    f->_git = [git copy] ?: @{};
    return f;
}

- (uint64_t)generation { return _generation; }
- (MMSample *)sample { return _sample; }
- (MMPower *)power { return _power; }
- (NSArray<MMAgent *> *)agents { return _agents; }
- (NSArray<MMSession *> *)sessions { return _sessions; }
- (NSArray<MMWorktree *> *)worktrees { return _worktrees; }
- (NSArray<MMClutterItem *> *)clutter { return _clutter; }
- (MMGitFacts *)gitFor:(MMWorktree *)w { return w.path ? _git[w.path] : nil; }

@end
