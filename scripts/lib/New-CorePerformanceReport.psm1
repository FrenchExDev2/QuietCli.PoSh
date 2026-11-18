function Invoke-QuietScriptNewCorePerformanceReport {
<#
.SYNOPSIS
Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.
.PARAMETER EvidenceRoot
One published bundle or the directory containing all downloaded matrix bundles.
.PARAMETER OutputDirectory
Report destination; may equal a bundle root, but never a raw report input directory.
.PARAMETER Revision
Expected exact workflow revision.
.PARAMETER ExpectedReports
Required matrix receipt count; zero disables only this cardinality check.
.PARAMETER Suite
Core/All requires integration and profiling; Git-only reports those as outside its scope.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$EvidenceRoot,[string]$OutputDirectory,[string]$Revision,[int]$ExpectedReports=0,[ValidateSet('Core','All','Git','Integration')][string]$Suite='All')
if(!$PSCmdlet.ShouldProcess(([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'../New-CorePerformanceReport.ps1'))),'Execute automation: New-CorePerformanceReport')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PerformanceStatistics.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PerformanceWorkloads.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PerformanceCharts.psm1')) -DisableNameChecking -ErrorAction Stop
function ConvertTo-ReportCell {
    <#
    .SYNOPSIS
    Escapes untrusted metadata for a single Markdown table cell.
    .PARAMETER Value
    Value to render; null means unavailable.
    #>
    param($Value)
    if($null -eq $Value){return '-'}
    ([string]$Value).Replace('|','\|').Replace("`r",' ').Replace("`n",' ').Replace('<','&lt;').Replace('>','&gt;')
}
function Format-ReportNumber {
    <#
    .SYNOPSIS
    Formats a measured finite number without culture-dependent separators or invented values.
    .PARAMETER Value
    Observed numeric value.
    #>
    param($Value)
    if($null -eq $Value -or ![double]::IsFinite([double]$Value)){return '-'}
    ([double]$Value).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
}
function Get-ReportMedian {
    <#
    .SYNOPSIS
    Computes the median of present observed timings for readable comparison tables.
    .PARAMETER Values
    Numeric observations.
    #>
    param([object[]]$Values)
    $items=@($Values|Where-Object {$null -ne $_}|Sort-Object)
    if(!$items.Count){return $null}
    if($items.Count%2){return $items[[int][Math]::Floor($items.Count/2)]}
    return ($items[$items.Count/2-1]+$items[$items.Count/2])/2
}
function Format-ReportP95 {
    <#
    .SYNOPSIS
    Formats a nearest-rank p95 and says when it is only the largest observation.
    .PARAMETER Statistics
    Get-QuietPerformanceStatistics result, or null.
    #>
    param($Statistics)
    if($null -eq $Statistics){return '-'}
    $text=Format-ReportNumber $Statistics.P95
    if($Statistics.P95IsMax){$text+=' (max)'}
    $text
}
function Format-ReportRange {
    <#
    .SYNOPSIS
    Formats a low-high interval of measured numbers.
    .PARAMETER Low
    Lower bound.
    .PARAMETER High
    Upper bound.
    #>
    param($Low,$High)
    if($null -eq $Low -or $null -eq $High){return '-'}
    (Format-ReportNumber $Low)+' – '+(Format-ReportNumber $High)
}
$charts=[Collections.Generic.List[object]]::new()
function Add-ReportChart {
    <#
    .SYNOPSIS
    Reserves a chart slot: Markdown receives the Mermaid source, HTML receives the inline SVG.
    .DESCRIPTION
    The slot is an HTML comment that escaped report text cannot produce, because table cells encode '<'.
    .PARAMETER Mermaid
    Fenced Mermaid block for the Markdown report.
    .PARAMETER Svg
    Script-free SVG for the HTML report.
    #>
    param([string]$Mermaid,[string]$Svg)
    [void]$text.AppendLine('<!--quiet-chart:'+$charts.Count+'-->')
    [void]$text.AppendLine()
    $charts.Add([pscustomobject]@{Mermaid=$Mermaid;Svg=$Svg})
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$manifests=@(if(Test-Path $EvidenceRoot){Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -Filter evidence-manifest.json|Where-Object {[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($EvidenceRoot),$_.FullName).Replace('\','/') -match '^(?:[^/]+/)?evidence-manifest\.json$'}})
$rows=[Collections.Generic.List[object]]::new();$gaps=[Collections.Generic.List[string]]::new()
$scenarioLines=[Collections.Generic.List[string]]::new();$profileLines=[Collections.Generic.List[string]]::new()
$hotspots=[Collections.Generic.List[object]]::new();$collectors=[Collections.Generic.List[object]]::new()
$workloads=[Collections.Generic.List[object]]::new();$definitions=@(Get-QuietPerformanceWorkloadCatalog)
$identities=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($manifestFile in $manifests){
    $bundle=Split-Path $manifestFile.FullName -Parent
    try{$manifest=Get-Content $manifestFile.FullName -Raw -Encoding utf8|ConvertFrom-Json}catch{$gaps.Add('Unreadable evidence manifest: '+$manifestFile.FullName);continue}
    if($manifest.Revision -cne $Revision){$gaps.Add('Revision mismatch: '+$manifestFile.FullName);continue}
    foreach($file in $manifest.Files){
        $path=[IO.Path]::Combine($bundle,$file.Path)
        if(!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.SHA256){$gaps.Add('Missing/modified evidence: '+$file.Path)}
    }
    foreach($gap in $manifest.EvidenceGaps){$gaps.Add([string]$gap)}
    $main=@($manifest.Files|Where-Object {$_.Path -match '^(?:[^/]+/)?(?:guest/)?summary\.json$' -and $_.Path -notmatch '(^|/)profiling/'})
    if(@($main|Where-Object Path -Match '/guest/summary\.json$').Count){$main=@($main|Where-Object Path -Match '/guest/summary\.json$')}
    foreach($entry in $main){
        $summaryPath=[IO.Path]::Combine($bundle,$entry.Path)
        try{$summary=Get-Content $summaryPath -Raw -Encoding utf8|ConvertFrom-Json}catch{$gaps.Add('Unreadable result JSON: '+$entry.Path);continue}
        if(!$summary.PSObject.Properties['Suites'] -or $summary.State -is [string]){continue}
        $core=@($summary.Suites|Where-Object Project -EQ 'FrenchExDev2.QuietCli.Core.PoSh')
        $import=$null;$controlled=$null
        if($core.Count){
            $imports=@($core[0].Performance|Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -eq 'FreshSessionImport'})
            if($imports.Count){$import=$imports[0]}
            $integrations=@($core[0].Integration|Where-Object Kind -EQ ControlledGitStatus)
            if($integrations.Count){$controlled=$integrations[0]}
        }
        $profileData=if($summary.PSObject.Properties['Profiling']){$summary.Profiling}else{$null}
        $mode=if($profileData -and $profileData.PSObject.Properties['TargetIdentity']){$profileData.TargetIdentity.EngineMode}elseif($summary.EngineIdentity){$summary.EngineIdentity.Mode}else{'-'}
        $label=$summary.State.Platform+' / '+$summary.PowerShellVersion+' / '+$mode
        if(!$identities.Add($label)){$gaps.Add('Duplicate matrix environment: '+$label)}
        $row=[ordered]@{Label=$label;RID=$summary.State.Platform;PowerShell=$summary.PowerShellVersion;CLR=$summary.HostRuntime;Mode=$mode;State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;ImportMedianMs=$null;ImportP95Ms=$null;ImportCount=$null;ImportP95IsMax=$null;AllocatedMiB=$null;ControlledStates=0;Profiling=$(if($Suite -ceq 'Git'){'Outside selected scope'}else{'Missing (phase not reached)'});ClrCollectors=0;Source=$entry.Path}
        if($import){
            $row.ImportMedianMs=$import.Statistics.ElapsedMs.Import.Median;$row.ImportP95Ms=$import.Statistics.ElapsedMs.Import.P95;$row.AllocatedMiB=$import.Statistics.AllocatedBytes.PairedDelta.Median/1MB
            $importCount=Get-QuietPerformanceMember $import.Statistics.ElapsedMs.Import 'Count'
            if($null -ne $importCount -and [int]$importCount -gt 0){$row.ImportCount=[int]$importCount;$row.ImportP95IsMax=(Get-QuietPerformanceRank -Count ([int]$importCount) -Quantile 0.95) -eq [int]$importCount}
        }
        $profiledWorkloads=$null
        if($controlled){
            $row.ControlledStates=$controlled.Scenarios.Count
            foreach($scenario in $controlled.Scenarios){
                $warm=@($scenario.Human.Samples|Where-Object Kind -EQ WarmEngine)
                $cells=@($label,$scenario.Name,(Format-ReportNumber $scenario.Human.Samples[0].InvocationMs),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object {$_.InvocationMs}))),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object {$_.ReferenceMs}))),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object {$_.CallbackMs}))),$scenario.Samples.Count)
                $scenarioLines.Add('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
            }
        }
        if($profileData){
            $row.Profiling=$profileData.State
            if($profileData.PSObject.Properties['Collectors']){$row.ClrCollectors=$profileData.Collectors.Count}
            $linePath=[IO.Path]::Combine((Split-Path $summaryPath -Parent),'profiling/powershell-lines.json')
            if(Test-Path $linePath){
                try{
                    $lineData=Get-Content $linePath -Raw -Encoding utf8|ConvertFrom-Json
                    $profiledWorkloads=@(Get-QuietPerformanceMember $lineData 'Workloads')
                    $workloadOf={param($line)$name=Get-QuietPerformanceMember $line 'Workload';if($name){[string]$name}else{'All'}}
                    foreach($group in $lineData.Lines|Group-Object -Property {(& $workloadOf $_)+' / '+$_.Category}|Sort-Object Name){
                        $self=($group.Group|Measure-Object SelfMs -Sum).Sum
                        $profileLines.Add('| '+(ConvertTo-ReportCell $label)+' | PS lines | '+(ConvertTo-ReportCell $group.Name)+' | '+(Format-ReportNumber $self)+' ms self wall time |')
                    }
                    foreach($line in @($lineData.Lines|Sort-Object SelfMs -Descending|Select-Object -First 50)){
                        $hotspots.Add([pscustomobject]@{Host=$label;Workload=(& $workloadOf $line);Category=$line.Category;Path=$line.Path;Line=$line.Line;Hits=$line.Hits;SelfMs=$line.SelfMs;InclusiveMs=$line.InclusiveMs})
                    }
                }catch{$gaps.Add('Unreadable PowerShell line evidence: '+$label)}
            }elseif($Suite -ne 'Git'){$gaps.Add('Missing PowerShell line evidence: '+$label)}
            foreach($collector in $profileData.Collectors){
                $collectors.Add([pscustomobject]@{Host=$label;PID=$collector.TargetProcessId;Trace=$collector.Trace;Speedscope=$collector.Speedscope;Bytes=$collector.TraceBytes;SHA256=$collector.SHA256})
            }
            foreach($collector in $profileData.Collectors){
                foreach($property in $collector.ObservedFrameNames.PSObject.Properties){
                    $profileLines.Add('| '+(ConvertTo-ReportCell $label)+' | CLR PID '+$collector.TargetProcessId+' | '+$property.Name+' | '+$property.Value+' distinct frame names |')
                }
            }
        }
        if($Suite -ne 'Git'){
            $measured=Get-QuietPerformanceWorkloadRows -Label $label -Core $(if($core.Count){$core[0]}else{$null}) -ProfiledWorkloads $profiledWorkloads -Catalog $definitions
            foreach($workloadRow in $measured.Rows){$workloads.Add($workloadRow)}
            if($measured.Rejected){$gaps.Add('Workload values that are not finite numbers: '+$measured.Rejected+' in '+$label)}
        }
        if($Suite -ne 'Git' -and (!$import -or !$controlled -or $row.Profiling -ne 'Success')){$gaps.Add('Mandatory integration/profiling incomplete: '+$label)}
        if($row.State -ne 'Success' -or $row.Passed -le 0){$gaps.Add('Functional run did not succeed or contained no passing tests: '+$label)}
        $rows.Add([pscustomobject]$row)
    }
}
if(!$rows.Count){$gaps.Add('No readable test result was produced or downloaded.')}
if($ExpectedReports -gt 0 -and $rows.Count -ne $ExpectedReports){$gaps.Add("Expected $ExpectedReports matrix reports, found $($rows.Count).")}
$text=[Text.StringBuilder]::new()
[void]$text.AppendLine('# Performance results')
[void]$text.AppendLine()
[void]$text.AppendLine('Revision: `'+$Revision+'`. Generated: '+[DateTimeOffset]::UtcNow.ToString('o')+'.')
[void]$text.AppendLine()
[void]$text.AppendLine($(if($gaps.Count){'**Evidence status: INCOMPLETE or FAILED.** Read the explicit gaps below; missing measurements are not passes.'}else{'**Evidence status: COMPLETE for the reports listed below.** All listed functional runs and requested profilers succeeded.'}))
[void]$text.AppendLine()
[void]$text.AppendLine('This report is readable without opening CLR traces. Import and Git timing samples are uninstrumented; profiling runs separately. Results describe these machines and versions, not a universal OS speed ranking. Allocations are cumulative managed allocations corrected by a paired baseline, not retained memory. `-` means unavailable, never zero.')
if($Suite -eq 'Git'){[void]$text.AppendLine();[void]$text.AppendLine('**Scope: Git-only. Core integration, fresh imports and profilers were not requested for these reports.**')}
[void]$text.AppendLine()
[void]$text.AppendLine('## Matrix and import comparison')
[void]$text.AppendLine()
[void]$text.AppendLine('| RID | PowerShell | CLR | Hosting | State | Passed | Failed | Duration: import median ms | Import p95 ms | Allocated MiB | Git states | Profiling | CLR collectors |')
[void]$text.AppendLine('|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|')
foreach($row in $rows){
    $importP95=Format-ReportNumber $row.ImportP95Ms
    if($row.ImportP95IsMax){$importP95+=' (max of '+$row.ImportCount+')'}
    $cells=@($row.RID,$row.PowerShell,$row.CLR,$row.Mode,$row.State,$row.Passed,$row.Failed,(Format-ReportNumber $row.ImportMedianMs),$importP95,(Format-ReportNumber $row.AllocatedMiB),$row.ControlledStates,$row.Profiling,$row.ClrCollectors)
    [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
}
$runtimeNote=Get-QuietPerformanceRuntimeNote @($rows)
[void]$text.AppendLine()
[void]$text.AppendLine($runtimeNote)
if($Suite -ne 'Git'){
    [void]$text.AppendLine()
    [void]$text.AppendLine('## Workloads')
    [void]$text.AppendLine()
    [void]$text.AppendLine('Each workload is measured on its own. N is the number of observations behind the row. Quartiles and p95 use the nearest rank. A p95 marked **(max)** is the largest observation, which is always the case below 20 observations: it describes the worst run, not a stable tail. Q1–Q3 is the dispersion of the middle half. Instrumented rows run under the line profiler and are only comparable with each other. `-` means no observation, never zero.')
    [void]$text.AppendLine()
    [void]$text.AppendLine('### Coverage at a glance')
    [void]$text.AppendLine()
    [void]$text.AppendLine('Observations and environments behind each workload. Dashed boxes have no observation. Import and the first call are timed but not profiled.')
    [void]$text.AppendLine()
    $coverage=@(Get-QuietPerformanceWorkloadCoverage -Workloads $workloads.ToArray() -Catalog $definitions)
    Add-ReportChart -Mermaid (ConvertTo-QuietPerformanceMermaidOverview $coverage) -Svg (ConvertTo-QuietPerformanceSvgOverview $coverage)
    [void]$text.AppendLine('### Definitions')
    [void]$text.AppendLine()
    [void]$text.AppendLine('| Workload | Measure | Phase | Source | Limits |')
    [void]$text.AppendLine('|---|---|---|---|---|')
    $described=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($workloadRow in $workloads){
        if(!$described.Add($workloadRow.Workload+"`n"+$workloadRow.Measure)){continue}
        $cells=@($workloadRow.Workload,$workloadRow.Measure,$workloadRow.Phase,$workloadRow.Source,$workloadRow.Limits)
        [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
    }
    $series=@(Get-QuietPerformanceChartSeries -Workloads $workloads.ToArray())
    if($series.Count){
        [void]$text.AppendLine()
        [void]$text.AppendLine('### Charts by workload')
        [void]$text.AppendLine()
        [void]$text.AppendLine('One chart per measure and variant, one bar per environment: the bar is the median, the thin line spans Q1–Q3, and the number at the tip is the median with its N. Bars of different environments are side by side, not ranked: their runtimes differ (see the note above). The tables below hold every statistic.')
        $chartGroups=[ordered]@{}
        foreach($chart in $series){if(!$chartGroups.Contains($chart.Workload)){$chartGroups[$chart.Workload]=[Collections.Generic.List[object]]::new()};$chartGroups[$chart.Workload].Add($chart)}
        foreach($chartGroup in $chartGroups.GetEnumerator()){
            [void]$text.AppendLine()
            [void]$text.AppendLine('<details open><summary>'+[Net.WebUtility]::HtmlEncode($chartGroup.Key)+' ('+$chartGroup.Value.Count+' charts)</summary>')
            [void]$text.AppendLine()
            foreach($chart in $chartGroup.Value){
                Add-ReportChart -Mermaid (ConvertTo-QuietPerformanceMermaidChart $chart) -Svg (ConvertTo-QuietPerformanceSvgChart $chart)
                [void]$text.AppendLine('<sub>'+(ConvertTo-ReportCell (Get-QuietPerformanceChartCaption $chart))+'</sub>')
                [void]$text.AppendLine()
            }
            [void]$text.AppendLine('</details>')
        }
    }
    [void]$text.AppendLine()
    [void]$text.AppendLine('### Statistics by environment')
    foreach($group in $workloads|Group-Object Host){
        [void]$text.AppendLine()
        [void]$text.AppendLine('#### '+(ConvertTo-ReportCell $group.Name))
        [void]$text.AppendLine()
        [void]$text.AppendLine('| Workload | Measure | Variant | N | Median ms | Q1–Q3 ms | Min–Max ms | p95 ms |')
        [void]$text.AppendLine('|---|---|---|---:|---:|---:|---:|---:|')
        foreach($workloadRow in $group.Group){
            $s=$workloadRow.Statistics
            $cells=@($workloadRow.Workload,$workloadRow.Measure,$workloadRow.Variant,$(if($s){$s.Count}else{0}),$(if($s){Format-ReportNumber $s.Median}else{'-'}),$(if($s){Format-ReportRange $s.Q1 $s.Q3}else{'-'}),$(if($s){Format-ReportRange $s.Min $s.Max}else{'-'}),(Format-ReportP95 $s))
            [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
        }
    }
}
[void]$text.AppendLine()
[void]$text.AppendLine('## Controlled Git scenarios')
[void]$text.AppendLine()
[void]$text.AppendLine('Eight owned states cover unborn, clean, mixed index/worktree edits, conflict, detached HEAD, linked worktree, dirty local submodule and 512 generated Unicode paths. Each has four human-status calls and four porcelain-v2 byte/NUL-text calls at two read sizes. The companion Git module is forbidden. Exact state oracles, output counts/digests, zero exit, complete streams and one completion are required.')
[void]$text.AppendLine()
[void]$text.AppendLine('| Host | Fixture | Duration: first quiet ms | Warm quiet median ms | Git reference median ms | Callback median ms | v2 transport checks |')
[void]$text.AppendLine('|---|---|---:|---:|---:|---:|---:|')
foreach($line in $scenarioLines){[void]$text.AppendLine($line)}
[void]$text.AppendLine()
[void]$text.AppendLine('## Where the instrumented work appears')
[void]$text.AppendLine()
[void]$text.AppendLine('User callback/workload and Core facade lines come from Profiler 4.3.0. CLR stacks come from pinned dotnet-trace 10.0.750501. An isolated engine has its own collector; integrated hosting shares the PowerShell PID. PS self wall time can include C# calls and waits. Distinct CLR frame-name counts identify code origins, **not CPU percentages or time shares**. These columns must not be added together. Native Git execution and unresolved frames are not relabeled as Core C#.')
[void]$text.AppendLine()
[void]$text.AppendLine('| Host | Observation | Code category | Measured value |')
[void]$text.AppendLine('|---|---|---|---:|')
foreach($line in $profileLines){[void]$text.AppendLine($line)}
[void]$text.AppendLine()
[void]$text.AppendLine('## PowerShell line hotspots by environment')
[void]$text.AppendLine()
[void]$text.AppendLine('Up to 50 observed lines per environment, ordered by self wall time. Inclusive and self times overlap and are not an additive CPU breakdown. Paths and line numbers identify source locations; hits are instrumented observations.')
[void]$text.AppendLine()
foreach($group in $hotspots|Group-Object Host){
    [void]$text.AppendLine('### '+(ConvertTo-ReportCell $group.Name))
    [void]$text.AppendLine()
    [void]$text.AppendLine('| Workload | Category | Source | Line | Hits | Self ms | Inclusive ms |')
    [void]$text.AppendLine('|---|---|---|---:|---:|---:|---:|')
    foreach($line in $group.Group){
        $cells=@($line.Workload,$line.Category,$line.Path,$line.Line,$line.Hits,(Format-ReportNumber $line.SelfMs),(Format-ReportNumber $line.InclusiveMs))
        [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
    }
    [void]$text.AppendLine()
}
[void]$text.AppendLine('## CLR trace provenance')
[void]$text.AppendLine()
[void]$text.AppendLine('Trace and speedscope names refer to their original per-environment evidence artifacts; the combined HTML is self-contained and does not need those files to display the tables.')
[void]$text.AppendLine()
[void]$text.AppendLine('| Host | PID | Trace | Speedscope | Trace bytes | SHA-256 |')
[void]$text.AppendLine('|---|---:|---|---|---:|---|')
foreach($collector in $collectors){
    $cells=@($collector.Host,$collector.PID,$collector.Trace,$collector.Speedscope,$collector.Bytes,$collector.SHA256)
    [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
}
[void]$text.AppendLine()
[void]$text.AppendLine('## Evidence gaps and interpretation')
[void]$text.AppendLine()
if($gaps.Count){foreach($gap in $gaps){[void]$text.AppendLine('- '+(ConvertTo-ReportCell $gap))}}else{[void]$text.AppendLine('- No missing or modified evidence was detected in the supplied bundles.')}
[void]$text.AppendLine('- Fresh-import samples use seven retained pairs after one discarded warm-up pair, with no user profile and warm filesystem caches. First engine calls and warm calls are separate observations. With seven imports, the import p95 is the largest of the seven.')
[void]$text.AppendLine('- '+$runtimeNote)
[void]$text.AppendLine('- Distinct CLR frame-name counts identify where code comes from. They are never CPU shares, and they cover the whole profiled run, not one workload. Profiler collectors attach after import and engine start, so import and the first call are measured but not profiled.')
[void]$text.AppendLine('- Assertions have no machine-dependent speed threshold. Property/fuzz inputs, seeds and targeted mutation outcomes remain in the JSON receipts. A small mutant catalogue is not exhaustive coverage.')
[void]$text.AppendLine('- This report verifies supplied checksums and identifies the workflow revision/run. Checksums alone do not authenticate the author, and local results do not prove unexecuted ARM64 or remote matrix jobs.')
[void]$text.AppendLine('- Detailed JSON, partial failure logs, source identities, fixture manifests, PS speedscope/line data and raw/converted CLR traces remain beside this Markdown report in the job artifacts.')
$markdown=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.md')
$jsonPath=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.json')
$htmlPath=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.html')
$source=$text.ToString().Replace("`r`n","`n")
$slot=[regex]'<!--quiet-chart:(\d+)-->'
$markdownText=$slot.Replace($source,{param($match)$charts[[int]$match.Groups[1].Value].Mermaid})
[void][IO.File]::WriteAllTextAsync($markdown,$markdownText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
$body=(Microsoft.PowerShell.Utility\ConvertFrom-Markdown -InputObject $source).Html
$body=$slot.Replace($body,{param($match)'<figure class="qc-figure">'+$charts[[int]$match.Groups[1].Value].Svg+'</figure>'})
$html=@'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer"><title>QuietCli performance evidence</title>
<style>
:root{--page:#f5f7fa;--surface:#fcfcfb;--ink:#17283b;--ink-2:#52514e;--muted:#898781;--grid:#c9d3df;--head:#e5edf7;--title:#123e69;--link:#005fa9;--series:#2a78d6;--hover:#eef3fa}
@media (prefers-color-scheme:dark){:root{--page:#0d0d0d;--surface:#1a1a19;--ink:#f0efec;--ink-2:#c3c2b7;--muted:#898781;--grid:#2c2c2a;--head:#22262c;--title:#9ec5f4;--link:#86b6ef;--series:#3987e5;--hover:#24272b}}
body{font:16px/1.5 system-ui,sans-serif;margin:2rem 16px;color:var(--ink);background:var(--page)}main{max-width:100rem;margin:auto}table{display:block;overflow-x:auto;border-collapse:collapse;background:var(--surface);margin:1rem 0}th,td{padding:.5rem .7rem;border:1px solid var(--grid);text-align:left}th{background:var(--head)}h1,h2,h3,h4{color:var(--title)}code{overflow-wrap:anywhere}td{overflow-wrap:anywhere}a{color:var(--link)}
details{margin:1rem 0}summary{cursor:pointer;font-weight:600;color:var(--title)}sub{display:block;color:var(--ink-2);line-height:1.4;margin:-.25rem 0 1rem}
.qc-figure{margin:1rem 0;padding:.75rem;background:var(--surface);border:1px solid var(--grid);border-radius:6px;overflow-x:auto}.qc{display:block;font:12px system-ui,sans-serif}
.qc-title{fill:var(--ink);font-weight:600;font-size:13px}.qc-key,.qc-n,.qc-box-detail{fill:var(--ink-2)}.qc-label{fill:var(--ink-2)}.qc-value{fill:var(--ink);font-variant-numeric:tabular-nums}
.qc-axis{stroke:var(--grid);stroke-width:1}.qc-bar{fill:var(--series)}.qc-whisker{stroke:var(--ink);stroke-width:1.5}.qc-hit{fill:transparent}.qc-row:hover .qc-hit{fill:var(--hover)}
.qc-box{fill:var(--surface);stroke:var(--series);stroke-width:1.5}.qc-gap{stroke:var(--muted);stroke-dasharray:4 3}.qc-box-name{fill:var(--ink);font-weight:600}
</style></head><body><main>
'@
$html+=$body+"`n</main></body></html>`n"
[IO.File]::WriteAllText($htmlPath,$html.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
$workloadRecords=@(foreach($workloadRow in $workloads){
    $s=$workloadRow.Statistics
    [ordered]@{Host=$workloadRow.Host;Workload=$workloadRow.Workload;Measure=$workloadRow.Measure;Variant=$workloadRow.Variant;Phase=$workloadRow.Phase;Instrumented=$workloadRow.Instrumented;Source=$workloadRow.Source;Limits=$workloadRow.Limits;Count=$(if($s){$s.Count}else{0});Min=$(if($s){$s.Min});Q1=$(if($s){$s.Q1});Median=$(if($s){$s.Median});Q3=$(if($s){$s.Q3});Max=$(if($s){$s.Max});Iqr=$(if($s){$s.Iqr});P95=$(if($s){$s.P95});P95IsMax=$(if($s){$s.P95IsMax})}
})
Write-WorkspaceJson $jsonPath @{Revision=$Revision;Rows=$rows.ToArray();Workloads=$workloadRecords;RuntimeNote=$runtimeNote;Statistics='Nearest-rank quartiles and p95; P95IsMax marks a p95 equal to the largest observation (always true below 20 observations).';ProfilingLines=$hotspots.ToArray();Collectors=$collectors.ToArray();EvidenceGaps=$gaps.ToArray();ExpectedReports=$ExpectedReports;ManifestCount=$manifests.Count}
$localManifest=[IO.Path]::Combine($OutputDirectory,'evidence-manifest.json')
if(Test-Path $localManifest){
    $manifest=Get-Content $localManifest -Raw -Encoding utf8|ConvertFrom-Json
    $manifest.Files=@($manifest.Files|Where-Object Path -NotIn @('PERFORMANCES_RESULTS.md','PERFORMANCES_RESULTS.json','PERFORMANCES_RESULTS.html'))+@(foreach($path in @($markdown,$jsonPath,$htmlPath)){@{Path=[IO.Path]::GetFileName($path);Bytes=(Get-Item $path).Length;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash}})
    Write-WorkspaceJson $localManifest $manifest
}else{
    Write-WorkspaceJson $localManifest @{
        Revision=$Revision;Repository=$env:GITHUB_REPOSITORY;RunId=$env:GITHUB_RUN_ID;RunAttempt=$env:GITHUB_RUN_ATTEMPT
        EvidenceGaps=$gaps.ToArray();SourceManifests=@(foreach($file in $manifests){@{Path=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($EvidenceRoot),$file.FullName).Replace('\','/');SHA256=(Get-FileHash $file.FullName -Algorithm SHA256).Hash}})
        Files=@(foreach($path in @($markdown,$jsonPath,$htmlPath)){@{Path=[IO.Path]::GetFileName($path);Bytes=(Get-Item $path).Length;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash}})
    }
}
[pscustomobject]@{Markdown=$markdown;Html=$htmlPath;Json=$jsonPath;Rows=$rows.Count;Gaps=$gaps.Count}
if($gaps.Count){throw 'PerformanceReportEvidenceIncomplete'}

}
Export-ModuleMember -Function 'Invoke-QuietScriptNewCorePerformanceReport'
