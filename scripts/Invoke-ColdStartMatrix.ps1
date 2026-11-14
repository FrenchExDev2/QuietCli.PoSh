#requires -Version 7.6
<#
.SYNOPSIS
Single entry point: builds the baseline and every requested ReadyToRun candidate, then runs the cold-start A/B
gate on every requested target (Windows locally, Linux distributions in containers), with configurable concurrency.

.DESCRIPTION
Mirrors what .github/workflows/quietcli2-readytorun.yml does across its Windows job and its Linux matrix, but as
one repeatable local command instead of several manual steps. 'windows' runs Invoke-ColdStartGate.ps1 directly on
this machine. Each Linux target builds its own ReadyToRun candidate for that target's runtime identifier, pulls
its already-published test image by locked digest (Get-CiImageForDevelopment.ps1 — never builds one; see that
script's own notes on why building is restricted to a native Linux CI runner), and runs the gate inside it via
Invoke-ContainerColdStart.ps1. Every target's result is informational: an unstable A/A noise floor, an
inconclusive/slower verdict, or one target's outright failure never aborts the others — this command always
finishes and reports what happened per target. Render the combined result afterward with
Show-ColdStartMatrixReport.ps1 (also usable any time on its own, without rerunning anything).

.PARAMETER Targets
Which targets to run. 'windows' only makes sense on a Windows host and is skipped with a warning elsewhere.
Linux targets are container runs and work from any host with a working Podman engine. Mutually exclusive with
-All; omit both to get the full default target list below.

.PARAMETER All
Fills -Targets automatically instead of naming it explicitly: 'windows' plus every Linux distribution
(debian, alpine) for the architecture(s) selected by -Platform (both when -Platform is omitted). Mutually
exclusive with -Targets.

.PARAMETER Platform
Architecture(s) to include when -All fills -Targets ('x64', 'arm' for arm64, or both). Ignored without -All.

.PARAMETER MaxConcurrency
How many Linux container targets run at once. The Windows target (if included) always runs first, by itself,
since it is a local run on the same machine's CPU rather than an isolated container.

.PARAMETER CandidateLabel
Display name of the ReadyToRun candidate forwarded to every target's gate.

.PARAMETER WorkspaceRoot
QuietCli2 root.

.PARAMETER SkipBuild
Skips rebuilding the baseline (./scripts/Build-Workspace.ps1), reusing whatever is already built.

.PARAMETER Headless
Suppresses the per-container visible monitor window; the combined matrix progress is still printed to the host
console as each target finishes. Local test-run policy otherwise opens one window per running container target.

.PARAMETER RegistryToken
Optional GHCR read token forwarded to Get-CiImageForDevelopment.ps1; anonymous pulls are attempted when omitted.
Ignored when -LocalBuild is set.

.PARAMETER LocalBuild
Builds every requested Linux target's image locally with New-CiImage.ps1 (via Podman) instead of pulling an
already-published one with Get-CiImageForDevelopment.ps1. x64 targets build natively on Podman's own Linux
backend; arm64 targets build through Podman's qemu emulation when the host supports it, and simply fail that
one target (without aborting the others) when it does not. Never publishes anything.

.OUTPUTS
One result object per target (Target, State, ReportFile/Error) — also written to
<WorkspaceRoot>/artifacts/coldstart-matrix/<UTC-stamp>.json for later reference.

.EXAMPLE
./scripts/Invoke-ColdStartMatrix.ps1

.EXAMPLE
./scripts/Invoke-ColdStartMatrix.ps1 -Targets debian-x64, alpine-x64 -MaxConcurrency 1 -Headless

.EXAMPLE
./scripts/Invoke-ColdStartMatrix.ps1 -Targets debian-x64, alpine-x64, debian-arm64, alpine-arm64 -LocalBuild -Headless

.EXAMPLE
./scripts/Invoke-ColdStartMatrix.ps1 -All -Platform x64 -LocalBuild -Headless -SkipBuild -MaxConcurrency 4
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('windows', 'debian-x64', 'alpine-x64', 'debian-arm64', 'alpine-arm64')]
    [string[]]$Targets,
    [switch]$All,
    [ValidateSet('x64', 'arm')]
    [string[]]$Platform,
    [ValidateRange(1, 8)][int]$MaxConcurrency = 2,
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'readytorun',
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$SkipBuild,
    [switch]$Headless,
    [AllowEmptyString()][string]$RegistryToken = $env:QUIETCLI_REGISTRY_TOKEN,
    [switch]$LocalBuild
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ColdStartMatrix')){return}
$ErrorActionPreference = 'Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
foreach ($module in 'RunEncoding', 'RunFormat') { Import-Module ([IO.Path]::Combine($PSScriptRoot,"lib/$module.psm1")) -Force -DisableNameChecking }

$linuxTargetMap = @{
    'debian-x64'    = @{ Platform = 'debian'; Rid = 'linux-x64' }
    'alpine-x64'    = @{ Platform = 'alpine'; Rid = 'linux-musl-x64' }
    'debian-arm64'  = @{ Platform = 'debian'; Rid = 'linux-arm64' }
    'alpine-arm64'  = @{ Platform = 'alpine'; Rid = 'linux-musl-arm64' }
}

