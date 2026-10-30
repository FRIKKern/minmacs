// A fixture process for test/gains.sh. Usage: fixture <megabytes> [seconds]
// It touches the given megabytes, so its footprint is known, then sleeps. It exits on its own after the given
// seconds or as soon as its parent goes away, so a crashed test never leaves it running.
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    size_t mb = argc > 1 ? (size_t)atoi(argv[1]) : 0;
    int seconds = argc > 2 ? atoi(argv[2]) : 30;
    char *block = mb ? malloc(mb << 20) : NULL;
    if (block) memset(block, 1, mb << 20);
    pid_t parent = getppid();
    time_t end = time(NULL) + seconds;
    while (time(NULL) < end && getppid() == parent) usleep(100000);
    free(block);
    return 0;
}
