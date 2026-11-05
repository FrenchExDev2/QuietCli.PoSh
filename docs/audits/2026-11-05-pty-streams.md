# PTY stream and LLVM main qualification — 2026-11-05

The POSIX bridge passed the strengthened native qualification on local Linux x64 containers. This pass added no production C changes. Stream regressions exercise exact binary delivery under backpressure, concurrent resize acknowledgements, output-consumer disconnect with child reaping, and signal exit status with an intact output prefix. These checks establish correctness for the exercised cases, not a throughput improvement.

## Results

| Environment | Assertions | Property groups | Fuzz executions | Killed / selected mutants | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Alpine/musl, LLVM main runtimes | 43 | 6 | 20,000 | 31 / 31 | Success |
| Alpine/musl, packaged runtimes | 43 | 6 | 20,000 | 31 / 31 | Success |
| Debian/glibc, Clang 14 compatibility layout | 43 | 6 | 20,000 | 31 / 31 | Success |

All three campaigns reported zero surviving, invalid, timed-out or infrastructure-failed mutants. This score covers the explicit catalogue only. The standalone mandatory-phase guard regression also passed, including rejection of an absent executed-input count. The 58 official libFuzzer/FuzzedDataProvider unit tests passed with the rebuilt LLVM main libraries.

## LLVM provenance

- Source checkout: `C:\code\FrenchExDev\FrenchExDev_i2\LLVM\llvm-project`, branch `main`, commit `3d534989cdf0df35a0570514e03b23587d14fadd`.
- Source mounted read-only; compiler-rt outputs built in the dedicated Linux volume inside Alpine.
- Bootstrap compiler: Alpine Clang 22.1.3. Clang itself was not rebuilt.
- libFuzzer, ASan and UBSan archives came from that source build. Exported runtime manifest and the five required archive SHA-256 values were verified before compiling the fuzz target.
- Qualification image: `localhost/quietcli2-pty-llvm-main:3d534989-x64`, ID `caece5d4f7e7a624869812c3762ef4b25bdfc280eb275424503fe2574c15b4a2`.
- ASan, UBSan and leak detection remained enabled. The main-runtime fuzz executable remained PIE (ELF type 3).
- Main does not include the separate draft RSS-shutdown fix. On musl its internal RSS thread remains disabled with an enforced 1 GiB container memory bound. This does not disable leak detection.
- Native independence receipt: zero product build files, loaded product modules and forbidden AI command calls.

## Retained evidence

Paths below are relative to the QuietCli2 monorepo unless stated otherwise. Reports remain local under ignored artifact directories.

- LLVM-main full qualification: `artifacts/containers/alpine-20261105-080308-9f8024/status.json`; detailed fuzz provenance: `guest/fuzz/report.json` beneath that run.
- Packaged-musl qualification: `artifacts/containers/alpine-20261105-064609-18d0e1/status.json`.
- Glibc qualification: `artifacts/containers/debian-20261105-070006-efab83/status.json`.
- Delivery-guard regression: `artifacts/qualification-guards/c9b44809827c414faeb8bb4c809b8791/summary.json`.
- LLVM export, relative to the workspace: `LLVM/libfuzzer-lab/artifacts/20261105-075826-54a006/runtime/build.json`.
- LLVM unit test output, relative to the workspace: `LLVM/libfuzzer-lab/artifacts/20261105-080442-8d8a84/worker.stdout.log`.

Earlier failed attempts remain preserved. A controlled glibc startup diagnostic reproduced ASan 14 PIE crashes in an empty program; it is distinct from the musl RSS shutdown leak. Only the Clang 14 glibc x64 test executable uses the checked non-PIE compatibility layout; shipped transport binaries retain their hardening requirements.

Local execution here covers Linux x64. ARM64 qualification is configured in the workflow but was not executed on this host. This prepared LLVM-main image is an explicit local test image; default workflow image recipes were not replaced by it. No commit, push or publication was performed by this qualification.
