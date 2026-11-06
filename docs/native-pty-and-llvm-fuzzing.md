# QuietCli native PTY bridge and LLVM fuzzing findings

This document describes QuietCli's Linux PTY bridge, the tests protecting it, and the LLVM tooling failures investigated during native qualification. Source and retained local evidence were inspected on November 6, 2026. Historical campaign results below describe the November 5 runs; no new campaign was executed for this documentation change.

## Bridge responsibility

[`quietcli-pty.c`](../FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c) provides a generic Unix pseudo-terminal transport. It does not parse executable-specific output or implement business handlers. Windows uses a separate ConPTY implementation.

The bridge accepts a Unix-domain control socket path, initial terminal columns and rows, and an executable argument vector after `--`. Dimensions must contain decimal digits and represent a value from 1 through 1000. Defaults are 120 columns and 40 rows. Invalid startup arguments return 125.

Startup opens a PTY and forks. The child establishes its own session and controlling terminal, maps the slave to stdin/stdout/stderr, closes inherited descriptors, and executes the requested program directly. Executable lookup never falls back to a shell. Empty PATH entries are ignored; an explicit `.` remains supported. An unset PATH uses `/usr/bin:/bin`.

The parent performs three concurrent activities:

| Path | Responsibility | Failure behavior |
| --- | --- | --- |
| Main thread | Forward PTY output to stdout using bounded 32 KiB blocks | Output forwarding failure kills and reaps the child; return 125 |
| Input thread | Forward stdin to the PTY master | On stdin EOF, send the terminal's configured VEOF byte rather than pretending a PTY supports pipe half-close |
| Control thread | Assemble resize frames, apply terminal dimensions and acknowledge them | Control disconnect or acknowledgement-write failure kills the child process group, falling back to the child PID when the group does not yet exist |

PTY output merges the child's stdout and stderr. The transport does not retain a complete output history. `write_all` handles interrupted and partial writes and rejects zero progress. The output reader treats PTY `EIO` as terminal closure. Shutdown cancels and joins forwarding threads, closes descriptors and waits for the child.

SIGTERM, SIGINT and SIGHUP are installed and blocked before fork until the parent publishes the child PID. The child restores default dispositions before execution. Signal forwarding preserves `errno` and targets the child's private group, with a PID fallback before session creation. Normal child exit status is preserved; signal termination maps to `128 + signal`. Executable lookup failures return 127 for a missing path and 126 for other execution failures.

## Resize wire contract

A resize frame contains exactly five bytes:

| Byte | Meaning |
| --- | --- |
| 0 | Opcode 1 |
| 1–2 | Columns, unsigned big-endian |
| 3–4 | Rows, unsigned big-endian |

Both dimensions must be in 1..1000. `decode_resize` validates the entire frame before assigning a new `winsize`, so rejection leaves the destination unchanged. Successful decoding clears pixel dimensions. The control thread supports fragmented reads and successive frames. It returns one byte: 0 after successful decoding and `TIOCSWINSZ`, otherwise 1.

## Test layers and their boundaries

Tests live in the [native companion directory](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/), outside the production module.

- [`pty-tests.c`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-tests.c) exercises parser boundaries, PATH behavior, descriptor closure, signal delivery, startup failure cleanup and real PTY lifecycle behavior. Stream regressions check exact binary delivery under backpressure, responsive resize acknowledgements while output is blocked, consumer disconnect with child reaping, and signal exit status with a preserved output prefix.
- [`pty-properties.h`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-properties.h) supplies generated property groups. Independent expectations in [`pty-oracles.h`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-oracles.h) use separate decimal conversion and wire-format logic, including destination preservation on rejected resize inputs.
- [`pty-fuzz.c`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-fuzz.c) includes the production C source with its entry point renamed. `LLVMFuzzerTestOneInput` invokes only the pure dimension and resize decoders, compares results with the independent oracles and aborts on disagreement. It does not start a child, execute a command or fuzz the complete concurrent transport.
- [`Fuzz.ps1`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Fuzz.ps1) builds the target with libFuzzer, AddressSanitizer and UndefinedBehaviorSanitizer. Its default budget is 20,000 executions, seed 633419, maximum input length 4096 bytes and a two-second per-input timeout. Seed inputs include minimum/maximum dimensions, leading zeros, long digit strings, malformed text, truncated/overlong resize frames and unknown opcodes. Leak detection remains enabled.
- [`Invoke-PtyMutation.ps1`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1) evaluates deliberately changed source against the assertions. Killed mutants establish assertion sensitivity for that catalogue; they are not historical production bugs found by fuzzing.
- [`Hardening.ps1`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Hardening.ps1) inspects the shipped ELF files for static PIE, RELRO, immediate binding and a non-executable stack rather than trusting build flags alone.

