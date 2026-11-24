// An agent row's story, and Claude Code's scratch as the owner's Mac had it. Included by window.m, after collapse.m.
// The owner wrote: "On Agent we want to see what they been doing, where they are, what worktrees, their milestones
// etc, what cache it hold, etc." Here a fixture agent works in a fixture worktree whose finding holds a pull request,
// with a session Know read, a server it started, a port of its own and its session's scratch, and the story says
// each of them. Another agent with none of these facts says none of them: a missing fact is left out, never guessed.

static NSString *StoryOf(MMWindowRow *r) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMWindowFact *f in r.facts) [a addObject:[NSString stringWithFormat:@"%@=%@%@", f.label, f.value, f.link ? [@" -> " stringByAppendingString:f.link] : @""]];
    return [a componentsJoinedByString:@"; "];
}

/// Claude Code's scratch as Noo-Noo's finding of it: a session's folder, or an entry of its scratchpad.
static MMFinding *ScratchAt(NSString *rel, NSString *state, uint64_t bytes) {
    NSString *dir = Dir(rel);
    BOOL free = [state isEqualToString:@"free"];
    return Finding(@"noonoo", @"clutter", [@"claude-code-scratch:" stringByAppendingString:dir], @"Claude Code scratch", dir, 0, 0, bytes,
                   P(@"remove", MMReversibleTrash),
                   @{@"kindID": @"claude-code-scratch", @"kindTitle": @"Claude Code scratch", @"name": @"Claude Code scratch", @"state": state, @"path": dir,
                     @"owner": rel.pathComponents[1], @"section": free ? @"leftovers" : @"kept", @"why": free ? @"nothing has used it for 2 d" : @"its session is alive",
                     @"collapse": @{@"title": @"Claude Code scratch", @"one": @"session", @"many": @"sessions"}});
}

