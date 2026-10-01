// Test fixture: pretends to be a host that launches an agent itself (an orchestrator app).
//   fakehost <program> [args...]    runs the program as a child and waits
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    if (fork() == 0) { execv(argv[1], argv + 1); _exit(1); }
    int st; wait(&st);
    return 0;
}
