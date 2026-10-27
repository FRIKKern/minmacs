// Where a process lives on screen, so a menu can jump there. Listed under Know in PLAN.md section 3.
// SYNTHESIS.md gives Where no number of its own. It starts from LH Where.h and Where.m, and uses P9 and P23.
#import <Foundation/Foundation.h>
#import "Core/Senses/MMSenses.h"

/// The kind of place a process runs in.
typedef NS_ENUM(NSInteger, MMPlaceKind) { MMPlaceUnknown, MMPlaceCmux, MMPlaceTmux, MMPlaceTerminal, MMPlaceITerm, MMPlaceApp };

/// The terminal tab, multiplexer pane or app that runs a process. Every field may be empty.
@interface MMPlace : NSObject
@property (readonly) MMPlaceKind kind;
@property (readonly, copy) NSString *app;               // "cmux", "Terminal", "Ghostty", "Claude"
@property (readonly, copy) NSString *label;             // one line for people, such as "cmux, LocoHost, repo check"
@property (readonly, copy) NSString *tab;               // the tab, pane or window title when the app tells us
@property (readonly, copy) NSString *window, *workspace, *surface;   // cmux UUIDs
@property (readonly, copy) NSString *target, *tty;      // a tmux pane id, a terminal device such as ttys003
@property (readonly) pid_t appPid;
@end

/// Where pid runs. cmux and tmux are asked through their own CLIs with MMRun and a time limit.
/// Terminal and iTerm2 are matched by the tty of the shell above pid. Anything else is the responsible app of P9.
/// wait NO returns the last answer, or nil, and refreshes on MMQueue(@"core", @"where"). wait YES looks now, for the CLI.
MMPlace *MMWhereIs(MMProcKey key, MMSample *s, BOOL wait);
/// Brings the place forward. Terminal and iTerm2 need the person's permission the first time. It runs cmux, tmux or
/// osascript and can block for seconds, so call it off the main thread.
BOOL MMGoTo(MMPlace *place, NSString **error);
