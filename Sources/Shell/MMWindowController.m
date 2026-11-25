// The window's controller, MMWindowController.h.
#import <stdatomic.h>
#import "Shell/MMWindowController.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMFixRunner.h"
#import "Shell/MMWindowLog.h"
#import "Shell/MMAsk.h"
#import "Core/MMCore.h"

static const NSTimeInterval kEndShows = 4;               // an ended run stays on the model this long, then lets go

/// What the keep-awake expert answers. The shell links without Sources/Experts, so these are asked for by name.
@protocol MMWindowLidExpert <NSObject>
/// The menu's own toggle, on main: it asks first when the lid mode turns on, then changes it off main.
- (void)act:(NSString *)what key:(nullable NSString *)key;
/// The same, told whether a person made the press, read at the press: only then is there a confirm, D3.
- (void)act:(NSString *)what key:(nullable NSString *)key present:(BOOL)present;
/// The change itself, with its undo record. Never on main.
- (NSString *)set:(NSString *)what value:(id)value by:(NSString *)by;
@end

@implementation MMWindowController {
    id _token;                                           // main
    id _pulls;                                           // main: the observer of MMPulls while open
    uint64_t _shown;                                     // main: the generation of the last model sent
    _Atomic uint64_t _wanted;                            // the newest generation asked for
    atomic_bool _open, _loginOn;
    // One run at a time. Main sets it at the press, before anything is queued, so a second press that lands right
    // behind the first finds it set. The window queue clears it when the run's end has arrived, or when no run began.
    atomic_bool _busy;
    void (^_afterRun)(void);                             // main: what waits for the run to end, such as a quit
    // Only on the window queue:
    MMSnapshot *_s;
    MMPerformance *_p;
    MMPerformanceLookBack *_lookBack;
    MMWindowRun *_run;
    MMFixRunner *_runner;
    NSDate *_endedAt;                                    // when the last run ended: a plan built before it is spent
    MMWindowLog *_log;                                   // the log as last read, while open
    NSString *_logStamp;                                 // MMLogStamp and the day at that read
    NSArray *_week;                                      // the 7 days as last read, while open: memory, disk, first hour
    long long _weekHour;                                 // the hour of that read
    NSUInteger _weekWrites;                              // MMHistoryWeekWrites at that read
    NSMutableSet<NSString *> *_undoing;                  // the records an Undo press is taking back now
    NSMutableDictionary<NSString *, NSString *> *_undoProblems;   // what a restore answered, by rid, while open
    MMWindowModel *_built;                               // the last model sent, which an ask reads its rows and plan from
    MMWindowAnswer *_answer;                             // the answer of the last ask, while open
    NSInteger _asks;                                     // counts the asks, so the window tells a new answer
    MMModelStop *_asking;                                // the Claude call of the ask that runs now, or nil
    MMWindowAnswer *_askingRules;                        // the rules' answer of that ask, for its Stop
    NSMutableArray<MMAskTurn *> *_turns;                 // the last questions and answers of this open window
}

static dispatch_queue_t AskQueue(void) { return MMQueue(@"core", @"ask", QOS_CLASS_USER_INITIATED); }

static dispatch_queue_t Queue(void) { return MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED); }

- (BOOL)open { return atomic_load(&_open); }

- (void)setOpen:(BOOL)open {
    if (atomic_exchange(&_open, open) == open) return;
    if (!open) {
        [MMGraph.shared stopObserving:_token];
        if (_pulls) [NSNotificationCenter.defaultCenter removeObserver:_pulls];
        _token = nil; _pulls = nil; _model = nil; _shown = 0;
        atomic_store(&_wanted, 0);
        // The run and its runner stay: a run under way ends on its own and then clears itself.
        dispatch_async(Queue(), ^{ self->_s = nil; self->_p = nil; self->_lookBack = nil; self->_log = nil; self->_logStamp = nil; self->_undoProblems = nil; self->_week = nil;
                                     // A closed window stops a Claude call that runs, and lets its answer and its conversation go.
                                     [self stopAsking];
                                     self->_built = nil; self->_answer = nil; self->_turns = nil; });
        return;
    }
    atomic_store(&_loginOn, [self.shell loginEnabled]);
    __weak MMWindowController *weak = self;
    _token = [MMGraph.shared observe:^(MMSnapshot *s) { [weak take:s]; }];
    // A pull request gh told about, or a look that ended: the same snapshot again, with what is known now.
    _pulls = [NSNotificationCenter.defaultCenter addObserverForName:MMPullsDidChangeNotification object:nil queue:nil
                                                         usingBlock:^(NSNotification *n) { [weak sendSoon]; }];
    MMSnapshot *now = MMGraph.shared.current;
    if (now) { [self take:now]; return; }
    // The first launch: no snapshot yet. The welcome needs none, so it is there with the window.
    MMWindowWelcome *welcome = MMWindowWelcomeNow(atomic_load(&_loginOn));
    if (!welcome) return;
    MMWindowModel *m = [MMWindowModel new];
    m.welcome = welcome;
    _model = m;
    if (self.onModel) self.onModel(m);
}

