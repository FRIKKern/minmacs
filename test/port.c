// The tests' port probe, in place of nc. Issue #58: a shell that runs nc against local ports reads as a reverse
// shell to an endpoint security agent, which then kills the test run.
// Usage:
//   port listening <port>             exit 0 when something accepts on 127.0.0.1:<port>
//   port free <port>                  prints the first port from <port> up that nothing accepts on
//   port wait <port> [tenths]         waits until it accepts, 100 tenths of a second at most; exit 0 if it does
//   port gone <port> [tenths]         waits until it no longer accepts, as long; exit 0 if it stopped
//   port unix <path> [seconds]        sends stdin to a unix socket, closes the sending side and prints the reply,
//                                     2 seconds at most; with seconds, connects, sends nothing and holds that long
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int Accepts(int port) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 0;
    struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int ok = connect(s, (struct sockaddr *)&a, sizeof a) == 0;
    close(s);
    return ok;
}

static int Unix(const char *path, int hold) {
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) return 1;
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof a.sun_path) return 1;
    strcpy(a.sun_path, path);
    if (connect(s, (struct sockaddr *)&a, sizeof a) != 0) return 1;
    if (hold > 0) { sleep((unsigned)hold); close(s); return 0; }
    char b[4096];
    ssize_t n;
    while ((n = read(0, b, sizeof b)) > 0)
        if (write(s, b, (size_t)n) != n) return 1;
    shutdown(s, SHUT_WR);
    struct pollfd p = {.fd = s, .events = POLLIN};
    while (poll(&p, 1, 2000) > 0 && (n = read(s, b, sizeof b)) > 0) fwrite(b, 1, (size_t)n, stdout);
    close(s);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: port listening|free|wait|gone <port> [tenths], or port unix <path> [seconds]\n"); return 2; }
    const char *verb = argv[1];
    if (!strcmp(verb, "unix")) return Unix(argv[2], argc > 3 ? atoi(argv[3]) : 0);
    int port = atoi(argv[2]), tenths = argc > 3 ? atoi(argv[3]) : 100;
    if (port <= 0 || port > 65535) return 2;
    if (!strcmp(verb, "listening")) return Accepts(port) ? 0 : 1;
    if (!strcmp(verb, "free")) {
        while (port <= 65535 && Accepts(port)) port++;
        printf("%d\n", port);
        return 0;
    }
    int want = !strcmp(verb, "wait") ? 1 : !strcmp(verb, "gone") ? 0 : -1;
    if (want < 0) return 2;
    for (int i = 0; i < tenths && Accepts(port) != want; i++) usleep(100000);
    return Accepts(port) == want ? 0 : 1;
}
