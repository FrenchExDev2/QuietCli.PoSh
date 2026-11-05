/* Coverage-guided target: pure parsers only, without process creation or command execution. */
#define main bridge_main
#include "../../FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c"
#undef main
#include "pty-oracles.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 4096) return 0;
    char text[4097];
    if (size) memcpy(text, data, size);
    text[size] = '\0';
    if (parse_dimension(text) != expected_dimension(text) || !resize_matches(data, size)) abort();
    return 0;
}
