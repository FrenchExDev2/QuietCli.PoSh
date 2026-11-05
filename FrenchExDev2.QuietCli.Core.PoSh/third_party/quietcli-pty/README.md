# Static Unix transport bridge notices

The Linux x64 bridge is compiled from `src/native/quietcli-pty.c` with GCC and
statically linked with musl. The same static executable is shipped for glibc and
musl x64 runtime identifiers. `resources/transport/<rid>/build.json` records the
source hash, compiler, build options, executable hash and base image identity.
The development build script installs no tools and must run inside its owned
Alpine container.

Upstream notices retained alongside this file:

- `musl-COPYRIGHT.txt`: https://git.musl-libc.org/cgit/musl/plain/COPYRIGHT
- `GCC-RUNTIME-EXCEPTION-3.1.txt`: https://github.com/gcc-mirror/gcc/blob/releases/gcc-16/COPYING.RUNTIME
- `GPL-3.0.txt`: https://github.com/gcc-mirror/gcc/blob/releases/gcc-16/COPYING3

QuietCli's bridge source remains covered by the project's root license.
