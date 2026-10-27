// Test fixture: an agent that works and starts an app as its own child.
//   agent --work 60 --app <path to an app's executable>
// It holds a caffeinate child while it works, the signal its fixture row reads, and the app runs in its process tree.
// test/minmacs.sh builds it under a name unique to the run and stops it, its caffeinate and the app by pid.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int work = 0; const char *app = NULL;
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--work")) work = atoi(argv[i + 1]);
        if (!strcmp(argv[i], "--app")) app = argv[i + 1];
    }
    char t[16];
    snprintf(t, sizeof t, "%d", work);
    if (work > 0 && fork() == 0) { execl("/usr/bin/caffeinate", "caffeinate", "-i", "-t", t, (char *)NULL); _exit(1); }
    if (app && fork() == 0) { execl(app, app, (char *)NULL); _exit(1); }
    for (int i = 0; i < 300; i++) sleep(1);
    return 0;
}
