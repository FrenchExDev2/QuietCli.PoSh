<#
.SYNOPSIS
Fails closed when a Core/All CI result lacks mandatory import and Core-only controlled Git evidence.
.PARAMETER Summary
Completed companion or focused integration summary.
#>
[CmdletBinding()]
param([Parameter(Mandatory)]$Summary)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$imports=@($Summary.Performance|Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -ceq 'FreshSessionImport'})
$diagnostics=@($Summary.Performance|Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -ceq 'ImportDiagnostics'})
$controlled=@($Summary.Integration|Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -ceq 'ControlledGitStatus'})
$startup=@($Summary.Performance|Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -ceq 'FreshProcessStartup'})
if($Summary.Failed -ne 0 -or $imports.Count -ne 1 -or $diagnostics.Count -ne 1 -or $controlled.Count -ne 1){throw 'CoreIntegrationEvidenceMissing'}
if($imports[0].Samples.Count -ne 14 -or $imports[0].Iterations -ne 7 -or $imports[0].Validation.MutantsKilled -ne 4){throw 'CoreImportEvidenceIncomplete'}
$expectedModes=@('Import','CmdletOperations','PreloadManagement','PreloadUtility','PreloadBoth','Read','Parse','DotSource')
if($diagnostics[0].Count -ne 10 -or @($diagnostics[0].Samples|Where-Object Mode -EQ Import).Count -ne 3){throw 'CoreImportDiagnosticsIncomplete'}
foreach($mode in $expectedModes){if($mode -cnotin $diagnostics[0].Samples.Mode){throw 'CoreImportDiagnosticModeMissing'}}
if($startup.Count -ne 1 -or $startup[0].Iterations -ne 7 -or $startup[0].Samples.Count -ne 28){throw 'CoreStartupEvidenceIncomplete'}
foreach($telemetry in @($false,$true)){foreach($timers in @($false,$true)){
    $arm=@($startup[0].Samples|Where-Object {$_.TelemetryEnabled -eq $telemetry -and $_.MeasurePhases -eq $timers})
    if($arm.Count -ne 7){throw 'CoreStartupArmMissing'}
    foreach($sample in $arm){
        if($sample.DatabaseCreated -ne $telemetry -or $sample.Calls.Count -ne 4 -or @($sample.Calls|Where-Object Stage -CEQ FirstCall).Count -ne 1 -or @($sample.Calls|Where-Object Stage -CEQ WarmCall).Count -ne 3){throw 'CoreStartupCallEvidenceIncomplete'}
        foreach($call in $sample.Calls){
            $required=@('InvocationMs','ExecutionMs','NativeMs')
            if($timers){$required+='ResultConstructionMs'}
            if($timers -and $telemetry){$required+=@('MetadataProjectionMs','SaveRoundTripMs','QueueWaitMs','WriteGateWaitMs','ValidationMs','WriterPreparationMs','SqliteWriteMs')}
            foreach($name in $required){
                $value=$call.$name
                if($null -eq $value -or $value -isnot [ValueType] -or ![double]::IsFinite([double]$value) -or $value -lt 0){throw 'CoreStartupTimerMissingOrInvalid'}
            }
            if(!$telemetry -and $null -ne $call.SaveRoundTripMs){throw 'CoreStartupDisabledStorageMeasured'}
        }
    }
}}
$evidence=$controlled[0]
$required=@('unborn','clean','mixed','conflict','detached','linked-worktree','submodule','bulk')
if($evidence.Failed -ne 0 -or $evidence.Passed -ne 8 -or $evidence.Scenarios.Count -ne 8 -or $evidence.GitModuleLoaded -or $evidence.RegisteredHandlers -ne 0){throw 'CoreControlledStatusIncomplete'}
foreach($name in $required){
    $rows=@($evidence.Scenarios|Where-Object Name -CEQ $name)
    if($rows.Count -ne 1){throw ('CoreControlledScenarioMissing: '+$name)}
    $row=$rows[0]
    if($row.GitModuleLoaded -or $row.RegisteredHandlers -ne 0 -or $row.Samples.Count -ne 4 -or $row.Human.Samples.Count -ne 4 -or $row.EngineRid -cne $evidence.RuntimeIdentifier){throw 'CoreControlledScenarioIncomplete'}
    foreach($mode in @('Bytes','Text')){foreach($size in @(1024,16384)){
        $samples=@($row.Samples|Where-Object {$_.Mode -ceq $mode -and $_.ReadBlockBytes -eq $size})
        if($samples.Count -ne 1){throw 'CoreControlledTransportMissing'}
        $sample=$samples[0]
        if($sample.Outcome -cne 'Success' -or !$sample.SourceComplete -or !$sample.AnalysisComplete -or $sample.Business.CompleteCalls -ne 1 -or $sample.Business.SHA256 -cne $row.Oracle.SHA256 -or $sample.Business.Bytes -ne $row.Oracle.Bytes -or $sample.Business.Records -ne $row.Oracle.Records){throw 'CoreControlledSampleFailed'}
    }}
}
if($evidence.Validation.ValidCases -ne 32 -or $evidence.Validation.DamagedCases -ne 448 -or $evidence.Validation.Mutations.Count -ne 5 -or @($evidence.Validation.Mutations|Where-Object State -CNE Killed).Count){throw 'CoreControlledAssertionQualificationIncomplete'}
