/* Generic Unix PTY spawn bridge. No shell or executable-specific parsing. */
#define _GNU_SOURCE
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid;
/* Before setsid the child has no private group yet. Never signal our own group. */
static void signal_child(pid_t child, int number) {
    if (kill(-child, number) < 0 && errno == ESRCH) kill(child, number);
}
static void forward_signal(int number) {
    int saved = errno;
    if (child_pid > 0) signal_child((pid_t)child_pid, number);
    errno = saved;
}
/* A procfs fallback also handles inherited descriptors above a lowered rlimit. */
static int close_inherited_proc(void) {
    DIR *directory = opendir("/proc/self/fd");
    if (!directory) return -1;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) {
            int saved = errno, result = closedir(directory);
            if (saved) { errno = saved; return -1; }
            return result;
        }
        char *end; long fd = strtol(entry->d_name, &end, 10);
        if (*end == '\0' && fd > STDERR_FILENO && fd <= INT_MAX && fd != dirfd(directory)) close((int)fd);
    }
}
static int close_inherited(void) {
#ifdef SYS_close_range
    if (syscall(SYS_close_range, 3U, ~0U, 0) == 0) return 0;
#endif
    return close_inherited_proc();
}
static int parse_dimension(const char *text) {
    if (!*text) return -1;
    int value = 0;
    for (; *text; text++) {
        if (*text < '0' || *text > '9') return -1;
        value = value * 10 + (*text - '0');
        if (value > 1000) return -1;
    }
    return value > 0 ? value : -1;
}
/* Decode a complete resize frame without touching terminal state on rejection. */
static int decode_resize(const unsigned char *command, size_t length, struct winsize *size) {
    if (length != 5 || command[0] != 1) return -1;
    unsigned int columns = 256U * command[1] + command[2];
    unsigned int rows = 256U * command[3] + command[4];
    if (columns == 0 || rows == 0 || columns > 1000 || rows > 1000) return -1;
    struct winsize decoded = { .ws_col = (unsigned short)columns, .ws_row = (unsigned short)rows };
    *size = decoded;
    return 0;
}
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
        if (!length) { if (!end) break; part = end + 1; continue; }
        char *candidate = malloc(length + strlen(arguments[0]) + 2);
        if (!candidate) { errno = ENOMEM; return; }
        memcpy(candidate, part, length); candidate[length] = '/'; strcpy(candidate + length + 1, arguments[0]);
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
        if (count <= 0) { signal_child(bridge->child, SIGKILL); return NULL; }
        length += (size_t)count;
        if (length != sizeof(command)) continue;
        unsigned char acknowledgement = 1;
        struct winsize size;
        if (decode_resize(command, sizeof(command), &size) == 0 && ioctl(bridge->master, TIOCSWINSZ, &size) == 0) acknowledgement = 0;
        if (write_all(bridge->control, &acknowledgement, 1)) { signal_child(bridge->child, SIGKILL); return NULL; }
        length = 0;
    }
}
int main(int argc, char **argv) {
    const char *control_path = NULL; int columns = 120, rows = 40, first = 1;
    for (; first < argc; first++) {
        if (!strcmp(argv[first], "--")) { first++; break; }
        if (first + 1 >= argc) return 125;
        if (!strcmp(argv[first], "--control")) control_path = argv[++first];
        else if (!strcmp(argv[first], "--columns")) columns = parse_dimension(argv[++first]);
        else if (!strcmp(argv[first], "--rows")) rows = parse_dimension(argv[++first]);
        else return 125;
    }
    if (!control_path || first >= argc || columns < 1 || columns > 1000 || rows < 1 || rows > 1000) return 125;
    struct sockaddr_un address; memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX;
    if (strlen(control_path) >= sizeof(address.sun_path)) return 125;
    strcpy(address.sun_path, control_path);
    /* Install handlers before fork and defer delivery until child_pid is published. */
    sigset_t blocked, previous; sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM); sigaddset(&blocked, SIGINT); sigaddset(&blocked, SIGHUP);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous)) return 125;
    struct sigaction action = { .sa_handler = forward_signal }; sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL) || sigaction(SIGHUP, &action, NULL)) return 125;
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL)) return 125;
    int master, slave; struct winsize size = { .ws_row = (unsigned short)rows, .ws_col = (unsigned short)columns };
    if (openpty(&master, &slave, NULL, NULL, &size)) { perror("quietcli-pty: openpty"); return 125; }
    pid_t child = fork();
    if (child < 0) { perror("quietcli-pty: fork"); close(master); close(slave); return 125; }
    if (child == 0) {
        action.sa_handler = SIG_DFL;
        if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL) || sigaction(SIGHUP, &action, NULL) || sigaction(SIGPIPE, &action, NULL)) _exit(125);
        if (sigprocmask(SIG_SETMASK, &previous, NULL)) _exit(125);
        close(master);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0) _exit(125);
        if (dup2(slave, STDIN_FILENO) < 0 || dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0) _exit(125);
        if (close_inherited()) _exit(125);
        exec_no_shell(argv + first);
        int missing = errno == ENOENT || errno == ENOTDIR;
        perror("quietcli-pty: execv"); _exit(missing ? 127 : 126);
    }
    child_pid = child; close(slave);
    if (sigprocmask(SIG_SETMASK, &previous, NULL) || fcntl(master, F_SETFD, FD_CLOEXEC) < 0) goto startup_failed;
    int control = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (control < 0 || connect(control, (struct sockaddr *)&address, sizeof(address)) < 0) { perror("quietcli-pty: control"); if (control >= 0) close(control); goto startup_failed; }
    struct bridge bridge = { .master = master, .control = control, .child = child };
    pthread_t input_thread, control_thread;
    if (pthread_create(&input_thread, NULL, forward_input, &bridge)) { close(control); goto startup_failed; }
    if (pthread_create(&control_thread, NULL, forward_control, &bridge)) { pthread_cancel(input_thread); pthread_join(input_thread, NULL); close(control); goto startup_failed; }
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
    if (failed) signal_child(child, SIGKILL);
    pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    child_pid = 0;
    if (failed || waited < 0) return 125;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 125;
startup_failed:
    signal_child(child, SIGKILL); close(master);
    while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
    child_pid = 0;
    return 125;
}
