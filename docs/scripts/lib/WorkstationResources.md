# WorkstationResources.psm1

## Purpose

Implements ownership tracking and safe, bounded teardown for temporary Podman containers/images created on behalf of a "development workstation" run, so that cleanup never removes a resource it did not itself create, never force-removes or prunes, and never deletes outside a known report root (even through filesystem reparse points/symlinks). This solves the operational risk of a crashed or interrupted CI/dev-workstation worker leaving containers/images behind, or — worse — a cleanup pass accidentally wiping unrelated Podman resources or files outside its own sandbox. It is dot-sourced indirectly via `scripts/Ci.Process.ps1` and used by `scripts/Remove-DevelopmentWorkstationRun.ps1` and `scripts/lib/DevelopmentWorkstation.psm1` (per grep), with coverage in `FrenchExDev2.QuietCli.Core.Tests.PoSh/WorkstationResources.Tests.ps1` and a smoke test `Invoke-DevelopmentWorkstationSmoke.ps1`.

## Usage

Exported functions:
- `Register-WorkstationRun([string] $RunDirectory, [string] $WorkspaceRoot, $PodmanIdentity)` — creates and persists an initial ownership receipt (`Kind='QuietCli.DevelopmentWorkstation'`, `Owner` = current host/user/PID/process-start-time, `State='Running'`).
- `Add-WorkstationResource([string] $RunDirectory, [ValidateSet('Container','Image')] $Kind, [string] $Name)` — declares a resource *before* creating it; validates `$Name` against `^(localhost/)?quietcli-workstation-[a-z0-9-]+$`, throws `WorkstationResourceNameInvalid` otherwise.
- `Test-WorkstationOwnerActive($Owner)` — `$true` (treated as "protected / do not touch") unless the recorded PID and exact process-start-time can be matched to a currently-running process; defaults to "active"/protected on any ambiguity.
- `Test-WorkstationDirectoryBoundary([string] $Root, [string] $Path)` — rejects a path outside `$Root`, or any reparse point found anywhere along the parent chain up to root, or anywhere inside the subtree being considered.
- `Get-WorkstationCleanupDecision([string] $RunDirectory, [string] $WorkspaceRoot)` — classifies a run as `Unmanaged`, `Protected`, `Active`, or `Inactive`, based on the ownership receipt's internal consistency and the owning process's liveness.
- `Remove-WorkstationOwnedResource($Resource, [switch] $Preview)` — removes one container/image only after re-verifying its name pattern, confirming it still carries the expected `io.frenchexdev.quietcli.workstation.run` label matching this run, and confirming it is not currently in use (running container, or image with live container references). Returns one of `Unverified`, `Absent`, `Foreign`, `InUse`, `Eligible` (when `-Preview`), `Removed`, `InUseOrFailed`.
- `Complete-WorkstationRun([string] $RunDirectory, [string] $State)` — releases every declared resource (re-verifying the Podman engine/store identity first) and writes the terminal receipt.
- `Get-WorkstationPodmanIdentity` / `Test-WorkstationPodmanIdentity($Expected)` — reads/compares the actual Podman engine hostname + storage graph root, so a later default-connection change can't silently point cleanup at a different engine/store than the one that created the resources.

Example:
```powershell
. ./scripts/lib/WorkstationResources.psm1
$identity = Get-WorkstationPodmanIdentity
$receipt = Register-WorkstationRun -RunDirectory $runDir -WorkspaceRoot $workspace -PodmanIdentity $identity
Add-WorkstationResource -RunDirectory $runDir -Kind Container -Name 'quietcli-workstation-abc123'
# ... later ...
Complete-WorkstationRun -RunDirectory $runDir -State 'Succeeded'
```

## Dependencies

- Dot-sources `../Ci.Process.ps1` (line 3) for `Invoke-CiProcess`, the bounded native-process runner used by `Invoke-WorkstationResourceCommand`.
- Shells out to `podman` exclusively (`info`, `container`/`image` `exists`/`inspect`/`rm`, `ps --all --filter ancestor=...`) — always with an explicit, bounded argument vector, never with `Force`/`prune` flags, consistent with the module's stated safety goal.
- Reads/writes `ownership.json` inside each run directory using `ConvertFrom-Json -AsHashtable -DateKind String` / `ConvertTo-Json -Depth 12`.
- Assumes `[Environment]::MachineName`/`UserName`/`PID` and `Get-Process -Id $PID` are available and meaningful (i.e., not running inside some exotic sandboxing where PID reuse across the whole container lifetime is unverifiable another way).