/// Main. One build per generation: a snapshot the window already holds or has asked for is not built again.
- (void)take:(MMSnapshot *)s {
    if (!self.open || !s || s.generation <= atomic_load(&_wanted)) return;
    atomic_store(&_wanted, s.generation);
    dispatch_async(Queue(), ^{
        // A newer snapshot came while this one waited, so this one is stale.
        if (!self.open || s.generation < atomic_load(&self->_wanted)) return;
        if (!self->_lookBack) self->_lookBack = [MMPerformanceLookBack read:MMGains.shared now:NSDate.date];
        self->_p = [MMPerformance from:s history:s.history lookBack:self->_lookBack];
        self->_s = s;
        [self askPlaces:s];
        [self send];
    });
}

/// The window queue, while open. Where each agent runs on screen is the window's alone, so the window asks Know for
/// it and no build does, issue #52. Know answers on its own queue, at most once a minute a process, and the story
/// reads the answer from Know's memory, so a place asked for now shows from the next snapshot on.
- (void)askPlaces:(MMSnapshot *)s {
    MMSample *sample = s.facts.sample;
    if (!sample) return;
    for (MMFinding *f in [s findingsFor:@"minmacs"]) {
        if (![f.kind isEqualToString:@"agent"] || !f.procs.count) continue;
        MMProcKey k = {0, 0};
        [f.procs.firstObject getValue:&k size:sizeof k];
        (void)MMWhereIs(k, sample, NO);
    }
}

/// The window queue. A model of the snapshot held, with the switches and the run as they are now. It builds no
/// MMPerformance, so a step of a run or a changed rule costs only the feed.
- (void)send {
    if (!_s || !_p || !self.open) return;
    MMWindowExtras *x = [MMWindowExtras readWithLogin:atomic_load(&_loginOn)];
    x.run = _run;
    x.log = MMWindowLogWithUndo([self readLog], _undoing, _undoProblems);
    x.stripWeek = MMPrefBool(MMWindowWeekKey, NO);
    if (x.stripWeek) [self readWeek:x];
    x.welcome = MMWindowWelcomeNow(x.loginOn);
    MMWindowModel *m = MMWindowModelFrom(_s, _p, x);
    m.answer = _answer;
    _built = m;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.open || m.generation < self->_shown) return;
        self->_shown = m.generation; self->_model = m;
        if (self.onModel) self.onModel(m);
    });
}

/// The window queue, while open. The log is read again only when MMLogStamp moved, two stats and no query, or the
/// day turned, which changes the words "Today" and "Yesterday". No timer: a new snapshot or a press asks.
- (MMWindowLog *)readLog {
    NSString *stamp = [MMLogStamp() stringByAppendingString:[NSCalendar.currentCalendar startOfDayForDate:NSDate.date].description];
    if (_log && [stamp isEqualToString:_logStamp]) return _log;
    MMLog *log = MMLog.shared;
    if (!log) return _log;
    _log = MMWindowLogRead(log, NSDate.date, MMWindowLogMost, MMWindowLogDays);
    _logStamp = stamp;
    return _log;
}

