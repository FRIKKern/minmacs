// The arguments of one CLI verb, and where its output goes. Pattern P61.
// A verb prints through these methods only, never with printf. The same verb then runs in the CLI process,
// or in the app when the CLI hands it over core.sock, and its output reaches the person's terminal either way.
#import <Foundation/Foundation.h>

@class MMSnapshot;

/// Exit statuses every verb shares.
enum {
    MMExitOK = 0,
    MMExitFailed = 1,        // the verb ran and something did not work, or nothing matched
    MMExitUsage = 2,         // an unknown verb, a missing argument or a bad value
    MMExitNeedsApp = 3,      // the verb changes things, and no MinMacs app answers on core.sock
};

@interface MMArgs : NSObject
/// Parses words, the arguments after the verb. usage names the flags that take a value, such as "--port <n>".
/// Every verb takes --json and --dry-run.
+ (instancetype)verb:(NSString *)verb words:(NSArray<NSString *> *)words usage:(NSString *)usage;

@property (readonly, copy) NSString *verb;               // "hosts"
@property (readonly, copy) NSString *usage;              // "hosts [port] [--json]"
@property (readonly, copy) NSArray<NSString *> *all;     // every word after the verb, as given
@property (readonly, copy) NSArray<NSString *> *words;   // the words that are not flags or flag values
@property (readonly) BOOL json, dryRun;
/// The name the binary ran under: "minmacs", or a legacy name such as "locohost".
@property (copy) NSString *program;
/// The folder the person ran the CLI in. In the app this is the CLI's folder, not the app's.
@property (copy) NSString *cwd;
/// YES when the verb runs inside the app, handed over core.sock.
@property BOOL inApp;

/// The word at i, or nil.
- (NSString *)word:(NSUInteger)i;
/// YES when the flag is given, such as "--here".
- (BOOL)has:(NSString *)flag;
/// The value of a flag given as "--port 3000" or "--port=3000", or nil.
- (NSString *)option:(NSString *)flag;

/// The snapshot the verb reads. In the app, the current one. In the CLI, one built cold, once per run.
@property (readonly) MMSnapshot *snapshot;
/// The same, for a verb that reports CPU or new connections. In the CLI it is built from a second sample taken
/// a second after the first, which every expert saw, so those count. In the app it is the current one.
@property (readonly) MMSnapshot *settledSnapshot;

/// One line to standard output.
- (void)print:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
/// One line to standard error.
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
/// A JSON value to standard output, pretty printed with sorted keys.
- (void)printJSON:(id)value;
/// Prints "usage: minmacs <usage>" to standard error and returns MMExitUsage.
- (int)usageError;
/// For a verb whose change must run in the app. Returns 0 inside the app. Outside it says so on standard error
/// and returns MMExitNeedsApp, so the verb returns that status.
- (int)needsApp;

/// When set, output collects here instead of going to the terminal. The app sets these for a handed-over verb.
@property (strong) NSMutableString *outBuffer, *errBuffer;
@end
