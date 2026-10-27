// Checks the Settings window's controls without drawing: each one calls its block with the right expert and value.
// Prints one line per check as name<TAB>want<TAB>got. Built with Sources/UI only, like the render tool.
#import <Cocoa/Cocoa.h>
#import "UI/MMSettings.h"

static void Out(NSString *name, NSString *want, NSString *got) { printf("%s\t%s\t%s\n", name.UTF8String, want.UTF8String, (got ?: @"nil").UTF8String); }

static NSArray *All(NSView *root, Class cls) {
    NSMutableArray *out = [NSMutableArray new], *todo = [NSMutableArray arrayWithObject:root];
    while (todo.count) {
        NSView *v = todo.firstObject; [todo removeObjectAtIndex:0];
        if ([v isKindOfClass:cls]) [out addObject:v];
        [todo addObjectsFromArray:v.subviews];
    }
    return out;
}

static id Find(NSView *root, Class cls, NSString *ident) {
    for (NSView *v in All(root, cls)) if ([v.identifier isEqualToString:ident]) return v;
    return nil;
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    MMSettings *s = [MMSettings new];
    MMSettingsExpert *lh = [MMSettingsExpert expert:@"locohost" name:@"LocoHost" symbol:@"server.rack"];
    lh.mode = @"eager";
    MMSettingsExpert *in = [MMSettingsExpert expert:@"insomnia" name:@"Insomnia" symbol:@"cup.and.saucer"];
    in.iconVisible = NO;
    s.experts = @[lh, in];
    NSMutableArray *calls = [NSMutableArray new];
    s.onIcon = ^(NSString *e, BOOL v) { [calls addObject:[NSString stringWithFormat:@"icon %@ %d", e, v]]; };
    s.onMode = ^(NSString *e, NSString *m) { [calls addObject:[NSString stringWithFormat:@"mode %@ %@", e, m]]; };
    s.onModel = ^(NSString *m) { [calls addObject:[@"model " stringByAppendingString:m]]; };
    s.onOneIcon = ^(BOOL on) { [calls addObject:[NSString stringWithFormat:@"one %d", on]]; };
    s.onOpenMenu = ^(NSString *e, NSView *v) { [calls addObject:[@"open " stringByAppendingString:e]]; };

    Out(@"settings: the default model is auto", @"auto", s.model);
    Out(@"settings: the models in order", @"auto,haiku,sonnet,opus,luna", [MMSettingsModels() componentsJoinedByString:@","]);
    Out(@"settings: the auto title says what it does", @"Auto: Haiku, Then Luna", MMSettingsModelTitle(@"auto"));
    Out(@"settings: the first pane is Overview", @"Overview", MMSettingsPaneTitle(0));

    NSView *experts = [s viewFor:MMSettingsExperts];
    NSButton *box = Find(experts, NSButton.class, @"insomnia");
    Out(@"settings: a hidden icon shows unchecked", @"0", [NSString stringWithFormat:@"%ld", (long)box.state]);
    [box performClick:nil];
    NSPopUpButton *mode = Find(experts, NSPopUpButton.class, @"locohost");
    Out(@"settings: the mode menu shows the saved mode", @"Eager", mode.titleOfSelectedItem);
    [mode selectItemAtIndex:0];
    [mode sendAction:mode.action to:mode.target];
    Out(@"settings: an expert with no mode has no mode menu", @"nil", Find(experts, NSPopUpButton.class, @"insomnia") ? @"menu" : @"nil");

    NSView *general = [s viewFor:MMSettingsGeneral];
    NSPopUpButton *model = All(general, NSPopUpButton.class).firstObject;
    [model selectItemAtIndex:1];
    [model sendAction:model.action to:model.target];
    for (NSButton *b in All(general, NSButton.class)) if ([b.title isEqualToString:@"Show One Icon"]) [b performClick:nil];

    NSView *overview = [s viewFor:MMSettingsOverview];
    NSButton *open = Find(overview, NSButton.class, @"locohost");
    [open performClick:nil];
    Out(@"settings: each control calls its block", @"icon insomnia 1|mode locohost idle|model haiku|one 1|open locohost", [calls componentsJoinedByString:@"|"]);
    Out(@"settings: the view keeps the new state", @"idle yes haiku", [NSString stringWithFormat:@"%@ %@ %@", lh.mode, in.iconVisible ? @"yes" : @"no", s.model]);

    MMSettings *bare = [MMSettings new];
    bare.experts = @[lh];
    NSButton *dim = Find([bare viewFor:MMSettingsExperts], NSButton.class, @"locohost");
    Out(@"settings: a control with no block is dimmed", @"no", dim.enabled ? @"yes" : @"no");
}}