/// The window queue, while open and while the strip shows the 7 days. The points are read again only when the hour
/// turned or this process wrote an hour since: one read an hour, two at most, and none while the strip shows the hour.
- (void)readWeek:(MMWindowExtras *)x {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    long long hour = (long long)floor(now / 3600);
    NSUInteger writes = MMHistoryWeekWrites();
    if (!_week || hour != _weekHour || writes != _weekWrites) {
        MMLog *log = MMLog.shared;
        if (!log) return;
        NSTimeInterval first = 0;
        NSArray *memory = MMHistoryWeekHours(log, MMHistoryWeekMemory, now, MMHistoryWeekDays, &first);
        _week = @[memory, MMHistoryWeekHours(log, MMHistoryWeekDisk, now, MMHistoryWeekDays, NULL), @(first)];
        _weekHour = hour; _weekWrites = writes;
    }
    x.memoryWeek = _week[0]; x.diskWeek = _week[1]; x.weekFirstAt = [_week[2] doubleValue];
}

/// The strip's choice, from its two words. A look, kept as a pref with no row in the log, off main.
- (void)windowStripWeek:(BOOL)week {
    dispatch_async(Queue(), ^{ MMSetPref(MMWindowWeekKey, @(week)); [self send]; });
}

- (void)sendSoon { dispatch_async(Queue(), ^{ [self send]; }); }

#pragma mark - MMWindowHost

- (BOOL)running { return atomic_load(&_busy); }

/// The window queue. The run is over, or none began. Whoever waited for it is told on main.
- (void)ended {
    atomic_store(&_busy, false);
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^then)(void) = self->_afterRun;
        self->_afterRun = nil;
        if (then) then();
    });
}

- (BOOL)stopRunThen:(void (^)(void))then {
    if (!atomic_load(&_busy)) return NO;
    _afterRun = [then copy];
    [self windowStopRun];
    return YES;
}

- (void)windowRunFixEverything {
    if (atomic_exchange(&_busy, true)) return;
    dispatch_async(Queue(), ^{
        // A plan built before the last run ended may name things that run already acted on. The press waits for a
        // snapshot built since, which the run's own rebuild brings.
        BOOL spent = self->_endedAt && (!self->_s.builtAt || [self->_s.builtAt compare:self->_endedAt] != NSOrderedDescending);
        MMPerformance *p = spent ? nil : self->_p;
        NSInteger n = 0;
        for (MMPerformanceFix *f in p.fixes) if (!f.needsYou) n++;
        if (!n) { [self ended]; return; }
        MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
        __weak MMWindowController *weak = self;
        // Progress comes on the runner's queue. The run is kept and sent from the window queue.
        runner.onProgress = ^(MMWindowRun *run) {
            dispatch_async(Queue(), ^{
                MMWindowController *me = weak;
                if (!me) return;
                me->_run = run;
                [me send];
                if (run.running) return;
                // What came back is in the gains log now, so the look-back is read again for the next build.
                me->_lookBack = nil;
                me->_endedAt = me->_runner.endedAt ?: NSDate.date;
                [me ended];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEndShows * NSEC_PER_SEC)), Queue(), ^{
                    MMWindowController *later = weak;
                    if (!later || later->_run != run) return;
                    later->_run = nil;
                    [later send];
                });
            });
        };
        self->_runner = runner;
        [runner start];
    });
}

- (void)windowStopRun { dispatch_async(Queue(), ^{ [self->_runner stop]; }); }

- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice {
    NSString *expert = MMWindowRuleExpert(ruleID);
    if (!expert || choice < MMModeIdle || choice > MMModeEager) return;
    dispatch_async(Queue(), ^{
        MMSetMode(expert, (MMMode)choice, @"window");
        [self send];
        // Each expert reads its mode when the graph prepares a snapshot, so its plan follows at the next build.
        [MMGraph.shared rebuild:@"window mode"];
    });
}

/// Start in the welcome, on main. This and the Settings switch are the only places the window changes the login item,
/// so nothing is added before the person answered. The prefs are written here, before anything else can build a
/// model, so no later model brings the welcome back.
- (void)windowWelcomeStart:(BOOL)openAtLogin {
    if (MMPrefBool(MMWindowWelcomedKey, NO)) return;
    MMWindowWelcomeDone();
    // Only a change is asked for: a person whose answer is what the login item already is gets nothing touched.
    BOOL before = [self.shell loginEnabled];
    if (before != openAtLogin) [self.shell setLogin:openAtLogin];
    BOOL after = [self.shell loginEnabled];
    atomic_store(&_loginOn, after);
    // The rows go in on the window queue, never on main, and before the model they show in. The log holds what the
    // login item became, which is what the system took, not only what was asked.
    dispatch_async(Queue(), ^{
        MMLogSetting(MMWindowWelcomedKey, @NO, @YES, @"welcome");
        MMLogSetting(MMWindowLoginKey, @(before), @(after), @"welcome");
        [self send];
    });
}

