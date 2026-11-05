# Objectif : Comparer des démarrages indépendants du fuzzer sauvegardé et de programmes témoins ASan.
param([string]$ExpectedRuntimeIdentifier='linux-x64')
$ErrorActionPreference='Stop'
. /source/scripts/Ci.Process.ps1
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='ASan startup comparison';Workspace='/source';ProjectDirectory='/source';Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;ContainerId=$env:QUIETCLI_MUTATION_CONTAINER;ProcessId=$PID;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');Passed=0;Failed=0;Case='Preparing controls';Error=$null}
function Save-ProbeJson {
    <#
    .SYNOPSIS
    Atomically saves the diagnostic's own UTF-8 evidence.
    .PARAMETER Name
    Report filename under the owned output directory.
    .PARAMETER Value
    Explicit diagnostic record.
    #>
    param([string]$Name,$Value)
    $path=Join-Path /evidence $Name
    [void][IO.File]::WriteAllTextAsync(($path+'.tmp'),($Value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [IO.File]::Move(($path+'.tmp'),$path,$true)
}
$entries=[Collections.Generic.List[object]]::new();$groups=[Collections.Generic.List[object]]::new()
Save-ProbeJson status.json $state
try{
    if($state.Platform -cne $ExpectedRuntimeIdentifier){throw 'Diagnostic guest mismatch'}
    $work=Join-Path ([IO.Path]::GetTempPath()) ('asan-startup-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($work)
    $source=Join-Path $work empty.c
    [void][IO.File]::WriteAllTextAsync($source,'int main(void) { return 0; }',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $original=Join-Path $work original-fuzzer;Copy-Item /source/original-fuzzer $original
    [IO.File]::SetUnixFileMode($original,([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute))
    # Objectif : Compiler des témoins vides avec et sans ASan, en PIE et en adresse fixe.
    foreach($case in @(@{Name='plain';Compiler='gcc';Flags=@()},@{Name='asan-pie';Compiler='clang';Flags=@('-fPIE','-pie','-fsanitize=address,undefined')},@{Name='asan-exec';Compiler='clang';Flags=@('-fno-pie','-no-pie','-fsanitize=address,undefined')})){
        $result=Invoke-CiProcess $case.Compiler (@('-O1','-g')+$case.Flags+@($source,'-o',(Join-Path $work $case.Name))) -TimeoutSeconds 60
        if($result.Outcome -ne 'Success'){throw ('Diagnostic compilation failed: '+$case.Name)}
    }
    $programs=@(@{Name='original-fuzzer';Path=$original;Arguments=@('-runs=2','-seed=633419','-rss_limit_mb=512','-detect_leaks=1','-print_final_stats=1')},@{Name='plain';Path=(Join-Path $work plain);Arguments=@()},@{Name='asan-pie';Path=(Join-Path $work asan-pie);Arguments=@()},@{Name='asan-exec';Path=(Join-Path $work asan-exec);Arguments=@()})
    Save-ProbeJson environment.json @{Runtime=$state.Platform;Kernel=[IO.File]::ReadAllTextAsync('/proc/sys/kernel/osrelease',[Text.Encoding]::UTF8).GetAwaiter().GetResult().Trim();MmapRandomBits=[IO.File]::ReadAllTextAsync('/proc/sys/vm/mmap_rnd_bits',[Text.Encoding]::UTF8).GetAwaiter().GetResult().Trim();OriginalSHA256=(Get-FileHash $original).Hash;Scope='Independent startup experiment; never authorizes qualification'}
    # Objectif : Observer 32 démarrages par témoin en gardant tous les codes de sortie et les traces ASan.
    foreach($program in $programs){
        $failed=0;$header=[IO.File]::ReadAllBytesAsync($program.Path).GetAwaiter().GetResult();$elf=[BitConverter]::ToUInt16($header,16)
        for($trial=1;$trial -le 32;$trial++){
            $state.Case=$program.Name+' '+$trial+'/32';Save-ProbeJson status.json $state
            $env:ASAN_OPTIONS='detect_leaks=1:verbosity=1:log_path=/evidence/asan-'+$program.Name+'-'+$trial
            $log=@{Lines=[Collections.Generic.Queue[string]]::new()}
            $result=Invoke-CiProcess $program.Path $program.Arguments -TimeoutSeconds 10 -State $log -OnOutput {param($e,$s)if($s.Lines.Count -ge 8){$null=$s.Lines.Dequeue()};$s.Lines.Enqueue($e.Text)}
            if($result.Outcome -eq 'Success'){$state.Passed++}else{$failed++;$state.Failed++}
            $entries.Add(@{Program=$program.Name;Trial=$trial;Outcome=$result.Outcome;ExitCode=$result.ExitCode;Diagnostics=@($log.Lines)})
        }
        $groups.Add(@{Program=$program.Name;ElfType=$elf;Attempts=32;Failures=$failed})
        Save-ProbeJson attempts.json @($entries);Save-ProbeJson groups.json @($groups)
    }
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Error=$_.ToString();$state.Failed++}
finally{$state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Save-ProbeJson summary.json @{State=$state;Groups=@($groups);Scope='Diagnostic only; all failed starts retained'};Save-ProbeJson status.json $state}
if($state.State -ne 'Success'){exit 1}
