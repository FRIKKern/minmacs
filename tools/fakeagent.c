// Test fixture: pretends to be an agent harness.
//   fakeagent --work 6     holds a caffeinate child for 6 seconds (a "turn"), then idles
//   fakeagent              idles
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int work = 0;
    for (int i = 1; i + 1 < argc; i++) if (!strcmp(argv[i], "--work")) work = atoi(argv[i + 1]);
    if (work > 0 && fork() == 0) {
        char t[16]; snprintf(t, sizeof t, "%d", work);
        execl("/usr/bin/caffeinate", "caffeinate", "-i", "-t", t, (char *)NULL);
        _exit(1);
    }
    for (int i = 0; i < 120; i++) sleep(1);
    return 0;
}
