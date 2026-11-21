# Companion modules

[Back to the QuietCli overview](../README.md)

The `QuietCli` PowerShell module provides Core, the engine foundation. A companion module adds **tested business handlers for one executable** on top of it, so callers get typed results without writing a parser. `quiet` selects a registered handler when you supply no `-Output` and `-Complete` callbacks. Related: [Streaming, callbacks and results](README-streaming.md).

| Module | Role | Status | Docs |
| --- | --- | --- | --- |
| `FrenchExDev2.QuietCli.Core.PoSh` | The `quiet` engine facade: execution, callbacks, delivery, Recall, gains, configuration, agent instructions | See [installation and runtime requirements](../docs/README-PSGallery.md) | [Core README](../src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md) |
| `FrenchExDev2.QuietCli.Git.PoSh` | Git business handlers (for example `git status`) | **Partial qualification** | [Git README](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/README.md), [companion modules overview](../README.md#companion-modules) |
| `FrenchExDev2.QuietCli.Vagrant.PoSh` | `up` and `provision` machine-readable events and per-machine UI lanes | **Partial**; real Vagrant/provider qualification remains open | [Vagrant README](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/README.md) |

Each module has a companion test project (`*.Tests.PoSh`). Use `Get-Command -Module FrenchExDev2.QuietCli.Core.PoSh` to list Core commands and `Get-Help <command> -Full` for command help.

Repository tooling discovers these projects and their test runners through the shared
[workspace catalogue](../docs/README-workspace-projects.md). It also lists explicitly publishable and excluded
packages; test companions and execution modes such as `All` are never public packages.

## Write your own module

`New-QuietModule` generates a business module, an inert catalogue, a handler skeleton and a companion test project. Implement probes, version policy, command selection and analysis from the executable's documentation. The initial companion suite fails until independent business assertions are supplied. Inventory membership alone never establishes semantic support.

Guidelines:

- Keep unsupported variants and version/platform gaps explicit; a missing contract must fail instead of falling back to a guess.
- Keep a handler's parsers caller-local: retain only the business values the result needs.
- Put independent assertions, generated properties, malformed-input fuzzing and mutation catalogues in the companion test project. See [Tests and qualification](README-qualification.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
