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

NSString *MMNoticeLines(NSArray<NSArray<NSString *> *> *failures) {
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *by = [NSMutableDictionary new];
    for (NSArray<NSString *> *x in failures) {
        if (x.count < 2) continue;
        NSString *why = x[1].length ? x[1] : @"it failed";
        if (!by[why]) { by[why] = [NSMutableArray new]; [order addObject:why]; }
        [by[why] addObject:x[0].length ? x[0] : @"something"];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *why in order) {
        NSArray<NSString *> *names = by[why];
        NSString *who;
        if (names.count == 1) who = names[0];
        else if (names.count <= 3) who = [[[names subarrayWithRange:NSMakeRange(0, names.count - 1)] componentsJoinedByString:@", "] stringByAppendingFormat:@" and %@", names.lastObject];
        else who = [[[names subarrayWithRange:NSMakeRange(0, 2)] componentsJoinedByString:@", "] stringByAppendingFormat:@" and %lu more", (unsigned long)(names.count - 2)];
        [lines addObject:[NSString stringWithFormat:@"%@: %@", who, why]];
    }
    return [lines componentsJoinedByString:@"\n"];
}
