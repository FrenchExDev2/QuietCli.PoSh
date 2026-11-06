# Repository and distribution

[Back to the QuietCli overview](README.md)

Related: [Development](README-development.md), [Tests and qualification](README-qualification.md), [package installation](docs/PSGallery.md).

The [public repository](https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh) has one root checkout. Open `QuietCli2.code-workspace` in VS Code. Shared scripts own build, package verification and dependency-aware CI; modules retain their declared package boundaries. Builds and tests do not commit, push or publish.

`New-WorkspacePackage.ps1` creates module archives and SHA-256 manifests. `Test-WorkspacePackage.ps1` verifies paths, sizes, hashes and manifests before extraction; `-TestImport` explicitly enables execution of verified package code. File integrity is distinct from author authentication. Gallery publication is manually dispatched and requires qualification of the exact delivered revision.

For repository commands, dependency rules and publication gates, read [AGENTS.md](AGENTS.md). For API details, use installed command help, the [Core README](FrenchExDev2.QuietCli.Core.PoSh/README.md) and the [Recall documentation](docs/recall.md). For agent usage documents, see the [agent documents index](docs/agents/README.md).
