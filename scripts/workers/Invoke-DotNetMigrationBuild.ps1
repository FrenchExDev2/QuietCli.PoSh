#requires -Version 7.6
<#
.SYNOPSIS
Executes owned Release-build assessment requests with per-target terminal receipts.
.PARAMETER WorkspaceRoot
Tooling source root.
.PARAMETER RunDirectory
Owned directory containing request.json and progress/log/result artifacts.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Migration.DotNet.psm1') -ErrorAction Stop
$request=Get-Content (Join-Path $RunDirectory 'request.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
if(!$PSCmdlet.ShouldProcess($request.Plan.DotNetRoot,'Execute selected Release builds and save owned evidence')){return}
$report=$request.Plan;$report.Mode='Build'
$selected=@($report.Results | Where-Object Selected)
$projects=@($selected | ForEach-Object {if($_.ItemId){$_.ItemId}else{[IO.Path]::GetFileNameWithoutExtension($_.Path)}} | Sort-Object -Unique)
$state=[ordered]@{Project=($projects -join ', ');Task='.NET migration: Release builds';Workspace=$report.SourceRoot;ProjectDirectory=$report.DotNetRoot;Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Starting';Error=$null;Runs=@()}
if($projects.Count -eq 1){$state.ProjectDirectory=[IO.Path]::GetDirectoryName($selected[0].Path)}
$env:DOTNET_CLI_UI_LANGUAGE='en';$env:DOTNET_CLI_FORCE_UTF8_ENCODING='1';$env:DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE='true'
$deadline=[DateTimeOffset]::UtcNow.AddSeconds([int]$request.TotalTimeoutSeconds-5)
Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
try{
    if((Get-FileHash -LiteralPath $report.PolicyPath).Hash -cne $report.PolicySha256){throw 'DotNetBuildPolicyChanged'}
    $index=0
    foreach($row in $selected){
        $index++;$clock=[Diagnostics.Stopwatch]::StartNew();$started=[DateTimeOffset]::UtcNow
        $run=[pscustomobject]@{Platform=$state.Platform;State='Running';StartedUtc=$started.ToString('o');FinishedUtc=$null;Identity="pwsh:$PID $($row.RelativePath)"}
        $state.Runs=@($run);$state.Case="[$index/$($selected.Count)] $($row.Path)";$row.State='Running'
        Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
        $logPath=Join-Path $RunDirectory ("target-$index.log");$row.LogPath=$logPath
        $writer=$null;$capture=$null
        try{
            if([DateTimeOffset]::UtcNow -gt $deadline){$row.State='NotCompleted';$row.Error='Campaign deadline reached';continue}
            if((Get-FileHash -LiteralPath $row.Path).Hash -cne $row.Sha256){$row.State='Stale';$row.Error='Target changed after discovery';continue}
            $writer=[IO.StreamWriter]::new($logPath,$false,[Text.UTF8Encoding]::new($false));$writer.AutoFlush=$true;$writer.NewLine="`n"
            $capture=@{Row=$row;Writer=$writer;Bytes=0L;Tail=[Collections.Generic.Queue[string]]::new();State=$state;StatusPath=(Join-Path $RunDirectory 'status.json');CapturingSdk=$true;LastHeartbeat=[DateTimeOffset]::UtcNow}
            $observer={param($record,$data)
                $data.Row.OutputLines++
                $text=$record.Text
                if($data.CapturingSdk -and $text.Trim() -match '^\d+\.\d+\.\S+$'){$data.Row.SdkVersion=$text.Trim()}
                $bytes=[Text.Encoding]::UTF8.GetByteCount($text)+1
                if($data.Bytes+$bytes -le 8MB){$data.Writer.WriteLine($text);$data.Bytes+=$bytes}else{$data.Row.LogTruncated=$true}
                if($data.Tail.Count -ge 12){[void]$data.Tail.Dequeue()};$data.Tail.Enqueue($text.Substring(0,[Math]::Min(1024,$text.Length)))
                if(([DateTimeOffset]::UtcNow-$data.LastHeartbeat).TotalSeconds -ge 2){Write-WorkspaceJson $data.StatusPath $data.State;$data.LastHeartbeat=[DateTimeOffset]::UtcNow}
            }
            $sdk=Invoke-CiProcess -FilePath dotnet -ArgumentList @('--version') -WorkingDirectory $row.WorkingDirectory -TimeoutSeconds ([Math]::Min(30,[int]$request.TimeoutSeconds)) -OnOutput $observer -State $capture
            if($sdk.Outcome -ne 'Success'){$row.State=if($sdk.Outcome -eq 'Timeout'){'Timeout'}else{'Failed'};$row.ExitCode=$sdk.ExitCode;$row.Error='SDK resolution failed';continue}
            if(!$row.SdkVersion){$row.State='Failed';$row.Error='SDK version was not observed';continue}
            $row.Executable=$sdk.FilePath;$capture.CapturingSdk=$false
            $remaining=[Math]::Min([int]$request.TimeoutSeconds-$clock.Elapsed.TotalSeconds,($deadline-[DateTimeOffset]::UtcNow).TotalSeconds)
            if($remaining -lt 1){$row.State='Timeout';$row.Error='Target deadline exhausted by SDK resolution';continue}
            $native=Invoke-CiProcess -FilePath dotnet -ArgumentList $row.Arguments -WorkingDirectory $row.WorkingDirectory -TimeoutSeconds ([Math]::Max(1,[int]$remaining)) -OnOutput $observer -State $capture
            $library=Get-Module Migration.DotNet
            $row.State=& $library {param($receipt) Get-DotNetBuildOutcome $receipt} $native
            $row.ExitCode=$native.ExitCode
            if((Get-FileHash -LiteralPath $row.Path).Hash -cne $row.Sha256){$row.State='Stale';$row.Error='Target changed during the build'}
            $row.Diagnostics=$capture.Tail.ToArray()
        }catch{$row.State='Crash';$row.Error=$_.Exception.Message}
        finally{
            if($null -ne $capture){$row.Diagnostics=$capture.Tail.ToArray()}
            if($writer){$writer.Dispose()}
            $row.DurationMs=[Math]::Round($clock.Elapsed.TotalMilliseconds,1);$run.State=$row.State;$run.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
            if($row.State -eq 'Success'){$state.Passed++}else{$state.Failed++}
            Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
            Write-WorkspaceJson $report.ReportPath $report
        }
    }
    $report.Complete=@($selected | Where-Object {$_.State -in @('Planned','Running','NotCompleted')}).Count -eq 0
    $report.Passed=$report.Complete -and $selected.Count -gt 0 -and @($selected | Where-Object State -CNE Success).Count -eq 0 -and !$report.DiscoveryGaps.Count
    $report.State=if($report.Passed){'Success'}elseif(!$report.Complete){'Incomplete'}else{'Failed'}
    $state.State=if($report.Passed){'Success'}else{'Failed'}
}catch{$report.State='Crash';$state.State='Crash';$state.Error=$_.Exception.Message;$state.Failed++}
finally{
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson $report.ReportPath $report
    $sources=@(foreach($path in @($PSCommandPath,(Join-Path $WorkspaceRoot 'scripts/lib/Migration.DotNet.psm1'),(Join-Path $WorkspaceRoot 'scripts/Ci.Process.ps1'))){[pscustomobject]@{Path=$path;Sha256=(Get-FileHash -LiteralPath $path).Hash}})
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;BuildReport=$report;Sources=$sources;Qualification='Release compilation only; no product test or migration acceptance.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
if(!$report.Passed){exit 1}
