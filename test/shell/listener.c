// A fixture server for the where checks: listens on 127.0.0.1:<port> and waits to be stopped.
//   listener <port> [ready]   exits 1 when the port is taken; once it listens, makes the file ready
// The ready file tells the test the socket is in the table. A live pid alone does not: on a busy Mac the exec can
// take longer than the test's wait, and a cold where then samples before the listen.
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons((unsigned short)atoi(argv[1])); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 4) != 0) return 1;
    if (argc > 2) { int r = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644); if (r >= 0) close(r); }
    for (;;) pause();
}