The campaign requires an actual executed-input count from libFuzzer's final statistics. A successful launch or requested budget alone is insufficient. Reports retain compiler identity, arguments, seed, corpus hashes, sanitizer settings, target hash and terminal outcome. Optional LLVM runtime exports are checked against their manifest, RID and five archive hashes before compilation.

## Finding 1: libFuzzer RSS-monitor shutdown leak on musl

The PTY qualification investigation exposed a failure in the fuzzing runtime itself. On Alpine 3.24 / musl x86_64 with Clang 22.1.3, an empty fuzz target can complete its requested runs and then fail LeakSanitizer's exit-time check. The observed report contains **56 bytes in two allocations: 8 direct and 48 indirect**, with allocation stacks leading to `StartRssThread`.

The diagnostic control uses a target whose `LLVMFuzzerTestOneInput` immediately returns zero. With `-rss_limit_mb=512`, it reports the leak; with `-rss_limit_mb=0`, the same target exits cleanly while leak detection remains enabled. The failure was also reproduced with unmodified libFuzzer rebuilt from the LLVM checkout and linked with distribution sanitizer runtimes. This isolates the issue from QuietCli's parser and PTY process management.

The original non-Fuchsia implementation detaches an RSS-monitor thread with an endless loop. Normal completion leaves it alive during process teardown, before its C++ thread-support allocations have been released for LeakSanitizer's exit-time check.

### Proposed LLVM correction

