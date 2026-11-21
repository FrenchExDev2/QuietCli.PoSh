<p align="center">
  <img src="../../../../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli Git

The Git companion gives [QuietCli](../../../../README.md) reusable handlers for commands such as `git status`, `git log` and `git diff`. Scripts and agents can read structured results without writing their own parsers.

**Preview.** Qualification varies by command, version and platform. [Coverage and limits](#coverage-and-limits)

## Installation

Use PowerShell Core 7.6+ and install Git separately. To install a published package from PowerShell Gallery, including previews, run the following in PowerShell.

```powershell
Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Prerelease -Repository PSGallery -Scope CurrentUser
Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
```

The package requires a compatible `FrenchExDev2.QuietCli.Core.PoSh` installation. [Gallery details](../../../../docs/README-PSGallery.md#companion-packages)

For a [built source checkout](../../../../README.md#from-a-source-checkout), open a fresh PowerShell session at the repository root and load both local modules.

```powershell
Import-Module ./src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1 -ErrorAction Stop
```

## Quick start

Run this from a Git working tree to inspect the outcome, branch and change counts.

```powershell
$result = quiet -AsObject git status
$result.Outcome
$result.Data | Select-Object Branch, Counts, AnswerComplete
```

Before basing an automated decision on the result, check `Outcome`, `Completeness`, `Error` and `Data.AnswerComplete`. [Streaming and result contract](../../../../readmes/README-streaming.md)

The local result also includes entries, upstream state, in-progress operations and a compact `Digest`. Use `quiet -UI git status` for a live view. [Status details and measured scenarios](../../../../docs/audits/2026-11-14-git-status-states-profiles.md)

## Coverage and limits

- The version check accepts stable Git `>= 2.40.0` and `< 2.57.0`, including Git for Windows builds.
- `Get-QuietGitCoverage` reports the inventory, implemented handlers and qualification status separately. Commands or forms without a matching handler require explicit callbacks.
- Handlers for mutations observe local state around one native operation. Their reports describe the changes they can observe.

An explicit `git show` of a blob can produce a local artifact. After reading it, release it with `Remove-QuietGitArtifact -Artifact $result.Data.Artifact`, using the result from that `show` call.

[Git test companion](../../test/FrenchExDev2.QuietCli.Git.Tests.PoSh/README.md) · [Qualification and CI](../../../../readmes/README-qualification-when-where-how.md) · [Audit index](../../../../docs/README.md#dated-audits-and-evidence)

## Credits

The QuietCli Git module uses the MIT license. The separately installed Git executable is distributed under GNU GPL v2. [Module license](LICENSE) · [Git license credits](LICENSE_CREDITS.md)

[Third-party notices](THIRD_PARTY_NOTICES.md) record the sources and licenses for material referenced or adapted by this module. [Repository credits](../../../../CREDITS.md#git)
