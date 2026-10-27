// A fixture process for test/act.sh. Usage: fixture plain|ignore-term [seconds]
// It sleeps, and exits on its own after the given seconds or as soon as its parent goes away,
// so a crashed test never leaves it running. ignore-term ignores SIGTERM, so only SIGKILL ends it early.
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "ignore-term") == 0) signal(SIGTERM, SIG_IGN);
    int seconds = argc > 2 ? atoi(argv[2]) : 30;
    pid_t parent = getppid();
    time_t end = time(NULL) + seconds;
    while (time(NULL) < end && getppid() == parent) usleep(100000);
    return 0;
}
