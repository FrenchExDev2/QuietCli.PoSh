/* Generic Unix PTY spawn bridge. No shell or executable-specific parsing. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid;
static void forward_signal(int number) { if (child_pid > 0) kill(-(pid_t)child_pid, number); }
static int write_all(int fd, const unsigned char *data, size_t length) {
    while (length) { ssize_t written = write(fd, data, length); if (written < 0 && errno == EINTR) continue; if (written <= 0) return -1; data += written; length -= (size_t)written; }
    return 0;
}
struct bridge { int master, control; pid_t child; };
static void exec_no_shell(char **arguments) {
    if (strchr(arguments[0], '/')) { execv(arguments[0], arguments); return; }
    const char *path = getenv("PATH"); if (!path) path = "/usr/bin:/bin";
    const char *part = path; int denied = 0;
    do {
        const char *end = strchr(part, ':'); size_t length = end ? (size_t)(end - part) : strlen(part);
        char *candidate = malloc(length + strlen(arguments[0]) + 2);
        if (!candidate) { errno = ENOMEM; return; }
        if (length) { memcpy(candidate, part, length); candidate[length] = '/'; strcpy(candidate + length + 1, arguments[0]); }
        else strcpy(candidate, arguments[0]);
        execv(candidate, arguments); int saved = errno; free(candidate);
        if (saved == EACCES) denied = 1;
        else if (saved != ENOENT && saved != ENOTDIR) { errno = saved; return; }
        if (!end) break;
        part = end + 1;
    } while (1);
    errno = denied ? EACCES : ENOENT;
}
static void *forward_input(void *argument) {
    struct bridge *bridge = argument; unsigned char bytes[32768];
    for (;;) {
        ssize_t count = read(STDIN_FILENO, bytes, sizeof(bytes));
        if (count > 0) { if (write_all(bridge->master, bytes, (size_t)count)) return NULL; }
        else if (count == 0) {
            struct termios settings; unsigned char eof = 4;
            if (!tcgetattr(bridge->master, &settings)) eof = settings.c_cc[VEOF];
            write_all(bridge->master, &eof, 1); return NULL;
        } else if (errno != EINTR) return NULL;
    }
}
static void *forward_control(void *argument) {
    struct bridge *bridge = argument; unsigned char command[5]; size_t length = 0;
    for (;;) {
        ssize_t count = read(bridge->control, command + length, sizeof(command) - length);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { kill(-bridge->child, SIGKILL); return NULL; }
        length += (size_t)count;
        if (length != sizeof(command)) continue;
        unsigned char acknowledgement = 1;
        if (command[0] == 1) {
            struct winsize size = { .ws_col = (unsigned short)((command[1] << 8) | command[2]), .ws_row = (unsigned short)((command[3] << 8) | command[4]) };
            if (size.ws_col && size.ws_row && size.ws_col <= 1000 && size.ws_row <= 1000 && ioctl(bridge->master, TIOCSWINSZ, &size) == 0) acknowledgement = 0;
        }
        if (write_all(bridge->control, &acknowledgement, 1)) { kill(-bridge->child, SIGKILL); return NULL; }
        length = 0;
    }
}
int main(int argc, char **argv) {
    const char *control_path = NULL; int columns = 120, rows = 40, first = 1;
    for (; first < argc; first++) {
        if (!strcmp(argv[first], "--")) { first++; break; }
        if (first + 1 >= argc) return 125;
        if (!strcmp(argv[first], "--control")) control_path = argv[++first];
        else if (!strcmp(argv[first], "--columns")) columns = atoi(argv[++first]);
        else if (!strcmp(argv[first], "--rows")) rows = atoi(argv[++first]);
        else return 125;
    }
    if (!control_path || first >= argc || columns < 1 || columns > 1000 || rows < 1 || rows > 1000) return 125;
    int master, slave; struct winsize size = { .ws_row = (unsigned short)rows, .ws_col = (unsigned short)columns };
    if (openpty(&master, &slave, NULL, NULL, &size)) { perror("quietcli-pty: openpty"); return 125; }
    pid_t child = fork();
    if (child < 0) { perror("quietcli-pty: fork"); close(master); close(slave); return 125; }
    if (child == 0) {
        close(master);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0) _exit(125);
        if (dup2(slave, STDIN_FILENO) < 0 || dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0) _exit(125);
        if (slave > STDERR_FILENO) close(slave);
        exec_no_shell(argv + first);
        int missing = errno == ENOENT || errno == ENOTDIR;
        perror("quietcli-pty: execv"); _exit(missing ? 127 : 126);
    }
    child_pid = child; close(slave);
    signal(SIGTERM, forward_signal); signal(SIGINT, forward_signal); signal(SIGHUP, forward_signal); signal(SIGPIPE, SIG_IGN);
    int control = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address; memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX;
    if (strlen(control_path) >= sizeof(address.sun_path)) { kill(-child, SIGKILL); close(master); return 125; }
    strcpy(address.sun_path, control_path);
    if (control < 0 || connect(control, (struct sockaddr *)&address, sizeof(address)) < 0) { perror("quietcli-pty: control"); kill(-child, SIGKILL); close(master); return 125; }
    struct bridge bridge = { .master = master, .control = control, .child = child };
    pthread_t input_thread, control_thread;
    if (pthread_create(&input_thread, NULL, forward_input, &bridge)) { kill(-child, SIGKILL); close(control); close(master); return 125; }
    if (pthread_create(&control_thread, NULL, forward_control, &bridge)) { pthread_cancel(input_thread); pthread_join(input_thread, NULL); kill(-child, SIGKILL); close(control); close(master); return 125; }
    unsigned char bytes[32768]; int status = 0, failed = 0;
    for (;;) {
        ssize_t count = read(master, bytes, sizeof(bytes));
        if (count > 0) { if (write_all(STDOUT_FILENO, bytes, (size_t)count)) { failed = 1; break; } }
        else if (count == 0 || errno == EIO) break;
        else if (errno != EINTR) { failed = 1; break; }
    }
    pthread_cancel(input_thread); pthread_cancel(control_thread);
    pthread_join(input_thread, NULL); pthread_join(control_thread, NULL);
    close(control); close(master);
    if (failed) kill(-child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    child_pid = 0;
    if (failed) return 125;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 125;
}
