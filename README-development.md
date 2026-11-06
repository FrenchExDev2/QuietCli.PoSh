# Development

[Back to the QuietCli overview](README.md)

Working from a source checkout. Related: [Tests and qualification](README-qualification.md), [Repository and distribution](README-distribution.md).

The Core development manifest declares **0.2.0-preview** (`ModuleVersion='0.2.0'`, `PSData.Prerelease='preview'`). The sections below describe this source checkout; their features may not be available in earlier published packages. Building or testing does not publish a release.

## Start with the local Core module

From the repository root, use a separate PowerShell Core 7.6+ session and import the local manifest:

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1

# Count received stdout bytes without retaining their content.
$r = quiet -AsObject -C analysis -StdoutMode Bytes -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    if ($event.Stream -eq 'stdout') {
        $runtime.Data.Bytes += $event.ByteCount
    }
} executable arguments

# Inspect execution and source completeness before using the business result.
$r.Outcome
$r.Execution
$r.Completeness

# Produce a bounded delivery and inspect measured volumes.
$json = ConvertTo-QuietJson $r -MaxOutputBytes 4096
Get-QuietCliGain -C analysis
```

Replace `executable arguments` with the intended native command. Facade options precede the executable; native arguments follow it. For an exact argument vector, use `-FilePath` and `-ArgumentList`. Use `-WorkingDirectory` to select the native working directory and `-C` to label the measurement context.

A built module needs no SDK to import or run. Import does not compile C# or start the engine. If binaries are missing or stale, build with `./scripts/Build-Workspace.ps1`, then start a fresh PowerShell process before importing rebuilt assemblies. Build inputs are pinned in `global.json` and the project configuration. Keep modules with overlapping public command names in separate sessions.

See the [Core module README](FrenchExDev2.QuietCli.Core.PoSh/README.md) and [package installation and publication](docs/PSGallery.md) for detailed setup.
