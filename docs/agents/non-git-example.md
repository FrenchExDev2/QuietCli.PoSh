# Analyzing a non-Git executable

`AGENTS.md` uses Git for every example. QuietCli itself is not tied to Git: without a registered
handler, supply `-Output` and `-Complete` callbacks and the engine runs the command directly.

This example inventories the installed .NET SDKs with `dotnet --list-sdks`. Its output was read
from `dotnet --list-sdks` before writing the parser: one record per line, `<version> [<sdk root>]`.
Read the help or official documentation of any other executable before adapting the parser.

```powershell
# Objective: List the installed .NET SDKs as typed objects.
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$workingDirectory = (Get-Location).Path
$sdkOutput = {
    param($event, $runtime)
    if ($event.Stream -ne 'stdout') { return }
    $match = [regex]::Match($event.Text.TrimEnd([char[]]"`r`n"), '^(?<version>\S+) \[(?<path>.+)\]$')
    if (!$match.Success) { throw 'InvalidDotnetSdkRecord' }
    [void]$runtime.Data.Sdks.Add([pscustomobject]@{ Version = $match.Groups['version'].Value; Root = $match.Groups['path'].Value })
}
$sdkComplete = {
    param($runtime)
    [pscustomobject]@{ InstalledSdks = $runtime.Data.Sdks.Count; Sdks = $runtime.Data.Sdks.ToArray() }
}
$sdks = quiet -AsObject -C sdk-inventory -WorkingDirectory $workingDirectory -RecordDelimiter "`n" -Data @{ Sdks = [Collections.Generic.List[object]]::new() } -Output $sdkOutput -Complete $sdkComplete -FilePath dotnet -ArgumentList @('--list-sdks')
if ($sdks.Outcome -ne 'Success' -or !$sdks.Completeness.Source -or !$sdks.Completeness.Analysis -or $sdks.Error.Count) {
    FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $sdks -MaxItems 5 -MaxOutputBytes 4096
    throw 'DotnetSdkInventoryIncomplete'
}
FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $sdks -MaxItems 5 -MaxOutputBytes 4096
```

Verified on this repository's local module: the call returns `Outcome` `Success` with both
`Completeness` flags true, no errors, and a `Data.Sdks` array. The SDK list is machine-specific.

## What this example shows

- **Direct execution needs both callbacks.** `-Output` accumulates records in `runtime.Data`;
  `-Complete` returns the single business object.
- **Fail on unrecognized records.** The parser throws on a line that does not match, instead of
  skipping it. A skipped line would silently produce an incomplete inventory.
- **A parser covers one format.** This one covers `--list-sdks` only. It does not parse
  `dotnet --info` or any human-readable output.
- **The business scope is the machine's installed SDKs**, not a statement about which SDK a given
  project uses (`global.json` decides that).

## What this example is not

It is not an automated test: `AgentInstructions.Tests.ps1` runs only the `quiet-example` blocks of
`AGENTS.md` and `examples.md`. If this parser becomes reusable, it belongs in a companion business module with its own
independently asserted tests, as the project rules require.
