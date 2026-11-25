// Ask MinMacs in the whole window, MMWindowParts.h: the field's question and the answer's presses go to the host, a
// new answer that names a row makes it the active one, and Escape and typed keys find the field. Nothing here acts.
#import "UI/Window/MMWindowViewParts.h"

@implementation MMWindowView (Ask)

- (void)wireAsk {
    __weak typeof(self) me = self;
    MMWindowAskBar *bar = _middle.askBar;
    MMWindowAnswerView *answer = _middle.answerView;
    bar.onAsk = ^(NSString *q) { [me ask:q]; };
    bar.onEscape = ^{ [me escape]; };
    answer.onAsk = ^(NSString *q) { [me ask:q]; };
    answer.onBack = ^{ [me putAnswerAway]; };
    answer.onRow = ^(NSString *key) { [me showRow:key]; };
    answer.onLog = ^(NSString *key) { [me showLogEntry:key]; };
    answer.onSuggest = ^(MMWindowSuggest *s) { [me pressSuggest:s]; };
}

- (void)ask:(NSString *)question {
    if (_quiet || _flips > 0) return;
    id<MMWindowHost> h = self.host;
    // "keep this" means the row whose story shows now, the one under the pointer or the active one.
    if ([h respondsToSelector:@selector(windowAsk:row:)]) [h windowAsk:question row:_hovered ?: _active];
}

/// Only a person's press on the answer's own button acts, through the host: the keep or the restore of the window.
- (void)pressSuggest:(MMWindowSuggest *)s {
    if (_quiet || _flips > 0 || s.note.length) return;
    id<MMWindowHost> h = self.host;
    if ([s.action isEqualToString:@"undo"]) [h windowUndo:s.target];
    else if ([s.action isEqualToString:@"keep"] && [h respondsToSelector:@selector(windowKeep:)]) [h windowKeep:s.target];
    else if ([s.action isEqualToString:@"stop"] && [h respondsToSelector:@selector(windowAskStop)]) [h windowAskStop];
}

- (void)putAnswerAway {
    MMWindowAnswer *a = self.model.answer;
    if (!a) return;
    _middle.putAway = a.serial;
    [_middle showAnswer];
    id<MMWindowHost> h = self.host;
    if ([h respondsToSelector:@selector(windowAskBack)]) [h windowAskBack];
}

/// The log back, with this entry at its top.
- (void)showLogEntry:(NSString *)key {
    [self putAnswerAway];
    MMWindowLogView *log = _middle.logView;
    NSArray<MMWindowLogEntry *> *entries = log.log.entries;
    for (NSInteger i = 0; i < (NSInteger)entries.count; i++) if ([entries[(NSUInteger)i].key isEqualToString:key]) { log.first = i; break; }
}

- (void)takeAnswer {
    MMWindowAnswer *a = self.model.answer;
    if (!a || a.serial <= _answerSeen) return;
    _answerSeen = a.serial;
    // A new answer is read where the log was, even after an older one was put away.
    if (_middle.putAway == a.serial) _middle.putAway = 0;
    // An answer is no row's story: the person just asked for it, so an active row lets go and the answer shows, and
    // the hover rule's way back is to the answer, not to that row. A row under the pointer still peeks over it. An
    // answer about a row makes that row the active one instead, since its story is the answer.
    if (a.row.length && [self.model row:a.row]) { [self showRow:a.row]; return; }
    _hovered = nil;
    self.activeRow = nil;
    [_middle showAnswer];
}

- (BOOL)escapeAsk {
    if (!_middle.showsAnswer) return NO;
    [self putAnswerAway];
    return YES;
}

- (BOOL)typeIntoAsk:(NSEvent *)e {
    if (_quiet || !self.model || self.showsWelcome || self.showsSettings || _middle.askBar.focused) return NO;
    NSEventModifierFlags flags = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagShift | NSEventModifierFlagCapsLock);
    if (flags) return NO;
    // Return, Tab, Space, Delete, Escape and the arrows keep their own work.
    unsigned short code = e.keyCode;
    if (code == 36 || code == 48 || code == 49 || code == 51 || code == 53 || code == 76 || code == 117 || (code >= 123 && code <= 126)) return NO;
    NSString *typed = e.characters;
    if (!typed.length || [typed characterAtIndex:0] < 0x20 || ([typed characterAtIndex:0] >= 0xF700 && [typed characterAtIndex:0] <= 0xF8FF)) return NO;
    [_middle.askBar typeKey:e];
    return YES;
}

- (BOOL)editKey:(NSEvent *)e {
    if (![self.window.firstResponder isKindOfClass:NSText.class]) return NO;
    NSString *key = e.charactersIgnoringModifiers.lowercaseString;
    SEL action = [key isEqualToString:@"x"] ? @selector(cut:) : [key isEqualToString:@"c"] ? @selector(copy:) : [key isEqualToString:@"v"] ? @selector(paste:)
               : [key isEqualToString:@"a"] ? @selector(selectAll:) : [key isEqualToString:@"z"] ? @selector(undo:) : NULL;
    return action && [NSApp sendAction:action to:nil from:self];
}

- (void)restAsk { [_middle.askBar rest]; _middle.putAway = 0; }

@end
