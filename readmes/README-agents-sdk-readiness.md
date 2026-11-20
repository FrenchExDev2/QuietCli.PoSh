# SDK readiness

`scripts/Test-SdkReadiness.ps1` reports whether the pinned .NET SDK (`global.json`) is current and whether
ReadyToRun (Crossgen2) is actually publishable for every target `Build-Workspace.ps1 -ReadyToRun` would attempt,
**without building, installing or publishing anything**. It exists because `-ReadyToRun` on `Build-Workspace.ps1`
is unverified against the pinned .NET 11 RC SDK's Crossgen2 package availability per RID (see
[docs/README-run-profiles.md](docs/README-run-profiles.md), "ReadyToRun candidate (local A/B)"), and checking that by hand
means cross-referencing `global.json`, `dotnet --list-sdks`/`--list-runtimes` and the NuGet Crossgen2 listing for
six RIDs.

## What it checks

1. **SDK freshness** — the version pinned in `global.json` versus the SDK `dotnet` actually resolves when run
   from the workspace (`dotnet --version`, which honors `rollForward`), versus the latest SDK published for that
   channel (`releases-index.json` from the official .NET release metadata).
2. **Installed runtimes** — `dotnet --list-runtimes`, used to find the local `Microsoft.NETCore.App` version for
   each target framework (`net10.0`, `net11.0`).
3. **Crossgen2 publication** — whether `Microsoft.NETCore.App.Crossgen2.<Rid>` has a NuGet version matching that
   exact local runtime version, for every framework/RID pair `-ReadyToRun` actually publishes:
   - `net10.0` / `-LocalRuntimeIdentifier` (the `lib/inprocess` publication)
   - `net11.0` / each `-RuntimeIdentifier` (every `lib/engine/<rid>` publication)

Each check degrades independently to `Unknown` on failure (missing `dotnet`, no network, unlisted channel) rather
than failing the whole run.

## Output

A single `[pscustomobject]` (`SchemaVersion = 1`), always written to the pipeline:

| Field | Meaning |
|---|---|
| `Sdk.Pinned` | `global.json` version, `RollForward`, `AllowPrerelease`, derived `Channel` (e.g. `11.0`) |
| `Sdk.InstalledSdks` | `dotnet --list-sdks` versions/paths |
| `Sdk.EffectiveVersion` / `EffectiveMatchesPinned` | What `dotnet --version` actually resolves to here, and whether it matches the pin exactly |
| `Sdk.Channel` / `IsPinnedLatestInChannel` | Latest SDK published for the pinned channel, and whether the pin is already that version |
| `ReadyToRun` | One row per framework/RID pair: `LocalRuntimeVersion`, `Crossgen2PackageId`, `Status` (`Published`, `NotPublished`, `RuntimeNotInstalled`, `Unknown`) |
| `Gaps` | Flat list of coded gap strings, e.g. `Crossgen2NotPublished: net11.0/linux-arm64 runtime 11.0.0-rc.3.26522.1` |
| `ReadyToRunFeasible` | `true` only when no row is `NotPublished` or `RuntimeNotInstalled` |

Downstream scripts branch on this object (`$report.Gaps.Count`, `$report.ReadyToRunFeasible`) instead of
re-parsing console text.

## Usage

```powershell
# Scripted: object only, no console output.
$report = ./scripts/Test-SdkReadiness.ps1

# Interactive: also prints a UTF-8 box-drawing summary table.
./scripts/Test-SdkReadiness.ps1

# Also prints the exact command proposed for each gap. Never installs or publishes anything itself.
./scripts/Test-SdkReadiness.ps1 -Update

# Skip every network call (channel lookup, NuGet Crossgen2 listing); those fields come back Unknown.
./scripts/Test-SdkReadiness.ps1 -Offline
```

`-WorkspaceRoot`, `-RuntimeIdentifier` and `-LocalRuntimeIdentifier` default to the same values as
`Build-Workspace.ps1`, so a readiness check and the matching build target the same RIDs without repeating them.

## Known limitations

- Crossgen2 matching is exact-string equality between the locally installed runtime version and a published
  NuGet version. A compatible but differently-numbered build is reported `NotPublished`; this is a conservative
  false negative, never a false positive.
- The network calls are plain, read-only `GET`s to the public .NET release-metadata blob and the NuGet
  flat-container API — not the QuietCli engine, and not subject to its "no automatic network access" rule, which
  governs the engine's own native command execution. `-Offline` exists to skip them entirely when that matters.
- `-Update` only prints proposed commands (SDK install, or "do not enable `-ReadyToRun` for this target yet").
  It never runs `dotnet publish`, an SDK installer, or any other mutating command — consistent with this
  workspace's rule that no install or escalation is performed automatically.