/// D3, on main: on a Mac that runs unattended nobody presses Start, so the welcome's defaults apply without it. The
/// login item is turned on, as the welcome's switch starts for a person new to MinMacs, and the rows say it was
/// unattended that did it. It runs once: after it, as after Start, the welcome never comes back.
+ (BOOL)skipWelcomeUnattended:(id<MMWindowLogin>)login {
    if (!NSThread.isMainThread || !MMUnattended() || MMPrefBool(MMWindowWelcomedKey, NO)) return NO;
    MMWindowWelcomeDone();
    BOOL before = [login loginEnabled];
    if (!before) [login setLogin:YES];
    BOOL after = [login loginEnabled];
    dispatch_async(Queue(), ^{
        MMLogSetting(MMWindowWelcomedKey, @NO, @YES, @"unattended");
        MMLogSetting(MMWindowLoginKey, @(before), @(after), @"unattended");
    });
    return YES;
}

- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on {
    if ([switchID isEqualToString:@"login"]) {
        BOOL before = [self.shell loginEnabled];
        [self.shell setLogin:on];
        BOOL after = [self.shell loginEnabled];
        atomic_store(&_loginOn, after);
        dispatch_async(Queue(), ^{ MMLogSetting(MMWindowLoginKey, @(before), @(after), @"window"); [self send]; });
        return;
    }
    // Asking gh about a worktree's pull request: a pref, with its row in the log.
    if ([switchID isEqualToString:@"prs"]) {
        dispatch_async(Queue(), ^{ MMSetSetting(MMPullsPrefKey, @(on), @"window"); [self send]; });
        return;
    }
    // Ask uses Claude: a pref, with its row in the log.
    if ([switchID isEqualToString:@"askclaude"]) {
        dispatch_async(Queue(), ^{ MMSetSetting(MMAskClaudeKey, @(on), @"window"); [self send]; });
        return;
    }
    // Keep awake now and While agents work are Insomnia's own settings, set with their record, off main.
    NSString *setting = @{@"awake": @"manual", @"agents": @"agents"}[switchID ?: @""];
    if (setting) {
        id<MMWindowLidExpert> e = (id)MMExpertNamed(@"insomnia");
        if (![e respondsToSelector:@selector(set:value:by:)]) return;
        dispatch_async(Queue(), ^{ (void)[e set:setting value:@(on) by:@"manual"]; [self send]; });
        return;
    }
    if (![switchID isEqualToString:@"lid"]) return;
    id<MMWindowLidExpert> e = (id)MMExpertNamed(@"insomnia");
    if (!e) return;
    // D3: read now, at the press, on main. By the time the expert asks, the press is long past.
    BOOL present = MMPersonPresses();
    dispatch_async(Queue(), ^{
        // Read again here, off main, so a press on a switch that already moved does nothing.
        if ([MMWindowExtras readWithLogin:NO].lidOn == on) { [self send]; return; }
        if ([e respondsToSelector:@selector(act:key:)]) {
            // The expert's own toggle keeps its confirm for a person who is there, the one administrator prompt, and
            // its notice on failure.
            // It changes the setting on its own queue and tells nobody, so the switch is read again a little later.
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([e respondsToSelector:@selector(act:key:present:)]) [e act:@"lid" key:nil present:present];
                else [e act:@"lid" key:nil];
                for (NSNumber *wait in @[@1, @5])
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), Queue(), ^{ [self send]; });
            });
        } else if ([e respondsToSelector:@selector(set:value:by:)]) {
            (void)[e set:@"lid" value:@(on) by:@"manual"];
            [self send];
        }
    });
}

