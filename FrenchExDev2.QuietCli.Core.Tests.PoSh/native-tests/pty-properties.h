/* Deterministic generated properties; no user-selected executable is ever launched. */
#ifndef QUIETCLI_PTY_PROPERTIES_H
#define QUIETCLI_PTY_PROPERTIES_H
#include "pty-oracles.h"
#define PROPERTY_SEED UINT32_C(633419)
static uint32_t property_random = PROPERTY_SEED;
static uint32_t next_property_random(void) {
    property_random ^= property_random << 13;
    property_random ^= property_random >> 17;
    property_random ^= property_random << 5;
    return property_random;
}
static void property_failure(const char *name, unsigned int index, const void *bytes, size_t length) {
    fprintf(stderr, "PROPERTY_FAILURE name=%s seed=%u case=%u length=%zu\n", name, PROPERTY_SEED, index, length);
    const char *directory = getenv("QUIETCLI_PTY_EVIDENCE");
    if (directory) {
        char path[PATH_MAX];
        int count = snprintf(path, sizeof(path), "%s/property-%s-%08u.bin", directory, name, index);
        if (count > 0 && (size_t)count < sizeof(path)) {
            FILE *file = fopen(path, "wb");
            if (file) { if (fwrite(bytes, 1, length, file) != length) perror("property evidence"); fclose(file); }
        }
    }
}
static int property_valid_dimensions(void) {
    for (unsigned int value = 1; value <= 1000; value++) {
        char text[32]; snprintf(text, sizeof(text), "%010u", value);
        if (parse_dimension(text) != (int)value) { property_failure("valid-dimension", value, text, strlen(text)); return 0; }
    }
    return 1;
}
static int property_dimension_strings(void) {
    static const unsigned char alphabet[] = "0123456789+- \t\nxyz\xff";
    for (unsigned int i = 0; i < 25000; i++) {
        char text[257]; size_t length = next_property_random() % 256;
        for (size_t j = 0; j < length; j++) text[j] = (char)alphabet[next_property_random() % (sizeof(alphabet) - 1)];
        if (i % 4 == 0) { snprintf(text, sizeof(text), "%u", next_property_random() % 2001); length = strlen(text); }
        text[length] = '\0';
        if (parse_dimension(text) != expected_dimension(text)) { property_failure("dimension", i, text, length); return 0; }
    }
    return 1;
}
static int property_control_decoder(void) {
    unsigned char bytes[32];
    for (unsigned int value = 1; value <= 1000; value++) {
        unsigned int rows = 1 + ((value - 1) * 37 % 1000);
        unsigned char valid[] = { 1, (unsigned char)(value >> 8), (unsigned char)value, (unsigned char)(rows >> 8), (unsigned char)rows };
        if (!resize_matches(valid, sizeof(valid))) { property_failure("resize-valid", value, valid, sizeof(valid)); return 0; }
    }
    for (unsigned int i = 0; i < 25000; i++) {
        size_t length = next_property_random() % sizeof(bytes);
        for (size_t j = 0; j < length; j++) bytes[j] = (unsigned char)next_property_random();
        if (!resize_matches(bytes, length)) { property_failure("resize", i, bytes, length); return 0; }
    }
    const unsigned int edges[] = { 0, 1, 999, 1000, 1001, 65535 };
    for (size_t i = 0; i < sizeof(edges) / sizeof(*edges); i++) for (size_t j = 0; j < sizeof(edges) / sizeof(*edges); j++) {
        unsigned char edge[] = { 1, (unsigned char)(edges[i] >> 8), (unsigned char)edges[i], (unsigned char)(edges[j] >> 8), (unsigned char)edges[j] };
        if (!resize_matches(edge, sizeof(edge))) { property_failure("resize-edge", (unsigned int)(i * 6 + j), edge, sizeof(edge)); return 0; }
    }
    return 1;
}
static pid_t property_session_child(int master, int slave, int *control) {
    int ready[2]; assert(!pipe(ready));
    pid_t child = fork(); assert(child >= 0);
    if (!child) {
        close(ready[0]); close(master); close(slave); close(control[0]); close(control[1]);
        assert(setsid() == getpid()); alarm(10);
        unsigned char byte = 1; assert(!write_all(ready[1], &byte, 1)); close(ready[1]);
        for (;;) pause();
    }
    close(ready[1]); unsigned char byte; assert(read(ready[0], &byte, 1) == 1); close(ready[0]);
    return child;
}
static int property_control_stream(int truncated) {
    int master, slave, control[2]; struct winsize expected = { .ws_col = 120, .ws_row = 40 };
    assert(!openpty(&master, &slave, NULL, NULL, &expected)); assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, control));
    pid_t child = property_session_child(master, slave, control);
    struct bridge bridge = { .master = master, .control = control[1], .child = child };
    pthread_t thread; assert(!pthread_create(&thread, NULL, forward_control, &bridge));
    int ok = 1;
    if (truncated >= 0) {
        const unsigned char bytes[] = { 1, 0, 80, 0, 24 };
        if (truncated) ok = write_all(control[0], bytes, (size_t)truncated) == 0;
    } else for (unsigned int i = 0; i < 256 && ok; i++) {
        unsigned char bytes[5];
        for (size_t j = 0; j < sizeof(bytes); j++) bytes[j] = (unsigned char)next_property_random();
        if (i % 3 == 0) {
            unsigned int columns = 1 + next_property_random() % 1000, rows = 1 + next_property_random() % 1000;
            bytes[0] = 1; bytes[1] = (unsigned char)(columns >> 8); bytes[2] = (unsigned char)columns;
            bytes[3] = (unsigned char)(rows >> 8); bytes[4] = (unsigned char)rows;
        }
        for (size_t sent = 0; sent < sizeof(bytes) && ok;) {
            size_t count = 1 + next_property_random() % 4;
            if (count > sizeof(bytes) - sent) count = sizeof(bytes) - sent;
            ok = write_all(control[0], bytes + sent, count) == 0; sent += count;
            if (sent < sizeof(bytes)) { struct pollfd fd = { .fd = control[0], .events = POLLIN }; if (poll(&fd, 1, 0) != 0) ok = 0; }
        }
        struct pollfd fd = { .fd = control[0], .events = POLLIN }; unsigned char ack = 255;
        if (!ok || poll(&fd, 1, 1000) != 1 || read(control[0], &ack, 1) != 1) ok = 0;
        int valid = expected_resize(bytes, sizeof(bytes));
        if (valid) { expected.ws_col = (unsigned short)(256U * bytes[1] + bytes[2]); expected.ws_row = (unsigned short)(256U * bytes[3] + bytes[4]); }
        struct winsize actual;
        if (ack != (valid ? 0 : 1) || ioctl(master, TIOCGWINSZ, &actual) || actual.ws_col != expected.ws_col || actual.ws_row != expected.ws_row) ok = 0;
        if (!ok) property_failure("stream", i, bytes, sizeof(bytes));
    }
    assert(!shutdown(control[0], SHUT_WR)); assert(!pthread_join(thread, NULL));
    if (truncated >= 0) { struct pollfd fd = { .fd = control[0], .events = POLLIN }; if (poll(&fd, 1, 0) != 0) ok = 0; }
    if (reap(child) != 128 + SIGKILL) ok = 0;
    close(control[0]); close(control[1]); close(master); close(slave);
    return ok;
}
static int property_descriptor_sets(void) {
    for (unsigned int i = 0; i < 32; i++) {
        unsigned int minimums[16]; for (size_t j = 0; j < 16; j++) minimums[j] = next_property_random();
        pid_t child = fork(); assert(child >= 0);
        if (!child) {
            struct rlimit limit; assert(!getrlimit(RLIMIT_NOFILE, &limit));
            unsigned int cap = limit.rlim_cur > 8192 ? 4096 : (unsigned int)(limit.rlim_cur / 2);
            assert(cap >= 16);
            struct stat before[3], after;
            for (int fd = 0; fd < 3; fd++) assert(!fstat(fd, &before[fd]));
            int base = open("/dev/null", O_RDONLY), descriptors[16]; assert(base >= 0);
            for (size_t j = 0; j < 16; j++) { descriptors[j] = fcntl(base, F_DUPFD, (int)(3 + minimums[j] % cap)); assert(descriptors[j] >= 3); }
            limit.rlim_cur = 32; assert(!setrlimit(RLIMIT_NOFILE, &limit));
            if (i % 2 ? close_inherited_proc() : close_inherited()) _exit(1);
            if (fcntl(base, F_GETFD) != -1 || errno != EBADF) _exit(2);
            for (size_t j = 0; j < 16; j++) if (fcntl(descriptors[j], F_GETFD) != -1 || errno != EBADF) _exit(3);
            for (int fd = 0; fd < 3; fd++) if (fstat(fd, &after) || after.st_dev != before[fd].st_dev || after.st_ino != before[fd].st_ino) _exit(4);
            _exit(0);
        }
        if (reap(child)) { property_failure("descriptors", i, minimums, sizeof(minimums)); return 0; }
    }
    return 1;
}
static void run_property_tests(void) {
    printf("PROPERTY seed=%u dimensions=25000 controls=25000 frames=256 descriptor_sets=32\n", PROPERTY_SEED); fflush(stdout);
    check(property_valid_dimensions(), "property: every allowed dimension and leading zeros accepted");
    check(property_dimension_strings(), "property: generated dimensions match independent decimal grammar");
    check(property_control_decoder(), "property: control decoding is bounded and rejection preserves state");
    check(property_control_stream(-1), "property: fragmented valid/invalid requests preserve terminal semantics");
    int truncated = 1; for (int cut = 0; cut < 5; cut++) if (!property_control_stream(cut)) truncated = 0;
    check(truncated, "property: every truncated control frame kills and reaps its owned child without acknowledgement");
    check(property_descriptor_sets(), "property: generated descriptor sets close above a lowered limit and preserve standard streams");
}
#endif
