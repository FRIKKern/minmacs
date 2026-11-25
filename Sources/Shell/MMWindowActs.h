// What an item of a row's menu in the window does, MMWindowMenuItem in UI/Window/MMWindowModel.h. The controller
// hands each pick here, off main. An item that changes something runs through the action paths the menus and Fix
// Everything use: MMRunAction with the expert's -pressAction:finding:step:policy:, MMRunWrapUp and MMKeep, each with
// "window" as who acted, so the log says "by you in the window" and Undo takes back what its record allows. None asks
// for a confirm: Undo is there, D3. An item that only shows or copies goes to the desk, on main, and keeps no record.
// No AppKit here: the shell's desk, MMWindowDesk.m, holds it, and a check passes a fake.
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"

NS_ASSUME_NONNULL_BEGIN

/// The Mac's own hands for the items that change nothing MinMacs keeps: bring an app forward, show a folder, copy.
/// Every call comes on main.
@protocol MMWindowDesk <NSObject>
- (void)showApp:(pid_t)pid;                             // brings the app forward with all its windows
- (void)hideApp:(pid_t)pid;
- (void)reveal:(NSString *)path;                        // selects it in its folder in the Finder
- (void)openFolder:(NSString *)path;                    // opens the folder itself in the Finder
- (void)openInTerminal:(NSString *)path;
- (void)openURL:(NSString *)url;
- (void)copyText:(NSString *)text;
@end

/// The desk of the app, on NSWorkspace, NSRunningApplication and the general pasteboard. MMWindowDesk.m.
id<MMWindowDesk> MMWindowRealDesk(void);

/// The words a press in the window gives MMRunAction, MMRunWrapUp and MMKeep: "window".
extern NSString *const MMWindowBy;

/// One pick of an item of the row `key`'s menu, read again from s and p, the snapshot the window shows now. Blocks
/// while an action runs, so it never runs on main or on the window's queue. Returns the record of an action, or nil;
/// *problem says why nothing ran, and a failure is also a notice, D3. "show-row" and "go-to" are the window's own and
/// do nothing here. The graph is asked to build again after anything that changed.
MMUndoRecord *_Nullable MMWindowRowAct(NSString *action, NSString *key, MMSnapshot *s, MMPerformance *p,
                                       id<MMWindowDesk> _Nullable desk, NSString *_Nullable *_Nullable problem);

NS_ASSUME_NONNULL_END
