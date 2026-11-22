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

The package requires `FrenchExDev2.QuietCli.Core.PoSh` with the companion command contract. If import reports `QuietCompanionCommandContractRequired`, update Core and import both modules in a fresh session. [Gallery details](../../../../docs/README-PSGallery.md#companion-packages)

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

The local result also includes entries, upstream state, in-progress operations and a compact `Digest`.
Use `quiet -Watch 200ms git status` at an interactive prompt to monitor the working tree, or
`quiet -WatchOnKeypress git status` to refresh when you press a key. Press Ctrl+C to stop.
[Watch options](../../../Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md#watch-a-command) · [Status details and measured scenarios](../../../../docs/audits/2026-11-14-git-status-states-profiles.md)

## Read a tree and a blob

From a Git working tree with a committed `README.md`, inspect its tree entry and then read the corresponding blob. Choose another committed path by changing `$path`.

<!-- git-example:blob -->
```powershell
$path = 'README.md'
$tree = quiet -AsObject -FilePath git -ArgumentList @('ls-tree', 'HEAD', '--', $path)
[void]$tree.OnFailure({ throw 'Could not read the committed tree' })
if ($tree.Data.Entries.Count -ne 1 -or $tree.Data.Entries[0].Type -cne 'blob') {
    throw 'Expected one committed blob'
}

$blob = quiet -AsObject -FilePath git -ArgumentList @('show', ('HEAD:' + $path))
$artifact = $blob.Data.Artifact
try {
    [void]$blob.OnFailure({ throw 'The blob artifact is incomplete' })
    if (!$artifact.Complete) { throw 'The blob artifact is incomplete' }
    $hash = (Get-FileHash -LiteralPath $artifact.Path -Algorithm SHA256).Hash
    if ($hash -cne $artifact.SHA256) { throw 'Artifact content changed' }
    [pscustomobject]@{ Bytes = $artifact.Bytes; SHA256 = $hash }
} finally {
    if ($artifact) { Remove-QuietGitArtifact -Artifact $artifact }
}
```

`show` returns an owned file with the exact requested output for a blob, including any transformations Git was asked to apply. Keep and release the descriptor in the originating module session. Read or stream the file before release. [Command forms and result fields](../../../../docs/README-git-command-reference.md)

## Coverage and limits

- The version check accepts stable Git `>= 2.40.0` and `< 2.57.0`, including Git for Windows builds.
- `Get-QuietGitCoverage` reports the inventory, implemented handlers and qualification status separately. The [generated command reference](../../../../docs/README-git-command-reference.md) links native forms to their result fields and limitations. Commands or forms without a matching handler require explicit callbacks.
- Handlers for mutations observe local state around one native operation. Their reports describe the changes they can observe.

[Create a handler based on Git](../../../../docs/README-create-git-handler.md) shows how to register and assert one form.

[Git test companion](../../test/FrenchExDev2.QuietCli.Git.Tests.PoSh/README.md) · [Qualification and CI](../../../../readmes/README-qualification-github.md) · [Audit index](../../../../docs/README.md#dated-audits-and-evidence)

## Credits

The QuietCli Git module uses the MIT license. The separately installed Git executable is distributed under GNU GPL v2. [Module license](LICENSE) · [Git license credits](LICENSE_CREDITS.md)

[Third-party notices](THIRD_PARTY_NOTICES.md) record the sources and licenses for material referenced or adapted by this module. [Repository credits](../../../../CREDITS.md#git)