/// A press on Undo in the log. The same path as the notification's Undo: -[MMUndo restore:] on core.undo, which
/// refuses a record it cannot take back and a second restore of one that runs. The entry shows that it is being taken
/// back at once, and the log read again once the restore wrote its row shows it was.
- (void)windowUndo:(NSString *)rid {
    if (![rid isKindOfClass:NSString.class] || !rid.length) return;
    dispatch_async(Queue(), ^{
        if (!self->_undoing) self->_undoing = [NSMutableSet new];
        if ([self->_undoing containsObject:rid]) return;
        [self->_undoing addObject:rid];
        [self->_undoProblems removeObjectForKey:rid];
        [self noteAnswer:@"undo" target:rid note:@"Taking it back."];
        [self send];
        dispatch_async(MMQueue(@"core", @"undo", QOS_CLASS_UTILITY), ^{
            NSString *problem = [MMUndo.shared restore:rid];
            dispatch_async(Queue(), ^{
                [self->_undoing removeObject:rid];
                if (problem) { if (!self->_undoProblems) self->_undoProblems = [NSMutableDictionary new]; self->_undoProblems[rid] = problem; }
                [self noteAnswer:@"undo" target:rid note:problem ? [@"It did not go back: " stringByAppendingString:problem] : @"Taken back. The log has it."];
                [self send];
            });
        });
    });
}

#pragma mark - Ask MinMacs

/// The window queue. The answer's suggestion was pressed: its button gives way to this line.
- (void)noteAnswer:(NSString *)action target:(NSString *)target note:(NSString *)note {
    MMWindowSuggest *s = _answer.suggest;
    if ([s.action isEqualToString:action] && [s.target isEqualToString:target]) _answer = [_answer withNote:note];
}

/// The window queue: a question and its answer, kept for the next ask's context while the window stays open.
- (void)remember:(MMWindowAnswer *)a {
    if (!a.question.length || a.asking) return;
    if (!_turns) _turns = [NSMutableArray new];
    [_turns addObject:[MMAskTurn question:a.question answer:a.answer]];
    while (_turns.count > MMAskTurnsKept) [_turns removeObjectAtIndex:0];
}

/// The window queue: the Claude call that runs now stops, and its ask is told as stopped, in the window and the log.
- (void)stopAsking {
    if (!_asking) return;
    [_asking stop];
    _asking = nil;
    MMWindowAnswer *stopped = MMAskStopped(_askingRules);
    _askingRules = nil;
    MMAskLog(stopped, @"window");
    if (_answer.asking) _answer = stopped;
}

/// Return in Ask MinMacs. Tier 0 answers on the window queue from the model last sent and the log's rows. What it has
/// no answer for goes to Claude, tier 1, with the pref ask.claude on: the answer says "Asking Claude" with Stop at
/// once, and Claude's words come in a later model, off this queue on the ask queue, within MMAskClaudeTimeout().
/// Each ask writes its row and sends a model with the answer. It acts on nothing.
- (void)windowAsk:(NSString *)question row:(NSString *)rowKey {
    NSString *q = MMAskQuestion(question);
    if (!q) return;
    NSString *row = [rowKey isKindOfClass:NSString.class] && rowKey.length ? [rowKey copy] : nil;
    dispatch_async(Queue(), ^{
        if (!self.open || !self->_built) return;
        [self stopAsking];
        MMAskWorld *w = [MMAskWorld new];
        w.model = self->_built;
        w.rows = [MMAskWorld rowsOf:MMLog.shared];
        w.targets = [MMAskWorld targetsOf:self->_built snapshot:self->_s];
        w.row = row;
        w.now = NSDate.date;
        MMWindowAnswer *a = MMAskTier0(q, w);
        a.serial = ++self->_asks;
        if (![a.kind isEqualToString:@"unknown"] || !MMAskUsesClaude()) {
            MMAskLog(a, @"window");
            [self remember:a];
            self->_answer = a;
            [self send];
            return;
        }
        MMModelStop *stop = [MMModelStop new];
        NSArray<MMAskTurn *> *turns = [self->_turns copy];
        self->_asking = stop; self->_askingRules = a;
        self->_answer = MMAskAsking(a);
        [self send];
        dispatch_async(AskQueue(), ^{
            MMWindowAnswer *b = stop.stopped ? nil : MMAskTier1(a, w, turns, stop);
            dispatch_async(Queue(), ^{
                // A Stop, a newer ask or a closed window told it already.
                if (!b || stop.stopped || self->_asking != stop) return;
                self->_asking = nil; self->_askingRules = nil;
                b.serial = a.serial;
                MMAskLog(b, @"window");
                [self remember:b];
                if (self.open) { self->_answer = b; [self send]; }
            });
        });
    });
}

