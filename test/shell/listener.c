// A fixture server for the where checks: listens on 127.0.0.1:<port> and waits to be stopped.
//   listener <port>    exits 1 when the port is taken
#include <arpa/inet.h>
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
    for (;;) pause();
}
