/* Independent decimal grammar and wire-format expectations shared by test drivers. */
#ifndef QUIETCLI_PTY_ORACLES_H
#define QUIETCLI_PTY_ORACLES_H
#include <stdint.h>

static int expected_dimension(const char *text) {
    size_t length = strlen(text);
    if (!length || strspn(text, "0123456789") != length) return -1;
    char *end; errno = 0;
    unsigned long long value = strtoull(text, &end, 10);
    return errno != ERANGE && !*end && value >= 1 && value <= 1000 ? (int)value : -1;
}
static int expected_resize(const unsigned char *bytes, size_t length) {
    if (length != 5 || bytes[0] != 1) return 0;
    uint32_t columns = ((uint32_t)bytes[1] << 8) | bytes[2];
    uint32_t rows = ((uint32_t)bytes[3] << 8) | bytes[4];
    return columns >= 1 && columns <= 1000 && rows >= 1 && rows <= 1000;
}
static int resize_matches(const unsigned char *bytes, size_t length) {
    struct winsize before = { .ws_row = 17, .ws_col = 23, .ws_xpixel = 11, .ws_ypixel = 13 }, after = before;
    int accepted = decode_resize(bytes, length, &after) == 0;
    if (accepted != expected_resize(bytes, length)) return 0;
    if (!accepted) return !memcmp(&before, &after, sizeof(before));
    return after.ws_col == (unsigned short)(256U * bytes[1] + bytes[2]) &&
        after.ws_row == (unsigned short)(256U * bytes[3] + bytes[4]) && !after.ws_xpixel && !after.ws_ypixel;
}
#endif
