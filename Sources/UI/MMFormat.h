// Words and numbers for every expert: one set of formatters for bytes, durations, plurals and cuts (A16, P60).
// Menus, cards, notifications and the CLI all use these, so a size or a time reads the same everywhere.
#import <Foundation/Foundation.h>

/// "905 MB", "1.2 GB", "12 KB", "1.1 TB". Binary units, as du and LocoHost and WorkForest use.
/// Finder counts in thousands, so its figures read about 7 percent higher. Thread safe, like every formatter here.
NSString *MMBytes(uint64_t bytes);
/// "45s", "12m", "3h 4m", "5d 2h", "13d". The second part is left out when it is zero or the time is a week or more.
NSString *MMDuration(NSTimeInterval seconds);
/// The first part of a duration: "5d" from "5d 17h". For rows and gray tails.
NSString *MMShortDuration(NSTimeInterval seconds);
/// "9m ago" for a date in the past, "now" under a minute, empty for nil.
NSString *MMAgo(NSDate *date);
/// "1 server", "2 servers", "3 processes", "2 entries". One rule for every expert.
NSString *MMPlural(NSInteger n, NSString *word);
/// The text cut at the tail with an ellipsis, at most n characters. Never cuts in the middle.
NSString *MMCut(NSString *s, NSUInteger n);
/// The text with a capital first letter and nothing else changed. For titles.
NSString *MMCapitalized(NSString *s);
/// The text with a capital first letter and a final period, unless it already ends in . ? or !.
NSString *MMSentence(NSString *s);
