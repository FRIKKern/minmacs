// The model call of the review broker, patterns P39, P40 and P42.
// Ported from WorkForest's Review.m, which LocoHost's Review.m shares line for line, with three changes:
// every call gets its own temp folder, the usage is split as the CLI reports it, and the input is compacted.
#import "Core/Review/MMReview.h"
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static const NSTimeInterval kTimeout = 240;

/// <support folder>/review, made on first use. The support folder is $MINMACS_HOME when it is set,
/// as MMSupportDir in Store says. Store lands on its own branch, so the broker finds the folder itself.
NSString *MMReviewDir(void) {
    NSString *env = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
    NSString *base = env.length ? env : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MinMacs"];
    NSString *dir = [base stringByAppendingPathComponent:@"review"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

#pragma mark - Usage

@interface MMUsage ()
@property (readwrite) NSInteger input, cacheWrite5m, cacheWrite1h, cacheRead, output, thinking;
@property (readwrite) double listCostUSD, seconds;
@property (readwrite, copy) NSString *model;
@end

@implementation MMUsage

- (NSInteger)uncached { return self.input + self.cacheWrite5m + self.cacheWrite1h + self.output; }

- (NSDictionary *)json {
    return @{@"model": self.model ?: @"", @"input": @(self.input), @"cache_write_5m": @(self.cacheWrite5m),
             @"cache_write_1h": @(self.cacheWrite1h), @"cache_read": @(self.cacheRead), @"output": @(self.output),
             @"thinking": @(self.thinking), @"uncached": @(self.uncached), @"list_cost_usd": @(self.listCostUSD),
             @"seconds": @(self.seconds)};
}

+ (instancetype)fromJSON:(NSDictionary *)j {
    if (![j isKindOfClass:NSDictionary.class]) return nil;
    MMUsage *u = [MMUsage new];
    u.model = [j[@"model"] isKindOfClass:NSString.class] ? j[@"model"] : nil;
    u.input = [j[@"input"] integerValue]; u.cacheWrite5m = [j[@"cache_write_5m"] integerValue];
    u.cacheWrite1h = [j[@"cache_write_1h"] integerValue]; u.cacheRead = [j[@"cache_read"] integerValue];
    u.output = [j[@"output"] integerValue]; u.thinking = [j[@"thinking"] integerValue];
    u.listCostUSD = [j[@"list_cost_usd"] doubleValue]; u.seconds = [j[@"seconds"] doubleValue];
    return u;
}

/// The sum of two calls. The model is the second one's when it has one.
- (MMUsage *)adding:(MMUsage *)o {
    if (!o) return self;
    MMUsage *u = [MMUsage new];
    u.input = self.input + o.input; u.cacheWrite5m = self.cacheWrite5m + o.cacheWrite5m;
    u.cacheWrite1h = self.cacheWrite1h + o.cacheWrite1h; u.cacheRead = self.cacheRead + o.cacheRead;
    u.output = self.output + o.output; u.thinking = self.thinking + o.thinking;
    u.listCostUSD = self.listCostUSD + o.listCostUSD; u.seconds = self.seconds + o.seconds;
    u.model = o.model.length ? o.model : self.model;
    return u;
}

/// The usage in `claude -p --output-format json`. Cache writes are split by TTL when the CLI says how.
/// A write it does not split goes to the TTL the call asked for, and to one hour when it asked for none,
/// since Claude Code asks for one hour on a subscription. Research F, sections 1.2 and 2.1.
+ (instancetype)fromClaude:(NSDictionary *)j ttl:(NSString *)ttl {
    MMUsage *u = [MMUsage new];
    NSDictionary *x = [j[@"usage"] isKindOfClass:NSDictionary.class] ? j[@"usage"] : @{};
    u.input = [x[@"input_tokens"] integerValue];
    u.cacheRead = [x[@"cache_read_input_tokens"] integerValue];
    u.output = [x[@"output_tokens"] integerValue];
    NSDictionary *details = [x[@"output_tokens_details"] isKindOfClass:NSDictionary.class] ? x[@"output_tokens_details"] : @{};
    u.thinking = [details[@"thinking_tokens"] integerValue];
    NSInteger writes = [x[@"cache_creation_input_tokens"] integerValue];
    NSDictionary *split = [x[@"cache_creation"] isKindOfClass:NSDictionary.class] ? x[@"cache_creation"] : @{};
    u.cacheWrite5m = [split[@"ephemeral_5m_input_tokens"] integerValue];
    u.cacheWrite1h = [split[@"ephemeral_1h_input_tokens"] integerValue];
    NSInteger rest = writes - u.cacheWrite5m - u.cacheWrite1h;
    if (rest > 0) { if ([ttl isEqualToString:@"5m"]) u.cacheWrite5m += rest; else u.cacheWrite1h += rest; }
    u.listCostUSD = [j[@"total_cost_usd"] doubleValue];
    return u;
}

/// One turn.completed event of `codex exec --json`. Codex counts cached input inside input_tokens, research F 1.2,
/// and reasoning inside output_tokens. It reports no cost, and no Luna price was found, so the list cost stays 0.
- (void)addCodexTurn:(NSDictionary *)x {
    NSInteger cached = [x[@"cached_input_tokens"] integerValue];
    self.input += MAX(0, [x[@"input_tokens"] integerValue] - cached);
    self.cacheRead += cached;
    self.output += [x[@"output_tokens"] integerValue];
    self.thinking += [x[@"reasoning_output_tokens"] integerValue];
}

@end

#pragma mark - Answer

@interface MMAnswer ()
@property (readwrite) NSDictionary *json;
@property (readwrite, copy) NSString *model, *error, *note;
@property (readwrite) MMUsage *usage;
@end

@implementation MMAnswer @end

#pragma mark - Redaction, P42

NSString *MMRedact(NSString *s) {
    static NSArray<NSArray *> *rules; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *word = @"(?:token|secret|password|passwd|pwd|api[_-]?key|apikey|auth|credential|private[_-]?key|session|cookie|bearer)";
        rules = @[
            @[[NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(?i)(\\b[\\w.-]*%@[\\w.-]*\\s*[=:]\\s*)[^\\s'\"]+", word] options:0 error:nil], @"$1<redacted>"],
            @[[NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(?i)(--?[\\w-]*%@[\\w-]*\\s+)[^\\s-][^\\s]*", word] options:0 error:nil], @"$1<redacted>"],
            @[[NSRegularExpression regularExpressionWithPattern:@"(://)[^/\\s:@]+:[^/\\s@]+@" options:0 error:nil], @"$1<redacted>@"],
            @[[NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9+_\\-]{40,}" options:0 error:nil], @"<redacted>"]];
    });
    if (![s isKindOfClass:NSString.class]) return nil;
    NSMutableString *m = [s mutableCopy];
    for (NSArray *r in rules) [r[0] replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:r[1]];
    return m;
}

/// The home folder as ~, wherever it appears.
static NSString *Tilde(NSString *s) {
    NSString *home = NSHomeDirectory();
    return home.length > 1 ? [s stringByReplacingOccurrencesOfString:home withString:@"~"] : s;
}

NSString *MMClip(NSString *s, NSUInteger max) {
    if (![s isKindOfClass:NSString.class]) return nil;
    s = [[[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
          filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    s = MMRedact(Tilde(s));
    if (!s.length) return nil;
    if (max == 0) return s;
    return s.length > max ? [[s substringToIndex:max - 1] stringByAppendingString:@"…"] : s;
}

/// F5. What the model gets: every string redacted with the home folder as ~ and clipped at 400 characters,
/// and every null, false, zero and empty value dropped. An id is never redacted, so the answer maps back to it.
/// nil when nothing is left.
id MMCompactFacts(id v, NSString *key) {
    if (!v || v == NSNull.null) return nil;
    if ([v isKindOfClass:NSString.class]) {
        NSString *s = Tilde(v);
        if (![key isEqualToString:@"id"]) s = MMRedact(s);
        if (s.length > 400) s = [[s substringToIndex:399] stringByAppendingString:@"…"];
        return s.length ? s : nil;
    }
    if ([v isKindOfClass:NSNumber.class]) return [v doubleValue] == 0 ? nil : v;   // @NO is 0 too
    if ([v isKindOfClass:NSDate.class]) return [NSISO8601DateFormatter stringFromDate:v timeZone:NSTimeZone.localTimeZone
                                                                        formatOptions:NSISO8601DateFormatWithInternetDateTime];
    if ([v isKindOfClass:NSArray.class]) {
        NSMutableArray *a = [NSMutableArray new];
        for (id x in v) { id c = MMCompactFacts(x, nil); if (c) [a addObject:c]; }
        return a.count ? a : nil;
    }
    if ([v isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d = [NSMutableDictionary new];
        for (id k in v) { if (![k isKindOfClass:NSString.class]) continue; id c = MMCompactFacts(v[k], k); if (c) d[k] = c; }
        return d.count ? d : nil;
    }
    return MMCompactFacts([v description], key);
}

/// Compact JSON with sorted keys, so a batch whose facts did not change gives the same bytes.
NSData *MMReviewJSON(id obj) {
    if (!obj) return NSData.data;
    return [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil] ?: NSData.data;
}

#pragma mark - Running a CLI

/// A CLI by name: the test variable, the pref, the usual install paths, then a login shell's PATH.
/// The test variable wins even when it names nothing, so a test never reaches the real CLI.
static NSString *FindTool(NSString *name, NSString *envKey, NSString *prefKey, NSArray<NSString *> *paths) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *env = NSProcessInfo.processInfo.environment[envKey];
    if (env.length) return env;
    id pref = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)prefKey, CFSTR("no.guerrilla.minmacs")));
    if ([pref isKindOfClass:NSString.class] && [fm isExecutableFileAtPath:pref]) return pref;
    for (NSString *p in paths)
        if ([fm isExecutableFileAtPath:p.stringByExpandingTildeInPath]) return p.stringByExpandingTildeInPath;
    // Last resort: ask a login shell, which knows the person's PATH. whence -p skips aliases.
    NSTask *t = [NSTask new]; NSPipe *out = [NSPipe pipe];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"]; t.arguments = @[@"-lc", [@"whence -p " stringByAppendingString:name]];
    t.standardOutput = out; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    [t waitUntilExit];
    NSString *p = [[[NSString alloc] initWithData:[out.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [fm isExecutableFileAtPath:p] ? p : nil;
}

/// A fresh folder for one call, under <support>/review/calls. Parallel calls never share a file.
static NSString *CallDir(void) {
    NSString *root = [MMReviewDir() stringByAppendingPathComponent:@"calls"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    char tmpl[PATH_MAX];
    snprintf(tmpl, sizeof tmpl, "%s/call.XXXXXX", root.fileSystemRepresentation);
    return mkdtemp(tmpl) ? @(tmpl) : nil;
}

/// Runs a CLI with input on stdin, in cwd, with the given variables removed and env added.
/// Returns NO with *error set when it could not start or did not finish in time.
static BOOL Run(NSString *path, NSArray *args, NSData *input, NSString *cwd, NSDictionary *add, BOOL (^drop)(NSString *key),
                NSData **outData, NSData **errData, int *status, NSString **error) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    for (NSString *k in env.allKeys) if (drop(k)) [env removeObjectForKey:k];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", [@"~/.local/bin" stringByExpandingTildeInPath]];
    [env addEntriesFromDictionary:add ?: @{}];
    t.environment = env;
    t.currentDirectoryURL = [NSURL fileURLWithPath:cwd];   // a fresh folder, so no project CLAUDE.md or AGENTS.md is picked up
    NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe], *err = [NSPipe pipe];
    t.standardInput = in; t.standardOutput = out; t.standardError = err;
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) { *error = [NSString stringWithFormat:@"could not start %@: %@", path.lastPathComponent, e.localizedDescription]; return NO; }

    // The input goes in on its own queue, so a CLI that answers before it reads cannot block us.
    // F_SETNOSIGPIPE turns a CLI that exits without reading into EPIPE instead of a signal.
    __block NSData *o = nil, *x = nil;
    dispatch_group_t g = dispatch_group_create();
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    int wfd = in.fileHandleForWriting.fileDescriptor;
    fcntl(wfd, F_SETNOSIGPIPE, 1);
    dispatch_group_async(g, q, ^{
        const uint8_t *p = input.bytes; size_t left = input.length;
        while (left > 0) { ssize_t n = write(wfd, p, left); if (n <= 0) break; p += n; left -= (size_t)n; }
        [in.fileHandleForWriting closeFile];
    });
    dispatch_group_async(g, q, ^{ o = [out.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_async(g, q, ^{ x = [err.fileHandleForReading readDataToEndOfFile]; });
    if (dispatch_group_wait(g, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC))) != 0) {
        [t terminate];
        *error = [NSString stringWithFormat:@"%@ did not answer within %.0f seconds", path.lastPathComponent, kTimeout];
        return NO;
    }
    [t waitUntilExit];
    *outData = o; *errData = x; *status = t.terminationStatus;
    return YES;
}

static NSString *Trimmed(NSData *d, NSUInteger max) {
    NSString *s = [[[NSString alloc] initWithData:d ?: NSData.data encoding:NSUTF8StringEncoding] ?: @""
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length > max ? [s substringToIndex:max] : s;
}

static NSString *JSONText(id obj) { return [[NSString alloc] initWithData:MMReviewJSON(obj) encoding:NSUTF8StringEncoding]; }

#pragma mark - Claude

/// What one claude call needs. tools "" turns every tool off. schema nil asks for words. cwd nil makes a fresh folder.
@interface MMClaudeCall : NSObject
@property (copy) NSString *model, *system, *tools, *effort, *ttl, *cwd;
@property NSDictionary *schema;
@end
@implementation MMClaudeCall @end

/// Claude through `claude -p` on the person's own login. Returns the parsed JSON, or nil with a.error set.
static NSDictionary *AskClaude(MMAnswer *a, NSString *claude, MMClaudeCall *c, NSData *prompt) {
    NSMutableArray *args = [@[@"-p", @"--model", c.model, @"--output-format", @"json", @"--tools", c.tools ?: @"",
                              @"--no-session-persistence", @"--strict-mcp-config", @"--setting-sources", @"",
                              @"--system-prompt", c.system ?: @""] mutableCopy];
    if (c.effort.length) [args addObjectsFromArray:@[@"--effort", c.effort]];
    if (c.schema) [args addObjectsFromArray:@[@"--json-schema", JSONText(c.schema)]];
    if (c.tools.length) [args addObjectsFromArray:@[@"--allowedTools", c.tools]];
    // The person's own Claude login, never an API key from the environment, and not a nested session of the agent that launched us.
    NSArray *dropped = @[@"ANTHROPIC_API_KEY", @"ANTHROPIC_AUTH_TOKEN", @"CLAUDECODE", @"CLAUDE_CODE_ENTRYPOINT", @"CLAUDE_CODE_SSE_PORT"];
    NSDictionary *add = c.ttl.length ? @{@"CLAUDE_CODE_PROMPT_CACHE_TTL": c.ttl} : nil;
    NSString *dir = c.cwd ? nil : CallDir();
    NSData *out, *err; int status; NSString *e = nil;
    a.model = c.model;
    NSDate *start = NSDate.date;
    BOOL ran = Run(claude, args, prompt, c.cwd ?: dir ?: NSTemporaryDirectory(), add,
                   ^BOOL(NSString *k) { return [dropped containsObject:k]; }, &out, &err, &status, &e);
    if (dir) [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    if (!ran) { a.error = e; return nil; }

    NSDictionary *j = out.length ? [NSJSONSerialization JSONObjectWithData:out options:0 error:nil] : nil;
    if (![j isKindOfClass:NSDictionary.class]) {
        NSString *msg = Trimmed(err.length ? err : out, 300);
        a.error = msg.length ? msg : [NSString stringWithFormat:@"claude exited with status %d", status];
        return nil;
    }
    MMUsage *u = [MMUsage fromClaude:j ttl:c.ttl];
    u.model = c.model; u.seconds = -start.timeIntervalSinceNow;
    a.usage = u;
    if ([j[@"is_error"] boolValue]) { a.error = [j[@"result"] description] ?: @"claude reported an error"; return nil; }
    if (!c.schema) return [j[@"result"] isKindOfClass:NSString.class] ? @{@"text": j[@"result"]} : nil;
    id so = j[@"structured_output"];
    if (![so isKindOfClass:NSDictionary.class]) {
        NSData *d = [[j[@"result"] description] dataUsingEncoding:NSUTF8StringEncoding];
        so = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    }
    if (![so isKindOfClass:NSDictionary.class]) { a.error = @"the answer did not match the schema"; return nil; }
    return so;
}

#pragma mark - Codex

/// The Luna models Codex offers this account, newest first as Codex lists them, then the known names.
static NSArray<NSString *> *LunaModels(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"CODEX_HOME"] ?: [@"~/.codex" stringByExpandingTildeInPath];
    NSData *d = [NSData dataWithContentsOfFile:[home stringByAppendingPathComponent:@"models_cache.json"]];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSMutableArray *l = [NSMutableArray new];
    if ([j isKindOfClass:NSDictionary.class] && [j[@"models"] isKindOfClass:NSArray.class])
        for (NSDictionary *m in j[@"models"])
            if ([m isKindOfClass:NSDictionary.class] && [m[@"slug"] isKindOfClass:NSString.class] && [m[@"slug"] containsString:@"luna"]) [l addObject:m[@"slug"]];
    for (NSString *m in @[@"gpt-6-luna", @"gpt-5.6-luna"]) if (![l containsObject:m]) [l addObject:m];
    return l;
}

/// A TOML basic string, for codex -c key=value.
static NSString *TOMLString(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [NSString stringWithFormat:@"\"%@\"", s];
}

/// The message inside a codex error, which is often an API error body as JSON.
static NSString *CodexMessage(NSString *m) {
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:[m dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data options:0 error:nil];
    if ([j isKindOfClass:NSDictionary.class] && [j[@"error"] isKindOfClass:NSDictionary.class] && [j[@"error"][@"message"] isKindOfClass:NSString.class])
        return j[@"error"][@"message"];
    return m;
}

/// OpenAI through `codex exec`. Every tool is turned off and the sandbox is read-only, so the model only answers.
static NSDictionary *AskCodexModel(MMAnswer *a, NSString *codex, NSString *model, NSString *system, NSDictionary *schemaObj,
                                   NSString *effort, NSData *prompt) {
    NSString *dir = CallDir();
    if (!dir) { a.error = @"could not make a folder for the call"; return nil; }
    NSString *schema = [dir stringByAppendingPathComponent:@"schema.json"], *answer = [dir stringByAppendingPathComponent:@"answer.json"];
    [MMReviewJSON(schemaObj) writeToFile:schema atomically:YES];
    NSMutableArray *args = [@[@"exec", @"--model", model, @"--json", @"--output-schema", schema, @"--output-last-message", answer,
                              @"--sandbox", @"read-only", @"--skip-git-repo-check", @"--ephemeral", @"--ignore-user-config", @"--ignore-rules",
                              @"-c", [NSString stringWithFormat:@"model_reasoning_effort=\"%@\"", effort.length ? effort : @"low"],
                              @"-c", @"web_search=\"disabled\"", @"-c", @"approval_policy=\"never\"",
                              @"-c", @"include_apply_patch_tool=false", @"-c", @"features.multi_agent=false",
                              @"-c", [@"developer_instructions=" stringByAppendingString:TOMLString(system ?: @"")]] mutableCopy];
    for (NSString *f in @[@"shell_tool", @"unified_exec", @"apps", @"plugins", @"browser_use", @"computer_use", @"image_generation",
                          @"multi_agent", @"hooks", @"view_image", @"skill_search", @"tool_suggest", @"goals", @"sleep_tool"])
        [args addObjectsFromArray:@[@"--disable", f]];
    [args addObject:@"-"];
    // The person's ChatGPT login from ~/.codex, never an API key from the environment, and not a nested session of a running Codex.
    NSData *out, *err; int status; NSString *e = nil;
    a.model = model;
    NSDate *start = NSDate.date;
    BOOL ran = Run(codex, args, prompt, dir, nil, ^BOOL(NSString *k) {
        return [@[@"OPENAI_API_KEY", @"OPENAI_BASE_URL"] containsObject:k] || ([k hasPrefix:@"CODEX_"] && ![k isEqualToString:@"CODEX_HOME"]);
    }, &out, &err, &status, &e);
    NSData *d = ran ? [NSData dataWithContentsOfFile:answer] : nil;
    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    if (!ran) { a.error = e; return nil; }

    MMUsage *u = [MMUsage new];
    u.model = model;
    NSString *failure = nil;
    for (NSString *line in [[[NSString alloc] initWithData:out ?: NSData.data encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"]) {
        NSDictionary *ev = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data options:0 error:nil];
        if (![ev isKindOfClass:NSDictionary.class]) continue;
        if ([ev[@"type"] isEqual:@"turn.completed"] && [ev[@"usage"] isKindOfClass:NSDictionary.class]) {
            [u addCodexTurn:ev[@"usage"]];
        } else if ([ev[@"type"] isEqual:@"turn.failed"] && [ev[@"error"] isKindOfClass:NSDictionary.class] &&
                   [ev[@"error"][@"message"] isKindOfClass:NSString.class]) {
            failure = CodexMessage(ev[@"error"][@"message"]);
        } else if ([ev[@"type"] isEqual:@"error"] && [ev[@"message"] isKindOfClass:NSString.class]) {
            failure = failure ?: CodexMessage(ev[@"message"]);
        }
    }
    u.seconds = -start.timeIntervalSinceNow;
    a.usage = u;
    id so = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    if ([so isKindOfClass:NSDictionary.class]) return so;
    NSString *msg = failure ?: Trimmed(err, 300);
    a.error = msg.length ? [msg substringToIndex:MIN(300, msg.length)] : [NSString stringWithFormat:@"codex exited with status %d", status];
    return nil;
}

/// "luna" tries each Luna model this account offers, moving on only when the account cannot use that model.
static NSDictionary *AskCodex(MMAnswer *a, NSString *codex, NSString *model, NSString *system, NSDictionary *schema,
                              NSString *effort, NSData *prompt) {
    NSArray *models = [model isEqualToString:@"luna"] ? LunaModels() : @[model];
    MMUsage *spent = nil;
    NSDictionary *so = nil;
    for (NSString *m in models) {
        a.error = nil; a.usage = nil;
        so = AskCodexModel(a, codex, m, system, schema, effort, prompt);
        spent = spent ? [spent adding:a.usage] : a.usage;
        if (so) break;
        if (!([a.error containsString:@"not supported"] || [a.error containsString:@"model_not_found"] || [a.error containsString:@"does not exist"])) break;
    }
    a.usage = spent;
    return so;
}

static BOOL IsCodexModel(NSString *m) { return [m isEqualToString:@"luna"] || [m hasPrefix:@"gpt-"]; }

#pragma mark - The model

@implementation MMModel

+ (NSString *)claudePath {
    return FindTool(@"claude", @"MINMACS_CLAUDE", @"review.claudePath",
                    @[@"~/.local/bin/claude", @"~/.claude/local/claude", @"/opt/homebrew/bin/claude", @"/usr/local/bin/claude", @"~/.npm-global/bin/claude", @"~/.bun/bin/claude"]);
}

+ (NSString *)codexPath {
    return FindTool(@"codex", @"MINMACS_CODEX", @"review.codexPath",
                    @[@"~/.local/bin/codex", @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex", @"~/.npm-global/bin/codex", @"~/.bun/bin/codex"]);
}

+ (MMAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
            input:(NSDictionary *)input effort:(NSString *)effort {
    return [self ask:model system:system schema:schema input:input effort:effort ttl:nil];
}

/// The broker's call: ask:system:schema:input:effort: with the cache TTL of research F4. ttl nil leaves Claude Code's own.
+ (MMAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
            input:(NSDictionary *)input effort:(NSString *)effort ttl:(NSString *)ttl {
    MMAnswer *a = [MMAnswer new];
    model = model.length ? model : @"auto";
    effort = effort.length ? effort : @"low";
    NSData *prompt = MMReviewJSON(MMCompactFacts(input, nil) ?: @{});
    MMClaudeCall *c = [MMClaudeCall new];
    c.system = system; c.tools = @""; c.effort = effort; c.ttl = ttl; c.schema = schema ?: @{@"type": @"object"};
    NSDictionary *so = nil;
    if ([model isEqualToString:@"auto"]) {
        // Haiku first. Luna when claude is missing, signed out, out of usage or fails in any other way.
        NSString *claude = [self claudePath], *codex = nil;
        c.model = @"haiku";
        if (claude) so = AskClaude(a, claude, c, prompt);
        if (!so) {
            a.note = [NSString stringWithFormat:@"Haiku: %@", claude ? a.error : @"claude CLI not found"];
            MMUsage *haiku = a.usage;
            a.error = nil; a.usage = nil;
            if ((codex = [self codexPath])) so = AskCodex(a, codex, @"luna", system, c.schema, effort, prompt);
            else a.error = @"codex CLI not found";
            a.usage = haiku ? [haiku adding:a.usage] : a.usage;   // a failed Haiku call may still have spent tokens
            if (!so) a.error = [NSString stringWithFormat:@"%@. Luna: %@", a.note, a.error];
        }
    } else if (IsCodexModel(model)) {
        NSString *codex = [self codexPath];
        if (codex) so = AskCodex(a, codex, model, system, c.schema, effort, prompt);
        else a.error = @"codex CLI not found. Install Codex and sign in, or set review.codexPath.";
    } else {
        NSString *claude = [self claudePath];
        c.model = model;
        if (claude) so = AskClaude(a, claude, c, prompt);
        else a.error = @"claude CLI not found. Install Claude Code and sign in, or set review.claudePath.";
    }
    a.json = so;
    if (!a.usage) { a.usage = [MMUsage new]; a.usage.model = a.model; }
    return a;
}

/// Investigate's call, PLAN.md section 4 and research F9: Claude with only Read, Grep and Glob, run in folder.
+ (MMAnswer *)investigate:(NSString *)question system:(NSString *)system folder:(NSString *)folder {
    MMAnswer *a = [MMAnswer new];
    NSString *claude = [self claudePath];
    if (!claude) { a.error = @"claude CLI not found. Install Claude Code and sign in, or set review.claudePath."; a.usage = [MMUsage new]; return a; }
    MMClaudeCall *c = [MMClaudeCall new];
    c.model = @"haiku"; c.system = system; c.tools = @"Read,Grep,Glob"; c.effort = @"low"; c.cwd = folder;
    NSDictionary *so = AskClaude(a, claude, c, [question dataUsingEncoding:NSUTF8StringEncoding]);
    a.json = so;
    if (!a.usage) a.usage = [MMUsage new];
    return a;
}

@end
