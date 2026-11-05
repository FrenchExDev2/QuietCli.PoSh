# Objective: Execute CI tools directly without loading the product being built or tested.
if(!(Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts) -and !(Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)){
    $ciUtf8=[Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding=$ciUtf8;[Console]::OutputEncoding=$ciUtf8;$OutputEncoding=$ciUtf8
}
function Invoke-CiProcess {
    <#
    .SYNOPSIS
    Runs an explicit tool with asynchronous stream draining and an owned-process deadline.
    .DESCRIPTION
    Uses only PowerShell and System.Diagnostics. It never discovers or loads QuietCli modules,
    constructs a shell command, retains a full output capture, or retries a failed operation.
    .PARAMETER FilePath
    Native executable resolved as an application, never as a PowerShell alias or function.
    .PARAMETER ArgumentList
    Exact native argument vector.
    .PARAMETER WorkingDirectory
    Explicit working directory, defaulting to the caller's current location.
    .PARAMETER TimeoutSeconds
    Wall-clock deadline; only the owned process tree is terminated.
    .PARAMETER OnOutput
    Optional observer receiving a line record and State. Otherwise output streams to the CI log.
    .PARAMETER State
    Caller-owned progress or metadata state; it is never serialized by this function.
    .PARAMETER InputText
    Optional bounded stdin payload, excluded from returned metadata and logs.
    .PARAMETER MaxRecordChars
    Maximum unterminated record size, independent of total output volume.
    #>
    [CmdletBinding()]param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$ArgumentList=@(),
        [string]$WorkingDirectory=(Get-Location).Path,
        [ValidateRange(1,7200)][int]$TimeoutSeconds=600,
        [scriptblock]$OnOutput,
        $State,
        [AllowEmptyString()][string]$InputText,
        [ValidateRange(1024,1048576)][int]$MaxRecordChars=131072
    )
    $application=Get-Command $FilePath -CommandType Application -ErrorAction Stop|Select-Object -First 1
    $start=[Diagnostics.ProcessStartInfo]::new($application.Source)
    $start.WorkingDirectory=$WorkingDirectory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.RedirectStandardInput=$PSBoundParameters.ContainsKey('InputText')
    if($start.RedirectStandardInput){$start.StandardInputEncoding=[Text.Encoding]::UTF8}
    if($start.RedirectStandardInput -and [Text.Encoding]::UTF8.GetByteCount($InputText) -gt 16384){throw 'CiInputTooLarge'}
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach($argument in $ArgumentList){$start.ArgumentList.Add($argument)}
    $emit={param($stream,$line)
        if($OnOutput){$null=& $OnOutput ([pscustomobject]@{Stream=$stream;Text=$line}) $State}
        elseif($stream -eq 'stderr'){[void][Console]::Error.WriteLineAsync($line).GetAwaiter().GetResult()}
        else{[void][Console]::Out.WriteLineAsync($line).GetAwaiter().GetResult()}
    }
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    $watch=[Diagnostics.Stopwatch]::StartNew();$outcome='Success';$started=$false;$exitCode=-1
    try{
        $started=$process.Start()
        if($start.RedirectStandardInput){
            [void]$process.StandardInput.WriteAsync($InputText).WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
            [void]$process.StandardInput.FlushAsync().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
            $process.StandardInput.Close()
        }
        $readers=@{stdout=$process.StandardOutput;stderr=$process.StandardError}
        $buffers=@{stdout=[char[]]::new(4096);stderr=[char[]]::new(4096)}
        $pending=@{stdout='';stderr=''}
        $tasks=@{stdout=$readers.stdout.ReadAsync($buffers.stdout,0,4096);stderr=$readers.stderr.ReadAsync($buffers.stderr,0,4096)}
        while($tasks.Count){
            if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){if(!$process.HasExited){$process.Kill($true)};$outcome='Timeout';break}
            foreach($stream in @($tasks.Keys)){
                if(!$tasks[$stream].IsCompleted){continue}
                $count=$tasks[$stream].GetAwaiter().GetResult()
                if(!$count){if($pending[$stream].Length){& $emit $stream $pending[$stream]};$tasks.Remove($stream);continue}
                $text=$pending[$stream]+[string]::new($buffers[$stream],0,$count)
                while(($newline=$text.IndexOf("`n",[StringComparison]::Ordinal)) -ge 0){
                    if($newline -gt $MaxRecordChars){throw 'CiRecordTooLarge'}
                    & $emit $stream $text.Substring(0,$newline).TrimEnd("`r")
                    $text=$text.Substring($newline+1)
                }
                if($text.Length -gt $MaxRecordChars){throw 'CiRecordTooLarge'}
                $pending[$stream]=$text
                $tasks[$stream]=$readers[$stream].ReadAsync($buffers[$stream],0,4096)
            }
            if($tasks.Count){[void][Threading.Tasks.Task]::Delay(5).GetAwaiter().GetResult()}
        }
        if(!$process.HasExited){
            try{[void]$process.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(3)).GetAwaiter().GetResult()}
            catch [TimeoutException]{if($outcome -ne 'Timeout'){throw}}
        }
        if($process.HasExited){$exitCode=$process.ExitCode}
        if($exitCode -ne 0 -and $outcome -eq 'Success'){$outcome='Failed'}
        [pscustomobject]@{FilePath=$application.Source;Outcome=$outcome;ExitCode=$exitCode;ElapsedMs=$watch.Elapsed.TotalMilliseconds}
    }finally{if($started -and !$process.HasExited){try{$process.Kill($true)}catch{}};$process.Dispose()}
}
