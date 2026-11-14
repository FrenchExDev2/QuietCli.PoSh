#requires -Version 7.6
<#
.SYNOPSIS
Stages a baseline and a ReadyToRun candidate module into a private, networkless container and runs
Invoke-ColdStartGate.ps1 as the guest entrypoint, then retrieves artifacts/coldstart back to the host.

.DESCRIPTION
Unlike Invoke-ContainerWorker.ps1, this never dispatches a Suite: there is exactly one guest entrypoint
(Invoke-ColdStartGate.ps1) and no test assertions to stage or verify, so this script stays independent of that
hardened, Suite-coupled worker rather than bolting cold-start support onto it. An unstable A/A noise floor or an
inconclusive/slower A/B verdict is never a crash here — same informational policy as the Windows ReadyToRun
workflow (see docs/README-readytorun_profiling.md); only a guest crash, a missing report or an architecture mismatch is.

.PARAMETER WorkspaceRoot
QuietCli2 root; source of 'scripts' and the already-built baseline module.

.PARAMETER RunDirectory
Dedicated host report directory.

.PARAMETER Image
Already prepared platform image; never pulled implicitly.

.PARAMETER Platform
Declared platform label (alpine/debian), verified against the guest's reported runtime identifier.

.PARAMETER CandidateModule
Host path to the already-built ReadyToRun candidate module's .psd1 manifest (see New-ReadyToRunCandidate.ps1).

.PARAMETER CandidateLabel
Display name of the candidate build forwarded to the gate.

