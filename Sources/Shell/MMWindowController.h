// The live part of the menu window, issue #62: the object the shell owns between the graph and the panel.
//
//   main                         no.guerrilla.minmacs.core.window            main
//   MMGraph observe ──snapshot──► one MMPerformance per generation ──model──► onModel(model)
//   MMWindowHost calls ─────────► MMSetMode, the lid, Fix Everything ───────► a new model of the same snapshot
//
// Until the person pressed Start once, every model holds the welcome, MMWindowWelcomeNow. Opened before the first
// snapshot, the controller hands over a model of generation 0 that holds the welcome alone, so the welcome is there
// at once. Its switch starts on for a person whose first launch had the window, and on what the login item is now
// for anyone who had MinMacs before. Start applies the two answers: the login item through the shell, the removal choice and the done mark.
//
// It works only while the window is open: -setOpen:NO ends the observing and lets the last snapshot go. A snapshot
// that arrives while an older one is still being built replaces it, so only the newest generation reaches main.
// Fix Everything runs on its own queue through MMFixRunner, and each step sends a model whose run moved.
#import <Cocoa/Cocoa.h>
#import "UI/Window/MMWindowUI.h"

NS_ASSUME_NONNULL_BEGIN

/// Open at login, as the window needs it. MMShell answers with SMAppService. A check answers with a fake, so no
/// check ever touches the real login item.
@protocol MMWindowLogin <NSObject>
- (BOOL)loginEnabled;
- (void)setLogin:(BOOL)on;
@end

@interface MMWindowController : NSObject <MMWindowHost>
/// Each new model, on main. Set it before -setOpen:YES.
@property (copy, nullable) void (^onModel)(MMWindowModel *model);
/// The shell, for Open at login. Without one the switch reads off and a press changes nothing.
/// Only two things ever call -setLogin: here: the switch in Settings, and Start in the welcome.
@property (weak, nullable) id<MMWindowLogin> shell;
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
