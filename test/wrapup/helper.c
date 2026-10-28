// Test fixture for test/wrapup.sh: a helper a workstream leaves behind, such as a headless browser.
//   helper <pidfile> [stubborn]    writes its pid to pidfile and waits. stubborn ignores SIGTERM.
// test/wrapup.sh copies it to a name unique to the run, so nothing else on this Mac is matched by name.
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    if (argc > 2 && !strcmp(argv[2], "stubborn")) signal(SIGTERM, SIG_IGN);
    FILE *f = fopen(argv[1], "w");
    if (!f) return 1;
    fprintf(f, "%d\n", getpid());
    fclose(f);
    for (int i = 0; i < 1800; i++) sleep(1);   // never outlives the test by more than half an hour
    return 0;
}
