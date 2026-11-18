# New-QuietCompanion.ps1

<!-- script-source:begin -->
Source file: [`New-QuietCompanion.ps1`](../../scripts/New-QuietCompanion.ps1)
<!-- script-source:end -->

## Create a companion

~~~powershell
./scripts/New-QuietCompanion.ps1 -Name Packer -LicenseCreditsPath ./packer-credits.md -WhatIf
./scripts/New-QuietCompanion.ps1 -Name Packer -LicenseCreditsPath ./packer-credits.md
~~~

Provide a UTF-8 Markdown file with a level-two heading and links to the native tool's licenses. The executable defaults to the lowercase name. Set `-Executable` to override it, or set `-WorkspaceRoot` to select a different QuietCli checkout.

The script creates `companion/packer` from updated `origin/develop` via [Start-QuietWorkBranch](Start-QuietWorkBranch.md). Use `-GitBranch packer-parser` or `-GitBranch companion/packer-parser` to choose a different branch. For an active `companion/*` branch, use `-NoGitBranch` to skip branch creation. The two options belong to separate parameter sets.

Use `-WithCSharp` to declare a parser project for both supported .NET targets. The generated suite checks local module loading. The generated README records that scope. See the [companion guide](../../README-add-companion.md) for adding handlers and tests.

## Effects and recovery

`-WhatIf` reports the destination and the branch operation before any write or remote access. `-Confirm` covers the complete operation. The generator stages and checks all files before installing them and rejects an existing group or generated workflow contract. If generation fails after the branch is created, fix the cause and retry with `-NoGitBranch`. The work branch and any retained stash remain available. See the [library implementation contract](lib/New-QuietCompanion.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates and registers a new QuietCli companion on a work branch.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
