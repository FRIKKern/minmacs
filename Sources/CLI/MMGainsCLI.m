// `minmacs gains`: the kept log of what came back, MMGains.h, as totals by day, by kind and by who did it.
// It reads the gains table only. It samples nothing and changes nothing but dropping rows past 30 days and
// settling rows whose items left the Trash, as every read of the table does.
#import "CLI/MMCLI.h"
#import "Core/Store/MMGains.h"

static NSString *Bytes(id n) {
    static NSByteCountFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSByteCountFormatter new]; f.countStyle = NSByteCountFormatterCountStyleMemory; f.allowsNonnumericFormatting = NO; });
    return [f stringFromByteCount:[n longLongValue]];
}
static NSString *Pad(NSString *s, NSUInteger n) {
    s = s ?: @"";
    return s.length >= n ? [s stringByAppendingString:@" "] : [s stringByPaddingToLength:n withString:@" " startingAtIndex:0];
}
static NSString *Line(NSString *label, NSDictionary *t) {
    NSInteger n = [t[@"actions"] integerValue];
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@%@ memory, %@ disk, %ld action%@", Pad(label, 13),
                          Bytes(t[@"memoryBack"]), Bytes(t[@"diskBack"]), (long)n, n == 1 ? @"" : @"s"];
    if ([t[@"diskInTrash"] longLongValue] > 0) [s appendFormat:@", %@ still in the Trash", Bytes(t[@"diskInTrash"])];
    return s;
}

int MMGainsVerb(MMArgs *a) {
    NSInteger days = 7;
    NSString *d = [a option:@"--days"];
    if (d) {
        NSScanner *sc = [NSScanner scannerWithString:d];
        NSInteger n = 0;
        if (![sc scanInteger:&n] || !sc.isAtEnd || n < 1 || n > MMGainsKeepDays) {
            [a error:@"--days takes a whole number from 1 to %ld", (long)MMGainsKeepDays];
            return [a usageError];
        }
        days = n;
    }
    if (a.words.count) return [a usageError];
    NSDictionary *j = [MMGains.shared summary:days now:NSDate.date];
    if (a.json) { [a printJSON:j]; return 0; }
    [a print:@"What came back. Memory and disk are two numbers and are never added together."];
    [a print:@"%@", Line(@"Today", j[@"today"])];
    [a print:@"%@", Line([NSString stringWithFormat:@"%ld days", (long)days], j[@"total"])];
    if (days > 1) {
        [a print:@""];
        [a print:@"%@%@%@%@", Pad(@"Day", 13), Pad(@"Memory", 12), Pad(@"Disk", 12), @"Actions"];
        for (NSDictionary *x in j[@"byDay"])
            [a print:@"%@%@%@%@", Pad(x[@"day"], 13), Pad(Bytes(x[@"memoryBack"]), 12), Pad(Bytes(x[@"diskBack"]), 12), x[@"actions"]];
    }
    NSDictionary *kinds = j[@"byKind"], *who = j[@"byWho"];
    NSMutableArray *k = [NSMutableArray new];
    for (NSString *name in [kinds.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if ([kinds[name][@"actions"] integerValue]) [k addObject:name];
    if (k.count) {
        [a print:@""];
        [a print:@"By kind"];
        for (NSString *name in k) [a print:@"  %@", Line(name, kinds[name])];
    }
    NSMutableArray *w = [NSMutableArray new];
    for (NSString *name in @[MMGainByYou, MMGainByAuto, MMGainByRun]) if ([who[name][@"actions"] integerValue]) [w addObject:name];
    if (w.count) {
        [a print:@""];
        [a print:@"By who did it"];
        for (NSString *name in w) [a print:@"  %@", Line(name, who[name])];
    }
    if (![j[@"total"][@"actions"] integerValue]) [a print:@"Nothing came back in these days."];
    return 0;
}
