#import "CLI/MMArgs.h"
#import "CLI/MMCLI.h"
#include <stdio.h>

@interface MMArgs ()
@property (readwrite, copy) NSString *verb, *usage;
@property (readwrite, copy) NSArray<NSString *> *all, *words;
@property (strong) NSMutableDictionary<NSString *, NSString *> *values;
@property (strong) NSMutableSet<NSString *> *flags;
@property (strong) MMSnapshot *cachedSnapshot;
@end

/// The flags in a usage line that take a value: "--port <n>" names --port.
static NSSet<NSString *> *ValueFlags(NSString *usage) {
    NSMutableSet *s = [NSMutableSet new];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(--[A-Za-z0-9-]+)[ =]<" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:usage ?: @"" options:0 range:NSMakeRange(0, usage.length)])
        [s addObject:[usage substringWithRange:[m rangeAtIndex:1]]];
    return s;
}

@implementation MMArgs

+ (instancetype)verb:(NSString *)verb words:(NSArray<NSString *> *)words usage:(NSString *)usage {
    MMArgs *a = [self new];
    a.verb = verb; a.usage = usage ?: verb; a.all = words ?: @[];
    a.values = [NSMutableDictionary new]; a.flags = [NSMutableSet new];
    a.program = @"minmacs";
    a.cwd = NSFileManager.defaultManager.currentDirectoryPath;
    NSSet *takes = ValueFlags(usage);
    NSMutableArray *plain = [NSMutableArray new];
    BOOL rest = NO;
    for (NSUInteger i = 0; i < a.all.count; i++) {
        NSString *w = a.all[i];
        if (rest || ![w hasPrefix:@"--"] || w.length == 2) {
            if ([w isEqualToString:@"--"] && !rest) { rest = YES; continue; }
            [plain addObject:w]; continue;
        }
        NSRange eq = [w rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *flag = [w substringToIndex:eq.location];
            a.values[flag] = [w substringFromIndex:eq.location + 1];
            [a.flags addObject:flag];
        } else if ([takes containsObject:w] && i + 1 < a.all.count) {
            a.values[w] = a.all[++i];
            [a.flags addObject:w];
        } else {
            [a.flags addObject:w];
        }
    }
    a.words = plain;
    return a;
}

- (BOOL)json { return [self.flags containsObject:@"--json"]; }
- (BOOL)dryRun { return [self.flags containsObject:@"--dry-run"]; }
- (NSString *)word:(NSUInteger)i { return i < self.words.count ? self.words[i] : nil; }
- (BOOL)has:(NSString *)flag { return [self.flags containsObject:flag]; }
- (NSString *)option:(NSString *)flag { return self.values[flag]; }

- (MMSnapshot *)snapshot {
    @synchronized (self) {
        if (!self.cachedSnapshot) self.cachedSnapshot = MMCLISnapshot(self.inApp);
        return self.cachedSnapshot;
    }
}

- (void)write:(NSString *)line error:(BOOL)err {
    NSString *s = [line stringByAppendingString:@"\n"];
    NSMutableString *buf = err ? self.errBuffer : self.outBuffer;
    if (buf) { @synchronized (buf) { [buf appendString:s]; } return; }
    fputs(s.UTF8String, err ? stderr : stdout);
}

- (void)print:(NSString *)format, ... {
    va_list ap; va_start(ap, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    [self write:s error:NO];
}

- (void)error:(NSString *)format, ... {
    va_list ap; va_start(ap, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    [self write:s error:YES];
}

- (void)printJSON:(id)value {
    id v = MMJSONSafe(value);
    NSData *d = [NSJSONSerialization dataWithJSONObject:v
                                                options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                  error:nil];
    [self write:d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null" error:NO];
}

- (int)usageError {
    // A usage line may carry a short description after three spaces. The error shows the syntax alone.
    NSString *syntax = [self.usage componentsSeparatedByString:@"   "].firstObject;
    [self error:@"usage: %@ %@", self.program ?: @"minmacs", syntax];
    return MMExitUsage;
}

- (int)needsApp {
    if (self.inApp) return MMExitOK;
    [self error:@"MinMacs is not running, so %@ cannot change anything. Open MinMacs, or add --dry-run to see what it would do.", self.verb];
    return MMExitNeedsApp;
}

@end
