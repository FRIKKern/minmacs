// The answers of Ask MinMacs on the render's busy day, MMWindowFixture.m: each in the words Shell/MMAsk.m gives, so
// the render's checks hold the answer's view to them. "ask-empty" and "ask-typing" have no answer.
#import "UI/Window/MMWindowFixtureParts.h"

static MMWindowAnswerEntry *Entry(NSString *sentence, NSString *why, NSString *detail, NSString *row, NSString *logKey) {
    MMWindowAnswerEntry *e = [MMWindowAnswerEntry new];
    e.sentence = sentence; e.why = why; e.detail = detail; e.row = row; e.logKey = logKey;
    return e;
}

static MMWindowSuggest *Suggest(NSString *action, NSString *title, NSString *target, NSString *command, NSString *help) {
    MMWindowSuggest *s = [MMWindowSuggest new];
    s.action = action; s.title = title; s.target = target; s.command = command; s.help = help;
    return s;
}

MMWindowAnswer *MMWindowFixtureAnswer(NSString *name) {
    MMWindowAnswer *a = [MMWindowAnswer new];
    a.serial = 1;
    if ([name isEqualToString:@"ask-why"]) {
        a.question = @"why did you stop 4321"; a.kind = @"why";
        a.answer = @"The log holds 2 actions on “4321”, newest first, each with its own reason.";
        a.entries = @[Entry(@"Stopped :4321 Astro. Undo starts it again.", @"Its reason: idle for 2 h 10 min, no agent above it. The review said: No requests in 2 hours and nothing in its project changed.",
                            @"14:02 · on its own, Careful", @"server:4321", nil),
                      Entry(@"Stopped :4321 Astro, started again 09:12.", @"The review said: Idle since last night; its port answered no requests.",
                            @"Yesterday 08:40 · by you, in Fix Everything", nil, @"undo:118")];
    } else if ([name isEqualToString:@"ask-keep"]) {
        a.question = @"keep fix-auth-redirect"; a.kind = @"keep";
        a.answer = @"A keep means no rule acts on fix-auth-redirect for 7 days. Nothing changes until you press Keep for 7 days.";
        a.entries = @[Entry(@"fix-auth-redirect", nil, nil, @"worktree:fix-auth-redirect", nil)];
        a.suggest = Suggest(@"keep", @"Keep for 7 days", @"worktree:fix-auth-redirect", @"minmacs keep /Users/sam/code/atlas-worktrees/fix-auth-redirect",
                            @"No rule stops or removes it for 7 days. Fix Everything leaves it too.");
    } else if ([name isEqualToString:@"ask-undo"]) {
        a.question = @"undo the last one"; a.kind = @"undo";
        a.answer = @"The newest thing can still be taken back. Nothing changes until you press Undo.";
        a.entries = @[Entry(@"Stopped :3001 Next.js. Undo starts it again.", nil, @"14:02 · on its own, Careful", nil, @"undo:0")];
        a.suggest = Suggest(@"undo", @"Undo", @"rid-0", @"minmacs restore rid-0", @"Undo starts it again.");
    } else if ([name isEqualToString:@"ask-undone"]) {
        a = [MMWindowFixtureAnswer(@"ask-undo") withNote:@"Taking it back."];
    } else if ([name isEqualToString:@"ask-plan"]) {
        a.question = @"what would you clean now"; a.kind = @"plan";
        a.answer = @"Fix Everything would run 5 fixes and give back 3.16 GB memory and 19.1 GB disk. Nothing runs until you press it.";
        a.entries = @[Entry(@"Wrap Up fix-auth-redirect.", nil, @"+1.80 GB memory · +1.91 GB disk", nil, nil),
                      Entry(@"Move 1 leftover to the Trash.", nil, @"+14.5 GB disk", nil, nil),
                      Entry(@"Stop 5 idle servers.", nil, @"+816 MB memory", nil, nil),
                      Entry(@"Quit 1 app.", nil, @"+578 MB memory", nil, nil),
                      Entry(@"Remove 3 merged worktrees.", nil, @"+2.62 GB disk", nil, nil),
                      Entry(@"Clean npm cache.", @"Skipped, since it waits for your own press.", nil, nil, nil),
                      Entry(@"Tune the ranking", @"Skipped, since it asks you.", nil, @"agent:0", nil)];
    } else if ([name isEqualToString:@"ask-asking"]) {
        // Tier 1 while Claude is asked, in the words Shell/MMAskClaude.m gives: Asking Claude, with Stop.
        a.question = @"Hey there"; a.kind = @"unknown"; a.asking = YES;
        a.answer = MMWindowAskAsking;
        a.suggest = Suggest(@"stop", @"Stop", @"ask", nil, @"Stops asking Claude. Nothing was done, and nothing will be.");
    } else if ([name isEqualToString:@"ask-claude"]) {
        a.question = @"is :6006 still needed"; a.kind = @"claude"; a.answeredBy = @"claude"; a.model = @"opus"; a.tokens = 1240;
        a.answer = @":6006 Storybook has had no requests for 6 hours and no agent above it, so Fix Everything would stop it. If you still use it, keep it.";
        a.byline = @"Answered by Claude · 1,240 tokens";
        a.entries = @[Entry(@":6006 Storybook", nil, nil, @"server:6006", nil)];
        a.suggest = Suggest(@"keep", @"Keep for 4 hours", @"server:6006", @"minmacs keep 6006", @"No rule stops or removes it for 4 hours. Fix Everything leaves it too.");
    } else if ([name isEqualToString:@"ask-unreachable"]) {
        a.question = @"Hey there"; a.kind = @"unknown"; a.model = @"opus";
        a.answer = @"Claude isn't reachable: Not logged in · Please run /login. The rules answer the questions below.";
        a.examples = @[@"Why did you stop :4321 Astro?", @"What would you clean now?", @"What is :3001 Next.js?"];
    } else {
        a.question = @"is it going to rain tomorrow"; a.kind = @"unknown";
        a.answer = MMWindowAskCannot;
        a.examples = @[@"Why did you stop :4321 Astro?", @"What would you clean now?", @"What is :3001 Next.js?"];
    }
    return a;
}
