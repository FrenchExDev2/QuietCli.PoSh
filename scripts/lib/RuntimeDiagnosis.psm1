#requires -Version 7.6
function Get-QuietDiagnosisValue {
    <# .SYNOPSIS
    Reads optional diagnostic data without treating malformed input as established evidence.
    .PARAMETER InputObject
    Inert dictionary or report object.
    .PARAMETER Name
    Expected member name.
    #>
    param($InputObject,[string]$Name)
    if($null -eq $InputObject){return $null}
    if($InputObject -is [Collections.IDictionary]){return ,($InputObject[$Name])}
    $property=$InputObject.PSObject.Properties[$Name]
    if($property){return ,($property.Value)}
    return $null
}

function Get-QuietRuntimeDiagnosis {
    <#
    .SYNOPSIS
    Separates host bootstrap failures, architecture mismatches and native-resource RID selection evidence.
    .DESCRIPTION
    Preserves reported RIDs verbatim. ELF machine, loaded libc paths and process/OS architecture must
    agree before a portable asset load can support an asset-selection finding. A SQLite load proves
    only that diagnostic load, never whole-product or release compatibility. Incomplete evidence is inconclusive.
    .PARAMETER Image
    Curated image identity containing Architecture and Os.
    .PARAMETER Observations
    Default and explicitly selected runtime-root probe outcomes and their guest reports.
    .PARAMETER ExpectedRuntimeIdentifier
    Portable Linux target from the workspace catalogue.
    .PARAMETER ExpectedRuntimeMajor
    Required CLR major for the selected PowerShell host.
    #>
    [CmdletBinding()]
    param($Image,[AllowNull()][AllowEmptyCollection()][object[]]$Observations,
        [Parameter(Mandatory)][ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
        [ValidateRange(10,99)][int]$ExpectedRuntimeMajor=10)
    $architecture=if($ExpectedRuntimeIdentifier.EndsWith('arm64')){'arm64'}else{'x64'}
    $machine=if($architecture -eq 'arm64'){183}else{62}
    $libc=if($ExpectedRuntimeIdentifier.Contains('-musl-')){'Musl'}else{'Gnu'}
    $imageArch=Get-QuietDiagnosisValue $Image Architecture
    $imageMismatch=($imageArch -in @('amd64','x64','arm64')) -and $(if($architecture -eq 'arm64'){$imageArch -cne 'arm64'}else{$imageArch -cnotin @('amd64','x64')})
    $findings=[Collections.Generic.List[string]]::new()
    $usable=[Collections.Generic.List[object]]::new()
    $launched=0;$successfulProcesses=0
    $defaultSucceeded=$false;$defaultObserved=$false
    foreach($observation in $Observations){
        $name=Get-QuietDiagnosisValue $observation Name
        if($name -is [string] -and $name -ceq 'Default'){$defaultObserved=$true}
        $probe=Get-QuietDiagnosisValue $observation Probe
        $outcome=Get-QuietDiagnosisValue $observation Outcome
        if($outcome -is [string] -and $outcome -ceq 'Success'){$successfulProcesses++}
        $schema=Get-QuietDiagnosisValue $probe SchemaVersion
        $phase=Get-QuietDiagnosisValue $probe Phase
        if($outcome -isnot [string] -or $outcome -cne 'Success' -or ($schema -isnot [int] -and $schema -isnot [long]) -or $schema -ne 1 -or $phase -isnot [string] -or $phase -cne 'Complete'){continue}
        $launched++
        $linux=Get-QuietDiagnosisValue $probe Linux
        $processArch=Get-QuietDiagnosisValue $probe ProcessArchitecture
        $osArch=Get-QuietDiagnosisValue $probe OSArchitecture
        $elfMachine=Get-QuietDiagnosisValue $probe ElfMachine
        $major=Get-QuietDiagnosisValue $probe FrameworkMajor
        $observedLibc=Get-QuietDiagnosisValue $probe Libc
        if($processArch -in @('x64','arm64') -and $processArch -cne $architecture){$imageMismatch=$true}
        if($osArch -in @('x64','arm64') -and $osArch -cne $architecture){$imageMismatch=$true}
        $reported=Get-QuietDiagnosisValue $probe RuntimeIdentifier
        if($reported -isnot [string] -or !$reported){continue}
        if($linux -isnot [bool] -or !$linux -or $processArch -isnot [string] -or $osArch -isnot [string] -or $processArch -cne $architecture -or $osArch -cne $architecture -or
            ($elfMachine -isnot [int] -and $elfMachine -isnot [long] -and $elfMachine -isnot [ushort]) -or $elfMachine -ne $machine -or
            $observedLibc -isnot [string] -or $observedLibc -cne $libc -or ($major -isnot [int] -and $major -isnot [long]) -or $major -ne $ExpectedRuntimeMajor){continue}
        $usable.Add($observation)
        if($name -is [string] -and $name -ceq 'Default'){$defaultSucceeded=$true}
    }
    $bootstrapFault=$defaultObserved -and !$defaultSucceeded -and $usable.Count -gt 0
    $selectionFault=$false;$ridMismatch=$false;$nativeFailure=$false
    foreach($observation in $usable){
        $probe=Get-QuietDiagnosisValue $observation Probe
        $reported=Get-QuietDiagnosisValue $probe RuntimeIdentifier
        if($reported -isnot [string] -or !$reported){continue}
        $raw=Get-QuietDiagnosisValue $probe RawNative
        $expected=Get-QuietDiagnosisValue $probe ExpectedNative
        $hashMatches=Get-QuietDiagnosisValue $expected HashMatches
        $nativeOutcome=Get-QuietDiagnosisValue $expected Outcome
        $nativeGood=$nativeOutcome -is [string] -and $nativeOutcome -ceq 'Success' -and $hashMatches -is [bool] -and $hashMatches -eq $true
        if(!$nativeGood){$nativeFailure=$true}
        $rawOutcome=Get-QuietDiagnosisValue $raw Outcome
        $rawHash=Get-QuietDiagnosisValue $raw HashMatches
        if($reported -ceq $ExpectedRuntimeIdentifier -and ($rawOutcome -isnot [string] -or $rawOutcome -cne 'Success' -or $rawHash -isnot [bool] -or !$rawHash)){$nativeFailure=$true}
        if($reported -cne $ExpectedRuntimeIdentifier){
            $ridMismatch=$true
            if($rawOutcome -is [string] -and $rawOutcome -ceq 'Missing' -and $nativeGood){$selectionFault=$true}
        }
    }
    if($bootstrapFault){$findings.Add('DefaultHostFailsButExplicitRuntimeRootWorks')}
    if($ridMismatch){$findings.Add('ReportedRidDiffersFromRequestedPortableTarget')}
    if($selectionFault){$findings.Add('RawRidAssetMissingButExpectedAssetLoadsWithVerifiedHash')}
    if($nativeFailure){$findings.Add('ExpectedNativeAssetNotSuccessfullyLoaded')}
    $imageOS=Get-QuietDiagnosisValue $Image Os
    $decision=if($imageMismatch){'ArchitectureMismatch'}
        elseif($imageOS -isnot [string] -or $imageOS -cne 'linux' -or $imageArch -isnot [string] -or $imageArch -cnotin @('amd64','x64','arm64')){'Inconclusive'}
        elseif(!$launched){if($successfulProcesses){'Inconclusive'}else{'HostUnavailable'}}
        elseif(!$usable.Count){'Inconclusive'}
        elseif($bootstrapFault -and $selectionFault){'BootstrapAndAssetSelection'}
        elseif($selectionFault){'AssetSelection'}
        elseif($nativeFailure){'NativeAssetsUnusable'}
        elseif($bootstrapFault){'BootstrapConfiguration'}
        elseif($ridMismatch -or !$defaultObserved){'Inconclusive'}else{'NoMismatchObserved'}
    $next=[Collections.Generic.List[string]]::new()
    if($bootstrapFault){$next.Add('Correct the PowerShell runtime-root configuration; rebuild only if the image recipe changes.')}
    if($selectionFault){$next.Add('Review raw-RID resource paths and CI identity comparisons; qualify any explicit portable-RID mapping before adopting it.')}
    if($decision -eq 'ArchitectureMismatch'){$next.Add('Select a native image matching the requested architecture; do not waive the architecture guard.')}
    if($decision -in @('HostUnavailable','Inconclusive','NativeAssetsUnusable')){$next.Add('Inspect retained startup/native-load diagnostics before choosing an image or code change.')}
    [pscustomobject]@{SchemaVersion=1;Decision=$decision;Findings=$findings.ToArray();NextSteps=$next.ToArray();ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;
        BootstrapConfigurationProblem=$bootstrapFault;AssetSelectionProblem=$selectionFault;UsableProbeCount=$usable.Count;
        ReportedRuntimeIdentifiers=@($usable|ForEach-Object {Get-QuietDiagnosisValue (Get-QuietDiagnosisValue $_ Probe) RuntimeIdentifier}|Select-Object -Unique);
        RecreateUnchangedContainerFixesIssue=if($decision -in @('BootstrapAndAssetSelection','AssetSelection','BootstrapConfiguration','ArchitectureMismatch')){$false}else{$null};
        WholeProductCompatibilityProven=$false;Qualification='DiagnosticOnly'}
}
function Copy-QuietRuntimeProbeInputs {
    <#
    .SYNOPSIS
    Stages the engine-independent probe and its exact library dependencies while preserving their relative paths.
    .PARAMETER ScriptsRoot
    Source scripts directory containing the entry point and lib directory.
    .PARAMETER Destination
    Owned diagnostic input directory; no product binaries or configuration are copied.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ScriptsRoot,[Parameter(Mandatory)][string]$Destination)
    if(!$PSCmdlet.ShouldProcess($Destination,'Stage the runtime probe and its library dependencies')){return}
    $files=@('Probe-ContainerRuntime.ps1','lib/Probe-ContainerRuntime.psm1','lib/Ci.Process.psm1','lib/RuntimeTargets.psm1','lib/BinaryHeaders.psm1','lib/RuntimeDiagnosis.psm1')
    foreach($relative in $files){if(!(Test-Path -LiteralPath ([IO.Path]::Combine($ScriptsRoot,$relative)) -PathType Leaf)){throw ('RuntimeProbeInputMissing: '+$relative)}}
    foreach($relative in $files){
        $target=[IO.Path]::Combine($Destination,$relative)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath ([IO.Path]::Combine($ScriptsRoot,$relative)) -Destination $target -ErrorAction Stop
    }
    [pscustomobject]@{Destination=$Destination;Files=$files.Count}
}
Export-ModuleMember -Function Get-QuietRuntimeDiagnosis,Copy-QuietRuntimeProbeInputs
