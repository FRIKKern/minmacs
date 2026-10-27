// Test fixture: a process that stands in for a working agent or a script's process. It sleeps for the seconds given,
// 600 by default. test/insomnia.sh builds it under a name unique to the run, and the test tool starts and stops it by pid.
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int s = argc > 1 ? atoi(argv[1]) : 600;
    for (int i = 0; i < s; i++) sleep(1);
    return 0;
}
