# AgentDocuments.ps1

## Purpose

Supplies two helper functions used to produce the agent-facing documentation bundle (`AGENTS.md`, `SKILL.md`, `openai.yaml`) that ships inside the public Core package and that backs the Claude Code skill document. It solves the problem of keeping that bundle byte-identical, UTF-8/LF-only, and non-empty whenever it is copied into a staging or distribution directory. It is invoked by `scripts/New-WorkspacePackage.ps1` (line 35, when packaging `FrenchExDev2.QuietCli.Core.PoSh`) and by `scripts/Sync-SkillDocument.ps1` (line 17, when regenerating `docs/agents/SKILL.md` from `docs/agents/AGENTS.md`).

## Usage

This file defines a function library; it has no script-level `param()` block and must be dot-sourced before use.

| Function | Parameter | Type | Mandatory | Default |
|---|---|---|---|---|
| `Copy-QuietProductionAgentDocuments` | `WorkspaceRoot` | `string` | No (no `Mandatory` attribute, no validation) | none |
| `Copy-QuietProductionAgentDocuments` | `ModuleDirectory` | `string` | No (no `Mandatory` attribute, no validation) | none |
| `New-QuietSkillDocumentText` | `AgentsText` | `string` | Yes | none |

```powershell
. ./scripts/AgentDocuments.ps1
Copy-QuietProductionAgentDocuments -WorkspaceRoot (Split-Path $PSScriptRoot -Parent) -ModuleDirectory $stage
```

## Dependencies

- No dot-sourcing of other scripts.
- Uses only `System.IO.File` async APIs (`ReadAllBytesAsync`, `WriteAllBytesAsync`) and `System.IO.Directory.CreateDirectory`.
- Assumes `docs/agents/AGENTS.md`, `docs/agents/SKILL.md`, and `docs/agents/openai.yaml` exist under `WorkspaceRoot` and are already UTF-8/LF.

## Side effects

- Reads the three fixed-name documents under `<WorkspaceRoot>/docs/agents` (line 11-18).
- Creates `<ModuleDirectory>/resources/agents` (line 19).
- Writes the three documents' bytes unmodified into that directory (line 20).

## Findings

- DESIGN: line 10's `param([string]$WorkspaceRoot,[string]$ModuleDirectory)` has no `[Parameter(Mandatory)]` and no path validation on either parameter. An empty or `$null` value flows straight into `Join-Path` and fails with a generic PowerShell error rather than a clear, named one — unlike the throw-with-named-sentinel pattern used two lines later (line 16, `'AgentDocumentMustBeNonemptyUtf8Lf'`).
- The validation throw at line 16 (`throw 'AgentDocumentMustBeNonemptyUtf8Lf'`) does not say *which* of the three documents (`AGENTS.md`, `SKILL.md`, `openai.yaml`) failed the empty/CR check, which makes triage harder than necessary when one of the three is accidentally edited with CRLF line endings.
- Good: both functions correctly use `.GetAwaiter().GetResult()` over async file APIs (lines 14, 20) rather than their synchronous equivalents, in line with the repository's async-preference convention.
- The list of expected filenames (`'AGENTS.md','SKILL.md','openai.yaml'`, line 13) is a hardcoded literal array rather than a shared constant; reasonable for a narrow, stable contract, but it means adding a fourth agent document requires editing this file directly with no compiler-checked single source of truth.
- Testability: exercised by `FrenchExDev2.QuietCli.Core.Tests.PoSh/AgentInstructions.Tests.ps1` (dot-sources this file at line 89 and calls `Copy-QuietProductionAgentDocuments` at line 154), so the happy path has real coverage. No test was found specifically targeting the CRLF/empty-content rejection path (line 16) in isolation.

## Verdict

Fit for purpose: small, correctly uses async I/O, and has a real Pester caller. The single highest-priority fix is adding `[Parameter(Mandatory)]` plus basic validation to both public functions' parameters, and naming the offending file in the `AgentDocumentMustBeNonemptyUtf8Lf` throw.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
