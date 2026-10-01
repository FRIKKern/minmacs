// Test fixture: pretends to be an agent harness.
//   fakeagent --work 6           holds a caffeinate child for 6 seconds (a "turn"), then idles
//   fakeagent --work 6 --w self  the same, but the child is `caffeinate -i -w <fakeagent pid>`
//   fakeagent --work 6 --w other the child watches pid 1 instead, as another program's caffeinate would
//   fakeagent                    idles
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int work = 0; const char *watch = NULL;
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--work")) work = atoi(argv[i + 1]);
        if (!strcmp(argv[i], "--w")) watch = argv[i + 1];
    }
    char t[16], w[16];
    snprintf(t, sizeof t, "%d", work);
    snprintf(w, sizeof w, "%d", watch && !strcmp(watch, "other") ? 1 : (int)getpid());
    if (work > 0 && fork() == 0) {
        if (watch) execl("/usr/bin/caffeinate", "caffeinate", "-i", "-w", w, "-t", t, (char *)NULL);
        else       execl("/usr/bin/caffeinate", "caffeinate", "-i", "-t", t, (char *)NULL);
        _exit(1);
    }
    for (int i = 0; i < 120; i++) sleep(1);
    return 0;
}
