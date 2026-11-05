# Objectif : Exécuter des mutations C ciblées sans modifier les sources et conserver chaque résultat.
#requires -Version 7.6
<#
.SYNOPSIS
Runs a baseline and an explicit, source-checked native PTY mutation catalogue.
.DESCRIPTION
This targeted campaign is not exhaustive operator or line coverage. GCC uses documented
compile/link options (https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html).
Invalid mutants and timeouts never count as kills. Any survivor or incomplete run fails CI.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER CompilerPath
Existing GCC on Linux or the pinned Zig compiler on Windows. No compiler is installed.
.PARAMETER Image
Existing Linux x64 image used only by the Windows launcher, without pulling or network access.
.PARAMETER RunDirectory
Private output directory; generated when omitted.
.PARAMETER Headless
CI mode without a desktop monitoring window.
.PARAMETER Worker
Internal background worker mode.
.PARAMETER ExpectedRuntimeIdentifier
Required native Linux architecture and libc; rejects a mismatched guest before compilation.
.PARAMETER RequireFuzz
Requires coverage-guided decoder fuzzing with ASan/UBSan, as in every Linux CI job.
.PARAMETER FuzzRuns
Required libFuzzer execution count for the original source.
#>
[CmdletBinding()]param(
    [string]$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$CompilerPath,
    [string]$Image='localhost/quietcli2-debian-net11:2.56.0',
    [string]$RunDirectory,
    [ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
    [switch]$RequireFuzz,
    [ValidateRange(1000,10000000)][int]$FuzzRuns=20000,
    [switch]$Headless,
    [switch]$Worker
)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
if(!$Worker){
    if(!$Headless -and !$IsWindows){throw 'Use the Windows host launcher for a visible local monitor.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'pty-mutation') ([guid]::NewGuid().ToString('N'))}
    $RunDirectory=[IO.Path]::GetFullPath($RunDirectory,$PWD.Path)
    if(Test-Path $RunDirectory){throw 'MutationRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $runner=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
    $arguments=@('-File',('"'+$PSCommandPath+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$RunDirectory+'"'),'-Image',$Image,'-Worker')
    if($CompilerPath){$arguments+=@('-CompilerPath',('"'+$CompilerPath+'"'))}
    if($ExpectedRuntimeIdentifier){$arguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
    if($RequireFuzz){$arguments+=@('-RequireFuzz','-FuzzRuns',$FuzzRuns)}
    $options=@{FilePath=$runner;ArgumentList=$arguments;PassThru=$true;RedirectStandardOutput=(Join-Path $RunDirectory 'worker.stdout.log');RedirectStandardError=(Join-Path $RunDirectory 'worker.stderr.log')}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $process=Start-Process @options
    $monitor=$null
    if(!$Headless){
        $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
        $monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$RunDirectory+'"'))
        "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    }
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 1800
    [pscustomobject]@{State=$summary.State.State;Mutation=$summary.Mutation;RunDirectory=$RunDirectory}
    if($summary.State.State -ne 'Success'){throw "PTY mutation campaign failed: $RunDirectory"}
    return
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Native PTY mutation';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=$(if($IsWindows){'linux-x64 (Podman)'}else{[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier});State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;Case='Baseline';Error=$null}
if($env:QUIETCLI_MUTATION_CONTAINER){$state.ContainerId=$env:QUIETCLI_MUTATION_CONTAINER}
$status=Join-Path $RunDirectory 'status.json'
$results=[Collections.Generic.List[object]]::new()
$metrics=@{Selected=0;Killed=0;Survived=0;Invalid=0;Timeout=0;Error=0;Score=$null;Scope='Explicit targeted C mutations; not exhaustive coverage'}
$fuzz=@{State='NotRequested';RequestedRuns=$FuzzRuns;ExecutedRuns=0}
$baseline=@{State='NotRun';Assertions=0;PropertyGroups=0;Failed=0;PropertySeed=633419}
Write-WorkspaceJson $status $state
function Invoke-PtyOperation {
    <#
    .SYNOPSIS
    Runs an explicit compiler or fixture contract and retains bounded diagnostics.
    .PARAMETER FilePath
    Documented executable or candidate fixture.
    .PARAMETER Arguments
    Explicit argument vector.
    .PARAMETER TimeoutSeconds
    Owned process deadline.
    #>
    param([string]$FilePath,[string[]]$Arguments,[int]$TimeoutSeconds=60)
    $data=@{Lines=[Collections.Generic.List[string]]::new()}
    $result=Invoke-CiProcess -FilePath $FilePath -ArgumentList $Arguments -TimeoutSeconds $TimeoutSeconds -State $data -OnOutput {param($e,$s)if($s.Lines.Count -ge 80){$s.Lines.RemoveAt(0)};$s.Lines.Add($e.Text)}
    return @{Outcome=$result.Outcome;ExitCode=$result.ExitCode;Diagnostics=@($data.Lines)}
}
try{
    if($ExpectedRuntimeIdentifier -and (!$IsLinux -or [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier -cne $ExpectedRuntimeIdentifier)){throw 'NativeMutationRuntimeMismatch'}
    $sourcePath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c'
    $testsPath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-tests.c'
    $testInputs=@(foreach($name in @('pty-tests.c','pty-properties.h','pty-oracles.h')){$path=Join-Path (Split-Path $testsPath -Parent) $name;@{Name=$name;Path=$path;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash}})
    $source=(Get-Content $sourcePath -Raw -Encoding utf8).Replace("`r`n","`n")
    $sourceHash=(Get-FileHash $sourcePath -Algorithm SHA256).Hash
    $testHash=(Get-FileHash $testsPath -Algorithm SHA256).Hash
    if(!$CompilerPath){
        if($IsWindows){$CompilerPath=(Get-ChildItem (Join-Path $WorkspaceRoot 'artifacts/toolchains') -Filter zig.exe -Recurse|Select-Object -First 1).FullName}
        else{$CompilerPath=(Get-Command gcc -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source}
    }
    $zig=[IO.Path]::GetFileNameWithoutExtension($CompilerPath) -eq 'zig'
    $version=Invoke-PtyOperation $CompilerPath $(if($zig){@('version')}else{@('--version')})
    if($version.Outcome -ne 'Success'){throw 'CompilerVersionUnavailable'}
    if($zig){$lock=Get-Content (Join-Path $WorkspaceRoot 'build/zig.lock.json') -Raw -Encoding utf8|ConvertFrom-Json;if($version.Diagnostics[0] -cne $lock.Version){throw 'CompilerVersionMismatch'}}
    $help=Invoke-PtyOperation $CompilerPath $(if($zig){@('cc','--help')}else{@('--help')})
    if($help.Outcome -ne 'Success'){throw 'CompilerHelpUnavailable'}
    . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Hardening.ps1')
    Write-WorkspaceJson (Join-Path $RunDirectory 'hardening.json') @(Assert-PtyHardening $WorkspaceRoot)
    $catalogue=@(
        @{Id='stream-drops-last-byte';Find='write_all(STDOUT_FILENO, bytes, (size_t)count)';Replace='write_all(STDOUT_FILENO, bytes, (size_t)count - 1)'},
        @{Id='stream-writes-to-stdin';Find='write_all(STDOUT_FILENO, bytes, (size_t)count)';Replace='write_all(STDIN_FILENO, bytes, (size_t)count)'},
        @{Id='output-error-reports-success';Find='if (failed || waited < 0) return 125;';Replace='if (failed || waited < 0) return 0;'},
        @{Id='output-error-leaves-child';Find='if (failed) signal_child(child, SIGKILL);';Replace='if (failed) (void)child;'},
        @{Id='control-thread-reads-stdin';Find='pthread_create(&control_thread, NULL, forward_control, &bridge)';Replace='pthread_create(&control_thread, NULL, forward_input, &bridge)'},
        @{Id='write-loses-eintr';Find='written < 0 && errno == EINTR';Replace='written < 0 && errno == EAGAIN'},
        @{Id='write-stops-after-partial';Find='length -= (size_t)written;';Replace='length = 0;'},
        @{Id='write-wrong-pointer';Find='data += written;';Replace='data += 1;'},
        @{Id='group-to-pid';Find='kill(-child, number)';Replace='kill(child, number)'},
        @{Id='lose-startup-signal';Find='errno == ESRCH';Replace='errno == EACCES'},
        @{Id='handler-corrupts-errno';Find='errno = saved;';Replace='errno = saved + 1;';Occurrence=0},
        @{Id='dimension-upper-too-low';Find='value > 1000';Replace='value > 999'},
        @{Id='dimension-upper-too-high';Find='value > 1000';Replace='value > 1001'},
        @{Id='dimension-accepts-zero';Find='value > 0 ? value : -1';Replace='value >= 0 ? value : -1'},
        @{Id='dimension-rejects-nine';Find="*text > '9'";Replace="*text > '8'"},
        @{Id='empty-path-stops-search';Find="if (!length) { if (!end) break; part = end + 1; continue; }";Replace='if (!length) { errno = ENOENT; return; }'},
        @{Id='missing-default-path';Find='"/usr/bin:/bin"';Replace='"/nonexistent"'},
        @{Id='lost-permission-error';Find='if (saved == EACCES) denied = 1;';Replace='if (saved == EACCES) denied = 0;'},
        @{Id='lost-executable-format-error';Find='else if (saved != ENOENT && saved != ENOTDIR) { errno = saved; return; }';Replace='else if (saved != ENOENT && saved != ENOTDIR) { errno = ENOENT; return; }'},
        @{Id='range-leaks-low-descriptors';Find='SYS_close_range, 3U';Replace='SYS_close_range, 513U'},
        @{Id='proc-leaks-high-descriptors';Find='fd <= INT_MAX';Replace='fd < 512'},
        @{Id='proc-closes-stderr';Find='fd > STDERR_FILENO';Replace='fd >= STDERR_FILENO'},
        @{Id='child-ignores-signals';Find='action.sa_handler = SIG_DFL;';Replace='action.sa_handler = SIG_IGN;'},
        @{Id='child-retains-signal-mask';Find='if (sigprocmask(SIG_SETMASK, &previous, NULL)) _exit(125);';Replace='if (sigprocmask(SIG_BLOCK, &blocked, NULL)) _exit(125);'},
        @{Id='failed-connect-leaks-socket';Find='if (control >= 0) close(control);';Replace='if (control < 0) close(control);'},
        @{Id='wrong-default-columns';Find='int columns = 120, rows = 40';Replace='int columns = 121, rows = 40'},
        @{Id='lost-child-exit-code';Find='if (WIFEXITED(status)) return WEXITSTATUS(status);';Replace='if (WIFEXITED(status)) return 0;'},
        @{Id='resize-wrong-command';Find='command[0] != 1';Replace='command[0] != 2'},
        @{Id='resize-accepts-zero';Find='columns == 0';Replace='columns == 65535'},
        @{Id='resize-upper-too-high';Find='if (columns == 0 || rows == 0 || columns > 1000 || rows > 1000)';Replace='if (columns == 0 || rows == 0 || columns > 1001 || rows > 1000)'},
        @{Id='resize-copies-columns-to-rows';Find='unsigned int rows = 256U * command[3] + command[4];';Replace='unsigned int rows = 256U * command[1] + command[2];'}
    )
    $metrics.Selected=$catalogue.Count
    Write-WorkspaceJson (Join-Path $RunDirectory 'catalogue.json') $catalogue
    Write-WorkspaceJson (Join-Path $RunDirectory 'inputs.json') @{SourceSHA256=$sourceHash;TestsSHA256=$testHash;TestInputs=$testInputs;PropertySeed=633419;Compiler=$CompilerPath;Version=$version;Host=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;Image=$(if($IsWindows){$Image}else{$null})}
    foreach($mutation in @(@{Id='baseline'})+$catalogue){
        $state.Case=$mutation.Id;Write-WorkspaceJson $status $state
        $directory=Join-Path $RunDirectory $mutation.Id
        $native=Join-Path $directory 'FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c'
        $tests=Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/pty-tests.c'
        [void][IO.Directory]::CreateDirectory((Split-Path $native -Parent));[void][IO.Directory]::CreateDirectory((Split-Path $tests -Parent))
        $candidate=$source
        if($mutation.Id -ne 'baseline'){
            $matches=[regex]::Matches($source,[regex]::Escape($mutation.Find))
            if($mutation.ContainsKey('Occurrence')){$match=$matches[[int]$mutation.Occurrence]}
            else{if($matches.Count -ne 1){throw "Mutation anchor drift: $($mutation.Id) ($($matches.Count) matches)"};$match=$matches[0]}
            $candidate=$source.Remove($match.Index,$match.Length).Insert($match.Index,$mutation.Replace)
        }
        [void][IO.File]::WriteAllTextAsync($native,$candidate,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        foreach($inputFile in $testInputs){Copy-Item $inputFile.Path (Join-Path (Split-Path $tests -Parent) $inputFile.Name)}
        $binary=Join-Path $directory 'pty-tests'
        $arguments=@('-std=c11','-O2','-Wall','-Wextra','-Werror','-fstack-protector-strong','-D_FORTIFY_SOURCE=2','-fPIE','-pie','-Wl,-z,relro,-z,now','-pthread',$tests,'-lutil','-o',$binary)
        if($zig){$arguments=@('cc','-target','x86_64-linux-musl','-static')+$arguments}
        $compile=Invoke-PtyOperation $CompilerPath $arguments -TimeoutSeconds 600
        Write-WorkspaceJson (Join-Path $directory 'compiler.json') $compile
        $compileState=if($compile.Outcome -eq 'Timeout'){'Timeout'}elseif($compile.Outcome -in @('Success','Failed')){'Invalid'}else{'Error'}
        $entry=@{Id=$mutation.Id;State=$compileState;SourceSHA256=(Get-FileHash $native -Algorithm SHA256).Hash;Execution=$null}
        if($compile.Outcome -eq 'Success'){
            $container=$null
            try{
                if($IsWindows){
                    $container='quietcli-pty-mut-'+[guid]::NewGuid().ToString('N')
                    $state.ContainerId=$container;Write-WorkspaceJson $status $state
                    $execution=Invoke-PtyOperation podman @('run','--pull=never','--rm','--network=none','--name',$container,'--volume',($directory+':/tests:ro'),'--volume',($directory+':/evidence:rw'),'--env','QUIETCLI_PTY_EVIDENCE=/evidence','--entrypoint','/tests/pty-tests',$Image) -TimeoutSeconds 45
                }else{
                    $previousEvidence=$env:QUIETCLI_PTY_EVIDENCE
                    try{$env:QUIETCLI_PTY_EVIDENCE=$directory;$execution=Invoke-PtyOperation $binary @() -TimeoutSeconds 45}finally{if($null -eq $previousEvidence){Remove-Item Env:QUIETCLI_PTY_EVIDENCE -ErrorAction SilentlyContinue}else{$env:QUIETCLI_PTY_EVIDENCE=$previousEvidence}}
                }
                $entry.Execution=$execution
                $passes=@($execution.Diagnostics|Where-Object {$_ -like 'PASS *'}).Count
                $fails=@($execution.Diagnostics|Where-Object {$_ -like 'FAIL *'}).Count
                if($execution.Outcome -eq 'Timeout' -or $execution.ExitCode -eq 142){$entry.State='Timeout'}
                elseif($execution.Outcome -eq 'Success' -and $passes -ge 43 -and !$fails){$entry.State='Survived'}
                elseif($execution.Outcome -eq 'Failed' -and ($fails -gt 0 -or $execution.ExitCode -in @(134,139))){$entry.State='Killed'}
                else{$entry.State='Error'}
                if($execution.Outcome -ne 'Timeout'){$container=$null} # --rm completed after the owned command terminated.
            }finally{
                if($container){$cleanup=Invoke-PtyOperation podman @('rm','--force',$container) -TimeoutSeconds 20;if($cleanup.Outcome -ne 'Success'){throw "Owned mutant container cleanup failed: $container"}}
            }
        }
        if($mutation.Id -eq 'baseline'){
            Write-WorkspaceJson (Join-Path $directory 'result.json') $entry
            if($entry.State -ne 'Survived'){throw 'Unmodified baseline failed; mutation results are not valid.'}
            $entry.State='BaselinePassed'
            $propertyGroups=@($execution.Diagnostics|Where-Object {$_ -like 'PASS property:*'}).Count
            $baseline=@{State='Success';Assertions=$passes;PropertyGroups=$propertyGroups;Failed=$fails;PropertySeed=633419}
            if($propertyGroups -lt 6){throw 'ProcessPropertySuiteIncomplete'}
            if($RequireFuzz){
                $state.Case='Coverage-guided decoder fuzzing with ASan/UBSan';Write-WorkspaceJson $status $state
                . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Fuzz.ps1')
                $fuzz=Invoke-PtyFuzz -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory fuzz) -Runs $FuzzRuns
                if($fuzz.State -cne 'Success'){throw 'CoverageGuidedFuzzFailedOrIncomplete; see fuzz/report.json'}
            }
        }else{
            $metrics[$entry.State]++
            if($entry.State -eq 'Killed'){$state.Passed++}else{$state.Failed++}
        }
        $results.Add($entry);Write-WorkspaceJson (Join-Path $directory 'result.json') $entry
        Write-WorkspaceJson (Join-Path $RunDirectory 'mutants.json') @($results)
        Write-WorkspaceJson $status $state
    }
    if((Get-FileHash $sourcePath -Algorithm SHA256).Hash -cne $sourceHash -or (Get-FileHash $testsPath -Algorithm SHA256).Hash -cne $testHash){throw 'Source or tests changed during mutation campaign.'}
    foreach($inputFile in $testInputs){if((Get-FileHash $inputFile.Path -Algorithm SHA256).Hash -cne $inputFile.SHA256){throw 'Property or oracle source changed during mutation campaign.'}}
    $denominator=$metrics.Killed+$metrics.Survived
    if($denominator){$metrics.Score=[math]::Round(100.0*$metrics.Killed/$denominator,2)}
    $state.State=if($state.Failed -or $metrics.Killed -ne $metrics.Selected){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Error=$_.ToString();$state.Failed++}
finally{
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Baseline=$baseline;Mutation=$metrics;Fuzz=$fuzz;HostRuntime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;OSArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();OSDescription=[Runtime.InteropServices.RuntimeInformation]::OSDescription;MachineName=[Environment]::MachineName}
    Write-WorkspaceJson $status $state
}
if($state.State -ne 'Success'){exit 1}
