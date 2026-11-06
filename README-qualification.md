# Tests and qualification

[Back to the QuietCli overview](README.md)

How QuietCli is tested and what qualification means. Related: [Development](README-development.md), [Repository and distribution](README-distribution.md), [CI documents](docs/ci/linux-images.md).

Tests belong in companion projects, including independent C# assertions and PowerShell scenarios. Focused Recall tooling provides:

- `Compare-QuietRecallAnalysis`: two analyses with independent states, projected differences, diagnostics, cursor counts, durations and allocations. Delivered events alone do not prove business use; ignored events require an explicit declaration.
- `Export-QuietRecallFixture`: an exact capture and a test skeleton that fails until independent business expectations are written.
- `Reduce-QuietRecall`: a bounded event reducer driven by an explicit failure predicate, preserving failure without claiming global minimality.

From the repository root:

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild

# Focused development campaigns.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Recall -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallMutation -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite RecallLarge -SkipBuild -TimeoutSeconds 1800
```

Local runs start a background worker and a dedicated visible PowerShell monitor. The launcher prints its reopening command; the monitor closes after saving the terminal result. `-Headless` is reserved for CI. Reports default to the system temporary directory under `QuietCli2/<workspace-id>/<category>/<run-id>`, outside the checkout. `-RunDirectory` overrides the location. CI uses its artifact upload paths. Export evidence requiring durable retention before temporary storage is cleared.

Qualification combines examples, generated properties, malformed-input fuzzing and targeted mutation campaigns. Recall covers retention policies, byte identity, mixed streams, fragmented Unicode, references, durable recovery and import integrity. `RecallLarge` uses actual 4 GiB + 1 MiB native output and checks streaming replay, ZIP64 export/import and bounded working memory; it requires twelve GiB of free disk space. Performance measurements separate ordinary streaming, capture, recording, delivery and reanalysis.

The CI matrix covers stable/.NET 10 and preview/.NET 11 hosting, Windows/Linux and x64/ARM64, with explicit native PTY qualification. Configured targets and successful local campaigns do not qualify unexecuted platforms. Missing, failed or incomplete required phases block release qualification. Reports identify the source revision, runtime, architecture, executed scenarios and remaining gaps.
