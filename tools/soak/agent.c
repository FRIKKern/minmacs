// The soak's fake agent: a process the fixture registry row names, with no working signal, so Insomnia holds
// nothing for it. It calls setsid, so it runs in a session of its own, and exits by itself after the seconds given.
//   agent <seconds> <tag>    the tag is the run's, so the sampler can check a pid is its own before it stops it
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int s = argc > 1 ? atoi(argv[1]) : 600;
    setsid();
    for (int i = 0; i < s; i++) sleep(1);
    return 0;
}
