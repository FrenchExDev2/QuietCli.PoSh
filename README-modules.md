# Companion modules

[Back to the QuietCli overview](README.md)

Core is the engine. A companion module adds **tested business handlers for one executable** on top of it, so callers get typed results without writing a parser. `quiet` selects a registered handler when you supply no `-Output` and `-Complete` callbacks. Related: [Streaming, callbacks and results](README-streaming.md).

| Module | Role | Status | Docs |
| --- | --- | --- | --- |
| `FrenchExDev2.QuietCli.Core.PoSh` | The `quiet` engine facade: execution, callbacks, delivery, Recall, gains, configuration, agent instructions | `0.2.0-preview` in development | [Core README](FrenchExDev2.QuietCli.Core.PoSh/README.md) |
| `FrenchExDev2.QuietCli.Git.PoSh` | Git business handlers (for example `git status`) | **Under development**; the worked example of a companion module | [Git README](FrenchExDev2.QuietCli.Git.PoSh/README.md), [Git example in the overview](README.md#example-a-companion-module-git-under-development) |

Each module has a companion test project (`*.Tests.PoSh`). `Get-Command -Module FrenchExDev2.QuietCli.Core.PoSh` lists every public command and `Get-Help <command> -Full` documents it.

## Write your own module

`New-QuietModule` generates a business module, an inert catalogue, a handler skeleton and a companion test project. Implement probes, version policy, command selection and analysis from the executable's documentation. The initial companion suite fails until independent business assertions are supplied. Inventory membership alone never establishes semantic support.

Guidelines:

- Keep unsupported variants and version/platform gaps explicit; a missing contract must fail instead of falling back to a guess.
- Keep a handler's parsers caller-local: retain only the business values the result needs.
- Put independent assertions, generated properties, malformed-input fuzzing and mutation catalogues in the companion test project. See [Tests and qualification](README-qualification.md).
