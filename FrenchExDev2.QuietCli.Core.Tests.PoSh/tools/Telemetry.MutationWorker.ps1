#requires -Version 7.6
<#
.SYNOPSIS
Checks observable PowerShell telemetry contracts against one owned source-mutant module.
.PARAMETER ModulePath
Exact test-subject Core manifest.
.PARAMETER Fixture
Independent native producer assembly.
.PARAMETER DatabasePath
Private SQLite file for this baseline or mutant.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$ModulePath,[Parameter(Mandatory)][string]$Fixture,[Parameter(Mandatory)][string]$DatabasePath)
$ErrorActionPreference='Stop'
$env:QUIETCLI2_DATABASE=$DatabasePath;$env:QUIETCLI2_ENGINE_MODE='InProcess'
Import-Module $ModulePath -Force
$dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
$cases=[Collections.Generic.List[object]]::new();$passed=0;$failed=0
function Invoke-TelemetryCase {
    <#
    .SYNOPSIS
    Records independent assertion failures as structured evidence instead of treating crashes as killed mutants.
    .PARAMETER Name
    Observable contract.
    .PARAMETER Assertion
    Assertion block with no incidental output.
    #>
    param([string]$Name,[scriptblock]$Assertion)
    try{$null=& $Assertion;$script:passed++;$script:cases.Add(@{Name=$Name;State='Passed'})}
    catch{$script:failed++;$script:cases.Add(@{Name=$Name;State='Failed';Error=$_.Exception.Message})}
}
try{
    Invoke-TelemetryCase 'AsObject and new Complete object expose inclusive allocation intervals' {
        $r=quiet -AsObject -C allocated -Complete {param($runtime)[pscustomobject]@{Buffer=[byte[]]::new(65536)}} $dotnet $Fixture emit 8192
        if($r.Outcome -ne 'Success' -or $r.Measurement.Allocation.Status -ne 'Measured' -or $r.Measurement.CompleteAllocation.AllocatedBytes -lt 65536 -or $r.Measurement.Allocation.AllocatedBytes -lt $r.Measurement.CompleteAllocation.AllocatedBytes){throw 'AllocationIntervalMissing'}
        if($r.Measurement.OutputBytes -ne $null -or $r.Measurement.ReductionBytes -ne $null){throw 'AsObjectInventedDeliverySize'}
        $report=Get-QuietCliGain -C allocated -AsObject
        if($report.RootInvocationAllocatedBytes -ne $r.Measurement.Allocation.AllocatedBytes -or $report.RootCompleteAllocatedBytes -ne $r.Measurement.CompleteAllocation.AllocatedBytes){throw 'AllocationPersistenceMissing'}
    }
    Invoke-TelemetryCase 'actual delivery uses native bytes and resets the local reduction' {
        $r=quiet -AsObject -Data @{Count=1} -Output {param($event,$runtime)} $dotnet $Fixture emit 8192
        $text=Out-QuietResult $r
        if($r.Measurement.ReductionBytes -ne 8192-[Text.Encoding]::UTF8.GetByteCount($text)){throw 'LocalDeliveryReductionChanged'}
    }
    Invoke-TelemetryCase 'process diagnostics are optional and shared samples are never independent processes' {
        $ordinary=Get-QuietEngine
        if($ordinary.PSObject.Properties['Allocations']){throw 'ProcessDiagnosticsBecameImplicit'}
        $diagnostic=Get-QuietEngine -IncludeAllocations
        if(!$diagnostic.Allocations.SharedProcess -or $diagnostic.Allocations.Caller.ProcessId -ne $PID -or $diagnostic.Allocations.Engine.ProcessId -ne $PID -or $diagnostic.Allocations.Caller.Precise){throw 'ProcessDiagnosticScopeChanged'}
        $rejected=$false
        try{$null=Get-QuietEngine -Precise}catch{if($_.Exception.Message -eq 'AllocationPrecisionRequiresIncludeAllocations'){$rejected=$true}else{throw}}
        if(!$rejected){throw 'PrecisionWithoutDiagnosticWasAccepted'}
    }
}finally{Stop-QuietEngine}
[pscustomobject]@{Passed=$passed;Failed=$failed;Cases=$cases.ToArray()}|ConvertTo-Json -Depth 8 -Compress
if($failed){exit 1}
