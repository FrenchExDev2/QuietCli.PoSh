<#
.SYNOPSIS
Measures read-only commands against shared controlled fixtures in an isolated worker.
.PARAMETER WorkspaceRoot
Selected source root.
.PARAMETER RunDirectory
Owned monitored report directory.
.PARAMETER RtkPath
Explicit installed or temporary RTK executable.
.PARAMETER CasesPath
Optional inert JSON array of explicit comparison cases.
#>
param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$RtkPath,[string]$CasesPath)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
. (Join-Path $PSScriptRoot 'Status.Fixtures.ps1')
$collect={param($e,$r) $r.Data[$e.Stream]+=$e.ByteCount;if($e.Stream -eq 'stdout'){[void]$r.Data.Text.Append($e.Text)}}
$newData={@{stdout=0L;stderr=0L;terminal=0L;Text=[Text.StringBuilder]::new()}}
$dotnet=(Get-Command dotnet -CommandType Application).Source
$fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
$version=quiet -AsObject -Role Probe -Data (& $newData) -Output $collect -FilePath $RtkPath -ArgumentList @('--version')
if($version.Outcome -ne 'Success'){throw 'RtkVersionProbeFailed'}
$cases=[Collections.Generic.List[object]]::new()
if($CasesPath){
    foreach($case in @(Get-Content -LiteralPath $CasesPath -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable)){$cases.Add($case)}
}else{
    $git=(Get-Command git -CommandType Application).Source
    $fixtures=New-QuietControlledStatusFixtures -Root (Join-Path $RunDirectory 'comparison-git-fixtures') -GitPath $git
    foreach($state in $fixtures){
        $facts=@($state.Entries|Where-Object Status -NE '!!'|ForEach-Object {$_.Path;if($_.ContainsKey('OriginalPath')){$_.OriginalPath}})
        $cases.Add(@{Name=('git-'+$state.Name);Family='Git';FilePath=$git;Arguments=@('status','--short','--untracked-files=all');WorkingDirectory=$state.Path;RtkArguments=@('git','status','--short','--untracked-files=all');ExpectedFacts=$facts;ExpectedExit=0;RtkMode='CommandFilter';Oracle='New-QuietControlledStatusFixtures literal paths'})
    }
    foreach($producer in @(
        @{Name='large-output';Arguments=@('emit','1048576');Stdout=1048576;Stderr=0;Exit=0},
        @{Name='mixed-streams';Arguments=@('mixed','32768','16384');Stdout=32768;Stderr=16384;Exit=0},
        @{Name='unicode';Arguments=@('unicode');Stdout=14;Stderr=0;Exit=0},
        @{Name='native-failure';Arguments=@('fail');Stdout=0;Stderr=17;Exit=7}
    )){
        # RTK bypass is a documented passthrough control, not a claimed synthetic-output compressor.
        $cases.Add(@{Name=('fixture-'+$producer.Name);Family='CSharpFixture';FilePath=$dotnet;Arguments=@($fixture)+$producer.Arguments;WorkingDirectory=$RunDirectory;RtkArguments=@('bypass',$dotnet,$fixture)+$producer.Arguments;ExpectedStdout=$producer.Stdout;ExpectedStderr=$producer.Stderr;ExpectedExit=$producer.Exit;ExpectedFacts=@();RtkMode='PassthroughControl';Oracle='Independent fixture byte counts'})
    }
}
$samples=[Collections.Generic.List[object]]::new()
foreach($case in $cases){
    foreach($iteration in 1..3){
        $raw=quiet -AsObject -Recall -RecallMaxBytes All -WorkingDirectory $case.WorkingDirectory -Data (& $newData) -Output $collect -FilePath $case.FilePath -ArgumentList ([string[]]$case.Arguments)
        if($raw.Execution.Native.ExitCode -ne $case.ExpectedExit){throw ('CorpusNativeExitMismatch: '+$case.Name)}
        if($case.ContainsKey('ExpectedStdout') -and ($raw.Data.stdout -ne $case.ExpectedStdout -or $raw.Data.stderr -ne $case.ExpectedStderr)){throw ('CorpusNativeByteMismatch: '+$case.Name)}
        $text=$raw.Data.Text.ToString()
        if(@($case.ExpectedFacts|Where-Object {!$text.Contains($_,[StringComparison]::Ordinal)}).Count){throw ('CorpusNativeFactMismatch: '+$case.Name)}
        $rtk=quiet -AsObject -WorkingDirectory $case.WorkingDirectory -Data (& $newData) -Output $collect -FilePath $RtkPath -ArgumentList ([string[]]$case.RtkArguments)
        $replayed=Invoke-QuietRecall $raw -Data (& $newData) -Output $collect
        foreach($pair in @(@{Name='NativeViaQuiet';Result=$raw},@{Name='RTKViaQuiet';Result=$rtk},@{Name='RecallReanalysis';Result=$replayed})){
            $r=$pair.Result;$text=$r.Data.Text.ToString();$facts=@($case.ExpectedFacts)
            $missing=@($facts|Where-Object {!$text.Contains($_,[StringComparison]::Ordinal)})
            $samples.Add(@{Case=$case.Name;Family=$case.Family;Oracle=$case.Oracle;RtkMode=$case.RtkMode;Implementation=$pair.Name;Iteration=$iteration;Outcome=$r.Outcome;ElapsedMs=$r.Execution.ElapsedMs;StdoutBytes=$r.Data.stdout;StderrBytes=$r.Data.stderr;Utf8TextBytes=[Text.Encoding]::UTF8.GetByteCount($text);ExpectedFacts=$facts.Count;RecoveredFacts=($facts.Count-$missing.Count);MissingFactExamples=@($missing|Select-Object -First 10);Allocation=$(if($pair.Name -eq 'RTKViaQuiet'){$null}else{$r.Measurement.Allocation})})
        }
    }
}
$report=@{State='Measured';Version=$version.Data.Text.ToString().Trim();BinarySHA256=(Get-FileHash -LiteralPath $RtkPath -Algorithm SHA256).Hash;CorpusCases=$cases.Count;Samples=$samples.ToArray();RecoveryDisabled=($env:RTK_RECALL -eq '0' -or $env:RTK_TEE -eq '0');Limitations=@('Git scenarios reuse the eight shared controlled fixtures.','C# producer scenarios are RTK bypass controls; no filtering advantage is claimed for them.','RTK runs through QuietCli; standalone RTK overhead and underlying child allocations are not isolated.','Reanalysis avoids native startup. Output-byte reduction does not establish token or financial savings.')}
Write-WorkspaceJson (Join-Path $RunDirectory 'recall-rtk.json') $report
$report|ConvertTo-Json -Depth 16 -Compress
