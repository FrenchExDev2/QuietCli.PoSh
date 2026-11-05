# Objectif : Amorcer les outils documentés du workspace lorsque DevPoSh/pump n’est pas installé, notamment en CI.
if(!(Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts) -and !(Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)){
    $bootstrapUtf8=[Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding=$bootstrapUtf8;[Console]::OutputEncoding=$bootstrapUtf8;$OutputEncoding=$bootstrapUtf8
}
if(!(Get-Command pump -ErrorAction SilentlyContinue)){
    function script:pump {
        <#
.SYNOPSIS
Minimal bootstrap for explicit tool contracts; never captures raw output or imports V1.
        .DESCRIPTION
        Accepts AsObject, WorkingDirectory, State, OnOutput, Complete, TimeoutSeconds and bounded InputText before the executable. InputText is sent through stdin and never included in the delivery. Restricted to documented workspace tools dotnet, git, podman, gh, pwsh, rg and zig.
        #>
        $options=@{WorkingDirectory=(Get-Location).Path;TimeoutSeconds=600;State=@{}};$position=0
        while($position -lt $args.Count -and [string]$args[$position] -like '-*'){
            $name=([string]$args[$position]).TrimStart('-');$position++
            if($name -eq 'AsObject'){continue}
            if($name -notin @('WorkingDirectory','State','OnOutput','Complete','TimeoutSeconds','InputText')){throw "UnsupportedBootstrapOption: $name"}
            if($position -ge $args.Count){throw 'MissingBootstrapOptionValue'}
            $options[$name]=$args[$position];$position++
        }
        if(!$options.ContainsKey('OnOutput') -or !$options.ContainsKey('Complete')){throw 'ExplicitBootstrapContractRequired'}
        $binary=[string]$args[$position];$position++
        if([IO.Path]::GetFileNameWithoutExtension($binary) -notin @('dotnet','git','podman','gh','pwsh','rg','zig')){throw 'UnsupportedBootstrapExecutable'}
        $application=Get-Command $binary -CommandType Application -ErrorAction Stop|Select-Object -First 1
        $start=[Diagnostics.ProcessStartInfo]::new($application.Source)
        $start.WorkingDirectory=$options.WorkingDirectory;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.RedirectStandardInput=$options.ContainsKey('InputText')
        if($start.RedirectStandardInput -and [Text.Encoding]::UTF8.GetByteCount([string]$options.InputText) -gt 16384){throw 'BootstrapInputTooLarge'}
        $start.StandardOutputEncoding=[Text.Encoding]::UTF8;$start.StandardErrorEncoding=[Text.Encoding]::UTF8
        for(;$position -lt $args.Count;$position++){foreach($argument in @($args[$position])){$start.ArgumentList.Add([string]$argument)}}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$start;$watch=[Diagnostics.Stopwatch]::StartNew();$outcome='Success';$started=$false
        try{
            $started=$process.Start()
            if($start.RedirectStandardInput){
                [void]$process.StandardInput.WriteAsync([string]$options.InputText).WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
                [void]$process.StandardInput.FlushAsync().WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
                $process.StandardInput.Close()
            }
            $readers=@{stdout=$process.StandardOutput;stderr=$process.StandardError}
            $buffers=@{stdout=[char[]]::new(4096);stderr=[char[]]::new(4096)}
            $pending=@{stdout='';stderr=''}
            $tasks=@{stdout=$readers.stdout.ReadAsync($buffers.stdout,0,4096);stderr=$readers.stderr.ReadAsync($buffers.stderr,0,4096)}
            while($tasks.Count){
                if($watch.Elapsed.TotalSeconds -gt $options.TimeoutSeconds){if(!$process.HasExited){$process.Kill($true)};$outcome='Timeout';break}
                foreach($stream in @($tasks.Keys)){
                    if(!$tasks[$stream].IsCompleted){continue}
                    $count=$tasks[$stream].GetAwaiter().GetResult()
                    if($count -eq 0){
                        if($pending[$stream].Length){$null=& $options.OnOutput ([pscustomobject]@{Stream=$stream;Text=$pending[$stream]}) $options.State}
                        $pending[$stream]='';$tasks.Remove($stream);continue
                    }
                    $text=$pending[$stream]+[string]::new($buffers[$stream],0,$count)
                    while(($newline=$text.IndexOf("`n",[StringComparison]::Ordinal)) -ge 0){
                        if($newline -gt 8192){throw 'BootstrapRecordTooLarge'}
                        $line=$text.Substring(0,$newline).TrimEnd("`r")
                        $null=& $options.OnOutput ([pscustomobject]@{Stream=$stream;Text=$line}) $options.State
                        $text=$text.Substring($newline+1)
                    }
                    if($text.Length -gt 8192){throw 'BootstrapRecordTooLarge'}
                    $pending[$stream]=$text
                    $tasks[$stream]=$readers[$stream].ReadAsync($buffers[$stream],0,4096)
                }
                if($tasks.Count){[void][Threading.Tasks.Task]::Delay(5).GetAwaiter().GetResult()}
            }
            if(!$process.HasExited){[void]$process.WaitForExitAsync().WaitAsync([TimeSpan]::FromSeconds(3)).GetAwaiter().GetResult()}
            if($process.ExitCode -ne 0 -and $outcome -eq 'Success'){$outcome='Failed'}
            $data=& $options.Complete $options.State $null
            [pscustomobject]@{Outcome=$outcome;Data=$data;Execution=@{ExitCode=$process.ExitCode;ElapsedMs=$watch.Elapsed.TotalMilliseconds}}
        }finally{if($started -and !$process.HasExited){try{$process.Kill($true)}catch{}};$process.Dispose()}
    }
}
if(!(Get-Command Out-QuietResult -ErrorAction SilentlyContinue)){
    function script:Out-QuietResult {
        <#
.SYNOPSIS
Delivers only the small bootstrap result, which has no capture or internal fields.
        .PARAMETER InputObject
        Bootstrap result.
        .PARAMETER MaxOutputBytes
        Accepted for the same administrative call shape as installed pump.
        #>
        [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,[int]$MaxOutputBytes=6000)
        process{$text=ConvertTo-Json -InputObject $InputObject -Depth 8 -Compress;if([Text.Encoding]::UTF8.GetByteCount($text) -gt $MaxOutputBytes){$text=ConvertTo-Json -InputObject @{Outcome=$InputObject.Outcome;Execution=$InputObject.Execution;Diagnostics='See tool failure.'} -Compress};$text}
    }
}
