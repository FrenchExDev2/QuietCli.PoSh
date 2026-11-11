#requires -Version 7.6
function Get-QuietCaseRegistrationCondition {
    <#
    .SYNOPSIS
    Reads a supported optional registration guard from the AST without evaluating environment expressions.
    .PARAMETER Assignment
    Literal case registration whose enclosing guards are inspected.
    #>
    param([Parameter(Mandatory)]$Assignment)
    $parent=$Assignment.Parent
    while($parent -and $parent -isnot [Management.Automation.Language.FunctionDefinitionAst]){
        if($parent -is [Management.Automation.Language.IfStatementAst]){
            if($parent.Clauses.Count -ne 1 -or $parent.ElseClause){throw 'TestCaseMetadataConditionalRegistrationUnsupported'}
            $condition=$parent.Clauses[0].Item1.Extent.Text
            $match=[regex]::Match($condition,'\A\$env:(QUIETCLI_[A-Z0-9_]+)\s+-c?eq\s+[''"]1[''"]\z')
            if(!$match.Success){throw 'TestCaseMetadataConditionalRegistrationUnsupported'}
            return $match.Groups[1].Value+'=1'
        }
        $parent=$parent.Parent
    }
    $null
}
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
            if($dependency -cnotin @('FileSystem','NativeProcess','GitProcess','DotNetBuild','EngineState','ProcessEnvironment') -or !$dependencies.Add($dependency)){throw ('TestCaseMetadataDependenciesInvalid: '+$name)}
        }
        if($item.TestKind -ceq 'Unit' -and $dependencies.Count){throw ('TestCaseMetadataUnitHasDependencies: '+$name)}
        if($item.TestKind -ceq 'Integration' -and !$dependencies.Count){throw ('TestCaseMetadataIntegrationNeedsDependencies: '+$name)}
        foreach($key in $item.Keys){if($key -cnotin @('TestKind','Dependencies','NativeTransport','EnabledWhen')){throw ('TestCaseMetadataFieldInvalid: '+$name+' / '+$key)}}
        if($item.ContainsKey('NativeTransport') -and $item.NativeTransport -cnotin @('Stubbed','OwnedFixture')){throw ('TestCaseMetadataTransportInvalid: '+$name)}
        if($item.ContainsKey('EnabledWhen') -and ($item.EnabledWhen -isnot [string] -or $item.EnabledWhen -cnotmatch '\AQUIETCLI_[A-Z0-9_]+=1\z')){throw ('TestCaseMetadataConditionInvalid: '+$name)}
    }
    foreach($name in $Metadata.Keys){if($name -cnotin $CaseNames){throw ('TestCaseMetadataOrphan: '+$name)}}
}

function Get-QuietTestCaseInventory {
    <#
    .SYNOPSIS
    Reads a companion's literal case registrations and metadata through the AST without executing tests.
    .PARAMETER Path
    Companion runner source to inspect, including owned negative fixtures.
    .PARAMETER RunnerName
    Runner function declared by the owning test manifest.
    .PARAMETER CaseSources
    Explicit helper sources declared by that companion for composed case factories.
    #>
    param([Parameter(Mandatory)][string]$Path,[string]$RunnerName='Invoke-QuietCoreTests',[string[]]$CaseSources=@())
    $source=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('TestCaseMetadataParseFailed: '+$Path)}
    $runners=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $RunnerName},$true))
    if($runners.Count -ne 1){throw 'TestCaseMetadataRunnerMissingOrDuplicate'}
    $names=[Collections.Generic.List[string]]::new();$declarations=[Collections.Generic.List[object]]::new()
    $conditions=@{}
    foreach($assignment in $runners[0].Body.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
        $left=$assignment.Left
        if($left -is [Management.Automation.Language.IndexExpressionAst] -and $left.Target -is [Management.Automation.Language.VariableExpressionAst] -and $left.Target.VariablePath.UserPath -ieq 'cases'){
            if($CaseSources.Count -and $left.Index.Extent.Text -ceq '$entry.Key' -and $assignment.Right.Extent.Text -ceq '$entry.Value' -and $assignment.Operator -eq 'Equals'){continue}
            if($left.Index -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $assignment.Operator -ne 'Equals'){throw 'TestCaseMetadataRegistrationMustBeLiteral'}
            $names.Add($left.Index.Value)
            $condition=Get-QuietCaseRegistrationCondition $assignment
            if($condition){$conditions[$left.Index.Value]=$condition}
        }
        if($left -is [Management.Automation.Language.VariableExpressionAst] -and $left.VariablePath.UserPath -ieq 'caseMetadata'){$declarations.Add($assignment.Right)}
    }
    foreach($helper in $CaseSources){
        $helperText=[IO.File]::ReadAllText($helper,[Text.UTF8Encoding]::new($false,$true))
        $helperAst=[Management.Automation.Language.Parser]::ParseInput($helperText,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ('TestCaseMetadataParseFailed: '+$helper)}
        foreach($assignment in $helperAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
            $left=$assignment.Left
            if($left -isnot [Management.Automation.Language.IndexExpressionAst] -or $left.Target -isnot [Management.Automation.Language.VariableExpressionAst] -or $left.Target.VariablePath.UserPath -ine 'cases'){continue}
            if($left.Index -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $assignment.Operator -ne 'Equals'){throw 'TestCaseMetadataRegistrationMustBeLiteral'}
            $names.Add($left.Index.Value)
            $condition=Get-QuietCaseRegistrationCondition $assignment
            if($condition){$conditions[$left.Index.Value]=$condition}
        }
    }
    if(!$names.Count -or $declarations.Count -ne 1){throw 'TestCaseMetadataCatalogueMissingOrDuplicate'}
    if($declarations[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or $declarations[0].Expression -isnot [Management.Automation.Language.HashtableAst]){throw 'TestCaseMetadataMustBeLiteral'}
    try{$metadata=$declarations[0].Expression.SafeGetValue()}catch{throw 'TestCaseMetadataMustBeLiteral'}
    if($metadata -isnot [hashtable]){throw 'TestCaseMetadataMustBeHashtable'}
    Assert-QuietTestCaseMetadata -CaseNames $names.ToArray() -Metadata $metadata
    foreach($name in $names){
        $declared=$metadata[$name].ContainsKey('EnabledWhen')
        if($conditions.ContainsKey($name)){
            if(!$declared -or $metadata[$name].EnabledWhen -cne $conditions[$name]){throw ('TestCaseMetadataConditionMismatch: '+$name)}
        }elseif($declared){throw ('TestCaseMetadataUnexpectedCondition: '+$name)}
    }
    [pscustomobject]@{CaseNames=$names.ToArray();Metadata=$metadata;Count=$names.Count}
}

