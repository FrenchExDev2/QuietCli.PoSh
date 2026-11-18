#requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PerformanceStatistics.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietPerformanceMember {
    <#
    .SYNOPSIS
    Reads one member of a JSON object or dictionary, or returns nothing when it is absent.
    .DESCRIPTION
    Arrays are written to the pipeline item by item, so callers wrap collections in @().
    .PARAMETER InputObject
    Parsed evidence object, dictionary or null.
    .PARAMETER Name
    Member name.
    #>
    [CmdletBinding()]
    param([AllowNull()]$InputObject,[Parameter(Mandatory)][string]$Name)
    if($null -eq $InputObject){return}
    if($InputObject -is [Collections.IDictionary]){if($InputObject.Contains($Name)){$InputObject[$Name]};return}
    $property=$InputObject.PSObject.Properties[$Name]
    if($property){$property.Value}
}

function Get-QuietPerformanceItems {
    <#
    .SYNOPSIS
    Returns the items of an evidence collection whose member (Kind by default) equals a value, ordinally.
    .PARAMETER Collection
    Evidence items, or null.
    .PARAMETER Value
    Expected member value.
    .PARAMETER Member
    Member to compare.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Collection,[Parameter(Mandatory)][string]$Value,[string]$Member='Kind')
    foreach($item in @($Collection)){
        if($null -ne $item -and [string](Get-QuietPerformanceMember $item $Member) -ceq $Value){$item}
    }
}

function Get-QuietPerformanceNumbers {
    <#
    .SYNOPSIS
    Projects one numeric member of each item. Absent members are skipped; present values that are not finite numbers are counted.
    .PARAMETER Items
    Evidence items.
    .PARAMETER Member
    Numeric member name.
    .PARAMETER Rejected
    Counter incremented once per present value that is not a finite number.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Items,[Parameter(Mandatory)][string]$Member,[Parameter(Mandatory)][ref]$Rejected)
    $values=[Collections.Generic.List[double]]::new()
    foreach($item in @($Items)){
        if($null -eq $item){continue}
        $present=@(Get-QuietPerformanceMember $item $Member)
        if(!$present.Count){continue}
        $raw=$present[0]
        $numeric=$present.Count -eq 1 -and ($raw -is [double] -or $raw -is [long] -or $raw -is [int] -or $raw -is [decimal] -or $raw -is [single])
        if(!$numeric -or ![double]::IsFinite([double]$raw)){$Rejected.Value++;continue}
        $values.Add([double]$raw)
    }
    ,$values.ToArray()
}

function New-QuietPerformanceGroup {
    <#
    .SYNOPSIS
    Creates one measured variant of a workload measure.
    .PARAMETER Variant
    Variant label; '-' when the measure has a single variant.
    .PARAMETER Values
    Observations.
    #>
    [CmdletBinding()]
    param([string]$Variant='-',[AllowEmptyCollection()][double[]]$Values=@())
    [pscustomobject]@{Variant=$Variant;Values=[double[]]@($Values)}
}

function Get-QuietPerformanceHumanSamples {
    <#
    .SYNOPSIS
    Returns the human git status samples of one kind across every controlled Git state.
    .PARAMETER Context
    Selection context {Performance, Integration, Rejected}.
    .PARAMETER Kind
    Sample kind: FirstCallWithColdEngine or WarmEngine.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Kind)
    foreach($evidence in @(Get-QuietPerformanceItems $Context.Integration 'ControlledGitStatus')){
        foreach($scenario in @(Get-QuietPerformanceMember $evidence 'Scenarios')){
            Get-QuietPerformanceItems @(Get-QuietPerformanceMember (Get-QuietPerformanceMember $scenario 'Human') 'Samples') $Kind
        }
    }
}

