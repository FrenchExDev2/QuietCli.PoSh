# Development

[Back to the QuietCli overview](README.md) · [Tests and qualification](README-qualification.md) · [Repository and distribution](README-distribution.md)

Prepare a new machine with the [development workstation guide](README-development-workstation.md):
PowerShell bootstrap, the exact .NET SDK, Git, VS Code Stable/Insiders, Podman, wrkflw and native/diagnostic tools
on Windows, Debian, Ubuntu, Alpine and Fedora. Its host-aware installer also offers read-only checks.

The local workflow is **checkout → verify sources → build → fresh PowerShell session → import local manifests → execute → inspect YAML**. The public installed module is `QuietCli`; the source projects retain their internal directory and manifest names.

## Check out, build and run Core

Use PowerShell Core 7.6+, Git and the exact .NET SDK pinned in `global.json` (currently `11.0.100-rc.3.26522.148`). Build before importing the local modules. Close sessions that already loaded this checkout's assemblies before rebuilding.

**1. Check out and build.**

The commands start in a parent directory of your choice and clone the whole monorepo into `$HOME/src/QuietCli`. For an existing checkout, set `$checkout` to its root and skip the clone. Git performs this initial bootstrap before local `quiet` is available; the build script uses the engine-independent process helper.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
New-Item -ItemType Directory -Path (Split-Path $checkout -Parent) -Force | Out-Null
git clone --branch develop https://github.com/FrenchExDev2/QuietCli.PoSh.git $checkout
if ($LASTEXITCODE -ne 0) { throw 'CheckoutFailed' }
Set-Location $checkout
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
```

All paths are relative to the monorepo root. `-Restore` verifies the committed source lock; on an intentionally edited checkout, `./scripts/Initialize-Workspace.ps1` without `-Restore` refreshes the local lock. A successful build creates the compiled engine and companion binaries; it does not publish or install a Gallery package.

**2. Import and run in a fresh session.**

**Open a new PowerShell Core 7.6+ session with its normal profile**, then paste the following block. Reassigning `$checkout` makes the new session independent of variables from the build session.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
Set-Location $checkout
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Get-Alias quiet

$r = quiet -AsObject -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null; Records = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Data.Records++
        }
    } `
    -Complete {
        param($runtime)
        if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version }
    } `
    dotnet --version
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteSdkVersion'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

YAML excerpt; invocation IDs and other envelope metadata are omitted. The version shown is the SDK selected in this checkout. `-Output` reads one native record; `-Complete` creates `{ SdkVersion }`. `-AsObject` keeps that result local, and `Out-QuietResult -AsYaml` formats the same result without executing `dotnet` again.

```yaml
"Outcome": "Success"
"Context": "sdk-version"
"Data":
  "SdkVersion": "11.0.100-rc.3.26522.148"
"Completeness":
  "Source": true
  "Analysis": true
```

The source manifest above loads the local Core project. The public Gallery module is named `QuietCli`; its installation uses `Install-PSResource -Name QuietCli` and `Import-Module QuietCli`.

## Run the Git companion

After the shared build, open a fresh session and follow the [Git quick start](FrenchExDev2.QuietCli.Git.PoSh/README.md#quick-start). It imports both local manifests, defines the repository explicitly and shows the handler's YAML projection.

## Rebuild and validate

A built module needs no SDK to import or run. Source builds need the pinned SDK and the bundled native resources; import does not compile or install dependencies. Keep `engine.hosting` at `Auto` unless a specific host is being qualified. Imports of rebuilt assemblies require a new PowerShell process.

From the checkout root, use `./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild` for a Core development check, `-Suite Git` for the Git companion, or `-Suite All` for both. These launch monitored test runs; qualification boundaries, reports and the release matrix are documented in [tests and qualification](README-qualification.md).

If bundled Linux PTY bridges must be regenerated, read the help for [Build-PtyBridge.ps1](scripts/Build-PtyBridge.ps1): it requires an existing pinned Zig compiler or the explicit `-DownloadCompiler` option. Normal builds verify existing bridges and do not silently install a compiler.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
