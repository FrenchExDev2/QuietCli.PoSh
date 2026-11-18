#requires -Version 7.6
# Renders a synthetic three-environment bundle in-process and checks what a reader sees in MD, HTML and JSON.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name Common
    $null=Import-QuietTestLibrary -Name New-CorePerformanceReport
    $scripts=Get-QuietTestScriptsRoot
    $revision='d'*40
    # Explicitly synthetic: the runtimes mirror the hosted matrix (musl on 7.6.10/.NET 10.0.14, others on 7.7.0/.NET 11.0.0).
    $targets=@(@('linux-musl-x64','7.6.10','InProcess','10.0.14'),@('linux-x64','7.7.0','InProcess','11.0.0'),@('win-x64','7.7.0','Process','11.0.0'))
    $newBundle={param([string]$Root,[scriptblock]$Edit={param($Index,$Summary,$Lines)})
        $random=[Random]::new(7)
        $n={param([double]$Base,[double]$Spread)[Math]::Round($Base+$random.NextDouble()*$Spread,3)}
        $inputRoot=[IO.Path]::Combine($Root,'input');$index=0
        foreach($target in $targets){
            $profiles=[IO.Path]::Combine($inputRoot,'job-'+$index,'profiling')
            [void][IO.Directory]::CreateDirectory($profiles)
            $bytes=[Text.Encoding]::UTF8.GetBytes('Explicit synthetic trace fixture '+$index)
            [IO.File]::WriteAllBytes([IO.Path]::Combine($profiles,'s.nettrace'),$bytes)
            Write-WorkspaceJson ([IO.Path]::Combine($profiles,'s.nettrace.speedscope.json')) @{SyntheticIntegrityFixture=$true}
            $collectors=@(foreach($number in 1..$(if($target[2] -ceq 'Process'){2}else{1})){@{TargetProcessId=100+$index*2+$number;Trace='s.nettrace';Speedscope='s.nettrace.speedscope.json';TraceBytes=$bytes.Length;SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));ObservedFrameNames=@{CoreCSharp=3;OtherOrUnresolved=1}}})
            $profiling=@{SyntheticIntegrityFixture=$true;State='Success';ProfilerVersion='4.3.0';ClrProfilerVersion='10.0.750501';TargetIdentity=@{EngineMode=$target[2]};Collectors=$collectors}
            Write-WorkspaceJson ([IO.Path]::Combine($profiles,'summary.json')) $profiling
            $profiled=@(foreach($name in 'GitTransport','Framing','Metadata','Events'){
                Write-WorkspaceJson ([IO.Path]::Combine($profiles,'powershell.'+$name+'.speedscope.json')) @{SyntheticIntegrityFixture=$true}
                @{Name=$name;Scope='synthetic';Iterations=6;Speedscope='powershell.'+$name+'.speedscope.json';SamplesMs=@(1..6|ForEach-Object {& $n (20*$index+30) 15})}
            })
            $lines=@{SyntheticIntegrityFixture=$true;Instrumented=$true;Workloads=$profiled;Lines=@(
                @{Workload='Events';Category='CorePowerShellFacade';Path='synthetic<script>alert(1)</script>.ps1';Line=3;Hits=4;SelfMs=1.5;InclusiveMs=3}
                @{Workload='GitTransport';Category='UserCallbacksAndWorkload';Path='synthetic-workload.ps1';Line=9;Hits=8;SelfMs=0.75;InclusiveMs=1}
            )}
            $scenarios=@(foreach($s in 1..8){@{Name="S$s";Human=@{Samples=@(
                @{Kind='FirstCallWithColdEngine';InvocationMs=(& $n 90 40);ExecutionMs=(& $n 70 10);ReferenceMs=2;CallbackMs=1}
                @{Kind='WarmEngine';InvocationMs=(& $n 12 6);ExecutionMs=(& $n 9 3);ReferenceMs=2;CallbackMs=(& $n 0.4 0.3)}
                @{Kind='WarmEngine';InvocationMs=(& $n 12 6);ExecutionMs=(& $n 9 3);ReferenceMs=2;CallbackMs=(& $n 0.4 0.3)}
            )};Samples=@(1,2)}})
            $performance=@(
                @{Kind='FreshProcessStartup';Iterations=7;Samples=@(foreach($telemetry in @($false,$true)){foreach($timers in @($false,$true)){foreach($repeat in 1..7){
                    @{MeasurePhases=$timers;TelemetryEnabled=$telemetry;ImportMs=150;Calls=@(foreach($call in 0..3){
                        @{Stage=$(if($call){'WarmCall'}else{'FirstCall'});InvocationMs=20;ResultConstructionMs=1;MetadataProjectionMs=$(if($telemetry){1});SaveRoundTripMs=$(if($telemetry){8});QueueWaitMs=$(if($telemetry){2});WriteGateWaitMs=$(if($telemetry){0.5});ValidationMs=$(if($telemetry){1});WriterPreparationMs=$(if($telemetry){0.2});SqliteWriteMs=$(if($telemetry){3})}
                    })}
                }}})}
                @{Kind='FreshSessionImport';Samples=@(1..7|ForEach-Object {@{Mode='Import';ElapsedMs=(& $n 400 120)};@{Mode='Baseline';ElapsedMs=(& $n 250 40)}});Pairs=@(1..7|ForEach-Object {@{ElapsedMs=(& $n 150 60)}});Statistics=@{ElapsedMs=@{Import=@{Count=7;Median=450;P95=510;Max=510}};AllocatedBytes=@{PairedDelta=@{Median=4MB}}}}
                @{Kind='EngineStartup';Mode=$target[2];ElapsedMs=(& $n 60 10)}
                @(1..3|ForEach-Object {@{Kind='EngineTransport';Mode=$target[2];ElapsedMs=(& $n 180 40)}})
                @(foreach($implementation in 'PowerShell','CSharp'){foreach($width in 64,8192){1..3|ForEach-Object {@{Kind='RecordFraming';Implementation=$implementation;RecordWidth=$width;ElapsedMs=(& $n $(if($implementation -eq 'CSharp'){3}else{40}) 5)}}}})
                @(foreach($listeners in 0,1,4){foreach($collect in $false,$true){1..3|ForEach-Object {@{Kind='EventEmission';Listeners=$listeners;CollectEvents=$collect;Events=512;EmitMs=(& $n (2+$listeners*1.5+[int]$collect) 1)}}}})
            )
            $summary=@{SyntheticIntegrityFixture=$true;State=@{State='Success';Platform=$target[0];Passed=5;Failed=0};Suites=@(@{Project='FrenchExDev2.QuietCli.Core.PoSh';Performance=$performance;Integration=@(@{Kind='ControlledGitStatus';Scenarios=$scenarios})});Profiling=$profiling;EngineIdentity=@{Mode=$target[2]};PowerShellVersion=$target[1];HostRuntime=$target[3]}
            & $Edit $index $summary $lines
            Write-WorkspaceJson ([IO.Path]::Combine($profiles,'powershell-lines.json')) $lines
            Write-WorkspaceJson ([IO.Path]::Combine($inputRoot,'job-'+$index,'summary.json')) $summary
            $index++
        }
        $bundle=[IO.Path]::Combine($Root,'bundle')
        $null=& ([IO.Path]::Combine($scripts,'New-CoreEvidenceBundle.ps1')) -ReportRoot $inputRoot -OutputDirectory $bundle -Revision $revision -RequireProfiling -Confirm:$false
        $bundle
    }
    $render={param([string]$Bundle,[string]$Output,[string]$Suite='All',[int]$Expected=3)
        try { Invoke-QuietScriptNewCorePerformanceReport -EvidenceRoot $Bundle -OutputDirectory $Output -Revision $revision -ExpectedReports $Expected -Suite $Suite -Confirm:$false } catch { $diagnostic=[IO.Path]::Combine($Output,'PERFORMANCES_RESULTS.json'); if(Test-Path -LiteralPath $diagnostic){Write-Host ((Get-Content -LiteralPath $diagnostic -Raw -Encoding utf8|ConvertFrom-Json).EvidenceGaps -join '; ')}; throw }
    }
    $readText={param([string]$Path)[IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))}
    $root=[IO.Path]::Combine($TestDrive,'complete')
    $bundle=& $newBundle $root
    $result=& $render $bundle ([IO.Path]::Combine($root,'out'))
    $md=& $readText $result.Markdown
    $html=& $readText $result.Html
    $data=Get-Content $result.Json -Raw -Encoding utf8|ConvertFrom-Json
    $mermaidCount=([regex]::Matches($md,'(?m)^```mermaid$')).Count
}

