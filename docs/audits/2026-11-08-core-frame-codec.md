# Audit 2026-11-08: Core protocol frame codec

Scope: `FrenchExDev2.QuietCli.Core.PoSh/engine/FrameCodec.cs` (new), `Protocol.cs`, `ProtocolClient.cs`, and the engine
test cases in `FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/ProtocolClientCases.cs`.
Roadmap item: wave B point 3 of the Core optimization plan (one write per frame, one shared codec).

## What changed

- `FrameCodec` is the single implementation of the wire layout (two little-endian Int32 lengths, UTF-8 header, binary
  payload): `WriteAsync` (one buffer, one write call), `ParseLengths` (the bounds check) and `ReadBodyAsync`.
- `Protocol` (engine side) and `ProtocolClient` (caller side) call it. Each keeps its own deadlines and its own error
  codes (`ResponseTooLarge`, `InputBlockTooLarge`, `ControlFrameTooLarge`); only the shared layout moved.
- A frame used to reach the pipe in three writes (prefixes, header, payload; the client skipped empty parts). It is now
  one write plus one flush. No performance gain is claimed: it was not measured.

## Launch commands

Run from the repository root (`FrenchExDev2.QuietCli.PoSh`), PowerShell 7.6+, in a visible `pwsh` window.

| Evidence | Command |
|---|---|
| Official gate (includes the engine assertions, expects 67 passed) | `./scripts/Invoke-WorkspaceCi.ps1 -Suite Core` |
| Engine assertions alone, after a build | `dotnet <engine-tests output>/QuietCli.Engine.Tests.dll <native directory>` |
| Only the protocol cases | the same command with `--case "*protocol*"`, then `--case "*frame*"` |

Parameters used in this audit: build of `QuietCli.Engine.Tests.csproj` in Release to a private output directory
(the module's `lib/` was not touched), `QUIETCLI_RECALL_TEST_ROOT` set to a scratch directory, `build-manifest.json`
copied next to the test assembly. The runs went through `quiet` with a visible monitor window. The official gate
`Invoke-WorkspaceCi.ps1 -Suite Core` was **not** run in this audit.

## Results

### Engine assertions

67 passed, 0 failed, 0 skipped (11 s). Two cases are new:

- `each frame reaches the pipe in exactly one write on both sides`: 200 generated frames (payload 0 to 16384 bytes,
  header padded to 3000 bytes), counted on a stream that records write and flush calls; seed `20261109`.
- `length prefixes are accepted exactly inside the protocol bounds`: 2000 prefixes, the first 289 from a
  boundary grid (`int.MinValue`, -1, 0, 1, 2, 1023, 1024, 16384, 16385, 65536, 1048576, 1048577, `int.MaxValue` and
  neighbors) crossed with itself, the rest random; the oracle is written from `protocol.json` bounds, not from the
  implementation; seed `20261110`.

The nine pre-existing protocol cases (round trip, fragmentation, oversize, invalid lengths, truncation, cancellation)
pass unchanged against the shared codec.

A first run without the environment variable and the manifest reported 9 failures (8 Recall cases:
`RecallTestRootRequired`; 1 metadata case: missing `build-manifest.json`). Both are fixture requirements, not codec
defects; the protocol cases passed in that run too.

### Mutation (hand-written, 10 mutants of `FrameCodec.cs`)

| Mutants | Killed | Survived | Crashed | Timeout | Invalid | Score | Duration |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 10 | 0 | 0 | 0 | 0 | 100% | 2m24s |

Mutants: header minimum relaxed, header maximum made exclusive, payload minimum tightened, payload maximum made
exclusive, prefix overlap, payload overwriting the header, last byte not written, written count one short, read prefix
misaligned, prefix size 9. Each ran the full 67-case suite; the source file was restored after the campaign
(checked: original text, LF endings).

## Gaps

1. Throughput and latency were not measured; the single-write change is a correctness and syscall-count property here.
2. The read path still allocates a header and a payload array per frame; pooling is a separate, measured step.
3. The mutants are hand-written and not part of a committed catalogue; the runner lives in the session scratch
   directory. Add them to a committed Core engine mutation catalogue before release qualification.
4. Real two-process behavior (engine standard pipes) is covered only by the existing integration suites, which were
   not run here.
5. `Invoke-WorkspaceCi.ps1 -Suite Core` and the `Integration` suite are still required before publication.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