static void AgentStory(void) {
    World();
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSString *sid = @"5d3c1a2b-0f4e-4a8b-9c7d-6e5f4a3b2c1d";
    NSString *wt = Dir(@"trees/agent-story"), *cwd = Dir(@"trees/agent-story/Sources");
    Tree(wt, NO, MMMergedNone);

    // The agent: Claude Code in the worktree, running 44 minutes, a session Know read with its last hour.
    Proc(71050, 30 * MB);
    gChildren[@71011] = @[@71050];
    TSession *x = [TSession new];
    x.agent = @"claude-code"; x.sessionID = sid; x.cwd = cwd; x.branch = @"agent-story"; x.title = @"Give the agent row a story"; x.pid = 71011;
    x.started = [NSDate dateWithTimeIntervalSinceNow:-2640]; x.lastActive = [NSDate dateWithTimeIntervalSinceNow:-180];
    // Three tool uses in the last hour, one of them two hours old and so not recent; two files edited lately.
    x.toolUseTimes = @[@(now - 7200), @(now - 1500), @(now - 600), @(now - 200)];
    x.edits = @{@"/x/old.m": @(now - 7000), @"/x/a.m": @(now - 600), @"/x/b.m": @(now - 200)};
    [gSessions addObject:x];
    NSMutableArray *mm = [gFindings[@"minmacs"] mutableCopy];
    for (NSUInteger i = 0; i < mm.count; i++) {
        MMFinding *f = mm[i];
        if (![f.stableKey isEqualToString:@"claude-code:s-71011"]) continue;
        NSMutableDictionary *fx = [f.facts mutableCopy];
        fx[@"project"] = cwd; fx[@"ports"] = @[@49210];
        fx[@"where"] = @"cmux, minmacs, agent story"; fx[@"whereApp"] = @"cmux"; fx[@"whereGo"] = @YES;
        mm[i] = Finding(@"minmacs", @"agent", [@"claude-code:" stringByAppendingString:sid], f.title, nil, 71011, 200 * MB, 0, nil, fx);
    }
    [mm addObject:Finding(@"minmacs", @"agent", @"codex:bare", @"Codex", nil, 71060, 50 * MB, 0, nil,
                          @{@"harnessID": @"codex", @"name": @"Codex", @"state": @"idle", @"pid": @71060})];
    gFindings[@"minmacs"] = mm;

    // Its worktree, with the pull request the window's pull requests wrote, and a server its child runs.
    NSMutableArray *trees = [gFindings[@"workforest"] mutableCopy];
    [trees addObject:Finding(@"workforest", @"worktree", wt, @"repo/agent-story", wt, 0, 0, 40 * MB, nil,
                             @{@"path": wt, @"repo": Dir(@"repo"), @"branch": @"agent-story", @"dirty": @1, @"untracked": @0, @"unpushed": @0,
                               @"lastWorkAt": @(now - 60), @"pullRequest": @{@"number": @142, @"title": @"Agent story", @"state": @"open",
                                                                          @"url": @"https://example.invalid/pull/142", @"milestone": @"Phase 6"}})];
    gFindings[@"workforest"] = trees;
    NSMutableArray *servers = [gFindings[@"locohost"] mutableCopy];
    [servers addObject:Finding(@"locohost", @"server", @"story#dev", @":5175 Vite agent-story", wt, 71050, 30 * MB, 0, P(@"stop", MMReversibleRestart),
                               @{@"port": @5175, @"framework": @"Vite", @"project": @"agent-story", @"state": @"active"})];
    gFindings[@"locohost"] = servers;

    // Its session's scratch, a folder named by the session, and an entry of its scratchpad inside it.
    NSString *scratch = [@"tmp/-Users-fixture/" stringByAppendingString:sid];
    NSMutableArray *clutter = [gFindings[@"noonoo"] mutableCopy];
    [clutter addObject:ScratchAt(scratch, @"live", 112ull * 1000 * 1000)];
    [clutter addObject:ScratchAt([scratch stringByAppendingString:@"/scratchpad/notes.txt"], @"free", 5ull * 1000 * 1000)];
    gFindings[@"noonoo"] = clutter;

    MMSnapshot *s = WorldSnapshot();
    MMWindowModel *m = MMWindowModelFrom(s, Build(s), [MMWindowExtras readWithLogin:YES]);
    MMWindowRow *agent = [m row:[@"minmacs:agent:claude-code:" stringByAppendingString:sid]];
    NSString *home = [wt stringByAbbreviatingWithTildeInPath];
    T(@"agent story: what it has been doing, where it is, its worktree and pull request, and what it holds, each from its fact",
      [NSString stringWithFormat:@"Agent=Claude Code; Project=%@/Sources; Branch=agent-story; Running=44 min; Last active=3 min ago; "
       @"Recently=3 tool uses, 2 files edited in the last hour; Runs in=cmux, minmacs, agent story; Worktree=repo · agent-story -> workforest:worktree:%@; "
       @"Pull request=#142 · open · milestone: Phase 6; Serves=port 49210; Server=:5175 Vite -> locohost:server:story#dev; "
       @"Cache=Claude Code scratch · 112 MB -> noonoo:clutter:claude-code-scratch:%@; Processes=1 process under it · 30 MB; State=working", home, wt, Dir(scratch)],
      StoryOf(agent));
    T(@"agent story: its name is the session's title, so no Session line repeats it; its first line says when it was last active",
      @"Give the agent row a story | Working. Last active 3 min ago.", [NSString stringWithFormat:@"%@ | %@ %@", agent.name, agent.fate.lead, agent.fate.note]);
    T(@"agent story: Go to names the app, and --json carries it and each link", @"cmux cmux 3",
      [NSString stringWithFormat:@"%@ %@ %lu", agent.goTo, agent.json[@"goTo"],
       (unsigned long)[[agent.json[@"facts"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"link != nil"]] count]]);
    T(@"agent story: the row's second line is as before, its harness and its folder", @"yes",
      YN([[agent.storyFacts.firstObject phrase] isEqualToString:@"Claude Code"] && [agent.storyFacts[1].phrase isEqualToString:@"in Sources"]));

    // An agent with its harness and its state alone: no session, no process in the sample, no place, no folder.
    MMWindowRow *other = [m row:@"minmacs:agent:codex:bare"];
    T(@"agent story: an agent with few facts says only those, and has no Go to", @"Agent=Codex; State=idle no",
      [NSString stringWithFormat:@"%@ %@", StoryOf(other), YN(other.goTo != nil)]);

    // A link to a member of a row that stands for several names that row. Two more sessions make three of a kin.
    [clutter addObject:ScratchAt(@"tmp/-Users-fixture/11111111-2222-3333-4444-555555555555", @"live", 90ull * 1000 * 1000)];
    [clutter addObject:ScratchAt(@"tmp/-Users-fixture/66666666-7777-8888-9999-000000000000", @"live", 80ull * 1000 * 1000)];
    gFindings[@"noonoo"] = clutter;
    MMSnapshot *s2 = WorldSnapshot();
    MMWindowModel *m2 = MMWindowModelFrom(s2, Build(s2), [MMWindowExtras readWithLogin:YES]);
    MMWindowRow *agent2 = [m2 row:[@"minmacs:agent:claude-code:" stringByAppendingString:sid]];
    NSString *link = nil;
    for (MMWindowFact *f in agent2.facts) if ([f.label isEqualToString:@"Cache"]) link = f.link;
    T(@"agent story: its cache's link names the one row its kin stands as", @"kin:noonoo:claude-code-scratch yes", [NSString stringWithFormat:@"%@ %@", link, YN([m2 row:link] != nil)]);
}