/// Stop, while Claude is asked: the call ends, and the answer says nothing came back.
- (void)windowAskStop { dispatch_async(Queue(), ^{ if (!self->_asking) return; [self stopAsking]; [self send]; }); }

- (void)windowAskBack { dispatch_async(Queue(), ^{ [self stopAsking]; if (!self->_answer) return; self->_answer = nil; [self send]; }); }

/// A press on an answer's Keep. The keep its row's own menu gives: MMKeep, by the expert's stable key, for 4 hours or
/// 7 days, with its row in the log, then a rebuild so the rows say it. Read fresh from the snapshot at the press.
- (void)windowKeep:(NSString *)rowKey {
    if (![rowKey isKindOfClass:NSString.class] || !rowKey.length) return;
    dispatch_async(Queue(), ^{
        MMAskTarget *t = MMAskTargetOf([self->_s finding:rowKey]);
        if (!t) return;
        NSTimeInterval span = MMAskKeepFor(t.expert);
        [MMKeep keep:t.stableKey expert:t.expert until:[NSDate dateWithTimeIntervalSinceNow:span] by:@"window" name:t.name];
        [self noteAnswer:@"keep" target:rowKey note:[NSString stringWithFormat:@"Kept for %@. No rule acts on it until then.", span < 86400 ? @"4 hours" : @"7 days"]];
        [self send];
        [MMGraph.shared rebuild:@"window keep"];
    });
}

/// The story of a row shows in the window. For a linked worktree on a branch, MMPulls asks the person's gh for its pull
/// request: on demand only, never for a tick or a snapshot, and never while the window is closed. A look that began is
/// shown at once, and once more past the time gh may take, so a look that got no answer leaves the story.
- (void)windowShowsStory:(NSString *)key {
    if (!self.open || ![key isKindOfClass:NSString.class] || !key.length) return;
    dispatch_async(Queue(), ^{
        if (!self.open || !self->_p) return;
        MMPerformanceRow *r = [self->_p row:key];
        MMFinding *f = r.finding ?: [self->_s finding:r.findingID];
        if (![f.expert isEqualToString:@"workforest"] || ![f.kind isEqualToString:@"worktree"]) return;
        NSDictionary *x = f.facts;
        NSString *repo = [x[@"repo"] isKindOfClass:NSString.class] ? x[@"repo"] : nil, *branch = [x[@"branch"] isKindOfClass:NSString.class] ? x[@"branch"] : nil;
        NSString *head = [x[@"head"] isKindOfClass:NSString.class] ? x[@"head"] : nil, *folder = f.path ?: x[@"path"];
        if (!repo.length || !branch.length || [x[@"main"] boolValue] || [x[@"protected"] boolValue] || [x[@"missing"] boolValue]) return;
        if (![MMPulls.shared want:folder repo:repo branch:branch head:head]) return;
        [self send];
        __weak MMWindowController *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MMPulls.shared.timeout + 1.2) * NSEC_PER_SEC)), Queue(), ^{ [weak send]; });
    });
}

/// A press on Go to in an agent's story. Know's last answer for where the agent runs, with no wait, and MMGoTo off
/// main, since cmux, tmux and AppleScript can take seconds. A place that is gone or a refusal is a notice, D3.
- (void)windowGoTo:(NSString *)rowKey {
    if (![rowKey isKindOfClass:NSString.class] || !rowKey.length) return;
    dispatch_async(Queue(), ^{
        MMFinding *f = [self->_s finding:rowKey];
        MMSample *sample = self->_s.facts.sample;
        if (![f.kind isEqualToString:@"agent"] || !f.procs.count || !sample) return;
        MMProcKey k = {0, 0};
        [f.procs.firstObject getValue:&k size:sizeof k];
        MMPlace *place = MMWhereIs(k, sample, NO);
        if (!place || !MMPlaceGoable(place)) return;
        dispatch_async(MMQueue(@"core", @"go", QOS_CLASS_USER_INITIATED), ^{
            NSString *err = nil;
            if (!MMGoTo(place, &err) && err) MMNotice(@"minmacs", [NSString stringWithFormat:@"Could Not Go to %@", place.app.length ? place.app : @"It"], err);
        });
    });
}

/// The shell's -applicationShouldTerminate: lets a run end its step first, so this never quits in the middle of one.
- (void)windowQuit { [NSApp terminate:nil]; }

@end
