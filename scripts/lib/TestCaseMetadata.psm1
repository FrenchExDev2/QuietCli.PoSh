#requires -Version 7.6
function Assert-QuietTestCaseMetadata {
    <#
    .SYNOPSIS
    Rejects incomplete or contradictory test classifications before selection or execution.
    .PARAMETER CaseNames
    Complete ordered catalogue of executable cases, including filtered and TTY cases.
    .PARAMETER Metadata
    Explicit classifications keyed by the exact case name.
    #>
    param([Parameter(Mandatory)][string[]]$CaseNames,[Parameter(Mandatory)][hashtable]$Metadata)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $CaseNames){
        if([string]::IsNullOrWhiteSpace($name) -or !$names.Add($name)){throw ('TestCaseMetadataDuplicate: '+$name)}
        if($name -cnotin @($Metadata.Keys)){throw ('TestCaseMetadataMissing: '+$name)}
        $item=$Metadata[$name]
        if($item -isnot [hashtable] -or !$item.ContainsKey('TestKind') -or $item.TestKind -cnotin @('Unit','Integration')){throw ('TestCaseMetadataKindInvalid: '+$name)}
        if(!$item.ContainsKey('Dependencies') -or $item.Dependencies -isnot [array]){throw ('TestCaseMetadataDependenciesInvalid: '+$name)}
        $dependencies=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($dependency in $item.Dependencies){
            if($dependency -cnotin @('FileSystem','NativeProcess','GitProcess','DotNetBuild','EngineState') -or !$dependencies.Add($dependency)){throw ('TestCaseMetadataDependenciesInvalid: '+$name)}
        }
        if($item.TestKind -ceq 'Unit' -and $dependencies.Count){throw ('TestCaseMetadataUnitHasDependencies: '+$name)}
        if($item.TestKind -ceq 'Integration' -and !$dependencies.Count){throw ('TestCaseMetadataIntegrationNeedsDependencies: '+$name)}
        foreach($key in $item.Keys){if($key -cnotin @('TestKind','Dependencies','NativeTransport')){throw ('TestCaseMetadataFieldInvalid: '+$name+' / '+$key)}}
        if($item.ContainsKey('NativeTransport') -and $item.NativeTransport -cnotin @('Stubbed','OwnedFixture')){throw ('TestCaseMetadataTransportInvalid: '+$name)}
    }
    foreach($name in $Metadata.Keys){if($name -cnotin $CaseNames){throw ('TestCaseMetadataOrphan: '+$name)}}
}

function Get-QuietTestCaseInventory {
    <#
    .SYNOPSIS
    Reads literal Core case registrations and metadata through the AST without importing or executing tests.
    .PARAMETER Path
    Core test runner source to inspect, including owned negative fixtures.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $source=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('TestCaseMetadataParseFailed: '+$Path)}
    $runners=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-QuietCoreTests'},$true))
    if($runners.Count -ne 1){throw 'TestCaseMetadataRunnerMissingOrDuplicate'}
    $names=[Collections.Generic.List[string]]::new();$declarations=[Collections.Generic.List[object]]::new()
    foreach($assignment in $runners[0].Body.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
        $left=$assignment.Left
        if($left -is [Management.Automation.Language.IndexExpressionAst] -and $left.Target -is [Management.Automation.Language.VariableExpressionAst] -and $left.Target.VariablePath.UserPath -ieq 'cases'){
            if($left.Index -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $assignment.Operator -ne 'Equals'){throw 'TestCaseMetadataRegistrationMustBeLiteral'}
            $names.Add($left.Index.Value)
        }
        if($left -is [Management.Automation.Language.VariableExpressionAst] -and $left.VariablePath.UserPath -ieq 'caseMetadata'){$declarations.Add($assignment.Right)}
    }
    if(!$names.Count -or $declarations.Count -ne 1){throw 'TestCaseMetadataCatalogueMissingOrDuplicate'}
    if($declarations[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or $declarations[0].Expression -isnot [Management.Automation.Language.HashtableAst]){throw 'TestCaseMetadataMustBeLiteral'}
    try{$metadata=$declarations[0].Expression.SafeGetValue()}catch{throw 'TestCaseMetadataMustBeLiteral'}
    if($metadata -isnot [hashtable]){throw 'TestCaseMetadataMustBeHashtable'}
    Assert-QuietTestCaseMetadata -CaseNames $names.ToArray() -Metadata $metadata
    [pscustomobject]@{CaseNames=$names.ToArray();Metadata=$metadata;Count=$names.Count}
}
Export-ModuleMember -Function Assert-QuietTestCaseMetadata,Get-QuietTestCaseInventory
