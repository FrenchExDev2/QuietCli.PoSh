/* Unit and process regressions for the bundled Linux bridge, without engine dependencies. */
#define _GNU_SOURCE
#include <unistd.h>
static ssize_t injected_write(int fd, const void *data, size_t length);
#define write injected_write
#define main bridge_main
#include "../../FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c"
#undef main
#undef write
#undef NDEBUG
#include <assert.h>
#include <poll.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <time.h>

static int failures;
static void check(int condition, const char *name) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", name); fflush(stdout);
    if (!condition) failures++;
}
/* Fault injection is private to the calling thread; real PTY threads use write unchanged. */
static _Thread_local struct {
    int enabled, error, interrupted, calls;
    size_t limit, used;
    unsigned char bytes[1024];
} output_fault;
static ssize_t injected_write(int fd, const void *data, size_t length) {
    if (!output_fault.enabled) return write(fd, data, length);
    if (++output_fault.calls > 4096) { errno = ELOOP; return -1; }
    if (output_fault.interrupted) { output_fault.interrupted--; errno = EINTR; return -1; }
    if (output_fault.error) { errno = output_fault.error; return -1; }
    size_t count = length < output_fault.limit ? length : output_fault.limit;
    if (count > sizeof(output_fault.bytes) - output_fault.used) { errno = EOVERFLOW; return -1; }
    memcpy(output_fault.bytes + output_fault.used, data, count);
    output_fault.used += count;
    return (ssize_t)count;
}
static void test_write_all(void) {
    unsigned char payload[513];
    for (size_t i = 0; i < sizeof(payload); i++) payload[i] = (unsigned char)(i * 37U);
    memset(&output_fault, 0, sizeof(output_fault)); output_fault.enabled = 1;
    check(write_all(-1, payload, 0) == 0 && output_fault.calls == 0, "empty write makes no system call");
    check(write_all(-1, payload, sizeof(payload)) == -1 && output_fault.calls == 1, "zero-progress write stops without spinning");
    output_fault.calls = 0; output_fault.error = EPIPE; errno = 0;
    check(write_all(-1, payload, sizeof(payload)) == -1 && errno == EPIPE && output_fault.calls == 1,
        "permanent write error is returned without retry");
    int valid = 1;
    /* Fixed schedules exercise binary equality, pointer advancement and repeated interruptions. */
    for (unsigned int trial = 0; trial < 1000; trial++) {
        memset(&output_fault, 0, sizeof(output_fault)); output_fault.enabled = 1;
        output_fault.limit = 1U + (trial * 73U % 127U); output_fault.interrupted = (int)(trial % 7U);
        size_t length = 1U + (trial * 97U % sizeof(payload));
        if (write_all(-1, payload, length) || output_fault.used != length ||
            memcmp(output_fault.bytes, payload, length)) { valid = 0; break; }
    }
    output_fault.enabled = 0;
    check(valid, "1000 short-write and EINTR schedules preserve every binary byte");
}
static int reap(pid_t pid) {
    int status; pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result != pid) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
