// Test fixture: pretends to be an agent harness.
//   fakeagent --work 6           holds a caffeinate child for 6 seconds (a "turn"), then idles
//   fakeagent --work 6 --w self  the same, but the child is `caffeinate -i -w <fakeagent pid>`
//   fakeagent --work 6 --w other the child watches pid 1 instead, as another program's caffeinate would
//   fakeagent                    idles
//   fakeagent --listen 4310 --pidfile <path>
//                                listens on 127.0.0.1:4310 itself, as an agent with a local server of its own does,
//                                in a session of its own, and writes its pid to the file
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int work = 0, port = 0; const char *watch = NULL, *pidfile = NULL;
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--work")) work = atoi(argv[i + 1]);
        if (!strcmp(argv[i], "--w")) watch = argv[i + 1];
        if (!strcmp(argv[i], "--listen")) port = atoi(argv[i + 1]);
        if (!strcmp(argv[i], "--pidfile")) pidfile = argv[i + 1];
    }
    if (port > 0) {
        setsid();
        int s = socket(AF_INET, SOCK_STREAM, 0), on = 1;
        struct sockaddr_in a; memset(&a, 0, sizeof a);
        a.sin_family = AF_INET; a.sin_port = htons((unsigned short)port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
        if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 4) != 0) return 1;
    }
    if (pidfile) { FILE *f = fopen(pidfile, "w"); if (f) { fprintf(f, "%d\n", (int)getpid()); fclose(f); } }
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