[LLVM PR #239109: Stop the RSS monitor before exit-time leak checking](https://github.com/llvm/llvm-project/pull/239109) replaces the detached thread with an owned monitor. A condition variable allows prompt shutdown; an `atexit` handler requests stop, wakes the thread and joins it. PID ownership prevents a forked target from joining a parent-only thread. RSS enforcement remains active during fuzzing; the patch does not suppress leaks or disable sanitizers.

Verified with `gh pr view` on November 6, 2026: the PR is **open, not a draft, and not merged**. Its head is `148f527f3a9a521a96345858adb194c4aa711a7b`. This is a dated status observation, not an assertion of upstream acceptance.

The local patch review records the following validation:

- Four enabled/disabled-RSS reproducer controls pass after the change with ASan, UBSan and leak detection enabled.
- The shutdown regression covers normal exit and exit from a forked target.
- A deliberate **12,345-byte leak** is still detected after monitor shutdown.
- The shutdown regression and existing `fuzzer-oom.test` both pass, preserving RSS-limit enforcement.
- All **58 libFuzzer/FuzzedDataProvider unit tests** pass.

These results cover the recorded local musl x86_64 environment, not the complete LLVM suite or every LLVM platform. Historical patch validation and the current PR head are separate evidence identities; the old results do not automatically qualify later PR edits.

### QuietCli qualification workaround

Until the selected runtime contains the correction, the musl fuzz runner sets `-rss_limit_mb=0` and requires an observable cgroup memory limit of at most **1 GiB**. It retains `-malloc_limit_mb=512`, AddressSanitizer, UndefinedBehaviorSanitizer and `-detect_leaks=1`. Missing external memory bounds fail qualification. This replaces the defective internal monitor with a container bound; it does not establish that the upstream bug has been fixed.

## Finding 2: ASan 14 PIE startup crashes on glibc x64

A separate startup diagnostic reproduced intermittent failures in an empty `int main(void) { return 0; }` program instrumented with ASan/UBSan. This failure therefore does not require a PTY decoder input or libFuzzer target.

The retained controlled experiment ran 32 independent starts for each executable:

| Executable | ELF type | Failed starts / attempts |
| --- | --- | ---: |
| Original fuzzer | PIE, type 3 | 5 / 32 |
| Plain empty program | PIE, type 3 | 0 / 32 |
| ASan/UBSan empty program | PIE, type 3 | 7 / 32 |
| ASan/UBSan empty program | Fixed-address, type 2 | 0 / 32 |

The evidence supports an ASan startup/layout compatibility problem in the tested environment. It does not establish a universal diagnosis for every compiler, kernel or crash. The probe retains kernel and address-randomization metadata, per-attempt outcomes and sanitizer traces.

The compatibility adjustment is deliberately narrow: only a glibc `linux-x64` fuzz executable using Clang 14 and no explicit LLVM runtime export receives `-fno-pie -no-pie`. The runner verifies ELF type 2. Shipped PTY bridges retain their static-PIE hardening requirements. The rebuilt LLVM-main musl fuzz executable remains PIE, type 3. This incident is distinct from the musl RSS-monitor leak and has no claimed fix in PR #239109.

## Recorded native qualification

The [November 5 PTY audit](audits/2026-11-05-pty-streams.md) records the following completed Linux x64 campaigns:

| Environment | Assertions | Property groups | Fuzz executions | Killed / selected mutants |
| --- | ---: | ---: | ---: | ---: |
| Alpine/musl, rebuilt LLVM-main runtimes | 43 | 6 | 20,000 | 31 / 31 |
| Alpine/musl, distribution runtimes | 43 | 6 | 20,000 | 31 / 31 |
| Debian/glibc, Clang 14 compatibility layout | 43 | 6 | 20,000 | 31 / 31 |

The audit records no surviving, invalid, timed-out or infrastructure-failed mutants in those campaigns. It also states that the stream-strengthening pass required no production C changes. These records do not demonstrate a fuzz-discovered defect in the production decoders. They demonstrate successful bounded campaigns plus independently reproduced failures in the testing runtime.

The rebuilt runtime provenance identifies LLVM commit `3d534989cdf0df35a0570514e03b23587d14fadd`, with Alpine Clang as bootstrap compiler. libFuzzer, ASan and UBSan were built from that checkout; Clang itself was not rebuilt. The unpatched main export did not include the separate RSS-shutdown correction.

Local ARM64 execution and a full LLVM-suite run were not established by these results. Fuzzing the decoders does not qualify concurrent stream behavior by itself. The mutation catalogue is finite. Historical counts must not be substituted for the requirements of a later revision.

## Evidence locations and reproduction

Repository-relative links above identify the maintained source and test drivers. The following workspace-relative paths identify retained investigation material; they are local evidence, not downloadable public artifacts:

- `LLVM/libfuzzer-lab/README.md`: laboratory workflow and scope.
- `LLVM/libfuzzer-lab/EmptyTarget.cpp` and `run.sh`: empty-target reproducer and RSS controls.
- `LLVM/libfuzzer-lab/artifacts/review-20261105-060258/PR.md` and `rss-monitor-shutdown.patch`: historical patch proposal and validation record.
- `LLVM/libfuzzer-lab/artifacts/20261105-080442-8d8a84/worker.stdout.log`: inspected unit-test output reporting 58 passed tests.
- `LLVM/libfuzzer-lab/artifacts/20261105-075826-54a006/runtime/build.json`: runtime-export provenance referenced by the audit.

The QuietCli startup diagnostic source is [`audit/Probe-FuzzStartup.ps1`](../FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/audit/Probe-FuzzStartup.ps1). Its inspected results are under `artifacts/pty-fuzz-startup/65e47b5b620545a0a1a2e221a1dc0c5a/run/groups.json`, relative to the QuietCli root. The three historical container-report paths referenced by the November 5 audit were not present at their original locations during this documentation review; the campaign totals above are attributed to that audit rather than presented as revalidated raw reports.

For a new campaign, use the maintained monitored launchers and an existing qualified Linux image. `scripts/Invoke-ContainerCi.ps1` with `-Suite Mutation`, an explicit platform and the expected runtime identifier selects native qualification. The laboratory's `Packaged-Reproducer` isolates the distribution-runtime RSS issue; patched-source `Upstream-Reproducer` and `Focused-Check` require the additional shutdown regression. Do not request those patched-source checks from unpatched main. The lab's full `Check` action is broader than the targeted tests described here.

Follow the repository's visible-monitor and report-location rules for new runs. Preserve failures, seeds, crash artifacts and source/runtime identities. A documentation update does not rebuild the bridge, rerun qualification, publish a package or authorize an upstream change.