/* Test lookup in a disposable child so a successful exec cannot replace the suite. */
static int lookup(const char *path, const char *name, int expected_errno) {
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        if (path) assert(!setenv("PATH", path, 1)); else assert(!unsetenv("PATH"));
        char *args[] = { (char *)name, NULL }; exec_no_shell(args);
        _exit(errno == expected_errno ? 0 : 99);
    }
    return reap(child);
}
static void test_descriptors(int proc) {
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        int fd = open("/dev/null", O_RDONLY); assert(fd >= 0);
        int high = fcntl(fd, F_DUPFD, 512); assert(high >= 512);
        struct rlimit limit; assert(!getrlimit(RLIMIT_NOFILE, &limit));
        limit.rlim_cur = 64; assert(!setrlimit(RLIMIT_NOFILE, &limit));
        if (proc ? close_inherited_proc() : close_inherited()) _exit(1);
        if (fcntl(fd, F_GETFD) != -1 || errno != EBADF) _exit(2);
        if (fcntl(high, F_GETFD) != -1 || errno != EBADF) _exit(3);
        for (int i = 0; i < 3; i++) if (fcntl(i, F_GETFD) < 0) _exit(4);
        _exit(0);
    }
    check(reap(child) == 0, proc ? "procfs fallback closes low/high descriptors; standard streams preserved" : "inherited low/high descriptors closed; standard streams preserved");
}
static void ignore_signal(int number) { (void)number; }
static void test_group(void) {
    int ready[2]; assert(!pipe(ready));
    pid_t leader = fork(); assert(leader >= 0);
    if (!leader) {
        close(ready[0]); assert(setsid() == getpid());
        struct sigaction action = { .sa_handler = ignore_signal }; sigemptyset(&action.sa_mask);
        assert(!sigaction(SIGTERM, &action, NULL));
        pid_t descendant = fork(); assert(descendant >= 0);
        if (!descendant) {
            action.sa_handler = SIG_DFL; assert(!sigaction(SIGTERM, &action, NULL));
            alarm(5); unsigned char byte = 1; assert(!write_all(ready[1], &byte, 1));
            for (;;) pause();
        }
        close(ready[1]); _exit(reap(descendant) == 128 + SIGTERM ? 0 : 1);
    }
    close(ready[1]); unsigned char byte; assert(read(ready[0], &byte, 1) == 1); close(ready[0]);
    signal_child(leader, SIGTERM);
    check(reap(leader) == 0, "signal targets descendants in the private process group");
}
static void test_startup_failure(const char *self) {
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        int before = 0;
        for (int fd = 3; fd < 1024; fd++) if (fcntl(fd, F_GETFD) >= 0) before++;
        char *args[] = { "quietcli-pty", "--control", "/nonexistent/quietcli-control", "--", (char *)self, "--fixture", NULL };
        int result = bridge_main(6, args);
        int after = 0;
        for (int fd = 3; fd < 1024; fd++) if (fcntl(fd, F_GETFD) >= 0) after++;
        int status; pid_t waited = waitpid(-1, &status, WNOHANG);
        _exit(result == 125 && waited == -1 && errno == ECHILD && child_pid == 0 && before == after ? 0 : 1);
    }
    check(reap(child) == 0, "control connection failure kills and reaps the child");
}
static void test_signal(int session, int number) {
    int ready[2]; assert(!pipe(ready));
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        close(ready[0]);
        alarm(2);
        if (session) assert(setsid() == getpid());
        unsigned char byte = 1; assert(!write_all(ready[1], &byte, 1));
        for (;;) pause();
    }
    close(ready[1]); unsigned char byte; assert(read(ready[0], &byte, 1) == 1); close(ready[0]);
    child_pid = child; errno = EDOM; forward_signal(number);
    int preserved = errno == EDOM;
    check(reap(child) == 128 + number && preserved, session ? "signal reaches private session; errno preserved" : "signal reaches child before setsid; errno preserved");
    child_pid = 0;
}
/* Exercise real PTY setup, control connection, exec, and shutdown with idle stdin. */
static void test_bridge(const char *self, const char *directory) {
    char socket_path[108]; assert(snprintf(socket_path, sizeof(socket_path), "%s/control", directory) > 0);
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0); assert(listener >= 0);
    struct sockaddr_un address = { .sun_family = AF_UNIX }; strcpy(address.sun_path, socket_path);
    assert(!bind(listener, (struct sockaddr *)&address, sizeof(address))); assert(!listen(listener, 1));
    int input[2]; assert(!pipe(input));
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        close(input[1]); assert(dup2(input[0], STDIN_FILENO) >= 0);
        char *args[] = { "quietcli-pty", "--control", socket_path, "--", (char *)self, "--fixture", NULL };
        _exit(bridge_main(6, args));
    }
    close(input[0]);
    struct pollfd pfd = { .fd = listener, .events = POLLIN };
    int connected = poll(&pfd, 1, 5000) == 1;
    int control = connected ? accept(listener, NULL, NULL) : -1;
    int result = reap(child);
    check(connected && control >= 0 && result == 23, "real PTY has controlling session, clean descriptors, dimensions and idle-input shutdown");
    if (control >= 0) close(control);
    close(input[1]); close(listener); unlink(socket_path);
}
/* A bounded producer and a streaming oracle exercise real PTY backpressure. */
#define STREAM_BYTES ((1U << 20) + 137U)
static long long monotonic_ms(void) {
    struct timespec time; assert(!clock_gettime(CLOCK_MONOTONIC, &time));
    return (long long)time.tv_sec * 1000 + time.tv_nsec / 1000000;
}
static unsigned char stream_byte(size_t offset) {
    return (unsigned char)(offset * 73U + offset / 251U);
}
/* The fixture writes directly, without depending on the helper under test. */
static int fixture_write(int fd, const void *data, size_t count) {
    size_t offset = 0;
    while (offset != count) {
        ssize_t written = write(fd, (const unsigned char *)data + offset, count - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return -1;
        offset += (size_t)written;
    }
    return 0;
}
static int binary_fixture(const char *pid_path, const char *mode) {
    alarm(10);
    struct termios settings;
    if (tcgetattr(0, &settings)) return 95;
    cfmakeraw(&settings); if (tcsetattr(0, TCSANOW, &settings)) return 95;
    int hold = !strcmp(mode, "hold");
    if (hold) {
        struct sigaction action = { .sa_handler = SIG_IGN }; sigemptyset(&action.sa_mask);
        if (sigaction(SIGHUP, &action, NULL)) return 95;
    }
    int marker = open(pid_path, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (marker < 0) return 95;
    pid_t identity = getpid(); int recorded = fixture_write(marker, &identity, sizeof(identity)); close(marker);
    if (recorded) return 95;
    unsigned char bytes[32768];
    for (size_t offset = 0; offset < STREAM_BYTES;) {
        size_t count = STREAM_BYTES - offset; if (count > sizeof(bytes)) count = sizeof(bytes);
        for (size_t i = 0; i < count; i++) bytes[i] = stream_byte(offset + i);
        if (fixture_write(1, bytes, count)) { if (!hold) return 96; break; }
        offset += count;
    }
    if (hold) for (;;) pause();
    return 47;
}
static int wait_bounded(pid_t child, int *code, int milliseconds) {
    long long deadline = monotonic_ms() + milliseconds;
    do {
        int status; pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) {
            *code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            return 1;
        }
        if (result < 0 && errno != EINTR) return 0;
        usleep(1000);
    } while (monotonic_ms() < deadline);
    return 0;
}
static void test_stream(const char *self, const char *directory, int mode) {
    char socket_path[108], pid_path[PATH_MAX];
    assert(snprintf(socket_path, sizeof(socket_path), "%s/stream-%d", directory, mode) > 0);
    assert(snprintf(pid_path, sizeof(pid_path), "%s/producer-%d", directory, mode) > 0);
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0); assert(listener >= 0);
    struct sockaddr_un address = { .sun_family = AF_UNIX }; strcpy(address.sun_path, socket_path);
    assert(!bind(listener, (struct sockaddr *)&address, sizeof(address))); assert(!listen(listener, 1));
    int input[2], output[2]; assert(!pipe(input)); assert(!pipe(output));
    int capacity = fcntl(output[1], F_SETPIPE_SZ, 4096); assert(capacity >= 4096);
    pid_t bridge = fork(); assert(bridge >= 0);
    if (!bridge) {
        close(input[1]); close(output[0]); close(listener);
        assert(dup2(input[0], 0) >= 0); assert(dup2(output[1], 1) >= 0);
        /* Keep a probe writer until backpressure is observed, then close it before EOF. */
    close(input[0]);
        char *args[] = { "quietcli-pty", "--control", socket_path, "--", (char *)self,
            "--binary-fixture", pid_path, mode == 1 ? "hold" : "normal", NULL };
        _exit(bridge_main(8, args));
    }
    /* Keep a probe writer until backpressure is observed, then close it before EOF. */
    close(input[0]);
    struct pollfd connection = { .fd = listener, .events = POLLIN };
    int control = poll(&connection, 1, 5000) == 1 ? accept(listener, NULL, NULL) : -1;
    int full = 0; long long deadline = monotonic_ms() + 5000;
    while (control >= 0 && monotonic_ms() < deadline) {
        int queued = 0; assert(!ioctl(output[0], FIONREAD, &queued));
        struct pollfd pressure = { .fd = output[1], .events = POLLOUT };
        if (queued > 0 && poll(&pressure, 1, 0) == 0) { full = 1; break; }
        struct pollfd event = { .fd = output[0], .events = POLLIN };
        if (poll(&event, 1, 1) > 0 && (event.revents & POLLHUP)) break;
        usleep(1000);
    }
    pid_t producer = 0;
    int marker = open(pid_path, O_RDONLY);
    if (marker >= 0) { if (read(marker, &producer, sizeof(producer)) != sizeof(producer)) producer = 0; close(marker); }
    if (mode == 0) {
        const unsigned char frame[] = {1, 0, 132, 0, 43}; unsigned char ack = 255;
        int sent = full && send(control, frame, sizeof(frame), MSG_NOSIGNAL) == sizeof(frame);
        struct pollfd event = { .fd = control, .events = POLLIN };
        int responsive = sent && poll(&event, 1, 3000) == 1 && read(control, &ack, 1) == 1 && ack == 0;
        check(responsive, "resize control remains responsive while the output pipe is full");
    }
    close(output[1]);
    if (mode == 2 && full) assert(!kill(bridge, SIGTERM));
    size_t received = 0; int exact = 1, eof = 0;
    if (mode == 1) { close(output[0]); output[0] = -1; }
    else {
        unsigned char bytes[4093]; deadline = monotonic_ms() + 5000;
        while (monotonic_ms() < deadline) {
            struct pollfd event = { .fd = output[0], .events = POLLIN };
            int ready = poll(&event, 1, 100);
            if (ready < 0 && errno == EINTR) continue;
            if (ready <= 0) continue;
            ssize_t count = read(output[0], bytes, sizeof(bytes));
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) { eof = count == 0; break; }
            for (ssize_t i = 0; i < count; i++) if (bytes[i] != stream_byte(received + (size_t)i)) exact = 0;
            received += (size_t)count; deadline = monotonic_ms() + 5000;
            if (mode == 0) usleep(1000);
        }
    }
    int code = -1, completed = wait_bounded(bridge, &code, 5000);
    int reaped = producer > 0 && kill(producer, 0) < 0 && errno == ESRCH;
    /* Kill the command first, allowing the bridge to reap it during failure cleanup. */
    if (!reaped && producer > 0) { if (kill(-producer, SIGKILL) < 0) kill(producer, SIGKILL); }
    if (!completed && !wait_bounded(bridge, &code, 2000)) { kill(bridge, SIGKILL); (void)reap(bridge); }
    if (mode == 0) check(full && eof && exact && received == STREAM_BYTES && completed && code == 47 && reaped,
        "slow consumer receives every binary byte and the command is reaped");
    else if (mode == 1) check(full && completed && code == 125 && reaped,
        "closed output kills and reaps a command that ignores terminal hangup");
    else check(full && eof && exact && received > 0 && received < STREAM_BYTES && completed && code == 128 + SIGTERM && reaped,
        "termination during backpressure preserves the output prefix and signal exit status");
    fprintf(stderr, "STREAM mode=%d bytes=%zu pipe=%d exact=%d exit=%d pressured=%d producer=%ld reaped=%d completed=%d\n",
        mode, received, capacity, exact, code, full, (long)producer, reaped, completed);
    if (output[0] >= 0) close(output[0]);
    close(input[1]); if (control >= 0) close(control); close(listener); unlink(socket_path); unlink(pid_path);
}
#include "pty-properties.h"
int main(int argc, char **argv) {
    alarm(30);
    if (argc == 4 && !strcmp(argv[1], "--binary-fixture")) return binary_fixture(argv[2], argv[3]);
    if (argc == 2 && !strcmp(argv[1], "--fixture")) {
        struct winsize size;
        if (!isatty(0) || !isatty(1) || !isatty(2) || getsid(0) != getpid() || tcgetpgrp(0) != getpid()) return 90;
        if (ioctl(0, TIOCGWINSZ, &size) || size.ws_col != 120 || size.ws_row != 40) return 91;
        for (int fd = 3; fd < 1024; fd++) if (fcntl(fd, F_GETFD) >= 0) return 92;
        sigset_t mask; assert(!sigprocmask(SIG_SETMASK, NULL, &mask));
        if (sigismember(&mask, SIGTERM) || sigismember(&mask, SIGINT) || sigismember(&mask, SIGHUP)) return 93;
        const int signals[] = { SIGTERM, SIGINT, SIGHUP, SIGPIPE };
        for (size_t i = 0; i < sizeof(signals) / sizeof(*signals); i++) {
            struct sigaction action; assert(!sigaction(signals[i], NULL, &action));
            if (action.sa_handler != SIG_DFL) return 94;
        }
        return 23;
    }
    check(parse_dimension("1") == 1 && parse_dimension("999") == 999 && parse_dimension("1000") == 1000, "dimension boundaries and decimal digits accepted");
    test_write_all();
    const char *invalid[] = { "", "0", "1001", "-1", "+1", " 2", "2x", "99999999999999999999999999" };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); i++) check(parse_dimension(invalid[i]) == -1, "malformed/out-of-range dimension rejected");
    char directory[] = "/tmp/quietcli-pty-unit-XXXXXX"; assert(mkdtemp(directory)); assert(!chdir(directory));
    assert(!symlink("/bin/true", "true"));
    check(lookup("", "true", ENOENT) == 0, "empty PATH excludes working directory");
    check(lookup(":/nonexistent::", "true", ENOENT) == 0, "leading/middle/trailing empty PATH entries excluded");
    check(lookup(".", "true", 0) == 0, "explicit current directory remains supported");
    check(lookup("", "./true", 0) == 0, "explicit relative executable remains supported");
    check(lookup(NULL, "true", 0) == 0, "unset PATH uses system default");
    check(lookup("/nonexistent:/bin", "true", 0) == 0, "lookup continues after missing PATH directory");
    check(lookup(":/bin::", "true", 0) == 0, "empty PATH entries do not hide later valid directories");
    int script = open("no-shell", O_CREAT | O_WRONLY, 0700); assert(script >= 0);
    assert(write(script, "exit 0\n", 7) == 7); close(script);
    check(lookup(".", "no-shell", ENOEXEC) == 0, "exec never falls back to a shell");
    assert(!chmod("no-shell", 0600));
    check(lookup(".:/nonexistent", "no-shell", EACCES) == 0, "lookup retains permission-denied outcome");
    test_descriptors(0); test_descriptors(1);
    for (int session = 0; session < 2; session++) {
        test_signal(session, SIGTERM); test_signal(session, SIGINT); test_signal(session, SIGHUP);
    }
    test_group();
    char self[PATH_MAX]; ssize_t length = readlink("/proc/self/exe", self, sizeof(self) - 1); assert(length > 0); self[length] = '\0';
    test_bridge(self, directory);
    test_startup_failure(self);
    for (int mode = 0; mode < 3; mode++) test_stream(self, directory, mode);
    run_property_tests();
    unlink("true"); unlink("no-shell"); assert(!chdir("/")); assert(!rmdir(directory));
    return failures ? 1 : 0;
}
