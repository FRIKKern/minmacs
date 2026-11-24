// An agent that serves a port of its own. Included by window.m, after planned.m.
// Claude Code's binary is named by its version, ~/.local/share/claude/versions/2.1.331, and it listens on a local
// port. LocoHost writes such a listener as kind agent, named by the agent, with the agent's session title, and
// MinMacs's agent finding names the ports its own process listens on. Here the working agent 71011 of the world is
// that listener, so one pid is a server row and an agent row: each names the other, and the ring counts it once.

static void AgentPort(void) {
    World();
    MMSnapshot *s0 = WorldSnapshot();
    MMPerformance *p0 = Build(s0);
    uint64_t servers0 = [p0.memory.parts[MMPerformanceServers] unsignedLongLongValue], agents0 = [p0.memory.parts[MMPerformanceAgents] unsignedLongLongValue];

    TSession *x = [TSession new];
    x.agent = @"claude-code"; x.sessionID = @"s-71011"; x.cwd = Dir(@"app"); x.title = @"Access permissions request inquiry"; x.pid = 71011;
    x.started = [NSDate dateWithTimeIntervalSinceNow:-2640]; x.lastActive = NSDate.date;
    [gSessions addObject:x];
    NSMutableArray *servers = [gFindings[@"locohost"] mutableCopy];
    // As MMLHHost's json writes it: the framework and the agent are the registry's name, not the binary's "2.1.331".
    [servers addObject:Finding(@"locohost", @"server", @"agent-49210", @":49210 Claude Code app", Dir(@"app"), 71011, 200 * MB, 0, P(@"stop", MMReversibleRestart),
                               @{@"port": @49210, @"ports": @[@49210], @"kind": @"agent", @"framework": @"Claude Code", @"agent": @"Claude Code",
                                 @"agentPid": @71011, @"agentTitle": @"Access permissions request inquiry", @"name": @"2.1.331", @"project": @"app",
                                 @"launcher": @"Terminal", @"state": @"recent", @"uptimeSeconds": @2640})];
    gFindings[@"locohost"] = servers;
    NSMutableArray *mm = [gFindings[@"minmacs"] mutableCopy];
    for (NSUInteger i = 0; i < mm.count; i++) {
        MMFinding *f = mm[i];
        if (![f.stableKey isEqualToString:@"claude-code:s-71011"]) continue;
        NSMutableDictionary *fx = [f.facts mutableCopy]; fx[@"ports"] = @[@49210];
        mm[i] = Finding(@"minmacs", @"agent", f.stableKey, f.title, nil, 71011, 200 * MB, 0, nil, fx);
    }
    gFindings[@"minmacs"] = mm;

    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    MMWindowRow *server = [m row:@"locohost:server:agent-49210"], *agent = [m row:@"minmacs:agent:claude-code:s-71011"];
    NSString *(^story)(MMWindowRow *) = ^(MMWindowRow *r) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMWindowFact *f in r.facts) [a addObject:[NSString stringWithFormat:@"%@=%@", f.label, f.value]];
        return [a componentsJoinedByString:@"; "];
    };
    NSString *(^phrases)(MMWindowRow *) = ^(MMWindowRow *r) {
        return [[[r.storyFacts valueForKey:@"phrase"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != nil AND SELF != %@", NSNull.null]] componentsJoinedByString:@"; "];
    };
    T(@"window: an agent's own port is named by the agent, not by its binary", @":49210 Claude Code", server.name);
    T(@"window: its story names the agent and its session, and who started the agent", @"Port=:49210; Agent=Claude Code; Session=Access permissions request inquiry; Project=app; Started by=Terminal; Running=44 min",
      story(server));
    T(@"window: and as phrases on its second line", @"Claude Code; Access permissions request inquiry; in app; started by Terminal; up 44 min", phrases(server));
    T(@"window: the agent's row says the port it serves",
      [NSString stringWithFormat:@"Access permissions request inquiry | Agent=Claude Code; Project=%@; Running=44 min; Last active=just now; Serves=port 49210; State=working | serves port 49210",
       [Dir(@"app") stringByAbbreviatingWithTildeInPath]],
      [NSString stringWithFormat:@"%@ | %@ | %@", agent.name, story(agent), [phrases(agent) componentsSeparatedByString:@"; "].lastObject]);
    T(@"window: a server an agent started still says it was started by the agent", @"Started by=Claude Code",
      [story([m row:@"locohost:server:app#dev"]) componentsSeparatedByString:@"; "][3]);

    // One pid, two rows that hold each other: the ring counts it once, in servers, and the agents' part lets it go.
    uint64_t servers1 = [p.memory.parts[MMPerformanceServers] unsignedLongLongValue], agents1 = [p.memory.parts[MMPerformanceAgents] unsignedLongLongValue];
    T(@"window: the ring counts the agent's server once, in servers, and not again in agents", @"200 -200 0",
      [NSString stringWithFormat:@"%lld %lld %lld", (long long)(servers1 - servers0) / (long long)MB, ((long long)agents1 - (long long)agents0) / (long long)MB,
       ((long long)(servers1 + agents1) - (long long)(servers0 + agents0)) / (long long)MB]);
    T(@"window: both rows still show their own number", @"200 200", [NSString stringWithFormat:@"%llu %llu", server.bytes / MB, agent.bytes / MB]);
}
