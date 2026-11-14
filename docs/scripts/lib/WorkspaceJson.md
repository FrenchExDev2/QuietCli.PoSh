# WorkspaceJson.psm1

## Purpose and usage

Exports `Write-WorkspaceJson -Path <file> -Value <metadata>` to publish UTF-8 JSON with LF
line endings through a same-directory temporary file and an atomic replacement. Creates
missing parent directories and removes its owned temporary file on failure.

## Dependencies and effects

Uses PowerShell JSON conversion and System.IO only. Import with `-DisableNameChecking
-ErrorAction Stop`; import defines the function without writing files or initializing a product.
Common re-exports this command; SourceIdentity imports it directly to write build manifests.
This shared dependency avoids a Common/SourceIdentity import cycle.

The function writes only when explicitly invoked. It is an internal writer used by guarded
operations and progress reporters, and delegates preview policy to those callers. It performs
no native execution, network access or automatic business-output capture. Its JSON depth is 32.

## Validation and limits

The Tooling companion checks missing parents, Unicode, relative paths and a blocked-parent
counterexample. Atomic replacement does not promise durable storage after a machine crash.

<!-- script-contract:begin -->
## Execution contract

Purpose: Publishes UTF-8 JSON atomically, creating missing destination directories for reports and monitors.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
