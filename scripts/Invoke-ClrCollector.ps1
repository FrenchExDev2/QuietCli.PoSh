<#
.SYNOPSIS
Collects one pinned EventPipe trace, signals actual recording readiness and retains terminal diagnostics.
.PARAMETER ClrProfilerPath
Pinned dotnet-trace DLL.
.PARAMETER TargetProcessId
Owned PowerShell or engine process to sample.
.PARAMETER OutputPath
NetTrace artifact path.
.PARAMETER ReadyPath
File written only after the collector reports recording.
#>
param([string]$ClrProfilerPath,[int]$TargetProcessId,[string]$OutputPath,[string]$ReadyPath)
$ErrorActionPreference='Stop'
$env:DOTNET_ROLL_FORWARD_TO_PRERELEASE='1'
. (Join-Path $PSScriptRoot 'Common.ps1')
$state=@{Ready=$false;Path=$ReadyPath;Log=[Collections.Generic.List[string]]::new()}
$result=Invoke-CiProcess -FilePath dotnet -ArgumentList @('--roll-forward','LatestMajor',$ClrProfilerPath,'collect','--process-id',[string]$TargetProcessId,'--profile','dotnet-sampled-thread-time','--buffersize','64','--duration','00:00:00:30','--output',$OutputPath) -TimeoutSeconds 90 -State $state -OnOutput {
    param($event,$state)
    if($state.Log.Count -lt 200){$state.Log.Add($event.Text)}
    if($event.Text -match 'Recording trace|Output File\s*:'){
        [void][IO.File]::WriteAllTextAsync($state.Path,'recording',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult();$state.Ready=$true
    }
}
Write-WorkspaceJson ($OutputPath+'.collector.json') @{Execution=$result;Ready=$state.Ready;Log=$state.Log.ToArray()}
if($result.Outcome -ne 'Success' -or !$state.Ready -or !(Test-Path $OutputPath) -or (Get-Item $OutputPath).Length -eq 0){exit 1}
