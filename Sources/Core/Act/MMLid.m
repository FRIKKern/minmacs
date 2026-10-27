// The lid override of P54: the commands Insomnia runs for `pmset -a disablesleep`, ported from IN main.m:675-711.
// The rule file and the two commands it allows are the same as Insomnia's, so a Mac that has the rule keeps it.
// Nothing here reads the override. MMPower.lidOverride reads it from IOKit.
#import "Core/Act/MMAct.h"
#import "Core/Know/MMGit.h"
#include <fcntl.h>
#include <spawn.h>
#include <unistd.h>

extern char **environ;

static NSString *const kRuleFile = @"/etc/sudoers.d/insomnia";
static const NSTimeInterval kCommandLimit = 10;     // sudo and pmset answer in well under a second
static const NSTimeInterval kPromptLimit = 120;     // the administrator prompt waits for the person

static NSDictionary<NSString *, NSString *> *Env(void) { return NSProcessInfo.processInfo.environment; }

/// The fake a test names, only inside a test home. A real run never reads it.
static NSString *Fake(void) {
    if (!Env()[@"MINMACS_HOME"].length) return nil;
    NSString *f = Env()[@"MINMACS_INSOMNIA_CMD"];
    return f.length ? f : nil;
}

@implementation MMLidOverride

+ (NSString *)unavailableReason {
    if (Env()[@"MINMACS_HOME"].length && !Fake()) return @"a test home never changes power settings";
    return nil;
}

/// Runs cmd, the real program first, or the fake with cmd as its arguments. NO on main, past the limit or on a non-zero exit.
static BOOL Run(NSArray<NSString *> *cmd, NSTimeInterval limit, NSString **error) {
    NSString *problem = nil;
    if (NSThread.isMainThread) problem = @"it never runs on the main thread";
    else problem = [MMLidOverride unavailableReason];
    if (problem) { if (error) *error = problem; return NO; }
    NSString *fake = Fake();
    NSString *path = fake ?: cmd.firstObject;
    NSArray *args = fake ? cmd : [cmd subarrayWithRange:NSMakeRange(1, cmd.count - 1)];
    NSDictionary *env = fake ? @{@"MINMACS_HOME": Env()[@"MINMACS_HOME"]} : nil;
    NSData *err = nil;
    MMRunResult r = MMRun(path, args, nil, env, nil, limit, NULL, &err);
    if (r.didRun && !r.timedOut && r.status == 0) return YES;
    if (error) {
        NSString *said = [[[NSString alloc] initWithData:err ?: [NSData data] encoding:NSUTF8StringEncoding]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        *error = !r.didRun ? [NSString stringWithFormat:@"%@ did not start", path.lastPathComponent]
               : r.timedOut ? [NSString stringWithFormat:@"%@ did not answer in time", [cmd[0] lastPathComponent]]
               : said.length ? said : [NSString stringWithFormat:@"%@ exited with status %d", [cmd[0] lastPathComponent], r.status];
    }
    return NO;
}

+ (BOOL)set:(BOOL)on error:(NSString **)error {
    return Run(@[@"/usr/bin/sudo", @"-n", @"/usr/bin/pmset", @"-a", @"disablesleep", on ? @"1" : @"0"], kCommandLimit, error);
}

+ (BOOL)ruleInstalled {
    return Run(@[@"/usr/bin/sudo", @"-n", @"-l", @"/usr/bin/pmset", @"-a", @"disablesleep", @"1"], kCommandLimit, NULL);
}

+ (BOOL)installRule:(NSString **)error {
    NSString *rule = [NSString stringWithFormat:
        @"%@ ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0", NSUserName()];
    NSString *sh = [NSString stringWithFormat:
        @"printf '%%s\\n' '%@' > %@ && chmod 0440 %@ && visudo -cf %@ || { rm -f %@; exit 1; }",
        rule, kRuleFile, kRuleFile, kRuleFile, kRuleFile];
    NSString *script = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",
        [sh stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    if (!Run(@[@"/usr/bin/osascript", @"-e", script], kPromptLimit, error)) return NO;
    if ([self ruleInstalled]) return YES;
    if (error) *error = @"the rule did not take effect";
    return NO;
}

+ (BOOL)sleepDisplay {
    return Run(@[@"/usr/bin/pmset", @"displaysleepnow"], kCommandLimit, NULL);
}

+ (void)clearWithoutWaiting {
    if ([self unavailableReason]) return;
    NSString *fake = Fake();
    NSArray<NSString *> *cmd = @[@"/usr/bin/sudo", @"-n", @"/usr/bin/pmset", @"-a", @"disablesleep", @"0"];
    NSArray<NSString *> *argv = fake ? [@[fake] arrayByAddingObjectsFromArray:cmd] : cmd;
    char **cargv = calloc(argv.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argv.count; i++) cargv[i] = (char *)argv[i].fileSystemRepresentation;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&fa, fd, "/dev/null", fd ? O_WRONLY : O_RDONLY, 0);
    pid_t pid = 0;
    posix_spawn(&pid, cargv[0], &fa, NULL, cargv, environ);
    posix_spawn_file_actions_destroy(&fa);
    free(cargv);
}

@end
