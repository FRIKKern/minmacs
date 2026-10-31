// The soak's fixture server, in place of a python3 -c http.server. Issue #58: an endpoint security agent read the
// shell's Python one-liners that call setsid as a reverse shell. It calls setsid, so it runs in a session of its own,
// writes its pid file with its cwd, answers each connection with a short HTTP reply, and exits by itself after the
// seconds given, even if the soak script dies.
//   server <port> <pid-dir> <seconds> <tag>    the tag is the run's, so the soak can check a pid is its own
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: server <port> <pid-dir> <seconds> <tag>\n"); return 2; }
    int port = atoi(argv[1]), life = atoi(argv[3]);
    setsid();
    int s = socket(AF_INET, SOCK_STREAM, 0), on = 1;
    if (s < 0) return 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
    struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 16) != 0) return 1;
    char path[1024], cwd[1024];
    snprintf(path, sizeof path, "%s/%d", argv[2], getpid());
    FILE *f = fopen(path, "w");
    if (f) { fputs(getcwd(cwd, sizeof cwd) ? cwd : "", f); fclose(f); }
    alarm((unsigned)(life > 0 ? life : 600));   // SIGALRM ends it
    static const char reply[] = "HTTP/1.0 200 OK\r\nContent-Length: 3\r\n\r\nok\n";
    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) continue;
        char b[1024];
        (void)read(c, b, sizeof b);
        (void)write(c, reply, sizeof reply - 1);
        close(c);
    }
}