.PARAMETER ExpectedRuntimeIdentifier
Required architecture and libc family in the guest.
.PARAMETER ContainerRuntime
Explicit selection overrides the checkout dotenv key; absent configuration uses Podman-first application discovery on Windows and Linux.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][ValidateSet('alpine', 'debian')][string]$Platform,
    [Parameter(Mandatory)][string]$CandidateModule,
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'readytorun',
    [ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
    [AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ContainerColdStartWorker')){return}
$ErrorActionPreference = 'Stop'; Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
$owner = [guid]::NewGuid().ToString('N'); $name = 'quietcli2-coldstart-' + $owner.Substring(0, 12)
$state = @{ Project = 'FrenchExDev2.QuietCli.Core.PoSh'; Task = 'ReadyToRun cold-start report'; Workspace = $WorkspaceRoot; ProjectDirectory = ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh')); Platform = $Platform; State = 'Preparing'; StartedUtc = [DateTimeOffset]::UtcNow.ToString('o'); ProcessId = $PID; ContainerId = $name; Passed = $null; Failed = $null; Case = 'Staging baseline and candidate modules'; FinishedUtc = $null; Error = $null; Image = $Image; Owner = $owner }
$status = [IO.Path]::Combine($RunDirectory,'status.json')
Write-WorkspaceJson $status $state
$created = $false
try {
    $stage = [IO.Path]::Combine($RunDirectory,'workspace'); [void][IO.Directory]::CreateDirectory($stage)
    foreach ($file in Get-ChildItem -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'scripts')) -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath(([IO.Path]::Combine($WorkspaceRoot,'scripts')), $file.FullName)
        $destination = [IO.Path]::Combine(([IO.Path]::Combine($stage,'scripts')),$relative)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    foreach ($file in Get-ChildItem -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh')) -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath(([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh')), $file.FullName)
        if ($relative -match '(^|[\\/])(\.git|bin|obj)[\\/]') { continue }
        $destination = [IO.Path]::Combine(([IO.Path]::Combine($stage,'FrenchExDev2.QuietCli.Core.PoSh')),$relative)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    $candidateRoot = Split-Path -Parent ([IO.Path]::GetFullPath($CandidateModule))
    foreach ($file in Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Force) {
        $relative = [IO.Path]::GetRelativePath($candidateRoot, $file.FullName)
        $destination = [IO.Path]::Combine(([IO.Path]::Combine($stage,'candidate')),$relative)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
    $candidateRelative = [IO.Path]::GetRelativePath($candidateRoot, [IO.Path]::GetFullPath($CandidateModule)).Replace('\', '/')

    $imageState = @{ Id = $null }
    $inspect = Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('image', 'inspect', '--format', '{{.Id}}', $Image) -TimeoutSeconds 20 -State $imageState -OnOutput { param($e, $s) if ($e.Stream -eq 'stdout') { $s.Id = $e.Text.Trim() } }
    if ($inspect.Outcome -ne 'Success' -or $imageState.Id -notmatch '^(sha256:)?[a-f0-9]{64}$') { throw 'PreparedImageIdentityUnavailable' }
    $state.ImageId = $imageState.Id

    $guestArguments = @(
        '-File', '/workspace/scripts/Invoke-ColdStartGate.ps1',
        '-CandidateModule', "/workspace/candidate/$candidateRelative",
        '-CandidateLabel', $CandidateLabel,
        '-BaselineModule', '/workspace/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1',
        '-ArtifactsDirectory', '/workspace/artifacts/coldstart',
        '-MeasurePackageSize'
    )
    $null = Invoke-WorkspaceNative $ContainerRuntime (@('create', '--pull=never', '--name', $name, '--label', ('org.frenchexdev.quietcli2.owner=' + $owner), '--network', 'none', '--entrypoint', 'pwsh', $imageState.Id) + $guestArguments) $WorkspaceRoot -TimeoutSeconds 30
    $created = $true
    $null = Invoke-WorkspaceNative $ContainerRuntime @('cp', ($stage.Replace('\', '/') + '/.'), ($name + ':/workspace')) $WorkspaceRoot -TimeoutSeconds 90
    $state.State = 'Running'; $state.Case = 'Container running; elapsed time is a heartbeat, no test counters apply'; Write-WorkspaceJson $status $state
    $null = Invoke-WorkspaceNative $ContainerRuntime @('start', $name) $WorkspaceRoot -TimeoutSeconds 30
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(900)
    do {
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw [TimeoutException]::new('GuestColdStartDeadlineExceeded') }
        $containerState = @{ Value = '' }
        $inspection = Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('inspect', '--format', '{{.State.Status}}', $name) -TimeoutSeconds 15 -State $containerState -OnOutput { param($e, $s) if ($e.Stream -eq 'stdout') { $s.Value = $e.Text.Trim() } }
        if ($inspection.Outcome -ne 'Success' -or $containerState.Value -in @('exited', 'stopped')) { break }
        Write-WorkspaceJson $status $state
        [void][Threading.Tasks.Task]::Delay(2000).GetAwaiter().GetResult()
    } while ($true)
    $null = Invoke-WorkspaceNative $ContainerRuntime @('cp', ($name + ':/workspace/artifacts/coldstart'), ([IO.Path]::Combine($RunDirectory,'guest'))) $WorkspaceRoot -TimeoutSeconds 60
    $exit = @{ Value = '' }
    $exitInspection = Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('inspect', '--format', '{{.State.ExitCode}}', $name) -TimeoutSeconds 15 -State $exit -OnOutput { param($e, $s) if ($e.Stream -eq 'stdout') { $s.Value = $e.Text.Trim() } }
    if ($exitInspection.Outcome -ne 'Success' -or $exit.Value -notmatch '^-?\d+$') { throw 'GuestExitCodeUnconfirmed' }
    $state.GuestExitCode = [int]$exit.Value
    $guestFiles = @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($RunDirectory,'guest')) -Filter 'ab-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    if ($guestFiles.Count -eq 0) {
        # An unstable A/A noise floor aborts the gate before writing an A/B result; this is a report, not a crash.
        if ($state.GuestExitCode -eq 0) { throw 'GuestColdStartReportMissingAfterCleanExit' }
        $state.State = 'InconclusiveNoiseFloor'; $state.Case = 'A/A control was not conclusive on this container; see guest logs'
    }
    else {
        $report = Get-Content -LiteralPath $guestFiles[0].FullName -Encoding utf8 -Raw | ConvertFrom-Json
        $actualRid = $report.Environment.RuntimeIdentifier
        if ($ExpectedRuntimeIdentifier -and $actualRid -and $actualRid -cne $ExpectedRuntimeIdentifier) { throw 'GuestArchitectureMismatch' }
        $expectedPattern = if ($Platform -eq 'alpine') { '^linux-musl-(x64|arm64)$' } else { '^linux-(x64|arm64)$' }
        if ($actualRid -and $actualRid -cnotmatch $expectedPattern) { throw 'GuestRuntimeDoesNotMatchRequestedPlatform' }
        $state.State = 'Success'; $state.Case = 'Guest cold-start report retained'; $state.ReportFile = $guestFiles[0].Name
    }
}
catch {
    $state.State = 'Crash'; $state.Error = $_.ToString()
    if ($created) {
        $diagnostics = @{ Lines = [Collections.Generic.Queue[object]]::new() }
        try {
            $logs = Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('logs', $name) -TimeoutSeconds 20 -State $diagnostics -OnOutput { param($e, $s) if ($s.Lines.Count -ge 80) { $null = $s.Lines.Dequeue() }; $s.Lines.Enqueue(@{ Stream = $e.Stream; Text = $e.Text }) }
            Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'guest-diagnostics.json')) @{ Outcome = $logs.Outcome; ExitCode = $logs.ExitCode; Lines = @($diagnostics.Lines) }
        }
        catch { Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'guest-diagnostics.json')) @{ Outcome = 'Unavailable'; Error = $_.ToString() } }
    }
}
finally {
    $state.Cleanup = 'NotCreated'
    if ($created) { try { $null = Invoke-WorkspaceNative $ContainerRuntime @('rm', '--force', $name) $WorkspaceRoot -TimeoutSeconds 20; $state.Cleanup = 'RemovedOwnedContainer' } catch { $state.Cleanup = 'Unconfirmed: owned container ' + $name } }
    $state.FinishedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'summary.json')) @{ State = $state }
    Write-WorkspaceJson $status $state
}
if ($state.State -eq 'Crash') { exit 1 }