/// Claude Code's scratch shaped as the owner's Mac had it, from `minmacs clutter list --json`: session folders in use
/// under /private/tmp/claude-501/<project>/<session>, and inside one live session's folder the entries of its
/// scratchpad, each a member of the same registry row. Kept apart for that, every one stood as a row of its own.
static void CollapseReal(void) {
    World();
    NSMutableArray *clutter = [NSMutableArray new];
    uint64_t outer = 0;
    NSArray *sessions = @[@"8a29b38f-9c84-488e-968f-fa8c5d4ae563", @"d42cf9c3-9b61-463e-a932-d57e59c32436", @"0b1c2d3e-4f50-6172-8394-a5b6c7d8e9f0"];
    for (NSUInteger i = 0; i < sessions.count; i++) {
        uint64_t b = (uint64_t)(119 - i * 7) * 1000 * 1000;
        outer += b;
        [clutter addObject:ScratchAt([@"claude-501/-Users-fixture/" stringByAppendingString:sessions[i]], @"live", b)];
    }
    // Other agents' build folders under the same tmp, as the row's paths find them.
    for (NSString *dir in @[@"mm-cache-collapse/render", @"mm-wt-project/after"]) {
        outer += 100ull * 1000 * 1000;
        [clutter addObject:ScratchAt([@"claude-501/" stringByAppendingString:dir], @"live", 100ull * 1000 * 1000)];
    }
    // Inside the live session d42cf9c3: its scratchpad's entries, one of them old enough to go.
    for (NSInteger i = 0; i < 6; i++)
        [clutter addObject:ScratchAt([NSString stringWithFormat:@"claude-501/-Users-fixture/%@/scratchpad/file%ld.txt", sessions[1], (long)i], i == 0 ? @"free" : @"live", 20ull * 1000 * 1000)];
    gFindings[@"noonoo"] = clutter;
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    NSInteger scratchRows = 0;
    for (MMWindowRow *r in Caches(m).rows) if ([r.name isEqualToString:@"Claude Code scratch"]) scratchRows++;
    MMWindowRow *row = [m row:@"kin:noonoo:claude-code-scratch"];
    T(@"collapse real: eleven scratch members, six of them inside a live session's folder, are one row", @"1 11 6",
      [NSString stringWithFormat:@"%ld %@ %@", (long)scratchRows, row.json[@"collapsed"][@"count"], row.json[@"collapsed"][@"inside"]]);
    T(@"collapse real: its size counts the outer folders only, so what lies inside is not counted twice", @"yes 5 sessions",
      [NSString stringWithFormat:@"%@ %@", YN(row.bytes == outer), FactOf(row, @"Holds").value]);
    T(@"collapse real: in use, and its split counts the outer five", @"in use | 5 sessions in use",
      [NSString stringWithFormat:@"%@ | %@", row.state, FactOf(row, @"Now").value]);
    T(@"collapse real: Performance and clutter list still keep every member apart", @"11", @(p.diskGroups[1].rows.count));
}
