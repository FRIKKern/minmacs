// Weak stand-ins for the few Store and Senses functions Act calls.
// Phase 1 builds Store and Senses in parallel with Act, so Act must link without them.
// Each function here is a weak definition. When the Store or Senses file with the real one is linked,
// the linker takes that one and drops this one, with no error. Delete this file once both have landed.
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import "Core/Store/MMStore.h"
#import "Core/Senses/MMSenses.h"

static NSString *MakeDir(NSString *dir) {
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

__attribute__((weak)) NSString *MMSupportDir(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    if (home.length) return MakeDir(home);
    return MakeDir([NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"]);
}

__attribute__((weak)) NSString *MMExpertDir(NSString *expert) {
    return MakeDir([MMSupportDir() stringByAppendingPathComponent:expert]);
}

// With MINMACS_HOME set, prefs live in a plist inside it, so a test never writes the person's prefs domain.
static NSString *TestPrefsPath(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    return home.length ? [home stringByAppendingPathComponent:@"prefs.plist"] : nil;
}

__attribute__((weak)) id MMPref(NSString *key) {
    NSString *path = TestPrefsPath();
    if (path) @synchronized (NSFileManager.class) { return [NSDictionary dictionaryWithContentsOfFile:path][key]; }
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("no.guerrilla.minmacs")));
}

__attribute__((weak)) void MMSetPref(NSString *key, id value) {
    NSString *path = TestPrefsPath();
    if (path) {
        @synchronized (NSFileManager.class) {
            NSMutableDictionary *all = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary new];
            if (value) all[key] = value; else [all removeObjectForKey:key];
            [all writeToFile:path atomically:YES];
        }
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR("no.guerrilla.minmacs"));
    CFPreferencesAppSynchronize(CFSTR("no.guerrilla.minmacs"));
}

// A zombie counts as gone: it has exited and only waits for its parent to read its status.
__attribute__((weak)) BOOL MMProcAlive(MMProcKey key) {
    if (key.pid <= 0) return NO;
    struct kinfo_proc kp;
    size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, key.pid };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return NO;
    if (kp.kp_proc.p_stat == SZOMB) return NO;
    return (uint64_t)kp.kp_proc.p_starttime.tv_sec == key.startSec;
}

__attribute__((weak)) NSString *MMProcKeyString(MMProcKey key) {
    return [NSString stringWithFormat:@"%d:%llu", key.pid, key.startSec];
}
