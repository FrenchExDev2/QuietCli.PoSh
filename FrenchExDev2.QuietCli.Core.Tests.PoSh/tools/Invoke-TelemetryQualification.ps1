#requires -Version 7.6
<#
.SYNOPSIS
Runs focused allocation and gain qualification with the shared visible monitor and owned source mutants.
.PARAMETER WorkspaceRoot
Workspace containing the built Core engine and companion tests.
.PARAMETER RunDirectory
New private report directory; defaults to the workspace temporary report root.
.PARAMETER Mutation
Runs the bounded source mutation catalogue after the C# and PowerShell baselines pass.
.PARAMETER Worker
Internal background entry point; the parent owns its timeout and visible monitor.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))),[string]$RunDirectory,[switch]$Mutation,[switch]$Worker)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
if(!$Worker){
    if(!$IsWindows){throw 'Local qualification requires the Windows visible monitor.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'telemetry') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'TestRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $arguments=@('-File',('"'+$PSCommandPath+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$RunDirectory+'"'),'-Worker')
    if($Mutation){$arguments+='-Mutation'}
    $process=Start-Process $runner -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log')
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -PassThru
    "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $process -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds 900
    $summary
    if($summary.State.State -ne 'Success'){throw "Telemetry qualification failed: $RunDirectory"}
    return
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Allocation, gain, properties, fuzz and mutation';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Starting';Error=$null}
$env:PSModulePath=$WorkspaceRoot+[IO.Path]::PathSeparator+$env:PSModulePath
$statusPath=Join-Path $RunDirectory 'status.json'
$results=[Collections.Generic.List[object]]::new()
$baseline=$null
function Invoke-TelemetryEngineCases {
    <#
    .SYNOPSIS
    Executes the independent compiled cases with bounded native execution and a structured result requirement.
    .PARAMETER Assembly
    Exact built companion assembly.
    .PARAMETER NativeDirectory
    Verified SQLite native dependency directory.
    #>
    param([string]$Assembly,[string]$NativeDirectory)
    $capture=@{Report=$null}
    $execution=Invoke-CiProcess -FilePath dotnet -ArgumentList @($Assembly,$NativeDirectory,'--telemetry-only') -TimeoutSeconds 30 -State $capture -OnOutput {
        param($line,$capture)
        if($line.Stream -eq 'stdout' -and $line.Text.StartsWith('{"Passed":')){$capture.Report=ConvertFrom-Json -InputObject $line.Text}
        else{[Console]::WriteLine($line.Text)}
    }
    if(!$capture.Report -or $execution.Outcome -eq 'Timeout'){throw 'TelemetryCasesCrashedOrTimedOut'}
    return [pscustomobject]@{Execution=$execution;Report=$capture.Report}
}
function Invoke-TelemetryPowerShellCases {
    <#
    .SYNOPSIS
    Runs a fresh caller against one owned PowerShell test-subject module and requires structured assertions.
    .PARAMETER ModulePath
    Exact Core manifest under test.
    .PARAMETER DatabasePath
    Private SQLite file for this test process.
    #>
    param([string]$ModulePath,[string]$DatabasePath)
    $capture=@{Report=$null}
    $scriptPath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/tools/Telemetry.MutationWorker.ps1'
    $fixturePath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $execution=Invoke-CiProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-File',$scriptPath,'-ModulePath',$ModulePath,'-Fixture',$fixturePath,'-DatabasePath',$DatabasePath) -TimeoutSeconds 60 -State $capture -OnOutput {
        param($line,$capture)
        if($line.Stream -eq 'stdout' -and $line.Text.StartsWith('{"Passed":')){$capture.Report=ConvertFrom-Json -InputObject $line.Text}
        else{[Console]::WriteLine($line.Text)}
    }
    if(!$capture.Report -or $execution.Outcome -eq 'Timeout'){throw 'PowerShellTelemetryCasesCrashedOrTimedOut'}
    return [pscustomobject]@{Execution=$execution;Report=$capture.Report}
}
try{
    Write-WorkspaceJson $statusPath $state
    Write-WorkspaceJson (Join-Path $RunDirectory 'source-identity.json') (Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries)
    $native=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+$state.Platform+'/native')
    $state.Case='C# deterministic properties, malformed metadata fuzz and SQLite regressions';Write-WorkspaceJson $statusPath $state
    $baseline=Invoke-TelemetryEngineCases (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests/QuietCli.Engine.Tests.dll') $native
    Write-WorkspaceJson (Join-Path $RunDirectory 'baseline.json') $baseline
    if($baseline.Execution.Outcome -ne 'Success' -or $baseline.Report.Failed -ne 0){throw 'TelemetryBaselineFailed'}
    $state.Passed+=$baseline.Report.Passed
    $state.Case='PowerShell Complete objects and SQLite in integrated and isolated hosting';Write-WorkspaceJson $statusPath $state
    . (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
    Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'measurements.sqlite')
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -Force
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -Force
    $samples=& (Get-Module FrenchExDev2.QuietCli.Core.Tests.PoSh) {
        param($root)
        . (Join-Path $root 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Telemetry.Tests.ps1')
        Test-QuietAllocationTelemetry $root
        Measure-QuietProcessAllocations $root
    } $WorkspaceRoot
    Write-WorkspaceJson (Join-Path $RunDirectory 'process-allocations.json') @($samples)
    $state.Passed++
    if($Mutation){
        $catalogue=@(
            @{Name='allocation-zero';File='AllocationMeter.cs';From='checked(ended - started)';To='0L'},
            @{Name='allocation-thread-guard';File='AllocationMeter.cs';From='endThread == threadId ? checked(ended - started) : null';To='checked(ended - started)'},
            @{Name='allocation-stop-cache';File='AllocationMeter.cs';From='if (measurement != null) return measurement;';To='if (false) return measurement!;'},
            @{Name='gain-includes-object-only';File='GainAccumulator.cs';From='checked(comparedBusiness - delivered)';To='checked(business - delivered)'},
            @{Name='gain-unknown-size';File='GainAccumulator.cs';From='deliveriesComplete && deliverySizesKnown && comparedSourcesKnown';To='deliveriesComplete && comparedSourcesKnown'},
            @{Name='gain-snapshot-completeness';File='GainAccumulator.cs';From='row.Completeness is { Source: true, Analysis: true } && row.Sources != null';To='true'},
            @{Name='gain-source-duplication';File='GainAccumulator.cs';From='comparedBusiness + (bytes ?? 0)';To='comparedBusiness + 2 * (bytes ?? 0)'},
            @{Name='allocation-thread-report';File='GainAccumulator.cs';From='allocationThreadChanges++;';To='allocationThreadChanges += 0;'},
            @{Name='allocation-validation';File='MeasurementModels.cs';From='Nonnegative(value.AllocatedBytes);';To='// Mutant omits allocation sign validation.'},
            @{Name='process-default-precision';File='ProcessAllocationSnapshot.cs';From='Capture(bool precise = false)';To='Capture(bool precise = true)'},
            @{Name='process-thread-only';File='ProcessAllocationSnapshot.cs';From='GC.GetTotalAllocatedBytes(precise)';To='GC.GetAllocatedBytesForCurrentThread()'}
        )
        foreach($mutant in $catalogue){
            $state.Case='Mutation: '+$mutant.Name;Write-WorkspaceJson $statusPath $state
            $directory=Join-Path $RunDirectory ('mutation/'+$mutant.Name)
            [void][IO.Directory]::CreateDirectory($directory)
            foreach($relative in @('FrenchExDev2.QuietCli.Core.PoSh/engine','FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests')){
                foreach($file in Get-QuietSourceFiles (Join-Path $WorkspaceRoot $relative)){
                    $destination=Join-Path $directory ($relative+'/'+$file.Path)
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                    [IO.File]::Copy((Join-Path $WorkspaceRoot ($relative+'/'+$file.Path)),$destination)
                }
            }
            foreach($relative in @('global.json','FrenchExDev2.QuietCli.Core.PoSh/protocol.json')){[IO.File]::Copy((Join-Path $WorkspaceRoot $relative),(Join-Path $directory $relative))}
            $path=Join-Path $directory ('FrenchExDev2.QuietCli.Core.PoSh/engine/'+$mutant.File)
            $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw ('MutantAnchorNotUnique: '+$mutant.Name)}
            [IO.File]::WriteAllTextAsync($path,$source.Replace($mutant.From,$mutant.To).Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $build=Invoke-CiProcess -FilePath dotnet -ArgumentList @('build',(Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj'),'-f','net11.0','-c','Release','-o',(Join-Path $directory 'out'),'--nologo') -WorkingDirectory $directory -TimeoutSeconds 120
            if($build.Outcome -ne 'Success'){throw ('InvalidSourceMutant: '+$mutant.Name)}
            $run=Invoke-TelemetryEngineCases (Join-Path $directory 'out/QuietCli.Engine.Tests.dll') $native
            $outcome=if($run.Execution.Outcome -eq 'Failed' -and $run.Report.Failed -gt 0){'Killed'}elseif($run.Execution.Outcome -eq 'Success' -and $run.Report.Failed -eq 0){'Survived'}else{'Error'}
            $result=@{Name=$mutant.Name;State=$outcome;SourceSHA256=(Get-FileHash $path -Algorithm SHA256).Hash;Run=$run}
            Write-WorkspaceJson (Join-Path $directory 'result.json') $result
            $results.Add($result)
            if($outcome -eq 'Killed'){$state.Passed++}else{$state.Failed++}
            Write-WorkspaceJson $statusPath $state
        }
        $state.Project='FrenchExDev2.QuietCli.Core.PoSh';$state.ProjectDirectory=Join-Path $WorkspaceRoot $state.Project
        $state.Case='PowerShell source mutation baseline';Write-WorkspaceJson $statusPath $state
        $moduleDirectory=Join-Path $RunDirectory 'powershell-subject/FrenchExDev2.QuietCli.Core.PoSh'
        $originalModule=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'
        foreach($file in Get-QuietSourceFiles $originalModule){
            $destination=Join-Path $moduleDirectory $file.Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            [IO.File]::Copy((Join-Path $originalModule $file.Path),$destination)
        }
        Copy-Item -LiteralPath (Join-Path $originalModule 'lib') -Destination (Join-Path $moduleDirectory 'lib') -Recurse
        $manifest=Join-Path $moduleDirectory 'FrenchExDev2.QuietCli.Core.PoSh.psd1'
        $psBaseline=Invoke-TelemetryPowerShellCases $manifest (Join-Path $RunDirectory 'powershell-baseline.sqlite')
        Write-WorkspaceJson (Join-Path $RunDirectory 'powershell-baseline.json') $psBaseline
        if($psBaseline.Execution.Outcome -ne 'Success' -or $psBaseline.Report.Failed -ne 0){throw 'PowerShellMutationBaselineFailed'}
        $psCatalogue=@(
            @{Name='ps-invocation-allocation';File='Invoke.ps1';From='$result.Measurement.Allocation = $allocation.Stop()';To='$result.Measurement.Allocation = $null'},
            @{Name='ps-complete-allocation';File='Invoke.ps1';From='$Runtime.CompleteAllocation = $allocation.Stop()';To='$Runtime.CompleteAllocation = $null'},
            @{Name='ps-allocation-persistence';File='Gain.ps1';From='Allocation=$Result.Measurement.Allocation';To='Allocation=$null'}
        )
        # SharedProcess (EngineCommands.cs) and ReductionBytes (DeliveryCommands.cs) are compiled now; their mutants live in the C# catalogues.
        foreach($mutant in $psCatalogue){
            $state.Case='Mutation: '+$mutant.Name;Write-WorkspaceJson $statusPath $state
            $directory=Join-Path $RunDirectory ('mutation/'+$mutant.Name);[void][IO.Directory]::CreateDirectory($directory)
            $path=Join-Path $moduleDirectory ('src/'+$mutant.File)
            $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw ('MutantAnchorNotUnique: '+$mutant.Name)}
            try{
                $modified=$source.Replace($mutant.From,$mutant.To).Replace("`r`n","`n")
                [IO.File]::WriteAllTextAsync($path,$modified,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                [IO.File]::WriteAllTextAsync((Join-Path $directory $mutant.File),$modified,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $run=Invoke-TelemetryPowerShellCases $manifest (Join-Path $directory 'measurements.sqlite')
                $outcome=if($run.Execution.Outcome -eq 'Failed' -and $run.Report.Failed -gt 0){'Killed'}elseif($run.Execution.Outcome -eq 'Success' -and $run.Report.Failed -eq 0){'Survived'}else{'Error'}
                $result=@{Name=$mutant.Name;State=$outcome;SourceSHA256=(Get-FileHash $path -Algorithm SHA256).Hash;Run=$run}
                Write-WorkspaceJson (Join-Path $directory 'result.json') $result
                $results.Add($result)
                if($outcome -eq 'Killed'){$state.Passed++}else{$state.Failed++}
            }finally{[IO.File]::WriteAllTextAsync($path,$source,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
            Write-WorkspaceJson $statusPath $state
        }
    }
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Failed++;$state.Error=$_.ToString()}
finally{
    if(Get-Command Stop-QuietEngine -ErrorAction SilentlyContinue){Stop-QuietEngine}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Baseline=$baseline;Mutations=$results.ToArray();PropertySeeds=@(87499,56841);FuzzSeed=9874;PropertyIterations=512;FuzzExecutions=512}
    Write-WorkspaceJson $statusPath $state
}
if($state.State -ne 'Success'){exit 1}