function Get-QuietPerformanceVariantGroups {
    <#
    .SYNOPSIS
    Groups items by a computed variant label and projects one numeric member per group, in ordinal label order.
    .PARAMETER Items
    Evidence items.
    .PARAMETER Label
    Script block receiving one item and returning its variant label.
    .PARAMETER Member
    Numeric member name.
    .PARAMETER Context
    Selection context whose Rejected counter receives invalid values.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Items,[Parameter(Mandatory)][scriptblock]$Label,[Parameter(Mandatory)][string]$Member,[Parameter(Mandatory)]$Context)
    $groups=[Collections.Generic.SortedDictionary[string,Collections.Generic.List[object]]]::new([StringComparer]::Ordinal)
    foreach($item in @($Items)){
        if($null -eq $item){continue}
        $name=[string](& $Label $item)
        if(!$groups.ContainsKey($name)){$groups[$name]=[Collections.Generic.List[object]]::new()}
        $groups[$name].Add($item)
    }
    foreach($entry in $groups.GetEnumerator()){New-QuietPerformanceGroup -Variant $entry.Key -Values (Get-QuietPerformanceNumbers $entry.Value.ToArray() $Member $Context.Rejected)}
}

function Get-QuietPerformanceWorkloadCatalog {
    <#
    .SYNOPSIS
    Lists the uninstrumented workload measures that the performance report reads from a Core suite summary.
    .DESCRIPTION
    Each entry names its workload, measure, measured phase, evidence source and limits. Its Select block
    receives a context {Performance, Integration, Rejected} and returns groups {Variant, Values}. A new
    measure is one new entry; the statistics and the report stay unchanged.
    #>
    [CmdletBinding()]
    param()
    $startupSelect={
        param($context)
        $items=@(foreach($campaign in @(Get-QuietPerformanceItems $context.Performance 'FreshProcessStartup')){
            foreach($sample in @(Get-QuietPerformanceMember $campaign 'Samples')){
                if([bool](Get-QuietPerformanceMember $sample 'MeasurePhases') -ne $context.Definition.Instrumented){continue}
                $telemetry=if(Get-QuietPerformanceMember $sample 'TelemetryEnabled'){'on'}else{'off'}
                if($context.Definition.StartupMetric -ceq 'ImportMs'){
                    $item=@{Variant=('telemetry='+$telemetry)}
                    $raw=Get-QuietPerformanceMember $sample 'ImportMs'
                    if($null -ne $raw){$item.Value=$raw}
                    $item;continue
                }
                foreach($call in @(Get-QuietPerformanceMember $sample 'Calls')){
                    $stage=[string](Get-QuietPerformanceMember $call 'Stage')
                    if($context.Definition.Stage -and $stage -cne $context.Definition.Stage){continue}
                    $item=@{Variant=('telemetry='+$telemetry+', '+$stage)}
                    $raw=Get-QuietPerformanceMember $call $context.Definition.StartupMetric
                    if($null -ne $raw){$item.Value=$raw}
                    $item
                }
            }
        })
        Get-QuietPerformanceVariantGroups $items {param($item)$item.Variant} 'Value' $context
    }
    @(
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Fresh-process import';Phase='Import-Module in a new pwsh, warm file cache, no profile';Source='Performance[FreshSessionImport].Samples[Mode=Import].ElapsedMs';Limits='Excludes engine start and the first command.'
            Select={param($context)
                $items=@(foreach($import in @(Get-QuietPerformanceItems $context.Performance 'FreshSessionImport')){Get-QuietPerformanceItems @(Get-QuietPerformanceMember $import 'Samples') 'Import' -Member 'Mode'})
                New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers $items 'ElapsedMs' $context.Rejected)
            }}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Import minus paired baseline';Phase='Same pair: import process minus empty process';Source='Performance[FreshSessionImport].Pairs.ElapsedMs';Limits='Signed deltas are kept; process noise affects both sides.'
            Select={param($context)
                $items=@(foreach($import in @(Get-QuietPerformanceItems $context.Performance 'FreshSessionImport')){Get-QuietPerformanceMember $import 'Pairs'})
                New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers $items 'ElapsedMs' $context.Rejected)
            }}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='First call, cold engine';Phase='First quiet git status of each owned state';Source='Integration[ControlledGitStatus].Scenarios.Human.Samples[FirstCallWithColdEngine].InvocationMs';Limits='One first call per state: different repositories, not repetitions.'
            Select={param($context)New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers @(Get-QuietPerformanceHumanSamples $context 'FirstCallWithColdEngine') 'InvocationMs' $context.Rejected)}}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Engine startup';Phase='Get-QuietEngine after Stop-QuietEngine, helper assembly already loaded';Source='Performance[EngineStartup].ElapsedMs';Limits='One sample per hosting mode; not a fresh-process start.'
            Select={param($context)Get-QuietPerformanceVariantGroups @(Get-QuietPerformanceItems $context.Performance 'EngineStartup') {param($item)'hosting='+(Get-QuietPerformanceMember $item 'Mode')} 'ElapsedMs' $context}}
        [pscustomobject]@{Workload='GitTransport';Measure='Warm call';Phase='quiet git status, whole invocation';Source='Integration[ControlledGitStatus].Scenarios.Human.Samples[WarmEngine].InvocationMs';Limits='Eight different states pooled; native Git time included.'
            Select={param($context)New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers @(Get-QuietPerformanceHumanSamples $context 'WarmEngine') 'InvocationMs' $context.Rejected)}}
        [pscustomobject]@{Workload='GitTransport';Measure='Warm execution';Phase='Execution.ElapsedMs: native run, transport and callbacks';Source='Integration[ControlledGitStatus].Scenarios.Human.Samples[WarmEngine].ExecutionMs';Limits='Includes native Git work.'
            Select={param($context)New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers @(Get-QuietPerformanceHumanSamples $context 'WarmEngine') 'ExecutionMs' $context.Rejected)}}
        [pscustomobject]@{Workload='GitTransport';Measure='Warm callbacks';Phase='Execution.CallbackMs: user -Output and -Complete blocks';Source='Integration[ControlledGitStatus].Scenarios.Human.Samples[WarmEngine].CallbackMs';Limits='These callbacks are deliberately short.'
            Select={param($context)New-QuietPerformanceGroup -Values (Get-QuietPerformanceNumbers @(Get-QuietPerformanceHumanSamples $context 'WarmEngine') 'CallbackMs' $context.Rejected)}}
        [pscustomobject]@{Workload='GitTransport';Measure='8 MiB transport';Phase='Fixture producer, back-pressure, metadata and callback dispatch';Source='Performance[EngineTransport].ElapsedMs';Limits='Not pure IPC latency.'
            Select={param($context)Get-QuietPerformanceVariantGroups @(Get-QuietPerformanceItems $context.Performance 'EngineTransport') {param($item)'hosting='+(Get-QuietPerformanceMember $item 'Mode')} 'ElapsedMs' $context}}
        [pscustomobject]@{Workload='Framing';Measure='1 MiB framing';Phase='Delimiter scan and record copies, no callback or IPC';Source='Performance[RecordFraming].ElapsedMs';Limits='Synthetic blocks: their weight here says nothing about framing in ordinary use.'
            Select={param($context)Get-QuietPerformanceVariantGroups @(Get-QuietPerformanceItems $context.Performance 'RecordFraming') {param($item)[string](Get-QuietPerformanceMember $item 'Implementation')+', width='+(Get-QuietPerformanceMember $item 'RecordWidth')} 'ElapsedMs' $context}}
        [pscustomobject]@{Workload='Metadata';Measure='Outside execution';Phase='InvocationMs minus ExecutionMs of each warm call: dispatch, result projection, metadata save';Source='Integration[ControlledGitStatus].Scenarios.Human.Samples[WarmEngine]';Limits='Not metadata alone: dispatch and projection are included and the save is not split out.'
            Select={param($context)
                $values=[Collections.Generic.List[double]]::new()
                foreach($sample in @(Get-QuietPerformanceHumanSamples $context 'WarmEngine')){
                    $total=Get-QuietPerformanceNumbers @($sample) 'InvocationMs' $context.Rejected
                    $inner=Get-QuietPerformanceNumbers @($sample) 'ExecutionMs' $context.Rejected
                    if($total.Count -and $inner.Count){$values.Add($total[0]-$inner[0])}
                }
                New-QuietPerformanceGroup -Values $values.ToArray()
            }}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Fresh-process startup import';StartupMetric='ImportMs';Instrumented=$false;Stage='';Phase='Actual Import-Module followed by short calls in each fresh process; warm filesystem caches.';Source='Performance[FreshProcessStartup].Samples.ImportMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Fresh-process first short call';StartupMetric='InvocationMs';Instrumented=$false;Stage='FirstCall';Phase='First quiet git --version in a fresh module/engine; native launch and telemetry included.';Source='Performance[FreshProcessStartup].Samples.Calls.InvocationMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='ImportFirstCall';Measure='Fresh-process warm short call';StartupMetric='InvocationMs';Instrumented=$false;Stage='WarmCall';Phase='Three short calls after the first in each fresh process; separate telemetry arms.';Source='Performance[FreshProcessStartup].Samples.Calls.InvocationMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Diagnostic short call';StartupMetric='InvocationMs';Instrumented=$true;Stage='';Phase='Whole diagnostic invocation; compare to ordinary short-call arm for timer overhead.';Source='Performance[FreshProcessStartup].Samples.Calls.InvocationMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Result construction';StartupMetric='ResultConstructionMs';Instrumented=$true;Stage='';Phase='Final source flags and result envelope, before metadata projection and save; no business Data traversal.';Source='Performance[FreshProcessStartup].Samples.Calls.ResultConstructionMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Metadata projection';StartupMetric='MetadataProjectionMs';Instrumented=$true;Stage='';Phase='Caller closed metadata projection before sending the save request; absent when telemetry is disabled.';Source='Performance[FreshProcessStartup].Samples.Calls.MetadataProjectionMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Save round-trip';StartupMetric='SaveRoundTripMs';Instrumented=$true;Stage='';Phase='Caller save exchange including adaptation/IPC, queue, validation and SQLite; inclusive, never add nested phases.';Source='Performance[FreshProcessStartup].Samples.Calls.SaveRoundTripMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Writer queue wait';StartupMetric='QueueWaitMs';Instrumented=$true;Stage='';Phase='Queue admission and wait until worker starts; may include earlier background preparation.';Source='Performance[FreshProcessStartup].Samples.Calls.QueueWaitMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Write gate wait';StartupMetric='WriteGateWaitMs';Instrumented=$true;Stage='';Phase='Worker wait for same-path writers in this process; excludes other processes SQLite lock wait.';Source='Performance[FreshProcessStartup].Samples.Calls.WriteGateWaitMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Metadata validation and JSON';StartupMetric='ValidationMs';Instrumented=$true;Stage='';Phase='Closed schema validation and metadata JSON encoding on the worker; no business serialization.';Source='Performance[FreshProcessStartup].Samples.Calls.ValidationMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='Writer preparation';StartupMetric='WriterPreparationMs';Instrumented=$true;Stage='';Phase='Writer lookup or open/schema/statements if still needed; background preparation can already have completed.';Source='Performance[FreshProcessStartup].Samples.Calls.WriterPreparationMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Metadata';Measure='SQLite write';StartupMetric='SqliteWriteMs';Instrumented=$true;Stage='';Phase='Binding, stepping, reset and SQLite lock/durability waits; implicit invocation transaction, not pure disk time.';Source='Performance[FreshProcessStartup].Samples.Calls.SqliteWriteMs';Limits='Diagnostic and ordinary arms remain separate. Missing values stay unknown. Save round-trip includes its storage phases.';Select=$startupSelect}
        [pscustomobject]@{Workload='Events';Measure='Emit loop';Phase='Emit calls inside -Complete, payloads allocated before the call';Source='Performance[EventEmission].EmitMs';Limits='These listeners only count; real listeners add their own cost.'
            Select={param($context)Get-QuietPerformanceVariantGroups @(Get-QuietPerformanceItems $context.Performance 'EventEmission') {param($item)'listeners='+(Get-QuietPerformanceMember $item 'Listeners')+', collect='+$(if(Get-QuietPerformanceMember $item 'CollectEvents'){'on'}else{'off'})} 'EmitMs' $context}}
    )
}

