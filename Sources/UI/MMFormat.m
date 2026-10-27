#import "MMFormat.h"

NSString *MMBytes(uint64_t b) {
    const double K = 1024, M = K * K, G = M * K, T = G * K;
    // Each unit starts where the smaller one would round up to 1024, so "1024 MB" never shows.
    if (b >= T - G / 20) return [NSString stringWithFormat:@"%.1f TB", b / T];
    if (b >= G - M / 2) return [NSString stringWithFormat:@"%.1f GB", b / G];
    if (b >= M - K / 2) return [NSString stringWithFormat:@"%.0f MB", b / M];
    // Under a kilobyte rounds up, so something that holds bytes never reads as zero.
    return [NSString stringWithFormat:@"%.0f KB", ceil(b / K)];
}

NSString *MMDuration(NSTimeInterval s) {
    long t = (long)MAX(0, s);
    if (t < 60) return [NSString stringWithFormat:@"%lds", t];
    if (t < 3600) return [NSString stringWithFormat:@"%ldm", t / 60];
    if (t < 86400) return t % 3600 >= 60 ? [NSString stringWithFormat:@"%ldh %ldm", t / 3600, t % 3600 / 60] : [NSString stringWithFormat:@"%ldh", t / 3600];
    // Past a week the hours say nothing, so "13d" and not "13d 4h". This is WorkForest's rule; LocoHost kept the hours.
    return t % 86400 >= 3600 && t < 7 * 86400 ? [NSString stringWithFormat:@"%ldd %ldh", t / 86400, t % 86400 / 3600] : [NSString stringWithFormat:@"%ldd", t / 86400];
}

NSString *MMShortDuration(NSTimeInterval s) { return [MMDuration(s) componentsSeparatedByString:@" "].firstObject; }

NSString *MMAgo(NSDate *d) {
    if (!d) return @"";
    NSTimeInterval s = -d.timeIntervalSinceNow;
    return s < 60 ? @"now" : [MMShortDuration(s) stringByAppendingString:@" ago"];
}

NSString *MMPlural(NSInteger n, NSString *word) {
    if (n == 1 || !word.length) return [NSString stringWithFormat:@"%ld %@", (long)n, word ?: @""];
    NSString *w = word;
    NSString *last = [w substringFromIndex:w.length - 1];
    BOOL vowelBefore = w.length > 1 && [@"aeiou" containsString:[w substringWithRange:NSMakeRange(w.length - 2, 1)]];
    if ([last isEqualToString:@"y"] && !vowelBefore) w = [[w substringToIndex:w.length - 1] stringByAppendingString:@"ies"];
    else if ([w hasSuffix:@"s"] || [w hasSuffix:@"x"] || [w hasSuffix:@"ch"] || [w hasSuffix:@"sh"]) w = [w stringByAppendingString:@"es"];
    else w = [w stringByAppendingString:@"s"];
    return [NSString stringWithFormat:@"%ld %@", (long)n, w];
}

NSString *MMCut(NSString *s, NSUInteger n) {
    if (!s) return @"";
    if (s.length <= n || n == 0) return s;
    // Cut on a whole character, so an emoji or an accent is never split.
    NSString *head = [s substringToIndex:[s rangeOfComposedCharacterSequenceAtIndex:n - 1].location];
    return [[head stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByAppendingString:@"…"];
}

NSString *MMCapitalized(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length ? [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]] : @"";
}

NSString *MMSentence(NSString *s) {
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) return @"";
    s = [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]];
    return [s hasSuffix:@"."] || [s hasSuffix:@"?"] || [s hasSuffix:@"!"] || [s hasSuffix:@"…"] ? s : [s stringByAppendingString:@"."];
}
