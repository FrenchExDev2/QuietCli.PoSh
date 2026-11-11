#requires -Version 7.6
<#
.SYNOPSIS
Launches Invoke-ContainerColdStartWorker.ps1 in the background with a visible monitor, local only.

.PARAMETER WorkspaceRoot
QuietCli2 root.

.PARAMETER Image
Prepared local image containing PowerShell and .NET 11 RC (see New-CiImage.ps1).

.PARAMETER Platform
Platform label for the monitor and runtime-identifier check.

.PARAMETER CandidateModule
Host path to the already-built ReadyToRun candidate module's .psd1 manifest (see New-ReadyToRunCandidate.ps1).

.PARAMETER CandidateLabel
Display name of the candidate build forwarded to the gate.

.PARAMETER ExpectedRuntimeIdentifier
Required guest RID.

.PARAMETER Headless
CI-only mode without a desktop window.
.PARAMETER ContainerRuntime
Explicit selection overrides the checkout dotenv key; absent configuration uses Podman-first application discovery on Windows and Linux.

.PARAMETER TimeoutSeconds
Maximum worker duration, including staging and cleanup.

.EXAMPLE
./scripts/Invoke-ContainerColdStart.ps1 -Image $image.Image -Platform debian -CandidateModule $candidate -ExpectedRuntimeIdentifier linux-x64 -Headless
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][ValidateSet('alpine', 'debian')][string]$Platform,
    [Parameter(Mandatory)][string]$CandidateModule,
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'readytorun',
    [ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
    [switch]$Headless,
    [AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime,
    [ValidateRange(1, 7200)][int]$TimeoutSeconds = 1200
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ContainerColdStart')){return}
$ErrorActionPreference = 'Stop'; . (Join-Path $PSScriptRoot 'Common.ps1')
$ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
$run = Join-Path (Get-QuietReportRoot $WorkspaceRoot 'coldstart-containers') ($Platform + '-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
[void][IO.Directory]::CreateDirectory($run)
$runner = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$arguments = @('-File', (ConvertTo-CiArgument ((Join-Path $PSScriptRoot 'Invoke-ContainerColdStartWorker.ps1'))), '-WorkspaceRoot', (ConvertTo-CiArgument ($WorkspaceRoot)), '-RunDirectory', (ConvertTo-CiArgument ($run)), '-Image', (ConvertTo-CiArgument ($Image)), '-Platform', $Platform, '-CandidateModule', (ConvertTo-CiArgument ($CandidateModule)), '-CandidateLabel', (ConvertTo-CiArgument ($CandidateLabel)))
if ($ExpectedRuntimeIdentifier) { $arguments += @('-ExpectedRuntimeIdentifier', $ExpectedRuntimeIdentifier) }
$arguments+=@('-ContainerRuntime',$ContainerRuntime)
$options = @{ FilePath = $runner; ArgumentList = $arguments; PassThru = $true; RedirectStandardOutput = (Join-Path $run 'worker.stdout.log'); RedirectStandardError = (Join-Path $run 'worker.stderr.log') }; if ($IsWindows) { $options.WindowStyle = 'Hidden' }
if (!$Headless -and !$IsWindows) { throw 'A local visible monitor requires the Windows host launcher.' }
$worker = Start-Process @options
$monitor = $null
if (!$Headless) { $monitorPath = Join-Path $PSScriptRoot 'Watch-Tests.ps1'; $monitor = Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File', (ConvertTo-CiArgument ($monitorPath)), '-RunDirectory', (ConvertTo-CiArgument ($run))) -PassThru; "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$run`"" }
$summary = Wait-WorkspaceWorker -Worker $worker -RunDirectory $run -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
[pscustomobject]@{ State = $summary.State.State; Platform = $summary.State.Platform; RunDirectory = $run; ReportFile = $summary.State.ReportFile }
if ($summary.State.State -eq 'Crash' -or $summary.State.State -eq 'Timeout') { throw "Container cold-start report did not complete: $run" }