function Get-QuietPerformanceWorkloadRows {
    <#
    .SYNOPSIS
    Computes one statistics row per workload measure and variant for one environment.
    .DESCRIPTION
    Reads the uninstrumented measures through the catalog, then the instrumented profiler workloads
    recorded by Profiler.Target.ps1. A measure without data still yields one row whose Statistics is
    null, so a missing measure stays visible. Values that are not finite numbers are counted in Rejected.
    .PARAMETER Label
    Environment label.
    .PARAMETER Core
    Core suite summary {Performance, Integration}, or null.
    .PARAMETER ProfiledWorkloads
    Profiler workload records {Name, Scope, SamplesMs}, or null.
    .PARAMETER Catalog
    Workload catalog; Get-QuietPerformanceWorkloadCatalog by default.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Label,[AllowNull()]$Core,[AllowNull()][AllowEmptyCollection()][object[]]$ProfiledWorkloads,[object[]]$Catalog=@(Get-QuietPerformanceWorkloadCatalog))
    $rejected=0
    $context=[pscustomobject]@{Performance=@(Get-QuietPerformanceMember $Core 'Performance');Integration=@(Get-QuietPerformanceMember $Core 'Integration');Rejected=[ref]$rejected;Definition=$null}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($definition in $Catalog){
        $context.Definition=$definition
        $groups=@(& $definition.Select $context)
        if(!$groups.Count){$groups=@(New-QuietPerformanceGroup)}
        foreach($group in $groups){
            $rows.Add([pscustomobject]@{Host=$Label;Workload=$definition.Workload;Measure=$definition.Measure;Variant=$group.Variant;Phase=$definition.Phase;Instrumented=[bool](Get-QuietPerformanceMember $definition 'Instrumented');Source=$definition.Source;Limits=$definition.Limits;Statistics=(Get-QuietPerformanceStatistics -Values $group.Values)})
        }
    }
    foreach($workload in @($ProfiledWorkloads)){
        if($null -eq $workload){continue}
        $name=[string](Get-QuietPerformanceMember $workload 'Name')
        $values=Get-QuietPerformanceNumbers @(foreach($value in @(Get-QuietPerformanceMember $workload 'SamplesMs')){@{Value=$value}}) 'Value' ([ref]$rejected)
        $rows.Add([pscustomobject]@{Host=$Label;Workload=$name;Measure='Instrumented iteration';Variant='-';Phase=[string](Get-QuietPerformanceMember $workload 'Scope');Instrumented=$true;Source=('profiling/powershell-lines.json Workloads['+$name+'].SamplesMs');Limits='Under the line profiler: slower than the same work uninstrumented. Compare only with other instrumented rows.';Statistics=(Get-QuietPerformanceStatistics -Values $values)})
    }
    [pscustomobject]@{Rows=$rows.ToArray();Rejected=$rejected}
}

