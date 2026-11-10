// The live part of the menu window, issue #62: the object the shell owns between the graph and the panel.
//
//   main                         no.guerrilla.minmacs.core.window            main
//   MMGraph observe ──snapshot──► one MMPerformance per generation ──model──► onModel(model)
//   MMWindowHost calls ─────────► MMSetMode, the lid, Fix Everything ───────► a new model of the same snapshot
//
// It works only while the window is open: -setOpen:NO ends the observing and lets the last snapshot go. A snapshot
// that arrives while an older one is still being built replaces it, so only the newest generation reaches main.
// Fix Everything runs on its own queue through MMFixRunner, and each step sends a model whose run moved.
#import <Cocoa/Cocoa.h>
#import "UI/Window/MMWindowUI.h"

@class MMShell;

NS_ASSUME_NONNULL_BEGIN

@interface MMWindowController : NSObject <MMWindowHost>
/// Each new model, on main. Set it before -setOpen:YES.
@property (copy, nullable) void (^onModel)(MMWindowModel *model);
/// The shell, for Open at login. Without one the switch reads off and a press changes nothing.
@property (weak, nullable) MMShell *shell;
/// The last model sent, main only. nil before the first and after -setOpen:NO.
@property (readonly, nullable) MMWindowModel *model;
@property (readonly) BOOL open;
/// Main only. YES starts observing and builds from the current snapshot at once. NO stops and frees what it held.
/// A run of Fix Everything that is under way goes on to its end either way.
- (void)setOpen:(BOOL)open;
/// YES from the press on Fix Everything until that run's end arrived. Any queue.
@property (readonly) BOOL running;
/// Main only. With no run under way it returns NO and does nothing. With one, it asks the run to stop after the step
/// it is in and calls the block on main once the run ended.
- (BOOL)stopRunThen:(void (^)(void))then;
@end

NS_ASSUME_NONNULL_END
