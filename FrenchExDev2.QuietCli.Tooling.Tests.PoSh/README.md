# QuietCli repository tooling tests

This private test companion owns repository automation qualification, independently of the Core product matrix.
It is never published to PowerShell Gallery. Its own manifest declares its runner, complete test metadata and execution policy.

Distribution.Tests separately owns the three complete Core distribution cases. The same tooling job runs them once in an owned Git-absent checkout with verified reused binaries; product matrix rows keep their native RID.

`./scripts/Invoke-WorkspaceCi.ps1 -Suite Tooling -SkipBuild` runs the complete tooling catalogue with the visible local monitor.
Use `-Case '<wildcard>'` for an explicitly partial development run.
Product `All` discovers Core, Git and Vagrant; the CI gate separately requires the tooling workflow when shared sources change.
Private assertion helpers remain in Core.Tests and are invoked in that module's scope; ownership of the literal catalogue belongs here.

Each existing FrenchExDev PowerShell module is an application consumer. It can use Core and the separately generated companion for its executable.
An application module does not become a QuietCli companion merely because it uses QuietCli.