if ($Targets -and $All) { throw "Specify either -Targets or -All, not both." }
if ($Platform -and -not $All) { throw "-Platform only applies together with -All." }
if ($All) {
    $architectures = if ($Platform) { $Platform | ForEach-Object { if ($_ -eq 'arm') { 'arm64' } else { 'x64' } } } else { @('x64', 'arm64') }
    $Targets = @('windows') + @($linuxTargetMap.Keys | Where-Object { $architectures -contains ($_ -replace '^(debian|alpine)-', '') } | Sort-Object)
}
elseif (-not $Targets) {
    $Targets = @('windows', 'debian-x64', 'alpine-x64', 'debian-arm64', 'alpine-arm64')
}

$candidateRoot = [IO.Path]::Combine(([IO.Path]::GetTempPath()),('quietcli-coldstart-matrix-' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
[void][IO.Directory]::CreateDirectory($candidateRoot)
$results = [Collections.Generic.List[object]]::new()

try {
    if (-not $SkipBuild) {
        Write-Host "Building the baseline (every distribution) ..."
        & ([IO.Path]::Combine($PSScriptRoot,'Build-Workspace.ps1'))
    }

    if ($Targets -contains 'windows') {
        if (-not $IsWindows) {
            Write-Warning "Skipping 'windows': this host is not Windows."
            $results.Add([pscustomobject]@{ Target = 'windows'; State = 'Skipped'; Detail = 'Not a Windows host'; ReportFile = $null })
        }
        else {
            Write-Host "windows: building the ReadyToRun candidate and running the gate locally ..."
            try {
                $candidate = & ([IO.Path]::Combine($PSScriptRoot,'New-ReadyToRunCandidate.ps1')) -CandidateRoot ([IO.Path]::Combine($candidateRoot,'windows')) -WorkspaceRoot $WorkspaceRoot
                & ([IO.Path]::Combine($PSScriptRoot,'Invoke-ColdStartGate.ps1')) -CandidateModule $candidate -CandidateLabel $CandidateLabel -MeasurePackageSize | Out-Host
                $results.Add([pscustomobject]@{ Target = 'windows'; State = 'Ran'; Detail = $null; ReportFile = $null })
            }
            catch {
                Write-Warning "windows target did not complete cleanly: $_"
                $results.Add([pscustomobject]@{ Target = 'windows'; State = 'Failed'; Detail = $_.ToString(); ReportFile = $null })
            }
        }
    }

    $linuxKeys = @($Targets | Where-Object { $linuxTargetMap.ContainsKey($_) })
    if ($linuxKeys.Count -gt 0) {
        Write-Host "Running $($linuxKeys.Count) Linux target(s) with -MaxConcurrency $MaxConcurrency ..."
        $linuxResults = $linuxKeys | ForEach-Object -ThrottleLimit $MaxConcurrency -Parallel {
            $key = $_
            $map = $using:linuxTargetMap
            $target = $map[$key]
            $scriptRoot = $using:PSScriptRoot
            $workspaceRoot = $using:WorkspaceRoot
            $candidateLabel = $using:CandidateLabel
            $headless = $using:Headless
            $registryToken = $using:RegistryToken
            $localBuild = $using:LocalBuild
            $candidateRootPerTarget = [IO.Path]::Combine($using:candidateRoot,$key)
            try {
                $candidate = & ([IO.Path]::Combine($scriptRoot,'New-ReadyToRunCandidate.ps1')) -CandidateRoot $candidateRootPerTarget -WorkspaceRoot $workspaceRoot -RuntimeIdentifier $target.Rid
                $image = if ($localBuild) {
                    & ([IO.Path]::Combine($scriptRoot,'New-CiImage.ps1')) -RuntimeIdentifier $target.Rid -WorkspaceRoot $workspaceRoot
                }
                else {
                    & ([IO.Path]::Combine($scriptRoot,'Get-CiImageForDevelopment.ps1')) -RuntimeIdentifier $target.Rid -WorkspaceRoot $workspaceRoot -RegistryToken $registryToken
                }
                $outcome = & ([IO.Path]::Combine($scriptRoot,'Invoke-ContainerColdStart.ps1')) -WorkspaceRoot $workspaceRoot -Image $image.Image -Platform $target.Platform -CandidateModule $candidate -CandidateLabel $candidateLabel -ExpectedRuntimeIdentifier $target.Rid -Headless:$headless
                [pscustomobject]@{ Target = $key; State = $outcome.State; Detail = $null; ReportFile = $outcome.ReportFile; RunDirectory = $outcome.RunDirectory }
            }
            catch {
                $detail = $_.ToString() + "`n" + $_.ScriptStackTrace + "`n" + $_.Exception.StackTrace
                [pscustomobject]@{ Target = $key; State = 'Failed'; Detail = $detail; ReportFile = $null; RunDirectory = $null }
            }
        }
        foreach ($result in $linuxResults) {
            if ($result.State -in @('Failed', 'Crash', 'Timeout')) { Write-Warning "$($result.Target) did not complete cleanly: $($result.Detail)" }
            $results.Add($result)
        }
    }
}
finally {
    Remove-Item -LiteralPath $candidateRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$matrixDirectory = [IO.Path]::Combine($WorkspaceRoot,'artifacts/coldstart-matrix')
[void][IO.Directory]::CreateDirectory($matrixDirectory)
$matrixPath = [IO.Path]::Combine($matrixDirectory,([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '.json'))
Write-WorkspaceJson $matrixPath @{ Targets = $Targets; Results = @($results) }

''
"Matrix result ($matrixPath):"
Format-RunTable -Headers @('Target', 'State', 'Detail') -Rows @($results | ForEach-Object { , @($_.Target, $_.State, $(if ($_.Detail) { $_.Detail } else { '-' })) })
''
"Render the combined report with: ./scripts/Show-ColdStartMatrixReport.ps1"
$results