function Get-QuietPerformanceRuntimeNote {
    <#
    .SYNOPSIS
    States which runtimes the compared environments use and what a comparison between them cannot support.
    .PARAMETER Environments
    Report rows with RID, PowerShell and CLR members.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Environments)
    $groups=[Collections.Generic.SortedDictionary[string,Collections.Generic.SortedSet[string]]]::new([StringComparer]::Ordinal)
    foreach($environment in @($Environments)){
        if($null -eq $environment){continue}
        $name='PowerShell '+(Get-QuietPerformanceMember $environment 'PowerShell')+' on '+(Get-QuietPerformanceMember $environment 'CLR')
        if(!$groups.ContainsKey($name)){$groups[$name]=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)}
        [void]$groups[$name].Add([string](Get-QuietPerformanceMember $environment 'RID'))
    }
    if(!$groups.Count){return 'No environment was read, so no comparison is possible.'}
    $parts=@(foreach($entry in $groups.GetEnumerator()){$entry.Key+' ('+(@($entry.Value) -join ', ')+')'})
    if($groups.Count -eq 1){return 'All environments use '+$parts[0]+'. They still run on different runners, so a difference between rows is not causal and does not rank operating systems.'}
    'Environments use different runtimes: '+($parts -join '; ')+'. The rows are not a general operating-system ranking, and a difference between rows on different runners or runtimes is not causal.'
}

Export-ModuleMember -Function 'Get-QuietPerformanceMember','Get-QuietPerformanceItems','Get-QuietPerformanceNumbers','New-QuietPerformanceGroup','Get-QuietPerformanceHumanSamples','Get-QuietPerformanceVariantGroups','Get-QuietPerformanceWorkloadCatalog','Get-QuietPerformanceWorkloadRows','Get-QuietPerformanceRuntimeNote'