## Side effects

- Writes `ownership.json` (atomically: write to a GUID-suffixed temp file, then `[IO.File]::Move($temporary,$path,$true)`, lines 15-17) inside `$RunDirectory` on every `Register-WorkstationRun`/`Add-WorkstationResource`/`Complete-WorkstationRun` call.
- Removes Podman containers/images (`podman <kind> rm <name>`) during `Complete-WorkstationRun`/`Remove-WorkstationOwnedResource`, but only for resources whose name pattern, ownership label, and non-in-use state all check out.
- `Test-WorkstationDirectoryBoundary` performs a recursive filesystem walk (`EnumerateFileSystemInfos`) to check for reparse points before any caller would act on its `$true` result — read-only itself, but intended to gate a subsequent deletion elsewhere.
- No writes outside the owning run directory except the Podman resource removals themselves.

## Findings

- No bug found in the atomic-write pattern (`Write-WorkstationOwnership`, lines 5-18): temp-file + `Move($force=$true)` is the correct way to avoid a reader observing a partially-written receipt, and it is used consistently by every mutating function in the module.
- CONVENTION: `Write-WorkstationOwnership` (line 16) constructs its own `[Text.UTF8Encoding]::new($false)` inline instead of reusing `RunEncoding.psm1`'s `Write-RunTextFile`/`$script:Utf8Writer`. This duplicates the "UTF-8 without BOM" policy that already exists as a single source of truth elsewhere in the same `scripts/lib/` folder — a DRY violation per AGENTS.md's explicit SOLID/DRY instruction ("avoid duplicated business rules... logic"), and it also means this file does not get the LF-normalization (`ConvertTo-RunLf`) that `Write-RunTextFile` applies, so a receipt written on a code path that somehow introduced `\r\n` (unlikely from `ConvertTo-Json`, but not structurally prevented) would violate the repo's "UTF-8 and LF line endings on disk" rule without any guard here.
- DESIGN: `Test-WorkstationOwnerActive` (lines 56-72) treats *every* ambiguous case — different machine, missing owner/PID/timestamp, or an exception while parsing the recorded start time (line 71, broad `catch{return $true}`) — as "active" (i.e., protected from cleanup). This is a safe default (fail closed), explicitly documented in the synopsis ("foreign or unverifiable ownership stays protected"), so it is not a bug, but the broad `catch` at line 71 swallows the actual parse exception with no logging, which could hide a real bug in the receipt format if it ever starts producing unparseable timestamps silently.
- DESIGN: `Remove-WorkstationOwnedResource` (lines 156-186) does several sequential `Invoke-WorkstationResourceCommand` calls (`exists`, `inspect`, possibly `ps --all --filter ancestor=...`, then `rm`) with no transactional guarantee between them — a container could transition to "running" between the `inspect` check (line 175) and the `rm` call (line 183) in a genuinely concurrent environment. Given this tooling is for single-worker temporary dev workstations (per the module's framing), this TOCTOU window is unlikely to be exploitable in practice, but it is worth noting since the module explicitly cares about safety margins elsewhere (never force/prune).
- Security: `Invoke-WorkstationResourceCommand` (lines 119-130) bounds stdout accumulation to 1 MiB (`throw 'WorkstationResourceMetadataTooLarge'`) — a sensible guard against a compromised/unexpected `podman` response causing unbounded memory growth; no similar bound exists on stderr, but `Invoke-CiProcess`'s own contract (not reviewed here) may already cap that elsewhere.
- Testability: has a dedicated `WorkstationResources.Tests.ps1` and a smoke test (`Invoke-DevelopmentWorkstationSmoke.ps1`); no mutation-test entries for this file were found in `RunProfiles.Mutation.ps1`, which focuses on the run-profile/statistics family — given the safety-critical nature of resource deletion here (wrong boundary = deleting someone else's container), targeted mutation testing of the ownership/label/running-state comparisons in `Remove-WorkstationOwnedResource` and `Get-WorkstationCleanupDecision` would be a meaningful addition per AGENTS.md's mutation-testing mandate for "state/lifecycle logic."

## Verdict

Solid and conscientiously safety-first in design (fail-closed ownership checks, no force/prune, atomic receipt writes, reparse-point rejection); the highest-priority fix is replacing the inline UTF-8 encoding in `Write-WorkstationOwnership` (line 16) with the shared `RunEncoding.psm1::Write-RunTextFile`, both to eliminate the duplicated encoding policy and to pick up its LF normalization for free.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Atomically persists an ownership receipt beside a run's evidence.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
