# Export-CiFailureDiagnostics.ps1

Standard WhatIf/Confirm guards creation of the bundle before credentials are read or diagnostics
are copied. WhatIf validates the source/destination shape but creates no output directory.

Creates `artifacts/failure-diagnostics` for a failure-only GitHub Actions artifact. It reads only
named worker/report/image diagnostics under `artifacts`, skips reparse points and staged workspaces,
and never copies `.env`, authfiles, credential stores, native binaries or raw source files.

Before writing, it redacts credential-valued environment variables and their Base64 forms, GitHub
token patterns, Authorization/password assignments and PEM private keys. CI supplies its ephemeral
token solely for redaction. No secret value is printed or included in the manifest.

```powershell
./scripts/Export-CiFailureDiagnostics.ps1
```

`-WorkspaceRoot` defaults to the selected repository. `-OutputDirectory` defaults to
`artifacts/failure-diagnostics` and must not already exist. `-MaxFileBytes` defaults to 1048576 and
accepts 1024 through 2097152 bytes. A reparse-point artifacts root is rejected before export.

Limits: 64 files, 1 MiB per source file, the last 120 lines, 2048 characters per line and 32768
characters per retained file. The manifest distinguishes omitted/oversized/unreadable/truncated
sources. Redacted copies use `.redacted.log`; they are diagnostic text, not parseable JSON evidence.
Suite/terminal JSON is projected to state and at most eight failed cases before redaction, so large
performance arrays cannot displace the useful assertion failures from the retained tail.
The complete original reports remain on the runner and are not uploaded by this exporter.
The generated bundle is separate from qualification evidence and does not indicate qualification.

The allowlist also retains bounded Gallery installation diagnostics; credentials are redacted before export, just as for worker and registry logs.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a bounded, credential-redacted failure bundle from an allowlist of CI report filenames.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
