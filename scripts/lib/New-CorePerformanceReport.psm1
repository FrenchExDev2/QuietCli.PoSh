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
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$manifests=@(if(Test-Path $EvidenceRoot){Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -Filter evidence-manifest.json|Where-Object {[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($EvidenceRoot),$_.FullName).Replace('\','/') -match '^(?:[^/]+/)?evidence-manifest\.json$'}})
$rows=[Collections.Generic.List[object]]::new();$gaps=[Collections.Generic.List[string]]::new()
$scenarioLines=[Collections.Generic.List[string]]::new();$profileLines=[Collections.Generic.List[string]]::new()
$hotspots=[Collections.Generic.List[object]]::new();$collectors=[Collections.Generic.List[object]]::new()
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
        $row=[ordered]@{Label=$label;RID=$summary.State.Platform;PowerShell=$summary.PowerShellVersion;CLR=$summary.HostRuntime;Mode=$mode;State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;ImportMedianMs=$null;ImportP95Ms=$null;AllocatedMiB=$null;ControlledStates=0;Profiling=$(if($Suite -ceq 'Git'){'Outside selected scope'}else{'Missing (phase not reached)'});ClrCollectors=0;Source=$entry.Path}
        if($import){$row.ImportMedianMs=$import.Statistics.ElapsedMs.Import.Median;$row.ImportP95Ms=$import.Statistics.ElapsedMs.Import.P95;$row.AllocatedMiB=$import.Statistics.AllocatedBytes.PairedDelta.Median/1MB}
        if($controlled){
            $row.ControlledStates=$controlled.Scenarios.Count
            foreach($scenario in $controlled.Scenarios){
                $warm=@($scenario.Human.Samples|Where-Object Kind -EQ WarmEngine)
                $cells=@($label,$scenario.Name,(Format-ReportNumber $scenario.Human.Samples[0].InvocationMs),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object InvocationMs))),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object ReferenceMs))),(Format-ReportNumber (Get-ReportMedian @($warm|ForEach-Object CallbackMs))),$scenario.Samples.Count)
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
                    foreach($group in $lineData.Lines|Group-Object Category){
                        $self=($group.Group|Measure-Object SelfMs -Sum).Sum
                        $profileLines.Add('| '+(ConvertTo-ReportCell $label)+' | PS lines | '+(ConvertTo-ReportCell $group.Name)+' | '+(Format-ReportNumber $self)+' ms self wall time |')
                    }
                    foreach($line in @($lineData.Lines|Sort-Object SelfMs -Descending|Select-Object -First 50)){
                        $hotspots.Add([pscustomobject]@{Host=$label;Category=$line.Category;Path=$line.Path;Line=$line.Line;Hits=$line.Hits;SelfMs=$line.SelfMs;InclusiveMs=$line.InclusiveMs})
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
    $cells=@($row.RID,$row.PowerShell,$row.CLR,$row.Mode,$row.State,$row.Passed,$row.Failed,(Format-ReportNumber $row.ImportMedianMs),(Format-ReportNumber $row.ImportP95Ms),(Format-ReportNumber $row.AllocatedMiB),$row.ControlledStates,$row.Profiling,$row.ClrCollectors)
    [void]$text.AppendLine('| '+(($cells|ForEach-Object {ConvertTo-ReportCell $_}) -join ' | ')+' |')
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
    [void]$text.AppendLine('| Category | Source | Line | Hits | Self ms | Inclusive ms |')
    [void]$text.AppendLine('|---|---|---:|---:|---:|---:|')
    foreach($line in $group.Group){
        $cells=@($line.Category,$line.Path,$line.Line,$line.Hits,(Format-ReportNumber $line.SelfMs),(Format-ReportNumber $line.InclusiveMs))
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
[void]$text.AppendLine('- Fresh-import samples use seven retained pairs after one discarded warm-up pair, with no user profile and warm filesystem caches. First engine calls and warm calls are separate observations.')
[void]$text.AppendLine('- Assertions have no machine-dependent speed threshold. Property/fuzz inputs, seeds and targeted mutation outcomes remain in the JSON receipts. A small mutant catalogue is not exhaustive coverage.')
[void]$text.AppendLine('- This report verifies supplied checksums and identifies the workflow revision/run. Checksums alone do not authenticate the author, and local results do not prove unexecuted ARM64 or remote matrix jobs.')
[void]$text.AppendLine('- Detailed JSON, partial failure logs, source identities, fixture manifests, PS speedscope/line data and raw/converted CLR traces remain beside this Markdown report in the job artifacts.')
$markdown=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.md')
$jsonPath=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.json')
$htmlPath=[IO.Path]::Combine($OutputDirectory,'PERFORMANCES_RESULTS.html')
[void][IO.File]::WriteAllTextAsync($markdown,$text.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
$body=(Microsoft.PowerShell.Utility\ConvertFrom-Markdown -InputObject $text.ToString()).Html
$html=@'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer"><title>QuietCli performance evidence</title>
<style>body{font:16px/1.5 system-ui,sans-serif;margin:2rem;color:#17283b;background:#f5f7fa}main{max-width:100rem;margin:auto}table{display:block;overflow-x:auto;border-collapse:collapse;background:white;margin:1rem 0}th,td{padding:.5rem .7rem;border:1px solid #c9d3df;text-align:left}th{background:#e5edf7}h1,h2,h3{color:#123e69}code{overflow-wrap:anywhere}td{overflow-wrap:anywhere}a{color:#005fa9}</style></head><body><main>
'@
$html+=$body+"`n</main></body></html>`n"
[IO.File]::WriteAllText($htmlPath,$html.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
Write-WorkspaceJson $jsonPath @{Revision=$Revision;Rows=$rows.ToArray();ProfilingLines=$hotspots.ToArray();Collectors=$collectors.ToArray();EvidenceGaps=$gaps.ToArray();ExpectedReports=$ExpectedReports;ManifestCount=$manifests.Count}
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
