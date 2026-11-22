#requires -Version 7.6
<# .SYNOPSIS
Exercises the actual Spectre live surface in a dedicated, unredirected Windows console and saves viewport evidence.
.PARAMETER WorkspaceRoot
Selected source workspace containing the built local engine.
.PARAMETER RunDirectory
New external report directory; generated when omitted.
.PARAMETER Worker
Internal unredirected console worker. Use the ordinary entry point to retain the visible monitor.
.PARAMETER GitWatch
Also verifies that the local launcher loads Git and opens the Watch dashboard with its defaults.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'../../../..'))),[string]$RunDirectory,[switch]$Worker,[switch]$GitWatch)
$ErrorActionPreference='Stop'
$root=$WorkspaceRoot
$run=$RunDirectory
Import-Module (Join-Path $root 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
if(!$Worker){
    if(!$IsWindows){throw 'The interactive console probe requires a Windows desktop.'}
    if(!$run){$run=Join-Path (Get-QuietReportRoot $root 'ui-console') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $run){throw 'ConsoleSmokeRunExists'}
    [void][IO.Directory]::CreateDirectory($run)
    $runner=Join-Path $PSHOME 'pwsh.exe'
    # This worker must own a real console: redirecting stdout would select a different product surface.
    $workerArguments=@('-File',(ConvertTo-CiArgument $PSCommandPath),'-WorkspaceRoot',(ConvertTo-CiArgument $root),'-RunDirectory',(ConvertTo-CiArgument $run),'-Worker')
    if($GitWatch){$workerArguments+='-GitWatch'}
    $process=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList $workerArguments
    $monitorPath=Join-Path $root 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $run)) -RedirectStandardError (Join-Path $run 'monitor.stderr.log')
    'Monitor: pwsh -File '+(ConvertTo-CiArgument $monitorPath)+' -RunDirectory '+(ConvertTo-CiArgument $run)
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $run -WorkspaceRoot $root -TimeoutSeconds 120
    [pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$run}
    if($summary.State.State -ne 'Success'){throw "Console smoke failed: $run"};return
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Interactive Spectre console resize';Workspace=$root;ProjectDirectory=(Join-Path $root 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh');Platform='win-x64';State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Attach live surface';Error=$null}
Write-WorkspaceJson (Join-Path $run 'status.json') $state
$renderer=$null;$frames=[Collections.Generic.List[object]]::new()
try{
    Import-Module (Join-Path $root 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    [void][Reflection.Assembly]::LoadFrom((Join-Path $root 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/Spectre.Console.Ansi.dll'))
    [void][Reflection.Assembly]::LoadFrom((Join-Path $root 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/Spectre.Console.dll'))
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
/// <summary>Read-only console viewport capture and thread-safe renderer diagnostics.</summary>
public static class QuietUiConsoleProbe {
    /// <summary>Native console position.</summary>
    [StructLayout(LayoutKind.Sequential)] public struct Coord { public short X; public short Y; }
    /// <summary>Obtains the standard output console handle.</summary>
    /// <param name="kind">Standard output handle identifier.</param>
    [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int kind);
    /// <summary>Reads visible console cells without changing the console.</summary>
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool ReadConsoleOutputCharacterW(IntPtr handle, StringBuilder text, uint length, Coord origin, out uint read);
    [StructLayout(LayoutKind.Explicit, Size=20)]
    private struct KeyInput {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public int KeyDown;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort VirtualKey;
        [FieldOffset(14)] public ushort Character;
    }
    [DllImport("kernel32.dll", EntryPoint="WriteConsoleInputW", SetLastError=true)]
    private static extern bool WriteConsoleInput(IntPtr handle, ref KeyInput input, uint length, out uint written);
    /// <summary>Failures collected by the renderer's timer thread.</summary>
    public static readonly ConcurrentQueue<string> Errors = new();
    /// <summary>Records an observer error without requiring a PowerShell runspace.</summary>
    /// <param name="code">Error code.</param><param name="phase">Phase.</param><param name="message">Diagnostic.</param>
    public static void Error(string code, string phase, string message) => Errors.Enqueue(code+":"+phase+":"+message);
    /// <summary>Creates an invocation's explicit cancellation file after its live surface has started.</summary>
    /// <param name="path">Owned test cancellation file.</param>
    public static async System.Threading.Tasks.Task CancelAfterAsync(string path) {
        await System.Threading.Tasks.Task.Delay(1000);
        await System.IO.File.WriteAllTextAsync(path,"cancel",new UTF8Encoding(false));
    }
    /// <summary>Sends two key-down events to this worker's own console and records the last visible frame.</summary>
    /// <param name="ready">Signal created by the first completed Watch cycle.</param>
    /// <param name="cancel">Signal that stops the watcher after the capture.</param>
    public static async System.Threading.Tasks.Task<string[]> ExerciseWatchKeysAsync(string ready, string cancel) {
        try {
            for(int i=0; i<300 && !System.IO.File.Exists(ready); i++) await System.Threading.Tasks.Task.Delay(25);
            if(!System.IO.File.Exists(ready)) throw new TimeoutException("Watch did not complete its first cycle.");
            for(int i=0; i<2; i++) {
                await System.Threading.Tasks.Task.Delay(500);
                var key=new KeyInput { EventType=1, KeyDown=1, Repeat=1, VirtualKey=0x20, Character=0x20 };
                if(!WriteConsoleInput(GetStdHandle(-10),ref key,1,out uint written) || written!=1)
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            await System.Threading.Tasks.Task.Delay(750);
            return Capture();
        } finally {
            await System.IO.File.WriteAllTextAsync(cancel,"cancel",new UTF8Encoding(false));
        }
    }
    /// <summary>Captures the current viewport as rows of console cells.</summary>
    public static string[] Capture() {
        int width=Console.WindowWidth, height=Console.WindowHeight;
        var rows=new string[height];
        for(int row=0;row<height;row++) {
            var text=new StringBuilder(width+1);
            if(!ReadConsoleOutputCharacterW(GetStdHandle(-11),text,(uint)width,new Coord{X=(short)Console.WindowLeft,Y=(short)(Console.WindowTop+row)},out uint read))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            rows[row]=text.ToString(0,Math.Min((int)read,Math.Min(width,text.Length))).PadRight(width);
        }
        return rows;
    }
}
'@
    if([Console]::IsOutputRedirected -or ![Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive){throw 'InteractiveConsoleUnavailable'}
    [Console]::Title='QuietCli Core | Interactive console smoke'
    [Console]::CursorVisible=$false
    $logger=[Delegate]::CreateDelegate([Action[string,string,string]],[QuietUiConsoleProbe].GetMethod('Error'))
    $surface=[FrenchExDev2.QuietCli.Cmdlets.SpectreLiveSurface]::new()
    $renderer=[FrenchExDev2.QuietCli.Cmdlets.QuietUiRenderer]::new(3,$surface,$logger)
    $renderer.SetHeader([string[]]@('Project: QuietCli Core | Task: console smoke',$root,(Join-Path $root 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh')))
    foreach($index in 1..5){foreach($machine in 'web','db'){$renderer.Write([pscustomobject]@{Stream='stdout';Text="été 漢字 🙂 $machine message $index"},$machine);$renderer.NewLine($machine)}}
    foreach($size in @(@(120,28),@(80,20),@(36,12),@(22,10),@(110,26))){
        $state.Case='Resize '+($size -join 'x');Write-WorkspaceJson (Join-Path $run 'status.json') $state
        [Console]::SetBufferSize([Math]::Max([Console]::BufferWidth,$size[0]),[Math]::Max([Console]::BufferHeight,$size[1]))
        [Console]::SetWindowSize($size[0],$size[1])
        [Console]::SetBufferSize($size[0],[Console]::BufferHeight)
        [Threading.Tasks.Task]::Delay(700).GetAwaiter().GetResult()
        $rows=[QuietUiConsoleProbe]::Capture()
        [void]$frames.Add(@{Requested=$size;Width=[Console]::WindowWidth;Height=[Console]::WindowHeight;Rows=$rows})
        if(($rows -join "`n") -match 'QuietCli|QC' -and ($rows -join "`n") -match 'Task:| T:'){$state.Passed++}else{$state.Failed++}
        Write-WorkspaceJson (Join-Path $run 'frames.json') $frames.ToArray()
    }
    $renderer.Dispose();$renderer=$null
    $state.Case='Cancel a real UI invocation and reuse its live surface';Write-WorkspaceJson (Join-Path $run 'status.json') $state
    $cancel=Join-Path $run 'cancel.signal'
    $pending=[QuietUiConsoleProbe]::CancelAfterAsync($cancel)
    $dotnet=(Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture=Join-Path $root 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $cancelled=quiet -AsObject -Ui -CancellationFile $cancel -TimeoutSeconds 10 -FilePath $dotnet -ArgumentList @($fixture,'hang') -Output {param($event,$runtime)}
    [void]$pending.GetAwaiter().GetResult()
    $child=$cancelled.Execution.Native.ProcessId
    $removed=$child -and !(Get-Process -Id $child -ErrorAction SilentlyContinue)
    if($cancelled.Outcome -eq 'Cancelled' -and $removed){$state.Passed++}else{$state.Failed++}
    $next=quiet -AsObject -Ui -TimeoutSeconds 10 -FilePath $dotnet -ArgumentList @($fixture,'args','after-cancel') -Output {param($event,$runtime)}
    if($next.Outcome -eq 'Success' -and !@($next.Error | Where-Object Code -Like 'Ui*').Count){$state.Passed++}else{$state.Failed++}
    Write-WorkspaceJson (Join-Path $run 'cancellation.json') @{Outcome=$cancelled.Outcome;Execution=$cancelled.Execution;Error=$cancelled.Error;ChildRemoved=[bool]$removed;NextOutcome=$next.Outcome;NextErrors=$next.Error}
    foreach($mode in 'keypress','keypress-or-timer'){
        $state.Case='Watch '+$mode
        Write-WorkspaceJson ([IO.Path]::Combine($run,'status.json')) $state
        $ready = [IO.Path]::Combine($run,$mode+'.ready')
        $cancel = [IO.Path]::Combine($run,$mode+'.cancel')
        $data = @{ Cycles = 0; Ready = $ready }
        $pending = [QuietUiConsoleProbe]::ExerciseWatchKeysAsync($ready,$cancel)
        $conditions = if($mode -eq 'keypress'){@{WatchOnKeypress=$true}}else{@{Watch='30s';WatchOnKeypress=$true}}
        $output = @(quiet @conditions -UI -CancellationFile $cancel -TimeoutSeconds 5 -Data $data -Complete {
            param($runtime)
            $data = $runtime.Data
            $data.Cycles++
            $runtime.Ui.Write('Completed cycle '+$data.Cycles,'watch-test')
            if($data.Cycles -eq 1){[IO.File]::WriteAllText($data.Ready,'ready',[Text.UTF8Encoding]::new($false))}
        } -FilePath $dotnet -ArgumentList @($fixture,'args','watch'))
        $rows = $pending.GetAwaiter().GetResult()
        if($data.Cycles -ne 3 -or $output.Count -ne 0 -or ($rows -join "`n") -notmatch 'Completed cycle 3'){
            throw "Watch keyboard or live output changed: $mode, cycles=$($data.Cycles), outputs=$($output.Count)"
        }
        $state.Passed++
        Write-WorkspaceJson ([IO.Path]::Combine($run,$mode+'.json')) @{Cycles=$data.Cycles;Rows=$rows}
    }
    if($GitWatch){
        $state.Case='Git Watch through the local launcher with default arguments'
        Write-WorkspaceJson ([IO.Path]::Combine($run,'status.json')) $state
        $ready=[IO.Path]::Combine($run,'git-watch.ready')
        $cancel=[IO.Path]::Combine($run,'git-watch.cancel')
        $data=@{Cycles=0;Ready=$ready}
        $observe={
            param($event,$runtime)
            if($event.Type -eq 'GitStatusSummary'){
                $data.Cycles++
                if($data.Cycles -eq 1){[IO.File]::WriteAllText($data.Ready,'ready',[Text.UTF8Encoding]::new($false))}
            }
        }.GetNewClosure()
        $launcher=[IO.Path]::Combine($root,'scripts/Invoke-Quiet.ps1')
        if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'Git was already loaded before testing launcher defaults.'}
        Push-Location -LiteralPath $root
        try{
            $pending=[QuietUiConsoleProbe]::ExerciseWatchKeysAsync($ready,$cancel)
            $output=@(& $launcher -Code {quiet -WatchOnKeypress -CancellationFile $cancel -Listeners $observe git status})
            if($output.Count){throw "Git Watch did not open its dashboard; first outcome: $($output[0].Outcome)"}
            $rows=$pending.GetAwaiter().GetResult()
        }finally{Pop-Location}
        if($data.Cycles -ne 3 -or ($rows -join "`n") -notmatch 'Watch git status' -or ($rows -join "`n") -notmatch 'Branch:'){
            throw "Git Watch did not refresh its dashboard: cycles=$($data.Cycles)"
        }
        if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'Git remained loaded after the launcher returned.'}
        & $launcher -Companion @() -Code {
            if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'Core-only selection unexpectedly loaded Git.'}
        }
        $state.Passed++
        Write-WorkspaceJson ([IO.Path]::Combine($run,'git-watch.json')) @{Cycles=$data.Cycles;Rows=$rows}
    }
    if([QuietUiConsoleProbe]::Errors.Count){$state.Failed++;$state.Error=[QuietUiConsoleProbe]::Errors.ToArray() -join '; '}
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Failed';$state.Failed++;$state.Error=$_.ToString()}
finally{
    if($renderer){$renderer.Dispose()}
    [Console]::CursorVisible=$true
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $run 'summary.json') @{State=$state;Frames=$frames.ToArray();Scope='Real console and Spectre resize, native cancellation, child termination, surface reuse and Watch keyboard input; physical Ctrl+C not exercised'}
    Write-WorkspaceJson (Join-Path $run 'status.json') $state
}
