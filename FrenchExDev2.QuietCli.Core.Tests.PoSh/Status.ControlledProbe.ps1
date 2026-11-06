#requires -Version 7.6
<#
.SYNOPSIS
Tests owned complex repositories with Core-only human, byte and NUL-record callbacks.
.PARAMETER WorkspaceRoot
Local monorepo supplying the exact built Core.
.PARAMETER RunDirectory
Fresh owned fixture/report location below the current run, retained on failures.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
if(Get-Module FrenchExDev2.QuietCli.*){throw 'ContaminatedControlledStatusProcess'}
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
foreach($name in @('Status.Aggregation','Status.Execution','Status.Fixtures','Status.Assertions')){. (Join-Path $PSScriptRoot "$name.ps1")}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$validation=Test-QuietControlledStatusAssertions
$git=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$fixtures=New-QuietControlledStatusFixtures -Root (Join-Path $RunDirectory 'fixtures') -GitPath $git
Write-WorkspaceJson (Join-Path $RunDirectory 'fixture-manifest.json') $fixtures
. (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'measurements.sqlite') -Hosting $(if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'})
Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
$core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
$expectedPath=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1'))
if($core.Path -cne $expectedPath -or (Get-Alias quiet).ResolvedCommand.Module.Path -cne $expectedPath){throw 'ControlledStatusCorePathMismatch'}
$observed=[Collections.Generic.List[object]]::new()
try{
    foreach($fixture in $fixtures){
        if((Get-Module FrenchExDev2.QuietCli.Git.PoSh) -or @(Get-QuietHandler).Count){throw 'ControlledStatusBusinessCompanionLoaded'}
        Stop-QuietEngine
        $human=Invoke-QuietStatusComparison -RepositoryPath $fixture.Path -GitPath $git -WarmIterations 3
        $oracle=Get-QuietStatusOracle $fixture.Entries
        $samples=[Collections.Generic.List[object]]::new()
        foreach($mode in @('Bytes','Text')){
            foreach($block in @(1024,16384)){
                $state=@{Hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256);Bytes=0L;Records=0L;CompleteCalls=0}
                try{
                    $result=quiet -AsObject -WorkingDirectory $fixture.Path -TimeoutSeconds 60 -ReadBlockBytes $block -StdoutMode $mode -RecordDelimiter ([string][char]0) -Data $state -Output {
                        param($event,$runtime)
                        if($event.Stream -ne 'stdout'){return}
                        if($event.Kind -eq 'Bytes'){
                            $runtime.Data.Hash.AppendData($event.Bytes);$runtime.Data.Bytes+=$event.ByteCount
                            foreach($value in $event.Bytes){if($value -eq 0){$runtime.Data.Records++}}
                        }else{
                            $bytes=[Text.Encoding]::UTF8.GetBytes($event.Text+[char]0)
                            $runtime.Data.Hash.AppendData($bytes);$runtime.Data.Bytes+=$bytes.Length;$runtime.Data.Records++
                        }
                    } -Complete {
                        param($runtime)
                        $runtime.Data.CompleteCalls++
                        [pscustomobject]@{Bytes=$runtime.Data.Bytes;Records=$runtime.Data.Records;CompleteCalls=$runtime.Data.CompleteCalls;SHA256=[Convert]::ToHexString($runtime.Data.Hash.GetHashAndReset())}
                    } -FilePath $git -ArgumentList @('status','--porcelain=v2','-z','--untracked-files=all','--ignored=matching')
                    Assert-QuietControlledStatus $result $oracle
                    $samples.Add(@{Mode=$mode;ReadBlockBytes=$block;Business=$result.Data;Outcome=$result.Outcome;SourceComplete=$result.Completeness.Source;AnalysisComplete=$result.Completeness.Analysis;ElapsedMs=$result.Execution.ElapsedMs;CallbackMs=$result.Execution.CallbackMs})
                }finally{$state.Hash.Dispose()}
            }
        }
        if((Get-Module FrenchExDev2.QuietCli.Git.PoSh) -or @(Get-QuietHandler).Count){throw 'ControlledStatusBusinessCompanionLoaded'}
        $engine=Get-QuietEngine
        if($engine.Engine.RuntimeIdentifier -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier){throw 'ControlledStatusEngineRidMismatch'}
        if($env:QUIETCLI_EXPECT_ENGINE_MODE -and $engine.Mode -cne $env:QUIETCLI_EXPECT_ENGINE_MODE){throw 'ControlledStatusEngineModeMismatch'}
        $observed.Add(@{Name=$fixture.Name;Oracle=$oracle;Human=$human;Samples=$samples.ToArray();GitModuleLoaded=$false;RegisteredHandlers=0;EngineMode=$engine.Mode;EngineRid=$engine.Engine.RuntimeIdentifier})
        Write-WorkspaceJson (Join-Path $RunDirectory 'controlled-status.partial.json') @{Scenarios=$observed.ToArray();Validation=$validation}
        @{Kind='Progress';Scenario=$fixture.Name;Completed=$observed.Count}|ConvertTo-Json -Compress
    }
    $evidence=[pscustomobject]@{Kind='ControlledGitStatus';Passed=$observed.Count;Failed=0;Scenarios=$observed.ToArray();Validation=$validation;CorePath=$core.Path;GitModuleLoaded=$false;RegisteredHandlers=0;ProcessId=$PID;PowerShellVersion=$PSVersionTable.PSVersion.ToString();RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;FixtureRoot=(Join-Path $RunDirectory 'fixtures');Limits='Disposable fixtures only; no network or external repositories. Human output is compared with the independent runner; porcelain bytes are predicted from literal fixture states. Source/analysis completeness, exact byte/record counts, digest and one completion are required. Engine sessions restart between scenarios; the managed assembly and filesystem caches may remain warm.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'controlled-status.json') $evidence
    @{Kind='Result';Evidence=$evidence}|ConvertTo-Json -Depth 20 -Compress
}finally{Stop-QuietEngine}
