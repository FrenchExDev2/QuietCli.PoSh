# Select-GitHubCiMatrix.ps1

Resolves the selected Core or Git-consumer recipe for all four Linux targets, looks up each fingerprint
in GHCR and verifies its configuration digest, architecture, Linux OS, source and fingerprint labels.
No image is built or published. Missing/inaccessible images select the approved local Docker fallback;
unexpected HTTP errors and invalid identities remain explicit failures.

Standard WhatIf/Confirm guards resolution and output writes. WhatIf returns before registry calls,
selection.json creation or GITHUB_OUTPUT append; the no-effect regression uses an owned absent path.

```powershell
./scripts/Select-GitHubCiMatrix.ps1 -Suite Core -OutputPath $env:GITHUB_OUTPUT
```

Outputs: `container_matrix`, `fallback_matrix`, `has_container`, `has_fallback`. The matrices are
disjoint and cover every target exactly once. An immutable GHCR reference is required for each native
job container. The full decision is saved in `artifacts/github-matrix/selection.json`.
The shared JSON writer creates the receipt's parent directories on a clean checkout; no preceding
workflow preparation step is required. Publication uses a sibling temporary file and atomic rename.
An optional ephemeral registry credential is held only in memory and is never written to the receipt.

The focused companion case `GitHub CI JSON receipts create missing parents and preserve preview
boundaries` runs the real selector for Core/Git/All with offline image adapters. It checks receipt
creation from absent directories, GitHub output append and WhatIf no-write behavior, without GHCR
access. This is filesystem integration evidence, not a hosted-runner or registry qualification.

`-WorkspaceRoot` defaults to the repository. `-Suite` accepts `Core`, `Git` or `All`, defaulting to
`All`. `-OutputPath` defaults to `GITHUB_OUTPUT`; a missing output path is an error.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves verified digests and emits disjoint GitHub container and non-publishing Docker matrices.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
