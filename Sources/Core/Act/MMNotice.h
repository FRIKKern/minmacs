// D3: no person is ever needed. MinMacs runs unattended on a fleet Mac, often with the lid shut and the display
// asleep, driven by an agent such as BarkBot. Nothing waits for a person:
//
//   a failure ──► MMNotice ──► a row of the log's notice table, which the window's middle and `minmacs log` show
//                          └─► at most one ordinary notification, through MMNotify, which needs no click
//   a confirm  ──► only for a press a person plainly made, MMPersonPresses, and never while unattended
//   the CLI    ──► never reads stdin when no person is at the terminal, MMNoPersonAtTerminal
//
// AGENTS.md invariant 6 has the rule. No modal alert is shown anywhere else: test/unattended.sh holds the list.
#import <Foundation/Foundation.h>

/// @"core.unattended": YES on a Mac that runs with nobody at it. `minmacs unattended on|off` sets it, with a row of
/// the log's setting table. The welcome is skipped and its defaults applied, and no confirm is ever shown.
extern NSString *const MMUnattendedKey;

/// YES when MINMACS_UNATTENDED=1 is in this process's environment, or the pref core.unattended is on.
/// MINMACS_UNATTENDED=0 says a person is here, whatever the pref holds. Safe from any queue.
BOOL MMUnattended(void);

/// For the CLI: YES when no person can answer at this process's terminal, so nothing is asked on it: stdin is not a
/// TTY, or MMUnattended. MINMACS_UNATTENDED=0 says a person is here even with no TTY; then nothing is read either,
/// and a verb that would have asked refuses instead.
BOOL MMNoPersonAtTerminal(void);

/// Main thread, in the app. YES only while main handles a click or a key press, the press a person makes in the
/// window or a menu, and the Mac is not unattended. Anything started on its own, from a URL, from the CLI or from a
/// timer gets NO. A confirm is shown only when this was YES at the press.
BOOL MMPersonPresses(void);

/// The log's table of things a person may want to know that no record says: {expert, title, text}.
extern NSString *const MMLogNoticeTable;                 // @"notice"

/// Where a failure goes instead of an alert: one row of the notice table, and at most one ordinary notification,
/// MMNotify's rate limit, with no Undo and no button. title is short title case, text full sentences. Any queue.
void MMNotice(NSString *expert, NSString *title, NSString *text);

/// Posted on the default center when `minmacs unattended on` ran in the app, so the shell applies what the welcome
/// would have. Any queue.
extern NSString *const MMUnattendedChangedNotification;
