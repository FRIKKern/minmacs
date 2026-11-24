// No person needed, D3. MMNotice.h says what each part does.
#import <Cocoa/Cocoa.h>
#import <unistd.h>
#import "Core/Act/MMNotice.h"
#import "Core/Act/MMAct.h"
#import "Core/Store/MMLog.h"
#import "Core/Store/MMStore.h"

NSString *const MMUnattendedKey = @"core.unattended";
NSString *const MMLogNoticeTable = @"notice";
NSString *const MMUnattendedChangedNotification = @"MMUnattendedChanged";

/// "1" or "0" from the environment, or nil when it says neither.
static NSString *EnvWord(void) {
    NSString *v = NSProcessInfo.processInfo.environment[@"MINMACS_UNATTENDED"];
    return [v isEqualToString:@"1"] || [v isEqualToString:@"0"] ? v : nil;
}

BOOL MMUnattended(void) {
    NSString *env = EnvWord();
    if (env) return [env isEqualToString:@"1"];
    return MMPrefBool(MMUnattendedKey, NO);
}

BOOL MMNoPersonAtTerminal(void) {
    if ([EnvWord() isEqualToString:@"0"]) return NO;
    return !isatty(STDIN_FILENO) || MMUnattended();
}

BOOL MMPersonPresses(void) {
    if (!NSThread.isMainThread || !NSApp || MMUnattended()) return NO;
    switch (NSApp.currentEvent.type) {
        case NSEventTypeLeftMouseDown: case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseDown: case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseDown: case NSEventTypeOtherMouseUp:
        case NSEventTypeKeyDown: case NSEventTypeKeyUp:
            return YES;
        default:
            return NO;
    }
}

void MMNotice(NSString *expert, NSString *title, NSString *text) {
    NSString *e = expert.length ? expert : @"core", *t = title.length ? title : @"Something Did Not Work";
    NSDictionary *body = @{@"expert": e, @"title": t, @"text": text ?: @""};
    MMLogWhenOpen(^(MMLog *log) { [log append:MMLogNoticeTable rid:nil expert:e subject:t state:@"notice" body:body]; });
    MMNotify(e, t, text ?: @"", nil);
}