Describe 'Invoke-QuietScriptNewCorePerformanceReport' {
    It 'publishes separate diagnostic phase charts and states their inclusive boundaries' {
        foreach($measure in @('Result construction','Metadata projection','Save round-trip','Writer queue wait','Write gate wait','Metadata validation and JSON','Writer preparation','SQLite write')){
            $phase=@($data.Workloads|Where-Object {$_.Measure -ceq $measure -and $_.Variant -ceq 'telemetry=on, FirstCall'})
            $phase.Count|Should -Be 3
            @($phase|Where-Object {$_.Count -ne 7 -or !$_.Instrumented}).Count|Should -Be 0
            $md|Should -Match ([regex]::Escape($measure))
        }
        @($data.Workloads|Where-Object {$_.Measure -ceq 'SQLite write' -and $_.Variant -like 'telemetry=off*' -and $_.Count -gt 0}).Count|Should -Be 0
        $md|Should -Match 'never add it to those phases'
        $md|Should -Match 'Telemetry-off save timings stay unavailable, never zero'
    }

    It 'rejects a report without the new startup timers instead of claiming complete evidence' {
        $badRoot=[IO.Path]::Combine($TestDrive,'no-startup')
        $badBundle=& $newBundle $badRoot {param($Index,$Summary,$Lines)$Summary.Suites[0].Performance=@($Summary.Suites[0].Performance|Where-Object Kind -NE 'FreshProcessStartup')}
        {& $render $badBundle ([IO.Path]::Combine($badRoot,'out'))}|Should -Throw 'PerformanceReportEvidenceIncomplete'
    }

    It 'reads every environment of a complete synthetic bundle without gaps' {
        $result.Rows|Should -Be 3
        $result.Gaps|Should -Be 0
        @($data.EvidenceGaps).Count|Should -Be 0
    }

    It 'writes LF-only UTF-8 without BOM and leaves no chart slot behind' {
        foreach($path in $result.Markdown,$result.Html,$result.Json){
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)|Should -BeFalse -Because $path
            ($bytes -contains 13)|Should -BeFalse -Because $path
        }
        $md|Should -Not -Match 'quiet-chart:'
        $html|Should -Not -Match 'quiet-chart:'
    }

    It 'separates the workloads and states phase, source and limits for each measure' {
        foreach($heading in '## Workloads','### Coverage at a glance','### Definitions','### Charts by workload','### Statistics by environment'){$md|Should -Match ('(?m)^'+[regex]::Escape($heading)+'$')}
        foreach($workload in 'ImportFirstCall','GitTransport','Framing','Metadata','Events'){$md|Should -Match ('<summary>'+$workload+' \(\d+ charts\)</summary>')}
        $names=@($data.Workloads|ForEach-Object Workload|Select-Object -Unique)
        $names|Should -Be @('ImportFirstCall','GitTransport','Framing','Metadata','Events')
        @($data.Workloads|Where-Object {!$_.Phase -or !$_.Source -or !$_.Limits}).Count|Should -Be 0
    }

    It 'covers Emit with 0, 1 and many listeners, collection on and off, in every environment' {
        $emit=@($data.Workloads|Where-Object {$_.Workload -ceq 'Events' -and !$_.Instrumented})
        $variants=@($emit|ForEach-Object Variant|Sort-Object -Unique)
        $variants|Should -Be @('listeners=0, collect=off','listeners=0, collect=on','listeners=1, collect=off','listeners=1, collect=on','listeners=4, collect=off','listeners=4, collect=on')
        $emit.Count|Should -Be 18
        @($emit|Where-Object Count -NE 3).Count|Should -Be 0
    }

    It 'gives N, median, quartiles and a p95 flagged as the maximum below 20 observations' {
        $md|Should -Match '\| Workload \| Measure \| Variant \| N \| Median ms \| Q1–Q3 ms \| Min–Max ms \| p95 ms \|'
        $md|Should -Match '\| 510\.00 \(max of 7\) \|'
        @($data.Workloads|Where-Object {$_.Count -gt 0 -and $_.Count -lt 20 -and !$_.P95IsMax}).Count|Should -Be 0
        @($data.Workloads|Where-Object {$_.Count -gt 0 -and ($_.Q1 -gt $_.Median -or $_.Median -gt $_.Q3 -or $_.P95 -gt $_.Max)}).Count|Should -Be 0
        $data.Statistics|Should -Match 'Nearest-rank'
    }

    It 'refuses an operating-system ranking and a causal reading across different runtimes' {
        $data.RuntimeNote|Should -BeLike 'Environments use different runtimes: *'
        $data.RuntimeNote|Should -Match 'PowerShell 7\.6\.10 on 10\.0\.14 \(linux-musl-x64\)'
        $data.RuntimeNote|Should -Match 'PowerShell 7\.7\.0 on 11\.0\.0 \(linux-x64, win-x64\)'
        $data.RuntimeNote|Should -Match 'not causal'
        $md.Contains($data.RuntimeNote)|Should -BeTrue
    }

    It 'says frame-name counts are not CPU shares and keeps workloads on hotspot lines' {
        $md|Should -Match 'not CPU percentages or time shares'
        $md|Should -Match '\| Workload \| Category \| Source \| Line \| Hits \| Self ms \| Inclusive ms \|'
        $md|Should -Match '\| Events \| CorePowerShellFacade \| synthetic&lt;script&gt;'
        @($data.ProfilingLines|ForEach-Object Workload|Sort-Object -Unique)|Should -Be @('Events','GitTransport')
    }

    It 'puts a Mermaid chart in Markdown and the same chart as inline SVG in HTML' {
        $mermaidCount|Should -BeGreaterThan 10
        ([regex]::Matches($md,'(?m)^xychart-beta horizontal$')).Count|Should -Be ($mermaidCount-1)
        ([regex]::Matches($md,'(?m)^flowchart LR$')).Count|Should -Be 1
        ([regex]::Matches($html,'<svg ')).Count|Should -Be $mermaidCount
        $html|Should -Not -Match '```mermaid|xychart-beta'
        foreach($match in [regex]::Matches($html,'(?s)<svg .*?</svg>')){$null=[xml]$match.Value}
    }

    It 'keeps the HTML free of scripts and external resources under a strict policy' {
        $html|Should -Match "Content-Security-Policy"" content=""default-src 'none'; style-src 'unsafe-inline'"
        $html|Should -Not -Match '<(?:script|link|img|iframe|object|embed)\b'
        $html|Should -Not -Match '\son[a-z]+='
        $html|Should -Not -Match '(?:href|src)=["'']?(?:https?:|//|javascript:)'
        $html|Should -Match '&lt;script&gt;'
    }

    It 'renders the same bytes twice apart from the generation time' {
        $again=& $render $bundle ([IO.Path]::Combine($root,'again'))
        $strip={param([string]$Text)$Text -replace 'Generated: [^ ]+\.','Generated: -.'}
        (& $strip (& $readText $again.Markdown))|Should -BeExactly (& $strip $md)
        (& $strip (& $readText $again.Html))|Should -BeExactly (& $strip $html)
    }

    It 'leaves workload charts out of a Git-only report' {
        $git=& $render $bundle ([IO.Path]::Combine($root,'git')) 'Git'
        $text=& $readText $git.Markdown
        $text|Should -Match 'Scope: Git-only'
        $text|Should -Not -Match '## Workloads|```mermaid'
        (& $readText $git.Html)|Should -Not -Match '<svg '
    }

    It 'records a non-finite workload value as an evidence gap instead of plotting it' {
        $badRoot=[IO.Path]::Combine($TestDrive,'non-finite')
        $badBundle=& $newBundle $badRoot {param($Index,$Summary,$Lines)if($Index -eq 0){$Summary.Suites[0].Performance[-1].EmitMs='NaN'}}
        $output=[IO.Path]::Combine($badRoot,'out')
        {& $render $badBundle $output}|Should -Throw 'PerformanceReportEvidenceIncomplete'
        $badData=Get-Content ([IO.Path]::Combine($output,'PERFORMANCES_RESULTS.json')) -Raw -Encoding utf8|ConvertFrom-Json
        @($badData.EvidenceGaps)|Should -Contain 'Workload values that are not finite numbers: 1 in linux-musl-x64 / 7.6.10 / InProcess'
        (& $readText ([IO.Path]::Combine($output,'PERFORMANCES_RESULTS.md')))|Should -Match 'INCOMPLETE or FAILED'
    }

    It 'shows a missing workload as a dashed gap rather than a zero' {
        $gapRoot=[IO.Path]::Combine($TestDrive,'no-events')
        $gapBundle=& $newBundle $gapRoot {param($Index,$Summary,$Lines)$Summary.Suites[0].Performance=@($Summary.Suites[0].Performance|Where-Object Kind -NE 'EventEmission')}
        $gapResult=& $render $gapBundle ([IO.Path]::Combine($gapRoot,'out'))
        $gapResult.Gaps|Should -Be 0
        $text=& $readText $gapResult.Markdown
        $text|Should -Match 'class U\d gap'
        $text|Should -Not -Match 'listeners=0, collect=off'
        $text|Should -Match '<summary>Events \(\d+ charts\)</summary>'
    }

    It 'writes nothing under -WhatIf' {
        $preview=[IO.Path]::Combine($TestDrive,'preview')
        $null=Invoke-QuietScriptNewCorePerformanceReport -EvidenceRoot $bundle -OutputDirectory $preview -Revision $revision -ExpectedReports 3 -WhatIf
        Test-Path $preview|Should -BeFalse
    }
}
