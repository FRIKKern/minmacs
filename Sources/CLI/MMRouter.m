#import "CLI/MMRouter.h"
#import "CLI/MMCLI.h"

@interface MMRoute ()
@property (readwrite) MMRouteKind kind;
@property (readwrite, copy) NSString *expert;
@property (readwrite) NSURL *url;
@property (readwrite, copy) NSArray<NSString *> *words;
@end
@implementation MMRoute
@end

NSArray<NSString *> *MMURLSchemes(void) { return @[@"minmacs", @"locohost"]; }

static MMRoute *Route(MMRouteKind kind, NSString *expert, NSURL *url, NSArray *words) {
    MMRoute *r = [MMRoute new];
    r.kind = kind; r.expert = expert; r.url = url; r.words = words;
    return r;
}

MMRoute *MMRouteURL(NSURL *url, NSDictionary<NSString *, NSString *> *legacyNames) {
    NSDictionary *names = legacyNames ?: MMLegacyNames();
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *cmd = url.host.lowercaseString ?: @"";
    NSArray *path = [url.path.lowercaseString componentsSeparatedByString:@"/"];
    path = [path filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (![scheme isEqualToString:@"minmacs"] && !names[scheme]) return Route(MMRouteNone, nil, url, nil);

    // The router owns these for every scheme, so no expert ever quits the app or changes the login item.
    if ([cmd isEqualToString:@"quit"]) return Route(MMRouteQuit, nil, url, nil);
    if ([cmd isEqualToString:@"login-on"]) return Route(MMRouteLoginOn, nil, url, nil);
    if ([cmd isEqualToString:@"login-off"]) return Route(MMRouteLoginOff, nil, url, nil);
    if ([cmd isEqualToString:@"settings"] || (!cmd.length && [scheme isEqualToString:@"minmacs"])) return Route(MMRouteSettings, nil, url, nil);

    NSString *expert = names[scheme];
    NSString *legacy = scheme;
    if ([scheme isEqualToString:@"minmacs"]) {
        // minmacs://locohost/review names the expert first.
        NSString *named = nil;
        for (NSString *k in names) if ([k isEqualToString:cmd] || [names[k] isEqualToString:cmd]) { named = names[k]; legacy = k; }
        if (named) {
            expert = named;
            cmd = path.firstObject ?: @"";
            if ([@[@"quit", @"login-on", @"login-off", @"settings"] containsObject:cmd]) return MMRouteURL([NSURL URLWithString:[@"minmacs://" stringByAppendingString:cmd]], names);
        } else expert = @"minmacs";
    }
    NSURLComponents *c = [NSURLComponents new];
    c.scheme = legacy; c.host = cmd;
    c.query = url.query;
    NSURL *own = c.URL ?: url;
    // The CLI words that do the same, when the expert has no -openURL: for it.
    NSArray *words = nil;
    if ([cmd isEqualToString:@"review"]) words = @[@"review", expert, @"--now"];
    else if ([cmd isEqualToString:@"restore"]) words = @[@"restore", @"--expert", expert];
    else if ([cmd isEqualToString:@"run-now"]) words = @[@"tidy", expert];
    return Route(cmd.length ? MMRouteExpert : MMRouteSettings, expert, own, words);
}
