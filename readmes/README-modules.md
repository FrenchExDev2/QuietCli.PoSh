# Companion modules

[Back to the QuietCli overview](../README.md)

QuietCli Core runs native commands and streams their output. A companion registers reusable business handlers for an executable so callers get structured results without writing a parser. See [handler selection](../docs/README-companion-handler-selection.md) for the effect of explicit callbacks and version constraints.

| Module | Role | Status | Docs |
| --- | --- | --- | --- |
| `FrenchExDev2.QuietCli.Core.PoSh` | The `quiet` engine facade: execution, callbacks, delivery, Recall, gains, configuration, agent instructions | See [installation and runtime requirements](../docs/README-PSGallery.md) | [Core README](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md) |
| `FrenchExDev2.QuietCli.Git.PoSh` | Git business handlers (for example `git status`) | **Partial qualification** | [Git README](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/README.md), [command reference](../docs/README-git-command-reference.md) |
| `FrenchExDev2.QuietCli.Vagrant.PoSh` | `up` and `provision` machine-readable events and per-machine UI lanes | **Partial**; real Vagrant/provider qualification remains open | [Vagrant README](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/README.md) |

## Load a companion and check a result

After [installing the Git companion and Git](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/README.md#installation), run this in a Git working tree.

```powershell
Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
Get-QuietHandler -Binary git | Select-Object Id, VersionRange, Qualification

$result = quiet -AsObject -WorkingDirectory $PWD.Path git status
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
    !$result.Completeness.Analysis -or $result.Error.Count) {
    throw 'Git status failed or its result is incomplete.'
}
$result.Data | Select-Object Branch, Counts
```

`Get-QuietHandler` reads registered metadata without starting a probe. Use the companion's command reference for accepted argument forms and its qualification limits. Inspect [the result envelope](README-streaming.md#anatomy-of-a-result) before using the business data.

## Write your own module

| Where the companion will live | Entry point | Starting point |
| --- | --- | --- |
| Your own project | `New-QuietModule` from installed Core | A business module with `src/Handler.ps1` and a separate `Invoke-ModuleTests` runner that fails until you add assertions. Follow [the standalone Git example](../docs/README-create-git-handler.md#load-the-handler-from-a-standalone-module). |
| The QuietCli monorepo | `./scripts/New-QuietCompanion.ps1` | A group with source and test projects, solution and CI declarations, and a test that checks module loading. Follow [the integration guide](README-add-companion.md). |

- Keep unsupported variants and version/platform gaps explicit; a missing contract must fail instead of falling back to a guess.
- Keep a handler's parsers caller-local: retain only the business values the result needs.
- Put independent assertions, generated properties, malformed-input fuzzing and mutation catalogues in the companion test project. See [the test authoring example](../docs/README-add-companion-tests.md) and [qualification](README-qualification.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