function Get-QuietCompanionTestInventory {
    <#
    .SYNOPSIS
    Resolves an owning test manifest's catalogue without loading that companion or its dependencies.
    .PARAMETER ManifestPath
    Companion manifest declaring RootModule and PrivateData.QuietCli.TestCatalogue.
    #>
    param([Parameter(Mandatory)][string]$ManifestPath)
    $null=[IO.File]::ReadAllText($ManifestPath,[Text.UTF8Encoding]::new($false,$true))
    $manifest=Import-PowerShellDataFile -LiteralPath $ManifestPath -ErrorAction Stop
    $declaration=if($manifest['PrivateData'] -and $manifest['PrivateData']['QuietCli']){$manifest['PrivateData']['QuietCli']['TestCatalogue']}else{$null}
    if($declaration -isnot [hashtable] -or $declaration.Count -ne 2 -or !$declaration.ContainsKey('Runner') -or !$declaration.ContainsKey('Sources') -or $declaration.Runner -cnotmatch '\AInvoke-Quiet[A-Z][A-Za-z0-9]*Tests\z' -or $declaration.Sources -isnot [array]){throw 'TestCaseMetadataCatalogueDeclarationInvalid'}
    $directory=Split-Path ([IO.Path]::GetFullPath($ManifestPath)) -Parent
    if($manifest['RootModule'] -isnot [string] -or !$manifest['RootModule'].EndsWith('.psm1',[StringComparison]::Ordinal)){throw 'TestCaseMetadataRootModuleInvalid'}
    $sources=[Collections.Generic.List[string]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($relative in @($manifest['RootModule'])+@($declaration.Sources)){
        if($relative -isnot [string] -or $relative -cnotmatch '\A[A-Za-z0-9_.-]+\.ps(?:1|m1)\z' -or !$seen.Add($relative)){throw 'TestCaseMetadataSourceInvalid'}
        $file=Get-Item -LiteralPath (Join-Path $directory $relative) -Force -ErrorAction Stop
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TestCaseMetadataSourceLinkRejected'}
        $sources.Add($file.FullName)
    }
    $inventory=Get-QuietTestCaseInventory -Path $sources[0] -RunnerName $declaration.Runner -CaseSources @($sources.ToArray()|Select-Object -Skip 1)
    $inventory|Add-Member NoteProperty RunnerName $declaration.Runner
    $inventory|Add-Member NoteProperty ManifestPath $ManifestPath
    $inventory
}
function Get-QuietActiveCaseMetadata {
    <#
    .SYNOPSIS
    Selects explicit optional cases using literal process-environment equality without evaluating expressions.
    .PARAMETER Metadata
    Full validated metadata owned by the selected companion.
    #>
    param([Parameter(Mandatory)][hashtable]$Metadata)
    $active=@{}
    foreach($name in $Metadata.Keys){
        $item=$Metadata[$name]
        if($item.ContainsKey('EnabledWhen')){
            $condition=$item.EnabledWhen.Split('=',2)
            if([Environment]::GetEnvironmentVariable($condition[0]) -cne $condition[1]){continue}
        }
        $active[$name]=$item
    }
    $active
}
Export-ModuleMember -Function Assert-QuietTestCaseMetadata,Get-QuietTestCaseInventory,Get-QuietCompanionTestInventory,Get-QuietActiveCaseMetadata
