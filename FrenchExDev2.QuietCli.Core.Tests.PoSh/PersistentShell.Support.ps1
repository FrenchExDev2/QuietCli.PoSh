function New-QuietGitRepositoryFixture {
    <#
    .SYNOPSIS
    Creates an owned repository; copied from Git.Tests without its module dependency.
    .PARAMETER Root
    Owned fixture directory.
    .PARAMETER Environment
    Isolated Git environment passed to every setup invocation.
    #>
    param([string]$Root,[hashtable]$Environment)
    $path=Join-Path $Root ('repository-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($path)
    Invoke-GitFixture $path @('init','--initial-branch=main') $Environment
    [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"base`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    Invoke-GitFixture $path @('add','file.txt') $Environment
    Invoke-GitFixture $path @('commit','-m','baseline') $Environment
    return $path
}

function Invoke-GitFixture {
    <#
    .SYNOPSIS
    Prepares the copied fixture with explicit Core callbacks, without a Git business handler.
    .PARAMETER Directory
    Owned repository directory.
    .PARAMETER Arguments
    Exact Git argument vector.
    .PARAMETER Environment
    Isolated Git settings.
    #>
    param([string]$Directory,[string[]]$Arguments,[hashtable]$Environment)
    $result=quiet -AsObject -Role Infrastructure -WorkingDirectory $Directory -Environment $Environment -Data @{Diagnostics=[Collections.Generic.Queue[string]]::new()} -Output {
        param($event,$runtime)
        if($runtime.Data.Diagnostics.Count -ge 8){$null=$runtime.Data.Diagnostics.Dequeue()}
        $runtime.Data.Diagnostics.Enqueue($event.Text)
    } -FilePath git -ArgumentList $Arguments
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('PersistentFixtureGitFailed: '+($Arguments -join ' ')+' / '+($result.Error|ConvertTo-Json -Compress)+' / '+($result.Data.Diagnostics.ToArray() -join ' | '))}
}

function Initialize-QuietPersistentConfiguration {
    <#
    .SYNOPSIS
    Creates a complete default configuration with private telemetry and recall destinations.
    .PARAMETER Directory
    New configuration directory owned by this sample.
    .PARAMETER Activate
    Selects the new configuration in the coordinator before its engine starts.
    #>
    param([string]$Directory,[switch]$Activate)
    $previous=[Environment]::GetEnvironmentVariable('QUIETCLI_CONFIG_DIRECTORY')
    $env:QUIETCLI_CONFIG_DIRECTORY=$Directory
    $file=New-QuietCliConfiguration -Confirm:$false
    $text=[IO.File]::ReadAllTextAsync($file.FullName,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $database=ConvertTo-Json (Join-Path $Directory 'gains.sqlite') -Compress
    $recall=ConvertTo-Json (Join-Path $Directory 'recall') -Compress
    $text=[regex]::Replace($text,'(?m)^  database:.*$', [Text.RegularExpressions.MatchEvaluator]{param($match)'  database: '+$database})
    $text=[regex]::Replace($text,'(?m)^  root:.*$', [Text.RegularExpressions.MatchEvaluator]{param($match)'  root: '+$recall})
    [void][IO.File]::WriteAllTextAsync($file.FullName,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    if($Activate){Import-QuietCliConfiguration -Path $file.FullName | Out-Null}
    elseif($null -eq $previous){Remove-Item Env:QUIETCLI_CONFIG_DIRECTORY -ErrorAction SilentlyContinue}
    else{$env:QUIETCLI_CONFIG_DIRECTORY=$previous}
    $file.FullName
}

function Get-QuietPersistentOracle {
    <# .SYNOPSIS
    Predicts porcelain v1 -z bytes from the fixture's literal modified and untracked files.
    #>
    $bytes=[Text.Encoding]::UTF8.GetBytes(" M file.txt`0?? é漢 space.txt`0")
    [pscustomobject]@{Bytes=$bytes.Length;Records=2;SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}

function Assert-QuietPersistentResult {
    <#
    .SYNOPSIS
    Checks independent content, native completion and successful callback finalization.
    .PARAMETER Result
    Core result envelope.
    .PARAMETER Oracle
    Expected fixture content summary.
    #>
    param($Result,$Oracle)
    Set-StrictMode -Version Latest
    if($Result.Outcome -cne 'Success' -or $Result.Execution.Native.ExitCode -ne 0 -or $Result.Error.Count){throw 'PersistentResultExecution'}
    if(!$Result.Completeness.Source -or !$Result.Completeness.Analysis){throw 'PersistentResultIncomplete'}
    if($Result.Data.Bytes -ne $Oracle.Bytes -or $Result.Data.Records -ne $Oracle.Records -or $Result.Data.SHA256 -cne $Oracle.SHA256 -or $Result.Data.CompleteCalls -ne 1){throw 'PersistentResultContent'}
    if($Result.Execution.Native.StdoutBytesRead -ne $Oracle.Bytes -or $Result.Execution.Native.StderrBytesRead -ne 0){throw 'PersistentResultVolumes'}
}

function Invoke-QuietPersistentStatus {
    <#
    .SYNOPSIS
    Counts and hashes Git machine output through dedicated Output and Complete callbacks.
    .PARAMETER Repository
    Immutable owned fixture repository.
    #>
    param([string]$Repository)
    $data=@{Bytes=0L;Records=0;CompleteCalls=0;Hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)}
    try{
        $result=quiet -AsObject -C persistent-status -WorkingDirectory $Repository -StdoutMode Bytes -Data $data -Output {
            param($event,$runtime)
            if($event.Stream -eq 'stdout'){
                $runtime.Data.Bytes+=$event.ByteCount
                $runtime.Data.Hash.AppendData($event.Bytes)
                foreach($value in $event.Bytes){if($value -eq 0){$runtime.Data.Records++}}
            }
        } -Complete {
            param($runtime)
            $runtime.Data.CompleteCalls++
            [pscustomobject]@{Bytes=$runtime.Data.Bytes;Records=$runtime.Data.Records;CompleteCalls=$runtime.Data.CompleteCalls;SHA256=[Convert]::ToHexString($runtime.Data.Hash.GetHashAndReset())}
        } -FilePath git -ArgumentList @('-c','core.quotepath=false','status','--porcelain=v1','-z','--untracked-files=all')
        Assert-QuietPersistentResult $result (Get-QuietPersistentOracle)
        return $result
    }finally{$data.Hash.Dispose()}
}

function Assert-QuietPersistentFrame {
    <#
    .SYNOPSIS
    Rejects missing, reordered or corrupt process/session evidence before retaining timings.
    .PARAMETER Frame
    Parsed child response.
    .PARAMETER Index
    One-based expected response number.
    .PARAMETER Token
    Expected session identity.
    .PARAMETER ProcessId
    Expected child PID.
    .PARAMETER Mode
    Execute or Retain workload.
    #>
    param($Frame,[int]$Index,[string]$Token,[int]$ProcessId,[string]$Mode)
    Set-StrictMode -Version Latest
    if($Frame.Kind -cne 'Sample' -or $Frame.Index -ne $Index -or $Frame.Token -cne $Token -or $Frame.ProcessId -ne $ProcessId -or !$Frame.SameReference){throw 'PersistentFrameIdentity'}
    $expected=if($Mode -eq 'Retain'){1}else{$Index}
    if($Frame.NativeExecutions -ne $expected){throw 'PersistentFrameExecutions'}
    foreach($field in @('CommandMs','DeliveryBytes','WorkingSetBytes','PrivateBytes')){
        if($null -eq $Frame.$field -or ![double]::IsFinite([double]$Frame.$field) -or [double]$Frame.$field -lt 0){throw 'PersistentFrameMeasurement'}
    }
    $oracle=Get-QuietPersistentOracle
    if($Frame.Bytes -ne $oracle.Bytes -or $Frame.Records -ne $oracle.Records -or $Frame.SHA256 -cne $oracle.SHA256){throw 'PersistentFrameContent'}
}
