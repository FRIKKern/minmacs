// `minmacs keep <port|path|cache name> [--days <n>]`: the keep a row's own menu gives, MMKeep by the expert's stable
// key, for a server, a worktree or a cache, so Ask MinMacs can name one verb for every keep it offers. A keep changes
// what the modes may stop or remove, so it runs through the app, as remove and restore do. --days 0 ends a keep.
#import "Shell/MMAsk.h"
#import "Shell/MMWindowFeed.h"
#import "Core/MMCore.h"
#import "CLI/MMCLI.h"

static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

MMFinding *MMKeepFind(MMSnapshot *s, NSString *arg) {
    NSString *a = [arg hasPrefix:@":"] ? [arg substringFromIndex:1] : arg;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    BOOL port = a.length && [a rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound;
    BOOL path = [arg hasPrefix:@"/"] || [arg hasPrefix:@"~"] || [arg hasPrefix:@"."];
    NSString *full = path ? [arg.stringByExpandingTildeInPath stringByStandardizingPath] : nil;
    for (MMFinding *f in s.findings) {
        if (!MMAskTargetOf(f)) continue;
        if (port) { if ([f.expert isEqualToString:@"locohost"] && [f.facts[@"port"] isKindOfClass:NSNumber.class] && [f.facts[@"port"] integerValue] == a.integerValue) return f; continue; }
        if (path) { if (f.path.length && [f.path.stringByStandardizingPath isEqualToString:full]) return f; continue; }
        // A cache by the name the window shows, as its tool names it, in any case.
        if ([f.expert isEqualToString:@"noonoo"] && ([MMWindowNameOf(f) caseInsensitiveCompare:arg] == NSOrderedSame || [Str(f.title) caseInsensitiveCompare:arg] == NSOrderedSame)) return f;
    }
    return nil;
}

static int KeepVerb(MMArgs *a) {
    if (a.words.count != 1) return [a usageError];
    NSString *daysOpt = [a option:@"--days"];
    if ([a has:@"--days"] && (!daysOpt.length || daysOpt.doubleValue < 0)) { [a error:@"--days takes a number from 0"]; return [a usageError]; }
    MMFinding *f = MMKeepFind(a.snapshot, a.words.firstObject);
    MMAskTarget *t = MMAskTargetOf(f);
    if (!t) { [a error:@"no server, worktree or cache is %@", a.words.firstObject]; return MMExitFailed; }
    NSTimeInterval span = daysOpt ? daysOpt.doubleValue * 86400 : MMAskKeepFor(t.expert);
    NSDate *until = span > 0 ? [NSDate dateWithTimeIntervalSinceNow:span] : nil;
    NSDictionary *j = @{@"expert": t.expert, @"key": t.stableKey, @"name": t.name, @"until": until ? @(until.timeIntervalSince1970) : NSNull.null, @"dryRun": @(a.dryRun)};
    if (!a.dryRun) {
        int needs = [a needsApp];
        if (needs) return needs;
        [MMKeep keep:t.stableKey expert:t.expert until:until by:@"cli" name:t.name];
        [MMGraph.shared rebuild:@"cli keep"];
    }
    if (a.json) { [a printJSON:j]; return 0; }
    NSString *how = until ? [NSString stringWithFormat:@"no rule acts on %@ for %@", t.name, span < 86400 ? [NSString stringWithFormat:@"%g hours", span / 3600] : [NSString stringWithFormat:@"%g days", span / 86400]]
                          : [NSString stringWithFormat:@"%@ is no longer kept", t.name];
    [a print:@"%@%@", a.dryRun ? @"would keep: " : @"", how];
    return 0;
}

MMVerbSpec *MMKeepVerbSpec(void) {
    MMVerbSpec *v = [MMVerbSpec verb:@"keep" usage:@"keep <port|path|cache name> [--days <n>] [--json] [--dry-run]   keep a server, worktree or cache from every rule for a while: 4 hours for a server and 7 days for the rest unless --days says, 0 ends it"
                             mutates:YES run:^int(MMArgs *a) { return KeepVerb(a); }];
    v.reads = MMVerbReadsCachedGit;
    return v;
}
