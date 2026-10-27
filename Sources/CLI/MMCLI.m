#import "MMCLI.h"
#import "Core/Runtime/MMWorker.h"
#include <stdio.h>
#include <string.h>

NSString *const MMPhase = @"phase 0";

typedef int (*MMVerbFn)(int argc, const char *argv[]);
typedef struct { const char *name; const char *summary; MMVerbFn run; } MMVerb;

static int Version(int argc, const char *argv[]) {
    printf("MinMacs %s (%s)\n", MM_VERSION, MMPhase.UTF8String);
    return 0;
}

static int Help(int argc, const char *argv[]);

// The disk walk worker of P4. The app starts it as a child of this binary. It is not a verb for people.
static int Walk(int argc, const char *argv[]) { return MMWorkerChildMain(); }

// One verb registry. Each expert adds its rows here until phase 1 moves the table to Core.
static const MMVerb kVerbs[] = {
    { "version", "print the version and exit", Version },
    { "help",    "list the verbs",             Help },
    { "_walk",   "the disk walk worker",       Walk },
};
static const size_t kVerbCount = sizeof kVerbs / sizeof kVerbs[0];

static int Help(int argc, const char *argv[]) {
    printf("usage: minmacs <verb>\n");
    for (size_t i = 0; i < kVerbCount; i++)
        if (kVerbs[i].name[0] != '_') printf("  %-10s %s\n", kVerbs[i].name, kVerbs[i].summary);
    return 0;
}

BOOL MMWantsCLI(int argc, const char *argv[]) {
    if (argc < 2) return NO;
    if (!strcmp(argv[1], "--version") || !strcmp(argv[1], "--help")) return YES;
    return argv[1][0] != '-';
}

int MMRunCLI(int argc, const char *argv[]) {
    const char *verb = argv[1];
    if (!strcmp(verb, "--version")) verb = "version";
    if (!strcmp(verb, "--help")) verb = "help";
    for (size_t i = 0; i < kVerbCount; i++)
        if (!strcmp(verb, kVerbs[i].name)) return kVerbs[i].run(argc - 1, argv + 1);
    fprintf(stderr, "minmacs: unknown verb '%s'. Try 'minmacs help'.\n", verb);
    return 2;
}
