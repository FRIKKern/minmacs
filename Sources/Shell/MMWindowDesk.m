// The app's desk for the window's row menus, MMWindowActs.h: the items that only show or copy. Main thread only.
// The shell hands it to MMWindowController. No check makes one: a check passes its own fake.
#import <Cocoa/Cocoa.h>
#import "Shell/MMWindowActs.h"

@interface MMWindowAppDesk : NSObject <MMWindowDesk>
@end

@implementation MMWindowAppDesk

/// The running app at pid, never MinMacs itself.
static NSRunningApplication *AppAt(pid_t pid) {
    if (pid <= 1 || pid == getpid()) return nil;
    return [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
}

- (void)showApp:(pid_t)pid {
    NSRunningApplication *a = AppAt(pid);
    if (a.hidden) [a unhide];
    [a activateWithOptions:NSApplicationActivateAllWindows];
}

- (void)hideApp:(pid_t)pid { [AppAt(pid) hide]; }

- (void)reveal:(NSString *)path { [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]]; }

- (void)openFolder:(NSString *)path { [NSWorkspace.sharedWorkspace selectFile:nil inFileViewerRootedAtPath:path]; }

/// As the worktree card of before opens it: Terminal, with the folder as where its shell starts.
- (void)openInTerminal:(NSString *)path {
    NSURL *term = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (term) [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:path]] withApplicationAtURL:term
                                     configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
}

/// Only a web address: a row's URL or pull request is never a file or a scheme that runs something.
- (void)openURL:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    if ([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"]) [NSWorkspace.sharedWorkspace openURL:u];
}

- (void)copyText:(NSString *)text {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}

@end

id<MMWindowDesk> MMWindowRealDesk(void) {
    static MMWindowAppDesk *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [MMWindowAppDesk new]; });
    return d;
}
